import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/feature_status.dart';
import '../../core/free/free_voice_engine.dart';
import '../../core/free/gradio_space.dart';
import '../../core/free/local_audio_store.dart';
import '../../core/free/mic_recorder.dart';
import '../../core/free/wav.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/audio_tile.dart';
import '../../widgets/common.dart';
import '../../widgets/local_audio_tile.dart';

enum ConversionDirection {
  maleToFemale('male_to_female', 'పురుష → స్త్రీ స్వరం', 'Male to Female Voice', 'male', 'female', Feature.maleToFemale),
  femaleToMale('female_to_male', 'స్త్రీ → పురుష స్వరం', 'Female to Male Voice', 'female', 'male', Feature.femaleToMale);

  const ConversionDirection(this.apiValue, this.titleTe, this.titleEn, this.from, this.to, this.feature);

  final String apiValue;
  final String titleTe;
  final String titleEn;
  final String from;
  final String to;
  final Feature feature;
}

/// Converts a recorded or uploaded voice. Uses the app's own server when one
/// is connected and ready; otherwise the free Seed-VC engine on Hugging Face.
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key, required this.direction, this.recorder});

  final ConversionDirection direction;

  /// Injected in tests; created automatically otherwise.
  final MicRecorder? recorder;

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  static const _audioTypes = XTypeGroup(
    label: 'Audio',
    extensions: ['wav', 'mp3', 'ogg', 'oga', 'opus', 'flac', 'm4a'],
    mimeTypes: ['audio/wav', 'audio/x-wav', 'audio/mpeg', 'audio/ogg', 'audio/flac', 'audio/mp4', 'audio/x-m4a'],
    uniformTypeIdentifiers: ['public.audio'],
  );

  late final AppController _app = AppScope.read(context);
  late final MicRecorder _mic = widget.recorder ?? MicRecorder();
  late FreeVoice _target = FreeVoice.forGender(widget.direction.to).first;

  bool _consent = false;
  bool _busySource = false; // recording finishing, reading or uploading a file
  bool _converting = false;
  String? _progress;
  bool _micExplained = false;
  Timer? _ticker;
  int _recSeconds = 0;

  // Free engine
  Uint8List? _sourceBytes;
  String _sourceName = 'recording.wav';
  LocalAudio? _sourcePreview;
  LocalAudio? _freeConverted;

  // App server
  AudioItem? _original;
  AudioItem? _converted;

  bool get _useServer => FeatureStatus.serverOf(_app, widget.direction.feature).ready;

  @override
  void dispose() {
    _ticker?.cancel();
    if (widget.recorder == null) _mic.dispose();
    final preview = _sourcePreview;
    if (preview != null && _app.playback.isPlaying(preview.id)) {
      final playback = _app.playback;
      Future.microtask(playback.stop); // not while the widget tree is locked
    }
    super.dispose();
  }

  // ---- Getting the source audio ------------------------------------------------

  Future<void> _toggleRecord() async {
    if (_mic.recording) {
      await _stopRecording();
      return;
    }
    if (!_micExplained) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.mic_rounded),
          title: const Text('Use the microphone? · మైక్ అనుమతి'),
          content: const Text(
            'The app records your voice only while the red Stop button is showing, for up to '
            '${FreeVoiceEngine.maxConvertSeconds} seconds. Android will ask you to allow the microphone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _micExplained = true;
    }
    try {
      await _app.playback.stop();
      final started = await _mic.start();
      if (!mounted) return;
      if (!started) {
        showMessage(
          context,
          'Microphone permission was not given. Allow it in Android Settings → Apps → Telugu AI Voice → Permissions.',
          error: true,
        );
        return;
      }
      setState(() => _recSeconds = 0);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSeconds++);
        if (_recSeconds >= FreeVoiceEngine.maxConvertSeconds) _stopRecording();
      });
    } catch (_) {
      if (mounted) showMessage(context, 'Could not start recording on this device.', error: true);
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _busySource = true);
    try {
      final bytes = await _mic.stop();
      if (!mounted) return;
      if (bytes == null || (wavSeconds(bytes) ?? 1) < 0.5) {
        showMessage(context, 'Nothing was recorded. Hold the phone close and try again.', error: true);
        return;
      }
      await _useSource(bytes, 'recording.wav', 'Your recording · మీ రికార్డింగ్');
    } catch (_) {
      if (mounted) showMessage(context, 'The recording could not be saved. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busySource = false);
    }
  }

  Future<void> _pickFile() async {
    final XFile? file = await openFile(acceptedTypeGroups: const [_audioTypes]);
    if (file == null || !mounted) return;
    final maxBytes = _useServer
        ? (_app.health?.limits.maxUploadMb ?? 20) * 1024 * 1024
        : FreeVoiceEngine.maxConvertBytes;
    setState(() => _busySource = true);
    try {
      if (await file.length() > maxBytes) {
        if (mounted) showMessage(context, 'Files must be ${maxBytes ~/ (1024 * 1024)} MB or smaller.', error: true);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _useSource(bytes, file.name, file.name);
    } catch (_) {
      if (mounted) showMessage(context, 'This file could not be read.', error: true);
    } finally {
      if (mounted) setState(() => _busySource = false);
    }
  }

  Future<void> _useSource(Uint8List bytes, String name, String title) async {
    if (_useServer) {
      try {
        final item = await _app.api.uploadAudio(bytes, name);
        if (!mounted) return;
        setState(() {
          _original = item;
          _converted = null;
        });
        showMessage(context, 'Uploaded · అప్‌లోడ్ అయింది');
      } on ApiException catch (e) {
        if (mounted) showMessage(context, e.message, error: true);
      }
      return;
    }
    final seconds = wavSeconds(bytes);
    if (seconds != null && seconds > FreeVoiceEngine.maxConvertSeconds + 1) {
      showMessage(context, 'Please use a recording of up to ${FreeVoiceEngine.maxConvertSeconds} seconds.', error: true);
      return;
    }
    await _app.playback.stop();
    setState(() {
      _sourceBytes = bytes;
      _sourceName = name;
      _sourcePreview = LocalAudio.preview(bytes, title: title);
      _freeConverted = null;
    });
  }

  // ---- Converting ----------------------------------------------------------------

  Future<void> _convert() async {
    if (_useServer) return _convertOnServer();
    final source = _sourceBytes;
    if (source == null) return;
    final d = widget.direction;
    await _app.playback.stop();
    setState(() {
      _converting = true;
      _progress = 'Starting…';
    });
    try {
      final wav = await _app.freeEngine.convert(
        source,
        _sourceName,
        _target,
        onProgress: (step, total, message) {
          if (mounted) setState(() => _progress = message);
        },
      );
      final item = await _app.localAudio.add(
        wav,
        title: '${d.titleEn} · ${_target.nameEn}',
        kind: 'converted',
        detail: _sourceName == 'recording.wav' ? 'From your recording' : 'From $_sourceName',
      );
      if (!mounted) return;
      setState(() => _freeConverted = item);
      showMessage(context, 'Converted · మార్పు పూర్తైంది');
      try {
        await _app.playback.toggle(item, () => _app.localAudio.bytesOf(item));
      } catch (_) {
        // The Play button still works.
      }
    } on FreeEngineException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Something went wrong during conversion. Please try again.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _converting = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _convertOnServer() async {
    final original = _original;
    if (original == null) return;
    setState(() => _converting = true);
    try {
      final result = await _app.api.convertVoice(
        direction: widget.direction.apiValue,
        consent: _consent,
        sourceAudioId: original.id,
      );
      if (!mounted) return;
      setState(() => _converted = result.converted);
      showMessage(context, 'Converted · మార్పు పూర్తైంది');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
      if (e.isProviderMissing) await _app.refreshServer();
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  // ---- UI --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final d = widget.direction;
    final useServer = _useServer;
    final hasSource = useServer ? _original != null : _sourceBytes != null;
    final recording = _mic.recording;
    final targets = FreeVoice.forGender(d.to);

    String? blocked;
    if (recording) {
      blocked = 'Stop the recording first.';
    } else if (!hasSource) {
      blocked = 'Record or upload a ${d.from} voice first.';
    } else if (!_consent) {
      blocked = 'Please confirm consent above.';
    }

    final sourceHint = useServer
        ? (app.health == null
            ? 'WAV, MP3, OGG, FLAC or M4A.'
            : '${app.health!.limits.allowedFormats.map((f) => f.toUpperCase()).join(', ')} · '
                'up to ${app.health!.limits.maxUploadMb} MB')
        : 'Speak clearly for 5–${FreeVoiceEngine.maxConvertSeconds} seconds, or upload a WAV, MP3, OGG, FLAC '
            'or M4A file up to ${FreeVoiceEngine.maxConvertBytes ~/ (1024 * 1024)} MB.';

    return Scaffold(
      appBar: AppBar(title: Text(d.titleEn)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        child: ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeading(telugu: d.titleTe, english: 'Change ${d.from} speech into a natural ${d.to} voice'),
              FeatureStatusBanner(feature: d.feature),

              // ---- 1. Source audio ---------------------------------------------------
              SectionCard(
                title: '1 · అసలు ఆడియో · Your ${d.from} voice',
                icon: Icons.mic_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('record-button'),
                            style: recording ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
                            onPressed: (_busySource || _converting) ? null : _toggleRecord,
                            icon: Icon(recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded),
                            label: Text(recording ? 'Stop · ${formatDuration(_recSeconds.toDouble())}' : 'Record · రికార్డ్'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const Key('upload-button'),
                            onPressed: (_busySource || _converting || recording) ? null : _pickFile,
                            icon: _busySource
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.upload_file_rounded),
                            label: const Text('Upload file'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(sourceHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    if (hasSource) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ready. Listen to it under "Before / after" below.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ---- 2. Target voice (free engine) -----------------------------------
              if (!useServer) ...[
                SectionCard(
                  title: '2 · కొత్త స్వరం · New voice',
                  icon: d.to == 'female' ? Icons.woman_rounded : Icons.man_rounded,
                  child: targets.length > 1
                      ? Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final v in targets)
                              ChoiceChip(
                                key: Key('target-${v.name}'),
                                label: Text('${v.label} – ${v.character}'),
                                selected: _target == v,
                                onSelected: _converting ? null : (_) => setState(() => _target = v),
                              ),
                          ],
                        )
                      : Text('${_target.label} – ${_target.character}'),
                ),
                const SizedBox(height: 14),
              ],

              // ---- Consent -------------------------------------------------------------
              SectionCard(
                title: '${useServer ? 2 : 3} · అనుమతి · Consent',
                icon: Icons.verified_user_rounded,
                child: CheckboxListTile(
                  key: const Key('consent-checkbox'),
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("This is my own voice, or I have the speaker's permission."),
                  subtitle: Text(
                    'I will not use converted audio to impersonate any real person.'
                    '${useServer ? '' : ' I agree that the recording is uploaded to the free Hugging Face server for conversion.'}',
                  ),
                ),
              ),
              const SizedBox(height: 20),

              FilledButton.icon(
                key: const Key('convert-button'),
                onPressed: (blocked == null && !_converting && !_busySource) ? _convert : null,
                icon: _converting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  _converting ? (_progress ?? 'Converting…') : 'మార్చండి · Convert to ${d.to} voice',
                ),
              ),
              if (blocked != null) ...[
                const SizedBox(height: 8),
                Text(
                  blocked,
                  key: const Key('convert-blocked-reason'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
              const SizedBox(height: 20),

              // ---- Before / after ------------------------------------------------------
              SectionCard(
                title: 'ముందు / తర్వాత · Before / after',
                icon: Icons.compare_arrows_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!useServer && _sourcePreview != null)
                      LocalAudioTile(item: _sourcePreview!, label: 'Before · అసలు', showShare: false)
                    else if (useServer && _original != null)
                      AudioSummaryTile(item: _original!, label: 'Before · అసలు')
                    else
                      const _Placeholder(text: 'Your recording will appear here'),
                    const SizedBox(height: 10),
                    if (!useServer && _freeConverted != null)
                      LocalAudioTile(key: const Key('converted-result'), item: _freeConverted!, label: 'After · మార్చినది')
                    else if (useServer && _converted != null)
                      AudioSummaryTile(item: _converted!, label: 'After · మార్చినది')
                    else
                      const _Placeholder(text: 'Converted voice will appear here'),
                    if (!useServer && _freeConverted != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Saved on this phone (see History). Tap Share to send it on WhatsApp or save it to Files.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(text, style: TextStyle(color: scheme.outline)),
    );
  }
}

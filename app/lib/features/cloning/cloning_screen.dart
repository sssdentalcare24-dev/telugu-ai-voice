import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloning/clone_models.dart';
import '../../core/cloning/clone_service.dart';
import '../../core/free/free_voice_engine.dart';
import '../../core/free/gradio_space.dart';
import '../../core/free/local_audio_store.dart';
import '../../core/free/mic_recorder.dart';
import '../../core/free/wav.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/audio_tile.dart' show formatDateTime;
import '../../widgets/common.dart';
import '../../widgets/local_audio_tile.dart';
import '../../widgets/telugu_keyboard.dart';

/// AI Voice Cloning: record a voice once, then type any text and hear it in
/// that voice. Three sections: Create Voice, My Voice Library, Text to Speech.
class CloningScreen extends StatefulWidget {
  const CloningScreen({super.key, this.recorder, this.initialTab = 0});

  /// Injected in tests; created automatically otherwise.
  final MicRecorder? recorder;
  final int initialTab;

  @override
  State<CloningScreen> createState() => _CloningScreenState();
}

class _CloningScreenState extends State<CloningScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  bool _preferServer = true;
  String? _selectedProfileId;
  ServerCloneService? _loadedServer;
  bool _loading = false;
  String? _loadError;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  CloneService _service(AppController app) =>
      (_preferServer && app.serverClone != null) ? app.serverClone! : app.phoneClone;

  void _ensureLoaded(AppController app) {
    final server = app.serverClone;
    if (!_preferServer || server == null || identical(server, _loadedServer)) return;
    _loadedServer = server;
    _loading = true;
    _loadError = null;
    server.load().then((_) {
      if (mounted) setState(() => _loading = false);
    }, onError: (Object e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    });
  }

  void _useVoice(VoiceProfile p) {
    setState(() => _selectedProfileId = p.id);
    _tabs.animateTo(2);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    _ensureLoaded(app);
    final service = _service(app);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                ScreenHeading(
                  telugu: 'AI వాయిస్ క్లోనింగ్',
                  english: 'Record a voice once, then type anything and hear it in that voice',
                  trailing: _ModeBadge(service: service),
                ),
                if (app.serverClone != null) ...[
                  SegmentedButton<bool>(
                    key: const Key('clone-mode'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.phone_android_rounded), label: Text('This phone · free')),
                      ButtonSegment(value: true, icon: Icon(Icons.dns_rounded), label: Text('App server')),
                    ],
                    selected: {_preferServer},
                    onSelectionChanged: (s) => setState(() {
                      _preferServer = s.first;
                      _selectedProfileId = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_loading) const LinearProgressIndicator(),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_loadError!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
          Material(
            color: theme.colorScheme.surface,
            child: TabBar(
              controller: _tabs,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(key: Key('tab-create'), icon: Icon(Icons.mic_rounded), text: 'Create Voice'),
                Tab(key: Key('tab-library'), icon: Icon(Icons.library_music_rounded), text: 'My Voices'),
                Tab(key: Key('tab-tts'), icon: Icon(Icons.record_voice_over_rounded), text: 'Text to Speech'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CreateVoiceTab(
                  key: ValueKey('create-${service.modeLabel}'),
                  service: service,
                  recorder: widget.recorder,
                  onCreated: (p) {
                    setState(() => _selectedProfileId = p.id);
                    _tabs.animateTo(1);
                  },
                ),
                _LibraryTab(service: service, onUse: _useVoice, onCreate: () => _tabs.animateTo(0)),
                _SpeakTab(
                  key: ValueKey('speak-${service.modeLabel}'),
                  service: service,
                  selectedProfileId: _selectedProfileId,
                  onSelect: (id) => setState(() => _selectedProfileId = id),
                  onCreate: () => _tabs.animateTo(0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.service});

  final CloneService service;

  @override
  Widget build(BuildContext context) {
    final color = service.onDevice ? AppColors.success : Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: service.onDevice
          ? 'Voices are saved on this phone. Speech is made by the free IndicF5 server on Hugging Face.'
          : 'Voices, consent records and history are kept on the app server.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(service.onDevice ? Icons.phone_android_rounded : Icons.dns_rounded, size: 15, color: color),
            const SizedBox(width: 5),
            Text(service.modeLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

String _errorText(Object e) => switch (e) {
      CloneException() => e.message,
      FreeEngineException() => e.message,
      _ => 'Something went wrong. Please try again.',
    };

// ---- 1. Create Voice ----------------------------------------------------------------

class _CreateVoiceTab extends StatefulWidget {
  const _CreateVoiceTab({super.key, required this.service, required this.onCreated, this.recorder});

  final CloneService service;
  final ValueChanged<VoiceProfile> onCreated;
  final MicRecorder? recorder;

  @override
  State<_CreateVoiceTab> createState() => _CreateVoiceTabState();
}

class _CreateVoiceTabState extends State<_CreateVoiceTab> with AutomaticKeepAliveClientMixin {
  static const _audioTypes = XTypeGroup(
    label: 'Audio',
    extensions: ['wav', 'mp3', 'ogg', 'flac', 'm4a'],
    mimeTypes: ['audio/wav', 'audio/x-wav', 'audio/mpeg', 'audio/ogg', 'audio/flac', 'audio/mp4', 'audio/x-m4a'],
    uniformTypeIdentifiers: ['public.audio'],
  );

  late final MicRecorder _mic = widget.recorder ?? MicRecorder();
  final _name = TextEditingController();
  final _speaker = TextEditingController();
  final _transcript = TextEditingController();
  String _category = 'female';
  String? _providerName;
  String _language = 'te';
  String _relationship = 'self';
  bool _consent = false;
  bool _makePreview = false;
  bool _micExplained = false;
  Timer? _ticker;
  int _seconds = 0;
  Uint8List? _sample;
  String _filename = 'voice_sample.wav';
  LocalAudio? _samplePreview;
  bool _busy = false;
  double _progress = 0;
  String? _progressText;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _transcript.text = CloneLanguage.byCode(_language).script ?? '';
    for (final c in [_name, _speaker, _transcript]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (widget.recorder == null) _mic.dispose();
    for (final c in [_name, _speaker, _transcript]) {
      c.dispose();
    }
    super.dispose();
  }

  CloneProviderInfo get _provider {
    final ready = widget.service.providers.where((p) => p.ready).toList();
    if (ready.isEmpty) return CloneProviderInfo.indicF5OnPhone;
    return ready.firstWhere((p) => p.name == _providerName, orElse: () => ready.first);
  }

  List<CloneLanguage> get _recordingLanguages {
    final codes = _provider.languages;
    return CloneLanguage.all.where((l) => codes.contains(l.code)).toList();
  }

  void _setLanguage(String code) {
    final old = CloneLanguage.byCode(_language).script ?? '';
    setState(() => _language = code);
    // Swap the reading script unless the user already typed their own words.
    if (_transcript.text.trim().isEmpty || _transcript.text == old) {
      _transcript.text = CloneLanguage.byCode(code).script ?? '';
    }
  }

  Future<void> _toggleRecord() async {
    if (_mic.recording) return _stopRecording();
    if (!_micExplained) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.mic_rounded),
          title: const Text('Use the microphone? · మైక్ అనుమతి'),
          content: Text(
            'The app records only while the red Stop button is showing (up to '
            '${_provider.maxSeconds.toStringAsFixed(0)} seconds). Android will ask you to allow the microphone.',
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
      await AppScope.read(context).playback.stop();
      final started = await _mic.start();
      if (!mounted) return;
      if (!started) {
        showMessage(context, 'Microphone permission was not given. Allow it in Android Settings → Apps → Telugu AI Voice.', error: true);
        return;
      }
      setState(() => _seconds = 0);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= _provider.maxSeconds) _stopRecording();
      });
    } catch (_) {
      if (mounted) showMessage(context, 'Could not start recording on this device.', error: true);
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      final bytes = await _mic.stop();
      if (!mounted) return;
      if (bytes == null || (wavSeconds(bytes) ?? 1) < 1) {
        showMessage(context, 'Nothing was recorded. Hold the phone close and try again.', error: true);
        setState(() {});
        return;
      }
      _useSample(bytes, 'voice_sample.wav');
    } catch (_) {
      if (mounted) showMessage(context, 'The recording could not be saved. Please try again.', error: true);
    }
  }

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [_audioTypes]);
    if (file == null || !mounted) return;
    if (await file.length() > 20 * 1024 * 1024) {
      if (mounted) showMessage(context, 'Please choose a file smaller than 20 MB.', error: true);
      return;
    }
    final bytes = await file.readAsBytes();
    if (mounted) _useSample(bytes, file.name);
  }

  void _useSample(Uint8List bytes, String name) {
    AppScope.read(context).playback.stop();
    setState(() {
      _sample = bytes;
      _filename = name;
      _samplePreview = LocalAudio.preview(bytes, title: 'Your recording · మీ రికార్డింగ్');
    });
  }

  void _reRecord() {
    AppScope.read(context).playback.stop();
    setState(() {
      _sample = null;
      _samplePreview = null;
      _seconds = 0;
    });
  }

  Future<void> _create() async {
    final sample = _sample;
    if (sample == null) return;
    FocusScope.of(context).unfocus();
    await AppScope.read(context).playback.stop();
    setState(() {
      _busy = true;
      _progress = 0.02;
      _progressText = 'Starting…';
    });
    try {
      final profile = await widget.service.createVoice(
        name: _name.text,
        category: _category,
        recordingLanguage: _language,
        sample: sample,
        filename: _filename,
        transcript: _provider.needsTranscript ? _transcript.text : null,
        provider: widget.service.onDevice ? null : _provider.name,
        makePreview: _makePreview,
        consent: ConsentRecord(
          relationship: _relationship,
          statement: ConsentRecord.statementFor(_relationship),
          speakerName: _relationship == 'self' ? null : _speaker.text.trim(),
        ),
        onProgress: (f, m) {
          if (mounted) {
            setState(() {
              _progress = f;
              _progressText = m;
            });
          }
        },
      );
      if (!mounted) return;
      showMessage(context, profile.warning ?? 'Voice "${profile.name}" saved · స్వరం సేవ్ అయింది', error: profile.warning != null);
      setState(() {
        _sample = null;
        _samplePreview = null;
        _consent = false;
        _name.clear();
        _speaker.clear();
      });
      widget.onCreated(profile);
    } catch (e) {
      if (mounted) showMessage(context, _errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final provider = _provider;
    final languages = _recordingLanguages;
    if (!languages.any((l) => l.code == _language) && languages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setLanguage(languages.first.code));
    }
    final lang = CloneLanguage.byCode(_language);
    final recording = _mic.recording;
    final seconds = _sample == null ? null : wavSeconds(_sample!);
    final readyProviders = widget.service.providers.where((p) => p.ready).toList();

    String? blocked;
    if (readyProviders.isEmpty) {
      blocked = 'No voice cloning provider is ready on the server.';
    } else if (_name.text.trim().isEmpty) {
      blocked = 'Give the voice a name.';
    } else if (recording) {
      blocked = 'Stop the recording first.';
    } else if (_sample == null) {
      blocked = 'Record or upload a voice sample.';
    } else if (seconds != null && seconds < provider.minSeconds) {
      blocked = 'Record at least ${provider.minSeconds.toStringAsFixed(0)} seconds.';
    } else if (provider.needsTranscript && _transcript.text.trim().length < 2) {
      blocked = 'Type the exact words spoken in the recording.';
    } else if (_relationship == 'permission' && _speaker.text.trim().isEmpty) {
      blocked = "Type the speaker's name.";
    } else if (!_consent) {
      blocked = 'Please confirm consent.';
    }

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 40),
      children: [
        ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '1 · స్వరం వివరాలు · About the voice',
                icon: Icons.badge_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('clone-name'),
                      controller: _name,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Voice name', hintText: 'e.g. My voice, Amma'),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (value, label, icon) in const [
                          ('female', 'స్త్రీ · Female', Icons.woman_rounded),
                          ('male', 'పురుష · Male', Icons.man_rounded),
                        ])
                          ChoiceChip(
                            key: Key('cat-$value'),
                            avatar: Icon(icon, size: 18),
                            label: Text(label),
                            selected: _category == value,
                            onSelected: (_) => setState(() => _category = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This is only a label. The new voice always sounds like the person in the recording – '
                      'a female voice must be recorded by a female speaker who agreed to it.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (!widget.service.onDevice && readyProviders.length > 1) ...[
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Provider', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: provider.name,
                            items: [
                              for (final p in readyProviders)
                                DropdownMenuItem(value: p.name, child: Text('${p.label}${p.paid ? ' · paid' : ' · free'}', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => _providerName = v),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Recording language', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('rec-lang'),
                          isExpanded: true,
                          value: languages.any((l) => l.code == _language) ? _language : null,
                          items: [for (final l in languages) DropdownMenuItem(value: l.code, child: Text(l.label))],
                          onChanged: (v) {
                            if (v != null) _setLanguage(v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: '2 · రికార్డ్ చేయండి · Record the voice',
                icon: Icons.mic_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Note(
                      icon: Icons.tips_and_updates_rounded,
                      text: '${provider.recommended}\nNo music or other voices. Hold the phone about a hand-width from your mouth.',
                    ),
                    const SizedBox(height: 12),
                    if (provider.needsTranscript || lang.script != null) ...[
                      Text(
                        lang.script != null ? 'Read this aloud · దీన్ని చదవండి:' : 'Say any sentence, then type the exact words below.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (lang.script != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.goldSoft.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(lang.script!, style: AppTheme.teluguBody(context).copyWith(fontSize: 18, height: 1.6)),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('clone-record'),
                            style: recording ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
                            onPressed: _busy ? null : _toggleRecord,
                            icon: Icon(recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded),
                            label: Text(recording ? 'Stop · ${formatDuration(_seconds.toDouble())}' : (_sample == null ? 'Record · రికార్డ్' : 'Record again')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const Key('clone-upload'),
                            onPressed: (_busy || recording) ? null : _pickFile,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Upload file'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (recording) ...[
                      LinearProgressIndicator(value: (_seconds / provider.maxSeconds).clamp(0, 1).toDouble()),
                      const SizedBox(height: 4),
                      Text(
                        'Aim for ${provider.minSeconds.toStringAsFixed(0)}–${provider.maxSeconds.toStringAsFixed(0)} seconds. '
                        'Stops by itself at ${provider.maxSeconds.toStringAsFixed(0)} s.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (_samplePreview != null) ...[
                      LocalAudioTile(key: const Key('clone-sample'), item: _samplePreview!, label: 'Your sample · మీ నమూనా', showShare: false),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              seconds == null
                                  ? 'Uploaded file: $_filename'
                                  : '${seconds.toStringAsFixed(1)} seconds'
                                      '${seconds < provider.minSeconds ? ' – too short' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: (seconds != null && seconds < provider.minSeconds) ? theme.colorScheme.error : null,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('clone-rerecord'),
                            onPressed: _busy ? null : _reRecord,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Re-record'),
                          ),
                        ],
                      ),
                    ],
                    if (provider.needsTranscript) ...[
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('clone-transcript'),
                        controller: _transcript,
                        minLines: 2,
                        maxLines: 5,
                        style: AppTheme.teluguBody(context),
                        decoration: const InputDecoration(
                          labelText: 'Exact words in the recording',
                          helperText: 'Change this if you said something different. The AI needs the exact words.',
                          helperMaxLines: 2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: '3 · అనుమతి · Consent',
                icon: Icons.verified_user_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioGroup<String>(
                      groupValue: _relationship,
                      onChanged: (v) => setState(() => _relationship = v ?? 'self'),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            key: const Key('consent-self'),
                            value: 'self',
                            contentPadding: EdgeInsets.zero,
                            title: const Text('This is my own voice'),
                          ),
                          RadioListTile<String>(
                            key: const Key('consent-permission'),
                            value: 'permission',
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Another person who gave me explicit permission'),
                          ),
                        ],
                      ),
                    ),
                    if (_relationship == 'permission')
                      TextField(
                        key: const Key('clone-speaker'),
                        controller: _speaker,
                        decoration: const InputDecoration(labelText: "Speaker's name"),
                      ),
                    CheckboxListTile(
                      key: const Key('clone-consent'),
                      value: _consent,
                      onChanged: (v) => setState(() => _consent = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('I confirm the above.'),
                      subtitle: Text(
                        '${ConsentRecord.statementFor(_relationship)} '
                        '${widget.service.onDevice ? 'The recording is sent to the free Hugging Face server whenever this voice speaks.' : 'The recording is stored on the app server and sent to ${provider.label}.'}',
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.service.onDevice)
                CheckboxListTile(
                  key: const Key('clone-preview'),
                  value: _makePreview,
                  onChanged: (v) => setState(() => _makePreview = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Also make a short spoken preview now'),
                  subtitle: const Text("Uses 1 of today's free voices. Leave it off to save them; you can still play your recording."),
                ),
              const SizedBox(height: 12),

              FilledButton.icon(
                key: const Key('clone-create'),
                onPressed: (blocked == null && !_busy) ? _create : null,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_busy ? (_progressText ?? 'Creating…') : 'AI స్వరం తయారు చేయండి · Create AI voice'),
              ),
              if (_busy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: _progress),
              ],
              if (blocked != null && !_busy) ...[
                const SizedBox(height: 8),
                Text(
                  blocked,
                  key: const Key('clone-blocked'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---- 2. My Voice Library --------------------------------------------------------------

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({required this.service, required this.onUse, required this.onCreate});

  final CloneService service;
  final ValueChanged<VoiceProfile> onUse;
  final VoidCallback onCreate;

  Future<void> _delete(BuildContext context, VoiceProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voice? · తొలగించాలా?'),
        content: Text('"${p.name}" and its recording will be deleted. Speech already made stays in History.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AppScope.read(context).playback.stop();
      await service.deleteVoice(p);
      if (context.mounted) showMessage(context, 'Deleted · తొలగించబడింది');
    } catch (e) {
      if (context.mounted) showMessage(context, _errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = service.profiles;
    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 40),
      children: [
        ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (profiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.record_voice_over_outlined, size: 56, color: theme.colorScheme.outline),
                      const SizedBox(height: 10),
                      Text('No voices yet · ఇంకా స్వరాలు లేవు', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Record a voice once to start.', style: TextStyle(color: theme.colorScheme.outline)),
                      const SizedBox(height: 14),
                      FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.mic_rounded), label: const Text('Create a voice')),
                    ],
                  ),
                ),
              for (final p in profiles) ...[
                _ProfileCard(profile: p, service: service, onUse: () => onUse(p), onDelete: () => _delete(context, p)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.service, required this.onUse, required this.onDelete});

  final VoiceProfile profile;
  final CloneService service;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = profile;
    final lang = CloneLanguage.byCode(p.recordingLanguage);
    final provider = service.providerFor(p.provider);
    final consentText = p.consent['relationship'] == 'permission'
        ? 'Permission from ${p.consent['speaker_name'] ?? 'the speaker'}'
        : 'Own voice';
    final consentAt = DateTime.tryParse(p.consent['accepted_at'] as String? ?? '')?.toLocal();
    return Card(
      key: Key('profile-${p.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: p.category == 'female' ? AppColors.goldSoft : scheme.primary.withValues(alpha: 0.12),
                  child: Icon(p.category == 'female' ? Icons.woman_rounded : Icons.man_rounded, color: p.category == 'female' ? AppColors.onGold : scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        '${p.category == 'female' ? 'Female' : 'Male'} · recorded in ${lang.name} · ${formatDateTime(p.createdAt)}',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                if (!p.ready)
                  Chip(label: Text(p.status == 'failed' ? 'Failed' : 'Not ready'), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 10),
            if (p.preview != null)
              LocalAudioTile(item: p.preview!, label: 'Voice preview · నమూనా', showShare: false)
            else if (p.sample != null)
              LocalAudioTile(item: p.sample!, label: 'Original recording', showShare: false),
            const SizedBox(height: 8),
            Text(
              'Voice ID: ${p.id}\nEngine: ${provider.label}${provider.crossLingual ? ' · speaks other languages too' : ''}\n'
              'Consent: $consentText${consentAt != null ? ' · ${formatDateTime(consentAt)}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline, height: 1.5),
            ),
            if (p.warning != null) ...[
              const SizedBox(height: 6),
              Text(p.warning!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('use-${p.id}'),
                    onPressed: p.ready ? onUse : null,
                    icon: const Icon(Icons.record_voice_over_rounded),
                    label: const Text('Use this voice'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  key: Key('delete-${p.id}'),
                  tooltip: 'Delete voice',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- 3. Text to Speech ------------------------------------------------------------------

class _SpeakTab extends StatefulWidget {
  const _SpeakTab({super.key, required this.service, required this.selectedProfileId, required this.onSelect, required this.onCreate});

  final CloneService service;
  final String? selectedProfileId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCreate;

  @override
  State<_SpeakTab> createState() => _SpeakTabState();
}

class _SpeakTabState extends State<_SpeakTab> with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  String _language = 'te';
  double _speed = 1.0;
  bool _keyboard = false;
  bool _busy = false;
  double _progress = 0;
  String? _progressText;
  LocalAudio? _result;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _text.text = CloneLanguage.byCode('te').sample ?? '';
    _text.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  VoiceProfile? get _profile {
    final ready = widget.service.profiles.where((p) => p.ready).toList();
    if (ready.isEmpty) return null;
    return ready.firstWhere((p) => p.id == widget.selectedProfileId, orElse: () => ready.first);
  }

  Future<void> _generate(VoiceProfile profile) async {
    FocusScope.of(context).unfocus();
    final app = AppScope.read(context);
    await app.playback.stop();
    setState(() {
      _busy = true;
      _progress = 0.05;
      _progressText = 'Connecting…';
    });
    try {
      final item = await widget.service.speak(
        profile: profile,
        text: _text.text.trim(),
        language: _language,
        speed: _speed,
        onProgress: (f, m) {
          if (mounted) {
            setState(() {
              _progress = f;
              _progressText = m;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _result = item);
      showMessage(context, 'Voice ready · వాయిస్ సిద్ధం');
      try {
        await app.playback.toggle(item, () => app.localAudio.bytesOf(item));
      } catch (_) {
        // The Play button on the result still works.
      }
    } catch (e) {
      if (mounted) showMessage(context, _errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadMp3(LocalAudio item) async {
    final link = widget.service.mp3Link(item);
    if (link == null) return;
    final ok = await launchUrl(link, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, 'Could not open the download link.', error: true);
  }

  Future<void> _deleteGeneration(LocalAudio item) async {
    try {
      final app = AppScope.read(context);
      if (app.playback.isPlaying(item.id)) await app.playback.stop();
      await widget.service.deleteGeneration(item);
      if (_result?.id == item.id) setState(() => _result = null);
    } catch (e) {
      if (mounted) showMessage(context, _errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final service = widget.service;
    final profile = _profile;
    final ready = service.profiles.where((p) => p.ready).toList();
    final provider = profile == null ? null : service.providerFor(profile.provider);
    final languages = CloneLanguage.all.where((l) => provider?.languages.contains(l.code) ?? l.code != 'en').toList();
    final language = languages.any((l) => l.code == _language) ? _language : (languages.isEmpty ? 'te' : languages.first.code);
    final lang = CloneLanguage.byCode(language);
    final maxChars = service.onDevice ? FreeVoiceEngine.maxChars : 2000;
    final length = _text.text.trim().characters.length;
    final speedAvailable = service.onDevice || (provider?.supportsSpeed ?? false);
    final scriptMismatch = length > 0 && !lang.matches(_text.text);

    String? blocked;
    if (profile == null) {
      blocked = 'Create a voice first.';
    } else if (length == 0) {
      blocked = 'Type some text first.';
    } else if (length > maxChars) {
      blocked = 'Text is longer than $maxChars characters.';
    }

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 40),
      children: [
        ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ready.isEmpty)
                _Note(
                  icon: Icons.info_outline_rounded,
                  text: 'You have no saved voices yet. Go to "Create Voice", record once, and the voice is saved for good.',
                ),
              if (ready.isEmpty) ...[
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: widget.onCreate, icon: const Icon(Icons.mic_rounded), label: const Text('Create a voice')),
                const SizedBox(height: 14),
              ],
              SectionCard(
                title: 'స్వరం & భాష · Voice and language',
                icon: Icons.record_voice_over_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Saved voice', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('clone-voice'),
                          isExpanded: true,
                          value: profile?.id,
                          hint: const Text('No saved voices'),
                          items: [
                            for (final p in ready)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.name} · ${p.category == 'female' ? 'Female' : 'Male'}', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: widget.onSelect,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Speak in', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('clone-lang'),
                          isExpanded: true,
                          value: language,
                          items: [for (final l in languages) DropdownMenuItem(value: l.code, child: Text(l.label))],
                          onChanged: (v) {
                            if (v == null) return;
                            final oldSample = CloneLanguage.byCode(language).sample;
                            setState(() => _language = v);
                            if (_text.text.trim().isEmpty || _text.text == oldSample) {
                              _text.text = CloneLanguage.byCode(v).sample ?? '';
                            }
                          },
                        ),
                      ),
                    ),
                    if (service.onDevice && !languages.any((l) => l.code == 'en')) ...[
                      const SizedBox(height: 6),
                      Text(
                        'English needs a paid provider (Sarvam AI or ElevenLabs) on the app server.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: 'మీ టెక్స్ట్ · Your text',
                icon: Icons.edit_note_rounded,
                trailing: language == 'te'
                    ? TextButton.icon(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _keyboard = !_keyboard);
                        },
                        icon: Icon(_keyboard ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded),
                        label: Text(_keyboard ? 'Hide' : 'తెలుగు కీబోర్డ్'),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('clone-text'),
                      controller: _text,
                      minLines: 6,
                      maxLines: 14,
                      keyboardType: TextInputType.multiline,
                      style: AppTheme.teluguBody(context),
                      decoration: InputDecoration(
                        hintText: 'Type in ${lang.name}…',
                        counterText: '$length / $maxChars',
                        counterStyle: TextStyle(color: length > maxChars ? theme.colorScheme.error : theme.colorScheme.outline),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (lang.sample != null)
                          TextButton.icon(
                            onPressed: () => _text.text = lang.sample!,
                            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                            label: const Text('Sample'),
                          ),
                        TextButton.icon(onPressed: _text.clear, icon: const Icon(Icons.clear_rounded, size: 18), label: const Text('Clear')),
                      ],
                    ),
                    if (scriptMismatch)
                      Text(
                        'This text is not written in ${lang.name} script. The voice reads the script you type, '
                        'so choose the matching language above.',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning),
                      ),
                    if (_keyboard && language == 'te') ...[
                      const SizedBox(height: 8),
                      TeluguKeyboard(controller: _text, onClose: () => setState(() => _keyboard = false)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: 'వేగం · Speed',
                icon: Icons.speed_rounded,
                trailing: TextButton(onPressed: () => setState(() => _speed = 1.0), child: const Text('Reset')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${_speed.toStringAsFixed(2)}×'),
                    Slider(
                      key: const Key('clone-speed'),
                      value: _speed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      label: '${_speed.toStringAsFixed(2)}×',
                      onChanged: speedAvailable ? (v) => setState(() => _speed = v) : null,
                    ),
                    Text(
                      speedAvailable
                          ? 'Changes the speaking speed without changing the voice\'s pitch.'
                          : '${provider?.label ?? 'This provider'} has no speed control.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              FilledButton.icon(
                key: const Key('clone-generate'),
                onPressed: (blocked == null && !_busy && profile != null) ? () => _generate(profile) : null,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.graphic_eq_rounded),
                label: Text(_busy ? (_progressText ?? 'Generating…') : 'వాయిస్ తయారు చేయండి · Generate voice'),
              ),
              if (_busy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: _progress),
              ],
              if (blocked != null && !_busy) ...[
                const SizedBox(height: 8),
                Text(blocked, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
              if (service.onDevice) ...[
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final account = AppScope.of(context).hfAccount;
                  return Text(
                    account == null
                        ? 'Made by the free AI4Bharat IndicF5 server: about 10–40 seconds each, about 2 a day. '
                            'Add your free Hugging Face account in Settings for about 5 a day.'
                        : 'Made by the free AI4Bharat IndicF5 server on ${account.name}: about ${account.dailyRequests} a day.',
                    key: const Key('clone-allowance'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  );
                }),
              ],

              if (_result != null) ...[
                const SizedBox(height: 20),
                SectionCard(
                  title: 'ఫలితం · Result',
                  icon: Icons.check_circle_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LocalAudioTile(key: const Key('clone-result'), item: _result!),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => shareLocalAudio(context, _result!),
                            icon: const Icon(Icons.share_rounded),
                            label: const Text('Share (WhatsApp…)'),
                          ),
                          if (service.canDownloadMp3)
                            FilledButton.tonalIcon(
                              key: const Key('clone-mp3'),
                              onPressed: () => _downloadMp3(_result!),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Download MP3'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => shareLocalAudio(context, _result!),
                              icon: const Icon(Icons.save_alt_rounded),
                              label: const Text('Save WAV to Files'),
                            ),
                        ],
                      ),
                      if (!service.canDownloadMp3) ...[
                        const SizedBox(height: 6),
                        Text(
                          'On this phone voices are saved as WAV (best quality). MP3 download comes from the app server.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.history_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('చరిత్ర · Generation history', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(tooltip: 'Refresh', onPressed: service.refreshHistory, icon: const Icon(Icons.refresh_rounded)),
                ],
              ),
              const SizedBox(height: 6),
              if (service.history.isEmpty)
                Text('Nothing made yet.', style: TextStyle(color: theme.colorScheme.outline))
              else
                for (final item in service.history.take(30)) ...[
                  LocalAudioTile(item: item, showDate: true, onDelete: () => _deleteGeneration(item)),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

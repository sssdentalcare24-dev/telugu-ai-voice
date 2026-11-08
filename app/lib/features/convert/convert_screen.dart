import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/feature_status.dart';
import '../../core/state/app_scope.dart';
import '../../widgets/audio_tile.dart';
import '../../widgets/common.dart';

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

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key, required this.direction});

  final ConversionDirection direction;

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

  bool _consent = false;
  bool _uploading = false;
  bool _converting = false;
  AudioItem? _original;
  AudioItem? _converted;

  Future<void> _pickAndUpload() async {
    final app = AppScope.read(context);
    final XFile? file = await openFile(acceptedTypeGroups: const [_audioTypes]);
    if (file == null || !mounted) return;
    final maxMb = app.health?.limits.maxUploadMb ?? 20;
    setState(() => _uploading = true);
    try {
      final size = await file.length();
      if (size > maxMb * 1024 * 1024) {
        if (mounted) showMessage(context, 'Files must be $maxMb MB or smaller.', error: true);
        return;
      }
      final bytes = await file.readAsBytes();
      final item = await app.api.uploadAudio(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _original = item;
        _converted = null;
      });
      showMessage(context, 'Uploaded · అప్‌లోడ్ అయింది');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _convert() async {
    final original = _original;
    if (original == null) return;
    final app = AppScope.read(context);
    setState(() => _converting = true);
    try {
      final result = await app.api.convertVoice(
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
      if (e.isProviderMissing) await app.refreshServer();
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final d = widget.direction;
    final status = FeatureStatus.of(app, d.feature);
    final limits = app.health?.limits;

    String? blocked;
    if (!status.ready) {
      blocked = status.message;
    } else if (_original == null) {
      blocked = 'Upload a ${d.from} voice recording first.';
    } else if (!_consent) {
      blocked = 'Please confirm consent above.';
    }

    return Scaffold(
      appBar: AppBar(title: Text(d.titleEn)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        child: ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeading(telugu: d.titleTe, english: 'Convert ${d.from} speech into a natural ${d.to} Telugu voice'),
              FeatureStatusBanner(feature: d.feature),

              // ---- Source audio ------------------------------------------------
              SectionCard(
                title: '1 · అసలు ఆడియో · Source audio',
                icon: Icons.mic_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.fiber_manual_record_rounded),
                            label: const Text('Record'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const StageTag(4),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const Key('upload-button'),
                            onPressed: (app.health == null || _uploading) ? null : _pickAndUpload,
                            icon: _uploading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.upload_file_rounded),
                            label: Text(_uploading ? 'Uploading…' : 'Upload file'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      limits == null
                          ? 'WAV, MP3, OGG, FLAC or M4A.'
                          : '${limits.allowedFormats.map((f) => f.toUpperCase()).join(', ')} · up to ${limits.maxUploadMb} MB · '
                              'up to ${(limits.maxAudioSeconds / 60).toStringAsFixed(0)} min',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (_original != null) ...[
                      const SizedBox(height: 12),
                      AudioSummaryTile(item: _original!, label: 'Before · అసలు'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ---- Consent -----------------------------------------------------
              SectionCard(
                title: '2 · అనుమతి · Consent',
                icon: Icons.verified_user_rounded,
                child: CheckboxListTile(
                  key: const Key('consent-checkbox'),
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('This is my own voice, or I have the speaker\'s permission.'),
                  subtitle: const Text('I will not use converted audio to impersonate any real person.'),
                ),
              ),
              const SizedBox(height: 20),

              FilledButton.icon(
                key: const Key('convert-button'),
                onPressed: (blocked == null && !_converting) ? _convert : null,
                icon: _converting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.swap_horiz_rounded),
                label: Text(_converting ? 'Converting…' : 'మార్చండి · Convert to ${d.to} voice'),
              ),
              if (blocked != null) ...[
                const SizedBox(height: 8),
                Text(
                  blocked,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
              const SizedBox(height: 20),

              // ---- Before / after ------------------------------------------------
              SectionCard(
                title: '3 · ముందు / తర్వాత · Before / after',
                icon: Icons.compare_arrows_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_original != null)
                      AudioSummaryTile(item: _original!, label: 'Before · అసలు')
                    else
                      const _Placeholder(text: 'Original recording will appear here'),
                    const SizedBox(height: 10),
                    if (_converted != null)
                      AudioSummaryTile(item: _converted!, label: 'After · మార్చినది')
                    else
                      const _Placeholder(text: 'Converted audio will appear here'),
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

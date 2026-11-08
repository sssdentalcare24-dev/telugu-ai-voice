import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/config/app_config.dart';
import '../../core/feature_status.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/tts/device_tts.dart';
import '../../widgets/audio_tile.dart';
import '../../widgets/common.dart';
import '../../widgets/telugu_keyboard.dart';

/// Where the speech comes from.
enum VoiceSource { server, phone }

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key, this.phoneVoice});

  /// Injected in tests; created automatically otherwise.
  final PhoneVoice? phoneVoice;

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final TextEditingController _text = TextEditingController(text: AppConfig.sampleTeluguText);
  late final PhoneVoice _phone = widget.phoneVoice ?? PhoneVoice();
  VoiceSource? _source; // null = choose automatically
  String _gender = 'female';
  String? _voiceId;
  String? _style;
  double _speed = 1.0;
  double _pitch = 0.0;
  bool _showKeyboard = false;
  bool _busy = false;
  AudioItem? _result;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
    _phone.addListener(_onChanged);
    _phone.init();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _phone.removeListener(_onChanged);
    if (widget.phoneVoice == null) _phone.dispose();
    _text.dispose();
    super.dispose();
  }

  List<Voice> _voicesFor(List<Voice> all) => all.where((v) => v.gender == _gender).toList();

  Voice? _selectedVoice(List<Voice> options) {
    if (options.isEmpty) return null;
    for (final v in options) {
      if (v.id == _voiceId) return v;
    }
    return options.firstWhere((v) => v.available, orElse: () => options.first);
  }

  Future<void> _generate(Voice voice) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final app = AppScope.read(context);
    try {
      final item = await app.api.generateSpeech(
        text: _text.text,
        voiceId: voice.id,
        speed: _speed,
        pitch: voice.supportsPitch ? _pitch : 0,
        style: _style,
      );
      if (!mounted) return;
      setState(() => _result = item);
      showMessage(context, 'Audio ready · ఆడియో సిద్ధం');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
      if (e.isProviderMissing) await app.refreshServer();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playPhone() async {
    FocusScope.of(context).unfocus();
    if (_phone.speaking) {
      await _phone.stop();
      return;
    }
    await _phone.speak(_text.text, speed: _speed, semitones: _pitch);
    if (mounted && _phone.state == PhoneVoiceState.unsupported) {
      showMessage(context, 'The phone voice could not start.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final serverStatus = FeatureStatus.serverOf(app, Feature.tts);
    final source = _source ?? (serverStatus.ready ? VoiceSource.server : VoiceSource.phone);
    final maxChars = app.health?.limits.maxTtsChars ?? 5000;
    final options = _voicesFor(app.voices);
    final voice = _selectedVoice(options);
    final length = _text.text.trim().characters.length;
    final tooLong = length > maxChars;
    final pitchEnabled = source == VoiceSource.phone || (voice?.supportsPitch ?? false);

    String? blockedReason;
    if (source == VoiceSource.server) {
      if (!serverStatus.ready) {
        blockedReason = serverStatus.message;
      } else if (voice == null) {
        blockedReason = 'No ${_gender == 'female' ? 'female' : 'male'} voice is listed by the server.';
      } else if (!voice.available) {
        blockedReason = 'The ${voice.provider} provider for this voice is not configured. Pick another voice.';
      }
    } else {
      blockedReason = switch (_phone.state) {
        PhoneVoiceState.checking => 'Checking the phone voice…',
        PhoneVoiceState.missing => 'No Telugu voice is installed on this phone. See the steps above.',
        PhoneVoiceState.unsupported => 'This device has no text-to-speech engine the app can use.',
        PhoneVoiceState.ready => null,
      };
    }
    if (blockedReason == null && length == 0) blockedReason = 'Type some Telugu text first.';
    if (blockedReason == null && tooLong) blockedReason = 'Text is longer than $maxChars characters.';

    return Scaffold(
      appBar: AppBar(title: const Text('Telugu Text to Voice')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        child: ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScreenHeading(telugu: 'తెలుగు టెక్స్ట్ నుండి వాయిస్', english: 'Type Telugu, choose a voice, listen'),

              // ---- Text ---------------------------------------------------------
              SectionCard(
                title: 'మీ టెక్స్ట్ · Your text',
                icon: Icons.edit_note_rounded,
                trailing: TextButton.icon(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _showKeyboard = !_showKeyboard);
                  },
                  icon: Icon(_showKeyboard ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded),
                  label: Text(_showKeyboard ? 'Hide' : 'తెలుగు కీబోర్డ్'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('tts-text'),
                      controller: _text,
                      minLines: 5,
                      maxLines: 12,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: AppTheme.teluguBody(context),
                      decoration: InputDecoration(
                        hintText: 'ఇక్కడ తెలుగులో టైప్ చేయండి…',
                        counterText: '$length / $maxChars',
                        counterStyle: TextStyle(color: tooLong ? theme.colorScheme.error : theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _text.text = AppConfig.sampleTeluguText,
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: const Text('Sample'),
                        ),
                        TextButton.icon(
                          onPressed: _text.clear,
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    if (_showKeyboard) ...[
                      const SizedBox(height: 8),
                      TeluguKeyboard(controller: _text, onClose: () => setState(() => _showKeyboard = false)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Tip: you can also add Telugu to Gboard (Settings → Languages) for a full phone keyboard.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ---- Voice source ------------------------------------------------------
              SectionCard(
                title: 'స్వరం · Voice',
                icon: Icons.record_voice_over_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<VoiceSource>(
                      key: const Key('voice-source'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: VoiceSource.phone,
                          icon: Icon(Icons.phone_android_rounded),
                          label: Text('Phone voice'),
                        ),
                        ButtonSegment(
                          value: VoiceSource.server,
                          icon: Icon(Icons.dns_rounded),
                          label: Text('Natural (server)'),
                        ),
                      ],
                      selected: {source},
                      onSelectionChanged: (s) => setState(() => _source = s.first),
                    ),
                    const SizedBox(height: 14),
                    if (source == VoiceSource.phone)
                      _PhoneVoicePanel(phone: _phone)
                    else ...[
                      if (!serverStatus.ready) ...[
                        _InfoBox(icon: serverStatus.icon, text: serverStatus.message),
                        const SizedBox(height: 12),
                      ],
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'female', icon: Icon(Icons.woman_rounded), label: Text('స్త్రీ · Female')),
                          ButtonSegment(value: 'male', icon: Icon(Icons.man_rounded), label: Text('పురుష · Male')),
                        ],
                        selected: {_gender},
                        onSelectionChanged: (s) => setState(() {
                          _gender = s.first;
                          _voiceId = null;
                          _style = null;
                          _pitch = 0;
                        }),
                      ),
                      const SizedBox(height: 14),
                      if (options.isEmpty)
                        Text(
                          app.health == null ? 'Voices load when the server is reachable.' : 'No voices configured.',
                          style: TextStyle(color: theme.colorScheme.outline),
                        )
                      else
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Voice',
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const Key('voice-dropdown'),
                              isExpanded: true,
                              value: voice?.id,
                              items: [
                                for (final v in options)
                                  DropdownMenuItem(
                                    value: v.id,
                                    child: Text(
                                      v.available ? v.displayName : '${v.displayName}  (not configured)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (id) => setState(() {
                                _voiceId = id;
                                _style = null;
                                _pitch = 0;
                              }),
                            ),
                          ),
                        ),
                      if (voice?.notes != null) ...[
                        const SizedBox(height: 8),
                        Text(voice!.notes!, style: theme.textTheme.bodySmall),
                      ],
                      if (voice != null && voice.styles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Speaking style',
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: _style,
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Default')),
                                for (final s in voice.styles) DropdownMenuItem<String?>(value: s, child: Text(s)),
                              ],
                              onChanged: (s) => setState(() => _style = s),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Accent: standard Telugu. Separate Telangana / Andhra accent voices are not offered today.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ---- Speed & pitch ---------------------------------------------------
              SectionCard(
                title: 'వేగం & పిచ్ · Speed & pitch',
                icon: Icons.tune_rounded,
                trailing: TextButton(
                  onPressed: () => setState(() {
                    _speed = 1.0;
                    _pitch = 0;
                  }),
                  child: const Text('Reset'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Speed  ${_speed.toStringAsFixed(2)}×'),
                    Slider(
                      value: _speed,
                      min: 0.25,
                      max: 2.0,
                      divisions: 35,
                      label: '${_speed.toStringAsFixed(2)}×',
                      onChanged: (v) => setState(() => _speed = v),
                    ),
                    Text('Pitch  ${_pitch >= 0 ? '+' : ''}${_pitch.toStringAsFixed(0)} semitones'),
                    Slider(
                      value: _pitch,
                      min: -12,
                      max: 12,
                      divisions: 24,
                      label: _pitch.toStringAsFixed(0),
                      onChanged: pitchEnabled ? (v) => setState(() => _pitch = v) : null,
                    ),
                    if (!pitchEnabled)
                      Text(
                        'This voice does not support pitch changes.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ---- Action -----------------------------------------------------------
              if (source == VoiceSource.phone)
                FilledButton.icon(
                  key: const Key('phone-play-button'),
                  onPressed: (blockedReason == null || _phone.speaking) ? _playPhone : null,
                  icon: Icon(_phone.speaking ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(_phone.speaking ? 'ఆపండి · Stop' : 'ఫోన్ స్వరంతో వినండి · Play with phone voice'),
                )
              else
                FilledButton.icon(
                  key: const Key('generate-button'),
                  onPressed: (blockedReason == null && !_busy && voice != null) ? () => _generate(voice) : null,
                  icon: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.graphic_eq_rounded),
                  label: Text(_busy ? 'Generating…' : 'వాయిస్ తయారు చేయండి · Generate audio'),
                ),
              if (blockedReason != null && !_phone.speaking) ...[
                const SizedBox(height: 8),
                Text(
                  blockedReason,
                  key: const Key('generate-blocked-reason'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
              if (source == VoiceSource.phone) ...[
                const SizedBox(height: 8),
                Text(
                  "The phone voice plays aloud only; it can't be saved or downloaded. "
                  'Natural voices you can save arrive with the server (Stage 3).',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],

              if (_result != null) ...[
                const SizedBox(height: 20),
                SectionCard(
                  title: 'ఫలితం · Result',
                  icon: Icons.check_circle_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AudioSummaryTile(item: _result!),
                      const SizedBox(height: 10),
                      const Row(
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 6),
                          Expanded(child: Text('In-app player and share sheet')),
                          StageTag(3),
                          SizedBox(width: 6),
                          StageTag(7),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Saved to your audio history.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneVoicePanel extends StatelessWidget {
  const _PhoneVoicePanel({required this.phone});

  final PhoneVoice phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (phone.state) {
      case PhoneVoiceState.checking:
        return const _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Checking the phone voice…');
      case PhoneVoiceState.unsupported:
        return const _InfoBox(
          icon: Icons.block_rounded,
          text: 'This device has no text-to-speech engine the app can use. Choose the server voice instead.',
        );
      case PhoneVoiceState.missing:
        return const _InfoBox(
          icon: Icons.download_rounded,
          text: 'No Telugu voice is installed on this phone. Open Android Settings, search "Text-to-speech", '
              'open the Google engine settings → Install voice data → తెలుగు (Telugu). Then come back to this screen.',
        );
      case PhoneVoiceState.ready:
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _InfoBox(
          icon: Icons.phone_android_rounded,
          text: "Uses this phone's built-in Telugu voice. Free and works offline. "
              'It sounds less natural than the server voices.',
        ),
        if (phone.voices.length > 1) ...[
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Phone voice',
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('phone-voice-dropdown'),
                isExpanded: true,
                value: phone.selectedVoice,
                items: [
                  for (final v in phone.voices)
                    DropdownMenuItem(
                      value: v['name'],
                      child: Text('${v['name']}  (${v['locale']})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: phone.selectVoice,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try each one: Android names voices by code, not by gender.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

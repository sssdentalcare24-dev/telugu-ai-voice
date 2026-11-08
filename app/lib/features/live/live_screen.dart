import 'package:flutter/material.dart';

import '../../core/feature_status.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/waveform.dart';

/// Live voice changer.
///
/// This screen never fakes live conversion with a pitch shifter. Controls stay
/// disabled until the server reports a genuine streaming engine AND the
/// streaming client (Stage 6) is built.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  String _direction = 'male_to_female';
  bool _consent = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = FeatureStatus.of(app, Feature.live);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Voice Changer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        child: ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeading(
                telugu: 'లైవ్ వాయిస్ ఛేంజర్',
                english: 'Real-time two-way voice conversion',
                trailing: StatusPill(status: status),
              ),
              const FeatureStatusBanner(feature: Feature.live),
              SectionCard(
                title: 'దిశ · Direction',
                icon: Icons.swap_horiz_rounded,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'male_to_female', label: Text('పురుష → స్త్రీ')),
                    ButtonSegment(value: 'female_to_male', label: Text('స్త్రీ → పురుష')),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) => setState(() => _direction = s.first),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5), width: 2),
                      ),
                      child: Icon(Icons.mic_off_rounded, size: 44, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 16),
                    // Flat on purpose: nothing is being captured.
                    AnimatedWaveform(
                      animate: false,
                      flatWhenIdle: true,
                      height: 48,
                      bars: 48,
                      color: AppColors.gold.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Microphone off · మైక్ ఆఫ్‌లో ఉంది',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'నియంత్రణలు · Controls',
                icon: Icons.tune_rounded,
                trailing: const StageTag(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      value: _consent,
                      onChanged: (v) => setState(() => _consent = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('I will only convert my own voice, with the listener\'s knowledge.'),
                    ),
                    const SwitchListTile(
                      value: true,
                      onChanged: null,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.headphones_rounded),
                      title: Text('Headphone monitoring'),
                      subtitle: Text('Use headphones to avoid echo and feedback.'),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            key: Key('live-start-button'),
                            onPressed: null,
                            child: Text('Start · ప్రారంభించండి'),
                          ),
                        ),
                        SizedBox(width: 10),
                        IconButton.outlined(
                          tooltip: 'Mute',
                          onPressed: null,
                          icon: Icon(Icons.mic_off_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status.ready
                          ? 'The server has a streaming engine. The in-app streaming client is built in Stage 6.'
                          : 'Start stays disabled until a genuine streaming voice-conversion engine is connected (Stage 6).',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: 'ఇది ఎలా పనిచేస్తుంది · How it will work',
                icon: Icons.info_outline_rounded,
                child: Text(
                  '• Your microphone audio streams to the server in small chunks over a WebSocket.\n'
                  '• A speech-to-speech AI model re-voices each chunk as ${_direction == 'male_to_female' ? 'female' : 'male'} speech, '
                  'keeping your Telugu words and timing.\n'
                  '• Converted audio streams back to your headphones with low delay.\n'
                  '• This needs a real-time conversion engine (usually a GPU server). Simple pitch shifting is not used, '
                  'because it sounds robotic and is not true voice conversion.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

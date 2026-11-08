import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/feature_status.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _server;
  late final TextEditingController _devUser;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _server = TextEditingController(text: app.apiBaseUrl);
    _devUser = TextEditingController(text: app.devUser);
  }

  @override
  void dispose() {
    _server.dispose();
    _devUser.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    setState(() => _saving = true);
    final app = AppScope.read(context);
    await app.setApiBaseUrl(_server.text);
    if (!mounted) return;
    setState(() => _saving = false);
    showMessage(
      context,
      app.connection == ServerConnection.online ? 'Connected · కనెక్ట్ అయింది' : 'Could not reach ${app.api.baseUrl}',
      error: app.connection != ServerConnection.online,
    );
  }

  Future<void> _saveDevUser() async {
    final value = _devUser.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_.\-]{3,64}$').hasMatch(value)) {
      showMessage(context, 'Use 3–64 letters, digits, ".", "_" or "-".', error: true);
      return;
    }
    await AppScope.read(context).setDevUser(value);
    if (mounted) showMessage(context, 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final health = app.health;
    final theme = Theme.of(context);

    final connectionText = switch (app.connection) {
      ServerConnection.checking => 'Checking…',
      ServerConnection.online =>
        'Online · v${health?.version} · ${health?.environment} · sign-in: ${health?.authMode}',
      ServerConnection.offline => 'Offline · ${app.lastError ?? ''}',
    };

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        ResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScreenHeading(telugu: 'సెట్టింగ్స్', english: 'Appearance, server and feature status'),

              SectionCard(
                title: 'Appearance · రూపం',
                icon: Icons.palette_outlined,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: 'Server · సర్వర్',
                icon: Icons.dns_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('server-url'),
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API server address',
                        hintText: 'http://10.0.2.2:8000',
                        helperText: 'Emulator: http://10.0.2.2:8000 · Phone on Wi-Fi: http://<PC IP>:8000',
                      ),
                      onSubmitted: (_) => _saveServer(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(connectionText, style: theme.textTheme.bodySmall),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _saving ? null : _saveServer,
                          child: Text(_saving ? 'Testing…' : 'Save & test'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (health == null || health.devAuth) ...[
                SectionCard(
                  title: 'Developer sign-in',
                  icon: Icons.badge_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'The server is in development mode (AUTH_MODE=dev), so this name identifies you instead of a '
                        'real sign-in. Production uses Firebase Authentication and refuses dev mode.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _devUser,
                              autocorrect: false,
                              decoration: const InputDecoration(labelText: 'Dev user name'),
                              onSubmitted: (_) => _saveDevUser(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(onPressed: _saveDevUser, child: const Text('Save')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              SectionCard(
                title: 'Feature status · ఫీచర్ల స్థితి',
                icon: Icons.fact_check_outlined,
                trailing: IconButton(
                  tooltip: 'Check again',
                  onPressed: app.refreshServer,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                child: Column(
                  children: [
                    for (final (feature, name) in const [
                      (Feature.tts, 'Telugu text to voice'),
                      (Feature.maleToFemale, 'Male → female conversion'),
                      (Feature.femaleToMale, 'Female → male conversion'),
                      (Feature.live, 'Live voice changer'),
                    ])
                      _FeatureRow(name: name, status: FeatureStatus.of(app, feature)),
                    const Divider(height: 24),
                    const _StaticRow(name: 'Upload & audio history', detail: 'Works with the local server now'),
                    const _StaticRow(name: 'Recording from microphone', detail: 'Stage 4'),
                    const _StaticRow(name: 'In-app player, share sheet', detail: 'Stages 3 and 7'),
                    const _StaticRow(name: 'Firebase sign-in', detail: 'Stage 3 (needs your Firebase project)'),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: 'Privacy & consent',
                icon: Icons.privacy_tip_outlined,
                child: Text(
                  '• API keys stay on the server; the app never contains them.\n'
                  '• Your audio is private to your account and opened through links that expire in minutes.\n'
                  '• Voice conversion requires your consent each time, and must not be used to impersonate real people.\n'
                  '• The microphone is only used after you allow it, and only while recording.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  '${AppConfig.appName} · ${AppConfig.appSubtitle}\nVersion ${AppConfig.version} · Fonts: Noto Sans, Noto Sans Telugu (OFL)',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.name, required this.status});

  final String name;
  final FeatureStatus status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (!status.ready)
                  Text(status.message, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(status: status, dense: true),
        ],
      ),
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text(detail, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

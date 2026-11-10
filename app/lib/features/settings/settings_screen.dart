import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/feature_status.dart';
import '../../core/free/free_voice_engine.dart';
import '../../core/free/gradio_space.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_colors.dart';
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
                      (Feature.cloning, 'AI voice cloning'),
                      (Feature.live, 'Live voice changer'),
                    ])
                      _FeatureRow(name: name, status: FeatureStatus.of(app, feature)),
                    const Divider(height: 24),
                    const _StaticRow(name: 'Recording from microphone', detail: 'Ready'),
                    const _StaticRow(name: 'In-app player, share, history on phone', detail: 'Ready'),
                    const _StaticRow(name: 'Upload & server history', detail: 'With an app server'),
                    const _StaticRow(name: 'Firebase sign-in', detail: 'Stage 3 (needs your Firebase project)'),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              const _PcServerCard(),
              const SizedBox(height: 14),
              const _HfAccountCard(),
              const SizedBox(height: 14),

              SectionCard(
                title: 'Free AI engines · ఉచిత AI',
                icon: Icons.auto_awesome_outlined,
                child: Text(
                  'Used when no app server is connected. Both are free public demo servers on Hugging Face – '
                  'no account or API key needed, but they need internet, can be slow or busy, and share a small '
                  'free daily GPU allowance per internet connection (a few voices or conversions a day; it refills '
                  'over time).\n\n'
                  '• Natural Telugu voice: AI4Bharat IndicF5 (IIT Madras). Your text is sent to it.\n'
                  '• Voice conversion: Seed-VC. Your recording is uploaded to it.\n'
                  '• AI voice cloning: IndicF5 speaks in a voice you recorded. The saved sample is sent with each request.\n'
                  '• Results are saved only on this phone. Use Share to keep a copy elsewhere.\n'
                  '• Live (real-time) conversion has no free streaming engine, so it stays off.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              const SizedBox(height: 14),

              SectionCard(
                title: 'Privacy & consent',
                icon: Icons.privacy_tip_outlined,
                child: Text(
                  '• API keys stay on the server; the app never contains them.\n'
                  '• Server audio is private to your account and opened through links that expire in minutes.\n'
                  '• Free-engine audio is sent to Hugging Face only when you press Make / Convert.\n'
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


/// Lets the user add their own free Hugging Face account so the free voice
/// engines use that account's daily allowance (about 5 voices a day, or about
/// 40 with PRO) instead of the shared one (about 2 a day).
class _HfAccountCard extends StatefulWidget {
  const _HfAccountCard();

  @override
  State<_HfAccountCard> createState() => _HfAccountCardState();
}

class _HfAccountCardState extends State<_HfAccountCard> {
  final _token = TextEditingController();
  bool _checking = false;
  bool _hide = true;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, 'Could not open $url', error: true);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _checking = true);
    try {
      final account = await AppScope.read(context).setHfToken(_token.text);
      if (!mounted) return;
      _token.clear();
      showMessage(context, 'Added ${account.name} · about ${account.dailyRequests} voices a day');
    } on FreeEngineException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final account = app.hfAccount;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(height: 1.5);
    return SectionCard(
      title: 'More free uses · Hugging Face account',
      icon: Icons.bolt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('hf-status'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (account == null ? AppColors.warning : AppColors.success).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              account == null
                  ? 'Not added. The free voice servers allow about 2 voices a day, shared by everyone on your internet connection.'
                  : 'Using ${account.name} (${account.isPro ? 'PRO' : 'free account'}): about ${account.dailyRequests} '
                      'voices or conversions a day. The allowance refills 24 hours after its first use.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
          if (account == null) ...[
            Text('Get about 5 voices a day free, in 2 minutes:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              '1. Create a free account and confirm your email.\n'
              '2. Open Access Tokens → "Create new token" → choose "Read" → name it "Telugu Voice" → Create.\n'
              '3. Copy the token (it starts with hf_) and paste it below.',
              style: small,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _open('https://huggingface.co/join'),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: const Text('1 · Create account'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open('https://huggingface.co/settings/tokens'),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('2 · Access Tokens'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('hf-token'),
              controller: _token,
              obscureText: _hide,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '3 · Paste your token',
                hintText: 'hf_…',
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Show' : 'Hide',
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('hf-save'),
              onPressed: _checking ? null : _save,
              icon: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_checking ? 'Checking…' : 'Save & check'),
            ),
          ] else
            OutlinedButton.icon(
              key: const Key('hf-remove'),
              onPressed: () => app.clearHfToken(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Remove token from this phone'),
            ),
          const SizedBox(height: 10),
          Text(
            'Use a "Read" token only. It stays on this phone and is sent only to the Hugging Face voice servers, '
            'so they count your uses on your account. You can delete it any time here or on Hugging Face. '
            'Need many more? Hugging Face PRO (about \$9 a month) gives about 8 times more, and extra time can be bought.',
            style: small?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}


/// Connects the app to the user's own PC voice server (pc-server/): IndicF5 on
/// their computer, so voices and cloned voices have no daily limit.
class _PcServerCard extends StatefulWidget {
  const _PcServerCard();

  @override
  State<_PcServerCard> createState() => _PcServerCardState();
}

class _PcServerCardState extends State<_PcServerCard> {
  final _url = TextEditingController();
  bool _checking = false;
  PcServerInfo? _info;
  String? _problem;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _problem = null;
    });
    try {
      final info = await AppScope.read(context).setPcUrl(_url.text);
      if (!mounted) return;
      setState(() => _info = info);
      _url.clear();
      showMessage(
        context,
        info.modelReady
            ? 'Connected to your PC · unlimited voices'
            : 'Connected. The PC is still getting the voice model ready – try again in a few minutes.',
      );
    } on FreeEngineException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _check(String url) async {
    setState(() {
      _checking = true;
      _problem = null;
    });
    try {
      final info = await AppScope.read(context).freeEngine.checkPc(url);
      if (mounted) setState(() => _info = info);
    } on FreeEngineException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final url = app.pcUrl;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(height: 1.5);
    final info = _info;
    String status;
    if (url == null) {
      status = 'Not set up. Run the voice AI on your Windows PC and the app makes voices and cloned voices '
          'with no daily limit, free, while the phone is on the same Wi-Fi.';
    } else if (_problem != null) {
      status = _problem!;
    } else if (info == null) {
      status = 'Saved: $url\nUsed whenever the PC answers; otherwise the free online server is used.';
    } else if (info.error != null) {
      status = 'The PC answered, but: ${info.error}';
    } else if (!info.modelReady) {
      status = 'Connected. The PC is still getting the voice model ready…';
    } else {
      status = 'Connected · unlimited · ${info.device}';
    }
    final good = url != null && _problem == null && (info == null || (info.modelReady && info.error == null));
    return SectionCard(
      title: 'My PC voice server · unlimited',
      icon: Icons.computer_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('pc-status'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (good ? AppColors.success : AppColors.warning).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(status, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 12),
          if (url == null) ...[
            Text(
              '1. On the PC, open this chat in the Claude app and download "Telugu-Voice-PC-Server.zip".\n'
              '2. Extract it and double-click "Telugu-Voice-PC-Server.bat". The first time it installs by itself (10–40 min).\n'
              '3. Type the address it shows, like 192.168.1.23:7860/k/482913.',
              style: small,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('pc-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'PC address', hintText: '192.168.1.23:7860/k/482913'),
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('pc-connect'),
              onPressed: _checking ? null : _connect,
              icon: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_rounded),
              label: Text(_checking ? 'Connecting…' : 'Connect'),
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('pc-check'),
                  onPressed: _checking ? null : () => _check(url),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_checking ? 'Checking…' : 'Check now'),
                ),
                OutlinedButton.icon(
                  key: const Key('pc-remove'),
                  onPressed: () => setState(() {
                    _info = null;
                    _problem = null;
                    app.clearPcUrl();
                  }),
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Remove'),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            'When the PC is off or you are away from its Wi-Fi, the app uses the free online server instead '
            '(with its daily limit). Conversion between male and female voices still uses the online server.',
            style: small?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

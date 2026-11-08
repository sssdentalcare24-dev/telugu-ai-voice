import 'package:flutter/material.dart';

import '../../core/api/api_models.dart';
import '../../core/free/local_audio_store.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../widgets/audio_tile.dart';
import '../../widgets/common.dart';
import '../../widgets/local_audio_tile.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final List<AudioItem> _items = [];
  String? _cursor;
  String? _kind; // null = all
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (AppScope.read(context).connection != ServerConnection.online) return;
    final id = ++_requestId; // newer requests (e.g. a filter change) win
    final app = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
      }
    });
    try {
      final page = await app.api.history(before: reset ? null : _cursor, kind: _kind);
      if (!mounted || id != _requestId) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
      });
    } on ApiException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e.isAuth && !(app.health?.devAuth ?? false)
            ? 'Sign-in required. Firebase sign-in is added in Stage 3; for local testing run the server with AUTH_MODE=dev.'
            : e.message;
      });
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _delete(AudioItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete audio? · తొలగించాలా?'),
        content: Text('"${item.title}" will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = AppScope.read(context);
    try {
      await app.api.deleteAudio(item.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((i) => i.id == item.id));
      showMessage(context, 'Deleted · తొలగించబడింది');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _deleteLocal(LocalAudio item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete audio? · తొలగించాలా?'),
        content: Text('"${item.title}" will be deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = AppScope.read(context);
    if (app.playback.isPlaying(item.id)) await app.playback.stop();
    await app.localAudio.delete(item);
    if (mounted) showMessage(context, 'Deleted · తొలగించబడింది');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    const filters = [
      (null, 'All · అన్నీ'),
      ('tts', 'Text to voice'),
      ('original', 'Originals'),
      ('converted', 'Converted'),
    ];

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          ResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ScreenHeading(
                  telugu: 'ఆడియో చరిత్ర',
                  english: 'Voices and conversions you made',
                ),

                // ---- Saved on this phone (free engines) ---------------------------------
                const _SectionLabel(icon: Icons.phone_android_rounded, text: 'ఈ ఫోన్‌లో · On this phone'),
                ListenableBuilder(
                  listenable: app.localAudio,
                  builder: (context, _) {
                    final items = app.localAudio.items;
                    if (items.isEmpty) {
                      return const _Notice(
                        icon: Icons.library_music_outlined,
                        text: 'Nothing saved yet. Natural voices and conversions you make will appear here.',
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items) ...[
                          LocalAudioTile(item: item, showDate: true, onDelete: () => _deleteLocal(item)),
                          const SizedBox(height: 10),
                        ],
                        if (!app.localAudio.persistent)
                          Text(
                            'In the browser, audio is kept only until you close the page. Use Share to keep a copy.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),

                // ---- Stored on the app server (when one is connected) -----------------
                if (app.connection != ServerConnection.online)
                  Text(
                    'Audio stored on an app server appears here when one is connected (Settings).',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  )
                else ...[
                _SectionLabel(
                  icon: Icons.dns_rounded,
                  text: 'సర్వర్ · On the server',
                  trailing: IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : () => _load(reset: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.$2),
                            selected: _kind == f.$1,
                            onSelected: (_) {
                              setState(() => _kind = f.$1);
                              _load(reset: true);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  _Notice(icon: Icons.error_outline_rounded, text: _error!)
                else if (_items.isEmpty && !_loading)
                  const _Notice(
                    icon: Icons.library_music_outlined,
                    text: 'No audio on the server yet.',
                  ),
                for (final item in _items) ...[
                  _HistoryCard(item: item, onDelete: () => _delete(item)),
                  const SizedBox(height: 10),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_cursor != null)
                  OutlinedButton(onPressed: () => _load(), child: const Text('Load more')),
                const SizedBox(height: 8),
                Text(
                  'Audio files are private to your account and are opened through short-lived secure links.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.onDelete});

  final AudioItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.1),
              child: Icon(kindIcon(item.kind), color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${kindLabel(item.kind)} · ${formatDateTime(item.createdAt)}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  Text(
                    '${formatDuration(item.durationSeconds)} · ${item.format.toUpperCase()} · ${formatBytes(item.sizeBytes)}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Play in browser',
              onPressed: () => openAudio(context, item),
              icon: Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 30),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'download') openAudio(context, item, download: true);
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'download', child: ListTile(leading: Icon(Icons.download_rounded), title: Text('Download'))),
                PopupMenuItem(
                  enabled: false,
                  value: 'share',
                  child: ListTile(leading: Icon(Icons.share_rounded), title: Text('Share'), trailing: StageTag(7)),
                ),
                PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Delete'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
        ],
      ),
    );
  }
}

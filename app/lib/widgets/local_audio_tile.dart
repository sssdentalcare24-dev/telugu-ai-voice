import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/free/local_audio_store.dart';
import '../core/state/app_scope.dart';
import 'audio_tile.dart' show formatDateTime;
import 'common.dart';

/// Opens the Android share sheet (WhatsApp, Drive, Files…) for [item].
Future<void> shareLocalAudio(BuildContext context, LocalAudio item) async {
  final app = AppScope.read(context);
  try {
    final XFile file;
    final mime = item.format == 'mp3' ? 'audio/mpeg' : 'audio/wav';
    final name = '${item.id}.${item.format}';
    if (!kIsWeb && item.path != null) {
      file = XFile(item.path!, mimeType: mime, name: name);
    } else {
      file = XFile.fromData(await app.localAudio.bytesOf(item), mimeType: mime, name: name);
    }
    await Share.shareXFiles([file], text: item.title);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Could not open the share menu.', error: true);
  }
}

/// A clip with an in-app Play/Stop button, Share and (optionally) Delete.
class LocalAudioTile extends StatelessWidget {
  const LocalAudioTile({super.key, required this.item, this.label, this.onDelete, this.showShare = true, this.showDate = false});

  final LocalAudio item;
  final String? label;
  final VoidCallback? onDelete;
  final bool showShare;
  final bool showDate;

  Future<void> _toggle(BuildContext context) async {
    final app = AppScope.read(context);
    try {
      await app.playback.toggle(item, () => app.localAudio.bytesOf(item));
    } catch (_) {
      if (context.mounted) showMessage(context, 'This audio could not be played.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app.playback,
      builder: (context, _) {
        final playing = app.playback.isPlaying(item.id);
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: playing ? 0.10 : 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.primary.withValues(alpha: playing ? 0.4 : 0.15)),
          ),
          child: Row(
            children: [
              IconButton(
                key: Key('play-${item.id}'),
                tooltip: playing ? 'Stop' : 'Play',
                onPressed: () => _toggle(context),
                icon: Icon(playing ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded),
                color: scheme.primary,
                iconSize: 40,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null)
                      Text(label!, style: TextStyle(fontSize: 12, color: scheme.outline, fontWeight: FontWeight.w600)),
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (item.detail != null)
                      Text(item.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.outline)),
                    Text(
                      [
                        if (showDate) formatDateTime(item.createdAt),
                        formatDuration(item.seconds),
                        formatBytes(item.sizeBytes),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              if (showShare)
                IconButton(
                  tooltip: 'Share or save',
                  onPressed: () => shareLocalAudio(context, item),
                  icon: const Icon(Icons.share_rounded),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        );
      },
    );
  }
}

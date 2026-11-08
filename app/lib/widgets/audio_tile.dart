import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/api_models.dart';
import '../core/state/app_scope.dart';
import 'common.dart';

/// Opens (plays in the browser) or downloads an audio item through a fresh
/// signed URL. The in-app player arrives with Stage 3.
Future<void> openAudio(BuildContext context, AudioItem item, {bool download = false}) async {
  final app = AppScope.read(context);
  try {
    final fresh = await app.api.audio(item.id); // refresh the short-lived signed link
    final uri = app.api.resolve(fresh.downloadPath, download: download);
    final ok = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );
    if (!ok && context.mounted) showMessage(context, 'Could not open the audio link.', error: true);
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  }
}

IconData kindIcon(String kind) => switch (kind) {
      'tts' => Icons.record_voice_over_rounded,
      'converted' => Icons.swap_horiz_rounded,
      'clone' => Icons.record_voice_over_rounded,
      _ => Icons.mic_rounded,
    };

String kindLabel(String kind) => switch (kind) {
      'tts' => 'Text to voice',
      'converted' => 'Converted',
      'clone' => 'Personal voice',
      _ => 'Original',
    };

String formatDateTime(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, $h12:$mm $ampm';
}

/// Compact card for one audio item with open/download actions.
class AudioSummaryTile extends StatelessWidget {
  const AudioSummaryTile({super.key, required this.item, this.label});

  final AudioItem item;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primary,
            child: Icon(kindIcon(item.kind), color: scheme.onPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(label!, style: TextStyle(fontSize: 12, color: scheme.outline, fontWeight: FontWeight.w600)),
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
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
            icon: const Icon(Icons.play_circle_fill_rounded),
            color: scheme.primary,
            iconSize: 32,
          ),
          IconButton(
            tooltip: 'Download',
            onPressed: () => openAudio(context, item, download: true),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'local_audio_store.dart';

/// Plays one [LocalAudio] at a time inside the app.
class AudioPlayback extends ChangeNotifier {
  AudioPlayer? _player; // created on first use, so tests never touch the plugin
  StreamSubscription<void>? _completeSub;
  String? _currentId;
  bool _playing = false;

  bool isPlaying(String id) => _playing && _currentId == id;

  /// Starts [item], or stops it if it is already playing.
  Future<void> toggle(LocalAudio item, Future<Uint8List> Function() loadBytes) async {
    if (isPlaying(item.id)) {
      await stop();
      return;
    }
    final player = _player ??= _create();
    await player.stop();
    _currentId = item.id;
    _playing = true;
    notifyListeners();
    try {
      if (!kIsWeb && item.path != null) {
        await player.play(DeviceFileSource(item.path!));
      } else if (item.bytes == null && item.path == null && item.url != null) {
        await player.play(UrlSource(item.url!));
      } else {
        await player.play(BytesSource(await loadBytes()));
      }
    } catch (_) {
      _playing = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    _playing = false;
    notifyListeners();
    await _player?.stop();
  }

  AudioPlayer _create() {
    final player = AudioPlayer();
    _completeSub = player.onPlayerComplete.listen((_) {
      _playing = false;
      notifyListeners();
    });
    return player;
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}

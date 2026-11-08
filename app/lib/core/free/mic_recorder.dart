import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records the microphone to a 16 kHz mono WAV.
class MicRecorder {
  AudioRecorder? _recorder; // created on first use
  bool _recording = false;

  bool get recording => _recording;

  /// Asks Android for microphone permission (the system dialog) and starts
  /// recording. Returns false if the user did not allow the microphone.
  Future<bool> start() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;
    var path = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    }
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    _recording = true;
    return true;
  }

  /// Stops and returns the WAV bytes (null if nothing was recorded).
  Future<Uint8List?> stop() async {
    final recorder = _recorder;
    if (recorder == null || !_recording) return null;
    _recording = false;
    final result = await recorder.stop();
    if (result == null || result.isEmpty) return null;
    if (kIsWeb) {
      // On the web the recorder returns a blob: URL.
      final response = await http.get(Uri.parse(result));
      return response.bodyBytes;
    }
    final file = File(result);
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {
      // Temporary file; the system cleans it up anyway.
    }
    return bytes;
  }

  Future<void> cancel() async {
    if (_recording) {
      _recording = false;
      await _recorder?.cancel();
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder?.dispose();
    _recorder = null;
  }
}

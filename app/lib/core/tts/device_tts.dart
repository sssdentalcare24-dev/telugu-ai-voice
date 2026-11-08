import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum PhoneVoiceState { checking, ready, missing, unsupported }

/// The phone's own text-to-speech engine (Android: Google Speech Services).
///
/// Free and offline once Telugu voice data is installed on the phone. It only
/// plays aloud; it cannot be saved as a file. The natural server voices
/// (IndicF5 / Indic Parler-TTS) are separate and arrive in Stage 3.
class PhoneVoice extends ChangeNotifier {
  PhoneVoice({FlutterTts? engine}) : _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  PhoneVoiceState state = PhoneVoiceState.checking;
  bool speaking = false;
  List<Map<String, String>> voices = const [];
  String? selectedVoice;
  bool _started = false;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      _tts.setStartHandler(() {
        speaking = true;
        _notify();
      });
      _tts.setCompletionHandler(() {
        speaking = false;
        _notify();
      });
      _tts.setCancelHandler(() {
        speaking = false;
        _notify();
      });
      _tts.setErrorHandler((dynamic _) {
        speaking = false;
        _notify();
      });
      voices = await _teluguVoices();
      bool available = voices.isNotEmpty;
      if (!available) {
        final result = await _tts.isLanguageAvailable('te-IN');
        available = result == true;
      }
      state = available ? PhoneVoiceState.ready : PhoneVoiceState.missing;
      if (voices.isNotEmpty) selectedVoice = voices.first['name'];
    } catch (_) {
      // The web build has no voice list; the browser picks a Telugu voice if it has one.
      state = kIsWeb ? PhoneVoiceState.ready : PhoneVoiceState.unsupported;
    }
    _notify();
  }

  Future<List<Map<String, String>>> _teluguVoices() async {
    try {
      final dynamic raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final out = <Map<String, String>>[];
      for (final dynamic v in raw) {
        if (v is Map) {
          final name = '${v['name'] ?? ''}';
          final locale = '${v['locale'] ?? ''}';
          if (name.isNotEmpty && locale.toLowerCase().replaceAll('_', '-').startsWith('te')) {
            out.add({'name': name, 'locale': locale});
          }
        }
      }
      out.sort((a, b) => a['name']!.compareTo(b['name']!));
      return out;
    } catch (_) {
      return const [];
    }
  }

  void selectVoice(String? name) {
    selectedVoice = name;
    _notify();
  }

  /// [speed] is a multiplier (1.0 = normal); [semitones] shifts pitch.
  Future<void> speak(String text, {double speed = 1.0, double semitones = 0}) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage('te-IN');
      for (final v in voices) {
        if (v['name'] == selectedVoice) {
          await _tts.setVoice(v);
          break;
        }
      }
      // flutter_tts doubles the rate on Android, so 0.5 means normal speed there.
      final double rate = kIsWeb ? speed : speed * 0.5;
      await _tts.setSpeechRate(rate.clamp(0.1, 2.0).toDouble());
      final double pitch = math.pow(2, semitones / 12).toDouble();
      await _tts.setPitch(pitch.clamp(0.5, 2.0).toDouble());
      speaking = true;
      _notify();
      await _tts.speak(text);
    } catch (_) {
      speaking = false;
      state = PhoneVoiceState.unsupported;
      _notify();
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _tts.stop().catchError((Object _) => null);
    super.dispose();
  }
}

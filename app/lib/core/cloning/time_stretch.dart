import 'dart:math' as math;
import 'dart:typed_data';

import '../free/wav.dart';

/// Changes the speed of speech in a 16-bit PCM WAV **without changing its
/// pitch** (WSOLA: waveform-similarity overlap-add). Used for providers that
/// have no speed setting of their own, such as the free IndicF5 engine.
///
/// [speed] > 1 is faster (shorter), < 1 slower. Returns [wav] unchanged for
/// speed 1, or for formats other than 16-bit PCM.
Uint8List timeStretchWav(Uint8List wav, double speed) {
  if ((speed - 1).abs() < 0.01) return wav;
  final info = parseWav(wav);
  if (info == null || info.audioFormat != 1 || info.bitsPerSample != 16 || info.channels < 1) return wav;
  final channels = info.channels;
  final view = ByteData.sublistView(wav, info.dataOffset, info.dataOffset + info.dataLength);
  final frames = info.dataLength ~/ (2 * channels);
  if (frames < info.sampleRate ~/ 10) return wav;

  // Mono analysis signal (average of channels) drives the alignment search.
  final mono = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += view.getInt16((i * channels + c) * 2, Endian.little);
    }
    mono[i] = sum / channels;
  }

  final sr = info.sampleRate;
  final n = (sr * 0.030).round() & ~1; // 30 ms window
  final hs = n ~/ 2; // output hop (50 % overlap)
  final ha = hs * speed; // input hop
  final delta = (sr * 0.010).round(); // ±10 ms search
  final window = Float32List(n);
  for (var i = 0; i < n; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }

  final outFrames = (frames / speed).ceil() + n;
  final out = List<Float32List>.generate(channels, (_) => Float32List(outFrames));
  final norm = Float32List(outFrames);

  var prev = 0; // input position of the previous chosen frame
  for (var k = 0;; k++) {
    final outPos = k * hs;
    final target = (k * ha).round();
    if (target + n >= frames || outPos + n >= outFrames) break;
    var pos = target;
    if (k > 0) {
      // Pick the frame near [target] that best continues the previous one.
      final natural = prev + hs;
      var best = -double.infinity;
      final lo = math.max(0, target - delta);
      final hi = math.min(frames - n - 1, target + delta);
      for (var cand = lo; cand <= hi; cand += 2) {
        var corr = 0.0;
        for (var i = 0; i < n; i += 4) {
          final a = natural + i < frames ? mono[natural + i] : 0.0;
          corr += a * mono[cand + i];
        }
        if (corr > best) {
          best = corr;
          pos = cand;
        }
      }
    }
    for (var c = 0; c < channels; c++) {
      final o = out[c];
      for (var i = 0; i < n; i++) {
        o[outPos + i] += window[i] * view.getInt16(((pos + i) * channels + c) * 2, Endian.little);
      }
    }
    for (var i = 0; i < n; i++) {
      norm[outPos + i] += window[i];
    }
    prev = pos;
  }

  var length = outFrames;
  while (length > 0 && norm[length - 1] == 0) {
    length--;
  }
  final data = ByteData(length * channels * 2);
  for (var i = 0; i < length; i++) {
    final w = norm[i] > 1e-3 ? norm[i] : 1.0;
    for (var c = 0; c < channels; c++) {
      final v = (out[c][i] / w).round().clamp(-32768, 32767);
      data.setInt16((i * channels + c) * 2, v, Endian.little);
    }
  }
  return buildWav(info, data.buffer.asUint8List());
}

/// Arguments for running [timeStretchWav] in a background isolate.
Uint8List timeStretchJob((Uint8List, double) job) => timeStretchWav(job.$1, job.$2);

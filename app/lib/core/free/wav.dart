import 'dart:typed_data';

/// Format and location of the samples in a RIFF/WAVE file.
class WavInfo {
  const WavInfo({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int audioFormat; // 1 = PCM, 3 = float
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  int get bytesPerSecond => sampleRate * channels * (bitsPerSample ~/ 8);
  double get seconds => bytesPerSecond == 0 ? 0 : dataLength / bytesPerSecond;

  bool sameFormat(WavInfo other) =>
      audioFormat == other.audioFormat &&
      channels == other.channels &&
      sampleRate == other.sampleRate &&
      bitsPerSample == other.bitsPerSample;
}

String _tag(Uint8List b, int o) => String.fromCharCodes(b.sublist(o, o + 4));

/// Parses a WAV header; returns null when [bytes] is not a WAV file.
WavInfo? parseWav(Uint8List bytes) {
  if (bytes.length < 12 || _tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') return null;
  final view = ByteData.sublistView(bytes);
  int? format, channels, rate, bits;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _tag(bytes, offset);
    var size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = view.getUint16(body, Endian.little);
      channels = view.getUint16(body + 2, Endian.little);
      rate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (format == null) return null;
      // Streams written while recording may carry a 0 or oversized length.
      if (size == 0 || body + size > bytes.length) size = bytes.length - body;
      return WavInfo(
        audioFormat: format,
        channels: channels!,
        sampleRate: rate!,
        bitsPerSample: bits!,
        dataOffset: body,
        dataLength: size,
      );
    }
    offset = body + size + (size & 1);
  }
  return null;
}

/// Length in seconds of a WAV file, or null for other formats.
double? wavSeconds(Uint8List bytes) => parseWav(bytes)?.seconds;

/// Builds a canonical 44-byte-header WAV around raw sample [data].
Uint8List buildWav(WavInfo format, Uint8List data) {
  final header = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  final blockAlign = format.channels * (format.bitsPerSample ~/ 8);
  tag(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, format.audioFormat, Endian.little);
  header.setUint16(22, format.channels, Endian.little);
  header.setUint32(24, format.sampleRate, Endian.little);
  header.setUint32(28, format.sampleRate * blockAlign, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, format.bitsPerSample, Endian.little);
  tag(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(data))
      .toBytes();
}

/// Joins WAV clips of the same format with a short silence between them.
/// Throws [ArgumentError] if a clip is not WAV or the formats differ.
Uint8List concatWavs(List<Uint8List> clips, {double gapSeconds = 0.3}) {
  if (clips.isEmpty) throw ArgumentError('No audio clips to join.');
  if (clips.length == 1) return clips.single;
  final infos = <WavInfo>[];
  for (final clip in clips) {
    final info = parseWav(clip);
    if (info == null) throw ArgumentError('Audio clip is not a WAV file.');
    if (infos.isNotEmpty && !infos.first.sameFormat(info)) throw ArgumentError('Audio clips have different formats.');
    infos.add(info);
  }
  final first = infos.first;
  final blockAlign = first.channels * (first.bitsPerSample ~/ 8);
  final gapBytes = (first.sampleRate * gapSeconds).round() * blockAlign;
  // 8-bit PCM is unsigned: its silence is 128, not 0.
  final silence = Uint8List(gapBytes);
  if (first.audioFormat == 1 && first.bitsPerSample == 8) silence.fillRange(0, gapBytes, 128);
  final data = BytesBuilder(copy: false);
  for (var i = 0; i < clips.length; i++) {
    if (i > 0) data.add(silence);
    data.add(Uint8List.sublistView(clips[i], infos[i].dataOffset, infos[i].dataOffset + infos[i].dataLength));
  }
  return buildWav(first, data.toBytes());
}

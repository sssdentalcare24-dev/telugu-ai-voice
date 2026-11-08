import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gradio_space.dart';
import 'wav.dart';

/// Voices offered by the free natural engine. Each one is a sample speaker
/// published by AI4Bharat with IndicF5; the engine speaks Telugu text in that
/// speaker's voice.
enum FreeVoice {
  female1('female', 4, 'స్త్రీ స్వరం 1', 'Female voice 1', 'Warm, clear'),
  female2('female', 1, 'స్త్రీ స్వరం 2', 'Female voice 2', 'Bright, higher'),
  male1('male', 3, 'పురుష స్వరం', 'Male voice', 'Calm, deep');

  const FreeVoice(this.gender, this.example, this.nameTe, this.nameEn, this.character);

  final String gender;

  /// Index of the speaker sample in the IndicF5 Space's example list.
  final int example;
  final String nameTe;
  final String nameEn;
  final String character;

  String get label => '$nameTe · $nameEn';

  static List<FreeVoice> forGender(String gender) => values.where((v) => v.gender == gender).toList();
}

/// Progress callback: [step] of [total] steps finished.
typedef FreeProgress = void Function(int step, int total, String message);

/// Free, no-key AI voice engines running on public Hugging Face Spaces:
///
/// * Text to speech: AI4Bharat **IndicF5** (natural Telugu, female and male).
/// * Voice conversion: **Seed-VC** (any voice -> the chosen female/male voice).
///
/// No API keys are involved, so nothing secret is shipped in the app. The
/// user's text or audio is sent to Hugging Face for processing, which the app
/// says clearly before every use.
class FreeVoiceEngine {
  FreeVoiceEngine({http.Client? client, String? ttsUrl, String? conversionUrl})
      : tts = GradioSpace(
          ttsUrl ?? defaultTtsUrl,
          name: 'The free Telugu voice server (AI4Bharat IndicF5)',
          client: client,
        ),
        conversion = GradioSpace(
          conversionUrl ?? defaultConversionUrl,
          name: 'The free voice-conversion server (Seed-VC)',
          client: client,
        );

  static const String defaultTtsUrl = 'https://ai4bharat-indicf5.hf.space';
  static const String defaultConversionUrl = 'https://plachta-seed-vc.hf.space';

  /// Longest text accepted in one go, and the size of each piece sent.
  /// [maxChars] counts letters as the screen shows them; one Telugu letter can
  /// be several code units, so the engine itself limits the number of pieces.
  ///
  /// Both Spaces run on Hugging Face ZeroGPU: each request must fit in about
  /// 60 seconds of GPU time and draws on a small free daily allowance per
  /// internet connection. So text goes in few, fairly large pieces (IndicF5
  /// splits long text internally), and typical messages need just one request.
  static const int maxChars = 1000;
  static const int chunkChars = 600;
  static const int maxChunks = 6;

  /// Longest recording accepted for conversion, and the largest file.
  static const int maxConvertSeconds = 60;
  static const int maxConvertBytes = 10 * 1024 * 1024;

  final GradioSpace tts;
  final GradioSpace conversion;

  /// Speaker samples, downloaded once and reused for conversions.
  final Map<int, Uint8List> _sampleAudio = {};

  /// Speaks Telugu [text] in [voice] and returns a WAV file.
  Future<Uint8List> synthesize(String text, FreeVoice voice, {FreeProgress? onProgress}) async {
    final chunks = splitForSpeech(text, maxChunk: chunkChars);
    if (chunks.isEmpty) throw FreeEngineException('Type some Telugu text first.');
    if (chunks.length > maxChunks) {
      throw FreeEngineException('The natural voice accepts up to about $maxChars letters at a time.');
    }
    final total = chunks.length + 1;
    onProgress?.call(0, total, 'Connecting to the free voice server…');
    final sample = await _speakerSample(voice.example);
    final clips = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      onProgress?.call(i + 1, total, chunks.length == 1 ? 'Making the voice…' : 'Making part ${i + 1} of ${chunks.length}…');
      final out = await tts.call('synthesize_speech', [chunks[i], GradioSpace.fileData(sample.path), sample.text]);
      final path = out.isEmpty ? null : GradioSpace.pathOf(out.first);
      if (path == null) throw FreeEngineException('${tts.name} did not return any audio. Please try again.');
      clips.add(await tts.download(path));
    }
    onProgress?.call(total, total, 'Done');
    try {
      return concatWavs(clips);
    } on ArgumentError {
      throw FreeEngineException('${tts.name} returned audio in an unexpected format.');
    }
  }

  /// Converts the speech in [source] (any common audio format) into [target]'s
  /// voice, keeping the words and timing. Returns a WAV file.
  Future<Uint8List> convert(Uint8List source, String filename, FreeVoice target, {FreeProgress? onProgress}) async {
    if (source.isEmpty) throw FreeEngineException('The recording is empty.');
    if (source.length > maxConvertBytes) {
      throw FreeEngineException('Please use a recording smaller than ${maxConvertBytes ~/ (1024 * 1024)} MB.');
    }
    final seconds = wavSeconds(source);
    if (seconds != null && seconds > maxConvertSeconds + 1) {
      throw FreeEngineException('Please use a recording of up to $maxConvertSeconds seconds.');
    }
    const total = 4;
    onProgress?.call(0, total, 'Getting the ${target.gender} voice…');
    final targetAudio = await _sampleBytes(target.example);
    onProgress?.call(1, total, 'Uploading your recording…');
    final sourcePath = await conversion.upload(source, _safeName(filename));
    final targetPath = await conversion.upload(targetAudio, 'target_${target.name}.wav');
    onProgress?.call(2, total, 'Converting the voice (about 10–60 seconds)…');
    final out = await conversion.call('predict_1', [
      GradioSpace.fileData(sourcePath),
      GradioSpace.fileData(targetPath),
      25, // diffusion steps: good quality at a reasonable speed
      1.0, // keep the original length
      0.7, // guidance
      false, // speech model (not the singing model)
      true, // auto pitch adjust
      0, // no extra pitch shift
    ]);
    // Outputs are [streaming preview, full result]; take the last real file.
    String? path;
    for (final item in out) {
      final p = GradioSpace.pathOf(item);
      if (p != null && !p.endsWith('.m3u8')) path = p;
    }
    if (path == null) throw FreeEngineException('${conversion.name} did not return any audio. Please try again.');
    onProgress?.call(3, total, 'Downloading the result…');
    final result = await conversion.download(path);
    onProgress?.call(total, total, 'Done');
    return result;
  }

  /// Speaks [text] in the voice of [sample] (a WAV/MP3 recording of one
  /// person saying exactly [transcript]) - zero-shot voice cloning with IndicF5.
  /// The sample is uploaded with each request; nothing is stored at the server.
  Future<Uint8List> synthesizeWithSample(
    String text,
    Uint8List sample,
    String transcript, {
    String filename = 'voice_sample.wav',
    FreeProgress? onProgress,
  }) async {
    final chunks = splitForSpeech(text, maxChunk: chunkChars);
    if (chunks.isEmpty) throw FreeEngineException('Type some text first.');
    if (chunks.length > maxChunks) {
      throw FreeEngineException('The free voice accepts up to about $maxChars letters at a time.');
    }
    if (transcript.trim().isEmpty) throw FreeEngineException('The voice sample has no transcript.');
    final total = chunks.length + 1;
    onProgress?.call(0, total, 'Sending your voice sample…');
    final path = await tts.upload(sample, filename);
    final clips = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      onProgress?.call(i + 1, total, chunks.length == 1 ? 'Speaking in your voice…' : 'Speaking part ${i + 1} of ${chunks.length}…');
      final out = await tts.call('synthesize_speech', [chunks[i], GradioSpace.fileData(path), transcript.trim()]);
      final result = out.isEmpty ? null : GradioSpace.pathOf(out.first);
      if (result == null) {
        final message = out.isEmpty ? null : GradioSpace.valueOf(out.first);
        throw FreeEngineException(
          message is String && message.startsWith('Error')
              ? '${tts.name}: $message'
              : '${tts.name} did not return any audio. Please try again.',
        );
      }
      clips.add(await tts.download(result));
    }
    onProgress?.call(total, total, 'Done');
    try {
      return concatWavs(clips);
    } on ArgumentError {
      throw FreeEngineException('${tts.name} returned audio in an unexpected format.');
    }
  }

  Future<({String path, String text})> _speakerSample(int example) async {
    final out = await tts.call('load_example', [example]);
    // Outputs: [text to speak, reference audio, text spoken in the reference]
    final path = out.length > 1 ? GradioSpace.pathOf(out[1]) : null;
    final text = out.length > 2 ? GradioSpace.valueOf(out[2]) : null;
    if (path == null || text is! String) {
      throw FreeEngineException('${tts.name} has changed its voice list. Please update the app.');
    }
    return (path: path, text: text);
  }

  Future<Uint8List> _sampleBytes(int example) async {
    final cached = _sampleAudio[example];
    if (cached != null) return cached;
    final sample = await _speakerSample(example);
    final bytes = await tts.download(sample.path);
    _sampleAudio[example] = bytes;
    return bytes;
  }

  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'recording.wav' : cleaned;
  }
}

/// Splits Telugu text into pieces of at most [maxChunk] characters, breaking at
/// sentence ends first, then at commas or spaces. Never splits inside a word.
List<String> splitForSpeech(String text, {int maxChunk = 300}) {
  final clean = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  if (clean.isEmpty) return const [];
  final sentences = <String>[];
  final buffer = StringBuffer();
  for (final rune in clean.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(ch);
    if ('.!?।॥\n'.contains(ch)) {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) sentences.add(s);
      buffer.clear();
    }
  }
  final rest = buffer.toString().trim();
  if (rest.isNotEmpty) sentences.add(rest);

  final pieces = <String>[];
  for (final sentence in sentences) {
    if (sentence.length <= maxChunk) {
      pieces.add(sentence);
      continue;
    }
    var current = '';
    for (final word in sentence.split(' ')) {
      if (word.length > maxChunk) {
        if (current.isNotEmpty) pieces.add(current);
        current = '';
        for (var i = 0; i < word.length; i += maxChunk) {
          pieces.add(word.substring(i, i + maxChunk > word.length ? word.length : i + maxChunk));
        }
        continue;
      }
      final next = current.isEmpty ? word : '$current $word';
      if (next.length > maxChunk) {
        pieces.add(current);
        current = word;
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) pieces.add(current);
  }

  // Merge short neighbours so each request carries as much text as allowed.
  final merged = <String>[];
  for (final piece in pieces) {
    if (merged.isNotEmpty && merged.last.length + 1 + piece.length <= maxChunk) {
      merged[merged.length - 1] = '${merged.last} $piece';
    } else {
      merged.add(piece);
    }
  }
  return merged;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gradio_space.dart';
import 'wav.dart';

/// The Hugging Face account behind a saved access token.
class HfAccount {
  const HfAccount({required this.name, required this.isPro});

  final String name;
  final bool isPro;

  /// Rough number of voices per day: each request reserves about 60 seconds of
  /// shared GPU time (free account about 5 min/day, PRO about 40 min/day).
  int get dailyRequests => isPro ? 40 : 5;
}

/// What the PC voice server reports about itself.
class PcServerInfo {
  const PcServerInfo({required this.device, required this.modelReady, required this.loading, this.error});

  final String device;
  final bool modelReady;
  final bool loading;
  final String? error;

  bool get onGpu => device.startsWith('GPU');
}

/// Turns what the user typed into a PC server address, e.g.
/// "192.168.1.23:7860/k/482913" -> "http://192.168.1.23:7860/k/482913".
String normalizePcUrl(String raw) {
  var v = raw.trim().replaceAll(' ', '');
  while (v.endsWith('/')) {
    v = v.substring(0, v.length - 1);
  }
  if (v.isEmpty) return v;
  if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'http://$v';
  return v;
}

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
      : _http = client,
        tts = GradioSpace(
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
  static const int chunkChars = 1200; // one request (one daily-allowance slot) for most texts
  static const int maxChunks = 6;

  /// Longest recording accepted for conversion, and the largest file.
  static const int maxConvertSeconds = 60;
  static const int maxConvertBytes = 10 * 1024 * 1024;

  final GradioSpace tts;
  final GradioSpace conversion;
  final http.Client? _http;

  // ---- The user's own PC (unlimited) ----------------------------------------------
  GradioSpace? _pc;
  DateTime? _pcCheckedAt;
  bool _pcOk = false;

  /// True when the last voice was made on the user's PC.
  bool lastUsedPc = false;

  /// Address of the user's PC voice server (see pc-server/), or null.
  String? get pcUrl => _pc?.baseUrl;
  set pcUrl(String? url) {
    final u = url == null ? '' : normalizePcUrl(url);
    _pc = u.isEmpty
        ? null
        : GradioSpace(u, name: 'Your PC voice server', client: _http, timeout: const Duration(minutes: 15));
    _pcCheckedAt = null;
  }

  /// Asks the PC voice server how it is doing. Throws a readable error when it
  /// cannot be reached or the address/code is wrong.
  Future<PcServerInfo> checkPc(String url) async {
    final u = normalizePcUrl(url);
    if (!RegExp(r'^https?://[^/]+/k/\d{6}$').hasMatch(u)) {
      throw FreeEngineException('Type the full address shown in the PC window, like 192.168.1.23:7860/k/482913.');
    }
    final http.Response r;
    try {
      r = await (_http ?? http.Client()).get(Uri.parse('$u/info')).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw FreeEngineException(
        'Cannot reach your PC. Is the voice server window open on the PC, and is this phone on the same Wi-Fi?',
        unreachable: true,
      );
    }
    if (r.statusCode == 404) {
      throw FreeEngineException('The PC answered, but the code is wrong. Copy the address again from the PC window.');
    }
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['server'] != 'telugu-voice-pc') throw const FormatException();
      return PcServerInfo(
        device: j['device'] as String? ?? '',
        modelReady: j['model_ready'] == true,
        loading: j['loading'] == true,
        error: j['error'] as String?,
      );
    } catch (_) {
      throw FreeEngineException('That address is not the Telugu AI Voice PC server.');
    }
  }

  /// The server to use now: the PC when it answers and its model is ready,
  /// otherwise the free online server.
  Future<GradioSpace> _voiceServer(FreeProgress? onProgress) async {
    final pc = _pc;
    if (pc == null) return tts;
    final now = DateTime.now();
    if (_pcCheckedAt == null || now.difference(_pcCheckedAt!) > const Duration(seconds: 30)) {
      _pcOk = false;
      try {
        final r = await (_http ?? http.Client()).get(Uri.parse('${pc.baseUrl}/info')).timeout(const Duration(seconds: 4));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        _pcOk = r.statusCode == 200 && j is Map && j['server'] == 'telugu-voice-pc' && j['model_ready'] == true;
      } catch (_) {
        _pcOk = false;
      }
      _pcCheckedAt = now;
    }
    if (_pcOk) return pc;
    onProgress?.call(0, 1, 'Your PC is not available – using the free online server…');
    return tts;
  }

  /// Runs [job] on the PC when possible; if the PC stops answering midway,
  /// runs it once more on the free online server.
  Future<T> _onVoiceServer<T>(FreeProgress? onProgress, Future<T> Function(GradioSpace server) job) async {
    final server = await _voiceServer(onProgress);
    try {
      final result = await job(server);
      lastUsedPc = !identical(server, tts);
      return result;
    } on FreeEngineException catch (e) {
      if (identical(server, tts) || !e.unreachable) rethrow;
      _pcOk = false;
      _pcCheckedAt = DateTime.now();
      onProgress?.call(0, 1, 'Lost the connection to your PC – using the free online server…');
      final result = await job(tts);
      lastUsedPc = false;
      return result;
    }
  }

  /// The user's own Hugging Face token (or null), sent to both servers.
  String? get token => tts.token;
  set token(String? value) {
    tts.token = value;
    conversion.token = value;
  }

  /// Checks a token with Hugging Face and returns the account it belongs to.
  Future<HfAccount> checkToken(String token) async {
    final t = token.trim();
    if (!t.startsWith('hf_') || t.length < 20) {
      throw FreeEngineException('That does not look like a Hugging Face token. It starts with "hf_".');
    }
    final client = _http ?? http.Client();
    final http.Response response;
    try {
      response = await client
          .get(Uri.parse('https://huggingface.co/api/whoami-v2'), headers: {'Authorization': 'Bearer $t'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw FreeEngineException('Could not reach Hugging Face to check the token. Check the internet connection.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw FreeEngineException('Hugging Face did not accept this token. Copy it again from your Access Tokens page.');
    }
    if (response.statusCode != 200) {
      throw FreeEngineException('Hugging Face could not check the token right now (HTTP ${response.statusCode}).');
    }
    try {
      final j = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return HfAccount(name: (j['name'] as String?) ?? 'your account', isPro: j['isPro'] == true);
    } catch (_) {
      throw FreeEngineException('Hugging Face sent an unexpected answer. Please try again.');
    }
  }

  /// Speaker samples, downloaded once and reused for conversions.
  final Map<int, Uint8List> _sampleAudio = {};

  /// Speaks Telugu [text] in [voice] and returns a WAV file.
  Future<Uint8List> synthesize(String text, FreeVoice voice, {FreeProgress? onProgress}) async {
    final chunks = splitForSpeech(text, maxChunk: chunkChars);
    if (chunks.isEmpty) throw FreeEngineException('Type some Telugu text first.');
    if (chunks.length > maxChunks) {
      throw FreeEngineException('The natural voice accepts up to about $maxChars letters at a time.');
    }
    return _onVoiceServer(onProgress, (server) async {
      final total = chunks.length + 1;
      onProgress?.call(0, total, 'Connecting to the voice server…');
      final sample = await _speakerSample(voice.example, server);
      final clips = <Uint8List>[];
      for (var i = 0; i < chunks.length; i++) {
        onProgress?.call(i + 1, total, chunks.length == 1 ? 'Making the voice…' : 'Making part ${i + 1} of ${chunks.length}…');
        final out = await server.call('synthesize_speech', [chunks[i], GradioSpace.fileData(sample.path), sample.text]);
        final path = out.isEmpty ? null : GradioSpace.pathOf(out.first);
        if (path == null) throw FreeEngineException('${server.name} did not return any audio. Please try again.');
        clips.add(await server.download(path));
      }
      onProgress?.call(total, total, 'Done');
      try {
        return concatWavs(clips);
      } on ArgumentError {
        throw FreeEngineException('${server.name} returned audio in an unexpected format.');
      }
    });
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
  /// Uses the user's PC when it is set up and reachable (no daily limit).
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
    return _onVoiceServer(onProgress, (server) async {
      final total = chunks.length + 1;
      onProgress?.call(0, total, 'Sending your voice sample…');
      final path = await server.upload(sample, filename);
      final clips = <Uint8List>[];
      for (var i = 0; i < chunks.length; i++) {
        onProgress?.call(i + 1, total, chunks.length == 1 ? 'Speaking in your voice…' : 'Speaking part ${i + 1} of ${chunks.length}…');
        final out = await server.call('synthesize_speech', [chunks[i], GradioSpace.fileData(path), transcript.trim()]);
        final result = out.isEmpty ? null : GradioSpace.pathOf(out.first);
        if (result == null) {
          final message = out.isEmpty ? null : GradioSpace.valueOf(out.first);
          throw FreeEngineException(
            message is String && message.startsWith('Error')
                ? '${server.name}: $message'
                : '${server.name} did not return any audio. Please try again.',
          );
        }
        clips.add(await server.download(result));
      }
      onProgress?.call(total, total, 'Done');
      try {
        return concatWavs(clips);
      } on ArgumentError {
        throw FreeEngineException('${server.name} returned audio in an unexpected format.');
      }
    });
  }

  Future<({String path, String text})> _speakerSample(int example, [GradioSpace? server]) async {
    final space = server ?? tts;
    final out = await space.call('load_example', [example]);
    // Outputs: [text to speak, reference audio, text spoken in the reference]
    final path = out.length > 1 ? GradioSpace.pathOf(out[1]) : null;
    final text = out.length > 2 ? GradioSpace.valueOf(out[2]) : null;
    if (path == null || text is! String) {
      throw FreeEngineException('${space.name} has changed its voice list. Please update the app.');
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

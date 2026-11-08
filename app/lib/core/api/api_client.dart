import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_models.dart';

/// Talks to the FastAPI backend. Holds no secrets: authentication is a
/// Firebase ID token (production) or the dev user header (local testing).
class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.devUser,
    this.idTokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// Absolute, without trailing slash, e.g. http://10.0.2.2:8000
  final String baseUrl;

  /// Sent as X-Dev-User when the server runs in AUTH_MODE=dev.
  final String? devUser;

  /// Supplies a Firebase ID token once sign-in is added.
  final Future<String?> Function()? idTokenProvider;

  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _longTimeout = Duration(minutes: 3);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// Absolute URL for a relative signed download path from the API.
  Uri resolve(String relativePath, {bool download = false}) {
    final uri = Uri.parse('$baseUrl$relativePath');
    if (!download) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, 'download': 'true'});
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json; charset=utf-8';
    final token = idTokenProvider == null ? null : await idTokenProvider!();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (devUser != null && devUser!.isNotEmpty) {
      headers['X-Dev-User'] = devUser!;
    }
    return headers;
  }

  Future<http.Response> _send(Future<http.Response> Function() request, Duration timeout) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException(0, 'TIMEOUT', 'The server took too long to respond.');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'NETWORK', 'Cannot reach the server at $baseUrl (${e.message}).');
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'Cannot reach the server at $baseUrl.');
    }
  }

  dynamic _decode(http.Response r) {
    final body = utf8.decode(r.bodyBytes);
    dynamic data;
    if (body.isNotEmpty) {
      try {
        data = jsonDecode(body);
      } catch (_) {
        data = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return data;
    var code = 'HTTP_${r.statusCode}';
    var message = 'Request failed (${r.statusCode}).';
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>;
      code = (err['code'] as String?) ?? code;
      message = (err['message'] as String?) ?? message;
    }
    throw ApiException(r.statusCode, code, message);
  }

  // ---- System ------------------------------------------------------------
  Future<ServerHealth> health() async {
    final r = await _send(() async => _http.get(_uri('/api/health'), headers: await _headers()), _timeout);
    return ServerHealth.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<List<Voice>> voices() async {
    final r = await _send(() async => _http.get(_uri('/api/voices'), headers: await _headers()), _timeout);
    final data = _decode(r) as Map<String, dynamic>;
    return (data['voices'] as List).map((e) => Voice.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---- Text to speech ---------------------------------------------------------
  Future<AudioItem> generateSpeech({
    required String text,
    required String voiceId,
    double speed = 1.0,
    double pitch = 0.0,
    String? style,
  }) async {
    final body = jsonEncode({
      'text': text,
      'voice_id': voiceId,
      'speed': speed,
      'pitch': pitch,
      if (style != null) 'style': style,
    });
    final r = await _send(
      () async => _http.post(_uri('/api/tts/generate'), headers: await _headers(json: true), body: body),
      _longTimeout,
    );
    return AudioItem.fromJson(_decode(r) as Map<String, dynamic>);
  }

  // ---- Audio library -------------------------------------------------------------
  Future<AudioItem> uploadAudio(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', _uri('/api/audio/upload'))
      ..headers.addAll(await _headers())
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final r = await _send(() async => http.Response.fromStream(await _http.send(req)), _longTimeout);
    return AudioItem.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<HistoryPage> history({int limit = 50, String? before, String? kind}) async {
    final query = <String, String>{
      'limit': '$limit',
      if (before != null) 'before': before,
      if (kind != null) 'kind': kind,
    };
    final r = await _send(
      () async => _http.get(_uri('/api/audio/history', query), headers: await _headers()),
      _timeout,
    );
    return HistoryPage.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<AudioItem> audio(String id) async {
    final r = await _send(() async => _http.get(_uri('/api/audio/$id'), headers: await _headers()), _timeout);
    return AudioItem.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<void> deleteAudio(String id) async {
    final r = await _send(() async => _http.delete(_uri('/api/audio/$id'), headers: await _headers()), _timeout);
    _decode(r);
  }

  // ---- Voice conversion ------------------------------------------------------------
  /// [direction] is 'male_to_female' or 'female_to_male'.
  Future<({AudioItem original, AudioItem converted})> convertVoice({
    required String direction,
    required bool consent,
    String? sourceAudioId,
    Uint8List? bytes,
    String? filename,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/voice/convert'))
      ..headers.addAll(await _headers())
      ..fields['direction'] = direction
      ..fields['consent'] = consent ? 'true' : 'false';
    if (sourceAudioId != null) req.fields['source_audio_id'] = sourceAudioId;
    if (bytes != null) {
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename ?? 'recording.wav'));
    }
    final r = await _send(() async => http.Response.fromStream(await _http.send(req)), _longTimeout);
    final data = _decode(r) as Map<String, dynamic>;
    return (
      original: AudioItem.fromJson(data['original'] as Map<String, dynamic>),
      converted: AudioItem.fromJson(data['converted'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> createLiveSession({required String direction, required bool consent}) async {
    final r = await _send(
      () async => _http.post(
        _uri('/api/voice/live/session'),
        headers: await _headers(json: true),
        body: jsonEncode({'direction': direction, 'consent': consent}),
      ),
      _timeout,
    );
    return _decode(r) as Map<String, dynamic>;
  }

  // ---- Generic JSON helpers (used by the voice cloning service) -------------------
  Future<dynamic> getJson(String path, [Map<String, String>? query]) async {
    final r = await _send(() async => _http.get(_uri(path, query), headers: await _headers()), _timeout);
    return _decode(r);
  }

  Future<dynamic> postJson(String path, Map<String, Object?> body, {bool long = false}) async {
    final r = await _send(
      () async => _http.post(_uri(path), headers: await _headers(json: true), body: jsonEncode(body)),
      long ? _longTimeout : _timeout,
    );
    return _decode(r);
  }

  Future<dynamic> postFile(
    String path, {
    required Uint8List bytes,
    required String filename,
    Map<String, String> fields = const {},
  }) async {
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(await _headers())
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final r = await _send(() async => http.Response.fromStream(await _http.send(req)), _longTimeout);
    return _decode(r);
  }

  Future<void> delete(String path) async {
    final r = await _send(() async => _http.delete(_uri(path), headers: await _headers()), _timeout);
    _decode(r);
  }

  /// Downloads a signed audio link (relative path from the API).
  Future<Uint8List> download(String relativePath) async {
    final r = await _send(() async => _http.get(resolve(relativePath)), _longTimeout);
    if (r.statusCode != 200) _decode(r);
    return r.bodyBytes;
  }

  void close() => _http.close();
}

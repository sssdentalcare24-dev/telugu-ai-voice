import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A readable error from one of the free online AI engines.
class FreeEngineException implements Exception {
  FreeEngineException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal client for a public Hugging Face Space built with Gradio 4/5
/// (the documented `/gradio_api/call/<name>` HTTP API).
///
/// These Spaces are free public demo servers: they can be asleep, busy or out
/// of their daily free GPU time. Every failure becomes a [FreeEngineException]
/// with a message a non-technical user can act on.
class GradioSpace {
  GradioSpace(this.baseUrl, {required this.name, http.Client? client}) : _client = client ?? http.Client();

  /// e.g. https://ai4bharat-indicf5.hf.space (no trailing slash)
  final String baseUrl;

  /// Shown in error messages, e.g. "The free Telugu voice server".
  final String name;
  final http.Client _client;

  static const Duration timeout = Duration(minutes: 4);

  /// Runs [api] with positional [data] and returns the output list.
  Future<List<dynamic>> call(String api, List<Object?> data) async {
    final start = await _send(
      () => _client.post(
        Uri.parse('$baseUrl/gradio_api/call/$api'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'data': data}),
      ),
    );
    String? eventId;
    try {
      eventId = (jsonDecode(utf8.decode(start.bodyBytes)) as Map)['event_id'] as String?;
    } catch (_) {
      eventId = null;
    }
    if (eventId == null || eventId.isEmpty) {
      throw FreeEngineException('$name did not accept the request. Please try again in a minute.');
    }
    final result = await _send(() => _client.get(Uri.parse('$baseUrl/gradio_api/call/$api/$eventId')));
    return parseEvents(utf8.decode(result.bodyBytes, allowMalformed: true), name);
  }

  /// Uploads a file and returns the server-side path to pass to [fileData].
  Future<String> upload(Uint8List bytes, String filename) async {
    final response = await _send(() async {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/gradio_api/upload'))
        ..files.add(http.MultipartFile.fromBytes('files', bytes, filename: filename));
      return http.Response.fromStream(await _client.send(request));
    });
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is List && decoded.isNotEmpty && decoded.first is String) return decoded.first as String;
    } catch (_) {
      // fall through
    }
    throw FreeEngineException('$name could not receive the audio file. Please try again.');
  }

  /// Downloads a file the Space produced (a `path` from an output).
  Future<Uint8List> download(String path) async {
    final response = await _send(() => _client.get(Uri.parse('$baseUrl/gradio_api/file=$path')));
    if (response.bodyBytes.isEmpty) throw FreeEngineException('$name returned an empty audio file.');
    return response.bodyBytes;
  }

  /// The JSON shape Gradio expects for a file input.
  static Map<String, Object?> fileData(String path) => {
        'path': path,
        'meta': {'_type': 'gradio.FileData'},
      };

  /// Unwraps `{"__type__": "update", "value": ...}` objects that some
  /// endpoints return instead of plain values.
  static Object? valueOf(Object? output) {
    if (output is Map && output.containsKey('__type__')) return output['value'];
    return output;
  }

  /// The `path` of a file output, or null.
  static String? pathOf(Object? output) {
    final value = valueOf(output);
    if (value is Map && value['path'] is String) return value['path'] as String;
    return null;
  }

  /// Reads the server-sent events of a finished call.
  static List<dynamic> parseEvents(String body, String name) {
    String? event;
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (event == 'complete') {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
        throw FreeEngineException('$name sent an unexpected answer. Please try again.');
      }
      if (event == 'error') throw FreeEngineException(friendlyError(data, name));
    }
    throw FreeEngineException('$name stopped without a result. It may be busy; please try again in a minute.');
  }

  static String friendlyError(String raw, String name) {
    String? text;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) text = decoded;
      if (decoded is Map) text = (decoded['error'] ?? decoded['message'])?.toString();
    } catch (_) {
      text = raw;
    }
    final lower = (text ?? '').toLowerCase();
    if (lower.contains('quota') || lower.contains('limit')) {
      return "$name has used up today's free limit. Please try again after a few hours.";
    }
    if (text == null || text.isEmpty || text == 'null') {
      // Public ZeroGPU Spaces hide the reason; the usual one is the free daily
      // GPU allowance of this internet connection.
      return "$name could not finish. It may be busy, or today's free limit for your internet "
          'connection may be used up (it refills over the day). Try again later, or switch between '
          'Wi-Fi and mobile data.';
    }
    final short = text.length > 220 ? '${text.substring(0, 220)}…' : text;
    return '$name reported a problem: $short';
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw FreeEngineException('$name is taking too long (it may be very busy). Please try again later.');
    } on http.ClientException {
      throw FreeEngineException('No internet connection, or $name cannot be reached right now.');
    } catch (e) {
      if (e is FreeEngineException) rethrow;
      throw FreeEngineException('No internet connection, or $name cannot be reached right now.');
    }
    final code = response.statusCode;
    if (code >= 200 && code < 300) return response;
    if (code == 429) throw FreeEngineException('$name is getting too many requests. Please wait a minute and try again.');
    if (code == 502 || code == 503 || code == 504) {
      throw FreeEngineException('$name is starting up or busy. Please wait a minute and try again.');
    }
    if (code == 404) throw FreeEngineException('$name is not available at the moment (it may have been moved or paused).');
    throw FreeEngineException('$name returned an error (HTTP $code). Please try again later.');
  }
}

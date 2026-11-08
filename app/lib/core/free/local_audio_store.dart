import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wav.dart';

/// One audio clip kept on this phone (made with the free engines).
class LocalAudio {
  const LocalAudio({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    required this.seconds,
    required this.sizeBytes,
    this.detail,
    this.path,
    this.bytes,
    this.url,
    this.remoteId,
    this.format = 'wav',
  });

  /// Also the file name, e.g. TeluguVoice_20261108_143012.
  final String id;
  final String title;

  /// 'tts', 'converted', 'original' or 'clone' (speech in a personal voice).
  final String kind;
  final DateTime createdAt;
  final double seconds;
  final int sizeBytes;

  /// e.g. the voice used, or the text that was spoken.
  final String? detail;

  /// File on the phone (null on the web or for unsaved previews).
  final String? path;

  /// In-memory audio (web, tests and unsaved previews).
  final Uint8List? bytes;

  /// Signed link for audio kept on the app server (server mode).
  final String? url;

  /// Id of the item on the server (server mode), e.g. a generation id.
  final String? remoteId;

  /// 'wav' or 'mp3'.
  final String format;

  /// An unsaved clip, e.g. a fresh recording before conversion.
  factory LocalAudio.preview(Uint8List bytes, {required String title, String kind = 'original'}) => LocalAudio(
        id: 'preview_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        kind: kind,
        createdAt: DateTime.now(),
        seconds: wavSeconds(bytes) ?? 0,
        sizeBytes: bytes.length,
        bytes: bytes,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'created_at': createdAt.toIso8601String(),
        'seconds': seconds,
        'size': sizeBytes,
        'detail': detail,
        'path': path,
        'format': format,
      };

  static LocalAudio? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return LocalAudio(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        seconds: (json['seconds'] as num).toDouble(),
        sizeBytes: (json['size'] as num).toInt(),
        detail: json['detail'] as String?,
        path: json['path'] as String?,
        format: json['format'] as String? ?? 'wav',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Keeps generated and converted audio on the phone, newest first.
///
/// On Android the clips are WAV files in the app's private storage, listed in
/// shared preferences. On the web (and in tests) they live in memory only.
class LocalAudioStore extends ChangeNotifier {
  LocalAudioStore({SharedPreferences? prefs, bool persist = true})
      : _prefs = prefs,
        _persist = persist;

  /// A store that never touches the disk (web and tests).
  LocalAudioStore.memory() : this(persist: false);

  static const _kIndex = 'local_audio_v1';
  static const int maxItems = 200;

  final SharedPreferences? _prefs;
  final bool _persist;
  final List<LocalAudio> _items = [];
  final Set<String> _issued = {};
  final Map<String, Directory> _dirs = {};

  bool get persistent => _persist && !kIsWeb && _prefs != null;
  List<LocalAudio> get items => List.unmodifiable(_items);

  /// Reads the saved list. Call once at start-up.
  Future<void> load() async {
    if (!persistent) return;
    final raw = _prefs!.getString(_kIndex);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _items
        ..clear()
        ..addAll(list.map(LocalAudio.fromJson).whereType<LocalAudio>().where((a) => a.path != null && File(a.path!).existsSync()));
      _issued.addAll(_items.map((a) => a.id));
      notifyListeners();
    } catch (_) {
      // A damaged index is ignored rather than crashing the app.
    }
  }

  /// Saves a new clip and returns it.
  Future<LocalAudio> add(Uint8List bytes, {required String title, required String kind, String? detail}) async {
    final item = await save(bytes, title: title, kind: kind, detail: detail, folder: 'audio');
    _items.insert(0, item);
    while (_items.length > maxItems) {
      await _deleteFile(_items.removeLast());
    }
    await _saveIndex();
    notifyListeners();
    return item;
  }

  /// Writes [bytes] to the app's private storage (or keeps them in memory)
  /// without listing them in History. Used for voice samples and previews.
  Future<LocalAudio> save(
    Uint8List bytes, {
    required String title,
    required String kind,
    String? detail,
    String folder = 'voices',
    String ext = 'wav',
  }) async {
    final now = DateTime.now();
    final id = _newId(now);
    String? path;
    if (persistent) {
      final dir = await _directory(folder);
      final file = File('${dir.path}/$id.$ext');
      await file.writeAsBytes(bytes, flush: true);
      path = file.path;
    }
    _issued.add(id);
    return LocalAudio(
      id: id,
      title: title,
      kind: kind,
      createdAt: now,
      seconds: wavSeconds(bytes) ?? 0,
      sizeBytes: bytes.length,
      detail: detail,
      path: path,
      bytes: persistent ? null : bytes,
      format: ext,
    );
  }

  /// Deletes a file written with [save].
  Future<void> discard(LocalAudio item) => _deleteFile(item);

  /// The audio bytes of [item].
  Future<Uint8List> bytesOf(LocalAudio item) async {
    if (item.bytes != null) return item.bytes!;
    if (item.path != null && !kIsWeb) return File(item.path!).readAsBytes();
    if (item.url != null) {
      final response = await http.get(Uri.parse(item.url!));
      if (response.statusCode == 200) return response.bodyBytes;
      throw StateError('This audio link has expired. Refresh and try again.');
    }
    throw StateError('This audio is no longer available.');
  }

  Future<void> delete(LocalAudio item) async {
    _items.removeWhere((a) => a.id == item.id);
    await _deleteFile(item);
    await _saveIndex();
    notifyListeners();
  }

  String _newId(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final base = 'TeluguVoice_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
    var id = base;
    var n = 2;
    while (_issued.contains(id)) {
      id = '${base}_${n++}';
    }
    return id;
  }

  Future<Directory> _directory(String folder) async {
    final cached = _dirs[folder];
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$folder');
    await dir.create(recursive: true);
    return _dirs[folder] = dir;
  }

  Future<void> _deleteFile(LocalAudio item) async {
    if (item.path == null || kIsWeb) return;
    try {
      final file = File(item.path!);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Already gone.
    }
  }

  Future<void> _saveIndex() async {
    if (!persistent) return;
    await _prefs!.setString(_kIndex, jsonEncode([for (final a in _items) a.toJson()]));
  }
}

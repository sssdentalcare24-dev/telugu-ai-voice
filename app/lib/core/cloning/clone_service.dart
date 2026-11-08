import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../free/free_voice_engine.dart';
import '../free/gradio_space.dart';
import '../free/local_audio_store.dart';
import '../free/wav.dart';
import 'clone_models.dart';
import 'time_stretch.dart';

/// A readable error from voice cloning (either mode).
class CloneException implements Exception {
  CloneException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One place to create, list and use personal voices. Two implementations:
///
/// * [LocalCloneService] – free, on this phone: voices are saved on the phone
///   and speech is made by AI4Bharat IndicF5 on Hugging Face.
/// * [ServerCloneService] – the app's own backend, which holds the API keys
///   for Sarvam AI / ElevenLabs (or uses IndicF5 with a server token) and keeps
///   profiles, consent records and history in its database.
abstract class CloneService extends ChangeNotifier {
  String get modeLabel;
  bool get onDevice;

  /// Providers a new voice can be created with (ready ones first).
  List<CloneProviderInfo> get providers;
  List<VoiceProfile> get profiles;

  /// Speech made with saved voices, newest first.
  List<LocalAudio> get history;

  bool get canDownloadMp3;

  Future<void> load();

  CloneProviderInfo providerFor(String name) =>
      providers.firstWhere((p) => p.name == name, orElse: () => CloneProviderInfo.indicF5OnPhone);

  Future<VoiceProfile> createVoice({
    required String name,
    required String category,
    required String recordingLanguage,
    required Uint8List sample,
    required String filename,
    required ConsentRecord consent,
    String? transcript,
    String? provider,
    CloneProgress? onProgress,
  });

  Future<void> deleteVoice(VoiceProfile profile);

  Future<LocalAudio> speak({
    required VoiceProfile profile,
    required String text,
    required String language,
    double speed = 1.0,
    CloneProgress? onProgress,
  });

  Future<void> deleteGeneration(LocalAudio item);

  Future<void> refreshHistory();

  /// MP3 download link for [item] (server mode only).
  Uri? mp3Link(LocalAudio item) => null;
}

String _shortTitle(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = t.runes.toList();
  return runes.length > 48 ? '${String.fromCharCodes(runes.take(48))}…' : t;
}

const _previewText = {
  'te': 'నమస్కారం! ఇది నా కొత్త AI స్వరం. మీకు ఎలా అనిపిస్తోంది?',
  'hi': 'नमस्ते! यह मेरी नई AI आवाज़ है। आपको कैसी लगी?',
};

// ---- Free, on this phone ----------------------------------------------------------

class LocalCloneService extends CloneService {
  LocalCloneService({required this.store, required this.engine, SharedPreferences? prefs, bool persist = true})
      : _prefs = persist ? prefs : null;

  static const _kProfiles = 'voice_profiles_v1';

  final LocalAudioStore store;
  final FreeVoiceEngine engine;
  final SharedPreferences? _prefs;
  final List<VoiceProfile> _profiles = [];

  @override
  String get modeLabel => 'This phone · free';

  @override
  bool get onDevice => true;

  @override
  List<CloneProviderInfo> get providers => const [CloneProviderInfo.indicF5OnPhone];

  @override
  List<VoiceProfile> get profiles => List.unmodifiable(_profiles);

  @override
  List<LocalAudio> get history => store.items.where((a) => a.kind == 'clone').toList();

  @override
  bool get canDownloadMp3 => false;

  bool get _persistent => _prefs != null && store.persistent;

  @override
  Future<void> load() async {
    if (!_persistent) return;
    final raw = _prefs!.getString(_kProfiles);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _profiles
        ..clear()
        ..addAll(list.map(VoiceProfile.fromLocalJson).whereType<VoiceProfile>().where((p) => p.sample != null));
      notifyListeners();
    } catch (_) {
      // A damaged list is ignored rather than crashing the app.
    }
  }

  Future<void> _save() async {
    if (!_persistent) return;
    await _prefs!.setString(_kProfiles, jsonEncode([for (final p in _profiles) p.toJson()]));
  }

  @override
  Future<VoiceProfile> createVoice({
    required String name,
    required String category,
    required String recordingLanguage,
    required Uint8List sample,
    required String filename,
    required ConsentRecord consent,
    String? transcript,
    String? provider,
    CloneProgress? onProgress,
  }) async {
    final info = CloneProviderInfo.indicF5OnPhone;
    final text = transcript?.trim() ?? '';
    if (name.trim().isEmpty) throw CloneException('Give the voice a name.');
    if (text.length < 2) throw CloneException('Type the exact words spoken in the recording.');
    final seconds = wavSeconds(sample);
    if (seconds != null && seconds < info.minSeconds) {
      throw CloneException('The recording is ${seconds.toStringAsFixed(0)} s. Please record at least ${info.minSeconds.toStringAsFixed(0)} seconds.');
    }
    if (seconds != null && seconds > info.maxSeconds + 0.5) {
      throw CloneException('The free engine uses up to ${info.maxSeconds.toStringAsFixed(0)} seconds. Please record a shorter sample.');
    }
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'wav';

    onProgress?.call(0.15, 'Saving your voice sample…');
    final saved = await store.save(sample, title: 'Voice sample · ${name.trim()}', kind: 'original', ext: ext);

    // A short preview proves the voice works. If the free server is busy the
    // voice is still saved; the user can make speech later.
    onProgress?.call(0.3, 'Creating your AI voice on the free server…');
    LocalAudio? preview;
    String? warning;
    final previewLang = _previewText.containsKey(recordingLanguage) ? recordingLanguage : 'te';
    try {
      final wav = await engine.synthesizeWithSample(
        _previewText[previewLang]!,
        sample,
        text,
        filename: 'voice_sample.$ext',
        onProgress: (step, total, message) => onProgress?.call(0.3 + 0.6 * step / total, message),
      );
      preview = await store.save(wav, title: 'Preview · ${name.trim()}', kind: 'clone');
    } on FreeEngineException catch (e) {
      warning = 'Voice saved, but the preview could not be made now. ${e.message}';
    }

    final now = DateTime.now();
    final profile = VoiceProfile(
      id: 'phone_${now.microsecondsSinceEpoch}',
      name: name.trim(),
      category: category,
      recordingLanguage: recordingLanguage,
      provider: info.name,
      status: 'ready',
      createdAt: now,
      providerVoiceId: 'indicf5:zero-shot',
      transcript: text,
      consent: consent.toJson(acceptedAt: now),
      sample: saved,
      preview: preview,
      warning: warning,
    );
    _profiles.insert(0, profile);
    await _save();
    onProgress?.call(1, 'Voice saved');
    notifyListeners();
    return profile;
  }

  @override
  Future<void> deleteVoice(VoiceProfile profile) async {
    _profiles.removeWhere((p) => p.id == profile.id);
    if (profile.sample != null) await store.discard(profile.sample!);
    if (profile.preview != null) await store.discard(profile.preview!);
    await _save();
    notifyListeners();
  }

  @override
  Future<LocalAudio> speak({
    required VoiceProfile profile,
    required String text,
    required String language,
    double speed = 1.0,
    CloneProgress? onProgress,
  }) =>
      freeGuard(() => _speak(profile: profile, text: text, language: language, speed: speed, onProgress: onProgress));

  Future<LocalAudio> _speak({
    required VoiceProfile profile,
    required String text,
    required String language,
    required double speed,
    CloneProgress? onProgress,
  }) async {
    final sample = profile.sample;
    final transcript = profile.transcript;
    if (sample == null || transcript == null) throw CloneException('This voice has no saved sample. Create it again.');
    if (!CloneProviderInfo.indicF5OnPhone.languages.contains(language)) {
      throw CloneException('The free engine does not speak ${CloneLanguage.byCode(language).name}.');
    }
    final bytes = await store.bytesOf(sample);
    var wav = await engine.synthesizeWithSample(
      text,
      bytes,
      transcript,
      filename: 'voice_sample.${sample.format}',
      onProgress: (step, total, message) => onProgress?.call(0.9 * step / total, message),
    );
    if ((speed - 1).abs() >= 0.01) {
      onProgress?.call(0.93, 'Adjusting the speed…');
      wav = kIsWeb ? timeStretchWav(wav, speed) : await compute(timeStretchJob, (wav, speed));
    }
    final lang = CloneLanguage.byCode(language);
    final item = await store.add(
      wav,
      title: _shortTitle(text),
      kind: 'clone',
      detail: '${profile.name} · ${lang.name}${(speed - 1).abs() >= 0.01 ? ' · ${speed.toStringAsFixed(2)}×' : ''}',
    );
    onProgress?.call(1, 'Done');
    notifyListeners();
    return item;
  }

  @override
  Future<void> deleteGeneration(LocalAudio item) async {
    await store.delete(item);
    notifyListeners();
  }

  @override
  Future<void> refreshHistory() async => notifyListeners();
}

// ---- The app's own server --------------------------------------------------------------

class ServerCloneService extends CloneService {
  ServerCloneService(this.api);

  final ApiClient api;
  final List<VoiceProfile> _profiles = [];
  final List<LocalAudio> _history = [];
  List<CloneProviderInfo> _providers = const [];
  String? _default;

  @override
  String get modeLabel => 'App server';

  @override
  bool get onDevice => false;

  @override
  List<CloneProviderInfo> get providers => _providers;

  String? get defaultProvider => _default;

  @override
  List<VoiceProfile> get profiles => List.unmodifiable(_profiles);

  @override
  List<LocalAudio> get history => List.unmodifiable(_history);

  @override
  bool get canDownloadMp3 => true;

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException catch (e) {
      throw CloneException(e.message);
    }
  }

  @override
  Future<void> load() => _guard(() async {
        final data = await api.getJson('/api/clone/providers') as Map<String, dynamic>;
        final list = [
          for (final p in (data['providers'] as List? ?? const []))
            if (p is Map<String, dynamic>) CloneProviderInfo.fromJson(p),
        ]..sort((a, b) => (b.ready ? 1 : 0) - (a.ready ? 1 : 0));
        _providers = list;
        _default = data['default'] as String?;
        final profiles = await api.getJson('/api/clone/profiles') as Map<String, dynamic>;
        _profiles
          ..clear()
          ..addAll([
            for (final p in (profiles['profiles'] as List? ?? const []))
              if (p is Map<String, dynamic>) _profile(p),
          ]);
        await _loadHistory();
        notifyListeners();
      });

  LocalAudio? _audio(Object? json, {String? kind, String? detail, String? remoteId}) {
    if (json is! Map<String, dynamic>) return null;
    final item = AudioItem.fromJson(json);
    return LocalAudio(
      id: item.id,
      title: item.title,
      kind: kind ?? item.kind,
      createdAt: item.createdAt,
      seconds: item.durationSeconds,
      sizeBytes: item.sizeBytes,
      detail: detail,
      url: api.resolve(item.downloadPath).toString(),
      remoteId: remoteId ?? item.id,
      format: item.format,
    );
  }

  VoiceProfile _profile(Map<String, dynamic> j, {String? warning}) => VoiceProfile(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        category: j['category'] as String? ?? 'female',
        recordingLanguage: j['recording_language'] as String? ?? 'te',
        provider: j['provider'] as String? ?? '',
        status: j['status'] as String? ?? 'draft',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        providerVoiceId: j['provider_voice_id'] as String?,
        transcript: j['transcript'] as String?,
        consent: Map<String, dynamic>.from(j['consent'] as Map? ?? const {}),
        sample: _audio(j['sample']),
        preview: _audio(j['preview'], kind: 'clone'),
        warning: warning ?? j['warning'] as String? ?? j['error'] as String?,
      );

  LocalAudio? _generation(Map<String, dynamic> g) {
    final lang = CloneLanguage.byCode(g['language'] as String? ?? 'te');
    final speed = (g['speed'] as num?)?.toDouble() ?? 1.0;
    return _audio(
      g['audio'],
      kind: 'clone',
      detail: '${g['profile_name']} · ${lang.name}${(speed - 1).abs() >= 0.01 ? ' · ${speed.toStringAsFixed(2)}×' : ''}',
      remoteId: g['id'] as String?,
    );
  }

  Future<void> _loadHistory() async {
    final data = await api.getJson('/api/clone/history', {'limit': '50'}) as Map<String, dynamic>;
    _history
      ..clear()
      ..addAll([
        for (final g in (data['items'] as List? ?? const []))
          if (g is Map<String, dynamic>) _generation(g),
      ].whereType<LocalAudio>());
  }

  @override
  Future<void> refreshHistory() => _guard(() async {
        await _loadHistory();
        notifyListeners();
      });

  @override
  Future<VoiceProfile> createVoice({
    required String name,
    required String category,
    required String recordingLanguage,
    required Uint8List sample,
    required String filename,
    required ConsentRecord consent,
    String? transcript,
    String? provider,
    CloneProgress? onProgress,
  }) =>
      _guard(() async {
        onProgress?.call(0.05, 'Saving the voice profile…');
        final created = await api.postJson('/api/clone/profiles', {
          'name': name.trim(),
          'category': category,
          'recording_language': recordingLanguage,
          if (provider != null) 'provider': provider,
          'consent': consent.toJson(),
        }) as Map<String, dynamic>;
        final id = created['id'] as String;
        try {
          onProgress?.call(0.25, 'Uploading your recording…');
          await api.postFile(
            '/api/clone/profiles/$id/sample',
            bytes: sample,
            filename: filename,
            fields: {if (transcript != null && transcript.trim().isNotEmpty) 'transcript': transcript.trim()},
          );
          onProgress?.call(0.5, 'Creating your AI voice…');
          final cloned = await api.postJson('/api/clone/profiles/$id/clone', const {}, long: true) as Map<String, dynamic>;
          final profile = _profile(cloned);
          _profiles.insert(0, profile);
          onProgress?.call(1, 'Voice saved');
          notifyListeners();
          return profile;
        } catch (_) {
          // Don't leave a half-made profile behind.
          try {
            await api.delete('/api/clone/profiles/$id');
          } catch (_) {}
          rethrow;
        }
      });

  @override
  Future<void> deleteVoice(VoiceProfile profile) => _guard(() async {
        await api.delete('/api/clone/profiles/${profile.id}');
        _profiles.removeWhere((p) => p.id == profile.id);
        notifyListeners();
      });

  @override
  Future<LocalAudio> speak({
    required VoiceProfile profile,
    required String text,
    required String language,
    double speed = 1.0,
    CloneProgress? onProgress,
  }) =>
      _guard(() async {
        onProgress?.call(0.2, 'Speaking in ${profile.name}\'s voice…');
        final g = await api.postJson(
          '/api/clone/tts',
          {'profile_id': profile.id, 'text': text, 'language': language, 'speed': speed},
          long: true,
        ) as Map<String, dynamic>;
        final item = _generation(g);
        if (item == null) throw CloneException('The server did not return audio.');
        _history.insert(0, item);
        onProgress?.call(1, 'Done');
        notifyListeners();
        return item;
      });

  @override
  Future<void> deleteGeneration(LocalAudio item) => _guard(() async {
        await api.delete('/api/clone/history/${item.remoteId}');
        _history.removeWhere((a) => a.remoteId == item.remoteId);
        notifyListeners();
      });

  @override
  Uri? mp3Link(LocalAudio item) {
    final url = item.url;
    if (url == null) return null;
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      if (item.format != 'mp3') 'format': 'mp3',
      'download': 'true',
    });
  }
}

/// Maps engine errors from the free path to [CloneException].
Future<T> freeGuard<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on FreeEngineException catch (e) {
    throw CloneException(e.message);
  }
}

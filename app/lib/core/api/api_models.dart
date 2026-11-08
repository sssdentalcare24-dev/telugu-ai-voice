/// Typed models for the FastAPI responses.
library;

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  bool get isProviderMissing =>
      code == 'PROVIDER_NOT_CONFIGURED' || code == 'LIVE_CONVERSION_UNAVAILABLE';
  bool get isAuth => statusCode == 401;
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => message;
}

Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const [];
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
bool _bool(Object? v) => v == true;
num _num(Object? v) => v is num ? v : 0;

class ProviderInfo {
  ProviderInfo({required this.name, required this.state, required this.message, required this.paid});

  factory ProviderInfo.fromJson(Map<String, dynamic> j) => ProviderInfo(
        name: _str(j['name']),
        state: _str(j['state'], 'not_configured'),
        message: _str(j['message']),
        paid: _bool(j['paid']),
      );

  final String name;

  /// ready | not_configured | not_implemented | unsupported
  final String state;
  final String message;
  final bool paid;

  bool get ready => state == 'ready';
}

class Capability {
  Capability({required this.available, required this.providers});

  final bool available;
  final List<ProviderInfo> providers;

  /// The most helpful explanation to show when the feature is not available.
  String get reason {
    if (available) return '';
    for (final p in providers) {
      if (p.message.isNotEmpty) return p.message;
    }
    return 'Not configured on the server yet.';
  }

  bool get needsCredentials => providers.any((p) => p.state == 'not_configured');
}

class ServerLimits {
  ServerLimits({
    required this.maxUploadMb,
    required this.maxAudioSeconds,
    required this.maxTtsChars,
    required this.allowedFormats,
  });

  factory ServerLimits.fromJson(Map<String, dynamic> j) => ServerLimits(
        maxUploadMb: _num(j['max_upload_mb']).toInt(),
        maxAudioSeconds: _num(j['max_audio_seconds']).toInt(),
        maxTtsChars: _num(j['max_tts_chars']).toInt(),
        allowedFormats: _list(j['allowed_formats']).whereType<String>().toList(),
      );

  final int maxUploadMb;
  final int maxAudioSeconds;
  final int maxTtsChars;
  final List<String> allowedFormats;
}

class ServerHealth {
  ServerHealth({
    required this.version,
    required this.environment,
    required this.authMode,
    required this.tts,
    required this.voiceConversion,
    required this.liveConversion,
    required this.limits,
  });

  factory ServerHealth.fromJson(Map<String, dynamic> j) {
    final caps = _map(j['capabilities']);
    final tts = _map(caps['tts']);
    final vc = _map(caps['voice_conversion']);
    final live = _map(caps['live_conversion']);
    List<ProviderInfo> one(Map<String, dynamic> m) =>
        m['provider'] is Map<String, dynamic> ? [ProviderInfo.fromJson(_map(m['provider']))] : <ProviderInfo>[];
    return ServerHealth(
      version: _str(j['version']),
      environment: _str(j['environment']),
      authMode: _str(j['auth_mode'], 'firebase'),
      tts: Capability(
        available: _bool(tts['available']),
        providers: _list(tts['providers']).map((e) => ProviderInfo.fromJson(_map(e))).toList(),
      ),
      voiceConversion: Capability(available: _bool(vc['available']), providers: one(vc)),
      liveConversion: Capability(available: _bool(live['available']) && _bool(live['streaming']), providers: one(live)),
      limits: ServerLimits.fromJson(_map(j['limits'])),
    );
  }

  final String version;
  final String environment;
  final String authMode;
  final Capability tts;
  final Capability voiceConversion;
  final Capability liveConversion;
  final ServerLimits limits;

  bool get devAuth => authMode == 'dev';
}

class Voice {
  Voice({
    required this.id,
    required this.provider,
    required this.gender,
    required this.displayName,
    required this.displayNameTe,
    required this.quality,
    required this.supportsPitch,
    required this.supportsSpeed,
    required this.styles,
    required this.notes,
    required this.available,
  });

  factory Voice.fromJson(Map<String, dynamic> j) => Voice(
        id: _str(j['id']),
        provider: _str(j['provider']),
        gender: _str(j['gender'], 'female'),
        displayName: _str(j['display_name']),
        displayNameTe: j['display_name_te'] as String?,
        quality: _str(j['quality'], 'standard'),
        supportsPitch: _bool(j['supports_pitch']),
        supportsSpeed: j['supports_speed'] != false,
        styles: _list(j['styles']).whereType<String>().toList(),
        notes: j['notes'] as String?,
        available: _bool(j['available']),
      );

  final String id;
  final String provider;
  final String gender; // female | male
  final String displayName;
  final String? displayNameTe;
  final String quality;
  final bool supportsPitch;
  final bool supportsSpeed;
  final List<String> styles;
  final String? notes;
  final bool available;

  bool get isFemale => gender == 'female';
}

class AudioItem {
  AudioItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.format,
    required this.sizeBytes,
    required this.durationSeconds,
    required this.createdAt,
    required this.sourceAudioId,
    required this.parameters,
    required this.downloadPath,
  });

  factory AudioItem.fromJson(Map<String, dynamic> j) => AudioItem(
        id: _str(j['id']),
        kind: _str(j['kind'], 'original'),
        title: _str(j['title'], 'Audio'),
        format: _str(j['format']),
        sizeBytes: _num(j['size_bytes']).toInt(),
        durationSeconds: _num(j['duration_seconds']).toDouble(),
        createdAt: DateTime.tryParse(_str(j['created_at']))?.toLocal() ?? DateTime.now(),
        sourceAudioId: j['source_audio_id'] as String?,
        parameters: _map(j['parameters']),
        downloadPath: _str(j['download_url']),
      );

  final String id;

  /// tts | original | converted
  final String kind;
  final String title;
  final String format;
  final int sizeBytes;
  final double durationSeconds;
  final DateTime createdAt;
  final String? sourceAudioId;
  final Map<String, dynamic> parameters;

  /// Relative signed URL, valid for a few minutes.
  final String downloadPath;
}

class HistoryPage {
  HistoryPage({required this.items, required this.nextCursor});

  factory HistoryPage.fromJson(Map<String, dynamic> j) => HistoryPage(
        items: _list(j['items']).map((e) => AudioItem.fromJson(_map(e))).toList(),
        nextCursor: j['next_cursor'] as String?,
      );

  final List<AudioItem> items;
  final String? nextCursor;
}

import 'package:flutter/foundation.dart';

/// Build-time and default configuration. No API keys ever live in the app:
/// paid AI calls go through the FastAPI backend, which holds the secrets, and
/// the free engines (public Hugging Face Spaces) need no keys at all.
abstract final class AppConfig {
  static const String appName = 'తెలుగు AI Voice';
  static const String appSubtitle = 'Telugu Voice Studio';
  static const String version = '0.5.1 · AI voice cloning + own Hugging Face account';

  /// Set with: flutter run --dart-define=API_BASE_URL=https://api.example.com
  /// Use "/" when the web app is served from the same origin as the API.
  static const String _buildApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const String sampleTeluguText = 'నమస్కారం! మీరు ఎలా ఉన్నారు? తెలుగు AI Voice యాప్‌కు స్వాగతం.';

  /// Server address used until the user changes it in Settings.
  static String get defaultApiBaseUrl {
    if (_buildApiBaseUrl.isNotEmpty) return _buildApiBaseUrl;
    if (kIsWeb) return 'http://localhost:8000';
    // The Android emulator reaches the host computer at 10.0.2.2.
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  /// Turns a configured value into an absolute base URL without a trailing slash.
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty || value == '/') {
      // Same-origin deployment (web app and API behind one domain).
      return kIsWeb ? Uri.base.origin : 'http://localhost:8000';
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

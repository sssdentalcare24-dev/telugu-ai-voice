import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../config/app_config.dart';

enum ServerConnection { checking, online, offline }

/// App-wide state: theme, server address, and what the server can do right now.
class AppController extends ChangeNotifier {
  AppController({required SharedPreferences prefs, http.Client? httpClient})
      : _prefs = prefs,
        _httpClient = httpClient {
    final mode = prefs.getString(_kTheme);
    _themeMode = ThemeMode.values.firstWhere((m) => m.name == mode, orElse: () => ThemeMode.system);
    _apiBaseUrl = prefs.getString(_kApiBase) ?? AppConfig.defaultApiBaseUrl;
    _devUser = prefs.getString(_kDevUser) ?? 'telugu-dev-user';
    _rebuildClient();
  }

  static const _kTheme = 'theme_mode';
  static const _kApiBase = 'api_base_url';
  static const _kDevUser = 'dev_user';

  final SharedPreferences _prefs;
  final http.Client? _httpClient;

  late ThemeMode _themeMode;
  late String _apiBaseUrl;
  late String _devUser;
  late ApiClient _api;

  ServerConnection _connection = ServerConnection.checking;
  ServerHealth? _health;
  List<Voice> _voices = const [];
  String? _lastError;
  int _refreshToken = 0;

  ThemeMode get themeMode => _themeMode;
  String get apiBaseUrl => _apiBaseUrl;
  String get devUser => _devUser;
  ApiClient get api => _api;
  ServerConnection get connection => _connection;
  ServerHealth? get health => _health;
  List<Voice> get voices => _voices;
  String? get lastError => _lastError;

  void _rebuildClient() {
    _api = ApiClient(
      baseUrl: AppConfig.normalizeBaseUrl(_apiBaseUrl),
      devUser: _devUser,
      httpClient: _httpClient,
    );
  }

  /// Re-reads /api/health and /api/voices. Safe to call any time.
  Future<void> refreshServer() async {
    final token = ++_refreshToken;
    _connection = ServerConnection.checking;
    _lastError = null;
    notifyListeners();
    try {
      final health = await _api.health();
      List<Voice> voices = const [];
      try {
        voices = await _api.voices();
      } on ApiException {
        voices = const [];
      }
      if (token != _refreshToken) return; // a newer refresh superseded this one
      _health = health;
      _voices = voices;
      _connection = ServerConnection.online;
    } on ApiException catch (e) {
      if (token != _refreshToken) return;
      _health = null;
      _voices = const [];
      _connection = ServerConnection.offline;
      _lastError = e.message;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kTheme, mode.name);
  }

  Future<void> setApiBaseUrl(String value) async {
    _apiBaseUrl = value.trim();
    await _prefs.setString(_kApiBase, _apiBaseUrl);
    _rebuildClient();
    await refreshServer();
  }

  Future<void> setDevUser(String value) async {
    _devUser = value.trim();
    await _prefs.setString(_kDevUser, _devUser);
    _rebuildClient();
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../cloning/clone_service.dart';
import '../config/app_config.dart';
import '../free/audio_playback.dart';
import '../free/free_voice_engine.dart';
import '../free/local_audio_store.dart';

enum ServerConnection { checking, online, offline }

/// App-wide state: theme, server address, what the server can do right now,
/// plus the free online engines and the audio kept on this phone.
class AppController extends ChangeNotifier {
  AppController({
    required SharedPreferences prefs,
    http.Client? httpClient,
    LocalAudioStore? localAudio,
    FreeVoiceEngine? freeEngine,
    AudioPlayback? playback,
  })  : _prefs = prefs,
        _httpClient = httpClient,
        localAudio = localAudio ?? LocalAudioStore(prefs: prefs),
        freeEngine = freeEngine ?? FreeVoiceEngine(),
        playback = playback ?? AudioPlayback() {
    final pc = prefs.getString(_kPcUrl);
    if (pc != null && pc.isNotEmpty) this.freeEngine.pcUrl = pc;
    final token = prefs.getString(_kHfToken);
    if (token != null && token.isNotEmpty) {
      this.freeEngine.token = token;
      _hfAccount = HfAccount(name: prefs.getString(_kHfName) ?? 'your account', isPro: prefs.getBool(_kHfPro) ?? false);
    }
    phoneClone = LocalCloneService(
      store: this.localAudio,
      engine: this.freeEngine,
      prefs: prefs,
      persist: this.localAudio.persistent,
    );
    final mode = prefs.getString(_kTheme);
    _themeMode = ThemeMode.values.firstWhere((m) => m.name == mode, orElse: () => ThemeMode.system);
    _apiBaseUrl = prefs.getString(_kApiBase) ?? AppConfig.defaultApiBaseUrl;
    _devUser = prefs.getString(_kDevUser) ?? 'telugu-dev-user';
    _rebuildClient();
  }

  static const _kTheme = 'theme_mode';
  static const _kHfToken = 'hf_token';
  static const _kHfName = 'hf_account_name';
  static const _kHfPro = 'hf_account_pro';
  static const _kPcUrl = 'pc_voice_server';
  static const _kApiBase = 'api_base_url';
  static const _kDevUser = 'dev_user';

  final SharedPreferences _prefs;
  final http.Client? _httpClient;

  /// Audio made with the free engines, kept on this phone.
  final LocalAudioStore localAudio;

  /// Free natural Telugu voice + voice conversion (public Hugging Face Spaces).
  final FreeVoiceEngine freeEngine;

  /// In-app player for [localAudio] clips.
  final AudioPlayback playback;

  HfAccount? _hfAccount;

  /// The user's own Hugging Face account, if they added a token in Settings.
  HfAccount? get hfAccount => _hfAccount;

  /// Checks and saves the user's Hugging Face token (kept on this phone only).
  Future<HfAccount> setHfToken(String token) async {
    final t = token.trim();
    final account = await freeEngine.checkToken(t);
    freeEngine.token = t;
    _hfAccount = account;
    await _prefs.setString(_kHfToken, t);
    await _prefs.setString(_kHfName, account.name);
    await _prefs.setBool(_kHfPro, account.isPro);
    notifyListeners();
    return account;
  }

  /// Address of the user's PC voice server (unlimited voices), or null.
  String? get pcUrl => freeEngine.pcUrl;

  /// Checks and saves the PC voice server address.
  Future<PcServerInfo> setPcUrl(String raw) async {
    final url = normalizePcUrl(raw);
    final info = await freeEngine.checkPc(url);
    freeEngine.pcUrl = url;
    await _prefs.setString(_kPcUrl, url);
    notifyListeners();
    return info;
  }

  Future<void> clearPcUrl() async {
    freeEngine.pcUrl = null;
    await _prefs.remove(_kPcUrl);
    notifyListeners();
  }

  Future<void> clearHfToken() async {
    freeEngine.token = null;
    _hfAccount = null;
    await _prefs.remove(_kHfToken);
    await _prefs.remove(_kHfName);
    await _prefs.remove(_kHfPro);
    notifyListeners();
  }

  /// Personal voices kept on this phone (free IndicF5 engine).
  late final LocalCloneService phoneClone;

  /// Personal voices on the app server, when the server offers cloning.
  ServerCloneService? _serverClone;
  ServerCloneService? get serverClone => _serverClone;

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
      final cloning = health.voiceCloning?.available ?? false;
      if (!cloning) {
        _serverClone = null;
      } else if (_serverClone?.api != _api) {
        _serverClone = ServerCloneService(_api);
      }
    } on ApiException catch (e) {
      if (token != _refreshToken) return;
      _health = null;
      _voices = const [];
      _connection = ServerConnection.offline;
      _serverClone = null;
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

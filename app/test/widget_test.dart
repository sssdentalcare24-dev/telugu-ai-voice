import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telugu_ai_voice/app.dart';
import 'package:telugu_ai_voice/core/api/api_client.dart';
import 'package:telugu_ai_voice/core/api/api_models.dart';
import 'package:telugu_ai_voice/core/free/audio_playback.dart';
import 'package:telugu_ai_voice/core/free/free_voice_engine.dart';
import 'package:telugu_ai_voice/core/free/local_audio_store.dart';
import 'package:telugu_ai_voice/core/free/mic_recorder.dart';
import 'package:telugu_ai_voice/core/free/wav.dart';
import 'package:telugu_ai_voice/core/state/app_controller.dart';
import 'package:telugu_ai_voice/core/state/app_scope.dart';
import 'package:telugu_ai_voice/core/theme/app_theme.dart';
import 'package:telugu_ai_voice/core/tts/device_tts.dart';
import 'package:telugu_ai_voice/features/convert/convert_screen.dart';
import 'package:telugu_ai_voice/features/tts/tts_screen.dart';
import 'package:telugu_ai_voice/widgets/telugu_keyboard.dart';

/// Stands in for the phone's TTS engine in tests.
class FakePhoneVoice extends PhoneVoice {
  final List<String> spoken = [];

  @override
  Future<void> init() async {
    state = PhoneVoiceState.ready;
    voices = const [
      {'name': 'te-in-x-tef-local', 'locale': 'te-IN'},
      {'name': 'te-in-x-tem-local', 'locale': 'te-IN'},
    ];
    selectedVoice = voices.first['name'];
    notifyListeners();
  }

  @override
  Future<void> speak(String text, {double speed = 1.0, double semitones = 0}) async {
    spoken.add(text);
    speaking = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    speaking = false;
    notifyListeners();
  }
}

/// Records what would have played, without the audio plugin.
class FakePlayback extends AudioPlayback {
  final List<String> played = [];
  String? _current;

  @override
  bool isPlaying(String id) => _current == id;

  @override
  Future<void> toggle(LocalAudio item, Future<Uint8List> Function() loadBytes) async {
    await loadBytes();
    played.add(item.id);
    _current = _current == item.id ? null : item.id;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _current = null;
    notifyListeners();
  }
}

/// Stands in for the microphone.
class FakeRecorder extends MicRecorder {
  bool _on = false;
  int starts = 0;

  @override
  bool get recording => _on;

  @override
  Future<bool> start() async {
    starts++;
    _on = true;
    return true;
  }

  @override
  Future<Uint8List?> stop() async {
    _on = false;
    return makeWav(2, sampleRate: 16000);
  }

  @override
  Future<void> dispose() async {}
}

/// Silent mono 16-bit WAV of [seconds].
Uint8List makeWav(double seconds, {int sampleRate = 24000}) {
  final format = WavInfo(
    audioFormat: 1,
    channels: 1,
    sampleRate: sampleRate,
    bitsPerSample: 16,
    dataOffset: 44,
    dataLength: 0,
  );
  return buildWav(format, Uint8List((sampleRate * seconds).round() * 2));
}

/// A pretend pair of Hugging Face Spaces (IndicF5 + Seed-VC).
class FakeSpaces {
  final List<String> calls = [];
  final List<Object?> lastData = [];

  late final MockClient client = MockClient((req) async {
    final path = req.url.path;
    final call = RegExp(r'^/gradio_api/call/([a-z_0-9]+)(/(.+))?$').firstMatch(path);
    if (req.method == 'POST' && call != null && call.group(3) == null) {
      calls.add(call.group(1)!);
      lastData
        ..clear()
        ..addAll((jsonDecode(req.body) as Map)['data'] as List);
      return _json({'event_id': 'ev-${call.group(1)}'});
    }
    if (req.method == 'GET' && call != null) {
      final out = switch (call.group(1)) {
        'load_example' => [
            {'__type__': 'update', 'value': 'text'},
            {
              '__type__': 'update',
              'value': {'path': '/tmp/gradio/ref/audio.wav', 'meta': {'_type': 'gradio.FileData'}},
            },
            {'__type__': 'update', 'value': 'ಉಲ್ಲೇಖ ಪಠ್ಯ'},
          ],
        'synthesize_speech' => [
            {'path': '/tmp/gradio/tts/audio.wav', 'meta': {'_type': 'gradio.FileData'}},
          ],
        'predict_1' => [
            {'path': '/tmp/gradio/vc/playlist.m3u8'},
            {'path': '/tmp/gradio/vc/audio.wav'},
          ],
        _ => null,
      };
      if (out == null) return http.Response('event: error\ndata: null\n\n', 200);
      return http.Response.bytes(utf8.encode('event: complete\ndata: ${jsonEncode(out)}\n\n'), 200);
    }
    if (path == '/gradio_api/upload') {
      calls.add('upload');
      return _json(['/tmp/gradio/up/file.wav']);
    }
    if (path.startsWith('/gradio_api/file=')) return http.Response.bytes(makeWav(1.5), 200);
    return http.Response('not found', 404);
  });
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _health({required bool tts}) => {
      'status': 'ok',
      'version': '0.2.0',
      'environment': 'test',
      'auth_mode': 'dev',
      'capabilities': {
        'tts': {
          'available': tts,
          'ready_providers': tts ? ['google'] : <String>[],
          'providers': [
            {
              'name': 'google',
              'state': tts ? 'ready' : 'not_implemented',
              'message': tts ? 'ok' : 'Google Cloud Text-to-Speech is not integrated yet. It is scheduled for Stage 3.',
              'paid': true,
            },
          ],
        },
        'voice_conversion': {
          'available': false,
          'provider': {'name': 'none', 'state': 'not_configured', 'message': 'Voice conversion is turned off.', 'paid': true},
        },
        'live_conversion': {
          'available': false,
          'streaming': false,
          'provider': {
            'name': 'none',
            'state': 'unsupported',
            'message': 'Live conversion is unavailable: no genuine streaming engine.',
            'paid': true,
          },
        },
      },
      'limits': {
        'max_upload_mb': 20,
        'max_audio_seconds': 300,
        'max_tts_chars': 5000,
        'allowed_formats': ['wav', 'mp3', 'ogg', 'flac', 'm4a'],
      },
    };

Map<String, dynamic> _voices({required bool available}) => {
      'voices': [
        for (final g in ['female', 'male'])
          {
            'id': 'google-te-$g-standard',
            'provider': 'google',
            'language_code': 'te-IN',
            'gender': g,
            'display_name': '${g == 'female' ? 'Female' : 'Male'} · Google Standard',
            'display_name_te': null,
            'quality': 'standard',
            'accent': 'standard',
            'supports_pitch': true,
            'supports_speed': true,
            'styles': <String>[],
            'notes': null,
            'available': available,
          },
      ],
    };

MockClient _server({bool tts = false, bool offline = false}) => MockClient((req) async {
      if (offline) throw http.ClientException('Connection refused', req.url);
      switch (req.url.path) {
        case '/api/health':
          return _json(_health(tts: tts));
        case '/api/voices':
          return _json(_voices(available: tts));
        case '/api/audio/history':
          return _json({'items': <Object>[], 'next_cursor': null});
        default:
          return _json({
            'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
          }, 404);
      }
    });

AppController _controller(SharedPreferences prefs, {bool tts = false, bool offline = false, FakeSpaces? spaces}) =>
    AppController(
      prefs: prefs,
      httpClient: _server(tts: tts, offline: offline),
      localAudio: LocalAudioStore.memory(),
      freeEngine: FreeVoiceEngine(client: (spaces ?? FakeSpaces()).client),
      playback: FakePlayback(),
    );

Future<void> _pumpFor(WidgetTester tester, {int times = 40}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<AppController> _startApp(WidgetTester tester, {bool tts = false, bool offline = false, FakeSpaces? spaces}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final controller = _controller(prefs, tts: tts, offline: offline, spaces: spaces);
  await tester.pumpWidget(TeluguVoiceApp(controller: controller));
  controller.refreshServer();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return controller;
}

Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('Home shows the four features with honest server status', (tester) async {
    final app = await _startApp(tester);
    expect(app.connection, ServerConnection.online);
    expect(find.text('తెలుగు టెక్స్ట్ → వాయిస్'), findsOneWidget);
    expect(find.text('పురుష → స్త్రీ స్వరం'), findsOneWidget);
    expect(find.text('స్త్రీ → పురుష స్వరం'), findsOneWidget);
    expect(find.text('లైవ్ వాయిస్ ఛేంజర్'), findsOneWidget);
    // Without a server provider, voice and conversions use the free online engines.
    expect(find.text('Free online'), findsNWidgets(3));
    expect(find.text('Unavailable'), findsOneWidget); // no free live streaming engine
    expect(find.text('Server online'), findsOneWidget);
  });

  testWidgets('Offline server is reported, not hidden', (tester) async {
    final app = await _startApp(tester, offline: true);
    expect(app.connection, ServerConnection.offline);
    expect(find.text('Free online AI voices'), findsOneWidget);
    expect(find.text('Free online'), findsNWidgets(3));
    expect(find.text('Offline'), findsOneWidget); // live conversion needs a server
  });

  testWidgets('Server Generate is disabled until the server has a TTS provider', (tester) async {
    await _startApp(tester);
    await tester.tap(find.text('తెలుగు టెక్స్ట్ → వాయిస్'));
    await _settleRoute(tester);
    await tester.tap(find.text('Server'));
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byKey(const Key('generate-button')));
    expect(button.onPressed, isNull);
    final reason = tester.widget<Text>(find.byKey(const Key('generate-blocked-reason')));
    expect(reason.data, contains('Stage 3'));
    // Sample Telugu text is prefilled.
    expect(find.textContaining('నమస్కారం'), findsWidgets);
  });

  testWidgets('Generate is enabled when a provider is ready', (tester) async {
    await _startApp(tester, tts: true);
    await tester.tap(find.text('తెలుగు టెక్స్ట్ → వాయిస్'));
    await _settleRoute(tester);
    final button = tester.widget<FilledButton>(find.byKey(const Key('generate-button')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Phone voice speaks the Telugu text offline', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final app = _controller(prefs, offline: true);
    final phone = FakePhoneVoice();
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(theme: AppTheme.light(), home: TtsScreen(phoneVoice: phone)),
      ),
    );
    app.refreshServer();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(app.connection, ServerConnection.offline);
    await tester.tap(find.text('Phone'));
    await tester.pump();
    expect(find.byKey(const Key('phone-voice-dropdown')), findsOneWidget);
    final play = find.byKey(const Key('phone-play-button'));
    expect(tester.widget<FilledButton>(play).onPressed, isNotNull);
    await tester.tap(play);
    await tester.pump();
    expect(phone.spoken.single, contains('నమస్కారం'));
    expect(find.textContaining('Stop'), findsOneWidget);
  });

  testWidgets('Natural voice is made by the free engine, saved and played', (tester) async {
    final spaces = FakeSpaces();
    final app = await _startApp(tester, offline: true, spaces: spaces);
    await tester.tap(find.text('తెలుగు టెక్స్ట్ → వాయిస్'));
    await _settleRoute(tester);
    expect(find.byKey(const Key('free-voice-dropdown')), findsOneWidget); // two female voices
    await tester.tap(find.byKey(const Key('free-generate-button')));
    await _pumpFor(tester);
    expect(spaces.calls, ['load_example', 'synthesize_speech']);
    expect(spaces.lastData.first, contains('నమస్కారం')); // the Telugu text is what gets spoken
    expect(find.byKey(const Key('free-result')), findsOneWidget);
    expect(app.localAudio.items.single.kind, 'tts');
    expect((app.playback as FakePlayback).played, [app.localAudio.items.single.id]);
    await tester.pump(const Duration(seconds: 5)); // let the snack bar go
  });

  testWidgets('Male to female: record, consent, convert with the free engine', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final spaces = FakeSpaces();
    final app = _controller(prefs, offline: true, spaces: spaces);
    final mic = FakeRecorder();
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ConvertScreen(direction: ConversionDirection.maleToFemale, recorder: mic),
        ),
      ),
    );
    await tester.pump();
    Finder convert() => find.byKey(const Key('convert-button'));
    expect(tester.widget<FilledButton>(convert()).onPressed, isNull);

    // Record: the app explains the microphone first, then records.
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(mic.starts, 1);
    expect(find.textContaining('Stop ·'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Ready.'), findsOneWidget);

    // Consent is required before converting.
    expect(tester.widget<FilledButton>(convert()).onPressed, isNull);
    await tester.tap(find.byKey(const Key('consent-checkbox')));
    await tester.pump();
    expect(tester.widget<FilledButton>(convert()).onPressed, isNotNull);

    await tester.tap(convert());
    await _pumpFor(tester);
    expect(spaces.calls, ['load_example', 'upload', 'upload', 'predict_1']);
    expect(find.byKey(const Key('converted-result')), findsOneWidget);
    final saved = app.localAudio.items.single;
    expect(saved.kind, 'converted');
    expect(saved.seconds, closeTo(1.5, 0.01));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Live screen never offers a fake start button', (tester) async {
    await _startApp(tester);
    await tester.tap(find.text('లైవ్ వాయిస్ ఛేంజర్'));
    await _settleRoute(tester);
    final start = tester.widget<FilledButton>(find.byKey(const Key('live-start-button')));
    expect(start.onPressed, isNull);
    expect(find.textContaining('genuine streaming'), findsWidgets);
  });

  testWidgets('Telugu keyboard types vowels, signs and deletes one mark', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TeluguKeyboard(controller: controller)))),
    );
    await tester.tap(find.text('హల్లులు'));
    await tester.pump();
    await tester.tap(find.text('క'));
    await tester.tap(find.text('గుణింతాలు'));
    await tester.pump();
    await tester.tap(find.text('◌ా')); // ◌ా
    await tester.pump();
    expect(controller.text, 'కా');
    await tester.ensureVisible(find.byTooltip('Backspace'));
    await tester.pump();
    await tester.tap(find.byTooltip('Backspace'));
    expect(controller.text, 'క');
  });

  test('ApiClient turns server errors into readable exceptions', () async {
    final client = ApiClient(
      baseUrl: 'http://test',
      devUser: 'tester',
      httpClient: MockClient((req) async {
        expect(req.headers['X-Dev-User'], 'tester');
        return _json({
          'error': {'code': 'PROVIDER_NOT_CONFIGURED', 'message': 'Not configured yet.'},
        }, 503);
      }),
    );
    await expectLater(
      client.generateSpeech(text: 'నమస్కారం', voiceId: 'google-te-female-hd'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'PROVIDER_NOT_CONFIGURED')
          .having((e) => e.isProviderMissing, 'isProviderMissing', true)),
    );
  });

  test('Download links resolve against the server address', () {
    final client = ApiClient(baseUrl: 'http://10.0.2.2:8000');
    final uri = client.resolve('/api/audio/abc/file?exp=1&sig=xyz', download: true);
    expect(uri.toString(), startsWith('http://10.0.2.2:8000/api/audio/abc/file?'));
    expect(uri.queryParameters, {'exp': '1', 'sig': 'xyz', 'download': 'true'});
  });
}

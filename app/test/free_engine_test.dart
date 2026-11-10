import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telugu_ai_voice/core/cloning/clone_models.dart';
import 'package:telugu_ai_voice/core/cloning/clone_service.dart';
import 'package:telugu_ai_voice/core/cloning/time_stretch.dart';
import 'package:telugu_ai_voice/core/free/free_voice_engine.dart';
import 'package:telugu_ai_voice/core/free/gradio_space.dart';
import 'package:telugu_ai_voice/core/free/local_audio_store.dart';
import 'package:telugu_ai_voice/core/free/wav.dart';

Uint8List _wav(double seconds, {int rate = 24000}) => buildWav(
      WavInfo(audioFormat: 1, channels: 1, sampleRate: rate, bitsPerSample: 16, dataOffset: 44, dataLength: 0),
      Uint8List((rate * seconds).round() * 2)..fillRange(0, 10, 7),
    );

void main() {
  _cloningGroup();

  group('WAV helpers', () {
    test('reads the length of a WAV file', () {
      expect(wavSeconds(_wav(2.5)), closeTo(2.5, 1e-6));
      expect(wavSeconds(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('joins clips with a short pause', () {
      final joined = concatWavs([_wav(1), _wav(2)], gapSeconds: 0.25);
      final info = parseWav(joined)!;
      expect(info.sampleRate, 24000);
      expect(info.seconds, closeTo(3.25, 1e-6));
      expect(joined.sublist(44, 54), everyElement(7)); // first clip's samples come first
    });

    test('refuses clips in different formats', () {
      expect(() => concatWavs([_wav(1), _wav(1, rate: 16000)]), throwsArgumentError);
    });
  });

  group('Telugu text splitting', () {
    test('keeps short text in one piece', () {
      expect(splitForSpeech('  నమస్కారం!   మీరు ఎలా ఉన్నారు?  '), ['నమస్కారం! మీరు ఎలా ఉన్నారు?']);
    });

    test('breaks long text at sentence ends, never inside words', () {
      const sentence = 'మా డాక్టర్లు ప్రతి రోజు ఉదయం పది గంటల నుండి అందుబాటులో ఉంటారు.';
      final text = List.filled(12, sentence).join(' '); // about 720 characters
      final pieces = splitForSpeech(text, maxChunk: 150);
      expect(pieces.length, greaterThan(1));
      for (final p in pieces) {
        expect(p.length, lessThanOrEqualTo(150));
        expect(p.endsWith('.'), isTrue);
      }
      expect(pieces.join(' '), text);
    });

    test('splits an over-long sentence at spaces', () {
      final text = List.filled(80, 'తెలుగు').join(' ');
      final pieces = splitForSpeech(text, maxChunk: 100);
      expect(pieces.every((p) => p.length <= 100), isTrue);
      expect(pieces.join(' '), text);
    });

    test('empty text gives nothing to send', () {
      expect(splitForSpeech('   \n '), isEmpty);
    });
  });

  group('Gradio API', () {
    test('reads the result of a finished call', () {
      final out = GradioSpace.parseEvents(
        'event: generating\ndata: null\n\nevent: complete\ndata: [{"path": "/tmp/a.wav"}]\n\n',
        'Server',
      );
      expect(GradioSpace.pathOf(out.first), '/tmp/a.wav');
    });

    test('explains a used-up daily quota in plain words', () {
      expect(
        () => GradioSpace.parseEvents('event: error\ndata: "You have exceeded your GPU quota (60s left)."\n\n', 'Server'),
        throwsA(isA<FreeEngineException>().having((e) => e.message, 'message', contains("today's free limit"))),
      );
    });

    test('a sleeping or busy server gives a retry message', () async {
      final space = GradioSpace(
        'https://x.hf.space',
        name: 'Server',
        client: MockClient((_) async => http.Response('starting', 503)),
      );
      await expectLater(
        space.call('anything', const []),
        throwsA(isA<FreeEngineException>().having((e) => e.message, 'message', contains('try again'))),
      );
    });

    test('no internet gives a clear message', () async {
      final space = GradioSpace(
        'https://x.hf.space',
        name: 'Server',
        client: MockClient((req) async => throw http.ClientException('Failed host lookup', req.url)),
      );
      await expectLater(
        space.upload(Uint8List(4), 'a.wav'),
        throwsA(isA<FreeEngineException>().having((e) => e.message, 'message', contains('No internet'))),
      );
    });
  });

  group('Hugging Face account', () {
    test('the token goes with every request to the voice servers', () async {
      final auth = <String?>[];
      final engine = FreeVoiceEngine(client: MockClient((req) async {
        auth.add(req.headers['Authorization']);
        if (req.url.path == '/gradio_api/upload') return http.Response('["/tmp/x.wav"]', 200);
        if (req.method == 'POST') return http.Response('{"event_id":"e1"}', 200);
        if (req.url.path.startsWith('/gradio_api/call/')) {
          return http.Response('event: complete\ndata: [{"path": "/tmp/o.wav"}]\n\n', 200);
        }
        return http.Response.bytes(_wav(1), 200);
      }));
      engine.token = 'hf_abcdefghijklmnopqrstuvwxyz';
      await engine.synthesizeWithSample('నమస్కారం', _wav(6), 'నమస్కారం');
      expect(auth, hasLength(4)); // upload, call, result, download
      expect(auth.every((a) => a == 'Bearer hf_abcdefghijklmnopqrstuvwxyz'), isTrue);
      engine.token = null;
      auth.clear();
      await engine.synthesizeWithSample('నమస్కారం', _wav(6), 'నమస్కారం');
      expect(auth.every((a) => a == null), isTrue);
    });

    test('checks the token with Hugging Face', () async {
      final engine = FreeVoiceEngine(client: MockClient((req) async {
        expect(req.url.toString(), 'https://huggingface.co/api/whoami-v2');
        if (req.headers['Authorization'] == 'Bearer hf_goodgoodgoodgoodgood') {
          return http.Response('{"type":"user","name":"samba","isPro":false}', 200);
        }
        return http.Response('{"error":"Invalid credentials"}', 401);
      }));
      final account = await engine.checkToken(' hf_goodgoodgoodgoodgood ');
      expect(account.name, 'samba');
      expect(account.dailyRequests, 5);
      await expectLater(engine.checkToken('hf_badbadbadbadbadbadbad'), throwsA(isA<FreeEngineException>()));
      await expectLater(engine.checkToken('not-a-token'), throwsA(isA<FreeEngineException>()));
    });

    test('a used-up allowance points to Settings, or to PRO when signed in', () {
      expect(
        GradioSpace.friendlyError('null', 'Server'),
        contains('add your free Hugging Face account in Settings'),
      );
      expect(GradioSpace.friendlyError('null', 'Server', signedIn: true), contains('PRO'));
    });
  });

  group('Free engine limits', () {
    test('refuses recordings longer than a minute before uploading anything', () async {
      var requests = 0;
      final engine = FreeVoiceEngine(client: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }));
      await expectLater(
        engine.convert(_wav(75, rate: 8000), 'long.wav', FreeVoice.female1),
        throwsA(isA<FreeEngineException>()),
      );
      expect(requests, 0);
    });

    test('voices are offered for both genders', () {
      expect(FreeVoice.forGender('female'), hasLength(2));
      expect(FreeVoice.forGender('male'), hasLength(1));
    });
  });

  test('memory store keeps newest first and deletes', () async {
    final store = LocalAudioStore.memory();
    final a = await store.add(_wav(1), title: 'one', kind: 'tts');
    final b = await store.add(_wav(2), title: 'two', kind: 'converted');
    expect(store.items.map((i) => i.title), ['two', 'one']);
    expect(a.id, isNot(b.id));
    expect(await store.bytesOf(b), hasLength(44 + 24000 * 2 * 2));
    await store.delete(b);
    expect(store.items.single.title, 'one');
  });
}

// ---- Voice cloning on the phone ---------------------------------------------------------

Uint8List _tone(double seconds, {int rate = 24000}) {
  final n = (rate * seconds).round();
  final data = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = (8000 * math.sin(2 * math.pi * 180 * i / rate)).round();
    data.setInt16(i * 2, v, Endian.little);
  }
  return buildWav(
    WavInfo(audioFormat: 1, channels: 1, sampleRate: rate, bitsPerSample: 16, dataOffset: 44, dataLength: 0),
    data.buffer.asUint8List(),
  );
}

MockClient _space(List<String> calls) => MockClient((req) async {
      final path = req.url.path;
      if (path == '/gradio_api/upload') {
        calls.add('upload');
        return http.Response('["/tmp/gradio/up/sample.wav"]', 200);
      }
      if (req.method == 'POST' && path.startsWith('/gradio_api/call/')) {
        calls.add(path.split('/').last);
        return http.Response('{"event_id":"e1"}', 200);
      }
      if (path.startsWith('/gradio_api/call/')) {
        return http.Response('event: complete\ndata: [{"path": "/tmp/gradio/out/audio.wav"}]\n\n', 200);
      }
      if (path.startsWith('/gradio_api/file=')) return http.Response.bytes(_wav(1.2), 200);
      return http.Response('', 404);
    });

const _consent = ConsentRecord(relationship: 'self', statement: 'This is my own voice.');

void _cloningGroup() {
  group('Speed control (WSOLA)', () {
    test('faster and slower keep the format and change the length', () {
      final input = _tone(2.0);
      final fast = parseWav(timeStretchWav(input, 1.5))!;
      final slow = parseWav(timeStretchWav(input, 0.75))!;
      expect(fast.sampleRate, 24000);
      expect(fast.seconds, closeTo(2.0 / 1.5, 0.08));
      expect(slow.seconds, closeTo(2.0 / 0.75, 0.08));
      expect(identical(timeStretchWav(input, 1.0), input), isTrue);
    });
  });

  group('LocalCloneService', () {
    test('records once, saves the voice, speaks any text, deletes', () async {
      final calls = <String>[];
      final store = LocalAudioStore.memory();
      final service = LocalCloneService(store: store, engine: FreeVoiceEngine(client: _space(calls)), persist: false);

      await expectLater(
        service.createVoice(
          name: 'Me', category: 'male', recordingLanguage: 'te', sample: _tone(2), filename: 'a.wav',
          transcript: 'నమస్కారం', consent: _consent,
        ),
        throwsA(isA<CloneException>().having((e) => e.message, 'message', contains('at least 5'))),
      );

      final profile = await service.createVoice(
        name: ' Me ', category: 'male', recordingLanguage: 'te', sample: _tone(8), filename: 'a.wav',
        transcript: 'నమస్కారం, ఇది నా స్వరం.', consent: _consent, makePreview: true,
      );
      expect(profile.name, 'Me');
      expect(profile.ready, isTrue);
      expect(profile.preview, isNotNull);
      expect(profile.consent['confirmed'], isTrue);
      expect(service.profiles, hasLength(1));
      expect(store.items, isEmpty); // samples and previews are not listed in History

      final item = await service.speak(profile: profile, text: 'आप कैसे हैं?', language: 'hi');
      expect(item.kind, 'clone');
      expect(item.detail, contains('Hindi'));
      expect(service.history.single.id, item.id);
      expect(calls.where((c) => c == 'upload'), hasLength(2)); // the sample goes with each request

      await expectLater(
        service.speak(profile: profile, text: 'Hello', language: 'en'),
        throwsA(isA<CloneException>()),
      );

      await service.deleteVoice(profile);
      expect(service.profiles, isEmpty);
      await service.deleteGeneration(item);
      expect(service.history, isEmpty);
    });

    test('a busy server still saves the voice, with a warning', () async {
      final store = LocalAudioStore.memory();
      final busy = MockClient((req) async => http.Response('starting', 503));
      final service = LocalCloneService(store: store, engine: FreeVoiceEngine(client: busy), persist: false);
      final profile = await service.createVoice(
        name: 'Me', category: 'female', recordingLanguage: 'te', sample: _tone(6), filename: 'a.wav',
        transcript: 'నమస్కారం', consent: _consent, makePreview: true,
      );
      expect(profile.preview, isNull);
      expect(profile.warning, contains('preview could not be made'));
      expect(service.profiles, hasLength(1));
    });

    test('without a preview, saving a voice makes no requests', () async {
      final calls = <String>[];
      final service = LocalCloneService(
        store: LocalAudioStore.memory(),
        engine: FreeVoiceEngine(client: _space(calls)),
        persist: false,
      );
      final profile = await service.createVoice(
        name: 'Me', category: 'female', recordingLanguage: 'te', sample: _tone(6), filename: 'a.wav',
        transcript: 'నమస్కారం', consent: _consent,
      );
      expect(profile.preview, isNull);
      expect(calls, isEmpty);
    });

    test('languages: script detection and the free engine list', () {
      expect(CloneLanguage.byCode('te').matches('నమస్కారం'), isTrue);
      expect(CloneLanguage.byCode('te').matches('नमस्ते'), isFalse);
      expect(CloneLanguage.all, hasLength(12));
      expect(CloneProviderInfo.indicF5OnPhone.languages, isNot(contains('en')));
    });
  });
}

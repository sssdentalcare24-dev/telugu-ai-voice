import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telugu_ai_voice/core/free/free_voice_engine.dart';
import 'package:telugu_ai_voice/core/free/gradio_space.dart';
import 'package:telugu_ai_voice/core/free/local_audio_store.dart';
import 'package:telugu_ai_voice/core/free/wav.dart';

Uint8List _wav(double seconds, {int rate = 24000}) => buildWav(
      WavInfo(audioFormat: 1, channels: 1, sampleRate: rate, bitsPerSample: 16, dataOffset: 44, dataLength: 0),
      Uint8List((rate * seconds).round() * 2)..fillRange(0, 10, 7),
    );

void main() {
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

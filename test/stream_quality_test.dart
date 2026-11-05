import 'package:flutter_test/flutter_test.dart';
import 'package:topo_tv/api/tapo_cloud.dart';

void main() {
  test('HD asks for the main stream', () {
    expect(StreamQuality.hd.resolution, 'HD');
    expect(StreamQuality.hd.streamType, 0);
  });

  test('low quality asks for something other than HD', () {
    expect(StreamQuality.low.resolution, isNot('HD'));
  });

  group('withQualityFallback', () {
    test('a rejected low stream falls back to HD', () async {
      final asked = <StreamQuality>[];
      final result = await withQualityFallback(StreamQuality.low, (q) async {
        asked.add(q);
        if (q == StreamQuality.low) throw TapoException('rejected', code: -1);
        return 'ok';
      });
      expect(result, 'ok');
      expect(asked, [StreamQuality.low, StreamQuality.hd]);
    });

    test('an offline camera is not asked twice', () async {
      for (final code in [-40401, -40406]) {
        var calls = 0;
        await expectLater(
          withQualityFallback(StreamQuality.low, (q) async {
            calls++;
            throw TapoException('Camera is offline', code: code);
          }),
          throwsA(isA<TapoException>()),
        );
        expect(calls, 1);
      }
    });

    test('network errors and expired sessions are not retried in HD', () async {
      for (final error in [TapoException('no network'), TapoException('expired', code: -20651)]) {
        var calls = 0;
        await expectLater(
          withQualityFallback(StreamQuality.low, (q) async {
            calls++;
            throw error;
          }),
          throwsA(isA<TapoException>()),
        );
        expect(calls, 1);
      }
    });

    test('a rejected HD stream is not retried', () async {
      var calls = 0;
      await expectLater(
        withQualityFallback(StreamQuality.hd, (q) async {
          calls++;
          throw TapoException('rejected', code: -1);
        }),
        throwsA(isA<TapoException>()),
      );
      expect(calls, 1);
    });
  });
}

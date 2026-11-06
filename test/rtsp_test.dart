import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matapo/api/rtsp_probe.dart';
import 'package:matapo/api/tapo_cloud.dart' show StreamQuality;
import 'package:matapo/state/app_state.dart';
import 'package:matapo/state/local_cameras.dart';

/// A tiny RTSP server that asks for Digest (or Basic) and accepts one account.
class _FakeCamera {
  _FakeCamera._(this._server, this.user, this.password, this.basic);

  static Future<_FakeCamera> start({String user = 'admin', String password = 'secreto', bool basic = false}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final camera = _FakeCamera._(server, user, password, basic);
    server.listen(camera._handle);
    return camera;
  }

  final ServerSocket _server;
  final String user;
  final String password;
  final bool basic;
  static const realm = 'IP Camera';
  static const nonce = 'abc123nonce';
  final requests = <String>[];

  int get port => _server.port;

  void _handle(Socket socket) {
    var buffer = '';
    socket.listen((data) {
      buffer += latin1.decode(data);
      while (buffer.contains('\r\n\r\n')) {
        final end = buffer.indexOf('\r\n\r\n');
        final head = buffer.substring(0, end);
        buffer = buffer.substring(end + 4);
        socket.add(latin1.encode(_respond(head)));
      }
    });
  }

  String _respond(String head) {
    final lines = head.split('\r\n');
    final [method, uri, _] = lines.first.split(' ');
    requests.add(method);
    final headers = {
      for (final l in lines.skip(1))
        if (l.contains(':')) l.substring(0, l.indexOf(':')).toLowerCase(): l.substring(l.indexOf(':') + 1).trim(),
    };
    final cseq = headers['cseq'];
    if (method == 'OPTIONS') return 'RTSP/1.0 200 OK\r\nCSeq: $cseq\r\nPublic: OPTIONS, DESCRIBE\r\n\r\n';
    final auth = headers['authorization'];
    if (auth != null && _valid(auth, method, uri)) {
      const sdp = 'v=0\r\nm=video 0 RTP/AVP 96\r\n';
      return 'RTSP/1.0 200 OK\r\nCSeq: $cseq\r\nContent-Type: application/sdp\r\n'
          'Content-Length: ${sdp.length}\r\n\r\n$sdp';
    }
    final challenge = basic ? 'Basic realm="$realm"' : 'Digest realm="$realm", nonce="$nonce", stale="FALSE"';
    return 'RTSP/1.0 401 Unauthorized\r\nCSeq: $cseq\r\nWWW-Authenticate: $challenge\r\n\r\n';
  }

  bool _valid(String auth, String method, String uri) {
    if (basic) return auth == 'Basic ${base64.encode(utf8.encode('$user:$password'))}';
    final c = parseAuthChallenge(auth)!;
    return c.params['username'] == user &&
        c.params['uri'] == uri &&
        c.params['response'] ==
            digestResponse(username: user, password: password, realm: realm, nonce: nonce, method: method, uri: uri);
  }

  Future<void> close() => _server.close();
}

Camera _camera(String id) => Camera({'deviceId': id, 'alias': id});

void main() {
  group('rtspUrl', () {
    const cam = LocalCamera(ip: '192.168.0.50', username: 'mi@user');

    test('HD is stream1 and low is stream2', () {
      expect(rtspUrl(cam, 'pw', StreamQuality.hd), 'rtsp://mi%40user:pw@192.168.0.50:554/stream1');
      expect(rtspUrl(cam, 'pw', StreamQuality.low), endsWith(':554/stream2'));
    });

    test('special characters in the account are percent-encoded', () {
      final url = rtspUrl(const LocalCamera(ip: '10.0.0.2', port: 8554, username: 'a:b'), 'p@ss/w:rd #1', StreamQuality.hd);
      expect(url, 'rtsp://a%3Ab:p%40ss%2Fw%3Ard%20%231@10.0.0.2:8554/stream1');
      final parsed = Uri.parse(url);
      expect(parsed.host, '10.0.0.2');
      expect(parsed.port, 8554);
      expect(Uri.decodeComponent(parsed.userInfo.split(':')[1]), 'p@ss/w:rd #1');
    });

    test('IPv6 addresses get brackets', () {
      expect(rtspBareUrl(const LocalCamera(ip: 'fe80::1', username: 'u'), StreamQuality.hd), 'rtsp://[fe80::1]:554/stream1');
    });

    test('settings survive JSON without the password', () {
      const c = LocalCamera(ip: '192.168.1.9', port: 8554, username: 'cam');
      final json = c.toJson();
      expect(json.keys, unorderedEquals(['ip', 'port', 'username']));
      expect(LocalCamera.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>), c);
    });

    test('form validation', () {
      expect(validateLocalCamera(ip: '', port: '554', username: 'u'), isNotNull);
      expect(validateLocalCamera(ip: '192.168.0.5', port: '70000', username: 'u'), isNotNull);
      expect(validateLocalCamera(ip: '192.168.0.5', port: '554', username: ''), isNotNull);
      expect(validateLocalCamera(ip: ' 192.168.0.5 ', port: '554', username: 'u'), isNull);
    });
  });

  group('Digest', () {
    test('matches the RFC 2617 example', () {
      expect(
        digestResponse(
          username: 'Mufasa',
          password: 'Circle Of Life',
          realm: 'testrealm@host.com',
          nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
          method: 'GET',
          uri: '/dir/index.html',
          qop: 'auth',
          nc: '00000001',
          cnonce: '0a4f113b',
        ),
        '6629fae49393a05397450978507c4ef1',
      );
    });

    test('Authorization header answers the challenge', () {
      final challenge = parseAuthChallenge(
        'Digest realm="testrealm@host.com", qop="auth,auth-int", '
        'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"',
      )!;
      final header = challenge.authorization(
        username: 'Mufasa',
        password: 'Circle Of Life',
        method: 'GET',
        uri: '/dir/index.html',
        cnonce: '0a4f113b',
      );
      final sent = parseAuthChallenge(header)!;
      expect(sent.scheme, 'digest');
      expect(sent.params['response'], '6629fae49393a05397450978507c4ef1');
      expect(sent.params['qop'], 'auth');
      expect(sent.params['nc'], '00000001');
      expect(sent.params['opaque'], '5ccc069c403ebaf9f0171e9517f40e41');
    });
  });

  group('WWW-Authenticate', () {
    test('Digest with quoted values and commas', () {
      final c = parseAuthChallenge('Digest realm="IP, Camera", nonce="n0", stale=FALSE')!;
      expect(c.isDigest, isTrue);
      expect(c.params, {'realm': 'IP, Camera', 'nonce': 'n0', 'stale': 'FALSE'});
    });

    test('Basic', () {
      final c = parseAuthChallenge('Basic realm="cam"')!;
      expect(c.isBasic, isTrue);
      expect(c.params['realm'], 'cam');
      expect(c.authorization(username: 'u', password: 'p', method: 'DESCRIBE', uri: 'x'), 'Basic dTpw');
    });

    test('Digest is preferred over Basic', () {
      expect(pickChallenge(['Basic realm="a"', 'Digest realm="b", nonce="c"'])!.isDigest, isTrue);
      expect(pickChallenge(['Basic realm="a"'])!.isBasic, isTrue);
      expect(pickChallenge(['Negotiate']), isNull);
    });
  });

  group('probeRtsp against a fake camera', () {
    test('right account: ok (Digest)', () async {
      final fake = await _FakeCamera.start();
      addTearDown(fake.close);
      final result = await probeRtsp(LocalCamera(ip: '127.0.0.1', port: fake.port, username: 'admin'), 'secreto');
      expect(result.status, RtspProbeStatus.ok);
      expect(fake.requests, ['OPTIONS', 'DESCRIBE', 'DESCRIBE']);
    });

    test('right account: ok (Basic)', () async {
      final fake = await _FakeCamera.start(basic: true);
      addTearDown(fake.close);
      final result = await probeRtsp(LocalCamera(ip: '127.0.0.1', port: fake.port, username: 'admin'), 'secreto');
      expect(result.status, RtspProbeStatus.ok);
    });

    test('wrong password: badCredentials', () async {
      final fake = await _FakeCamera.start();
      addTearDown(fake.close);
      final result = await probeRtsp(LocalCamera(ip: '127.0.0.1', port: fake.port, username: 'admin'), 'otra');
      expect(result.status, RtspProbeStatus.badCredentials);
      expect(result.message, 'Usuario o contraseña incorrectos');
    });

    test('nothing listening: unreachable', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final result = await probeRtsp(LocalCamera(ip: '127.0.0.1', port: port, username: 'admin'), 'x');
      expect(result.status, RtspProbeStatus.unreachable);
      expect(result.message, 'No responde en esa IP');
    });

    test('a silent server times out as unreachable', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((_) {});
      final result = await probeRtsp(
        LocalCamera(ip: '127.0.0.1', port: server.port, username: 'admin'),
        'x',
        timeout: const Duration(milliseconds: 300),
      );
      expect(result.status, RtspProbeStatus.unreachable);
    });
  });

  group('pickSource', () {
    const cam = LocalCamera(ip: '192.168.0.50', username: 'admin');

    AppState appWith(RtspProbeStatus status, List<String> calls) {
      final app = AppState()
        ..probe = (c, pw, {timeout = const Duration(seconds: 1)}) async {
          calls.add(pw);
          return RtspProbeResult(status);
        };
      app.debugSetLocal('cam1', cam, 'pw');
      return app;
    }

    test('camera answers locally: local RTSP', () async {
      final calls = <String>[];
      final app = appWith(RtspProbeStatus.ok, calls);
      final (source, url) = await app.pickSource(_camera('cam1'), StreamQuality.low);
      expect(source, StreamSource.local);
      expect(url, 'rtsp://admin:pw@192.168.0.50:554/stream2');
      // The good result is cached: a grid doesn't probe again.
      await app.pickSource(_camera('cam1'), StreamQuality.hd);
      expect(calls, ['pw']);
    });

    test('unreachable: cloud, and no probing again right away', () async {
      final calls = <String>[];
      final app = appWith(RtspProbeStatus.unreachable, calls);
      final (source, url) = await app.pickSource(_camera('cam1'), StreamQuality.hd);
      expect(source, StreamSource.cloud);
      expect(url, startsWith('http://127.0.0.1:'));
      await app.pickSource(_camera('cam1'), StreamQuality.hd);
      expect(calls, hasLength(1));
    });

    test('blocked after a failed local session: cloud without probing', () async {
      final calls = <String>[];
      final app = appWith(RtspProbeStatus.ok, calls)..blockLocal('cam1');
      final (source, _) = await app.pickSource(_camera('cam1'), StreamQuality.hd);
      expect(source, StreamSource.cloud);
      expect(calls, isEmpty);
    });

    test('no local settings: cloud without probing', () async {
      final calls = <String>[];
      final app = appWith(RtspProbeStatus.ok, calls);
      final (source, _) = await app.pickSource(_camera('other'), StreamQuality.hd);
      expect(source, StreamSource.cloud);
      expect(calls, isEmpty);
    });

    test('simultaneous starts share one probe', () async {
      final calls = <String>[];
      final gate = Completer<void>();
      final app = AppState()
        ..probe = (c, pw, {timeout = const Duration(seconds: 1)}) async {
          calls.add(pw);
          await gate.future;
          return const RtspProbeResult(RtspProbeStatus.ok);
        };
      app.debugSetLocal('cam1', cam, 'pw');
      final a = app.pickSource(_camera('cam1'), StreamQuality.low);
      final b = app.pickSource(_camera('cam1'), StreamQuality.low);
      gate.complete();
      expect((await a).$1, StreamSource.local);
      expect((await b).$1, StreamSource.local);
      expect(calls, hasLength(1));
    });
  });
}

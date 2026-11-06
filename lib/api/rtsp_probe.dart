import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../state/local_cameras.dart';
import 'tapo_cloud.dart' show StreamQuality;

enum RtspProbeStatus { ok, badCredentials, unreachable, otherError }

class RtspProbeResult {
  const RtspProbeResult(this.status, [this.detail]);
  final RtspProbeStatus status;

  /// What went wrong, for [RtspProbeStatus.otherError].
  final String? detail;

  bool get ok => status == RtspProbeStatus.ok;

  /// Short Spanish text for the "Probar" button result.
  String get message => switch (status) {
        RtspProbeStatus.ok => 'Conectada',
        RtspProbeStatus.badCredentials => 'Usuario o contraseña incorrectos',
        RtspProbeStatus.unreachable => 'No responde en esa IP',
        RtspProbeStatus.otherError => 'La cámara respondió con un error${detail == null ? '' : ': $detail'}',
      };

  @override
  String toString() => 'RtspProbeResult($status${detail == null ? '' : ', $detail'})';
}

/// Signature of [probeRtsp], so tests can swap in a fake.
typedef RtspProber = Future<RtspProbeResult> Function(LocalCamera camera, String password, {Duration timeout});

/// Checks that the camera answers RTSP on the home network and accepts the
/// camera account, without starting a player: `OPTIONS`, then `DESCRIBE`
/// of the HD stream, answering a Digest (or Basic) challenge if there is
/// one. Used by the "Probar" button and to choose between local video and
/// the cloud before a stream starts.
Future<RtspProbeResult> probeRtsp(
  LocalCamera camera,
  String password, {
  Duration timeout = const Duration(milliseconds: 2500),
}) async {
  final session = _RtspSession(camera);
  try {
    return await _probe(session, camera, password).timeout(timeout);
  } on TimeoutException {
    return const RtspProbeResult(RtspProbeStatus.unreachable);
  } on SocketException {
    return const RtspProbeResult(RtspProbeStatus.unreachable);
  } on _RtspClosed {
    return const RtspProbeResult(RtspProbeStatus.unreachable);
  } on FormatException catch (e) {
    return RtspProbeResult(RtspProbeStatus.otherError, e.message);
  } catch (e) {
    return RtspProbeResult(RtspProbeStatus.otherError, '$e');
  } finally {
    session.close();
  }
}

Future<RtspProbeResult> _probe(_RtspSession session, LocalCamera camera, String password) async {
  final url = rtspBareUrl(camera, StreamQuality.hd);
  // Some cameras want OPTIONS first; its answer is not needed.
  await session.request('OPTIONS', url);
  var response = await session.request('DESCRIBE', url, headers: {'Accept': 'application/sdp'});
  if (response.status == 401) {
    final challenge = pickChallenge(response.headers['www-authenticate'] ?? const []);
    if (challenge == null) return const RtspProbeResult(RtspProbeStatus.badCredentials);
    final authorization = challenge.authorization(
      username: camera.username,
      password: password,
      method: 'DESCRIBE',
      uri: url,
    );
    response = await session.request(
      'DESCRIBE',
      url,
      headers: {'Accept': 'application/sdp', 'Authorization': authorization},
    );
    if (response.status == 401) return const RtspProbeResult(RtspProbeStatus.badCredentials);
  }
  if (response.status == 200) return const RtspProbeResult(RtspProbeStatus.ok);
  return RtspProbeResult(RtspProbeStatus.otherError, '${response.status} ${response.reason}'.trim());
}

class RtspResponse {
  RtspResponse(this.status, this.reason, this.headers);
  final int status;
  final String reason;

  /// Lower-case header names; a header can appear more than once.
  final Map<String, List<String>> headers;
}

class _RtspClosed implements Exception {}

/// One RTSP/1.0 control connection. It reconnects once if the camera closes
/// it between requests (some do after a 401).
class _RtspSession {
  _RtspSession(this.camera);
  final LocalCamera camera;

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _buffer = BytesBuilder();
  Completer<void>? _wake;
  bool _closed = false;
  bool _disposed = false;
  int _cseq = 0;

  Future<void> _connect() async {
    final socket = await Socket.connect(camera.ip, camera.port, timeout: const Duration(seconds: 5));
    if (_disposed) {
      // The probe timed out while connecting.
      socket.destroy();
      throw _RtspClosed();
    }
    _socket = socket;
    _closed = false;
    _buffer.clear();
    _subscription = socket.listen(
      (data) {
        _buffer.add(data);
        _wake?.complete();
        _wake = null;
      },
      onDone: () {
        _closed = true;
        _wake?.complete();
        _wake = null;
      },
      onError: (Object _) {
        _closed = true;
        _wake?.complete();
        _wake = null;
      },
      cancelOnError: true,
    );
  }

  Future<RtspResponse> request(String method, String url, {Map<String, String> headers = const {}}) async {
    if (_socket == null || _closed) {
      await _disconnect();
      await _connect();
    }
    final text = StringBuffer('$method $url RTSP/1.0\r\n')
      ..write('CSeq: ${++_cseq}\r\n')
      ..write('User-Agent: Matapo\r\n');
    headers.forEach((k, v) => text.write('$k: $v\r\n'));
    text.write('\r\n');
    _socket!.add(utf8.encode(text.toString()));
    await _socket!.flush();
    return _readResponse();
  }

  Future<RtspResponse> _readResponse() async {
    while (true) {
      final bytes = _buffer.toBytes();
      final end = _indexOf(bytes, const [13, 10, 13, 10]);
      if (end >= 0) {
        final head = latin1.decode(bytes.sublist(0, end));
        final response = parseRtspHead(head);
        final length = int.tryParse(response.headers['content-length']?.first ?? '') ?? 0;
        final total = end + 4 + length;
        if (bytes.length >= total) {
          _buffer
            ..clear()
            ..add(bytes.sublist(total));
          return response;
        }
      }
      if (_closed) throw _RtspClosed();
      final wake = _wake = Completer<void>();
      await wake.future;
    }
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
  }

  void close() {
    _disposed = true;
    _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
  }
}

int _indexOf(List<int> data, List<int> pattern) {
  outer:
  for (var i = 0; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Parses the status line and headers of an RTSP response.
RtspResponse parseRtspHead(String head) {
  final lines = head.split('\r\n');
  final status = RegExp(r'^RTSP/\d\.\d\s+(\d{3})\s*(.*)$').firstMatch(lines.first.trim());
  if (status == null) throw FormatException('No es una respuesta RTSP: ${lines.first}');
  final headers = <String, List<String>>{};
  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    headers.putIfAbsent(line.substring(0, colon).trim().toLowerCase(), () => []).add(line.substring(colon + 1).trim());
  }
  return RtspResponse(int.parse(status.group(1)!), status.group(2)!.trim(), headers);
}

/// One `WWW-Authenticate` challenge: its scheme and parameters.
class AuthChallenge {
  AuthChallenge(this.scheme, this.params);

  /// Lower case: `digest` or `basic`.
  final String scheme;

  /// Lower-case parameter names, unquoted values.
  final Map<String, String> params;

  bool get isDigest => scheme == 'digest';
  bool get isBasic => scheme == 'basic';

  /// The `Authorization` header value answering this challenge.
  String authorization({
    required String username,
    required String password,
    required String method,
    required String uri,
    String? cnonce,
  }) {
    if (isBasic) return 'Basic ${base64.encode(utf8.encode('$username:$password'))}';
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'] ?? '';
    final qops = (params['qop'] ?? '').split(',').map((q) => q.trim().toLowerCase());
    final qop = qops.contains('auth') ? 'auth' : null;
    final nc = '00000001';
    final client = cnonce ?? _randomCnonce();
    final response = digestResponse(
      username: username,
      password: password,
      realm: realm,
      nonce: nonce,
      method: method,
      uri: uri,
      qop: qop,
      nc: nc,
      cnonce: client,
    );
    final parts = [
      'username="${_quote(username)}"',
      'realm="${_quote(realm)}"',
      'nonce="${_quote(nonce)}"',
      'uri="$uri"',
      'response="$response"',
      if (params['algorithm'] != null) 'algorithm=${params['algorithm']}',
      if (params['opaque'] != null) 'opaque="${_quote(params['opaque']!)}"',
      if (qop != null) ...['qop=$qop', 'nc=$nc', 'cnonce="$client"'],
    ];
    return 'Digest ${parts.join(', ')}';
  }
}

String _quote(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _randomCnonce() {
  final rng = Random.secure();
  return List.generate(8, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

String _md5(String s) => md5.convert(utf8.encode(s)).toString();

/// The Digest `response` value (RFC 2617, MD5), with or without `qop=auth`.
String digestResponse({
  required String username,
  required String password,
  required String realm,
  required String nonce,
  required String method,
  required String uri,
  String? qop,
  String nc = '00000001',
  String cnonce = '',
}) {
  final ha1 = _md5('$username:$realm:$password');
  final ha2 = _md5('$method:$uri');
  if (qop == null) return _md5('$ha1:$nonce:$ha2');
  return _md5('$ha1:$nonce:$nc:$cnonce:$qop:$ha2');
}

/// Parses one `WWW-Authenticate` header value, e.g.
/// `Digest realm="IP Camera", nonce="abc", stale="FALSE"` or
/// `Basic realm="x"`. Returns null when it can't be read.
AuthChallenge? parseAuthChallenge(String header) {
  final value = header.trim();
  final space = value.indexOf(RegExp(r'\s'));
  final scheme = (space < 0 ? value : value.substring(0, space)).toLowerCase();
  if (scheme.isEmpty) return null;
  final params = <String, String>{};
  final rest = space < 0 ? '' : value.substring(space + 1);
  var i = 0;
  while (i < rest.length) {
    while (i < rest.length && (rest[i] == ',' || rest[i].trim().isEmpty)) {
      i++;
    }
    final eq = rest.indexOf('=', i);
    if (eq < 0) break;
    final name = rest.substring(i, eq).trim().toLowerCase();
    i = eq + 1;
    final buffer = StringBuffer();
    if (i < rest.length && rest[i] == '"') {
      i++;
      while (i < rest.length && rest[i] != '"') {
        if (rest[i] == r'\' && i + 1 < rest.length) i++;
        buffer.write(rest[i]);
        i++;
      }
      i++; // closing quote
    } else {
      while (i < rest.length && rest[i] != ',') {
        buffer.write(rest[i]);
        i++;
      }
    }
    if (name.isNotEmpty) params[name] = buffer.toString().trim();
  }
  return AuthChallenge(scheme, params);
}

/// Picks the challenge to answer: Digest when offered, else Basic.
AuthChallenge? pickChallenge(List<String> headers) {
  final challenges = headers.map(parseAuthChallenge).whereType<AuthChallenge>().toList();
  for (final c in challenges) {
    if (c.isDigest) return c;
  }
  for (final c in challenges) {
    if (c.isBasic) return c;
  }
  return null;
}

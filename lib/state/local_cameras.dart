import '../api/tapo_cloud.dart' show StreamQuality;

/// Where a camera's video comes from: straight from the camera on the home
/// network (RTSP), or through TP-Link's cloud relay.
enum StreamSource { local, cloud }

/// A camera's address and camera account on the home network, for RTSP.
///
/// The password is not part of this object: it lives in the platform's
/// secure storage (Keychain on macOS, encrypted storage on Android).
class LocalCamera {
  const LocalCamera({required this.ip, this.port = defaultPort, required this.username});

  static const defaultPort = 554;

  final String ip;
  final int port;
  final String username;

  Map<String, dynamic> toJson() => {'ip': ip, 'port': port, 'username': username};

  factory LocalCamera.fromJson(Map<String, dynamic> json) => LocalCamera(
        ip: '${json['ip'] ?? ''}'.trim(),
        port: (json['port'] as num?)?.toInt() ?? defaultPort,
        username: '${json['username'] ?? ''}',
      );

  /// `ip:port` for RTSP URLs, with brackets around IPv6 addresses.
  String get authority => ip.contains(':') ? '[$ip]:$port' : '$ip:$port';

  @override
  bool operator ==(Object other) =>
      other is LocalCamera && other.ip == ip && other.port == port && other.username == username;

  @override
  int get hashCode => Object.hash(ip, port, username);
}

/// Tapo cameras serve the main (HD) stream at `/stream1` and the low one at
/// `/stream2`.
String rtspPath(StreamQuality quality) => quality == StreamQuality.low ? '/stream2' : '/stream1';

/// The stream URL without credentials (for RTSP requests and Digest).
String rtspBareUrl(LocalCamera camera, StreamQuality quality) =>
    'rtsp://${camera.authority}${rtspPath(quality)}';

/// The URL handed to the player, with the camera account in the userinfo.
/// User and password are percent-encoded, since they may contain `@`, `:`
/// or `/`; mpv (ffmpeg) and ExoPlayer decode them again.
String rtspUrl(LocalCamera camera, String password, StreamQuality quality) =>
    'rtsp://${Uri.encodeComponent(camera.username)}:${Uri.encodeComponent(password)}'
    '@${camera.authority}${rtspPath(quality)}';

/// Checks the form fields; returns an error message, or null when valid.
String? validateLocalCamera({required String ip, required String port, required String username}) {
  final host = ip.trim();
  if (host.isEmpty) return 'Ingresá la IP de la cámara';
  if (host.contains(RegExp(r'[\s/@?#]'))) return 'La IP no es válida';
  final p = int.tryParse(port.trim());
  if (p == null || p < 1 || p > 65535) return 'El puerto tiene que ser un número entre 1 y 65535';
  if (username.isEmpty) return 'Ingresá el usuario de la cuenta de la cámara';
  return null;
}

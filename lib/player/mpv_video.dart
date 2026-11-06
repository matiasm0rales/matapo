import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Live video on macOS: libmpv through media_kit, playing the relay's
/// MPEG-TS stream from `RelayBridge`. (AVPlayer only plays HLS, not a plain
/// progressive TS stream.)
///
/// Mirrors LivePlayer.kt on Android and reports the same events to
/// [onEvent], so LiveVideo handles both platforms the same way:
/// `firstFrame`, `size`, `snapshot` and at most one `error` per session.
/// One widget is one stream session: a new key means a new connection.
class MpvVideo extends StatefulWidget {
  const MpvVideo({super.key, required this.url, required this.snapshotPath, required this.onEvent});
  final String url;
  final String? snapshotPath;
  final void Function(Map<String, dynamic>) onEvent;

  @override
  State<MpvVideo> createState() => _MpvVideoState();

  /// Shuts down every libmpv player before the app quits.
  ///
  /// Otherwise mpv's core thread keeps calling into Dart while Flutter tears
  /// the engine down, and the app crashes on the way out (SIGABRT in
  /// `DLRT_GetFfiCallbackMetadata`, called from
  /// `mp_client_send_property_changes`). Disposing clears that callback and
  /// destroys the mpv handle first.
  static Future<void> disposeAll() => _MpvVideoState.disposeAll();
}

class _MpvVideoState extends State<MpvVideo> {
  /// A picture that hasn't moved this long is reported as an error, so the
  /// Flutter side reconnects instead of showing a frozen frame forever.
  static const _stallAfter = Duration(seconds: 10);
  static const _snapshotEvery = Duration(seconds: 20);

  /// Live camera preview: start on the first GOP and never build up delay.
  /// mpv must not reconnect on its own either: a reopened relay is a new
  /// session, and Flutter replaces the whole player for it (as on Android).
  static const _options = [
    ('cache', 'no'),
    ('cache-pause', 'no'),
    ('demuxer-lavf-o', 'fflags=+nobuffer'),
    ('demuxer-lavf-analyzeduration', '1'),
    // Tapo relays carry a second, unidentified stream (type 0x90) whose
    // parameters ffmpeg never finds, so it reads up to the default 5 MB
    // before starting: about two minutes at a camera's bitrate. 64 KB is
    // enough to find the H.264 stream in about 2 s.
    ('demuxer-lavf-probesize', '65536'),
    ('video-latency-hacks', 'yes'),
    ('aid', 'no'),
    ('network-timeout', '30'),
  ];

  /// Players on screen. The Mac doesn't sleep or start the screensaver while
  /// any is open, since it's used as an unattended camera monitor.
  static int _awake = 0;

  /// Every player that hasn't been disposed yet, for [disposeAll].
  static final _live = <Player>{};

  static Future<void> disposeAll() async {
    final players = _live.toList();
    _live.clear();
    await Future.wait(players.map((p) => p.dispose().catchError((Object _) {})));
  }

  late final Player _player;
  late final VideoController _controller;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _stallTimer;
  Timer? _latencyTimer;
  Timer? _snapshotTimer;
  bool _released = false;
  bool _failed = false;
  bool _speedUp = false;
  bool _checkingLatency = false;
  int _width = 0;
  int _height = 0;
  Duration _lastPosition = Duration.zero;
  DateTime _lastMovedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (_awake++ == 0) WakelockPlus.enable().ignore();
    _player = Player(
      configuration: const PlayerConfiguration(muted: true, bufferSize: 4 * 1024 * 1024),
    );
    _live.add(_player);
    _controller = VideoController(_player);
    _subscriptions
      ..add(_player.stream.error.listen(_onError))
      ..add(_player.stream.completed.listen((done) {
        if (done) _fail('Stream ended');
      }))
      ..add(_player.stream.width.listen((w) => _onSize(w, _height)))
      ..add(_player.stream.height.listen((h) => _onSize(_width, h)));
    _open();
  }

  Future<void> _open() async {
    final native = _player.platform;
    if (native is NativePlayer) {
      for (final (name, value) in _options) {
        try {
          await native.setProperty(name, value);
        } catch (_) {
          // An option this mpv build doesn't know; play without it.
        }
      }
    }
    if (_released) return;
    await _player.open(Media(widget.url), play: true);
    _latencyTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _checkLatency());
    await _controller.waitUntilFirstFrameRendered;
    if (_released || _failed) return;
    _emit({'state': 'firstFrame'});
    _lastPosition = _player.state.position;
    _lastMovedAt = DateTime.now();
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkStall());
    _snapshotTimer = Timer(const Duration(milliseconds: 1500), _snapshot);
  }

  void _emit(Map<String, dynamic> event) {
    if (!_released) widget.onEvent(event);
  }

  /// Reports at most one error per session; Flutter then replaces this view.
  void _fail(String message) {
    if (_failed || _released) return;
    _failed = true;
    _emit({'state': 'error', 'message': message});
  }

  /// mpv also logs recoverable decoder errors (a damaged frame, a missing
  /// reference at the start of the stream). Only an error that left the
  /// player without a stream (e.g. the relay answered 502) ends the session.
  Future<void> _onError(String message) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_released || _failed) return;
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      if (await native.getProperty('idle-active') == 'yes') _fail(message);
    } catch (_) {}
  }

  void _onSize(int? width, int? height) {
    final w = width ?? 0, h = height ?? 0;
    if (w == _width && h == _height) return;
    _width = w;
    _height = h;
    if (w > 0 && h > 0) _emit({'state': 'size', 'width': w, 'height': h});
  }

  void _checkStall() {
    if (_released || _failed) return;
    final position = _player.state.position;
    final now = DateTime.now();
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastMovedAt = now;
    } else if (now.difference(_lastMovedAt) > _stallAfter) {
      debugPrint('MatapoPlayer: no new frame for ${_stallAfter.inSeconds} s, reconnecting');
      _fail('Video stopped');
    }
  }

  /// The relay is an unbounded live file, so there is no live edge to seek
  /// to. Play slightly faster while more than ~1.5 s is buffered to drain
  /// accumulated delay (same thresholds as on Android).
  Future<void> _checkLatency() async {
    final native = _player.platform;
    if (_released || _checkingLatency || native is! NativePlayer) return;
    _checkingLatency = true;
    try {
      final ahead = double.tryParse(await native.getProperty('demuxer-cache-duration'));
      if (ahead == null || _released) return;
      if (!_speedUp && ahead > 1.5) {
        _speedUp = true;
        await _player.setRate(1.25);
      } else if (_speedUp && ahead < 0.6) {
        _speedUp = false;
        await _player.setRate(1.0);
      }
    } catch (_) {
      // Not available until the demuxer is running.
    } finally {
      _checkingLatency = false;
    }
  }

  /// Saves a JPEG of the current frame so the app can show the last picture
  /// instantly next time, while the stream is still connecting.
  Future<void> _snapshot() async {
    final path = widget.snapshotPath;
    if (_released || path == null) return;
    try {
      final bytes = await _player.screenshot(format: 'image/jpeg');
      if (bytes != null && !_released) {
        final tmp = File('$path.tmp');
        await tmp.parent.create(recursive: true);
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(path);
        _emit({'state': 'snapshot'});
      }
    } catch (_) {}
    if (!_released) _snapshotTimer = Timer(_snapshotEvery, _snapshot);
  }

  @override
  void dispose() {
    _released = true;
    _stallTimer?.cancel();
    _latencyTimer?.cancel();
    _snapshotTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    if (_live.remove(_player)) _player.dispose();
    if (--_awake == 0) WakelockPlus.disable().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Never focusable and never takes clicks: focus and taps stay with the
    // camera card around it, as with the Android view.
    return ExcludeFocus(
      child: IgnorePointer(
        child: Video(
          controller: _controller,
          controls: NoVideoControls,
          fill: Colors.transparent,
          wakelock: false,
        ),
      ),
    );
  }
}

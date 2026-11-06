import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../api/tapo_cloud.dart' show StreamQuality;
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/tv.dart' show KeyCap;
import 'android_video.dart';
import 'mpv_video.dart';
import 'stream_queue.dart';

enum LiveState { connecting, playing, retrying, failed }

/// Live camera video with connection state, auto-retry and error display.
class LiveVideo extends StatefulWidget {
  const LiveVideo({
    super.key,
    required this.app,
    required this.camera,
    this.compact = false,
    this.queued = true,
    this.onStateChanged,
    this.onSourceChanged,
  });

  final AppState app;
  final Camera camera;

  /// Compact = grid thumbnail: low-resolution stream, smaller texts, no long
  /// error explanations.
  final bool compact;

  /// Wait for a [StreamQueue] slot before connecting (lists and grids).
  /// The full-screen live view starts at once.
  final bool queued;
  final ValueChanged<LiveState>? onStateChanged;

  /// Called when a stream session picks local (RTSP) or cloud video.
  final ValueChanged<StreamSource>? onSourceChanged;

  @override
  State<LiveVideo> createState() => LiveVideoState();
}

class LiveVideoState extends State<LiveVideo> {
  /// Increments for every connection attempt; null while disconnected.
  int? _session;
  int _sessions = 0;
  LiveState _state = LiveState.connecting;
  String? _error;
  double _aspect = 16 / 9;
  int _failures = 0;
  Timer? _retryTimer;
  Timer? _stallTimer;
  bool _disposed = false;
  StreamTicket? _ticket;

  /// Source and URL of the current session, chosen in [_start].
  StreamSource? _source;
  String? _url;

  /// Increments on every [_start]; an older start that is still waiting
  /// (queue or probe) stops when it sees a newer one.
  int _attempt = 0;

  /// [AppState.localVersion] when the current session started.
  int _localVersion = 0;

  /// True while waiting for this stream's turn in the [StreamQueue].
  bool _waiting = false;

  /// A camera that shows no picture this long after its first connection
  /// attempt (retries included) is given up on for [autoRetryAfter], so it
  /// stops using a stream slot but still comes back on its own.
  static const giveUpAfter = Duration(seconds: 25);

  /// Monitors run unattended, so a camera or connection that comes back
  /// must recover without anyone pressing Retry.
  static const autoRetryAfter = Duration(seconds: 60);
  DateTime? _firstAttemptAt;

  LiveState get state => _state;
  bool get failed => _state == LiveState.failed;

  /// Where the current (or last) session's video comes from.
  StreamSource? get source => _source;

  /// Manual retry: skips the queue, since the user asked for this camera.
  void retry() => restart(skipQueue: true);

  @override
  void initState() {
    super.initState();
    _waiting = widget.queued;
    _start();
  }

  @override
  void didUpdateWidget(LiveVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camera.deviceId != widget.camera.deviceId ||
        widget.app.localVersion(widget.camera.deviceId) != _localVersion) {
      // Another camera, or its local settings were just changed.
      restart(resetFailures: true);
    }
  }

  void _setState(LiveState s, {String? error}) {
    if (_disposed) return;
    setState(() {
      _state = s;
      _error = error;
    });
    widget.onStateChanged?.call(s);
  }

  Future<void> _start({bool skipQueue = false}) async {
    final attempt = ++_attempt;
    _localVersion = widget.app.localVersion(widget.camera.deviceId);
    _stallTimer?.cancel();
    _releaseTicket();
    if (widget.queued && !skipQueue) {
      final ticket = _ticket = StreamQueue.instance.request();
      // initState sets _waiting itself; setState is only for restarts.
      if (!_waiting) setState(() => _waiting = true);
      await ticket.ready;
      // Superseded by a restart, or the view went away while waiting.
      if (_disposed || !identical(_ticket, ticket) || attempt != _attempt) {
        ticket.release();
        return;
      }
      setState(() => _waiting = false);
    } else if (_waiting) {
      setState(() => _waiting = false);
    }
    if (_disposed) return;
    final started = _firstAttemptAt ??= DateTime.now();
    final left = giveUpAfter - DateTime.now().difference(started);
    _stallTimer = Timer(left.isNegative ? Duration.zero : left, () {
      if (_state != LiveState.playing) _giveUp('La cámara no respondió a tiempo');
    });
    // Local video when the camera answers on the home network, else cloud.
    final (source, url) = await widget.app.pickSource(
      widget.camera,
      widget.compact ? StreamQuality.low : StreamQuality.hd,
    );
    if (_disposed || attempt != _attempt) return;
    final changed = source != _source;
    setState(() {
      _source = source;
      _url = url;
      _session = ++_sessions;
    });
    if (changed) widget.onSourceChanged?.call(source);
  }

  void _releaseTicket() {
    _ticket?.release();
    _ticket = null;
  }

  void _onEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    switch (event['state']) {
      case 'firstFrame':
        _releaseTicket();
        _failures = 0;
        _firstAttemptAt = null;
        _stallTimer?.cancel();
        _setState(LiveState.playing);
      case 'size':
        final w = (event['width'] as num).toDouble(), h = (event['height'] as num).toDouble();
        if (w > 0 && h > 0 && mounted) setState(() => _aspect = w / h);
      case 'snapshot':
        Snapshots.instance.updated(widget.camera.deviceId);
      case 'error':
        if (_source == StreamSource.local) {
          _fallBackToCloud('${event['message'] ?? ''}');
          return;
        }
        final relayError = widget.app.relay.lastErrors[widget.camera.deviceId];
        _onFailure(relayError ?? '${event['message'] ?? 'Se cortó la transmisión'}');
    }
  }

  /// A local (RTSP) session failed, e.g. away from home or the camera's
  /// stream limit: switch to the cloud at once. It doesn't count as a
  /// failure, so the camera isn't reported as not responding because of
  /// the home network.
  void _fallBackToCloud(String reason) {
    debugPrint('Matapo: local video for ${widget.camera.deviceId} failed ($reason), using the cloud');
    widget.app.blockLocal(widget.camera.deviceId);
    _stallTimer?.cancel();
    _retryTimer?.cancel();
    _releaseTicket();
    _releaseTexture();
    _firstAttemptAt = null;
    _setState(LiveState.retrying, error: 'No se pudo conectar en la red local; usando la nube');
    _start();
  }

  void _onFailure(String message) {
    if (_disposed) return;
    _stallTimer?.cancel();
    _releaseTicket();
    _releaseTexture();
    _failures++;
    final backoff = Duration(seconds: 2 * _failures);
    final started = _firstAttemptAt ?? DateTime.now();
    if (_failures > 3 || DateTime.now().difference(started) + backoff >= giveUpAfter) {
      _giveUp(message);
      return;
    }
    _setState(LiveState.retrying, error: message);
    _retryTimer?.cancel();
    _retryTimer = Timer(backoff, () {
      if (!_disposed) {
        _setState(LiveState.connecting);
        _start();
      }
    });
  }

  /// Pauses trying; the overlay offers a Retry button, and it tries again by
  /// itself after [autoRetryAfter].
  void _giveUp(String message) {
    _stallTimer?.cancel();
    _retryTimer?.cancel();
    _releaseTicket();
    _releaseTexture();
    _setState(LiveState.failed, error: message);
    _retryTimer = Timer(autoRetryAfter, () {
      if (!_disposed) restart();
    });
  }

  void _releaseTexture() {
    if (_session != null && mounted) setState(() => _session = null);
  }

  /// Reconnect from scratch (e.g. after privacy mode is turned off).
  void restart({bool resetFailures = true, bool skipQueue = false}) {
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _releaseTexture();
    if (resetFailures) {
      _failures = 0;
      _firstAttemptAt = null;
    }
    _setState(LiveState.connecting);
    _start(skipQueue: skipQueue);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _releaseTicket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return ColoredBox(
      color: MatapoColors.media,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (session != null)
            Center(
              child: AspectRatio(
                aspectRatio: _aspect,
                child: _surface(session),
              ),
            ),
          if (_state != LiveState.playing) _overlay(context),
        ],
      ),
    );
  }

  /// The platform video view for one stream session; both report the same
  /// events (firstFrame, size, snapshot, error) to [_onEvent].
  Widget _surface(int session) {
    final url = _url!;
    final snapshotPath = Snapshots.instance.pathFor(widget.camera.deviceId);
    if (Platform.isMacOS) {
      return MpvVideo(key: ValueKey(session), url: url, snapshotPath: snapshotPath, onEvent: _onEvent);
    }
    return AndroidVideo(key: ValueKey(session), url: url, snapshotPath: snapshotPath, onEvent: _onEvent);
  }

  Widget _overlay(BuildContext context) {
    final compact = widget.compact;
    final failed = _state == LiveState.failed;
    final text = switch (_state) {
      _ when _waiting => compact ? 'En espera' : 'Esperando a que carguen las otras cámaras…',
      LiveState.connecting => compact
          ? 'Conectando'
          : switch (_source) {
              StreamSource.local => 'Conectando con la cámara en tu red…',
              StreamSource.cloud => 'Conectando con la cámara por la nube de Tapo…',
              null => 'Conectando con la cámara…',
            },
      LiveState.retrying => 'Reconectando…',
      LiveState.failed => compact ? 'No responde' : 'La cámara no respondió',
      LiveState.playing => '',
    };
    const soft = Color(0xFFC9D3DC);
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (failed)
          Icon(Icons.videocam_off_rounded, color: soft, size: compact ? 26 : 48)
        else
          SizedBox(
            width: compact ? 22 : 36,
            height: compact ? 22 : 36,
            child: const CircularProgressIndicator(strokeWidth: 3, color: MatapoColors.onMedia),
          ),
        SizedBox(height: compact ? 8 : 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: MatapoColors.onMedia, fontSize: compact ? 16 : 22, fontWeight: FontWeight.w600),
        ),
        if (failed) ...[
          SizedBox(height: compact ? 10 : 18),
          // OK on the card or screen triggers this; it's also clickable.
          GestureDetector(
            onTap: retry,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 6 : 10),
              decoration: BoxDecoration(
                color: MatapoColors.primaryAction,
                borderRadius: BorderRadius.circular(MatapoRadius.full),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KeyCap('OK', onMedia: true),
                  const SizedBox(width: 8),
                  Text(
                    'Reintentar',
                    style: TextStyle(color: MatapoColors.onMedia, fontSize: compact ? 15 : 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (!compact && !failed && _error != null && _state != LiveState.connecting) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: soft, fontSize: 16),
            ),
          ),
        ],
      ],
    );
    final taken = snapshotTime(widget.camera.deviceId);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: MatapoColors.media,
          child: SnapshotView(
            deviceId: widget.camera.deviceId,
            fit: compact ? BoxFit.cover : BoxFit.contain,
            fallback: const SizedBox.expand(),
          ),
        ),
        if (compact && taken != null && !failed)
          // The last frame stays clear; a small chip says what's happening.
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: MatapoColors.media.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(MatapoRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: MatapoColors.onMedia),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: const TextStyle(color: MatapoColors.onMedia, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            color: MatapoColors.media.withValues(alpha: taken != null ? 0.55 : 0.85),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: taken == null
                ? status
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    decoration: BoxDecoration(
                      color: MatapoColors.media.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(MatapoRadius.lg),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        status,
                        if (!compact) ...[
                          const SizedBox(height: 8),
                          Text('Mostrando la última imagen de las $taken', style: const TextStyle(color: soft, fontSize: 15)),
                        ],
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}

/// Small "Local" / "Nube" label: whether a camera's video comes straight
/// from the camera on the home network or through the cloud. Text and icon,
/// never color alone.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source, this.onMedia = false, this.large = false});
  final StreamSource source;

  /// On top of video or a dark bar (white text), instead of a light card.
  final bool onMedia;

  /// TV size.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final local = source == StreamSource.local;
    final background = local
        ? MatapoColors.success
        : onMedia
            ? Colors.white.withValues(alpha: 0.18)
            : const Color(0xFFE6EBF0);
    final foreground = local || onMedia ? Colors.white : const Color(0xFF4A5661);
    final size = large ? 14.0 : 11.0;
    return Semantics(
      label: local ? 'Video local' : 'Video por la nube',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 9 : 6, vertical: large ? 4 : 2),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(large ? 6 : 4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(local ? Icons.home_rounded : Icons.cloud_rounded, size: size + 1, color: foreground),
            SizedBox(width: large ? 5 : 3),
            Text(
              local ? 'Local' : 'Nube',
              style: TextStyle(color: foreground, fontSize: size, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/tapo_cloud.dart' show TapoException;
import '../main.dart' show AppScope;
import '../player/live_player.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import 'desktop_cameras.dart' show togglePrivacy;
import 'desktop_theme.dart';

Future<void> openDesktopLive(BuildContext context, int index) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => DesktopLiveScreen(initialIndex: index),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// One camera filling the window. Controls appear while the mouse moves and
/// hide (with the pointer) after a few seconds.
class DesktopLiveScreen extends StatefulWidget {
  const DesktopLiveScreen({super.key, required this.initialIndex});
  final int initialIndex;

  @override
  State<DesktopLiveScreen> createState() => _DesktopLiveScreenState();
}

class _DesktopLiveScreenState extends State<DesktopLiveScreen> {
  late int _index = widget.initialIndex;
  final _focus = FocusNode(debugLabel: 'desktop-live');
  int _reconnects = 0;
  LiveState _liveState = LiveState.connecting;
  StreamSource? _source;

  bool _controls = true;
  bool _overControls = false;
  Timer? _hideTimer;

  // Pan/tilt: one request in flight; while busy only the latest direction
  // is kept, so holding a direction moves continuously without overshoot.
  bool _moving = false;
  (int, int)? _pendingMove;
  Timer? _holdTimer;
  DateTime _lastError = DateTime(2000);

  AppState get _app => AppScope.read(context);

  Camera? get _camera {
    final cams = _app.cameras;
    if (cams.isEmpty) return null;
    return cams[_index.clamp(0, cams.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _bump();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _refreshState();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _holdTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _refreshState() {
    final camera = _camera;
    if (camera != null) _app.refreshCameraState(camera);
  }

  /// Shows the controls and restarts the hide countdown.
  void _bump() {
    if (!_controls) setState(() => _controls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_overControls) setState(() => _controls = false);
    });
  }

  void _switchCamera(int delta) {
    final count = _app.cameras.length;
    if (count < 2) return;
    _goTo((_index + delta) % count);
  }

  void _goTo(int index) {
    if (index < 0 || index >= _app.cameras.length || index == _index) return;
    setState(() {
      _index = index;
      _liveState = LiveState.connecting;
      _source = null;
      _pendingMove = null;
    });
    _refreshState();
    _bump();
  }

  void _reconnect() {
    setState(() {
      _reconnects++;
      _liveState = LiveState.connecting;
    });
    final camera = _camera;
    if (camera != null) _app.refreshCameraState(camera, force: true);
  }

  Future<void> _move(int dx, int dy) async {
    final camera = _camera;
    if (camera == null) return;
    if (_moving) {
      _pendingMove = (dx, dy);
      return;
    }
    _moving = true;
    try {
      await _app.move(camera, dx, dy);
    } catch (e) {
      final now = DateTime.now();
      if (mounted && now.difference(_lastError) > const Duration(seconds: 2)) {
        _lastError = now;
        showDesktopMessage(context, e is TapoException ? e.message : e.toString(), error: true);
      }
      _pendingMove = null;
    } finally {
      _moving = false;
    }
    final pending = _pendingMove;
    _pendingMove = null;
    if (pending != null && mounted) await _move(pending.$1, pending.$2);
  }

  /// Pad button pressed: move now, then keep moving while held.
  void _startHold(int dx, int dy) {
    final step = _app.ptzStep;
    _move(dx * step, dy * step);
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 450), (_) => _move(dx * step, dy * step));
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    final camera = _camera;
    if (key == LogicalKeyboardKey.escape && !repeat) {
      DesktopWindow.isFullScreen().then((full) {
        if (full) {
          DesktopWindow.toggleFullScreen();
        } else if (mounted) {
          Navigator.of(context).maybePop();
        }
      });
      return KeyEventResult.handled;
    }
    if (!repeat && (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.bracketRight)) {
      _switchCamera(1);
      return KeyEventResult.handled;
    }
    if (!repeat && (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.bracketLeft)) {
      _switchCamera(-1);
      return KeyEventResult.handled;
    }
    if (!repeat && key == LogicalKeyboardKey.keyF) {
      DesktopWindow.toggleFullScreen();
      return KeyEventResult.handled;
    }
    final digit = int.tryParse(event.character ?? '');
    if (!repeat && digit != null && digit >= 1 && digit <= 9) {
      _goTo(digit - 1);
      return KeyEventResult.handled;
    }
    final dir = switch (key) {
      LogicalKeyboardKey.arrowLeft => (-1, 0),
      LogicalKeyboardKey.arrowRight => (1, 0),
      LogicalKeyboardKey.arrowUp => (0, 1),
      LogicalKeyboardKey.arrowDown => (0, -1),
      _ => null,
    };
    if (dir == null || camera == null) return KeyEventResult.ignored;
    if (camera.ptz == true && camera.privacy != true) {
      _move(dir.$1 * _app.ptzStep, dir.$2 * _app.ptzStep);
    } else if (!repeat && dir.$1 != 0) {
      _switchCamera(dir.$1);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final camera = _camera;
    if (camera == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }
    final privacy = camera.privacy == true;
    final canPtz = camera.ptz == true && !privacy;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _controls ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _bump(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _controls ? setState(() => _controls = false) : _bump(),
            onDoubleTap: DesktopWindow.toggleFullScreen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (privacy)
                  _PrivacyCover(onTurnOff: () => togglePrivacy(context, camera))
                else
                  LiveVideo(
                    key: ValueKey('${camera.deviceId}#$_reconnects'),
                    app: app,
                    camera: camera,
                    queued: false,
                    onStateChanged: (s) {
                      if (mounted) setState(() => _liveState = s);
                    },
                    onSourceChanged: (s) {
                      if (mounted) setState(() => _source = s);
                    },
                  ),
                // Top bar.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _Fade(
                    visible: _controls,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xCC000000), Color(0x00000000)],
                        ),
                      ),
                      child: Row(
                        children: [
                          MediaIconButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Volver (Esc)',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 14),
                          if (_liveState == LiveState.playing && !privacy) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: MatapoColors.error, borderRadius: BorderRadius.circular(4)),
                              child: const Text('EN VIVO',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 6),
                            if (_source != null) ...[
                              SourceChip(source: _source!, onMedia: true),
                              const SizedBox(width: 10),
                            ] else
                              const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              camera.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (camera.model.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(camera.model, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                          const Spacer(),
                          Text(
                            'Cámara ${_index + 1} de ${app.cameras.length}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom controls.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: Center(
                    child: _Fade(
                      visible: _controls,
                      child: MouseRegion(
                        onEnter: (_) => _overControls = true,
                        onExit: (_) {
                          _overControls = false;
                          _bump();
                        },
                        child: _ControlBar(
                          canPtz: canPtz,
                          privacy: privacy,
                          privacyKnown: camera.privacy != null,
                          step: app.ptzStep,
                          multiple: app.cameras.length > 1,
                          onPrevious: () => _switchCamera(-1),
                          onNext: () => _switchCamera(1),
                          onPrivacy: () => togglePrivacy(context, camera),
                          onReconnect: _reconnect,
                          onStep: app.setPtzStep,
                          onHold: _startHold,
                          onRelease: _stopHold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades a control layer and stops it from taking clicks while hidden.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: const Duration(milliseconds: 200), child: child),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.canPtz,
    required this.privacy,
    required this.privacyKnown,
    required this.step,
    required this.multiple,
    required this.onPrevious,
    required this.onNext,
    required this.onPrivacy,
    required this.onReconnect,
    required this.onStep,
    required this.onHold,
    required this.onRelease,
  });

  final bool canPtz;
  final bool privacy;
  final bool privacyKnown;
  final int step;
  final bool multiple;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPrivacy;
  final VoidCallback onReconnect;
  final ValueChanged<int> onStep;
  final void Function(int dx, int dy) onHold;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6101820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaIconButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Cámara anterior (Re Pág)',
            onPressed: multiple ? onPrevious : null,
          ),
          const SizedBox(width: 6),
          MediaIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Cámara siguiente (Av Pág)',
            onPressed: multiple ? onNext : null,
          ),
          const _Separator(),
          MediaIconButton(
            icon: privacy ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            tooltip: privacy ? 'Desactivar modo privacidad' : 'Activar modo privacidad',
            active: privacy,
            onPressed: privacyKnown ? onPrivacy : null,
          ),
          const SizedBox(width: 6),
          MediaIconButton(icon: Icons.refresh_rounded, tooltip: 'Reconectar', onPressed: onReconnect),
          if (canPtz) ...[
            const _Separator(),
            _PtzPad(onHold: onHold, onRelease: onRelease),
            const SizedBox(width: 10),
            _StepSelector(step: step, onStep: onStep),
          ],
          const _Separator(),
          const MediaIconButton(
            icon: Icons.fullscreen_rounded,
            tooltip: 'Pantalla completa (F)',
            onPressed: DesktopWindow.toggleFullScreen,
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 12), color: const Color(0x33FFFFFF));
}

/// Direction pad: press and hold to keep the camera moving.
class _PtzPad extends StatelessWidget {
  const _PtzPad({required this.onHold, required this.onRelease});
  final void Function(int dx, int dy) onHold;
  final VoidCallback onRelease;

  Widget _arrow(IconData icon, String tooltip, int dx, int dy) {
    return Tooltip(
      message: tooltip,
      child: Listener(
        onPointerDown: (_) => onHold(dx, dy),
        onPointerUp: (_) => onRelease(),
        onPointerCancel: (_) => onRelease(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrow(Icons.chevron_left_rounded, 'Girar a la izquierda (←)', -1, 0),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _arrow(Icons.expand_less_rounded, 'Subir (↑)', 0, 1),
            const SizedBox(height: 4),
            _arrow(Icons.expand_more_rounded, 'Bajar (↓)', 0, -1),
          ],
        ),
        const SizedBox(width: 4),
        _arrow(Icons.chevron_right_rounded, 'Girar a la derecha (→)', 1, 0),
      ],
    );
  }
}

class _StepSelector extends StatelessWidget {
  const _StepSelector({required this.step, required this.onStep});
  final int step;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cuánto se mueve la cámara por paso',
      child: PopupMenuButton<int>(
        initialValue: step,
        onSelected: onStep,
        color: Colors.white,
        itemBuilder: (_) => [
          for (final s in const [5, 10, 20]) PopupMenuItem(value: s, height: 32, child: Text('Paso de $s°')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$step°', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover({required this.onTurnOff});
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesktopColors.media,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off_outlined, color: Color(0xFFC9D3DC), size: 56),
            const SizedBox(height: 14),
            const Text('Modo privacidad activado',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('La cámara tiene el lente tapado y no transmite video.',
                style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 14)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onTurnOff,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Desactivar modo privacidad'),
            ),
          ],
        ),
      ),
    );
  }
}

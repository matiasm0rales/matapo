import 'package:flutter/material.dart';

import '../main.dart' show AppScope;
import '../player/live_player.dart';
import '../player/stream_queue.dart';
import '../screens/home_screen.dart' show cameraStatus;
import '../state/app_state.dart';
import 'desktop_live.dart';
import 'desktop_local_camera.dart';
import 'desktop_theme.dart';

/// Turns privacy mode on or off with progress and result messages.
Future<void> togglePrivacy(BuildContext context, Camera camera) async {
  final app = AppScope.read(context);
  final enable = !(camera.privacy ?? false);
  showDesktopMessage(context, enable ? 'Activando el modo privacidad…' : 'Desactivando el modo privacidad…');
  try {
    await app.setPrivacy(camera, enable);
    if (context.mounted) {
      showDesktopMessage(context, enable ? 'Modo privacidad activado' : 'Modo privacidad desactivado');
    }
  } catch (e) {
    if (context.mounted) showDesktopMessage(context, e.toString(), error: true);
  }
}

class CamerasSection extends StatefulWidget {
  const CamerasSection({super.key});

  @override
  State<CamerasSection> createState() => _CamerasSectionState();
}

class _CamerasSectionState extends State<CamerasSection> {
  final _videoKeys = <String, GlobalKey<LiveVideoState>>{};
  final _states = <String, LiveState>{};
  final _sources = <String, StreamSource>{};

  void _reconnect(Camera camera) {
    _videoKeys[camera.deviceId]?.currentState?.retry();
    AppScope.read(context).refreshCameraState(camera, force: true);
  }

  void _menu(Camera camera, int index, Offset position) {
    showContextMenu(context, position, [
      MenuAction('Ver en vivo', Icons.play_arrow_rounded, () => openDesktopLive(context, index)),
      null,
      MenuAction(
        camera.privacy == true ? 'Desactivar modo privacidad' : 'Activar modo privacidad',
        camera.privacy == true ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        camera.privacy == null ? null : () => togglePrivacy(context, camera),
      ),
      MenuAction('Reconectar', Icons.refresh_rounded, () => _reconnect(camera)),
      null,
      // Open previews restart by themselves when the settings change.
      MenuAction('Conexión local…', Icons.lan_outlined, () => showLocalCameraDialog(context, camera)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cameras = app.cameras;
    final active = app.foreground && TickerMode.valuesOf(context).enabled;
    if (cameras.isEmpty) return _EmptyCameras(app: app);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 380).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: (box.maxWidth - 48 - (columns - 1) * 16) / columns * 9 / 16 + 64,
          ),
          itemCount: cameras.length,
          itemBuilder: (context, i) {
            final camera = cameras[i];
            final key = _videoKeys.putIfAbsent(camera.deviceId, GlobalKey<LiveVideoState>.new);
            return _CameraCard(
              app: app,
              camera: camera,
              index: i,
              videoKey: key,
              showVideo: app.livePreviews && active,
              liveState: _states[camera.deviceId],
              source: _sources[camera.deviceId],
              onStateChanged: (s) {
                if (_states[camera.deviceId] != s) setState(() => _states[camera.deviceId] = s);
              },
              onSourceChanged: (s) {
                if (_sources[camera.deviceId] != s) setState(() => _sources[camera.deviceId] = s);
              },
              onOpen: () => openDesktopLive(context, i),
              onMenu: (pos) => _menu(camera, i, pos),
              onReconnect: () => _reconnect(camera),
            );
          },
        );
      },
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.app,
    required this.camera,
    required this.index,
    required this.videoKey,
    required this.showVideo,
    required this.liveState,
    required this.source,
    required this.onStateChanged,
    required this.onSourceChanged,
    required this.onOpen,
    required this.onMenu,
    required this.onReconnect,
  });

  final AppState app;
  final Camera camera;
  final int index;
  final GlobalKey<LiveVideoState> videoKey;
  final bool showVideo;
  final LiveState? liveState;
  final StreamSource? source;
  final ValueChanged<LiveState> onStateChanged;
  final ValueChanged<StreamSource> onSourceChanged;
  final VoidCallback onOpen;
  final void Function(Offset) onMenu;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = cameraStatus(camera, liveState, previews: showVideo);
    final privacy = camera.privacy == true;
    return HoverCard(
      onTap: onOpen,
      onSecondaryTap: onMenu,
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (privacy)
                  const _PrivacyPlaceholder()
                else if (showVideo)
                  LiveVideo(
                    key: videoKey,
                    app: app,
                    camera: camera,
                    compact: true,
                    onStateChanged: onStateChanged,
                    onSourceChanged: onSourceChanged,
                  )
                else
                  SnapshotView(
                    deviceId: camera.deviceId,
                    fallback: const ColoredBox(
                      color: DesktopColors.media,
                      child: Icon(Icons.videocam_outlined, color: Colors.white54, size: 36),
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xB3101820), borderRadius: BorderRadius.circular(6)),
                    child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                // Actions appear while the pointer is over the card.
                Positioned(
                  top: 8,
                  right: 8,
                  child: AnimatedOpacity(
                    opacity: hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: IgnorePointer(
                      ignoring: !hovered,
                      child: Row(
                        children: [
                          MediaIconButton(
                            icon: privacy ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            tooltip: privacy ? 'Desactivar modo privacidad' : 'Activar modo privacidad',
                            onPressed: camera.privacy == null ? null : () => togglePrivacy(context, camera),
                          ),
                          const SizedBox(width: 6),
                          MediaIconButton(icon: Icons.refresh_rounded, tooltip: 'Reconectar', onPressed: onReconnect),
                          const SizedBox(width: 6),
                          Builder(
                            builder: (context) => MediaIconButton(
                              icon: Icons.more_horiz_rounded,
                              tooltip: 'Más opciones',
                              onPressed: () {
                                final box = context.findRenderObject() as RenderBox;
                                onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(camera.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(icon, size: 10, color: color),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              [label, if (camera.model.isNotEmpty) camera.model].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (showVideo && !privacy && liveState == LiveState.playing && source != null) ...[
                            const SizedBox(width: 6),
                            SourceChip(source: source!),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (hovered) const Icon(Icons.open_in_full_rounded, size: 18, color: DesktopColors.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPlaceholder extends StatelessWidget {
  const _PrivacyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1B2733),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility_off_outlined, color: Color(0xFFC9D3DC), size: 32),
          SizedBox(height: 8),
          Text('Modo privacidad activado', style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 13)),
        ],
      ),
    );
  }
}

class _EmptyCameras extends StatelessWidget {
  const _EmptyCameras({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (app.loadingCameras) return const Center(child: CircularProgressIndicator());
    final error = app.camerasError;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(error != null ? Icons.cloud_off_rounded : Icons.videocam_off_outlined, size: 48, color: DesktopColors.secondary),
            const SizedBox(height: 12),
            Text(error != null ? 'No se pudieron cargar las cámaras' : 'Todavía no hay cámaras', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              error ?? 'Agregá cámaras con la app de Tapo en tu teléfono y después actualizá.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: DesktopColors.secondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: app.refreshCameras,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }
}

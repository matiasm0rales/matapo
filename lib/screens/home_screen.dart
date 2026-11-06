import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../main.dart';
import '../player/live_player.dart';
import '../player/stream_queue.dart';
import '../state/app_state.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';
import 'live_screen.dart';
import 'multiview_screen.dart';
import 'settings_screen.dart';

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadKeys = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// Maps number keys 1–9 to a zero-based index, or null.
int? digitIndex(LogicalKeyboardKey key) {
  final i = _digitKeys.indexOf(key);
  if (i >= 0) return i;
  final n = _numpadKeys.indexOf(key);
  return n >= 0 ? n : null;
}

/// Opens the full-screen live view for camera [index].
Future<void> openLive(BuildContext context, int index) async {
  final app = AppScope.read(context);
  if (index < 0 || index >= app.cameras.length) return;
  final previous = guideSection.value;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: MatapoMotion.navigation,
      pageBuilder: (_, _, _) => LiveScreen(initialIndex: index),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
  guideSection.value = previous;
}

enum HomeTab { cameras, multiview, settings }

/// Signed-in shell: a persistent top destination row and the active tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.cameras;
  bool _guideChecked = false;

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.home;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGuide());
  }

  Future<void> _maybeShowGuide() async {
    if (_guideChecked || !mounted) return;
    _guideChecked = true;
    final app = AppScope.read(context);
    if (!app.guideSeen) {
      await showRemoteGuide(context);
      await app.markGuideSeen();
    }
  }

  void _select(HomeTab tab) {
    setState(() => _tab = tab);
    guideSection.value = switch (tab) {
      HomeTab.cameras => GuideSection.home,
      HomeTab.multiview => GuideSection.multiview,
      HomeTab.settings => GuideSection.basics,
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Previews run while this page is visible: a full page on top (live
    // view, a grid) turns tickers off for it, a dialog does not.
    final active = app.foreground && TickerMode.valuesOf(context).enabled;
    return Scaffold(
      body: Padding(
        padding: tvSafePadding.copyWith(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusTraversalGroup(
              child: Row(
                children: [
                  Image.asset('assets/matapo.png', width: 40, height: 40, semanticLabel: 'Matapo'),
                  const SizedBox(width: MatapoSpace.sm),
                  const Text('Matapo', style: MatapoText.title),
                  const SizedBox(width: MatapoSpace.x2),
                  for (final (tab, label, icon) in const [
                    (HomeTab.cameras, 'Cámaras', Icons.videocam_rounded),
                    (HomeTab.multiview, 'Grillas', Icons.grid_view_rounded),
                    (HomeTab.settings, 'Ajustes', Icons.settings_rounded),
                  ]) ...[
                    _NavItem(label: label, icon: icon, selected: _tab == tab, onSelect: () => _select(tab)),
                    const SizedBox(width: MatapoSpace.sm),
                  ],
                  const Spacer(),
                  if (_tab == HomeTab.cameras) ...[
                    TvButton(
                      label: '',
                      semanticLabel: 'Actualizar cámaras',
                      icon: Icons.refresh_rounded,
                      busy: app.loadingCameras,
                      onPressed: app.refreshCameras,
                    ),
                    const SizedBox(width: MatapoSpace.sm),
                  ],
                  TvButton(
                    label: 'Guía',
                    icon: Icons.help_outline_rounded,
                    onPressed: () => showRemoteGuide(context, section: guideSection.value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MatapoSpace.lg),
            Expanded(
              child: FocusTraversalGroup(
                child: AnimatedSwitcher(
                  duration: MatapoMotion.navigation,
                  child: switch (_tab) {
                    HomeTab.cameras => CamerasPanel(key: const ValueKey('cameras'), active: active),
                    HomeTab.multiview => const MultiviewPanel(key: ValueKey('multiview')),
                    HomeTab.settings => const SettingsPanel(key: ValueKey('settings')),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top destination. Focus only outlines it; OK switches (no navigation on
/// focus). The active destination keeps its pale-blue surface.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.selected, required this.onSelect});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TvFocusable(
        onSelect: onSelect,
        builder: (context, focused) {
          final fg = selected ? MatapoColors.primaryPressed : MatapoColors.muted;
          return FocusRing(
            focused: focused,
            radius: MatapoRadius.full,
            child: AnimatedContainer(
              duration: MatapoMotion.focus,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: MatapoSpace.xl),
              decoration: BoxDecoration(
                color: selected ? MatapoColors.surfaceSelected : MatapoColors.surface,
                borderRadius: BorderRadius.circular(MatapoRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(width: MatapoSpace.sm),
                  Text(label, style: MatapoText.label.copyWith(color: fg)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The camera list: one card per camera with a live preview.
class CamerasPanel extends StatefulWidget {
  const CamerasPanel({super.key, required this.active});
  final bool active;

  @override
  State<CamerasPanel> createState() => _CamerasPanelState();
}

class _CamerasPanelState extends State<CamerasPanel> {
  final _videoKeys = <String, GlobalKey<LiveVideoState>>{};

  Future<void> _quickActions(Camera camera, int index) async {
    final app = AppScope.read(context);
    final privacy = camera.privacy;
    final action = await showTvDialog<String>(
      context,
      (context) => TvDialog(
        title: camera.name,
        message: camera.model,
        children: [
          TvTile(
            title: 'Ver en vivo',
            icon: Icons.play_arrow_rounded,
            autofocus: true,
            onSelect: () => Navigator.pop(context, 'live'),
          ),
          const SizedBox(height: MatapoSpace.md),
          TvTile(
            title: privacy == true ? 'Desactivar modo privacidad' : 'Activar modo privacidad',
            subtitle: privacy == null
                ? 'Consultando la cámara…'
                : privacy
                    ? 'El video vuelve a funcionar'
                    : 'Se tapa el lente y se corta el video',
            icon: privacy == true ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            onSelect: privacy == null ? null : () => Navigator.pop(context, 'privacy'),
          ),
          const SizedBox(height: MatapoSpace.md),
          TvTile(
            title: 'Reconectar la vista previa',
            icon: Icons.refresh_rounded,
            onSelect: () => Navigator.pop(context, 'reconnect'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'live':
        await openLive(context, index);
      case 'reconnect':
        _videoKeys[camera.deviceId]?.currentState?.restart();
        await app.refreshCameraState(camera, force: true);
      case 'privacy':
        final enable = !(privacy ?? false);
        showToast(context, enable ? 'Activando el modo privacidad…' : 'Desactivando el modo privacidad…', icon: Icons.hourglass_top_rounded);
        try {
          await app.setPrivacy(camera, enable);
          if (mounted) showToast(context, enable ? 'Modo privacidad activado' : 'Modo privacidad desactivado');
        } catch (e) {
          if (mounted) showToast(context, e.toString(), error: true);
        }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final index = digitIndex(event.logicalKey);
    if (index == null) return KeyEventResult.ignored;
    openLive(context, index);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cameras = app.cameras;
    final showVideo = app.livePreviews && widget.active;
    if (cameras.isEmpty) return _Empty(app: app);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomScrollView(
              // Build only what is on (or next to) the screen: cards scrolled
              // away stop streaming and show their last picture instead.
              scrollCacheExtent: const ScrollCacheExtent.pixels(300),
              slivers: [
                SliverPadding(
                  // Room for the focus outline and scale; never clip focus.
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, MatapoSpace.x2),
                  sliver: SliverToBoxAdapter(child: FavoriteGridCard(app: app, autofocus: true)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: MatapoSpace.cardGap,
                      crossAxisSpacing: MatapoSpace.cardGap,
                      childAspectRatio: 1.25,
                    ),
                    itemCount: cameras.length,
                    itemBuilder: (context, i) {
                      final camera = cameras[i];
                      return _CameraCard(
                        key: ValueKey(camera.deviceId),
                        app: app,
                        camera: camera,
                        number: i + 1,
                        showVideo: showVideo,
                        videoKey: _videoKeys.putIfAbsent(camera.deviceId, GlobalKey<LiveVideoState>.new),
                        onSelect: () => openLive(context, i),
                        onLongSelect: () => _quickActions(camera, i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MatapoSpace.sm),
          HintBar([
            (const KeyCap('OK'), 'Ver en vivo'),
            (const KeyCap('Mantené OK'), 'Acciones rápidas'),
            (const KeyCap('1–9'), 'Ir a una cámara'),
            (const KeyCap('', icon: Icons.menu_rounded), 'Guía del control'),
          ]),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final error = app.camerasError;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(gradient: featuredGradient, shape: BoxShape.circle, boxShadow: featuredShadow),
            child: Icon(error != null ? Icons.cloud_off_rounded : Icons.videocam_off_rounded, size: 44, color: MatapoColors.primary),
          ),
          const SizedBox(height: MatapoSpace.xl),
          Text(error != null ? 'No se pudieron cargar tus cámaras' : 'No hay cámaras en esta cuenta', style: MatapoText.headline),
          const SizedBox(height: MatapoSpace.sm),
          Text(
            error ?? 'Agregá cámaras con la app de Tapo en tu teléfono y después actualizá.',
            textAlign: TextAlign.center,
            style: MatapoText.body.copyWith(color: error != null ? MatapoColors.error : MatapoColors.muted),
          ),
          const SizedBox(height: MatapoSpace.x2),
          TvButton(
            label: error != null ? 'Reintentar' : 'Actualizar',
            icon: Icons.refresh_rounded,
            style: TvButtonStyle.primary,
            autofocus: true,
            busy: app.loadingCameras,
            onPressed: app.refreshCameras,
          ),
        ],
      ),
    );
  }
}

/// Camera status as text plus icon (never color alone).
(String, IconData, Color) cameraStatus(Camera camera, LiveState? live, {required bool previews}) {
  if (camera.privacy == true) return ('Privacidad activada', Icons.visibility_off_rounded, MatapoColors.muted);
  if (!previews) {
    final taken = snapshotTime(camera.deviceId);
    return (taken == null ? 'Lista' : 'Última imagen $taken', Icons.photo_camera_rounded, MatapoColors.muted);
  }
  return switch (live) {
    LiveState.playing => ('En vivo', Icons.circle, MatapoColors.success),
    LiveState.failed => ('No responde', Icons.error_outline_rounded, MatapoColors.error),
    LiveState.retrying => ('Reconectando', Icons.sync_rounded, MatapoColors.muted),
    _ => ('Conectando', Icons.sync_rounded, MatapoColors.muted),
  };
}

class _CameraCard extends StatefulWidget {
  const _CameraCard({
    super.key,
    required this.app,
    required this.camera,
    required this.number,
    required this.showVideo,
    required this.videoKey,
    required this.onSelect,
    required this.onLongSelect,
  });

  final AppState app;
  final Camera camera;
  final int number;
  final bool showVideo;
  final GlobalKey<LiveVideoState> videoKey;
  final VoidCallback onSelect;
  final VoidCallback onLongSelect;

  @override
  State<_CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<_CameraCard> {
  LiveState? _live;

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    final privacy = camera.privacy == true;
    final (status, statusIcon, statusColor) = cameraStatus(camera, _live, previews: widget.showVideo);
    return Semantics(
      button: true,
      label: '${widget.number}. ${camera.name}, $status',
      child: TvCard(
        onSelect: () {
          final video = widget.videoKey.currentState;
          if (video != null && video.failed) {
            video.retry();
          } else {
            widget.onSelect();
          }
        },
        onLongSelect: widget.onLongSelect,
        padding: const EdgeInsets.all(MatapoSpace.md),
        child: (focused) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MatapoRadius.sm),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (privacy)
                      const _Placeholder(icon: Icons.visibility_off_rounded, text: 'Modo privacidad activado')
                    else if (widget.showVideo)
                      LiveVideo(
                        key: widget.videoKey,
                        app: widget.app,
                        camera: camera,
                        compact: true,
                        onStateChanged: (s) => setState(() => _live = s),
                      )
                    else
                      SnapshotView(
                        deviceId: camera.deviceId,
                        fallback: const _Placeholder(icon: Icons.videocam_rounded, text: 'Presioná OK para ver'),
                      ),
                    Positioned(
                      left: MatapoSpace.sm,
                      top: MatapoSpace.sm,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: MatapoColors.surface, borderRadius: BorderRadius.circular(MatapoRadius.sm)),
                        child: Text(
                          '${widget.number}',
                          style: const TextStyle(color: MatapoColors.primaryPressed, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MatapoSpace.sm),
            Text(camera.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MatapoText.label),
            Row(
              children: [
                Icon(statusIcon, size: status == 'En vivo' ? 10 : 16, color: statusColor),
                const SizedBox(width: 6),
                Text(status, style: MatapoText.caption.copyWith(color: statusColor == MatapoColors.muted ? MatapoColors.muted : statusColor)),
                Expanded(
                  child: Text(
                    [' · ${camera.model}', if (camera.ptz == true) 'Movimiento'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatapoText.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: featuredGradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: MatapoColors.primary, size: 32),
            const SizedBox(height: MatapoSpace.sm),
            Text(text, style: MatapoText.caption),
          ],
        ),
      );
}

/// Picks the grid pinned to the home page. Returns the chosen id, '' to
/// unpin, or null when cancelled.
Future<void> chooseFavoriteGrid(BuildContext context) async {
  final app = AppScope.read(context);
  final current = app.favoriteGridId;
  final picked = await showTvDialog<String>(
    context,
    (context) => TvDialog(
      title: 'Grilla favorita',
      message: 'Fijada arriba en el inicio para abrirla con un botón.',
      children: [
        for (final grid in app.grids) ...[
          TvTile(
            title: grid.name,
            subtitle: '${grid.cameraCount} cámaras · ${grid.layout.label}',
            icon: Icons.grid_view_rounded,
            selected: grid.id == current,
            autofocus: grid.id == current || (current == null && grid.isAuto),
            onSelect: () => Navigator.pop(context, grid.id),
          ),
          const SizedBox(height: MatapoSpace.md),
        ],
        if (current != null)
          TvTile(
            title: 'Quitar del inicio',
            icon: Icons.star_outline_rounded,
            danger: true,
            onSelect: () => Navigator.pop(context, ''),
          ),
      ],
    ),
  );
  if (picked == null) return;
  await app.setFavoriteGrid(picked.isEmpty ? null : picked);
  if (context.mounted) {
    showToast(context, picked.isEmpty ? 'Quitada del inicio' : 'Fijada en el inicio', icon: Icons.star_rounded);
  }
}

/// Home-page card for the favourite grid: last pictures of its cameras
/// (no live streams, so the home page stays light), OK opens the grid.
class FavoriteGridCard extends StatelessWidget {
  const FavoriteGridCard({super.key, required this.app, this.autofocus = false});
  final AppState app;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final grid = app.favoriteGrid;
    if (grid == null) {
      return Semantics(
        button: true,
        label: 'Agregá una grilla favorita',
        child: TvCard(
          autofocus: autofocus,
          onSelect: () => chooseFavoriteGrid(context),
          padding: const EdgeInsets.symmetric(horizontal: MatapoSpace.xl, vertical: MatapoSpace.lg),
          child: (focused) => const Row(
            children: [
              Icon(Icons.star_outline_rounded, color: MatapoColors.primaryAction, size: 32),
              SizedBox(width: MatapoSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Agregá una grilla favorita', style: MatapoText.label),
                    Text('Fijá una grilla acá para abrirla con un botón.', style: MatapoText.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: MatapoColors.muted),
            ],
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Grilla favorita ${grid.name}, ${grid.cameraCount} cámaras. Presioná OK para ver.',
      child: TvCard(
        autofocus: autofocus,
        padding: const EdgeInsets.all(MatapoSpace.md),
        onSelect: () => openGrid(context, grid.id),
        onLongSelect: () => chooseFavoriteGrid(context),
        child: (focused) => Row(
          children: [
            SizedBox(
              width: 300,
              child: AspectRatio(aspectRatio: 16 / 9, child: GridSnapshotPreview(app: app, grid: grid)),
            ),
            const SizedBox(width: MatapoSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.star_rounded, color: MatapoColors.primaryAction, size: 20),
                      SizedBox(width: 6),
                      Text('Grilla favorita', style: TextStyle(color: MatapoColors.primaryPressed, fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: MatapoSpace.xs),
                  Text(grid.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MatapoText.headline),
                  Text('${grid.cameraCount} cámaras · ${grid.layout.label}', style: MatapoText.caption),
                  const SizedBox(height: MatapoSpace.md),
                  HintBar([
                    (const KeyCap('OK'), 'Ver grilla'),
                    (const KeyCap('Mantené OK'), 'Cambiar'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

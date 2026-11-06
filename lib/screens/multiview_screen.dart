import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../player/live_player.dart';
import '../player/stream_queue.dart';
import '../state/app_state.dart';
import '../state/grids.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';
import 'home_screen.dart' show cameraStatus, digitIndex, openLive;

final _nextKeys = {
  LogicalKeyboardKey.channelUp,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.mediaTrackNext,
  LogicalKeyboardKey.mediaFastForward,
};
final _prevKeys = {
  LogicalKeyboardKey.channelDown,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.mediaTrackPrevious,
  LogicalKeyboardKey.mediaRewind,
};

Future<void> openGrid(BuildContext context, String gridId) async {
  final previous = guideSection.value;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: MatapoMotion.navigation,
      pageBuilder: (_, _, _) => GridViewScreen(gridId: gridId),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
  guideSection.value = previous;
}

/// Opens the editor; returns the saved grid, or null when cancelled.
Future<GridPreset?> editGrid(BuildContext context, GridPreset? grid) {
  return Navigator.of(context).push<GridPreset>(MaterialPageRoute(builder: (_) => GridEditorScreen(initial: grid)));
}

/// Picks the camera for one tile. Returns '' for "empty", null on Back.
Future<String?> pickCamera(BuildContext context, {required int slot, String? current}) {
  final app = AppScope.read(context);
  return showTvDialog<String>(
    context,
    (context) => TvDialog(
      title: 'Cámara para la celda ${slot + 1}',
      children: [
        TvTile(
          title: 'Celda vacía',
          icon: Icons.crop_square_rounded,
          selected: current == null,
          autofocus: current == null,
          onSelect: () => Navigator.pop(context, ''),
        ),
        for (final camera in app.cameras) ...[
          const SizedBox(height: MatapoSpace.md),
          TvTile(
            title: camera.name,
            subtitle: camera.model,
            icon: Icons.videocam_rounded,
            selected: camera.deviceId == current,
            autofocus: camera.deviceId == current,
            onSelect: () => Navigator.pop(context, camera.deviceId),
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------- Panel --

/// Multi-view tab: the saved grids, the built-in "All cameras" grid and a
/// "New grid" card.
class MultiviewPanel extends StatelessWidget {
  const MultiviewPanel({super.key});

  Future<void> _options(BuildContext context, GridPreset grid) async {
    final app = AppScope.read(context);
    final action = await showTvDialog<String>(
      context,
      (context) => TvDialog(
        title: grid.name,
        message: '${grid.cameraCount} cámaras · ${grid.layout.label}',
        children: [
          TvTile(
            title: 'Ver',
            icon: Icons.play_arrow_rounded,
            autofocus: true,
            onSelect: () => Navigator.pop(context, 'open'),
          ),
          const SizedBox(height: MatapoSpace.md),
          TvTile(
            title: app.favoriteGridId == grid.id ? 'Quitar del inicio' : 'Fijar en el inicio',
            subtitle: app.favoriteGridId == grid.id
                ? 'Es tu grilla favorita del inicio'
                : 'Mostrar esta grilla arriba en el inicio',
            icon: app.favoriteGridId == grid.id ? Icons.star_outline_rounded : Icons.star_rounded,
            onSelect: () => Navigator.pop(context, 'favorite'),
          ),
          const SizedBox(height: MatapoSpace.md),
          if (grid.isAuto)
            TvTile(
              title: 'Guardar una copia para personalizarla',
              subtitle: 'Todas las cámaras se actualiza sola y no se puede editar',
              icon: Icons.copy_rounded,
              onSelect: () => Navigator.pop(context, 'copy'),
            )
          else ...[
            TvTile(title: 'Editar', icon: Icons.edit_rounded, onSelect: () => Navigator.pop(context, 'edit')),
            const SizedBox(height: MatapoSpace.md),
            TvTile(title: 'Duplicar', icon: Icons.copy_rounded, onSelect: () => Navigator.pop(context, 'copy')),
            const SizedBox(height: MatapoSpace.md),
            TvTile(
              title: 'Eliminar',
              icon: Icons.delete_rounded,
              danger: true,
              onSelect: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ],
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'open':
        await openGrid(context, grid.id);
      case 'favorite':
        final pin = app.favoriteGridId != grid.id;
        await app.setFavoriteGrid(pin ? grid.id : null);
        if (context.mounted) showToast(context, pin ? 'Fijada en el inicio' : 'Quitada del inicio', icon: Icons.star_rounded);
      case 'edit':
        await editGrid(context, grid);
      case 'copy':
        await editGrid(context, GridPreset(id: '', name: '${grid.name} (copia)', layout: grid.layout, slots: grid.slots));
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: '¿Eliminar "${grid.name}"?',
          message: 'Las cámaras no cambian; solo se borra esta grilla guardada.',
          confirmLabel: 'Eliminar',
          danger: true,
        );
        if (ok) {
          await app.deleteGrid(grid.id);
          if (context.mounted) showToast(context, 'Grilla eliminada');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final grids = app.grids;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: MatapoSpace.cardGap,
              crossAxisSpacing: MatapoSpace.cardGap,
              childAspectRatio: 1.3,
            ),
            itemCount: grids.length + 1,
            itemBuilder: (context, i) {
              if (i == grids.length) {
                return TvCard(
                  onSelect: () async {
                    final saved = await editGrid(context, null);
                    if (saved != null && context.mounted) showToast(context, '"${saved.name}" guardada');
                  },
                  child: (focused) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_rounded, size: 48, color: MatapoColors.primaryAction),
                      SizedBox(height: MatapoSpace.md),
                      Text('Nueva grilla', style: MatapoText.label),
                      Text('Elegí un diseño y las cámaras', style: MatapoText.caption),
                    ],
                  ),
                );
              }
              final grid = grids[i];
              final last = grid.id == app.activeGridId;
              return Semantics(
                label: '${grid.name}, ${grid.cameraCount} cámaras, ${grid.layout.label}${last ? ', última usada' : ''}',
                child: TvCard(
                  autofocus: i == 0,
                  selected: last,
                  padding: const EdgeInsets.all(MatapoSpace.md),
                  onSelect: () => openGrid(context, grid.id),
                  onLongSelect: () => _options(context, grid),
                  child: (focused) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutDiagram(app: app, grid: grid),
                      ),
                      const SizedBox(height: MatapoSpace.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(grid.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MatapoText.label),
                          ),
                          if (grid.id == app.favoriteGridId) ...[
                            const Icon(Icons.star_rounded, size: 20, color: MatapoColors.primaryAction, semanticLabel: 'Fijada en el inicio'),
                            const SizedBox(width: 4),
                          ],
                          if (last) ...[
                            const Icon(Icons.check_circle_rounded, size: 18, color: MatapoColors.primaryPressed),
                            const SizedBox(width: 4),
                            Text('Última usada', style: MatapoText.caption.copyWith(color: MatapoColors.primaryPressed)),
                          ],
                        ],
                      ),
                      Text(
                        '${grid.cameraCount} cámaras · ${grid.layout.label}${grid.isAuto ? ' · automática' : ''}',
                        style: MatapoText.caption,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: MatapoSpace.sm),
        HintBar([
          (const KeyCap('OK'), 'Ver grilla'),
          (const KeyCap('Mantené OK'), 'Fijar, editar o eliminar'),
          (const KeyCap('CH ±'), 'Cambiar de grilla mientras mirás'),
        ]),
      ],
    );
  }
}

/// A grid's layout filled with each camera's last captured picture. Used on
/// the home page, where it costs nothing compared with live streams.
class GridSnapshotPreview extends StatelessWidget {
  const GridSnapshotPreview({super.key, required this.app, required this.grid});
  final AppState app;
  final GridPreset grid;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(color: MatapoColors.media, borderRadius: BorderRadius.circular(MatapoRadius.sm)),
        padding: const EdgeInsets.all(3),
        child: TileLayout(
          layout: grid.layout,
          gap: 3,
          builder: (i) {
            final camera = app.cameraById(grid.slots[i]);
            final empty = Container(color: const Color(0xFF1B2733));
            return ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: camera == null
                  ? empty
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        if (camera.privacy == true)
                          Container(
                            color: const Color(0xFF1B2733),
                            child: const Icon(Icons.visibility_off_rounded, color: Color(0xFFC9D3DC), size: 16),
                          )
                        else
                          SnapshotView(
                            deviceId: camera.deviceId,
                            fallback: Container(
                              color: const Color(0xFF1B2733),
                              child: const Icon(Icons.videocam_rounded, color: Color(0xFFC9D3DC), size: 16),
                            ),
                          ),
                        Positioned(
                          left: 2,
                          bottom: 2,
                          right: 2,
                          child: Text(
                            camera.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                            ),
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Miniature of a grid's layout with the camera names in each tile.
class LayoutDiagram extends StatelessWidget {
  const LayoutDiagram({super.key, required this.app, required this.grid});
  final AppState app;
  final GridPreset grid;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(gradient: featuredGradient, borderRadius: BorderRadius.circular(MatapoRadius.sm)),
        padding: const EdgeInsets.all(6),
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: TileLayout(
              layout: grid.layout,
              gap: 4,
              builder: (i) {
                final camera = app.cameraById(grid.slots[i]);
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: camera != null ? MatapoColors.primary : MatapoColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: camera != null ? null : Border.all(color: MatapoColors.outline),
                  ),
                  child: Text(
                    camera?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MatapoColors.onPrimary, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Positions one widget per tile of [layout] inside the available box.
class TileLayout extends StatelessWidget {
  const TileLayout({super.key, required this.layout, required this.builder, this.gap = 8});
  final GridLayout layout;
  final Widget Function(int index) builder;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cw = box.maxWidth / layout.cols, ch = box.maxHeight / layout.rows;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < layout.slots; i++)
              Positioned(
                left: layout.tiles[i].left * cw + gap / 2,
                top: layout.tiles[i].top * ch + gap / 2,
                width: layout.tiles[i].width * cw - gap,
                height: layout.tiles[i].height * ch - gap,
                child: builder(i),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- Watching --

/// Full-screen multi-view of one grid; CH± or the top bar switches grids.
class GridViewScreen extends StatefulWidget {
  const GridViewScreen({super.key, required this.gridId});
  final String gridId;

  @override
  State<GridViewScreen> createState() => _GridViewScreenState();
}

class _GridViewScreenState extends State<GridViewScreen> {
  late String _gridId = widget.gridId;
  final _firstTile = FocusNode(debugLabel: 'grid-first-tile');
  final _barEntry = FocusNode(debugLabel: 'grid-bar-entry');
  bool _barFocused = false;
  bool _flash = true;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.multiview;
    _flashBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.read(context).setActiveGrid(_gridId);
      _firstTile.requestFocus();
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _firstTile.dispose();
    _barEntry.dispose();
    super.dispose();
  }

  /// Moves focus back to the tiles (they are excluded while the bar is
  /// focused, so re-include them first).
  void _focusTiles() {
    setState(() => _barFocused = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstTile.requestFocus();
    });
  }

  void _flashBar() {
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _switchTo(String id, {bool keepBarFocus = false}) {
    final app = AppScope.read(context);
    setState(() => _gridId = id);
    app.setActiveGrid(id);
    _flashBar();
    if (!keepBarFocus) _focusTiles();
  }

  void _step(int delta) {
    final grids = AppScope.read(context).grids;
    final i = grids.indexWhere((g) => g.id == _gridId);
    _switchTo(grids[(i + delta) % grids.length].id);
  }

  Future<void> _changeTile(GridPreset grid, int slot) async {
    if (grid.isAuto) {
      final copy = await confirmDialog(
        context,
        title: 'Todas las cámaras es automática',
        message: 'Guardá una copia de esta grilla para elegir la cámara de cada celda.',
        confirmLabel: 'Guardar una copia',
      );
      if (!copy || !mounted) return;
      final saved = await editGrid(
        context,
        GridPreset(id: '', name: 'Mi grilla', layout: grid.layout, slots: grid.slots),
      );
      if (saved != null && mounted) _switchTo(saved.id);
      return;
    }
    final picked = await pickCamera(context, slot: slot, current: grid.slots[slot]);
    if (picked == null || !mounted) return;
    final slots = [...grid.slots]..[slot] = picked.isEmpty ? null : picked;
    await AppScope.read(context).saveGrid(grid.copyWith(slots: slots));
  }

  void _openTile(GridPreset grid, int slot) {
    final id = grid.slots[slot];
    if (id == null) {
      _changeTile(grid, slot);
      return;
    }
    openLive(context, AppScope.read(context).cameraIndex(id));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, GridPreset grid) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_nextKeys.contains(key)) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (_prevKeys.contains(key)) {
      _step(-1);
      return KeyEventResult.handled;
    }
    final digit = digitIndex(key);
    if (digit != null && digit < grid.layout.slots) {
      _openTile(grid, digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Up from the top row of tiles enters the grid bar.
  KeyEventResult _tilesKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && !focused.focusInDirection(TraversalDirection.up)) {
      _barEntry.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _barKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    _focusTiles();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final grid = app.gridById(_gridId);
    final grids = app.grids;
    final showBar = _barFocused || _flash;
    return PopScope(
      // Back first leaves the grid bar, then closes the grid.
      canPop: !_barFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _focusTiles();
      },
      child: Scaffold(
        backgroundColor: MatapoColors.media,
        body: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) => _onKey(node, event, grid),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _tilesKey,
                  // While the grid bar has focus, arrows must stay inside it
                  // (the bar overlaps the top tiles); Down returns explicitly.
                  child: ExcludeFocus(
                    excluding: _barFocused,
                    child: FocusTraversalGroup(
                      child: TileLayout(
                        layout: grid.layout,
                        gap: 14,
                        builder: (i) {
                          final camera = app.cameraById(grid.slots[i]);
                          return _GridTile(
                            key: ValueKey('${grid.id}-$i-${camera?.deviceId}'),
                            app: app,
                            camera: camera,
                            number: i + 1,
                            focusNode: i == 0 ? _firstTile : null,
                            active: app.foreground && TickerMode.valuesOf(context).enabled,
                            onSelect: () => _openTile(grid, i),
                            onLongSelect: () => _changeTile(grid, i),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedOpacity(
                  opacity: showBar ? 1 : 0,
                  duration: MatapoMotion.navigation,
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (f) => setState(() => _barFocused = f),
                    onKeyEvent: _barKey,
                    child: FocusTraversalGroup(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(48, 20, 48, 20),
                        decoration: const BoxDecoration(color: MatapoColors.media),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(grid.name, style: MatapoText.title.copyWith(color: MatapoColors.onMedia)),
                                Text(
                                  '${grid.cameraCount} cámaras · ${grid.layout.label} · CH ± para cambiar',
                                  style: MatapoText.caption.copyWith(color: const Color(0xFFC9D3DC)),
                                ),
                              ],
                            ),
                            const SizedBox(width: MatapoSpace.x2),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                child: Row(
                                  children: [
                                    for (final g in grids) ...[
                                      TvChip(
                                        label: g.name,
                                        selected: g.id == grid.id,
                                        onMedia: true,
                                        focusNode: g.id == grid.id ? _barEntry : null,
                                        onSelect: () => _switchTo(g.id, keepBarFocus: true),
                                      ),
                                      const SizedBox(width: MatapoSpace.sm),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: MatapoSpace.md),
                            TvButton(
                              label: grid.isAuto ? 'Guardar una copia' : 'Editar grilla',
                              icon: grid.isAuto ? Icons.copy_rounded : Icons.edit_rounded,
                              onMedia: true,
                              onPressed: () async {
                                final saved = await editGrid(
                                  context,
                                  grid.isAuto
                                      ? GridPreset(id: '', name: 'Mi grilla', layout: grid.layout, slots: grid.slots)
                                      : grid,
                                );
                                if (saved != null && mounted) _switchTo(saved.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridTile extends StatefulWidget {
  const _GridTile({
    super.key,
    required this.app,
    required this.camera,
    required this.number,
    required this.active,
    required this.onSelect,
    required this.onLongSelect,
    this.focusNode,
  });

  final AppState app;
  final Camera? camera;
  final int number;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onLongSelect;
  final FocusNode? focusNode;

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  LiveState? _live;
  final _video = GlobalKey<LiveVideoState>();

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    final (status, icon, color) = camera == null
        ? ('Vacía', Icons.add_rounded, MatapoColors.muted)
        : cameraStatus(camera, _live, previews: true);
    return Semantics(
      button: true,
      label: camera == null ? 'Celda ${widget.number}, vacía' : 'Celda ${widget.number}, ${camera.name}, $status',
      child: TvFocusable(
        focusNode: widget.focusNode,
        ensureVisible: false,
        onSelect: () {
          final video = _video.currentState;
          if (video != null && video.failed) {
            video.retry();
          } else {
            widget.onSelect();
          }
        },
        onLongSelect: widget.onLongSelect,
        builder: (context, focused) => FocusRing(
          focused: focused,
          radius: MatapoRadius.md,
          onMedia: true,
          scale: false,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MatapoRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (camera == null)
                  Container(
                    color: const Color(0xFF1B2733),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: Color(0xFFC9D3DC), size: 36),
                        SizedBox(height: MatapoSpace.sm),
                        Text('Celda vacía · OK para agregar', style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 16)),
                      ],
                    ),
                  )
                else if (camera.privacy == true)
                  Container(
                    color: const Color(0xFF1B2733),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_off_rounded, color: Color(0xFFC9D3DC), size: 36),
                        SizedBox(height: MatapoSpace.sm),
                        Text('Modo privacidad activado', style: TextStyle(color: Color(0xFFC9D3DC), fontSize: 16)),
                      ],
                    ),
                  )
                else if (widget.active)
                  LiveVideo(
                    key: _video,
                    app: widget.app,
                    camera: camera,
                    compact: true,
                    onStateChanged: (s) => setState(() => _live = s),
                  ),
                // Name label on an opaque media backing for legibility.
                Positioned(
                  left: MatapoSpace.sm,
                  bottom: MatapoSpace.sm,
                  right: MatapoSpace.sm,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: MatapoColors.media.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(MatapoRadius.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${widget.number}',
                                style: const TextStyle(
                                  color: MatapoColors.onMedia,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: MatapoSpace.sm),
                              Flexible(
                                child: Text(
                                  camera?.name ?? 'Vacía',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MatapoColors.onMedia,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (camera != null && status == 'En vivo') ...[
                                const SizedBox(width: MatapoSpace.sm),
                                Icon(icon, size: 9, color: const Color(0xFF4CD99A)),
                                const SizedBox(width: 4),
                                const Text('En vivo', style: TextStyle(color: MatapoColors.onMedia, fontSize: 13)),
                              ],
                              if (color == MatapoColors.error) ...[
                                const SizedBox(width: MatapoSpace.sm),
                                Text(status, style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
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

// --------------------------------------------------------------- Editor --

class GridEditorScreen extends StatefulWidget {
  const GridEditorScreen({super.key, this.initial});

  /// Grid to edit; id '' (or null) creates a new one.
  final GridPreset? initial;

  @override
  State<GridEditorScreen> createState() => _GridEditorScreenState();
}

class _GridEditorScreenState extends State<GridEditorScreen> {
  late String _name = widget.initial?.name ?? '';
  late GridLayout _layout = widget.initial?.layout ?? GridLayout.quad;
  late List<String?> _slots = [...?widget.initial?.slots];
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.initial == null || widget.initial!.id.isEmpty;

  List<String?> _fit(List<String?> slots, GridLayout layout) =>
      List.generate(layout.slots, (i) => i < slots.length ? slots[i] : null);

  void _fillAll() {
    final app = AppScope.read(context);
    setState(() => _slots = _fit([for (final c in app.cameras) c.deviceId], _layout));
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final slots = _fit(_slots, _layout);
    if (slots.every((s) => s == null)) {
      setState(() => _error = 'Agregá al menos una cámara a la grilla.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.trim().isEmpty ? 'Grilla ${app.savedGrids.length + 1}' : _name.trim();
    final saved = await app.saveGrid(
      GridPreset(id: _isNew ? '' : widget.initial!.id, name: name, layout: _layout, slots: slots),
    );
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final slots = _fit(_slots, _layout);
    return Scaffold(
      body: Padding(
        padding: tvSafePadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: FocusTraversalGroup(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    Text(_isNew ? 'Nueva grilla' : 'Editar grilla', style: MatapoText.headline),
                    const Text('Elegí un diseño y después una cámara para cada celda.', style: MatapoText.caption),
                    const SizedBox(height: MatapoSpace.xl),
                    TvTextField(
                      label: 'Nombre',
                      hint: 'por ejemplo, Planta baja',
                      icon: Icons.label_rounded,
                      value: _name,
                      autofocus: true,
                      onChanged: (v) => setState(() => _name = v),
                    ),
                    const SizedBox(height: MatapoSpace.xl),
                    Text(
                      'Diseño',
                      style: MatapoText.caption.copyWith(color: MatapoColors.onSurface, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: MatapoSpace.sm),
                    Wrap(
                      spacing: MatapoSpace.sm,
                      runSpacing: MatapoSpace.md,
                      children: [
                        for (final l in GridLayout.values)
                          TvChip(label: l.label, selected: l == _layout, onSelect: () => setState(() => _layout = l)),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: MatapoSpace.md),
                      Row(
                        children: [
                          const Icon(Icons.error_rounded, color: MatapoColors.error),
                          const SizedBox(width: MatapoSpace.sm),
                          Expanded(
                            child: Text(_error!, style: MatapoText.body.copyWith(color: MatapoColors.error)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: MatapoSpace.x2),
                    TvButton(
                      label: 'Guardar grilla',
                      icon: Icons.check_rounded,
                      style: TvButtonStyle.primary,
                      busy: _saving,
                      expand: true,
                      onPressed: _save,
                    ),
                    const SizedBox(height: MatapoSpace.md),
                    Wrap(
                      spacing: MatapoSpace.sm,
                      runSpacing: MatapoSpace.sm,
                      children: [
                        TvButton(
                          label: 'Completar con todas',
                          icon: Icons.auto_awesome_mosaic_rounded,
                          onPressed: _fillAll,
                        ),
                        if (!_isNew)
                          TvButton(
                            label: 'Eliminar',
                            icon: Icons.delete_rounded,
                            style: TvButtonStyle.danger,
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: '¿Eliminar "${widget.initial!.name}"?',
                                message: 'Solo se borra esta grilla guardada.',
                                confirmLabel: 'Eliminar',
                                danger: true,
                              );
                              if (ok && context.mounted) {
                                await app.deleteGrid(widget.initial!.id);
                                if (context.mounted) Navigator.of(context).pop();
                              }
                            },
                          ),
                        TvButton(
                          label: 'Cancelar',
                          style: TvButtonStyle.text,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: MatapoSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const Text('Celdas', style: MatapoText.title),
                  const Text('OK en una celda para elegir su cámara.', style: MatapoText.caption),
                  const SizedBox(height: MatapoSpace.lg),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: FocusTraversalGroup(
                          child: TileLayout(
                            layout: _layout,
                            gap: 16,
                            builder: (i) {
                              final camera = app.cameraById(slots[i]);
                              return TvCard(
                                padding: const EdgeInsets.all(MatapoSpace.sm),
                                onSelect: () async {
                                  final picked = await pickCamera(context, slot: i, current: slots[i]);
                                  if (picked == null) return;
                                  setState(() => _slots = [...slots]..[i] = picked.isEmpty ? null : picked);
                                },
                                child: (focused) => Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      camera == null ? Icons.add_circle_outline_rounded : Icons.videocam_rounded,
                                      color: MatapoColors.primaryAction,
                                      size: _layout.slots > 6 ? 22 : 30,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      camera?.name ?? 'Celda ${i + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MatapoText.label.copyWith(fontSize: _layout.slots > 6 ? 15 : 18),
                                    ),
                                    if (camera == null && _layout.slots <= 6)
                                      const Text('Agregar cámara', style: MatapoText.caption),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

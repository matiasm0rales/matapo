import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show AppScope;
import '../player/live_player.dart';
import '../screens/multiview_screen.dart' show GridSnapshotPreview, TileLayout;
import '../state/app_state.dart';
import '../state/grids.dart';
import '../ui/theme.dart';
import 'desktop_live.dart';
import 'desktop_theme.dart';

Future<void> openDesktopGrid(BuildContext context, String gridId) {
  AppScope.read(context).setActiveGrid(gridId);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => DesktopGridScreen(gridId: gridId),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

String gridSubtitle(GridPreset grid) {
  final n = grid.cameraCount;
  return '${n == 1 ? '1 cámara' : '$n cámaras'} · ${grid.layout.label}';
}

/// Creates a grid (empty [grid.id]) or edits one; returns the saved grid.
Future<GridPreset?> editDesktopGrid(BuildContext context, GridPreset grid) {
  return showDialog<GridPreset>(context: context, builder: (_) => _GridEditor(initial: grid));
}

Future<void> newDesktopGrid(BuildContext context) async {
  final app = AppScope.read(context);
  final saved = await editDesktopGrid(
    context,
    GridPreset(id: '', name: 'Grilla ${app.savedGrids.length + 1}', layout: GridLayout.quad, slots: const []),
  );
  if (saved != null && context.mounted) showDesktopMessage(context, 'Grilla "${saved.name}" guardada');
}

/// Menu entries shared by the grid list and the grid view.
List<MenuAction?> gridActions(BuildContext context, GridPreset grid, {bool includeOpen = true}) {
  final app = AppScope.read(context);
  final pinned = app.favoriteGridId == grid.id;
  return [
    if (includeOpen) MenuAction('Abrir', Icons.grid_view_rounded, () => openDesktopGrid(context, grid.id)),
    MenuAction(
      pinned ? 'Quitar de favoritas' : 'Marcar como favorita',
      pinned ? Icons.star_rounded : Icons.star_outline_rounded,
      () => app.setFavoriteGrid(pinned ? null : grid.id),
    ),
    null,
    if (!grid.isAuto) MenuAction('Editar…', Icons.edit_outlined, () => editDesktopGrid(context, grid)),
    MenuAction(
      grid.isAuto ? 'Guardar como grilla nueva…' : 'Duplicar',
      Icons.copy_rounded,
      () async {
        final copy = GridPreset(
          id: '',
          name: grid.isAuto ? 'Mi grilla' : '${grid.name} (copia)',
          layout: grid.layout,
          slots: grid.slots,
        );
        final saved = grid.isAuto ? await editDesktopGrid(context, copy) : await app.saveGrid(copy);
        if (saved != null && context.mounted) showDesktopMessage(context, 'Grilla "${saved.name}" guardada');
      },
    ),
    if (!grid.isAuto) ...[
      null,
      MenuAction('Eliminar…', Icons.delete_outline_rounded, () async {
        final ok = await confirmDesktop(
          context,
          title: 'Eliminar "${grid.name}"',
          message: 'La grilla se borra de esta computadora. Las cámaras no cambian.',
          confirm: 'Eliminar',
          danger: true,
        );
        if (ok) await app.deleteGrid(grid.id);
      }, danger: true),
    ],
  ];
}

class GridsSection extends StatelessWidget {
  const GridsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final grids = app.grids;
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 340).floor().clamp(1, 5);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: (box.maxWidth - 48 - (columns - 1) * 16) / columns * 9 / 16 + 64,
          ),
          itemCount: grids.length + 1,
          itemBuilder: (context, i) {
            if (i == grids.length) return const _NewGridCard();
            final grid = grids[i];
            final favorite = app.favoriteGridId == grid.id;
            return HoverCard(
              onTap: () => openDesktopGrid(context, grid.id),
              onSecondaryTap: (pos) => showContextMenu(context, pos, gridActions(context, grid)),
              builder: (context, hovered) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: GridSnapshotPreview(app: app, grid: grid),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 6, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(grid.isAuto ? 'Todas las cámaras' : grid.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.titleMedium),
                                  ),
                                  if (favorite) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF2A900)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                grid.isAuto ? '${gridSubtitle(grid)} · automática' : gridSubtitle(grid),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Builder(
                          builder: (context) => IconButton(
                            tooltip: 'Más opciones',
                            icon: const Icon(Icons.more_horiz_rounded, size: 20),
                            onPressed: () {
                              final b = context.findRenderObject() as RenderBox;
                              showContextMenu(context, b.localToGlobal(b.size.bottomLeft(Offset.zero)), gridActions(context, grid));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NewGridCard extends StatelessWidget {
  const _NewGridCard();

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: () => newDesktopGrid(context),
      builder: (context, hovered) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline_rounded, size: 36, color: hovered ? MatapoColors.primaryAction : DesktopColors.secondary),
          const SizedBox(height: 8),
          Text('Nueva grilla', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('Elegí un diseño y las cámaras', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Several cameras live at once.
class DesktopGridScreen extends StatefulWidget {
  const DesktopGridScreen({super.key, required this.gridId});
  final String gridId;

  @override
  State<DesktopGridScreen> createState() => _DesktopGridScreenState();
}

class _DesktopGridScreenState extends State<DesktopGridScreen> {
  late String _gridId = widget.gridId;

  void _switchGrid(int delta) {
    final app = AppScope.read(context);
    final grids = app.grids;
    final i = grids.indexWhere((g) => g.id == _gridId);
    final next = grids[(i + delta) % grids.length];
    setState(() => _gridId = next.id);
    app.setActiveGrid(next.id);
  }

  Future<void> _changeTile(GridPreset grid, int slot, Offset position) async {
    final app = AppScope.read(context);
    final current = grid.slots[slot];
    showContextMenu(context, position, [
      for (final camera in app.cameras)
        MenuAction(
          camera.name,
          camera.deviceId == current ? Icons.check_rounded : Icons.videocam_outlined,
          () => _setTile(grid, slot, camera.deviceId),
        ),
      if (current != null) ...[
        null,
        MenuAction('Dejar vacía', Icons.crop_square_rounded, () => _setTile(grid, slot, null)),
      ],
    ]);
  }

  Future<void> _setTile(GridPreset grid, int slot, String? deviceId) async {
    final slots = [...grid.slots]..[slot] = deviceId;
    await AppScope.read(context).saveGrid(grid.copyWith(slots: slots));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.bracketRight) {
      _switchGrid(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.bracketLeft) {
      _switchGrid(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      DesktopWindow.toggleFullScreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final grid = app.gridById(_gridId);
    final active = app.foreground && TickerMode.valuesOf(context).enabled;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            Container(
              color: DesktopColors.media,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  MediaIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Volver (Esc)',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Theme(
                    data: Theme.of(context).copyWith(canvasColor: Colors.white),
                    child: PopupMenuButton<String>(
                      tooltip: 'Cambiar de grilla (Re Pág / Av Pág)',
                      color: Colors.white,
                      onSelected: (id) {
                        setState(() => _gridId = id);
                        app.setActiveGrid(id);
                      },
                      itemBuilder: (_) => [
                        for (final g in app.grids)
                          PopupMenuItem(
                            value: g.id,
                            height: 34,
                            child: Row(
                              children: [
                                Icon(g.id == grid.id ? Icons.check_rounded : Icons.grid_view_rounded, size: 18),
                                const SizedBox(width: 10),
                                Text(g.isAuto ? 'Todas las cámaras' : g.name),
                              ],
                            ),
                          ),
                      ],
                      child: Row(
                        children: [
                          Text(
                            grid.isAuto ? 'Todas las cámaras' : grid.name,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(gridSubtitle(grid), style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () async {
                      if (grid.isAuto) {
                        final saved = await editDesktopGrid(
                          context,
                          GridPreset(id: '', name: 'Mi grilla', layout: grid.layout, slots: grid.slots),
                        );
                        if (saved != null && mounted) setState(() => _gridId = saved.id);
                      } else {
                        await editDesktopGrid(context, grid);
                      }
                    },
                    icon: Icon(grid.isAuto ? Icons.copy_rounded : Icons.edit_outlined, size: 18),
                    label: Text(grid.isAuto ? 'Guardar como grilla nueva' : 'Editar grilla'),
                  ),
                  const SizedBox(width: 6),
                  const MediaIconButton(
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'Pantalla completa (F)',
                    onPressed: DesktopWindow.toggleFullScreen,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: TileLayout(
                  layout: grid.layout,
                  gap: 4,
                  builder: (slot) {
                    final camera = app.cameraById(grid.slots[slot]);
                    return _GridTile(
                      key: ValueKey('${grid.id}/$slot/${camera?.deviceId}'),
                      app: app,
                      camera: camera,
                      active: active,
                      editable: !grid.isAuto,
                      onOpen: camera == null ? null : () => openDesktopLive(context, app.cameraIndex(camera.deviceId)),
                      onChange: grid.isAuto ? null : (pos) => _changeTile(grid, slot, pos),
                    );
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

class _GridTile extends StatefulWidget {
  const _GridTile({
    super.key,
    required this.app,
    required this.camera,
    required this.active,
    required this.editable,
    required this.onOpen,
    required this.onChange,
  });
  final AppState app;
  final Camera? camera;
  final bool active;
  final bool editable;
  final VoidCallback? onOpen;
  final void Function(Offset)? onChange;

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    if (camera == null) {
      return ColoredBox(
        color: const Color(0xFF141E28),
        child: Center(
          child: widget.onChange == null
              ? const Text('Celda vacía', style: TextStyle(color: Colors.white54))
              : Builder(
                  builder: (context) => OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    onPressed: () {
                      final b = context.findRenderObject() as RenderBox;
                      widget.onChange!(b.localToGlobal(b.size.bottomLeft(Offset.zero)));
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Agregar cámara'),
                  ),
                ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapUp: widget.onChange == null ? null : (d) => widget.onChange!(d.globalPosition),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (camera.privacy == true)
              const ColoredBox(
                color: Color(0xFF1B2733),
                child: Center(child: Icon(Icons.visibility_off_outlined, color: Color(0xFFC9D3DC), size: 32)),
              )
            else if (widget.active)
              LiveVideo(app: widget.app, camera: camera, compact: true)
            else
              const ColoredBox(color: Colors.black),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xB3101820), borderRadius: BorderRadius.circular(6)),
                child: Text(camera.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            if (_hovered)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    if (widget.onChange != null)
                      Builder(
                        builder: (context) => MediaIconButton(
                          icon: Icons.swap_horiz_rounded,
                          tooltip: 'Cambiar cámara',
                          onPressed: () {
                            final b = context.findRenderObject() as RenderBox;
                            widget.onChange!(b.localToGlobal(b.size.bottomLeft(Offset.zero)));
                          },
                        ),
                      ),
                    const SizedBox(width: 6),
                    MediaIconButton(icon: Icons.open_in_full_rounded, tooltip: 'Ver en grande', onPressed: widget.onOpen),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridEditor extends StatefulWidget {
  const _GridEditor({required this.initial});
  final GridPreset initial;

  @override
  State<_GridEditor> createState() => _GridEditorState();
}

class _GridEditorState extends State<_GridEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late GridLayout _layout = widget.initial.layout;
  late List<String?> _slots = [...widget.initial.slots];
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.initial.id.isEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setLayout(GridLayout layout) {
    setState(() {
      _layout = layout;
      _slots = List<String?>.generate(layout.slots, (i) => i < _slots.length ? _slots[i] : null);
    });
  }

  void _fillAll() {
    final cams = AppScope.read(context).cameras;
    setState(() {
      _slots = List<String?>.generate(_layout.slots, (i) => i < cams.length ? cams[i].deviceId : null);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Poné un nombre a la grilla');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await AppScope.read(context).saveGrid(
      GridPreset(id: widget.initial.id, name: name, layout: _layout, slots: _slots),
    );
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'Nueva grilla' : 'Editar grilla'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Text('Diseño', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<GridLayout>(
              segments: [for (final l in GridLayout.values) ButtonSegment(value: l, label: Text(l.label))],
              selected: {_layout},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _setLayout(s.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Hacé clic en una celda para elegir la cámara.', style: Theme.of(context).textTheme.bodySmall),
                ),
                TextButton(onPressed: _fillAll, child: const Text('Completar con todas')),
              ],
            ),
            const SizedBox(height: 6),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(color: DesktopColors.sidebar, borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(6),
                child: TileLayout(
                  layout: _layout,
                  gap: 6,
                  builder: (i) {
                    final camera = app.cameraById(_slots[i]);
                    return Builder(
                      builder: (context) => Material(
                        color: camera != null ? MatapoColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final b = context.findRenderObject() as RenderBox;
                            showContextMenu(context, b.localToGlobal(b.size.center(Offset.zero)), [
                              for (final c in app.cameras)
                                MenuAction(
                                  c.name,
                                  c.deviceId == _slots[i] ? Icons.check_rounded : Icons.videocam_outlined,
                                  () => setState(() => _slots[i] = c.deviceId),
                                ),
                              null,
                              MenuAction('Dejar vacía', Icons.crop_square_rounded, () => setState(() => _slots[i] = null)),
                            ]);
                          },
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                camera?.name ?? '+ Elegir cámara',
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: camera != null ? Colors.white : DesktopColors.secondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_isNew ? 'Crear grilla' : 'Guardar')),
      ],
    );
  }
}

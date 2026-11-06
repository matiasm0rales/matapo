import 'package:flutter/material.dart';

import 'theme.dart';
import 'tv.dart';

enum GuideSection { basics, home, multiview, live }

enum _RemoteKey { up, down, left, right, ok, back, home, menu, chUp, chDown, digits }

class _Row {
  const _Row(this.keys, this.label, this.detail, this.highlight);
  final List<Widget> keys;
  final String label;
  final String detail;
  final Set<_RemoteKey> highlight;
}

const _dpad = {_RemoteKey.up, _RemoteKey.down, _RemoteKey.left, _RemoteKey.right};

final Map<GuideSection, (String, IconData, List<_Row>)> _sections = {
  GuideSection.basics: (
    'Básico',
    Icons.gamepad_rounded,
    [
      _Row([const KeyCap('', icon: Icons.open_with_rounded, large: true)], 'Move around',
          'Las flechas mueven el recuadro azul entre los elementos.', _dpad),
      _Row([const KeyCap('OK', large: true)], 'Elegir', 'Abre o activa el elemento marcado.', {_RemoteKey.ok}),
      _Row([const KeyCap('', icon: Icons.arrow_back_rounded, large: true)], 'Volver',
          'Primero cierra los diálogos y controles, y después vuelve a la pantalla anterior.', {_RemoteKey.back}),
      _Row([const KeyCap('', icon: Icons.menu_rounded, large: true)], 'Guía del control',
          'Menú o Info abren esta guía. ¿No tenés esas teclas? Usá el botón Guía.', {_RemoteKey.menu}),
      _Row([const KeyCap('OK', large: true)], 'Escribir',
          'En un campo de texto presioná OK para abrir el teclado del TV, o escribí desde la app Google TV del teléfono.', {_RemoteKey.ok}),
    ],
  ),
  GuideSection.home: (
    'Cámaras',
    Icons.videocam_rounded,
    [
      _Row([const KeyCap('OK', large: true)], 'Ver en vivo', 'Abre la cámara marcada en pantalla completa.', {_RemoteKey.ok}),
      _Row([const KeyCap('Mantené OK', large: true)], 'Acciones rápidas',
          'Mantené OK sobre una cámara para el modo privacidad y reconectar.', {_RemoteKey.ok}),
      _Row([const KeyCap('1 – 9', large: true)], 'Ir a una cámara', 'Los números abren las cámaras 1 a 9.', {_RemoteKey.digits}),
      _Row([const KeyCap('', icon: Icons.arrow_upward_rounded, large: true)], 'Menú superior',
          'Subí para cambiar entre Cámaras, Grillas y Ajustes, y presioná OK.', {_RemoteKey.up}),
    ],
  ),
  GuideSection.multiview: (
    'Grillas',
    Icons.grid_view_rounded,
    [
      _Row([const KeyCap('OK', large: true)], 'Abrir una grilla', 'En Grillas, OK abre la grilla marcada.', {_RemoteKey.ok}),
      _Row([const KeyCap('CH +', large: true), const SizedBox(width: 6), const KeyCap('CH −', large: true)],
          'Cambiar de grilla', 'Mientras mirás una grilla, los botones de canal pasan a la grilla siguiente o anterior.',
          {_RemoteKey.chUp, _RemoteKey.chDown}),
      _Row([const KeyCap('', icon: Icons.arrow_upward_rounded, large: true)], 'Barra de grillas',
          'Subí desde la fila de arriba para elegir otra grilla o editar esta.', {_RemoteKey.up}),
      _Row([const KeyCap('OK', large: true)], 'Pantalla completa', 'OK en una celda abre esa cámara en pantalla completa.', {_RemoteKey.ok}),
      _Row([const KeyCap('Mantené OK', large: true)], 'Cambiar una celda',
          'Mantené OK en una celda para poner otra cámara.', {_RemoteKey.ok}),
    ],
  ),
  GuideSection.live: (
    'Vista en vivo',
    Icons.live_tv_rounded,
    [
      _Row([const KeyCap('', icon: Icons.open_with_rounded, large: true)], 'Movimiento',
          'Con los controles ocultos, las flechas mueven la cámara. Mantené para seguir moviendo.', _dpad),
      _Row([const KeyCap('OK', large: true)], 'Mostrar controles',
          'Privacidad, paso, reconectar y cámara anterior o siguiente.', {_RemoteKey.ok}),
      _Row([const KeyCap('CH +', large: true), const SizedBox(width: 6), const KeyCap('CH −', large: true)],
          'Cambiar de cámara', 'Botones de canal, pista anterior o siguiente, o 1–9. Sin movimiento, izquierda y derecha también cambian.',
          {_RemoteKey.chUp, _RemoteKey.chDown}),
      _Row([const KeyCap('', icon: Icons.arrow_back_rounded, large: true)], 'Volver',
          'Primero oculta los controles y después vuelve a donde estabas.', {_RemoteKey.back}),
    ],
  ),
};

Future<void> showRemoteGuide(BuildContext context, {GuideSection section = GuideSection.basics}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: MatapoMotion.navigation,
      pageBuilder: (_, _, _) => RemoteGuide(initial: section),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class RemoteGuide extends StatefulWidget {
  const RemoteGuide({super.key, this.initial = GuideSection.basics});
  final GuideSection initial;

  @override
  State<RemoteGuide> createState() => _RemoteGuideState();
}

class _RemoteGuideState extends State<RemoteGuide> {
  late GuideSection _section = widget.initial;
  Set<_RemoteKey> _highlight = {};

  @override
  Widget build(BuildContext context) {
    final (_, _, rows) = _sections[_section]!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
        child: Container(
          decoration: BoxDecoration(color: MatapoColors.surface, borderRadius: BorderRadius.circular(MatapoRadius.xl)),
          padding: const EdgeInsets.fromLTRB(MatapoSpace.x3, MatapoSpace.x2, MatapoSpace.x3, MatapoSpace.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 170, child: Center(child: _Remote(highlight: _highlight))),
              const SizedBox(width: MatapoSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Guía del control remoto', style: MatapoText.headline),
                    const SizedBox(height: MatapoSpace.md),
                    Wrap(
                      spacing: MatapoSpace.sm,
                      runSpacing: MatapoSpace.sm,
                      children: [
                        for (final s in GuideSection.values)
                          TvChip(
                            label: _sections[s]!.$1,
                            icon: _sections[s]!.$2,
                            selected: s == _section,
                            autofocus: s == widget.initial,
                            onSelect: () => setState(() => _section = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: MatapoSpace.lg),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final row in rows)
                            _GuideRow(row: row, onFocus: (f) => setState(() => _highlight = f ? row.highlight : {})),
                        ],
                      ),
                    ),
                    const SizedBox(height: MatapoSpace.md),
                    Row(
                      children: [
                        TvButton(
                          label: 'Entendido',
                          icon: Icons.check_rounded,
                          style: TvButtonStyle.primary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: MatapoSpace.lg),
                        const Expanded(
                          child: Text('Abrí esta guía cuando quieras con Menú o Info.', style: MatapoText.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.row, required this.onFocus});
  final _Row row;
  final ValueChanged<bool> onFocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MatapoSpace.md),
      child: Semantics(
        label: '${row.label}. ${row.detail}',
        child: TvFocusable(
          onFocusChange: onFocus,
          onSelect: () {},
          builder: (context, focused) => FocusRing(
            focused: focused,
            scale: false,
            child: AnimatedContainer(
              duration: MatapoMotion.focus,
              padding: const EdgeInsets.symmetric(horizontal: MatapoSpace.lg, vertical: MatapoSpace.md),
              decoration: BoxDecoration(
                color: focused ? MatapoColors.surfaceSelected : MatapoColors.neutral,
                borderRadius: BorderRadius.circular(MatapoRadius.lg),
              ),
              child: Row(
                children: [
                  SizedBox(width: 132, child: Row(children: row.keys)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.label, style: MatapoText.label),
                        Text(row.detail, style: MatapoText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple remote illustration; keys in [highlight] are shown in blue.
class _Remote extends StatelessWidget {
  const _Remote({required this.highlight});
  final Set<_RemoteKey> highlight;

  bool _on(_RemoteKey k) => highlight.contains(k);
  Color _bg(_RemoteKey k) => _on(k) ? MatapoColors.primaryAction : MatapoColors.surfaceSelected;
  Color _fg(_RemoteKey k) => _on(k) ? MatapoColors.onPrimary : MatapoColors.primaryPressed;

  Widget _round(_RemoteKey k, IconData icon) => AnimatedContainer(
        duration: MatapoMotion.focus,
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: _bg(k), shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: _fg(k)),
      );

  Widget _arrow(_RemoteKey k, IconData icon) => AnimatedContainer(
        duration: MatapoMotion.focus,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _on(k) ? MatapoColors.primaryAction : Colors.transparent),
        child: Icon(icon, size: 22, color: _fg(k)),
      );

  Widget _rocker(String label, _RemoteKey? up, _RemoteKey? down) {
    final on = (up != null && _on(up)) || (down != null && _on(down));
    final fg = on ? MatapoColors.onPrimary : MatapoColors.primaryPressed;
    return AnimatedContainer(
      duration: MatapoMotion.focus,
      width: 36,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: on ? MatapoColors.primaryAction : MatapoColors.surfaceSelected,
        borderRadius: BorderRadius.circular(MatapoRadius.full),
      ),
      child: Column(
        children: [
          Icon(Icons.add_rounded, size: 16, color: fg),
          Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
          Icon(Icons.remove_rounded, size: 16, color: fg),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 124,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          gradient: featuredGradient,
          borderRadius: BorderRadius.circular(62),
          boxShadow: featuredShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: MatapoColors.primary, shape: BoxShape.circle)),
            const SizedBox(height: 14),
            Container(
              width: 98,
              height: 98,
              decoration: const BoxDecoration(color: MatapoColors.surface, shape: BoxShape.circle, boxShadow: cardShadow),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(top: 2, child: _arrow(_RemoteKey.up, Icons.keyboard_arrow_up_rounded)),
                  Positioned(bottom: 2, child: _arrow(_RemoteKey.down, Icons.keyboard_arrow_down_rounded)),
                  Positioned(left: 2, child: _arrow(_RemoteKey.left, Icons.keyboard_arrow_left_rounded)),
                  Positioned(right: 2, child: _arrow(_RemoteKey.right, Icons.keyboard_arrow_right_rounded)),
                  AnimatedContainer(
                    duration: MatapoMotion.focus,
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _bg(_RemoteKey.ok), shape: BoxShape.circle),
                    child: Text('OK', style: TextStyle(color: _fg(_RemoteKey.ok), fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _round(_RemoteKey.back, Icons.arrow_back_rounded),
                _round(_RemoteKey.home, Icons.home_rounded),
                _round(_RemoteKey.menu, Icons.menu_rounded),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_rocker('VOL', null, null), _rocker('CH', _RemoteKey.chUp, _RemoteKey.chDown)],
            ),
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: MatapoMotion.focus,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _bg(_RemoteKey.digits), borderRadius: BorderRadius.circular(MatapoRadius.sm)),
              child: Text('1 2 3 …', style: TextStyle(color: _fg(_RemoteKey.digits), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../debug/stress_screen.dart';
import '../main.dart' show AppScope, onAppExitRequested, showsVideo;
import '../state/app_state.dart';
import 'desktop_cameras.dart';
import 'desktop_grids.dart';
import 'desktop_live.dart';
import 'desktop_login.dart';
import 'desktop_settings.dart';
import 'desktop_theme.dart';

enum DesktopSection { cameras, grids, settings }

final desktopSection = ValueNotifier(DesktopSection.cameras);
final _navigatorKey = GlobalKey<NavigatorState>();

/// The macOS app: a regular desktop window (sidebar, mouse, menus, text
/// fields), built on the same state and video player as the TV app.
class MatapoDesktopApp extends StatefulWidget {
  const MatapoDesktopApp({super.key, required this.app});
  final AppState app;

  @override
  State<MatapoDesktopApp> createState() => _MatapoDesktopAppState();
}

class _MatapoDesktopAppState extends State<MatapoDesktopApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => widget.app.setForeground(showsVideo(state)),
      onExitRequested: onAppExitRequested,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _go(DesktopSection section) {
    if (widget.app.stage != AuthStage.signedIn) return;
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    desktopSection.value = section;
  }

  PlatformMenuItem _item(String label, LogicalKeyboardKey key, VoidCallback onSelected) => PlatformMenuItem(
        label: label,
        shortcut: SingleActivator(key, meta: true),
        onSelected: onSelected,
      );

  Widget _menus(Widget child) {
    final app = widget.app;
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Matapo',
          menus: [
            if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.about))
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformMenuItemGroup(members: [
              _item('Ajustes…', LogicalKeyboardKey.comma, () => _go(DesktopSection.settings)),
            ]),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
            ]),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
            ]),
          ],
        ),
        PlatformMenu(
          label: 'Ver',
          menus: [
            PlatformMenuItemGroup(members: [
              _item('Cámaras', LogicalKeyboardKey.digit1, () => _go(DesktopSection.cameras)),
              _item('Grillas', LogicalKeyboardKey.digit2, () => _go(DesktopSection.grids)),
              _item('Ajustes', LogicalKeyboardKey.digit3, () => _go(DesktopSection.settings)),
            ]),
            PlatformMenuItemGroup(members: [
              _item('Actualizar cámaras', LogicalKeyboardKey.keyR, () {
                if (app.stage == AuthStage.signedIn) app.refreshCameras();
              }),
            ]),
            if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.toggleFullScreen))
              const PlatformMenuItemGroup(members: [
                PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen),
              ]),
          ],
        ),
        const PlatformMenu(
          label: 'Ventana',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ],
        ),
      ],
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: widget.app,
      child: MaterialApp(
        title: 'Matapo',
        debugShowCheckedModeBanner: false,
        theme: buildDesktopTheme(),
        navigatorKey: _navigatorKey,
        builder: (context, child) => _menus(child!),
        home: const _DesktopRoot(),
      ),
    );
  }
}

class _DesktopRoot extends StatelessWidget {
  const _DesktopRoot();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget screen = switch (app.stage) {
      AuthStage.starting => const _Splash(),
      AuthStage.signedOut => const DesktopLoginScreen(key: ValueKey('login')),
      AuthStage.mfa => const DesktopMfaScreen(key: ValueKey('mfa')),
      AuthStage.signedIn when StressScreen.enabled => const StressScreen(),
      AuthStage.signedIn => const DesktopShell(key: ValueKey('shell')),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: screen);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/matapo.png', width: 88, height: 88),
            const SizedBox(height: 16),
            Text('Matapo', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(height: 12),
            Text('Conectando con tu cuenta de Tapo…', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key});

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent || desktopSection.value != DesktopSection.cameras) return KeyEventResult.ignored;
    final digit = int.tryParse(event.character ?? '');
    final cameras = AppScope.read(context).cameras;
    if (digit != null && digit >= 1 && digit <= cameras.length && digit <= 9) {
      openDesktopLive(context, digit - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) => _onKey(context, e),
        child: ValueListenableBuilder<DesktopSection>(
          valueListenable: desktopSection,
          builder: (context, section, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(section: section),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(section: section),
                    Expanded(
                      child: switch (section) {
                        DesktopSection.cameras => const CamerasSection(),
                        DesktopSection.grids => const GridsSection(),
                        DesktopSection.settings => const SettingsSection(),
                      },
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.section});
  final DesktopSection section;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final favorite = app.favoriteGrid;
    return Container(
      width: 220,
      color: DesktopColors.sidebar,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Image.asset('assets/matapo.png', width: 30, height: 30),
                const SizedBox(width: 10),
                Text('Matapo', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _NavItem(
            icon: Icons.videocam_outlined,
            label: 'Cámaras',
            trailing: '${app.cameras.length}',
            selected: section == DesktopSection.cameras,
            onTap: () => desktopSection.value = DesktopSection.cameras,
          ),
          _NavItem(
            icon: Icons.grid_view_outlined,
            label: 'Grillas',
            trailing: '${app.grids.length}',
            selected: section == DesktopSection.grids,
            onTap: () => desktopSection.value = DesktopSection.grids,
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Ajustes',
            selected: section == DesktopSection.settings,
            onTap: () => desktopSection.value = DesktopSection.settings,
          ),
          if (favorite != null) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 6),
              child: Text('FAVORITA', style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 0.6)),
            ),
            _NavItem(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFF2A900),
              label: favorite.isAuto ? 'Todas las cámaras' : favorite.name,
              selected: false,
              onTap: () => openDesktopGrid(context, favorite.id),
            ),
          ],
          const Spacer(),
          if (app.accountHint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.account_circle_outlined, size: 16, color: DesktopColors.secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(app.accountHint,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? trailing;
  final Color? iconColor;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? DesktopColors.accent : DesktopColors.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? DesktopColors.selected
                  : _hovered
                      ? DesktopColors.hover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 19, color: widget.iconColor ?? color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: color, fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                if (widget.trailing != null)
                  Text(widget.trailing!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.section});
  final DesktopSection section;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final (title, subtitle) = switch (section) {
      DesktopSection.cameras => (
          'Cámaras',
          app.cameras.isEmpty
              ? ''
              : 'Hacé clic en una cámara para verla en grande. Clic derecho para más opciones.',
        ),
      DesktopSection.grids => ('Grillas', 'Varias cámaras a la vez. Clic derecho para editar, duplicar o eliminar.'),
      DesktopSection.settings => ('Ajustes', ''),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (section == DesktopSection.cameras)
            OutlinedButton.icon(
              onPressed: app.loadingCameras ? null : app.refreshCameras,
              icon: app.loadingCameras
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Actualizar'),
            ),
          if (section == DesktopSection.grids)
            FilledButton.icon(
              onPressed: () => newDesktopGrid(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nueva grilla'),
            ),
        ],
      ),
    );
  }
}

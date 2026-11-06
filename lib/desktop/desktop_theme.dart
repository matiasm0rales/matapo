import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';

/// Desktop palette: the app's blues on calm, light macOS-style surfaces.
class DesktopColors {
  static const window = Color(0xFFF4F7FA);
  static const sidebar = Color(0xFFEAF0F6);
  static const card = Colors.white;
  static const border = Color(0xFFDCE4EC);
  static const hover = Color(0xFFE3EDF7);
  static const selected = Color(0xFFD5E7FA);
  static const text = Color(0xFF16202A);
  static const secondary = Color(0xFF5B6873);
  static const accent = MatapoColors.primaryAction;
  static const media = MatapoColors.media;
}

ThemeData buildDesktopTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MatapoColors.primary,
    brightness: Brightness.light,
    primary: MatapoColors.primaryAction,
    onPrimary: Colors.white,
    surface: DesktopColors.card,
    onSurface: DesktopColors.text,
    error: MatapoColors.error,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: DesktopColors.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: DesktopColors.window,
    // No fontFamily: Flutter uses the system font (SF Pro) on macOS.
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: DesktopColors.text),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: DesktopColors.text),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: DesktopColors.text),
      bodyLarge: TextStyle(fontSize: 14, color: DesktopColors.text),
      bodyMedium: TextStyle(fontSize: 13, color: DesktopColors.text),
      bodySmall: TextStyle(fontSize: 12, color: DesktopColors.secondary),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: MatapoColors.primaryAction, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: const BorderSide(color: DesktopColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    ),
    cardTheme: CardThemeData(
      color: DesktopColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DesktopColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: DesktopColors.border, thickness: 1, space: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 420),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    menuTheme: const MenuThemeData(style: MenuStyle(backgroundColor: WidgetStatePropertyAll(Colors.white))),
  );
}

/// Short message at the bottom of the window.
void showDesktopMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? MatapoColors.error : null,
      duration: const Duration(seconds: 3),
    ));
}

/// A menu item for [showContextMenu].
class MenuAction {
  const MenuAction(this.label, this.icon, this.onSelected, {this.danger = false});
  final String label;
  final IconData icon;
  final VoidCallback? onSelected;
  final bool danger;
}

/// A right-click style menu at [position] (global coordinates).
Future<void> showContextMenu(BuildContext context, Offset position, List<MenuAction?> actions) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(position);
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(local.dx, local.dy, overlay.size.width - local.dx, overlay.size.height - local.dy),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    color: Colors.white,
    items: [
      for (var i = 0; i < actions.length; i++)
        if (actions[i] == null)
          const PopupMenuDivider(height: 8)
        else
          PopupMenuItem<int>(
            value: i,
            height: 34,
            enabled: actions[i]!.onSelected != null,
            child: Row(
              children: [
                Icon(actions[i]!.icon, size: 18, color: actions[i]!.danger ? MatapoColors.error : DesktopColors.secondary),
                const SizedBox(width: 10),
                Text(
                  actions[i]!.label,
                  style: TextStyle(fontSize: 13, color: actions[i]!.danger ? MatapoColors.error : DesktopColors.text),
                ),
              ],
            ),
          ),
    ],
  );
  if (selected != null) actions[selected]?.onSelected?.call();
}

/// Confirmation dialog; returns true when the user confirms.
Future<bool> confirmDesktop(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: MatapoColors.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Native full screen of the app window (macOS).
class DesktopWindow {
  static const _channel = MethodChannel('matapo/window');

  static Future<void> toggleFullScreen() async {
    try {
      await _channel.invokeMethod<void>('toggleFullScreen');
    } catch (_) {}
  }

  static Future<bool> isFullScreen() async {
    try {
      return await _channel.invokeMethod<bool>('isFullScreen') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// A card that reacts to the mouse: highlighted border on hover, click and
/// right-click handlers.
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTap,
    this.tooltip,
  });
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final String? tooltip;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTap == null ? null : (d) => widget.onSecondaryTap!(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: DesktopColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hovered ? MatapoColors.primary : DesktopColors.border, width: _hovered ? 1.5 : 1),
            boxShadow: _hovered
                ? const [BoxShadow(color: Color(0x1A0B3A66), blurRadius: 14, offset: Offset(0, 4))]
                : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.builder(context, _hovered),
        ),
      ),
    );
  }
}

/// Round translucent icon button for use on top of video.
class MediaIconButton extends StatelessWidget {
  const MediaIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? MatapoColors.primaryAction : const Color(0xCC101820),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: onPressed == null ? Colors.white38 : Colors.white),
          ),
        ),
      ),
    );
  }
}

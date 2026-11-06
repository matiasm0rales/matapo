import 'package:flutter/material.dart';

import '../api/rtsp_probe.dart';
import '../main.dart' show AppScope;
import '../state/app_state.dart';
import '../state/local_cameras.dart';
import '../ui/theme.dart';
import 'desktop_theme.dart';

/// "Conexión local" dialog for one camera: IP, port and camera account for
/// video straight from the camera. Returns true when something was saved or
/// removed.
Future<bool> showLocalCameraDialog(BuildContext context, Camera camera) async {
  final changed = await showDialog<bool>(context: context, builder: (_) => _LocalCameraDialog(camera: camera));
  return changed ?? false;
}

class _LocalCameraDialog extends StatefulWidget {
  const _LocalCameraDialog({required this.camera});
  final Camera camera;

  @override
  State<_LocalCameraDialog> createState() => _LocalCameraDialogState();
}

class _LocalCameraDialogState extends State<_LocalCameraDialog> {
  late final AppState _app = AppScope.read(context);
  late final LocalCamera? _initial = _app.localCameraFor(widget.camera);
  late final _ip = TextEditingController(text: _initial?.ip ?? '');
  late final _port = TextEditingController(text: '${_initial?.port ?? LocalCamera.defaultPort}');
  late final _user = TextEditingController(text: _initial?.username ?? '');
  final _password = TextEditingController();

  bool _showPassword = false;
  bool _testing = false;
  bool _saving = false;
  String? _error;
  RtspProbeResult? _result;

  /// A password is stored already: an empty field keeps it.
  bool get _hasStoredPassword => _app.hasLocal(widget.camera);

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  /// The form as a [LocalCamera], or null (with [_error] set) when invalid.
  LocalCamera? _read() {
    final error = validateLocalCamera(ip: _ip.text, port: _port.text, username: _user.text) ??
        (_password.text.isEmpty && !_hasStoredPassword ? 'Ingresá la contraseña de la cuenta de la cámara' : null);
    setState(() => _error = error);
    if (error != null) return null;
    return LocalCamera(ip: _ip.text.trim(), port: int.parse(_port.text.trim()), username: _user.text);
  }

  Future<void> _test() async {
    final cam = _read();
    if (cam == null) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await _app.testLocal(widget.camera.deviceId, cam, _password.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  Future<void> _save() async {
    final cam = _read();
    if (cam == null) return;
    setState(() => _saving = true);
    try {
      await _app.setLocalCamera(widget.camera.deviceId, cam, _password.text.isEmpty ? null : _password.text);
      if (!mounted) return;
      Navigator.pop(context, true);
      showDesktopMessage(context, 'Conexión local guardada para ${widget.camera.name}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'No se pudo guardar la contraseña: $e';
        });
      }
    }
  }

  Future<void> _remove() async {
    await _app.setLocalCamera(widget.camera.deviceId, null, null);
    if (!mounted) return;
    Navigator.pop(context, true);
    showDesktopMessage(context, '${widget.camera.name} va a usar solo la nube');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return AlertDialog(
      title: Text('Conexión local · ${widget.camera.name}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Con la IP y la cuenta de la cámara, el video llega directo desde la cámara cuando estás en casa. '
              'Fuera de casa, Matapo usa la nube sola.',
              style: theme.textTheme.bodyMedium?.copyWith(color: DesktopColors.secondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ip,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'IP de la cámara', hintText: '192.168.0.50'),
                    onChanged: (_) => setState(() => _result = null),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Puerto'),
                    onChanged: (_) => setState(() => _result = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Usuario de la cámara'),
              onChanged: (_) => setState(() => _result = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Contraseña de la cámara',
                hintText: _hasStoredPassword ? 'Dejala vacía para mantener la guardada' : null,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onChanged: (_) => setState(() => _result = null),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            Text(
              'Usá la cuenta de la cámara (app de Tapo → cámara → Configuración avanzada → Cuenta de la cámara). '
              'Conviene reservar la IP en el router para que no cambie.',
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: MatapoColors.error)),
            ],
            if (_testing || result != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_testing)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(
                      result!.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 18,
                      color: result.ok ? MatapoColors.success : MatapoColors.error,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testing ? 'Probando la conexión…' : result!.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _testing ? DesktopColors.secondary : (result!.ok ? MatapoColors.success : MatapoColors.error),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_initial != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: MatapoColors.error),
            onPressed: _saving ? null : _remove,
            child: const Text('Quitar'),
          ),
        OutlinedButton(onPressed: _testing || _saving ? null : _test, child: const Text('Probar')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

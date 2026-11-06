import 'package:flutter/material.dart';

import '../api/rtsp_probe.dart';
import '../main.dart';
import '../state/app_state.dart';
import '../state/local_cameras.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';

Future<void> openLocalCameras(BuildContext context) => Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: MatapoMotion.navigation,
        pageBuilder: (_, _, _) => const LocalCamerasScreen(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );

/// TV: the cameras and whether each one has video over the home network.
class LocalCamerasScreen extends StatelessWidget {
  const LocalCamerasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: Padding(
        padding: tvSafePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Conexión local', style: MatapoText.headline),
            const SizedBox(height: MatapoSpace.sm),
            Text(
              'En casa, el video llega directo desde la cámara, sin pasar por la nube de Tapo. '
              'Fuera de casa se usa la nube sola. El movimiento y el modo privacidad siguen por la nube.',
              style: MatapoText.body.copyWith(color: MatapoColors.muted),
            ),
            const SizedBox(height: MatapoSpace.lg),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  if (app.cameras.isEmpty) const Text('No hay cámaras en esta cuenta', style: MatapoText.body),
                  for (final (i, camera) in app.cameras.indexed) ...[
                    TvTile(
                      title: camera.name,
                      subtitle: app.hasLocal(camera)
                          ? 'Local configurada · ${app.localCameraFor(camera)!.authority}'
                          : 'Solo nube',
                      icon: app.hasLocal(camera) ? Icons.home_rounded : Icons.cloud_rounded,
                      autofocus: i == 0,
                      trailing: const Icon(Icons.chevron_right_rounded, color: MatapoColors.muted),
                      onSelect: () => showTvDialog<void>(context, (_) => _LocalCameraForm(camera: camera)),
                    ),
                    const SizedBox(height: MatapoSpace.md),
                  ],
                ],
              ),
            ),
            const SizedBox(height: MatapoSpace.sm),
            HintBar([
              (const KeyCap('OK'), 'Configurar'),
              (const KeyCap('', icon: Icons.arrow_back_rounded), 'Volver'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _LocalCameraForm extends StatefulWidget {
  const _LocalCameraForm({required this.camera});
  final Camera camera;

  @override
  State<_LocalCameraForm> createState() => _LocalCameraFormState();
}

class _LocalCameraFormState extends State<_LocalCameraForm> {
  late final AppState _app = AppScope.read(context);
  late final LocalCamera? _initial = _app.localCameraFor(widget.camera);
  late String _ip = _initial?.ip ?? '';
  late String _port = '${_initial?.port ?? LocalCamera.defaultPort}';
  late String _user = _initial?.username ?? '';
  String _password = '';
  bool _testing = false;
  bool _saving = false;
  String? _error;
  RtspProbeResult? _result;

  bool get _hasStoredPassword => _app.hasLocal(widget.camera);

  LocalCamera? _read() {
    final error = validateLocalCamera(ip: _ip, port: _port, username: _user) ??
        (_password.isEmpty && !_hasStoredPassword ? 'Ingresá la contraseña de la cuenta de la cámara' : null);
    setState(() => _error = error);
    if (error != null) return null;
    return LocalCamera(ip: _ip.trim(), port: int.parse(_port.trim()), username: _user);
  }

  Future<void> _test() async {
    final cam = _read();
    if (cam == null) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await _app.testLocal(widget.camera.deviceId, cam, _password);
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
      await _app.setLocalCamera(widget.camera.deviceId, cam, _password.isEmpty ? null : _password);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Conexión local guardada para ${widget.camera.name}');
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
    final ok = await confirmDialog(
      context,
      title: '¿Quitar la conexión local?',
      message: '${widget.camera.name} va a usar solo la nube.',
      confirmLabel: 'Quitar',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _app.setLocalCamera(widget.camera.deviceId, null, null);
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, '${widget.camera.name} va a usar solo la nube');
  }

  void _changed(void Function() update) => setState(() {
        update();
        _result = null;
      });

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return TvDialog(
      title: 'Conexión local · ${widget.camera.name}',
      message: 'Usá la cuenta de la cámara (app de Tapo → cámara → Configuración avanzada → Cuenta de la cámara). '
          'Conviene reservar la IP en el router.',
      maxWidth: 760,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TvTextField(
                label: 'IP de la cámara',
                value: _ip,
                hint: '192.168.0.50',
                icon: Icons.lan_rounded,
                keyboardType: TextInputType.url,
                autofocus: true,
                onChanged: (v) => _changed(() => _ip = v.trim()),
              ),
            ),
            const SizedBox(width: MatapoSpace.md),
            SizedBox(
              width: 160,
              child: TvTextField(
                label: 'Puerto',
                value: _port,
                keyboardType: TextInputType.number,
                onChanged: (v) => _changed(() => _port = v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: MatapoSpace.md),
        TvTextField(
          label: 'Usuario de la cámara',
          value: _user,
          icon: Icons.person_rounded,
          onChanged: (v) => _changed(() => _user = v),
        ),
        const SizedBox(height: MatapoSpace.md),
        TvTextField(
          label: 'Contraseña de la cámara',
          value: _password,
          hint: _hasStoredPassword ? 'Guardada (dejala vacía para mantenerla)' : '',
          icon: Icons.lock_rounded,
          obscure: true,
          onChanged: (v) => _changed(() => _password = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: MatapoSpace.md),
          Text(_error!, style: MatapoText.body.copyWith(color: MatapoColors.error)),
        ],
        if (_testing || result != null) ...[
          const SizedBox(height: MatapoSpace.md),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                if (_testing)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))
                else
                  Icon(
                    result!.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    color: result.ok ? MatapoColors.success : MatapoColors.error,
                  ),
                const SizedBox(width: MatapoSpace.sm),
                Expanded(
                  child: Text(
                    _testing ? 'Probando la conexión…' : result!.message,
                    style: MatapoText.label.copyWith(
                      color: _testing ? MatapoColors.muted : (result!.ok ? MatapoColors.success : MatapoColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: MatapoSpace.x2),
        Wrap(
          spacing: MatapoSpace.md,
          runSpacing: MatapoSpace.md,
          children: [
            TvButton(label: 'Probar', icon: Icons.wifi_find_rounded, busy: _testing, onPressed: _testing ? null : _test),
            TvButton(
              label: 'Guardar',
              icon: Icons.check_rounded,
              style: TvButtonStyle.primary,
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (_initial != null)
              TvButton(label: 'Quitar', icon: Icons.delete_outline_rounded, style: TvButtonStyle.danger, onPressed: _remove),
            TvButton(label: 'Cancelar', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ],
    );
  }
}

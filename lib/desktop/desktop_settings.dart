import 'package:flutter/material.dart';

import '../main.dart' show AppScope;
import '../ui/theme.dart';
import 'desktop_local_camera.dart';
import 'desktop_theme.dart';

const appVersionLabel = '1.2.0';

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    Widget group(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: DesktopColors.secondary)),
              ),
              Card(child: Column(children: children)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                group('Video', [
                  SwitchListTile(
                    value: app.livePreviews,
                    onChanged: app.setLivePreviews,
                    title: const Text('Vistas previas en vivo'),
                    subtitle: const Text('Muestra el video de cada cámara en la lista. Desactivalo para ahorrar datos y batería.'),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Paso de movimiento'),
                    subtitle: const Text('Cuánto gira la cámara con cada flecha.'),
                    trailing: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 5, label: Text('5°')),
                        ButtonSegment(value: 10, label: Text('10°')),
                        ButtonSegment(value: 20, label: Text('20°')),
                      ],
                      selected: {app.ptzStep},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => app.setPtzStep(s.first),
                    ),
                  ),
                ]),
                group('Conexión local', [
                  ListTile(
                    leading: const Icon(Icons.lan_outlined),
                    title: const Text('Video directo desde la cámara'),
                    subtitle: const Text(
                      'En casa, el video llega por la red local, sin pasar por la nube de Tapo. '
                      'Fuera de casa se usa la nube sola. El movimiento y el modo privacidad siguen por la nube.',
                    ),
                  ),
                  for (final camera in app.cameras) ...[
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        app.hasLocal(camera) ? Icons.home_rounded : Icons.cloud_outlined,
                        color: app.hasLocal(camera) ? MatapoColors.success : DesktopColors.secondary,
                      ),
                      title: Text(camera.name),
                      subtitle: Text(
                        app.hasLocal(camera)
                            ? 'Local configurada · ${app.localCameraFor(camera)!.authority}'
                            : 'Solo nube',
                      ),
                      trailing: OutlinedButton(
                        onPressed: () => showLocalCameraDialog(context, camera),
                        child: const Text('Configurar…'),
                      ),
                    ),
                  ],
                ]),
                group('Cuenta', [
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(app.accountHint.isEmpty ? 'Cuenta de Tapo' : app.accountHint),
                    subtitle: Text('Servidor: ${app.regionHost}'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('Cerrar sesión'),
                    subtitle: const Text('Borra la sesión guardada en esta computadora.'),
                    onTap: () async {
                      final ok = await confirmDesktop(
                        context,
                        title: 'Cerrar sesión',
                        message: 'Vas a necesitar tu contraseña de Tapo para volver a entrar.',
                        confirm: 'Cerrar sesión',
                      );
                      if (ok) await app.logout();
                    },
                  ),
                ]),
                group('Acerca de', [
                  ListTile(
                    leading: Image.asset('assets/matapo.png', width: 36, height: 36),
                    title: const Text('Matapo $appVersionLabel'),
                    subtitle: const Text(
                      'Basada en Topo TV de Abdul Momin Sakib y en Topo de filirnd. Licencia MIT. '
                      'No está afiliada a TP-Link; Tapo es una marca de TP-Link.',
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

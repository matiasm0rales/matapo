import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';
import 'local_cameras_screen.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget value(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: MatapoSpace.md, vertical: 6),
          decoration: BoxDecoration(color: MatapoColors.surface, borderRadius: BorderRadius.circular(MatapoRadius.full)),
          child: Text(text, style: MatapoText.label.copyWith(color: MatapoColors.primaryPressed)),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              TvTile(
                title: 'Cuenta de Tapo',
                subtitle: app.accountHint.isEmpty ? 'Sesión iniciada · ${app.regionHost}' : '${app.accountHint} · ${app.regionHost}',
                icon: Icons.person_rounded,
                autofocus: true,
              ),
              const SizedBox(height: MatapoSpace.md),
              TvTile(
                title: 'Vistas previas en vivo en la lista de cámaras',
                subtitle: 'Desactivalo para ahorrar datos en TV más lentos',
                icon: Icons.videocam_rounded,
                // Changes only on OK, never on focus.
                trailing: ExcludeFocus(
                  child: Switch(
                    value: app.livePreviews,
                    activeThumbColor: MatapoColors.onPrimary,
                    activeTrackColor: MatapoColors.primaryAction,
                    onChanged: (v) => app.setLivePreviews(v),
                  ),
                ),
                onSelect: () => app.setLivePreviews(!app.livePreviews),
              ),
              const SizedBox(height: MatapoSpace.md),
              TvTile(
                title: 'Paso de movimiento',
                subtitle: 'Cuánto gira la cámara con cada flecha',
                icon: Icons.open_with_rounded,
                trailing: value('${app.ptzStep}°'),
                onSelect: () {
                  const steps = [5, 10, 20];
                  app.setPtzStep(steps[(steps.indexOf(app.ptzStep) + 1) % steps.length]);
                },
              ),
              const SizedBox(height: MatapoSpace.md),
              TvTile(
                title: 'Conexión local',
                subtitle: () {
                  final n = app.cameras.where(app.hasLocal).length;
                  return n == 0
                      ? 'Video directo desde las cámaras en tu casa'
                      : n == 1
                          ? '1 cámara con video local'
                          : '$n cámaras con video local';
                }(),
                icon: Icons.lan_rounded,
                trailing: const Icon(Icons.chevron_right_rounded, color: MatapoColors.muted),
                onSelect: () => openLocalCameras(context),
              ),
              const SizedBox(height: MatapoSpace.md),
              TvTile(
                title: 'Guía del control remoto',
                subtitle: 'Qué hace cada botón',
                icon: Icons.help_outline_rounded,
                trailing: const Icon(Icons.chevron_right_rounded, color: MatapoColors.muted),
                onSelect: () => showRemoteGuide(context),
              ),
              const SizedBox(height: MatapoSpace.md),
              TvTile(
                title: 'Cerrar sesión',
                subtitle: 'Borra la sesión de Tapo guardada en este TV',
                icon: Icons.logout_rounded,
                danger: true,
                onSelect: () async {
                  final ok = await confirmDialog(
                    context,
                    title: '¿Cerrar sesión?',
                    message: 'Vas a necesitar tu contraseña de Tapo y un código de verificación para volver a entrar.',
                    confirmLabel: 'Cerrar sesión',
                    danger: true,
                  );
                  if (ok && context.mounted) await app.logout();
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: MatapoSpace.x3),
        SizedBox(
          width: 250,
          child: Container(
            padding: const EdgeInsets.all(MatapoSpace.x2),
            decoration: BoxDecoration(
              gradient: featuredGradient,
              borderRadius: BorderRadius.circular(MatapoRadius.lg),
              boxShadow: featuredShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/matapo.png', width: 56, height: 56, semanticLabel: 'Matapo'),
                const SizedBox(height: MatapoSpace.md),
                const Text('Matapo 1.2.0', style: MatapoText.label),
                const SizedBox(height: MatapoSpace.xs),
                const Text(
                  'Basada en Topo TV de Abdul Momin Sakib y en Topo de filirnd. Licencia MIT. No está afiliada a TP-Link.',
                  style: MatapoText.caption,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

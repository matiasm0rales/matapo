import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/guide.dart';
import '../ui/theme.dart';
import '../ui/tv.dart';

/// Featured panel on the left of the sign-in screens.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    Widget feature(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: MatapoSpace.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: MatapoColors.surface, borderRadius: BorderRadius.circular(MatapoRadius.md)),
                child: Icon(icon, color: MatapoColors.primary, size: 24),
              ),
              const SizedBox(width: MatapoSpace.lg),
              Expanded(child: Text(text, style: MatapoText.body)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(MatapoSpace.x3),
      decoration: BoxDecoration(
        gradient: featuredGradient,
        borderRadius: BorderRadius.circular(MatapoRadius.xl),
        boxShadow: featuredShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Image.asset('assets/matapo.png', width: 64, height: 64, semanticLabel: 'Matapo'),
              const SizedBox(width: MatapoSpace.md),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Matapo', style: MatapoText.display),
                  Text('para Android TV', style: TextStyle(fontSize: 16, color: MatapoColors.primaryAction, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: MatapoSpace.x2),
          const Text('Tus cámaras Tapo en la pantalla grande.', style: MatapoText.title),
          const SizedBox(height: MatapoSpace.xl),
          feature(Icons.cloud_rounded, 'Video en vivo a través de la nube de Tapo'),
          feature(Icons.grid_view_rounded, 'Grillas de varias cámaras que podés guardar'),
          feature(Icons.open_with_rounded, 'Movimiento de la cámara con el control remoto'),
          const SizedBox(height: MatapoSpace.sm),
          const Text('App no oficial, sin relación con TP-Link.', style: MatapoText.caption),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.card});
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: tvSafePadding,
        child: Row(
          children: [
            const Expanded(flex: 10, child: Center(child: _Brand())),
            const SizedBox(width: MatapoSpace.x3),
            Expanded(
              flex: 11,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    padding: const EdgeInsets.all(MatapoSpace.x3),
                    decoration: BoxDecoration(
                      color: MatapoColors.surface,
                      borderRadius: BorderRadius.circular(MatapoRadius.xl),
                      boxShadow: cardShadow,
                    ),
                    child: card,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: MatapoSpace.md),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_rounded, color: MatapoColors.error, size: 22),
            const SizedBox(width: MatapoSpace.sm),
            Expanded(child: Text(text!, style: MatapoText.body.copyWith(color: MatapoColors.error, height: 1.3))),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordFocus = FocusNode();
  final _signInFocus = FocusNode();
  late String _email = AppScope.read(context).accountHint;
  String _password = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    guideSection.value = GuideSection.basics;
    _error = AppScope.read(context).camerasError;
  }

  @override
  void dispose() {
    _passwordFocus.dispose();
    _signInFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_email, _password);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Shell(
      card: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Iniciar sesión', style: MatapoText.headline),
          const Text('Usá la misma cuenta que en la app de Tapo.', style: MatapoText.caption),
          const SizedBox(height: MatapoSpace.xl),
          TvTextField(
            label: 'Correo electrónico',
            hint: 'nombre@ejemplo.com',
            icon: Icons.alternate_email_rounded,
            value: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onChanged: (v) => setState(() => _email = v.trim()),
            onSubmitted: () => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: MatapoSpace.lg),
          TvTextField(
            label: 'Contraseña',
            hint: 'Tu contraseña de Tapo',
            icon: Icons.lock_rounded,
            value: _password,
            obscure: true,
            focusNode: _passwordFocus,
            onChanged: (v) => setState(() => _password = v),
            onSubmitted: () => _signInFocus.requestFocus(),
          ),
          _ErrorText(_error),
          const SizedBox(height: MatapoSpace.x2),
          TvButton(
            label: _busy ? 'Iniciando sesión…' : 'Iniciar sesión',
            icon: Icons.login_rounded,
            style: TvButtonStyle.primary,
            focusNode: _signInFocus,
            busy: _busy,
            expand: true,
            onPressed: _signIn,
          ),
          const SizedBox(height: MatapoSpace.md),
          Row(
            children: [
              TvButton(
                label: 'Guía del control',
                icon: Icons.help_outline_rounded,
                style: TvButtonStyle.text,
                onPressed: () => showRemoteGuide(context),
              ),
              if (app.hasSavedSession) ...[
                const SizedBox(width: MatapoSpace.sm),
                TvButton(
                  label: 'Reintentar la sesión guardada',
                  icon: Icons.refresh_rounded,
                  style: TvButtonStyle.text,
                  onPressed: app.retrySavedSession,
                ),
              ],
            ],
          ),
          const SizedBox(height: MatapoSpace.sm),
          const Text('Tu contraseña nunca se guarda en este TV.', style: MatapoText.caption),
        ],
      ),
    );
  }
}

class MfaScreen extends StatefulWidget {
  const MfaScreen({super.key});

  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  final _codeFocus = FocusNode();
  final _verifyFocus = FocusNode();
  String _code = '';
  int? _sending;
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _codeFocus.dispose();
    _verifyFocus.dispose();
    super.dispose();
  }

  Future<void> _request(int type) async {
    setState(() {
      _sending = type;
      _error = null;
    });
    try {
      await AppScope.read(context).requestMfa(type);
      WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await AppScope.read(context).verifyMfa(_code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Widget _spinner() => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: MatapoColors.primaryAction),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pending = app.pendingMfa;
    if (pending == null) return const SizedBox.shrink();
    final requested = pending.requestedType;
    const chevron = Icon(Icons.chevron_right_rounded, color: MatapoColors.muted);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.cancelMfa();
      },
      child: _Shell(
        card: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Verify it's you", style: MatapoText.headline),
            Text(
              requested == null
                  ? 'Este TV es nuevo para tu cuenta de Tapo. Elegí cómo recibir el código.'
                  : requested == 1
                      ? 'Abrí la app de Tapo en tu teléfono e ingresá el código que muestra.'
                      : 'Ingresá el código que enviamos a ${pending.username}.',
              style: MatapoText.caption,
            ),
            const SizedBox(height: MatapoSpace.xl),
            if (requested == null) ...[
              if (pending.types.contains(1)) ...[
                TvTile(
                  title: 'Notificación en la app de Tapo',
                  subtitle: 'Recibí el código en tu teléfono',
                  icon: Icons.phone_iphone_rounded,
                  autofocus: true,
                  trailing: _sending == 1 ? _spinner() : chevron,
                  onSelect: _sending == null ? () => _request(1) : null,
                ),
                const SizedBox(height: MatapoSpace.md),
              ],
              if (pending.types.contains(2))
                TvTile(
                  title: 'Código por correo',
                  subtitle: 'Enviar un código a ${pending.username}',
                  icon: Icons.mail_rounded,
                  autofocus: !pending.types.contains(1),
                  trailing: _sending == 2 ? _spinner() : chevron,
                  onSelect: _sending == null ? () => _request(2) : null,
                ),
            ] else ...[
              TvTextField(
                label: 'Código de verificación',
                hint: 'Código de 6 dígitos',
                icon: Icons.pin_rounded,
                value: _code,
                keyboardType: TextInputType.number,
                focusNode: _codeFocus,
                onChanged: (v) => setState(() => _code = v.trim()),
                onSubmitted: () => _verifyFocus.requestFocus(),
              ),
              const SizedBox(height: MatapoSpace.xl),
              TvButton(
                label: _verifying ? 'Verificando…' : 'Verificar',
                icon: Icons.verified_user_rounded,
                style: TvButtonStyle.primary,
                expand: true,
                busy: _verifying,
                focusNode: _verifyFocus,
                onPressed: _verify,
              ),
              const SizedBox(height: MatapoSpace.md),
              Wrap(
                spacing: MatapoSpace.sm,
                children: [
                  TvButton(
                    label: 'Enviar de nuevo',
                    icon: Icons.refresh_rounded,
                    style: TvButtonStyle.text,
                    busy: _sending != null,
                    onPressed: () => _request(requested),
                  ),
                  if (pending.types.length > 1)
                    TvButton(
                      label: requested == 1 ? 'Usar el correo' : 'Usar la app de Tapo',
                      style: TvButtonStyle.text,
                      onPressed: () => _request(requested == 1 ? 2 : 1),
                    ),
                ],
              ),
            ],
            _ErrorText(_error),
            const SizedBox(height: MatapoSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                label: 'Volver a iniciar sesión',
                icon: Icons.arrow_back_rounded,
                style: TvButtonStyle.text,
                onPressed: app.cancelMfa,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

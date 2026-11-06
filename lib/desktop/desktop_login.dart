import 'package:flutter/material.dart';

import '../main.dart' show AppScope;
import '../ui/theme.dart';
import 'desktop_theme.dart';

/// Centered card used by sign-in and verification.
class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Image.asset('assets/matapo.png', width: 64, height: 64, semanticLabel: 'Matapo'),
        const SizedBox(height: 12),
        Text('Matapo', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: DesktopColors.secondary)),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: MatapoColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: MatapoColors.error, fontSize: 13))),
        ],
      ),
    );
  }
}

const _spinner = SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

class DesktopLoginScreen extends StatefulWidget {
  const DesktopLoginScreen({super.key});

  @override
  State<DesktopLoginScreen> createState() => _DesktopLoginScreenState();
}

class _DesktopLoginScreenState extends State<DesktopLoginScreen> {
  late final _email = TextEditingController(text: AppScope.read(context).accountHint);
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  bool _retrying = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retrySaved() async {
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      await AppScope.read(context).retrySavedSession();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _AuthCard(
      children: [
        const _Brand(subtitle: 'Iniciá sesión con la misma cuenta que usás en la app de Tapo.'),
        TextField(
          controller: _email,
          autofocus: _email.text.isEmpty,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded, size: 20)),
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          autofocus: _email.text.isNotEmpty,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _signIn(),
        ),
        const SizedBox(height: 16),
        _ErrorText(_error),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: SizedBox(height: 20, child: Center(child: _busy ? _spinner : const Text('Iniciar sesión'))),
        ),
        if (app.hasSavedSession) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _retrying ? null : _retrySaved,
            child: Text(_retrying ? 'Reintentando…' : 'Reintentar la sesión guardada'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Tu contraseña no se guarda en esta computadora. Matapo no está afiliada a TP-Link.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class DesktopMfaScreen extends StatefulWidget {
  const DesktopMfaScreen({super.key});

  @override
  State<DesktopMfaScreen> createState() => _DesktopMfaScreenState();
}

class _DesktopMfaScreenState extends State<DesktopMfaScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  int? _sending;
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
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
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await AppScope.read(context).verifyMfa(_code.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  static String _typeLabel(int type) => switch (type) {
        1 => 'Notificación en la app de Tapo',
        2 => 'Correo electrónico',
        _ => 'Método $type',
      };

  static IconData _typeIcon(int type) => type == 2 ? Icons.mail_outline_rounded : Icons.phone_iphone_rounded;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pending = app.pendingMfa;
    final requested = pending?.requestedType;
    final types = pending?.types ?? const <int>[];
    return _AuthCard(
      children: [
        _Brand(
          subtitle: requested == null
              ? 'Esta computadora es nueva para tu cuenta de Tapo. Elegí cómo recibir el código de verificación.'
              : requested == 1
                  ? 'Abrí la app de Tapo en tu teléfono para ver el código.'
                  : 'Te enviamos el código por correo electrónico.',
        ),
        if (requested == null)
          for (final type in types) ...[
            OutlinedButton.icon(
              onPressed: _sending != null ? null : () => _request(type),
              icon: _sending == type
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_typeIcon(type), size: 18),
              label: Text(_typeLabel(type)),
            ),
            const SizedBox(height: 8),
          ]
        else ...[
          TextField(
            controller: _code,
            focusNode: _codeFocus,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(labelText: 'Código de verificación', prefixIcon: Icon(Icons.pin_outlined, size: 20)),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 16),
          _ErrorText(_error),
          FilledButton(
            onPressed: _verifying ? null : _verify,
            child: SizedBox(height: 20, child: Center(child: _verifying ? _spinner : const Text('Verificar'))),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _sending != null ? null : () => _request(requested),
                child: const Text('Enviar de nuevo'),
              ),
              for (final other in types.where((t) => t != requested))
                TextButton(
                  onPressed: _sending != null ? null : () => _request(other),
                  child: Text(other == 1 ? 'Usar la app de Tapo' : 'Usar el correo'),
                ),
            ],
          ),
        ],
        if (requested == null) _ErrorText(_error),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: app.cancelMfa,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Volver a iniciar sesión'),
        ),
      ],
    );
  }
}

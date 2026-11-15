import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import 'auth_shell.dart';

/// Recuperar la contraseña: envía el enlace y confirma en la misma pantalla a qué correo.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _sentTo;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailController.text.trim();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: '${Uri.base.origin}/?mode=resetPassword',
          handleCodeInApp: true,
        ),
      );
      if (mounted) setState(() => _sentTo = email);
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => 'No encontramos una cuenta con este correo. Revisa que esté bien escrito.',
        'invalid-email' => 'Revisa el correo: parece incompleto.',
        'too-many-requests' => 'Pediste varios enlaces seguidos. Espera unos minutos e intenta de nuevo.',
        _ => friendlyError(e, fallback: 'No pudimos enviar el correo. Intenta de nuevo.'),
      };
      if (mounted) setState(() => _error = message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo;
    if (sent != null) {
      return AuthShell(
        onBack: widget.onBack,
        backTooltip: 'Volver a iniciar sesión',
        photo: 3,
        title: 'Revisa tu correo',
        subtitle: 'Si hay una cuenta con ese correo, te llegará un enlace para elegir una contraseña nueva.',
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.mark_email_read_outlined, color: OhtliColors.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sent,
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Puede tardar un par de minutos. Si no lo ves, busca en la carpeta de spam o promociones.',
            style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(label: 'Volver a iniciar sesión', onPressed: widget.onBack),
          const SizedBox(height: 10),
          Center(
            child: AuthLink(
              'Usar otro correo',
              onTap: () => setState(() => _sentTo = null),
            ),
          ),
        ],
      );
    }

    return AuthShell(
      onBack: widget.onBack,
      backTooltip: 'Volver a iniciar sesión',
      photo: 3,
      title: '¿Olvidaste tu contraseña?',
      subtitle: 'Escribe el correo de tu cuenta y te enviamos un enlace para elegir una nueva.',
      children: [
        Form(
          key: _formKey,
          child: AuthField(
            controller: _emailController,
            label: 'Correo electrónico',
            hint: 'nombre@correo.com',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            onChanged: (_) => _error == null ? null : setState(() => _error = null),
            validator: validateEmail,
          ),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          AuthErrorBox(_error!),
          const SizedBox(height: 16),
        ],
        AuthPrimaryButton(label: 'Enviar enlace', loading: _loading, onPressed: _send),
        const SizedBox(height: 14),
        Center(child: AuthLink('Volver a iniciar sesión', onTap: widget.onBack)),
      ],
    );
  }
}

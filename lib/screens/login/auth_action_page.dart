import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../register/register_page.dart' show PasswordChecklist, PasswordRules;
import 'auth_shell.dart';

/// Destino de los enlaces que manda Firebase por correo: confirmar el correo
/// (`mode=verifyEmail`) o elegir una contraseña nueva (`mode=resetPassword`).
class AuthActionPage extends StatefulWidget {
  const AuthActionPage({
    super.key,
    required this.mode,
    required this.oobCode,
    required this.onBackToLogin,
  });

  final String mode;
  final String oobCode;
  final VoidCallback onBackToLogin;

  @override
  State<AuthActionPage> createState() => _AuthActionPageState();
}

class _AuthActionPageState extends State<AuthActionPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _verifying = true;
  bool _saving = false;
  bool _success = false;
  bool _triedSubmit = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _email = '';

  /// Error que impide seguir (enlace vencido o inválido).
  String? _fatal;

  /// Error al guardar la contraseña nueva (se puede reintentar).
  String? _error;

  bool get _isReset => widget.mode == 'resetPassword';

  @override
  void initState() {
    super.initState();
    _executeAction();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _linkError(FirebaseAuthException e) => switch (e.code) {
        'expired-action-code' => 'Este enlace ya venció. Pide uno nuevo desde la pantalla de inicio de sesión.',
        'invalid-action-code' =>
          'Este enlace ya se usó o está incompleto. Si lo copiaste, revisa que esté completo, o pide uno nuevo.',
        'user-disabled' => 'La cuenta de este enlace está desactivada.',
        'user-not-found' => 'Ya no existe la cuenta de este enlace.',
        _ => friendlyError(e, fallback: 'No pudimos abrir este enlace. Pide uno nuevo.'),
      };

  Future<void> _executeAction() async {
    try {
      if (_isReset) {
        _email = await FirebaseAuth.instance.verifyPasswordResetCode(widget.oobCode);
      } else if (widget.mode == 'verifyEmail') {
        await FirebaseAuth.instance.applyActionCode(widget.oobCode);
        // Si la cuenta tiene la sesión abierta, que la app vea el correo ya confirmado
        try {
          await FirebaseAuth.instance.currentUser?.reload();
        } catch (_) {}
        _success = true;
      } else {
        _fatal = 'Este enlace no es de Ohtli o ya no se usa.';
      }
    } on FirebaseAuthException catch (e) {
      _fatal = _linkError(e);
    } catch (e) {
      _fatal = friendlyError(e, fallback: 'No pudimos abrir este enlace. Pide uno nuevo.');
    }
    if (mounted) setState(() => _verifying = false);
  }

  Future<void> _saveNewPassword() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _triedSubmit = true;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: _passwordController.text,
      );
      if (mounted) setState(() => _success = true);
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'weak-password' || 'password-does-not-meet-requirements' =>
          'La contraseña no cumple los requisitos. Revisa la lista.',
        _ => _linkError(e),
      };
      if (mounted) setState(() => _error = message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verifying) {
      return AuthShell(
        onBack: widget.onBackToLogin,
        title: _isReset ? 'Un momento…' : 'Confirmando tu correo…',
        subtitle: 'Estamos revisando el enlace.',
        children: [
          Center(child: CircularProgressIndicator(color: OhtliColors.accentText)),
        ],
      );
    }

    if (_fatal != null) {
      return AuthShell(
        onBack: widget.onBackToLogin,
        title: 'Este enlace no funcionó',
        subtitle: 'No pasa nada: puedes pedir uno nuevo en unos segundos.',
        children: [
          AuthErrorBox(_fatal!),
          const SizedBox(height: 22),
          AuthPrimaryButton(label: 'Ir a iniciar sesión', onPressed: widget.onBackToLogin),
        ],
      );
    }

    if (_success) {
      return AuthShell(
        onBack: widget.onBackToLogin,
        title: _isReset ? 'Contraseña actualizada' : 'Correo confirmado',
        subtitle: _isReset
            ? 'Ya puedes entrar a Ohtli con tu contraseña nueva.'
            : 'Gracias. Tu cuenta de Ohtli quedó lista.',
        children: [
          Icon(Icons.check_circle_rounded, size: 52, color: OhtliColors.accentText),
          const SizedBox(height: 22),
          AuthPrimaryButton(
            label: _isReset ? 'Iniciar sesión' : 'Continuar',
            onPressed: widget.onBackToLogin,
          ),
        ],
      );
    }

    return AuthShell(
      onBack: widget.onBackToLogin,
      title: 'Elige una contraseña nueva',
      subtitle: 'Para la cuenta $_email.',
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _triedSubmit ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthField(
                  controller: _passwordController,
                  label: 'Contraseña nueva',
                  obscure: _obscurePassword,
                  onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() => _error = null),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Escribe tu contraseña nueva.';
                    if (!PasswordRules.meetsAll(v)) return 'Aún le falta algo de la lista.';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                PasswordChecklist(password: _passwordController.text, highlightMissing: _triedSubmit),
                const SizedBox(height: 18),
                AuthField(
                  controller: _confirmController,
                  label: 'Repite la contraseña',
                  obscure: _obscureConfirm,
                  onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveNewPassword(),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Repite tu contraseña.';
                    if (v != _passwordController.text) return 'No coincide con la de arriba.';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (_error != null) ...[
          AuthErrorBox(_error!),
          const SizedBox(height: 16),
        ],
        AuthPrimaryButton(label: 'Guardar contraseña', loading: _saving, onPressed: _saveNewPassword),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Después podrás entrar con ella en todos tus dispositivos.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
          ),
        ),
      ],
    );
  }
}

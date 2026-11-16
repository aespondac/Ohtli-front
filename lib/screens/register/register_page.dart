import 'package:firebase_auth/firebase_auth.dart';
import '../../services/two_factor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;

import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/user_profile_helper.dart';
import '../login/auth_shell.dart';

/// Reglas de contraseña que se muestran y se revisan mientras se escribe.
class PasswordRules {
  const PasswordRules._();

  static const List<(String, bool Function(String))> rules = [
    ('Al menos 8 caracteres', _length),
    ('Mayúsculas y minúsculas', _cases),
    ('Al menos un número', _digit),
    (r'Al menos un símbolo (!, @, #, $…)', _symbol),
  ];

  static bool _length(String p) => p.length >= 8;
  static bool _cases(String p) => p.contains(RegExp(r'[A-ZÁÉÍÓÚÑ]')) && p.contains(RegExp(r'[a-záéíóúñ]'));
  static bool _digit(String p) => p.contains(RegExp(r'\d'));
  static bool _symbol(String p) => p.contains(RegExp(r'[^A-Za-z0-9ÁÉÍÓÚÑáéíóúñ\s]'));

  static bool meetsAll(String p) => rules.every((r) => r.$2(p));
}

/// Registro con correo o Google (escritorio y teléfono).
class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.onBack,
    required this.onLoginClick,
    required this.onRegisterSuccess,
  });

  final VoidCallback onBack;
  final VoidCallback onLoginClick;
  final VoidCallback onRegisterSuccess;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loadingEmail = false;
  bool _loadingGoogle = false;
  bool _triedSubmit = false;
  String? _error;

  bool get _busy => _loadingEmail || _loadingGoogle;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _handleRegister() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _triedSubmit = true;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loadingEmail = true);
    final email = _emailController.text.trim();
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      TextInput.finishAutofillContext();
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
      await credential.user?.updateDisplayName(fullName);

      final user = credential.user;
      if (user != null) {
        try {
          await UserProfileHelper.syncAndRestoreProfile(user, customDisplayName: fullName);
        } catch (e) {
          debugPrint('[registro] no se pudo preparar el perfil: $e');
        }
        try {
          await user.sendEmailVerification(
            ActionCodeSettings(url: '${Uri.base.origin}/?mode=verifyEmail', handleCodeInApp: true),
          );
        } catch (e) {
          debugPrint('[registro] no se pudo enviar la verificación: $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Te damos la bienvenida a Ohtli! Te enviamos un correo a $email para confirmar tu cuenta.'),
          backgroundColor: OhtliColors.stormyTeal,
          duration: const Duration(seconds: 6),
        ),
      );
      widget.onRegisterSuccess();
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'email-already-in-use' => 'Ya hay una cuenta con este correo. Inicia sesión o recupera tu contraseña.',
        'weak-password' || 'password-does-not-meet-requirements' =>
          'La contraseña no cumple los requisitos. Revisa la lista de arriba.',
        'invalid-email' => 'Revisa el correo: parece incompleto.',
        _ => friendlyError(e, fallback: 'No pudimos crear la cuenta. Intenta de nuevo.'),
      };
      if (mounted) setState(() => _error = message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _loadingGoogle = true;
    });
    try {
      UserCredential credential;
      try {
        credential = await FirebaseAuth.instance.signInWithPopup(
          // Siempre deja elegir la cuenta de Google: sin esto entra sola con la última usada
          // y no se puede agregar otra cuenta.
          GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
        );
      } on FirebaseAuthMultiFactorException catch (e) {
        final resolved = await TwoFactor.resolve(context, e);
        if (resolved == null) {
          if (mounted) setState(() => _error = 'Para entrar necesitas el código que llega a tu teléfono.');
          return;
        }
        credential = resolved;
      }
      final user = credential.user;
      if (user != null) {
        try {
          await UserProfileHelper.syncAndRestoreProfile(user);
        } catch (e) {
          debugPrint('[registro] no se pudo preparar el perfil: $e');
        }
      }
      if (!mounted) return;
      final name = user?.displayName?.split(' ').first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(name != null && name.isNotEmpty ? '¡Hola, $name!' : '¡Hola!'),
          backgroundColor: OhtliColors.stormyTeal,
        ),
      );
      widget.onRegisterSuccess();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request' && mounted) {
        setState(() => _error = friendlyError(e, fallback: 'No pudimos continuar con Google. Intenta de nuevo.'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, fallback: 'No pudimos continuar con Google. Intenta de nuevo.'));
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  void _openLegal(String path) {
    // En otra pestaña, para no perder lo que ya se escribió
    if (kIsWeb) web.window.open(path, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ohtliIsMobileWidth(MediaQuery.sizeOf(context).width);
    final firstName = AuthField(
      controller: _firstNameController,
      label: 'Nombre',
      autofillHints: const [AutofillHints.givenName],
      keyboardType: TextInputType.name,
      onChanged: _clearError,
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe tu nombre.' : null,
    );
    final lastName = AuthField(
      controller: _lastNameController,
      label: 'Apellidos',
      autofillHints: const [AutofillHints.familyName],
      keyboardType: TextInputType.name,
      onChanged: _clearError,
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe tus apellidos.' : null,
    );

    return AuthShell(
      onBack: widget.onBack,
      photo: 6,
      title: 'Crea tu cuenta',
      subtitle: 'Es gratis. Guarda lugares, arma rutas a tu medida y compártelas con tus amigos.',
      children: [
        AuthGoogleButton(onPressed: _busy ? null : _handleGoogleSignIn),
        const SizedBox(height: 22),
        const AuthDivider(),
        const SizedBox(height: 22),
        Form(
          key: _formKey,
          autovalidateMode: _triedSubmit ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isMobile) ...[
                  firstName,
                  const SizedBox(height: 18),
                  lastName,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: firstName),
                      const SizedBox(width: 14),
                      Expanded(child: lastName),
                    ],
                  ),
                const SizedBox(height: 18),
                AuthField(
                  controller: _emailController,
                  label: 'Correo electrónico',
                  hint: 'nombre@correo.com',
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  onChanged: _clearError,
                  validator: validateEmail,
                ),
                const SizedBox(height: 18),
                AuthField(
                  controller: _passwordController,
                  label: 'Contraseña',
                  obscure: _obscurePassword,
                  onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (v) {
                    _clearError(v);
                    setState(() {}); // la lista de requisitos se actualiza al escribir
                  },
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Elige una contraseña.';
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
                  onSubmitted: (_) => _handleRegister(),
                  onChanged: _clearError,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Repite tu contraseña.';
                    if (v != _passwordController.text) return 'No coincide con la contraseña de arriba.';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _LegalNote(onOpen: _openLegal),
        const SizedBox(height: 18),
        if (_error != null) ...[
          AuthErrorBox(_error!),
          const SizedBox(height: 16),
        ],
        AuthPrimaryButton(label: 'Crear cuenta', loading: _loadingEmail, onPressed: _handleRegister),
        const SizedBox(height: 22),
        AuthSwitchLine(prompt: '¿Ya tienes cuenta?', action: 'Inicia sesión', onTap: widget.onLoginClick),
      ],
    );
  }
}

/// Lista de requisitos que se marca mientras se escribe la contraseña.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({super.key, required this.password, required this.highlightMissing});

  final String password;
  final bool highlightMissing;

  @override
  Widget build(BuildContext context) {
    final ok = OhtliColors.accentText;
    final missing = highlightMissing
        ? OhtliColors.warningText
        : OhtliColors.subtleText;
    return Semantics(
      label: 'Requisitos de la contraseña',
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final (label, test) in PasswordRules.rules)
            Builder(builder: (context) {
              final met = test(password);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: met ? ok : missing,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    semanticsLabel: '$label: ${met ? 'cumplido' : 'pendiente'}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: met ? OhtliColors.onyx : missing),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _LegalNote extends StatefulWidget {
  const _LegalNote({required this.onOpen});

  final void Function(String path) onOpen;

  @override
  State<_LegalNote> createState() => _LegalNoteState();
}

class _LegalNoteState extends State<_LegalNote> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()..onTap = () => widget.onOpen('/tyc');
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()..onTap = () => widget.onOpen('/privacidad');

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = GoogleFonts.inter(
      color: OhtliColors.accentText,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: OhtliColors.accentText,
    );
    return Text.rich(
      TextSpan(
        style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: OhtliColors.subtleText),
        children: [
          const TextSpan(text: 'Al crear tu cuenta aceptas los '),
          TextSpan(text: 'Términos y Condiciones', style: link, recognizer: _terms, mouseCursor: SystemMouseCursors.click),
          const TextSpan(text: ' y el '),
          TextSpan(text: 'Aviso de Privacidad', style: link, recognizer: _privacy, mouseCursor: SystemMouseCursors.click),
          const TextSpan(text: ' de Ohtli.'),
        ],
      ),
    );
  }
}

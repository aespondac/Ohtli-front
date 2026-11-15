import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/saved_accounts.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/user_profile_helper.dart';
import 'auth_shell.dart';

/// Inicio de sesión (escritorio y teléfono).
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onBack,
    required this.onRegisterClick,
    required this.onLoginSuccess,
    required this.onForgotPasswordClick,
  });

  final VoidCallback onBack;
  final VoidCallback onRegisterClick;
  final VoidCallback onLoginSuccess;
  final VoidCallback onForgotPasswordClick;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _rememberSession = true;
  bool _loadingEmail = false;
  bool _loadingGoogle = false;
  String? _error;

  bool get _busy => _loadingEmail || _loadingGoogle;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _welcome(User? user) {
    final name = (user?.displayName?.trim().isNotEmpty ?? false) ? user!.displayName!.split(' ').first : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          name != null ? '¡Hola de nuevo, $name!' : '¡Hola de nuevo!',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        backgroundColor: OhtliColors.stormyTeal,
      ),
    );
  }

  Future<void> _setPersistence() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(
        _rememberSession ? Persistence.LOCAL : Persistence.SESSION,
      );
    }
  }

  Future<void> _handleLogin() async {
    if (_busy) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loadingEmail = true);
    try {
      await _setPersistence();
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Avisa al gestor de contraseñas del navegador que el acceso funcionó
      TextInput.finishAutofillContext();
      // Con "Recordar sesión", la cuenta queda disponible para cambiar desde el menú.
      if (_rememberSession && credential.user != null) {
        await SavedAccounts.remember(credential.user!);
      }
      if (!mounted) return;
      _welcome(credential.user);
      widget.onLoginSuccess();
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' || 'wrong-password' || 'invalid-credential' || 'invalid-login-credentials' =>
          'El correo o la contraseña no coinciden. Revisa ambos o recupera tu contraseña.',
        'invalid-email' => 'Revisa el correo: parece incompleto.',
        'user-disabled' => 'Esta cuenta está desactivada. Escríbenos si crees que es un error.',
        'too-many-requests' => 'Hubo demasiados intentos. Espera unos minutos o recupera tu contraseña.',
        _ => friendlyError(e, fallback: 'No pudimos iniciar sesión. Intenta de nuevo.'),
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
      await _setPersistence();
      final credential = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      if (_rememberSession && credential.user != null) {
        await SavedAccounts.remember(credential.user!);
      }
      final user = credential.user;
      if (user != null) {
        unawaited(UserProfileHelper.syncAndRestoreProfile(user).catchError((Object e) {
          debugPrint('[login] no se pudo preparar el perfil: $e');
        }));
      }
      if (!mounted) return;
      _welcome(user);
      widget.onLoginSuccess();
    } on FirebaseAuthException catch (e) {
      // Cerrar la ventana de Google no es un error: solo se vuelve al formulario
      if (e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request' && mounted) {
        setState(() => _error = friendlyError(e, fallback: 'No pudimos entrar con Google. Intenta de nuevo.'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, fallback: 'No pudimos entrar con Google. Intenta de nuevo.'));
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      onBack: widget.onBack,
      title: 'Hola de nuevo',
      subtitle: 'Entra para ver tus rutas, tus lugares guardados y lo que comparten tus amigos.',
      children: [
        AuthGoogleButton(onPressed: _busy ? null : _handleGoogleSignIn),
        const SizedBox(height: 22),
        const AuthDivider(),
        const SizedBox(height: 22),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthField(
                  controller: _emailController,
                  label: 'Correo electrónico',
                  hint: 'nombre@correo.com',
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  validator: validateEmail,
                  onChanged: (_) => _error == null ? null : setState(() => _error = null),
                ),
                const SizedBox(height: 18),
                AuthField(
                  controller: _passwordController,
                  label: 'Contraseña',
                  obscure: _obscurePassword,
                  onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  onChanged: (_) => _error == null ? null : setState(() => _error = null),
                  validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña.' : null,
                  trailingLabel: AuthLink(
                    '¿La olvidaste?',
                    fontSize: 13,
                    onTap: widget.onForgotPasswordClick,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _RememberRow(
          value: _rememberSession,
          onChanged: (v) => setState(() => _rememberSession = v),
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          AuthErrorBox(_error!),
          const SizedBox(height: 16),
        ],
        AuthPrimaryButton(label: 'Iniciar sesión', loading: _loadingEmail, onPressed: _handleLogin),
        const SizedBox(height: 22),
        AuthSwitchLine(prompt: '¿Primera vez en Ohtli?', action: 'Crea tu cuenta', onTap: widget.onRegisterClick),
      ],
    );
  }
}

class _RememberRow extends StatelessWidget {
  const _RememberRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: OhtliColors.stormyTeal,
                  side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.45), width: 1.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mantener la sesión abierta en este dispositivo',
                  style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import '../../services/two_factor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;

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
  final _passwordFocus = FocusNode();

  /// Cuentas que se recordaron en este dispositivo ("Mantener la sesión abierta").
  List<SavedAccount> _quick = SavedAccounts.list();

  /// Con cuentas recordadas, primero se ofrecen ellas; el formulario completo aparece
  /// con "Usar otra cuenta".
  late bool _showFullForm = _quick.isEmpty;
  String? _switchingUid;

  bool get _busy => _loadingEmail || _loadingGoogle || _switchingUid != null;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Entra con una cuenta recordada sin escribir la contraseña (misma sesión guardada que
  /// usa el cambio de cuenta del menú). Si esa sesión ya no sirve, pide la contraseña.
  Future<void> _quickLogin(SavedAccount account) async {
    if (_busy) return;
    if (!SavedAccounts.isSaved(account.uid)) {
      _askPassword(account);
      return;
    }
    setState(() {
      _error = null;
      _switchingUid = account.uid;
    });
    final result = await SavedAccounts.switchTo(account.uid);
    if (result == SwitchAccountResult.switched) {
      // Arranca la app desde el inicio con esa cuenta
      web.window.location.assign('${web.window.location.origin}/');
      return;
    }
    if (!mounted) return;
    setState(() => _switchingUid = null);
    if (result == SwitchAccountResult.expired) {
      _askPassword(account, expired: true);
    } else {
      setState(() => _error = 'No pudimos entrar con esa cuenta. Intenta de nuevo o escribe tu contraseña.');
    }
  }

  void _askPassword(SavedAccount account, {bool expired = true}) {
    setState(() {
      _quick = SavedAccounts.list();
      _showFullForm = true;
      _emailController.text = account.email;
      _passwordController.clear();
      _error = expired ? 'Por seguridad, escribe de nuevo la contraseña de ${_label(account)}.' : null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  Future<void> _forget(SavedAccount account) async {
    await SavedAccounts.forget(account.uid);
    if (!mounted) return;
    setState(() {
      _quick = SavedAccounts.list();
      if (_quick.isEmpty) _showFullForm = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Se quitó ${_label(account)} de este dispositivo.')),
    );
  }

  static String _label(SavedAccount a) => a.name.trim().isNotEmpty ? a.name.trim() : a.email;

  void _welcome(User? user) {
    final name = (user?.displayName?.trim().isNotEmpty ?? false) ? user!.displayName!.split(' ').first : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          name != null ? 'Sesión iniciada. ¡Qué gusto verte, $name!' : 'Sesión iniciada.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        backgroundColor: OhtliColors.stormyTeal,
      ),
    );
  }

  Future<void> _setPersistence() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(
        _rememberSession ? SavedAccounts.rememberedPersistence : Persistence.SESSION,
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
      UserCredential credential;
      try {
        credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } on FirebaseAuthMultiFactorException catch (e) {
        // Verificación en dos pasos: el código por SMS termina el inicio de sesión.
        final resolved = await TwoFactor.resolve(context, e);
        if (resolved == null) {
          if (mounted) setState(() => _error = 'Para entrar necesitas el código que llega a tu teléfono.');
          return;
        }
        credential = resolved;
      }
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
      UserCredential credential;
      try {
        credential = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } on FirebaseAuthMultiFactorException catch (e) {
        final resolved = await TwoFactor.resolve(context, e);
        if (resolved == null) {
          if (mounted) setState(() => _error = 'Para entrar necesitas el código que llega a tu teléfono.');
          return;
        }
        credential = resolved;
      }
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
      title: 'Iniciar sesión',
      logoHeader: true,
      children: _showFullForm ? _fullForm() : _quickChoices(),
    );
  }

  List<Widget> _quickChoices() {
    return [
      Text(
        'Continuar como',
        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
      ),
      const SizedBox(height: 10),
      for (final account in _quick) ...[
        _QuickAccountTile(
          account: account,
          label: _label(account),
          needsPassword: !SavedAccounts.isSaved(account.uid),
          loading: _switchingUid == account.uid,
          enabled: !_busy,
          onTap: () => _quickLogin(account),
          onForget: () => _forget(account),
        ),
        const SizedBox(height: 10),
      ],
      if (_error != null) ...[
        const SizedBox(height: 6),
        AuthErrorBox(_error!),
      ],
      const SizedBox(height: 14),
      SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => setState(() => _showFullForm = true),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
          label: const Text('Usar otra cuenta'),
          style: OutlinedButton.styleFrom(
            foregroundColor: OhtliColors.onyx,
            side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.16)),
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const SizedBox(height: 22),
      AuthSwitchLine(prompt: '¿Primera vez en Ohtli?', action: 'Crea tu cuenta', onTap: widget.onRegisterClick),
    ];
  }

  List<Widget> _fullForm() {
    return [
      if (_quick.isNotEmpty) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _showFullForm = false;
                      _error = null;
                    }),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(_quick.length == 1 ? 'Volver a ${_label(_quick.first)}' : 'Volver a mis cuentas'),
            style: TextButton.styleFrom(
              foregroundColor: OhtliColors.accentText,
              textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
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
                focusNode: _passwordFocus,
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
    ];
  }
}

/// Una cuenta recordada: foto o iniciales, nombre y correo. Al tocarla entra; la × la
/// quita de este dispositivo.
class _QuickAccountTile extends StatelessWidget {
  const _QuickAccountTile({
    required this.account,
    required this.label,
    required this.needsPassword,
    required this.loading,
    required this.enabled,
    required this.onTap,
    required this.onForget,
  });

  final SavedAccount account;
  final String label;
  final bool needsPassword;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final photo = account.photoURL;
    final secondary = needsPassword ? 'Escribe tu contraseña para entrar' : account.email;
    return Material(
      color: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: OhtliColors.stormyTeal,
                foregroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                onForegroundImageError: (photo != null && photo.isNotEmpty) ? (_, _) {} : null,
                child: Text(
                  account.initials,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
                    ),
                  ],
                ),
              ),
              if (loading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: OhtliColors.accentText),
                  ),
                )
              else ...[
                Icon(Icons.arrow_forward_rounded, size: 20, color: OhtliColors.accentText),
                IconButton(
                  onPressed: enabled ? onForget : null,
                  tooltip: 'Quitar $label de este dispositivo',
                  icon: Icon(Icons.close_rounded, size: 18, color: OhtliColors.subtleText),
                ),
              ],
            ],
          ),
        ),
      ),
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
                  'Recordarme en este dispositivo para entrar con un toque',
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

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import '../widgets/ohtli_ui.dart';

/// Verificación en dos pasos con un código por SMS (segundo factor de Firebase Auth).
///
/// Requisitos en Firebase: Identity Platform activado, el proveedor Teléfono y la
/// verificación en varios pasos (SMS) habilitada. La cuenta debe tener el correo verificado.
class TwoFactor {
  TwoFactor._();

  static User? get _user => FirebaseAuth.instance.currentUser;

  static Future<bool> isEnabled() async {
    final user = _user;
    if (user == null) return false;
    try {
      return (await user.multiFactor.getEnrolledFactors()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Envía el código para inscribir [phoneE164] como segundo factor. Devuelve el id de verificación.
  static Future<String> sendEnrollmentCode(String phoneE164) async {
    final user = _user;
    if (user == null) throw FirebaseAuthException(code: 'no-current-user');
    final session = await user.multiFactor.getSession();
    return _sendCode((completed, failed, sent) => FirebaseAuth.instance.verifyPhoneNumber(
          multiFactorSession: session,
          phoneNumber: phoneE164,
          verificationCompleted: completed,
          verificationFailed: failed,
          codeSent: sent,
          codeAutoRetrievalTimeout: (_) {},
        ));
  }

  static Future<void> confirmEnrollment(String verificationId, String smsCode) async {
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode);
    await _user!.multiFactor.enroll(PhoneMultiFactorGenerator.getAssertion(cred), displayName: 'Teléfono');
  }

  /// Quita todos los segundos factores. Firebase puede pedir un inicio de sesión reciente.
  static Future<void> disable() async {
    final user = _user;
    if (user == null) return;
    for (final f in await user.multiFactor.getEnrolledFactors()) {
      await user.multiFactor.unenroll(multiFactorInfo: f);
    }
  }

  static Future<String> _sendCode(
    Future<void> Function(
      void Function(PhoneAuthCredential) completed,
      void Function(FirebaseAuthException) failed,
      void Function(String, int?) sent,
    ) start,
  ) {
    final c = Completer<String>();
    start(
      (_) {},
      (e) {
        if (!c.isCompleted) c.completeError(e);
      },
      (id, _) {
        if (!c.isCompleted) c.complete(id);
      },
    ).catchError((Object e) {
      if (!c.isCompleted) c.completeError(e);
    });
    return c.future.timeout(const Duration(seconds: 90));
  }

  /// Termina un inicio de sesión (o reautenticación) que pidió el segundo factor: muestra
  /// un diálogo, manda el código al teléfono inscrito y lo resuelve. Devuelve null si se cancela.
  static Future<UserCredential?> resolve(BuildContext context, FirebaseAuthMultiFactorException e) {
    return showDialog<UserCredential>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SecondFactorDialog(resolver: e.resolver),
    );
  }

  /// Reautentica (para cambiar contraseña, borrar la cuenta…) resolviendo el segundo
  /// factor si la cuenta lo tiene. Lanza la excepción original si se cancela.
  static Future<void> reauthenticate(BuildContext context, User user, AuthCredential credential) async {
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthMultiFactorException catch (e) {
      if (!context.mounted) rethrow;
      final result = await resolve(context, e);
      if (result == null) rethrow;
    }
  }

  /// Texto para los errores de esta función.
  static String messageFor(Object e) {
    final code = e is FirebaseAuthException ? e.code : '';
    return switch (code) {
      'invalid-verification-code' => 'El código no coincide. Revísalo e intenta de nuevo.',
      'code-expired' || 'session-expired' => 'El código venció. Pide uno nuevo.',
      'too-many-requests' || 'quota-exceeded' => 'Hiciste muchos intentos. Espera unos minutos.',
      'unverified-email' => 'Primero verifica tu correo: te mandamos un enlace.',
      'requires-recent-login' => 'Por seguridad, cierra sesión, vuelve a entrar y repite este paso.',
      'operation-not-allowed' || 'admin-restricted-operation' => 'La verificación en dos pasos aún no está activada. Intenta más tarde.',
      'second-factor-already-in-use' => 'Ese teléfono ya está inscrito.',
      'maximum-second-factor-count-exceeded' => 'Ya tienes el máximo de teléfonos inscritos.',
      'network-request-failed' => 'Sin conexión. Revisa tu internet.',
      _ => 'No pudimos completar la verificación. Intenta de nuevo.',
    };
  }
}

String _mask(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  return d.length >= 4 ? '•••• ${d.substring(d.length - 4)}' : (phone ?? 'tu teléfono');
}

class _SecondFactorDialog extends StatefulWidget {
  final MultiFactorResolver resolver;
  const _SecondFactorDialog({required this.resolver});

  @override
  State<_SecondFactorDialog> createState() => _SecondFactorDialogState();
}

class _SecondFactorDialogState extends State<_SecondFactorDialog> {
  final _code = TextEditingController();
  String? _verificationId;
  String? _error;
  bool _busy = false;

  PhoneMultiFactorInfo? get _hint => widget.resolver.hints.whereType<PhoneMultiFactorInfo>().firstOrNull;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final hint = _hint;
    if (hint == null) {
      setState(() => _error = 'Tu cuenta usa un segundo factor que esta app aún no admite.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await TwoFactor._sendCode((completed, failed, sent) => FirebaseAuth.instance.verifyPhoneNumber(
            multiFactorSession: widget.resolver.session,
            multiFactorInfo: hint,
            verificationCompleted: completed,
            verificationFailed: failed,
            codeSent: sent,
            codeAutoRetrievalTimeout: (_) {},
          ));
      if (mounted) setState(() => _verificationId = id);
    } catch (e) {
      if (mounted) setState(() => _error = TwoFactor.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_verificationId == null || _code.text.trim().length != 6) {
      setState(() => _error = 'El código tiene 6 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _code.text.trim());
      final result = await widget.resolver.resolveSignIn(PhoneMultiFactorGenerator.getAssertion(cred));
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => _error = TwoFactor.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OhtliUi.radiusLarge)),
      title: Text('Verificación en dos pasos', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _verificationId == null && _busy
                  ? 'Enviando un código a ${_mask(_hint?.phoneNumber)}…'
                  : 'Escribe el código que enviamos por SMS a ${_mask(_hint?.phoneNumber)}.',
              style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx, height: 1.4),
            ),
            const SizedBox(height: 14),
            Semantics(
              label: 'Código de verificación',
              textField: true,
              child: TextField(
                controller: _code,
                autofocus: true,
                enabled: !_busy || _verificationId != null,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                onSubmitted: (_) => _confirm(),
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8, color: OhtliColors.onyx),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '······',
                  filled: true,
                  fillColor: OhtliColors.innerCardBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.xoconostle, fontWeight: FontWeight.w600)),
              ),
            ],
            TextButton(onPressed: _busy ? null : _send, child: const Text('Reenviar código')),
          ],
        ),
      ),
      actions: [
        OhtliSecondaryButton(compact: true, label: 'Cancelar', onPressed: _busy ? null : () => Navigator.of(context).pop()),
        OhtliPrimaryButton(compact: true, label: 'Entrar', loading: _busy && _verificationId != null, onPressed: _busy ? null : _confirm),
      ],
    );
  }
}

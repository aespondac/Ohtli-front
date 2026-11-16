import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/profile_directory.dart';
import '../services/user_private_data.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';

/// Teléfono verificado por SMS (Firebase Auth): se vincula a la cuenta con un código de
/// 6 dígitos. Firebase no deja que el mismo número esté en dos cuentas, y solo un
/// teléfono verificado entra al directorio para que te encuentren (función contactDirectory).
///
/// Requiere el proveedor «Teléfono» activado en Firebase Authentication.
class PhoneVerificationField extends StatefulWidget {
  /// Modo de prueba (cuestionario de Labs): no envía SMS ni guarda nada.
  final bool sandbox;
  final ValueChanged<String>? onVerified;

  const PhoneVerificationField({super.key, this.sandbox = false, this.onVerified});

  @override
  State<PhoneVerificationField> createState() => _PhoneVerificationFieldState();
}

enum _Stage { enter, sending, code, confirming, verified }

class _PhoneVerificationFieldState extends State<PhoneVerificationField> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  _Stage _stage = _Stage.enter;
  ConfirmationResult? _confirmation;
  String? _error;
  String? _verifiedPhone;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final current = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (current != null && current.isNotEmpty) {
      _verifiedPhone = current;
      _stage = _Stage.verified;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String _pretty(String e164) {
    final d = e164.replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return e164;
    final ten = d.substring(d.length - 10);
    return '+52 ${ten.substring(0, 2)} ${ten.substring(2, 6)} ${ten.substring(6)}';
  }

  String _messageFor(Object e) {
    final code = e is FirebaseAuthException ? e.code : '';
    switch (code) {
      case 'invalid-phone-number':
        return 'Ese número no parece válido. Escribe 10 dígitos.';
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return 'Ese número ya está en otra cuenta de Ohtli.';
      case 'invalid-verification-code':
        return 'El código no coincide. Revísalo e intenta de nuevo.';
      case 'code-expired':
      case 'session-expired':
        return 'El código venció. Pide uno nuevo.';
      case 'too-many-requests':
      case 'quota-exceeded':
        return 'Hiciste muchos intentos. Espera unos minutos.';
      case 'operation-not-allowed':
        return 'La verificación por SMS aún no está activada. Intenta más tarde.';
      case 'captcha-check-failed':
        return 'No pudimos comprobar que no eres un robot. Recarga e intenta de nuevo.';
      case 'requires-recent-login':
        return 'Por seguridad, vuelve a iniciar sesión y repite la verificación.';
      case 'network-request-failed':
        return 'Sin conexión. Revisa tu internet.';
      default:
        return 'No pudimos verificar el número. Intenta de nuevo.';
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    final phone = ProfileDirectory.normalizePhone(_phone.text);
    if (phone == null) {
      setState(() => _error = 'Escribe tu número de 10 dígitos.');
      return;
    }
    if (widget.sandbox) {
      setState(() => _error = 'En el modo de prueba no se envían SMS.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _stage = _Stage.sending;
      _error = null;
    });
    try {
      // Para cambiar de número: primero se quita el anterior.
      if (user.providerData.any((p) => p.providerId == 'phone') && user.phoneNumber != phone) {
        await user.unlink('phone');
      }
      _confirmation = await FirebaseAuth.instance.currentUser!.linkWithPhoneNumber(phone);
      if (!mounted) return;
      setState(() => _stage = _Stage.code);
      _startCooldown();
      SemanticsService.sendAnnouncement(View.of(context), 'Te enviamos un código por SMS.', TextDirection.ltr);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.enter;
        _error = _messageFor(e);
      });
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6 || _confirmation == null) {
      setState(() => _error = 'El código tiene 6 dígitos.');
      return;
    }
    setState(() {
      _stage = _Stage.confirming;
      _error = null;
    });
    try {
      await _confirmation!.confirm(code);
      final user = FirebaseAuth.instance.currentUser!;
      await user.reload();
      final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? ProfileDirectory.normalizePhone(_phone.text)!;
      await UserPrivateData.save(user.uid, {'phone': phone, 'phone_verified': true});
      if (!mounted) return;
      setState(() {
        _verifiedPhone = phone;
        _stage = _Stage.verified;
      });
      SemanticsService.sendAnnouncement(View.of(context), 'Número verificado.', TextDirection.ltr);
      widget.onVerified?.call(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.code;
        _error = _messageFor(e);
      });
    }
  }

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icon, color: OhtliColors.accentText),
        filled: true,
        fillColor: OhtliColors.innerCardBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6)),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.sending || _stage == _Stage.confirming;
    Widget body;
    switch (_stage) {
      case _Stage.verified:
        body = Container(
          key: const ValueKey('ok'),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: OhtliColors.stormyTeal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OhtliColors.accentText.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_rounded, color: OhtliColors.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_pretty(_verifiedPhone ?? ''), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                    Text('Verificado', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.accentText)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _stage = _Stage.enter;
                  _phone.clear();
                  _code.clear();
                  _error = null;
                }),
                child: const Text('Cambiar'),
              ),
            ],
          ),
        );
      case _Stage.code:
      case _Stage.confirming:
        body = Column(
          key: const ValueKey('code'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Escribe el código que enviamos a ${_pretty(ProfileDirectory.normalizePhone(_phone.text) ?? _phone.text)}.',
                style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx, height: 1.4)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Código de verificación',
                    textField: true,
                    child: TextField(
                      controller: _code,
                      autofocus: true,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      onSubmitted: (_) => _confirm(),
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 6, color: OhtliColors.onyx),
                      decoration: _deco('······', Icons.sms_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OhtliPrimaryButton(compact: true, label: 'Confirmar', loading: _stage == _Stage.confirming, onPressed: _confirm),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _cooldown > 0 || busy ? null : _send,
                  child: Text(_cooldown > 0 ? 'Reenviar en ${_cooldown}s' : 'Reenviar código'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            _stage = _Stage.enter;
                            _code.clear();
                            _error = null;
                          }),
                  child: const Text('Cambiar número'),
                ),
              ],
            ),
          ],
        );
      case _Stage.enter:
      case _Stage.sending:
        body = Row(
          key: const ValueKey('enter'),
          children: [
            Expanded(
              child: Semantics(
                label: 'Teléfono',
                textField: true,
                child: TextField(
                  controller: _phone,
                  enabled: !busy,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]'))],
                  onSubmitted: (_) => _send(),
                  style: GoogleFonts.inter(color: OhtliColors.onyx),
                  decoration: _deco('55 1234 5678', Icons.phone_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OhtliPrimaryButton(compact: true, label: 'Enviar código', loading: _stage == _Stage.sending, onPressed: _send),
          ],
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, axisAlignment: -1, child: c)),
          child: body,
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 16, color: OhtliColors.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.warningText, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

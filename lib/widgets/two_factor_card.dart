import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/two_factor.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';
import 'phone_verification_field.dart';

/// Activar o desactivar la verificación en dos pasos con el teléfono verificado.
class TwoFactorCard extends StatefulWidget {
  /// Modo de prueba: no envía nada.
  final bool sandbox;
  const TwoFactorCard({super.key, this.sandbox = false});

  @override
  State<TwoFactorCard> createState() => _TwoFactorCardState();
}

class _TwoFactorCardState extends State<TwoFactorCard> {
  bool? _enabled;
  bool _busy = false;
  String? _verificationId;
  String? _error;
  String? _info;
  final _code = TextEditingController();

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final on = widget.sandbox ? false : await TwoFactor.isEnabled();
    if (mounted) setState(() => _enabled = on);
  }

  Future<void> _start() async {
    final phone = _user?.phoneNumber;
    if (phone == null || widget.sandbox) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final id = await TwoFactor.sendEnrollmentCode(phone);
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
      await TwoFactor.confirmEnrollment(_verificationId!, _code.text.trim());
      _code.clear();
      _verificationId = null;
      await _refresh();
      if (mounted) setState(() => _info = 'Listo: cada vez que entres te pediremos un código por SMS.');
    } catch (e) {
      if (mounted) setState(() => _error = TwoFactor.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: OhtliColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OhtliUi.radiusLarge)),
        title: Text('¿Desactivar la verificación en dos pasos?', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
        content: Text('Tu cuenta quedará protegida solo con tu contraseña o tu cuenta de Google.', style: GoogleFonts.inter(color: OhtliColors.onyx)),
        actions: [
          OhtliSecondaryButton(compact: true, label: 'Cancelar', onPressed: () => Navigator.pop(c, false)),
          OhtliPrimaryButton(compact: true, label: 'Desactivar', onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TwoFactor.disable();
      await _refresh();
      if (mounted) setState(() => _info = 'Verificación en dos pasos desactivada.');
    } catch (e) {
      if (mounted) setState(() => _error = TwoFactor.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailVerification() async {
    try {
      await _user?.sendEmailVerification();
      if (mounted) setState(() => _info = 'Te mandamos un enlace a ${_user?.email}. Ábrelo y vuelve aquí.');
    } catch (e) {
      if (mounted) setState(() => _error = TwoFactor.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final hasPhone = (user?.phoneNumber ?? '').isNotEmpty;
    final emailOk = user?.emailVerified ?? false;
    final enabled = _enabled ?? false;

    Widget body;
    if (_enabled == null) {
      body = const LinearProgressIndicator(minHeight: 2);
    } else if (enabled) {
      body = Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Activada con tu teléfono verificado.', style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx)),
          OhtliSecondaryButton(compact: true, label: 'Desactivar', onPressed: _busy ? null : _disable),
        ],
      );
    } else if (!emailOk && !widget.sandbox) {
      body = Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Primero verifica tu correo.', style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx)),
          OhtliSecondaryButton(compact: true, label: 'Enviar enlace', icon: Icons.mark_email_read_outlined, onPressed: _sendEmailVerification),
        ],
      );
    } else if (!hasPhone) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Primero verifica tu teléfono:', style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx)),
          const SizedBox(height: 10),
          PhoneVerificationField(sandbox: widget.sandbox, onVerified: (_) => setState(() {})),
        ],
      );
    } else if (_verificationId == null) {
      body = Align(
        alignment: Alignment.centerLeft,
        child: OhtliPrimaryButton(
          compact: true,
          label: 'Activar con mi teléfono',
          icon: Icons.shield_rounded,
          loading: _busy,
          onPressed: _busy || widget.sandbox ? null : _start,
        ),
      );
    } else {
      body = Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Código de verificación',
              textField: true,
              child: TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                onSubmitted: (_) => _confirm(),
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 6, color: OhtliColors.onyx),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '······',
                  filled: true,
                  fillColor: OhtliColors.innerCardBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OhtliPrimaryButton(compact: true, label: 'Confirmar', loading: _busy, onPressed: _busy ? null : _confirm),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: enabled ? OhtliColors.accentText.withValues(alpha: 0.5) : OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(enabled ? Icons.verified_user_rounded : Icons.shield_outlined, color: OhtliColors.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Verificación en dos pasos', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              ),
              if (enabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(30)),
                  child: Text('Activada', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Además de tu contraseña, al entrar te pediremos un código que llega a tu teléfono.',
              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4)),
          const SizedBox(height: 12),
          body,
          if (_error != null || _info != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(_error ?? _info!,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: _error != null ? OhtliColors.xoconostle : OhtliColors.accentText)),
            ),
          ],
        ],
      ),
    );
  }
}

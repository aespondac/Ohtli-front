// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ohtli_sso.dart';
import '../../services/saved_accounts.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_accessibility_panel.dart' show ohtliAccent;

/// ohtli.quest/sso: con la sesión de ohtli.quest, entra al subdominio que la pidió.
///
/// Si en este navegador hay otras cuentas recordadas, deja elegir con cuál
/// continuar; si no, continúa sola con la cuenta actual.
class SsoBridgePage extends StatefulWidget {
  final Uri target;
  final VoidCallback onUseAnotherAccount;

  const SsoBridgePage({super.key, required this.target, required this.onUseAnotherAccount});

  @override
  State<SsoBridgePage> createState() => _SsoBridgePageState();
}

class _SsoBridgePageState extends State<SsoBridgePage> {
  bool _busy = false;
  String? _error;
  late final List<SavedAccount> _others;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _others = SavedAccounts.list().where((a) => a.uid != uid && SavedAccounts.isSaved(a.uid)).toList();
    // Sin otras cuentas, o justo después de elegir una (recarga): continúa solo.
    if (_others.isEmpty || OhtliSso.takeContinueAfterSwitch()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _continue());
    }
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OhtliSso.issueAndReturn(widget.target);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No pudimos conectar tu cuenta con ${widget.target.host}. Intenta de nuevo.';
      });
    }
  }

  Future<void> _switchTo(SavedAccount account) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await SavedAccounts.switchTo(account.uid);
    if (result == SwitchAccountResult.switched) {
      // Misma URL (/sso?return=…): al recargar continúa con la cuenta elegida.
      OhtliSso.markContinueAfterSwitch();
      html.window.location.reload();
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result == SwitchAccountResult.expired
          ? 'La sesión de esa cuenta caducó. Usa "Usar otra cuenta" para iniciar sesión con ella.'
          : 'No pudimos cambiar de cuenta. Intenta de nuevo.';
      _others.removeWhere((a) => a.uid == account.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? '';
    final email = user?.email ?? '';
    final textColor = OhtliColors.onyx;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(22),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 28, 26, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SvgPicture.asset(
                      'assets/logo.svg',
                      height: 26,
                      colorFilter: ColorFilter.mode(ohtliAccent, BlendMode.srcIn),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Continuar en ${widget.target.host}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _others.isEmpty ? 'Con tu cuenta de Ohtli' : 'Elige con qué cuenta de Ohtli quieres entrar',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 13, color: textColor.withOpacity(0.65)),
                    ),
                    const SizedBox(height: 20),
                    _AccountTile(
                      title: name.isNotEmpty ? name : email,
                      subtitle: name.isNotEmpty ? email : null,
                      trailing: _busy && _others.isEmpty
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal),
                            )
                          : Icon(Icons.arrow_forward_rounded, color: ohtliAccent, size: 20),
                      highlighted: true,
                      onTap: _busy ? null : _continue,
                    ),
                    for (final a in _others) ...[
                      const SizedBox(height: 8),
                      _AccountTile(
                        title: a.name.isNotEmpty ? a.name : a.email,
                        subtitle: a.name.isNotEmpty ? a.email : null,
                        onTap: _busy ? null : () => _switchTo(a),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.xoconostle),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : widget.onUseAnotherAccount,
                          child: Text('Usar otra cuenta', style: GoogleFonts.inter(color: ohtliAccent)),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => OhtliSso.cancelAndReturn(widget.target),
                          child: Text('Cancelar', style: GoogleFonts.inter(color: textColor.withOpacity(0.6))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool highlighted;
  final VoidCallback? onTap;

  const _AccountTile({required this.title, this.subtitle, this.trailing, this.highlighted = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final initials = title.split(RegExp(r'[\s@.]+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return Material(
      color: highlighted ? OhtliColors.stormyTeal.withOpacity(0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: highlighted ? ohtliAccent : OhtliColors.cardBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: OhtliColors.stormyTeal,
                child: Text(
                  initials,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withOpacity(0.6)),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

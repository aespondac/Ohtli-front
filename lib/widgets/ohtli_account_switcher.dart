import 'dart:convert';
import 'package:web/web.dart' as web;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/saved_accounts.dart';
import '../theme/colors.dart';
import 'ohtli_accessibility_panel.dart' show ohtliAccent;

/// Acciones de cuentas recordadas que comparten el menú lateral (escritorio) y la
/// sección "Cuentas" de Mi cuenta (móvil, donde no hay menú lateral).
class AccountSwitchActions {
  AccountSwitchActions._();

  /// Cambia a [account] (sesión recordada) y recarga la app con esa cuenta.
  static Future<void> switchTo(BuildContext context, SavedAccount account) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final label = account.name.isNotEmpty ? account.name : account.email;
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Cambiando a $label…', style: GoogleFonts.inter()),
        duration: const Duration(seconds: 6),
      ),
    );
    final result = await SavedAccounts.switchTo(account.uid);
    if (result == SwitchAccountResult.switched) {
      // Arranca la app desde el inicio con la nueva cuenta (sin datos en memoria de la anterior).
      web.window.location.assign('${web.window.location.origin}/');
      return;
    }
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: OhtliColors.xoconostle,
        content: Text(
          result == SwitchAccountResult.expired
              ? 'La sesión de $label caducó. Inicia sesión de nuevo con esa cuenta para recordarla.'
              : 'No pudimos cambiar a $label. Intenta de nuevo.',
          style: GoogleFonts.inter(color: Colors.white),
        ),
      ),
    );
  }

  /// Recuerda la cuenta actual para poder volver a ella con un toque.
  static Future<void> rememberCurrent(BuildContext context, User user) async {
    await SavedAccounts.remember(user);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        backgroundColor: OhtliColors.stormyTeal,
        content: Text(
          SavedAccounts.isSaved(user.uid)
              ? 'Listo: podrás volver a esta cuenta desde tus cuentas.'
              : 'No pudimos recordar esta cuenta. Intenta de nuevo.',
          style: GoogleFonts.inter(color: Colors.white),
        ),
      ),
    );
  }

  /// Lleva al inicio de sesión sin olvidar las cuentas recordadas. Si la cuenta actual
  /// no está recordada, avisa antes que para volver a ella habrá que escribir la contraseña.
  static Future<void> addAccount(
    BuildContext context, {
    required bool currentSaved,
    required VoidCallback onLogout,
  }) async {
    if (!currentSaved) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: OhtliColors.cloudDancer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Agregar otra cuenta',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
          ),
          content: Text(
            'Tu cuenta actual no está recordada en este navegador, así que para volver a ella '
            'tendrás que iniciar sesión otra vez. Para poder cambiar con un clic, inicia sesión '
            'con "Recordarme en este dispositivo" marcado.',
            style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancelar', style: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.7))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Continuar',
                style: GoogleFonts.inter(color: ohtliAccent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    onLogout();
  }

  /// Cerrar sesión conservando la cuenta recordada: guarda su sesión más reciente para
  /// el inicio rápido (se olvida con la × en la pantalla de inicio de sesión).
  static Future<void> logoutKeepingRemembered(VoidCallback onLogout) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && SavedAccounts.isSaved(user.uid)) await SavedAccounts.remember(user);
    onLogout();
  }
}

/// Sección "Cuentas" para móvil: la cuenta actual, las demás cuentas recordadas en este
/// navegador (un toque para cambiar), "Recordar esta cuenta" y "Agregar otra cuenta".
class OhtliAccountSwitcherSection extends StatelessWidget {
  /// Cierra la sesión y lleva al inicio de sesión (para "Agregar otra cuenta").
  final VoidCallback onLogout;

  const OhtliAccountSwitcherSection({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SavedAccounts.changes,
      builder: (context, _, _) {
        final user = FirebaseAuth.instance.currentUser;
        final saved = SavedAccounts.list();
        final currentSaved = user != null && SavedAccounts.isSaved(user.uid);
        final others = saved.where((a) => a.uid != user?.uid).toList();
        final divider = OhtliColors.cardBorder.withValues(alpha: 0.7);

        final rows = <Widget>[
          _AccountRow(
            name: user?.displayName ?? '',
            email: user?.email ?? '',
            photoURL: user?.photoURL,
            trailing: Icon(Icons.check_rounded, size: 20, color: ohtliAccent),
            subtitleOverride: currentSaved ? null : 'Cuenta actual · no recordada en este navegador',
          ),
          for (final a in others)
            _AccountRow(
              name: a.name,
              email: a.email,
              photoURL: a.photoURL,
              needsLogin: SavedAccounts.needsLogin(a.uid),
              trailing: Icon(
                SavedAccounts.needsLogin(a.uid) ? Icons.login_rounded : Icons.swap_horiz_rounded,
                size: 20,
                color: OhtliColors.onyx.withValues(alpha: 0.45),
              ),
              semanticsLabel: 'Cambiar a ${a.name.isNotEmpty ? a.name : a.email}',
              onTap: () => SavedAccounts.needsLogin(a.uid)
                  ? AccountSwitchActions.addAccount(context, currentSaved: currentSaved, onLogout: onLogout)
                  : AccountSwitchActions.switchTo(context, a),
            ),
          if (!currentSaved && user != null)
            _ActionRow(
              icon: Icons.bookmark_add_outlined,
              title: 'Recordar esta cuenta',
              subtitle: 'Para volver a ella con un toque',
              onTap: () => AccountSwitchActions.rememberCurrent(context, user),
            ),
          _ActionRow(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Agregar otra cuenta',
            subtitle: 'Marca "Recordarme" al iniciar sesión para poder cambiar',
            onTap: () => AccountSwitchActions.addAccount(context, currentSaved: currentSaved, onLogout: onLogout),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 8),
              child: Text(
                'CUENTAS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: OhtliColors.onyx.withValues(alpha: 0.5),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: OhtliColors.inputBg,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(height: 1, thickness: 1, indent: 68, color: divider),
                    rows[i],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccountRow extends StatelessWidget {
  final String name;
  final String email;
  final String? photoURL;
  final bool needsLogin;
  final Widget trailing;
  final String? subtitleOverride;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  const _AccountRow({
    required this.name,
    required this.email,
    required this.photoURL,
    required this.trailing,
    this.needsLogin = false,
    this.subtitleOverride,
    this.semanticsLabel,
    this.onTap,
  });

  String get _initials {
    final source = name.trim().isNotEmpty ? name : email;
    return source.split(RegExp(r'[\s@.]+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  }

  Widget _avatar() {
    const double size = 38;
    Widget initials() => Center(
          child: Text(_initials, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        );
    Widget content = initials();
    final url = photoURL;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:')) {
        try {
          content = ClipOval(
            child: Image.memory(base64.decode(url.split(',').last), width: size, height: size, fit: BoxFit.cover),
          );
        } catch (_) {}
      } else {
        content = ClipOval(
          child: Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => initials(),
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: OhtliColors.stormyTeal, shape: BoxShape.circle),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = name.isNotEmpty ? name : email;
    final subtitle = subtitleOverride ??
        (needsLogin ? 'Inicia sesión de nuevo' : (name.isNotEmpty && email.isNotEmpty ? email : null));
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _avatar(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: needsLogin ? OhtliColors.xoconostle : OhtliColors.onyx.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: OhtliColors.stormyTeal, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: OhtliColors.onyx.withValues(alpha: 0.35), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

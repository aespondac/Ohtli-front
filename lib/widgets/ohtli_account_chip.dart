import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/ohtli_sso.dart';
import '../theme/colors.dart';

/// Cuenta con sesión en un subdominio (lab, labs, api): nombre y un menú con
/// "Cambiar de cuenta" (vuelve al selector de ohtli.quest) y "Cerrar sesión".
/// Sin sesión no muestra nada.
class OhtliAccountChip extends StatelessWidget {
  /// Qué hacer al cerrar sesión; por defecto, cerrar la sesión de Firebase.
  final Future<void> Function()? onSignOut;

  /// Solo el avatar (pantallas angostas).
  final bool compact;

  const OhtliAccountChip({super.key, this.onSignOut, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return const SizedBox.shrink();
        final name = (user.displayName ?? '').trim();
        final email = user.email ?? '';
        final label = name.isNotEmpty ? name : email;
        final initials =
            label.split(RegExp(r'[\s@.]+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

        return PopupMenuButton<String>(
          tooltip: 'Tu cuenta de Ohtli',
          position: PopupMenuPosition.under,
          color: OhtliColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: OhtliColors.cardBorder),
          ),
          onSelected: (value) async {
            if (value == 'switch') {
              await OhtliSso.switchAccountOnSubdomain();
            } else if (value == 'logout') {
              if (onSignOut != null) {
                await onSignOut!();
              } else {
                await FirebaseAuth.instance.signOut();
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                  if (name.isNotEmpty && email.isNotEmpty)
                    Text(email,
                        style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx.withValues(alpha: 0.6))),
                ],
              ),
            ),
            const PopupMenuDivider(height: 8),
            if (OhtliSso.isSubdomain)
              PopupMenuItem<String>(
                value: 'switch',
                child: Row(children: [
                  Icon(Icons.switch_account_outlined, size: 18, color: OhtliColors.onyx.withValues(alpha: 0.85)),
                  const SizedBox(width: 12),
                  Text('Cambiar de cuenta', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx)),
                ]),
              ),
            PopupMenuItem<String>(
              value: 'logout',
              child: Row(children: [
                const Icon(Icons.logout_rounded, size: 18, color: OhtliColors.xoconostle),
                const SizedBox(width: 12),
                Text('Cerrar sesión', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.xoconostle)),
              ]),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: OhtliColors.stormyTeal,
                  child: Text(initials,
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5, color: OhtliColors.onyx),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: OhtliColors.onyx.withValues(alpha: 0.6)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

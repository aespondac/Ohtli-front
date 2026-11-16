import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;

import '../services/push_service.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';

/// Qué decir de los avisos push en cada estado.
String pushStatusHint(PushStatus s) => switch (s) {
      PushStatus.unsupported => 'Este navegador no recibe avisos con Ohtli cerrado.',
      PushStatus.needsInstall =>
        'En iPhone y iPad solo llegan con Ohtli en tu pantalla de inicio: en Safari toca Compartir → «Agregar a inicio» y ábrelo desde ahí.',
      PushStatus.denied => 'Bloqueaste las notificaciones de Ohtli. Actívalas en los ajustes de tu navegador para este sitio.',
      PushStatus.off => 'Solicitudes, invitaciones y avisos para salir de tu viaje, aunque Ohtli esté cerrado.',
      PushStatus.working => 'Activando…',
      PushStatus.on => 'Activados: te llegan aunque Ohtli esté cerrado.',
    };

/// Interruptor «Avisos en este dispositivo» (Cuenta → Privacidad).
class PushSettingTile extends StatelessWidget {
  const PushSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final push = PushService.instance;
    if (!push.configured) return const SizedBox.shrink();
    return ValueListenableBuilder<PushStatus>(
      valueListenable: push.status,
      builder: (context, s, _) {
        final canToggle = s == PushStatus.off || s == PushStatus.on;
        return SwitchListTile(
          activeThumbColor: OhtliColors.stormyTeal,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Avisos en este dispositivo',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14),
          ),
          subtitle: Text(
            pushStatusHint(s),
            style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withValues(alpha: 0.55)),
          ),
          value: s == PushStatus.on || s == PushStatus.working,
          onChanged: !canToggle
              ? null
              : (on) {
                  if (on) {
                    push.enableFromTap();
                  } else {
                    push.disable();
                  }
                },
        );
      },
    );
  }
}

/// Invitación a activar los avisos push, arriba de Notificaciones. Se va al activarlos o con
/// «Ahora no» (en este dispositivo).
class PushInviteBanner extends StatefulWidget {
  const PushInviteBanner({super.key});

  @override
  State<PushInviteBanner> createState() => _PushInviteBannerState();
}

class _PushInviteBannerState extends State<PushInviteBanner> {
  static const String _kDismissed = 'ohtli_push_banner_dismissed';
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    try {
      _dismissed = web.window.localStorage.getItem(_kDismissed) == '1';
    } catch (_) {}
  }

  void _dismiss() {
    try {
      web.window.localStorage.setItem(_kDismissed, '1');
    } catch (_) {}
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final push = PushService.instance;
    if (_dismissed || !push.configured) return const SizedBox.shrink();
    return ValueListenableBuilder<PushStatus>(
      valueListenable: push.status,
      builder: (context, s, _) {
        if (s != PushStatus.off && s != PushStatus.working && s != PushStatus.needsInstall) return const SizedBox.shrink();
        final install = s == PushStatus.needsInstall;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              install ? 'Avisos en iPhone' : 'Recibe tus avisos aunque Ohtli esté cerrado',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15.5, color: OhtliColors.onyx),
            ),
            const SizedBox(height: 3),
            Text(pushStatusHint(s), style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: OhtliColors.subtleText)),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!install)
              OhtliPrimaryButton(
                compact: true,
                label: 'Activar',
                icon: Icons.notifications_active_rounded,
                loading: s == PushStatus.working,
                onPressed: () => push.enableFromTap(),
              ),
            TextButton(
              onPressed: _dismiss,
              child: Text(install ? 'Entendido' : 'Ahora no', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
            ),
          ],
        );
        final icon = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(install ? Icons.add_to_home_screen_rounded : Icons.notifications_active_rounded, color: OhtliColors.stormyTeal, size: 20),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: OhtliSurface(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: 12), Expanded(child: text)]),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Row(children: [icon, const SizedBox(width: 14), Expanded(child: text), const SizedBox(width: 12), actions]);
            }),
          ),
        );
      },
    );
  }
}

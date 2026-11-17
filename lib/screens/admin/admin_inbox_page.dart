import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/admin.dart';
import '../../services/admin_inbox.dart';
import '../../services/place_feedback_service.dart';
import '../../theme/colors.dart';
import '../legal/legal_content.dart';
import 'app_feedback_page.dart';
import 'place_feedback_page.dart';

/// Bandeja de administración (solo superusuario), en tres secciones separadas: fotos donadas,
/// reportes de lugares y comentarios de la app. Cada una dice cuántos esperan revisión y tiene
/// su interruptor para avisar por correo de cada nuevo.
class AdminInboxPage extends StatefulWidget {
  final AdminInboxSection initial;
  const AdminInboxPage({super.key, this.initial = AdminInboxSection.feedback});

  @override
  State<AdminInboxPage> createState() => _AdminInboxPageState();
}

class _AdminInboxPageState extends State<AdminInboxPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: AdminInboxSection.values.length,
    vsync: this,
    initialIndex: AdminInboxSection.values.indexOf(widget.initial),
  );

  // Un stream por sección para toda la vida de la página (si se crean en build, cada redibujo
  // vuelve a suscribirse y el contador no alcanza a llegar).
  final Map<AdminInboxSection, Stream<int>> _pending = {
    for (final s in AdminInboxSection.values) s: AdminInbox.watchPending(s).asBroadcastStream(),
  };
  final Stream<Map<AdminInboxSection, bool>> _flags = AdminInbox.watchEmailFlags();

  static const _icons = {
    AdminInboxSection.donations: Icons.volunteer_activism_outlined,
    AdminInboxSection.reports: Icons.flag_outlined,
    AdminInboxSection.feedback: Icons.rate_review_outlined,
  };

  static const _emailText = {
    AdminInboxSection.donations: 'Avisarme por correo de cada foto donada',
    AdminInboxSection.reports: 'Avisarme por correo de cada reporte de un lugar',
    AdminInboxSection.feedback: 'Avisarme por correo de cada comentario',
  };

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _tab(AdminInboxSection s) => Tab(
        child: StreamBuilder<int>(
          stream: _pending[s],
          builder: (context, snap) {
            final n = snap.data ?? 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icons[s], size: 18),
                const SizedBox(width: 6),
                Text(s.label),
                if (n > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: OhtliColors.accentFill, borderRadius: BorderRadius.circular(10)),
                    child: Text('$n', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ],
            );
          },
        ),
      );

  Widget _emailSwitch(AdminInboxSection s, Map<AdminInboxSection, bool>? flags) {
    final on = flags?[s] ?? true;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(on ? Icons.mark_email_unread_outlined : Icons.unsubscribe_outlined,
              size: 20, color: on ? OhtliColors.stormyTeal : OhtliColors.subtleText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_emailText[s]!,
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                Text(on ? 'Llegan a ${LegalInfo.privacyEmail}' : 'Apagado: solo los verás aquí',
                    style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            activeTrackColor: OhtliColors.stormyTeal,
            onChanged: flags == null
                ? null
                : (v) async {
                    try {
                      await AdminInbox.setEmail(s, v);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.'), backgroundColor: OhtliColors.warning),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _body(AdminInboxSection s) => switch (s) {
        AdminInboxSection.donations => const PlaceFeedbackPage(type: kFeedbackPhoto, embedded: true),
        AdminInboxSection.reports => const PlaceFeedbackPage(type: kFeedbackReport, embedded: true),
        AdminInboxSection.feedback => const AppFeedbackPage(embedded: true),
      };

  @override
  Widget build(BuildContext context) {
    if (!isSuperUser()) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(child: Text('Esta sección es solo para el administrador de Ohtli.', style: GoogleFonts.inter(color: OhtliColors.onyx))),
      );
    }
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OhtliColors.onyx,
        title: Text('Bandeja de administración', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: OhtliColors.accentText,
          unselectedLabelColor: OhtliColors.subtleText,
          indicatorColor: OhtliColors.accentText,
          labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: [for (final s in AdminInboxSection.values) _tab(s)],
        ),
      ),
      body: StreamBuilder<Map<AdminInboxSection, bool>>(
        stream: _flags,
        builder: (context, snap) => TabBarView(
          controller: _tabs,
          children: [
            for (final s in AdminInboxSection.values)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _emailSwitch(s, snap.data),
                  Expanded(child: _body(s)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

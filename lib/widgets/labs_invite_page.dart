import 'package:flutter/material.dart';

import '../labs/lab_title.dart';
import '../screens/legal/legal_center_page.dart';
import '../screens/legal/legal_content.dart';
import '../services/labs_invite.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';

/// Invitación a pantalla completa para responder los estudios de Ohtli Labs (se muestra una
/// sola vez por momento, ver [LabsInvite]). Devuelve `true` al cerrar si la persona aceptó y
/// quedó registrada como tester.
class LabsInvitePage extends StatefulWidget {
  final LabsInviteMoment moment;

  /// Alta como tester. Si lanza, se avisa y la persona puede reintentar.
  final Future<void> Function() onAccept;

  const LabsInvitePage({super.key, required this.moment, required this.onAccept});

  static const consentPoints = [
    'Participas de forma voluntaria y puedes dejar Labs cuando quieras.',
    'Tus respuestas se guardan sin nombre ni correo, solo con un identificador interno para evitar duplicados.',
    'Los resultados agregados pueden publicarse en el Trabajo Terminal y en labs.ohtli.quest.',
    'Lo que veas en Labs es experimental y confidencial hasta su lanzamiento.',
    'No te pediremos datos sensibles ni de pago.',
  ];

  @override
  State<LabsInvitePage> createState() => _LabsInvitePageState();
}

class _LabsInvitePageState extends State<LabsInvitePage> {
  bool _sending = false;
  String? _error;

  String get _headline => switch (widget.moment) {
        LabsInviteMoment.aiTrip => 'Ya armaste tu primer viaje con la IA de Ohtli',
        LabsInviteMoment.aiGroup => 'Ya armaste tu primer plan con IA con tus amigos',
      };

  String get _lead => switch (widget.moment) {
        LabsInviteMoment.aiTrip =>
          '¿Nos cuentas qué tal te fue? Ohtli es un Trabajo Terminal de ESCOM-IPN y tu opinión nos ayuda a saber si las rutas que propone la IA de verdad te sirven.',
        LabsInviteMoment.aiGroup =>
          '¿Nos cuentas qué tal les fue? Ohtli es un Trabajo Terminal de ESCOM-IPN y tu opinión nos ayuda a saber si los planes en grupo funcionan para todos.',
      };

  Future<void> _accept() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onAccept();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'No pudimos registrarte como tester. Inténtalo de nuevo en un momento.';
        });
      }
    }
  }

  void _openTerms() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => LegalCenterPage(initialDoc: LegalDocId.labs, onBack: () => Navigator.of(ctx).pop()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = OhtliUi.pagePadding(width);
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, 56, pad, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.science_outlined, size: 16, color: OhtliColors.accent),
                    const SizedBox(width: 6),
                    Text('OHTLI LABS', style: OhtliUi.eyebrow(OhtliColors.accent)),
                  ]),
                  const SizedBox(height: 12),
                  Text(_headline, style: OhtliUi.title(size: width < 700 ? 28 : 36)),
                  const SizedBox(height: 12),
                  Text(_lead, style: OhtliUi.body(size: 15.5)),
                  const SizedBox(height: 22),
                  OhtliSurface(
                    radius: OhtliUi.radiusCard,
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fact(Icons.timer_outlined, 'Toma entre 5 y 15 minutos', 'Un cuestionario corto y, si quieres, calificar algunas rutas.'),
                      const SizedBox(height: 14),
                      _fact(Icons.workspace_premium_outlined, 'Ganas el título $kLabTitleName',
                          'Al responder cualquier estudio lo puedes mostrar en tu perfil.'),
                      const SizedBox(height: 14),
                      _fact(Icons.verified_user_outlined, 'Entras como tester de Labs',
                          'Pruebas funciones antes que nadie y ves los resultados liberados para testers.'),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  Text('Al aceptar das tu consentimiento:', style: OhtliUi.body(size: 13.5).copyWith(color: OhtliColors.onyx, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final t in LabsInvitePage.consentPoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_outline, size: 16, color: OhtliColors.accentText),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t, style: OhtliUi.body(size: 13))),
                      ]),
                    ),
                  TextButton(onPressed: _openTerms, child: const Text('Leer los términos de Ohtli Labs')),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(_error!, style: OhtliUi.body(size: 13).copyWith(color: OhtliColors.warningText)),
                  ],
                  const SizedBox(height: 18),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    OhtliPrimaryButton(
                      label: _sending ? 'Registrando…' : 'Acepto, quiero responder',
                      icon: Icons.arrow_forward_rounded,
                      highlight: true,
                      loading: _sending,
                      onPressed: _sending ? null : _accept,
                    ),
                    OhtliSecondaryButton(
                      label: 'Ahora no',
                      onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text('Te abriremos los estudios en labs.ohtli.quest con tu misma cuenta.', style: OhtliUi.body(size: 12)),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              tooltip: 'Cerrar',
              icon: const Icon(Icons.close_rounded),
              color: OhtliColors.onyx,
              onPressed: _sending ? null : () => Navigator.of(context).pop(false),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _fact(IconData icon, String title, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: OhtliColors.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: OhtliColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: OhtliUi.body(size: 14.5).copyWith(color: OhtliColors.onyx, fontWeight: FontWeight.w700)),
            Text(text, style: OhtliUi.body(size: 13)),
          ]),
        ),
      ]);
}

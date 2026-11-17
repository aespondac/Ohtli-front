import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/contribution_titles.dart';
import '../services/feedback_service.dart';
import '../services/place_feedback_service.dart';
import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import 'ohtli_ui.dart';

/// Después de subir la foto de un lugar del catálogo: ofrece donarla para que sea la foto del
/// lugar. Si acepta, sube una copia y queda pendiente de aprobación. No interrumpe si no acepta.
Future<void> offerPhotoDonation(
  BuildContext context, {
  required String poiId,
  required String poiName,
  required String dataUrl,
  String? tripId,
}) async {
  if (poiId.isEmpty) return;
  final donate = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: const Icon(Icons.volunteer_activism_rounded, color: OhtliColors.stormyTeal, size: 30),
      title: Text('¿Donas esta foto a $poiName?',
          textAlign: TextAlign.center, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
      content: Text(
        'Si la aprobamos, será la foto del lugar para todos en Ohtli, con tu nombre como crédito. '
        'En tu viaje se queda igual.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: OhtliColors.subtleText),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OhtliSecondaryButton(label: 'Solo para mi viaje', onPressed: () => Navigator.pop(ctx, false)),
        OhtliPrimaryButton(label: 'Donar foto', icon: Icons.volunteer_activism_rounded, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (donate != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final newTitle = await PlaceFeedbackService.donatePhoto(poiId: poiId, poiName: poiName, dataUrl: dataUrl, tripId: tripId);
    messenger.showSnackBar(SnackBar(
      content: Text(newTitle
          ? '¡Gracias! Ganaste el título ${kTitleDonor.name}. Si aprobamos tu foto, ganas ${kTitleDonorApproved.name}.'
          : '¡Gracias! Revisaremos tu foto y te avisamos cuando se publique.'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo enviar tu foto. Intenta de nuevo.'))));
  }
}

/// Cómo se presenta cada dato en la hoja de reporte: texto de la lista, ícono y la pregunta
/// con la que se pide la corrección.
const Map<String, (String, IconData, String)> _reportUi = {
  'closed': ('Cerró definitivamente', Icons.block_rounded, '¿Qué sabes? (opcional)'),
  'name': ('El nombre', Icons.title_rounded, '¿Cómo se llama en realidad?'),
  'address': ('La dirección', Icons.signpost_outlined, '¿Cuál es la dirección correcta?'),
  'location': ('La ubicación en el mapa', Icons.wrong_location_outlined, '¿Dónde está en realidad? (calle, esquina o referencia)'),
  'opening_hours': ('El horario', Icons.schedule_rounded, '¿Cuál es el horario correcto? p. ej. Lun a vie 9:00–18:00'),
  'price': ('El precio', Icons.payments_outlined, '¿Cuánto se gasta por persona, en pesos?'),
  'photo': ('La foto', Icons.hide_image_outlined, '¿Qué tiene de malo la foto?'),
  'category': ('El tipo de lugar', Icons.category_outlined, '¿Qué tipo de lugar es? p. ej. cafetería, museo, cantina'),
  'accessibility': ('La accesibilidad', Icons.accessible_rounded, '¿Qué hay o qué falta? rampas, elevador, baños…'),
  'description': ('La descripción', Icons.notes_rounded, '¿Qué le falta o qué está mal?'),
  'other': ('Algo más…', Icons.edit_note_rounded, 'Cuéntanos qué falta o qué está mal y cómo debería ser'),
};

/// Reportar un lugar: se elige qué dato (o "Algo más"), si falta o está mal, y se escribe la
/// corrección. Llega al administrador, que la aplica al aprobarla.
Future<void> showReportPlaceSheet(BuildContext context,
    {required String poiId, required String poiName, String photoUrl = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportPlaceSheet(poiId: poiId, poiName: poiName, photoUrl: photoUrl),
  );
}

class _ReportPlaceSheet extends StatefulWidget {
  const _ReportPlaceSheet({required this.poiId, required this.poiName, required this.photoUrl});
  final String poiId;
  final String poiName;
  final String photoUrl;

  @override
  State<_ReportPlaceSheet> createState() => _ReportPlaceSheetState();
}

class _ReportPlaceSheetState extends State<_ReportPlaceSheet> {
  String? _field;
  String _kind = kIssueWrong;
  final TextEditingController _value = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  // Sin "falta / está mal" en los que no aplica
  bool get _asksKind => !{'closed', 'other', 'photo', 'description'}.contains(_field);
  bool get _valueRequired => _field == 'other';

  Future<void> _send() async {
    final field = _field!;
    final text = _value.text.trim();
    setState(() => _sending = true);
    // Métrica de calidad del catálogo (también sin sesión)
    FeedbackService.report(widget.poiId, closed: field == 'closed', reason: field);
    try {
      final newTitle = await PlaceFeedbackService.report(
        poiId: widget.poiId,
        poiName: widget.poiName,
        issues: [PlaceIssue(field: field, kind: field == 'other' ? kIssueWrong : _kind, value: text)],
        // La foto que se reporta, para quitarla aunque sea una donación ya aprobada
        note: field == 'photo' && widget.photoUrl.isNotEmpty ? 'Foto reportada: ${widget.photoUrl}' : '',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(newTitle
            ? '¡Gracias! Ganaste el título ${kTitleReporter.name}. Si aprobamos tu reporte, ganas ${kTitleReporterApproved.name}.'
            : '¡Gracias! Lo revisamos y te avisamos cuando quede corregido.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: e is StateError ? e.message : 'No se pudo enviar el reporte.'))),
      );
    }
  }

  Widget _list() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('¿Qué falta o está mal en ${widget.poiName}?',
                style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Elige el dato y dinos cómo debería ser. Lo revisamos antes de cambiarlo.', style: OhtliUi.body(size: 13)),
          ),
          for (final e in _reportUi.entries)
            ListTile(
              leading: Icon(e.value.$2, color: OhtliColors.accentText),
              title: Text(e.value.$1, style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx)),
              trailing: Icon(Icons.chevron_right_rounded, color: OhtliColors.subtleText),
              onTap: () => setState(() {
                _field = e.key;
                _kind = kIssueWrong;
                _value.clear();
              }),
            ),
        ],
      );

  Widget _detail() {
    final ui = _reportUi[_field]!;
    final canSend = !_sending && (!_valueRequired || _value.text.trim().isNotEmpty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Volver',
                onPressed: _sending ? null : () => setState(() => _field = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Icon(ui.$2, color: OhtliColors.accentText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_field == 'other' ? 'Algo más de ${widget.poiName}' : '${ui.$1} · ${widget.poiName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_asksKind) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OhtliChoiceChip(label: 'Está mal', selected: _kind == kIssueWrong, onTap: () => setState(() => _kind = kIssueWrong)),
                      OhtliChoiceChip(label: 'Falta', selected: _kind == kIssueMissing, onTap: () => setState(() => _kind = kIssueMissing)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _value,
                  autofocus: true,
                  maxLength: _field == 'other' ? 500 : 200,
                  minLines: _field == 'other' ? 3 : 1,
                  maxLines: _field == 'other' ? 6 : 3,
                  keyboardType: _field == 'price' ? TextInputType.number : TextInputType.text,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    // La pregunta arriba y el ejemplo dentro, para que en móvil no se corte
                    labelText: ui.$3.split(RegExp(r' p\. ej\.| \(')).first,
                    hintText: ui.$3.contains(' p. ej.')
                        ? 'p. ej.${ui.$3.split(' p. ej.').last}'
                        : (ui.$3.contains(' (') ? ui.$3.substring(ui.$3.indexOf(' (') + 1) : null),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: OhtliPrimaryButton(
                    label: 'Enviar',
                    icon: Icons.flag_rounded,
                    loading: _sending,
                    onPressed: canSend ? _send : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(color: OhtliColors.cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: OhtliColors.cardBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(key: ValueKey(_field), child: _field == null ? _list() : _detail()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

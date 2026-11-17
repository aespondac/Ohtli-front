import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    await PlaceFeedbackService.donatePhoto(poiId: poiId, poiName: poiName, dataUrl: dataUrl, tripId: tripId);
    messenger.showSnackBar(const SnackBar(content: Text('¡Gracias! Revisaremos tu foto y te avisamos cuando se publique.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo enviar tu foto. Intenta de nuevo.'))));
  }
}

/// Reportar un lugar: se marca qué falta o qué está mal (y, si se sabe, el dato correcto).
Future<void> showReportPlaceSheet(BuildContext context, {required String poiId, required String poiName}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportPlaceSheet(poiId: poiId, poiName: poiName),
  );
}

class _ReportPlaceSheet extends StatefulWidget {
  const _ReportPlaceSheet({required this.poiId, required this.poiName});
  final String poiId;
  final String poiName;

  @override
  State<_ReportPlaceSheet> createState() => _ReportPlaceSheetState();
}

class _ReportPlaceSheetState extends State<_ReportPlaceSheet> {
  // campo → 'missing' | 'wrong'
  final Map<String, String> _kinds = {};
  final Map<String, TextEditingController> _values = {};
  final TextEditingController _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    for (final c in _values.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  TextEditingController _valueFor(String field) => _values.putIfAbsent(field, TextEditingController.new);

  Future<void> _send() async {
    setState(() => _sending = true);
    final issues = [
      for (final f in kReportableFields)
        if (_kinds[f.id] != null) PlaceIssue(field: f.id, kind: _kinds[f.id]!, value: _values[f.id]?.text ?? ''),
    ];
    try {
      await PlaceFeedbackService.report(poiId: widget.poiId, poiName: widget.poiName, issues: issues, note: _note.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('¡Gracias! Lo revisamos y te avisamos cuando quede corregido.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: e is StateError ? e.message : 'No se pudo enviar el reporte.'))),
      );
    }
  }

  Widget _fieldRow(PlaceField f) {
    final kind = _kinds[f.id];
    // "Cerró definitivamente" no es falta ni error: se marca o no
    final closedField = f.id == 'closed';
    Widget choice(String value, String label) => OhtliChoiceChip(
          label: label,
          selected: kind == value,
          onTap: () => setState(() => kind == value ? _kinds.remove(f.id) : _kinds[f.id] = value),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(f.label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
              ),
              if (closedField)
                choice(kIssueWrong, 'Sí, cerró')
              else ...[
                choice(kIssueMissing, 'Falta'),
                const SizedBox(width: 6),
                choice(kIssueWrong, 'Está mal'),
              ],
            ],
          ),
          if (kind != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _valueFor(f.id),
              maxLength: 200,
              keyboardType: f.id == 'price' ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                // El dato correcto es opcional; el ejemplo cabe completo en móvil
                hintText: f.hint,
                prefixIcon: Icon(kind == kIssueMissing ? Icons.add_rounded : Icons.edit_rounded, size: 18, color: OhtliColors.subtleText),
                filled: true,
                fillColor: OhtliColors.cloudDancer,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
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
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: OhtliColors.cardBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Reportar ${widget.poiName}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 4),
                Text('Marca qué falta o qué está mal. Lo revisamos antes de cambiarlo.', style: OhtliUi.body(size: 13.5)),
                const SizedBox(height: 18),
                for (final f in kReportableFields) _fieldRow(f),
                const SizedBox(height: 4),
                TextField(
                  controller: _note,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Algo más que debamos saber (opcional)',
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OhtliPrimaryButton(
                    label: 'Enviar reporte',
                    icon: Icons.flag_rounded,
                    loading: _sending,
                    onPressed: _sending || _kinds.isEmpty ? null : _send,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

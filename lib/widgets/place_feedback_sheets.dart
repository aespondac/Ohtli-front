import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/contribution_titles.dart';
import '../services/feedback_service.dart';
import '../services/place_feedback_service.dart';
import '../utils/opening_hours.dart';
import '../services/poi_suggestion_service.dart';
import '../models/poi_model.dart';
import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import 'ohtli_ui.dart';

/// Si el lugar del catálogo ya tiene foto.
Future<bool> placeHasCatalogPhoto(String poiId) async {
  try {
    final d = (await FirebaseFirestore.instance.collection('pois').doc(poiId).get()).data() ?? const {};
    final url = (d['photo_url'] ?? d['image_url'] ?? d['photo'] ?? '').toString();
    if (url.isNotEmpty) return true;
    final photos = d['photos'];
    return photos is List && photos.isNotEmpty;
  } catch (_) {
    return true; // si no se sabe, se pregunta
  }
}

/// Antes de elegir la foto de un lugar del catálogo: si el lugar no tiene foto, se dona sola
/// (true); si ya tiene, se pregunta Subir o Subir y donar. null si se cancela.
Future<bool?> decidePhotoDonation(BuildContext context, {required String poiId, required String poiName}) async {
  if (poiId.isEmpty) return false;
  if (!await placeHasCatalogPhoto(poiId)) return true;
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: OhtliColors.cardBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Foto de $poiName', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Este lugar ya tiene foto en Ohtli. Si donas la tuya y la aprobamos, la reemplaza para todos.',
                  style: OhtliUi.body(size: 13)),
            ),
            ListTile(
              leading: Icon(Icons.add_photo_alternate_outlined, color: OhtliColors.accentText),
              title: Text('Subir', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
              subtitle: Text('Solo para tu viaje', style: OhtliUi.body(size: 12.5)),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_rounded, color: OhtliColors.stormyTeal),
              title: Text('Subir y donar', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
              subtitle: Text('Para tu viaje y, si la aprobamos, como foto del lugar', style: OhtliUi.body(size: 12.5)),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Dona la foto ya recortada (sin preguntar: la decisión se tomó antes de elegirla).
Future<void> donatePhotoNow(
  ScaffoldMessengerState messenger, {
  required String poiId,
  required String poiName,
  required String dataUrl,
  String? tripId,
}) async {
  try {
    final newTitle = await PlaceFeedbackService.donatePhoto(poiId: poiId, poiName: poiName, dataUrl: dataUrl, tripId: tripId);
    messenger.showSnackBar(SnackBar(
      content: Text(newTitle
          ? 'Donaste tu foto a $poiName y ganaste el título ${kTitleDonor.name}. Si la aprobamos, ganas ${kTitleDonorApproved.name}.'
          : 'Donaste tu foto a $poiName. Te avisamos cuando la revisemos.'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo donar tu foto. Quedó solo en tu viaje.'))));
  }
}

/// Un dato que se puede reportar: texto en la lista, ícono, pregunta para la corrección, opciones
/// cerradas (si las hay) y si se pueden marcar varias, y si pregunta «falta / está mal».
class _ReportCase {
  final String id;
  final String label;
  final IconData icon;
  final String question;
  final String? example;
  final List<(String, String)> options; // (valor, texto)
  final bool multi;
  final bool asksKind;
  final bool needsText;
  const _ReportCase(this.id, this.label, this.icon, this.question,
      {this.example, this.options = const [], this.multi = false, this.asksKind = true, this.needsText = false});
}

// Montos de referencia por nivel de precio (los mismos del motor)
const _priceLevels = [('0', 'Gratis'), ('85', 'Económico · ~\$85'), ('220', 'Moderado · ~\$220'), ('450', 'Costoso · ~\$450'), ('950', 'De lujo · ~\$950')];

final List<_ReportCase> _reportCases = [
  const _ReportCase('closed', 'Cerró', Icons.block_rounded, '¿Qué pasó?',
      options: [('definitivo', 'Cerró definitivamente'), ('temporal', 'Cerró temporalmente'), ('mudanza', 'Se mudó a otro lugar')],
      asksKind: false),
  const _ReportCase('name', 'El nombre', Icons.title_rounded, '¿Cómo se llama en realidad?'),
  const _ReportCase('address', 'La dirección', Icons.signpost_outlined, '¿Cuál es la dirección correcta?',
      example: 'Calle, número y colonia'),
  const _ReportCase('location', 'La ubicación en el mapa', Icons.wrong_location_outlined, '¿Dónde está en realidad?',
      example: 'Esquina o referencia',
      options: [('calle', 'Está en otra calle'), ('cuadra', 'Está a una o dos cuadras'), ('colonia', 'Está en otra colonia')],
      asksKind: false),
  const _ReportCase('opening_hours', 'El horario', Icons.schedule_rounded, 'Horario correcto',
      example: 'Lun a vie 9:00–18:00',
      options: [('24h', 'Abre las 24 horas'), ('lunes', 'Cierra los lunes'), ('domingo', 'Cierra los domingos'),
        ('tarde', 'Abre más tarde'), ('temprano', 'Cierra más temprano')],
      multi: true),
  const _ReportCase('price', 'El precio', Icons.payments_outlined, '¿Cuánto se gasta por persona?',
      example: 'Monto exacto en pesos (opcional)', options: _priceLevels),
  const _ReportCase('photo', 'La foto', Icons.hide_image_outlined, '¿Qué tiene de malo?',
      options: [('otro_lugar', 'No es de este lugar'), ('calidad', 'Está borrosa o de mala calidad'),
        ('vieja', 'Está desactualizada'), ('inapropiada', 'Tiene contenido inapropiado')],
      multi: true, asksKind: false),
  _ReportCase('category', 'El tipo de lugar', Icons.category_outlined, '¿Qué tipo de lugar es?',
      options: [for (final e in kSuggestionCategories.entries) (e.key, e.value)]),
  const _ReportCase('accessibility', 'La accesibilidad', Icons.accessible_rounded, '¿Qué hay o qué falta?',
      options: [('rampa', 'Tiene rampa'), ('elevador', 'Tiene elevador'), ('bano', 'Baño accesible'),
        ('sin_escalones', 'Entrada sin escalones'), ('no_accesible', 'No es accesible en silla de ruedas')],
      multi: true),
  const _ReportCase('description', 'La descripción', Icons.notes_rounded, '¿Qué está mal?',
      options: [('falsa', 'Tiene información falsa'), ('vieja', 'Está desactualizada'), ('otro_lugar', 'Habla de otro lugar'),
        ('tono', 'El tono no es adecuado')],
      multi: true, asksKind: false),
  const _ReportCase('other', 'Algo más…', Icons.edit_note_rounded, 'Cuéntanos qué falta o qué está mal y cómo debería ser',
      asksKind: false, needsText: true),
];

/// Reportar un lugar: se marcan uno o varios datos (o «Algo más»), en cada uno qué está mal con
/// opciones y la corrección, y antes de enviar se ve cómo quedaría. El admin lo aplica al aprobar.
Future<void> showReportPlaceSheet(BuildContext context, {required Poi poi}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportPlaceSheet(poi: poi),
  );
}

class _CaseState {
  String kind = kIssueWrong;
  final Set<String> options = {};
  final TextEditingController text = TextEditingController();
}

class _ReportPlaceSheet extends StatefulWidget {
  const _ReportPlaceSheet({required this.poi});
  final Poi poi;

  @override
  State<_ReportPlaceSheet> createState() => _ReportPlaceSheetState();
}

class _ReportPlaceSheetState extends State<_ReportPlaceSheet> {
  final Map<String, _CaseState> _picked = {}; // en el orden de _reportCases
  bool _editing = false; // paso 2
  bool _sending = false;

  @override
  void dispose() {
    for (final c in _picked.values) {
      c.text.dispose();
    }
    super.dispose();
  }

  List<_ReportCase> get _selected => [for (final c in _reportCases) if (_picked.containsKey(c.id)) c];

  bool get _complete => _selected.every((c) {
        final st = _picked[c.id]!;
        if (c.needsText) return st.text.text.trim().isNotEmpty;
        // Algo concreto: una opción o la corrección escrita
        return st.options.isNotEmpty || st.text.text.trim().isNotEmpty;
      });

  /// La corrección que se aplicaría: el monto, la clave de categoría o el texto escrito.
  String _fixOf(_ReportCase c) {
    final st = _picked[c.id]!;
    final text = st.text.text.trim();
    if (c.id == 'price') {
      final n = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (n != null) return n.toStringAsFixed(0);
      return st.options.isEmpty ? '' : st.options.first;
    }
    if (c.id == 'category') return st.options.isEmpty ? '' : st.options.first;
    // La foto que se reporta, para que el admin vea cuál es (aunque sea una donación aprobada)
    if (c.id == 'photo') return widget.poi.photoUrl;
    return text;
  }

  String _optionLabel(_ReportCase c, String value) => c.options.firstWhere((o) => o.$1 == value, orElse: () => (value, value)).$2;

  Future<void> _send() async {
    setState(() => _sending = true);
    final issues = <PlaceIssue>[];
    for (final c in _selected) {
      final st = _picked[c.id]!;
      issues.add(PlaceIssue(
        field: c.id,
        kind: c.asksKind ? st.kind : kIssueWrong,
        value: _fixOf(c),
        options: [for (final o in st.options) _optionLabel(c, o)],
      ));
      // Métrica de calidad del catálogo
      FeedbackService.report(widget.poi.poiId, closed: c.id == 'closed' && st.options.contains('definitivo'), reason: c.id);
    }
    try {
      final newTitle = await PlaceFeedbackService.report(
        poiId: widget.poi.poiId,
        poiName: widget.poi.name,
        issues: issues,
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

  // ---------- Paso 1: qué está mal (varios) ----------
  Widget _list() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('¿Qué falta o está mal en ${widget.poi.name}?',
                style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('Marca todo lo que aplique. Lo revisamos antes de cambiarlo.', style: OhtliUi.body(size: 13)),
          ),
          for (final c in _reportCases)
            CheckboxListTile(
              value: _picked.containsKey(c.id),
              onChanged: (v) => setState(() => v == true ? _picked[c.id] = _CaseState() : _picked.remove(c.id)?.text.dispose()),
              secondary: Icon(c.icon, color: OhtliColors.accentText),
              title: Text(c.label, style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx)),
              activeColor: OhtliColors.stormyTeal,
              controlAffinity: ListTileControlAffinity.trailing,
              dense: true,
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: OhtliPrimaryButton(
                label: _picked.isEmpty ? 'Continuar' : 'Continuar (${_picked.length})',
                icon: Icons.arrow_forward_rounded,
                onPressed: _picked.isEmpty ? null : () => setState(() => _editing = true),
              ),
            ),
          ),
        ],
      );

  // ---------- Paso 2: cada dato, con opciones y corrección ----------
  Widget _caseEditor(_ReportCase c) {
    final st = _picked[c.id]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(c.icon, size: 18, color: OhtliColors.accentText),
              const SizedBox(width: 8),
              Expanded(child: Text(c.label.replaceAll('…', ''), style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx))),
              if (c.asksKind)
                Wrap(spacing: 6, children: [
                  OhtliChoiceChip(label: 'Está mal', selected: st.kind == kIssueWrong, onTap: () => setState(() => st.kind = kIssueWrong)),
                  OhtliChoiceChip(label: 'Falta', selected: st.kind == kIssueMissing, onTap: () => setState(() => st.kind = kIssueMissing)),
                ]),
            ],
          ),
          if (c.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(c.multi ? '${c.question} (puedes marcar varias)' : c.question, style: OhtliUi.body(size: 12.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in c.options)
                  OhtliChoiceChip(
                    label: o.$2,
                    selected: st.options.contains(o.$1),
                    onTap: () => setState(() {
                      if (st.options.contains(o.$1)) {
                        st.options.remove(o.$1);
                      } else {
                        if (!c.multi) st.options.clear();
                        st.options.add(o.$1);
                      }
                    }),
                  ),
              ],
            ),
          ],
          // Corrección escrita: en los que no tienen opciones es la principal; en los demás, opcional
          if (c.id != 'category' && c.id != 'photo') ...[
            const SizedBox(height: 10),
            TextField(
              controller: st.text,
              maxLength: c.id == 'other' ? 500 : 200,
              minLines: c.id == 'other' ? 3 : 1,
              maxLines: c.id == 'other' ? 6 : 3,
              keyboardType: c.id == 'price' ? TextInputType.number : TextInputType.text,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                labelText: c.options.isEmpty ? c.question : (c.example ?? 'Detalle (opcional)'),
                hintText: c.options.isEmpty ? c.example : null,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                filled: true,
                fillColor: OhtliColors.cardBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- Vista previa: cómo se vería el lugar con lo corregido ----------
  Widget _preview() {
    final poi = widget.poi;
    String? fixed(String id) {
      if (!_picked.containsKey(id)) return null;
      final c = _reportCases.firstWhere((x) => x.id == id);
      final st = _picked[id]!;
      switch (id) {
        case 'price':
          final v = _fixOf(c);
          if (v.isEmpty) return null;
          final n = double.tryParse(v) ?? 0;
          return n == 0 ? 'Gratis' : '~\$${n.toStringAsFixed(0)} por persona';
        case 'category':
          return st.options.isEmpty ? null : kSuggestionCategories[st.options.first];
        case 'opening_hours':
          final parts = [...st.options.map((o) => _optionLabel(c, o)), if (st.text.text.trim().isNotEmpty) st.text.text.trim()];
          return parts.isEmpty ? null : parts.join(' · ');
        case 'accessibility':
          final parts = st.options.map((o) => _optionLabel(c, o)).toList();
          return parts.isEmpty ? null : parts.join(' · ');
        default:
          final t = st.text.text.trim();
          return t.isEmpty ? null : t;
      }
    }

    Widget row(IconData icon, String current, String? next) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: OhtliColors.subtleText),
              const SizedBox(width: 8),
              Expanded(
                child: next == null
                    ? Text(current.isEmpty ? '—' : current, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx))
                    : Text.rich(TextSpan(children: [
                        if (current.isNotEmpty)
                          TextSpan(
                            text: '$current  ',
                            style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, decoration: TextDecoration.lineThrough),
                          ),
                        TextSpan(text: next, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.accentText)),
                      ])),
              ),
            ],
          ),
        );

    final closedSt = _picked['closed'];
    final closedLabel = closedSt == null || closedSt.options.isEmpty
        ? null
        : _optionLabel(_reportCases.first, closedSt.options.first);
    final photoFlagged = _picked.containsKey('photo');
    final newName = fixed('name');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 84,
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poi.photoUrl.isNotEmpty)
                    Image.network(poi.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: OhtliColors.innerCardBg))
                  else
                    Container(color: OhtliColors.innerCardBg),
                  if (photoFlagged)
                    Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(6),
                      child: Text('Foto en revisión',
                          textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (closedLabel != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: OhtliColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text(closedLabel, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.warningText)),
                  ),
                Text(newName ?? poi.name,
                    style: GoogleFonts.outfit(
                        fontSize: 16, fontWeight: FontWeight.w800, color: newName != null ? OhtliColors.accentText : OhtliColors.onyx)),
                row(Icons.category_outlined, poi.categoryDisplay, fixed('category')),
                row(Icons.payments_outlined, poi.priceDisplay, fixed('price')),
                row(Icons.signpost_outlined, poi.address, fixed('address')),
                row(Icons.schedule_rounded, poi.openingHours.isEmpty ? '' : formatOpeningHours(poi.openingHours), fixed('opening_hours')),
                if (_picked.containsKey('accessibility')) row(Icons.accessible_rounded, '', fixed('accessibility')),
                if (_picked.containsKey('location')) row(Icons.wrong_location_outlined, 'Ubicación', fixed('location') ?? 'por corregir'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Volver',
                  onPressed: _sending ? null : () => setState(() => _editing = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text('Dinos cómo debería ser',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final c in _selected) _caseEditor(c),
            const SizedBox(height: 4),
            Text('ASÍ SE VERÍA', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
            const SizedBox(height: 8),
            _preview(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(_complete ? 'Lo revisamos antes de publicarlo.' : 'Elige una opción o escribe la corrección en cada dato.',
                      style: OhtliUi.body(size: 12)),
                ),
                OhtliPrimaryButton(
                  label: 'Enviar',
                  icon: Icons.flag_rounded,
                  loading: _sending,
                  onPressed: _sending || !_complete ? null : _send,
                ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
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
                  child: KeyedSubtree(key: ValueKey(_editing), child: _editing ? _editor() : _list()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/poi_model.dart';
import '../services/contribution_titles.dart';
import '../services/feedback_service.dart';
import '../services/place_feedback_service.dart';
import '../services/poi_suggestion_service.dart';
import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import '../utils/opening_hours.dart';
import 'address_picker_widget.dart' deferred as address_picker;
import 'ohtli_ui.dart';
import 'place_feedback_sheets.dart';
import 'place_search_field.dart';
import '../screens/trips/trip_traveler_tools.dart' deferred as tools;

/// Reportar un lugar: primero se marcan los datos que faltan o están mal; luego hay una vista por
/// cada uno, con opciones cerradas, la corrección y cómo se vería. Cada «Siguiente» envía ese dato
/// como un reporte aparte; se puede quitar un dato de la lista sin perder lo demás.
class PlaceReportPage extends StatefulWidget {
  const PlaceReportPage({super.key, required this.poi});
  final Poi poi;

  @override
  State<PlaceReportPage> createState() => _PlaceReportPageState();
}

// ---------------------------------------------------------------------------
// Casos
// ---------------------------------------------------------------------------

class _Case {
  final String id;
  final String label;
  final IconData icon;
  const _Case(this.id, this.label, this.icon);
}

const List<_Case> _cases = [
  _Case('closed', 'Cerró o se mudó', Icons.block_rounded),
  _Case('name', 'El nombre', Icons.title_rounded),
  _Case('address', 'La dirección', Icons.signpost_outlined),
  _Case('location', 'La ubicación en el mapa', Icons.wrong_location_outlined),
  _Case('opening_hours', 'El horario', Icons.schedule_rounded),
  _Case('price', 'El precio', Icons.payments_outlined),
  _Case('photo', 'La foto', Icons.hide_image_outlined),
  _Case('category', 'El tipo de lugar', Icons.category_outlined),
  _Case('accessibility', 'La accesibilidad', Icons.accessible_rounded),
  _Case('description', 'La descripción', Icons.notes_rounded),
  _Case('other', 'Algo más…', Icons.edit_note_rounded),
];

_Case _caseOf(String id) => _cases.firstWhere((c) => c.id == id);

const _priceLevels = [('0', 'Gratis'), ('85', 'Económico · ~\$85'), ('220', 'Moderado · ~\$220'), ('450', 'Costoso · ~\$450'), ('950', 'De lujo · ~\$950')];
const _photoIssues = [('otro_lugar', 'No es de este lugar'), ('calidad', 'Está borrosa o de mala calidad'), ('vieja', 'Está desactualizada'), ('inapropiada', 'Tiene contenido inapropiado')];
const _accessOptions = [('rampa', 'Tiene rampa'), ('elevador', 'Tiene elevador'), ('bano', 'Baño accesible'), ('sin_escalones', 'Entrada sin escalones'), ('no_accesible', 'No es accesible en silla de ruedas')];
const _descIssues = [('falsa', 'Tiene información falsa'), ('vieja', 'Está desactualizada'), ('otro_lugar', 'Habla de otro lugar'), ('tono', 'El tono no es adecuado')];
const _closedKinds = [('definitivo', 'Cerró definitivamente'), ('temporal', 'Cerró temporalmente'), ('mudanza', 'Se mudó a otro lugar')];
// Si el lugar ya aparece como cerrado, lo que se reporta es que volvió a abrir (o que se mudó)
const _reopenKinds = [('reabrio', 'Ya volvió a abrir'), ('mudanza', 'Se mudó a otro lugar')];

// Días de la semana: OSM y etiqueta
const _osmDays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
const _dayLabels = ['L', 'M', 'Mi', 'J', 'V', 'S', 'D'];
const _dayNames = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Un horario: días, apertura y cierre, y una pausa opcional (p. ej. comida de 14 a 16).
class _HoursRow {
  final Set<int> days;
  TimeOfDay open;
  TimeOfDay close;
  TimeOfDay? pauseFrom;
  TimeOfDay? pauseTo;
  _HoursRow(this.days, this.open, this.close);
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Días en formato OSM, con rangos: {0,1,2,3,4} → Mo-Fr; {0,2} → Mo,We.
String _osmDaySpec(Set<int> days) {
  final sorted = days.toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(j - i >= 2 ? '${_osmDays[sorted[i]]}-${_osmDays[sorted[j]]}' : [for (var k = i; k <= j; k++) _osmDays[sorted[k]]].join(','));
    i = j + 1;
  }
  return parts.join(',');
}

/// Estado de lo que va escribiendo en cada dato (se conserva aunque lo quite de la lista).
class _Draft {
  String kind = kIssueWrong;
  final Set<String> options = {};
  final TextEditingController text = TextEditingController();
  // Horario
  bool allDay = false;
  final List<_HoursRow> rows = [];
  final List<DateTime> closedDates = [];
  // Mudanza o ubicación nueva
  String? movedName;
  double? lat;
  double? lng;
  final TextEditingController movedController = TextEditingController();
  // Dirección nueva (del modal de direcciones)
  Map<String, dynamic>? address;
  // Hasta cuándo cierra (temporal)
  DateTime? reopens;
  // Foto donada en este reporte
  bool donated = false;

  void dispose() {
    text.dispose();
    movedController.dispose();
  }
}

class _PlaceReportPageState extends State<PlaceReportPage> {
  final Set<String> _selected = {}; // en el orden de _cases
  final Map<String, _Draft> _drafts = {};
  final Set<String> _sent = {};
  String? _current; // null = lista
  bool _sending = false;
  bool _wonTitle = false;

  @override
  void dispose() {
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  Poi get poi => widget.poi;
  bool get _placeClosed => poi.isClosedPermanently || poi.isClosedTemporarily;
  List<(String, String)> get _statusKinds => _placeClosed ? _reopenKinds : _closedKinds;
  String _caseLabel(_Case c) => c.id == 'closed' && _placeClosed ? 'Volvió a abrir o se mudó' : c.label;
  _Draft _d(String id) => _drafts.putIfAbsent(id, () {
        final d = _Draft();
        if (id == 'opening_hours') d.rows.add(_HoursRow({0, 1, 2, 3, 4}, const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 18, minute: 0)));
        if (id == 'location') {
          d.lat = poi.location.lat;
          d.lng = poi.location.lng;
        }
        return d;
      });

  List<String> get _flow => [for (final c in _cases) if (_selected.contains(c.id)) c.id];
  List<String> get _pending => [for (final id in _flow) if (!_sent.contains(id)) id];

  // -------------------------------------------------------------------------
  // Horario → OSM
  // -------------------------------------------------------------------------

  String _osmHours(_Draft d) {
    if (d.allDay) return '24/7';
    final rules = <String>[];
    final covered = <int>{};
    for (final r in d.rows) {
      if (r.days.isEmpty) continue;
      covered.addAll(r.days);
      final times = r.pauseFrom != null && r.pauseTo != null
          ? '${_hhmm(r.open)}-${_hhmm(r.pauseFrom!)},${_hhmm(r.pauseTo!)}-${_hhmm(r.close)}'
          : '${_hhmm(r.open)}-${_hhmm(r.close)}';
      rules.add('${_osmDaySpec(r.days)} $times');
    }
    final off = {for (var i = 0; i < 7; i++) i}.difference(covered);
    if (off.isNotEmpty && rules.isNotEmpty) rules.add('${_osmDaySpec(off)} off');
    return rules.join('; ');
  }

  String _dateText(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  // -------------------------------------------------------------------------
  // Qué se envía de cada dato
  // -------------------------------------------------------------------------

  String _label(List<(String, String)> list, String v) => list.firstWhere((o) => o.$1 == v, orElse: () => (v, v)).$2;

  bool _ready(String id) {
    final d = _d(id);
    final text = d.text.text.trim();
    switch (id) {
      case 'closed':
        if (d.options.isEmpty) return false;
        return !d.options.contains('mudanza') || d.lat != null || text.isNotEmpty;
      case 'name':
        return text.isNotEmpty;
      case 'address':
        return d.address != null || text.isNotEmpty;
      case 'location':
        return d.lat != null && (d.lat != poi.location.lat || d.lng != poi.location.lng);
      case 'opening_hours':
        return d.allDay || d.rows.any((r) => r.days.isNotEmpty) || d.closedDates.isNotEmpty;
      case 'price':
      case 'category':
        return d.options.isNotEmpty || (id == 'price' && text.isNotEmpty);
      case 'photo':
      case 'accessibility':
      case 'description':
        return d.options.isNotEmpty || text.isNotEmpty || d.donated;
      case 'other':
        return text.isNotEmpty;
    }
    return false;
  }

  PlaceIssue _issue(String id) {
    final d = _d(id);
    final text = d.text.text.trim();
    switch (id) {
      case 'closed':
        final kind = d.options.isEmpty ? '' : d.options.first;
        return PlaceIssue(field: id, kind: kIssueWrong, value: text, options: [_label(_statusKinds, kind)], extra: {
          'status': kind,
          if (kind == 'mudanza' && d.lat != null) 'movedTo': {'name': d.movedName ?? '', 'lat': d.lat, 'lng': d.lng},
          if (kind == 'temporal' && d.reopens != null) 'reopens': d.reopens!.toIso8601String().substring(0, 10),
        });
      case 'address':
        final a = d.address;
        final full = a == null
            ? text
            : [a['street'], a['suburb'], if ((a['zip'] ?? '').toString().isNotEmpty) 'C.P. ${a['zip']}', a['city']]
                .where((x) => (x ?? '').toString().trim().isNotEmpty)
                .join(', ');
        return PlaceIssue(field: id, kind: d.kind, value: full, extra: {
          if (a != null && a['lat'] != null) 'location': {'lat': a['lat'], 'lng': a['lng']},
          if (text.isNotEmpty && a != null) 'detail': text,
        });
      case 'location':
        return PlaceIssue(field: id, kind: kIssueWrong, value: '${d.lat!.toStringAsFixed(6)}, ${d.lng!.toStringAsFixed(6)}', extra: {
          'location': {'lat': d.lat, 'lng': d.lng},
          if (text.isNotEmpty) 'detail': text,
        });
      case 'opening_hours':
        return PlaceIssue(field: id, kind: d.kind, value: _osmHours(d), extra: {
          if (d.closedDates.isNotEmpty) 'closedDates': [for (final x in d.closedDates) x.toIso8601String().substring(0, 10)],
          if (text.isNotEmpty) 'detail': text,
        });
      case 'price':
        final n = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
        return PlaceIssue(field: id, kind: d.kind, value: n != null ? n.toStringAsFixed(0) : (d.options.isEmpty ? '' : d.options.first));
      case 'category':
        return PlaceIssue(field: id, kind: d.kind, value: d.options.isEmpty ? '' : d.options.first);
      case 'photo':
        return PlaceIssue(field: id, kind: kIssueWrong, value: poi.photoUrl, options: [for (final o in d.options) _label(_photoIssues, o)], extra: {
          if (text.isNotEmpty) 'detail': text,
          if (d.donated) 'donatedReplacement': true,
        });
      case 'accessibility':
        return PlaceIssue(field: id, kind: d.kind, value: text, options: [for (final o in d.options) _label(_accessOptions, o)]);
      case 'description':
        return PlaceIssue(field: id, kind: kIssueWrong, value: text, options: [for (final o in d.options) _label(_descIssues, o)]);
      default:
        return PlaceIssue(field: id, kind: d.kind, value: text);
    }
  }

  /// Envía el dato actual como su propio reporte y pasa al siguiente.
  Future<void> _sendCurrent() async {
    final id = _current!;
    setState(() => _sending = true);
    final issue = _issue(id);
    FeedbackService.report(poi.poiId, closed: id == 'closed' && _d(id).options.contains('definitivo'), reason: id);
    try {
      // La foto se puede reportar solo para donar otra: entonces no hace falta un reporte
      final onlyDonation = id == 'photo' && _d(id).options.isEmpty && _d(id).text.text.trim().isEmpty;
      if (!onlyDonation) {
        final won = await PlaceFeedbackService.report(poiId: poi.poiId, poiName: poi.name, issues: [issue]);
        _wonTitle = _wonTitle || won;
      }
      if (!mounted) return;
      setState(() {
        _sent.add(id);
        _sending = false;
        final next = _pending;
        _current = next.isEmpty ? '_done' : next.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: e is StateError ? e.message : 'No se pudo enviar. Intenta de nuevo.'))),
      );
    }
  }

  void _toggleSelected(String id) => setState(() {
        if (_sent.contains(id)) return; // lo enviado ya no se quita
        if (_selected.contains(id)) {
          _selected.remove(id);
          if (_current == id) {
            final next = _pending;
            _current = next.isEmpty ? (_sent.isEmpty ? null : '_done') : next.first;
          }
        } else {
          _selected.add(id);
        }
      });

  // -------------------------------------------------------------------------
  // Pantallas
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final step = _current;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OhtliColors.onyx,
        leading: IconButton(
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Reportar ${poi.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(step),
                child: step == null ? _listView() : (step == '_done' ? _doneView() : _caseView(step)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listView() => ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text('¿Qué falta o está mal?', style: OhtliUi.title(size: 24)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text('Marca todo lo que aplique. Luego vas uno por uno y cada uno se envía al darle Siguiente.',
                style: OhtliUi.body(size: 13.5)),
          ),
          OhtliSurface(
            radius: 20,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final c in _cases)
                  CheckboxListTile(
                    value: _selected.contains(c.id),
                    onChanged: (_) => _toggleSelected(c.id),
                    secondary: Icon(c.icon, color: OhtliColors.accentText),
                    title: Text(_caseLabel(c), style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx)),
                    activeColor: OhtliColors.stormyTeal,
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OhtliPrimaryButton(
              label: _selected.isEmpty ? 'Continuar' : 'Continuar (${_selected.length})',
              icon: Icons.arrow_forward_rounded,
              onPressed: _selected.isEmpty ? null : () => setState(() => _current = _pending.first),
            ),
          ),
        ],
      );

  Widget _doneView() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.task_alt_rounded, size: 56, color: OhtliColors.stormyTeal),
            const SizedBox(height: 14),
            Text(_sent.length == 1 ? '¡Gracias! Enviamos tu reporte' : '¡Gracias! Enviamos tus ${_sent.length} reportes',
                textAlign: TextAlign.center, style: OhtliUi.title(size: 22)),
            const SizedBox(height: 8),
            Text(
              _wonTitle
                  ? 'Ganaste el título ${kTitleReporter.name}. Si aprobamos tus reportes, ganas ${kTitleReporterApproved.name}.'
                  : 'Los revisamos y te avisamos cuando queden corregidos.',
              textAlign: TextAlign.center,
              style: OhtliUi.body(size: 14),
            ),
            const SizedBox(height: 20),
            OhtliPrimaryButton(label: 'Listo', icon: Icons.check_rounded, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      );

  /// Encabezado del paso: los datos elegidos como fichas (✓ enviado, ✕ para quitarlo) y el avance.
  Widget _stepHeader(String id) {
    final flow = _flow;
    final index = flow.indexOf(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${index + 1} de ${flow.length}', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in flow)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InputChip(
                    label: Text(_caseLabel(_caseOf(f)).replaceAll('…', '')),
                    avatar: _sent.contains(f) ? const Icon(Icons.check_rounded, size: 16, color: OhtliColors.stormyTeal) : null,
                    selected: f == id,
                    showCheckmark: false,
                    selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.16),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onPressed: _sent.contains(f) ? null : () => setState(() => _current = f),
                    // Quitar este dato sin perder lo que lleva en los demás
                    onDeleted: _sent.contains(f) ? null : () => _toggleSelected(f),
                    deleteButtonTooltipMessage: 'Quitar',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(_caseOf(id).icon, color: OhtliColors.accentText),
            const SizedBox(width: 10),
            Expanded(child: Text(_caseLabel(_caseOf(id)).replaceAll('…', ''), style: OhtliUi.title(size: 22))),
          ],
        ),
      ],
    );
  }

  Widget _caseView(String id) {
    final d = _d(id);
    final isLast = _pending.length == 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _stepHeader(id),
        const SizedBox(height: 14),
        if (const {'name', 'address', 'opening_hours', 'price', 'category', 'accessibility'}.contains(id)) ...[
          Wrap(spacing: 8, children: [
            OhtliChoiceChip(label: 'Está mal', selected: d.kind == kIssueWrong, onTap: () => setState(() => d.kind = kIssueWrong)),
            OhtliChoiceChip(label: 'Falta', selected: d.kind == kIssueMissing, onTap: () => setState(() => d.kind = kIssueMissing)),
          ]),
          const SizedBox(height: 14),
        ],
        ..._body(id, d),
        const SizedBox(height: 18),
        Text('ASÍ SE VERÍA', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
        const SizedBox(height: 8),
        _preview(id, d),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(_ready(id) ? 'Al darle ${isLast ? 'Enviar' : 'Siguiente'} se envía este dato.' : 'Completa este dato para seguir.',
                  style: OhtliUi.body(size: 12.5)),
            ),
            OhtliPrimaryButton(
              label: isLast ? 'Enviar' : 'Siguiente',
              icon: isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded,
              loading: _sending,
              onPressed: _sending || !_ready(id) ? null : _sendCurrent,
            ),
          ],
        ),
      ],
    );
  }

  // ---------- Controles comunes ----------

  Widget _chips(List<(String, String)> options, Set<String> picked, {bool multi = false}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in options)
            OhtliChoiceChip(
              label: o.$2,
              selected: picked.contains(o.$1),
              onTap: () => setState(() {
                if (picked.contains(o.$1)) {
                  picked.remove(o.$1);
                } else {
                  if (!multi) picked.clear();
                  picked.add(o.$1);
                }
              }),
            ),
        ],
      );

  Widget _text(TextEditingController c, String label, {String? hint, int lines = 1, TextInputType? type}) => TextField(
        controller: c,
        minLines: lines,
        maxLines: lines + 3,
        maxLength: lines > 1 ? 500 : 200,
        keyboardType: type,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          filled: true,
          fillColor: OhtliColors.cardBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: OhtliColors.cardBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: OhtliColors.cardBorder)),
        ),
      );

  Widget _sub(String t) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 4), child: Text(t, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx)));

  Future<void> _pickOnMap(_Draft d, {required bool forAddress}) async {
    await address_picker.loadLibrary();
    if (!mounted) return;
    final initial = forAddress && d.address != null
        ? d.address
        : {'lat': d.lat ?? poi.location.lat, 'lng': d.lng ?? poi.location.lng, 'street': forAddress ? '' : poi.address};
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900, maxHeight: MediaQuery.of(ctx).size.height * 0.92),
          child: address_picker.AddressPickerWidget(
            initialAddress: initial,
            showNaming: false,
            title: forAddress ? 'Dirección de ${poi.name}' : 'Mueve el mapa hasta donde está ${poi.name}',
            saveLabel: forAddress ? 'Usar esta dirección' : 'Usar este punto',
            onCancel: () => Navigator.of(ctx).pop(),
            onSave: (a) => Navigator.of(ctx).pop(a),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (forAddress) d.address = result;
      final lat = result['lat'], lng = result['lng'];
      if (lat is num && lng is num) {
        d.lat = lat.toDouble();
        d.lng = lng.toDouble();
      }
    });
  }

  Future<void> _donateReplacement(_Draft d) async {
    await tools.loadLibrary();
    if (!mounted) return;
    final dataUrl = await tools.pickAndCropPhoto(context);
    if (dataUrl == null || !mounted) return;
    await donatePhotoNow(ScaffoldMessenger.of(context), poiId: poi.poiId, poiName: poi.name, dataUrl: dataUrl);
    if (mounted) setState(() => d.donated = true);
  }

  // ---------- Cuerpo de cada dato ----------

  List<Widget> _body(String id, _Draft d) {
    switch (id) {
      case 'closed':
        return [
          _chips(_statusKinds, d.options),
          if (d.options.contains('temporal')) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(d.reopens == null ? '¿Hasta cuándo? (opcional)' : 'Reabre el ${_dateText(d.reopens!)}'),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 730)), initialDate: d.reopens ?? now.add(const Duration(days: 7)));
                if (picked != null) setState(() => d.reopens = picked);
              },
            ),
          ],
          if (d.options.contains('mudanza')) ...[
            const SizedBox(height: 14),
            _sub('¿A dónde se mudó?'),
            PlaceSearchField(
              controller: d.movedController,
              hintText: 'Busca la nueva dirección o el lugar',
              onSelected: (name, lat, lng) => setState(() {
                d.movedName = name;
                d.lat = lat;
                d.lng = lng;
              }),
              onCleared: () => setState(() {
                d.movedName = null;
                d.lat = null;
                d.lng = null;
              }),
            ),
          ],
          const SizedBox(height: 14),
          _text(d.text, 'Detalle o razón (opcional)', hint: 'p. ej. Cerró en octubre; ahora está en la Roma', lines: 2),
        ];
      case 'name':
        return [_text(d.text, d.kind == kIssueMissing ? '¿Cómo se llama?' : '¿Cómo se llama en realidad?')];
      case 'address':
        return [
          OhtliSecondaryButton(
            label: d.address == null ? 'Poner la dirección correcta' : 'Cambiar la dirección',
            icon: Icons.edit_location_alt_outlined,
            onPressed: () => _pickOnMap(d, forAddress: true),
          ),
          if (d.address != null) ...[
            const SizedBox(height: 10),
            Text(_issue('address').value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
          ],
          const SizedBox(height: 14),
          _text(d.text, d.address == null ? 'O escríbela' : 'Detalle (opcional)', hint: 'Calle, número y colonia'),
        ];
      case 'location':
        final moved = d.lat != poi.location.lat || d.lng != poi.location.lng;
        return [
          Text('Mueve el mapa para poner el pin donde está la entrada del lugar.', style: OhtliUi.body(size: 13.5)),
          const SizedBox(height: 10),
          OhtliSecondaryButton(
            label: moved ? 'Ajustar otra vez en el mapa' : 'Abrir el mapa',
            icon: Icons.pin_drop_outlined,
            onPressed: () => _pickOnMap(d, forAddress: false),
          ),
          if (moved) ...[
            const SizedBox(height: 8),
            Text('Nuevo punto: ${d.lat!.toStringAsFixed(5)}, ${d.lng!.toStringAsFixed(5)}', style: OhtliUi.body(size: 12.5)),
          ],
          const SizedBox(height: 14),
          _text(d.text, 'Referencia (opcional)', hint: 'p. ej. Está en la esquina, frente al parque'),
        ];
      case 'opening_hours':
        return _hoursEditor(d);
      case 'price':
        return [
          _sub('¿Cuánto se gasta por persona?'),
          _chips(_priceLevels, d.options),
          const SizedBox(height: 12),
          _text(d.text, 'Monto exacto en pesos (opcional)', type: TextInputType.number),
        ];
      case 'photo':
        return [
          _sub('¿Qué tiene de malo? (puedes marcar varias)'),
          _chips(_photoIssues, d.options, multi: true),
          const SizedBox(height: 12),
          _text(d.text, 'Detalle (opcional)'),
          const SizedBox(height: 6),
          OhtliSurface(
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.volunteer_activism_rounded, color: OhtliColors.stormyTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      d.donated ? 'Donaste una foto para reemplazarla. ¡Gracias!' : '¿Tienes una mejor? Dónala y, si la aprobamos, reemplaza a esta.',
                      style: OhtliUi.body(size: 13)),
                ),
                const SizedBox(width: 8),
                OhtliSecondaryButton(label: d.donated ? 'Donar otra' : 'Donar foto', onPressed: () => _donateReplacement(d)),
              ],
            ),
          ),
        ];
      case 'category':
        return [_sub('¿Qué tipo de lugar es?'), _chips([for (final e in kSuggestionCategories.entries) (e.key, e.value)], d.options)];
      case 'accessibility':
        return [
          _sub('¿Qué hay o qué falta? (puedes marcar varias)'),
          _chips(_accessOptions, d.options, multi: true),
          const SizedBox(height: 12),
          _text(d.text, 'Detalle (opcional)'),
        ];
      case 'description':
        return [
          _sub('¿Qué está mal? (puedes marcar varias)'),
          _chips(_descIssues, d.options, multi: true),
          const SizedBox(height: 12),
          _text(d.text, '¿Cómo debería decir? (opcional)', lines: 3),
        ];
      default:
        return [_text(d.text, 'Cuéntanos qué falta o qué está mal y cómo debería ser', lines: 4)];
    }
  }

  // ---------- Horario ----------

  Future<TimeOfDay?> _time(TimeOfDay initial) => showTimePicker(context: context, initialTime: initial);

  Widget _timeButton(String label, TimeOfDay? t, ValueChanged<TimeOfDay> onPick, {TimeOfDay fallback = const TimeOfDay(hour: 14, minute: 0)}) =>
      OutlinedButton(
        onPressed: () async {
          final picked = await _time(t ?? fallback);
          if (picked != null) setState(() => onPick(picked));
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: OhtliColors.onyx,
          side: BorderSide(color: OhtliColors.cardBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(t == null ? label : '$label ${_hhmm(t)}'),
      );

  List<Widget> _hoursEditor(_Draft d) {
    final used = <int>{for (final r in d.rows) ...r.days};
    final closedDays = [for (var i = 0; i < 7; i++) if (!used.contains(i)) _dayNames[i]];
    return [
      SwitchListTile(
        value: d.allDay,
        onChanged: (v) => setState(() => d.allDay = v),
        contentPadding: EdgeInsets.zero,
        activeColor: OhtliColors.stormyTeal,
        title: Text('Abre las 24 horas, todos los días', style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
      ),
      if (!d.allDay) ...[
        for (var i = 0; i < d.rows.length; i++) _hoursRow(d, i),
        TextButton.icon(
          onPressed: () => setState(() => d.rows.add(_HoursRow({}, const TimeOfDay(hour: 10, minute: 0), const TimeOfDay(hour: 15, minute: 0)))),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar otro horario (p. ej. fines de semana)'),
        ),
        if (closedDays.isNotEmpty && d.rows.any((r) => r.days.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Row(children: [
              Icon(Icons.event_busy_rounded, size: 18, color: OhtliColors.subtleText),
              const SizedBox(width: 8),
              Expanded(child: Text('No abre: ${closedDays.join(', ')}', style: OhtliUi.body(size: 13))),
            ]),
          ),
      ],
      const SizedBox(height: 8),
      _sub('Fechas en las que no abre (opcional)'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final date in d.closedDates)
            InputChip(
              label: Text(_dateText(date)),
              onDeleted: () => setState(() => d.closedDates.remove(date)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Agregar fecha'),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 730)), initialDate: now);
              if (picked != null && !d.closedDates.contains(picked)) setState(() => d.closedDates..add(picked)..sort());
            },
          ),
        ],
      ),
      const SizedBox(height: 12),
      _text(d.text, 'Detalle (opcional)', hint: 'p. ej. La cocina cierra una hora antes'),
    ];
  }

  Widget _hoursRow(_Draft d, int i) {
    final r = d.rows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: OhtliColors.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: OhtliColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var day = 0; day < 7; day++)
                      ChoiceChip(
                        label: Text(_dayLabels[day]),
                        selected: r.days.contains(day),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selectedColor: OhtliColors.stormyTeal,
                        labelStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w700, color: r.days.contains(day) ? Colors.white : OhtliColors.subtleText),
                        onSelected: (on) => setState(() {
                          // Un día solo puede estar en un horario
                          if (on) {
                            for (final other in d.rows) {
                              other.days.remove(day);
                            }
                            r.days.add(day);
                          } else {
                            r.days.remove(day);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              if (d.rows.length > 1)
                IconButton(
                  tooltip: 'Quitar este horario',
                  onPressed: () => setState(() => d.rows.removeAt(i)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _timeButton('Abre', r.open, (t) => r.open = t),
              _timeButton('Cierra', r.close, (t) => r.close = t),
              if (r.pauseFrom == null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    r.pauseFrom = const TimeOfDay(hour: 14, minute: 0);
                    r.pauseTo = const TimeOfDay(hour: 16, minute: 0);
                  }),
                  icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
                  label: const Text('Agregar pausa'),
                )
              else ...[
                _timeButton('Pausa desde', r.pauseFrom, (t) => r.pauseFrom = t),
                _timeButton('hasta', r.pauseTo, (t) => r.pauseTo = t),
                IconButton(
                  tooltip: 'Quitar la pausa',
                  onPressed: () => setState(() {
                    r.pauseFrom = null;
                    r.pauseTo = null;
                  }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Vista previa ----------

  Widget _preview(String id, _Draft d) {
    String? next;
    String current = '';
    IconData icon = _caseOf(id).icon;
    switch (id) {
      case 'name':
        current = poi.name;
        next = d.text.text.trim().isEmpty ? null : d.text.text.trim();
      case 'address':
        current = poi.address;
        final v = _issue('address').value;
        next = v.isEmpty ? null : v;
      case 'location':
        current = 'Pin actual';
        next = (d.lat != poi.location.lat || d.lng != poi.location.lng) ? 'Pin movido a ${d.lat!.toStringAsFixed(5)}, ${d.lng!.toStringAsFixed(5)}' : null;
      case 'opening_hours':
        current = poi.openingHours.isEmpty ? '' : formatOpeningHours(poi.openingHours);
        final osm = _osmHours(d);
        final parts = [
          if (osm.isNotEmpty) formatOpeningHours(osm),
          if (d.closedDates.isNotEmpty) 'No abre: ${d.closedDates.map(_dateText).join(', ')}',
        ];
        next = parts.isEmpty ? null : parts.join(' · ');
      case 'price':
        current = poi.priceDisplay;
        final v = _issue('price').value;
        final n = double.tryParse(v);
        next = n == null ? null : (n == 0 ? 'Gratis' : '~\$${n.toStringAsFixed(0)} por persona');
      case 'category':
        current = poi.categoryDisplay;
        next = d.options.isEmpty ? null : kSuggestionCategories[d.options.first];
      case 'closed':
        current = poi.isClosedPermanently ? 'Cerró definitivamente' : (poi.isClosedTemporarily ? 'Cerrado temporalmente' : 'Abierto');
        if (d.options.contains('reabrio')) {
          next = 'Abierto de nuevo';
          break;
        }
        final k = d.options.isEmpty ? null : d.options.first;
        next = k == null
            ? null
            : (k == 'mudanza'
                ? 'Se mudó${d.movedName != null ? ' a ${d.movedName}' : ''}'
                : '${_label(_statusKinds, k)}${k == 'temporal' && d.reopens != null ? ' · reabre el ${_dateText(d.reopens!)}' : ''}');
      case 'accessibility':
        next = d.options.isEmpty ? null : d.options.map((o) => _label(_accessOptions, o)).join(' · ');
      case 'photo':
        next = d.donated ? 'Foto nueva en revisión' : (d.options.isEmpty ? null : 'Foto en revisión');
      case 'description':
        current = poi.description;
        next = d.text.text.trim().isEmpty ? (d.options.isEmpty ? null : 'Descripción en revisión') : d.text.text.trim();
      default:
        next = d.text.text.trim().isEmpty ? null : d.text.text.trim();
    }
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
              width: 72,
              height: 96,
              child: Stack(fit: StackFit.expand, children: [
                if (poi.photoUrl.isNotEmpty)
                  Image.network(poi.photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: OhtliColors.innerCardBg))
                else
                  Container(color: OhtliColors.innerCardBg),
                if (id == 'photo' && next != null)
                  Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(4),
                    child: Text(next, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id == 'name' && next != null ? next : poi.name,
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: id == 'name' && next != null ? OhtliColors.accentText : OhtliColors.onyx)),
                if (id != 'name' && id != 'photo') ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 15, color: OhtliColors.subtleText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          if (current.isNotEmpty && next != null)
                            TextSpan(
                              text: '${current.length > 90 ? '${current.substring(0, 90)}…' : current}  ',
                              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, decoration: TextDecoration.lineThrough),
                            ),
                          TextSpan(
                            text: next ?? (current.isEmpty ? 'Sin cambios todavía' : current),
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: next != null ? FontWeight.w700 : FontWeight.w400,
                                color: next != null ? OhtliColors.accentText : OhtliColors.onyx),
                          ),
                        ])),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

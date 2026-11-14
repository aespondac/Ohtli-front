import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

/// Ambientes que se pueden elegir (alimentan el eje "Atmósfera" del perfil del lugar).
const List<String> kPlaceVibes = [
  'tranquilo', 'acogedor', 'bohemio', 'animado', 'romántico', 'familiar', 'histórico', 'artístico',
  'al aire libre', 'arbolado', 'nocturno', 'contemplativo', 'gastronómico', 'tradicional', 'moderno', 'alternativo',
];

/// Para quién es ideal (eje "Dinámica social").
const Map<String, String> kPlaceIdealFor = {
  'solo': 'Ir solo',
  'pareja': 'En pareja',
  'amigos': 'Con amigos',
  'familia': 'En familia',
};

/// Rangos de precio por persona (nivel 0–4 que usa el motor).
const Map<int, String> kPlacePriceLevels = {
  0: 'Gratis',
  1: r'$ · hasta $100',
  2: r'$$ · $100–300',
  3: r'$$$ · $300–600',
  4: r'$$$$ · más de $600',
};

/// Preguntas de sí/no que una persona puede responder por haber ido.
const Map<String, String> kPlaceYesNo = {
  'wheelchair_accessible': 'Accesible en silla de ruedas',
  'musica_en_vivo': 'Hay música en vivo',
  'consumo_alcohol': 'Venden bebidas alcohólicas',
  'area_verde_cercana': 'Tiene áreas verdes o un parque cerca',
  'patrimonio_historico': 'Es un edificio o sitio histórico',
};

/// Lo que una persona sabe de un lugar por haberlo visitado. Solo se guarda lo que contestó:
/// "No sé" o vacío no se envía, para no inventar datos.
class PlaceDetailsDraft {
  String offers = ''; // separado por comas → subcategories
  final Set<String> vibes = {};
  final Set<String> idealFor = {};
  int? priceLevel;
  String openingHours = '';
  final Map<String, bool?> yesNo = {for (final k in kPlaceYesNo.keys) k: null};
  String tip = '';
  String description = '';

  bool get isEmpty =>
      offers.trim().isEmpty &&
      vibes.isEmpty &&
      idealFor.isEmpty &&
      priceLevel == null &&
      openingHours.trim().isEmpty &&
      yesNo.values.every((v) => v == null) &&
      tip.trim().isEmpty &&
      description.trim().isEmpty;

  /// Campos con los nombres que espera el motor (ver Yollotl-engine/api/admin_places.py).
  Map<String, dynamic> toMap() {
    final subcategories = offers.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return {
      if (subcategories.isNotEmpty) 'subcategories': subcategories,
      if (vibes.isNotEmpty) 'vibe_tags': vibes.toList(),
      if (idealFor.isNotEmpty) 'ideal_for': idealFor.toList(),
      if (priceLevel != null) 'price_level': priceLevel,
      if (openingHours.trim().isNotEmpty) 'opening_hours': openingHours.trim(),
      for (final e in yesNo.entries)
        if (e.value != null) e.key: e.value,
      if (tip.trim().isNotEmpty) 'tips': [tip.trim()],
      if (description.trim().isNotEmpty) 'description': description.trim(),
    };
  }
}

/// Partes del formulario, para mostrarlas juntas (visor) o repartidas en pasos (asistente).
enum PlaceDetailsSection { description, offers, vibes, idealFor, price, hours, yesNo, tip }

/// Campos del formulario. [sections] limita qué partes se muestran (todas por defecto).
class PlaceDetailsFields extends StatefulWidget {
  final PlaceDetailsDraft draft;
  final bool showDescription;
  final Set<PlaceDetailsSection>? sections;
  /// Sin títulos de sección (cuando el paso del asistente ya hace la pregunta).
  final bool compact;

  const PlaceDetailsFields({super.key, required this.draft, this.showDescription = true, this.sections, this.compact = false});

  @override
  State<PlaceDetailsFields> createState() => _PlaceDetailsFieldsState();
}

class _PlaceDetailsFieldsState extends State<PlaceDetailsFields> {
  PlaceDetailsDraft get d => widget.draft;
  bool _has(PlaceDetailsSection s) =>
      (widget.sections == null || widget.sections!.contains(s)) && (s != PlaceDetailsSection.description || widget.showDescription);

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _label(String text, {String? help}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            if (help != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(help, style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx.withValues(alpha: 0.55))),
              ),
          ],
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      selected: selected,
      showCheckmark: false,
      selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.22),
      side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: selected ? 0.6 : 0.2)),
      onSelected: (_) => setState(onTap),
    );
  }

  Widget _yesNo(String key, String label) {
    final value = d.yesNo[key];
    Widget opt(String text, bool? v) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(
            label: Text(text, style: GoogleFonts.inter(fontSize: 12)),
            selected: value == v,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.22),
            onSelected: (_) => setState(() => d.yesNo[key] = v),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 4,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220),
            child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx)),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [opt('Sí', true), opt('No', false), opt('No sé', null)]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_has(PlaceDetailsSection.description)) ...[
          const SizedBox(height: 4),
          TextFormField(
            initialValue: d.description,
            minLines: 2,
            maxLines: 4,
            onChanged: (v) => d.description = v,
            decoration: _decoration('¿Qué lo hace especial?', hint: 'Historia, qué se ve o qué se come, por qué ir…'),
          ),
          const SizedBox(height: 12),
        ],
        if (_has(PlaceDetailsSection.offers)) ...[
          TextFormField(
            initialValue: d.offers,
            onChanged: (v) => d.offers = v,
            decoration: _decoration('¿Qué ofrece?', hint: 'Ej. café de especialidad, postres, exposiciones (separa con comas)'),
          ),
        ],
        if (_has(PlaceDetailsSection.vibes)) ...[
          if (!compact) _label('¿Cómo es el ambiente?', help: 'Elige los que apliquen.'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kPlaceVibes.map((v) => _chip(v, d.vibes.contains(v), () => d.vibes.contains(v) ? d.vibes.remove(v) : d.vibes.add(v))).toList(),
          ),
        ],
        if (_has(PlaceDetailsSection.idealFor)) ...[
          _label('¿Para quién es ideal?'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kPlaceIdealFor.entries
                .map((e) => _chip(e.value, d.idealFor.contains(e.key),
                    () => d.idealFor.contains(e.key) ? d.idealFor.remove(e.key) : d.idealFor.add(e.key)))
                .toList(),
          ),
        ],
        if (_has(PlaceDetailsSection.price)) ...[
          if (!compact) _label('¿Cuánto se gasta por persona?'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...kPlacePriceLevels.entries.map((e) => _chip(e.value, d.priceLevel == e.key, () => d.priceLevel = d.priceLevel == e.key ? null : e.key)),
              _chip('No sé', d.priceLevel == null, () => d.priceLevel = null),
            ],
          ),
        ],
        if (_has(PlaceDetailsSection.hours)) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: d.openingHours,
            onChanged: (v) => d.openingHours = v,
            decoration: _decoration('Horario (si lo conoces)', hint: 'Ej. Lunes a domingo de 9:00 a 20:00'),
          ),
        ],
        if (_has(PlaceDetailsSection.yesNo)) ...[
          if (!compact) _label('Si lo sabes…', help: 'Deja "No sé" en lo que no tengas claro.') else const SizedBox(height: 16),
          ...kPlaceYesNo.entries.map((e) => _yesNo(e.key, e.value)),
        ],
        if (_has(PlaceDetailsSection.tip)) ...[
          const SizedBox(height: 10),
          TextFormField(
            initialValue: d.tip,
            maxLines: 2,
            onChanged: (v) => d.tip = v,
            decoration: _decoration('Un consejo para quien vaya (opcional)', hint: 'Ej. Llega temprano, pide la especialidad de la casa…'),
          ),
        ],
      ],
    );
  }
}

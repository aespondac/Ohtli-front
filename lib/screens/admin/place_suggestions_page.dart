import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;
import '../../config/admin.dart';
import '../../services/poi_suggestion_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/place_details_form.dart';

/// Revisión de lugares sugeridos desde el editor de viajes (solo superusuario).
///
/// 1. Se revisa lo que dijo quien lo sugirió y lo que aportaron otras personas.
/// 2. "Generar perfil": el motor redacta la receta de 4 ejes y calcula el vector.
/// 3. "Aprobar perfil": el lugar entra a la base de Ohtli y el recomendador lo usa.
class PlaceSuggestionsPage extends StatefulWidget {
  const PlaceSuggestionsPage({super.key});

  @override
  State<PlaceSuggestionsPage> createState() => _PlaceSuggestionsPageState();
}

class _PlaceSuggestionsPageState extends State<PlaceSuggestionsPage> {
  final Map<String, String> _busy = {}; // id → acción en curso
  bool _showReviewed = false;

  Future<void> _run(PoiSuggestion s, String label, Future<void> Function() action) async {
    setState(() => _busy[s.id] = label);
    try {
      await action();
    } catch (e) {
      _toast(friendlyError(e, fallback: e is StateError ? e.message : 'No se pudo completar. Intenta de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  Future<void> _editBasics(PoiSuggestion s) async {
    final name = TextEditingController(text: s.name);
    final description = TextEditingController(text: s.description);
    String category = kSuggestionCategories.containsKey(s.category) ? s.category : 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Corregir datos', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo de lugar', border: OutlineInputBorder()),
                  items: kSuggestionCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setD(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final n = name.text, d = description.text;
    name.dispose();
    description.dispose();
    if (ok != true) return;
    await _run(s, 'Guardando…', () => PoiSuggestionService.updateBasics(s.id, name: n, category: category, description: d));
  }

  Future<void> _generate(PoiSuggestion s) =>
      _run(s, 'Generando perfil… (puede tardar un minuto)', () async {
        await PoiSuggestionService.generateProfile(s.id);
        _toast('Perfil generado. Revísalo y apruébalo.');
      });

  Future<void> _approve(PoiSuggestion s) async {
    final recipe = TextEditingController(text: (s.profile?['semantic_description'] ?? '').toString());
    final original = recipe.text;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aprobar perfil de "${s.name}"', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Esta es la descripción con la que el recomendador entenderá el lugar. Si la corriges, el vector se '
                'vuelve a calcular con tu versión.',
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: recipe,
                minLines: 8,
                maxLines: 14,
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.4),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.verified_rounded, size: 18),
            label: const Text('Aprobar y activar en el recomendador'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    final edited = recipe.text.trim();
    recipe.dispose();
    if (ok != true) return;
    await _run(s, 'Aprobando…', () async {
      final res = await PoiSuggestionService.approveProfile(s.id, semanticDescription: edited != original.trim() ? edited : null);
      final rec = res['recommender'] is Map ? res['recommender'] as Map : const {};
      _toast(rec['snapshot'] == true
          ? '"${s.name}" ya está en la base de Ohtli y el recomendador lo puede usar.'
          : '"${s.name}" ya está en la base. El recomendador lo incluirá en su próxima actualización (diaria).');
    });
  }

  Future<void> _reject(PoiSuggestion s) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Rechazar "${s.name}"?', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seguirá en el viaje de quien lo sugirió, pero no entrará a la base de Ohtli.', style: GoogleFonts.inter(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Motivo (opcional)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.xoconostle, foregroundColor: Colors.white),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    final note = controller.text;
    controller.dispose();
    if (ok != true) return;
    await _run(s, 'Rechazando…', () async {
      await PoiSuggestionService.reject(s, note: note);
      _toast('Sugerencia rechazada.');
    });
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.inter()), backgroundColor: error ? OhtliColors.xoconostle : OhtliColors.stormyTeal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final bg = isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer;
    if (!isSuperUser()) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(child: Text('Esta sección es solo para el administrador de Ohtli.', style: GoogleFonts.inter(color: OhtliColors.onyx))),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OhtliColors.onyx,
        title: Text('Lugares sugeridos', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text('Ver revisados', style: GoogleFonts.inter(fontSize: 12.5)),
              selected: _showReviewed,
              onSelected: (v) => setState(() => _showReviewed = v),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<PoiSuggestion>>(
        stream: PoiSuggestionService.watchForReview(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(friendlyError(snap.error!, fallback: 'No se pudieron cargar las sugerencias.'),
                    textAlign: TextAlign.center, style: GoogleFonts.inter(color: OhtliColors.onyx)),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          final items = _showReviewed ? snap.data! : snap.data!.where((s) => s.status == kSuggestionPending).toList();
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.task_alt_rounded, size: 48, color: OhtliColors.stormyTeal),
                  const SizedBox(height: 12),
                  Text('No hay lugares por revisar', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                  const SizedBox(height: 4),
                  Text('Cuando alguien sugiera un lugar desde el editor aparecerá aquí.',
                      style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.6))),
                ],
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _SuggestionCard(
                  suggestion: items[i],
                  busyLabel: _busy[items[i].id],
                  isDark: isDark,
                  onEdit: () => _editBasics(items[i]),
                  onGenerate: () => _generate(items[i]),
                  onApprove: () => _approve(items[i]),
                  onReject: () => _reject(items[i]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final PoiSuggestion suggestion;
  final String? busyLabel;
  final bool isDark;
  final VoidCallback onEdit, onGenerate, onApprove, onReject;

  const _SuggestionCard({
    required this.suggestion,
    required this.busyLabel,
    required this.isDark,
    required this.onEdit,
    required this.onGenerate,
    required this.onApprove,
    required this.onReject,
  });

  static List<String> describeDetails(Map<String, dynamic> d) {
    final out = <String>[];
    List<String> list(String k) => d[k] is List ? (d[k] as List).map((e) => e.toString()).toList() : const [];
    if (list('subcategories').isNotEmpty) out.add('Ofrece: ${list('subcategories').join(', ')}');
    if (list('vibe_tags').isNotEmpty) out.add('Ambiente: ${list('vibe_tags').join(', ')}');
    if (list('ideal_for').isNotEmpty) out.add('Ideal para: ${list('ideal_for').map((k) => kPlaceIdealFor[k] ?? k).join(', ')}');
    if (d['price_level'] is num) out.add('Precio: ${kPlacePriceLevels[(d['price_level'] as num).toInt()] ?? d['price_level']}');
    if ((d['opening_hours'] ?? '').toString().isNotEmpty) out.add('Horario: ${d['opening_hours']}');
    for (final e in kPlaceYesNo.entries) {
      if (d[e.key] is bool) out.add('${e.value}: ${d[e.key] == true ? 'sí' : 'no'}');
    }
    for (final t in list('tips')) {
      out.add('Consejo: $t');
    }
    if ((d['description'] ?? '').toString().isNotEmpty && d.containsKey('by')) out.add('Comentario: ${d['description']}');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final pending = s.status == kSuggestionPending;
    final (Color tone, String statusLabel) = switch (s.status) {
      kSuggestionApproved => (OhtliColors.stormyTeal, 'Aprobado'),
      kSuggestionRejected => (OhtliColors.xoconostle, 'Rechazado'),
      _ => (OhtliColors.cempasuchil, s.profile != null ? 'Perfil listo para aprobar' : 'Pendiente'),
    };
    final muted = OhtliColors.onyx.withValues(alpha: 0.65);
    final details = describeDetails(s.details);
    final busy = busyLabel != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: pending ? 0.4 : 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.photoUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(s.photoUrl, width: 84, height: 84, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 84, height: 84)),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(s.name, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                          child: Text(statusLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: tone)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${kSuggestionCategories[s.category] ?? s.category} · sugerido por ${s.createdByName.isEmpty ? 'un viajero' : s.createdByName}'
                      '${s.createdAt == null ? '' : ' · ${s.createdAt!.day}/${s.createdAt!.month}/${s.createdAt!.year}'}',
                      style: GoogleFonts.inter(fontSize: 12.5, color: muted),
                    ),
                    if (s.address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, color: muted)),
                    ],
                    if (s.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s.description, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OhtliColors.onyx.withValues(alpha: 0.85))),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: details
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: Text(t, style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx)),
                      ))
                  .toList(),
            ),
          ],
          if (pending) _Contributions(suggestionId: s.id),
          if (s.profile != null && pending) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OhtliColors.cempasuchil.withValues(alpha: isDark ? 0.14 : 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Perfil generado (vector de ${s.profile!['vector_dim'] ?? 768} dimensiones)',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                  const SizedBox(height: 6),
                  Text((s.profile!['semantic_description'] ?? '').toString(),
                      maxLines: 8, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: muted)),
                ],
              ),
            ),
          ],
          if (s.status == kSuggestionRejected && (s.reviewNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Motivo: ${s.reviewNote}', style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: OhtliColors.xoconostle)),
          ],
          const SizedBox(height: 12),
          if (busy)
            Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(busyLabel!, style: GoogleFonts.inter(fontSize: 12.5, color: muted)),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (s.hasLocation)
                  TextButton.icon(
                    onPressed: () => html.window.open('https://www.google.com/maps/search/?api=1&query=${s.lat},${s.lng}', '_blank'),
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Ver en el mapa'),
                  )
                else
                  Text('Sin ubicación', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.xoconostle)),
                if (pending) ...[
                  TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Corregir datos')),
                  OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OhtliColors.xoconostle,
                      side: BorderSide(color: OhtliColors.xoconostle.withValues(alpha: 0.5)),
                    ),
                    child: const Text('Rechazar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: Text(s.profile == null ? 'Generar perfil' : 'Regenerar perfil'),
                  ),
                  if (s.profile != null)
                    ElevatedButton.icon(
                      onPressed: s.hasLocation ? onApprove : null,
                      icon: const Icon(Icons.verified_rounded, size: 18),
                      label: const Text('Aprobar perfil'),
                      style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white, elevation: 0),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Aportes de otras personas (se cargan al ver la tarjeta).
class _Contributions extends StatelessWidget {
  final String suggestionId;
  const _Contributions({required this.suggestionId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PoiContribution>>(
      future: PoiSuggestionService.contributions(suggestionId),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              list.length == 1 ? '1 persona aportó información' : '${list.length} personas aportaron información',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
            ),
            children: list
                .map((c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.byName, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      subtitle: Text(_SuggestionCard.describeDetails(c.data).join(' · '), style: GoogleFonts.inter(fontSize: 12)),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

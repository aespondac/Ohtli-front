import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;
import '../../config/admin.dart';
import '../../services/poi_suggestion_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';

/// Revisión de lugares sugeridos desde el editor de viajes (solo superusuario).
///
/// Aprobar copia el lugar a `pois/{id}` (mismo id que la sugerencia): entra al
/// catálogo de Ohtli y las paradas que ya lo usan quedan vinculadas.
class PlaceSuggestionsPage extends StatefulWidget {
  const PlaceSuggestionsPage({super.key});

  @override
  State<PlaceSuggestionsPage> createState() => _PlaceSuggestionsPageState();
}

class _PlaceSuggestionsPageState extends State<PlaceSuggestionsPage> {
  final Set<String> _busy = {};
  bool _showReviewed = false;

  Future<void> _approve(PoiSuggestion s) async {
    final edited = await showDialog<PoiSuggestion>(context: context, builder: (_) => _ApproveDialog(suggestion: s));
    if (edited == null) return;
    setState(() => _busy.add(s.id));
    try {
      await PoiSuggestionService.approve(s, edited: edited);
      _toast('"${edited.name}" ya es parte de la base de Ohtli.');
    } catch (e) {
      _toast(friendlyError(e, fallback: 'No se pudo aprobar. Revisa que tu correo esté verificado.'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
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
            Text('Seguirá en el viaje de quien lo sugirió, pero no entrará a la base de Ohtli.',
                style: GoogleFonts.inter(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)', border: OutlineInputBorder()),
            ),
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
    setState(() => _busy.add(s.id));
    try {
      await PoiSuggestionService.reject(s, note: note);
      _toast('Sugerencia rechazada.');
    } catch (e) {
      _toast(friendlyError(e, fallback: 'No se pudo rechazar. Intenta de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: error ? OhtliColors.xoconostle : OhtliColors.stormyTeal,
      ),
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
        body: Center(
          child: Text('Esta sección es solo para el administrador de Ohtli.', style: GoogleFonts.inter(color: OhtliColors.onyx)),
        ),
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
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          }
          final all = snap.data!;
          final items = _showReviewed ? all : all.where((s) => s.status == kSuggestionPending).toList();
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
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _buildCard(items[i], isDark),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(PoiSuggestion s, bool isDark) {
    final busy = _busy.contains(s.id);
    final pending = s.status == kSuggestionPending;
    final (Color tone, String statusLabel) = switch (s.status) {
      kSuggestionApproved => (OhtliColors.stormyTeal, 'Aprobado'),
      kSuggestionRejected => (OhtliColors.xoconostle, 'Rechazado'),
      _ => (OhtliColors.cempasuchil, 'Pendiente'),
    };
    final when = s.createdAt;
    final dateText = when == null ? '' : '${when.day}/${when.month}/${when.year}';
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
                        Expanded(
                          child: Text(s.name, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                        ),
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
                      '${dateText.isEmpty ? '' : ' · $dateText'}',
                      style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.6)),
                    ),
                    if (s.address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s.address, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.8))),
                    ],
                    if (s.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s.description, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OhtliColors.onyx.withValues(alpha: 0.8))),
                    ],
                    if (s.status == kSuggestionRejected && (s.reviewNote ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Motivo: ${s.reviewNote}', style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: OhtliColors.xoconostle)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                OutlinedButton(
                  onPressed: busy ? null : () => _reject(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OhtliColors.xoconostle,
                    side: BorderSide(color: OhtliColors.xoconostle.withValues(alpha: 0.5)),
                  ),
                  child: const Text('Rechazar'),
                ),
                ElevatedButton.icon(
                  onPressed: busy ? null : () => _approve(s),
                  icon: busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Revisar y aprobar'),
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

/// Permite corregir nombre, categoría y descripción antes de aprobar.
class _ApproveDialog extends StatefulWidget {
  final PoiSuggestion suggestion;
  const _ApproveDialog({required this.suggestion});

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.suggestion.name);
  late final TextEditingController _description = TextEditingController(text: widget.suggestion.description);
  late String _category = kSuggestionCategories.containsKey(widget.suggestion.category) ? widget.suggestion.category : 'other';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    return AlertDialog(
      title: Text('Aprobar lugar', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de lugar', border: OutlineInputBorder()),
              items: kSuggestionCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
            ),
            if (!s.hasLocation) ...[
              const SizedBox(height: 10),
              Text('Este lugar no tiene ubicación: no saldrá en los mapas ni en las rutas.',
                  style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.xoconostle)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _name.text.trim().length < 3
              ? null
              : () => Navigator.pop(
                    context,
                    PoiSuggestion(
                      id: s.id,
                      name: _name.text.trim(),
                      category: _category,
                      lat: s.lat,
                      lng: s.lng,
                      address: s.address,
                      description: _description.text.trim(),
                      photoUrl: s.photoUrl,
                      priceMxnAvg: s.priceMxnAvg,
                      status: s.status,
                      createdBy: s.createdBy,
                      createdByName: s.createdByName,
                      tripId: s.tripId,
                      createdAt: s.createdAt,
                    ),
                  ),
          style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          child: const Text('Aprobar y añadir a la base'),
        ),
      ],
    );
  }
}

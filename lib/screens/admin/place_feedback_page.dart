import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/admin.dart';
import '../../services/contribution_titles.dart';
import '../../services/place_feedback_service.dart';
import '../../services/poi_suggestion_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/ohtli_ui.dart';

/// Fotos donadas y reportes de lugares (solo superusuario). Aprobar una foto la vuelve la foto
/// del lugar; aprobar un reporte aplica los datos corregidos.
class PlaceFeedbackPage extends StatefulWidget {
  const PlaceFeedbackPage({super.key});

  @override
  State<PlaceFeedbackPage> createState() => _PlaceFeedbackPageState();
}

class _PlaceFeedbackPageState extends State<PlaceFeedbackPage> {
  final Map<String, String> _busy = {};
  bool _showReviewed = false;

  @override
  void initState() {
    super.initState();
    // Catálogo de títulos al día y títulos pendientes para quien ya los había ganado (testers de
    // Labs, lugares sugeridos y aportes anteriores). Lo hace el motor, que puede escribir los de todos.
    if (isSuperUser()) _syncTitles();
  }

  Future<void> _syncTitles() async {
    await ContributionTitles.ensureCatalog();
    try {
      final res = await PoiSuggestionService.postAdmin('/v1/admin/titles/sync', const {});
      final granted = res['granted'] is Map ? (res['granted'] as Map).values.fold<int>(0, (a, b) => a + ((b as num?)?.toInt() ?? 0)) : 0;
      if (granted > 0) _toast('Se entregaron $granted títulos pendientes.');
    } catch (_) {}
  }

  Future<void> _run(PlaceFeedback f, String label, Future<void> Function() action, String done) async {
    setState(() => _busy[f.id] = label);
    try {
      await action();
      _toast(done);
    } catch (e) {
      _toast(friendlyError(e, fallback: 'No se pudo completar. Intenta de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(f.id));
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? OhtliColors.warning : OhtliColors.stormyTeal),
    );
  }

  Future<void> _approvePhoto(PlaceFeedback f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Usar esta foto para ${f.poiName}?', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text('Reemplaza la foto del lugar para todos, con crédito a ${f.byName}.', style: GoogleFonts.inter(fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            child: const Text('Aprobar y reemplazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(f, 'Aprobando…', () => PlaceFeedbackService.approvePhoto(f), 'Listo: ${f.poiName} ya tiene la foto nueva.');
  }

  Future<void> _approveReport(PlaceFeedback f) async {
    // Lo que se puede aplicar directo en /pois, prellenado con lo que mandó la persona
    final applicable = [
      for (final i in f.issues)
        if (placeFieldOf(i.field).applies != null) i,
    ];
    final controllers = {for (final i in applicable) i.field: TextEditingController(text: i.value)};
    final closedReported = f.issues.any((i) => i.field == 'closed');
    bool markClosed = closedReported;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Aprobar reporte de ${f.poiName}', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    applicable.isEmpty && !closedReported
                        ? 'Nada de esto se aplica solo: corrígelo a mano si hace falta y apruébalo para avisarle a ${f.byName}.'
                        : 'Revisa los datos que se van a guardar en el lugar. Deja vacío lo que no quieras cambiar.',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  for (final i in applicable) ...[
                    TextField(
                      controller: controllers[i.field],
                      keyboardType: i.field == 'price' ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(labelText: placeFieldOf(i.field).label, border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (closedReported)
                    CheckboxListTile(
                      value: markClosed,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setD(() => markClosed = v ?? false),
                      title: const Text('Marcar el lugar como cerrado definitivamente'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
              child: const Text('Aprobar y aplicar'),
            ),
          ],
        ),
      ),
    );
    final values = <String, dynamic>{};
    for (final e in controllers.entries) {
      final text = e.value.text.trim();
      final target = placeFieldOf(e.key).applies!;
      if (text.isEmpty) continue;
      if (e.key == 'price') {
        final n = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (n != null) values[target] = n;
      } else {
        values[target] = text;
      }
    }
    for (final c in controllers.values) {
      c.dispose();
    }
    if (ok != true) return;
    await _run(f, 'Aplicando…', () => PlaceFeedbackService.approveReport(f, values, closed: markClosed),
        'Reporte aprobado${values.isEmpty && !markClosed ? '' : ' y aplicado'}.');
  }

  Future<void> _reject(PlaceFeedback f) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f.isPhoto ? '¿Rechazar la foto?' : '¿Rechazar el reporte?', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Motivo (se le muestra a quien la mandó)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.accentFill, foregroundColor: Colors.white),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    final note = controller.text;
    controller.dispose();
    if (ok != true) return;
    await _run(f, 'Rechazando…', () => PlaceFeedbackService.reject(f, note: note), 'Rechazado.');
  }

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
        title: Text('Fotos y reportes de lugares', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
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
      body: StreamBuilder<List<PlaceFeedback>>(
        stream: PlaceFeedbackService.watchForReview(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(friendlyError(snap.error!, fallback: 'No se pudo cargar la bandeja.'), style: GoogleFonts.inter()));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          final items = _showReviewed ? snap.data! : snap.data!.where((f) => f.pending).toList();
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.task_alt_rounded, size: 48, color: OhtliColors.stormyTeal),
                  const SizedBox(height: 12),
                  Text('Nada por revisar', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                  const SizedBox(height: 4),
                  Text('Aquí llegan las fotos donadas y los reportes de lugares.', style: OhtliUi.body(size: 13)),
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
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final f = items[i];
                  return _FeedbackCard(
                    feedback: f,
                    busyLabel: _busy[f.id],
                    onApprove: () => f.isPhoto ? _approvePhoto(f) : _approveReport(f),
                    onReject: () => _reject(f),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback, required this.busyLabel, required this.onApprove, required this.onReject});
  final PlaceFeedback feedback;
  final String? busyLabel;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  Widget _photo(String? url, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: OhtliUi.eyebrow(OhtliColors.subtleText)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: url == null || url.isEmpty
                  ? Container(
                      color: OhtliColors.innerCardBg,
                      alignment: Alignment.center,
                      child: Text('Sin foto', style: OhtliUi.body(size: 12.5)),
                    )
                  : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: OhtliColors.innerCardBg)),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final f = feedback;
    final when = f.createdAt == null ? '' : ' · ${f.createdAt!.day} ${_months[f.createdAt!.month - 1]}';
    final (String statusLabel, Color tone) = switch (f.status) {
      kFeedbackApproved => ('Aprobado', OhtliColors.stormyTeal),
      kFeedbackRejected => ('Rechazado', OhtliColors.subtleText),
      _ => ('Pendiente', OhtliColors.accent),
    };
    return OhtliSurface(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(f.isPhoto ? Icons.volunteer_activism_rounded : Icons.flag_rounded, color: OhtliColors.stormyTeal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${f.isPhoto ? 'Foto donada' : 'Reporte'} · ${f.poiName}',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Text(statusLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: tone)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('De ${f.byName}$when', style: OhtliUi.body(size: 12.5)),
          const SizedBox(height: 12),
          if (f.isPhoto)
            // La foto actual del lugar junto a la donada, para comparar
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('pois').doc(f.poiId).get(),
              builder: (context, snap) {
                final d = snap.data?.data() ?? const {};
                final current = (d['photo_url'] ?? d['image_url'] ?? d['photo'] ?? '').toString();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _photo(current, 'ACTUAL')),
                    const SizedBox(width: 12),
                    Expanded(child: _photo(f.photoUrl, 'DONADA')),
                  ],
                );
              },
            )
          else ...[
            for (final i in f.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${placeFieldOf(i.field).label}: ',
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                  ),
                  TextSpan(
                    text: i.field == 'closed' ? 'cerró definitivamente' : (i.kind == kIssueMissing ? 'falta' : 'está mal'),
                    style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.warningText, fontWeight: FontWeight.w600),
                  ),
                  if (i.value.isNotEmpty)
                    TextSpan(text: ' → ${i.value}', style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx)),
                ])),
              ),
            if (f.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('«${f.note}»', style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
            ],
          ],
          if (!f.pending && (f.reviewNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Motivo: ${f.reviewNote}', style: OhtliUi.body(size: 12.5)),
          ],
          if (f.pending) ...[
            const SizedBox(height: 14),
            busyLabel != null
                ? Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal)),
                    const SizedBox(width: 10),
                    Text(busyLabel!, style: OhtliUi.body(size: 13)),
                  ])
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OhtliPrimaryButton(
                        label: f.isPhoto ? 'Aprobar y usar' : 'Aprobar',
                        icon: Icons.check_rounded,
                        onPressed: onApprove,
                      ),
                      OhtliSecondaryButton(label: 'Rechazar', onPressed: onReject),
                    ],
                  ),
          ],
        ],
      ),
    );
  }
}

import '../../services/achievements_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;

import '../../config/admin.dart';
import '../../services/feedback_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/ohtli_ui.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _when(DateTime? d) {
  if (d == null) return '';
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} · $hh:$mm';
}

(String, IconData) _kindOf(String category) => switch (category) {
      'idea' => ('Idea', Icons.lightbulb_outline_rounded),
      'bug' => ('Algo falla', Icons.bug_report_outlined),
      _ => ('Otro', Icons.chat_bubble_outline_rounded),
    };

(String, Color) _statusOf(String status) => switch (status) {
      FeedbackService.statusReviewed => ('Revisado', OhtliColors.stormyTeal),
      FeedbackService.statusResolved => ('Resuelto', OhtliColors.subtleText),
      FeedbackService.statusFixed => ('Arreglado', OhtliColors.stormyTeal),
      _ => ('Nuevo', OhtliColors.accent),
    };

/// Comentarios de "Enviar comentarios" (solo superusuario): lista con filtros y búsqueda, y a la
/// derecha (o en su propia pantalla en el teléfono) el comentario con sus capturas, la cuenta, el
/// dispositivo, el estado de la app y los errores recientes.
class AppFeedbackPage extends StatefulWidget {
  /// Dentro de la bandeja de administración (sin barra propia).
  final bool embedded;

  const AppFeedbackPage({super.key, this.embedded = false});

  @override
  State<AppFeedbackPage> createState() => _AppFeedbackPageState();
}

class _AppFeedbackPageState extends State<AppFeedbackPage> {
  String _status = FeedbackService.statusNew; // '' = todos
  String _category = '';
  String _query = '';
  String? _selectedId;
  final Stream<List<AppFeedback>> _stream = FeedbackService.watchComments();

  bool _matches(AppFeedback f) {
    if (_status.isNotEmpty && f.status != _status) return false;
    if (_category.isNotEmpty && f.category != _category) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [f.message, f.screen, f.userName, f.user['correo'] ?? '', f.uid, f.device['navegador'] ?? '']
        .any((t) => t.toLowerCase().contains(q));
  }

  Widget _filters(List<AppFeedback> all) {
    int count(String s) => all.where((f) => f.status == s).length;
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
            selected: selected,
            onSelected: (_) => onTap(),
            selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.18),
            showCheckmark: false,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar por texto, persona, correo o pantalla',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: OhtliColors.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('Nuevos · ${count(FeedbackService.statusNew)}', _status == FeedbackService.statusNew,
                () => setState(() => _status = FeedbackService.statusNew)),
            chip('Revisados · ${count(FeedbackService.statusReviewed)}', _status == FeedbackService.statusReviewed,
                () => setState(() => _status = FeedbackService.statusReviewed)),
            chip('Resueltos · ${count(FeedbackService.statusResolved)}', _status == FeedbackService.statusResolved,
                () => setState(() => _status = FeedbackService.statusResolved)),
            chip('Todos · ${all.length}', _status.isEmpty, () => setState(() => _status = '')),
          ]),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('Todo tipo', _category.isEmpty, () => setState(() => _category = '')),
            for (final c in FeedbackService.commentCategories)
              chip(_kindOf(c).$1, _category == c, () => setState(() => _category = c)),
          ]),
        ),
      ],
    );
  }

  Widget _tile(AppFeedback f, bool selected, VoidCallback onTap) {
    final (kind, icon) = _kindOf(f.category);
    final (statusLabel, tone) = _statusOf(f.status);
    return Material(
      color: selected ? OhtliColors.stormyTeal.withValues(alpha: 0.12) : OhtliColors.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? OhtliColors.stormyTeal.withValues(alpha: 0.5) : OhtliColors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: OhtliColors.stormyTeal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 13.5, fontWeight: f.isNew ? FontWeight.w700 : FontWeight.w500, color: OhtliColors.onyx)),
                    const SizedBox(height: 4),
                    Text('$kind · ${f.userName} · ${_when(f.createdAt)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: 11.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(statusLabel, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: tone)),
                  ),
                  if (f.screenshots.isNotEmpty || f.errors.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (f.screenshots.isNotEmpty) ...[
                        Icon(Icons.image_outlined, size: 14, color: OhtliColors.subtleText),
                        Text(' ${f.screenshots.length}', style: OhtliUi.body(size: 11)),
                      ],
                      if (f.errors.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.error_outline_rounded, size: 14, color: OhtliColors.warningText),
                        Text(' ${f.errors.length}', style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.warningText)),
                      ],
                    ]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    final wide = MediaQuery.of(context).size.width >= 1000;
    final body = StreamBuilder<List<AppFeedback>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(friendlyError(snap.error!, fallback: 'No se pudo cargar la bandeja.'), style: GoogleFonts.inter()));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          final all = snap.data!;
          final items = all.where(_matches).toList();
          AppFeedback? selected;
          for (final f in all) {
            if (f.id == _selectedId) selected = f;
          }
          if (wide && selected == null && items.isNotEmpty) selected = items.first;

          final list = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 10), child: _filters(all)),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.task_alt_rounded, size: 44, color: OhtliColors.stormyTeal),
                            const SizedBox(height: 10),
                            Text('Nada por aquí', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                            const SizedBox(height: 4),
                            Text('Aquí llegan los comentarios de "Enviar comentarios".', style: OhtliUi.body(size: 12.5)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final f = items[i];
                          return _tile(f, wide && f.id == selected?.id, () {
                            if (wide) {
                              setState(() => _selectedId = f.id);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => Scaffold(
                                    backgroundColor: OhtliColors.cloudDancer,
                                    appBar: AppBar(
                                      backgroundColor: Colors.transparent,
                                      elevation: 0,
                                      foregroundColor: OhtliColors.onyx,
                                      title: Text('Comentario', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                                    ),
                                    body: AppFeedbackDetail(feedback: f),
                                  ),
                                ),
                              );
                            }
                          });
                        },
                      ),
              ),
            ],
          );
          if (!wide) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 420, child: list),
              Container(width: 1, color: OhtliColors.cardBorder),
              Expanded(
                child: selected == null
                    ? Center(child: Text('Elige un comentario para verlo.', style: OhtliUi.body()))
                    : AppFeedbackDetail(key: ValueKey(selected.id), feedback: selected),
              ),
            ],
          );
        },
);
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OhtliColors.onyx,
        title: Text('Comentarios de la app', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
      ),
      body: body,
    );
  }
}

/// Un comentario completo: texto, capturas, cuenta, dónde estaba, dispositivo, estado de la app,
/// errores y acciones (revisado, resuelto, nota, responder).
class AppFeedbackDetail extends StatefulWidget {
  final AppFeedback feedback;
  const AppFeedbackDetail({super.key, required this.feedback});

  @override
  State<AppFeedbackDetail> createState() => _AppFeedbackDetailState();
}

class _AppFeedbackDetailState extends State<AppFeedbackDetail> {
  bool _busy = false;
  late String _status = widget.feedback.status;
  late String? _note = widget.feedback.reviewNote;

  static const _deviceLabels = {
    'navegador': 'Navegador',
    'pantalla': 'Pantalla',
    'ventana': 'Ventana',
    'densidad': 'Densidad',
    'tactil': 'Táctil',
    'idioma': 'Idioma',
    'zonaHoraria': 'Zona horaria',
    'nucleos': 'Núcleos',
    'memoria': 'Memoria',
    'conexion': 'Conexión',
    'red': 'Red',
    'instalada': 'Instalada',
    'userAgent': 'User agent',
  };
  static const _systemLabels = {
    'version': 'Versión',
    'modo': 'Compilación',
    'renderer': 'Motor',
    'ruta': 'Ruta',
    'tema': 'Tema',
    'letra': 'Letra',
    'abiertaHace': 'Abierta hace',
    'errores': 'Errores',
  };
  static const _userLabels = {
    'nombre': 'Nombre',
    'correo': 'Correo',
    'correoVerificado': 'Verificado',
    'acceso': 'Acceso',
    'cuentaDesde': 'Cuenta desde',
    'uid': 'uid',
  };

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? OhtliColors.warning : OhtliColors.stormyTeal),
    );
  }

  Future<void> _setStatus(String status, {String? note}) async {
    setState(() => _busy = true);
    try {
      await FeedbackService.setCommentStatus(widget.feedback.id, status, note: note);
      if (!mounted) return;
      setState(() {
        _status = status;
        if (note != null) _note = note;
      });
      // Arreglado: el motor revisa sus logros para que le llegue Amini sin esperar.
      if (status == FeedbackService.statusFixed) AchievementsService.instance.evaluateFor(widget.feedback.uid);
      _toast(switch (status) {
        FeedbackService.statusReviewed => 'Marcado como revisado.',
        FeedbackService.statusResolved => 'Marcado como resuelto.',
        FeedbackService.statusFixed => 'Marcado como arreglado. Quien lo envió gana el título Amini.',
        _ => 'Guardado.',
      });
    } catch (e) {
      _toast(friendlyError(e, fallback: 'No se pudo guardar. Intenta de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nota interna', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Qué se hizo o qué falta', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (ok == true) await _setStatus(_status, note: text);
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('Copiado.');
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: OhtliUi.eyebrow(OhtliColors.subtleText)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _table(Map<String, String> data, Map<String, String> labels, {Set<String> copyable = const {}}) {
    final keys = [
      ...labels.keys.where(data.containsKey),
      ...data.keys.where((k) => !labels.containsKey(k)),
    ];
    if (keys.isEmpty) return Text('Sin datos.', style: OhtliUi.body(size: 12.5));
    return Container(
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(labels[k] ?? k,
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
                  ),
                  Expanded(
                    child: SelectableText(data[k]!, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx)),
                  ),
                  if (copyable.contains(k))
                    InkWell(
                      onTap: () => _copy(data[k]!),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.copy_rounded, size: 15, color: OhtliColors.subtleText),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openImage(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url, fit: BoxFit.contain))),
            Positioned(
              top: 8,
              right: 8,
              child: Row(children: [
                IconButton.filled(
                  tooltip: 'Abrir en otra pestaña',
                  onPressed: () => web.window.open(url, '_blank'),
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _screenshots(List<String> paths) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final p in paths)
            FutureBuilder<String>(
              future: FeedbackService.attachmentUrl(p),
              builder: (context, snap) {
                final url = snap.data;
                return InkWell(
                  onTap: url == null ? null : () => _openImage(url),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 200,
                    height: 140,
                    decoration: BoxDecoration(
                      color: OhtliColors.innerCardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OhtliColors.cardBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: snap.hasError
                        ? Text('No se pudo cargar', style: OhtliUi.body(size: 12))
                        : url == null
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Image.network(url, fit: BoxFit.cover, width: 200, height: 140),
                  ),
                );
              },
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final f = widget.feedback;
    final (kind, icon) = _kindOf(f.category);
    final (statusLabel, tone) = _statusOf(_status);
    final email = f.user['correo'];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: OhtliColors.stormyTeal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('$kind · ${f.userName}',
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(statusLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: tone)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${_when(f.createdAt)} · ${f.screen.isEmpty ? 'sin pantalla' : f.screen}${f.appVersion.isEmpty ? '' : ' · v${f.appVersion}'}',
                  style: OhtliUi.body(size: 12.5)),
              const SizedBox(height: 16),
              OhtliSurface(
                radius: 18,
                padding: const EdgeInsets.all(16),
                child: SelectableText(f.message,
                    style: GoogleFonts.inter(fontSize: 15, height: 1.5, color: OhtliColors.onyx)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_status != FeedbackService.statusReviewed)
                    OhtliPrimaryButton(
                      compact: true,
                      label: 'Marcar revisado',
                      icon: Icons.visibility_outlined,
                      loading: _busy,
                      onPressed: () => _setStatus(FeedbackService.statusReviewed),
                    ),
                  if (_status != FeedbackService.statusResolved)
                    OhtliSecondaryButton(
                      compact: true,
                      label: 'Resuelto',
                      icon: Icons.task_alt_rounded,
                      onPressed: _busy ? null : () => _setStatus(FeedbackService.statusResolved),
                    ),
                  if (_status != FeedbackService.statusFixed)
                    OhtliSecondaryButton(
                      compact: true,
                      label: 'Ya se arregló',
                      icon: Icons.rocket_launch_outlined,
                      onPressed: _busy ? null : () => _setStatus(FeedbackService.statusFixed),
                    ),
                  if (_status != FeedbackService.statusNew)
                    OhtliSecondaryButton(
                      compact: true,
                      label: 'Volver a nuevo',
                      icon: Icons.undo_rounded,
                      onPressed: _busy ? null : () => _setStatus(FeedbackService.statusNew),
                    ),
                  OhtliSecondaryButton(
                    compact: true,
                    label: (_note ?? '').isEmpty ? 'Nota' : 'Editar nota',
                    icon: Icons.sticky_note_2_outlined,
                    onPressed: _busy ? null : _editNote,
                  ),
                  if (email != null && email.isNotEmpty)
                    OhtliSecondaryButton(
                      compact: true,
                      label: 'Responder',
                      icon: Icons.reply_rounded,
                      onPressed: () => web.window.open(
                          'mailto:$email?subject=${Uri.encodeComponent('Tu comentario en Ohtli')}', '_blank'),
                    ),
                ],
              ),
              if ((_note ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Nota: $_note', style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
              ],
              if (f.screenshots.isNotEmpty) _section('CAPTURAS Y FOTOS · ${f.screenshots.length}', _screenshots(f.screenshots)),
              _section('CUENTA', _table(f.user, _userLabels, copyable: {'uid', 'correo'})),
              if (f.context.isNotEmpty) _section('DÓNDE ESTABA', _table(f.context, const {})),
              _section('DISPOSITIVO', _table(f.device, _deviceLabels)),
              if (f.system.isNotEmpty) _section('ESTADO DE OHTLI', _table(f.system, _systemLabels)),
              if (f.errors.isNotEmpty)
                _section(
                  'ERRORES RECIENTES · ${f.errors.length}',
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OhtliColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OhtliColors.warning.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in f.errors.reversed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SelectableText(
                              '${(e['at'] ?? '').replaceFirst('T', ' ').split('.').first}${e['where'] == null ? '' : ' · ${e['where']}'}\n${e['message'] ?? ''}',
                              style: GoogleFonts.robotoMono(fontSize: 11.5, color: OhtliColors.onyx, height: 1.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

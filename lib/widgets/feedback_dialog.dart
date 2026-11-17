import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_diagnostics.dart';
import '../services/feedback_service.dart';
import '../theme/colors.dart';
import '../utils/web_helpers.dart';
import 'ohtli_ui.dart';

/// Botón "Enviar comentarios": abre [showFeedbackDialog]. En `compact` es solo el ícono con
/// tooltip (barras de título y encabezados estrechos).
class FeedbackButton extends StatelessWidget {
  final String screen;
  final Map<String, String> Function()? contextBuilder;
  final bool compact;

  const FeedbackButton({super.key, required this.screen, this.contextBuilder, this.compact = false});

  @override
  Widget build(BuildContext context) {
    void open() => showFeedbackDialog(context, screen: screen, extra: contextBuilder?.call());
    if (compact) {
      return IconButton(
        tooltip: 'Enviar comentarios',
        onPressed: open,
        icon: Icon(Icons.rate_review_outlined, color: OhtliColors.accentText, size: 21),
      );
    }
    return TextButton.icon(
      onPressed: open,
      icon: Icon(Icons.rate_review_outlined, size: 17, color: OhtliColors.accentText),
      label: Text(
        'Enviar comentarios',
        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.accentText),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// Hoja para mandar un comentario al equipo de Ohtli. Antes de abrirla se toma una captura de lo
/// que se ve; la persona puede quitarla, agregar fotos y ver lo que se envía. Se guarda en
/// Firestore (`app_feedback`) y la Cloud Function lo manda por correo.
Future<void> showFeedbackDialog(BuildContext context, {required String screen, Map<String, String>? extra}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final capture = await AppDiagnostics.captureScreen();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => _FeedbackSheet(screen: screen, extra: extra, messenger: messenger, capture: capture),
  );
}

class _FeedbackSheet extends StatefulWidget {
  final String screen;
  final Map<String, String>? extra;
  final ScaffoldMessengerState? messenger;
  final Uint8List? capture;

  const _FeedbackSheet({required this.screen, this.extra, this.messenger, this.capture});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  static const _kinds = <String, (String, IconData, String)>{
    'idea': ('Una idea', Icons.lightbulb_outline_rounded, '¿Qué te gustaría que hiciera Ohtli?'),
    'bug': ('Algo falla', Icons.bug_report_outlined, '¿Qué pasó y qué esperabas que pasara?'),
    'other': ('Otro', Icons.chat_bubble_outline_rounded, 'Escribe tu comentario'),
  };

  final _text = TextEditingController();
  final List<FeedbackAttachment> _attachments = [];
  String _category = 'idea';
  bool _includeDiagnostics = true;
  bool _sending = false;
  String? _error;
  late final Map<String, String> _device = AppDiagnostics.device();
  late final Map<String, String> _system = AppDiagnostics.system();
  late final Map<String, String> _user = AppDiagnostics.user();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (widget.capture != null && widget.capture!.length <= FeedbackService.maxAttachmentBytes) {
      _attachments.add(FeedbackAttachment(widget.capture!, 'image/png', isScreenCapture: true));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().length >= FeedbackService.commentMinLength;

  Future<void> _addPhoto() async {
    try {
      final f = await pickFile(accept: 'image/png,image/jpeg,image/webp,image/gif');
      if (f == null || !mounted) return;
      if (!f.mimeType.startsWith('image/')) {
        setState(() => _error = 'Solo se pueden adjuntar imágenes.');
        return;
      }
      if (f.bytes.length > FeedbackService.maxAttachmentBytes) {
        setState(() => _error = 'La imagen pesa más de 5 MB. Elige una más ligera.');
        return;
      }
      setState(() {
        _error = null;
        _attachments.add(FeedbackAttachment(f.bytes, f.mimeType));
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo leer la imagen.');
    }
  }

  Future<void> _send() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await FeedbackService.sendComment(
        message: _text.text,
        category: _category,
        screen: widget.screen,
        context: widget.extra,
        attachments: _attachments,
        includeDiagnostics: _includeDiagnostics,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.messenger?.showSnackBar(
        SnackBar(
          content: Text('¡Gracias! Recibimos tu comentario.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.stormyTeal,
        ),
      );
    } catch (e) {
      debugPrint('[Feedback] no se pudo enviar el comentario: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'No se pudo enviar. Revisa tu conexión e inténtalo otra vez.';
      });
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text, style: OhtliUi.eyebrow(OhtliColors.subtleText)),
      );

  Widget _thumb(int index) {
    final a = _attachments[index];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: InteractiveViewer(child: Image.memory(a.bytes, fit: BoxFit.contain)),
              ),
            ),
          ),
          child: Container(
            width: 92,
            height: 120,
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(child: SizedBox.expand(child: Image.memory(a.bytes, fit: BoxFit.cover, gaplessPlayback: true))),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: OhtliColors.cardBg,
                  child: Text(
                    a.isScreenCapture ? 'Esta pantalla' : 'Foto ${index + 1}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: Material(
            color: OhtliColors.onyx,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : () => setState(() => _attachments.removeAt(index)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 14, color: OhtliColors.cloudDancer),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addTile() => InkWell(
        onTap: _sending ? null : _addPhoto,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 92,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OhtliColors.accentText.withValues(alpha: 0.5), width: 1.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, color: OhtliColors.accentText),
              const SizedBox(height: 6),
              Text('Agregar\nfoto',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: OhtliColors.accentText)),
            ],
          ),
        ),
      );

  // ---------- Vista previa: lo que se envía ----------
  Widget _previewRow(IconData icon, String title, List<String> lines) {
    final shown = lines.where((l) => l.trim().isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: OhtliColors.stormyTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 2),
                Text(shown.join(' · '), style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final d = _device;
    final s = _system;
    final errors = AppDiagnostics.recentErrors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _previewRow(Icons.person_outline_rounded, 'Tu cuenta', [_user['nombre'] ?? '', _user['correo'] ?? '']),
          _previewRow(Icons.place_outlined, 'Dónde estabas', [
            widget.screen,
            ...?widget.extra?.entries.map((e) => '${e.key}: ${e.value}'),
          ]),
          _previewRow(Icons.photo_library_outlined, 'Imágenes',
              [_attachments.isEmpty ? 'ninguna' : '${_attachments.length} adjunta${_attachments.length == 1 ? '' : 's'}']),
          if (_includeDiagnostics) ...[
            _previewRow(Icons.devices_outlined, 'Dispositivo', [
              d['navegador'] ?? '',
              if (d['pantalla'] != null) 'pantalla ${d['pantalla']}',
              if (d['ventana'] != null) 'ventana ${d['ventana']}',
              d['memoria'] ?? '',
              d['red'] ?? d['conexion'] ?? '',
              d['instalada'] == null ? '' : (d['instalada']!.startsWith('sí') ? 'instalada' : 'en el navegador'),
            ]),
            _previewRow(Icons.tune_rounded, 'Estado de Ohtli', [
              'v${s['version'] ?? ''}',
              'tema ${s['tema'] ?? ''}',
              'letra ${s['letra'] ?? ''}',
              'abierta hace ${s['abiertaHace'] ?? ''}',
              errors.isEmpty ? 'sin errores' : '${errors.length} error${errors.length == 1 ? '' : 'es'} reciente${errors.length == 1 ? '' : 's'}',
            ]),
          ] else
            _previewRow(Icons.devices_outlined, 'Dispositivo y sistema', ['no se envían']),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(color: OhtliColors.cardBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                Row(
                  children: [
                    Icon(Icons.rate_review_outlined, color: OhtliColors.accentText, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Enviar comentarios',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 20, color: OhtliColors.onyx)),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: _sending ? null : () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: OhtliColors.subtleText),
                    ),
                  ],
                ),
                Text(
                  signedIn
                      ? 'Cuéntanos qué te gustó, qué no o qué falló. Lo lee el equipo de Ohtli.'
                      : 'Inicia sesión para enviarnos comentarios.',
                  style: OhtliUi.body(size: 13.5),
                ),
                if (signedIn) ...[
                  _label('¿QUÉ NOS QUIERES CONTAR?'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in FeedbackService.commentCategories)
                        OhtliChoiceChip(
                          label: _kinds[c]!.$1,
                          icon: _kinds[c]!.$2,
                          selected: _category == c,
                          onTap: () {
                            if (!_sending) setState(() => _category = c);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('feedback-text'),
                    controller: _text,
                    enabled: !_sending,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: FeedbackService.commentMaxLength,
                    style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx),
                    decoration: InputDecoration(
                      hintText: _kinds[_category]!.$3,
                      hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
                      filled: true,
                      fillColor: OhtliColors.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: OhtliColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6),
                      ),
                    ),
                  ),
                  _label('CAPTURAS Y FOTOS'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Row(
                      children: [
                        for (var i = 0; i < _attachments.length; i++) ...[_thumb(i), const SizedBox(width: 14)],
                        if (_attachments.length < FeedbackService.maxAttachments) _addTile(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hasta ${FeedbackService.maxAttachments} imágenes de 5 MB. Toca una para verla completa.',
                    style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _includeDiagnostics,
                    activeTrackColor: OhtliColors.stormyTeal,
                    onChanged: _sending ? null : (v) => setState(() => _includeDiagnostics = v),
                    title: Text('Incluir info del dispositivo y del sistema',
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                    subtitle: Text('Navegador, pantalla, red, versión de Ohtli y errores recientes. Nos ayuda a encontrar la falla.',
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
                  ),
                  _label('LO QUE SE ENVÍA'),
                  _preview(),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.warningText)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _valid ? 'Solo lo ve el equipo de Ohtli.' : 'Escribe al menos ${FeedbackService.commentMinLength} letras.',
                          style: OhtliUi.body(size: 12),
                        ),
                      ),
                      OhtliPrimaryButton(
                        label: 'Enviar',
                        icon: Icons.send_rounded,
                        loading: _sending,
                        onPressed: _valid && !_sending ? _send : null,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/feedback_service.dart';
import '../theme/colors.dart';
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

/// Diálogo para mandar un comentario al equipo de Ohtli. Guarda en Firestore
/// (`app_feedback`) y la Cloud Function lo manda por correo; la persona no abre su correo.
Future<void> showFeedbackDialog(BuildContext context, {required String screen, Map<String, String>? extra}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _FeedbackDialog(screen: screen, extra: extra, messenger: messenger),
  );
}

class _FeedbackDialog extends StatefulWidget {
  final String screen;
  final Map<String, String>? extra;
  final ScaffoldMessengerState? messenger;

  const _FeedbackDialog({required this.screen, this.extra, this.messenger});

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  static const _labels = {'idea': 'Una idea', 'bug': 'Algo falla', 'other': 'Otro'};
  final _text = TextEditingController();
  String _category = 'idea';
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().length >= FeedbackService.commentMinLength;

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

  @override
  Widget build(BuildContext context) {
    final signedIn = FirebaseAuth.instance.currentUser != null;
    return AlertDialog(
      backgroundColor: OhtliColors.cloudDancer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      title: Row(
        children: [
          Icon(Icons.rate_review_outlined, color: OhtliColors.accentText, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Enviar comentarios',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 19, color: OhtliColors.onyx),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                signedIn
                    ? 'Cuéntanos qué te gustó, qué no o qué falló. Lo lee el equipo de Ohtli.'
                    : 'Inicia sesión para enviarnos comentarios.',
                style: OhtliUi.body(size: 13.5),
              ),
              if (signedIn) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in FeedbackService.commentCategories)
                      OhtliChoiceChip(
                        label: _labels[c] ?? c,
                        selected: _category == c,
                        onTap: () { if (!_sending) setState(() => _category = c); },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('feedback-text'),
                  controller: _text,
                  enabled: !_sending,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: FeedbackService.commentMaxLength,
                  style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx),
                  decoration: InputDecoration(
                    hintText: _category == 'bug'
                        ? '¿Qué pasó y qué esperabas que pasara?'
                        : 'Escribe tu comentario',
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
                Text(
                  'Junto con tu comentario mandamos la pantalla, la versión de Ohtli y tu navegador para entender mejor qué pasó.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText, height: 1.4),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.warningText)),
                ],
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(signedIn ? 'Cancelar' : 'Cerrar', style: GoogleFonts.inter(color: OhtliColors.subtleText)),
        ),
        if (signedIn)
          OhtliPrimaryButton(
            compact: true,
            label: 'Enviar',
            icon: Icons.send_rounded,
            loading: _sending,
            onPressed: _valid ? _send : null,
          ),
      ],
    );
  }
}

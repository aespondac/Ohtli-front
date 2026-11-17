import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import 'lab_models.dart';
import 'lab_research_repository.dart';

/// Piezas comunes de la consola de investigación.

Color studyStatusColor(StudyStatus s) => switch (s) {
      StudyStatus.borrador => OhtliColors.subtleText,
      StudyStatus.preregistrado => const Color(0xFF6C5CE7),
      StudyStatus.reclutando || StudyStatus.enCurso => OhtliColors.stormyTeal,
      StudyStatus.analisis || StudyStatus.enRevision => OhtliColors.accent,
      StudyStatus.publicado => const Color(0xFF2F6F4F),
      StudyStatus.pausado => OhtliColors.warningText,
      StudyStatus.archivado || StudyStatus.cancelado => OhtliColors.subtleText,
    };

class LabTag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const LabTag(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(text, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

class ConfidentialTag extends StatelessWidget {
  const ConfidentialTag({super.key});
  @override
  Widget build(BuildContext context) => LabTag('Confidencial', color: OhtliColors.warningText, icon: Icons.lock_outline_rounded);
}

/// Campo de texto con etiqueta, para formularios de la consola.
Widget labField(TextEditingController c, String label, {int maxLines = 1, bool enabled = true, String? hint, TextInputType? keyboard}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
      ),
    );

/// Muestra el error de una operación como aviso (las reglas devuelven permission-denied).
Future<void> runLabAction(BuildContext context, Future<void> Function() action, {String? ok}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (ok != null) messenger.showSnackBar(SnackBar(content: Text(ok)));
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    final msg = '$e'.contains('permission-denied')
        ? 'No tienes permiso para hacer esto (o falta un paso previo, como el NDA).'
        : 'No se pudo completar: $e';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }
}

Future<bool> confirmLab(BuildContext context, String title, String message, {String confirm = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(confirm)),
      ],
    ),
  );
  return r == true;
}

/// Texto real de algo confidencial si la sesión puede leer `private/details`; si no, el
/// enmascarado.
class RevealedText extends StatelessWidget {
  final String masked;
  final bool confidential;
  final Future<Map<String, dynamic>?> Function() load;
  final String field;
  final TextStyle? style;
  const RevealedText({super.key, required this.masked, required this.confidential, required this.load, this.field = 'title', this.style});

  @override
  Widget build(BuildContext context) {
    if (!confidential) return Text(masked, style: style);
    return FutureBuilder<Map<String, dynamic>?>(
      future: load(),
      builder: (_, s) {
        final real = s.data?[field]?.toString();
        if (real == null || real.isEmpty) return Text(masked, style: style);
        return Text('$real  ·  $masked', style: style);
      },
    );
  }
}

/// Cache simple de los detalles reales (para no pedirlos en cada redibujo).
class SecretCache {
  SecretCache._();
  static final Map<String, Future<Map<String, dynamic>?>> _cache = {};

  static Future<Map<String, dynamic>?> study(String id) =>
      _cache.putIfAbsent('study:$id', () => LabResearch.instance.secretOf(LabResearch.instance.studies.doc(id)));
  static Future<Map<String, dynamic>?> project(String id) =>
      _cache.putIfAbsent('project:$id', () => LabResearch.instance.secretOf(LabResearch.instance.projects.doc(id)));
  static void forget(String key) => _cache.remove(key);
}

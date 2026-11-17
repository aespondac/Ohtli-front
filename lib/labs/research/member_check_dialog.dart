import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import 'lab_models.dart';
import 'lab_research_repository.dart';

/// Validación de participantes (*member checking*): el tester lee el resumen y los resultados del
/// paper y dice si se ve reflejado. Un voto por ronda; anónimo para el equipo.
class MemberCheckDialog extends StatefulWidget {
  final LabPaper paper;
  const MemberCheckDialog({super.key, required this.paper});

  static Future<bool?> show(BuildContext context, LabPaper paper) =>
      showDialog<bool>(context: context, builder: (_) => MemberCheckDialog(paper: paper));

  @override
  State<MemberCheckDialog> createState() => _MemberCheckDialogState();
}

class _MemberCheckDialogState extends State<MemberCheckDialog> {
  MemberCheckVote? _vote;
  MemberCheckVote? _already;
  final _comment = TextEditingController();
  bool _saving = false, _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    LabResearch.instance.myVote(widget.paper).then((v) {
      if (mounted) setState(() => (_already = v, _loading = false));
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_vote == null) return;
    setState(() => (_saving = true, _error = null));
    try {
      await LabResearch.instance.vote(widget.paper, _vote!, _comment.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => (_saving = false, _error = 'No se guardó tu validación. Puede que la ventana ya haya cerrado.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paper;
    final closes = p.checkClosesAt;
    return AlertDialog(
      backgroundColor: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('¿Te ves reflejado en los resultados?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 20, color: OhtliColors.onyx)),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(p.title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: OhtliColors.onyx)),
                  const SizedBox(height: 8),
                  Text(p.abstract.isEmpty ? 'El equipo aún no escribe el resumen.' : p.abstract,
                      style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: OhtliColors.subtleText)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.verified_user_outlined, size: 18, color: OhtliColors.stormyTeal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Tus respuestas están incluidas en estos resultados, de forma anónima y agregada.',
                            style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx)),
                      ),
                    ]),
                  ),
                  if (closes != null) ...[
                    const SizedBox(height: 8),
                    Text('Puedes responder hasta el ${closes.day}/${closes.month}/${closes.year}.',
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
                  ],
                  const SizedBox(height: 16),
                  if (_already != null)
                    Text('Ya respondiste en esta ronda: ${_already!.label}. ¡Gracias!',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal))
                  else ...[
                    Wrap(spacing: 8, children: [
                      for (final v in MemberCheckVote.values)
                        ChoiceChip(
                          label: Text(v.label),
                          selected: _vote == v,
                          onSelected: (_) => setState(() => _vote = v),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _comment,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '¿Qué falta o qué no coincide con tu experiencia? (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_error != null) Text(_error!, style: TextStyle(color: OhtliColors.warningText)),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        if (_already == null)
          FilledButton(
            onPressed: _vote == null || _saving ? null : _send,
            child: Text(_saving ? 'Enviando…' : 'Enviar validación'),
          ),
      ],
    );
  }
}

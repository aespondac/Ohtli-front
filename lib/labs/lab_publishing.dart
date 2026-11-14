import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_access.dart';
import 'lab_aggregates.dart';
import 'lab_article.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';

/// Selector de visibilidad (pipeline: privado → testers → público). Solo el superusuario abre al público.
class VisibilityPicker extends StatelessWidget {
  final String value;
  final LabRole role;
  final ValueChanged<String>? onChanged;
  const VisibilityPicker({super.key, required this.value, required this.role, this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final v in LabVisibility.all)
            DropdownMenuItem(
              value: v,
              enabled: v != LabVisibility.public || role == LabRole.admin,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LabVisibility.icon(v), size: 15, color: v == LabVisibility.public && role != LabRole.admin ? OhtliColors.subtleText : OhtliColors.stormyTeal),
                const SizedBox(width: 6),
                Text(LabVisibility.label(v), style: labCell()),
              ]),
            ),
        ],
        onChanged: onChanged == null ? null : (v) => v == null ? null : onChanged!(v),
      );
}

String slugify(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  var out = s;
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  out = out.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return out.length > 70 ? out.substring(0, 70) : out;
}

// ---------------------------------------------------------------------------------------------
// Artículos
// ---------------------------------------------------------------------------------------------

class LabPostsPanel extends StatefulWidget {
  final LabRole role;
  const LabPostsPanel({super.key, required this.role});

  @override
  State<LabPostsPanel> createState() => _LabPostsPanelState();
}

class _LabPostsPanelState extends State<LabPostsPanel> {
  String? _editing; // id, 'new' o null

  @override
  Widget build(BuildContext context) {
    if (_editing != null) {
      return _PostEditor(
        postId: _editing == 'new' ? null : _editing,
        role: widget.role,
        onClose: () => setState(() => _editing = null),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('Publicaciones',
              caption: 'Cada artículo congela los datos de las corridas que cita. Avanza por la pipeline: '
                  'privado (laboratorio) → testers → público en labs.ohtli.quest/news, sin iniciar sesión.'),
          _PipelineLegend(),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => setState(() => _editing = 'new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nuevo artículo'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: LabRepository.instance.watchAllPosts(),
        builder: (context, snap) {
          if (snap.hasError) return LabCard(child: Text('Error: ${snap.error}', style: labCell()));
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return LabCard(child: Text('Aún no hay artículos.', style: labCell()));
          return Column(
            children: docs.map((d) {
              final m = d.data();
              final vis = LabVisibility.of(m);
              final published = m['status'] == 'published';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Icon(LabVisibility.icon(vis), size: 18, color: OhtliColors.stormyTeal),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text('${m['title'] ?? '(sin título)'}', style: labCell(bold: true)),
                    ),
                    Text(published ? 'Publicado · ${LabVisibility.label(vis)}' : 'Borrador', style: labCell()),
                    Text('actualizado ${fmtDate(m['updatedAt'])}', style: labCell()),
                    if (published && vis == LabVisibility.public)
                      SelectableText('labs.ohtli.quest/news/${m['slug']}', style: labCell()),
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = d.id),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar'),
                    ),
                  ]),
                ),
              );
            }).toList(),
          );
        },
      ),
    ]);
  }
}

class _PipelineLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget step(IconData i, String t, String d) => Container(
          width: 210,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: OhtliColors.innerCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: OhtliColors.cardBorder)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 18, color: OhtliColors.stormyTeal),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: labCell(bold: true)),
                Text(d, style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
              ]),
            ),
          ]),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      step(Icons.science_outlined, '1. Ejecutar', 'Corridas en la consola (privadas)'),
      step(Icons.lock_outline_rounded, '2. Revisión interna', 'Solo miembros del laboratorio'),
      step(Icons.group_outlined, '3. Testers', 'Liberado a testers registrados'),
      step(Icons.public_rounded, '4. Público', 'Artículo en el blog, sin sesión'),
    ]);
  }
}

class _PostEditor extends StatefulWidget {
  final String? postId;
  final LabRole role;
  final VoidCallback onClose;
  const _PostEditor({required this.postId, required this.role, required this.onClose});

  @override
  State<_PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<_PostEditor> {
  final _title = TextEditingController();
  final _slug = TextEditingController();
  final _authors = TextEditingController(text: 'Trabajo Terminal 2026-B156 · ESCOM-IPN');
  final _summary = TextEditingController();
  final _body = TextEditingController();
  String _visibility = LabVisibility.private;
  String _status = 'draft';
  final Set<String> _runIds = {};
  final Set<String> _aggs = {};
  List<Map<String, dynamic>> _snapshots = [];
  bool _loading = true, _saving = false, _preview = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _runs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = LabRepository.instance;
    final runs = await repo.runs.orderBy('startedAt', descending: true).limit(60).get();
    _runs = runs.docs.where((d) => d.data()['status'] == 'completed').toList();
    if (widget.postId != null) {
      final m = (await repo.posts.doc(widget.postId).get()).data() ?? {};
      _title.text = m['title'] ?? '';
      _slug.text = m['slug'] ?? '';
      _authors.text = m['authors'] ?? _authors.text;
      _summary.text = m['summary'] ?? '';
      _body.text = m['body'] ?? '';
      _visibility = LabVisibility.of(m);
      _status = m['status'] ?? 'draft';
      _runIds.addAll(((m['runIds'] as List?) ?? []).map((e) => '$e'));
      _aggs.addAll(((m['aggregateStudies'] as List?) ?? []).map((e) => '$e'));
      _snapshots = ((m['snapshots'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<List<Map<String, dynamic>>> _freeze() async {
    final out = <Map<String, dynamic>>[];
    for (final r in _runs.where((r) => _runIds.contains(r.id))) {
      out.add(await buildRunSnapshot(r.id, r.data()));
    }
    for (final sid in _aggs) {
      final study = studyById(sid);
      if (study == null) continue;
      final docs = (await LabRepository.instance.responses.where('studyId', isEqualTo: sid).get()).docs.map((d) => d.data()).toList();
      final clean = cleanResponses(study.kind, docs);
      out.add(buildAggregateSnapshot(study, sid == 'sus' ? aggregateSus(clean) : aggregateRelevance(clean)));
    }
    return out;
  }

  Map<String, dynamic> _current() => {
        'title': _title.text.trim(),
        'slug': _slug.text.trim().isEmpty ? slugify(_title.text) : slugify(_slug.text),
        'authors': _authors.text.trim(),
        'summary': _summary.text.trim(),
        'body': _body.text,
        'snapshots': _snapshots,
        'visibility': _visibility,
        'status': _status,
        'publishedAt': _status == 'published' ? DateTime.now() : null,
      };

  Future<void> _save({bool refreeze = false}) async {
    if (_title.text.trim().isEmpty) return;
    if (_visibility == LabVisibility.public && _status == 'published' && widget.role != LabRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solo el superusuario puede publicar en abierto.')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (refreeze || _snapshots.isEmpty) _snapshots = await _freeze();
      final data = _current()
        ..['runIds'] = _runIds.toList()
        ..['aggregateStudies'] = _aggs.toList()
        ..['frozenAt'] = FieldValue.serverTimestamp();
      data['publishedAt'] = _status == 'published' ? FieldValue.serverTimestamp() : null;
      await LabRepository.instance.savePost(widget.postId, data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Artículo guardado')));
      if (widget.postId == null) widget.onClose();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _f(TextEditingController c, String l, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: lines,
          style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx),
          decoration: InputDecoration(labelText: l, filled: true, fillColor: OhtliColors.inputBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_preview) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(onPressed: () => setState(() => _preview = false), icon: const Icon(Icons.arrow_back), label: const Text('Volver al editor')),
        LabCard(padding: const EdgeInsets.all(28), child: LabArticleView(post: {..._current(), 'publishedAt': null})),
      ]);
    }
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(onPressed: widget.onClose, icon: const Icon(Icons.arrow_back)),
          Expanded(child: LabSectionTitle(widget.postId == null ? 'Nuevo artículo' : 'Editar artículo')),
        ]),
        _f(_title, 'Título'),
        _f(_slug, 'Ruta (labs.ohtli.quest/news/…); vacío = se genera del título'),
        _f(_authors, 'Autoría'),
        _f(_summary, 'Resumen (entradilla)', lines: 3),
        _f(_body, 'Cuerpo: párrafos separados por línea en blanco, "## " subtítulo, "- " viñeta, **negritas**', lines: 14),
        Text('Datos citados (se congelan al guardar)', style: labCell(bold: true)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final r in _runs)
            FilterChip(
              selected: _runIds.contains(r.id),
              label: Text('${studyById('${r.data()['studyId']}')?.title ?? r.data()['studyId']} · ${fmtDate(r.data()['startedAt'])}',
                  style: GoogleFonts.inter(fontSize: 11.5)),
              onSelected: (v) => setState(() => v ? _runIds.add(r.id) : _runIds.remove(r.id)),
            ),
          for (final sid in ['relevancia', 'sus'])
            FilterChip(
              selected: _aggs.contains(sid),
              label: Text('Agregados: ${studyById(sid)!.title}', style: GoogleFonts.inter(fontSize: 11.5)),
              onSelected: (v) => setState(() => v ? _aggs.add(sid) : _aggs.remove(sid)),
            ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Visibilidad: ', style: labCell(bold: true)),
            VisibilityPicker(value: _visibility, role: widget.role, onChanged: (v) => setState(() => _visibility = v)),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Estado: ', style: labCell(bold: true)),
            DropdownButton<String>(
              value: _status,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                DropdownMenuItem(value: 'published', child: Text('Publicado')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'draft'),
            ),
          ]),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ElevatedButton.icon(
            onPressed: _saving ? null : () => _save(refreeze: true),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar y congelar datos'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar sin actualizar datos'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              if (_snapshots.isEmpty) _snapshots = await _freeze();
              setState(() => _preview = true);
            },
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Vista previa'),
          ),
        ]),
        if (_visibility == LabVisibility.public && widget.role != LabRole.admin)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('La publicación abierta la aprueba el superusuario.', style: labCell()),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Miembros (solo superusuario)
// ---------------------------------------------------------------------------------------------

class LabMembersPanel extends StatefulWidget {
  const LabMembersPanel({super.key});

  @override
  State<LabMembersPanel> createState() => _LabMembersPanelState();
}

class _LabMembersPanelState extends State<LabMembersPanel> {
  final _email = TextEditingController();
  String _role = 'researcher';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('Miembros del laboratorio',
              caption: 'Los miembros ejecutan pruebas, ven los resultados privados y redactan artículos. '
                  'La invitación se acepta sola cuando la persona entra a lab.ohtli.quest con ese correo verificado.'),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _email,
                decoration: InputDecoration(labelText: 'Correo', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
            DropdownButton<String>(
              value: _role,
              items: const [
                DropdownMenuItem(value: 'researcher', child: Text('Miembro del laboratorio')),
                DropdownMenuItem(value: 'tester', child: Text('Tester')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'researcher'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final e = _email.text.trim();
                if (!e.contains('@')) return;
                await LabAccess.invite(e, _role);
                _email.clear();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitación registrada para $e')));
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Invitar'),
              style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            ),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<int>(
            future: LabAccess.testerCount(),
            builder: (context, s) => Text('Testers registrados: ${s.data ?? '…'}', style: labCell(bold: true)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('Miembros e invitaciones'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: LabAccess.watchMembers(),
            builder: (context, s) {
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) return Text('Sin miembros además del superusuario.', style: labCell());
              return Column(
                children: docs
                    .map((d) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text('${d.data()['email'] ?? d.id}', style: labCell(bold: true)),
                          subtitle: Text('${d.data()['role']} · desde ${fmtDate(d.data()['joinedAt'])}', style: labCell()),
                          trailing: IconButton(
                            tooltip: 'Quitar del laboratorio',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => LabAccess.removeMember(d.id, d.data()['email'] as String?),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const Divider(),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: LabAccess.watchInvites(),
            builder: (context, s) {
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) return Text('Sin invitaciones pendientes.', style: labCell());
              return Column(
                children: docs
                    .map((d) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.mail_outline),
                          title: Text(d.id, style: labCell(bold: true)),
                          subtitle: Text('invitación · ${d.data()['role']}', style: labCell()),
                          trailing: IconButton(
                            tooltip: 'Cancelar invitación',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => d.reference.delete(),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ]),
      ),
    ]);
  }
}

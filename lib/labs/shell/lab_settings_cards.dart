import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../lab_access.dart';
import '../lab_widgets.dart';
import '../research/lab_iam.dart';
import '../research/lab_research_repository.dart';
import '../research/research_widgets.dart';

/// Tarjetas de la pestaña Configuración, comunes a proyectos, estudios, experimentos, encuestas y
/// funcionalidades (como las páginas de IAM y registros de cada recurso en GCP).

final _repo = LabResearch.instance;
TextStyle _h(double size) => GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: OhtliColors.onyx);

String labAuditLabel(String a) => switch (a) {
      'project.create' => 'Proyecto creado',
      'project.members' => 'Miembros del proyecto',
      'project.declassify' => 'Proyecto desclasificado',
      'iam.update' => 'Accesos actualizados',
      'iam.migrate' => 'Migración al IAM',
      'resource.share' => 'Compartido con otros proyectos',
      'resource.unshare' => 'Dejó de compartirse',
      'study.create' => 'Estudio creado',
      'study.preregister' => 'Preregistro congelado',
      'study.amend' => 'Enmienda al preregistro',
      'study.status' => 'Cambio de estado',
      'study.move' => 'Cambio de proyecto',
      'study.enroll' => 'Inscripción de un tester',
      'study.leave' => 'Baja de un tester',
      'experiment.create' => 'Experimento creado',
      'experiment.update' => 'Experimento editado',
      'survey.create' => 'Encuesta creada',
      'survey.update' => 'Encuesta editada',
      'paper.create' => 'Paper creado',
      'paper.stage' => 'Etapa del paper',
      'paper.review' => 'Dictamen',
      'paper.check_extend' => 'Validación extendida',
      'paper.publish' => 'Publicado en el blog',
      'feature.save' => 'Funcionalidad guardada',
      'feature.stage' => 'Destino de la funcionalidad',
      'nda.accept' => 'NDA aceptado',
      _ => a,
    };

String _detail(dynamic d) {
  if (d is! Map || d.isEmpty) return '';
  return [
    for (final e in d.entries)
      if (e.key != 'before' && e.key != 'projectId') '${e.key}: ${e.value}',
  ].join(', ');
}

/// Bitácora de un recurso ([target], p. ej. `study:abc`, o varios en [targets]) o de todo un
/// proyecto ([projectId]).
class LabAuditCard extends StatelessWidget {
  final String? target;
  final List<String> targets;
  final String? projectId;
  const LabAuditCard({super.key, this.target, this.targets = const [], this.projectId});

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream =
        projectId != null ? _repo.watchProjectAudit(projectId!) : _repo.watchAudit(limit: 300);
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Bitácora', style: _h(16)),
        const SizedBox(height: 4),
        Text(
          projectId != null
              ? 'Todo lo que pasó en el proyecto y sus recursos. Solo se agrega: nadie puede editarla ni borrarla.'
              : 'Solo se agrega: nadie puede editarla ni borrarla.',
          style: labCell(),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (c, snap) {
            if (snap.hasError) return Text('No pudimos cargar la bitácora.', style: labCell());
            if (!snap.hasData) return const LinearProgressIndicator();
            final wanted = {?target, ...targets};
            final docs = (snap.data!.docs).where((d) => wanted.isEmpty || wanted.contains(d.data()['target'])).take(60).toList();
            if (docs.isEmpty) return Text('Sin movimientos todavía.', style: labCell());
            return Column(children: [
              for (final d in docs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded, size: 18),
                  title: Text(labAuditLabel(d.data()['action']?.toString() ?? ''), style: labCell(bold: true)),
                  subtitle: Text([
                    if (wanted.isEmpty) d.data()['target']?.toString() ?? '',
                    _detail(d.data()['detail']),
                  ].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: Text(fmtDate(d.data()['at']), style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// IAM de un recurso: concesiones heredadas del proyecto (solo lectura) y las propias, editables por
/// su propietario. Guarda con [LabResearch.setIam].
class LabIamCard extends StatefulWidget {
  final LabResourceKind kind;
  final String id;
  final String? projectId;

  /// IAM del proyecto (para recursos dentro de uno). Null si el recurso es el proyecto.
  final Map<String, String>? inherited;
  final Map<String, String> own;
  final bool canManage;

  /// Datos para crear el documento de un recurso integrado que aún no lo tiene.
  final Map<String, dynamic> seed;
  const LabIamCard({
    super.key,
    required this.kind,
    required this.id,
    required this.own,
    required this.canManage,
    this.projectId,
    this.inherited,
    this.seed = const {},
  });

  @override
  State<LabIamCard> createState() => _LabIamCardState();
}

class _LabIamCardState extends State<LabIamCard> {
  late Map<String, String> _iam = Map.of(widget.own);
  bool _dirty = false;
  bool _saving = false;

  @override
  void didUpdateWidget(LabIamCard old) {
    super.didUpdateWidget(old);
    if (!_dirty) _iam = Map.of(widget.own);
  }

  String _who(String principal, Map<String, Map<String, dynamic>> members) {
    if (principal == kLabAllMembers) return 'Todos los miembros del laboratorio';
    final m = members[principal];
    final user = FirebaseAuth.instance.currentUser;
    final isMe = user?.uid == principal;
    // El superusuario no tiene ficha en lab_members: para la propia cuenta se usa la sesión.
    final name = m?['displayName'] ?? m?['email'] ?? (isMe ? (user?.displayName ?? user?.email) : null) ?? principal;
    return '$name${isMe ? ' (tú)' : ''}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await runLabAction(context, () async {
      await _repo.setIam(widget.kind, widget.id, _iam, projectId: widget.projectId, seed: widget.seed);
      if (mounted) setState(() => _dirty = false);
    }, ok: 'Accesos guardados.');
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _add(Map<String, Map<String, dynamic>> members) async {
    String? who;
    var role = LabIamRole.viewer;
    final candidates = [kLabAllMembers, ...members.keys.where((k) => !_iam.containsKey(k))]..removeWhere((k) => _iam.containsKey(k));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Dar acceso'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: who,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Persona', border: OutlineInputBorder(), isDense: true),
                items: [for (final k in candidates) DropdownMenuItem(value: k, child: Text(_who(k, members), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => set(() => who = v),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in [LabIamRole.viewer, LabIamRole.editor, LabIamRole.owner])
                  ChoiceChip(
                    label: Text(r.label),
                    selected: role == r,
                    onSelected: who == kLabAllMembers && r == LabIamRole.owner ? null : (_) => set(() => role = r),
                  ),
              ]),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(role.description, style: labCell())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: who == null ? null : () => Navigator.pop(c, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true || who == null) return;
    setState(() {
      _iam[who!] = role.key!;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final problem = _dirty ? validateIamChange(_iam, requireOwner: widget.kind == LabResourceKind.project) : null;
    return LabCard(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: LabAccess.watchMembers(),
        builder: (context, snap) {
          final members = {
            for (final d in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (const ['researcher', 'admin', 'reviewer'].contains(d.data()['role'])) d.id: d.data(),
          };
          final inherited = widget.inherited ?? const {};
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Accesos (IAM)', style: _h(16))),
              if (widget.canManage)
                OutlinedButton.icon(onPressed: () => _add(members), icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Dar acceso')),
            ]),
            const SizedBox(height: 4),
            Text(
              widget.inherited == null
                  ? 'Estos roles los heredan todos los estudios, experimentos, encuestas y funcionalidades del proyecto.'
                  : 'Los roles del proyecto se heredan aquí. Puedes dar acceso extra solo a este recurso; nunca quita lo que da el proyecto.',
              style: labCell(),
            ),
            const SizedBox(height: 10),
            if (inherited.isNotEmpty) ...[
              Text('Heredado del proyecto', style: labCell(bold: true)),
              for (final e in inherited.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(e.key == kLabAllMembers ? Icons.groups_outlined : Icons.person_outline, size: 20),
                  title: Text(_who(e.key, members), style: labCell()),
                  trailing: Text(parseIamRole(e.value).label, style: labCell()),
                ),
              const SizedBox(height: 6),
              Text(widget.inherited == null ? 'Roles' : 'Solo en este recurso', style: labCell(bold: true)),
            ],
            if (_iam.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('Nadie todavía.', style: labCell())),
            for (final e in _iam.entries.toList()..sort((a, b) => parseIamRole(b.value).rank.compareTo(parseIamRole(a.value).rank)))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(e.key == kLabAllMembers ? Icons.groups_outlined : Icons.person_outline, size: 20),
                title: Text(_who(e.key, members), style: labCell()),
                trailing: !widget.canManage
                    ? Text(parseIamRole(e.value).label, style: labCell())
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButton<String>(
                          value: parseIamRole(e.value).key,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final r in [LabIamRole.viewer, LabIamRole.editor, LabIamRole.owner])
                              if (!(e.key == kLabAllMembers && r == LabIamRole.owner)) DropdownMenuItem(value: r.key, child: Text(r.label)),
                          ],
                          onChanged: (v) => setState(() {
                            if (v != null) _iam[e.key] = v;
                            _dirty = true;
                          }),
                        ),
                        IconButton(
                          tooltip: 'Quitar acceso',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() {
                            _iam.remove(e.key);
                            _dirty = true;
                          }),
                        ),
                      ]),
              ),
            if (_dirty) ...[
              const SizedBox(height: 8),
              if (problem != null) Text(problem, style: labCell().copyWith(color: OhtliColors.xoconostle)),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: _saving || problem != null ? null : _save, child: const Text('Guardar accesos')),
                TextButton(
                  onPressed: _saving ? null : () => setState(() {
                    _iam = Map.of(widget.own);
                    _dirty = false;
                  }),
                  child: const Text('Descartar'),
                ),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}

/// Compartir con otros proyectos (importable por sus estudios), como compartir un recurso entre
/// proyectos en GCP. Solo el propietario; nunca si es clasificado.
class LabSharedCard extends StatelessWidget {
  final LabResourceKind kind;
  final String id;
  final String? projectId;
  final bool shared;
  final bool confidential;
  final bool canManage;
  final Map<String, dynamic> seed;
  const LabSharedCard({
    super.key,
    required this.kind,
    required this.id,
    required this.shared,
    required this.canManage,
    this.projectId,
    this.confidential = false,
    this.seed = const {},
  });

  @override
  Widget build(BuildContext context) => LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Liberación', style: _h(16)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: shared && !confidential,
            onChanged: !canManage || confidential
                ? null
                : (v) => runLabAction(context, () => _repo.setShared(kind, id, v, projectId: projectId, seed: seed),
                    ok: v ? 'Ahora otros proyectos pueden usarlo en sus estudios.' : 'Ya no se comparte.'),
            title: const Text('Compartir con otros proyectos'),
            subtitle: Text(confidential
                ? 'Es clasificado: no se puede compartir hasta que el proyecto se desclasifique.'
                : 'Los estudios de otros proyectos podrán importarlo. Sigue perteneciendo a este proyecto.'),
          ),
          if (!canManage) Text('Solo el propietario puede cambiarlo.', style: labCell()),
        ]),
      );
}

/// Filas de datos de solo lectura (estado, origen, claves).
class LabFactsCard extends StatelessWidget {
  final String title;
  final List<(String, String)> facts;
  final List<Widget> actions;
  const LabFactsCard({super.key, required this.title, required this.facts, this.actions = const []});

  @override
  Widget build(BuildContext context) => LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _h(16)),
          const SizedBox(height: 8),
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 150, child: Text(f.$1, style: labCell(bold: true))),
                Expanded(child: Text(f.$2, style: labCell())),
              ]),
            ),
          if (actions.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 8, runSpacing: 8, children: actions)],
        ]),
      );
}

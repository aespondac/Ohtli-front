import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../research/lab_iam.dart';
import '../research/lab_models.dart';

/// Proyectos que coinciden con la búsqueda: por nombre visible, nombre en clave o id. En los
/// confidenciales el nombre visible ya es "Proyecto `Codename`", así que el nombre real nunca entra
/// en la búsqueda.
List<LabProject> filterProjects(List<LabProject> projects, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return projects;
  return [
    for (final p in projects)
      if (p.name.toLowerCase().contains(q) || p.id.toLowerCase().contains(q) || (p.codename ?? '').toLowerCase().contains(q)) p,
  ];
}

/// Recientes primero (en su orden) y después el resto por nombre.
List<LabProject> orderProjects(List<LabProject> projects, List<String> recent) {
  final byId = {for (final p in projects) p.id: p};
  final first = [for (final id in recent) ?byId[id]];
  final rest = [for (final p in projects) if (!recent.contains(p.id)) p]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [...first, ...rest];
}

/// Botón de la barra superior con el proyecto actual (como el selector de proyecto de GCP).
class LabProjectPickerButton extends StatelessWidget {
  final LabProject? project;
  final VoidCallback onTap;
  final bool compact;
  const LabProjectPickerButton({super.key, required this.project, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Tooltip(
      message: 'Cambiar de proyecto',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: BoxConstraints(maxWidth: compact ? 210 : 360),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: OhtliColors.cardBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(p?.confidential == true ? Icons.lock_outline_rounded : Icons.folder_outlined, size: 18, color: OhtliColors.stormyTeal),
            const SizedBox(width: 8),
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.name ?? 'Elige un proyecto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                if (p != null && !compact)
                  Text(p.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.robotoMono(fontSize: 10.5, color: OhtliColors.subtleText)),
              ]),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, color: OhtliColors.subtleText),
          ]),
        ),
      ),
    );
  }
}

/// Resultado del selector: un proyecto o "crear uno nuevo".
sealed class LabPickerResult {}

class LabPickedProject extends LabPickerResult {
  final String id;
  LabPickedProject(this.id);
}

class LabCreateProject extends LabPickerResult {}

/// Diálogo de selección con búsqueda, recientes y "Crear proyecto". [roleOf] da el rol de la
/// persona en cada proyecto (se muestra como en GCP).
Future<LabPickerResult?> showLabProjectPicker(
  BuildContext context, {
  required List<LabProject> projects,
  required List<String> recent,
  required String? currentId,
  required LabIamRole Function(LabProject) roleOf,
  bool canCreate = true,
}) {
  final fullScreen = MediaQuery.of(context).size.width < 600;
  final picker = LabProjectPicker(
    projects: projects,
    recent: recent,
    currentId: currentId,
    roleOf: roleOf,
    canCreate: canCreate,
  );
  return showDialog<LabPickerResult>(
    context: context,
    builder: (c) => fullScreen
        ? Dialog.fullscreen(backgroundColor: OhtliColors.cardBg, child: picker)
        : Dialog(
            backgroundColor: OhtliColors.cardBg,
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560), child: picker),
          ),
  );
}

class LabProjectPicker extends StatefulWidget {
  final List<LabProject> projects;
  final List<String> recent;
  final String? currentId;
  final LabIamRole Function(LabProject) roleOf;
  final bool canCreate;
  const LabProjectPicker({
    super.key,
    required this.projects,
    required this.recent,
    required this.currentId,
    required this.roleOf,
    this.canCreate = true,
  });

  @override
  State<LabProjectPicker> createState() => _LabProjectPickerState();
}

class _LabProjectPickerState extends State<LabProjectPicker> {
  final _query = TextEditingController();
  bool _onlyRecent = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _onlyRecent ? [for (final p in widget.projects) if (widget.recent.contains(p.id)) p] : widget.projects;
    final list = orderProjects(filterProjects(base, _query.text), widget.recent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Selecciona un proyecto', style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w800, color: OhtliColors.onyx))),
          if (widget.canCreate)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, LabCreateProject()),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Crear proyecto'),
            ),
          IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _query,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Buscar por nombre, nombre en clave o id',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Todos'), selected: !_onlyRecent, onSelected: (_) => setState(() => _onlyRecent = false)),
          ChoiceChip(label: const Text('Recientes'), selected: _onlyRecent, onSelected: (_) => setState(() => _onlyRecent = true)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(_onlyRecent ? 'Aún no has abierto proyectos.' : 'Ningún proyecto coincide.', style: GoogleFonts.inter(color: OhtliColors.subtleText)))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: OhtliColors.cardBorder),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final current = p.id == widget.currentId;
                    final role = widget.roleOf(p);
                    return ListTile(
                      key: ValueKey('project-${p.id}'),
                      selected: current,
                      selectedTileColor: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                      leading: Icon(p.confidential ? Icons.lock_outline_rounded : Icons.folder_outlined, color: OhtliColors.stormyTeal),
                      title: Row(children: [
                        Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: OhtliColors.onyx))),
                        if (p.confidential) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: OhtliColors.xoconostle.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                            child: Text('Confidencial', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: OhtliColors.xoconostle)),
                          ),
                        ],
                      ]),
                      subtitle: Text(p.id, style: GoogleFonts.robotoMono(fontSize: 11, color: OhtliColors.subtleText)),
                      trailing: Text(role.label, style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
                      onTap: () => Navigator.pop(context, LabPickedProject(p.id)),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

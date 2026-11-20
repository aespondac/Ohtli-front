import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/lab/experiments/agents_experiment_page.dart';
import '../screens/lab/experiments/affinity_validation_experiment_page.dart';
import '../screens/lab/experiments/apis_experiment_page.dart';
import '../screens/lab/experiments/osrm_experiment_page.dart';
import '../screens/lab/experiments/recolector_experiment_page.dart';
import '../screens/lab/experiments/taste_vector_experiment_page.dart';
import '../theme/colors.dart';
import '../widgets/ohtli_account_chip.dart';
import '../widgets/ohtli_theme_toggle.dart';
import 'lab_access.dart';
import 'lab_catalog.dart';
import 'lab_eval_page.dart';
import 'lab_experiments.dart';
import 'lab_publishing.dart';
import 'lab_widgets.dart';
import 'labs_top_bar.dart';
import 'research/lab_iam.dart';
import 'research/lab_models.dart';
import 'research/lab_research_repository.dart';
import 'research/research_console.dart';
import 'research/research_papers.dart';
import 'research/research_participate.dart';
import 'shell/lab_location.dart';
import 'shell/lab_location_store.dart';
import 'shell/lab_project_picker.dart';
import 'shell/lab_project_views.dart';
import 'shell/lab_resource_pages.dart';

/// Ohtli Labs con sesión, al estilo de la consola de GCP: arriba se elige el proyecto y el menú
/// lateral da acceso a sus estudios, experimentos, encuestas y funcionalidades; la gestión (IAM,
/// estado, liberación, bitácora, revisiones) vive en la Configuración de cada recurso.
///
///  - Miembros del laboratorio: la consola por proyectos, más Laboratorio (todos los proyectos,
///    revisiones, artículos, miembros) y Participa.
///  - Testers: Participa (estudios y encuestas abiertos, resultados) y los experimentos, sin selector.
///  - Revisores invitados: sus revisiones y los resultados liberados.
///
/// La ubicación es una clave de [LabLocation] (`p:<proyecto>/<área>/<recurso>/<pestaña>` o una
/// sección global) y se guarda en la URL (`?r=`) con [LabLocationStore].
class LabsAppPage extends StatefulWidget {
  final String? initialSection;
  final VoidCallback onSignOut;
  final VoidCallback onOpenTerms;
  const LabsAppPage({super.key, this.initialSection, required this.onSignOut, required this.onOpenTerms});

  /// La ubicación pedida tiene sentido para el rol; si no, la de inicio del rol. Acepta también las
  /// claves del menú anterior (`exp:`, `study:`, `sma`, `studies`, …) y las lleva a su proyecto.
  static String validSection(String? section, LabRole role, {String? lastProjectId}) =>
      LabLocation.resolve(section, role, lastProjectId: lastProjectId).toKey();

  @override
  State<LabsAppPage> createState() => _LabsAppPageState();
}

class _NavEntry {
  final String key;
  final IconData icon;
  final String label;
  final String? badge;
  final Color? badgeColor;
  const _NavEntry(this.key, this.icon, this.label, {this.badge, this.badgeColor});
}

/// Proyectos base aunque su documento todavía no exista (el admin los crea al abrir Estudios).
final _baseProjects = [
  const LabProject(
    id: kPlatformProjectId,
    name: kPlatformProjectName,
    description: 'Experimentos de la plataforma y funcionalidades del sistema multiagente.',
    iam: {kLabAllMembers: 'viewer'},
  ),
  const LabProject(
    id: kTtProjectId,
    name: kTtProjectName,
    description: 'Pruebas del capítulo 6 del Trabajo Terminal 2026-B156.',
    iam: {kLabAllMembers: 'editor'},
  ),
];

/// Funcionalidades del sistema con tablero propio (se dividen en la fase 4).
const _platformModules = [
  ('sma', 'Sistema multiagente', 'Éxito de las recomendaciones (Agente Crítico), políticas que aprenden, categorías emergentes y mensajes entre agentes.'),
];

/// Vistas que siguen vivas al cambiar de sección (para no cortar una corrida ni perder lo escrito).
const _kMaxAliveViews = 14;

class _LabsAppPageState extends State<LabsAppPage> {
  final LabLocationStore _store = LabLocationStore.create();
  LabRole _role = LabRole.none;
  bool _loaded = false;
  String? _roleError;
  late String _section;
  final List<String> _visited = [];
  List<LabProject> _projects = const [];
  bool _projectsLoaded = false;
  StreamSubscription<List<LabProject>>? _projectsSub;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? _store.initialKey ?? '';
    _load();
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    LabRole r;
    try {
      r = await LabAccess.roleOf(FirebaseAuth.instance.currentUser);
    } catch (e) {
      if (mounted) setState(() => _roleError = '$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _role = r;
      _roleError = null;
      _loaded = true;
      _section = _resolve(_section);
    });
    if (r.isMember) {
      _projectsSub?.cancel();
      _projectsSub = LabResearch.instance.watchProjects().listen((list) {
        if (!mounted) return;
        setState(() {
          _projects = list;
          _projectsLoaded = true;
        });
        _checkProjectAccess();
      }, onError: (_) {
        if (mounted) setState(() => _projectsLoaded = true);
      });
    }
  }

  String _resolve(String? key) => LabsAppPage.validSection(key, _role, lastProjectId: _store.lastProjectId);

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _go(String key) {
    final next = _resolve(key);
    setState(() => _section = next);
    _store.save(next, projectId: LabLocation.parse(next)?.projectId);
    // En móvil el menú es un panel que se cierra al elegir.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) _scaffoldKey.currentState!.closeDrawer();
  }

  /// Proyectos que la persona ve (rol de Lector o más), con los base aunque no existan todavía.
  List<LabProject> get _visibleProjects {
    final byId = {for (final p in _baseProjects) p.id: p, for (final p in _projects) p.id: p};
    return [
      for (final p in byId.values)
        if (projectRoleOf(p, uid: _uid, labRole: _role).canView) p,
    ];
  }

  LabProject? _projectById(String? id) {
    for (final p in _visibleProjects) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Un proyecto inexistente o sin acceso (p. ej. un enlace viejo) lleva a "Todos los proyectos".
  void _checkProjectAccess() {
    final loc = LabLocation.parse(_section);
    if (loc == null || !loc.inProject || _projectById(loc.projectId) != null) return;
    _go('projects');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No tienes acceso a ese proyecto o ya no existe.')),
      );
    });
  }

  /// Proyecto del menú: el de la ubicación o, en las secciones globales, el último abierto.
  LabProject? get _navProject {
    final loc = LabLocation.parse(_section);
    return _projectById(loc?.projectId ?? _store.lastProjectId) ?? _projectById(kPlatformProjectId);
  }

  Future<void> _pickProject() async {
    final result = await showLabProjectPicker(
      context,
      projects: _visibleProjects,
      recent: _store.recentProjects,
      currentId: _navProject?.id,
      roleOf: (p) => projectRoleOf(p, uid: _uid, labRole: _role),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case LabPickedProject(:final id):
        _go(LabLocation.project(id, LabArea.overview).toKey());
      case LabCreateProject():
        final id = await showCreateProjectDialog(context);
        if (id != null && mounted) _go(LabLocation.project(id, LabArea.overview).toKey());
    }
  }

  List<(String, List<_NavEntry>)> _groups() {
    if (_role.isReviewer) {
      return const [
        ('REVISIÓN EXTERNA', [
          _NavEntry('reviews', Icons.rate_review_outlined, 'Tus revisiones'),
          _NavEntry('resultados', Icons.article_outlined, 'Resultados liberados'),
        ]),
      ];
    }
    const participa = ('PARTICIPA', [
      _NavEntry('participa', Icons.how_to_reg_rounded, 'Estudios abiertos'),
      _NavEntry('encuestas', Icons.ballot_outlined, 'Encuestas abiertas'),
      _NavEntry('resultados', Icons.article_outlined, 'Resultados liberados'),
    ]);
    if (!_role.isMember) {
      return [
        participa,
        ('EXPERIMENTOS', [
          for (final e in kLabExperiments) _NavEntry('exp:${e.id}', e.icon, e.title, badge: e.status, badgeColor: e.statusColor),
        ]),
      ];
    }
    final p = _navProject;
    String k(LabArea a) => LabLocation.project(p!.id, a).toKey();
    return [
      if (p != null)
        ('PROYECTO', [
          _NavEntry(k(LabArea.overview), Icons.dashboard_outlined, LabArea.overview.label),
          _NavEntry(k(LabArea.studies), Icons.biotech_outlined, LabArea.studies.label),
          _NavEntry(k(LabArea.experiments), Icons.science_outlined, LabArea.experiments.label),
          _NavEntry(k(LabArea.surveys), Icons.ballot_outlined, LabArea.surveys.label),
          _NavEntry(k(LabArea.functionalities), Icons.toggle_on_outlined, LabArea.functionalities.label),
          _NavEntry(k(LabArea.settings), Icons.settings_outlined, LabArea.settings.label),
        ]),
      ('LABORATORIO', [
        const _NavEntry('projects', Icons.folder_copy_outlined, 'Todos los proyectos'),
        const _NavEntry('reviews', Icons.rate_review_outlined, 'Revisiones'),
        const _NavEntry('posts', Icons.edit_note_rounded, 'Artículos y blog'),
        if (_role == LabRole.admin) const _NavEntry('members', Icons.manage_accounts_outlined, 'Miembros del laboratorio'),
      ]),
      participa,
    ];
  }

  /// Entrada del menú que queda marcada: el área del proyecto (aunque se esté dentro de un recurso).
  String get _navSelected {
    final loc = LabLocation.parse(_section);
    if (loc == null || !loc.inProject) return _section;
    return LabLocation.project(loc.projectId!, loc.area!).toKey();
  }

  String _titleOf(String section) {
    final loc = LabLocation.parse(section);
    if (loc != null && loc.inProject) {
      final res = loc.resourceId;
      if (res != null && loc.area == LabArea.experiments) return builtinExperimentById(res)?.title ?? LabArea.experiments.label;
      if (res != null && loc.area == LabArea.surveys) return builtinSurveyById(res)?.title ?? LabArea.surveys.label;
      return loc.area!.label;
    }
    for (final g in _groups()) {
      for (final e in g.$2) {
        if (e.key == section) return e.label;
      }
    }
    if (section.startsWith('exp:')) return experimentById(section.substring(4))?.title ?? 'Ohtli Labs';
    return 'Ohtli Labs';
  }

  /// Clave con la que se conserva viva una vista: sin la pestaña.
  String _aliveKey(String section) => LabLocation.parse(section)?.withoutTab.toKey() ?? section;

  /// Las pruebas del TT pueden tardar minutos: su vista nunca se descarta.
  bool _isRunner(String key) {
    final loc = LabLocation.parse(key);
    return loc != null && loc.area == LabArea.experiments && builtinExperimentById(loc.resourceId ?? '')?.ttRunner != null;
  }

  @override
  Widget build(BuildContext context) {
    currentLabRole = _role;
    final isMobile = MediaQuery.of(context).size.width < 900;
    if (_roleError != null) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: _topBar(isMobile: isMobile, title: 'Ohtli Labs', withMenu: false),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: LabCard(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('No pudimos verificar tu acceso a Labs',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                  const SizedBox(height: 8),
                  Text('Revisa tu conexión e inténtalo de nuevo.', style: labCell()),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _roleError = null);
                      _load();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    if (!_loaded) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
      );
    }

    // Sin rol todavía: un solo consentimiento para todo Labs.
    if (_role == LabRole.none) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: _topBar(isMobile: isMobile, title: 'Ohtli Labs', withMenu: false),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: LabConsentCard(
                onOpenTerms: widget.onOpenTerms,
                onAccepted: () => setState(() {
                  _role = LabRole.tester;
                  _section = 'participa';
                }),
              ),
            ),
          ),
        ),
      );
    }

    final alive = _aliveKey(_section);
    if (!_visited.contains(alive)) {
      _visited.add(alive);
      while (_visited.length > _kMaxAliveViews) {
        final victim = _visited.firstWhere((k) => k != alive && !_isRunner(k), orElse: () => '');
        if (victim.isEmpty) break;
        _visited.remove(victim);
      }
    }
    final content = IndexedStack(
      index: _visited.indexOf(alive),
      sizing: StackFit.expand,
      children: [
        for (final s in _visited) KeyedSubtree(key: ValueKey(s), child: _content(s == alive ? _section : s, isMobile)),
      ],
    );

    final nav = _Sidebar(groups: _groups(), selected: _navSelected, onSelect: _go);
    if (isMobile) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: OhtliColors.cloudDancer,
        appBar: _topBar(isMobile: true, title: _titleOf(_section), withMenu: true),
        drawer: Drawer(width: 300, backgroundColor: OhtliColors.cardBg, child: SafeArea(child: nav)),
        body: content,
      );
    }
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 272, child: nav),
        Expanded(
          child: Column(children: [
            _topBar(isMobile: false, title: _titleOf(_section), withMenu: false),
            Expanded(child: content),
          ]),
        ),
      ]),
    );
  }

  PreferredSizeWidget _topBar({required bool isMobile, required String title, required bool withMenu}) {
    final picker = _role.isMember && _loaded
        ? LabProjectPickerButton(project: _navProject, onTap: _pickProject, compact: isMobile)
        : null;
    final titleText = Text(title,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(fontSize: isMobile ? 17 : 19, fontWeight: FontWeight.w800, color: OhtliColors.onyx));
    return AppBar(
      backgroundColor: OhtliColors.cardBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: withMenu
          ? Builder(
              builder: (context) => IconButton(
                tooltip: 'Menú de Labs',
                icon: Icon(Icons.menu_rounded, color: OhtliColors.onyx),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          : null,
      titleSpacing: withMenu ? 0 : 24,
      // En móvil solo cabe el selector; en escritorio, selector y título (como GCP).
      title: picker == null
          ? titleText
          : (isMobile
              ? Align(alignment: Alignment.centerLeft, child: picker)
              : Row(children: [picker, const SizedBox(width: 16), Flexible(child: titleText)])),
      shape: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
      actions: [
        const OhtliThemeToggle(),
        const SizedBox(width: 8),
        OhtliAccountChip(compact: isMobile, onSignOut: () async => widget.onSignOut()),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _scroll(Widget child, {double maxWidth = 1100}) => Builder(builder: (context) {
        final isMobile = MediaQuery.of(context).size.width < 900;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(isMobile ? 16 : 28, 20, isMobile ? 16 : 28, 40),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
          ),
        );
      });

  Widget _content(String section, bool isMobile) {
    final loc = LabLocation.parse(section);
    if (loc != null && loc.inProject) return _projectContent(loc, isMobile);
    if (section == 'participa') {
      // Solo estudios: las encuestas (relevancia, SUS, calibración) tienen su propia sección.
      return _scroll(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabParticipantHeader(
            title: 'Estudios abiertos',
            caption: 'Inscríbete en un estudio para usar sus funciones en prueba y responder sus encuestas.',
            role: _role,
            onLeft: () => setState(() => _role = LabRole.none),
          ),
          const SizedBox(height: 12),
          LabOpenStudiesView(
            showTitle: false,
            emptyState: LabCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Por ahora ningún estudio está reclutando participantes.', style: labCell(bold: true)),
                const SizedBox(height: 4),
                Text('Mientras, puedes ayudarnos respondiendo las encuestas abiertas.', style: labCell()),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _go('encuestas'),
                  icon: const Icon(Icons.ballot_outlined, size: 18),
                  label: const Text('Ver encuestas abiertas'),
                ),
              ]),
            ),
          ),
        ]),
        maxWidth: 820,
      );
    }
    if (section == 'encuestas') {
      return _scroll(
        LabOpenSurveysView(
          role: _role,
          onLeft: () => setState(() => _role = LabRole.none),
          onOpenExperiment: (id) => _go('exp:$id'),
        ),
        maxWidth: 820,
      );
    }
    if (section == 'projects') {
      return _scroll(LabProjectsPanel(role: _role, onOpen: (id) => _go(LabLocation.project(id, LabArea.overview).toKey())));
    }
    if (section == 'reviews') return _scroll(LabReviewsPanel(role: _role));
    if (section == 'resultados') return _scroll(const LabReleasedView(), maxWidth: 820);
    if (section == 'posts') return _scroll(LabPostsPanel(role: _role));
    if (section == 'members') return _scroll(const LabMembersPanel());
    if (section.startsWith('exp:')) {
      final e = experimentById(section.substring(4));
      if (e != null) return _embeddedExperiment(e, isMobile, back: () => _go('participa'));
    }
    return _scroll(LabCard(child: Text('Esta sección no existe.', style: labCell())));
  }

  Widget _projectContent(LabLocation loc, bool isMobile) {
    final project = _projectById(loc.projectId);
    if (project == null) {
      return _projectsLoaded
          ? _scroll(LabCard(child: Text('No tienes acceso a este proyecto o ya no existe.', style: labCell())))
          : const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
    }
    final role = projectRoleOf(project, uid: _uid, labRole: _role);
    final pid = project.id;
    String key(LabArea a, [String? res, String? tab]) => LabLocation.project(pid, a, resourceId: res, tab: tab).toKey();
    final res = loc.resourceId;
    final ctx = LabPageCtx(project: project, labRole: _role, uid: _uid, tab: loc.tab, go: _go);
    switch (loc.area!) {
      case LabArea.overview:
        return _scroll(LabProjectOverview(project: project, role: role, onGo: (a) => _go(key(a))));
      case LabArea.studies:
        if (res != null) return _scroll(LabStudyPage(ctx: ctx, studyId: res));
        return _scroll(LabStudiesPanel(key: ValueKey('studies-$pid'), role: _role, project: project, onOpen: (id) => _go(key(LabArea.studies, id))));
      case LabArea.experiments:
        if (res != null) {
          final page = builtinExperimentById(res)?.page;
          // Los integrados con pantalla propia ocupan todo el alto; el resto va en scroll.
          if (page != null) {
            return LabExperimentPage(
              ctx: ctx,
              experimentId: res,
              ownPage: () => LabEmbedded(child: _experimentPage(page.id, () => _go(key(LabArea.experiments)))),
            );
          }
          return _scroll(LabExperimentPage(ctx: ctx, experimentId: res));
        }
        return _scroll(LabLibraryPanel(project: project, onOpen: (id) => _go(key(LabArea.experiments, id))));
      case LabArea.surveys:
        if (res != null) return _scroll(LabSurveyPage(ctx: ctx, surveyId: res));
        return _scroll(LabSurveysPanel(project: project, onOpen: (id) => _go(key(LabArea.surveys, id))));
      case LabArea.functionalities:
        if (res != null) return _scroll(LabFunctionalityPage(ctx: ctx, functionalityId: res));
        return _scroll(LabFeaturesPanel(
          role: _role,
          projectId: pid,
          modules: pid == kPlatformProjectId ? _platformModules : const [],
          onOpen: (id) => _go(key(LabArea.functionalities, id)),
        ));
      case LabArea.settings:
        return _scroll(LabProjectSettings(
          project: project,
          role: role,
          labRole: _role,
          section: res ?? 'general',
          onSection: (s) => _go(key(LabArea.settings, s)),
          onOpenStudy: (id, tab) => _go(key(LabArea.studies, id, tab)),
        ));
    }
  }

  Widget _embeddedExperiment(LabExperiment e, bool isMobile, {required VoidCallback back}) => LabEmbedded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ExperimentHeader(experiment: e, isMobile: isMobile),
          Expanded(child: _experimentPage(e.id, back)),
        ]),
      );

  Widget _experimentPage(String id, VoidCallback back) {
    return switch (id) {
      'recolector' => RecolectorExperimentPage(onBack: back),
      'taste' => TasteVectorExperimentPage(onBack: back),
      'osrm' => OsrmExperimentPage(onBack: back),
      'agents' => AgentsExperimentPage(onBack: back),
      'afinidad' => AffinityValidationExperimentPage(onBack: back),
      _ => ApisExperimentPage(onBack: back),
    };
  }
}

/// Encabezado común de cada experimento (mismo nombre y estado que en la portada pública).
class _ExperimentHeader extends StatelessWidget {
  final LabExperiment experiment;
  final bool isMobile;
  const _ExperimentHeader({required this.experiment, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final e = experiment;
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 28, 20, isMobile ? 16 : 28, 8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: e.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(e.icon, color: e.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(e.category, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: OhtliColors.subtleText)),
                  _Badge(text: e.status, color: e.statusColor),
                ]),
                const SizedBox(height: 4),
                Text(e.description, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45)),
                const SizedBox(height: 2),
                Text('Experimental: puede fallar o cambiar sin aviso.',
                    style: GoogleFonts.inter(fontSize: 11.5, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: color)),
      );
}

/// Menú lateral de Labs: grupos con encabezado y elementos con icono, como el menú de Ohtli.
class _Sidebar extends StatelessWidget {
  final List<(String, List<_NavEntry>)> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  const _Sidebar({required this.groups, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        border: Border(right: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Marca: lleva a la portada pública de Labs.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
          child: InkWell(
            onTap: () => LabsTopBar.go(LabsSection.home),
            borderRadius: BorderRadius.circular(10),
            child: Row(children: [
              SvgPicture.asset('assets/logo.svg', height: 22, colorFilter: ColorFilter.mode(OhtliColors.onyx, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(8)),
                child: Text('LABS', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white)),
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            children: [
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Text(g.$1,
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: OhtliColors.subtleText)),
                ),
                for (final e in g.$2) _item(e),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: OhtliColors.cardBorder),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: () => LabsTopBar.go(LabsSection.news),
              icon: const Icon(Icons.public_rounded, size: 16),
              label: const Text('Noticias de Labs'),
            ),
            TextButton.icon(
              onPressed: () => LabsTopBar.go(LabsSection.home),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('labs.ohtli.quest'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _item(_NavEntry e) {
    final active = e.key == selected;
    final color = active ? OhtliColors.stormyTeal : OhtliColors.onyx.withValues(alpha: 0.75);
    return Semantics(
      button: true,
      selected: active,
      label: e.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: active ? OhtliColors.stormyTeal.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => onSelect(e.key),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(e.icon, size: 19, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, height: 1.3, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
                ),
                // Estado del experimento como punto (el nombre completo cabe); el texto en el tooltip
                // y en el encabezado del experimento.
                if (e.badge != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: e.badge!,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: e.badgeColor ?? OhtliColors.subtleText, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

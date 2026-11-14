import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/ohtli_sso.dart';
import '../theme/colors.dart';
import 'lab_access.dart';
import 'lab_article.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';
import 'labs_top_bar.dart';

/// lab.ohtli.quest/eval — entrada pública para testers de los estudios que lo requieren.
/// También es el espacio de testers en lab.ohtli.quest: alta como tester, estudios abiertos y
/// resultados liberados para testers.
class LabEvalPage extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onOpenTerms;
  final VoidCallback? onOpenConsole;
  final VoidCallback? onOpenTechnical;
  const LabEvalPage({super.key, required this.onLogin, required this.onOpenTerms, this.onOpenConsole, this.onOpenTechnical});

  @override
  State<LabEvalPage> createState() => _LabEvalPageState();
}

class _LabEvalPageState extends State<LabEvalPage> {
  bool _consent = false;
  String? _studyId;
  Map<String, dynamic>? _post;
  LabRole _role = LabRole.none;
  bool _roleLoaded = false;
  // Se crean al mostrarse por primera vez y no en cada build: si no, cada redibujo
  // (girar el móvil, cambiar el tamaño) volvía a suscribirse y mostraba el spinner.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _releasedPosts =
      LabRepository.instance.watchPublishedPosts([LabVisibility.testers, LabVisibility.public]);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeStudies =
      LabRepository.instance.studies.where('active', isEqualTo: true).snapshots();

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final r = await LabAccess.roleOf(FirebaseAuth.instance.currentUser);
    if (mounted) {
      setState(() {
        _role = r;
        _roleLoaded = true;
        if (r.isTester) _consent = true; // ya aceptó al unirse
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isMobile = MediaQuery.of(context).size.width < 700;
    Widget body;
    if (user == null) {
      body = _intro(signedIn: false);
    } else if (!_roleLoaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_consent) {
      body = _consentCard();
    } else if (_post != null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(onPressed: () => setState(() => _post = null), icon: const Icon(Icons.arrow_back), label: const Text('Volver')),
        LabCard(padding: const EdgeInsets.all(28), child: LabArticleView(post: _post!)),
      ]);
    } else if (_studyId == null) {
      body = Column(children: [_hubHeader(), const SizedBox(height: 12), _studyPicker(), const SizedBox(height: 12), _released()]);
    } else if (_studyId == 'sus') {
      body = _SusFlow(onDone: () => setState(() => _studyId = null));
    } else {
      body = _RelevanceFlow(onDone: () => setState(() => _studyId = null));
    }
    Future<void> signOut() async {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        _consent = false;
        _studyId = null;
        _role = LabRole.none;
      });
    }

    final showConsole = _role.isMember && widget.onOpenConsole != null;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: LabsTopBar(
        current: LabsSection.participate,
        trailing: user == null
            ? null
            : MediaQuery.of(context).size.width < 820 // mismo corte que LabsTopBar
                ? PopupMenuButton<String>(
                    tooltip: 'Tu cuenta',
                    icon: Icon(Icons.account_circle_outlined, color: OhtliColors.onyx),
                    onSelected: (v) {
                      if (v == 'console') widget.onOpenConsole?.call();
                      if (v == 'technical') widget.onOpenTechnical?.call();
                      if (v == 'signout') signOut();
                    },
                    itemBuilder: (_) => [
                      if (showConsole) const PopupMenuItem(value: 'console', child: Text('Consola')),
                      if (widget.onOpenTechnical != null) const PopupMenuItem(value: 'technical', child: Text('Experimentos')),
                      const PopupMenuItem(value: 'signout', child: Text('Salir')),
                    ],
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: [
                if (showConsole)
                  TextButton.icon(onPressed: widget.onOpenConsole, icon: const Icon(Icons.biotech_rounded, size: 16), label: const Text('Consola')),
                if (widget.onOpenTechnical != null) TextButton(onPressed: widget.onOpenTechnical, child: const Text('Experimentos')),
                TextButton(onPressed: signOut, child: const Text('Salir')),
              ]),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: body)),
      ),
    );
  }

  Widget _intro({required bool signedIn}) => LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ayúdanos a evaluar Ohtli', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 8),
          Text(
            'Ohtli es un planificador de itinerarios turísticos para la Ciudad de México desarrollado como Trabajo Terminal '
            'en ESCOM-IPN. Buscamos personas que prueben la aplicación y califiquen sus recomendaciones. '
            'Toma entre 5 y 15 minutos y tus respuestas se usan de forma anónima y solo con fines académicos.',
            style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText, height: 1.5),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: widget.onLogin,
            icon: const Icon(Icons.login_rounded),
            // En labs/lab.ohtli.quest la sesión llega por SSO con la cuenta de ohtli.quest: si ya
            // la tienes abierta allá, no hay que "iniciar sesión" de nuevo, solo continuar con ella.
            label: Text(OhtliSso.isSubdomain ? 'Continuar con tu cuenta de Ohtli' : 'Iniciar sesión para participar'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
          const SizedBox(height: 8),
          Text('Usamos tu cuenta solo para evitar respuestas duplicadas; tu nombre y correo no se guardan con las respuestas.',
              style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
        ]),
      );

  Widget _consentCard() => LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('Consentimiento informado'),
          for (final t in [
            'Participo de forma voluntaria y puedo dejar el estudio en cualquier momento.',
            'Mis respuestas se guardan sin nombre ni correo, ligadas a un identificador interno de la cuenta para evitar duplicados.',
            'Los resultados agregados pueden publicarse en el Trabajo Terminal y en labs.ohtli.quest.',
            'No se me pedirán datos sensibles ni de pago.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle_outline, size: 16, color: OhtliColors.stormyTeal),
                const SizedBox(width: 8),
                Expanded(child: Text(t, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx, height: 1.4))),
              ]),
            ),
          TextButton(onPressed: widget.onOpenTerms, child: const Text('Leer los términos de Ohtli Labs')),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              final u = FirebaseAuth.instance.currentUser;
              if (u == null) return;
              if (!_role.isTester) await LabAccess.joinAsTester(u);
              setState(() {
                _consent = true;
                if (!_role.isTester) _role = LabRole.tester;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            child: const Text('Acepto y me uno como tester'),
          ),
        ]),
      );

  Widget _hubHeader() => LabCard(
        child: Row(children: [
          const Icon(Icons.verified_user_outlined, color: OhtliColors.stormyTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Espacio de testers', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              Text('Tu rol: ${_role.label}. Aquí participas en estudios y ves los resultados que el laboratorio libera para testers.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
            ]),
          ),
          if (_role == LabRole.tester)
            TextButton(
              onPressed: () async {
                final u = FirebaseAuth.instance.currentUser;
                if (u == null) return;
                await LabAccess.leave(u);
                setState(() {
                  _role = LabRole.none;
                  _consent = false;
                });
              },
              child: const Text('Dejar de ser tester'),
            ),
        ]),
      );

  Widget _released() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _releasedPosts,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return LabCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const LabSectionTitle('Resultados liberados', caption: 'Artículos del laboratorio disponibles para testers.'),
            if (snap.hasError && docs.isEmpty)
              Text('No pudimos cargar los resultados. Recarga la página para intentar de nuevo.', style: labCell())
            else if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (docs.isEmpty)
              Text('Todavía no hay resultados liberados.', style: labCell()),
            for (final d in docs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(LabVisibility.icon(LabVisibility.of(d.data())), color: OhtliColors.stormyTeal),
                title: Text('${d.data()['title']}', style: labCell(bold: true)),
                subtitle: Text('${fmtDate(d.data()['publishedAt'])} · ${LabVisibility.label(LabVisibility.of(d.data()))}', style: labCell()),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() => _post = d.data()),
              ),
          ]),
        );
      },
    );
  }

  Widget _studyPicker() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeStudies,
      builder: (context, snap) {
        final active = snap.data?.docs.map((d) => d.id).toSet() ?? {};
        final list = kLabStudies.where((s) => s.needsTesters && active.contains(s.id)).toList();
        if (snap.hasError && !snap.hasData) {
          return LabCard(child: Text('No pudimos cargar los estudios. Recarga la página para intentar de nuevo.', style: labCell()));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (list.isEmpty) {
          return LabCard(child: Text('Por ahora no hay estudios abiertos. ¡Gracias por tu interés!', style: labCell()));
        }
        return Column(children: [
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LabCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.kind == LabStudyKind.sus ? 'Prueba la app y cuéntanos (10–15 min)' : 'Califica recomendaciones (5 min)',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                  const SizedBox(height: 6),
                  Text(
                    s.kind == LabStudyKind.sus
                        ? 'Realiza cuatro tareas en ohtli.quest y responde un cuestionario corto de usabilidad.'
                        : 'Te mostramos itinerarios generados por Ohtli y calificas qué tan bien encaja cada lugar con la intención del viaje.',
                    style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() => _studyId = s.id),
                    style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
                    child: const Text('Comenzar'),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class _Likert extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  final String low;
  final String high;
  const _Likert({required this.value, required this.onChanged, this.low = 'Totalmente en desacuerdo', this.high = 'Totalmente de acuerdo'});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, children: [
          for (var i = 1; i <= 5; i++)
            ChoiceChip(
              label: Text('$i'),
              selected: value == i,
              selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.25),
              onSelected: (_) => onChanged(i),
            ),
        ]),
        Text('1 = $low · 5 = $high', style: GoogleFonts.inter(fontSize: 10.5, color: OhtliColors.subtleText)),
      ]);
}

class _SusFlow extends StatefulWidget {
  final VoidCallback onDone;
  const _SusFlow({required this.onDone});

  @override
  State<_SusFlow> createState() => _SusFlowState();
}

class _SusFlowState extends State<_SusFlow> {
  final List<int?> _sus = List.filled(10, null);
  final List<int?> _sat = List.filled(kSatisfactionItems.length, null);
  final List<String?> _tasks = List.filled(kSusTasks.length, null);
  String? _visitor, _age, _device;
  final _comment = TextEditingController();
  bool _sending = false, _sent = false;

  bool get _complete => !_sus.contains(null) && !_sat.contains(null) && !_tasks.contains(null) && _visitor != null;

  Future<void> _send() async {
    setState(() => _sending = true);
    await LabRepository.instance.addResponse('sus', {
      'sus': _sus,
      'satisfaction': _sat,
      'tasks': _tasks,
      'profile': {'visitor_type': _visitor, 'age_range': _age, 'device': _device},
      'comment': _comment.text.trim().substring(0, math.min(1000, _comment.text.trim().length)),
    });
    setState(() {
      _sending = false;
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return LabCard(
        child: Column(children: [
          const Icon(Icons.favorite_rounded, color: OhtliColors.cempasuchil, size: 40),
          const SizedBox(height: 8),
          Text('¡Gracias! Tus respuestas quedaron registradas.', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 12),
          TextButton(onPressed: widget.onDone, child: const Text('Volver')),
        ]),
      );
    }
    Widget drop(String label, String? v, List<String> opts, ValueChanged<String?> f) => SizedBox(
          width: 250,
          child: DropdownButtonFormField<String>(
            value: v,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: f,
          ),
        );
    return Column(children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('1. Sobre ti'),
          Wrap(spacing: 12, runSpacing: 12, children: [
            drop('Tipo de visitante', _visitor, ['Residente de la CDMX', 'Turista nacional', 'Turista internacional'], (v) => setState(() => _visitor = v)),
            drop('Edad', _age, ['18–24', '25–34', '35–44', '45–59', '60 o más'], (v) => setState(() => _age = v)),
            drop('Dispositivo', _device, ['Celular', 'Computadora', 'Tableta'], (v) => setState(() => _device = v)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('2. Tareas en ohtli.quest',
              caption: 'Abre https://ohtli.quest en otra pestaña, realiza cada tarea y marca cómo te fue.'),
          for (var i = 0; i < kSusTasks.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('T${i + 1}. ${kSusTasks[i]}', style: labCell(bold: true)),
                Wrap(spacing: 6, children: [
                  for (final o in ['completada', 'con dificultad', 'no completada'])
                    ChoiceChip(label: Text(o), selected: _tasks[i] == o, onSelected: (_) => setState(() => _tasks[i] = o)),
                ]),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('3. Usabilidad (SUS)'),
          for (var i = 0; i < 10; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${kSusItems[i]}', style: labCell(bold: true)),
                _Likert(value: _sus[i], onChanged: (v) => setState(() => _sus[i] = v)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('4. Tu itinerario'),
          for (var i = 0; i < kSatisfactionItems.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kSatisfactionItems[i], style: labCell(bold: true)),
                _Likert(value: _sat[i], onChanged: (v) => setState(() => _sat[i] = v)),
              ]),
            ),
          TextField(
            controller: _comment,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Comentarios (opcional, sin datos personales)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _complete && !_sending ? _send : null,
            icon: const Icon(Icons.send_rounded),
            label: Text(_complete ? 'Enviar respuestas' : 'Responde todas las preguntas'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
        ]),
      ),
    ]);
  }
}

class _RelevanceFlow extends StatefulWidget {
  final VoidCallback onDone;
  const _RelevanceFlow({required this.onDone});

  @override
  State<_RelevanceFlow> createState() => _RelevanceFlowState();
}

class _RelevanceFlowState extends State<_RelevanceFlow> {
  String? _runId;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _seen = {};
  Map<String, dynamic>? _row;
  int _opt = 0;
  List<int?> _grades = [];
  bool _loading = true, _sending = false;
  int _count = 0;
  String? _error;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cfg = (await LabRepository.instance.studies.doc('relevancia').get()).data() ?? {};
      _runId = cfg['sourceRunId'] as String?;
      if (_runId == null) throw 'El estudio aún no tiene itinerarios asignados.';
      _rows = (await LabRepository.instance.rows(_runId!))
          .where((r) => r['status'] == 'completed' && ((r['options'] as List?) ?? []).isNotEmpty)
          .toList();
      _next();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _next() {
    final pool = <List<int>>[];
    for (var i = 0; i < _rows.length; i++) {
      final opts = (_rows[i]['options'] as List);
      for (var j = 0; j < opts.length; j++) {
        if (((opts[j] as Map)['route'] as List? ?? []).isNotEmpty && !_seen.contains('$i/$j')) pool.add([i, j]);
      }
    }
    if (pool.isEmpty) {
      _row = null;
      return;
    }
    final pick = pool[_rng.nextInt(pool.length)];
    _row = _rows[pick[0]];
    _opt = pick[1];
    _seen.add('${pick[0]}/${pick[1]}');
    _grades = List.filled(((_row!['options'] as List)[_opt]['route'] as List).length, null);
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final sc = Map<String, dynamic>.from(_row!['scenario'] as Map);
    final opt = Map<String, dynamic>.from((_row!['options'] as List)[_opt] as Map);
    await LabRepository.instance.addResponse('relevancia', {
      'runId': _runId,
      'rowIndex': _row!['index'],
      'scenarioId': sc['id'],
      'optionIndex': _opt,
      'theme': opt['theme_key'] ?? opt['theme'],
      'mood': sc['mood'],
      'poiIds': (opt['route'] as List).map((s) => (s as Map)['poi_id']).toList(),
      'grades': _grades,
    });
    setState(() {
      _sending = false;
      _count++;
      _next();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return LabCard(child: Text(_error!, style: labCell()));
    if (_row == null) {
      return LabCard(
        child: Column(children: [
          Text('¡Listo! Calificaste $_count itinerarios. Gracias.', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          TextButton(onPressed: widget.onDone, child: const Text('Volver')),
        ]),
      );
    }
    final sc = Map<String, dynamic>.from(_row!['scenario'] as Map);
    final opt = Map<String, dynamic>.from((_row!['options'] as List)[_opt] as Map);
    final route = (opt['route'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Column(children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Itinerario ${_count + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: OhtliColors.subtleText)),
          const SizedBox(height: 6),
          Text('“${sc['mood']}”', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 4),
          Text('Saliendo de ${(sc['origin'] as Map?)?['name']} · presupuesto \$${(sc['budget'] as num?)?.toStringAsFixed(0)} MXN · ${opt['theme'] ?? ''}',
              style: labCell()),
          const SizedBox(height: 8),
          Text('Califica qué tan bien encaja cada lugar con lo que busca esta persona.',
              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
        ]),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < route.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LabCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i + 1}. ${route[i]['name']}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              Text('${route[i]['category']} · ${route[i]['arrival_time']}–${route[i]['departure_time']}', style: labCell()),
              if ((route[i]['description'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    (route[i]['description'] as String).replaceAll(RegExp(r'\[EJE \d - [^\]]+\]:\s*'), '').split('\n').first,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText, height: 1.4),
                  ),
                ),
              const SizedBox(height: 8),
              _Likert(value: _grades[i], onChanged: (v) => setState(() => _grades[i] = v), low: 'Nada pertinente', high: 'Muy pertinente'),
            ]),
          ),
        ),
      Row(children: [
        ElevatedButton.icon(
          onPressed: !_grades.contains(null) && !_sending ? _send : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Enviar y seguir'),
          style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: widget.onDone, child: Text(_count > 0 ? 'Terminar' : 'Salir')),
      ]),
    ]);
  }
}

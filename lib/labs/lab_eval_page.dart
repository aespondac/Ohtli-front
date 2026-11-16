import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/ohtli_sso.dart';
import '../theme/colors.dart';
import 'lab_access.dart';
import 'lab_aggregates.dart';
import 'lab_article.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_title.dart';
import 'lab_widgets.dart';
import 'labs_top_bar.dart';

/// labs.ohtli.quest/eval sin sesión: qué es el estudio y cómo participar. Con sesión, la app
/// muestra el Labs unificado (LabsAppPage) en la sección "Participa".
class LabEvalPage extends StatelessWidget {
  final VoidCallback onLogin;
  const LabEvalPage({super.key, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: const LabsTopBar(current: LabsSection.participate),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: LabCard(
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
                  onPressed: onLogin,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// Consentimiento único de Ohtli Labs: al aceptarlo la cuenta queda como tester y tiene acceso a
/// estudios, experimentos y resultados liberados (sustituye la lista de espera del panel anterior).
class LabConsentCard extends StatefulWidget {
  final VoidCallback onOpenTerms;
  final VoidCallback onAccepted;
  const LabConsentCard({super.key, required this.onOpenTerms, required this.onAccepted});

  @override
  State<LabConsentCard> createState() => _LabConsentCardState();
}

class _LabConsentCardState extends State<LabConsentCard> {
  bool _sending = false;

  Future<void> _accept() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    setState(() => _sending = true);
    try {
      await LabAccess.joinAsTester(u);
      if (mounted) widget.onAccepted();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos registrarte como tester. Inténtalo de nuevo en un momento.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bienvenido a Ohtli Labs', style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 6),
          Text(
            'Aquí participas en los estudios del laboratorio, pruebas funciones experimentales antes de que lleguen a Ohtli '
            'y ves los resultados que se liberan para testers. Para entrar, acepta el consentimiento:',
            style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5),
          ),
          const SizedBox(height: 14),
          const LabSectionTitle('Consentimiento informado'),
          for (final t in [
            'Participo de forma voluntaria y puedo dejar Labs en cualquier momento.',
            'Mis respuestas se guardan sin nombre ni correo, ligadas a un identificador interno de la cuenta para evitar duplicados.',
            'Los resultados agregados pueden publicarse en el Trabajo Terminal y en labs.ohtli.quest.',
            'Lo que vea en Labs es experimental y confidencial hasta su lanzamiento.',
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
            onPressed: _sending ? null : _accept,
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            child: Text(_sending ? 'Registrando…' : 'Acepto y entro a Labs'),
          ),
        ]),
      );
}

/// Sección "Participa": estudios abiertos para testers (SUS y relevancia).
class LabParticipateView extends StatefulWidget {
  final LabRole role;

  /// "Dejar de ser tester": la cuenta vuelve a ver el consentimiento.
  final VoidCallback onLeft;
  const LabParticipateView({super.key, required this.role, required this.onLeft});

  @override
  State<LabParticipateView> createState() => _LabParticipateViewState();
}

class _LabParticipateViewState extends State<LabParticipateView> {
  String? _studyId;
  // Una sola suscripción (no en cada build: cada redibujo volvía a mostrar el spinner).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeStudies =
      LabRepository.instance.studies.where('active', isEqualTo: true).snapshots();

  @override
  void initState() {
    super.initState();
    // Quien respondió algún estudio antes de que existiera el título también lo recibe.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      LabRepository.instance.responses.where('uid', isEqualTo: uid).limit(1).get().then((q) {
        if (q.docs.isNotEmpty) LabTitle.grant(uid);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_studyId == 'sus') return _SusFlow(onDone: () => setState(() => _studyId = null));
    if (_studyId != null) return _RelevanceFlow(onDone: () => setState(() => _studyId = null));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabCard(
        child: Row(children: [
          const Icon(Icons.verified_user_outlined, color: OhtliColors.stormyTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Estudios abiertos', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              Text('Tu rol: ${widget.role.label}. Cada estudio toma pocos minutos y tus respuestas son anónimas.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
            ]),
          ),
          if (widget.role == LabRole.tester)
            TextButton(
              onPressed: () async {
                final u = FirebaseAuth.instance.currentUser;
                if (u == null) return;
                await LabAccess.leave(u);
                widget.onLeft();
              },
              child: const Text('Dejar de ser tester'),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      _studyPicker(),
    ]);
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

/// Sección "Resultados": artículos liberados para testers (y públicos), leídos dentro de Labs.
class LabReleasedView extends StatefulWidget {
  const LabReleasedView({super.key});

  @override
  State<LabReleasedView> createState() => _LabReleasedViewState();
}

class _LabReleasedViewState extends State<LabReleasedView> {
  Map<String, dynamic>? _post;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _releasedPosts =
      LabRepository.instance.watchPublishedPosts([LabVisibility.testers, LabVisibility.public]);

  @override
  Widget build(BuildContext context) {
    if (_post != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(onPressed: () => setState(() => _post = null), icon: const Icon(Icons.arrow_back), label: const Text('Todos los resultados')),
        LabCard(padding: const EdgeInsets.all(28), child: LabArticleView(post: _post!)),
      ]);
    }
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
  bool _alreadySent = false;

  @override
  void initState() {
    super.initState();
    // Si ya respondió (p. ej. volvió a "Comenzar" o recargó), no se le pide de nuevo.
    LabRepository.instance.myResponses('sus').then((r) {
      if (mounted && r.isNotEmpty) setState(() => _alreadySent = true);
    }).catchError((_) {});
  }

  bool get _complete => !_sus.contains(null) && !_sat.contains(null) && !_tasks.contains(null) && _visitor != null;

  Future<void> _send() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      await LabRepository.instance.addResponse('sus', susResponseId(uid), {
        'sus': _sus,
        'satisfaction': _sat,
        'tasks': _tasks,
        'profile': {'visitor_type': _visitor, 'age_range': _age, 'device': _device},
        'comment': _comment.text.trim().substring(0, math.min(1000, _comment.text.trim().length)),
      });
      if (mounted) setState(() => _sent = true);
      if (await LabTitle.grant(uid) && mounted) LabTitle.announce(context);
    } catch (e) {
      if (!mounted) return;
      // Las reglas rechazan un segundo envío (ID determinista) o un estudio ya cerrado.
      final mine = await LabRepository.instance.myResponses('sus').catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;
      if (mine.isNotEmpty) {
        setState(() => _alreadySent = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos guardar tus respuestas. Puede que el estudio se haya cerrado; inténtalo de nuevo en un momento.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent || _alreadySent) {
      return LabCard(
        child: Column(children: [
          const Icon(Icons.favorite_rounded, color: OhtliColors.cempasuchil, size: 40),
          const SizedBox(height: 8),
          Text(_sent ? '¡Gracias! Tus respuestas quedaron registradas.' : 'Ya respondiste este cuestionario. ¡Gracias por participar!', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
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
  // Alternativas ya vistas o calificadas, como "<index de la fila>/<alternativa>". Incluye las de
  // visitas anteriores (de sus respuestas guardadas) para no volver a juzgar lo mismo al recargar.
  final Set<String> _seen = {};
  int _previouslyGraded = 0;
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
      try {
        for (final r in await LabRepository.instance.myResponses('relevancia', runId: _runId)) {
          _seen.add('${r['rowIndex']}/${r['optionIndex']}');
        }
        _previouslyGraded = _seen.length;
      } catch (_) {}
      _next();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  int? _firstUnseen(Map<String, dynamic> row) {
    final opts = (row['options'] as List);
    for (var j = 0; j < opts.length; j++) {
      if (((opts[j] as Map)['route'] as List? ?? []).isNotEmpty && !_seen.contains('${row['index']}/$j')) return j;
    }
    return null;
  }

  /// Las alternativas de una misma solicitud se califican seguidas: así cada solicitud tiene sus
  /// alternativas juzgadas por la misma persona y se puede comparar la mejor de las tres.
  void _next() {
    final same = _row == null ? null : _firstUnseen(_row!);
    if (same != null) {
      _opt = same;
    } else {
      final pool = <int>[];
      for (var i = 0; i < _rows.length; i++) {
        if (_firstUnseen(_rows[i]) != null) pool.add(i);
      }
      if (pool.isEmpty) {
        _row = null;
        return;
      }
      _row = _rows[pool[_rng.nextInt(pool.length)]];
      _opt = _firstUnseen(_row!)!;
    }
    _seen.add('${_row!['index']}/$_opt');
    _grades = List.filled(((_row!['options'] as List)[_opt]['route'] as List).length, null);
  }

  Future<void> _send() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _sending = true);
    final sc = Map<String, dynamic>.from(_row!['scenario'] as Map);
    final opt = Map<String, dynamic>.from((_row!['options'] as List)[_opt] as Map);
    final rowIndex = (_row!['index'] as num).toInt();
    try {
      await LabRepository.instance.addResponse('relevancia', relevanceResponseId(uid, _runId!, rowIndex, _opt), {
        'runId': _runId,
        'rowIndex': rowIndex,
        'scenarioId': sc['id'],
        'optionIndex': _opt,
        'theme': opt['theme_key'] ?? opt['theme'],
        'mood': sc['mood'],
        'poiIds': (opt['route'] as List).map((s) => (s as Map)['poi_id']).toList(),
        'grades': _grades,
        'criterion': 'intencion_y_tema',
      });
      if (mounted) setState(() => _count++);
      if (await LabTitle.grant(uid) && mounted) LabTitle.announce(context);
    } catch (e) {
      // Ya calificada antes (ID determinista) o estudio cerrado: se avisa y se sigue con otra.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se guardó esta calificación (ya la habías enviado o el estudio se cerró). Seguimos con otra.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _next();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return LabCard(child: Text(_error!, style: labCell()));
    if (_row == null) {
      return LabCard(
        child: Column(children: [
          Text(
              _count > 0
                  ? '¡Listo! Calificaste $_count itinerarios. Gracias.'
                  : _previouslyGraded > 0
                      ? 'Ya calificaste todos los itinerarios de este estudio. ¡Gracias!'
                      : 'Por ahora no hay itinerarios para calificar.', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
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
          Text('Saliendo de ${(sc['origin'] as Map?)?['name']} · presupuesto \$${(sc['budget'] as num?)?.toStringAsFixed(0)} MXN',
              style: labCell()),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: OhtliColors.stormyTeal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Alternativa ${_opt + 1} de ${(_row!['options'] as List).length} · ${opt['theme'] ?? ''}',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              'Ohtli propone tres alternativas con enfoques distintos para la misma intención. '
              'Califica qué tan bien encaja cada lugar con lo que busca esta persona dentro del enfoque de esta alternativa.',
              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, height: 1.4)),
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

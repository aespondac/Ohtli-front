import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_access.dart';
import 'lab_aggregates.dart';
import 'lab_publishing.dart';
import 'lab_repository.dart';
import 'lab_runner.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';

/// Paneles de las pruebas del Trabajo Terminal (configurar, ejecutar, monitorear, exportar).
/// Se muestran dentro del Labs unificado (LabsAppPage), en la sección "Pruebas del TT", solo para
/// miembros del laboratorio.
///
/// Rol de la sesión (lo fija LabsAppPage); decide qué controles se muestran.
/// Las reglas de Firestore son las que protegen los datos.
LabRole currentLabRole = LabRole.none;

IconData labStudyIcon(LabStudyKind k) => switch (k) {
      LabStudyKind.scenarios => Icons.route_rounded,
      LabStudyKind.load => Icons.speed_rounded,
      LabStudyKind.checklist => Icons.wifi_off_rounded,
      LabStudyKind.relevance => Icons.thumbs_up_down_rounded,
      LabStudyKind.sus => Icons.groups_rounded,
    };

/// Panel de una prueba (escenarios, carga, verificación o estudio con testers).
class LabStudyPanel extends StatelessWidget {
  final LabStudy study;
  const LabStudyPanel({super.key, required this.study});

  @override
  Widget build(BuildContext context) => _StudyPanel(study: study);
}

class _StudyPanel extends StatelessWidget {
  final LabStudy study;
  const _StudyPanel({super.key, required this.study});

  @override
  Widget build(BuildContext context) {
    final body = switch (study.kind) {
      LabStudyKind.scenarios => _ScenarioRunner(study: study),
      LabStudyKind.load => _LoadRunner(study: study),
      LabStudyKind.checklist => _ChecklistRunner(study: study),
      LabStudyKind.relevance || LabStudyKind.sus => _TesterStudy(study: study),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip('TT ${study.chapter}', OhtliColors.stormyTeal),
            _chip(study.criterion, OhtliColors.xoconostle),
            if (study.needsTesters) _chip('Requiere testers', OhtliColors.cempasuchil),
          ]),
          const SizedBox(height: 10),
          Text(study.title, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 6),
          Text(study.description, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45)),
        ]),
      ),
      const SizedBox(height: 16),
      body,
      if (study.kind != LabStudyKind.relevance && study.kind != LabStudyKind.sus) ...[
        const SizedBox(height: 16),
        _RunHistory(study: study),
      ],
    ]);
  }
}

Widget _chip(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
    );

// ---------------------------------------------------------------------------------------------
// Escenarios (formales y batería)
// ---------------------------------------------------------------------------------------------

class _ScenarioRunner extends StatefulWidget {
  final LabStudy study;
  const _ScenarioRunner({required this.study});

  @override
  State<_ScenarioRunner> createState() => _ScenarioRunnerState();
}

class _ScenarioRunnerState extends State<_ScenarioRunner> {
  late List<LabScenario> _scenarios;
  final Set<String> _enabled = {};
  final _label = TextEditingController();
  final _count = TextEditingController(text: '30');
  final _pause = TextEditingController(text: '5');
  final _sla = TextEditingController(text: '45');
  bool _running = false;
  bool _cancel = false;
  final Map<String, String> _stage = {};
  final List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _summary;
  String? _runId;

  bool get _isBattery => widget.study.id == 'bateria_30';

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  void _rebuild() {
    _scenarios = _isBattery ? batteryScenarios(int.tryParse(_count.text) ?? 30) : formalScenarios();
    _enabled
      ..clear()
      ..addAll(_scenarios.map((s) => s.id));
  }

  Future<void> _run() async {
    final selected = _scenarios.where((s) => _enabled.contains(s.id)).toList();
    if (selected.isEmpty) return;
    final sla = double.tryParse(_sla.text) ?? 45;
    final pause = int.tryParse(_pause.text) ?? 5;
    setState(() {
      _running = true;
      _cancel = false;
      _rows.clear();
      _stage.clear();
      _summary = null;
    });
    final runner = LabRunner();
    final runId = await LabRepository.instance.createRun(widget.study.id, {
      'scenarios': selected.map((s) => s.toJson()).toList(),
      'pause_s': pause,
      'sla_s': sla,
      'api': LabRunner.apiBase,
      'mode': 'secuencial',
    }, label: _label.text.trim());
    setState(() => _runId = runId);
    for (var i = 0; i < selected.length; i++) {
      if (_cancel) break;
      final sc = selected[i];
      setState(() => _stage[sc.id] = 'iniciando');
      final row = await runner.runScenario(sc, onStage: (s) {
        if (mounted) setState(() => _stage[sc.id] = s);
      });
      await LabRepository.instance.addRow(runId, i, row);
      if (!mounted) return;
      setState(() {
        _rows.add(row);
        _stage[sc.id] = '${row['status']}';
        _summary = summarizeRows(_rows, slaSeconds: sla);
      });
      if (i < selected.length - 1 && !_cancel) await Future.delayed(Duration(seconds: pause));
    }
    final summary = summarizeRows(_rows, slaSeconds: sla);
    await LabRepository.instance.finishRun(runId, summary, status: _cancel ? 'cancelled' : 'completed');
    if (mounted) {
      setState(() {
        _running = false;
        _summary = summary;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const LabSectionTitle('Configuración de la corrida',
              caption: 'Cada escenario se envía a api.ohtli.quest con tu sesión y se espera a que el SMA termine; '
                  'la corrida guarda la configuración exacta y cada resultado en Firestore.'),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 260, child: _field(_label, 'Etiqueta (p. ej. "v4 catálogo curado")')),
            if (_isBattery)
              SizedBox(
                width: 130,
                child: _field(_count, 'Escenarios', onChanged: (_) => setState(_rebuild)),
              ),
            SizedBox(width: 130, child: _field(_pause, 'Pausa (s)')),
            SizedBox(width: 130, child: _field(_sla, 'SLA (s)')),
            ElevatedButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(_running ? 'Ejecutando…' : 'Ejecutar ${_enabled.length} escenarios'),
              style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            ),
            if (_running)
              OutlinedButton.icon(
                onPressed: () => setState(() => _cancel = true),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Detener al terminar el actual'),
              ),
          ]),
          const SizedBox(height: 14),
          _scenarioTable(),
        ]),
      ),
      if (_summary != null) ...[
        const SizedBox(height: 16),
        _SummaryView(summary: _summary!, live: _running, runId: _runId),
      ],
    ]);
  }

  Widget _scenarioTable() {
    final byId = {for (final r in _rows) (r['scenario'] as Map)['id']: r};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 52,
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Escenario')),
          DataColumn(label: Text('Topología')),
          DataColumn(label: Text('Presup.')),
          DataColumn(label: Text('Horario')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('E2E (s)')),
          DataColumn(label: Text('Paradas')),
          DataColumn(label: Text('CA-01')),
          DataColumn(label: Text('Traslape')),
        ],
        rows: _scenarios.map((s) {
          final r = byId[s.id];
          final m = (r?['metrics'] as Map?) ?? {};
          return DataRow(cells: [
            DataCell(Checkbox(
              value: _enabled.contains(s.id),
              onChanged: _running ? null : (v) => setState(() => v == true ? _enabled.add(s.id) : _enabled.remove(s.id)),
            )),
            DataCell(Text(s.id, style: labCell(bold: true))),
            DataCell(SizedBox(width: 300, child: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: labCell()))),
            DataCell(Text(s.topology, style: labCell())),
            DataCell(Text('\$${s.budget.toStringAsFixed(0)}', style: labCell())),
            DataCell(Text(s.startTime != null ? '${s.startTime}–${s.endTime}' : 'tema', style: labCell())),
            DataCell(StatusDot(_stage[s.id] ?? 'pendiente')),
            DataCell(Text(fmtNum(r?['e2e_s']), style: labCell())),
            DataCell(Text(fmtNum(m['stops'], digits: 0), style: labCell())),
            DataCell(Text(m.isEmpty ? '—' : (m['feasible'] == true ? 'cumple' : 'no cumple'), style: labCell(bold: true))),
            DataCell(Text(fmtNum(m['overlap_mean'], digits: 2), style: labCell())),
          ]);
        }).toList(),
      ),
    );
  }
}

Widget _field(TextEditingController c, String label, {ValueChanged<String>? onChanged, int maxLines = 1}) => TextField(
      controller: c,
      onChanged: onChanged,
      maxLines: maxLines,
      style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: OhtliColors.inputBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

class _SummaryView extends StatelessWidget {
  final Map<String, dynamic> summary;
  final bool live;
  final String? runId;
  const _SummaryView({required this.summary, this.live = false, this.runId});

  @override
  Widget build(BuildContext context) {
    final sla = summary['sla_s'] ?? 45;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabSectionTitle(live ? 'Resultados en vivo' : 'Resumen de la corrida', caption: runId != null ? 'lab_runs/$runId' : null),
        Wrap(spacing: 10, runSpacing: 10, children: [
          MetricTile(label: 'Completados', value: '${summary['completed']}/${summary['n']}', hint: 'errores ${summary['errors']} · timeouts ${summary['timeouts']}'),
          MetricTile(label: 'Latencia E2E media', value: fmtNum(summary['e2e_mean_s'], suffix: ' s')),
          MetricTile(
              label: 'p95 E2E',
              value: fmtNum(summary['e2e_p95_s'], suffix: ' s'),
              hint: 'SLA ≤ $sla s: ${summary['sla_ok']}/${summary['completed']}',
              color: (summary['e2e_p95_s'] ?? 0) <= sla ? const Color(0xFF3F8F5B) : OhtliColors.cempasuchil),
          MetricTile(label: 'Viabilidad CA-01', value: fmtNum(summary['feasible_pct'], suffix: '%'), hint: 'ventanas, jornada y presupuesto'),
          MetricTile(label: 'Paradas por escenario', value: fmtNum(summary['stops_mean'])),
          MetricTile(label: 'Traslape entre alternativas', value: fmtNum(summary['overlap_mean'], digits: 2), hint: 'Jaccard (0 = distintas)'),
          MetricTile(label: 'Afinidad media', value: fmtNum(summary['match_mean'], digits: 2), hint: 'match_score'),
          MetricTile(label: 'Precio estimado', value: fmtNum(summary['price_estimated_pct'], suffix: '%')),
        ]),
        if ((summary['sources'] as Map?)?.isNotEmpty == true) ...[
          const SizedBox(height: 14),
          Text('Procedencia de las paradas', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          const SizedBox(height: 6),
          LabBars(
            data: (summary['sources'] as Map).entries.map((e) => MapEntry('${e.key}', (e.value as num).toDouble())).toList()
              ..sort((a, b) => b.value.compareTo(a.value)),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Concurrencia
// ---------------------------------------------------------------------------------------------

class _LoadRunner extends StatefulWidget {
  final LabStudy study;
  const _LoadRunner({required this.study});

  @override
  State<_LoadRunner> createState() => _LoadRunnerState();
}

class _LoadRunnerState extends State<_LoadRunner> {
  final _levels = TextEditingController(text: '10, 25, 50');
  final _pause = TextEditingController(text: '90');
  final _label = TextEditingController();
  bool _running = false;
  String _status = '';
  final Map<int, Map<String, dynamic>> _byLevel = {};
  final Map<int, int> _done = {};

  Future<void> _run() async {
    final levels = _levels.text.split(RegExp(r'[,\s]+')).map(int.tryParse).whereType<int>().where((x) => x > 0 && x <= 60).toList();
    if (levels.isEmpty) return;
    final pause = int.tryParse(_pause.text) ?? 90;
    setState(() {
      _running = true;
      _byLevel.clear();
      _done.clear();
    });
    final runId = await LabRepository.instance.createRun(widget.study.id, {
      'levels': levels,
      'pause_between_levels_s': pause,
      'api': LabRunner.apiBase,
      'mode': 'ráfaga simultánea por nivel; escenarios de la batería en orden cíclico',
    }, label: _label.text.trim());
    final runner = LabRunner();
    await runner.vibeVector('cultural');
    await runner.vibeVector('gastronomico');
    await runner.vibeVector('naturaleza');
    var idx = 0;
    for (var li = 0; li < levels.length; li++) {
      final n = levels[li];
      setState(() => _status = 'Nivel $n: enviando $n solicitudes simultáneas…');
      final scs = batteryScenarios(n);
      _done[n] = 0;
      final futures = scs.map((sc) => runner.runScenario(sc).then((r) {
            if (mounted) setState(() => _done[n] = (_done[n] ?? 0) + 1);
            return r;
          }));
      final rows = await Future.wait(futures);
      for (final r in rows) {
        r['level'] = n;
        await LabRepository.instance.addRow(runId, idx++, r);
      }
      final s = summarizeRows(rows);
      setState(() => _byLevel[n] = s);
      await LabRepository.instance.updateRun(runId, {'summary': {'levels': {for (final e in _byLevel.entries) '${e.key}': e.value}}});
      if (li < levels.length - 1) {
        setState(() => _status = 'Pausa de $pause s antes del siguiente nivel…');
        await Future.delayed(Duration(seconds: pause));
      }
    }
    await LabRepository.instance.finishRun(runId, {'levels': {for (final e in _byLevel.entries) '${e.key}': e.value}});
    if (mounted) {
      setState(() {
        _running = false;
        _status = 'Corrida terminada (lab_runs/$runId).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LabSectionTitle('Ráfagas simultáneas',
            caption: 'Cada nivel dispara N solicitudes al mismo tiempo y espera a que todas terminen. '
                'Los errores de memoria se revisan además en Cloud Logging.'),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 220, child: _field(_label, 'Etiqueta')),
          SizedBox(width: 160, child: _field(_levels, 'Niveles')),
          SizedBox(width: 160, child: _field(_pause, 'Pausa entre niveles (s)')),
          ElevatedButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(_running ? 'Ejecutando…' : 'Ejecutar prueba de carga'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
        ]),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
          ),
        for (final e in _done.entries)
          if (!_byLevel.containsKey(e.key))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: e.value / e.key, color: OhtliColors.stormyTeal),
            ),
        if (_byLevel.isNotEmpty) ...[
          const SizedBox(height: 14),
          _LoadTable(levels: _byLevel.map((k, v) => MapEntry('$k', v))),
        ],
      ]),
    );
  }
}

class _LoadTable extends StatelessWidget {
  final Map<String, dynamic> levels;
  const _LoadTable({required this.levels});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 34,
          columns: const [
            DataColumn(label: Text('Simultáneas')),
            DataColumn(label: Text('Completadas')),
            DataColumn(label: Text('Tasa de error')),
            DataColumn(label: Text('Media (s)')),
            DataColumn(label: Text('p95 (s)')),
            DataColumn(label: Text('Máx (s)')),
            DataColumn(label: Text('≤ 45 s')),
          ],
          rows: levels.entries.map((e) {
            final s = Map<String, dynamic>.from(e.value as Map);
            return DataRow(cells: [
              DataCell(Text(e.key, style: labCell(bold: true))),
              DataCell(Text('${s['completed']}/${s['n']}', style: labCell())),
              DataCell(Text(fmtNum(s['error_rate_pct'], suffix: '%'), style: labCell(bold: true))),
              DataCell(Text(fmtNum(s['e2e_mean_s']), style: labCell())),
              DataCell(Text(fmtNum(s['e2e_p95_s']), style: labCell())),
              DataCell(Text(fmtNum(s['e2e_max_s']), style: labCell())),
              DataCell(Text('${s['sla_ok']}/${s['completed']}', style: labCell())),
            ]);
          }).toList(),
        ),
      );
}

// ---------------------------------------------------------------------------------------------
// Lista de verificación fuera de línea (CA-05)
// ---------------------------------------------------------------------------------------------

class _ChecklistRunner extends StatefulWidget {
  final LabStudy study;
  const _ChecklistRunner({required this.study});

  @override
  State<_ChecklistRunner> createState() => _ChecklistRunnerState();
}

class _ChecklistRunnerState extends State<_ChecklistRunner> {
  static const browsers = ['Chrome (escritorio)', 'Safari (iPhone)'];
  final Map<String, String> _state = {}; // '$browser|$item' -> pasa|falla
  final _notes = TextEditingController();
  final _label = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final runId = await LabRepository.instance.createRun(widget.study.id, {
      'browsers': browsers,
      'items': kOfflineChecklist.map((i) => {'id': i.id, 'text': i.text}).toList(),
    }, label: _label.text.trim());
    var idx = 0, pass = 0, fail = 0;
    final perBrowser = <String, Map<String, int>>{};
    for (final b in browsers) {
      for (final it in kOfflineChecklist) {
        final v = _state['$b|${it.id}'] ?? 'pendiente';
        if (v == 'pasa') pass++;
        if (v == 'falla') fail++;
        perBrowser.putIfAbsent(b, () => {'pasa': 0, 'falla': 0, 'pendiente': 0});
        perBrowser[b]![v] = (perBrowser[b]![v] ?? 0) + 1;
        await LabRepository.instance.addRow(runId, idx++, {'browser': b, 'item': it.id, 'text': it.text, 'result': v});
      }
    }
    await LabRepository.instance.finishRun(runId, {
      'pass': pass,
      'fail': fail,
      'total': browsers.length * kOfflineChecklist.length,
      'pass_pct': 100.0 * pass / (browsers.length * kOfflineChecklist.length),
      'per_browser': perBrowser,
      'notes': _notes.text.trim(),
    });
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Guardado en lab_runs/$runId')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LabSectionTitle('Verificación manual',
            caption: 'Abre ohtli.quest en cada navegador, sigue los pasos y marca el resultado. Al guardar se crea una corrida.'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Paso')),
              for (final b in browsers) DataColumn(label: Text(b)),
            ],
            rows: kOfflineChecklist.map((it) {
              return DataRow(cells: [
                DataCell(SizedBox(width: 420, child: Text(it.text, style: labCell()))),
                for (final b in browsers)
                  DataCell(DropdownButton<String>(
                    value: _state['$b|${it.id}'] ?? 'pendiente',
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'pendiente', child: Text('pendiente')),
                      DropdownMenuItem(value: 'pasa', child: Text('pasa')),
                      DropdownMenuItem(value: 'falla', child: Text('falla')),
                    ],
                    onChanged: (v) => setState(() => _state['$b|${it.id}'] = v ?? 'pendiente'),
                  )),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field(_notes, 'Observaciones (versión de navegador, dispositivo, incidencias)', maxLines: 2)),
          const SizedBox(width: 12),
          SizedBox(width: 200, child: _field(_label, 'Etiqueta')),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar corrida'),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Estudios con testers (relevancia y SUS)
// ---------------------------------------------------------------------------------------------

class _TesterStudy extends StatelessWidget {
  final LabStudy study;
  const _TesterStudy({required this.study});

  @override
  Widget build(BuildContext context) {
    final repo = LabRepository.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchStudy(study.id),
      builder: (context, snap) {
        final cfg = snap.data?.data() ?? {};
        final active = cfg['active'] == true;
        return Column(children: [
          LabCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LabSectionTitle('Participación',
                  caption: 'Activo = aparece en lab.ohtli.quest/eval para que los testers participen con su cuenta.'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                activeColor: OhtliColors.stormyTeal,
                title: Text(active ? 'Abierto a testers' : 'Cerrado', style: labCell(bold: true)),
                subtitle: Text('Enlace público: https://lab.ohtli.quest/eval', style: labCell()),
                onChanged: (v) => repo.setStudy(study.id, {'active': v}),
              ),
              if (study.kind == LabStudyKind.relevance) _SourceRunPicker(current: cfg['sourceRunId'] as String?),
            ]),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: repo.watchResponses(study.id),
            builder: (context, rs) {
              final raw = rs.data?.docs.map((d) => d.data()).toList() ?? [];
              final docs = cleanResponses(study.kind, raw);
              final agg = study.kind == LabStudyKind.sus ? aggregateSus(docs) : aggregateRelevance(docs);
              return LabCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabSectionTitle('Respuestas (${docs.length})',
                      caption: 'Agregados calculados en vivo, visibles solo para el laboratorio. Para liberarlos, '
                          'cítalos en un artículo (Artículos y resultados) con la visibilidad que corresponda.'),
                  AggregateView(kind: study.kind, agg: agg),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    OutlinedButton.icon(
                      onPressed: docs.isEmpty ? null : () => downloadText('${study.id}_respuestas.json', toJsonPretty(anonymizeResponses(docs)), mime: 'application/json'),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Respuestas (JSON, anónimas)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: docs.isEmpty ? null : () => downloadText('${study.id}_respuestas.csv', responsesCsv(study.kind, docs), mime: 'text/csv'),
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('CSV'),
                    ),
                  ]),
                ]),
              );
            },
          ),
        ]);
      },
    );
  }
}

class _SourceRunPicker extends StatelessWidget {
  final String? current;
  const _SourceRunPicker({required this.current});

  @override
  Widget build(BuildContext context) {
    final repo = LabRepository.instance;
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: Future.wait([
        repo.runs.where('studyId', isEqualTo: 'escenarios_formales').orderBy('startedAt', descending: true).limit(10).get(),
        repo.runs.where('studyId', isEqualTo: 'bateria_30').orderBy('startedAt', descending: true).limit(10).get(),
      ]).then((qs) => [...qs[0].docs, ...qs[1].docs].where((d) => d.data()['status'] == 'completed').toList()),
      builder: (context, snap) {
        final runs = snap.data ?? [];
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Text('Itinerarios a juzgar:', style: labCell(bold: true)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: runs.any((r) => r.id == current) ? current : null,
                hint: const Text('Elige una corrida completada'),
                items: runs
                    .map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.data()['studyId']} · ${fmtDate(r.data()['startedAt'])} ${r.data()['label'] ?? ''}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (id) async {
                  if (id == null) return;
                  if (current != null && current != id) await repo.updateRun(current!, {'evalSource': false});
                  await repo.updateRun(id, {'evalSource': true});
                  await repo.setStudy('relevancia', {'sourceRunId': id});
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Historial de corridas
// ---------------------------------------------------------------------------------------------

class _RunHistory extends StatelessWidget {
  final LabStudy study;
  const _RunHistory({required this.study});

  @override
  Widget build(BuildContext context) {
    final repo = LabRepository.instance;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LabSectionTitle('Historial de corridas',
            caption: 'Publicar una corrida la muestra en labs.ohtli.quest. Las exportaciones sirven como anexo del TT.'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: repo.watchRuns(study.id),
          builder: (context, snap) {
            if (snap.hasError) return Text('Error: ${snap.error}', style: labCell());
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return Text('Aún no hay corridas.', style: labCell());
            return Column(children: docs.map((d) => _RunTile(id: d.id, data: d.data(), study: study)).toList());
          },
        ),
      ]),
    );
  }
}

class _RunTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final LabStudy study;
  const _RunTile({required this.id, required this.data, required this.study});

  String _headline() {
    final s = (data['summary'] as Map?) ?? {};
    switch (study.kind) {
      case LabStudyKind.scenarios:
        return '${s['completed'] ?? '—'}/${s['n'] ?? '—'} completados · p95 ${fmtNum(s['e2e_p95_s'], suffix: ' s')} · CA-01 ${fmtNum(s['feasible_pct'], suffix: '%')} · traslape ${fmtNum(s['overlap_mean'], digits: 2)}';
      case LabStudyKind.load:
        final lv = (s['levels'] as Map?) ?? {};
        return lv.entries.map((e) => '${e.key}: ${(e.value as Map)['completed']}/${(e.value as Map)['n']} (${fmtNum((e.value as Map)['error_rate_pct'], suffix: '% error')})').join(' · ');
      case LabStudyKind.checklist:
        return '${s['pass'] ?? 0}/${s['total'] ?? 0} pasos aprobados · ${s['fail'] ?? 0} fallas';
      default:
        return '';
    }
  }

  Future<void> _export(BuildContext context, {required bool csv}) async {
    final rows = await LabRepository.instance.rows(id);
    final name = '${study.id}_${id.substring(0, 6)}';
    if (!csv) {
      downloadText('$name.json', toJsonPretty({'run': data, 'rows': rows}), mime: 'application/json');
      return;
    }
    downloadText('$name.csv', runRowsCsv(study.kind, rows), mime: 'text/csv');
  }

  @override
  Widget build(BuildContext context) {
    final vis = LabVisibility.of(data);
    final published = vis != LabVisibility.private;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: published ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusDot('${data['status']}'),
          Text(fmtDate(data['startedAt']), style: labCell(bold: true)),
          if ((data['label'] ?? '').toString().isNotEmpty) Text('“${data['label']}”', style: labCell()),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Text(_headline(), style: labCell())),
          VisibilityPicker(
            value: vis,
            role: currentLabRole,
            onChanged: data['status'] == 'running' ? null : (v) => LabRepository.instance.setRunVisibility(id, v),
          ),
          TextButton.icon(onPressed: () => _export(context, csv: true), icon: const Icon(Icons.table_chart_outlined, size: 16), label: const Text('CSV')),
          TextButton.icon(onPressed: () => _export(context, csv: false), icon: const Icon(Icons.data_object_rounded, size: 16), label: const Text('JSON')),
          TextButton.icon(
            onPressed: () => _editNotes(context),
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: Text((data['notes'] ?? '').toString().isEmpty ? 'Notas' : 'Editar notas'),
          ),
        ],
      ),
    );
  }

  Future<void> _editNotes(BuildContext context) async {
    final c = TextEditingController(text: (data['notes'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notas de la corrida'),
        content: SizedBox(width: 520, child: TextField(controller: c, maxLines: 6, decoration: const InputDecoration(hintText: 'Contexto, incidencias, interpretación…'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) await LabRepository.instance.updateRun(id, {'notes': c.text.trim()});
  }
}

String runRowsCsv(LabStudyKind kind, List<Map<String, dynamic>> rows) {
  if (kind == LabStudyKind.checklist) {
    return toCsv(['navegador', 'paso', 'descripcion', 'resultado'], rows.map((r) => [r['browser'], r['item'], r['text'], r['result']]).toList());
  }
  return toCsv(
    ['nivel', 'escenario', 'titulo', 'topologia', 'presupuesto', 'perfil', 'intencion', 'inicio', 'fin', 'ritmo', 'radio_km', 'fecha',
     'estado', 'e2e_s', 'ack_ms', 'comparador_ms', 'generador_ms', 'recomendador_ms', 'alternativas', 'paradas', 'ca01_viable',
     'ventanas_ok_pct', 'jornada_ok_pct', 'presupuesto_ok_pct', 'traslape', 'afinidad', 'categorias', 'precio_estimado_pct', 'fuentes', 'error'],
    rows.map((r) {
      final sc = Map<String, dynamic>.from(r['scenario'] as Map? ?? {});
      final m = Map<String, dynamic>.from(r['metrics'] as Map? ?? {});
      final a = Map<String, dynamic>.from(r['agent_ms'] as Map? ?? {});
      return [
        r['level'], sc['id'], sc['title'], sc['topology'], sc['budget'], sc['profile'], sc['mood'], sc['start_time'], sc['end_time'],
        sc['stay_factor'], sc['radius_km'], sc['travel_date'], r['status'], r['e2e_s'], r['ack_ms'], a['comparador'], a['generador'],
        a['recomendador'], m['options'], m['stops'], m['feasible'], m['window_ok_pct'], m['day_ok_pct'], m['budget_ok_pct'],
        m['overlap_mean'], m['match_mean'], m['distinct_categories'], m['price_estimated_pct'],
        (m['sources'] as Map?)?.entries.map((e) => '${e.key}:${e.value}').join(' '), r['error'],
      ];
    }).toList(),
  );
}

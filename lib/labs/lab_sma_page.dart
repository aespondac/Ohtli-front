/// Panel "Sistema multiagente" de Ohtli Labs (miembros): cómo aprende el SMA.
///
/// - Éxito de las recomendaciones (Agente Crítico): IER y sus componentes, por tema, estilo de
///   apertura, medio de traslado, estrategia de presupuesto e intención.
/// - Políticas que aprenden (bandidos): uso e IER de cada brazo por contexto.
/// - Categorías emergentes (Agente Curador): evidencia y estado, con activar / retirar.
/// - Mensajes entre agentes: pedidos de Comparador y Generador al Recolector y su resultado.
library;

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../theme/colors.dart';
import 'lab_runner.dart';
import 'lab_widgets.dart';

class LabSmaPanel extends StatefulWidget {
  const LabSmaPanel({super.key});

  @override
  State<LabSmaPanel> createState() => _LabSmaPanelState();
}

class _LabSmaPanelState extends State<LabSmaPanel> {
  Map<String, dynamic>? _critic, _policies, _categories, _messages;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(Uri.parse('${LabRunner.apiBase}$path'), headers: await _headers());
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode} en $path';
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        _get('/v1/critic/summary'),
        _get('/v1/agents/policies'),
        _get('/v1/categories'),
        _get('/v1/agents/messages?limit=30'),
      ]);
      if (!mounted) return;
      setState(() {
        _critic = res[0];
        _policies = res[1];
        _categories = res[2];
        _messages = res[3];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      final r = await http.post(Uri.parse('${LabRunner.apiBase}/v1/categories/$id/status'),
          headers: await _headers(), body: jsonEncode({'status': status}));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cambiar el estado: $e')));
      }
    }
  }

  String _pct(dynamic v) => v is num ? '${(v * 100).toStringAsFixed(0)} %' : '—';

  Widget _group(String title, Map? groups, {String Function(String)? label}) {
    final entries = (groups ?? {}).entries.where((e) => e.key != 'null' && (e.value as Map)['n'] != null).toList()
      ..sort((a, b) => ((b.value as Map)['n'] as num).compareTo((a.value as Map)['n'] as num));
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.subtleText)),
        const SizedBox(height: 6),
        LabBars(
          maxValue: 1,
          data: [
            for (final e in entries.take(8))
              MapEntry('${label?.call(e.key) ?? e.key} (${(e.value as Map)['n']})', ((e.value as Map)['ier'] as num? ?? 0).toDouble()),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    if (_error != null) {
      return LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No se pudo cargar el estado del SMA', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_error!, style: labCell()),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
        ]),
      );
    }
    final c = _critic ?? {};
    final g = (c['global'] as Map?) ?? {};
    final cats = ((_categories?['categories'] as List?) ?? []).cast<Map>();
    final msgs = ((_messages?['messages'] as List?) ?? []).cast<Map>();
    final pols = ((_policies?['policies'] as Map?) ?? {});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const LabSectionTitle('Sistema multiagente',
          caption: 'Éxito = la persona elige la recomendación, no la modifica, la hace y la comparte (IER).'),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Éxito de las recomendaciones (Agente Crítico)',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 10),
          if (c['status'] == 'empty')
            Text('Todavía no hay evaluaciones: el Crítico corre cada 3 horas.', style: labCell())
          else ...[
            Wrap(spacing: 10, runSpacing: 10, children: [
              MetricTile(label: 'Recomendaciones', value: '${c['recommendations'] ?? 0}', hint: '${c['scored'] ?? 0} evaluadas'),
              MetricTile(label: 'IER medio', value: fmtNum(g['ier'], digits: 2), hint: 'de 0 a 1'),
              MetricTile(label: 'Elegidas', value: _pct(g['choice_rate'])),
              MetricTile(label: 'Sin cambios', value: _pct(g['unmodified']), hint: 'de las elegidas'),
              MetricTile(label: 'Realizadas', value: _pct(g['completed']), hint: 'de las elegidas'),
              MetricTile(label: 'Compartidas', value: _pct(g['share_rate']), hint: 'de las elegidas'),
            ]),
            _group('IER por tema (Generador)', c['by_theme'] as Map?),
            _group('IER por política (Generador)', c['by_policy_arm'] as Map?),
            _group('IER por estilo de apertura (Recomendador)', c['by_opening_style'] as Map?),
            _group('IER por medio de traslado', c['by_transport_mode'] as Map?),
            _group('IER por intención (Comparador)', c['by_intent_category'] as Map?),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Políticas que aprenden', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 4),
          Text('Bandido de Thompson por contexto: cada brazo se usa más mientras más éxito tiene (10 % de exploración).',
              style: labCell()),
          if (pols.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Sin recomendaciones maduras todavía (14 días).', style: labCell())),
          for (final e in pols.entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.key.replaceAll('__', ' · '), style: labCell(bold: true)),
                for (final a in (e.value as Map).entries)
                  Text('  ${a.key}: ${(a.value as Map)['n']} usos · IER ${fmtNum((a.value as Map)['ier'], digits: 2)}', style: labCell()),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Categorías emergentes (Agente Curador)',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 4),
          Text('Nacen de intenciones mal cubiertas; se activan con lugares suficientes y se retiran si fracasan.', style: labCell()),
          if (cats.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Aún no hay categorías emergentes.', style: labCell())),
          for (final cat in cats)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${cat['label']} · ${cat['status']}', style: labCell(bold: true)),
                    Text('${cat['n_pois']} lugares · ${(cat['evidence'] as Map?)?['n_moods'] ?? 0} intenciones', style: labCell()),
                    if ((cat['keywords'] as List?)?.isNotEmpty ?? false)
                      Text('Palabras: ${(cat['keywords'] as List).join(', ')}', style: labCell()),
                  ]),
                ),
                if (cat['status'] != 'activa')
                  TextButton(onPressed: () => _setStatus('${cat['id']}', 'activa'), child: const Text('Activar')),
                if (cat['status'] != 'retirada')
                  TextButton(onPressed: () => _setStatus('${cat['id']}', 'retirada'), child: const Text('Retirar')),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mensajes entre agentes', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          if (msgs.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Sin pedidos todavía.', style: labCell())),
          for (final m in msgs)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${m['from']} → ${m['to']} · ${m['kind'] == 'cobertura_baja' ? 'cobertura baja' : 'tema sin candidatos'} · '
                '${m['status']} · ${m['requests'] ?? 1} solicitudes'
                '${(m['result'] as Map?)?['acquired'] != null ? ' · ${(m['result'] as Map)['acquired']} lugares cosechados' : ''}',
                style: labCell(),
              ),
            ),
        ]),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Actualizar')),
      ),
    ]);
  }
}

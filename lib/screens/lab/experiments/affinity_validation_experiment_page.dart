import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../../labs/affinity_validation.dart';
import '../../../labs/lab_access.dart';
import '../../../labs/lab_repository.dart';
import '../../../theme/colors.dart';
import '../widgets/lab_experiment_shell.dart';

const _accent = Color(0xFF2F6F4F);
const _apiBase = 'https://api-xluju5gywq-uc.a.run.app';

/// Validación de afinidad: pruebas automáticas del puntaje del Comparador y calibración a ciegas
/// con personas (sistema contra lugares al azar). La lógica vive en labs/affinity_validation.dart.
class AffinityValidationExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const AffinityValidationExperimentPage({super.key, required this.onBack});

  @override
  State<AffinityValidationExperimentPage> createState() => _AffinityValidationExperimentPageState();
}

class _AffinityValidationExperimentPageState extends State<AffinityValidationExperimentPage> {
  // --- Pruebas automáticas ---
  bool _running = false;
  String _progress = '';
  List<AffinityCheck>? _checks;
  DateTime? _ranAt;
  int? _elapsedS;
  // Una corrida aislada puede engañar (la recuperación de un lugar conocido dio 1 de 4 y luego 4 de 4
  // con las mismas peticiones): por omisión se corre 3 veces y se marca lo que cambia entre corridas.
  int _times = 3;
  int? _ranTimes;

  // --- Calibración ---
  String _themeId = kAffinityThemes.first.id;
  bool _loadingItems = false;
  String? _calibrationError;
  List<CalibrationItem>? _items;
  final Map<String, int> _grades = {};
  bool _submitted = false;
  bool _saving = false;
  String? _saveNote;
  static List<Map<String, dynamic>>? _catalogCache;

  Future<Map<String, dynamic>> _match(Map<String, dynamic> payload) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/v1/comparador/match-test'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return {...jsonDecode(response.body) as Map<String, dynamic>, '_bytes': response.bodyBytes.length};
  }

  Future<void> _runChecks() async {
    setState(() {
      _running = true;
      _progress = 'Iniciando…';
      _checks = null;
    });
    final sw = Stopwatch()..start();
    final times = _times;
    final checks = await runAffinityChecksRepeated(_match, times: times, onProgress: (s) {
      if (mounted) setState(() => _progress = s);
    });
    if (!mounted) return;
    setState(() {
      _running = false;
      _checks = checks;
      _ranAt = DateTime.now();
      _elapsedS = sw.elapsed.inSeconds;
      _ranTimes = times;
    });
  }

  void _copyReport() {
    final report = {
      'experimento': 'validacion_afinidad',
      'fecha': _ranAt?.toIso8601String(),
      'segundos': _elapsedS,
      'corridas': _ranTimes,
      if (_checks != null) 'veredicto': verdictOf(_checks!).headline,
      'pruebas': _checks?.map((c) => c.toJson()).toList(),
    };
    Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe copiado al portapapeles.')));
  }

  Future<List<Map<String, dynamic>>> _catalog() async {
    if (_catalogCache != null) return _catalogCache!;
    final res = await http.get(Uri.parse('$_apiBase/v1/pois?limit=1000')).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final pois = ((jsonDecode(res.body) as Map)['pois'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    return _catalogCache = pois;
  }

  Future<void> _startCalibration() async {
    setState(() {
      _loadingItems = true;
      _calibrationError = null;
      _items = null;
      _grades.clear();
      _submitted = false;
      _saveNote = null;
    });
    try {
      final theme = themeById(_themeId)!;
      final results = await Future.wait([_match(theme.payload), _catalog()]);
      final ranked = rankedOf(results[0] as Map<String, dynamic>);
      final items = buildCalibrationItems(ranked, results[1] as List<Map<String, dynamic>>, math.Random());
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _calibrationError = 'No pudimos cargar los lugares: el motor no respondió. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _submitCalibration() async {
    final items = _items!;
    setState(() {
      _submitted = true;
      _saving = true;
    });
    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      uid = null; // sin Firebase (vista previa): se muestra el resultado sin guardarlo
    }
    if (uid == null || !currentLabRole.isTester) {
      setState(() {
        _saving = false;
        _saveNote = 'Este resultado no se guardó: necesitas una sesión de Ohtli Labs para que cuente en el estudio.';
      });
      return;
    }
    try {
      await LabRepository.instance.addResponse(kCalibrationStudyId, calibrationResponseId(uid, _themeId), {
        'profileId': _themeId,
        'poiIds': [for (final i in items) i.id],
        'sources': [for (final i in items) i.source],
        'ranks': [for (final i in items) i.rank],
        'grades': [for (final i in items) _grades[i.id]!],
      });
      if (mounted) setState(() => _saveNote = 'Guardado. ¡Gracias! Puedes calificar otro perfil.');
    } catch (e) {
      final dup = e.toString().contains('permission-denied');
      if (mounted) {
        setState(() => _saveNote = dup
            ? 'Ya habías calificado este perfil (solo cuenta una vez por persona). Prueba con otro.'
            : 'No se pudo guardar tu calificación. Intenta de nuevo más tarde.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabExperimentShell(
      title: 'Validación de afinidad',
      subtitle: 'Comprueba que el puntaje de afinidad del Comparador mide lo que dice medir: pruebas automáticas '
          'contra el motor y calibración a ciegas con personas, comparando contra lugares al azar.',
      category: 'Evaluación',
      status: 'NUEVO',
      statusColor: _accent,
      targetModule: 'Ohtli.quest / Recomendaciones',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAutomaticCard(),
          const SizedBox(height: 24),
          _buildCalibrationCard(),
          if (currentLabRole.isMember) ...[
            const SizedBox(height: 24),
            _CalibrationAggregate(),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pruebas automáticas

  Widget _card({required List<Widget> children}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _h(String text) => Text(text, style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700, color: OhtliColors.onyx));

  Widget _p(String text) => Text(text, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45));

  Widget _buildAutomaticCard() {
    final checks = _checks;
    final pass = checks?.where((c) => c.status == CheckStatus.pass).length ?? 0;
    final warn = checks?.where((c) => c.status == CheckStatus.warn).length ?? 0;
    final fail = checks?.where((c) => c.status == CheckStatus.fail).length ?? 0;
    return _card(children: [
      _h('1. Pruebas automáticas'),
      const SizedBox(height: 6),
      _p('Cuatro perfiles con un tema claro (cultura, noche, café, naturaleza) y variaciones controladas. '
          'Cada prueba dice qué pregunta y con qué umbral aprueba. Cada corrida tarda unos 25 s; la primera '
          'descarga además ~17 MB para la prueba de accesibilidad.'),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Corridas:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
        for (final n in const [1, 3, 5])
          ChoiceChip(
            label: Text('$n'),
            selected: _times == n,
            onSelected: _running ? null : (v) => v ? setState(() => _times = n) : null,
            selectedColor: _accent,
            disabledColor: _times == n ? _accent : OhtliColors.innerCardBg,
            showCheckmark: false,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _times == n ? Colors.white : OhtliColors.onyx),
            backgroundColor: OhtliColors.innerCardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: OhtliColors.cardBorder)),
          ),
        Text('Más corridas = más certeza de que un resultado no es casualidad.',
            style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        ElevatedButton.icon(
          onPressed: _running ? null : _runChecks,
          icon: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(checks == null ? Icons.play_arrow_rounded : Icons.refresh_rounded, size: 20),
          label: Text(_running ? 'Ejecutando…' : (checks == null ? 'Ejecutar pruebas' : 'Repetir pruebas')),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            // Desactivado (mientras corre o carga): sin esto el texto desaparecía sobre el fondo oscuro.
            disabledBackgroundColor: _accent.withValues(alpha: 0.55),
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (checks != null && !_running)
          OutlinedButton.icon(
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar informe'),
            style: OutlinedButton.styleFrom(
              foregroundColor: OhtliColors.onyx,
              side: BorderSide(color: OhtliColors.cardBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
      ]),
      if (_running) ...[
        const SizedBox(height: 12),
        _p(_progress),
      ],
      if (checks != null) ...[
        const SizedBox(height: 18),
        _verdictBanner(verdictOf(checks)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill('$pass aprobadas', CheckStatus.pass),
          _pill('$warn con aviso', CheckStatus.warn),
          _pill('$fail fallidas', CheckStatus.fail),
          if (_elapsedS != null)
            Text('${_ranTimes == 1 ? '1 corrida' : '$_ranTimes corridas'} en $_elapsedS s',
                style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
        ]),
        const SizedBox(height: 14),
        for (final c in checks) _checkTile(c),
        const SizedBox(height: 6),
        _p(_ranTimes == 1
            ? 'Con una sola corrida no se puede saber si un resultado es estable. Usa 3 o más antes de sacar conclusiones.'
            : 'Las pruebas marcadas como inestables cambiaron entre corridas: en el detalle está el resultado de cada una. '
                'Guarda el informe para comparar después de cada cambio en el motor.'),
      ],
    ]);
  }

  Widget _verdictBanner(AffinityVerdict v) {
    final (color, icon) = switch (v.level) {
      VerdictLevel.reliable => (const Color(0xFF15803D), Icons.verified_rounded),
      VerdictLevel.caveats => (const Color(0xFFB45309), Icons.report_rounded),
      VerdictLevel.unreliable => (const Color(0xFFB91C1C), Icons.gpp_bad_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('¿La afinidad es confiable? ${v.headline}',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 4),
            Text(v.explanation, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx, height: 1.45)),
          ]),
        ),
      ]),
    );
  }

  static Color _statusColor(CheckStatus s) => switch (s) {
        CheckStatus.pass => const Color(0xFF15803D),
        CheckStatus.warn => const Color(0xFFB45309),
        CheckStatus.fail => const Color(0xFFB91C1C),
      };

  static IconData _statusIcon(CheckStatus s) => switch (s) {
        CheckStatus.pass => Icons.check_circle_rounded,
        CheckStatus.warn => Icons.error_outline_rounded,
        CheckStatus.fail => Icons.cancel_rounded,
      };

  Widget _pill(String text, CheckStatus s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _statusColor(s).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_statusIcon(s), size: 14, color: _statusColor(s)),
          const SizedBox(width: 5),
          Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(s))),
        ]),
      );

  Widget _checkTile(AffinityCheck c) {
    final color = _statusColor(c.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(_statusIcon(c.status), color: color),
          title: Text('${c.title}${c.unstable ? ' · inestable' : ''}',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          subtitle: Text(c.result, style: GoogleFonts.inter(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _p(c.question),
            if (c.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final d in c.details)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(d, style: GoogleFonts.robotoMono(fontSize: 11.5, color: OhtliColors.onyx, height: 1.35)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ calibración

  Widget _buildCalibrationCard() {
    final theme = themeById(_themeId)!;
    final items = _items;
    final allGraded = items != null && items.every((i) => _grades.containsKey(i.id));
    return _card(children: [
      _h('2. Calibración a ciegas'),
      const SizedBox(height: 6),
      _p('Elige un perfil e imagina que eres esa persona. Te mostramos 12 lugares: 6 los eligió el sistema y 6 son '
          'al azar del catálogo, mezclados y sin decir cuál es cuál. Califica del 1 al 5 qué tan bien encaja cada uno. '
          'Si la afinidad funciona, los del sistema deben salir mejor calificados.'),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in kAffinityThemes)
          ChoiceChip(
            label: Text(t.label),
            selected: t.id == _themeId,
            onSelected: _loadingItems || (items != null && !_submitted)
                ? null
                : (v) {
                    if (v) {
                      setState(() {
                        _themeId = t.id;
                        _items = null;
                        _submitted = false;
                        _saveNote = null;
                        _grades.clear();
                      });
                    }
                  },
            selectedColor: _accent,
            // Desactivados mientras se califica: sin esto quedaban blanco sobre blanco.
            disabledColor: t.id == _themeId ? _accent : OhtliColors.innerCardBg,
            labelStyle: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.id == _themeId ? Colors.white : OhtliColors.onyx,
            ),
            backgroundColor: OhtliColors.innerCardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: OhtliColors.cardBorder)),
          ),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Text('Perfil: ${theme.description}',
            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx, height: 1.4)),
      ),
      const SizedBox(height: 14),
      if (items == null)
        ElevatedButton.icon(
          onPressed: _loadingItems ? null : _startCalibration,
          icon: _loadingItems
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.how_to_vote_rounded, size: 20),
          label: Text(_loadingItems ? 'Cargando lugares…' : 'Empezar a calificar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            // Desactivado (mientras corre o carga): sin esto el texto desaparecía sobre el fondo oscuro.
            disabledBackgroundColor: _accent.withValues(alpha: 0.55),
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      if (_calibrationError != null) ...[
        const SizedBox(height: 10),
        Text(_calibrationError!, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFB91C1C))),
      ],
      if (items != null) ...[
        for (var i = 0; i < items.length; i++) _itemCard(i + 1, items[i]),
        const SizedBox(height: 8),
        if (!_submitted)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: allGraded ? _submitCalibration : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _accent.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: Text(allGraded ? 'Enviar y ver resultado' : 'Califica los ${items.length - _grades.length} restantes'),
            ),
          )
        else
          _myResult(items),
      ],
    ]);
  }

  /// Misma fuente de texto para los lugares del sistema y los del azar (si no, la descripción delata
  /// cuál es cuál): el eje 1 de la ficha semántica, en español. La descripción general (a veces en
  /// inglés, de Wikipedia) solo si no hay ficha.
  static String _blurb(Map<String, dynamic> poi) {
    final axes = (poi['semantic_description'] ?? '').toString();
    final m = RegExp(r'\]:\s*([^\n]+)').firstMatch(axes);
    final axis = m?.group(1)?.trim() ?? '';
    if (axis.isNotEmpty) return axis;
    for (final k in ['editorial_summary', 'description']) {
      final v = (poi[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Widget _itemCard(int n, CalibrationItem item) {
    final poi = item.poi;
    final grade = _grades[item.id];
    final blurb = _blurb(poi);
    final reveal = _submitted;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reveal ? (item.source == 'sistema' ? _accent : OhtliColors.cardBorder) : OhtliColors.cardBorder,
          width: reveal && item.source == 'sistema' ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('$n. ${poi['name']}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          if (reveal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: item.source == 'sistema' ? _accent.withValues(alpha: 0.14) : OhtliColors.cardBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.source == 'sistema' ? 'Sistema · #${item.rank}' : 'Al azar',
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w700, color: item.source == 'sistema' ? _accent : OhtliColors.subtleText),
              ),
            ),
        ]),
        // Sin alcaldía: el ranking del sistema a veces la trae como "CDMX" y el catálogo con su nombre
        // real, lo que delataba cuáles lugares eran del sistema.
        Text((poi['category'] ?? '').toString(), style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
        if (blurb.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(blurb,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx, height: 1.4)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var g = 1; g <= 5; g++)
            ChoiceChip(
              label: Text('$g'),
              selected: grade == g,
              onSelected: _submitted ? null : (_) => setState(() => _grades[item.id] = g),
              selectedColor: _accent,
              // Tras enviar quedan desactivados: sin esto se veían como bloques blancos sin número.
              disabledColor: grade == g ? _accent : OhtliColors.cardBg,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: grade == g ? Colors.white : OhtliColors.onyx),
              backgroundColor: OhtliColors.cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: OhtliColors.cardBorder)),
            ),
          Text('1 = nada · 5 = perfecto', style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
        ]),
      ]),
    );
  }

  Widget _myResult(List<CalibrationItem> items) {
    final summary = summarizeCalibration([
      {
        'sources': [for (final i in items) i.source],
        'ranks': [for (final i in items) i.rank],
        'grades': [for (final i in items) _grades[i.id]],
      }
    ]);
    final lift = summary.lift ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tu resultado', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        const SizedBox(height: 6),
        Text(
          'Lugares del sistema: ${summary.meanSystem?.toStringAsFixed(1)} de 5 · al azar: ${summary.meanBase?.toStringAsFixed(1)} de 5.',
          style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        _p(lift > 0
            ? 'Para ti, el sistema le ganó al azar por ${lift.toStringAsFixed(1)} puntos. Arriba marcamos cuáles eran del sistema.'
            : lift == 0
                ? 'Para ti, el sistema empató con el azar. Arriba marcamos cuáles eran del sistema.'
                : 'Para ti, el azar salió mejor que el sistema. Es justo lo que este estudio busca detectar.'),
        if (_saving) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(color: _accent),
        ],
        if (_saveNote != null) ...[
          const SizedBox(height: 8),
          _p(_saveNote!),
        ],
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                    _items = null;
                    _submitted = false;
                    _saveNote = null;
                    _grades.clear();
                  }),
          style: OutlinedButton.styleFrom(
            foregroundColor: OhtliColors.onyx,
            side: BorderSide(color: OhtliColors.cardBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Calificar otro perfil'),
        ),
      ]),
    );
  }
}

/// Resultados de todas las calibraciones (solo miembros del laboratorio: las reglas solo les dejan
/// leer las respuestas de todos).
class _CalibrationAggregate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: LabRepository.instance.watchResponses(kCalibrationStudyId),
      builder: (context, snap) {
        final docs = snap.data?.docs.map((d) => d.data()).toList() ?? const <Map<String, dynamic>>[];
        final all = summarizeCalibration(docs);
        final byProfile = summarizeCalibrationByProfile(docs);
        final ci = all.liftCi95;
        final p = all.signTestP;
        final (conclusion, conclusionColor) = all.sessions == 0
            ? ('Todavía no hay calificaciones.', OhtliColors.subtleText)
            : all.beatsRandom
                ? ('Hay evidencia de que el sistema supera al azar (p < 0.05 y el intervalo no incluye el 0).',
                    const Color(0xFF15803D))
                : (all.wins + all.losses >= 10 && p != null && p < 0.05 && all.losses > all.wins)
                    ? ('El azar está superando al sistema: la afinidad no está funcionando.', const Color(0xFFB91C1C))
                    : ('Aún no hay evidencia suficiente: hacen falta más sesiones o la diferencia es pequeña.',
                        const Color(0xFFB45309));
        String f(double? v, [int d = 2]) => v == null ? '—' : v.toStringAsFixed(d);
        String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(0)} %';
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text(k, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText))),
                Text(v, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
              ]),
            );
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('3. Resultados de la calibración (laboratorio)',
                style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            const SizedBox(height: 6),
            Text(
              'Solo lo ven los miembros del laboratorio. Con pocas sesiones los números cambian mucho: '
              'como referencia, junta al menos 20 antes de sacar conclusiones.',
              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, height: 1.4),
            ),
            if (snap.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('No se pudieron leer las respuestas.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFB91C1C))),
              ),
            const SizedBox(height: 6),
            row('Sesiones', '${all.sessions}'),
            row('Calificación promedio · sistema', f(all.meanSystem)),
            row('Calificación promedio · al azar', f(all.meanBase)),
            row('Ventaja del sistema (puntos)', all.lift == null ? '—' : '${all.lift! >= 0 ? '+' : ''}${f(all.lift)}'),
            row('Relevantes (4–5) · sistema', pct(all.relevantSystem)),
            row('Relevantes (4–5) · al azar', pct(all.relevantBase)),
            row('Sesiones ganadas / empatadas / perdidas', '${all.wins} / ${all.ties} / ${all.losses}'),
            row('Spearman posición ↔ calificación', f(all.rankCorrelation)),
            row('Prueba de signos (p)', p == null ? '—' : (p < 0.001 ? '< 0.001' : p.toStringAsFixed(3))),
            row('Ventaja · intervalo 95 %', ci == null ? '— (mínimo 3 sesiones)' : '${f(ci.$1)} a ${f(ci.$2)}'),
            const SizedBox(height: 10),
            Text(conclusion, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: conclusionColor, height: 1.4)),
            if (byProfile.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Por perfil', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
              for (final e in byProfile.entries)
                row(
                  themeById(e.key)?.label ?? e.key,
                  '${e.value.sessions} ses. · ${f(e.value.meanSystem, 1)} vs ${f(e.value.meanBase, 1)}'
                      '${e.value.signTestP == null ? '' : ' · p ${e.value.signTestP! < 0.001 ? '< 0.001' : e.value.signTestP!.toStringAsFixed(2)}'}',
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'Cómo leerlo: la afinidad sirve si el sistema supera al azar con p < 0.05, el intervalo de la ventaja queda '
              'por encima de 0 y la correlación es positiva (el 1.º del ranking recibe mejores calificaciones que el 6.º). '
              'Un perfil que se queda atrás señala dónde falla la afinidad.',
              style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText, height: 1.4),
            ),
          ]),
        );
      },
    );
  }
}

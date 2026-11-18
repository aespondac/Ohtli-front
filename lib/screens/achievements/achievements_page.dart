import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/achievement_rarity.dart';
import '../../services/achievements_service.dart';
import '../../services/ohtli_features.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_ui.dart';

/// Logros: la vitrina de títulos de viajero. Es una función en prueba (`logros` en lab_features).
/// Cada título muestra su nombre, qué significa en náhuatl, cómo se consigue, su rareza y, si ya
/// se ganó, cuándo y cuánto tardó. Los otorga el motor (docs/logros.md).
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FeatureAccess>(
      valueListenable: OhtliFeatures.instance.access,
      builder: (context, access, _) {
        final pad = OhtliUi.pagePadding(MediaQuery.of(context).size.width);
        if (!access.isOn(kFeatureLogros)) {
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, 40, pad, 40),
            child: const OhtliEmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Logros todavía está en prueba',
              message: 'Por ahora solo la ven los testers del estudio que la evalúa.',
            ),
          );
        }
        return const _AchievementsView();
      },
    );
  }
}

// ───────────── Catálogo de presentación ─────────────

enum _Group { explorar, crear, acompanado, mejorar, constancia, especiales, proximamente }

extension on _Group {
  (String, String, IconData) get info => switch (this) {
        _Group.explorar => ('EXPLORA', 'Recorre la ciudad', Icons.explore_outlined),
        _Group.crear => ('CUENTA', 'Crea y comparte', Icons.auto_stories_outlined),
        _Group.acompanado => ('ACOMPAÑA', 'Viaja acompañado', Icons.groups_outlined),
        _Group.mejorar => ('APORTA', 'Mejora Ohtli', Icons.handyman_outlined),
        _Group.constancia => ('VUELVE', 'Constancia', Icons.event_repeat_outlined),
        _Group.especiales => ('ESPECIALES', 'Títulos especiales', Icons.auto_awesome_outlined),
        _Group.proximamente => ('PRÓXIMAMENTE', 'Llegan con nuevas funciones', Icons.hourglass_top_rounded),
      };
}

/// Grupo e ícono de cada título (los que no estén aquí van a "Especiales").
const Map<String, (_Group, IconData)> _kMeta = {
  'pochtecatl': (_Group.explorar, Icons.hiking_rounded),
  'recorre_alcaldias': (_Group.explorar, Icons.map_outlined),
  'ichtaca': (_Group.explorar, Icons.travel_explore_rounded),
  'de_todo_un_poco': (_Group.explorar, Icons.category_outlined),
  'a_pie_bici_auto': (_Group.explorar, Icons.directions_bike_rounded),
  'madrugador_noctambulo': (_Group.explorar, Icons.nights_stay_outlined),
  'tlapalehuiani': (_Group.explorar, Icons.accessible_forward_rounded),
  'tlacuilo': (_Group.crear, Icons.edit_note_rounded),
  'citlalli': (_Group.crear, Icons.star_outline_rounded),
  'tlahuilli': (_Group.crear, Icons.lightbulb_outline_rounded),
  'momentos': (_Group.crear, Icons.photo_library_outlined),
  'cencalli': (_Group.acompanado, Icons.diversity_3_rounded),
  'calpixqui': (_Group.acompanado, Icons.cottage_outlined),
  'tlahtocan': (_Group.acompanado, Icons.how_to_vote_outlined),
  'tetlauhtilli': (_Group.acompanado, Icons.card_giftcard_rounded),
  'tlamatini': (_Group.mejorar, Icons.flag_outlined),
  'altepetl': (_Group.mejorar, Icons.fact_check_outlined),
  'nemactia': (_Group.mejorar, Icons.add_a_photo_outlined),
  'tlanemmaca': (_Group.mejorar, Icons.photo_outlined),
  'calpulli': (_Group.mejorar, Icons.add_location_alt_outlined),
  'tlapohuani': (_Group.mejorar, Icons.playlist_add_check_rounded),
  'tlachixqui': (_Group.mejorar, Icons.thumbs_up_down_outlined),
  'amini': (_Group.mejorar, Icons.bug_report_outlined),
  'altepetlahtolli': (_Group.mejorar, Icons.science_outlined),
  'primera_mano': (_Group.mejorar, Icons.verified_outlined),
  'tozquitl': (_Group.mejorar, Icons.record_voice_over_outlined),
  'insider_fundador': (_Group.mejorar, Icons.workspace_premium_outlined),
  'xiuhpohualli': (_Group.constancia, Icons.wb_sunny_outlined),
  'cexihuitl': (_Group.constancia, Icons.cake_outlined),
  'viajero': (_Group.especiales, Icons.backpack_outlined),
  'ometeotl': (_Group.especiales, Icons.all_inclusive_rounded),
  'guia': (_Group.proximamente, Icons.person_add_alt_outlined),
  'namictli': (_Group.proximamente, Icons.favorite_border_rounded),
  'ixpopoyotl': (_Group.proximamente, Icons.visibility_off_outlined),
  'tlaxtlahuilli': (_Group.proximamente, Icons.receipt_long_outlined),
};

/// Significado en náhuatl (si el título lo es) y cómo se consigue. Lo que no esté aquí usa la
/// descripción del catálogo.
const Map<String, (String?, String)> _kInfo = {
  'viajero': (null, 'Crea tu cuenta en Ohtli.'),
  'ometeotl': ('La dualidad, origen de todo lo que existe', 'Título especial que otorga Ohtli.'),
  'pochtecatl_1': ('El comerciante viajero', 'Completa 3 viajes.'),
  'pochtecatl_2': ('El comerciante viajero', 'Completa 10 viajes.'),
  'pochtecatl_3': ('El comerciante viajero', 'Completa 25 viajes.'),
  'recorre_alcaldias': (null, 'Visita lugares en las 16 alcaldías de la Ciudad de México.'),
  'ichtaca': ('Lo escondido', 'Visita 10 lugares que casi nadie visita.'),
  'de_todo_un_poco': (null, 'Visita lugares de 5 categorías distintas.'),
  'a_pie_bici_auto': (null, 'Completa viajes con traslados a pie, en bici y en auto.'),
  'madrugador_noctambulo': (null, 'Haz un viaje que empiece antes de las 8 o termine después de las 22.'),
  'tlapalehuiani': ('El que ayuda', 'Al reseñar un viaje, califica si los lugares fueron accesibles.'),
  'tlacuilo_1': ('El que pinta los códices', 'Publica tu primera crónica de viaje con fotos.'),
  'tlacuilo_2': ('El que pinta los códices', 'Publica 5 crónicas de viaje con fotos.'),
  'tlacuilo_3': ('El que pinta los códices', 'Publica 15 crónicas de viaje con fotos.'),
  'citlalli': ('Estrella', 'Que uno de tus viajes aparezca en los destacados de Explorar.'),
  'cencalli': ('La familia, la casa entera', 'Edita un viaje en vivo con otra persona.'),
  'tlahuilli': ('Luz', 'Que otra persona use uno de tus viajes como base para el suyo.'),
  'momentos': (null, 'Llena los 12 momentos de tu perfil.'),
  'calpixqui': ('El que organiza la casa', 'Organiza un viaje grupal que sí se realice.'),
  'tlahtocan': ('El consejo', 'Que tu grupo vote y complete el viaje elegido.'),
  'tetlauhtilli': ('El regalo', 'Prepara un viaje sorpresa que su destinatario abra.'),
  'tlamatini': ('La persona que sabe', 'Avisa qué falta o está mal en un lugar.'),
  'tlamatini_2': ('La persona que sabe', 'Que 5 de tus reportes de lugares se aprueben.'),
  'tlamatini_3': ('La persona que sabe', 'Que 20 de tus reportes de lugares se aprueben.'),
  'altepetl': ('El pueblo, la ciudad', 'Que uno de tus reportes corrija un lugar.'),
  'nemactia': ('Dar, ofrecer', 'Dona una foto de un lugar.'),
  'tlanemmaca': ('El don, lo que se ofrece', 'Que tu foto donada sea la imagen de un lugar.'),
  'calpulli': ('El barrio, la casa grande', 'Suma a Ohtli un lugar que no estaba.'),
  'tlapohuani': ('El que cuenta', 'Suma 10 lugares nuevos aprobados al catálogo.'),
  'tlachixqui': ('El que observa', 'Califica 20 lugares que te recomendó la IA.'),
  'amini': ('El cazador', 'Que un comentario tuyo se convierta en un arreglo publicado.'),
  'altepetlahtolli': ('La palabra de la ciudad', 'Responde un estudio de Ohtli Labs.'),
  'primera_mano': (null, 'Participa en un estudio de Labs cuya función se vuelva oficial.'),
  'tozquitl': ('La voz', 'Valida los resultados de un estudio de Labs.'),
  'insider_fundador': (null, 'Prueba una función desde su beta hasta que se vuelva oficial.'),
  'xiuhpohualli': ('La cuenta del año', 'Viaja en las cuatro estaciones del año.'),
  'cexihuitl': ('Un año', 'Cumple un año en Ohtli con al menos un viaje.'),
  'guia': (null, 'Invita a un amigo y que complete su primer viaje.'),
  'namictli': ('La pareja', 'Haz un viaje en pareja.'),
  'ixpopoyotl': ('Ciego', 'Ve a una cita a ciegas organizada por Ohtli.'),
  'tlaxtlahuilli': ('La paga', 'Reparte los gastos de un viaje entre quienes fueron.'),
};

/// Títulos con niveles: se muestran en una sola tarjeta.
const Map<String, List<String>> _kFamilies = {
  'pochtecatl': ['pochtecatl_1', 'pochtecatl_2', 'pochtecatl_3'],
  'tlacuilo': ['tlacuilo_1', 'tlacuilo_2', 'tlacuilo_3'],
  'tlamatini': ['tlamatini', 'tlamatini_2', 'tlamatini_3'],
};

/// Una tarjeta de la vitrina (un título o una familia con niveles).
class _Badge {
  final String key;
  final String name;
  final String? meaning;
  final String how;
  final _Group group;
  final IconData icon;
  final int levels; // 1 = sin niveles
  final int earnedLevels;
  final AchievementProgress? progress; // hacia el siguiente nivel
  final bool comingSoon;
  final bool active; // es el título que muestra en su perfil
  final DateTime? earnedAt; // del último nivel ganado
  final Duration? took; // cuánto tardó (solo metas de más de un paso)
  final double? percent; // % de viajeros que lo tienen (del nivel que se muestra)
  final int holders;
  const _Badge({
    required this.key,
    required this.name,
    required this.meaning,
    required this.how,
    required this.group,
    required this.icon,
    this.levels = 1,
    this.earnedLevels = 0,
    this.progress,
    this.comingSoon = false,
    this.active = false,
    this.earnedAt,
    this.took,
    this.percent,
    this.holders = 0,
  });

  bool get earned => earnedLevels > 0;
  bool get complete => earnedLevels >= levels;
  double get ratio => complete ? 1 : (progress?.ratio ?? 0);
  Rarity? get rarity => comingSoon || percent == null ? null : rarityOf(percent!);
}

String _baseName(String name) => name.replaceAll(RegExp(r'\s+(I{1,3})$'), '');

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

class _Data {
  final Map<String, Map<String, dynamic>> titles;
  final Set<String> owned;
  final String activeId;
  final Map<String, dynamic> log; // achievementLog
  final Map<String, AchievementProgress> prog;
  final int? totalUsers;
  final DateTime? accountCreated;
  const _Data(this.titles, this.owned, this.activeId, this.log, this.prog, this.totalUsers, this.accountCreated);

  DateTime? earnedAt(String id) => _date((log[id] as Map?)?['earnedAt']);

  /// Desde que tuvo el primer avance (o, sin ese dato, desde que creó su cuenta) hasta que lo ganó.
  Duration? took(String id, {String? startId}) {
    final end = earnedAt(id);
    final start = _date((log[startId ?? id] as Map?)?['startedAt']);
    if (end == null || start == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  _Badge badge({
    required String key,
    required List<String> ids,
  }) {
    final meta = _kMeta[key];
    final earnedIds = ids.where(owned.contains).toList();
    final earnedCount = earnedIds.length;
    final shownId = earnedCount == 0 ? ids.first : (earnedCount < ids.length ? ids[earnedCount] : ids.last);
    final lastEarned = earnedCount == 0 ? null : earnedIds.last;
    final t = titles[shownId] ?? const {};
    final info = _kInfo[shownId];
    final soon = t['comingSoon'] == true || meta?.$1 == _Group.proximamente;
    // La rareza que se muestra es la del nivel más alto que ya tiene (o la del primero si ninguno).
    final rarityId = lastEarned ?? ids.first;
    final holders = (titles[rarityId]?['holders'] as num?)?.toInt();
    return _Badge(
      key: key,
      name: ids.length > 1 ? _baseName((titles[ids.first]?['name'] ?? key).toString()) : (t['name'] ?? key).toString(),
      meaning: info?.$1,
      how: info?.$2 ?? (t['description'] ?? '').toString(),
      group: soon ? _Group.proximamente : (meta?.$1 ?? _Group.especiales),
      icon: meta?.$2 ?? Icons.auto_awesome_outlined,
      levels: ids.length,
      earnedLevels: earnedCount,
      progress: prog[shownId],
      comingSoon: soon,
      active: ids.contains(activeId),
      earnedAt: lastEarned == null ? null : earnedAt(lastEarned),
      // Solo los de varios pasos tienen inicio (achievementLog.{id}.startedAt; en niveles, el del primero).
      took: lastEarned == null ? null : took(lastEarned, startId: ids.first),
      percent: holdersPercent(holders, totalUsers),
      holders: holders ?? 0,
    );
  }

  List<_Badge> badges() {
    final inFamily = {for (final f in _kFamilies.values) ...f};
    return [
      for (final fam in _kFamilies.entries)
        if (fam.value.any(titles.containsKey)) badge(key: fam.key, ids: fam.value.where(titles.containsKey).toList()),
      for (final e in titles.entries)
        if (!inFamily.contains(e.key) && e.value['hidden'] != true) badge(key: e.key, ids: [e.key]),
    ];
  }
}

// ───────────── Vista ─────────────

enum _Filter { todos, ganados, porGanar }

enum _Sort { tema, rareza }

class _AchievementsView extends StatefulWidget {
  const _AchievementsView();

  @override
  State<_AchievementsView> createState() => _AchievementsViewState();
}

class _AchievementsViewState extends State<_AchievementsView> {
  final _db = FirebaseFirestore.instance;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _titles = _db.collection('titles').snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stats = _db.collection('app_config').doc('achievements').snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _user;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _user = _db.collection('users').doc(uid).snapshots();
    // El motor revisa los logros (y otorga los que ya se ganaron) cada vez que se abre.
    AchievementsService.instance.evaluate();
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _user,
      builder: (context, userSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _titles,
        builder: (context, titleSnap) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _stats,
          builder: (context, statsSnap) => ValueListenableBuilder<Map<String, AchievementProgress>>(
            valueListenable: AchievementsService.instance.progress,
            builder: (context, prog, _) {
              final user = userSnap.data?.data() ?? const {};
              return AchievementsBoard(
                loading: !titleSnap.hasData,
                titles: {for (final d in titleSnap.data?.docs ?? const []) d.id: d.data()},
                owned: {for (final t in (user['possessedTitles'] as List?) ?? const ['viajero']) t.toString()},
                activeId: (user['activeTitleId'] ?? 'viajero').toString(),
                log: (user['achievementLog'] as Map?)?.cast<String, dynamic>() ?? const {},
                progress: prog,
                totalUsers: (statsSnap.data?.data()?['totalUsers'] as num?)?.toInt(),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// La vitrina con los datos ya cargados (se puede probar sin Firebase).
class AchievementsBoard extends StatefulWidget {
  final bool loading;
  final Map<String, Map<String, dynamic>> titles;
  final Set<String> owned;
  final String activeId;
  final Map<String, dynamic> log;
  final Map<String, AchievementProgress> progress;
  final int? totalUsers;
  const AchievementsBoard({
    super.key,
    this.loading = false,
    required this.titles,
    required this.owned,
    required this.activeId,
    required this.log,
    required this.progress,
    required this.totalUsers,
  });

  @override
  State<AchievementsBoard> createState() => _AchievementsBoardState();
}

class _AchievementsBoardState extends State<AchievementsBoard> {
  _Filter _filter = _Filter.todos;
  _Sort _sort = _Sort.tema;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final pad = OhtliUi.pagePadding(width);
    final isMobile = width < 760;
    final w = widget;
    final data = _Data(w.titles, w.owned, w.activeId, w.log, w.progress, w.totalUsers, null);
    final badges = data.badges();
    final loading = w.loading;
    final earnedCount = data.titles.keys.where(data.owned.contains).length;
    final total = data.titles.values.where((t) => t['comingSoon'] != true && t['hidden'] != true).length;
    final activeName = (data.titles[data.activeId]?['name'] ?? 'Viajero').toString();
    final closest = (badges.where((b) => !b.complete && !b.comingSoon && (b.progress?.value ?? 0) > 0).toList()
          ..sort((a, b) => b.ratio.compareTo(a.ratio)))
        .firstOrNull;
    final rarest = (badges.where((b) => b.earned && b.percent != null).toList()
          ..sort((a, b) => a.percent!.compareTo(b.percent!)))
        .firstOrNull;

    bool show(_Badge b) => switch (_filter) {
          _Filter.todos => true,
          _Filter.ganados => b.earned,
          _Filter.porGanar => !b.complete,
        };
    int order(_Badge a, _Badge b) {
      if (a.earned != b.earned) return a.earned ? -1 : 1;
      return b.ratio.compareTo(a.ratio);
    }

    final visible = badges.where(show).toList();
    final sections = <(String, String, IconData, List<_Badge>, bool)>[
      if (_sort == _Sort.tema) ...[
        for (final g in _Group.values)
          if (visible.any((b) => b.group == g))
            (g.info.$1, g.info.$2, g.info.$3, visible.where((b) => b.group == g).toList()..sort(order), g != _Group.proximamente),
      ] else ...[
        for (final r in Rarity.values)
          if (visible.any((b) => b.rarity == r))
            (r.label.toUpperCase(), _rarityTitle(r), Icons.diamond_outlined, visible.where((b) => b.rarity == r).toList()..sort(order), true),
        if (visible.any((b) => b.rarity == null))
          ('SIN DATOS', 'Próximamente o sin recuento', Icons.hourglass_top_rounded, visible.where((b) => b.rarity == null).toList(), false),
      ],
    ];

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, isMobile ? 24 : 36, pad, 0),
        sliver: SliverToBoxAdapter(
          child: _Header(
            isMobile: isMobile,
            summary: loading ? 'Cargando tus títulos…' : 'Has ganado $earnedCount de $total títulos. En tu perfil muestras «$activeName».',
            filter: _filter,
            sort: _sort,
            onFilter: (f) => setState(() => _filter = f),
            onSort: (s) => setState(() => _sort = s),
          ),
        ),
      ),
      if (!loading)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 22, pad, 0),
          sliver: SliverToBoxAdapter(
            child: _Summary(
              earned: earnedCount,
              pending: total - earnedCount,
              rarest: rarest,
              closest: closest,
              isMobile: isMobile,
            ),
          ),
        ),
      if (loading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())))
      else
        for (final s in sections)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 34, pad, 0),
            sliver: SliverToBoxAdapter(
              child: _Section(eyebrow: s.$1, title: s.$2, icon: s.$3, badges: s.$4, showCount: s.$5),
            ),
          ),
      const SliverToBoxAdapter(child: SizedBox(height: 72)),
    ]);
  }
}

String _rarityTitle(Rarity r) => switch (r) {
      Rarity.legendario => 'Casi nadie los tiene',
      Rarity.epico => 'Muy difíciles',
      Rarity.raro => 'Para pocos',
      Rarity.pocoComun => 'Poco comunes',
      Rarity.comun => 'Los más comunes',
    };

class _Header extends StatelessWidget {
  final bool isMobile;
  final String summary;
  final _Filter filter;
  final _Sort sort;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<_Sort> onSort;
  const _Header({
    required this.isMobile,
    required this.summary,
    required this.filter,
    required this.sort,
    required this.onFilter,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final controls = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final (f, label) in const [(_Filter.todos, 'Todos'), (_Filter.ganados, 'Ganados'), (_Filter.porGanar, 'Por ganar')])
        OhtliChoiceChip(label: label, selected: filter == f, onTap: () => onFilter(f)),
      const SizedBox(width: 6),
      for (final (s, label, icon) in const [(_Sort.tema, 'Por tema', Icons.grid_view_rounded), (_Sort.rareza, 'Por rareza', Icons.diamond_outlined)])
        OhtliChoiceChip(label: label, icon: icon, selected: sort == s, onTap: () => onSort(s)),
    ]);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.emoji_events_rounded, size: 14, color: OhtliColors.accentText),
        const SizedBox(width: 6),
        Text('TU VITRINA DE VIAJERO', style: OhtliUi.eyebrow(OhtliColors.accentText)),
      ]),
      const SizedBox(height: 8),
      Text('Logros', style: OhtliUi.title(size: isMobile ? 28 : 38)),
      const SizedBox(height: 4),
      Text(summary, style: OhtliUi.body(size: isMobile ? 13.5 : 15)),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 18), controls]);
  }
}

/// Numeralia (número + texto, sin íconos ni fondos), el más raro y el más cercano.
class _Summary extends StatelessWidget {
  final int earned;
  final int pending;
  final _Badge? rarest;
  final _Badge? closest;
  final bool isMobile;
  const _Summary({required this.earned, required this.pending, required this.rarest, required this.closest, required this.isMobile});

  Widget _stat(String n, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(n, style: OhtliUi.title(size: isMobile ? 26 : 32)),
        Text(label, style: OhtliUi.body(size: 13)),
      ]);

  Widget _spot(String eyebrow, _Badge b, Widget detail) => OhtliSurface(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          _Medallion(icon: b.icon, earned: b.earned, highlight: !b.earned),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eyebrow, style: OhtliUi.eyebrow(OhtliColors.accentText)),
              const SizedBox(height: 3),
              Text(b.name, style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              const SizedBox(height: 6),
              detail,
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final stats = Row(children: [
      _stat('$earned', 'ganados'),
      SizedBox(width: isMobile ? 28 : 40),
      _stat('$pending', 'por ganar'),
    ]);
    final spots = [
      if (rarest != null)
        _spot('TU TÍTULO MÁS RARO', rarest!, _RarityTag(badge: rarest!)),
      if (closest != null) _spot('TE FALTA POCO', closest!, _ProgressBar(progress: closest!.progress!)),
    ];
    if (isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        stats,
        for (final s in spots) ...[const SizedBox(height: 14), s],
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: stats)),
        for (final s in spots) ...[const SizedBox(width: 14), Expanded(flex: 4, child: s)],
        if (spots.length < 2) for (var i = spots.length; i < 2; i++) ...[const SizedBox(width: 14), const Expanded(flex: 4, child: SizedBox())],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String eyebrow;
  final String title;
  final IconData icon;
  final List<_Badge> badges;
  final bool showCount;
  const _Section({required this.eyebrow, required this.title, required this.icon, required this.badges, required this.showCount});

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((b) => b.earned).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OhtliSectionHeader(
        eyebrow: eyebrow,
        title: title,
        icon: icon,
        trailing: showCount
            ? Text('$earned de ${badges.length}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.subtleText))
            : null,
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 980 ? 3 : (c.maxWidth > 600 ? 2 : 1);
        const gap = 14.0;
        // Filas con tarjetas del mismo alto.
        return Column(children: [
          for (var i = 0; i < badges.length; i += cols)
            Padding(
              padding: EdgeInsets.only(bottom: i + cols < badges.length ? gap : 0),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    Expanded(child: i + j < badges.length ? _BadgeCard(badge: badges[i + j]) : const SizedBox.shrink()),
                  ],
                ]),
              ),
            ),
        ]);
      }),
    ]);
  }
}

class _BadgeCard extends StatelessWidget {
  final _Badge badge;
  const _BadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return OhtliSurface(
      selected: b.active,
      accent: OhtliColors.accent,
      padding: const EdgeInsets.all(18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Medallion(icon: b.icon, earned: b.earned, dimmed: b.comingSoon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Título (y niveles)
            Row(children: [
              Flexible(
                child: Text(b.name,
                    style: GoogleFonts.outfit(
                        fontSize: 17, fontWeight: FontWeight.w800, color: b.earned ? OhtliColors.onyx : OhtliColors.onyx.withValues(alpha: 0.8))),
              ),
              if (b.levels > 1) ...[const SizedBox(width: 8), _LevelPips(levels: b.levels, earned: b.earnedLevels)],
            ]),
            // Qué significa en náhuatl
            if (b.meaning != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('«${b.meaning}»',
                    style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, color: OhtliColors.accentText)),
              ),
            const SizedBox(height: 8),
            // Cómo se consigue
            Text(b.how, style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: OhtliColors.onyx.withValues(alpha: 0.82))),
            const Spacer(),
            const SizedBox(height: 14),
            _footer(b),
            if (!b.comingSoon && b.percent != null) ...[const SizedBox(height: 10), _RarityTag(badge: b)],
          ]),
        ),
      ]),
    );
  }

  Widget _footer(_Badge b) {
    if (b.comingSoon) return const _Tag(label: 'Próximamente', icon: Icons.hourglass_top_rounded);
    final p = b.progress;
    final stillLeveling = b.earned && !b.complete && p != null && p.goal > 1;
    if (b.earned && !stillLeveling) return _EarnedLine(badge: b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (stillLeveling) ...[_EarnedLine(badge: b), const SizedBox(height: 10)],
      if (p != null && p.goal > 1)
        _ProgressBar(progress: p, prefix: b.levels > 1 ? 'Nivel ${b.earnedLevels + 1}: ' : '')
      else
        const _Tag(label: 'Por ganar', icon: Icons.lock_outline_rounded),
    ]);
  }
}

/// "Lo conseguiste el 17 nov 2026 · te tomó 3 semanas" (y si es el de su perfil).
class _EarnedLine extends StatelessWidget {
  final _Badge badge;
  const _EarnedLine({required this.badge});

  @override
  Widget build(BuildContext context) {
    final b = badge;
    final parts = <String>[
      if (b.levels > 1) 'Nivel ${b.earnedLevels} de ${b.levels}',
      if (b.earnedAt != null) 'Lo conseguiste el ${shortDate(b.earnedAt!)}' else 'Conseguido',
      if (b.took != null) 'te tomó ${durationText(b.took!)}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _Tag(label: parts.join(' · '), icon: Icons.check_circle_rounded, color: tealText),
      if (b.active) ...[const SizedBox(height: 6), _Tag(label: 'En tu perfil', icon: Icons.person_pin_rounded, color: OhtliColors.accentText)],
    ]);
  }
}

class _RarityTag extends StatelessWidget {
  final _Badge badge;
  const _RarityTag({required this.badge});

  @override
  Widget build(BuildContext context) {
    final r = badge.rarity;
    if (r == null) return const SizedBox.shrink();
    // Row, no Wrap: la tarjeta mide su alto con IntrinsicHeight y Wrap no lo soporta.
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: r.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: r.color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.diamond_outlined, size: 12, color: r.color),
          const SizedBox(width: 4),
          Text(r.label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: r.color)),
        ]),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(holdersText(badge.holders, badge.percent!),
            style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
      ),
    ]);
  }
}

class _Medallion extends StatelessWidget {
  final IconData icon;
  final bool earned;
  final bool dimmed;
  final bool highlight;
  const _Medallion({required this.icon, required this.earned, this.dimmed = false, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: earned
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [OhtliColors.accentFill, OhtliColors.accentFill.withValues(alpha: 0.72)],
              )
            : null,
        color: earned ? null : (highlight ? OhtliColors.accent.withValues(alpha: 0.14) : OhtliColors.innerCardBg),
        border: earned ? null : Border.all(color: OhtliColors.cardBorder),
        boxShadow: earned ? [BoxShadow(color: OhtliColors.accentFill.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))] : null,
      ),
      child: Icon(
        icon,
        size: 23,
        color: earned ? Colors.white : (highlight ? OhtliColors.accentText : OhtliColors.subtleText.withValues(alpha: dimmed ? 0.55 : 0.9)),
      ),
    );
  }
}

class _LevelPips extends StatelessWidget {
  final int levels;
  final int earned;
  const _LevelPips({required this.levels, required this.earned});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Nivel $earned de $levels',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < levels; i++)
            Container(
              margin: const EdgeInsets.only(right: 3),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < earned ? OhtliColors.accent : Colors.transparent,
                border: Border.all(color: i < earned ? OhtliColors.accent : OhtliColors.subtleText.withValues(alpha: 0.6)),
              ),
            ),
        ]),
      );
}

class _ProgressBar extends StatelessWidget {
  final AchievementProgress progress;
  final String prefix;
  const _ProgressBar({required this.progress, this.prefix = ''});

  @override
  Widget build(BuildContext context) {
    final shown = progress.value > progress.goal ? progress.goal : progress.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: progress.ratio,
          minHeight: 7,
          backgroundColor: OhtliColors.innerCardBg,
          color: OhtliColors.accent,
        ),
      ),
      const SizedBox(height: 6),
      Text('$prefix$shown de ${progress.goal}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.subtleText)),
    ]);
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  const _Tag({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? OhtliColors.subtleText;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: c)),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12, height: 1.35, fontWeight: FontWeight.w700, color: c))),
    ]);
  }
}

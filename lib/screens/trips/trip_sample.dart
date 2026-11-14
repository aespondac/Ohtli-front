import 'dart:async';

import '../../models/trip_model.dart';
import '../../services/trip_social_service.dart';
import '../../theme/cdmx_photos.dart';

/// Viaje de muestra: reúne todos los elementos de un viaje publicado (portada, texto,
/// texto con imagen, paradas con y sin fotos, traslados en varios modos, mensajes y
/// reacciones) para revisar el diseño sin depender de datos reales. Se abre en /muestra.
/// Nada de lo que se haga en él se guarda.
const String kSampleTripId = 'muestra';
const String kSampleOwnerId = 'muestra-ana';
const String kSampleMyUid = 'muestra-tu';
const String kSampleMyName = 'Tú';

enum SampleStage { antes, durante, despues }

extension SampleStageLabel on SampleStage {
  String get label => switch (this) {
        SampleStage.antes => 'Antes',
        SampleStage.durante => 'Durante',
        SampleStage.despues => 'Después',
      };
}

class TripSample {
  TripSample._();

  static String _photo(String category, int i) => CdmxPhotos.byCategory[category]![i];

  static DateTime _day(SampleStage stage) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (stage) {
      SampleStage.antes => today.add(const Duration(days: 6)),
      SampleStage.durante => today,
      SampleStage.despues => today.subtract(const Duration(days: 3)),
    };
  }

  static Trip trip(SampleStage stage) {
    final day = _day(stage);
    return Trip(
      id: kSampleTripId,
      userId: kSampleOwnerId,
      title: 'Un sábado de la Roma a Coyoacán',
      description: 'Viaje de muestra de Ohtli: café, parque, museo, tacos y cantina en un mismo día. '
          'Aquí se ve cómo luce cada parte de un viaje publicado.',
      coverUrl: CdmxPhotos.covers[0],
      status: 'published',
      visibility: 'public',
      createdAt: day.subtract(const Duration(days: 12)),
      updatedAt: day.subtract(const Duration(days: 1)),
      travelDate: day,
      coAuthorIds: const ['muestra-luis', kSampleMyUid],
      coAuthorNames: const ['Luis Ramírez', kSampleMyName],
      surpriseTargetIds: const ['muestra-mar'],
      surpriseTargetNames: const ['Mar'],
      reviewedAt: stage == SampleStage.despues ? day.add(const Duration(days: 1)) : null,
    );
  }

  static Map<String, dynamic> get author => {'uid': kSampleOwnerId, 'displayName': 'Ana López', 'photoURL': null};

  static List<Map<String, dynamic>> get coAuthors => [
        {'uid': 'muestra-luis', 'displayName': 'Luis Ramírez', 'photoURL': null, 'title': 'Viajero'},
        {'uid': kSampleMyUid, 'displayName': kSampleMyName, 'photoURL': null, 'title': 'Viajero'},
      ];

  /// Paradas visitadas según la etapa.
  static Set<String> visited(SampleStage stage) => switch (stage) {
        SampleStage.antes => <String>{},
        SampleStage.durante => {'p1', 'p2', 'd1', 'p3', 'p4'},
        SampleStage.despues => {'p1', 'p2', 'd1', 'p3', 'p4', 'p5', 'p6'},
      };

  /// Horas reales (llegada, salida) registradas con "Llegué" / "Ya me voy".
  static const Map<String, (String, String?)> _times = {
    'p1': ('09:04', '09:52'),
    'p2': ('10:06', '10:58'),
    'd1': ('11:01', '11:15'),
    'p3': ('11:42', '12:55'),
    'p4': ('13:08', null), // durante: aquí están ahora
    'p5': ('15:10', '16:40'),
    'p6': ('16:55', '19:20'),
  };

  static List<TripSection> sections(SampleStage stage) {
    final done = visited(stage);
    final bool after = stage == SampleStage.despues;
    // Desde el día del viaje se califica cada parada al visitarla.
    int r(String id, int v) => done.contains(id) ? v : 0;
    String? arrived(String id) => done.contains(id) ? _times[id]!.$1 : null;
    String? left(String id) => done.contains(id) ? (_times[id]!.$2 ?? (after ? '14:05' : null)) : null;

    PlaceSection place(
      String id, {
      required String title,
      required String description,
      required int rating,
      required String main,
      List<String> more = const [],
      double cost = 0,
      double? realCost,
      required double lat,
      required double lng,
      String? from,
      String? to,
      bool unplanned = false,
      String? cover,
    }) =>
        PlaceSection(
          id: id,
          title: title,
          description: description,
          rating: r(id, rating),
          mainPhotoUrl: main,
          secondaryPhotoUrls: more,
          cost: cost,
          lat: lat,
          lng: lng,
          arrivalTime: from,
          departureTime: to,
          unplanned: unplanned,
          arrivedAt: arrived(id),
          leftAt: left(id),
          realCost: done.contains(id) ? realCost : null,
          coverUrl: cover,
        );

    return [
      TextSection(
        id: 't0',
        markdownText: 'La idea era **caminar mucho y comer mejor**: empezar con café en la Roma, '
            'cruzar al Centro para ver Bellas Artes y terminar en Coyoacán.\n\n'
            '- Lleven efectivo para los tacos y la cantina.\n'
            '- El museo pide boleto con horario.',
      ),
      TextSection(
        id: 'tb1',
        markdownText: '| Concepto | Monto [money:MXN:total] |\n|---|---|\n'
            '| Café y pan | 140 |\n| Taxi a Bellas Artes | 110 |\n| Museo del Palacio | 90 |\n'
            '| Tacos | 180 |\n| Boleto Casa Azul | 320 |\n| Cantina | 250 |',
      ),
      place('p1',
          title: 'Café en la Roma Norte',
          description: 'Barra de especialidad en Insurgentes y Guanajuato. **El flat white** y el pan dulce del día valen la parada.',
          rating: 5,
          main: _photo('cafe', 1),
          more: [_photo('cafe', 2)],
          cover: _photo('cafe', 0),
          cost: 140,
          realCost: 165,
          lat: 19.4189,
          lng: -99.1627,
          from: '09:00',
          to: '09:45'),
      TransferSection(id: 'x1', mode: 'walking', durationMins: 13, distanceKm: 1.0, notes: 'Por Álvaro Obregón, bajo los árboles.'),
      place('p2',
          title: 'Parque México',
          description: 'Vuelta completa al parque, perros paseando y la fuente del Foro Lindbergh.',
          rating: 4,
          main: _photo('park', 1),
          cover: _photo('park', 2),
          lat: 19.4116,
          lng: -99.1693,
          from: '10:00',
          to: '11:00'),
      if (stage != SampleStage.antes)
        place('d1',
            title: 'Paletas en Michoacán',
            description: 'No estaba en el plan: el calor pidió una paleta de mango con chile.',
            rating: 5,
            main: '',
            realCost: 70,
            lat: 19.4123,
            lng: -99.1671,
            unplanned: true),
      TransferSection(id: 'x2', mode: 'taxi', durationMins: 22, distanceKm: 5.1, cost: 110),
      place('p3',
          title: 'Palacio de Bellas Artes',
          description: 'Los murales del segundo piso y la cúpula desde la Alameda.',
          rating: 5,
          main: CdmxPhotos.covers[1],
          more: [CdmxPhotos.covers[0]],
          cover: CdmxPhotos.byCategory['theatre']![1],
          cost: 90,
          realCost: 90,
          lat: 19.4352,
          lng: -99.1412,
          from: '11:30',
          to: '12:45'),
      TextImageSection(
        id: 'ti1',
        markdownText: 'Al salir cruzamos la **Alameda Central**. Es el respiro perfecto entre museo y comida: '
            'bancas a la sombra y la mejor vista de la cúpula.',
        imageUrl: _photo('park', 3),
        layout: 'right',
      ),
      TransferSection(id: 'x3', mode: 'walking', durationMins: 8, distanceKm: 0.6),
      place('p4',
          title: 'Tacos de suadero en el Centro',
          description: 'Taquería de barra, sin mesas. Suadero, longaniza y campechanos; **las salsas son de la casa**.',
          rating: 5,
          main: _photo('restaurant', 4),
          more: [_photo('restaurant', 6), _photo('restaurant', 0)],
          cover: _photo('restaurant', 8),
          cost: 180,
          realCost: 236,
          lat: 19.4307,
          lng: -99.1390,
          from: '13:00',
          to: '14:00'),
      TransferSection(id: 'x4', mode: 'metro', durationMins: 35, distanceKm: 9.4, cost: 5, notes: 'Línea 2 y transbordo a la 3 hasta Coyoacán.'),
      TextSection(
        id: 'tip1',
        markdownText: '> [!TIP]\n> En hora pico el metro va lleno: suban al vagón de en medio y tengan a mano la tarjeta de movilidad.',
      ),
      place('p5',
          title: 'Museo Frida Kahlo',
          description: 'La Casa Azul. Compren boleto en línea: se agota con días de anticipación.',
          rating: 4,
          main: _photo('museum', 3),
          cover: _photo('museum', 1),
          cost: 320,
          realCost: 320,
          lat: 19.3551,
          lng: -99.1626,
          from: '15:00',
          to: '16:30'),
      TransferSection(id: 'x5', mode: 'bike', durationMins: 6, distanceKm: 0.8, isEstimated: true),
      place('p6',
          title: 'Cantina La Guadalupana',
          description: 'Para cerrar: botanas con la bebida y dominó en las mesas del fondo.',
          rating: 3,
          main: '',
          cost: 250,
          lat: 19.3497,
          lng: -99.1622,
          from: '17:00'),
      TextSection(
        id: 't1',
        markdownText: '**Lo que aprendimos**\n\n'
            '1. Salir temprano: a las 11 el Centro ya está lleno.\n'
            '2. El metro es lo más rápido para llegar a Coyoacán.\n'
            '3. *Siempre* hay lugar para un taco más.',
      ),
    ];
  }

  static List<TripNote> notes(SampleStage stage) {
    final base = _day(stage).subtract(const Duration(days: 2));
    DateTime at(int h, int m) => DateTime(base.year, base.month, base.day, h, m);
    return [
      TripNote(id: 'n1', blockId: 't0', authorId: 'muestra-luis', authorName: 'Luis Ramírez', text: '¡Me apunto! ¿Nos vemos en el café?', createdAt: at(18, 2)),
      TripNote(
        id: 'n2',
        blockId: 'p1',
        authorId: kSampleOwnerId,
        authorName: 'Ana López',
        text: 'El flat white de aquí vale cada peso ☕',
        createdAt: at(18, 10),
        reactions: const {kSampleMyUid: 'heart', 'muestra-luis': 'heart'},
      ),
      TripNote(id: 'n3', blockId: 'p1', authorId: kSampleMyUid, authorName: kSampleMyName, text: 'Yo aparto la mesa de la ventana', createdAt: at(18, 14)),
      TripNote(
        id: 'n4',
        blockId: 'p2',
        authorId: 'muestra-luis',
        authorName: 'Luis Ramírez',
        text: 'Aquí nos tomamos la foto del grupo 📸',
        createdAt: at(19, 1),
        reactions: const {kSampleOwnerId: 'photo'},
      ),
      TripNote(
        id: 'n9',
        blockId: 'd1',
        authorId: 'muestra-luis',
        authorName: 'Luis Ramírez',
        text: '¡Esto no estaba en el plan! 🍦',
        createdAt: at(11, 3),
        reactions: const {kSampleOwnerId: 'haha', kSampleMyUid: 'fire'},
      ),
      TripNote(id: 'n10', blockId: 'tb1', authorId: kSampleOwnerId, authorName: 'Ana López', text: 'Salimos a unos \$1,100 por persona', createdAt: at(17, 40)),
      TripNote(id: 'n5', blockId: 'p4', authorId: kSampleOwnerId, authorName: 'Ana López', text: 'Pidan la de suadero con todo', createdAt: at(20, 30)),
      TripNote(id: 'n6', blockId: 'p4', authorId: kSampleMyUid, authorName: kSampleMyName, text: '¿Cuántos por persona?', createdAt: at(20, 31)),
      TripNote(
        id: 'n7',
        blockId: 'p4',
        authorId: 'muestra-luis',
        authorName: 'Luis Ramírez',
        text: 'Mínimo cinco 😂',
        createdAt: at(20, 33),
        reactions: const {kSampleMyUid: 'haha', kSampleOwnerId: 'haha'},
      ),
      TripNote(
        id: 'n8',
        blockId: 'p5',
        authorId: kSampleOwnerId,
        authorName: 'Ana López',
        text: 'Ya compré los boletos para las 15:00',
        createdAt: at(21, 5),
        reactions: const {'muestra-luis': 'hundred'},
      ),
    ];
  }

  static Map<String, Map<String, String>> get reactions => {
        't0': {'muestra-luis': 'heart'},
        'p1': {kSampleOwnerId: 'heart', 'muestra-luis': 'fire', kSampleMyUid: 'heart'},
        'p3': {kSampleOwnerId: 'surprise', 'muestra-luis': 'photo'},
        'ti1': {kSampleOwnerId: 'photo'},
        'd1': {kSampleOwnerId: 'surprise', 'muestra-luis': 'fire'},
        'tb1': {'muestra-luis': 'hundred'},
        'p4': {kSampleOwnerId: 'fire', 'muestra-luis': 'fire', kSampleMyUid: 'hundred'},
      };
}

/// Mensajes y reacciones de la muestra: viven en memoria y se pierden al recargar.
class SampleTripSocialService extends TripSocialService {
  SampleTripSocialService(List<TripNote> notes, Map<String, Map<String, String>> reactions)
      : _notes = List.of(notes),
        _reactions = {for (final e in reactions.entries) e.key: Map.of(e.value)},
        super(kSampleOwnerId, kSampleTripId);

  final List<TripNote> _notes;
  final Map<String, Map<String, String>> _reactions;
  final _notesCtrl = StreamController<List<TripNote>>.broadcast();
  final _reactionsCtrl = StreamController<Map<String, Map<String, String>>>.broadcast();
  int _seq = 0;

  void _emitNotes() => _notesCtrl.add(List.unmodifiable(_notes));
  void _emitReactions() => _reactionsCtrl.add({for (final e in _reactions.entries) e.key: Map.unmodifiable(e.value)});

  @override
  Stream<List<TripNote>> notesStream() async* {
    yield List.unmodifiable(_notes);
    yield* _notesCtrl.stream;
  }

  @override
  Stream<Map<String, Map<String, String>>> reactionsStream() async* {
    yield {for (final e in _reactions.entries) e.key: Map.unmodifiable(e.value)};
    yield* _reactionsCtrl.stream;
  }

  TripNote _copy(TripNote n, {String? text, DateTime? editedAt, Map<String, String>? reactions}) => TripNote(
        id: n.id,
        blockId: n.blockId,
        authorId: n.authorId,
        authorName: n.authorName,
        authorPhoto: n.authorPhoto,
        text: text ?? n.text,
        createdAt: n.createdAt,
        editedAt: editedAt ?? n.editedAt,
        reactions: reactions ?? n.reactions,
      );

  @override
  Future<void> addNote({
    required String blockId,
    required String authorId,
    required String authorName,
    String? authorPhoto,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _notes.add(TripNote(
      id: 'local-${_seq++}',
      blockId: blockId,
      authorId: authorId,
      authorName: authorName,
      authorPhoto: authorPhoto,
      text: clean,
      createdAt: DateTime.now(),
    ));
    _emitNotes();
  }

  @override
  Future<void> editNote(String noteId, String text) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    if (i < 0 || text.trim().isEmpty) return;
    _notes[i] = _copy(_notes[i], text: text.trim(), editedAt: DateTime.now());
    _emitNotes();
  }

  @override
  Future<void> deleteNote(String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
    _emitNotes();
  }

  @override
  Future<void> reactToNote(String noteId, String uid, String? kind) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    if (i < 0) return;
    final m = Map<String, String>.from(_notes[i].reactions);
    if (kind == null) {
      m.remove(uid);
    } else {
      m[uid] = kind;
    }
    _notes[i] = _copy(_notes[i], reactions: m);
    _emitNotes();
  }

  @override
  Future<void> reactToBlock(String blockId, String uid, String? kind) async {
    final m = _reactions.putIfAbsent(blockId, () => {});
    if (kind == null) {
      m.remove(uid);
    } else {
      m[uid] = kind;
    }
    _emitReactions();
  }
}

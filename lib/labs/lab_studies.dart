/// Catálogo de estudios de Ohtli Labs.
///
/// Cada estudio corresponde a una prueba del capítulo 6 del Trabajo Terminal. La definición vive
/// en el código (versionada con git) y la consola de lab.ohtli.quest puede ajustar su
/// configuración por corrida; cada corrida guarda la configuración exacta que usó.
library;

enum LabStudyKind { scenarios, load, checklist, relevance, sus }

class LabPlace {
  final String name;
  final double lat;
  final double lng;
  const LabPlace(this.name, this.lat, this.lng);
  Map<String, double> get point => {'lat': lat, 'lng': lng};
}

class LabPlaces {
  static const zocalo = LabPlace('Zócalo', 19.4326, -99.1332);
  static const coyoacan = LabPlace('Jardín Hidalgo, Coyoacán', 19.3500, -99.1620);
  static const condesa = LabPlace('Condesa', 19.4121, -99.1716);
  static const parqueMexico = LabPlace('Parque México', 19.4119, -99.1699);
  static const polanco = LabPlace('Polanco', 19.4260, -99.1863);
  static const sanAngel = LabPlace('Plaza San Jacinto, San Ángel', 19.3455, -99.1915);
  static const chapultepec = LabPlace('Castillo de Chapultepec', 19.4204, -99.1819);
  static const tlahuac = LabPlace('Centro de Tláhuac', 19.2869, -99.0049);
}

/// Perfiles de gusto de la batería (se vectorizan con /v1/api/vibe).
const Map<String, String> kLabProfiles = {
  'cultural': 'Turista cultural interesado en museos, arquitectura virreinal, muralismo e historia de la Ciudad de México.',
  'gastronomico': 'Turista gastronómico que busca mercados tradicionales, cocina mexicana, cafeterías de especialidad y cantinas.',
  'naturaleza': 'Turista que prefiere parques, jardines, áreas verdes, miradores y caminatas tranquilas al aire libre.',
  'familiar': 'Familia con niños que busca áreas verdes, zoológico, museos interactivos y actividades recreativas.',
};

const List<String> kLabMoods = [
  'Quiero una tarde tranquila de arte y museos',
  'Gastronomía y mercados tradicionales',
  'Recorrido bohemio por cafés y librerías',
  'Paseo al aire libre por parques y jardines',
  'Historia prehispánica y centro histórico',
];

/// Un escenario ejecutable contra el motor (POST /v1/itinerary).
class LabScenario {
  final String id;
  final String title;
  final String purpose;
  final LabPlace origin;
  final LabPlace? destination;
  final String topology;
  final double budget;
  final String profile;
  final String mood;
  final String? startTime;
  final String? endTime;
  final double stayFactor;
  final double? radiusKm;
  final String? travelDate; // AAAA-MM-DD; null = hoy

  const LabScenario({
    required this.id,
    required this.title,
    this.purpose = '',
    required this.origin,
    this.destination,
    this.topology = 'radio',
    required this.budget,
    required this.profile,
    required this.mood,
    this.startTime,
    this.endTime,
    this.stayFactor = 1.0,
    this.radiusKm,
    this.travelDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'purpose': purpose,
        'origin': {'name': origin.name, ...origin.point},
        if (destination != null) 'destination': {'name': destination!.name, ...destination!.point},
        'topology': topology,
        'budget': budget,
        'profile': profile,
        'mood': mood,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        'stay_factor': stayFactor,
        if (radiusKm != null) 'radius_km': radiusKm,
        if (travelDate != null) 'travel_date': travelDate,
      };
}

/// Próximo lunes (los recintos oficiales cierran en lunes), en formato AAAA-MM-DD.
String nextMonday([DateTime? from]) {
  final d = from ?? DateTime.now();
  final add = (DateTime.monday - d.weekday + 7) % 7;
  final m = DateTime(d.year, d.month, d.day).add(Duration(days: add == 0 ? 7 : add));
  return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

/// Próximo día de la semana dado (1 = lunes … 7 = domingo).
String nextWeekday(int weekday, [DateTime? from]) {
  final d = from ?? DateTime.now();
  var add = (weekday - d.weekday + 7) % 7;
  if (add == 0) add = 7;
  final m = DateTime(d.year, d.month, d.day).add(Duration(days: add));
  return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

/// Escenarios formales de la sección 6.1.2 (1 a 5; el 6, fuera de línea, es una lista de verificación).
List<LabScenario> formalScenarios() => [
      LabScenario(
        id: 'E1',
        title: 'Turista cultural con presupuesto moderado (Centro Histórico)',
        purpose: 'Densidad de POIs en el Centro Histórico, respeto a horarios de museos y trayectos peatonales.',
        origin: LabPlaces.zocalo,
        topology: 'radio',
        radiusKm: 2.5,
        budget: 500,
        profile: 'cultural',
        mood: 'Arte novohispano y museos virreinales en el Centro Histórico',
        startTime: '10:00',
        endTime: '18:00',
        travelDate: nextWeekday(DateTime.wednesday),
      ),
      LabScenario(
        id: 'E2',
        title: 'Turista gastronómico y bohemio (Roma–Condesa–Juárez)',
        purpose: 'Topología de anillo, costos más altos y coherencia horaria en franja nocturna.',
        origin: LabPlaces.parqueMexico,
        topology: 'anillo',
        radiusKm: 3.0,
        budget: 1200,
        profile: 'gastronomico',
        mood: 'Cafeterías de especialidad, galerías contemporáneas y gastronomía de autor',
        startTime: '14:00',
        endTime: '22:00',
        travelDate: nextWeekday(DateTime.friday),
      ),
      LabScenario(
        id: 'E3',
        title: 'Turista familiar y recreativo (Chapultepec–Polanco)',
        purpose: 'Ritmo relajado (+25% de estancia) sobre las ventanas del TOPTW y atractivos gratuitos.',
        origin: LabPlaces.chapultepec,
        topology: 'radio',
        budget: 800,
        profile: 'familiar',
        mood: 'Áreas verdes, zoológico y recintos interactivos para niños',
        startTime: '09:00',
        endTime: '16:00',
        stayFactor: 1.25,
        travelDate: nextWeekday(DateTime.saturday),
      ),
      LabScenario(
        id: 'E4',
        title: 'Turista tradicional e histórico (Coyoacán → San Ángel)',
        purpose: 'Elipse direccional entre dos puntos distantes.',
        origin: LabPlaces.coyoacan,
        destination: LabPlaces.sanAngel,
        topology: 'elipse',
        budget: 400,
        profile: 'cultural',
        mood: 'Historia, plazas y arquitectura tradicional de Coyoacán y San Ángel',
        startTime: '11:00',
        endTime: '17:00',
        travelDate: nextWeekday(DateTime.sunday),
      ),
      LabScenario(
        id: 'E5',
        title: 'Caso límite: presupuesto \$0, radio de 800 m, periferia y lunes',
        purpose: 'Activación del protocolo de relajación en cascada (radio, presupuesto, monumentos abiertos).',
        origin: LabPlaces.tlahuac,
        topology: 'radio',
        radiusKm: 0.8,
        budget: 0,
        profile: 'cultural',
        mood: 'Lugares gratuitos para conocer la historia del barrio',
        startTime: '10:00',
        endTime: '16:00',
        travelDate: nextMonday(),
      ),
    ];

/// Batería determinista de 30 escenarios (la misma de la línea base del 12-nov-2026).
List<LabScenario> batteryScenarios([int n = 30]) {
  const origins = [LabPlaces.zocalo, LabPlaces.coyoacan, LabPlaces.condesa, LabPlaces.polanco, LabPlaces.sanAngel];
  const elipses = [
    [LabPlaces.coyoacan, LabPlaces.sanAngel],
    [LabPlaces.condesa, LabPlaces.polanco],
    [LabPlaces.zocalo, LabPlaces.condesa],
  ];
  const budgets = [200.0, 400.0, 700.0, 1200.0];
  const profiles = ['cultural', 'gastronomico', 'naturaleza'];
  final out = <LabScenario>[];
  for (var i = 0; i < n; i++) {
    final topo = ['radio', 'anillo', 'elipse'][i % 3];
    final a = topo == 'elipse' ? elipses[i % elipses.length][0] : origins[i % origins.length];
    final b = topo == 'elipse' ? elipses[i % elipses.length][1] : null;
    out.add(LabScenario(
      id: 'B${(i + 1).toString().padLeft(2, '0')}',
      title: '${a.name}${b != null ? ' → ${b.name}' : ''} · $topo · \$${budgets[i % budgets.length].toStringAsFixed(0)}',
      origin: a,
      destination: b,
      topology: topo,
      budget: budgets[i % budgets.length],
      profile: profiles[i % profiles.length],
      mood: kLabMoods[i % kLabMoods.length],
    ));
  }
  return out;
}

class LabChecklistItem {
  final String id;
  final String text;
  const LabChecklistItem(this.id, this.text);
}

/// Escenario 6 (CA-05): verificación manual fuera de línea en DevTools.
const kOfflineChecklist = [
  LabChecklistItem('o1', 'Con red: abrir un viaje guardado y confirmar que se ve completo.'),
  LabChecklistItem('o2', 'DevTools → Network → Offline y recargar: la app abre desde el service worker.'),
  LabChecklistItem('o3', 'Sin red: el viaje guardado muestra paradas, horarios y mapa en caché.'),
  LabChecklistItem('o4', 'Sin red: exportar el PDF del viaje sin errores.'),
  LabChecklistItem('o5', 'Sin red: un viaje no guardado muestra el aviso de sin conexión (no un 404).'),
  LabChecklistItem('o6', 'Volver a conectar: aparece "Recuperaste la conexión" y los cambios se sincronizan.'),
];

/// Cuestionario SUS (System Usability Scale, Brooke 1996), traducción al español.
const kSusItems = [
  'Creo que me gustaría usar Ohtli con frecuencia.',
  'Encontré Ohtli innecesariamente complejo.',
  'Pensé que Ohtli era fácil de usar.',
  'Creo que necesitaría el apoyo de un técnico para poder usar Ohtli.',
  'Encontré que las funciones de Ohtli estaban bien integradas.',
  'Pensé que había demasiada inconsistencia en Ohtli.',
  'Imagino que la mayoría de las personas aprendería a usar Ohtli muy rápido.',
  'Encontré Ohtli muy complicado de usar.',
  'Me sentí muy seguro(a) usando Ohtli.',
  'Necesité aprender muchas cosas antes de poder usar Ohtli.',
];

/// Preguntas de satisfacción con el itinerario (escala 1–5).
const kSatisfactionItems = [
  'El itinerario reflejó mis gustos e intereses.',
  'Los lugares recomendados eran adecuados para mi presupuesto.',
  'Los horarios y traslados del itinerario me parecieron realistas.',
  'Las tres alternativas eran distintas entre sí.',
  'Usaría Ohtli para planear una visita real a la CDMX.',
];

/// Tareas guiadas para la evaluación con usuarios.
const kSusTasks = [
  'Completa tu perfil de gustos (onboarding).',
  'Genera un itinerario para mañana desde el Zócalo con \$500 MXN.',
  'Compara las tres alternativas y guarda la que prefieras.',
  'Abre el viaje guardado y descárgalo en PDF.',
];

class LabStudy {
  final String id;
  final String title;
  final String chapter; // sección del TT que alimenta
  final String criterion; // criterio de aceptación relacionado
  final String description;
  final LabStudyKind kind;
  final bool needsTesters;

  const LabStudy({
    required this.id,
    required this.title,
    required this.chapter,
    required this.criterion,
    required this.description,
    required this.kind,
    this.needsTesters = false,
  });
}

const kLabStudies = [
  LabStudy(
    id: 'escenarios_formales',
    title: 'Escenarios formales (E1–E5)',
    chapter: '6.1.2 · 6.4 · 7.1',
    criterion: 'CA-01 · CA-02',
    description: 'Los cinco escenarios operativos del capítulo 6 con horario, ritmo, radio y día de la semana fijos. '
        'Verifica presupuesto, ventanas horarias, jornada y latencia de punta a punta.',
    kind: LabStudyKind.scenarios,
  ),
  LabStudy(
    id: 'bateria_30',
    title: 'Batería de 30 escenarios',
    chapter: '6.5 · 6.6.1 · 6.8 · 7.2 · 7.4',
    criterion: 'CA-01 · CA-02',
    description: 'Cinco orígenes, tres topologías, cuatro presupuestos, tres perfiles y cinco intenciones; '
        'la misma batería de la línea base del 12-nov-2026, ejecutada de forma secuencial.',
    kind: LabStudyKind.scenarios,
  ),
  LabStudy(
    id: 'concurrencia',
    title: 'Concurrencia (10 · 25 · 50 solicitudes)',
    chapter: '6.6.3 · 7.4',
    criterion: 'CA-06',
    description: 'Ráfagas de solicitudes simultáneas de itinerario; mide tasa de error, latencia y trabajos completados.',
    kind: LabStudyKind.load,
  ),
  LabStudy(
    id: 'offline_ca05',
    title: 'Continuidad fuera de línea (E6)',
    chapter: '6.4 · 7.1',
    criterion: 'CA-05',
    description: 'Lista de verificación manual en DevTools (Network → Offline) para Chrome y Safari móvil.',
    kind: LabStudyKind.checklist,
  ),
  LabStudy(
    id: 'relevancia',
    title: 'Juicio de relevancia de recomendaciones',
    chapter: '6.5.1 · 6.5.2 · 7.2',
    criterion: 'Precision@k · nDCG',
    description: 'Evaluadores califican del 1 al 5 qué tan pertinente es cada parada para la intención del escenario.',
    kind: LabStudyKind.relevance,
    needsTesters: true,
  ),
  LabStudy(
    id: 'sus',
    title: 'Evaluación con usuarios (SUS y satisfacción)',
    chapter: '6.7 · 7.5',
    criterion: 'SUS ≥ 68',
    description: 'Tareas guiadas, cuestionario SUS de 10 reactivos y satisfacción con el itinerario.',
    kind: LabStudyKind.sus,
    needsTesters: true,
  ),
];

LabStudy? studyById(String id) {
  for (final s in kLabStudies) {
    if (s.id == id) return s;
  }
  return null;
}

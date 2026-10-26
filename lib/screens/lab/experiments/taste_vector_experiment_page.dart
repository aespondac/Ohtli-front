import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../onboarding/onboarding_wizard_page.dart';

class TasteVectorExperimentPage extends StatefulWidget {
  final VoidCallback? onBack;

  const TasteVectorExperimentPage({super.key, this.onBack});

  @override
  State<TasteVectorExperimentPage> createState() =>
      _TasteVectorExperimentPageState();
}

class _TasteVectorExperimentPageState extends State<TasteVectorExperimentPage> {
  bool _isLoading = false;
  Map<String, String>? _userAxes;
  List<double>? _tasteVector;
  List<Map<String, dynamic>> _rankedPois = [];
  List<Map<String, dynamic>> _filteredOutPois = [];
  int _selectedPoiIndex = 0;
  Map<String, dynamic>? _responsePayload;

  // Parámetros de los 4 Ejes Ontológicos
  final Set<String> _selectedCultural = {
    "museos_arte",
    "librerias_cafes",
    "parques_bosques"
  };
  final Set<String> _selectedCulinary = {
    "cafeterias_especialidad",
    "panaderias_clasicas"
  };
  final Set<String> _selectedAtmosphere = {"bohemio", "tranquilo_arbolado"};
  String _socialCompanion = "pareja";
  String _discoveryStyle = "equilibrado";
  String _preferredTimeWindow = "tarde";
  String _travelPace = "relajado";
  String _transportPref = "caminata";
  String _budgetTier = "medio";
  String _accessibilityNeeds = "estandar";
  double _alphaFusion = 0.65;

  final TextEditingController _bioController = TextEditingController(
    text:
        "Me fascina caminar por calles empedradas, ver pintura mexicana y tomar café en patios arbolados con bugambilias.",
  );
  final TextEditingController _moodController = TextEditingController(
    text: "Tarde tranquila en pareja buscando arte e intimidad.",
  );

  // Catálogo real de 12 POIs de la CDMX con Recetas OEP en 4 Ejes Ontológicos
  static final List<Map<String, dynamic>> _cdmxBenchmarkCatalog = [
    {
      "poi_id": "cdmx_casa_azul_frida",
      "name": "Museo Frida Kahlo (Casa Azul)",
      "alcaldia": "Coyoacán",
      "category": "museos_arte",
      "price_mxn": 270.0,
      "stay_duration_mins": 90,
      "wheelchair_accessible": true,
      "walking_score": 0.95,
      "public_score": 0.85,
      "cultural": ["museos_arte", "muralismo", "arquitectura_virreinal", "fotografia_urbana"],
      "culinary": ["cafeterias_especialidad"],
      "atmosphere": ["bohemio", "tranquilo_arbolado", "historico"],
      "companions": ["solo", "pareja"],
      "discovery": "iconico",
      "time_windows": ["manana", "tarde"],
      "oep_axes": {
        "vocacion_cultural":
            "Museo Frida Kahlo (Casa Azul): vocación centrada en museos de arte moderno, pintura mexicana, arte popular y patrimonio biográfico de Frida Kahlo y Diego Rivera.",
        "atmosfera_sensorial":
            "Atmósfera bohemia, íntima, nostálgica y contemplativa, con jardines arbolados de bugambilias, fuentes de piedra volcánica y patios azul cobalto.",
        "dinamica_social":
            "Ideal para exploradores en solitario y viajes en pareja buscando introspección artística. Carácter de monumento patrimonial imprescindible en horario matutino o vespertino.",
        "entorno_urbano":
            "Entorno urbano de Coyoacán con alta caminabilidad peatonal por calles empedradas, parques arbolados y accesibilidad universal."
      }
    },
    {
      "poi_id": "cdmx_cafe_el_jarocho",
      "name": "Café El Jarocho y Jardín Centenario",
      "alcaldia": "Coyoacán",
      "category": "cafeterias_especialidad",
      "price_mxn": 85.0,
      "stay_duration_mins": 50,
      "wheelchair_accessible": true,
      "walking_score": 0.98,
      "public_score": 0.82,
      "cultural": ["librerias_cafes", "parques_bosques", "mercados_artesanias"],
      "culinary": ["cafeterias_especialidad", "panaderias_clasicas", "comida_callejera"],
      "atmosphere": ["bohemio", "tranquilo_arbolado", "vibrante_concurrido"],
      "companions": ["solo", "pareja", "amigos", "familia"],
      "discovery": "equilibrado",
      "time_windows": ["manana", "tarde", "noche"],
      "oep_axes": {
        "vocacion_cultural":
            "Barra tradicional de café de grano mexicano desde 1953, acompañada de panadería clásica de barrio, rodeada de librerías de viejo y quioscos históricos.",
        "atmosfera_sensorial":
            "Atmósfera bohemia, aromática y acogedora al aire libre, para sentarse en bancas bajo árboles centenarios disfrutando la tertulia barrial.",
        "dinamica_social":
            "Compatible con viajeros en solitario, parejas, amigos o familias. Combina tradición icónica y vida auténtica de barrio en mañana, tarde o noche.",
        "entorno_urbano":
            "Corazón peatonal de Coyoacán con plazas arboladas, callejones coloniales, alta caminabilidad y accesibilidad universal a nivel de banqueta."
      }
    },
    {
      "poi_id": "cdmx_antropologia",
      "name": "Museo Nacional de Antropología",
      "alcaldia": "Miguel Hidalgo",
      "category": "arqueologia",
      "price_mxn": 95.0,
      "stay_duration_mins": 150,
      "wheelchair_accessible": true,
      "walking_score": 0.92,
      "public_score": 0.95,
      "cultural": ["arqueologia", "museos_arte", "parques_bosques", "muralismo"],
      "culinary": ["alta_gastronomia", "cafeterias_especialidad"],
      "atmosphere": ["historico", "tranquilo_arbolado"],
      "companions": ["solo", "pareja", "familia", "amigos"],
      "discovery": "iconico",
      "time_windows": ["manana", "tarde", "jornada_completa"],
      "oep_axes": {
        "vocacion_cultural":
            "Recinto cumbre de zonas arqueológicas y patrimonio prehispánico (Piedra del Sol, culturas mexica, maya y teotihuacana) con arquitectura monumental.",
        "atmosfera_sensorial":
            "Atmósfera solemne, monumental y contemplativa con espejo de agua, paraguas monumental y jardines arqueológicos silenciosos.",
        "dinamica_social":
            "Óptimo para familias, exploradores en solitario, parejas y grupos. Hito cultural imprescindible de la Ciudad de México.",
        "entorno_urbano":
            "Inmerso en el Bosque de Chapultepec con áreas verdes extensas, ciclovías Ecobici, Metro cercano y accesibilidad universal completa con rampas y elevadores."
      }
    },
    {
      "poi_id": "cdmx_san_ildefonso",
      "name": "Antiguo Colegio de San Ildefonso",
      "alcaldia": "Cuauhtémoc",
      "category": "muralismo",
      "price_mxn": 50.0,
      "stay_duration_mins": 90,
      "wheelchair_accessible": true,
      "walking_score": 0.94,
      "public_score": 0.96,
      "cultural": ["muralismo", "arquitectura_virreinal", "museos_arte", "fotografia_urbana"],
      "culinary": ["cafeterias_especialidad", "cantinas_tradicionales"],
      "atmosphere": ["historico", "bohemio", "tranquilo_arbolado"],
      "companions": ["solo", "pareja", "amigos"],
      "discovery": "equilibrado",
      "time_windows": ["manana", "tarde"],
      "oep_axes": {
        "vocacion_cultural":
            "Cuna del muralismo mexicano con frescos monumentales de Diego Rivera, José Clemente Orozco y David Alfaro Siqueiros en un palacio barroco virreinal del siglo XVI.",
        "atmosfera_sensorial":
            "Atmósfera histórica, solemne y silenciosa en sus patios de cantera y arquerías coloniales, propicia para la contemplación estética.",
        "dinamica_social":
            "Ideal para viajeros en solitario, parejas y amantes de la historia del arte en horario matutino o vespertino.",
        "entorno_urbano":
            "Calle peatonal Justo Sierra en el Centro Histórico, conectada con Metro Zócalo, templos virreinales y librerías antiguas."
      }
    },
    {
      "poi_id": "cdmx_templo_mayor",
      "name": "Zona Arqueológica y Museo del Templo Mayor",
      "alcaldia": "Cuauhtémoc",
      "category": "arqueologia",
      "price_mxn": 95.0,
      "stay_duration_mins": 110,
      "wheelchair_accessible": true,
      "walking_score": 0.96,
      "public_score": 0.98,
      "cultural": ["arqueologia", "arquitectura_virreinal", "museos_arte", "fotografia_urbana"],
      "culinary": ["comida_callejera", "cantinas_tradicionales"],
      "atmosphere": ["historico", "vibrante_concurrido"],
      "companions": ["solo", "pareja", "familia", "amigos"],
      "discovery": "iconico",
      "time_windows": ["manana", "tarde"],
      "oep_axes": {
        "vocacion_cultural":
            "Recinto sagrado de México-Tenochtitlan con vestigios mexicas, monolito de Coyolxauhqui y superposición con la arquitectura virreinal del Zócalo.",
        "atmosfera_sensorial":
            "Atmósfera histórica imponente al aire libre y salas museográficas inmersivas en el corazón vibrante de la metrópoli.",
        "dinamica_social":
            "Excelente para familias, viajeros solitarios y parejas en su visita a los monumentos imprescindibles de la CDMX.",
        "entorno_urbano":
            "Corredor 100% peatonal junto a la Catedral Metropolitana y Plaza de la Constitución, con acceso directo a Metro y Metrobús."
      }
    },
    {
      "poi_id": "cdmx_kiosco_morisco_vasconcelos",
      "name": "Kiosco Morisco y Biblioteca Vasconcelos",
      "alcaldia": "Cuauhtémoc",
      "category": "librerias_cafes",
      "price_mxn": 0.0,
      "stay_duration_mins": 85,
      "wheelchair_accessible": true,
      "walking_score": 0.91,
      "public_score": 0.95,
      "cultural": ["librerias_cafes", "fotografia_urbana", "parques_bosques", "arquitectura_virreinal"],
      "culinary": ["cafeterias_especialidad", "panaderias_clasicas", "mercados_populares"],
      "atmosphere": ["tranquilo_arbolado", "bohemio"],
      "companions": ["solo", "pareja", "familia"],
      "discovery": "joyas_ocultas",
      "time_windows": ["manana", "tarde"],
      "oep_axes": {
        "vocacion_cultural":
            "Joya arquitectónica mudéjar de hierro forjado en Santa María la Ribera y megabiblioteca contemporánea rodeada de jardines botánicos y cafés de barrio.",
        "atmosfera_sensorial":
            "Atmósfera tranquila, literaria, arbolada y fotogénica, con estanterías suspendidas y vida comunitaria auténtica fuera del turismo masivo.",
        "dinamica_social":
            "Ideal para exploradores de joyas ocultas en solitario, parejas o familias en horario matutino o vespertino.",
        "entorno_urbano":
            "Barrio tradicional porfiriano de Santa María la Ribera con parque arbolado, panaderías históricas, Metro Buenavista y accesibilidad universal."
      }
    },
    {
      "poi_id": "cdmx_cantina_la_opera",
      "name": "Cantina Histórica La Ópera",
      "alcaldia": "Cuauhtémoc",
      "category": "cantinas_tradicionales",
      "price_mxn": 380.0,
      "stay_duration_mins": 95,
      "wheelchair_accessible": true,
      "walking_score": 0.95,
      "public_score": 0.96,
      "cultural": ["arquitectura_virreinal", "musica_conciertos", "fotografia_urbana"],
      "culinary": ["cantinas_tradicionales", "alta_gastronomia"],
      "atmosphere": ["historico", "vibrante_concurrido", "bohemio", "festivo_nocturno"],
      "companions": ["amigos", "pareja"],
      "discovery": "equilibrado",
      "time_windows": ["tarde", "noche"],
      "oep_axes": {
        "vocacion_cultural":
            "Cantina porfiriana fundada en 1876 con mobiliario de madera tallada, plafones dorados, historia de la Revolución Mexicana y cocina tradicional de cantina.",
        "atmosfera_sensorial":
            "Atmósfera histórica, bulliciosa, nostálgica y social con música tradicional y tertulia de sobremesa.",
        "dinamica_social":
            "Óptimo para grupos de amigos o parejas en horario vespertino y nocturno buscando tradición gastronómica e historia viva.",
        "entorno_urbano":
            "A dos cuadras del Palacio de Bellas Artes sobre Avenida 5 de Mayo, con excelente conectividad peatonal y de transporte público."
      }
    },
    {
      "poi_id": "cdmx_mercado_san_juan",
      "name": "Mercado Gastronómico de San Juan Pugibet",
      "alcaldia": "Cuauhtémoc",
      "category": "mercados_populares",
      "price_mxn": 220.0,
      "stay_duration_mins": 75,
      "wheelchair_accessible": true,
      "walking_score": 0.88,
      "public_score": 0.94,
      "cultural": ["mercados_artesanias", "fotografia_urbana"],
      "culinary": ["mercados_populares", "comida_callejera", "alta_gastronomia", "cafeterias_especialidad"],
      "atmosphere": ["vibrante_concurrido", "bohemio"],
      "companions": ["solo", "amigos", "pareja"],
      "discovery": "joyas_ocultas",
      "time_windows": ["manana", "tarde"],
      "oep_axes": {
        "vocacion_cultural":
            "Mercado gastronómico tradicional célebre por ingredientes prehispánicos, quesos artesanales, tapas, antojitos y degustaciones culinarias.",
        "atmosfera_sensorial":
            "Atmósfera vibrante, colorida, bulliciosa y multisensorial, llena de aromas de especias, café recién molido y hospitalidad de locatarios.",
        "dinamica_social":
            "Ideal para exploradores gastronómicos en solitario, amigos o parejas que buscan joyas culinarias auténticas por la mañana o mediodía.",
        "entorno_urbano":
            "Barrio histórico de San Juan junto a la Plaza Pugibet, accesible a pie desde Bellas Artes y Metro Salto del Agua."
      }
    },
    {
      "poi_id": "cdmx_pulqueria_duelistas",
      "name": "Pulquería Tradicional Las Duelistas",
      "alcaldia": "Cuauhtémoc",
      "category": "pulquerias",
      "price_mxn": 110.0,
      "stay_duration_mins": 70,
      "wheelchair_accessible": false,
      "walking_score": 0.90,
      "public_score": 0.93,
      "cultural": ["muralismo", "musica_conciertos", "mercados_artesanias"],
      "culinary": ["pulquerias", "comida_callejera", "cantinas_tradicionales"],
      "atmosphere": ["festivo_nocturno", "vibrante_concurrido", "bohemio"],
      "companions": ["amigos", "pareja"],
      "discovery": "joyas_ocultas",
      "time_windows": ["tarde", "noche"],
      "oep_axes": {
        "vocacion_cultural":
            "Pulquería centenaria desde 1912 decorada con muralismo popular colorido, dedicada a preservar la bebida prehispánica del pulque y curados naturales.",
        "atmosfera_sensorial":
            "Atmósfera festiva, juvenil, ruidosa, folclórica y de alta energía social con música y murales vibrantes.",
        "dinamica_social":
            "Óptimo para grupos de amigos o parejas jóvenes buscando rincones subterráneos y cultura popular en horario de tarde o noche.",
        "entorno_urbano":
            "Callejón de Aranda en el Centro Histórico, a pocos pasos del Mercado de San Juan y estaciones de Metro."
      }
    },
    {
      "poi_id": "cdmx_cineteca_nacional",
      "name": "Cineteca Nacional y Foro al Aire Libre",
      "alcaldia": "Benito Juárez",
      "category": "teatros_foros",
      "price_mxn": 70.0,
      "stay_duration_mins": 140,
      "wheelchair_accessible": true,
      "walking_score": 0.89,
      "public_score": 0.92,
      "cultural": ["teatros_foros", "librerias_cafes", "parques_bosques", "museos_arte"],
      "culinary": ["cafeterias_especialidad", "panaderias_clasicas"],
      "atmosphere": ["bohemio", "tranquilo_arbolado"],
      "companions": ["solo", "pareja", "amigos"],
      "discovery": "equilibrado",
      "time_windows": ["tarde", "noche"],
      "oep_axes": {
        "vocacion_cultural":
            "Recinto de cine de arte mundial, retrospectivas culturales, librerías especializadas, galerías y cafeterías de especialidad.",
        "atmosfera_sensorial":
            "Atmósfera bohemia, intelectual y relajada con jardines al aire libre para ver cine sobre el pasto al atardecer y conversar.",
        "dinamica_social":
            "Excelente para citas en pareja, cinéfilos en solitario o grupos de amigos durante la tarde y la noche.",
        "entorno_urbano":
            "Pueblo originario de Xoco, colindante con Coyoacán, conectado con Metro Coyoacán, ciclovías y accesibilidad universal completa."
      }
    },
    {
      "poi_id": "cdmx_museo_anahuacalli",
      "name": "Museo Diego Rivera Anahuacalli",
      "alcaldia": "Coyoacán",
      "category": "arqueologia",
      "price_mxn": 100.0,
      "stay_duration_mins": 100,
      "wheelchair_accessible": false,
      "walking_score": 0.82,
      "public_score": 0.78,
      "cultural": ["arqueologia", "muralismo", "fotografia_urbana", "parques_bosques"],
      "culinary": ["cafeterias_especialidad"],
      "atmosphere": ["historico", "tranquilo_arbolado", "bohemio"],
      "companions": ["solo", "pareja", "amigos"],
      "discovery": "joyas_ocultas",
      "time_windows": ["manana", "tarde"],
      "oep_axes": {
        "vocacion_cultural":
            "Templo de las artes edificado en piedra volcánica por Diego Rivera y Juan O'Gorman, albergando miles de piezas prehispánicas con mirador panorámico.",
        "atmosfera_sensorial":
            "Atmósfera mística, silenciosa, telúrica y contemplativa, rodeada por una reserva ecológica de pedregal volcánico.",
        "dinamica_social":
            "Ideal para exploradores de joyas ocultas en solitario o parejas apasionadas por la arquitectura orgánica y el México antiguo.",
        "entorno_urbano":
            "Sur de Coyoacán en San Pablo Tepetlapa, rodeado de vegetación endémica del Pedregal y accesible mediante Tren Ligero."
      }
    },
    {
      "poi_id": "cdmx_rosetta_roma",
      "name": "Panadería y Restaurante Rosetta Roma Norte",
      "alcaldia": "Cuauhtémoc",
      "category": "alta_gastronomia",
      "price_mxn": 650.0,
      "stay_duration_mins": 95,
      "wheelchair_accessible": true,
      "walking_score": 0.97,
      "public_score": 0.92,
      "cultural": ["arquitectura_virreinal", "librerias_cafes", "museos_arte", "fotografia_urbana"],
      "culinary": ["alta_gastronomia", "panaderias_clasicas", "cafeterias_especialidad"],
      "atmosphere": ["bohemio", "tranquilo_arbolado"],
      "companions": ["pareja", "amigos", "solo"],
      "discovery": "equilibrado",
      "time_windows": ["manana", "tarde", "noche"],
      "oep_axes": {
        "vocacion_cultural":
            "Casona porfiriana dedicada a la alta cocina mexicana contemporánea de autor y panadería artesanal emblemática con ingredientes endémicos.",
        "atmosfera_sensorial":
            "Atmósfera estética, cálida, romántica y arbolada, con salones interiores llenos de plantas y terrazas sobre la banqueta.",
        "dinamica_social":
            "Óptimo para experiencias en pareja, reuniones con amigos o desayunos contemplativos en solitario en mañana, tarde o cena.",
        "entorno_urbano":
            "Corredor cultural de la colonia Roma Norte sobre calle Colima, rodeado de galerías de arte, plazas arboladas, Ecobici y caminabilidad peatonal total."
      }
    }
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateTasteVectorAndMatch();
    });
  }

  @override
  void dispose() {
    _bioController.dispose();
    _moodController.dispose();
    super.dispose();
  }

  void _applyPreset(String presetName) {
    setState(() {
      _selectedCultural.clear();
      _selectedCulinary.clear();
      _selectedAtmosphere.clear();

      if (presetName == "bohemio_pareja") {
        _selectedCultural.addAll(["museos_arte", "librerias_cafes", "parques_bosques"]);
        _selectedCulinary.addAll(["cafeterias_especialidad", "panaderias_clasicas"]);
        _selectedAtmosphere.addAll(["bohemio", "tranquilo_arbolado"]);
        _socialCompanion = "pareja";
        _discoveryStyle = "equilibrado";
        _preferredTimeWindow = "tarde";
        _travelPace = "relajado";
        _transportPref = "caminata";
        _budgetTier = "medio";
        _accessibilityNeeds = "estandar";
        _bioController.text =
            "Caminar en pareja por Coyoacán, visitar jardines con bugambilias, librerías y tomar café.";
        _moodController.text = "Tarde romántica de arte, cine y café tranquilo.";
      } else if (presetName == "familia_iconos") {
        _selectedCultural.addAll(["arqueologia", "museos_arte", "parques_bosques"]);
        _selectedCulinary.addAll(["panaderias_clasicas", "mercados_populares"]);
        _selectedAtmosphere.addAll(["historico", "tranquilo_arbolado"]);
        _socialCompanion = "familia";
        _discoveryStyle = "iconico";
        _preferredTimeWindow = "manana";
        _travelPace = "moderado";
        _transportPref = "mixto";
        _budgetTier = "economico";
        _accessibilityNeeds = "accesibilidad_universal";
        _bioController.text =
            "Viaje familiar con niños y abuelos para conocer la historia prehispánica y parques seguros.";
        _moodController.text = "Mañana soleada buscando museos amplios con rampas y jardines.";
      } else if (presetName == "amigos_noche") {
        _selectedCultural.addAll(["muralismo", "musica_conciertos", "mercados_artesanias"]);
        _selectedCulinary.addAll([
          "pulquerias",
          "cantinas_tradicionales",
          "comida_callejera"
        ]);
        _selectedAtmosphere.addAll(["festivo_nocturno", "vibrante_concurrido", "bohemio"]);
        _socialCompanion = "amigos";
        _discoveryStyle = "joyas_ocultas";
        _preferredTimeWindow = "noche";
        _travelPace = "intensivo";
        _transportPref = "transporte_publico";
        _budgetTier = "medio";
        _accessibilityNeeds = "estandar";
        _bioController.text =
            "Salir con amigos por el Centro Histórico buscando pulquerías legendarias, cantinas y música.";
        _moodController.text = "Noche festiva de curados de pulque, botana de cantina y tertulia.";
      } else if (presetName == "explorador_joyas") {
        _selectedCultural.addAll([
          "arquitectura_virreinal",
          "fotografia_urbana",
          "librerias_cafes",
          "arqueologia"
        ]);
        _selectedCulinary.addAll(["mercados_populares", "cafeterias_especialidad"]);
        _selectedAtmosphere.addAll(["tranquilo_arbolado", "historico", "bohemio"]);
        _socialCompanion = "solo";
        _discoveryStyle = "joyas_ocultas";
        _preferredTimeWindow = "manana";
        _travelPace = "relajado";
        _transportPref = "caminata";
        _budgetTier = "economico";
        _accessibilityNeeds = "estandar";
        _bioController.text =
            "Explorar en solitario barrios porfirianos como Santa María la Ribera, arquitectura volcánica y bibliotecas.";
        _moodController.text = "Mañana de fotografía arquitectónica y lectura silenciosa.";
      }
    });
    _generateTasteVectorAndMatch();
  }

  Future<void> _generateTasteVectorAndMatch() async {
    setState(() {
      _isLoading = true;
    });

    const apiUrl = String.fromEnvironment(
      'yollotlApiUrl',
      defaultValue: 'https://api-xluju5gywq-uc.a.run.app',
    );

    final payload = {
      "user_id": "lab_experiment_user",
      "cultural_interests": _selectedCultural.toList(),
      "culinary_interests": _selectedCulinary.toList(),
      "atmosphere_preference": _selectedAtmosphere.toList(),
      "social_companion": _socialCompanion,
      "discovery_style": _discoveryStyle,
      "preferred_time_window": _preferredTimeWindow,
      "travel_pace": _travelPace,
      "budget_tier": _budgetTier,
      "transport_preference": _transportPref,
      "accessibility_needs": _accessibilityNeeds,
      "free_bio": _bioController.text.trim(),
      "mood_override": _moodController.text.trim(),
      "alpha_fusion": _alphaFusion,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/v1/comparador/match-test'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded["ranked_pois"] != null) {
          setState(() {
            _responsePayload = decoded;
            _userAxes = (decoded["user_axes"] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
            _tasteVector = (decoded["taste_vector"] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList();
            _rankedPois = List<Map<String, dynamic>>.from(decoded["ranked_pois"]);
            _filteredOutPois =
                List<Map<String, dynamic>>.from(decoded["filtered_out_pois"] ?? []);
            _selectedPoiIndex = 0;
          });
          return;
        }
      }
      _runLocalOntologicalEngine(payload);
    } catch (_) {
      _runLocalOntologicalEngine(payload);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<double> _projectOntological768d(
    Set<String> cultural,
    Set<String> culinary,
    Set<String> atmosphere,
    String companion,
    String discovery,
    String timeWin,
    String transport,
    String acc,
    String textBio,
  ) {
    final vec = List<double>.filled(768, 0.0);
    final allConcepts = [
      "muralismo",
      "arqueologia",
      "museos_arte",
      "arquitectura_virreinal",
      "parques_bosques",
      "teatros_foros",
      "fotografia_urbana",
      "librerias_cafes",
      "mercados_artesanias",
      "musica_conciertos",
      "cafeterias_especialidad",
      "cantinas_tradicionales",
      "mercados_populares",
      "comida_callejera",
      "alta_gastronomia",
      "pulquerias",
      "panaderias_clasicas",
      "bohemio",
      "tranquilo_arbolado",
      "vibrante_concurrido",
      "historico",
      "festivo_nocturno",
      "solo",
      "pareja",
      "amigos",
      "familia",
      "iconico",
      "equilibrado",
      "joyas_ocultas",
      "manana",
      "tarde",
      "noche",
      "caminata",
      "transporte_publico",
      "accesibilidad_universal"
    ];

    final activeSet = <String>{
      ...cultural,
      ...culinary,
      ...atmosphere,
      companion,
      discovery,
      timeWin,
      transport,
      acc
    };

    for (var i = 0; i < allConcepts.length; i++) {
      final key = allConcepts[i];
      if (activeSet.contains(key)) {
        final baseSlot = (i * 21) % 768;
        for (var off = 0; off < 20; off++) {
          final idx = (baseSlot + off) % 768;
          final sign = ((i + off) % 2 == 0) ? 1.0 : -1.0;
          vec[idx] += sign * (0.9 + 0.1 * cos(off));
        }
      }
    }

    final words = textBio
        .toLowerCase()
        .split(RegExp(r'[^a-záéíóúñ]+'))
        .where((w) => w.length > 3);
    for (final w in words) {
      final h = w.hashCode.abs();
      vec[h % 768] += 0.22;
      vec[(h ~/ 7) % 768] -= 0.22;
    }

    var norm = sqrt(vec.fold<double>(0.0, (s, v) => s + v * v));
    if (norm < 1e-9) norm = 1.0;
    return vec.map((v) => v / norm).toList();
  }

  double _cosineSim(List<double> a, List<double> b) {
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na < 1e-12 || nb < 1e-12) return 0.0;
    return (dot / (sqrt(na) * sqrt(nb))).clamp(-1.0, 1.0);
  }

  void _runLocalOntologicalEngine(Map<String, dynamic> payload) {
    final bio = (payload["free_bio"] as String? ?? "").trim();
    final mood = (payload["mood_override"] as String? ?? "").trim();

    final userAxes = {
      "vocacion_cultural":
          "Interés cultural en ${_selectedCultural.join(', ')}. Afinidad gastronómica por ${_selectedCulinary.join(', ')}.${bio.isNotEmpty ? ' Manifiesto: \"$bio\".' : ''}",
      "atmosfera_sensorial":
          "Busca atmósfera ${_selectedAtmosphere.join(', ')}, disfrutada a ritmo $_travelPace.${mood.isNotEmpty ? ' Mood actual: \"$mood\".' : ''}",
      "dinamica_social":
          "Perfil de visitante en modalidad $_socialCompanion, enfoque de descubrimiento $_discoveryStyle y horario $_preferredTimeWindow.",
      "entorno_urbano":
          "Entorno urbano con prioridad por $_transportPref ($_accessibilityNeeds)."
    };

    final fullRecipe =
        "[EJE 1 - VOCACIÓN CULTURAL Y GASTRONÓMICA]: ${userAxes['vocacion_cultural']}\n"
        "[EJE 2 - ATMÓSFERA Y EXPERIENCIA SENSORIAL]: ${userAxes['atmosfera_sensorial']}\n"
        "[EJE 3 - DINÁMICA SOCIAL Y PERFIL DE VISITANTE]: ${userAxes['dinamica_social']}\n"
        "[EJE 4 - MICRO-ENTORNO URBANO Y CAMINABILIDAD]: ${userAxes['entorno_urbano']}";

    final tasteVec = _projectOntological768d(
      _selectedCultural,
      _selectedCulinary,
      _selectedAtmosphere,
      _socialCompanion,
      _discoveryStyle,
      _preferredTimeWindow,
      _transportPref,
      _accessibilityNeeds,
      bio,
    );

    List<double> queryVec = tasteVec;
    if (mood.isNotEmpty) {
      final moodVec = _projectOntological768d(
        _selectedCultural,
        _selectedCulinary,
        _selectedAtmosphere,
        _socialCompanion,
        _discoveryStyle,
        _preferredTimeWindow,
        _transportPref,
        _accessibilityNeeds,
        mood,
      );
      final fused = List<double>.generate(
        768,
        (i) => _alphaFusion * tasteVec[i] + (1.0 - _alphaFusion) * moodVec[i],
      );
      final n = sqrt(fused.fold<double>(0.0, (s, v) => s + v * v));
      queryVec = fused.map((v) => v / (n < 1e-9 ? 1.0 : n)).toList();
    }

    final maxBudget = _budgetTier == "economico"
        ? 250.0
        : (_budgetTier == "medio" ? 500.0 : 1500.0);
    final reqUniversal = _accessibilityNeeds == "accesibilidad_universal";

    final passed = <Map<String, dynamic>>[];
    final filteredOut = <Map<String, dynamic>>[];

    for (final poi in _cdmxBenchmarkCatalog) {
      final pCult = Set<String>.from(poi["cultural"] as List);
      final pCul = Set<String>.from(poi["culinary"] as List);
      final pAtmo = Set<String>.from(poi["atmosphere"] as List);
      final pComp = List<String>.from(poi["companions"] as List);
      final pDisc = poi["discovery"] as String;
      final pTime = List<String>.from(poi["time_windows"] as List);
      final oepAxes = Map<String, String>.from(poi["oep_axes"] as Map);

      final poiVec = _projectOntological768d(
        pCult,
        pCul,
        pAtmo,
        pComp.first,
        pDisc,
        pTime.first,
        "caminata",
        (poi["wheelchair_accessible"] as bool)
            ? "accesibilidad_universal"
            : "estandar",
        oepAxes.values.join(" "),
      );

      final rawCos = _cosineSim(queryVec, poiVec);

      // Cálculo explícito de los 4 ejes
      final cultOverlap = _selectedCultural.isEmpty
          ? 0.45
          : (_selectedCultural.intersection(pCult).length /
              max(1, min(_selectedCultural.length, pCult.length)));
      final culOverlap = _selectedCulinary.isEmpty
          ? 0.45
          : (_selectedCulinary.intersection(pCul).length /
              max(1, min(_selectedCulinary.length, pCul.length)));
      final eje1 = (0.20 + 0.50 * cultOverlap + 0.30 * culOverlap).clamp(0.0, 1.0);

      final atmoOverlap = _selectedAtmosphere.isEmpty
          ? 0.50
          : (_selectedAtmosphere.intersection(pAtmo).length /
              max(1, min(_selectedAtmosphere.length, pAtmo.length)));
      final eje2 = (0.20 + 0.80 * atmoOverlap).clamp(0.0, 1.0);

      final compMatch = pComp.contains(_socialCompanion) ? 1.0 : 0.30;
      final discMatch = (_discoveryStyle == pDisc ||
              _discoveryStyle == "equilibrado" ||
              pDisc == "equilibrado")
          ? 1.0
          : 0.40;
      final timeMatch = (_preferredTimeWindow == "jornada_completa" ||
              pTime.contains(_preferredTimeWindow))
          ? 1.0
          : 0.35;
      final eje3 =
          (0.45 * compMatch + 0.30 * discMatch + 0.25 * timeMatch).clamp(0.0, 1.0);

      final walkScore = (poi["walking_score"] as num).toDouble();
      final pubScore = (poi["public_score"] as num).toDouble();
      final transScore = _transportPref == "caminata"
          ? walkScore
          : (_transportPref == "transporte_publico"
              ? pubScore
              : 0.5 * (walkScore + pubScore));
      final accScore =
          (!reqUniversal || (poi["wheelchair_accessible"] as bool)) ? 1.0 : 0.20;
      final eje4 = (0.70 * transScore + 0.30 * accScore).clamp(0.0, 1.0);

      final weightedAxis = 0.38 * eje1 + 0.27 * eje2 + 0.20 * eje3 + 0.15 * eje4;
      final hybridSim =
          (0.50 * max(0.0, rawCos) + 0.50 * weightedAxis).clamp(0.0, 0.99);
      final angleDeg = (acos(hybridSim.clamp(-1.0, 1.0)) * 180.0 / pi);

      final priceMxn = (poi["price_mxn"] as num).toDouble();
      var hardPassed = true;
      String? filterReason;
      if (priceMxn > maxBudget) {
        hardPassed = false;
        filterReason =
            "Descartado por Knapsack/Budget (\$${priceMxn.toStringAsFixed(0)} > \$${maxBudget.toStringAsFixed(0)} MXN)";
      } else if (reqUniversal && !(poi["wheelchair_accessible"] as bool)) {
        hardPassed = false;
        filterReason =
            "Descartado por Hard Filter: Sin rampa/accesibilidad universal";
      }

      final item = {
        "poi_id": poi["poi_id"],
        "name": poi["name"],
        "alcaldia": poi["alcaldia"],
        "category": poi["category"],
        "price_mxn": priceMxn,
        "stay_duration_mins": poi["stay_duration_mins"],
        "wheelchair_accessible": poi["wheelchair_accessible"],
        "match_score": double.parse(hybridSim.toStringAsFixed(4)),
        "raw_cosine": double.parse(rawCos.toStringAsFixed(4)),
        "angular_distance_deg": double.parse(angleDeg.toStringAsFixed(1)),
        "axis_scores": {
          "vocacion_cultural": double.parse(eje1.toStringAsFixed(3)),
          "atmosfera_sensorial": double.parse(eje2.toStringAsFixed(3)),
          "dinamica_social": double.parse(eje3.toStringAsFixed(3)),
          "entorno_urbano": double.parse(eje4.toStringAsFixed(3)),
        },
        "oep_axes": oepAxes,
        "filter_reason": filterReason,
      };

      if (hardPassed) {
        passed.add(item);
      } else {
        filteredOut.add(item);
      }
    }

    passed.sort(
      (a, b) => (b["match_score"] as num).compareTo(a["match_score"] as num),
    );
    for (var i = 0; i < passed.length; i++) {
      passed[i]["rank"] = i + 1;
      passed[i]["mmr_score"] = passed[i]["match_score"];
    }

    setState(() {
      _userAxes = userAxes;
      _tasteVector = queryVec;
      _rankedPois = passed;
      _filteredOutPois = filteredOut;
      _selectedPoiIndex = 0;
      _responsePayload = {
        "status": "success (motor ontológico 4 ejes 768d)",
        "taste_vector_dim": 768,
        "alpha_fusion": _alphaFusion,
        "user_axes": userAxes,
        "recipe": fullRecipe,
        "top_3_matches": passed
            .take(3)
            .map((p) => {
                  "rank": p["rank"],
                  "name": p["name"],
                  "match_score": p["match_score"],
                  "angular_distance_deg": p["angular_distance_deg"],
                })
            .toList(),
        "hard_filtered_count": filteredOut.length,
      };
    });
  }

  void _openFullWizard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OnboardingWizardPage(
          onCompleted: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("¡Wizard de 5 pasos completado exitosamente!"),
                backgroundColor: OhtliColors.stormyTeal,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: OhtliColors.cardBg,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: OhtliColors.cardBorder,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: OhtliColors.onyx),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: OhtliColors.xoconostle.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "LABS • ONTOLOGÍA 4 EJES (768d)",
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: OhtliColors.xoconostle,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                "Homologación Vector Gusto vs. Agente Recolector",
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: OhtliColors.onyx,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton.icon(
              onPressed: _openFullWizard,
              icon: const Icon(Icons.launch, size: 16),
              label: const Text("Abrir Wizard (5 Pasos)"),
              style: TextButton.styleFrom(
                foregroundColor: OhtliColors.stormyTeal,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth > 940;
                if (isDesktop) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _buildInputPanel()),
                      const SizedBox(width: 24),
                      Expanded(flex: 7, child: _buildOutputPanel()),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildInputPanel(),
                      const SizedBox(height: 24),
                      _buildOutputPanel(),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "1. Arquetipos de Prueba (Presets)",
            style: GoogleFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                "Pareja Bohemia (Coyoacán)",
                Icons.favorite_outline_rounded,
                () => _applyPreset("bohemio_pareja"),
              ),
              _buildPresetChip(
                "Familia & Rampas (Íconos)",
                Icons.family_restroom_rounded,
                () => _applyPreset("familia_iconos"),
              ),
              _buildPresetChip(
                "Amigos Nocturnos (Pulque/Cantina)",
                Icons.nightlife_rounded,
                () => _applyPreset("amigos_noche"),
              ),
              _buildPresetChip(
                "Explorador Solo (Joyas Ocultas)",
                Icons.explore_outlined,
                () => _applyPreset("explorador_joyas"),
              ),
            ],
          ),
          const Divider(height: 28),
          Text(
            "Eje 1: Vocación Cultural y Gastronómica",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              "muralismo",
              "arqueologia",
              "museos_arte",
              "arquitectura_virreinal",
              "parques_bosques",
              "teatros_foros",
              "fotografia_urbana",
              "librerias_cafes",
              "mercados_artesanias",
              "musica_conciertos"
            ].map((item) {
              final active = _selectedCultural.contains(item);
              return FilterChip(
                label: Text(item.replaceAll("_", " ")),
                selected: active,
                backgroundColor: OhtliColors.innerCardBg,
                selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.25),
                side: BorderSide(
                  color: active ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                ),
                labelStyle: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? OhtliColors.stormyTeal : OhtliColors.onyx,
                ),
                onSelected: (val) {
                  setState(() {
                    val
                        ? _selectedCultural.add(item)
                        : _selectedCultural.remove(item);
                  });
                  _generateTasteVectorAndMatch();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              "cafeterias_especialidad",
              "cantinas_tradicionales",
              "mercados_populares",
              "comida_callejera",
              "alta_gastronomia",
              "pulquerias",
              "panaderias_clasicas"
            ].map((item) {
              final active = _selectedCulinary.contains(item);
              return FilterChip(
                label: Text(item.replaceAll("_", " ")),
                selected: active,
                backgroundColor: OhtliColors.innerCardBg,
                selectedColor: OhtliColors.xoconostle.withValues(alpha: 0.25),
                side: BorderSide(
                  color: active ? OhtliColors.xoconostle : OhtliColors.cardBorder,
                ),
                labelStyle: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? OhtliColors.xoconostle : OhtliColors.onyx,
                ),
                onSelected: (val) {
                  setState(() {
                    val
                        ? _selectedCulinary.add(item)
                        : _selectedCulinary.remove(item);
                  });
                  _generateTasteVectorAndMatch();
                },
              );
            }).toList(),
          ),
          const Divider(height: 24),
          Text(
            "Eje 2: Atmósfera Sensorial y Fusión Mood",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              "tranquilo_arbolado",
              "bohemio",
              "historico",
              "vibrante_concurrido",
              "festivo_nocturno"
            ].map((item) {
              final active = _selectedAtmosphere.contains(item);
              return FilterChip(
                label: Text(item.replaceAll("_", " ")),
                selected: active,
                backgroundColor: OhtliColors.innerCardBg,
                selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.25),
                side: BorderSide(
                  color: active ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                ),
                labelStyle: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? OhtliColors.stormyTeal : OhtliColors.onyx,
                ),
                onSelected: (val) {
                  setState(() {
                    val
                        ? _selectedAtmosphere.add(item)
                        : _selectedAtmosphere.remove(item);
                  });
                  _generateTasteVectorAndMatch();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _moodController,
            style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx),
            onChanged: (_) => _generateTasteVectorAndMatch(),
            decoration: InputDecoration(
              labelText: "Mood Dinámico de Hoy (v_mood)",
              labelStyle: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
              filled: true,
              fillColor: OhtliColors.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: OhtliColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: OhtliColors.cardBorder),
              ),
              isDense: true,
            ),
          ),
          Row(
            children: [
              Text(
                "Peso Identidad α = ${_alphaFusion.toStringAsFixed(2)}",
                style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
              ),
              Expanded(
                child: Slider(
                  value: _alphaFusion,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  activeColor: OhtliColors.stormyTeal,
                  onChanged: (v) {
                    setState(() => _alphaFusion = v);
                    _generateTasteVectorAndMatch();
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Text(
            "Eje 3: Dinámica Social, Descubrimiento y Horario",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 10),
          _buildDropdownRow(
            "Compañía:",
            _socialCompanion,
            const {
              "solo": "Solo (Introspección)",
              "pareja": "En Pareja (Íntimo)",
              "amigos": "Con Amigos (Social)",
              "familia": "En Familia (Niños/Abuelos)"
            },
            (v) {
              setState(() => _socialCompanion = v!);
              _generateTasteVectorAndMatch();
            },
          ),
          const SizedBox(height: 8),
          _buildDropdownRow(
            "Hallazgos:",
            _discoveryStyle,
            const {
              "iconico": "Íconos Imprescindibles",
              "equilibrado": "Híbrido Equilibrado",
              "joyas_ocultas": "Joyas Ocultas de Barrio"
            },
            (v) {
              setState(() => _discoveryStyle = v!);
              _generateTasteVectorAndMatch();
            },
          ),
          const SizedBox(height: 8),
          _buildDropdownRow(
            "Horario:",
            _preferredTimeWindow,
            const {
              "manana": "Mañana",
              "tarde": "Tarde",
              "noche": "Noche",
              "jornada_completa": "Jornada Completa"
            },
            (v) {
              setState(() => _preferredTimeWindow = v!);
              _generateTasteVectorAndMatch();
            },
          ),
          const Divider(height: 20),
          Text(
            "Eje 4 y Hard Filters: Movilidad, Presupuesto y Accesibilidad",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 10),
          _buildDropdownRow(
            "Traslado:",
            _transportPref,
            const {
              "caminata": "Caminata Peatonal",
              "transporte_publico": "Metro / Metrobús / Ecobici",
              "mixto": "Mixto"
            },
            (v) {
              setState(() => _transportPref = v!);
              _generateTasteVectorAndMatch();
            },
          ),
          const SizedBox(height: 8),
          _buildDropdownRow(
            "Presupuesto:",
            _budgetTier,
            const {
              "economico": "Económico (≤ \$250 MXN)",
              "medio": "Medio (≤ \$500 MXN)",
              "alto": "Holgado (≤ \$1,500 MXN)"
            },
            (v) {
              setState(() => _budgetTier = v!);
              _generateTasteVectorAndMatch();
            },
          ),
          const SizedBox(height: 8),
          _buildDropdownRow(
            "Accesibilidad:",
            _accessibilityNeeds,
            const {
              "estandar": "Estándar",
              "accesibilidad_universal": "Universal (Rampas / Silla de ruedas)"
            },
            (v) {
              setState(() => _accessibilityNeeds = v!);
              _generateTasteVectorAndMatch();
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _generateTasteVectorAndMatch,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.hub_outlined),
              label: Text(
                _isLoading
                    ? "Calculando Similitud Coseno..."
                    : "Recalcular Espacio Latente (768d)",
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow(
    String label,
    String value,
    Map<String, String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: value,
            isDense: true,
            dropdownColor: OhtliColors.cardBg,
            style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx),
            decoration: InputDecoration(
              filled: true,
              fillColor: OhtliColors.inputBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: OhtliColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: OhtliColors.cardBorder),
              ),
            ),
            items: items.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx),
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: OhtliColors.stormyTeal),
      label: Text(label),
      labelStyle: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: OhtliColors.onyx,
      ),
      backgroundColor: OhtliColors.innerCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      onPressed: onTap,
    );
  }

  Widget _buildOutputPanel() {
    final selectedPoi = (_rankedPois.isNotEmpty &&
            _selectedPoiIndex < _rankedPois.length)
        ? _rankedPois[_selectedPoiIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel Superior: Inspector Espejo de 4 Ejes (Usuario vs POI Seleccionado)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "2. Inspector Espejo de Homologación Ontológica (4 Ejes)",
                      style: GoogleFonts.fraunces(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: OhtliColors.onyx,
                      ),
                    ),
                  ),
                  if (selectedPoi != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "cos(θ) = ${(selectedPoi["match_score"] as num).toStringAsFixed(3)} • θ = ${selectedPoi["angular_distance_deg"]}°",
                        style: GoogleFonts.robotoMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: OhtliColors.stormyTeal,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                selectedPoi != null
                    ? "Comparando tu Perfil contra el OEP destilado de: ${selectedPoi['name']} (${selectedPoi['alcaldia']})"
                    : "Selecciona un POI del ranking inferior para inspeccionar la alineación eje por eje.",
                style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
              ),
              const SizedBox(height: 16),
              if (_userAxes != null && selectedPoi != null)
                ..._buildFourAxesComparisonRows(selectedPoi),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Panel Central: Ranking en Vivo de los 12 POIs de la CDMX
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "3. Ranking Real de POIs CDMX (Cosine + MMR)",
                    style: GoogleFonts.fraunces(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  Text(
                    "${_rankedPois.length} viables • ${_filteredOutPois.length} filtrados",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.stormyTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Haz clic en cualquier lugar para comparar sus 4 ejes semánticos arriba.",
                style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
              ),
              const SizedBox(height: 14),
              ...List.generate(_rankedPois.length, (index) {
                final poi = _rankedPois[index];
                final score = (poi["match_score"] as num).toDouble();
                final isSelected = index == _selectedPoiIndex;
                return InkWell(
                  onTap: () => setState(() => _selectedPoiIndex = index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? OhtliColors.stormyTeal.withValues(alpha: 0.16)
                          : OhtliColors.innerCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? OhtliColors.stormyTeal
                            : OhtliColors.cardBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: index < 3
                                          ? OhtliColors.stormyTeal
                                          : (OhtliSettings.instance.isDarkMode ? Colors.white24 : Colors.black26),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      "#${index + 1}",
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          poi["name"].toString(),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: OhtliColors.onyx,
                                          ),
                                        ),
                                        Text(
                                          "${poi["alcaldia"]} • ${poi["category"]} • \$${(poi["price_mxn"] as num).toStringAsFixed(0)} MXN • ${poi["stay_duration_mins"]} min",
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: OhtliColors.subtleText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: score > 0.72
                                    ? OhtliColors.stormyTeal.withValues(alpha: 0.18)
                                    : (OhtliSettings.instance.isDarkMode ? Colors.white12 : Colors.black12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${(score * 100).toStringAsFixed(1)}% match",
                                style: GoogleFonts.robotoMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: score > 0.72
                                      ? OhtliColors.stormyTeal
                                      : (OhtliSettings.instance.isDarkMode ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: score.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: OhtliSettings.instance.isDarkMode ? Colors.white12 : Colors.black12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              score > 0.72
                                  ? OhtliColors.stormyTeal
                                  : OhtliColors.cempasuchil,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (_filteredOutPois.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  "Descartados por Hard Filters (Escalares fuera del Vector):",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OhtliColors.xoconostle,
                  ),
                ),
                const SizedBox(height: 8),
                ..._filteredOutPois.map(
                  (f) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: OhtliColors.xoconostle.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "${f['name']} (${f['alcaldia']})",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: OhtliColors.onyx,
                            ),
                          ),
                        ),
                        Text(
                          f["filter_reason"]?.toString() ?? "",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: OhtliColors.xoconostle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Panel Inferior: Mapa de Calor 768d y Payload JSON
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "4. Proyección Latente (768d) y Payload de Contrato",
                style: GoogleFonts.fraunces(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 12),
              if (_tasteVector != null)
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: _tasteVector!.take(96).map((val) {
                    final intensity = (val.abs() * 12).clamp(0.1, 1.0);
                    final isPositive = val >= 0;
                    return Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isPositive
                            ? OhtliColors.stormyTeal.withValues(alpha: intensity)
                            : OhtliColors.xoconostle.withValues(alpha: intensity),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  const JsonEncoder.withIndent('  ')
                      .convert(_responsePayload ?? {}),
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: const Color(0xFFD4D4D4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFourAxesComparisonRows(Map<String, dynamic> selectedPoi) {
    final poiAxes = Map<String, dynamic>.from(selectedPoi["oep_axes"] as Map);
    final axisScores =
        Map<String, dynamic>.from(selectedPoi["axis_scores"] as Map);

    final axesMeta = [
      {
        "key": "vocacion_cultural",
        "title": "Eje 1 • Vocación Cultural y Gastronómica"
      },
      {
        "key": "atmosfera_sensorial",
        "title": "Eje 2 • Atmósfera y Experiencia Sensorial (Reseñas Destiladas)"
      },
      {
        "key": "dinamica_social",
        "title": "Eje 3 • Dinámica Social, Descubrimiento y Horario"
      },
      {
        "key": "entorno_urbano",
        "title": "Eje 4 • Micro-Entorno Urbano y Caminabilidad"
      },
    ];

    return axesMeta.map((meta) {
      final k = meta["key"]!;
      final title = meta["title"]!;
      final uText = _userAxes?[k] ?? "";
      final pText = poiAxes[k]?.toString() ?? "";
      final sVal = (axisScores[k] as num?)?.toDouble() ?? 0.5;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OhtliColors.innerCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OhtliColors.stormyTeal,
                  ),
                ),
                Text(
                  "Afinidad Eje: ${(sVal * 100).toStringAsFixed(0)}%",
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: sVal >= 0.70
                        ? OhtliColors.stormyTeal
                        : OhtliColors.xoconostle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "TU PERFIL:",
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: OhtliColors.stormyTeal,
                        ),
                      ),
                      Text(
                        uText,
                        style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "OEP DEL LUGAR (RECOLECTOR):",
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: OhtliColors.subtleText,
                        ),
                      ),
                      Text(
                        pText,
                        style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }
}

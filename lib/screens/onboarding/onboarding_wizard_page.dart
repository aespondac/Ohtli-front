import '../../services/user_private_data.dart';
import '../../services/outing_prefs.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../theme/colors.dart';
import '../construction_page.dart'; // RouteBackgroundPainter
import '../../utils/friendly_errors.dart';
import '../../models/poi_model.dart';
import '../../services/saved_places.dart';
import '../../theme/cdmx_photos.dart';
import '../../widgets/address_picker_widget.dart';
import '../places/places_page.dart';
import '../../services/profile_directory.dart';
import '../../services/public_profiles.dart';
import '../../services/friend_requests.dart';
import '../../widgets/ohtli_ui.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../../widgets/feedback_dialog.dart';
import '../../widgets/phone_verification_field.dart';
import '../../widgets/two_factor_card.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../services/profile_photo_service.dart';
import '../../utils/web_helpers.dart';

class OnboardingWizardPage extends StatefulWidget {
  /// Versión del cuestionario. Si app_config/onboarding.requiredVersion es mayor que la
  /// que completó la persona (onboarding_version), main.dart se lo vuelve a mostrar.
  static const int currentVersion = 2;

  final VoidCallback onCompleted;

  /// Modo de prueba (Ohtli Labs): recorre los pasos sin llamar al motor ni guardar nada, así
  /// el perfil de gustos real de la persona no cambia.
  final bool sandbox;

  const OnboardingWizardPage({
    super.key,
    required this.onCompleted,
    this.sandbox = false,
  });

  static List<double> _buildDeterministic768dFallback(String recipeText) {
    final List<double> raw = List<double>.filled(768, 0.0);
    final bytes = utf8.encode(recipeText.toLowerCase());
    int hash = 2166136261;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    for (int i = 0; i < 768; i++) {
      final int b = bytes.isEmpty ? 42 : bytes[i % bytes.length];
      final double angle = ((hash + i * 31 + b * 17) % 10000) / 10000.0 * 2 * math.pi;
      raw[i] = math.sin(angle) * 0.7 + math.cos(angle * 0.5) * 0.3;
    }
    double normSq = 0.0;
    for (final v in raw) {
      normSq += v * v;
    }
    final double norm = normSq > 0 ? math.sqrt(normSq) : 1.0;
    return raw.map((v) => v / norm).toList();
  }

  /// Invokes Yollotl Engine (/v1/user/cultural-profile) to compute the 768d
  /// text-embedding-004 taste vector and persists it into /users/{uid}/private/account.
  static Future<List<double>> synthesizeAndSaveProfile(
    String uid,
    Map<String, dynamic> rawPayload, {
    Map<String, String>? previewAxes,
  }) async {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(rawPayload);
    payload['user_id'] = uid;

    const apiUrl = String.fromEnvironment(
      'yollotlApiUrl',
      defaultValue: 'https://api-xluju5gywq-uc.a.run.app',
    );

    List<double>? tasteVector;
    String? tasteRecipe;
    Map<String, dynamic>? tasteAxes;
    String tasteModel = 'vertex_ai_text_embedding_004';

    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/v1/user/cultural-profile'),
            headers: {
              "Content-Type": "application/json",
              // El motor verifica que el token corresponda a user_id
              if (idToken != null) "Authorization": "Bearer $idToken",
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final rawVec = decoded['taste_vector'];
          if (rawVec is List && rawVec.isNotEmpty) {
            tasteVector = rawVec.map((e) => (e as num).toDouble()).toList();
          }
          if (decoded['recipe'] != null) {
            tasteRecipe = decoded['recipe'].toString();
          }
          if (decoded['user_axes'] is Map) {
            tasteAxes = Map<String, dynamic>.from(decoded['user_axes'] as Map);
          }
        }
        print("Cultural profile 4-axis 768d vector synthesized via Yollotl Engine.");
      }
    } catch (httpError) {
      print("Yollotl API call failed or offline, using deterministic 768d fallback: $httpError");
    }

    tasteAxes ??= previewAxes != null
        ? Map<String, dynamic>.from(previewAxes)
        : <String, dynamic>{
            "vocacion_cultural": (payload['cultural_interests'] as List?)?.join(', ') ?? '',
            "atmosfera_sensorial": (payload['atmosphere_preference'] as List?)?.join(', ') ?? '',
            "dinamica_social":
                "${joinOptions(OutingPref.companion.read(payload))} / ${payload['discovery_style'] ?? 'equilibrado'}",
            "entorno_urbano":
                "${joinOptions(OutingPref.transport.read(payload))} (${payload['accessibility_needs'] ?? 'estandar'})",
          };

    tasteRecipe ??= tasteAxes.entries.map((e) => "[${e.key}]: ${e.value}").join("\n");

    if (tasteVector == null || tasteVector.isEmpty) {
      tasteVector = _buildDeterministic768dFallback(tasteRecipe);
      tasteModel = 'deterministic_semantic_768d';
    }

    try {
      // onboarding_completed y updatedAt van al perfil público; el resto, al privado
      await UserPrivateData.save(uid, {
        "cultural_profile": payload,
        "taste_axes": tasteAxes,
        if (previewAxes != null) "taste_axes_preview": previewAxes,
        "taste_recipe": tasteRecipe,
        "taste_vector": tasteVector,
        "taste_vector_dim": tasteVector.length,
        "taste_model": tasteModel,
        "onboarding_completed": true,
        "taste_updated_at": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
      print("Client-side Firestore user document synchronized successfully.");
    } catch (fsWriteErr) {
      print(
        "Client-side direct Firestore write warning (backend dual-write guarantees persistence): $fsWriteErr",
      );
    }

    return tasteVector;
  }

  @override
  State<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends State<OnboardingWizardPage> {
  static const int _totalSteps = 8;
  int _currentStep = 0;
  bool _isSynthesizing = false;
  String _synthesisMessage = "Estamos preparando tus primeras recomendaciones…";

  // Paso 1: Vocación Cultural
  final Set<String> _selectedCultural = {};

  // Paso 2: Gastronomía y Atmósfera Sensorial
  final Set<String> _selectedCulinary = {};
  final Set<String> _selectedAtmosphere = {};

  // Paso 3: Dinámica Social y Nivel de Descubrimiento
  // Con quién, a qué hora, ritmo y cómo te mueves admiten varias opciones (en el orden en que se eligen)
  final Set<String> _socialCompanions = {"pareja"};
  String _discoveryStyle = "equilibrado";
  final Set<String> _preferredTimeWindows = {"tarde"};

  // Paso 4: Ritmo, Movilidad, Presupuesto y Accesibilidad
  final Set<String> _travelPaces = {"moderado"};
  final Set<String> _transportPrefs = {"caminata"};
  String _accessibilityNeeds = "estandar";

  // Paso 4: gasto promedio por salida (estimado con las respuestas; la persona lo ajusta)
  double? _avgBudgetOverride;

  // Paso 5: primeros lugares (se guardan en "Mis lugares" y entran al vector de gustos)
  final List<String> _seedPlaceIds = [];
  List<Poi> _catalog = const [];
  bool _catalogLoading = false;
  String _placeQuery = '';

  // Paso 6: direcciones (casa, hotel, oficina) para empezar rutas desde ahí
  final List<Map<String, dynamic>> _newAddresses = [];
  bool _addingAddress = false;

  // Texto libre de versiones anteriores (ya no se pide; se conserva si existía)
  String _existingBio = '';

  // Gustos prellenados con los lugares elegidos (solo si la persona no los ha tocado)
  bool _tastesTouched = false;
  bool _tastesPrefilled = false;

  // Amigos en Ohtli
  List<DocumentSnapshot> _friendSuggestions = const [];
  bool _friendsLoaded = false;
  final Set<String> _requested = {};
  Set<String> _myFriendIds = {};
  String _friendQuery = '';
  List<DocumentSnapshot> _friendResults = const [];
  bool _friendSearching = false;
  Timer? _friendDebounce;

  // Privacidad: perfil público, usertag, teléfono y si te pueden encontrar por correo o teléfono
  bool _profilePublic = true;
  bool _contactDiscoverable = true;
  bool _notificationsOn = true;
  final TextEditingController _tagController = TextEditingController();

  // Paso "Tus datos": nombre como quedó en el registro o en Google, para corregirlo
  late final String _registeredName = (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
  late final TextEditingController _firstNameController =
      TextEditingController(text: _registeredName.split(RegExp(r'\s+')).first);
  late final TextEditingController _lastNameController = TextEditingController(
      text: _registeredName.split(RegExp(r'\s+')).skip(1).join(' '));
  late String _lastNameForTag = _registeredName;
  String get _typedName => '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
  // Foto de perfil: la de Google o la que suba aquí
  String? _photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
  bool _photoUploading = false;
  String? _currentTag;
  /// null, 'checking', 'ok', 'taken' o 'invalid'
  String? _tagStatus;
  Timer? _tagDebounce;

  final List<Map<String, dynamic>> _culturalOptions = [
    {"id": "muralismo", "label": "Muralismo y Arte Monumental", "icon": Icons.brush_outlined},
    {"id": "arqueologia", "label": "Zonas Arqueológicas y Prehispánicas", "icon": Icons.account_balance_outlined},
    {"id": "museos_arte", "label": "Museos Clásicos y Contemporáneos", "icon": Icons.museum_outlined},
    {"id": "arquitectura_virreinal", "label": "Arquitectura Virreinal y Barroca", "icon": Icons.church_outlined},
    {"id": "parques_bosques", "label": "Bosques y Jardines Históricos", "icon": Icons.park_outlined},
    {"id": "teatros_foros", "label": "Teatros, Cine de Arte y Foros", "icon": Icons.theater_comedy_outlined},
    {"id": "fotografia_urbana", "label": "Fotografía Urbana y Miradores", "icon": Icons.photo_camera_outlined},
    {"id": "librerias_cafes", "label": "Librerías de Viejo y Tertulia", "icon": Icons.menu_book_outlined},
    {"id": "mercados_artesanias", "label": "Mercados de Artesanías y Diseño", "icon": Icons.storefront_outlined},
    {"id": "musica_conciertos", "label": "Jazz, Sonideros y Música Viva", "icon": Icons.music_note_outlined},
  ];

  final List<Map<String, dynamic>> _culinaryOptions = [
    {"id": "cafeterias_especialidad", "label": "Cafés de Especialidad", "icon": Icons.local_cafe_outlined},
    {"id": "cantinas_tradicionales", "label": "Cantinas Históricas con Botana", "icon": Icons.wine_bar_outlined},
    {"id": "mercados_populares", "label": "Mercados Gastronómicos Típicos", "icon": Icons.restaurant_outlined},
    {"id": "comida_callejera", "label": "Antojitos Callejeros Emblemáticos", "icon": Icons.lunch_dining_outlined},
    {"id": "alta_gastronomia", "label": "Alta Cocina Contemporánea", "icon": Icons.dinner_dining_outlined},
    {"id": "pulquerias", "label": "Pulquerías y Bebidas Ancestrales", "icon": Icons.local_bar_outlined},
    {"id": "panaderias_clasicas", "label": "Panaderías Tradicionales de Barrio", "icon": Icons.bakery_dining_outlined},
  ];

  final List<Map<String, dynamic>> _atmosphereOptions = [
    {"id": "tranquilo_arbolado", "label": "Tranquilo, Silencioso y Arbolado", "icon": Icons.eco_outlined},
    {"id": "bohemio", "label": "Bohemio, Íntimo y Artístico", "icon": Icons.palette_outlined},
    {"id": "historico", "label": "Solemne, Monumental e Histórico", "icon": Icons.auto_stories_outlined},
    {"id": "vibrante_concurrido", "label": "Vibrante y Lleno de Vida Urbana", "icon": Icons.bolt_outlined},
    {"id": "festivo_nocturno", "label": "Festivo, Musical y Social", "icon": Icons.nightlife_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingSelectionsIfAny();
    // Lugares es el 3.er paso: el catálogo se carga mientras se ajusta la accesibilidad y los datos.
    _ensureCatalog();
  }

  Future<void> _loadExistingSelectionsIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final data = await UserPrivateData.get(user.uid);
      if (mounted) {
        setState(() {
          _profilePublic = data['privacy_public'] != false;
          _contactDiscoverable = data['contact_discoverable'] != false;
          _notificationsOn = data['privacy_notifications'] != false;
          _currentTag = data['usertag'] as String?;
          final savedPhoto = data['photoURL'];
          if (savedPhoto is String && savedPhoto.startsWith('http')) _photoUrl = savedPhoto;
          _tagController.text = _currentTag ?? _suggestTag(user.displayName ?? (data['displayName'] as String?) ?? '');
        });
        _checkTag(_tagController.text, immediate: true);
      }
      final profile = data['cultural_profile'];
      if (profile is Map && mounted) {
        setState(() {
          if (profile['cultural_interests'] is List) {
            _selectedCultural
              ..clear()
              ..addAll((profile['cultural_interests'] as List).map((e) => e.toString()));
          }
          if (profile['culinary_interests'] is List) {
            _selectedCulinary
              ..clear()
              ..addAll((profile['culinary_interests'] as List).map((e) => e.toString()));
          }
          if (profile['atmosphere_preference'] is List) {
            _selectedAtmosphere
              ..clear()
              ..addAll((profile['atmosphere_preference'] as List).map((e) => e.toString()));
          }
          // Lista nueva o valor único de perfiles anteriores
          for (final (pref, target) in [
            (OutingPref.companion, _socialCompanions),
            (OutingPref.timeWindow, _preferredTimeWindows),
            (OutingPref.pace, _travelPaces),
            (OutingPref.transport, _transportPrefs),
          ]) {
            target
              ..clear()
              ..addAll(pref.read(profile));
          }
          if (profile['discovery_style'] is String) {
            _discoveryStyle = profile['discovery_style'];
          }
          if (profile['accessibility_needs'] is String) {
            _accessibilityNeeds = profile['accessibility_needs'];
          }
          if (profile['free_bio'] is String) {
            _existingBio = profile['free_bio'];
          }
          // Ya tenía gustos: no se reemplazan con los de los lugares
          _tastesTouched = _selectedCultural.isNotEmpty || _selectedCulinary.isNotEmpty;
          if (profile['avg_budget_mxn'] is num) {
            _avgBudgetOverride = (profile['avg_budget_mxn'] as num).toDouble();
          }
          if (profile['seed_poi_ids'] is List) {
            _seedPlaceIds
              ..clear()
              ..addAll((profile['seed_poi_ids'] as List).map((e) => e.toString()));
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tagController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _tagDebounce?.cancel();
    _friendDebounce?.cancel();
    _stepScrollController.dispose();
    super.dispose();
  }

  /// Orden: accesibilidad primero (para que cada quien ajuste la letra antes de todo), sus datos
  /// (foto y nombre), luego lugares, que prellenan los gustos.
  static const List<String> _stepIds = ['a11y', 'profile', 'places', 'tastes', 'outings', 'addresses', 'friends', 'privacy'];
  String get _stepId => _stepIds[_currentStep];

  /// El usertag es obligatorio para todos (identifica tu perfil aunque sea privado).
  bool get _tagOk => _tagStatus == 'ok';

  bool get _canProceed {
    switch (_stepId) {
      case 'profile':
        return _firstNameController.text.trim().isNotEmpty && _tagOk;
      case 'tastes':
        return _selectedCultural.length >= 2 && _selectedCulinary.isNotEmpty;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _finishOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  Map<String, String> _buildPreviewAxes() {
    final cultLabels = _selectedCultural.isEmpty
        ? "exploración cultural general"
        : _selectedCultural.join(", ");
    final culLabels = _selectedCulinary.isEmpty
        ? "sabores tradicionales"
        : _selectedCulinary.join(", ");
    final atmoLabels = _selectedAtmosphere.isEmpty
        ? "ambiente auténtico"
        : _selectedAtmosphere.join(", ");
    final bio = _existingBio.trim();

    return {
      "Eje 1 • Vocación Cultural y Gastronómica":
          "Afinidad por $cultLabels y experiencias en $culLabels.${bio.isNotEmpty ? ' \"$bio\"' : ''}",
      "Eje 2 • Atmósfera y Experiencia Sensorial":
          "Vibras $atmoLabels a un ritmo ${joinOptions(_travelPaces.toList())}.",
      "Eje 3 • Dinámica Social y Descubrimiento":
          "Viaje en modalidad ${joinOptions(_socialCompanions.toList())}, enfoque $_discoveryStyle en franja ${joinOptions(_preferredTimeWindows.toList())}.",
      "Eje 4 • Micro-Entorno y Caminabilidad":
          "Prioridad de traslado: ${joinOptions(_transportPrefs.toList())} ($_accessibilityNeeds).",
    };
  }

  Future<void> _finishOnboarding() async {
    if (widget.sandbox) {
      setState(() {
        _isSynthesizing = true;
        _synthesisMessage = "Modo de prueba: tu perfil real no se modificó.";
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) widget.onCompleted();
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSynthesizing = true;
      _synthesisMessage = "Guardando tus lugares y preparando tus recomendaciones…";
    });

    final payload = {
      "user_id": user.uid,
      "cultural_interests": _selectedCultural.toList(),
      "culinary_interests": _selectedCulinary.toList(),
      "atmosphere_preference": _selectedAtmosphere.toList(),
      ...OutingPref.companion.write(_socialCompanions),
      "discovery_style": _discoveryStyle,
      ...OutingPref.timeWindow.write(_preferredTimeWindows),
      ...OutingPref.pace.write(_travelPaces),
      "budget_tier": _budgetTierFor(_avgBudget),
      "avg_budget_mxn": _avgBudget,
      "seed_poi_ids": List<String>.from(_seedPlaceIds),
      ...OutingPref.transport.write(_transportPrefs),
      "accessibility_needs": _accessibilityNeeds,
      "free_bio": _existingBio,
    };

    // Lugares y direcciones primero: no dependen del motor y no deben perderse si este falla
    try {
      await SavedPlaces.addAll(_seedPlaceIds);
    } catch (e) {
      debugPrint('[onboarding] no se pudieron guardar los lugares: $e');
    }
    await _saveNewAddresses(user.uid);
    await _savePrivacy(user.uid);

    try {
      await OnboardingWizardPage.synthesizeAndSaveProfile(
        user.uid,
        payload,
        previewAxes: _buildPreviewAxes(),
      );

      // Esta versión del cuestionario ya está completa (main.dart vuelve a pedirlo si
      // app_config/onboarding.requiredVersion es mayor).
      await UserPrivateData.save(user.uid, {'onboarding_version': OnboardingWizardPage.currentVersion});
      setState(() {
        _synthesisMessage =
            "¡Listo! Tus rutas ya se parecen a ti.";
      });

      await Future.delayed(const Duration(milliseconds: 1200));

      if (mounted) {
        widget.onCompleted();
      }
    } catch (e) {
      print("Error completing onboarding: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ocurrió un detalle al guardar tu perfil: $e"),
            backgroundColor: OhtliColors.accentFill,
          ),
        );
        setState(() => _isSynthesizing = false);
      }
    }
  }

  // ==========================================================
  // UI
  // ==========================================================
  static const List<Map<String, dynamic>> _stepMeta = [
    {"label": "Accesibilidad", "icon": Icons.accessibility_new_rounded},
    {"label": "Tus datos", "icon": Icons.badge_outlined},
    {"label": "Lugares", "icon": Icons.bookmark_add_outlined},
    {"label": "Gustos", "icon": Icons.palette_outlined},
    {"label": "Salidas", "icon": Icons.directions_walk_rounded},
    {"label": "Direcciones", "icon": Icons.home_work_outlined},
    {"label": "Amigos", "icon": Icons.people_alt_outlined},
    {"label": "Privacidad", "icon": Icons.lock_outline_rounded},
  ];

  final ScrollController _stepScrollController = ScrollController();

  void _goToStep(int step) {
    if (step == _currentStep) return;
    final target = _stepIds[step];
    if (target == 'places') _ensureCatalog();
    // Al pasar de Lugares a lo siguiente, los lugares elegidos marcan los gustos.
    if (_stepId == 'places' && step > _currentStep) _prefillTastesFromPlaces();
    if (_stepId == 'profile') _saveName();
    if (target == 'friends') _loadFriendSuggestions();
    setState(() => _currentStep = step);
    if (_stepScrollController.hasClients) _stepScrollController.jumpTo(0);
  }

  String get _blockedHint {
    if (_stepId == 'profile') {
      if (_firstNameController.text.trim().isEmpty) return "Escribe tu nombre";
      if (!_tagOk) {
        if (_tagController.text.trim().isEmpty) return "Elige tu usertag";
        return _tagStatus == 'checking' ? "Revisando tu usertag…" : "Elige otro usertag";
      }
    }
    if (_stepId == 'tastes') {
      if (_selectedCultural.length < 2) {
        final missing = 2 - _selectedCultural.length;
        return missing == 1 ? "Elige 1 actividad más" : "Elige al menos 2 actividades";
      }
      return "Elige al menos 1 sabor";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ohtliIsMobileWidth(MediaQuery.of(context).size.width);
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RouteBackgroundPainter(OhtliColors.routeLine),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _isSynthesizing
                      ? KeyedSubtree(key: const ValueKey('loading'), child: _buildLoadingView())
                      : KeyedSubtree(key: const ValueKey('wizard'), child: _buildWizardCard(isMobile)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    final axes = [
      {"label": "Tus gustos", "icon": Icons.palette_outlined, "color": OhtliColors.stormyTeal},
      {"label": "El ambiente", "icon": Icons.spa_outlined, "color": OhtliColors.cempasuchil},
      {"label": "Con quién sales", "icon": Icons.groups_outlined, "color": OhtliColors.xoconostle},
      {"label": "Cómo te mueves", "icon": Icons.directions_walk_rounded, "color": OhtliColors.stormyTeal},
    ];
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(color: OhtliColors.stormyTeal, strokeWidth: 3),
                ),
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    color: OhtliColors.accent.withValues(alpha: 0.8),
                    strokeWidth: 2,
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    'assets/icon_isologo.svg',
                    colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Text(
            "Armando tu Ohtli",
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _synthesisMessage,
              key: ValueKey(_synthesisMessage),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: OhtliColors.subtleText,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Los 4 ejes aparecen uno a uno mientras se sintetiza el perfil
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: List.generate(axes.length, (i) {
              final a = axes[i];
              final color = a["color"] as Color;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 500 + i * 350),
                curve: Curves.easeOutBack,
                builder: (context, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a["icon"] as IconData, size: 15, color: color),
                      const SizedBox(width: 6),
                      Text(
                        a["label"] as String,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 22),

        ],
      ),
    );
  }

  Widget _buildWizardCard(bool isMobile) {
    final isLast = _currentStep == _totalSteps - 1;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: isMobile ? 10 : 24),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 20 : 36, isMobile ? 20 : 28, isMobile ? 20 : 36, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SvgPicture.asset(
                          'assets/icon_isologo.svg',
                          colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Tu Ohtli a tu medida",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 15 : 16,
                                fontWeight: FontWeight.w700,
                                color: OhtliColors.onyx,
                              ),
                            ),
                            Text(
                              isMobile
                                  ? "Paso ${_currentStep + 1} de $_totalSteps · ${_stepMeta[_currentStep]["label"]}"
                                  : "Así armamos rutas que sí te gusten",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                      if (!isMobile)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Text(
                          "Paso ${_currentStep + 1} de $_totalSteps",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.subtleText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FeedbackButton(
                        compact: true,
                        screen: 'onboarding',
                        contextBuilder: () => {
                          'paso': '${_currentStep + 1} de $_totalSteps · ${_stepMeta[_currentStep]["label"]}',
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _buildStepper(isMobile),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                controller: _stepScrollController,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(isMobile ? 20 : 36, 20, isMobile ? 20 : 36, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_currentStep),
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildStepContent(constraints.maxWidth, isMobile),
                    ),
                  ),
                ),
              ),
            ),
            // Barra de acciones fija
            Container(
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 36, 14, isMobile ? 16 : 36, isMobile ? 16 : 22),
              decoration: BoxDecoration(
                color: OhtliColors.cardBg,
                border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
              ),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    OhtliSecondaryButton(compact: true, label: isMobile ? 'Atrás' : 'Anterior', icon: Icons.arrow_back_rounded, onPressed: _previousStep),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _canProceed ? 0 : 1,
                      child: Text(
                        _blockedHint,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OhtliPrimaryButton(
                    compact: isMobile,
                    highlight: isLast,
                    label: isLast ? '¡Listo, empezar!' : 'Siguiente',
                    icon: isLast ? Icons.auto_awesome_rounded : Icons.arrow_forward_rounded,
                    onPressed: _canProceed ? _nextStep : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Indicador de pasos: segmentos con etiqueta; los pasos ya visitados son navegables
  static TextStyle _stepLabelStyle(bool active) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      );

  /// Ancho de cada paso en escritorio: proporcional a su etiqueta (en negritas, como
  /// cuando está activa) más el icono, para que «Accesibilidad» no se corte.
  List<int> _stepFlexes(bool isMobile) {
    if (isMobile) return List.filled(_totalSteps, 1);
    return [
      for (final meta in _stepMeta)
        ((TextPainter(
                  text: TextSpan(text: meta["label"] as String, style: _stepLabelStyle(true)),
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                )..layout())
                .width +
            19 + 4)
            .ceil(),
    ];
  }

  Widget _buildStepper(bool isMobile) {
    final flexes = _stepFlexes(isMobile);
    return Row(
      children: List.generate(_totalSteps, (i) {
        final done = i < _currentStep;
        final active = i == _currentStep;
        final meta = _stepMeta[i];
        final color = (done || active) ? OhtliColors.stormyTeal : OhtliColors.subtleText.withValues(alpha: 0.6);
        return Expanded(
          flex: flexes[i],
          child: Padding(
            padding: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 6),
            child: InkWell(
              onTap: done ? () => _goToStep(i) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(height: 5, color: OhtliColors.innerCardBg),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            widthFactor: (done || active) ? 1 : 0,
                            child: Container(
                              height: 5,
                              color: active ? OhtliColors.stormyTeal : OhtliColors.stormyTeal.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(done ? Icons.check_circle_rounded : meta["icon"] as IconData, size: 14, color: color),
                        if (!isMobile) ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              meta["label"] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _stepLabelStyle(active).copyWith(color: active ? OhtliColors.onyx : color),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent(double width, bool isMobile) {
    switch (_stepId) {
      case 'a11y':
        return _buildA11yStep(width);
      case 'profile':
        return _buildProfileStep(width);
      case 'places':
        return _buildSeedPlacesStep(width);
      case 'tastes':
        return _buildTastesStep(width, isMobile);
      case 'outings':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_buildSocialDiscoveryStep(), const SizedBox(height: 30), _buildPaceMobilityStep()],
        );
      case 'addresses':
        return _buildAddressesStep();
      case 'friends':
        return _buildFriendsStep(width);
      case 'privacy':
        return _buildPrivacyStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepHeader({required String eyebrow, required String title, required String description}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow.toUpperCase(), style: OhtliUi.eyebrow(OhtliColors.accentText)),
        const SizedBox(height: 8),
        Semantics(header: true, child: Text(title, style: OhtliUi.title(size: 28))),
        const SizedBox(height: 10),
        Text(
          description,
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildGroupLabel(String text, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: OhtliColors.onyx),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildMultiHint() => Text(
        "Elige una o varias",
        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
      );

  Widget _buildSelectionCounter(int count, {int? min}) {
    final ok = min == null || count >= min;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok && count > 0 ? OhtliColors.stormyTeal.withValues(alpha: 0.12) : OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ok && count > 0 ? OhtliColors.stormyTeal.withValues(alpha: 0.3) : OhtliColors.cardBorder),
      ),
      child: Text(
        min != null ? "$count seleccionadas · mín. $min" : "$count seleccionadas",
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: ok && count > 0 ? OhtliColors.stormyTeal : OhtliColors.subtleText,
        ),
      ),
    );
  }

  // Cuadrícula de mosaicos de selección múltiple
  Widget _buildMultiSelectGrid({
    required List<Map<String, dynamic>> options,
    required Set<String> selected,
    required Color accent,
    required double width,
    required bool isMobile,
  }) {
    final columns = width < 420 ? 2 : (width < 700 ? 3 : 4);
    const spacing = 10.0;
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: options.map((opt) {
        final id = opt["id"] as String;
        final isSelected = selected.contains(id);
        return SizedBox(
          width: tileWidth,
          child: _StaggerIn(index: options.indexOf(opt), child: _SelectableTile(
            icon: opt["icon"] as IconData,
            label: opt["label"] as String,
            selected: isSelected,
            accent: accent,
            onTap: () => setState(() {
              _tastesTouched = true;
              if (isSelected) {
                selected.remove(id);
              } else {
                selected.add(id);
              }
            }),
          )),
        );
      }).toList(),
    );
  }

  // Grupo de selección única con pastillas que se ajustan en móvil
  Widget _buildChoiceGroup({
    required List<Map<String, dynamic>> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final id = opt["value"] as String;
        final isSelected = id == value;
        return _ChoicePill(
          icon: opt["icon"] as IconData,
          label: opt["label"] as String,
          selected: isSelected,
          onTap: () => setState(() => onChanged(id)),
        );
      }).toList(),
    );
  }

  // Grupo de selección múltiple con pastillas; siempre queda al menos una opción
  Widget _buildMultiChoiceGroup({
    required List<Map<String, dynamic>> options,
    required Set<String> selected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final id = opt["value"] as String;
        final isSelected = selected.contains(id);
        return _ChoicePill(
          icon: opt["icon"] as IconData,
          label: opt["label"] as String,
          selected: isSelected,
          onTap: () => setState(() {
            if (!isSelected) {
              selected.add(id);
            } else if (selected.length > 1) {
              selected.remove(id);
            }
          }),
        );
      }).toList(),
    );
  }

  Widget _buildSocialDiscoveryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Tus salidas",
          title: "¿Cómo te gusta salir?",
          description: "No es lo mismo recorrer la ciudad solo que con niños o con amigos de noche.",
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("¿Con quién acostumbras recorrer la ciudad?", trailing: _buildMultiHint()),
        const SizedBox(height: 12),
        _buildMultiChoiceGroup(
          selected: _socialCompanions,
          options: const [
            {"value": "solo", "label": "Solo", "icon": Icons.person_outline},
            {"value": "pareja", "label": "En Pareja", "icon": Icons.favorite_border},
            {"value": "amigos", "label": "Amigos", "icon": Icons.groups_outlined},
            {"value": "familia", "label": "Familia", "icon": Icons.family_restroom_outlined},
          ],
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("¿Qué tipo de lugares prefieres?"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _discoveryStyle,
          onChanged: (v) => _discoveryStyle = v,
          options: const [
            {"value": "iconico", "label": "Íconos Imprescindibles", "icon": Icons.account_balance_outlined},
            {"value": "equilibrado", "label": "Híbrido Equilibrado", "icon": Icons.auto_awesome_mosaic_outlined},
            {"value": "joyas_ocultas", "label": "Joyas Ocultas de Barrio", "icon": Icons.explore_outlined},
          ],
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("¿A qué hora sales?", trailing: _buildMultiHint()),
        const SizedBox(height: 12),
        _buildMultiChoiceGroup(
          selected: _preferredTimeWindows,
          options: const [
            {"value": "manana", "label": "Mañana", "icon": Icons.wb_sunny_outlined},
            {"value": "tarde", "label": "Tarde", "icon": Icons.wb_twilight_outlined},
            {"value": "noche", "label": "Noche", "icon": Icons.nights_stay_outlined},
            {"value": "jornada_completa", "label": "Todo el Día", "icon": Icons.schedule_outlined},
          ],
        ),
      ],
    );
  }

  Widget _buildPaceMobilityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Ritmo y presupuesto",
          title: "¿A qué ritmo y cuánto gastas?",
          description: "Calculamos un gasto promedio con lo que elegiste; ajústalo si quieres.",
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("Ritmo de la jornada", trailing: _buildMultiHint()),
        const SizedBox(height: 12),
        _buildMultiChoiceGroup(
          selected: _travelPaces,
          options: const [
            {"value": "relajado", "label": "Relajado", "icon": Icons.spa_outlined},
            {"value": "moderado", "label": "Equilibrado", "icon": Icons.explore_outlined},
            {"value": "intensivo", "label": "Intensivo", "icon": Icons.bolt_outlined},
          ],
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("¿Cómo te mueves?", trailing: _buildMultiHint()),
        const SizedBox(height: 12),
        _buildMultiChoiceGroup(
          selected: _transportPrefs,
          options: const [
            {"value": "caminata", "label": "Caminata Peatonal", "icon": Icons.directions_walk},
            {"value": "bicicleta", "label": "Bici / Ecobici", "icon": Icons.pedal_bike},
            {"value": "transporte_publico", "label": "Metro / Metrobús", "icon": Icons.directions_subway},
            {"value": "mixto", "label": "Mixto", "icon": Icons.alt_route},
            {"value": "auto", "label": "Taxi / Auto", "icon": Icons.local_taxi},
          ],
        ),
        const SizedBox(height: 26),
        _buildBudgetEstimator(),
      ],
    );
  }

  // ==========================================================
  // Presupuesto promedio estimado
  // ==========================================================

  /// Costo típico por persona (MXN) de comer en cada tipo de lugar.
  static const Map<String, double> _foodCost = {
    "cafeterias_especialidad": 140,
    "cantinas_tradicionales": 320,
    "mercados_populares": 160,
    "comida_callejera": 110,
    "alta_gastronomia": 950,
    "pulquerias": 170,
    "panaderias_clasicas": 90,
  };

  /// Entrada típica de cada vocación cultural (muchos lugares son gratis).
  static const Map<String, double> _entryCost = {
    "muralismo": 40,
    "arqueologia": 95,
    "museos_arte": 90,
    "arquitectura_virreinal": 0,
    "parques_bosques": 0,
    "teatros_foros": 250,
    "fotografia_urbana": 30,
    "librerias_cafes": 0,
    "mercados_artesanias": 0,
    "musica_conciertos": 280,
  };

  static const Map<String, double> _transportCost = {
    "caminata": 0,
    "bicicleta": 35,
    "transporte_publico": 25,
    "mixto": 90,
    "auto": 260,
  };

  static const Map<String, double> _paceFactor = {"relajado": 0.85, "moderado": 1.0, "intensivo": 1.25};

  /// A ritmo intensivo se come más veces en la salida.
  static const Map<String, double> _paceFoodFactor = {"relajado": 1.0, "moderado": 1.0, "intensivo": 1.5};

  double _avg(Iterable<String> ids, Map<String, double> table, double fallback) {
    final values = ids.where(table.containsKey).map((id) => table[id]!).toList();
    if (values.isEmpty) return fallback;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// (comida, entradas, traslados, total) por salida, redondeado a 50.
  ({double food, double entries, double transport, double total}) get _budgetEstimate {
    // Con varios ritmos o medios se promedia entre los elegidos
    final pace = _avg(_travelPaces, _paceFactor, 1.0);
    final food = _avg(_selectedCulinary, _foodCost, 200) * _avg(_travelPaces, _paceFoodFactor, 1.0);
    final entries = _avg(_selectedCultural, _entryCost, 60) * 2; // ~2 recintos por salida
    final transport = _avg(_transportPrefs, _transportCost, 40);
    double round50(double v) => (v / 50).round() * 50.0;
    final total = round50((food + entries + transport) * pace).clamp(150.0, 3000.0);
    return (food: round50(food), entries: round50(entries), transport: round50(transport), total: total);
  }

  double get _avgBudget => _avgBudgetOverride ?? _budgetEstimate.total;

  String _budgetTierFor(double amount) => amount < 300 ? "economico" : (amount <= 650 ? "medio" : "alto");

  String _money(double v) => "\$${v.round()}";

  Widget _buildBudgetEstimator() {
    final est = _budgetEstimate;
    final value = _avgBudget.clamp(150.0, 3000.0);
    final adjusted = _avgBudgetOverride != null && (_avgBudgetOverride! - est.total).abs() >= 1;
    Widget part(IconData icon, String label, double amount) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: OhtliColors.subtleText),
            const SizedBox(width: 6),
            Text("$label ${amount <= 0 ? 'gratis' : '~${_money(amount)}'}",
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel("¿Cuánto gastas normalmente en una salida?"),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(value),
                    style: GoogleFonts.outfit(fontSize: 34, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text("MXN por persona", style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText)),
                  ),
                  const Spacer(),
                  if (adjusted)
                    TextButton(
                      onPressed: () => setState(() => _avgBudgetOverride = null),
                      child: Text("Usar estimado (${_money(est.total)})",
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.accentText)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                adjusted
                    ? "Lo ajustaste tú. Lo usaremos como tope al armar tus rutas."
                    : "Lo estimamos con lo que elegiste. Muévelo si gastas más o menos.",
                style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
              ),
              Slider(
                value: value,
                min: 150,
                max: 3000,
                divisions: 57,
                label: _money(value),
                activeColor: OhtliColors.stormyTeal,
                onChanged: (v) => setState(() => _avgBudgetOverride = v),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  part(Icons.restaurant_outlined, "Comida", est.food),
                  part(Icons.confirmation_number_outlined, "Entradas", est.entries),
                  part(Icons.directions_transit_outlined, "Traslados", est.transport),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // Primeros lugares
  // ==========================================================

  /// Categorías del catálogo que corresponden a cada respuesta.
  static const Map<String, List<String>> _interestCategories = {
    "muralismo": ["artwork", "arts_centre", "museum"],
    "arqueologia": ["arqueologia", "museum", "monument"],
    "museos_arte": ["museum", "gallery"],
    "arquitectura_virreinal": ["place_of_worship", "monument", "attraction"],
    "parques_bosques": ["park", "garden", "nature_reserve"],
    "teatros_foros": ["theatre", "cinema", "arts_centre"],
    "fotografia_urbana": ["viewpoint", "attraction", "monument"],
    "librerias_cafes": ["books", "library", "cafe"],
    "mercados_artesanias": ["marketplace"],
    "musica_conciertos": ["bar", "pub", "nightclub"],
    "cafeterias_especialidad": ["cafe", "coffee"],
    "cantinas_tradicionales": ["cantina", "bar"],
    "mercados_populares": ["marketplace"],
    "comida_callejera": ["fast_food"],
    "alta_gastronomia": ["restaurant"],
    "pulquerias": ["pulqueria"],
    "panaderias_clasicas": ["bakery", "pastry"],
  };

  Future<void> _ensureCatalog() async {
    if (_catalog.isNotEmpty || _catalogLoading) return;
    setState(() => _catalogLoading = true);
    try {
      final pois = await PlacesPage.loadCatalog();
      if (mounted) setState(() => _catalog = pois.where((p) => p.isValidCulturalPlace).toList());
    } catch (e) {
      debugPrint('[onboarding] catálogo no disponible: $e');
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u');

  /// Sugerencias según las respuestas, alternando categorías para que haya variedad.
  List<Poi> get _placeSuggestions {
    final query = _norm(_placeQuery.trim());
    if (query.isNotEmpty) {
      return _catalog.where((p) => _norm(p.name).contains(query)).take(18).toList();
    }
    final cats = <String>[];
    for (final id in [..._selectedCultural, ..._selectedCulinary]) {
      for (final c in _interestCategories[id] ?? const <String>[]) {
        if (!cats.contains(c)) cats.add(c);
      }
    }
    // Sin gustos todavía (Lugares va antes): una mezcla variada de la ciudad.
    if (cats.isEmpty) cats.addAll(["museum", "cafe", "park", "marketplace", "theatre", "viewpoint", "restaurant", "gallery", "bar", "bakery"]);
    final byCat = <String, List<Poi>>{
      for (final c in cats) c: _catalog.where((p) => p.category == c && p.imageUrl.isNotEmpty).toList(),
    };
    final out = <Poi>[];
    var round = 0;
    while (out.length < 18 && byCat.values.any((l) => l.length > round)) {
      for (final c in cats) {
        final list = byCat[c]!;
        if (round < list.length && !out.contains(list[round])) out.add(list[round]);
        if (out.length >= 18) break;
      }
      round++;
    }
    return out;
  }

  /// Detalle del lugar (foto, historia, ubicación…); desde ahí también se elige.
  void _openSeedPlace(Poi poi, int position) {
    PoiDetailDialog.show(
      context,
      poi,
      surface: 'onboarding',
      position: position,
      picked: _seedPlaceIds.contains(poi.poiId),
      onPick: (picked) {
        if (!mounted) return;
        setState(() {
          _seedPlaceIds.remove(poi.poiId);
          if (picked) _seedPlaceIds.add(poi.poiId);
        });
      },
    );
  }

  Widget _buildSeedPlacesStep(double width) {
    final suggestions = _placeSuggestions;
    final columns = width < 420 ? 2 : (width < 700 ? 3 : 4);
    const spacing = 10.0;
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Empecemos por los lugares",
          title: "¿Qué lugares te llaman?",
          description:
              "Elige los que conoces o quieres conocer; toca «Ver» para conocer cada uno. Se guardan en Mis lugares y con ellos marcamos tus gustos en el siguiente paso.",
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: (v) => setState(() => _placeQuery = v),
          style: GoogleFonts.inter(color: OhtliColors.onyx),
          decoration: InputDecoration(
            hintText: "Busca un lugar que ya conozcas o quieras conocer",
            hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: OhtliColors.accentText),
            filled: true,
            fillColor: OhtliColors.innerCardBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: OhtliColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: OhtliColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildGroupLabel(
          _placeQuery.trim().isEmpty ? "Sugeridos para ti" : "Resultados",
          trailing: _buildSelectionCounter(_seedPlaceIds.length),
        ),
        const SizedBox(height: 12),
        if (_catalogLoading && _catalog.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
          )
        else if (suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _catalog.isEmpty
                  ? "No pudimos cargar los lugares. Puedes seguir y guardarlos después desde Lugares."
                  : "No encontramos lugares con ese nombre.",
              style: GoogleFonts.inter(color: OhtliColors.subtleText),
            ),
          )
        else
          Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final poi in suggestions)
                SizedBox(
                  width: tileWidth,
                  child: _StaggerIn(index: suggestions.indexOf(poi), child: _SeedPlaceTile(
                    poi: poi,
                    selected: _seedPlaceIds.contains(poi.poiId),
                    onTap: () => setState(() {
                      if (!_seedPlaceIds.remove(poi.poiId)) _seedPlaceIds.add(poi.poiId);
                    }),
                    onView: () => _openSeedPlace(poi, suggestions.indexOf(poi)),
                  )),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          "Opcional, pero ayuda mucho: elige 3 o más.",
          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
        ),
      ],
    );
  }

  // ==========================================================
  // Direcciones
  // ==========================================================

  Future<void> _saveNewAddresses(String uid) async {
    if (_newAddresses.isEmpty || widget.sandbox) return;
    try {
      final data = await UserPrivateData.get(uid);
      final existing = (data['addresses'] is List)
          ? (data['addresses'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      await UserPrivateData.save(uid, {'addresses': [...existing, ..._newAddresses]});
    } catch (e) {
      debugPrint('[onboarding] no se pudieron guardar las direcciones: $e');
    }
  }

  Widget _buildAddressesStep() {
    if (_addingAddress) {
      return AddressPickerWidget(
        existingNames: _newAddresses
            .map((a) => (a['customName'] as String?) ?? '')
            .where((n) => n.isNotEmpty)
            .toList(),
        onCancel: () => setState(() => _addingAddress = false),
        onSave: (address) => setState(() {
          final now = DateTime.now().millisecondsSinceEpoch;
          _newAddresses.add({
            ...address,
            'id': 'addr_${now}_${address['street'].hashCode}',
            'updatedAt': now,
          });
          _addingAddress = false;
        }),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Tus puntos de partida",
          title: "¿Desde dónde sueles salir?",
          description:
              "Guarda tu casa, tu hotel o la oficina para empezar tus rutas desde ahí con un toque. Puedes cambiarlas después en Cuenta.",
        ),
        const SizedBox(height: 20),
        for (final a in _newAddresses)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.place_outlined, color: OhtliColors.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ((a['customName'] as String?)?.isNotEmpty ?? false) ? a['customName'] : (a['category'] ?? 'Dirección'),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      Text(
                        "${a['street'] ?? ''}, ${a['suburb'] ?? ''}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar dirección',
                  onPressed: () => setState(() => _newAddresses.remove(a)),
                  icon: Icon(Icons.close_rounded, size: 18, color: OhtliColors.subtleText),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _addingAddress = true),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(_newAddresses.isEmpty ? "Agregar una dirección" : "Agregar otra"),
            style: OutlinedButton.styleFrom(
              foregroundColor: OhtliColors.accentText,
              side: BorderSide(color: OhtliColors.accentText.withValues(alpha: 0.5)),
              shape: const StadiumBorder(),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Opcional. Si prefieres, sigue sin agregar ninguna.",
          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
        ),
      ],
    );
  }

  // ==========================================================
  // Lugares → gustos
  // ==========================================================

  /// Qué gusto sugiere cada categoría del catálogo (cultura/sabor y ambiente).
  static const Map<String, List<String>> _categoryTastes = {
    "museum": ["museos_arte"],
    "gallery": ["museos_arte"],
    "artwork": ["muralismo"],
    "arts_centre": ["muralismo", "teatros_foros"],
    "arqueologia": ["arqueologia"],
    "place_of_worship": ["arquitectura_virreinal"],
    "monument": ["arquitectura_virreinal"],
    "park": ["parques_bosques"],
    "garden": ["parques_bosques"],
    "nature_reserve": ["parques_bosques"],
    "theatre": ["teatros_foros"],
    "cinema": ["teatros_foros"],
    "viewpoint": ["fotografia_urbana"],
    "attraction": ["fotografia_urbana"],
    "books": ["librerias_cafes"],
    "library": ["librerias_cafes"],
    "marketplace": ["mercados_artesanias", "mercados_populares"],
    "bar": ["musica_conciertos", "cantinas_tradicionales"],
    "pub": ["musica_conciertos"],
    "nightclub": ["musica_conciertos"],
    "cafe": ["cafeterias_especialidad"],
    "coffee": ["cafeterias_especialidad"],
    "cantina": ["cantinas_tradicionales"],
    "fast_food": ["comida_callejera"],
    "restaurant": ["alta_gastronomia"],
    "pulqueria": ["pulquerias"],
    "bakery": ["panaderias_clasicas"],
    "pastry": ["panaderias_clasicas"],
  };

  static const Map<String, String> _categoryAtmosphere = {
    "park": "tranquilo_arbolado",
    "garden": "tranquilo_arbolado",
    "nature_reserve": "tranquilo_arbolado",
    "museum": "historico",
    "monument": "historico",
    "place_of_worship": "historico",
    "arqueologia": "historico",
    "gallery": "bohemio",
    "books": "bohemio",
    "arts_centre": "bohemio",
    "cafe": "bohemio",
    "marketplace": "vibrante_concurrido",
    "fast_food": "vibrante_concurrido",
    "attraction": "vibrante_concurrido",
    "bar": "festivo_nocturno",
    "pub": "festivo_nocturno",
    "nightclub": "festivo_nocturno",
    "cantina": "festivo_nocturno",
    "pulqueria": "festivo_nocturno",
  };

  /// Marca los gustos que se parecen a los lugares elegidos. Solo si la persona aún no
  /// los ha tocado: nunca le quitamos lo que ya eligió.
  void _prefillTastesFromPlaces() {
    if (_tastesTouched || _seedPlaceIds.isEmpty) return;
    final chosen = _catalog.where((p) => _seedPlaceIds.contains(p.poiId));
    final culturalIds = _culturalOptions.map((o) => o["id"] as String).toSet();
    final culinaryIds = _culinaryOptions.map((o) => o["id"] as String).toSet();
    final cultural = <String>{};
    final culinary = <String>{};
    final atmosphere = <String>{};
    for (final p in chosen) {
      for (final id in _categoryTastes[p.category] ?? const <String>[]) {
        if (culturalIds.contains(id)) cultural.add(id);
        if (culinaryIds.contains(id)) culinary.add(id);
      }
      final a = _categoryAtmosphere[p.category];
      if (a != null) atmosphere.add(a);
    }
    if (cultural.isEmpty && culinary.isEmpty && atmosphere.isEmpty) return;
    setState(() {
      _selectedCultural
        ..clear()
        ..addAll(cultural);
      _selectedCulinary
        ..clear()
        ..addAll(culinary);
      _selectedAtmosphere
        ..clear()
        ..addAll(atmosphere);
      _tastesPrefilled = true;
    });
  }

  // ==========================================================
  // Paso: accesibilidad
  // ==========================================================

  Widget _buildA11yStep(double width) {
    final settings = OhtliSettings.instance;
    final name = (FirebaseAuth.instance.currentUser?.displayName ?? '').split(' ').first;
    const sizes = [
      (OhtliFontSize.small, 'Chica', 13.0),
      (OhtliFontSize.medium, 'Normal', 16.0),
      (OhtliFontSize.large, 'Grande', 19.0),
      (OhtliFontSize.extraLarge, 'Muy grande', 22.0),
    ];
    const themes = [
      (OhtliThemeMode.system, 'Como mi equipo', Icons.brightness_auto_rounded),
      (OhtliThemeMode.light, 'Claro', Icons.light_mode_rounded),
      (OhtliThemeMode.dark, 'Oscuro', Icons.dark_mode_rounded),
    ];
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            eyebrow: name.isEmpty ? "¡Bienvenido a Ohtli!" : "¡Hola, $name!",
            title: "Primero, que estés a gusto",
            description: "Ajusta cómo se ve Ohtli. Lo verás al instante y puedes cambiarlo cuando quieras desde el botón de accesibilidad.",
          ),
          const SizedBox(height: 24),
          _buildGroupLabel("Tamaño de la letra"),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < sizes.length; i++)
                _StaggerIn(
                  index: i,
                  child: _OptionCard(
                    selected: settings.fontSize == sizes[i].$1,
                    onTap: () => settings.fontSize = sizes[i].$1,
                    semanticsLabel: 'Letra ${sizes[i].$2}',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Aa',
                            textScaler: TextScaler.noScaling,
                            style: GoogleFonts.outfit(fontSize: sizes[i].$3 * 1.6, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                        const SizedBox(height: 4),
                        Text(sizes[i].$2, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
          _buildGroupLabel("Colores"),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in themes)
                OhtliChoiceChip(label: t.$2, icon: t.$3, selected: settings.themeMode == t.$1, onTap: () => settings.themeMode = t.$1),
            ],
          ),
          const SizedBox(height: 26),
          _buildGroupLabel("¿Cómo te mueves por la ciudad?"),
          const SizedBox(height: 6),
          Text("Si eliges rampas y accesos, tus rutas evitan escaleras y caminos difíciles cuando se pueda.",
              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45)),
          const SizedBox(height: 12),
          _buildChoiceGroup(
            value: _accessibilityNeeds,
            onChanged: (v) => _accessibilityNeeds = v,
            options: const [
              {"value": "estandar", "label": "Camino sin problema", "icon": Icons.directions_walk_outlined},
              {"value": "accesibilidad_universal", "label": "Necesito rampas y accesos", "icon": Icons.accessible_outlined},
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // Paso: gustos (prellenados con los lugares)
  // ==========================================================

  Widget _buildTastesStep(double width, bool isMobile) {
    Widget grid(List<Map<String, dynamic>> options, Set<String> selected, Color accent) => _buildMultiSelectGrid(
          options: options,
          selected: selected,
          accent: accent,
          width: width,
          isMobile: isMobile,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Lo que te gusta",
          title: "¿Qué disfrutas de la ciudad?",
          description: "Con esto elegimos los lugares de tus rutas. Marca todo lo que te llame.",
        ),
        if (_tastesPrefilled) ...[
          const SizedBox(height: 16),
          _StaggerIn(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OhtliColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OhtliColors.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: OhtliColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Marcamos lo que se parece a los lugares que elegiste. Ajusta lo que quieras.",
                      style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        _buildGroupLabel("Actividades", trailing: _buildSelectionCounter(_selectedCultural.length, min: 2)),
        const SizedBox(height: 12),
        grid(_culturalOptions, _selectedCultural, OhtliColors.stormyTeal),
        const SizedBox(height: 28),
        _buildGroupLabel("Sabores", trailing: _buildSelectionCounter(_selectedCulinary.length, min: 1)),
        const SizedBox(height: 12),
        grid(_culinaryOptions, _selectedCulinary, OhtliColors.cempasuchil),
        const SizedBox(height: 28),
        _buildGroupLabel("Ambiente", trailing: _buildSelectionCounter(_selectedAtmosphere.length)),
        const SizedBox(height: 12),
        grid(_atmosphereOptions, _selectedAtmosphere, OhtliColors.xoconostle),
      ],
    );
  }

  // ==========================================================
  // Paso: amigos en Ohtli
  // ==========================================================

  Future<void> _loadFriendSuggestions() async {
    if (_friendsLoaded) return;
    _friendsLoaded = true;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || widget.sandbox) return;
    try {
      final db = FirebaseFirestore.instance;
      final graph = await db.collection('users').doc(me.uid).collection('social').doc('graph').get();
      _myFriendIds = ((graph.data()?['friends'] as List?) ?? const []).map((e) => e.toString()).toSet();
      final snap = await db.collection('public_profiles').limit(40).get();
      final list = snap.docs
          .where((d) => d.id != me.uid && !_myFriendIds.contains(d.id) && d.data()['profilePrivate'] != true && d.data()['isDeleted'] != true)
          .take(12)
          .toList();
      if (mounted) setState(() => _friendSuggestions = list);
    } catch (e) {
      debugPrint('[onboarding] sugerencias de amigos: $e');
    }
  }

  void _onFriendQuery(String q) {
    setState(() => _friendQuery = q);
    _friendDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _friendResults = const [];
        _friendSearching = false;
      });
      return;
    }
    _friendDebounce = Timer(const Duration(milliseconds: 380), () => _searchFriends(q.trim()));
  }

  Future<void> _searchFriends(String q) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    setState(() => _friendSearching = true);
    final found = <DocumentSnapshot>[];
    try {
      // Nombre (cualquier palabra, sin acentos), usertag con o sin @, correo o teléfono
      found.addAll(await PublicProfiles.search(q,
          lookup: ProfileDirectory.lookup, classify: ProfileDirectory.classify, normalizeTag: ProfileDirectory.normalizeTag));
    } catch (e) {
      debugPrint('[onboarding] búsqueda de amigos: $e');
    }
    if (!mounted || _friendQuery.trim() != q) return;
    setState(() {
      // Solo perfiles públicos se pueden encontrar.
      _friendResults = found.where((d) => d.id != me.uid && (d.data() as Map<String, dynamic>?)?['profilePrivate'] != true).toList();
      _friendSearching = false;
    });
  }

  Future<void> _addFriend(DocumentSnapshot doc) async {
    if (_requested.contains(doc.id)) return;
    setState(() => _requested.add(doc.id));
    try {
      await FriendRequests.send(doc.id);
    } catch (e) {
      debugPrint('[onboarding] solicitud: $e');
      if (mounted) setState(() => _requested.remove(doc.id));
    }
  }

  Widget _buildFriendsStep(double width) {
    final searching = _friendQuery.trim().isNotEmpty;
    final list = searching ? _friendResults : _friendSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Viaja acompañado",
          title: "¿Quiénes de tus amigos ya están aquí?",
          description: "Agrégalos para ver sus viajes, armar rutas juntos y prepararles sorpresas.",
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: _onFriendQuery,
          style: GoogleFonts.inter(color: OhtliColors.onyx),
          decoration: InputDecoration(
            hintText: "Nombre, @usertag, correo o teléfono",
            hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14),
            prefixIcon: Icon(Icons.person_search_rounded, color: OhtliColors.accentText),
            suffixIcon: _friendSearching
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
            filled: true,
            fillColor: OhtliColors.innerCardBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: OhtliColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: OhtliColors.cardBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6)),
          ),
        ),
        const SizedBox(height: 8),
        Text("Solo aparecen perfiles públicos. El correo y el teléfono deben estar completos.",
            style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
        const SizedBox(height: 16),
        _buildGroupLabel(searching ? "Resultados" : "Viajeros en Ohtli",
            trailing: _requested.isEmpty ? null : _buildSelectionCounter(_requested.length)),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              searching
                  ? (_friendSearching ? "Buscando…" : "No encontramos un perfil público con eso.")
                  : (widget.sandbox ? "En el modo de prueba no se muestran personas." : "Todavía no hay sugerencias. Búscalos por su nombre o @usertag."),
              style: GoogleFonts.inter(color: OhtliColors.subtleText),
            ),
          )
        else
          for (var i = 0; i < list.length; i++) _StaggerIn(index: i, child: _friendRow(list[i])),
        const SizedBox(height: 8),
        Text("Opcional. También puedes hacerlo después desde Amigos.", style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
      ],
    );
  }

  Widget _friendRow(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final name = (data['displayName'] as String?) ?? 'Viajero Ohtli';
    final photo = data['photoURL'] as String?;
    final tag = data['usertag'] as String?;
    final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final isFriend = _myFriendIds.contains(doc.id);
    final requested = _requested.contains(doc.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: OhtliColors.innerCardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: requested ? OhtliColors.accentText.withValues(alpha: 0.5) : OhtliColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: OhtliColors.stormyTeal),
              child: ClipOval(
                child: photo != null && photo.isNotEmpty
                    ? Image.network(photo, fit: BoxFit.cover, errorBuilder: (c, e, s) => Center(child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800))))
                    : Center(child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                  if (tag != null && tag.isNotEmpty) Text('@$tag', style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: isFriend
                  ? Text('Ya son amigos', key: const ValueKey('f'), style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, fontWeight: FontWeight.w600))
                  : requested
                      ? Row(
                          key: const ValueKey('r'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 18, color: OhtliColors.accentText),
                            const SizedBox(width: 4),
                            Text('Enviada', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.accentText, fontWeight: FontWeight.w700)),
                          ],
                        )
                      : OhtliSecondaryButton(key: const ValueKey('a'), compact: true, label: 'Añadir', icon: Icons.person_add_alt_1_rounded, onPressed: () => _addFriend(doc)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // Paso: privacidad (perfil público, usertag, teléfono)
  // ==========================================================

  static String _suggestTag(String displayName) {
    final base = _norm(displayName).replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).join('.');
    return base.length >= 3 ? (base.length > 20 ? base.substring(0, 20) : base) : '';
  }

  void _checkTag(String raw, {bool immediate = false}) {
    _tagDebounce?.cancel();
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _tagStatus = null);
      return;
    }
    final tag = ProfileDirectory.normalizeTag(text);
    if (tag == null) {
      setState(() => _tagStatus = 'invalid');
      return;
    }
    final problem = ProfileDirectory.tagProblem(tag);
    if (problem != null && tag != _currentTag) {
      setState(() => _tagStatus = problem);
      return;
    }
    if (tag == _currentTag) {
      setState(() => _tagStatus = 'ok');
      return;
    }
    setState(() => _tagStatus = 'checking');
    _tagDebounce = Timer(Duration(milliseconds: immediate ? 0 : 450), () async {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) return;
      bool free;
      try {
        free = await ProfileDirectory.isTagAvailable(tag, me.uid);
      } catch (_) {
        free = true; // Sin conexión: se vuelve a comprobar al guardar.
      }
      if (!mounted || ProfileDirectory.normalizeTag(_tagController.text) != tag) return;
      setState(() => _tagStatus = free ? 'ok' : 'taken');
    });
  }

  Future<void> _savePrivacy(String uid) async {
    if (widget.sandbox) return;
    try {
      await UserPrivateData.save(uid, {
        'privacy_public': _profilePublic,
        'contact_discoverable': _contactDiscoverable,
        'privacy_notifications': _notificationsOn,
      });
    } catch (e) {
      debugPrint('[onboarding] privacidad: $e');
    }
    final tag = ProfileDirectory.normalizeTag(_tagController.text);
    if (tag != null && tag != _currentTag) {
      try {
        await ProfileDirectory.claimTag(uid, tag);
      } catch (e) {
        debugPrint('[onboarding] usertag: $e');
      }
    }
  }

  Widget _switchCard({required IconData icon, required String title, required String body, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: value ? OhtliColors.accentText.withValues(alpha: 0.45) : OhtliColors.cardBorder),
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: OhtliColors.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                  const SizedBox(height: 3),
                  Text(body, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4)),
                ],
              ),
            ),
            Switch(value: value, onChanged: (v) => setState(() => onChanged(v)), activeThumbColor: Colors.white, activeTrackColor: OhtliColors.stormyTeal),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await pickFile(accept: 'image/*');
    if (picked == null || picked.bytes.isEmpty || !mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OhtliImageCropperDialog(
        imageBytes: picked.bytes,
        onCropped: (base64) async {
          setState(() => _photoUploading = true);
          try {
            final url = await ProfilePhotoService.upload(base64);
            if (mounted) setState(() => _photoUrl = url);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo subir la foto. Intenta de nuevo.'))),
              );
            }
          } finally {
            if (mounted) setState(() => _photoUploading = false);
          }
        },
      ),
    );
  }

  String _savedName = '';

  /// Al escribir el nombre, si aún no tiene usertag y no ha tocado la sugerencia,
  /// la sugerencia sigue al nombre.
  void _onNameChanged() {
    final untouched = _tagController.text.isEmpty || _tagController.text == _suggestTag(_lastNameForTag);
    final suggestion = _suggestTag(_typedName);
    if (_currentTag == null && untouched && suggestion != _tagController.text) {
      _tagController.text = suggestion;
      _checkTag(suggestion);
    }
    _lastNameForTag = _typedName;
    setState(() {});
  }

  /// Guarda el nombre corregido (perfil, cuenta y perfil público). Si aún no tiene
  /// usertag y no tocó la sugerencia, la vuelve a sugerir con el nombre nuevo.
  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = _typedName;
    if (widget.sandbox || user == null || name.isEmpty) return;
    final previous = _savedName.isNotEmpty ? _savedName : _registeredName;
    if (name == previous) return;
    _savedName = name;
    try {
      await user.updateDisplayName(name);
      await UserPrivateData.save(user.uid, {'displayName': name, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('[onboarding] no se pudo guardar el nombre: $e');
    }
  }

  Widget _buildProfileStep(double width) {
    InputDecoration deco(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
          prefixIcon: Icon(icon, color: OhtliColors.accentText),
          filled: true,
          fillColor: OhtliColors.innerCardBg,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6)),
        );
    final first = TextField(
      controller: _firstNameController,
      onChanged: (_) => _onNameChanged(),
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.givenName],
      style: GoogleFonts.inter(color: OhtliColors.onyx, fontWeight: FontWeight.w600),
      decoration: deco("Nombre(s)", Icons.person_outline_rounded),
    );
    final last = TextField(
      controller: _lastNameController,
      onChanged: (_) => _onNameChanged(),
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.familyName],
      style: GoogleFonts.inter(color: OhtliColors.onyx, fontWeight: FontWeight.w600),
      decoration: deco("Apellidos", Icons.badge_outlined),
    );
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Tus datos",
          title: "Así te verán y te encontrarán",
          description: ProfilePhotoService.signedInWithGoogle
              ? "Tomamos tu nombre y tu foto de Google. Si algo no está bien, corrígelo aquí."
              : "Revisa cómo quedó tu nombre al registrarte y agrega una foto para que te reconozcan.",
        ),
        const SizedBox(height: 20),
        if (!widget.sandbox) ...[
          _buildProfilePhotoCard(),
          const SizedBox(height: 20),
        ],
        _buildGroupLabel("Tu nombre"),
        const SizedBox(height: 10),
        if (width < 520) ...[
          first,
          const SizedBox(height: 10),
          last,
        ] else
          Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 10),
              Expanded(child: last),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          "Así aparece en tu perfil, en los planes que compartes y cuando alguien te busca.",
          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, height: 1.4),
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.mail_outline_rounded, size: 16, color: OhtliColors.subtleText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Tu correo: $email",
                  style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _buildTagField(),
        const SizedBox(height: 20),
        _buildPhoneSection(),
      ],
    );
  }

  /// Foto de perfil: si entró con Google ya se ve la suya y la puede cambiar; si no, se la pide.
  Widget _buildProfilePhotoCard() {
    final google = ProfilePhotoService.signedInWithGoogle;
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    final name = _typedName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
                backgroundImage: hasPhoto ? NetworkImage(_photoUrl!) : null,
                child: hasPhoto
                    ? null
                    : Text(initial, style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
              ),
              if (_photoUploading)
                const SizedBox(width: 68, height: 68, child: CircularProgressIndicator(strokeWidth: 2.5, color: OhtliColors.stormyTeal)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasPhoto ? 'Tu foto' : 'Agrega tu foto',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 2),
                Text(
                  google && hasPhoto
                      ? 'Es la de tu cuenta de Google. Puedes cambiarla.'
                      : (hasPhoto ? 'Así te verán tus amigos.' : 'Para que tus amigos te reconozcan al invitarte a un plan.'),
                  style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, height: 1.35),
                ),
                const SizedBox(height: 10),
                OhtliSecondaryButton(
                  label: hasPhoto ? 'Cambiar foto' : 'Subir foto',
                  icon: Icons.photo_camera_outlined,
                  onPressed: _photoUploading ? null : _pickProfilePhoto,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Usertag (obligatorio) con su estado: libre, ocupado, no permitido…
  Widget _buildTagField() {
    final tagHelp = switch (_tagStatus) {
      'checking' => ('Revisando…', OhtliColors.subtleText, Icons.hourglass_top_rounded),
      'ok' => (ProfileDirectory.normalizeTag(_tagController.text) == _currentTag ? 'Es tu usertag' : '¡Está libre!', OhtliColors.accentText, Icons.check_circle_rounded),
      'taken' => ('Ya lo tiene alguien más. Prueba otro.', OhtliColors.warningText, Icons.cancel_rounded),
      'invalid' => ('De 3 a 20: letras, números, punto o guion bajo.', OhtliColors.warningText, Icons.info_outline_rounded),
      'reserved' => ('Ese usertag está reservado. Prueba otro.', OhtliColors.warningText, Icons.block_rounded),
      'prohibited' => ('Ese usertag no está permitido. Prueba otro.', OhtliColors.warningText, Icons.block_rounded),
      _ => ('Es tu nombre único en Ohtli: así te encuentran y te etiquetan.', OhtliColors.subtleText, Icons.alternate_email_rounded),
    };
    InputDecoration deco(String hint, IconData icon, {String? prefix}) => InputDecoration(
          hintText: hint,
          prefixText: prefix,
          prefixIcon: Icon(icon, color: OhtliColors.accentText),
          filled: true,
          fillColor: OhtliColors.innerCardBg,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.cardBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel("Tu usertag"),
        const SizedBox(height: 10),
        Semantics(
          label: 'Usertag',
          textField: true,
          child: TextField(
            controller: _tagController,
            onChanged: _checkTag,
            autocorrect: false,
            style: GoogleFonts.inter(color: OhtliColors.onyx, fontWeight: FontWeight.w600),
            decoration: deco("tu.nombre", Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(tagHelp.$3, size: 15, color: tagHelp.$2),
              const SizedBox(width: 6),
              Expanded(child: Text(tagHelp.$1, style: GoogleFonts.inter(fontSize: 12.5, color: tagHelp.$2, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ],
    );
  }

  /// Teléfono (opcional) con verificación por SMS y, ya verificado, la de dos pasos.
  Widget _buildPhoneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel("Tu teléfono"),
        const SizedBox(height: 10),
        PhoneVerificationField(sandbox: widget.sandbox, onVerified: (_) => setState(() {})),
        // Con el teléfono verificado se puede activar la verificación en dos pasos.
        if ((FirebaseAuth.instance.currentUser?.phoneNumber ?? '').isNotEmpty && !widget.sandbox) ...[
          const SizedBox(height: 12),
          const TwoFactorCard(),
        ],
        const SizedBox(height: 6),
        Text("Opcional. Te mandamos un código por SMS para confirmar que es tuyo. Con él podrás activar la verificación en dos pasos y, si tu perfil es público, que alguien que ya tiene tu número te encuentre. Nunca lo mostramos.",
            style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText, height: 1.4)),
      ],
    );
  }

  Widget _buildPrivacyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Privacidad",
          title: "Tú decides quién te ve",
          description: "Puedes cambiar todo esto después en Cuenta → Privacidad.",
        ),
        const SizedBox(height: 20),
        _StaggerIn(
          index: 0,
          child: _switchCard(
            icon: Icons.public_rounded,
            title: "Perfil público",
            body: _profilePublic
                ? "Cualquiera puede ver tu perfil, tus viajes públicos y encontrarte."
                : "Solo tus amigos ven tus viajes y tus amigos. Nadie te encuentra al buscar.",
            value: _profilePublic,
            onChanged: (v) => _profilePublic = v,
          ),
        ),
        if (_profilePublic)
          _StaggerIn(
            index: 1,
            child: _switchCard(
              icon: Icons.person_search_rounded,
              title: "Que me encuentren por correo o teléfono",
              body: "Quien escriba tu correo o tu teléfono verificado completos te verá en Amigos. No se muestran en tu perfil.",
              value: _contactDiscoverable,
              onChanged: (v) => _contactDiscoverable = v,
            ),
          ),
        _StaggerIn(
          index: 2,
          child: _switchCard(
            icon: Icons.notifications_active_outlined,
            title: "Avisos",
            body: "Te avisamos de solicitudes, comentarios y cuando tus rutas estén listas.",
            value: _notificationsOn,
            onChanged: (v) => _notificationsOn = v,
          ),
        ),
      ],
    );
  }
}

/// Lugar del catálogo con foto, para elegir los primeros lugares.
class _SeedPlaceTile extends StatelessWidget {
  const _SeedPlaceTile({required this.poi, required this.selected, required this.onTap, required this.onView});

  final Poi poi;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: poi.name,
      child: Material(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? OhtliColors.accentText : OhtliColors.cardBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
                      LayoutBuilder(
                        builder: (context, c) => Image.network(
                          CdmxPhotos.sized(poi.imageUrl, c.maxWidth, MediaQuery.devicePixelRatioOf(context)),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? OhtliColors.stormyTeal : Colors.black.withValues(alpha: 0.45),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(selected ? Icons.check_rounded : Icons.add_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                      // Ver el detalle sin marcarlo
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Semantics(
                          button: true,
                          label: 'Ver ${poi.name}',
                          excludeSemantics: true,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: const StadiumBorder(),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: onView,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.visibility_outlined, size: 14, color: Colors.white),
                                    const SizedBox(width: 5),
                                    Text('Ver', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poi.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      Text(
                        poi.categoryDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mosaico seleccionable (selección múltiple) con icono, etiqueta y check animado.
class _SelectableTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _SelectableTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_SelectableTile> createState() => _SelectableTileState();
}

class _SelectableTileState extends State<_SelectableTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover && !selected ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 108,
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.10) : OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? accent : (_hover ? accent.withValues(alpha: 0.35) : OhtliColors.cardBorder),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: accent.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 6))]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected ? accent : accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(widget.icon, size: 19, color: selected ? Colors.white : accent),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: selected
                          ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), size: 20, color: accent)
                          : Icon(Icons.circle_outlined,
                              key: const ValueKey('off'), size: 20, color: OhtliColors.subtleText.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilla de selección única.
class _ChoicePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? OhtliColors.stormyTeal : OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
            boxShadow: selected
                ? [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: selected ? Colors.white : OhtliColors.stormyTeal),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : OhtliColors.onyx,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrada escalonada: aparece desde abajo con un pequeño retraso según su posición.
/// Respeta «reducir movimiento» del sistema.
class _StaggerIn extends StatelessWidget {
  final int index;
  final Widget child;
  const _StaggerIn({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final delay = (index.clamp(0, 12)) * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + delay),
      curve: Interval(delay / (380 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c)),
      child: child,
    );
  }
}

/// Tarjeta de opción grande (p. ej. tamaño de letra) con borde al seleccionarse.
class _OptionCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String semanticsLabel;
  const _OptionCard({required this.selected, required this.onTap, required this.child, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 116,
            height: 104,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? OhtliColors.stormyTeal.withValues(alpha: 0.10) : OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? OhtliColors.stormyTeal : OhtliColors.cardBorder, width: selected ? 2 : 1),
              boxShadow: selected ? [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))] : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../theme/colors.dart';
import '../../models/poi_model.dart';
import '../../models/trip_model.dart';
import '../../widgets/poi_card.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../../widgets/trip_planner_dialog.dart';
import '../trips/trip_editor_page.dart';

class PlacesPage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;
  final VoidCallback? onLoginClick;

  const PlacesPage({
    super.key,
    this.onBack,
    this.showBackButton = false,
    this.onLoginClick,
  });

  @override
  State<PlacesPage> createState() => _PlacesPageState();

  /// Inicia la descarga del catálogo en cuanto arranca la app (también "despierta"
  /// al servidor si estaba inactivo), para que la sección Lugares abra con datos listos.
  static void prefetch() {
    _PlacesPageState._loadCatalog().catchError((_) => <Poi>[]);
  }
}

class _PlacesPageState extends State<PlacesPage> with SingleTickerProviderStateMixin {
  static List<Poi> _globalPoisCache = [];
  static Future<List<Poi>>? _inflightCatalog;
  static const String _apiUrl = String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');

  // Una sola descarga compartida del catálogo (precarga + pantalla), sin duplicar peticiones.
  // El tiempo de espera cubre el arranque en frío del servidor (puede tardar ~1 min).
  static Future<List<Poi>> _loadCatalog({bool forceRefresh = false}) {
    if (!forceRefresh && _inflightCatalog != null) return _inflightCatalog!;
    final future = () async {
      final uri = Uri.parse('$_apiUrl/v1/pois${forceRefresh ? "?refresh=true" : ""}');
      final response = await http.get(uri).timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['pois'] is! List) {
        throw Exception('Respuesta inesperada del catálogo');
      }
      final rawList = decoded['pois'] as List;
      final list = rawList
          .map((item) => Poi.fromMap(Map<String, dynamic>.from(item as Map)))
          .where((p) => p.isValidCulturalPlace)
          .toList();
      if (list.isEmpty) throw Exception('Catálogo vacío');
      _globalPoisCache = list;
      if (kIsWeb) {
        try {
          html.window.localStorage['ohtli_cached_pois_v2'] = jsonEncode(rawList);
        } catch (_) {}
      }
      return list;
    }();
    _inflightCatalog = future;
    // Si falla, permite reintentar más tarde
    future.catchError((_) {
      if (identical(_inflightCatalog, future)) _inflightCatalog = null;
      return <Poi>[];
    });
    return future;
  }

  bool _isSlowLoad = false;
  Timer? _slowLoadTimer;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _paraTiScrollController = ScrollController();
  final ScrollController _descubreScrollController = ScrollController();
  final ScrollController _misLugaresScrollController = ScrollController();
  final ScrollController _revisitaScrollController = ScrollController();

  AnimationController? _shimmerController;

  List<String> _savedPoiIds = [];
  List<String> _viewedPoiIds = [];
  List<double> _userTasteVector = [];

  bool _isLoadingPois = true;
  String? _poisError;
  List<Poi> _allPois = [];
  String _searchQuery = '';

  int? _selectedPriceFilter;
  String? _selectedCategoryFilter;

  static const Map<String, IconData> _categoryIcons = {
    'all': Icons.apps_rounded,
    'restaurant': Icons.restaurant_rounded,
    'cafe': Icons.local_cafe_rounded,
    'fast_food': Icons.lunch_dining_rounded,
    'bakery': Icons.bakery_dining_rounded,
    'museum_art': Icons.museum_rounded,
    'bar_pub': Icons.local_bar_rounded,
    'books_shop': Icons.menu_book_rounded,
    'park': Icons.park_rounded,
    'culture': Icons.theater_comedy_rounded,
    'attraction': Icons.attractions_rounded,
  };

  static const List<Map<String, String>> _categoryFilters = [
    {'id': 'all', 'label': 'Todos', 'emoji': '✨'},
    {'id': 'restaurant', 'label': 'Restaurantes', 'emoji': '🍽️'},
    {'id': 'cafe', 'label': 'Cafeterías', 'emoji': '☕'},
    {'id': 'fast_food', 'label': 'Comida Rápida', 'emoji': '🍔'},
    {'id': 'bakery', 'label': 'Panaderías', 'emoji': '🥐'},
    {'id': 'museum_art', 'label': 'Museos y Arte', 'emoji': '🏛️'},
    {'id': 'bar_pub', 'label': 'Bares y Cantinas', 'emoji': '🍸'},
    {'id': 'books_shop', 'label': 'Librerías y Tiendas', 'emoji': '📚'},
    {'id': 'park', 'label': 'Parques y Miradores', 'emoji': '🌳'},
    {'id': 'culture', 'label': 'Teatro y Cultura', 'emoji': '🎭'},
    {'id': 'attraction', 'label': 'Atracciones', 'emoji': '🎡'},
  ];

  bool _matchesPrice(Poi poi, int priceLevel) {
    if (priceLevel == 1) {
      return poi.priceLevel <= 1;
    }
    return poi.priceLevel == priceLevel;
  }

  bool _matchesCategory(Poi poi, String categoryKey) {
    if (categoryKey == 'all') return true;
    final cat = poi.category.toLowerCase().trim();
    switch (categoryKey) {
      case 'restaurant':
        return cat == 'restaurant';
      case 'cafe':
        return cat == 'cafe' || cat == 'coffee' || cat == 'internet_cafe';
      case 'fast_food':
        return cat == 'fast_food';
      case 'bakery':
        return cat == 'bakery' || cat == 'pastry' || cat == 'ice_cream';
      case 'museum_art':
        return cat == 'museum' || cat == 'artwork' || cat == 'gallery' || cat == 'arts_centre';
      case 'bar_pub':
        return cat == 'bar' || cat == 'pub' || cat == 'nightclub';
      case 'books_shop':
        return cat == 'books' || cat == 'book_store' || cat == 'department_store' || cat == 'marketplace' || cat == 'market';
      case 'park':
        return cat == 'park' || cat == 'viewpoint' || cat == 'zoo';
      case 'culture':
        return cat == 'theatre' || cat == 'theater' || cat == 'cinema' || cat == 'library' || cat == 'community_centre' || cat == 'cultural_centre';
      case 'attraction':
        return cat == 'attraction' || cat == 'tourist_attraction' || cat == 'theme_park';
      default:
        return cat == categoryKey.toLowerCase();
    }
  }

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _loadSavedPlaces();
    _loadViewedPlaces();
    _loadUserTasteVector();

    // 1. In-memory cache: instantáneo (0ms) al regresar de pestañas o vistas
    if (_globalPoisCache.isNotEmpty) {
      _allPois = List<Poi>.from(_globalPoisCache);
      _isLoadingPois = false;
    } else {
      // 2. LocalStorage cache: instantáneo (0ms) al recargar página
      _loadCachedPoisFromLocalStorage();
    }

    // 3. Stale-While-Revalidate: refresco silencioso en segundo plano
    _fetchPois();

    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
        });
      }
    });
  }

  void _loadCachedPoisFromLocalStorage() {
    if (kIsWeb) {
      try {
        final cached = html.window.localStorage['ohtli_cached_pois_v2'];
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached);
          if (decoded is List) {
            final list = decoded
                .map((item) => Poi.fromMap(Map<String, dynamic>.from(item as Map)))
                .where((p) => p.isValidCulturalPlace)
                .toList();
            if (list.isNotEmpty) {
              _allPois = list;
              _globalPoisCache = list;
              _isLoadingPois = false;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading cached POIs from localStorage: $e');
      }
    }
  }

  @override
  void dispose() {
    _shimmerController?.dispose();
    _slowLoadTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _paraTiScrollController.dispose();
    _descubreScrollController.dispose();
    _misLugaresScrollController.dispose();
    _revisitaScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPois({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (_allPois.isEmpty) {
      setState(() {
        _isLoadingPois = true;
        _poisError = null;
        _isSlowLoad = false;
      });
      // Si tarda, avisa que el servidor está arrancando en lugar de dejar solo el esqueleto
      _slowLoadTimer?.cancel();
      _slowLoadTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _allPois.isEmpty) setState(() => _isSlowLoad = true);
      });
    }

    try {
      final list = await _loadCatalog(forceRefresh: forceRefresh);
      _slowLoadTimer?.cancel();
      if (mounted) {
        setState(() {
          _allPois = list;
          _isLoadingPois = false;
          _isSlowLoad = false;
        });
      }
      return;
    } catch (e) {
      debugPrint('Error fetching POIs from Yollotl Engine API: $e');
    }
    _slowLoadTimer?.cancel();

    // Con datos en caché no hace falta el respaldo: se conservan los actuales
    if (_allPois.isNotEmpty) {
      if (mounted) setState(() => _isLoadingPois = false);
      return;
    }

    // Respaldo acotado a Firestore (cada documento incluye su vector de 768 dimensiones,
    // así que nunca se descarga la colección completa desde el navegador)
    try {
      final snapshot = await FirebaseFirestore.instance.collection('pois').limit(250).get();
      final list = snapshot.docs
          .map((d) => Poi.fromFirestore(d))
          .where((p) => p.isValidCulturalPlace)
          .toList();

      if (mounted) {
        setState(() {
          _allPois = list;
          _isLoadingPois = false;
          _isSlowLoad = false;
          if (list.isEmpty) _poisError = 'No se pudo cargar el catálogo de lugares.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPois = false;
          _isSlowLoad = false;
          if (_allPois.isEmpty) {
            _poisError = e.toString();
          }
        });
      }
    }
  }

  void _loadSavedPlaces() {
    if (kIsWeb) {
      try {
        final saved = html.window.localStorage['ohtli_saved_pois'];
        if (saved != null && saved.isNotEmpty) {
          _savedPoiIds = saved.split(',').where((id) => id.trim().isNotEmpty).toList();
        }
      } catch (_) {}
    }
  }

  void _toggleSavePoi(String poiId) {
    if (poiId.isEmpty) return;
    setState(() {
      if (_savedPoiIds.contains(poiId)) {
        _savedPoiIds.remove(poiId);
      } else {
        _savedPoiIds.insert(0, poiId);
      }
    });

    if (kIsWeb) {
      try {
        html.window.localStorage['ohtli_saved_pois'] = _savedPoiIds.join(',');
      } catch (_) {}
    }
  }

  void _loadViewedPlaces() {
    if (kIsWeb) {
      try {
        final saved = html.window.localStorage['ohtli_viewed_pois'];
        if (saved != null && saved.isNotEmpty) {
          _viewedPoiIds = saved.split(',').where((id) => id.trim().isNotEmpty).toList();
        }
      } catch (_) {}
    }
  }

  void _recordPlaceViewed(String poiId) {
    if (poiId.isEmpty) return;
    setState(() {
      _viewedPoiIds.remove(poiId);
      _viewedPoiIds.insert(0, poiId);
      if (_viewedPoiIds.length > 20) {
        _viewedPoiIds = _viewedPoiIds.sublist(0, 20);
      }
    });

    if (kIsWeb) {
      try {
        html.window.localStorage['ohtli_viewed_pois'] = _viewedPoiIds.join(',');
      } catch (_) {}
    }
  }

  Future<void> _loadUserTasteVector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final rawVec = data['taste_vector'];
          if (rawVec is List && rawVec.isNotEmpty) {
            _userTasteVector = rawVec.map((e) => (e as num).toDouble()).toList();
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {});
    }
  }

  double _computeCosineSimilarity(List<double> vecA, List<double> vecB) {
    if (vecA.isEmpty || vecB.isEmpty || vecA.length != vecB.length) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vecA.length; i++) {
      dot += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  int _calculateAffinity(Poi poi, int fallbackIndex) {
    if (_userTasteVector.isNotEmpty && poi.embeddingVector.isNotEmpty && _userTasteVector.length == poi.embeddingVector.length) {
      final sim = _computeCosineSimilarity(_userTasteVector, poi.embeddingVector);
      return (sim * 100).clamp(70.0, 99.0).toInt();
    }
    const fallbackScores = [98, 97, 96, 95, 94, 93, 92, 91, 90, 89];
    return fallbackScores[fallbackIndex % fallbackScores.length];
  }

  void _onPoiTapped(Poi poi) {
    _recordPlaceViewed(poi.poiId);
    PoiDetailDialog.show(
      context,
      poi,
      isSaved: _savedPoiIds.contains(poi.poiId),
      onSaveToggle: (saved) {
        setState(() {
          if (saved) {
            if (!_savedPoiIds.contains(poi.poiId)) _savedPoiIds.insert(0, poi.poiId);
          } else {
            _savedPoiIds.remove(poi.poiId);
          }
        });
      },
      onCreateRoute: () => _createRouteFromPlace(poi),
    );
  }

  void _createRouteFromPlace(Poi poi) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Inicia sesión para crear una ruta desde ${poi.name}.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: OhtliColors.stormyTeal,
          behavior: SnackBarBehavior.floating,
          action: widget.onLoginClick != null
              ? SnackBarAction(
                  label: 'Iniciar sesión',
                  textColor: OhtliColors.cempasuchil,
                  onPressed: widget.onLoginClick!,
                )
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    TripPlannerDialog.show(
      context,
      initialOriginPoi: poi,
      onManualPlanSelected: () => _createManualRouteFromPlace(poi),
    );
  }

  Future<void> _createManualRouteFromPlace(Poi poi) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final tripId = const Uuid().v4();
      final now = DateTime.now();

      final initialPlace = PlaceSection(
        id: 'sec_${now.millisecondsSinceEpoch}_0',
        title: poi.name,
        description: poi.cleanNarrative,
        rating: 5,
        mainPhotoUrl: poi.imageUrl,
        secondaryPhotoUrls: [],
        cost: poi.priceMxnAvg ?? (poi.priceLevel * 60.0),
        currency: 'MXN',
      );

      final newTrip = Trip(
        id: tripId,
        userId: user.uid,
        title: 'Ruta desde ${poi.name}',
        description: 'Itinerario cultural comenzando en ${poi.name}, ${poi.coloniaAlcaldiaDisplay}.',
        coverUrl: poi.imageUrl,
        status: 'draft',
        visibility: 'private',
        createdAt: now,
        updatedAt: now,
      );

      final content = TripContent(sections: [initialPlace]);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('trips')
          .doc(tripId)
          .set(newTrip.toMap());

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('trips')
          .doc(tripId)
          .collection('details')
          .doc('content')
          .set(content.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ruta creada. Abriendo editor...',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: OhtliColors.cempasuchil,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripEditorPage(trip: newTrip),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear la ruta: $e'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _selectedPriceFilter = null;
      _selectedCategoryFilter = null;
    });
  }

  void _scrollSection(ScrollController controller, double offset) {
    controller.animateTo(
      (controller.offset + offset).clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;

    if (_isLoadingPois && _allPois.isEmpty) {
      return _buildSkeletonView(isMobile, screenSize);
    }

    if (_poisError != null && _allPois.isEmpty) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: SafeArea(
          child: _buildErrorState(_poisError!),
        ),
      );
    }

    final allPois = _allPois;
    final isFiltering = _searchQuery.isNotEmpty || _selectedPriceFilter != null || _selectedCategoryFilter != null;

    // Filter results across text, price, and category
    final searchResults = isFiltering
        ? allPois.where((poi) {
            // Price filter
            if (_selectedPriceFilter != null && !_matchesPrice(poi, _selectedPriceFilter!)) {
              return false;
            }
            // Category filter
            if (_selectedCategoryFilter != null && !_matchesCategory(poi, _selectedCategoryFilter!)) {
              return false;
            }
            // Text search
            if (_searchQuery.isNotEmpty) {
              return poi.name.toLowerCase().contains(_searchQuery) ||
                  poi.poiId.toLowerCase().contains(_searchQuery) ||
                  poi.categoryDisplay.toLowerCase().contains(_searchQuery) ||
                  poi.description.toLowerCase().contains(_searchQuery) ||
                  poi.cleanNarrative.toLowerCase().contains(_searchQuery) ||
                  poi.coloniaAlcaldiaDisplay.toLowerCase().contains(_searchQuery) ||
                  poi.vibeTags.any((v) => v.toLowerCase().contains(_searchQuery));
            }
            return true;
          }).toList()
        : <Poi>[];

    // 1. "Para ti": Exactly 5 cards with highest affinity, double width (2x)
    final paraTiPois = List<Poi>.from(allPois);
    paraTiPois.sort((a, b) {
      final scoreA = _calculateAffinity(a, 0);
      final scoreB = _calculateAffinity(b, 1);
      return scoreB.compareTo(scoreA);
    });
    final paraTiCards = paraTiPois.take(5).toList();

    // 2. "Descubre nuevos lugares": Todos los lugares indexados en la CDMX para scroll horizontal continuo
    final descubrePois = List<Poi>.from(allPois);

    // 3. "Mis lugares": Lugares que el usuario guardó / marcó como favoritos
    final misLugaresPois = allPois.where((p) => _savedPoiIds.contains(p.poiId)).toList();
    misLugaresPois.sort((a, b) {
      final indexA = _savedPoiIds.indexOf(a.poiId);
      final indexB = _savedPoiIds.indexOf(b.poiId);
      return indexA.compareTo(indexB);
    });

    // 4. "Revisita tus lugares": Historial de lugares que ha consultado
    final revisitaPois = allPois.where((p) => _viewedPoiIds.contains(p.poiId)).toList();
    revisitaPois.sort((a, b) {
      final indexA = _viewedPoiIds.indexOf(a.poiId);
      final indexB = _viewedPoiIds.indexOf(b.poiId);
      return indexA.compareTo(indexB);
    });

    // Card sizing
    final standardWidth = 280.0;
    final doubleWidth = isMobile ? math.min(560.0, screenSize.width - 48) : 560.0;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // Top Search Bar (Clean and direct)
            SliverToBoxAdapter(
              key: const ValueKey('places_top_bar'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 36,
                  isMobile ? 16 : 28,
                  isMobile ? 16 : 36,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showBackButton && widget.onBack != null) ...[
                      TextButton.icon(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Volver'),
                        style: TextButton.styleFrom(
                          foregroundColor: OhtliColors.stormyTeal,
                          padding: EdgeInsets.zero,
                          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (FirebaseAuth.instance.currentUser == null) ...[
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/logo.svg',
                            height: 24,
                            fit: BoxFit.contain,
                            colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                          ),
                          const Spacer(),
                          if (widget.onLoginClick != null)
                            ElevatedButton(
                              onPressed: widget.onLoginClick,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OhtliColors.stormyTeal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              child: const Text('Iniciar sesión'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Título de la sección
                    Text(
                      'Lugares',
                      style: GoogleFonts.outfit(
                        fontSize: isMobile ? 28 : 34,
                        fontWeight: FontWeight.w800,
                        color: OhtliColors.onyx,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Descubre ${allPois.length} rincones culturales de la Ciudad de México',
                      style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText),
                    ),
                    const SizedBox(height: 18),

                    // Search Bar
                    Container(
                      key: const ValueKey('places_search_box'),
                      decoration: BoxDecoration(
                        color: OhtliColors.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OhtliColors.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: TextField(
                        key: const ValueKey('places_search_field'),
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Buscar lugares, colonias, museos, cafés...',
                          hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.search_rounded, color: OhtliColors.stormyTeal, size: 22),
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchFocusNode.requestFocus();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        ),
                      ),
                    ),
                    _buildFilterBar(isMobile),
                  ],
                ),
              ),
            ),

            // If user is searching or filtering, display Filtered Results Grid
            if (isFiltering) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36, vertical: 8),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _searchQuery.isNotEmpty
                                        ? 'Resultados para "${_searchController.text}"'
                                        : 'Lugares encontrados',
                                  ),
                                  TextSpan(
                                    text: '  ${searchResults.length}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: OhtliColors.stormyTeal,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _clearAllFilters,
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: Text(isMobile ? 'Limpiar' : 'Limpiar y ver secciones'),
                            style: TextButton.styleFrom(
                              foregroundColor: OhtliColors.stormyTeal,
                              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (searchResults.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptySearchState(),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36, vertical: 16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isMobile
                              ? 1
                              : (screenSize.width < 1150 ? 2 : (screenSize.width < 1600 ? 3 : 4)),
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          mainAxisExtent: 440,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final poi = searchResults[index];
                            final isSaved = _savedPoiIds.contains(poi.poiId);
                            return PoiCard(
                              poi: poi,
                              height: 440,
                              isSaved: isSaved,
                              onToggleSave: () => _toggleSavePoi(poi.poiId),
                              onCreateRoute: () => _createRouteFromPlace(poi),
                              onTap: () => _onPoiTapped(poi),
                            );
                          },
                          childCount: searchResults.length,
                        ),
                      ),
                    ),
                ] else ...[
                  // ================= SECCIÓN 1: "PARA TI" =================
                  // Horizontal carousel limited to exactly 5 cards, 2x width
                  SliverToBoxAdapter(
                    child: _buildCleanSectionHeader(
                      title: 'Para ti',
                      isMobile: isMobile,
                      controller: _paraTiScrollController,
                      scrollStep: doubleWidth + 18,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: isMobile ? 480 : 540,
                      child: ListView.builder(
                        controller: _paraTiScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36),
                        itemCount: paraTiCards.length,
                        itemBuilder: (context, index) {
                          final poi = paraTiCards[index];
                          final isSaved = _savedPoiIds.contains(poi.poiId);
                          return Padding(
                            padding: const EdgeInsets.only(right: 18, top: 4, bottom: 16),
                            child: PoiCard(
                              poi: poi,
                              width: doubleWidth,
                              height: isMobile ? 460 : 520,
                              isDoubleWidth: true,
                              affinity: _calculateAffinity(poi, index),
                              isSaved: isSaved,
                              onToggleSave: () => _toggleSavePoi(poi.poiId),
                              onCreateRoute: () => _createRouteFromPlace(poi),
                              onTap: () => _onPoiTapped(poi),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ================= SECCIÓN 2: "DESCUBRE NUEVOS LUGARES" =================
                  // 8 cards in CDMX, 1x width
                  SliverToBoxAdapter(
                    child: _buildCleanSectionHeader(
                      title: 'Descubre nuevos lugares',
                      isMobile: isMobile,
                      controller: _descubreScrollController,
                      scrollStep: standardWidth + 18,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 440,
                      child: ListView.builder(
                        controller: _descubreScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36),
                        itemCount: descubrePois.length,
                        itemBuilder: (context, index) {
                          final poi = descubrePois[index];
                          final isSaved = _savedPoiIds.contains(poi.poiId);
                          return Padding(
                            padding: const EdgeInsets.only(right: 18, top: 4, bottom: 16),
                            child: PoiCard(
                              poi: poi,
                              width: standardWidth,
                              height: 420,
                              isSaved: isSaved,
                              onToggleSave: () => _toggleSavePoi(poi.poiId),
                              onCreateRoute: () => _createRouteFromPlace(poi),
                              onTap: () => _onPoiTapped(poi),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ================= SECCIÓN 3: "MIS LUGARES" (ANTES DEL HISTORIAL) =================
                  // Lugares guardados por el usuario
                  SliverToBoxAdapter(
                    child: _buildCleanSectionHeader(
                      title: 'Mis lugares',
                      count: misLugaresPois.length,
                      isMobile: isMobile,
                      controller: _misLugaresScrollController,
                      scrollStep: standardWidth + 18,
                      showArrows: misLugaresPois.isNotEmpty,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: misLugaresPois.isEmpty
                        ? Padding(
                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36, vertical: 8),
                            child: _buildEmptyMisLugaresBanner(),
                          )
                        : SizedBox(
                            height: 440,
                            child: ListView.builder(
                              controller: _misLugaresScrollController,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36),
                              itemCount: misLugaresPois.length,
                              itemBuilder: (context, index) {
                                final poi = misLugaresPois[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 18, top: 4, bottom: 16),
                                  child: PoiCard(
                                    poi: poi,
                                    width: standardWidth,
                                    height: 420,
                                    isSaved: true,
                                    onToggleSave: () => _toggleSavePoi(poi.poiId),
                                    onCreateRoute: () => _createRouteFromPlace(poi),
                                    onTap: () => _onPoiTapped(poi),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ================= SECCIÓN 4: "REVISITA TUS LUGARES" (HISTORIAL) =================
                  // Historial de lugares consultados
                  SliverToBoxAdapter(
                    child: _buildCleanSectionHeader(
                      title: 'Revisita tus lugares',
                      count: revisitaPois.length,
                      isMobile: isMobile,
                      controller: _revisitaScrollController,
                      scrollStep: standardWidth + 18,
                      showArrows: revisitaPois.isNotEmpty,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: revisitaPois.isEmpty
                        ? Padding(
                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36, vertical: 8),
                            child: _buildEmptyRevisitaBanner(),
                          )
                        : SizedBox(
                            height: 440,
                            child: ListView.builder(
                              controller: _revisitaScrollController,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36),
                              itemCount: revisitaPois.length,
                              itemBuilder: (context, index) {
                                final poi = revisitaPois[index];
                                final isSaved = _savedPoiIds.contains(poi.poiId);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 18, top: 4, bottom: 16),
                                  child: PoiCard(
                                    poi: poi,
                                    width: standardWidth,
                                    height: 420,
                                    isSaved: isSaved,
                                    onToggleSave: () => _toggleSavePoi(poi.poiId),
                                    onCreateRoute: () => _createRouteFromPlace(poi),
                                    onTap: () => _onPoiTapped(poi),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 60)),
                ],
              ],
            ),
          ),
        );
  }

  /// Clean section header without description and without icon
  Widget _buildCleanSectionHeader({
    required String title,
    required bool isMobile,
    required ScrollController controller,
    required double scrollStep,
    bool showArrows = true,
    int? count,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 36,
        14,
        isMobile ? 16 : 36,
        12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: isMobile ? 21 : 25,
                      fontWeight: FontWeight.w800,
                      color: OhtliColors.onyx,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: OhtliColors.stormyTeal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isMobile && showArrows)
            Row(
              children: [
                _buildShelfArrow(Icons.arrow_back_ios_new_rounded, 'Anterior', () => _scrollSection(controller, -scrollStep)),
                const SizedBox(width: 8),
                _buildShelfArrow(Icons.arrow_forward_ios_rounded, 'Siguiente', () => _scrollSection(controller, scrollStep)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildShelfArrow(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      color: OhtliColors.onyx,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: OhtliColors.cardBg,
        fixedSize: const Size(38, 38),
        shape: CircleBorder(side: BorderSide(color: OhtliColors.cardBorder)),
      ),
    );
  }

  Widget _buildEmptyShelf({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyMisLugaresBanner() {
    return _buildEmptyShelf(
      icon: Icons.bookmark_border_rounded,
      color: OhtliColors.cempasuchil,
      title: 'Aún no guardas lugares',
      message: 'Guarda tus rincones favoritos tocando el ícono de marcador en cualquier tarjeta o modal para tenerlos a mano.',
    );
  }

  Widget _buildEmptyRevisitaBanner() {
    return _buildEmptyShelf(
      icon: Icons.history_rounded,
      color: OhtliColors.stormyTeal,
      title: 'Tu historial está vacío',
      message: 'Los lugares que explores se guardarán aquí automáticamente para que puedas revisarlos cuando quieras.',
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded, size: 34, color: OhtliColors.stormyTeal),
            ),
            const SizedBox(height: 18),
            Text(
              'No encontramos resultados',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
            ),
            const SizedBox(height: 8),
            Text(
              'Intenta con otra palabra clave como cafetería, museo o una colonia, o quita algún filtro.',
              style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Limpiar búsqueda y filtros'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: OhtliColors.xoconostle),
            const SizedBox(height: 16),
            Text(
              'Error al cargar los lugares',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _fetchPois(forceRefresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    double borderRadius = 8,
  }) {
    if (_shimmerController == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _shimmerController!,
      builder: (context, child) {
        final v = _shimmerController!.value;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + (v * 3.0), -0.2),
              end: Alignment(0.5 + (v * 3.0), 0.2),
              colors: const [
                Color(0xFFE8EEF3),
                Color(0xFFF8FAFC),
                Color(0xFFE8EEF3),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCard(double width) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildShimmerBox(width: 80, height: 18, borderRadius: 12),
                      const Spacer(),
                      _buildShimmerBox(width: 24, height: 24, borderRadius: 12),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildShimmerBox(width: width * 0.7, height: 20, borderRadius: 6),
                  const SizedBox(height: 8),
                  _buildShimmerBox(width: width * 0.45, height: 14, borderRadius: 6),
                  const SizedBox(height: 14),
                  _buildShimmerBox(width: double.infinity, height: 12, borderRadius: 4),
                  const SizedBox(height: 6),
                  _buildShimmerBox(width: width * 0.8, height: 12, borderRadius: 4),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildShimmerBox(width: 50, height: 16, borderRadius: 6),
                      _buildShimmerBox(width: 90, height: 32, borderRadius: 8),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonView(bool isMobile, Size screenSize) {
    final standardWidth = 280.0;
    final doubleWidth = isMobile ? math.min(560.0, screenSize.width - 48) : 560.0;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 36,
              isMobile ? 16 : 28,
              isMobile ? 16 : 36,
              40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top placeholder / title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildShimmerBox(width: 140, height: 28, borderRadius: 8),
                    _buildShimmerBox(width: 100, height: 36, borderRadius: 20),
                  ],
                ),
                const SizedBox(height: 20),
                // Search bar shimmer placeholder
                _buildShimmerBox(
                  width: double.infinity,
                  height: 52,
                  borderRadius: 16,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: _isSlowLoad
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: OhtliColors.cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: OhtliColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: OhtliColors.stormyTeal),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Preparando el catálogo de lugares… La primera carga puede tardar unos segundos mientras el servidor arranca.',
                                    style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 36),

                // Section 1: "Para ti" skeleton
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildShimmerBox(width: 120, height: 24, borderRadius: 6),
                    Row(
                      children: [
                        _buildShimmerBox(width: 32, height: 32, borderRadius: 16),
                        const SizedBox(width: 8),
                        _buildShimmerBox(width: 32, height: 32, borderRadius: 16),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: isMobile ? 480 : 540,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 3,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 18, top: 4, bottom: 16),
                        child: _buildSkeletonCard(doubleWidth),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Section 2: "Descubre nuevos lugares" skeleton
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildShimmerBox(width: 220, height: 24, borderRadius: 6),
                    Row(
                      children: [
                        _buildShimmerBox(width: 32, height: 32, borderRadius: 16),
                        const SizedBox(width: 8),
                        _buildShimmerBox(width: 32, height: 32, borderRadius: 16),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 480,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 18, top: 4, bottom: 16),
                        child: _buildSkeletonCard(standardWidth),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isMobile) {
    final categoryRow = ShaderMask(
      // Desvanecido en los bordes para sugerir que la fila se desplaza
      shaderCallback: (rect) => const LinearGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.94, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          children: _categoryFilters.map((cat) {
            final id = cat['id']!;
            final isSelected = (_selectedCategoryFilter == null && id == 'all') || (_selectedCategoryFilter == id);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                label: cat['label']!,
                icon: _categoryIcons[id],
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    if (id == 'all' || _selectedCategoryFilter == id) {
                      _selectedCategoryFilter = null;
                    } else {
                      _selectedCategoryFilter = id;
                    }
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );

    final priceSelector = _buildPriceSelector();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                categoryRow,
                const SizedBox(height: 10),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: priceSelector),
              ],
            )
          : Row(
              children: [
                Expanded(child: categoryRow),
                const SizedBox(width: 12),
                priceSelector,
              ],
            ),
    );
  }

  // Selector de precio segmentado compacto
  Widget _buildPriceSelector() {
    final prices = [
      {'level': null, 'symbol': 'Todos', 'label': 'Cualquier precio'},
      {'level': 1, 'symbol': '\$', 'label': 'Económico'},
      {'level': 2, 'symbol': '\$\$', 'label': 'Moderado'},
      {'level': 3, 'symbol': '\$\$\$', 'label': 'Costoso'},
      {'level': 4, 'symbol': '\$\$\$\$', 'label': 'Exclusivo'},
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Icon(Icons.payments_outlined, size: 16, color: OhtliColors.subtleText),
          ),
          ...prices.map((p) {
            final level = p['level'] as int?;
            final isSelected = _selectedPriceFilter == level;
            return Tooltip(
              message: p['label'] as String,
              child: InkWell(
                onTap: () => setState(() {
                  _selectedPriceFilter = (level != null && _selectedPriceFilter == level) ? null : level;
                }),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? OhtliColors.stormyTeal : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    p['symbol'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    String? tooltip,
  }) {
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? OhtliColors.onyx : OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? OhtliColors.onyx : OhtliColors.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: isSelected ? OhtliColors.cloudDancer : OhtliColors.stormyTeal),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? OhtliColors.cloudDancer : OhtliColors.onyx,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: chip);
    }
    return chip;
  }
}

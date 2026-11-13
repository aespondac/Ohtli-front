// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
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
import '../../theme/cdmx_photos.dart';
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

  /// Catálogo compartido (misma descarga que usa Lugares) para otras vistas, como Explorar.
  static Future<List<Poi>> loadCatalog() {
    if (_PlacesPageState._globalPoisCache.isNotEmpty) {
      return Future.value(_PlacesPageState._globalPoisCache);
    }
    return _PlacesPageState._loadCatalog();
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
  final ScrollController _pageScrollController = ScrollController();

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
    _pageScrollController.dispose();
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

    // Medidas de tarjetas
    final hPad = _hPad(isMobile);
    const standardWidth = 268.0;
    const standardHeight = 372.0;
    final doubleWidth = isMobile ? math.min(520.0, screenSize.width - 48) : 560.0;
    final immersiveHeight = isMobile ? 470.0 : 520.0;
    final categoriesCount = allPois.map((p) => p.category).toSet().length;

    Widget shelf({
      required ScrollController controller,
      required List<Poi> pois,
      required double height,
      required Widget Function(Poi poi, int index) builder,
      double gap = 20,
    }) {
      return SizedBox(
        height: height,
        child: ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 22),
          itemCount: pois.length,
          separatorBuilder: (_, _) => SizedBox(width: gap),
          itemBuilder: (context, index) => builder(pois[index], index),
        ),
      );
    }

    Widget standardCard(Poi poi, {bool? saved}) => PoiCard(
          poi: poi,
          width: standardWidth,
          height: standardHeight - 28,
          variant: PoiCardVariant.standard,
          isSaved: saved ?? _savedPoiIds.contains(poi.poiId),
          onToggleSave: () => _toggleSavePoi(poi.poiId),
          onCreateRoute: () => _createRouteFromPlace(poi),
          onTap: () => _onPoiTapped(poi),
        );

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: CustomScrollView(
          controller: _pageScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              key: const ValueKey('places_top_bar'),
              child: _buildHero(
                isMobile: isMobile,
                placesCount: allPois.length,
                categoriesCount: categoriesCount,
                coverUrl: CdmxPhotos.covers.first,
              ),
            ),

            // Barra de filtros fija con efecto de vidrio
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyFilterDelegate(
                height: isMobile ? 112 : 72,
                builder: (context, overlaps) => _buildStickyFilters(isMobile, overlaps),
              ),
            ),

            if (isFiltering) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _searchQuery.isNotEmpty ? 'Resultados para "${_searchController.text}"' : 'Lugares encontrados',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 22 : 26,
                                fontWeight: FontWeight.w800,
                                color: OhtliColors.onyx,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${searchResults.length} ${searchResults.length == 1 ? 'lugar coincide' : 'lugares coinciden'} con tu búsqueda',
                              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _pillButton(
                        icon: Icons.close_rounded,
                        label: isMobile ? 'Limpiar' : 'Limpiar filtros',
                        onTap: _clearAllFilters,
                      ),
                    ],
                  ),
                ),
              ),
              if (searchResults.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptySearchState())
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 60),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: isMobile ? 520 : 320,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 30,
                      mainAxisExtent: isMobile ? 400 : standardHeight - 20,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final poi = searchResults[index];
                        return PoiCard(
                          poi: poi,
                          variant: PoiCardVariant.standard,
                          isSaved: _savedPoiIds.contains(poi.poiId),
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
              // ================= PARA TI =================
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  eyebrow: 'Recomendado',
                  title: 'Para ti',
                  subtitle: _userTasteVector.isNotEmpty
                      ? 'Elegidos según tus gustos y tu forma de viajar'
                      : 'Una selección de imperdibles para empezar',
                  icon: Icons.auto_awesome_rounded,
                  color: OhtliColors.stormyTeal,
                  isMobile: isMobile,
                  controller: _paraTiScrollController,
                  scrollStep: doubleWidth + 22,
                ),
              ),
              SliverToBoxAdapter(
                child: shelf(
                  controller: _paraTiScrollController,
                  pois: paraTiCards,
                  height: immersiveHeight + 34,
                  gap: 22,
                  builder: (poi, index) => PoiCard(
                    poi: poi,
                    width: doubleWidth,
                    height: immersiveHeight,
                    variant: PoiCardVariant.immersive,
                    affinity: _calculateAffinity(poi, index),
                    isSaved: _savedPoiIds.contains(poi.poiId),
                    onToggleSave: () => _toggleSavePoi(poi.poiId),
                    onCreateRoute: () => _createRouteFromPlace(poi),
                    onTap: () => _onPoiTapped(poi),
                  ),
                ),
              ),

              // ================= DESCUBRE =================
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  eyebrow: 'Explora',
                  title: 'Descubre nuevos lugares',
                  subtitle: 'Rincones de toda la ciudad que aún no conoces',
                  icon: Icons.explore_rounded,
                  color: OhtliColors.xoconostle,
                  isMobile: isMobile,
                  controller: _descubreScrollController,
                  scrollStep: (standardWidth + 20) * 2,
                ),
              ),
              SliverToBoxAdapter(
                child: shelf(
                  controller: _descubreScrollController,
                  pois: descubrePois,
                  height: standardHeight,
                  builder: (poi, _) => standardCard(poi),
                ),
              ),

              // ================= MIS LUGARES =================
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  eyebrow: 'Guardados',
                  title: 'Mis lugares',
                  subtitle: 'Tus favoritos, listos para tu próxima ruta',
                  icon: Icons.favorite_rounded,
                  color: OhtliColors.cempasuchil,
                  count: misLugaresPois.length,
                  isMobile: isMobile,
                  controller: _misLugaresScrollController,
                  scrollStep: (standardWidth + 20) * 2,
                  showArrows: misLugaresPois.isNotEmpty,
                ),
              ),
              SliverToBoxAdapter(
                child: misLugaresPois.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 12),
                        child: _buildEmptyMisLugaresBanner(),
                      )
                    : shelf(
                        controller: _misLugaresScrollController,
                        pois: misLugaresPois,
                        height: standardHeight,
                        builder: (poi, _) => standardCard(poi, saved: true),
                      ),
              ),

              // ================= REVISITA =================
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  eyebrow: 'Historial',
                  title: 'Revisita tus lugares',
                  subtitle: 'Lo último que exploraste',
                  icon: Icons.history_rounded,
                  color: const Color(0xFF3949AB),
                  count: revisitaPois.length,
                  isMobile: isMobile,
                  controller: _revisitaScrollController,
                  scrollStep: 680,
                  showArrows: revisitaPois.isNotEmpty,
                ),
              ),
              SliverToBoxAdapter(
                child: revisitaPois.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 12),
                        child: _buildEmptyRevisitaBanner(),
                      )
                    : shelf(
                        controller: _revisitaScrollController,
                        pois: revisitaPois,
                        height: 96 + 28,
                        gap: 14,
                        builder: (poi, _) => PoiCard(
                          poi: poi,
                          width: isMobile ? screenSize.width * 0.8 : 340,
                          height: 96,
                          variant: PoiCardVariant.compact,
                          onTap: () => _onPoiTapped(poi),
                        ),
                      ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 72)),
            ],
          ],
        ),
      ),
    );
  }

  double _hPad(bool isMobile) => isMobile ? 16 : 40;

  // ───────────────────────── Portada ─────────────────────────

  Widget _buildHero({
    required bool isMobile,
    required int placesCount,
    required int categoriesCount,
    required String coverUrl,
  }) {
    final hPad = _hPad(isMobile);
    final isGuest = FirebaseAuth.instance.currentUser == null;

    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 10 : hPad, isMobile ? 10 : 24, isMobile ? 10 : hPad, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isMobile ? 26 : 34),
        child: Stack(
          children: [
            // Fotografía de fondo
            Positioned.fill(
              child: Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            // Velo de color de marca para legibilidad
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF123338).withValues(alpha: 0.97),
                      const Color(0xFF1B4A51).withValues(alpha: 0.90),
                      OhtliColors.stormyTeal.withValues(alpha: 0.45),
                      OhtliColors.xoconostle.withValues(alpha: 0.30),
                    ],
                    stops: const [0.0, 0.42, 0.75, 1.0],
                  ),
                ),
              ),
            ),
            // Destellos decorativos
            Positioned(
              right: -80,
              top: -90,
              child: _glowOrb(260, OhtliColors.cempasuchil.withValues(alpha: 0.35)),
            ),
            Positioned(
              left: -60,
              bottom: -120,
              child: _glowOrb(240, Colors.white.withValues(alpha: 0.10)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 20 : 40, isMobile ? 18 : 28, isMobile ? 20 : 40, isMobile ? 22 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra superior
                  Row(
                    children: [
                      if (widget.showBackButton && widget.onBack != null)
                        _heroGlassButton(
                          icon: Icons.arrow_back_rounded,
                          label: 'Volver',
                          onTap: widget.onBack!,
                        )
                      else
                        SvgPicture.asset(
                          'assets/logo.svg',
                          height: 22,
                          fit: BoxFit.contain,
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        ),
                      const Spacer(),
                      if (isGuest && widget.onLoginClick != null)
                        ElevatedButton(
                          onPressed: widget.onLoginClick,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: OhtliColors.stormyTeal,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          child: const Text('Iniciar sesión'),
                        ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 26 : 40),
                  // Etiqueta superior
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(color: OhtliColors.cempasuchil, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'CIUDAD DE MÉXICO',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      'Descubre tu próximo\nlugar favorito',
                      style: GoogleFonts.outfit(
                        fontSize: isMobile ? 32 : 50,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.02,
                        letterSpacing: isMobile ? -0.8 : -1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      'Museos, cafés, cantinas y miradores curados por Ohtli para armar rutas a tu medida.',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 14 : 15.5,
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(height: isMobile ? 22 : 30),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: _buildSearchField(isMobile),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _heroStat(Icons.place_rounded, '$placesCount', 'lugares'),
                      _heroStat(Icons.category_rounded, '$categoriesCount', 'categorías'),
                      _heroStat(Icons.favorite_rounded, '${_savedPoiIds.length}', 'guardados'),
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

  Widget _glowOrb(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _heroGlassButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.22), width: 0.8)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: OhtliColors.cempasuchil),
        const SizedBox(width: 6),
        Text(value, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.75))),
      ],
    );
  }

  Widget _buildSearchField(bool isMobile) {
    return Container(
      key: const ValueKey('places_search_box'),
      height: isMobile ? 56 : 62,
      padding: const EdgeInsets.only(left: 6, right: 6),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 30, offset: const Offset(0, 14)),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search_rounded, color: OhtliColors.stormyTeal, size: 24),
          Expanded(
            child: TextField(
              key: const ValueKey('places_search_field'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: OhtliColors.stormyTeal,
              decoration: InputDecoration(
                hintText: isMobile ? 'Busca lugares o colonias' : 'Busca museos, cafés, colonias o un ambiente…',
                hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              tooltip: 'Borrar búsqueda',
              icon: Icon(Icons.close_rounded, size: 20, color: OhtliColors.subtleText),
              onPressed: () {
                _searchController.clear();
                _searchFocusNode.requestFocus();
              },
            ),
          if (!isMobile)
            ElevatedButton(
              onPressed: () => _searchFocusNode.requestFocus(),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              child: const Text('Buscar'),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── Barra de filtros fija ─────────────────────────

  Widget _buildStickyFilters(bool isMobile, bool overlaps) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: OhtliColors.cloudDancer.withValues(alpha: overlaps ? 0.82 : 1.0),
            border: Border(
              bottom: BorderSide(color: overlaps ? OhtliColors.cardBorder : Colors.transparent),
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: _hPad(isMobile)),
          alignment: Alignment.center,
          child: _buildFilterBar(isMobile, showSearchShortcut: overlaps),
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isMobile, {bool showSearchShortcut = false}) {
    final categoryRow = ShaderMask(
      // Desvanecido en los bordes para sugerir que la fila se desplaza
      shaderCallback: (rect) => const LinearGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.94, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 28),
        child: Row(
          children: [
            if (showSearchShortcut)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildFilterChip(
                  label: 'Buscar',
                  icon: Icons.search_rounded,
                  isSelected: false,
                  onTap: () {
                    _pageScrollController.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
                    Future.delayed(const Duration(milliseconds: 460), () {
                      if (mounted) _searchFocusNode.requestFocus();
                    });
                  },
                ),
              ),
            ..._categoryFilters.map((cat) {
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
            }),
          ],
        ),
      ),
    );

    final priceSelector = _buildPriceSelector();

    return isMobile
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
          );
  }

  // Selector de precio segmentado
  Widget _buildPriceSelector() {
    final prices = [
      {'level': null, 'symbol': 'Todo', 'label': 'Cualquier precio'},
      {'level': 1, 'symbol': '\$', 'label': 'Económico'},
      {'level': 2, 'symbol': '\$\$', 'label': 'Moderado'},
      {'level': 3, 'symbol': '\$\$\$', 'label': 'Costoso'},
      {'level': 4, 'symbol': '\$\$\$\$', 'label': 'Exclusivo'},
    ];
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: prices.map((p) {
          final level = p['level'] as int?;
          final isSelected = _selectedPriceFilter == level;
          return Tooltip(
            message: p['label'] as String,
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedPriceFilter = (level != null && _selectedPriceFilter == level) ? null : level;
              }),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? OhtliColors.onyx : Colors.transparent,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    p['symbol'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? OhtliColors.cloudDancer : OhtliColors.subtleText,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
            boxShadow: isSelected
                ? [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: isSelected ? Colors.white : OhtliColors.stormyTeal),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : OhtliColors.onyx,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: OhtliColors.cardBg,
      shape: StadiumBorder(side: BorderSide(color: OhtliColors.cardBorder)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: OhtliColors.onyx),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Encabezados de sección ─────────────────────────

  Widget _buildSectionHeader({
    required String eyebrow,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isMobile,
    required ScrollController controller,
    required double scrollStep,
    bool showArrows = true,
    int? count,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_hPad(isMobile), isMobile ? 26 : 36, _hPad(isMobile), 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(
                      eyebrow.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: isMobile ? 24 : 30,
                          fontWeight: FontWeight.w800,
                          color: OhtliColors.onyx,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                      ),
                    ),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: color),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText),
                ),
              ],
            ),
          ),
          if (!isMobile && showArrows)
            Row(
              children: [
                _buildShelfArrow(Icons.arrow_back_rounded, 'Anterior', () => _scrollSection(controller, -scrollStep)),
                const SizedBox(width: 8),
                _buildShelfArrow(Icons.arrow_forward_rounded, 'Siguiente', () => _scrollSection(controller, scrollStep)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildShelfArrow(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: OhtliColors.onyx,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: OhtliColors.cardBg,
        hoverColor: OhtliColors.stormyTeal.withValues(alpha: 0.1),
        fixedSize: const Size(44, 44),
        shape: CircleBorder(side: BorderSide(color: OhtliColors.cardBorder)),
      ),
    );
  }

  // ───────────────────────── Estados vacíos y error ─────────────────────────

  Widget _buildEmptyShelf({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.10), OhtliColors.cardBg],
        ),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, 0.25)!],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Icon(icon, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45),
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
      icon: Icons.favorite_rounded,
      color: OhtliColors.cempasuchil,
      title: 'Aún no guardas lugares',
      message: 'Toca el corazón en cualquier tarjeta para tener tus rincones favoritos siempre a la mano.',
    );
  }

  Widget _buildEmptyRevisitaBanner() {
    return _buildEmptyShelf(
      icon: Icons.history_rounded,
      color: const Color(0xFF3949AB),
      title: 'Tu historial está vacío',
      message: 'Los lugares que abras aparecerán aquí automáticamente para que vuelvas a ellos cuando quieras.',
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [OhtliColors.stormyTeal.withValues(alpha: 0.18), OhtliColors.xoconostle.withValues(alpha: 0.14)],
                  ),
                ),
                child: const Icon(Icons.travel_explore_rounded, size: 40, color: OhtliColors.stormyTeal),
              ),
              const SizedBox(height: 20),
              Text(
                'No encontramos resultados',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba con otra palabra, como "cafetería", "museo" o el nombre de una colonia, o quita algún filtro.',
                style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: _clearAllFilters,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Limpiar búsqueda y filtros'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: OhtliColors.xoconostle.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 38, color: OhtliColors.xoconostle),
              ),
              const SizedBox(height: 18),
              Text(
                'No pudimos cargar los lugares',
                style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
              ),
              const SizedBox(height: 8),
              Text(
                'Revisa tu conexión e inténtalo de nuevo en unos segundos.',
                style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText, height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 8),
                Text(error, style: GoogleFonts.firaCode(fontSize: 11, color: OhtliColors.subtleText), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => _fetchPois(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  shape: const StadiumBorder(),
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Esqueleto de carga ─────────────────────────

  Widget _buildShimmerBox({
    required double width,
    required double height,
    double borderRadius = 8,
  }) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final base = isDark ? const Color(0xFF1E1E22) : const Color(0xFFE6E2DA);
    final highlight = isDark ? const Color(0xFF2C2C33) : const Color(0xFFF6F4EF);
    if (_shimmerController == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(borderRadius)),
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
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonStandardCard(double width, double height) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildShimmerBox(width: width, height: double.infinity, borderRadius: 24)),
          const SizedBox(height: 14),
          _buildShimmerBox(width: width * 0.75, height: 18, borderRadius: 6),
          const SizedBox(height: 8),
          _buildShimmerBox(width: width * 0.5, height: 13, borderRadius: 6),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildShimmerBox(width: 64, height: 22, borderRadius: 20),
              const SizedBox(width: 6),
              _buildShimmerBox(width: 54, height: 22, borderRadius: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonView(bool isMobile, Size screenSize) {
    final hPad = _hPad(isMobile);
    final doubleWidth = isMobile ? math.min(520.0, screenSize.width - 48) : 560.0;

    Widget headerSkeleton(double titleWidth) => Padding(
          padding: EdgeInsets.fromLTRB(hPad, 34, hPad, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShimmerBox(width: 90, height: 11, borderRadius: 4),
              const SizedBox(height: 10),
              _buildShimmerBox(width: titleWidth, height: 26, borderRadius: 8),
            ],
          ),
        );

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Portada
              Padding(
                padding: EdgeInsets.fromLTRB(isMobile ? 10 : hPad, isMobile ? 10 : 24, isMobile ? 10 : hPad, 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isMobile ? 26 : 34),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(isMobile ? 20 : 40, isMobile ? 18 : 28, isMobile ? 20 : 40, isMobile ? 22 : 36),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [const Color(0xFF173F45), OhtliColors.stormyTeal, OhtliColors.xoconostle.withValues(alpha: 0.8)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SvgPicture.asset(
                          'assets/logo.svg',
                          height: 22,
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        ),
                        SizedBox(height: isMobile ? 26 : 40),
                        Text(
                          'Descubre tu próximo\nlugar favorito',
                          style: GoogleFonts.outfit(
                            fontSize: isMobile ? 32 : 50,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.02,
                            letterSpacing: isMobile ? -0.8 : -1.6,
                          ),
                        ),
                        SizedBox(height: isMobile ? 22 : 30),
                        Container(
                          height: isMobile ? 56 : 62,
                          constraints: const BoxConstraints(maxWidth: 680),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: Text(
                                    _isSlowLoad
                                        ? 'Despertando el servidor… la primera carga puede tardar unos segundos.'
                                        : 'Preparando el catálogo de lugares…',
                                    key: ValueKey(_isSlowLoad),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.9)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Filtros
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                child: Row(
                  children: List.generate(
                    isMobile ? 3 : 7,
                    (i) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildShimmerBox(width: i == 0 ? 80 : 120, height: 42, borderRadius: 30),
                    ),
                  ),
                ),
              ),

              headerSkeleton(140),
              SizedBox(
                height: isMobile ? 470 : 520,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  itemCount: 3,
                  separatorBuilder: (_, _) => const SizedBox(width: 22),
                  itemBuilder: (_, _) => _buildShimmerBox(width: doubleWidth, height: isMobile ? 470 : 520, borderRadius: 28),
                ),
              ),

              headerSkeleton(240),
              SizedBox(
                height: 344,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  itemCount: 6,
                  separatorBuilder: (_, _) => const SizedBox(width: 20),
                  itemBuilder: (_, _) => _buildSkeletonStandardCard(268, 344),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encabezado fijo para la barra de filtros; avisa cuando el contenido pasa por debajo.
class _StickyFilterDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget Function(BuildContext context, bool overlaps) builder;

  _StickyFilterDelegate({required this.height, required this.builder});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: builder(context, overlapsContent || shrinkOffset > 0));
  }

  @override
  bool shouldRebuild(covariant _StickyFilterDelegate oldDelegate) => true;
}

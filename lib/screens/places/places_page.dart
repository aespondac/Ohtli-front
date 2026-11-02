// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:math' as math;
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
}

class _PlacesPageState extends State<PlacesPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _paraTiScrollController = ScrollController();
  final ScrollController _descubreScrollController = ScrollController();
  final ScrollController _misLugaresScrollController = ScrollController();
  final ScrollController _revisitaScrollController = ScrollController();

  List<String> _savedPoiIds = [];
  List<String> _viewedPoiIds = [];
  List<double> _userTasteVector = [];

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
    _loadViewedPlaces();
    _loadUserTasteVector();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _paraTiScrollController.dispose();
    _descubreScrollController.dispose();
    _misLugaresScrollController.dispose();
    _revisitaScrollController.dispose();
    super.dispose();
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

  Future<void> _createRouteFromPlace(Poi poi) async {
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

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('pois').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState(snapshot.error.toString());
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
            }

            final docs = snapshot.data?.docs ?? [];
            final allPois = docs
                .map((d) => Poi.fromFirestore(d))
                .where((poi) => poi.isValidCulturalPlace)
                .toList();

            final searchQuery = _searchController.text.trim().toLowerCase();
            final isSearching = searchQuery.isNotEmpty;

            // Search filter
            final searchResults = isSearching
                ? allPois.where((poi) {
                    return poi.name.toLowerCase().contains(searchQuery) ||
                        poi.categoryDisplay.toLowerCase().contains(searchQuery) ||
                        poi.description.toLowerCase().contains(searchQuery) ||
                        poi.cleanNarrative.toLowerCase().contains(searchQuery) ||
                        poi.coloniaAlcaldiaDisplay.toLowerCase().contains(searchQuery) ||
                        poi.vibeTags.any((v) => v.toLowerCase().contains(searchQuery));
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

            return CustomScrollView(
              slivers: [
                // Top Search Bar (Clean and direct)
                SliverToBoxAdapter(
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

                        // Search Bar
                        Container(
                          decoration: BoxDecoration(
                            color: OhtliColors.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: OhtliColors.cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Buscar lugares, colonias, museos, cafés...',
                              hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14),
                              prefixIcon: const Icon(Icons.search_rounded, color: OhtliColors.stormyTeal, size: 22),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // If user is searching, display Search Results Grid
                if (isSearching) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 36, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            'Resultados para "${_searchController.text}" (${searchResults.length})',
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            child: const Text('Ver todas las secciones'),
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
                              isDoubleWidth: true,
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
            );
          },
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
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 36,
        14,
        isMobile ? 16 : 36,
        14,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
              letterSpacing: -0.2,
            ),
          ),
          if (!isMobile && showArrows)
            Row(
              children: [
                IconButton(
                  onPressed: () => _scrollSection(controller, -scrollStep),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15),
                  color: OhtliColors.onyx,
                  style: IconButton.styleFrom(
                    backgroundColor: OhtliColors.cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: OhtliColors.cardBorder),
                    ),
                  ),
                  tooltip: 'Anterior',
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _scrollSection(controller, scrollStep),
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                  color: OhtliColors.onyx,
                  style: IconButton.styleFrom(
                    backgroundColor: OhtliColors.cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: OhtliColors.cardBorder),
                    ),
                  ),
                  tooltip: 'Siguiente',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyMisLugaresBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.bookmark_border_rounded, size: 24, color: OhtliColors.cempasuchil),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Guarda tus rincones favoritos tocando el ícono de marcador en cualquier tarjeta o modal para tenerlos a mano.',
              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRevisitaBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Text(
        'Los lugares que explores se guardarán aquí automáticamente para que puedas revisarlos cuando quieras.',
        style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: OhtliColors.subtleText),
            const SizedBox(height: 16),
            Text(
              'No encontramos resultados',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
            ),
            const SizedBox(height: 8),
            Text(
              'Intenta con otra palabra clave como cafetería, museo o una colonia.',
              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.cempasuchil,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Limpiar Búsqueda'),
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
              onPressed: () => setState(() {}),
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
}

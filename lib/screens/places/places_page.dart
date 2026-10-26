import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/colors.dart';
import '../../models/poi_model.dart';
import '../../widgets/poi_card.dart';
import '../../widgets/poi_detail_dialog.dart';

class PlacesPage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;

  const PlacesPage({
    super.key,
    this.onBack,
    this.showBackButton = false,
  });

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'Todos';
  String _selectedPrice = 'Todos';
  String _collectionName = 'pois'; // 'pois' (Prod) o 'pois_lab' (Sandbox)
  String _sortBy = 'name_asc'; // 'name_asc', 'name_desc', 'category', 'price_asc'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection(_collectionName).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState(snapshot.error.toString());
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            final allPois = docs.map((d) => Poi.fromFirestore(d)).toList();

            // Extract unique categories for filter chips
            final categorySet = <String>{};
            for (final p in allPois) {
              if (p.category.isNotEmpty) {
                categorySet.add(p.category);
              }
            }
            final categories = ['Todos', ...categorySet.toList()..sort()];

            // Filter logic
            final query = _searchController.text.trim().toLowerCase();
            final filteredPois = allPois.where((poi) {
              final matchesQuery = query.isEmpty ||
                  poi.name.toLowerCase().contains(query) ||
                  poi.categoryDisplay.toLowerCase().contains(query) ||
                  poi.semanticDescription.toLowerCase().contains(query) ||
                  poi.description.toLowerCase().contains(query) ||
                  poi.vibeTags.any((v) => v.toLowerCase().contains(query)) ||
                  poi.actividadEconomica.toLowerCase().contains(query);

              final matchesCategory = _selectedCategory == 'Todos' || poi.category == _selectedCategory;

              final matchesPrice = _selectedPrice == 'Todos' ||
                  (_selectedPrice == 'Gratis' && poi.priceLevel == 0) ||
                  (_selectedPrice == '\$' && poi.priceLevel == 1) ||
                  (_selectedPrice == '\$\$' && poi.priceLevel == 2) ||
                  (_selectedPrice == '\$\$\$' && poi.priceLevel == 3) ||
                  (_selectedPrice == '\$\$\$\$' && poi.priceLevel == 4);

              return matchesQuery && matchesCategory && matchesPrice;
            }).toList();

            // Sort logic
            filteredPois.sort((a, b) {
              switch (_sortBy) {
                case 'name_asc':
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                case 'name_desc':
                  return b.name.toLowerCase().compareTo(a.name.toLowerCase());
                case 'category':
                  return a.category.compareTo(b.category);
                case 'price_asc':
                  return a.priceLevel.compareTo(b.priceLevel);
                default:
                  return 0;
              }
            });

            // Metrics
            final totalPois = allPois.length;
            final withVector = allPois.where((p) => p.hasVector).length;
            final withRecipe = allPois.where((p) => p.semanticDescription.isNotEmpty || p.oepAxes.isNotEmpty).length;
            final formalPlaces = allPois.where((p) => p.formalidad).length;

            return CustomScrollView(
              slivers: [
                // Header & Controls
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 32,
                      vertical: 24,
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
                        ],

                        // Main Title Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.place_rounded, color: OhtliColors.stormyTeal, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Lugares Indexados por el Agente Recolector',
                                          style: GoogleFonts.outfit(
                                            fontSize: isMobile ? 22 : 28,
                                            fontWeight: FontWeight.w800,
                                            color: OhtliColors.onyx,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Puntos de interés (POIs) procesados y enriquecidos con datos multi-fuente (INEGI, OSM, Wikipedia, FGJ CDMX) y perfil semántico OEP con vector de 768 dimensiones.',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 13 : 14,
                                      color: OhtliColors.subtleText,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isMobile) ...[
                              const SizedBox(width: 24),
                              _buildCollectionToggle(),
                            ],
                          ],
                        ),

                        if (isMobile) ...[
                          const SizedBox(height: 16),
                          _buildCollectionToggle(),
                        ],

                        const SizedBox(height: 24),

                        // Metrics Cards
                        _buildMetricsRow(
                          isMobile: isMobile,
                          total: totalPois,
                          withVector: withVector,
                          withRecipe: withRecipe,
                          formal: formalPlaces,
                        ),

                        const SizedBox(height: 24),

                        // Search and Filter Bar
                        _buildFilterBar(categories, isMobile),
                      ],
                    ),
                  ),
                ),

                // POIs Grid / List
                if (filteredPois.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 32,
                      vertical: 8,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isMobile
                            ? 1
                            : (screenSize.width < 1150
                                ? 2
                                : (screenSize.width < 1600 ? 3 : 4)),
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        mainAxisExtent: 440,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final poi = filteredPois[index];
                          return PoiCard(
                            poi: poi,
                            onTap: () => PoiDetailDialog.show(context, poi),
                          );
                        },
                        childCount: filteredPois.length,
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 48),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCollectionToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption(
            title: 'Producción',
            subtitle: 'pois',
            isActive: _collectionName == 'pois',
            onTap: () => setState(() => _collectionName = 'pois'),
          ),
          _buildToggleOption(
            title: 'Sandbox Labs',
            subtitle: 'pois_lab',
            isActive: _collectionName == 'pois_lab',
            onTap: () => setState(() => _collectionName = 'pois_lab'),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? OhtliColors.stormyTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: isActive ? Colors.white : OhtliColors.subtleText,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : OhtliColors.onyx,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.firaCode(
                    fontSize: 9.5,
                    color: isActive ? Colors.white.withValues(alpha: 0.8) : OhtliColors.subtleText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow({
    required bool isMobile,
    required int total,
    required int withVector,
    required int withRecipe,
    required int formal,
  }) {
    final items = [
      {'label': 'Total Indexados', 'value': '$total', 'icon': Icons.place_rounded, 'color': OhtliColors.stormyTeal},
      {'label': 'Receta OEP', 'value': '$withRecipe', 'icon': Icons.auto_awesome_rounded, 'color': OhtliColors.cempasuchil},
      {'label': 'Vectores 768d', 'value': '$withVector', 'icon': Icons.hub_rounded, 'color': const Color(0xFF10B981)},
      {'label': 'Negocios Formales', 'value': '$formal', 'icon': Icons.verified_rounded, 'color': OhtliColors.xoconostle},
    ];

    if (isMobile) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items.map((item) {
          return SizedBox(
            width: (MediaQuery.of(context).size.width - 44) / 2,
            child: _buildMetricCard(item),
          );
        }).toList(),
      );
    }

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _buildMetricCard(item),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMetricCard(Map<String, dynamic> item) {
    final color = item['color'] as Color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item['icon'] as IconData, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item['value'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: OhtliColors.onyx,
                  ),
                ),
                Text(
                  item['label'] as String,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: OhtliColors.subtleText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<String> categories, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Search field + Sort dropdown
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, vibra (#bohemio), categoría o palabras clave...',
                    hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: OhtliColors.stormyTeal, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: OhtliColors.innerCardBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: OhtliColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: OhtliColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Sort dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: OhtliColors.innerCardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OhtliColors.cardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    icon: const Icon(Icons.sort_rounded, size: 18, color: OhtliColors.stormyTeal),
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                    dropdownColor: OhtliColors.cardBg,
                    items: const [
                      DropdownMenuItem(value: 'name_asc', child: Text('Nombre (A-Z)')),
                      DropdownMenuItem(value: 'name_desc', child: Text('Nombre (Z-A)')),
                      DropdownMenuItem(value: 'category', child: Text('Por Categoría')),
                      DropdownMenuItem(value: 'price_asc', child: Text('Por Precio')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _sortBy = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 2: Category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                String displayLabel = cat;
                if (cat != 'Todos') {
                  final samplePoi = Poi(
                    poiId: '',
                    name: '',
                    category: cat,
                    location: const PoiLocation(lat: 0, lng: 0),
                  );
                  displayLabel = samplePoi.categoryDisplay;
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(displayLabel),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                    selectedColor: OhtliColors.stormyTeal,
                    backgroundColor: OhtliColors.innerCardBg,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : OhtliColors.onyx,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Row 3: Price filter chips
          Row(
            children: [
              Text(
                'Precio:',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
              ),
              const SizedBox(width: 8),
              ...['Todos', 'Gratis', '\$', '\$\$', '\$\$\$', '\$\$\$\$'].map((price) {
                final isSelected = _selectedPrice == price;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => _selectedPrice = price),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? OhtliColors.cempasuchil : OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? OhtliColors.cempasuchil : OhtliColors.cardBorder,
                        ),
                      ),
                      child: Text(
                        price,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected ? Colors.white : OhtliColors.onyx,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (_searchController.text.isNotEmpty || _selectedCategory != 'Todos' || _selectedPrice != 'Todos') ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _selectedCategory = 'Todos';
                      _selectedPrice = 'Todos';
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 14),
                  label: const Text('Limpiar filtros'),
                  style: TextButton.styleFrom(
                    foregroundColor: OhtliColors.xoconostle,
                    textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded, size: 48, color: OhtliColors.stormyTeal),
            ),
            const SizedBox(height: 20),
            Text(
              'No se encontraron lugares',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: OhtliColors.onyx,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Prueba con otros términos de búsqueda o cambia los filtros de categoría y precio.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: OhtliColors.subtleText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _selectedCategory = 'Todos';
                  _selectedPrice = 'Todos';
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Restablecer Filtros'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              'Error al cargar los lugares indexados',
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
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

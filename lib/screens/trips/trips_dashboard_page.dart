import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../theme/colors.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/trip_card.dart';
import '../construction_page.dart'; // To reuse RouteBackgroundPainter

class TripsDashboardPage extends StatefulWidget {
  const TripsDashboardPage({super.key});

  @override
  State<TripsDashboardPage> createState() => _TripsDashboardPageState();
}

class _TripsDashboardPageState extends State<TripsDashboardPage> {
  final TripService _tripService = TripService();
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  // Curated Unsplash images of Mexico City to offer as high-quality cover defaults
  final List<Map<String, String>> _curatedCovers = [
    {
      'name': 'Bellas Artes',
      'url': 'https://images.unsplash.com/photo-1585464297241-9342febb879f?w=600&auto=format&fit=crop&q=80',
    },
    {
      'name': 'El Ángel',
      'url': 'https://images.unsplash.com/photo-1512813583145-baaa340ef29f?w=600&auto=format&fit=crop&q=80',
    },
    {
      'name': 'Chapultepec',
      'url': 'https://images.unsplash.com/photo-1599839575945-a9e5af0c3fa5?w=600&auto=format&fit=crop&q=80',
    },
    {
      'name': 'Paseo de la Reforma',
      'url': 'https://images.unsplash.com/photo-1518156677180-95a2893f3e9f?w=600&auto=format&fit=crop&q=80',
    },
  ];

  void _showCreateTripDialog(BuildContext context) {
    if (_userId == null) return;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedVisibility = 'private'; // default
    String selectedStatus = 'draft'; // default to Plan (borrador)
    String selectedCoverUrl = _curatedCovers[0]['url']!; // default to first cover

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = OhtliSettings.instance.isDarkMode;

            return AlertDialog(
              backgroundColor: OhtliColors.cloudDancer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Crear Nuevo Plan',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    color: OhtliColors.onyx.withOpacity(0.6),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title Field
                        TextFormField(
                          controller: titleController,
                          maxLength: 50,
                          style: GoogleFonts.inter(color: OhtliColors.onyx),
                          decoration: InputDecoration(
                            labelText: 'Título del viaje *',
                            labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6)),
                            hintText: 'Ej. Fin de semana en Coyoacán',
                            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.3)),
                            filled: true,
                            fillColor: OhtliColors.inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 1.5),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Por favor ingresa un título';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Description Field
                        TextFormField(
                          controller: descriptionController,
                          maxLength: 150,
                          maxLines: 2,
                          style: GoogleFonts.inter(color: OhtliColors.onyx),
                          decoration: InputDecoration(
                            labelText: 'Descripción corta',
                            labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6)),
                            hintText: 'Ej. Museos, cafés y paseos por el centro histórico.',
                            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.3)),
                            filled: true,
                            fillColor: OhtliColors.inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Cover Selector Title
                        Text(
                          'Selecciona una portada para tu camino:',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.onyx.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Grid/Row of Curated Covers
                        SizedBox(
                          height: 75,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _curatedCovers.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final item = _curatedCovers[index];
                              final isSelected = selectedCoverUrl == item['url'];
                              return GestureDetector(
                                onTap: () => setDialogState(() => selectedCoverUrl = item['url']!),
                                child: Container(
                                  width: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? OhtliColors.stormyTeal
                                          : OhtliColors.cantera.withOpacity(0.4),
                                      width: isSelected ? 3 : 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          item['url']!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: OhtliColors.cantera,
                                            child: const Icon(Icons.broken_image_rounded, size: 16),
                                          ),
                                        ),
                                        Container(
                                          color: Colors.black.withOpacity(isSelected ? 0.1 : 0.3),
                                        ),
                                        Center(
                                          child: Text(
                                            item['name']!,
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              shadows: [
                                                const Shadow(
                                                  blurRadius: 4,
                                                  color: Colors.black54,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Visibility & Status Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Visibilidad:',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: OhtliColors.onyx.withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    value: selectedVisibility,
                                    dropdownColor: isDark ? const Color(0xFF25252A) : Colors.white,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: OhtliColors.inputBg,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'private',
                                        child: Text('Privado', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx)),
                                      ),
                                      DropdownMenuItem(
                                        value: 'public',
                                        child: Text('Público', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx)),
                                      ),
                                    ],
                                    onChanged: (val) => setDialogState(() => selectedVisibility = val ?? 'private'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Guardar como:',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: OhtliColors.onyx.withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    value: selectedStatus,
                                    dropdownColor: isDark ? const Color(0xFF25252A) : Colors.white,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: OhtliColors.inputBg,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'draft',
                                        child: Text('Plan (Borrador)', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx)),
                                      ),
                                      DropdownMenuItem(
                                        value: 'published',
                                        child: Text('Publicado', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx)),
                                      ),
                                    ],
                                    onChanged: (val) => setDialogState(() => selectedStatus = val ?? 'draft'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.only(right: 24, bottom: 24),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      color: OhtliColors.onyx.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      // Show loading on original screen
                      Navigator.of(dialogContext).pop();
                      
                      final tripId = const Uuid().v4();
                      final now = DateTime.now();
                      
                      final newTrip = Trip(
                        id: tripId,
                        userId: _userId,
                        title: titleController.text.trim(),
                        description: descriptionController.text.trim(),
                        coverUrl: selectedCoverUrl,
                        status: selectedStatus,
                        visibility: selectedVisibility,
                        createdAt: now,
                        updatedAt: now,
                      );

                      try {
                        await _tripService.createTrip(_userId, newTrip);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                selectedStatus == 'draft' 
                                    ? 'Plan creado con éxito' 
                                    : 'Viaje publicado con éxito',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              backgroundColor: OhtliColors.stormyTeal,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Error al guardar el viaje: $e',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              backgroundColor: OhtliColors.xoconostle,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Guardar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showComingSoonToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              message,
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: OhtliColors.stormyTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _deleteTrip(Trip trip) async {
    if (_userId == null) return;
    try {
      await _tripService.deleteTrip(_userId, trip.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${trip.title}" ha sido eliminado.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: OhtliColors.stormyTeal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al eliminar el viaje: $e',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
          ),
        ),
      );
    }

    final double width = MediaQuery.of(context).size.width;
    final int crossAxisCount = width > 1200 ? 3 : (width > 700 ? 2 : 1);
    final double padding = width > 800 ? 32.0 : 16.0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: 80,
          title: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding - 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mis Viajes',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Organiza y comparte tus caminos',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: OhtliColors.onyx.withOpacity(0.5),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                
                // Styled "Crear Plan" button on desktop / tablet
                if (width > 600)
                  ElevatedButton.icon(
                    onPressed: () => _showCreateTripDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Crear Plan',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: TabBar(
                isScrollable: true,
                indicatorColor: OhtliColors.stormyTeal,
                indicatorWeight: 3,
                labelColor: OhtliColors.stormyTeal,
                unselectedLabelColor: OhtliColors.onyx.withOpacity(0.5),
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Publicados'),
                  Tab(text: 'Planes'),
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            // Map dotted line background
            Positioned.fill(
              child: CustomPaint(
                painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.3)),
              ),
            ),

            StreamBuilder<List<Trip>>(
              stream: _tripService.getTripsStream(_userId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Ocurrió un error al cargar tus viajes: ${snapshot.error}',
                        style: GoogleFonts.inter(color: OhtliColors.xoconostle),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
                    ),
                  );
                }

                final allTrips = snapshot.data ?? [];
                final publishedTrips = allTrips.where((t) => t.status == 'published').toList();
                final draftTrips = allTrips.where((t) => t.status == 'draft').toList();

                return TabBarView(
                  children: [
                    // --- TAB: PUBLICADOS ---
                    _buildTripsList(
                      publishedTrips, 
                      'Aún no tienes viajes publicados.',
                      'Cuando termines un plan, podrás publicarlo para que todo el mundo vea tu recorrido.',
                      crossAxisCount, 
                      padding,
                    ),

                    // --- TAB: PLANES (Borradores) ---
                    _buildTripsList(
                      draftTrips, 
                      'Tu libreta de caminos está vacía.',
                      'Crea tu primer plan para comenzar a diseñar tu ruta por la Ciudad de México.',
                      crossAxisCount, 
                      padding,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        
        // Floating Action Button on mobile instead of AppBar button
        floatingActionButton: width <= 600
            ? FloatingActionButton(
                onPressed: () => _showCreateTripDialog(context),
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add_rounded),
              )
            : null,
      ),
    );
  }

  Widget _buildTripsList(
    List<Trip> trips, 
    String emptyTitle, 
    String emptySub,
    int crossAxisCount,
    double padding,
  ) {
    if (trips.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OhtliColors.stormyTeal.withOpacity(0.06),
                  border: Border.all(
                    color: OhtliColors.stormyTeal.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  color: OhtliColors.stormyTeal,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                emptyTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  emptySub,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.5,
                    color: OhtliColors.onyx.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _showCreateTripDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  'Crear Plan',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OhtliColors.stormyTeal,
                  side: const BorderSide(color: OhtliColors.stormyTeal),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, 20, padding, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 16 / 15.5, // Perfect height-to-width ratio for our card design
      ),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        return TripCard(
          trip: trip,
          onEdit: () => _showComingSoonToast(
            context,
            'La edición interactiva del plan de viaje estará disponible próximamente en el Issue #11.',
          ),
          onDelete: () => _deleteTrip(trip),
        );
      },
    );
  }
}

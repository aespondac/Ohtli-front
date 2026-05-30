import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../../theme/colors.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/trip_card.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../construction_page.dart'; // To reuse RouteBackgroundPainter

class TripsDashboardPage extends StatefulWidget {
  const TripsDashboardPage({super.key});

  @override
  State<TripsDashboardPage> createState() => _TripsDashboardPageState();
}

class _TripsDashboardPageState extends State<TripsDashboardPage> {
  final TripService _tripService = TripService();
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;



  void _showCreateTripDialog(BuildContext context) {
    if (_userId == null) return;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final travelDateController = TextEditingController();
    DateTime? selectedTravelDate;
    String? selectedCoverBase64;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                  if (!isSaving)
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
                          enabled: !isSaving,
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
                          enabled: !isSaving,
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
                        const SizedBox(height: 12),

                        // Travel Date Field
                        TextFormField(
                          controller: travelDateController,
                          readOnly: true,
                          enabled: !isSaving,
                          style: GoogleFonts.inter(color: OhtliColors.onyx),
                          decoration: InputDecoration(
                            labelText: 'Fecha del viaje',
                            labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6)),
                            hintText: 'Selecciona la fecha de tu viaje',
                            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.3)),
                            filled: true,
                            fillColor: OhtliColors.inputBg,
                            prefixIcon: const Icon(Icons.calendar_today_rounded, color: OhtliColors.stormyTeal, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 1.5),
                            ),
                          ),
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedTravelDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              builder: (context, child) {
                                final isDark = OhtliSettings.instance.isDarkMode;
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: ColorScheme.light(
                                      primary: OhtliColors.stormyTeal,
                                      onPrimary: Colors.white,
                                      onSurface: OhtliColors.onyx,
                                      surface: isDark ? const Color(0xFF1E1E22) : Colors.white,
                                    ),
                                    dialogBackgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedTravelDate = picked;
                                final months = [
                                  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
                                  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
                                ];
                                travelDateController.text = '${picked.day} de ${months[picked.month - 1]} de ${picked.year}';
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Cover Selector Title
                        Text(
                          'Portada del viaje',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.onyx.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Custom Cover Image Uploader Dropzone
                        GestureDetector(
                          onTap: isSaving
                              ? null
                              : () {
                                  if (kIsWeb) {
                                    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
                                    uploadInput.click();
                                    uploadInput.onChange.listen((e) {
                                      final files = uploadInput.files;
                                      if (files != null && files.isNotEmpty) {
                                        final file = files[0];
                                        final reader = html.FileReader();
                                        reader.onLoadEnd.listen((e) {
                                          final dynamic result = reader.result;
                                          if (result is String && result.isNotEmpty) {
                                            try {
                                              final String base64Data = result.split(',').last;
                                              final Uint8List bytes = base64Decode(base64Data);
                                              if (bytes.isNotEmpty) {
                                                Future.delayed(const Duration(milliseconds: 200), () {
                                                  if (context.mounted) {
                                                    showDialog(
                                                      context: context,
                                                      barrierDismissible: false,
                                                      builder: (context) => OhtliImageCropperDialog(
                                                        imageBytes: bytes,
                                                        isCircle: false,
                                                        onCropped: (String base64String) {
                                                          setDialogState(() {
                                                            selectedCoverBase64 = base64String;
                                                          });
                                                        },
                                                      ),
                                                    );
                                                  }
                                                });
                                              }
                                            } catch (err) {
                                              print("Error decoding or cropping image: $err");
                                            }
                                          }
                                        });
                                        reader.readAsDataUrl(file);
                                      }
                                    });
                                  } else {
                                    _showComingSoonToast(
                                      context,
                                      'La selección de portadas locales en dispositivos nativos se habilitará en la siguiente fase.',
                                    );
                                  }
                                },
                          child: Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              color: OhtliColors.inputBg.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: OhtliColors.cantera.withOpacity(0.6),
                                width: 1.5,
                              ),
                            ),
                            child: selectedCoverBase64 != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.memory(
                                          base64Decode(selectedCoverBase64!.split(',').last),
                                          fit: BoxFit.cover,
                                        ),
                                        Positioned(
                                          right: 12,
                                          bottom: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Cambiar portada',
                                              style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: OhtliColors.onyx.withOpacity(0.4),
                                        size: 36,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Sube una imagen de portada',
                                        style: GoogleFonts.inter(
                                          color: OhtliColors.onyx.withOpacity(0.5),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.only(right: 24, bottom: 24),
              actions: isSaving
                  ? [
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(right: 16),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
                          ),
                        ),
                      )
                    ]
                  : [
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
                            setDialogState(() {
                              isSaving = true;
                            });

                            final tripId = const Uuid().v4();
                            final now = DateTime.now();
                            String finalCoverUrl = "";

                            // 1. Upload Cover to Storage if provided
                            if (selectedCoverBase64 != null) {
                              try {
                                final rawBase64 = selectedCoverBase64!.contains(',')
                                    ? selectedCoverBase64!.split(',').last
                                    : selectedCoverBase64!;
                                final imageBytes = base64Decode(rawBase64);
                                final storageRef = FirebaseStorage.instance
                                    .ref('users/$_userId/trips/$tripId/cover.jpg');
                                await storageRef.putData(
                                  Uint8List.fromList(imageBytes),
                                  SettableMetadata(contentType: 'image/jpeg'),
                                );
                                final bucket = FirebaseStorage.instance.app.options.storageBucket;
                                finalCoverUrl =
                                    "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F$_userId%2Ftrips%2F$tripId%2Fcover.jpg?alt=media";
                              } catch (e) {
                                print("Error uploading cover to Storage: $e");
                              }
                            }

                            // 2. Create Trip document as a private draft
                            final newTrip = Trip(
                              id: tripId,
                              userId: _userId,
                              title: titleController.text.trim(),
                              description: descriptionController.text.trim(),
                              coverUrl: finalCoverUrl,
                              status: 'draft', // Regla de negocio: inicia como borrador
                              visibility: 'private', // Regla de negocio: inicia como privado
                              createdAt: now,
                              updatedAt: now,
                              travelDate: selectedTravelDate,
                            );

                            try {
                              await _tripService.createTrip(_userId, newTrip);
                              Navigator.of(dialogContext).pop();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Plan creado con éxito',
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
                              setDialogState(() {
                                isSaving = false;
                              });
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
    final int crossAxisCount = width > 1200 ? 4 : (width > 800 ? 3 : (width > 550 ? 2 : 1));
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
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icon_isologo.svg',
                    width: 40,
                    height: 40,
                    colorFilter: const ColorFilter.mode(
                      OhtliColors.stormyTeal,
                      BlendMode.srcIn,
                    ),
                  ),
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
        childAspectRatio: 16 / 14.5, // Sleek, modern, and compact height-to-width ratio
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

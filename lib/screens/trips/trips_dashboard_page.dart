// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../theme/colors.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/trip_card.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../construction_page.dart'; // To reuse RouteBackgroundPainter
import 'trip_editor_page.dart';
import 'trip_viewer_page.dart';

class TripsDashboardPage extends StatefulWidget {
  const TripsDashboardPage({super.key});

  @override
  State<TripsDashboardPage> createState() => _TripsDashboardPageState();
}

class _TripsDashboardPageState extends State<TripsDashboardPage> {
  final TripService _tripService = TripService();
  String? _userId = FirebaseAuth.instance.currentUser?.uid;

  // Cache for author profiles (co-authored trips)
  final Map<String, Map<String, String?>> _authorProfilesCache = {};

  StreamSubscription<User?>? _authSub;
  StreamSubscription? _ownedSub;
  StreamSubscription? _coAuthorSub;
  StreamSubscription? _surpriseSub;

  List<Trip> _ownedTrips = [];
  List<Trip> _coAuthorTrips = [];
  List<Trip> _surpriseTrips = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _cancelStreams();
        if (mounted) {
          setState(() {
            _userId = null;
            _ownedTrips = [];
            _coAuthorTrips = [];
            _surpriseTrips = [];
            _isLoading = false;
          });
        }
      } else {
        if (user.uid != _userId || _ownedSub == null || _coAuthorSub == null || _surpriseSub == null) {
          _subscribeToStreams(user.uid);
        }
      }
    });
    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser != null) {
      _subscribeToStreams(initialUser.uid);
    }
  }

  void _cancelStreams() {
    _ownedSub?.cancel();
    _coAuthorSub?.cancel();
    _surpriseSub?.cancel();
    _ownedSub = null;
    _coAuthorSub = null;
    _surpriseSub = null;
  }

  void _subscribeToStreams(String uid) {
    _cancelStreams();

    if (mounted) {
      setState(() {
        _userId = uid;
        _isLoading = true;
      });
    }

    _ownedSub = _tripService.getTripsStream(uid).listen((trips) {
      if (mounted) {
        setState(() {
          _ownedTrips = trips;
          _isLoading = false;
        });
      }
    }, onError: (err) {
      print("DEBUG: ownedTripsStream error: $err");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });

    _coAuthorSub = FirebaseFirestore.instance
        .collectionGroup('trips')
        .where('coAuthorIds', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      final trips = snapshot.docs
          .map((doc) => Trip.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      if (mounted) {
        setState(() {
          _coAuthorTrips = trips;
        });
      }
    }, onError: (err) {
      print("DEBUG: coAuthorTripsStream error: $err");
    });

    _surpriseSub = FirebaseFirestore.instance
        .collectionGroup('trips')
        .where('surpriseTargetIds', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      final trips = snapshot.docs
          .map((doc) => Trip.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      if (mounted) {
        setState(() {
          _surpriseTrips = trips;
        });
      }
    }, onError: (err) {
      print("DEBUG: surpriseTripsStream error: $err");
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelStreams();
    super.dispose();
  }

  void _showCreateTripDialog(BuildContext context) {
    final uid = _userId;
    if (uid == null) return;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final travelDateController = TextEditingController();
    DateTime? selectedTravelDate;
    String? selectedCoverBase64;
    bool isSurprise = false;
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
                      color: OhtliColors.onyx.withValues(alpha: 0.6),
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
                            labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.6)),
                            hintText: 'Ej. Fin de semana en Coyoacán',
                            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
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
                            labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.6)),
                            hintText: 'Ej. Museos, cafés y paseos por el centro histórico.',
                            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
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
                            labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.6)),
                            hintText: 'Selecciona la fecha de tu viaje',
                            hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
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
                                    ), dialogTheme: DialogThemeData(backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white),
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
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: Text(
                            '¿Es un plan sorpresa?',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: OhtliColors.onyx.withValues(alpha: 0.8),
                            ),
                          ),
                          subtitle: Text(
                            'Tus mejores amigos mutuos verán este plan cuando se abra.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: OhtliColors.onyx.withValues(alpha: 0.5),
                            ),
                          ),
                          value: isSurprise,
                          activeColor: OhtliColors.stormyTeal,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) {
                            setDialogState(() {
                              isSurprise = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Cover Selector Title
                        Text(
                          'Portada del viaje',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.onyx.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Custom Cover Image Uploader Dropzone
                        GestureDetector(
                          onTap: isSaving
                              ? null
                              : () {
                                  if (kIsWeb) {
                                    final uploadInput = html.FileUploadInputElement()
                                      ..accept = 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw';
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
                              color: OhtliColors.inputBg.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: OhtliColors.cantera.withValues(alpha: 0.6),
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
                                              color: Colors.black.withValues(alpha: 0.6),
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
                                        color: OhtliColors.onyx.withValues(alpha: 0.4),
                                        size: 36,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Sube una imagen de portada',
                                        style: GoogleFonts.inter(
                                          color: OhtliColors.onyx.withValues(alpha: 0.5),
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
                            color: OhtliColors.onyx.withValues(alpha: 0.6),
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
                                    .ref('users/$uid/trips/$tripId/cover.jpg');
                                await storageRef.putData(
                                  Uint8List.fromList(imageBytes),
                                  SettableMetadata(contentType: 'image/jpeg'),
                                );
                                final bucket = FirebaseStorage.instance.app.options.storageBucket;
                                finalCoverUrl =
                                    "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F$uid%2Ftrips%2F$tripId%2Fcover.jpg?alt=media";
                              } catch (e) {
                                print("Error uploading cover to Storage: $e");
                              }
                            }

                            // 2. Create Trip document as a private draft
                            final newTrip = Trip(
                              id: tripId,
                              userId: uid,
                              title: titleController.text.trim(),
                              description: descriptionController.text.trim(),
                              coverUrl: finalCoverUrl,
                              status: 'draft', // Regla de negocio: inicia como borrador
                              visibility: 'private', // Regla de negocio: inicia como privado
                              createdAt: now,
                              updatedAt: now,
                              travelDate: selectedTravelDate,
                              isSurprise: isSurprise,
                            );

                            try {
                              await _tripService.createTrip(uid, newTrip);
                              Navigator.of(dialogContext).pop();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Plan creado con éxito. Redirigiendo al editor...',
                                      style: GoogleFonts.inter(color: Colors.white),
                                    ),
                                    backgroundColor: OhtliColors.stormyTeal,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
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
    final uid = _userId;
    if (uid == null) return;
    try {
      await _tripService.deleteTrip(uid, trip.id);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final int crossAxisCount = width > 1200 ? 4 : (width > 800 ? 3 : (width > 550 ? 2 : 1));
        final double padding = width > 800 ? 32.0 : 16.0;
        final bool isDark = OhtliSettings.instance.isDarkMode;

        // Combine all owned and co-authored trips, avoiding duplicates by trip ID
        final Map<String, Trip> combinedMap = {};
        for (var trip in _ownedTrips) {
          combinedMap[trip.id] = trip;
        }
        for (var trip in _coAuthorTrips) {
          combinedMap[trip.id] = trip;
        }
        
        final allTrips = combinedMap.values.toList();
        // Sort combined list by createdAt descending
        allTrips.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final publishedTrips = allTrips.where((t) => t.status == 'published').toList();
        final draftTrips = allTrips.where((t) => t.status == 'draft').toList();

        Widget? surpriseSection;
        if (_surpriseTrips.isNotEmpty) {
          surpriseSection = _buildSurprisePlansSection(_surpriseTrips, isDark);
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: OhtliColors.cloudDancer,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              centerTitle: false,
              titleSpacing: 0,
              toolbarHeight: 80,
              title: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
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
                            color: OhtliColors.onyx.withValues(alpha: 0.5),
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
                    unselectedLabelColor: OhtliColors.onyx.withValues(alpha: 0.5),
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
                    painter: RouteBackgroundPainter(OhtliColors.cantera.withValues(alpha: 0.3)),
                  ),
                ),

                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
                        ),
                      )
                    : TabBarView(
                        children: [
                          // --- TAB: PUBLICADOS ---
                          _buildTripsList(
                            publishedTrips, 
                            'Aún no tienes viajes publicados.',
                            'Cuando termines un plan, podrás publicarlo para que todo el mundo vea tu recorrido.',
                            crossAxisCount, 
                            padding,
                            width,
                          ),

                          // --- TAB: PLANES (Borradores) ---
                          (draftTrips.isEmpty && _surpriseTrips.isEmpty)
                              ? _buildTripsList(
                                  [], 
                                  'Tu libreta de caminos está vacía.',
                                  'Crea tu primer plan para comenzar a diseñar tu ruta por la Ciudad de México.',
                                  crossAxisCount, 
                                  padding,
                                  width,
                                )
                              : ListView(
                                  padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
                                  children: [
                                    if (surpriseSection != null) ...[
                                      surpriseSection,
                                      const SizedBox(height: 24),
                                    ],
                                    if (draftTrips.isNotEmpty) ...[
                                      Text(
                                        'Mis Planes de Viaje',
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: OhtliColors.onyx,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildTripsGrid(draftTrips, crossAxisCount, width, padding),
                                    ],
                                  ],
                                ),
                        ],
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
      },
    );
  }

  Widget _buildTripsList(
    List<Trip> trips, 
    String emptyTitle, 
    String emptySub,
    int crossAxisCount,
    double padding,
    double availableWidth,
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
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.06),
                  border: Border.all(
                    color: OhtliColors.stormyTeal.withValues(alpha: 0.15),
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
                    color: OhtliColors.onyx.withValues(alpha: 0.5),
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
    
    // Calculate the width of a single card
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 24) / crossAxisCount;
    
    // Calculate aspect ratio dynamically to prevent vertical text overflows:
    // - If it's a mobile 1-column layout, we want a compact horizontal card of fixed height (125px).
    // - Otherwise, standard vertical layout where height = (cardWidth * 9 / 16) + 168px (to perfectly fit paddings, titles, descriptions, and dual dates without overflow!).
    final double cardHeight = crossAxisCount == 1 
        ? 125.0 
        : (cardWidth * 9 / 16) + 168.0;
    
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, 20, padding, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: computedAspectRatio,
      ),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final bool isCoAuthored = trip.userId != _userId;
        
        // For co-authored trips, fetch author profile lazily
        if (isCoAuthored && !_authorProfilesCache.containsKey(trip.userId)) {
          _authorProfilesCache[trip.userId] = {'name': null, 'photo': null};
          FirebaseFirestore.instance.collection('users').doc(trip.userId).get().then((doc) {
            if (doc.exists && mounted) {
              final data = doc.data();
              setState(() {
                _authorProfilesCache[trip.userId] = {
                  'name': (data?['displayName'] as String?) ?? 'Viajero Ohtli',
                  'photo': data?['photoURL'] as String?,
                };
              });
            }
          });
        }
        
        final authorProfile = isCoAuthored ? _authorProfilesCache[trip.userId] : null;

        return TripCard(
          trip: trip,
          isHorizontal: crossAxisCount == 1,
          addedByName: isCoAuthored ? (authorProfile?['name'] ?? 'Cargando...') : null,
          addedByPhotoURL: isCoAuthored ? (authorProfile?['photo']) : null,
          onEdit: () {
            if (trip.status == 'published') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripViewerPage(trip: trip),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripEditorPage(trip: trip),
                ),
              );
            }
          },
          onFeDeErratas: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TripEditorPage(trip: trip),
              ),
            );
          },
          onDelete: () => _deleteTrip(trip),
        );
      },
    );
  }

  Widget _buildTripsGrid(List<Trip> trips, int crossAxisCount, double availableWidth, double padding) {
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 24) / crossAxisCount;
    final double cardHeight = crossAxisCount == 1 
        ? 125.0 
        : (cardWidth * 9 / 16) + 168.0;
    
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: computedAspectRatio,
      ),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final bool isCoAuthored = trip.userId != _userId;
        
        if (isCoAuthored && !_authorProfilesCache.containsKey(trip.userId)) {
          _authorProfilesCache[trip.userId] = {'name': null, 'photo': null};
          FirebaseFirestore.instance.collection('users').doc(trip.userId).get().then((doc) {
            if (doc.exists && mounted) {
              final data = doc.data();
              setState(() {
                _authorProfilesCache[trip.userId] = {
                  'name': (data?['displayName'] as String?) ?? 'Viajero Ohtli',
                  'photo': data?['photoURL'] as String?,
                };
              });
            }
          });
        }
        
        final authorProfile = isCoAuthored ? _authorProfilesCache[trip.userId] : null;

        return TripCard(
          trip: trip,
          isHorizontal: crossAxisCount == 1,
          addedByName: isCoAuthored ? (authorProfile?['name'] ?? 'Cargando...') : null,
          addedByPhotoURL: isCoAuthored ? (authorProfile?['photo']) : null,
          onEdit: () {
            if (trip.status == 'published') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripViewerPage(trip: trip),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripEditorPage(trip: trip),
                ),
              );
            }
          },
          onFeDeErratas: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TripEditorPage(trip: trip),
              ),
            );
          },
          onDelete: () => _deleteTrip(trip),
        );
      },
    );
  }

  Widget _buildSurprisePlansSection(List<Trip> surpriseTrips, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '🎁',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Text(
              'Planes Sorpresa Para Ti',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: OhtliColors.onyx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: surpriseTrips.length,
            itemBuilder: (context, index) {
              final trip = surpriseTrips[index];
              final isLocked = trip.surpriseUnlockDate != null && 
                  DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
                      .isBefore(DateTime(trip.surpriseUnlockDate!.year, trip.surpriseUnlockDate!.month, trip.surpriseUnlockDate!.day));
              final isOpened = trip.surpriseOpenedBy.contains(_userId);

              return _buildSurpriseCard(trip, isLocked, isOpened, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSurpriseCard(Trip trip, bool isLocked, bool isOpened, bool isDark) {
    final Color cardColor = isDark ? const Color(0xFF25252A) : Colors.white;

    Widget cardContent;
    if (isLocked) {
      final date = trip.surpriseUnlockDate!;
      cardContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_rounded, size: 28, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            'Plan Sorpresa Cerrado',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            'Disponible el ${date.day}/${date.month}/${date.year}',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      );
    } else if (!isOpened) {
      cardContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.95, end: 1.05),
            duration: const Duration(seconds: 1),
            curve: Curves.easeInOut,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: const Text('🎁', style: TextStyle(fontSize: 32)),
          ),
          const SizedBox(height: 10),
          Text(
            '¡Tienes un Regalo!',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toca para abrir la sorpresa',
            style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.onyx.withOpacity(0.6)),
          ),
        ],
      );
    } else {
      cardContent = Stack(
        children: [
          if (trip.coverUrl.isNotEmpty)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  trip.coverUrl,
                  fit: BoxFit.cover,
                  color: Colors.black.withOpacity(0.35),
                  colorBlendMode: BlendMode.srcOver,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Revelado 🎁',
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  trip.title,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'De tu Mejor Amigo',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLocked 
              ? Colors.grey.withOpacity(0.2)
              : (isOpened ? Colors.transparent : OhtliColors.stormyTeal.withOpacity(0.3)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isLocked
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '¡Aún no es momento de abrir este regalo! 🤫 Estará disponible el ${trip.surpriseUnlockDate!.day}/${trip.surpriseUnlockDate!.month}/${trip.surpriseUnlockDate!.year}.',
                        style: GoogleFonts.inter(),
                      ),
                      backgroundColor: OhtliColors.stormyTeal,
                    ),
                  );
                }
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TripViewerPage(
                        tripId: trip.id,
                        authorId: trip.userId,
                      ),
                    ),
                  ).then((_) {
                    setState(() {});
                  });
                },
          child: cardContent,
        ),
      ),
    );
  }
}

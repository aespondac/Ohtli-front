// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print, use_build_context_synchronously

import '../../services/feedback_service.dart';
import 'dart:async';
import 'dart:convert';
import '../../utils/web_helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../widgets/ohtli_ui.dart';
import '../../widgets/ohtli_service_icon.dart';
import '../../theme/colors.dart';
import '../../theme/cdmx_photos.dart';
import '../../utils/friendly_errors.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../widgets/trip_card.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../widgets/surprise_polaroid_card.dart';
import '../../widgets/trip_polaroid.dart';
import '../../services/trip_activity.dart';
import '../../services/hidden_trips.dart';
import '../../services/itinerary_blackboard_service.dart';
import '../../widgets/trip_planner_dialog.dart';
import 'trip_editor_page.dart';
import 'trip_viewer_page.dart';

class TripsDashboardPage extends StatefulWidget {
  const TripsDashboardPage({super.key});

  @override
  State<TripsDashboardPage> createState() => _TripsDashboardPageState();
}

class _TripsDashboardPageState extends State<TripsDashboardPage> {
  final TripService _tripService = TripService();
  final ItineraryBlackboardService _blackboardService = ItineraryBlackboardService();
  String? _userId = FirebaseAuth.instance.currentUser?.uid;

  // Cache for author profiles (co-authored trips)
  final Map<String, Map<String, String?>> _authorProfilesCache = {};

  StreamSubscription<User?>? _authSub;
  StreamSubscription? _ownedSub;
  StreamSubscription? _coAuthorSub;
  StreamSubscription? _surpriseSub;
  StreamSubscription? _jobsSub;

  /// Planes con IA terminados que todavía no abres.
  Set<String> _newJobIds = {};

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
    TripActivity.instance.addListener(_onActivity);
    HiddenTrips.instance.addListener(_onActivity);
  }

  void _onActivity() {
    if (mounted) setState(() {});
  }

  static bool _jobIsReady(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString();
    final res = data['result'] as Map<String, dynamic>? ?? {};
    final options = (res['options'] as List<dynamic>?) ?? [];
    final chosen = data['created_trip_id'] != null || status == 'chosen' || status == 'dismissed';
    return !chosen && options.isNotEmpty;
  }

  void _cancelStreams() {
    _ownedSub?.cancel();
    _coAuthorSub?.cancel();
    _surpriseSub?.cancel();
    _jobsSub?.cancel();
    _ownedSub = null;
    _coAuthorSub = null;
    _surpriseSub = null;
    _jobsSub = null;
  }

  void _subscribeToStreams(String uid) {
    _cancelStreams();

    if (mounted) {
      setState(() {
        _userId = uid;
        _isLoading = true;
      });
    }

    // Sincronizar y recuperar jobs calculados en segundo plano por Yollotl Engine
    _blackboardService.syncUserJobsFromBackend(uid);

    // Novedades: comentarios en viajes publicados y planes con IA recién terminados
    TripActivity.instance.start(uid);
    HiddenTrips.instance.start(uid);
    _jobsSub = FirebaseFirestore.instance
        .collection('itinerary_jobs')
        .where('user_id', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      final ready = snap.docs.where((d) => _jobIsReady(d.data())).map((d) => d.id).toList();
      TripActivity.instance.baselineJobs(ready);
      final fresh = ready.where(TripActivity.instance.isJobNew).toSet();
      if (mounted) {
        setState(() {
          _newJobIds = fresh;
          _readyJobCount = ready.length;
        });
      }
    }, onError: (_) {});

    _ownedSub = _tripService.getTripsStream(uid).listen((trips) {
      if (mounted) {
        setState(() {
          // Las notas de versión se gestionan en Administración, no en Mis viajes.
          _ownedTrips = trips.where((t) => !t.isReleaseNotes).toList();
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
          .map((doc) => Trip.fromMap(doc.data(), doc.id))
          .where((t) => !t.isReleaseNotes)
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
          .map((doc) => Trip.fromMap(doc.data(), doc.id))
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
    TripActivity.instance.removeListener(_onActivity);
    HiddenTrips.instance.removeListener(_onActivity);
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
                                    pickFile(accept: 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw').then((picked) {
                                      if (picked == null) return;
                                            try {
                                              final Uint8List bytes = picked.bytes;
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
                                      friendlyError(e, fallback: 'No pudimos guardar el viaje. Intenta de nuevo.'),
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

  // Borra un trabajo de IA y ofrece "Deshacer" (antes se borraba sin confirmación)
  Future<void> _discardJobWithUndo(QueryDocumentSnapshot doc, {required String message}) async {
    final ref = FirebaseFirestore.instance.collection('itinerary_jobs').doc(doc.id);
    final backup = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>? ?? {});
    try {
      await ref.delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e), style: GoogleFonts.inter()), backgroundColor: OhtliColors.xoconostle),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: OhtliColors.onyx,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: OhtliColors.cempasuchil,
            onPressed: () => ref.set(backup),
          ),
        ),
      );
  }

  void _openAiPlanner() => TripPlannerDialog.show(context);

  // En móvil: un solo botón "Nuevo viaje" que ofrece las dos formas de empezar
  void _showNewTripSheet() {
    final isDark = OhtliSettings.instance.isDarkMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        Widget option(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            title: Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: OhtliColors.cardBorder, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                option(Icons.auto_awesome_rounded, 'Planear con IA', 'Te proponemos 3 rutas según tus gustos', OhtliColors.stormyTeal, _openAiPlanner),
                option(Icons.edit_note_rounded, 'Crear plan por mi cuenta', 'Empieza un borrador en blanco', OhtliColors.cempasuchil, () => _showCreateTripDialog(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle, Widget? leading, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  title,
                  style: OhtliUi.title(size: 22),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: OhtliUi.body(size: 13.5)),
          ],
        ],
      ),
    );
  }

  int _readyJobCount = 0;

  /// Etiqueta de pestaña: nombre, contador en su propia píldora y punto si hay algo nuevo.
  Widget _tabLabel(String label, int count, bool hasNews) {
    return Builder(builder: (context) {
      final selected = DefaultTextStyle.of(context).style.color == Colors.white;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : OhtliColors.onyx.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text('$count', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ],
          if (hasNews) ...[
            const SizedBox(width: 6),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: OhtliColors.xoconostle,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 1.5),
              ),
            ),
          ],
        ],
      );
    });
  }

  bool _isSurpriseLocked(Trip trip) {
    final DateTime? unlockDate = trip.surpriseUnlockDates[_userId];
    if (trip.unlockOnPublish) return trip.status != 'published';
    if (unlockDate == null) return false;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).isBefore(DateTime(unlockDate.year, unlockDate.month, unlockDate.day));
  }

  void _openTrip(Trip trip) {
    if (trip.status == 'published') TripActivity.instance.markTripSeen(trip.id);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => trip.status == 'published' ? TripViewerPage(trip: trip) : TripEditorPage(trip: trip)),
    ).then((_) {
      if (trip.status == 'published') TripActivity.instance.markTripSeen(trip.id);
      if (mounted) setState(() {});
    });
  }

  Widget _countBadge(int n, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        '$n',
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: filled ? Colors.white : color),
      ),
    );
  }

  // Esqueleto de tarjetas mientras llegan los viajes (en lugar de un spinner)
  Widget _buildSkeletonGrid(int crossAxisCount, double width, double padding) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final base = isDark ? const Color(0xFF26262B) : OhtliColors.cantera.withValues(alpha: 0.35);
    final cardWidth = (width - padding * 2 - (crossAxisCount - 1) * 18) / crossAxisCount;
    final cardHeight = crossAxisCount == 1 ? 112.0 : (cardWidth * 0.6) + 112.0;
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6)));
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(padding, 20, padding, 20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: cardWidth / cardHeight,
      ),
      itemCount: crossAxisCount == 1 ? 4 : crossAxisCount * 2,
      itemBuilder: (context, i) {
        final card = isDark ? const Color(0xFF1E1E22) : Colors.white;
        final details = Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bar(140, 14), const SizedBox(height: 10), bar(double.infinity, 10), const SizedBox(height: 6), bar(100, 10)],
          ),
        );
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: crossAxisCount == 1
              ? Row(children: [Container(width: 130, color: base), Expanded(child: details)])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [AspectRatio(aspectRatio: 16 / 9, child: Container(color: base)), details],
                ),
        );
      },
    );
  }

  /// Quita de tus viajes uno que es de otra persona (sorpresa o coautoría), con opción
  /// de deshacer. El viaje sigue siendo de su dueño.
  Future<void> _hideTrip(Trip trip) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await HiddenTrips.instance.hide(trip.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            trip.isSurprise ? 'Quitamos la sorpresa de tus planes.' : 'Quitamos "${trip.title}" de tus viajes.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: OhtliColors.stormyTeal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: Colors.white,
            onPressed: () => HiddenTrips.instance.unhide(trip.id).catchError((_) {}),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'No pudimos quitar el viaje. Intenta de nuevo.'),
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
    }
  }

  void _deleteTrip(Trip trip) async {
    final uid = _userId;
    if (uid == null) return;
    if (trip.userId != uid) {
      await _hideTrip(trip);
      return;
    }
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
              friendlyError(e, fallback: 'No pudimos eliminar el viaje. Intenta de nuevo.'),
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
        final int crossAxisCount = width > 1500 ? 5 : (width > 1100 ? 4 : (width > 760 ? 3 : (width > 520 ? 2 : 1)));
        final double padding = width > 800 ? 40.0 : 16.0;
        final bool isDark = OhtliSettings.instance.isDarkMode;

        // Combine all owned, co-authored, and opened surprise trips, avoiding duplicates by trip ID
        final Map<String, Trip> combinedMap = {};
        for (var trip in _ownedTrips) {
          combinedMap[trip.id] = trip;
        }
        final hidden = HiddenTrips.instance;
        for (var trip in _coAuthorTrips) {
          if (hidden.contains(trip.id)) continue;
          combinedMap[trip.id] = trip;
        }
        for (var trip in _surpriseTrips) {
          if (hidden.contains(trip.id)) continue;
          final bool isOpened = trip.surpriseOpenedBy.contains(_userId);
          if (isOpened) {
            combinedMap[trip.id] = trip;
          }
        }
        
        final allTrips = combinedMap.values.toList();
        // Sort combined list by createdAt descending
        allTrips.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final publishedTrips = allTrips.where((t) => t.status == 'published').toList();
        final draftTrips = allTrips.where((t) => t.status == 'draft' && !(t.isSurprise && t.userId == _userId)).toList();
        // Sorpresas que tú preparas para tus amigos (aún sin publicar)
        final mySurpriseDrafts = allTrips.where((t) => t.status == 'draft' && t.isSurprise && t.userId == _userId).toList();

        final unopenedSurprises = _surpriseTrips.where((t) {
          if (hidden.contains(t.id)) return false;
          final bool isOpened = t.surpriseOpenedBy.contains(_userId);
          return !isOpened;
        }).toList();

        Widget? surpriseSection;
        if (unopenedSurprises.isNotEmpty) {
          surpriseSection = _buildSurprisePlansSection(unopenedSurprises, crossAxisCount, width, padding, isDark);
        }

        final int planCount = draftTrips.length + mySurpriseDrafts.length + unopenedSurprises.length;

        // Revisa comentarios nuevos en los viajes publicados (una vez por sesión)
        for (final t in publishedTrips) {
          TripActivity.instance.check(t);
        }
        final bool publishedNews = publishedTrips.any((t) => TripActivity.instance.tripsWithNews.contains(t.id));
        final bool plansNews = _newJobIds.isNotEmpty || unopenedSurprises.any((t) => !_isSurpriseLocked(t));
        final bool isMobileHeader = width <= 600;
        String summary;
        if (_isLoading) {
          summary = 'Cargando tus viajes…';
        } else if (publishedTrips.isEmpty && planCount + _readyJobCount == 0) {
          summary = 'Organiza y comparte tus caminos';
        } else {
          final parts = <String>[
            '${publishedTrips.length} ${publishedTrips.length == 1 ? 'publicado' : 'publicados'}',
            '${planCount + _readyJobCount} ${planCount + _readyJobCount == 1 ? 'plan' : 'planes'}',
          ];
          summary = parts.join(' · ');
        }

        // Si aún no hay viajes publicados, abre directo en Planes (donde está lo que estás armando)
        return DefaultTabController(
          key: ValueKey('tabs-$_isLoading'),
          length: 2,
          initialIndex: (!_isLoading && publishedTrips.isEmpty && planCount > 0) ? 1 : 0,
          child: Scaffold(
            backgroundColor: OhtliColors.cloudDancer,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              centerTitle: false,
              titleSpacing: 0,
              toolbarHeight: isMobileHeader ? 104 : 128,
              title: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_rounded, size: 14, color: OhtliColors.accentText),
                              const SizedBox(width: 6),
                              Text('TU LIBRETA DE CAMINOS', style: OhtliUi.eyebrow(OhtliColors.accentText)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Mis viajes', style: OhtliUi.title(size: isMobileHeader ? 28 : 38)),
                          const SizedBox(height: 4),
                          Text(summary, style: OhtliUi.body(size: isMobileHeader ? 13.5 : 15)),
                        ],
                      ),
                    ),

                    // Dos formas claras de empezar (escritorio / tablet)
                    if (!isMobileHeader)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OhtliSecondaryButton(
                            label: 'Crear plan',
                            icon: Icons.add_rounded,
                            onPressed: () => _showCreateTripDialog(context),
                          ),
                          const SizedBox(width: 10),
                          OhtliPrimaryButton(
                            label: 'Planear con IA',
                            icon: Icons.auto_awesome_rounded,
                            onPressed: _openAiPlanner,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: OhtliColors.stormyTeal,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 5))],
                    ),
                    splashBorderRadius: BorderRadius.circular(30),
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.only(bottom: 12),
                    labelColor: Colors.white,
                    unselectedLabelColor: OhtliColors.onyx.withValues(alpha: 0.65),
                    labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                    unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                    tabs: [
                      Tab(height: 42, child: _tabLabel('Publicados', _isLoading ? 0 : publishedTrips.length, publishedNews)),
                      Tab(height: 42, child: _tabLabel('Planes', _isLoading ? 0 : planCount + _readyJobCount, plansNews)),
                    ],
                  ),
                ),
              ),
            ),
            body: Stack(
              children: [
                _isLoading
                    ? _buildSkeletonGrid(crossAxisCount, width, padding)
                    : TabBarView(
                        children: [
                          // --- TAB: PUBLICADOS ---
                          _buildTripsList(
                            publishedTrips,
                            'Aún no has publicado viajes',
                            planCount > 0
                                ? 'Cuando termines uno de tus planes, publícalo para que otros vean tu recorrido.'
                                : 'Cuando termines un plan, podrás publicarlo para que todo el mundo vea tu recorrido.',
                            crossAxisCount,
                            padding,
                            width,
                            showGoToPlans: planCount > 0,
                          ),

                          // --- TAB: PLANES (Borradores & Opciones de Viaje IA) ---
                          StreamBuilder<QuerySnapshot>(
                            // Consulta acotada al usuario: las reglas solo permiten leer jobs propios.
                            stream: FirebaseFirestore.instance
                                .collection('itinerary_jobs')
                                .where('user_id', isEqualTo: _userId ?? FirebaseAuth.instance.currentUser?.uid ?? '__none__')
                                .snapshots(),
                            builder: (context, aiSnap) {
                              final currentUid = _userId ?? FirebaseAuth.instance.currentUser?.uid;
                              final List<QueryDocumentSnapshot> aiJobs = [];

                              if (aiSnap.hasData && currentUid != null) {
                                for (final doc in aiSnap.data!.docs) {
                                  final data = doc.data() as Map<String, dynamic>? ?? {};
                                  final docUid = (data['user_id'] ??
                                          data['userId'] ??
                                          (data['request'] is Map
                                              ? (data['request']['user_id'] ?? data['request']['userId'])
                                              : null))
                                      ?.toString();
                                  if (docUid == currentUid) {
                                    aiJobs.add(doc);
                                  }
                                }

                                aiJobs.sort((a, b) {
                                  final aData = a.data() as Map<String, dynamic>;
                                  final bData = b.data() as Map<String, dynamic>;
                                  final aTime = aData['created_at'];
                                  final bTime = bData['created_at'];
                                  if (aTime is Timestamp && bTime is Timestamp) {
                                    return bTime.compareTo(aTime);
                                  }
                                  return 0;
                                });
                              }

                              if (draftTrips.isEmpty && mySurpriseDrafts.isEmpty && unopenedSurprises.isEmpty && aiJobs.isEmpty) {
                                return _buildTripsList(
                                  [],
                                  'Tu libreta de caminos está vacía',
                                  'Pide 3 rutas a la IA según tus gustos o arma tu propio plan desde cero.',
                                  crossAxisCount,
                                  padding,
                                  width,
                                );
                              }

                              return ListView(
                                padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
                                children: [
                                  if (aiJobs.isNotEmpty) ...[
                                    _buildAiTriadsSection(aiJobs, width, isDark, padding),
                                  ],
                                  if (surpriseSection != null) ...[
                                    surpriseSection,
                                    const SizedBox(height: 24),
                                  ],
                                  if (mySurpriseDrafts.isNotEmpty) ...[
                                    _buildSectionHeader(
                                      'Sorpresas que preparas',
                                      subtitle: 'Viajes que estás armando para regalar. Tus amigos los abrirán en la fecha que elegiste.',
                                      leading: const Icon(Icons.card_giftcard_rounded, size: 18, color: OhtliColors.xoconostle),
                                      trailing: _countBadge(mySurpriseDrafts.length, OhtliColors.xoconostle),
                                    ),
                                    _buildTripsGrid(mySurpriseDrafts, crossAxisCount, width, padding),
                                    const SizedBox(height: 28),
                                  ],
                                  if (draftTrips.isNotEmpty) ...[
                                    _buildSectionHeader(
                                      'Borradores',
                                      subtitle: 'Los planes que estás armando. Publícalos cuando estén listos.',
                                      trailing: _countBadge(draftTrips.length, OhtliColors.cempasuchil),
                                    ),
                                    _buildTripsGrid(draftTrips, crossAxisCount, width, padding),
                                    const SizedBox(height: 80),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
              ],
            ),
            
            // Móvil: un solo botón que ofrece IA o plan manual
            floatingActionButton: isMobileHeader
                ? FloatingActionButton.extended(
                    onPressed: _showNewTripSheet,
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text('Nuevo viaje', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildAiTriadsSection(
    List<QueryDocumentSnapshot> aiJobs,
    double width,
    bool isDark,
    double padding,
  ) {
    if (aiJobs.isEmpty) return const SizedBox.shrink();

    final generatingJobs = <QueryDocumentSnapshot>[];
    final failedJobs = <QueryDocumentSnapshot>[];
    final completedJobs = <QueryDocumentSnapshot>[];

    for (final doc in aiJobs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      final progress = (data['progress_percent'] as num?)?.toInt() ?? 0;
      final res = data['result'] as Map<String, dynamic>? ?? {};
      final options = (res['options'] as List<dynamic>?) ?? [];
      final hasCreatedTrip = data['created_trip_id'] != null || status == 'chosen';

      // Si la opción ya fue elegida y convertida a viaje, NO debe aparecer como en curso
      if (hasCreatedTrip) {
        continue;
      }

      if ((status == 'completed' || progress >= 100 || options.isNotEmpty) && options.isNotEmpty) {
        completedJobs.add(doc);
      } else if (status == 'failed' || status == 'error' || status == 'completed') {
        // Antes los fallidos desaparecían sin aviso; ahora se muestran con opción de reintentar
        failedJobs.add(doc);
      } else if (status != 'dismissed') {
        generatingJobs.add(doc);
      }
    }

    if (generatingJobs.isEmpty && completedJobs.isEmpty && failedJobs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==========================================
        // 1. JOBS EN PROCESO DE GENERACIÓN CON IA
        // ==========================================
        if (generatingJobs.isNotEmpty) ...[
          _buildSectionHeader(
            'En preparación',
            subtitle: 'Estamos armando tus rutas. Puedes salir y volver: seguirá avanzando.',
            leading: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.cempasuchil)),
            ),
            trailing: _countBadge(generatingJobs.length, OhtliColors.cempasuchil),
          ),
          Column(
            children: generatingJobs.map((doc) => _buildGeneratingJobCard(doc, isDark)).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // ==========================================
        // 1.b JOBS QUE NO SE PUDIERON COMPLETAR
        // ==========================================
        if (failedJobs.isNotEmpty) ...[
          _buildSectionHeader(
            'No se pudieron generar',
            leading: const Icon(Icons.error_outline_rounded, size: 18, color: OhtliColors.xoconostle),
          ),
          Column(
            children: failedJobs.map((doc) => _buildFailedJobCard(doc, isDark)).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // ==========================================
        // 2. OPCIONES DE VIAJE COMPLETADAS Y LISTAS
        // ==========================================
        if (completedJobs.isNotEmpty) ...[
          _buildSectionHeader(
            'Listos para elegir',
            subtitle: 'Compara las 3 rutas y quédate con tu favorita cuando quieras.',
            leading: const Icon(Icons.auto_awesome_rounded, size: 18, color: OhtliColors.stormyTeal),
            trailing: _countBadge(completedJobs.length, OhtliColors.stormyTeal, filled: true),
          ),

          // Tarjetas de opciones listas: mismo ancho y rejilla que los viajes
          Builder(builder: (context) {
            final int crossAxisCount = width > 1500 ? 5 : (width > 1100 ? 4 : (width > 760 ? 3 : (width > 520 ? 2 : 1)));
            final double cardWidth = (width - padding * 2 - (crossAxisCount - 1) * 18) / crossAxisCount;
            final double cardHeight = crossAxisCount == 1 ? 300.0 : (cardWidth * 0.6) + 112.0;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Las fotos sobresalen por arriba de cada tarjeta: espacio y sin recorte
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(top: 30),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 40,
                crossAxisSpacing: 18,
                childAspectRatio: cardWidth / cardHeight,
              ),
              itemCount: completedJobs.length,
              itemBuilder: (context, i) => _buildReadyJobCard(completedJobs[i], isDark),
            );
          }),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildReadyJobCard(QueryDocumentSnapshot doc, bool isDark) {
    final data = doc.data() as Map<String, dynamic>;
    final req = data['request'] as Map<String, dynamic>? ?? {};
    final originName = (data['origin_name'] ?? req['origin_name'] ?? req['mood_text'] ?? 'Ciudad de México').toString();
    final budget = (req['budget'] as num?)?.toDouble() ?? 500.0;
    final res = data['result'] as Map<String, dynamic>? ?? {};
    final options = (res['options'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    final isNew = _newJobIds.contains(doc.id);

    // Primera foto de cada ruta
    final photos = <String>[];
    for (var i = 0; i < options.length && photos.length < 3; i++) {
      final route = options[i]['route'] as List<dynamic>? ?? const [];
      String? url;
      for (final stop in route) {
        if (stop is! Map) continue;
        final raw = (stop['photo_url'] ?? stop['main_photo_url'] ?? stop['image_url'] ?? stop['photo'] ?? '').toString().trim();
        if (raw.isNotEmpty) {
          url = raw;
          break;
        }
      }
      url ??= CdmxPhotos.forCategory((route.isNotEmpty && route.first is Map ? (route.first as Map)['category'] : '')?.toString(), i);
      photos.add(url);
    }

    void open() {
      TripActivity.instance.markJobSeen(doc.id);
      TripPlannerDialog.show(context, initialGeneratedOptions: options, optionsJobId: doc.id, originName: originName);
    }

    return _HoverCard(
      onTap: open,
      highlight: isNew,
      inGrid: true,
      builder: (hover) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fotos apiladas (una por ruta), igual que en el visor
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: PolaroidDesk(borderRadius: BorderRadius.circular(20), child: const SizedBox.expand())),
                // Las tres fotos (una por ruta) se salen por la parte de arriba del recuadro
                Positioned(left: 0, right: 0, top: -30, bottom: 8, child: PolaroidStack(photos: photos, spread: hover, scale: 1.0, align: 1, fillWidthFraction: 0.68)),
                Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isNew ? OhtliColors.xoconostle : Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 12, color: isNew ? Colors.white : OhtliColors.accentText),
                          const SizedBox(width: 5),
                          Text(isNew ? 'Nuevo · IA' : 'Plan con IA',
                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: isNew ? Colors.white : OhtliColors.accentText)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 0, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rutas desde $originName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.2, height: 1.15)),
                const SizedBox(height: 2),
                Text(options.take(3).map((o) => (o['theme'] ?? o['editorial_headline'] ?? 'Ruta').toString()).join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: OhtliColors.subtleText)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          OhtliMetaPill(icon: Icons.payments_outlined, label: '\$${budget.toStringAsFixed(0)} MXN por persona'),
                        ]),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 19, color: OhtliColors.onyx.withValues(alpha: 0.45)),
                      tooltip: 'Descartar rutas',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        FeedbackService.itineraryDiscarded(doc.id, reason: 'descartar');
                        _discardJobWithUndo(doc, message: 'Rutas descartadas');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedJobCard(QueryDocumentSnapshot doc, bool isDark) {
    final data = doc.data() as Map<String, dynamic>;
    final req = data['request'] as Map<String, dynamic>? ?? {};
    final originName = (data['origin_name'] ?? req['origin_name'] ?? 'Ciudad de México').toString();
    final status = (data['status'] ?? '').toString();
    final reason = status == 'completed'
        ? 'No encontramos lugares que encajen con esas preferencias.'
        : 'Hubo un problema al calcular la ruta.';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OhtliColors.xoconostle.withOpacity(0.35), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: OhtliColors.xoconostle.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.route_outlined, size: 18, color: OhtliColors.xoconostle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan desde $originName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white60 : OhtliColors.subtleText),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => TripPlannerDialog.show(context, originName: originName),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text('Intentar de nuevo', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OhtliColors.stormyTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          FeedbackService.itineraryDiscarded(doc.id, reason: 'descartar');
                          await doc.reference.set({'status': 'dismissed'}, SetOptions(merge: true));
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyError(e), style: GoogleFonts.inter()), backgroundColor: OhtliColors.xoconostle),
                          );
                        }
                      },
                      child: Text('Descartar', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingJobCard(QueryDocumentSnapshot doc, bool isDark) {
    final data = doc.data() as Map<String, dynamic>;
    final req = data['request'] as Map<String, dynamic>? ?? {};
    final originName = (data['origin_name'] ?? req['origin_name'] ?? req['mood_text'] ?? 'Ciudad de México').toString();
    final progress = (data['progress_percent'] as num?)?.toInt() ?? 20;
    final agent = (data['current_agent'] ?? 'comparador').toString();

    String agentStageText;
    if (agent.toLowerCase().contains('comparador')) {
      agentStageText = 'Buscando lugares que van con tu estilo...';
    } else if (agent.toLowerCase().contains('generador')) {
      agentStageText = 'Trazando el recorrido y los traslados...';
    } else if (agent.toLowerCase().contains('recomendador')) {
      agentStageText = 'Dando los últimos toques a cada propuesta...';
    } else {
      agentStageText = 'Preparando tus rutas...';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OhtliColors.cempasuchil.withOpacity(0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: OhtliColors.cempasuchil.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 460;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Rutas desde $originName',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : OhtliColors.onyx,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$progress%',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: OhtliColors.cempasuchil),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  agentStageText,
                  style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white60 : OhtliColors.subtleText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () {
                    TripPlannerDialog.show(
                      context,
                      initialActiveJobId: doc.id,
                      originName: originName,
                    );
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: Text('Ver avance', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.45)),
                  tooltip: 'Cancelar',
                  onPressed: () => _discardJobWithUndo(doc, message: 'Generación cancelada'),
                ),
              ],
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, Align(alignment: Alignment.centerRight, child: actions)],
              );
            }
            return Row(children: [Expanded(child: title), const SizedBox(width: 8), actions]);
          }),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (progress.clamp(5, 100)) / 100.0,
              minHeight: 4,
              backgroundColor: OhtliColors.cempasuchil.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(OhtliColors.cempasuchil),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripsList(
    List<Trip> trips,
    String emptyTitle,
    String emptySub,
    int crossAxisCount,
    double padding,
    double availableWidth, {
    bool showGoToPlans = false,
  }) {
    if (trips.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OhtliServiceIcon(icon: showGoToPlans ? Icons.edit_note_rounded : Icons.map_rounded, color: OhtliColors.stormyTeal, size: 72),
                const SizedBox(height: 22),
                Text(emptyTitle, textAlign: TextAlign.center, style: OhtliUi.title(size: 24)),
                const SizedBox(height: 8),
                Text(emptySub, textAlign: TextAlign.center, style: OhtliUi.body(size: 14)),
                const SizedBox(height: 26),
                if (showGoToPlans)
                  Builder(
                    builder: (tabContext) => OhtliPrimaryButton(
                      label: 'Ver mis planes',
                      icon: Icons.edit_note_rounded,
                      onPressed: () => DefaultTabController.of(tabContext).animateTo(1),
                    ),
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OhtliPrimaryButton(label: 'Planear con IA', icon: Icons.auto_awesome_rounded, onPressed: _openAiPlanner),
                      OhtliSecondaryButton(label: 'Crear plan', icon: Icons.add_rounded, onPressed: () => _showCreateTripDialog(context)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Calculate the width of a single card
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 18) / crossAxisCount;
    
    // Calculate aspect ratio dynamically to prevent vertical text overflows:
    // - If it's a mobile 1-column layout, we want a compact horizontal card of fixed height (125px).
    // - Otherwise, standard vertical layout where height = (cardWidth * 9 / 16) + 168px (to perfectly fit paddings, titles, descriptions, and dual dates without overflow!).
    final double cardHeight = crossAxisCount == 1
        ? 112.0
        : (cardWidth * 0.6) + 112.0;
    
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, 20, padding, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
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

        final tripCard = TripCard(
          trip: trip,
          isHorizontal: crossAxisCount == 1,
          disable3D: trip.isSurprise,
          addedByName: isCoAuthored ? (authorProfile?['name'] ?? 'Cargando...') : null,
          addedByPhotoURL: isCoAuthored ? (authorProfile?['photo']) : null,
          hasNews: TripActivity.instance.tripsWithNews.contains(trip.id),
          newsLabel: 'Comentario nuevo',
          onEdit: () => _openTrip(trip),
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

        return tripCard;
      },
    );
  }

  Widget _buildTripsGrid(List<Trip> trips, int crossAxisCount, double availableWidth, double padding) {
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 18) / crossAxisCount;
    final double cardHeight = crossAxisCount == 1
        ? 112.0
        : (cardWidth * 0.6) + 112.0;
    
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
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

        final tripCard = TripCard(
          trip: trip,
          isHorizontal: crossAxisCount == 1,
          disable3D: false,
          addedByName: isCoAuthored ? (authorProfile?['name'] ?? 'Cargando...') : null,
          addedByPhotoURL: isCoAuthored ? (authorProfile?['photo']) : null,
          hasNews: TripActivity.instance.tripsWithNews.contains(trip.id),
          newsLabel: 'Comentario nuevo',
          onEdit: () => _openTrip(trip),
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

        return tripCard;
      },
    );
  }

  Widget _buildSurprisePlansSection(List<Trip> surpriseTrips, int crossAxisCount, double availableWidth, double padding, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Sorpresas por abrir',
          subtitle: 'Viajes que tus amigos prepararon para ti. Ábrelos cuando llegue el día.',
          leading: const Icon(Icons.card_giftcard_rounded, size: 18, color: OhtliColors.xoconostle),
          trailing: _countBadge(surpriseTrips.length, OhtliColors.xoconostle),
        ),
        _buildSurpriseTripsGrid(surpriseTrips, crossAxisCount, availableWidth, padding, isDark),
      ],
    );
  }

  Widget _buildSurpriseTripsGrid(List<Trip> trips, int crossAxisCount, double availableWidth, double padding, bool isDark) {
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 18) / crossAxisCount;
    final double cardHeight = crossAxisCount == 1
        ? 112.0
        : (cardWidth * 0.6) + 112.0;
    
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: computedAspectRatio,
      ),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final DateTime? unlockDate = trip.surpriseUnlockDates[_userId];
        bool isLocked = true;
        if (trip.unlockOnPublish) {
          isLocked = trip.status != 'published';
        } else if (unlockDate != null) {
          isLocked = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
              .isBefore(DateTime(unlockDate.year, unlockDate.month, unlockDate.day));
        } else {
          isLocked = false;
        }
        
        final bool isOpened = trip.surpriseOpenedBy.contains(_userId);

        if (!_authorProfilesCache.containsKey(trip.userId)) {
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
        
        final authorProfile = _authorProfilesCache[trip.userId];
        final String authorName = authorProfile?['name'] ?? 'Un amigo';

        final Widget surpriseCard = SurprisePolaroidCard(
          trip: trip,
          isLocked: isLocked,
          unlockDate: unlockDate,
          fromName: authorName,
          fromPhotoUrl: authorProfile?['photo'],
          isHorizontal: crossAxisCount == 1,
          onRemove: () => _hideTrip(trip),
          onOpen: () async {
            final uid = _userId;
            if (uid != null && !isOpened) {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(trip.userId)
                    .collection('trips')
                    .doc(trip.id)
                    .update({'surpriseOpenedBy': FieldValue.arrayUnion([uid])});
              } catch (e) {
                print("Error updating opened surprise state: $e");
              }
            }
            if (mounted) _openTrip(trip);
          },
        );

        if (crossAxisCount == 1) {
          return SizedBox(height: 112.0, child: surpriseCard);
        }
        return surpriseCard;
      },
    );
  }
}

/// Tarjeta blanca con elevación al pasar el cursor (y aviso de novedad).
class _HoverCard extends StatefulWidget {
  final Widget Function(bool hover) builder;
  final VoidCallback onTap;
  final bool highlight;
  final bool inGrid;
  const _HoverCard({required this.builder, required this.onTap, this.highlight = false, this.inGrid = false});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(bottom: widget.inGrid ? 0 : 12),
          padding: const EdgeInsets.all(6),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: widget.highlight ? OhtliColors.xoconostle.withValues(alpha: 0.55) : (_hover ? OhtliColors.stormyTeal.withValues(alpha: 0.35) : OhtliColors.cardBorder),
              width: widget.highlight ? 1.4 : 1,
            ),
            boxShadow: OhtliUi.softShadow(color: _hover ? OhtliColors.stormyTeal : null, raised: _hover),
          ),
          child: widget.builder(_hover),
        ),
      ),
    );
  }
}

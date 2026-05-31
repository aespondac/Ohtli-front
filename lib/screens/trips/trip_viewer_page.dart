import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_place_photo_stack.dart';
import '../../widgets/ohtli_markdown_renderer.dart';
import '../../services/markdown_helpers.dart';
import '../../widgets/ohtli_sidebar.dart';
import '../home_page.dart';
import '../account/account_management_page.dart';
import 'trip_editor_page.dart';

class TripViewerPage extends StatefulWidget {
  final Trip? trip;
  final String? tripId;
  final String? authorId;
  final bool isPublicLink;
  final VoidCallback? onLoginRedirect;
  final VoidCallback? onBackToDashboard;

  const TripViewerPage({
    super.key,
    this.trip,
    this.tripId,
    this.authorId,
    this.isPublicLink = false,
    this.onLoginRedirect,
    this.onBackToDashboard,
  });

  @override
  State<TripViewerPage> createState() => _TripViewerPageState();
}

class _TripViewerPageState extends State<TripViewerPage> {
  Trip? _trip;
  List<TripSection> _sections = [];
  Map<String, dynamic>? _authorProfile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTripData();
  }

  Future<void> _loadTripData() async {
    if (widget.trip != null) {
      _trip = widget.trip;
      await Future.wait([
        _loadTripContent(),
        _loadAuthorProfile(),
      ]);
    } else if (widget.tripId != null && widget.authorId != null) {
      try {
        final fetchedTrip = await TripService().getTrip(widget.authorId!, widget.tripId!);
        if (fetchedTrip != null) {
          _trip = fetchedTrip;
          await Future.wait([
            _loadTripContent(),
            _loadAuthorProfile(),
          ]);
        } else {
          setState(() {
            _errorMessage = "No se pudo encontrar el viaje. Puede que sea privado o haya sido eliminado.";
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = "Error al conectar con la base de datos: $e";
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _errorMessage = "Datos de consulta insuficientes para cargar la historia.";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAuthorProfile() async {
    if (_trip == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_trip!.userId).get();
      if (doc.exists && mounted) {
        setState(() {
          _authorProfile = doc.data();
        });
      }
    } catch (e) {
      print("Error loading author profile: $e");
    }
  }

  Future<void> _loadTripContent() async {
    if (_trip == null) return;
    try {
      final content = await TripService().getTripContent(_trip!.userId, _trip!.id);
      if (mounted) {
        setState(() {
          _sections = content?.sections ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error al cargar los bloques de la historia: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _showImageLightbox({
    required List<String> urls,
    required int initialIndex,
    required String title,
  }) {
    if (urls.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      builder: (context) {
        int currentIndex = initialIndex;
        final pageController = PageController(initialPage: initialIndex);

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dismiss gesture on empty space
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // PageView for swiping images
                  PageView.builder(
                    controller: pageController,
                    itemCount: urls.length,
                    onPageChanged: (index) {
                      setState(() {
                        currentIndex = index;
                      });
                    },
                    itemBuilder: (context, idx) {
                      final url = urls[idx];
                      final provider = _getImageProvider(url);
                      return GestureDetector(
                        onTap: () {},
                        child: Center(
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 3.0,
                            child: Container(
                              constraints: BoxConstraints(
                                maxHeight: MediaQuery.of(context).size.height * 0.75,
                                maxWidth: MediaQuery.of(context).size.width * 0.9,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image(
                                  image: provider,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Close Button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black45,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  // Left Arrow for Desktop/Web
                  if (urls.length > 1 && currentIndex > 0)
                    Positioned(
                      left: 16,
                      child: GestureDetector(
                        onTap: () {
                          pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                          ),
                          child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  // Right Arrow for Desktop/Web
                  if (urls.length > 1 && currentIndex < urls.length - 1)
                    Positioned(
                      right: 16,
                      child: GestureDetector(
                        onTap: () {
                          pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                          ),
                          child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  // Page indicator & Title at the bottom
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (urls.length > 1) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "${currentIndex + 1} de ${urls.length}",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('data:')) {
      final String base64Data = url.split(',').last;
      return MemoryImage(base64Decode(base64Data));
    }
    return NetworkImage(url);
  }

  double _calculateTableTotal(TableData tableData, int colIdx) {
    double total = 0.0;
    for (int r = 0; r < tableData.rows.length; r++) {
      final valStr = tableData.rows[r][colIdx];
      final cleanStr = valStr.replaceAll(RegExp(r'[^\d.-]'), '');
      final double? val = double.tryParse(cleanStr);
      if (val != null) {
        total += val;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 800;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: OhtliColors.stormyTeal,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Cargando historia...",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : OhtliColors.onyx,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: OhtliColors.xoconostle, size: 48),
                const SizedBox(height: 16),
                Text(
                  "¡Vaya! Ocurrió un inconveniente",
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: OhtliColors.xoconostle,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: widget.onBackToDashboard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Volver al Dashboard"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    final bool hasActiveSession = currentUser != null;
    final bool showTopNavbar = widget.isPublicLink;
    final bool isOwner = currentUser != null && _trip != null && _trip!.userId == currentUser.uid;

    final Widget mainScrollableContent = SingleChildScrollView(
      child: Column(
        children: [
          _buildCoverHeader(isDark, isDesktop),
          const SizedBox(height: 36),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _sections.length,
                    itemBuilder: (context, index) {
                      return _buildBlockCard(_sections[index], isDark, isDesktop, index);
                    },
                  ),
                  _buildErrataHistorySection(isDark),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );

    final Widget bodyContent = Row(
      children: [
        if (isDesktop && !widget.isPublicLink && hasActiveSession)
          OhtliSidebar(
            currentIndex: 1,
            onTabSelected: (index) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => HomePage(
                    initialIndex: index,
                    onLogout: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    onNavigateToAccount: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AccountManagementPage(
                            onBackToHome: (idx) {
                              Navigator.pop(context);
                            },
                            onLogout: () async {
                              await FirebaseAuth.instance.signOut();
                              Navigator.pushReplacementNamed(context, '/login');
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            onNavigateToAccount: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AccountManagementPage(
                    onBackToHome: (idx) {
                      Navigator.pop(context);
                    },
                    onLogout: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                  ),
                ),
              );
            },
            onLogout: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        Expanded(
          child: Stack(
            children: [
              mainScrollableContent,
              if (!widget.isPublicLink && !isDesktop)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: GestureDetector(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else if (widget.onBackToDashboard != null) {
                        widget.onBackToDashboard!();
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1E1E22) : Colors.white).withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : OhtliColors.onyx,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      appBar: showTopNavbar ? _buildPublicNavbar(hasActiveSession, isDark) : null,
      body: bodyContent,
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TripEditorPage(trip: _trip!),
                  ),
                ).then((_) {
                  _loadTripData();
                });
              },
              backgroundColor: OhtliColors.xoconostle,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: const Icon(Icons.history_edu_rounded, size: 20),
              label: Text(
                'Fe de Erratas',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildPublicNavbar(bool isLoggedIn, bool isDark) {
    return AppBar(
      title: SvgPicture.asset(
        'assets/logo.svg',
        height: 22,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
      ),
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      elevation: 0.5,
      actions: [
        if (isLoggedIn)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: OutlinedButton.icon(
              onPressed: widget.onBackToDashboard,
              icon: const Icon(Icons.dashboard_rounded, size: 14),
              label: Text(
                'Mis Viajes',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: OhtliColors.stormyTeal,
                side: const BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: widget.onLoginRedirect,
              icon: const Icon(Icons.login_rounded, size: 14),
              label: Text(
                'Iniciar Sesión',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAuthorWidget(String name, String? photoUrl, String role, bool isDark) {
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Escrito por",
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : OhtliColors.onyx,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              role,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: OhtliColors.stormyTeal,
          ),
          child: ClipOval(
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image(
                    image: _getImageProvider(photoUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        initials,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrataHistorySection(bool isDark) {
    final errata = _trip?.errataHistory ?? [];
    if (errata.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Divider(color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3), height: 40),
        Row(
          children: [
            const Icon(Icons.history_edu_rounded, color: OhtliColors.xoconostle, size: 20),
            const SizedBox(width: 8),
            Text(
              "Notas de Cambios y Fe de Erratas",
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : OhtliColors.onyx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...errata.reversed.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF231E1E) : const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF5A2C2C) : const Color(0xFFFEE2E2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Corrección publicada",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: OhtliColors.xoconostle,
                      ),
                    ),
                    Text(
                      "${entry.date.day}/${entry.date.month}/${entry.date.year}",
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  entry.note,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : OhtliColors.onyx,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _formatSpanishDate(DateTime? date) {
    if (date == null) return 'Sin fecha de viaje';
    final months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;
    return 'el $day de $month del $year';
  }

  Widget _buildCoverHeader(bool isDark, bool isDesktop) {
    final String cover = _trip?.coverUrl ?? '';
    final String title = _trip?.title ?? 'Sin Título';
    final String desc = _trip?.description ?? '';

    final String authorName = _authorProfile?['displayName'] ?? 'Viajero Ohtli';
    final String? authorPhoto = _authorProfile?['photoURL'];
    final String authorRole = 'Viajero';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover.isNotEmpty)
            Container(
              width: double.infinity,
              height: isDesktop ? 500 : 320,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: _getImageProvider(cover),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.outfit(
                                fontSize: isDesktop ? 32 : 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? OhtliColors.cantera : OhtliColors.onyx,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatSpanishDate(_trip?.travelDate),
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              OhtliMarkdownText(
                                text: desc,
                                style: GoogleFonts.inter(
                                  fontSize: 14.5,
                                  color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.7),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isDesktop) ...[
                        const SizedBox(width: 32),
                        _buildAuthorWidget(authorName, authorPhoto, authorRole, isDark),
                      ],
                    ],
                  ),
                  if (!isDesktop) ...[
                    const SizedBox(height: 20),
                    _buildAuthorWidget(authorName, authorPhoto, authorRole, isDark),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockCard(TripSection section, bool isDark, bool isDesktop, int index) {
    Widget blockContent = const SizedBox();

    if (section is PlaceSection) {
      blockContent = _buildPlaceBlockViewer(section, isDark, isDesktop);
    } else if (section is TextSection) {
      final alertData = parseAlertMarkdown(section.markdownText);
      final tableData = parseTableMarkdown(section.markdownText);

      if (alertData != null) {
        blockContent = _buildAlertBlockViewer(alertData, isDark);
      } else if (tableData != null) {
        blockContent = _buildTableBlockViewer(tableData, isDark);
      } else {
        blockContent = _buildTextBlockViewer(section, isDark);
      }
    } else if (section is TextImageSection) {
      blockContent = _buildTextImageBlockViewer(section, isDark, isDesktop);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: blockContent,
    );
  }

  Widget _buildPlaceBlockViewer(PlaceSection place, bool isDark, bool isDesktop) {
    // Collect active photo urls
    final List<Map<String, dynamic>> drawOrderSlots = [];
    final List<String> activeUrls = [];
    if (place.mainPhotoUrl.isNotEmpty) {
      drawOrderSlots.add({'url': place.mainPhotoUrl, 'type': 'place_main'});
      activeUrls.add(place.mainPhotoUrl);
    }
    for (int i = 0; i < place.secondaryPhotoUrls.length; i++) {
      final url = place.secondaryPhotoUrls[i];
      if (url.isNotEmpty) {
        drawOrderSlots.add({'url': url, 'type': 'place_sec_$i'});
        activeUrls.add(url);
      }
    }

    // Sort to guarantee correct stack rendering depth (main is front, sec_0 is middle, sec_1 is back)
    drawOrderSlots.sort((a, b) {
      final tA = a['type'] as String;
      final tB = b['type'] as String;
      if (tA == 'place_sec_1') return -1;
      if (tA == 'place_sec_0' && tB == 'place_main') return -1;
      return 1;
    });

    final Widget photoStackWidget = drawOrderSlots.isNotEmpty
        ? OhtliPlacePhotoStack(
            drawOrderSlots: drawOrderSlots,
            isDark: isDark,
            slotBuilder: (slot, _) {
              final String currentUrl = slot['url'] as String;
              final int clickedIndex = activeUrls.indexOf(currentUrl);
              final ImageProvider provider = _getImageProvider(currentUrl);
              return GestureDetector(
                onTap: () => _showImageLightbox(
                  urls: activeUrls,
                  initialIndex: clickedIndex >= 0 ? clickedIndex : 0,
                  title: place.title.isNotEmpty ? place.title : 'Fotos del Lugar',
                ),
                child: Hero(
                  tag: 'place_photo_${place.id}_${slot['url']}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      image: DecorationImage(
                        image: provider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          )
        : const SizedBox.shrink();

    final Widget infoWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place.title.isNotEmpty ? place.title : 'Sin Título del Lugar',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 6),
        // Star ratings
        Row(
          children: List.generate(5, (starIdx) {
            final active = starIdx < place.rating;
            return Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              color: active ? Colors.amber : (isDark ? Colors.white24 : OhtliColors.cantera),
              size: 16,
            );
          }),
        ),
        if (place.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          OhtliMarkdownText(
            text: place.description,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
        ],
        // Cost Badge
        if (place.cost > 0.0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF332711) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFFFBBF24).withValues(alpha: 0.25) : const Color(0xFFFDE68A),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.payments_outlined, size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  "Costo estimado: \$ ${place.cost.toStringAsFixed(2)} ${place.currency}",
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (isDesktop && drawOrderSlots.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          photoStackWidget,
          const SizedBox(width: 24),
          Expanded(child: infoWidget),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (drawOrderSlots.isNotEmpty) ...[
          Center(child: photoStackWidget),
          const SizedBox(height: 16),
        ],
        infoWidget,
      ],
    );
  }

  Widget _buildAlertBlockViewer(AlertData alert, bool isDark) {
    Color alertColor = OhtliColors.stormyTeal;
    IconData alertIcon = Icons.info_outline_rounded;
    String alertName = "Nota / Info";
    
    if (alert.type == AlertType.warning) {
      alertColor = OhtliColors.xoconostle;
      alertIcon = Icons.warning_amber_rounded;
      alertName = "Advertencia";
    } else if (alert.type == AlertType.tip) {
      alertColor = OhtliColors.cempasuchil;
      alertIcon = Icons.lightbulb_outline_rounded;
      alertName = "Consejo / Tip";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C32) : alertColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? alertColor.withValues(alpha: 0.3) : alertColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: alertColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(alertIcon, color: alertColor, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                alertName,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: alertColor,
                ),
              ),
            ],
          ),
          if (alert.content.isNotEmpty) ...[
            const SizedBox(height: 10),
            OhtliMarkdownText(
              text: alert.content,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white70 : OhtliColors.onyx,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableBlockViewer(TableData table, bool isDark) {
    final int numCols = table.columns.length;
    final bool showTotalRow = table.columns.any((col) => col.type == 'money' && col.isTotalEnabled);
    final Color headerBg = isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.12);
    final Color cellBorder = isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.25);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Headers
          Row(
            children: List.generate(numCols, (colIdx) {
              final col = table.columns[colIdx];
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cellBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      col.type == 'money'
                          ? Icons.payments_rounded
                          : col.type == 'number'
                              ? Icons.tag_rounded
                              : Icons.text_fields_rounded,
                      size: 11,
                      color: OhtliColors.stormyTeal.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: OhtliMarkdownText(
                        text: col.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                          color: isDark ? Colors.white : OhtliColors.onyx,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          // Rows
          ...List.generate(table.rows.length, (rowIdx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(numCols, (colIdx) {
                  final col = table.columns[colIdx];
                  final bool isMoney = col.type == 'money';
                  final bool isNumber = col.type == 'number';
                  final val = table.rows[rowIdx][colIdx];

                  return Container(
                    width: 150,
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cellBorder),
                    ),
                    child: Align(
                      alignment: (isMoney || isNumber) ? Alignment.centerRight : Alignment.centerLeft,
                      child: isMoney && val.isNotEmpty
                          ? RichText(
                              textAlign: TextAlign.right,
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '\$ ',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  TextSpan(
                                    text: val,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white : OhtliColors.onyx,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${col.currency}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : OhtliMarkdownText(
                              text: val,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: isDark ? Colors.white70 : OhtliColors.onyx,
                              ),
                              textAlign: (isMoney || isNumber) ? TextAlign.right : TextAlign.left,
                            ),
                    ),
                  );
                }),
              ),
            );
          }),
          // Totals Row
          if (showTotalRow) ...[
            const SizedBox(height: 2),
            Row(
              children: List.generate(numCols, (colIdx) {
                final col = table.columns[colIdx];
                final bool isMoneyTotal = col.type == 'money' && col.isTotalEnabled;

                return Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMoneyTotal
                        ? (isDark ? const Color(0xFF2C2C32) : OhtliColors.stormyTeal.withValues(alpha: 0.04))
                        : Colors.transparent,
                    border: isMoneyTotal
                        ? Border(
                            top: BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                            bottom: BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                          )
                        : null,
                  ),
                  child: isMoneyTotal
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total:',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: OhtliColors.stormyTeal,
                              ),
                            ),
                            Text(
                              '\$ ${_calculateTableTotal(table, colIdx).toStringAsFixed(2)} ${col.currency}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : OhtliColors.onyx,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextBlockViewer(TextSection textSec, bool isDark) {
    if (textSec.markdownText.isEmpty) return const SizedBox.shrink();
    return OhtliMarkdownText(
      text: textSec.markdownText,
      style: GoogleFonts.inter(
        fontSize: 13.5,
        color: isDark ? Colors.white70 : OhtliColors.onyx,
        height: 1.5,
      ),
    );
  }

  Widget _buildTextImageBlockViewer(TextImageSection section, bool isDark, bool isDesktop) {
    final Widget imageWidget = section.imageUrl.isNotEmpty
        ? Center(
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _showImageLightbox(
                    urls: [section.imageUrl],
                    initialIndex: 0,
                    title: "Foto adjunta",
                  ),
                  child: Image(
                    image: _getImageProvider(section.imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    final Widget textWidget = section.markdownText.isNotEmpty
        ? OhtliMarkdownText(
            text: section.markdownText,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : OhtliColors.onyx,
              height: 1.5,
            ),
          )
        : const SizedBox.shrink();

    if (isDesktop && section.imageUrl.isNotEmpty) {
      final bool isLeft = section.layout == 'left';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLeft) ...[
            imageWidget,
            const SizedBox(width: 20),
          ],
          Expanded(child: textWidget),
          if (!isLeft) ...[
            const SizedBox(width: 20),
            imageWidget,
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.imageUrl.isNotEmpty) ...[
          imageWidget,
          const SizedBox(height: 14),
        ],
        textWidget,
      ],
    );
  }
}

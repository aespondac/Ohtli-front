import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../theme/colors.dart';
import '../../widgets/image_cropper_dialog.dart';

class TripEditorPage extends StatefulWidget {
  final Trip trip;

  const TripEditorPage({super.key, required this.trip});

  @override
  State<TripEditorPage> createState() => _TripEditorPageState();
}

class _TripEditorPageState extends State<TripEditorPage> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late String _visibility;
  late String _status;
  late String _coverUrl;
  
  List<TripSection> _sections = [];
  bool _isLoadingContent = true;
  bool _isSavingCloud = false;
  
  Timer? _debounceTimer;
  
  // Local changes tracking
  DateTime? _lastSavedCloudTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.trip.title);
    _descriptionController = TextEditingController(text: widget.trip.description);
    _visibility = widget.trip.visibility;
    _status = widget.trip.status;
    _coverUrl = widget.trip.coverUrl;

    _loadCloudContentAndCheckCache();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Double resilient load
  Future<void> _loadCloudContentAndCheckCache() async {
    try {
      final cloudContent = await TripService().getTripContent(widget.trip.userId, widget.trip.id);
      if (cloudContent != null) {
        if (mounted) {
          setState(() {
            _sections = cloudContent.sections;
            _isLoadingContent = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingContent = false;
          });
        }
      }

      // Check browser localStorage for newer local cache
      _checkLocalCache();
    } catch (e) {
      print("Error loading cloud content: $e");
      if (mounted) {
        setState(() {
          _isLoadingContent = false;
        });
      }
      _checkLocalCache();
    }
  }

  void _checkLocalCache() {
    if (!kIsWeb) return;

    try {
      final String? cachedStr = html.window.localStorage['ohtli_trip_draft_${widget.trip.id}'];
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        final int localUpdatedAt = decoded['updatedAt'] ?? 0;
        final int cloudUpdatedAt = widget.trip.updatedAt.millisecondsSinceEpoch;

        // If local draft is newer by more than 1 second, offer recovery
        if (localUpdatedAt > (cloudUpdatedAt + 1000)) {
          _showRecoveryDialog(decoded);
        }
      }
    } catch (e) {
      print("Error checking local cache: $e");
    }
  }

  void _showRecoveryDialog(Map<String, dynamic> cache) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: OhtliColors.cloudDancer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Borrador local detectado',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: OhtliColors.onyx,
            ),
          ),
          content: Text(
            'Hemos encontrado un borrador local en este navegador con cambios más recientes que los guardados en la nube. ¿Deseas recuperar tus últimos cambios?',
            style: GoogleFonts.inter(
              color: OhtliColors.onyx.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _discardLocalCache();
              },
              child: Text(
                'Descartar',
                style: GoogleFonts.inter(
                  color: OhtliColors.xoconostle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _applyLocalCache(cache);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Recuperar',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _applyLocalCache(Map<String, dynamic> cache) {
    setState(() {
      if (cache['trip'] != null) {
        _titleController.text = cache['trip']['title'] ?? _titleController.text;
        _descriptionController.text = cache['trip']['description'] ?? _descriptionController.text;
        _coverUrl = cache['trip']['coverUrl'] ?? _coverUrl;
        _visibility = cache['trip']['visibility'] ?? _visibility;
        _status = cache['trip']['status'] ?? _status;
      }
      if (cache['content'] != null) {
        _sections = TripContent.fromMap(cache['content']).sections;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Borrador recuperado exitosamente.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.stormyTeal,
      ),
    );
  }

  void _discardLocalCache() {
    if (kIsWeb) {
      html.window.localStorage.remove('ohtli_trip_draft_${widget.trip.id}');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Borrador local descartado.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.xoconostle,
      ),
    );
  }

  // Local caching & debounced auto-save triggers
  void _onDataChanged() {
    _saveToLocalCache();
  }

  void _saveToLocalCache() {
    if (!kIsWeb) return;

    try {
      final now = DateTime.now();
      final cacheData = {
        'updatedAt': now.millisecondsSinceEpoch,
        'trip': {
          'title': _titleController.text,
          'description': _descriptionController.text,
          'coverUrl': _coverUrl,
          'visibility': _visibility,
          'status': _status,
        },
        'content': {
          'sections': _sections.map((s) => s.toMap()).toList(),
        }
      };

      html.window.localStorage['ohtli_trip_draft_${widget.trip.id}'] = jsonEncode(cacheData);

      // Trigger cloud auto-save debounce
      _triggerCloudAutoSaveDebounce();
    } catch (e) {
      print("Error saving local cache: $e");
    }
  }

  void _triggerCloudAutoSaveDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 30), () {
      _saveToCloudFirestore();
    });
  }

  Future<void> _saveToCloudFirestore() async {
    if (_isSavingCloud) return;

    setState(() {
      _isSavingCloud = true;
    });

    final now = DateTime.now();

    final updatedTrip = Trip(
      id: widget.trip.id,
      userId: widget.trip.userId,
      title: _titleController.text,
      description: _descriptionController.text,
      coverUrl: _coverUrl,
      status: _status,
      visibility: _visibility,
      createdAt: widget.trip.createdAt,
      updatedAt: now,
      travelDate: widget.trip.travelDate,
    );

    final updatedContent = TripContent(sections: _sections);

    try {
      await Future.wait([
        TripService().updateTrip(widget.trip.userId, updatedTrip),
        TripService().updateTripContent(widget.trip.userId, widget.trip.id, updatedContent),
      ]);

      if (mounted) {
        setState(() {
          _isSavingCloud = false;
          _lastSavedCloudTime = now;
        });
      }
    } catch (e) {
      print("Error saving to cloud: $e");
      if (mounted) {
        setState(() {
          _isSavingCloud = false;
        });
      }
    }
  }

  // Actions on Blocks
  void _addBlock(String type) {
    setState(() {
      final String id = 'sec_${DateTime.now().millisecondsSinceEpoch}_${_sections.length}';
      if (type == 'place') {
        _sections.add(PlaceSection(
          id: id,
          title: '',
          description: '',
          rating: 0,
          mainPhotoUrl: '',
          secondaryPhotoUrls: [],
        ));
      } else if (type == 'text') {
        _sections.add(TextSection(
          id: id,
          markdownText: '',
        ));
      } else if (type == 'text_image') {
        _sections.add(TextImageSection(
          id: id,
          markdownText: '',
          imageUrl: '',
          layout: 'left',
        ));
      }
      _onDataChanged();
    });
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final temp = _sections[index];
      _sections[index] = _sections[index - 1];
      _sections[index - 1] = temp;
      _onDataChanged();
    });
  }

  void _moveDown(int index) {
    if (index >= _sections.length - 1) return;
    setState(() {
      final temp = _sections[index];
      _sections[index] = _sections[index + 1];
      _sections[index + 1] = temp;
      _onDataChanged();
    });
  }

  void _deleteBlock(int index) {
    setState(() {
      _sections.removeAt(index);
      _onDataChanged();
    });
  }

  // Mutator Helpers
  void _updatePlaceBlock(int index, {String? title, String? description, int? rating, String? photo}) {
    final current = _sections[index] as PlaceSection;
    setState(() {
      _sections[index] = PlaceSection(
        id: current.id,
        title: title ?? current.title,
        description: description ?? current.description,
        rating: rating ?? current.rating,
        mainPhotoUrl: photo ?? current.mainPhotoUrl,
        secondaryPhotoUrls: current.secondaryPhotoUrls,
      );
      _onDataChanged();
    });
  }

  void _updateTextBlock(int index, {String? markdown}) {
    final current = _sections[index] as TextSection;
    setState(() {
      _sections[index] = TextSection(
        id: current.id,
        markdownText: markdown ?? current.markdownText,
      );
      _onDataChanged();
    });
  }

  void _updateTextImageBlock(int index, {String? markdown, String? photo, String? layout}) {
    final current = _sections[index] as TextImageSection;
    setState(() {
      _sections[index] = TextImageSection(
        id: current.id,
        markdownText: markdown ?? current.markdownText,
        imageUrl: photo ?? current.imageUrl,
        layout: layout ?? current.layout,
      );
      _onDataChanged();
    });
  }

  void _uploadImageForBlock(int index, String type) {
    if (!kIsWeb) return;

    try {
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
              if (!mounted) return;
              try {
                final String base64Data = result.split(',').last;
                final Uint8List bytes = base64Decode(base64Data);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => OhtliImageCropperDialog(
                    imageBytes: bytes,
                    isCircle: false, // 16:9 Aspect Ratio
                    onCropped: (String base64String) {
                      final String finalPhotoUrl = 'data:image/png;base64,$base64String';
                      if (type == 'place') {
                        _updatePlaceBlock(index, photo: finalPhotoUrl);
                      } else if (type == 'text_image') {
                        _updateTextImageBlock(index, photo: finalPhotoUrl);
                      }
                    },
                  ),
                );
              } catch (err) {
                print("Error decodando imagen: $err");
              }
            }
          });
          reader.readAsDataUrl(file);
        }
      });
    } catch (err) {
      print("Error abriendo selector de imágenes: $err");
    }
  }

  void _uploadCoverImage() {
    if (!kIsWeb) return;

    try {
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
              if (!mounted) return;
              try {
                final String base64Data = result.split(',').last;
                final Uint8List bytes = base64Decode(base64Data);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => OhtliImageCropperDialog(
                    imageBytes: bytes,
                    isCircle: false, // 16:9 Aspect Ratio
                    onCropped: (String base64String) {
                      setState(() {
                        _coverUrl = 'data:image/png;base64,$base64String';
                        _onDataChanged();
                      });
                    },
                  ),
                );
              } catch (err) {
                print("Error decodando portada: $err");
              }
            }
          });
          reader.readAsDataUrl(file);
        }
      });
    } catch (err) {
      print("Error abriendo selector de portada: $err");
    }
  }

  // Privacy Visibility Warning Trigger
  void _changeVisibility(String newVis) {
    if (newVis == _visibility) return;

    if (_visibility == 'public' && newVis == 'private') {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: OhtliColors.cloudDancer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              '¿Cambiar a Privado?',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: OhtliColors.onyx,
              ),
            ),
            content: Text(
              'Al cambiar la visibilidad a Privado, todos los enlaces compartidos previamente de esta bitácora dejarán de estar accesibles al público de inmediato.',
              style: GoogleFonts.inter(
                color: OhtliColors.onyx.withValues(alpha: 0.8),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: GoogleFonts.inter(
                    color: OhtliColors.onyx.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _visibility = newVis;
                    _onDataChanged();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.xoconostle,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Cambiar a Privado',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      setState(() {
        _visibility = newVis;
        _onDataChanged();
      });
    }
  }

  // Exit checking
  Future<bool> _onWillPop() async {
    _debounceTimer?.cancel();
    await _saveToCloudFirestore();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;

    String syncStatusText = "Cambios guardados localmente";
    IconData syncIcon = Icons.cloud_done_outlined;
    Color syncColor = OhtliColors.stormyTeal;

    if (_isSavingCloud) {
      syncStatusText = "Guardando en la nube...";
      syncIcon = Icons.sync_rounded;
      syncColor = OhtliColors.xoconostle;
    } else if (_lastSavedCloudTime != null) {
      syncStatusText = "Sincronizado en la nube";
      syncIcon = Icons.cloud_done_rounded;
    }

    Widget mainContent = _isLoadingContent
        ? const Center(
            child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Image Selector
              GestureDetector(
                onTap: _uploadCoverImage,
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    image: _coverUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(_coverUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _coverUrl.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.image_outlined,
                                size: 36,
                                color: OhtliColors.stormyTeal,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Añadir imagen de portada',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  color: OhtliColors.stormyTeal,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          alignment: Alignment.bottomRight,
                          padding: const EdgeInsets.all(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'Cambiar portada',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Title and Description inputs
              TextFormField(
                controller: _titleController,
                maxLines: 2,
                onChanged: (_) => _onDataChanged(),
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
                decoration: InputDecoration(
                  hintText: 'Título de tu viaje',
                  hintStyle: GoogleFonts.inter(
                    color: OhtliColors.onyx.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                onChanged: (_) => _onDataChanged(),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: OhtliColors.onyx.withValues(alpha: 0.7),
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: 'Escribe una breve descripción del viaje...',
                  hintStyle: GoogleFonts.inter(
                    color: OhtliColors.onyx.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),

              const Divider(height: 48, color: OhtliColors.cantera),

              // Blocks List Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bitácora del Viaje',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  Text(
                    '${_sections.length} bloques',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: OhtliColors.onyx.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Blocks List
              _sections.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.playlist_add_rounded, size: 40, color: OhtliColors.cantera),
                          const SizedBox(height: 12),
                          Text(
                            'Tu bitácora está vacía',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: OhtliColors.onyx.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '¡Añade bloques abajo para empezar a documentar!',
                            style: GoogleFonts.inter(
                              color: OhtliColors.onyx.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sections.length,
                      itemBuilder: (context, index) {
                        final section = _sections[index];
                        return _buildBlockCard(index, section, isDark);
                      },
                    ),

              const SizedBox(height: 32),
              
              // Bottom Action Blocks Selection
              Text(
                'Añadir Bloque de Contenido',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.onyx.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildAddBlockButton(
                      label: 'Lugar',
                      icon: Icons.location_on_rounded,
                      onTap: () => _addBlock('place'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAddBlockButton(
                      label: 'Texto',
                      icon: Icons.notes_rounded,
                      onTap: () => _addBlock('text'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAddBlockButton(
                      label: 'Texto/Imagen',
                      icon: Icons.photo_library_rounded,
                      onTap: () => _addBlock('text_image'),
                    ),
                  ),
                ],
              ),
            ],
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: OhtliColors.onyx,
            onPressed: () async {
              final bool shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          title: Row(
            children: [
              Icon(syncIcon, color: syncColor, size: 18),
              const SizedBox(width: 6),
              Text(
                syncStatusText,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: OhtliColors.onyx.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          actions: [
            // Visibility Dropdown
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _visibility,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  iconEnabledColor: OhtliColors.stormyTeal,
                  dropdownColor: isDark ? const Color(0xFF25252A) : Colors.white,
                  items: [
                    DropdownMenuItem(
                      value: 'private',
                      child: Text(
                        'Privado',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: OhtliColors.onyx,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'public',
                      child: Text(
                        'Público',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: OhtliColors.onyx,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      _changeVisibility(val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: mainContent,
          ),
        ),
      ),
    );
  }

  Widget _buildBlockCard(int index, TripSection section, bool isDark) {
    String typeLabel = "Bloque";
    IconData typeIcon = Icons.article_outlined;
    Widget blockContent = const SizedBox();

    if (section is PlaceSection) {
      typeLabel = "Lugar Visitado";
      typeIcon = Icons.location_on_rounded;
      blockContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: section.title,
                  onChanged: (val) => _updatePlaceBlock(index, title: val),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: OhtliColors.onyx,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Nombre del Lugar',
                    hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: const UnderlineInputBorder(borderSide: BorderSide(color: OhtliColors.cantera)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Rating Stars Bar
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (starIndex) {
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      starIndex < section.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: starIndex < section.rating ? Colors.amber : OhtliColors.cantera,
                      size: 20,
                    ),
                    onPressed: () {
                      _updatePlaceBlock(index, rating: starIndex + 1);
                    },
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: section.description,
            onChanged: (val) => _updatePlaceBlock(index, description: val),
            maxLines: 2,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: OhtliColors.onyx.withValues(alpha: 0.7),
            ),
            decoration: InputDecoration(
              hintText: 'Escribe una breve reseña de este lugar...',
              hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 12),
          // Main Photo upload field
          GestureDetector(
            onTap: () => _uploadImageForBlock(index, 'place'),
            child: Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
                  width: 1,
                ),
                image: section.mainPhotoUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(section.mainPhotoUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: section.mainPhotoUrl.isEmpty
                  ? Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined, size: 20, color: OhtliColors.stormyTeal),
                          const SizedBox(width: 8),
                          Text(
                            'Sube una foto del lugar',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: OhtliColors.stormyTeal,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
        ],
      );
    } else if (section is TextSection) {
      typeLabel = "Nota / Historia";
      typeIcon = Icons.notes_rounded;
      blockContent = TextFormField(
        initialValue: section.markdownText,
        onChanged: (val) => _updateTextBlock(index, markdown: val),
        maxLines: 4,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: OhtliColors.onyx,
          height: 1.4,
        ),
        decoration: InputDecoration(
          hintText: 'Escribe tu anécdota, historia o consejo aquí...',
          hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      );
    } else if (section is TextImageSection) {
      typeLabel = "Nota con Imagen";
      typeIcon = Icons.photo_library_rounded;
      blockContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Alineación de la imagen:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: OhtliColors.onyx.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Izquierda', style: GoogleFonts.inter(fontSize: 11)),
                selected: section.layout == 'left',
                onSelected: (val) {
                  if (val) _updateTextImageBlock(index, layout: 'left');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Derecha', style: GoogleFonts.inter(fontSize: 11)),
                selected: section.layout == 'right',
                onSelected: (val) {
                  if (val) _updateTextImageBlock(index, layout: 'right');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Upload Image for block
          GestureDetector(
            onTap: () => _uploadImageForBlock(index, 'text_image'),
            child: Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
                  width: 1,
                ),
                image: section.imageUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(section.imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: section.imageUrl.isEmpty
                  ? Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined, size: 20, color: OhtliColors.stormyTeal),
                          const SizedBox(width: 8),
                          Text(
                            'Sube una imagen lateral',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: OhtliColors.stormyTeal,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: section.markdownText,
            onChanged: (val) => _updateTextImageBlock(index, markdown: val),
            maxLines: 3,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: OhtliColors.onyx,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Añade tu descripción lateral...',
              hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: OhtliColors.onyx.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Block header controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(typeIcon, size: 16, color: OhtliColors.stormyTeal),
                const SizedBox(width: 8),
                Text(
                  typeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                // Up Button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  color: index > 0 ? OhtliColors.stormyTeal : OhtliColors.cantera,
                  onPressed: index > 0 ? () => _moveUp(index) : null,
                ),
                const SizedBox(width: 12),
                // Down Button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                  color: index < _sections.length - 1 ? OhtliColors.stormyTeal : OhtliColors.cantera,
                  onPressed: index < _sections.length - 1 ? () => _moveDown(index) : null,
                ),
                const SizedBox(width: 12),
                // Delete Button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  color: OhtliColors.xoconostle,
                  onPressed: () => _deleteBlock(index),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: blockContent,
          ),
        ],
      ),
    );
  }

  Widget _buildAddBlockButton({required String label, required IconData icon, required VoidCallback onTap}) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    return Material(
      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: OhtliColors.stormyTeal.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: OhtliColors.stormyTeal, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.stormyTeal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

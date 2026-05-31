import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../theme/colors.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../widgets/ohtli_markdown_editor.dart';
import '../../widgets/ohtli_place_photo_stack.dart';
import '../../services/markdown_helpers.dart';
import 'package:uuid/uuid.dart';
import 'widgets/alert_block_editor.dart';
import 'widgets/table_block_editor.dart';

class TripEditorPage extends StatefulWidget {
  final Trip trip;

  const TripEditorPage({super.key, required this.trip});

  @override
  State<TripEditorPage> createState() => _TripEditorPageState();
}

class _TripEditorPageState extends State<TripEditorPage> {
  late TextEditingController _titleController;
  late MarkdownRichTextController _descriptionController;
  late String _visibility;
  late String _status;
  late String _coverUrl;
  DateTime? _travelDate;
  List<ErrataEntry> _errataHistory = [];
  
  List<TripSection> _sections = [];
  bool _isLoadingContent = true;
  bool _isSavingCloud = false;
  
  Timer? _debounceTimer;
  
  // Persistent TextEditingControllers for text inputs to avoid cursor jumps
  final Map<String, TextEditingController> _blockControllers = {};

  // Persistent FocusNodes for text inputs to return focus when formatting
  final Map<String, FocusNode> _blockFocusNodes = {};

  // Image provider cache to prevent flickering
  final Map<String, ImageProvider> _imageProvidersCache = {};

  // Local changes tracking
  DateTime? _lastSavedCloudTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.trip.title);
    _descriptionController = MarkdownRichTextController(text: widget.trip.description, context: context);
    _visibility = widget.trip.visibility;
    _status = widget.trip.status;
    _coverUrl = widget.trip.coverUrl;
    _travelDate = widget.trip.travelDate;
    _errataHistory = List.from(widget.trip.errataHistory);

    _loadCloudContentAndCheckCache();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    for (var controller in _blockControllers.values) {
      controller.dispose();
    }
    for (var node in _blockFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getFocusNode(String key) {
    return _blockFocusNodes.putIfAbsent(key, () => FocusNode());
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
        _descriptionController.text = cache['trip']['description'] ?? _descriptionController.markdownText;
        _coverUrl = cache['trip']['coverUrl'] ?? _coverUrl;
        _visibility = cache['trip']['visibility'] ?? _visibility;
        _status = cache['trip']['status'] ?? _status;
      }
      if (cache['content'] != null) {
        _sections = TripContent.fromMap(cache['content']).sections;
        // Update all text controllers to match restored text
        for (var section in _sections) {
          if (section is TextSection && _blockControllers.containsKey(section.id)) {
            _blockControllers[section.id]!.text = section.markdownText;
          } else if (section is TextImageSection && _blockControllers.containsKey(section.id)) {
            _blockControllers[section.id]!.text = section.markdownText;
          }
        }
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

  // Image provider helper that handles local base64 drafts as well as cloud network images
  ImageProvider _getImageProvider(String url) {
    return _imageProvidersCache.putIfAbsent(url, () {
      if (url.startsWith('data:image') || url.startsWith('data:')) {
        final String base64Data = url.split(',').last;
        return MemoryImage(base64Decode(base64Data));
      }
      return NetworkImage(url);
    });
  }

  // Local caching & debounced auto-save triggers
  void _onDataChanged() {
    _saveToLocalCache();
  }

  void _syncAllTables() {
    for (int index = 0; index < _sections.length; index++) {
      final section = _sections[index];
      if (section is TextSection) {
        final tableData = parseTableMarkdown(section.markdownText);
        if (tableData != null) {
          final int numCols = tableData.columns.length;
          final int numRows = tableData.rows.length;

          final List<TableColumn> updatedColumns = [];
          for (int c = 0; c < numCols; c++) {
            final ctrl = _blockControllers['${section.id}_h_$c'];
            final currentCol = tableData.columns[c];
            updatedColumns.add(TableColumn(
              name: ctrl?.text ?? currentCol.name,
              type: currentCol.type,
              currency: currentCol.currency,
            ));
          }

          final List<List<String>> updatedRows = [];
          for (int r = 0; r < numRows; r++) {
            final List<String> rowCells = [];
            for (int c = 0; c < numCols; c++) {
              final ctrl = _blockControllers['${section.id}_cell_${r}_$c'];
              rowCells.add(ctrl?.text ?? tableData.rows[r][c]);
            }
            updatedRows.add(rowCells);
          }

          final newMarkdown = serializeTableMarkdown(TableData(columns: updatedColumns, rows: updatedRows));
          _sections[index] = TextSection(id: section.id, markdownText: newMarkdown);
        }
      }
    }
  }

  void _saveToLocalCache() {
    if (!kIsWeb) return;
    _syncAllTables();

    try {
      final now = DateTime.now();
      final cacheData = {
        'updatedAt': now.millisecondsSinceEpoch,
        'trip': {
          'title': _titleController.text,
          'description': _descriptionController.markdownText,
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
    _syncAllTables();

    setState(() {
      _isSavingCloud = true;
    });

    final now = DateTime.now();
    String finalCoverUrl = _coverUrl;

    // 1. Upload Cover to Storage if it's a base64 local draft
    if (_coverUrl.startsWith('data:')) {
      try {
        final String base64Data = _coverUrl.split(',').last;
        final Uint8List bytes = base64Decode(base64Data);
        final storageRef = FirebaseStorage.instance
            .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/cover.jpg');
        await storageRef.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final bucket = FirebaseStorage.instance.app.options.storageBucket;
        finalCoverUrl =
            "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fcover.jpg?alt=media";
      } catch (e) {
        print("Error uploading cover to Storage: $e");
      }
    }

    final List<TripSection> updatedSections = [];
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    final int timestamp = now.millisecondsSinceEpoch;

    for (var section in _sections) {
      if (section is PlaceSection) {
        String finalMain = section.mainPhotoUrl;
        if (finalMain.startsWith('data:')) {
          try {
            final String base64Data = finalMain.split(',').last;
            final Uint8List bytes = base64Decode(base64Data);
            final String filename = "${section.id}_main_$timestamp.jpg";
            final storageRef = FirebaseStorage.instance
                .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/sections/$filename');
            await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
            finalMain = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fsections%2F$filename?alt=media";
          } catch (e) {
            print("Error uploading section main photo: $e");
          }
        }

        final List<String> finalSec = [];
        for (int i = 0; i < section.secondaryPhotoUrls.length; i++) {
          String secUrl = section.secondaryPhotoUrls[i];
          if (secUrl.startsWith('data:')) {
            try {
              final String base64Data = secUrl.split(',').last;
              final Uint8List bytes = base64Decode(base64Data);
              final String filename = "${section.id}_sec_${timestamp}_$i.jpg";
              final storageRef = FirebaseStorage.instance
                  .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/sections/$filename');
              await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
              secUrl = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fsections%2F$filename?alt=media";
            } catch (e) {
              print("Error uploading section secondary photo $i: $e");
            }
          }
          finalSec.add(secUrl);
        }

        updatedSections.add(PlaceSection(
          id: section.id,
          title: section.title,
          description: section.description,
          rating: section.rating,
          mainPhotoUrl: finalMain,
          secondaryPhotoUrls: finalSec,
          cost: section.cost,
          currency: section.currency,
        ));
      } else if (section is TextImageSection) {
        String finalImg = section.imageUrl;
        if (finalImg.startsWith('data:')) {
          try {
            final String base64Data = finalImg.split(',').last;
            final Uint8List bytes = base64Decode(base64Data);
            final String filename = "${section.id}_image_$timestamp.jpg";
            final storageRef = FirebaseStorage.instance
                .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/sections/$filename');
            await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
            finalImg = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fsections%2F$filename?alt=media";
          } catch (e) {
            print("Error uploading section text_image photo: $e");
          }
        }

        updatedSections.add(TextImageSection(
          id: section.id,
          markdownText: section.markdownText,
          imageUrl: finalImg,
          layout: section.layout,
        ));
      } else {
        updatedSections.add(section);
      }
    }

    final updatedTrip = Trip(
      id: widget.trip.id,
      userId: widget.trip.userId,
      title: _titleController.text,
      description: _descriptionController.markdownText,
      coverUrl: finalCoverUrl,
      status: _status,
      visibility: _visibility,
      createdAt: widget.trip.createdAt,
      updatedAt: now,
      travelDate: _travelDate,
      errataHistory: _errataHistory,
    );

    final updatedContent = TripContent(sections: updatedSections);

    try {
      await Future.wait([
        TripService().updateTrip(widget.trip.userId, updatedTrip),
        TripService().updateTripContent(widget.trip.userId, widget.trip.id, updatedContent),
      ]);

      // Dynamic Garbage Collector for Firebase Storage section photos
      await _cleanupStoragePhotos(widget.trip.userId, widget.trip.id, updatedSections);

      if (mounted) {
        setState(() {
          _sections = updatedSections;
          _coverUrl = finalCoverUrl; // Keep local state in sync with network URL
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

  Future<void> _cleanupStoragePhotos(String userId, String tripId, List<TripSection> finalSections) async {
    try {
      final storageRef = FirebaseStorage.instance.ref('users/$userId/trips/$tripId/sections');
      final listResult = await storageRef.listAll();
      
      // Gather all referenced URLs
      final Set<String> referencedUrls = {};
      for (var sec in finalSections) {
        if (sec is PlaceSection) {
          if (sec.mainPhotoUrl.isNotEmpty) {
            referencedUrls.add(sec.mainPhotoUrl);
          }
          for (var url in sec.secondaryPhotoUrls) {
            if (url.isNotEmpty) {
              referencedUrls.add(url);
            }
          }
        } else if (sec is TextImageSection) {
          if (sec.imageUrl.isNotEmpty) {
            referencedUrls.add(sec.imageUrl);
          }
        }
      }

      // Check each file in storage sections folder
      for (var item in listResult.items) {
        final filename = item.name;
        bool isReferenced = false;
        for (var url in referencedUrls) {
          // If the referenced url contains the filename, it is in use
          if (url.contains(filename)) {
            isReferenced = true;
            break;
          }
        }
        if (!isReferenced) {
          print("Deleting orphaned storage section photo: ${item.name}");
          await item.delete();
        }
      }
    } catch (e) {
      // Ignore safe errors (such as directory not existing)
      print("Warning in _cleanupStoragePhotos: $e");
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
      } else if (type == 'table') {
        _sections.add(TextSection(
          id: id,
          markdownText: '| Columna 1 | Columna 2 |\n|---|---|\n| Celda 1 | Celda 2 |',
        ));
      } else if (type == 'notes') {
        _sections.add(TextSection(
          id: id,
          markdownText: '> [!NOTE]\n> Escribe tu nota aquí',
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
      final sec = _sections[index];
      _blockControllers.remove(sec.id);
      _sections.removeAt(index);
      _onDataChanged();
    });
  }

  // Mutator Helpers
  void _updatePlaceBlock(int index, {
    String? title,
    String? description,
    int? rating,
    String? mainPhoto,
    List<String>? secondaryPhotos,
    double? cost,
    String? currency,
  }) {
    final current = _sections[index] as PlaceSection;
    
    String finalMainPhoto = mainPhoto ?? current.mainPhotoUrl;
    List<String> finalSecondary = List<String>.from(secondaryPhotos ?? current.secondaryPhotoUrls);
    
    // Collect all valid/non-empty photos in order
    final List<String> allPhotos = [];
    if (finalMainPhoto.isNotEmpty) allPhotos.add(finalMainPhoto);
    for (var photo in finalSecondary) {
      if (photo.isNotEmpty) allPhotos.add(photo);
    }
    
    // Distribute them back: first goes to main, next go to secondary
    if (allPhotos.isNotEmpty) {
      finalMainPhoto = allPhotos[0];
      finalSecondary = allPhotos.sublist(1);
    } else {
      finalMainPhoto = '';
      finalSecondary = [];
    }
    
    // Ensure secondary list is padded to at least 2 elements so indexing works for secondary slot 0 and 1
    while (finalSecondary.length < 2) {
      finalSecondary.add('');
    }

    final newSection = PlaceSection(
      id: current.id,
      title: title ?? current.title,
      description: description ?? current.description,
      rating: rating ?? current.rating,
      mainPhotoUrl: finalMainPhoto,
      secondaryPhotoUrls: finalSecondary,
      cost: cost ?? current.cost,
      currency: currency ?? current.currency,
    );
    
    if (current.title != newSection.title ||
        current.description != newSection.description ||
        current.rating != newSection.rating ||
        current.mainPhotoUrl != newSection.mainPhotoUrl ||
        current.cost != newSection.cost ||
        current.currency != newSection.currency ||
        !listEquals(current.secondaryPhotoUrls, newSection.secondaryPhotoUrls)) {
      setState(() {
        _sections[index] = newSection;
      });
      _onDataChanged();
    }
  }

  void _updatePlaceSecondaryPhoto(int blockIndex, int slotIndex, String base64Photo) {
    final current = _sections[blockIndex] as PlaceSection;
    final List<String> currentSecondary = List<String>.from(current.secondaryPhotoUrls);
    
    // Pad the list with empty strings to guarantee slotIndex exists
    while (currentSecondary.length <= slotIndex) {
      currentSecondary.add('');
    }
    
    currentSecondary[slotIndex] = base64Photo;
    _updatePlaceBlock(blockIndex, secondaryPhotos: currentSecondary);
  }

  void _deletePlaceSecondaryPhoto(int blockIndex, int slotIndex) {
    final current = _sections[blockIndex] as PlaceSection;
    final List<String> currentSecondary = List<String>.from(current.secondaryPhotoUrls);
    if (slotIndex < currentSecondary.length) {
      currentSecondary[slotIndex] = '';
      
      // Trim trailing empty entries to keep the array compact
      while (currentSecondary.isNotEmpty && currentSecondary.last.isEmpty) {
        currentSecondary.removeLast();
      }
      
      _updatePlaceBlock(blockIndex, secondaryPhotos: currentSecondary);
    }
  }

  void _updateTextBlock(int index, {String? markdown}) {
    final current = _sections[index] as TextSection;
    final newSection = TextSection(
      id: current.id,
      markdownText: markdown ?? current.markdownText,
    );
    if (current.markdownText != newSection.markdownText) {
      setState(() {
        _sections[index] = newSection;
      });
      _onDataChanged();
    }
  }

  void _updateTextImageBlock(int index, {String? markdown, String? photo, String? layout}) {
    final current = _sections[index] as TextImageSection;
    final newSection = TextImageSection(
      id: current.id,
      markdownText: markdown ?? current.markdownText,
      imageUrl: photo ?? current.imageUrl,
      layout: layout ?? current.layout,
    );
    if (current.markdownText != newSection.markdownText ||
        current.imageUrl != newSection.imageUrl ||
        current.layout != newSection.layout) {
      setState(() {
        _sections[index] = newSection;
      });
      _onDataChanged();
    }
  }

  void _uploadImageForBlock(int index, String type) {
    if (!kIsWeb) return;

    try {
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
              if (!mounted) return;
              try {
                final String base64Data = result.split(',').last;
                final Uint8List bytes = base64Decode(base64Data);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => OhtliImageCropperDialog(
                    imageBytes: bytes,
                    isCircle: false,
                    aspectRatio: 3 / 4, // 3:4 Aspect Ratio for Place & Text/Image
                    onCropped: (String base64String) {
                      final String finalPhotoUrl = base64String;
                      if (type == 'place_main') {
                        _updatePlaceBlock(index, mainPhoto: finalPhotoUrl);
                      } else if (type == 'place_sec_0') {
                        _updatePlaceSecondaryPhoto(index, 0, finalPhotoUrl);
                      } else if (type == 'place_sec_1') {
                        _updatePlaceSecondaryPhoto(index, 1, finalPhotoUrl);
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
                        _coverUrl = base64String;
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

  Future<void> _showPublishOptionsDialog() async {
    DateTime? tempDate = _travelDate;
    String tempVisibility = _visibility;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: OhtliColors.cloudDancer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Publicar Viaje',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Para publicar esta historia, la fecha del viaje es obligatoria.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Fecha de Viaje (Obligatoria):',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: OhtliColors.stormyTeal,
                                onPrimary: Colors.white,
                                onSurface: OhtliColors.onyx,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          tempDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 14, color: OhtliColors.stormyTeal),
                    label: Text(
                      tempDate != null
                          ? '${tempDate!.day}/${tempDate!.month}/${tempDate!.year}'
                          : 'Seleccionar Fecha',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: OhtliColors.stormyTeal,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Visibilidad:',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OhtliColors.cantera.withValues(alpha: 0.5)),
                    ),
                    child: DropdownButton<String>(
                      value: tempVisibility,
                      isExpanded: true,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: OhtliColors.stormyTeal),
                      items: [
                        DropdownMenuItem(
                          value: 'public',
                          child: Text('Pública (cualquiera con el link)', style: GoogleFonts.inter(fontSize: 12.5)),
                        ),
                        DropdownMenuItem(
                          value: 'private',
                          child: Text('Privada (solo yo)', style: GoogleFonts.inter(fontSize: 12.5)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setStateDialog(() {
                            tempVisibility = val;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: tempDate == null
                      ? null
                      : () async {
                          Navigator.pop(dialogContext);
                          setState(() {
                            _travelDate = tempDate;
                            _visibility = tempVisibility;
                            _status = 'published';
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Publicando bitácora de viaje...',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              backgroundColor: OhtliColors.stormyTeal,
                              duration: const Duration(milliseconds: 600),
                            ),
                          );

                          _syncAllTables();
                          await _saveToCloudFirestore();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '¡Tu viaje ha sido publicado con éxito!',
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
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Publicar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showErrataDialog() async {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: OhtliColors.cloudDancer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.history_edu_rounded, color: OhtliColors.xoconostle, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Publicar Fe de Errata',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Introduce una breve nota detallando las correcciones realizadas. Esta nota se mostrará al final de la publicación para transparencia de tus lectores.',
                    style: GoogleFonts.inter(fontSize: 12, height: 1.45, color: OhtliColors.onyx.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Descripción de cambios realizados:',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ej. Se actualizaron costos de boletos y se corrigió el nombre del hotel...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: OhtliColors.cantera.withValues(alpha: 0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: OhtliColors.xoconostle, width: 1.2),
                      ),
                    ),
                    onChanged: (val) {
                      setStateDialog(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: noteController.text.trim().isEmpty
                      ? null
                      : () async {
                          final String noteText = noteController.text.trim();
                          Navigator.pop(dialogContext);

                          final newErrata = ErrataEntry(
                            id: const Uuid().v4(),
                            note: noteText,
                            date: DateTime.now(),
                          );

                          setState(() {
                            _errataHistory.add(newErrata);
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Guardando correcciones...',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              backgroundColor: OhtliColors.xoconostle,
                              duration: const Duration(milliseconds: 600),
                            ),
                          );

                          _syncAllTables();
                          await _saveToCloudFirestore();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '¡Fe de Errata publicada con éxito!',
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                                backgroundColor: OhtliColors.xoconostle,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.xoconostle,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Publicar Errata',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handlePublishAction() async {
    if (_status == 'published') {
      await _showErrataDialog();
    } else {
      await _showPublishOptionsDialog();
    }
  }

  // Exit checking
  Future<bool> _onWillPop() async {
    _debounceTimer?.cancel();
    _syncAllTables();
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
                            image: _getImageProvider(_coverUrl),
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
              OhtliMarkdownEditor(
                controller: _descriptionController,
                focusNode: _getFocusNode('trip_description'),
                hintText: 'Escribe una breve descripción del viaje...',
                minLines: 3,
                maxLines: null,
                onChanged: _onDataChanged,
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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.start,
                children: [
                  _buildAddBlockButton(
                    label: 'Lugar',
                    icon: Icons.location_on_rounded,
                    onTap: () => _addBlock('place'),
                    width: 105,
                  ),
                  _buildAddBlockButton(
                    label: 'Texto',
                    icon: Icons.notes_rounded,
                    onTap: () => _addBlock('text'),
                    width: 105,
                  ),
                  _buildAddBlockButton(
                    label: 'Texto/Imagen',
                    icon: Icons.photo_library_rounded,
                    onTap: () => _addBlock('text_image'),
                    width: 125,
                  ),
                  _buildAddBlockButton(
                    label: 'Tabla',
                    icon: Icons.table_chart_rounded,
                    onTap: () => _addBlock('table'),
                    width: 105,
                  ),
                  _buildAddBlockButton(
                    label: 'Notas',
                    icon: Icons.info_outline_rounded,
                    onTap: () => _addBlock('notes'),
                    width: 105,
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
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _status == 'published'
                  ? ElevatedButton.icon(
                      onPressed: _handlePublishAction,
                      icon: const Icon(Icons.history_edu_rounded, size: 14, color: Colors.white),
                      label: Text(
                        'Fe de Errata',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OhtliColors.xoconostle,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _handlePublishAction,
                      icon: const Icon(Icons.publish_rounded, size: 14, color: Colors.white),
                      label: Text(
                        'Publicar',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OhtliColors.stormyTeal,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
            ),
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: mainContent,
              ),
            ),
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
      
      final titleController = _blockControllers.putIfAbsent(
        '${section.id}_title',
        () {
          final c = TextEditingController(text: section.title);
          c.addListener(() {
            _updatePlaceBlock(index, title: c.text);
          });
          return c;
        },
      );

      final controller = _blockControllers.putIfAbsent(
        '${section.id}_desc',
        () {
          final c = MarkdownRichTextController(text: section.description, context: context);
          c.addListener(() {
            _updatePlaceBlock(index, description: c.markdownText);
          });
          return c;
        },
      );
      final focusNode = _getFocusNode('${section.id}_desc');

      final costController = _blockControllers.putIfAbsent(
        '${section.id}_cost',
        () {
          final c = TextEditingController(text: section.cost > 0 ? section.cost.toString() : '');
          c.addListener(() {
            final double? parsed = double.tryParse(c.text);
            _updatePlaceBlock(index, cost: parsed ?? 0.0);
          });
          return c;
        },
      );

      final List<Map<String, dynamic>> slots = [
        {
          'url': section.mainPhotoUrl,
          'label': 'Principal',
          'type': 'place_main',
          'onTap': () => _uploadImageForBlock(index, 'place_main'),
          'onDelete': () => _updatePlaceBlock(index, mainPhoto: ''),
        },
        {
          'url': section.secondaryPhotoUrls.isNotEmpty ? section.secondaryPhotoUrls[0] : '',
          'label': 'Foto 2',
          'type': 'place_sec_0',
          'onTap': () => _uploadImageForBlock(index, 'place_sec_0'),
          'onDelete': () => _deletePlaceSecondaryPhoto(index, 0),
        },
        {
          'url': section.secondaryPhotoUrls.length > 1 ? section.secondaryPhotoUrls[1] : '',
          'label': 'Foto 3',
          'type': 'place_sec_1',
          'onTap': () => _uploadImageForBlock(index, 'place_sec_1'),
          'onDelete': () => _deletePlaceSecondaryPhoto(index, 1),
        },
      ];

      final uploadedSlots = slots.where((s) => (s['url'] as String).isNotEmpty).toList();

      final Widget rightColumnWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: titleController,
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
          // Description Box wrapping toolbar and text field
          OhtliMarkdownEditor(
            controller: controller,
            focusNode: focusNode,
            hintText: 'Escribe una breve reseña de este lugar...',
            minLines: 2,
            maxLines: null,
          ),
          // Yellow Cost Block
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF332711) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFFFBBF24).withValues(alpha: 0.3) : const Color(0xFFFDE68A),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.payments_rounded,
                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Costo:',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: section.currency.isNotEmpty ? section.currency : 'MXN',
                    dropdownColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.onyx,
                    ),
                    underline: const SizedBox(),
                    isDense: true,
                    items: <String>['MXN', 'USD', 'EUR', 'CAD', 'GBP'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _updatePlaceBlock(index, currency: val);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      controller: costController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: OhtliColors.onyx,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

      // Determine next empty slot callback to auto-add
      final nextEmptySlot = slots.firstWhere((s) => (s['url'] as String).isEmpty, orElse: () => {});
      final nextEmptySlotOnTap = nextEmptySlot.isNotEmpty ? nextEmptySlot['onTap'] as VoidCallback? : null;


      final Widget leftColumnWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          uploadedSlots.isNotEmpty
              ? _buildPhotoStack(uploadedSlots, isDark)
              : SizedBox(
                  width: 120,
                  height: 160,
                  child: _buildPlacePhotoSlot(
                    blockIndex: index,
                    photoUrl: '',
                    label: 'Principal',
                    onTap: () => _uploadImageForBlock(index, 'place_main'),
                    onDelete: () => _updatePlaceBlock(index, mainPhoto: ''),
                    isDark: isDark,
                  ),
                ),
          if (nextEmptySlotOnTap != null)
            Container(
              width: 120,
              margin: EdgeInsets.only(
                top: uploadedSlots.isNotEmpty ? 0 : 8,
                left: uploadedSlots.isNotEmpty ? 10 : 0,
              ),
              child: OutlinedButton(
                onPressed: nextEmptySlotOnTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: OhtliColors.stormyTeal,
                  side: BorderSide(
                    color: OhtliColors.stormyTeal.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Añadir Foto',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

      blockContent = LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth >= 500;
          if (isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leftColumnWidget,
                const SizedBox(width: 16),
                Expanded(child: rightColumnWidget),
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: leftColumnWidget,
                ),
                const SizedBox(height: 16),
                rightColumnWidget,
              ],
            );
          }
        },
      );
    } else if (section is TextSection) {
      final alertData = parseAlertMarkdown(section.markdownText);
      final tableData = parseTableMarkdown(section.markdownText);

      if (alertData != null) {
        typeLabel = "Nota del Plan / Alerta";
        typeIcon = Icons.info_outline_rounded;
        blockContent = OhtliAlertBlockEditor(
          alertData: alertData,
          isDark: isDark,
          onChanged: (newMarkdown) => _updateTextBlock(index, markdown: newMarkdown),
        );
      } else if (tableData != null) {
        typeLabel = "Tabla";
        typeIcon = Icons.table_chart_rounded;
        blockContent = OhtliTableBlockEditor(
          tableMarkdown: section.markdownText,
          isDark: isDark,
          onChanged: (newMarkdown) => _updateTextBlock(index, markdown: newMarkdown),
        );
      } else {
        typeLabel = "Nota / Historia";
        typeIcon = Icons.notes_rounded;
        
        final controller = _blockControllers.putIfAbsent(
          section.id,
          () {
            final c = MarkdownRichTextController(text: section.markdownText, context: context);
            c.addListener(() {
              _updateTextBlock(index, markdown: c.markdownText);
            });
            return c;
          },
        );

        final focusNode = _getFocusNode(section.id);

        blockContent = OhtliMarkdownEditor(
          controller: controller,
          focusNode: focusNode,
          hintText: 'Escribe tu anécdota, historia o consejo aquí...',
          minLines: 4,
          maxLines: null,
        );
      }
    } else if (section is TextImageSection) {
      typeLabel = "Nota con Imagen";
      typeIcon = Icons.photo_library_rounded;

      final controller = _blockControllers.putIfAbsent(
        section.id,
        () {
          final c = MarkdownRichTextController(text: section.markdownText, context: context);
          c.addListener(() {
            _updateTextImageBlock(index, markdown: c.markdownText);
          });
          return c;
        },
      );
      final focusNode = _getFocusNode(section.id);

      blockContent = LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth >= 500;
          final bool isImageLeft = section.layout == 'left';

          final Widget imageWidget = Container(
            width: 125,
            height: 165,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
                width: 1,
              ),
              image: section.imageUrl.isNotEmpty
                  ? DecorationImage(
                      image: _getImageProvider(section.imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: section.imageUrl.isEmpty
                ? GestureDetector(
                    onTap: () => _uploadImageForBlock(index, 'text_image'),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 20, color: isDark ? OhtliColors.onyx.withValues(alpha: 0.6) : OhtliColors.stormyTeal),
                        const SizedBox(height: 6),
                        Text(
                          'Subir (3:4)',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? OhtliColors.onyx.withValues(alpha: 0.6) : OhtliColors.stormyTeal,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => _showImageLightbox(_getImageProvider(section.imageUrl), 'Nota con Imagen'),
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(11),
                              bottomRight: Radius.circular(11),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              GestureDetector(
                                onTap: () => _uploadImageForBlock(index, 'text_image'),
                                behavior: HitTestBehavior.opaque,
                                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 11),
                              ),
                              Container(width: 1, height: 10, color: Colors.white24),
                              GestureDetector(
                                onTap: () => _updateTextImageBlock(index, photo: ''),
                                behavior: HitTestBehavior.opaque,
                                child: const Icon(Icons.delete_rounded, color: Colors.white, size: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          );

          final Widget textEditorWidget = OhtliMarkdownEditor(
            controller: controller,
            focusNode: focusNode,
            hintText: 'Añade tu descripción lateral...',
            minLines: 4,
            maxLines: null,
          );

          return Column(
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
                    checkmarkColor: Colors.white,
                    label: Text('Izquierda', style: GoogleFonts.inter(fontSize: 11)),
                    selected: section.layout == 'left',
                    onSelected: (val) {
                      if (val) _updateTextImageBlock(index, layout: 'left');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    checkmarkColor: Colors.white,
                    label: Text('Derecha', style: GoogleFonts.inter(fontSize: 11)),
                    selected: section.layout == 'right',
                    onSelected: (val) {
                      if (val) _updateTextImageBlock(index, layout: 'right');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isImageLeft) ...[
                      imageWidget,
                      const SizedBox(width: 16),
                    ],
                    Expanded(child: textEditorWidget),
                    if (!isImageLeft) ...[
                      const SizedBox(width: 16),
                      imageWidget,
                    ],
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: imageWidget,
                    ),
                    const SizedBox(height: 16),
                    textEditorWidget,
                  ],
                ),
            ],
          );
        },
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


  Widget _buildPhotoStack(List<Map<String, dynamic>> uploadedSlots, bool isDark) {
    // Sort so back cards are drawn first and front card (place_main) is drawn last (on top/front of Stack)
    final List<Map<String, dynamic>> drawOrderSlots = List.from(uploadedSlots);
    drawOrderSlots.sort((a, b) {
      final typeA = a['type'] as String;
      final typeB = b['type'] as String;
      int weight(String type) {
        if (type == 'place_sec_1') return 0;
        if (type == 'place_sec_0') return 1;
        if (type == 'place_main') return 2;
        return 3;
      }
      return weight(typeA).compareTo(weight(typeB));
    });

    return OhtliPlacePhotoStack(
      drawOrderSlots: drawOrderSlots,
      isDark: isDark,
      slotBuilder: (displaySlot, displayIndex) {
        final String displayUrl = displaySlot['url'] as String;
        final String displayLabel = displaySlot['label'] as String;
        final VoidCallback displayOnTap = displaySlot['onTap'] as VoidCallback;
        final VoidCallback displayOnDelete = displaySlot['onDelete'] as VoidCallback;
        return _buildPlacePhotoSlot(
          blockIndex: -1,
          photoUrl: displayUrl,
          label: displayLabel,
          onTap: displayOnTap,
          onDelete: displayOnDelete,
          isDark: isDark,
          onPhotoTap: () => _showPlacePhotoGallery(drawOrderSlots, displayIndex, isDark),
        );
      },
    );
  }

  // Interactive gallery for showing visited place photos
  void _showPlacePhotoGallery(List<Map<String, dynamic>> drawOrderSlots, int initialIndex, bool isDark) {
    int currentIndex = initialIndex;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeSlot = drawOrderSlots[currentIndex];
            final String label = activeSlot['label'] as String;
            final String photoUrl = activeSlot['url'] as String;
            final VoidCallback onTap = activeSlot['onTap'] as VoidCallback;
            final VoidCallback onDelete = activeSlot['onDelete'] as VoidCallback;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Full screen touch-dismiss underlay
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      color: Colors.transparent,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  
                  // Gallery main card
                  Container(
                    width: (MediaQuery.of(context).size.width * 0.9).clamp(280.0, 360.0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Dialog Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              label == 'Principal' ? 'Foto Principal' : label,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: OhtliColors.onyx,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded, size: 20),
                              color: OhtliColors.onyx.withValues(alpha: 0.6),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Image display with navigation arrows
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Left navigation arrow
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                              color: currentIndex > 0
                                  ? OhtliColors.stormyTeal
                                  : OhtliColors.cantera.withValues(alpha: 0.4),
                              onPressed: currentIndex > 0
                                  ? () {
                                      setDialogState(() {
                                        currentIndex--;
                                      });
                                    }
                                  : null,
                            ),
                            
                            // Photo box
                            Expanded(
                              child: Container(
                                height: 260,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: OhtliColors.cantera.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                  image: DecorationImage(
                                    image: _getImageProvider(photoUrl),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            
                            // Right navigation arrow
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                              color: currentIndex < drawOrderSlots.length - 1
                                  ? OhtliColors.stormyTeal
                                  : OhtliColors.cantera.withValues(alpha: 0.4),
                              onPressed: currentIndex < drawOrderSlots.length - 1
                                  ? () {
                                      setDialogState(() {
                                        currentIndex++;
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Indicator
                        Text(
                          '${currentIndex + 1} de ${drawOrderSlots.length}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.onyx.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Quick actions row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onTap();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: OhtliColors.stormyTeal,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              icon: const Icon(Icons.edit_rounded, size: 14),
                              label: Text(
                                'Editar',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Container(width: 1, height: 16, color: OhtliColors.cantera.withValues(alpha: 0.3)),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onDelete();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: OhtliColors.xoconostle,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded, size: 14),
                              label: Text(
                                'Quitar',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
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

  // Builder helper for Place Photo slots
  Widget _buildPlacePhotoSlot({
    required int blockIndex,
    required String photoUrl,
    required String label,
    required VoidCallback onTap,
    required VoidCallback onDelete,
    required bool isDark,
    VoidCallback? onPhotoTap,
  }) {
    final bool hasPhoto = photoUrl.isNotEmpty;
    final Color placeholderColor = isDark ? OhtliColors.onyx.withValues(alpha: 0.6) : OhtliColors.stormyTeal;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
          width: 1,
        ),
        image: hasPhoto
            ? DecorationImage(
                image: _getImageProvider(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: !hasPhoto
          ? GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 18, color: placeholderColor),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: placeholderColor,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Full size click for Lightbox detail view / Gallery
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onPhotoTap ?? () => _showImageLightbox(_getImageProvider(photoUrl), label),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
                // Bottom hover/action bar for editing/deleting
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(11),
                        bottomRight: Radius.circular(11),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: onTap,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'Editar',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 12, color: Colors.white24),
                        GestureDetector(
                          onTap: onDelete,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.delete_rounded, color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'Quitar',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showImageLightbox(ImageProvider provider, String label) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 600, maxWidth: 600),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Image(
                        image: provider,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }



  Widget _buildAddBlockButton({required String label, required IconData icon, required VoidCallback onTap, double? width}) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    return SizedBox(
      width: width,
      child: Material(
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
      ),
    );
  }
}

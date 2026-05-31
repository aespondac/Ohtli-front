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
        _descriptionController.text = cache['trip']['description'] ?? _descriptionController.text;
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

    for (var section in _sections) {
      if (section is PlaceSection) {
        String finalMain = section.mainPhotoUrl;
        if (finalMain.startsWith('data:')) {
          try {
            final String base64Data = finalMain.split(',').last;
            final Uint8List bytes = base64Decode(base64Data);
            final storageRef = FirebaseStorage.instance
                .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/sections/${section.id}_main.jpg');
            await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
            finalMain = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fsections%2F${section.id}_main.jpg?alt=media";
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
              final storageRef = FirebaseStorage.instance
                  .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/sections/${section.id}_sec_$i.jpg');
              await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
              secUrl = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fsections%2F${section.id}_sec_$i.jpg?alt=media";
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
        ));
      } else if (section is TextImageSection) {
        String finalImg = section.imageUrl;
        if (finalImg.startsWith('data:')) {
          try {
            final String base64Data = finalImg.split(',').last;
            final Uint8List bytes = base64Decode(base64Data);
            final storageRef = FirebaseStorage.instance
                .ref('users/${widget.trip.userId}/trips/${widget.trip.id}/sections/${section.id}_image.jpg');
            await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
            finalImg = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${widget.trip.userId}%2Ftrips%2F${widget.trip.id}%2Fsections%2F${section.id}_image.jpg?alt=media";
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
      description: _descriptionController.text,
      coverUrl: finalCoverUrl,
      status: _status,
      visibility: _visibility,
      createdAt: widget.trip.createdAt,
      updatedAt: now,
      travelDate: widget.trip.travelDate,
    );

    final updatedContent = TripContent(sections: updatedSections);

    try {
      await Future.wait([
        TripService().updateTrip(widget.trip.userId, updatedTrip),
        TripService().updateTripContent(widget.trip.userId, widget.trip.id, updatedContent),
      ]);

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

  // Markdown tool injector helper
  void _injectMarkdown(TextEditingController controller, String wrapper, {FocusNode? focusNode}) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) {
      final newText = text + wrapper;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      if (focusNode != null) {
        focusNode.requestFocus();
      }
      _onDataChanged();
      return;
    }

    int start = selection.start;
    int end = selection.end;
    String selectedText = selection.textInside(text);

    // If selection is collapsed, expand to the current word under cursor to toggle it
    if (start == end) {
      int wordStart = start;
      while (wordStart > 0 && _isWordChar(text[wordStart - 1])) {
        wordStart--;
      }
      int wordEnd = end;
      while (wordEnd < text.length && _isWordChar(text[wordEnd])) {
        wordEnd++;
      }
      if (wordStart < wordEnd) {
        start = wordStart;
        end = wordEnd;
        selectedText = text.substring(start, end);
      }
    }

    // List item toggle
    if (wrapper == '- ') {
      if (selectedText.startsWith('- ')) {
        final unwrappedText = selectedText.substring(2);
        final newText = text.replaceRange(start, end, unwrappedText);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + unwrappedText.length,
          ),
        );
      } else {
        final newText = text.replaceRange(start, end, '- $selectedText');
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + 2 + selectedText.length,
          ),
        );
      }
      if (focusNode != null) {
        focusNode.requestFocus();
      }
      _onDataChanged();
      return;
    }

    final len = wrapper.length;
    const formatChars = {'*', '_', '~'};

    // Find contiguous formatting characters immediately surrounding the selection to handle nesting
    int leftFormatStart = start;
    while (leftFormatStart > 0 && formatChars.contains(text[leftFormatStart - 1])) {
      leftFormatStart--;
    }
    final leftFormats = text.substring(leftFormatStart, start);

    int rightFormatEnd = end;
    while (rightFormatEnd < text.length && formatChars.contains(text[rightFormatEnd])) {
      rightFormatEnd++;
    }
    final rightFormats = text.substring(end, rightFormatEnd);

    // Case 1: Surrounding format chain contains the wrapper (Unwrapping / Deletion)
    if (_hasFormat(leftFormats, rightFormats, wrapper)) {
      final newLeftFormats = leftFormats.replaceFirst(wrapper, '');
      final newRightFormats = rightFormats.replaceFirst(wrapper, '');

      final newText = text.replaceRange(leftFormatStart, rightFormatEnd, '$newLeftFormats$selectedText$newRightFormats');
      final newStart = leftFormatStart + newLeftFormats.length;

      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: newStart,
          extentOffset: newStart + selectedText.length,
        ),
      );
    }
    // Case 2: Wrapping the selection (Insertion)
    else {
      final newText = text.replaceRange(start, end, '$wrapper$selectedText$wrapper');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: start + len,
          extentOffset: start + len + selectedText.length,
        ),
      );
    }

    if (focusNode != null) {
      focusNode.requestFocus();
    }
    _onDataChanged();
  }

  bool _isWordChar(String char) {
    if (char.isEmpty) return false;
    const exclude = {' ', '\n', '\r', '\t', '*', '_', '~', '.', ',', '!', '?', ';', ':', '(', ')', '[', ']', '{', '}'};
    return !exclude.contains(char);
  }

  bool _hasFormat(String left, String right, String wrapper) {
    final leftAsterisks = _countOccurrences(left, '*');
    final rightAsterisks = _countOccurrences(right, '*');
    final leftUnderlines = _countOccurrences(left, '_');
    final rightUnderlines = _countOccurrences(right, '_');

    if (wrapper == '**') {
      return leftAsterisks >= 2 && rightAsterisks >= 2;
    } else if (wrapper == '*') {
      return (leftAsterisks == 1 || leftAsterisks == 3) && 
             (rightAsterisks == 1 || rightAsterisks == 3);
    } else if (wrapper == '_') {
      return leftUnderlines >= 1 && rightUnderlines >= 1;
    }
    return false;
  }

  int _countOccurrences(String source, String char) {
    int count = 0;
    int index = 0;
    while ((index = source.indexOf(char, index)) != -1) {
      count++;
      index += char.length;
    }
    return count;
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
              Builder(
                builder: (context) {
                  final descFocusNode = _getFocusNode('trip_description');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMarkdownToolbar(_descriptionController, isDark, focusNode: descFocusNode),
                      CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(_descriptionController, '**', focusNode: descFocusNode),
                          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(_descriptionController, '**', focusNode: descFocusNode),
                          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(_descriptionController, '*', focusNode: descFocusNode),
                          const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(_descriptionController, '*', focusNode: descFocusNode),
                          const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(_descriptionController, '_', focusNode: descFocusNode),
                          const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(_descriptionController, '_', focusNode: descFocusNode),
                        },
                        child: TextFormField(
                          controller: _descriptionController,
                          focusNode: descFocusNode,
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
                      ),
                    ],
                  );
                }
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
            _updatePlaceBlock(index, description: c.text);
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMarkdownToolbar(controller, isDark, focusNode: focusNode),
                const SizedBox(height: 4),
                CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
                  },
                  child: TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 2,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: OhtliColors.onyx,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe una breve reseña de este lugar...',
                      hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
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
      VoidCallback? nextEmptySlotOnTap;
      if (section.mainPhotoUrl.isEmpty) {
        nextEmptySlotOnTap = () => _uploadImageForBlock(index, 'place_main');
      } else if (section.secondaryPhotoUrls.isEmpty) {
        nextEmptySlotOnTap = () => _uploadImageForBlock(index, 'place_sec_0');
      } else if (section.secondaryPhotoUrls.length < 2) {
        nextEmptySlotOnTap = () => _uploadImageForBlock(index, 'place_sec_1');
      }

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
        blockContent = _buildAlertBlockEditor(index, section, alertData, isDark);
      } else if (tableData != null) {
        typeLabel = "Tabla";
        typeIcon = Icons.table_chart_rounded;
        blockContent = _buildTableBlockEditor(index, section, tableData, isDark);
      } else {
        typeLabel = "Nota / Historia";
        typeIcon = Icons.notes_rounded;
        
        final controller = _blockControllers.putIfAbsent(
          section.id,
          () {
            final c = MarkdownRichTextController(text: section.markdownText, context: context);
            c.addListener(() {
              _updateTextBlock(index, markdown: c.text);
            });
            return c;
          },
        );

        final focusNode = _getFocusNode(section.id);

        blockContent = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMarkdownToolbar(controller, isDark, focusNode: focusNode),
              const SizedBox(height: 4),
              CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
                  const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
                  const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
                  const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
                  const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
                  const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
                },
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
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
                ),
              ),
            ],
          ),
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
            _updateTextImageBlock(index, markdown: c.text);
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

          final Widget textEditorWidget = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMarkdownToolbar(controller, isDark, focusNode: focusNode),
                const SizedBox(height: 4),
                CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
                    const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
                  },
                  child: TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 4,
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
                ),
              ],
            ),
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

  Widget _buildAlertBlockEditor(int index, TextSection section, AlertData alert, bool isDark) {
    Color alertColor = OhtliColors.stormyTeal;
    IconData alertIcon = Icons.info_outline_rounded;
    String alertName = "Nota / Info";
    
    if (alert.type == AlertType.warning) {
      alertColor = OhtliColors.xoconostle;
      alertIcon = Icons.warning_amber_rounded;
      alertName = "Advertencia";
    } else if (alert.type == AlertType.tip) {
      alertColor = OhtliColors.cempasuchil; // Cempasúchil Marigold Orange
      alertIcon = Icons.lightbulb_outline_rounded;
      alertName = "Consejo / Tip";
    }

    final controller = _blockControllers.putIfAbsent(
      '${section.id}_alert',
      () {
        final c = TextEditingController(text: alert.content);
        c.addListener(() {
          final newMarkdown = serializeAlertMarkdown(alert.type, c.text);
          _updateTextBlock(index, markdown: newMarkdown);
        });
        return c;
      },
    );

    final focusNode = _getFocusNode('${section.id}_alert');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF25252A) : alertColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: alertColor, width: 4),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(alertIcon, color: alertColor, size: 20),
              const SizedBox(width: 8),
              Text(
                alertName,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: alertColor,
                ),
              ),
              const Spacer(),
              // Choice chips to toggle types
              Wrap(
                spacing: 6,
                children: AlertType.values.map((type) {
                  final bool isSelected = alert.type == type;
                  Color chipColor = OhtliColors.stormyTeal;
                  String chipLabel = "Info";
                  if (type == AlertType.warning) {
                    chipColor = OhtliColors.xoconostle;
                    chipLabel = "Alerta";
                  } else if (type == AlertType.tip) {
                    chipColor = OhtliColors.cempasuchil; // Cempasúchil Orange
                    chipLabel = "Tip";
                  }
                  
                  return ChoiceChip(
                    label: Text(
                      chipLabel,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : chipColor,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: chipColor,
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? Colors.transparent : chipColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    onSelected: (val) {
                      if (val) {
                        final newMarkdown = serializeAlertMarkdown(type, controller.text);
                        _updateTextBlock(index, markdown: newMarkdown);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(controller, '**', focusNode: focusNode),
              const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
              const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(controller, '*', focusNode: focusNode),
              const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
              const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(controller, '_', focusNode: focusNode),
            },
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              maxLines: 3,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: OhtliColors.onyx,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Escribe tu nota, advertencia o tip aquí...',
                hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBlockEditor(int index, TextSection section, TableData table, bool isDark) {
    final int numCols = table.columns.length;
    final int numRows = table.rows.length;

    TextEditingController getCellController(String key, String initialText) {
      return _blockControllers.putIfAbsent(key, () {
        final c = TextEditingController(text: initialText);
        c.addListener(_onDataChanged); // Trigger auto-save silently
        return c;
      });
    }

    void updateColumnType(int colIdx, String newType, String newCurrency) {
      final List<TableColumn> currentColumns = [];
      for (int c = 0; c < numCols; c++) {
        final ctrl = _blockControllers['${section.id}_h_$c'];
        final currentCol = table.columns[c];
        if (c == colIdx) {
          currentColumns.add(TableColumn(
            name: ctrl?.text ?? currentCol.name,
            type: newType,
            currency: newCurrency,
          ));
        } else {
          currentColumns.add(TableColumn(
            name: ctrl?.text ?? currentCol.name,
            type: currentCol.type,
            currency: currentCol.currency,
          ));
        }
      }

      final List<List<String>> currentRows = [];
      for (int r = 0; r < numRows; r++) {
        final List<String> rowCells = [];
        for (int c = 0; c < numCols; c++) {
          final ctrl = _blockControllers['${section.id}_cell_${r}_$c'];
          rowCells.add(ctrl?.text ?? table.rows[r][c]);
        }
        currentRows.add(rowCells);
      }

      _blockControllers.keys
          .where((k) => k.startsWith(section.id))
          .toList()
          .forEach((k) => _blockControllers.remove(k)?.dispose());

      final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
      _updateTextBlock(index, markdown: newMarkdown);
    }

    void addColumn() {
      final List<TableColumn> currentColumns = [];
      for (int c = 0; c < numCols; c++) {
        final ctrl = _blockControllers['${section.id}_h_$c'];
        final currentCol = table.columns[c];
        currentColumns.add(TableColumn(
          name: ctrl?.text ?? currentCol.name,
          type: currentCol.type,
          currency: currentCol.currency,
        ));
      }
      currentColumns.add(TableColumn(name: 'Columna ${numCols + 1}', type: 'text'));

      final List<List<String>> currentRows = [];
      for (int r = 0; r < numRows; r++) {
        final List<String> rowCells = [];
        for (int c = 0; c < numCols; c++) {
          final ctrl = _blockControllers['${section.id}_cell_${r}_$c'];
          rowCells.add(ctrl?.text ?? table.rows[r][c]);
        }
        rowCells.add(''); // Add cell for new column
        currentRows.add(rowCells);
      }

      _blockControllers.keys
          .where((k) => k.startsWith(section.id))
          .toList()
          .forEach((k) => _blockControllers.remove(k)?.dispose());

      final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
      _updateTextBlock(index, markdown: newMarkdown);
    }

    void deleteColumn(int colIdx) {
      if (numCols <= 1) return;
      final List<TableColumn> currentColumns = [];
      for (int c = 0; c < numCols; c++) {
        final ctrl = _blockControllers['${section.id}_h_$c'];
        final currentCol = table.columns[c];
        currentColumns.add(TableColumn(
          name: ctrl?.text ?? currentCol.name,
          type: currentCol.type,
          currency: currentCol.currency,
        ));
      }
      currentColumns.removeAt(colIdx);

      final List<List<String>> currentRows = [];
      for (int r = 0; r < numRows; r++) {
        final List<String> rowCells = [];
        for (int c = 0; c < numCols; c++) {
          final ctrl = _blockControllers['${section.id}_cell_${r}_$c'];
          rowCells.add(ctrl?.text ?? table.rows[r][c]);
        }
        rowCells.removeAt(colIdx);
        currentRows.add(rowCells);
      }

      _blockControllers.keys
          .where((k) => k.startsWith(section.id))
          .toList()
          .forEach((k) => _blockControllers.remove(k)?.dispose());

      final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
      _updateTextBlock(index, markdown: newMarkdown);
    }

    void addRow() {
      final List<TableColumn> currentColumns = [];
      for (int c = 0; c < numCols; c++) {
        final ctrl = _blockControllers['${section.id}_h_$c'];
        final currentCol = table.columns[c];
        currentColumns.add(TableColumn(
          name: ctrl?.text ?? currentCol.name,
          type: currentCol.type,
          currency: currentCol.currency,
        ));
      }

      final List<List<String>> currentRows = [];
      for (int r = 0; r < numRows; r++) {
        final List<String> rowCells = [];
        for (int c = 0; c < numCols; c++) {
          final ctrl = _blockControllers['${section.id}_cell_${r}_$c'];
          rowCells.add(ctrl?.text ?? table.rows[r][c]);
        }
        currentRows.add(rowCells);
      }
      currentRows.add(List<String>.filled(numCols, ''));

      _blockControllers.keys
          .where((k) => k.startsWith(section.id))
          .toList()
          .forEach((k) => _blockControllers.remove(k)?.dispose());

      final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
      _updateTextBlock(index, markdown: newMarkdown);
    }

    void deleteRow(int rowIdx) {
      final List<TableColumn> currentColumns = [];
      for (int c = 0; c < numCols; c++) {
        final ctrl = _blockControllers['${section.id}_h_$c'];
        final currentCol = table.columns[c];
        currentColumns.add(TableColumn(
          name: ctrl?.text ?? currentCol.name,
          type: currentCol.type,
          currency: currentCol.currency,
        ));
      }

      final List<List<String>> currentRows = [];
      for (int r = 0; r < numRows; r++) {
        final List<String> rowCells = [];
        for (int c = 0; c < numCols; c++) {
          final ctrl = _blockControllers['${section.id}_cell_${r}_$c'];
          rowCells.add(ctrl?.text ?? table.rows[r][c]);
        }
        currentRows.add(rowCells);
      }
      if (rowIdx < currentRows.length) {
        currentRows.removeAt(rowIdx);
      }

      _blockControllers.keys
          .where((k) => k.startsWith(section.id))
          .toList()
          .forEach((k) => _blockControllers.remove(k)?.dispose());

      final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
      _updateTextBlock(index, markdown: newMarkdown);
    }

    final Color headerBg = isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.2);
    final Color cellBorder = isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column Headers Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(numCols, (colIdx) {
                    final ctrl = getCellController(
                      '${section.id}_h_$colIdx',
                      table.columns[colIdx].name,
                    );
                    final col = table.columns[colIdx];
                    final bool isMoney = col.type == 'money';

                    return Container(
                      width: 155,
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final fNode = _getFocusNode('${section.id}_h_$colIdx');
                                    return CallbackShortcuts(
                                      bindings: <ShortcutActivator, VoidCallback>{
                                        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                      },
                                      child: TextFormField(
                                        controller: ctrl,
                                        focusNode: fNode,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: OhtliColors.onyx,
                                        ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                ),
                              ),
                              // Type menu selector (Texto vs Dinero)
                              PopupMenuButton<String>(
                                icon: Icon(
                                  isMoney ? Icons.payments_rounded : Icons.text_fields_rounded,
                                  size: 14,
                                  color: OhtliColors.stormyTeal,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (val) {
                                  if (val == 'text') {
                                    updateColumnType(colIdx, 'text', 'MXN');
                                  } else {
                                    updateColumnType(colIdx, 'money', val);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'text',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.text_fields_rounded, size: 14),
                                        const SizedBox(width: 8),
                                        Text('📝 Texto', style: GoogleFonts.inter(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  ...['MXN', 'USD', 'EUR', 'CAD', 'GBP'].map((curr) {
                                    return PopupMenuItem(
                                      value: curr,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.payments_rounded, size: 14, color: Colors.amber),
                                          const SizedBox(width: 8),
                                          Text('💵 Dinero ($curr)', style: GoogleFonts.inter(fontSize: 11)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ],
                          ),
                          if (numCols > 1)
                            Align(
                              alignment: Alignment.centerRight,
                              child: InkWell(
                                onTap: () => deleteColumn(colIdx),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: OhtliColors.xoconostle.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: OhtliColors.stormyTeal),
                    onPressed: addColumn,
                    tooltip: 'Añadir Columna',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Rows
              ...List.generate(numRows, (rowIdx) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      ...List.generate(numCols, (colIdx) {
                        final cellVal = table.rows[rowIdx][colIdx];
                        final ctrl = getCellController(
                          '${section.id}_cell_${rowIdx}_$colIdx',
                          cellVal,
                        );
                        final col = table.columns[colIdx];
                        final bool isMoney = col.type == 'money';

                        return Container(
                          width: 155,
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cellBorder),
                          ),
                          child: Builder(
                            builder: (context) {
                              final fNode = _getFocusNode('${section.id}_cell_${rowIdx}_$colIdx');
                              return CallbackShortcuts(
                                bindings: <ShortcutActivator, VoidCallback>{
                                  const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                },
                                child: TextFormField(
                                  controller: ctrl,
                                  focusNode: fNode,
                                  style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx),
                                  keyboardType: isMoney ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                                  inputFormatters: isMoney ? [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                  ] : null,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                    prefixText: isMoney ? '\$ ' : null,
                                    suffixText: isMoney ? col.currency : null,
                                    suffixStyle: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }
                          ),
                        );
                      }),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: OhtliColors.xoconostle),
                        onPressed: () => deleteRow(rowIdx),
                        tooltip: 'Eliminar Fila',
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: addRow,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(
            'Añadir Fila',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.1),
            foregroundColor: OhtliColors.stormyTeal,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
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

  // Builder helper for Markdown Toolbar
  Widget _buildMarkdownToolbar(TextEditingController controller, bool isDark, {FocusNode? focusNode}) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final text = value.text;
        final sel = value.selection;
        final isBold = _isFormatActive(text, sel, '**');
        final isItalic = _isFormatActive(text, sel, '*');
        final isUnderline = _isFormatActive(text, sel, '_');
        
        bool isList = false;
        if (sel.isValid) {
          final selectedText = sel.textInside(text);
          if (selectedText.startsWith('- ')) {
            isList = true;
          } else {
            int lineStart = sel.start;
            while (lineStart > 0 && text[lineStart - 1] != '\n') {
              lineStart--;
            }
            if (lineStart + 2 <= text.length && text.substring(lineStart, lineStart + 2) == '- ') {
              isList = true;
            }
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolbarButton(
                icon: Icons.format_bold_rounded,
                tooltip: 'Negrita (**)',
                isActive: isBold,
                onTap: () => _injectMarkdown(controller, '**', focusNode: focusNode),
              ),
              _buildToolbarButton(
                icon: Icons.format_italic_rounded,
                tooltip: 'Cursiva (*)',
                isActive: isItalic,
                onTap: () => _injectMarkdown(controller, '*', focusNode: focusNode),
              ),
              _buildToolbarButton(
                icon: Icons.format_underlined_rounded,
                tooltip: 'Subrayado (_)',
                isActive: isUnderline,
                onTap: () => _injectMarkdown(controller, '_', focusNode: focusNode),
              ),
              _buildToolbarButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: 'Lista (-)',
                isActive: isList,
                onTap: () => _injectMarkdown(controller, '- ', focusNode: focusNode),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color activeColor = OhtliColors.cempasuchil;
    final Color inactiveColor = isDark ? OhtliColors.onyx.withValues(alpha: 0.7) : OhtliColors.stormyTeal;

    return Tooltip(
      message: tooltip,
      textStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white),
      child: Container(
        decoration: BoxDecoration(
          color: isActive 
              ? (isDark ? activeColor.withValues(alpha: 0.15) : activeColor.withValues(alpha: 0.1)) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
          icon: Icon(
            icon, 
            size: 16, 
            color: isActive ? activeColor : inactiveColor,
          ),
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: onTap,
        ),
      ),
    );
  }

  bool _isFormatActive(String text, TextSelection sel, String wrapper) {
    if (!sel.isValid) return false;
    int start = sel.start;
    int end = sel.end;

    if (start == end) {
      int wordStart = start;
      while (wordStart > 0 && _isWordChar(text[wordStart - 1])) {
        wordStart--;
      }
      int wordEnd = end;
      while (wordEnd < text.length && _isWordChar(text[wordEnd])) {
        wordEnd++;
      }
      if (wordStart < wordEnd) {
        start = wordStart;
        end = wordEnd;
      }
    }

    const formatChars = {'*', '_', '~'};
    int leftFormatStart = start;
    while (leftFormatStart > 0 && formatChars.contains(text[leftFormatStart - 1])) {
      leftFormatStart--;
    }
    final leftFormats = text.substring(leftFormatStart, start);

    int rightFormatEnd = end;
    while (rightFormatEnd < text.length && formatChars.contains(text[rightFormatEnd])) {
      rightFormatEnd++;
    }
    final rightFormats = text.substring(end, rightFormatEnd);

    return leftFormats.contains(wrapper) && rightFormats.contains(wrapper);
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

class MarkdownRichTextController extends TextEditingController {
  final BuildContext context;

  MarkdownRichTextController({super.text, required this.context});

  List<InlineSpan> _parseInline(String text, TextStyle defaultStyle, Color syntaxColor, int globalOffset) {
    final List<InlineSpan> spans = [];
    
    // RegExp for inline bold (**), italic (*), and underline (_)
    final regExp = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(\_(.*?)\_)');
    final matches = regExp.allMatches(text);
    
    // Get cursor selection
    final cursorStart = selection.start;
    final cursorEnd = selection.end;
    final bool hasSelection = selection.isValid;

    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: defaultStyle));
      }
      
      final String matchText = match.group(0)!;
      final int startInText = globalOffset + match.start;
      final int endInText = globalOffset + match.end;

      // Hiding utility style: checks if cursor touches/is editing the marker
      TextStyle hideStyle(int mStart, int mEnd) {
        final bool isEditingMarker = hasSelection && (
          (cursorStart >= mStart && cursorStart <= mEnd) ||
          (cursorEnd >= mStart && cursorEnd <= mEnd)
        );
        if (isEditingMarker) {
          return defaultStyle.copyWith(color: syntaxColor);
        } else {
          return defaultStyle.copyWith(
            color: Colors.transparent,
            fontSize: 0.01,
            letterSpacing: -3.0,
          );
        }
      }

      if (matchText.startsWith('**') && matchText.endsWith('**')) {
        // Bold
        final innerText = match.group(2) ?? '';
        final leftMarkerStart = startInText;
        final leftMarkerEnd = startInText + 2;
        final rightMarkerStart = endInText - 2;
        final rightMarkerEnd = endInText;

        spans.add(TextSpan(text: '**', style: hideStyle(leftMarkerStart, leftMarkerEnd)));
        spans.add(TextSpan(text: innerText, style: defaultStyle.copyWith(fontWeight: FontWeight.bold)));
        spans.add(TextSpan(text: '**', style: hideStyle(rightMarkerStart, rightMarkerEnd)));
      } else if (matchText.startsWith('*') && matchText.endsWith('*')) {
        // Italic
        final innerText = match.group(4) ?? '';
        final leftMarkerStart = startInText;
        final leftMarkerEnd = startInText + 1;
        final rightMarkerStart = endInText - 1;
        final rightMarkerEnd = endInText;

        spans.add(TextSpan(text: '*', style: hideStyle(leftMarkerStart, leftMarkerEnd)));
        spans.add(TextSpan(text: innerText, style: defaultStyle.copyWith(fontStyle: FontStyle.italic)));
        spans.add(TextSpan(text: '*', style: hideStyle(rightMarkerStart, rightMarkerEnd)));
      } else if (matchText.startsWith('_') && matchText.endsWith('_')) {
        // Underline
        final innerText = match.group(6) ?? '';
        final leftMarkerStart = startInText;
        final leftMarkerEnd = startInText + 1;
        final rightMarkerStart = endInText - 1;
        final rightMarkerEnd = endInText;

        spans.add(TextSpan(text: '_', style: hideStyle(leftMarkerStart, leftMarkerEnd)));
        spans.add(TextSpan(text: innerText, style: defaultStyle.copyWith(decoration: TextDecoration.underline)));
        spans.add(TextSpan(text: '_', style: hideStyle(rightMarkerStart, rightMarkerEnd)));
      }
      
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: defaultStyle));
    }
    
    return spans;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final defaultStyle = style ?? GoogleFonts.inter(color: OhtliColors.onyx);
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color syntaxColor = isDark 
        ? OhtliColors.onyx.withValues(alpha: 0.12) 
        : OhtliColors.onyx.withValues(alpha: 0.18);
    final Color accentColor = OhtliColors.stormyTeal;

    final List<InlineSpan> spans = [];
    final lines = text.split('\n');
    int globalOffset = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      
      // 1. Markdown Table Check
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        final tableStyle = GoogleFonts.robotoMono(
          color: OhtliColors.onyx,
          fontSize: (defaultStyle.fontSize ?? 13) * 0.95,
          fontWeight: FontWeight.w500,
        );
        
        int lastPipe = 0;
        for (int c = 0; c < line.length; c++) {
          if (line[c] == '|') {
            if (c > lastPipe) {
              spans.add(TextSpan(
                text: line.substring(lastPipe, c),
                style: tableStyle,
              ));
            }
            spans.add(TextSpan(
              text: '|',
              style: tableStyle.copyWith(color: accentColor, fontWeight: FontWeight.bold),
            ));
            lastPipe = c + 1;
          }
        }
        if (lastPipe < line.length) {
          spans.add(TextSpan(
            text: line.substring(lastPipe),
            style: tableStyle,
          ));
        }
      } 
      // 2. Markdown Bullet List Check
      else if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* ')) {
        final leadingSpaces = line.length - line.trimLeft().length;
        final listMarker = line.trimLeft().startsWith('- ') ? '- ' : '* ';
        
        if (leadingSpaces > 0) {
          spans.add(TextSpan(text: line.substring(0, leadingSpaces), style: defaultStyle));
        }
        spans.add(TextSpan(
          text: listMarker,
          style: defaultStyle.copyWith(color: accentColor, fontWeight: FontWeight.bold),
        ));
        
        final remainingText = line.trimLeft().substring(2);
        spans.addAll(_parseInline(remainingText, defaultStyle, syntaxColor, globalOffset + leadingSpaces + 2));
      } 
      // 3. Normal text line
      else {
        spans.addAll(_parseInline(line, defaultStyle, syntaxColor, globalOffset));
      }

      if (!isLastLine) {
        spans.add(TextSpan(text: '\n', style: defaultStyle));
      }
      globalOffset += line.length + 1; // +1 for the '\n'
    }

    return TextSpan(children: spans, style: defaultStyle);
  }
}

// Markdown Alerta/Nota Helpers
enum AlertType { note, warning, tip }

class AlertData {
  final AlertType type;
  final String content;

  AlertData({required this.type, required this.content});
}

AlertData? parseAlertMarkdown(String markdown) {
  final trimmed = markdown.trim();
  if (!trimmed.startsWith('> [!')) return null;

  AlertType type = AlertType.note;
  if (trimmed.contains('[!WARNING]')) {
    type = AlertType.warning;
  } else if (trimmed.contains('[!TIP]')) {
    type = AlertType.tip;
  }

  final lines = markdown.split('\n');
  final List<String> contentLines = [];
  for (var line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith('> [!')) continue;
    if (trimmedLine.startsWith('>')) {
      var contentLine = trimmedLine.substring(1);
      if (contentLine.startsWith(' ')) {
        contentLine = contentLine.substring(1);
      }
      contentLines.add(contentLine);
    } else if (trimmedLine.isNotEmpty) {
      contentLines.add(trimmedLine);
    }
  }

  return AlertData(
    type: type,
    content: contentLines.join('\n').trim(),
  );
}

String serializeAlertMarkdown(AlertType type, String content) {
  final String typeStr = type == AlertType.warning 
      ? 'WARNING' 
      : (type == AlertType.tip ? 'TIP' : 'NOTE');
  
  final lines = content.split('\n');
  final buffer = StringBuffer();
  buffer.writeln('> [!$typeStr]');
  for (var line in lines) {
    buffer.writeln('> $line');
  }
  return buffer.toString().trim();
}

// Markdown Table Helpers
class TableColumn {
  final String name;
  final String type; // 'text' or 'money'
  final String currency; // 'MXN', 'USD', etc.

  TableColumn({required this.name, this.type = 'text', this.currency = 'MXN'});
}

class TableData {
  final List<TableColumn> columns;
  final List<List<String>> rows;

  TableData({required this.columns, required this.rows});
}

TableData? parseTableMarkdown(String markdown) {
  final lines = markdown.trim().split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.length < 2) return null;

  if (!lines[0].startsWith('|') || !lines[0].endsWith('|')) return null;
  if (!lines[1].startsWith('|') || !lines[1].endsWith('|')) return null;
  if (!lines[1].contains('---') && !lines[1].contains('-')) return null;

  List<String> splitRow(String row) {
    final parts = row.split('|');
    if (parts.length > 2) {
      final sub = parts.sublist(1, parts.length - 1);
      return sub.map((s) => s.trim()).toList();
    }
    return [];
  }

  final headers = splitRow(lines[0]);
  if (headers.isEmpty) return null;

  final List<TableColumn> columns = headers.map((h) {
    final moneyReg = RegExp(r'^(.*?)\s*\[money:([A-Z]{3,5})\]$');
    final textReg = RegExp(r'^(.*?)\s*\[text\]$');
    
    if (moneyReg.hasMatch(h)) {
      final match = moneyReg.firstMatch(h)!;
      return TableColumn(
        name: match.group(1)!.trim(),
        type: 'money',
        currency: match.group(2)!.toUpperCase(),
      );
    } else if (textReg.hasMatch(h)) {
      final match = textReg.firstMatch(h)!;
      return TableColumn(
        name: match.group(1)!.trim(),
        type: 'text',
      );
    } else {
      return TableColumn(name: h.trim(), type: 'text');
    }
  }).toList();

  final List<List<String>> rows = [];
  for (int i = 2; i < lines.length; i++) {
    if (lines[i].startsWith('|') && lines[i].endsWith('|')) {
      final rowParts = splitRow(lines[i]);
      while (rowParts.length < columns.length) {
        rowParts.add('');
      }
      rows.add(rowParts.sublist(0, columns.length));
    }
  }

  return TableData(columns: columns, rows: rows);
}

String serializeTableMarkdown(TableData table) {
  final buffer = StringBuffer();
  
  buffer.write('| ');
  final headerStrings = table.columns.map((col) {
    if (col.type == 'money') {
      return '${col.name} [money:${col.currency}]';
    } else {
      return col.name;
    }
  }).toList();
  buffer.write(headerStrings.join(' | '));
  buffer.writeln(' |');
  
  buffer.write('|');
  for (int i = 0; i < table.columns.length; i++) {
    buffer.write('---|');
  }
  buffer.writeln();
  
  for (final row in table.rows) {
    buffer.write('| ');
    buffer.write(row.join(' | '));
    buffer.writeln(' |');
  }
  
  return buffer.toString().trim();
}

// Standalone StatefulWidget for premium fanning out spring micro-animations on hover/tap
class OhtliPlacePhotoStack extends StatefulWidget {
  final List<Map<String, dynamic>> drawOrderSlots;
  final bool isDark;
  final Widget Function(Map<String, dynamic> slot, int index) slotBuilder;

  const OhtliPlacePhotoStack({
    super.key,
    required this.drawOrderSlots,
    required this.isDark,
    required this.slotBuilder,
  });

  @override
  State<OhtliPlacePhotoStack> createState() => _OhtliPlacePhotoStackState();
}

class _OhtliPlacePhotoStackState extends State<OhtliPlacePhotoStack> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final int count = widget.drawOrderSlots.length;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) => setState(() => _isHovered = false),
        onTapCancel: () => setState(() => _isHovered = false),
        child: SizedBox(
          width: 160,
          height: 195,
          child: Stack(
            clipBehavior: Clip.none,
            children: List.generate(count, (displayIndex) {
              final displaySlot = widget.drawOrderSlots[displayIndex];
              final String type = displaySlot['type'] as String;

              double rotation = 0.0;
              double offsetX = 0.0;
              double offsetY = 0.0;
              double scale = 1.0;

              // Compute bouncy premium offsets when hovered/tapped to fan out
              if (count == 3) {
                if (type == 'place_sec_1') { // back card
                  rotation = _isHovered ? -0.15 : -0.06;
                  offsetX = _isHovered ? -26.0 : -10.0;
                  offsetY = _isHovered ? -8.0 : -6.0;
                } else if (type == 'place_sec_0') { // middle card
                  rotation = _isHovered ? 0.12 : 0.05;
                  offsetX = _isHovered ? 24.0 : 8.0;
                  offsetY = _isHovered ? -5.0 : -3.0;
                } else if (type == 'place_main') { // front card
                  rotation = 0.0;
                  offsetX = 0.0;
                  offsetY = 0.0;
                  scale = _isHovered ? 1.05 : 1.0;
                }
              } else if (count == 2) {
                if (type != 'place_main') { // back card
                  rotation = _isHovered ? -0.12 : -0.05;
                  offsetX = _isHovered ? -20.0 : -8.0;
                  offsetY = _isHovered ? -6.0 : -4.0;
                } else { // front card
                  rotation = 0.0;
                  offsetX = 0.0;
                  offsetY = 0.0;
                  scale = _isHovered ? 1.05 : 1.0;
                }
              }

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack, // High-end spring physics curve
                left: 15 + offsetX,
                top: 10 + offsetY,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  scale: scale,
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    turns: rotation / (2 * 3.14159265),
                    child: SizedBox(
                      width: 120,
                      height: 160,
                      child: widget.slotBuilder(displaySlot, displayIndex),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

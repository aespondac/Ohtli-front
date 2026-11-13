import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../widgets/ohtli_markdown_editor.dart';
import '../../widgets/ohtli_place_photo_stack.dart';
import '../../services/markdown_helpers.dart';
import 'package:uuid/uuid.dart';
import 'widgets/alert_block_editor.dart';
import 'widgets/table_block_editor.dart';
import 'widgets/coauthors_modal.dart';
import 'trip_viewer_page.dart';
import '../places/places_page.dart';
import '../../models/poi_model.dart';
import '../../services/trip_transfers.dart';
import '../../config/editorial.dart';

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
  bool _isPublishing = false;
  
  Timer? _debounceTimer;
  
  // Persistent TextEditingControllers for text inputs to avoid cursor jumps
  final Map<String, TextEditingController> _blockControllers = {};

  // Persistent FocusNodes for text inputs to return focus when formatting
  final Map<String, FocusNode> _blockFocusNodes = {};

  // Deshacer / rehacer (E4): instantáneas JSON del viaje. Las ráfagas de escritura
  // se agrupan en un solo paso; las acciones estructurales siempre abren uno nuevo.
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String? _currentSnapshot;
  DateTime _lastSnapshotAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isRestoringSnapshot = false;
  bool _forceNewUndoStep = false;
  static const int _maxUndoSteps = 40;

  // Tipo de publicación: viaje o notas de versión (solo equipo editorial).
  late String _kind = widget.trip.kind;
  late final TextEditingController _versionController = TextEditingController(text: widget.trip.version ?? '');
  bool get _canPublishReleaseNotes => isEditorialTeam(FirebaseAuth.instance.currentUser?.uid);

  // Generación de los editores de bloque: al deshacer se recrean desde los datos.
  int _editorGeneration = 0;

  // Claves para desplazarse a un bloque desde el índice (E5).
  final Map<String, GlobalKey> _blockKeys = {};

  // Image provider cache to prevent flickering
  final Map<String, ImageProvider> _imageProvidersCache = {};

  // Local changes tracking
  DateTime? _lastSavedCloudTime;
  // Estado real de sincronización: antes el indicador decía "Sincronizado" aunque hubiera
  // cambios pendientes o el último guardado hubiera fallado.
  int _editVersion = 0;
  int _savedEditVersion = 0;
  String? _cloudSaveError;
  int _failedUploads = 0;
  bool get _hasPendingCloudChanges => _editVersion != _savedEditVersion;

  // New fields for co-authors & surprise
  List<String> _coAuthorIds = [];
  List<String> _originalCoAuthorIds = [];
  List<String> _coAuthorNames = [];
  bool _isSurprise = false;
  List<String> _surpriseTargetIds = [];
  List<String> _surpriseTargetNames = [];
  Map<String, DateTime> _surpriseUnlockDates = {};
  bool _unlockOnPublish = false;
  List<Map<String, dynamic>> _friendsList = [];
  bool _isLoadingFriends = false;

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

    // Initialize co-authors and surprise targets lists
    _coAuthorIds = List.from(widget.trip.coAuthorIds);
    _originalCoAuthorIds = List.from(widget.trip.coAuthorIds);
    _coAuthorNames = List.from(widget.trip.coAuthorNames);
    _isSurprise = widget.trip.isSurprise;
    _surpriseTargetIds = List.from(widget.trip.surpriseTargetIds);
    _surpriseTargetNames = List.from(widget.trip.surpriseTargetNames);
    _surpriseUnlockDates = Map.from(widget.trip.surpriseUnlockDates);
    _unlockOnPublish = widget.trip.unlockOnPublish;

    _loadCloudContentAndCheckCache();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (mounted) setState(() => _isLoadingFriends = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          final List<dynamic> friendsUids = data?['friends'] ?? [];
          final List<dynamic> myCloseFriends = data?['closeFriends'] ?? [];
          
          final Set<String> uidsToFetch = {
            ...friendsUids.cast<String>(),
            ..._coAuthorIds,
          };

          if (uidsToFetch.isNotEmpty) {
            final List<String> uidsList = uidsToFetch.take(30).toList();
            final friendsSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where(FieldPath.documentId, whereIn: uidsList)
                .get();
            
            final List<Map<String, dynamic>> fetched = [];
            for (var doc in friendsSnapshot.docs) {
              final dName = doc.data()['displayName'] ?? 'Viajero Ohtli';
              final List<dynamic> friendCloseFriends = doc.data()['closeFriends'] ?? [];
              final bool isMutualCloseFriend = friendCloseFriends.contains(user.uid) && 
                  myCloseFriends.contains(doc.id);
              
              fetched.add({
                'uid': doc.id,
                'displayName': dName,
                'photoURL': doc.data()['photoURL'],
                'isMutualCloseFriend': isMutualCloseFriend,
                'isCloseFriend': myCloseFriends.contains(doc.id),
                'isFriend': friendsUids.contains(doc.id),
              });
            }
            if (mounted) {
              setState(() {
                _friendsList = fetched;
                _isLoadingFriends = false;
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      print("Error loading friends in trip editor: $e");
    }
    if (mounted) setState(() => _isLoadingFriends = false);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _versionController.dispose();
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

      _resetUndoBaseline();
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
        _resetBlockEditors();
      }
    });
    _resetUndoBaseline();

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
    _recordUndoStep();
  }

  // ---------------------------------------------------------------------------
  // Deshacer / rehacer
  // ---------------------------------------------------------------------------
  String _buildSnapshot() => jsonEncode({
        'title': _titleController.text,
        'description': _descriptionController.markdownText,
        'coverUrl': _coverUrl,
        'sections': _sections.map((s) => s.toMap()).toList(),
      });

  void _resetUndoBaseline() {
    _currentSnapshot = _buildSnapshot();
    _lastSnapshotAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _recordUndoStep() {
    if (_isRestoringSnapshot) return;
    final snap = _buildSnapshot();
    if (_currentSnapshot == null) {
      _currentSnapshot = snap;
      return;
    }
    if (snap == _currentSnapshot) return;
    final now = DateTime.now();
    final bool hadUndo = _undoStack.isNotEmpty;
    final bool hadRedo = _redoStack.isNotEmpty;
    final bool sameBurst = !_forceNewUndoStep &&
        now.difference(_lastSnapshotAt) < const Duration(milliseconds: 1200);
    if (!sameBurst) {
      _undoStack.add(_currentSnapshot!);
      if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _currentSnapshot = snap;
    // Tras una acción estructural, lo siguiente que se escriba es otro paso.
    _lastSnapshotAt = _forceNewUndoStep ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    _forceNewUndoStep = false;
    if (hadUndo != _undoStack.isNotEmpty || hadRedo != _redoStack.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_currentSnapshot ?? _buildSnapshot());
    _applySnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_currentSnapshot ?? _buildSnapshot());
    _applySnapshot(_redoStack.removeLast());
  }

  void _applySnapshot(String snap) {
    final data = jsonDecode(snap) as Map<String, dynamic>;
    _isRestoringSnapshot = true;
    setState(() {
      _titleController.text = data['title'] ?? '';
      _descriptionController.text = data['description'] ?? '';
      _coverUrl = data['coverUrl'] ?? '';
      _sections = (data['sections'] as List<dynamic>)
          .map((m) => TripSection.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
      _resetBlockEditors();
    });
    _currentSnapshot = snap;
    _lastSnapshotAt = DateTime.fromMillisecondsSinceEpoch(0);
    _saveToLocalCache();
    _isRestoringSnapshot = false;
  }

  /// Descarta los controladores de texto de los bloques para que se vuelvan a
  /// crear con el contenido actual (tras deshacer o vincular un lugar).
  void _resetBlockEditors() {
    final old = _blockControllers.values.toList();
    _blockControllers.clear();
    _editorGeneration++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  Trip _buildCurrentTrip({String? coverUrl, DateTime? updatedAt}) {
    return Trip(
      id: widget.trip.id,
      userId: widget.trip.userId,
      title: _titleController.text,
      description: _descriptionController.markdownText,
      coverUrl: coverUrl ?? _coverUrl,
      status: _status,
      visibility: _visibility,
      createdAt: widget.trip.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      travelDate: _travelDate,
      errataHistory: _errataHistory,
      coAuthorIds: _coAuthorIds,
      coAuthorNames: _coAuthorNames,
      isSurprise: _isSurprise,
      surpriseTargetIds: _surpriseTargetIds,
      surpriseTargetNames: _surpriseTargetNames,
      surpriseUnlockDates: _surpriseUnlockDates,
      unlockOnPublish: _unlockOnPublish,
      surpriseOpenedBy: widget.trip.surpriseOpenedBy,
      reviewedAt: widget.trip.reviewedAt,
      kind: _kind,
      version: _kind == kTripKindReleaseNotes && _versionController.text.trim().isNotEmpty
          ? _versionController.text.trim()
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Vista previa (E6)
  // ---------------------------------------------------------------------------
  void _openPreview() {
    _syncAllTables();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripViewerPage(
          trip: _buildCurrentTrip(),
          previewSections: List<TripSection>.from(_sections),
        ),
      ),
    );
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
    final wasPending = _hasPendingCloudChanges;
    _editVersion++;
    if (!wasPending && mounted) {
      // Solo redibuja al pasar de "sincronizado" a "pendiente" (no en cada tecla)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _debounceTimer = Timer(const Duration(seconds: 4), () {
      _saveToCloudFirestore();
    });
  }

  Future<void> _saveToCloudFirestore() async {
    if (_isSavingCloud) return;
    _syncAllTables();

    setState(() {
      _isSavingCloud = true;
    });
    final versionAtStart = _editVersion;
    _failedUploads = 0;

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
        _failedUploads++;
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
        _failedUploads++;
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
        _failedUploads++;
            }
          }
          finalSec.add(secUrl);
        }

        updatedSections.add(section.copyWith(
          mainPhotoUrl: finalMain,
          secondaryPhotoUrls: finalSec,
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
        _failedUploads++;
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

    final updatedTrip = _buildCurrentTrip(coverUrl: finalCoverUrl, updatedAt: now);

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
          _cloudSaveError = null;
          // Si hubo fotos sin subir, el cambio sigue pendiente para reintentarlo
          _savedEditVersion = _failedUploads > 0 ? versionAtStart - 1 : versionAtStart;
        });
        if (_failedUploads > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _failedUploads == 1
                    ? 'Una foto no se pudo subir. La volveremos a intentar en el siguiente guardado.'
                    : '$_failedUploads fotos no se pudieron subir. Las volveremos a intentar en el siguiente guardado.',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: OhtliColors.xoconostle,
            ),
          );
        }
      }
    } catch (e) {
      final message = friendlyError(e, fallback: 'No se pudieron guardar tus cambios en la nube.');
      if (mounted) {
        setState(() {
          _isSavingCloud = false;
          _cloudSaveError = message;
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

  /// Índice actual de un bloque por su id. Los listeners de los controladores
  /// se crean una sola vez, así que no pueden guardar el índice: al reordenar
  /// escribirían en el bloque equivocado.
  int _idx(String id) => _sections.indexWhere((s) => s.id == id);

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
      } else if (type == 'transfer') {
        _sections.add(TransferSection(id: id));
      }
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final temp = _sections[index];
      _sections[index] = _sections[index - 1];
      _sections[index - 1] = temp;
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  void _moveDown(int index) {
    if (index >= _sections.length - 1) return;
    setState(() {
      final temp = _sections[index];
      _sections[index] = _sections[index + 1];
      _sections[index + 1] = temp;
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  void _deleteBlock(int index) {
    setState(() {
      final sec = _sections[index];
      _blockControllers.remove(sec.id);
      _sections.removeAt(index);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bloque eliminado', style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.onyx,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: OhtliColors.cempasuchil,
          onPressed: _undo,
        ),
      ),
    );
  }

  void _duplicateBlock(int index) {
    final map = Map<String, dynamic>.from(_sections[index].toMap());
    map['id'] = 'sec_${DateTime.now().millisecondsSinceEpoch}_${_sections.length}';
    setState(() {
      _sections.insert(index + 1, TripSection.fromMap(map));
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  void _reorderBlocks(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final moved = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, moved);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  void _scrollToBlock(String id) {
    final ctx = _blockKeys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  /// Etiqueta corta de un bloque para el índice.
  (String, IconData) _blockOutlineInfo(TripSection s) {
    if (s is TransferSection) return (describeTransfer(s), transferModeOf(s.mode).icon);
    if (s is UnknownSection) return ('Bloque no compatible', Icons.help_outline_rounded);
    if (s is PlaceSection) {
      final t = s.title.trim();
      return (t.isEmpty ? 'Lugar sin nombre' : t, Icons.location_on_rounded);
    }
    final String md = s is TextSection ? s.markdownText : (s as TextImageSection).markdownText;
    if (s is TextSection && parseTableMarkdown(md) != null) {
      return ('Tabla', Icons.table_chart_rounded);
    }
    final bool isAlert = s is TextSection && parseAlertMarkdown(md) != null;
    final line = md
        .split('\n')
        .map((l) => l
            .replaceAll(RegExp(r'\[![A-Z]+\]'), '')
            .replaceAll(RegExp(r'[#>*_`~\[\]]'), '')
            .trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final label = line.isEmpty
        ? (isAlert ? 'Nota' : (s is TextImageSection ? 'Texto con imagen' : 'Texto'))
        : line;
    final icon = isAlert
        ? Icons.info_outline_rounded
        : (s is TextImageSection ? Icons.photo_library_rounded : Icons.notes_rounded);
    return (label, icon);
  }

  // ---------------------------------------------------------------------------
  // Horarios y ubicación de la parada (E3)
  // ---------------------------------------------------------------------------
  void _replacePlace(String sectionId, PlaceSection Function(PlaceSection) change, {bool resetEditors = false}) {
    final i = _idx(sectionId);
    if (i < 0 || _sections[i] is! PlaceSection) return;
    setState(() {
      _sections[i] = change(_sections[i] as PlaceSection);
      if (resetEditors) _resetBlockEditors();
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickPlaceTime(String sectionId, {required bool arrival}) async {
    final i = _idx(sectionId);
    if (i < 0) return;
    final place = _sections[i] as PlaceSection;
    final current = _parseTime(arrival ? place.arrivalTime : place.departureTime) ??
        _parseTime(arrival ? null : place.arrivalTime) ??
        const TimeOfDay(hour: 10, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: arrival ? 'Hora de llegada' : 'Hora de salida',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    _replacePlace(sectionId, (p) => arrival
        ? p.copyWith(arrivalTime: _formatTime(picked))
        : p.copyWith(departureTime: _formatTime(picked)));
  }

  static String _normalize(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
    const to = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().toLowerCase();
  }

  /// Busca un lugar del catálogo y llena la parada con su ubicación, foto y costo.
  Future<void> _linkPlaceFromCatalog(String sectionId) async {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Poi? poi = await showDialog<Poi>(
      context: context,
      builder: (ctx) => _CatalogPickerDialog(isDark: isDark, normalize: _normalize),
    );
    if (poi == null || !mounted) return;
    _replacePlace(
      sectionId,
      (p) => p.copyWith(
        title: poi.name,
        description: p.description.trim().isEmpty ? poi.cleanNarrative : null,
        mainPhotoUrl: p.mainPhotoUrl.isEmpty && poi.imageUrl.isNotEmpty ? poi.imageUrl : null,
        cost: p.cost <= 0 ? (poi.priceMxnAvg ?? (poi.priceLevel * 60.0)) : null,
        lat: poi.location.isValid ? poi.location.lat : null,
        lng: poi.location.isValid ? poi.location.lng : null,
      ),
      resetEditors: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          poi.location.isValid
              ? '${poi.name} quedó vinculado y ya aparece en el mapa.'
              : '${poi.name} quedó vinculado, pero no tiene coordenadas en el catálogo.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.stormyTeal,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Revisión antes de publicar (E7)
  // ---------------------------------------------------------------------------
  /// Devuelve true si se puede continuar con la publicación.
  Future<bool> _confirmPublishChecklist() async {
    final places = _sections.whereType<PlaceSection>().toList();
    final List<String> errors = [];
    final List<String> warnings = [];
    if (_titleController.text.trim().isEmpty) errors.add('Ponle un título a tu viaje.');
    if (_kind == kTripKindReleaseNotes && _versionController.text.trim().isEmpty) {
      errors.add('Indica el número de versión de estas notas (ej. 1.4.0).');
    }
    if (_sections.isEmpty) errors.add('La bitácora está vacía: añade al menos un bloque.');
    final unnamed = places.where((p) => p.title.trim().isEmpty).length;
    if (unnamed > 0) errors.add(unnamed == 1 ? 'Hay 1 lugar sin nombre.' : 'Hay $unnamed lugares sin nombre.');
    if (_coverUrl.isEmpty) warnings.add('No tiene imagen de portada.');
    if (_descriptionController.markdownText.trim().isEmpty) warnings.add('No tiene descripción.');
    final noLocation = places.where((p) => p.lat == null || p.lng == null).length;
    if (noLocation > 0) {
      warnings.add(noLocation == 1
          ? '1 lugar no tiene ubicación y no saldrá bien en el mapa.'
          : '$noLocation lugares no tienen ubicación y no saldrán bien en el mapa.');
    }
    final noPhoto = places.where((p) => p.mainPhotoUrl.isEmpty).length;
    if (noPhoto > 0) warnings.add(noPhoto == 1 ? '1 lugar no tiene foto.' : '$noPhoto lugares no tienen foto.');
    if (errors.isEmpty && warnings.isEmpty) return true;

    Widget row(String text, bool isError) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isError ? Icons.error_rounded : Icons.warning_amber_rounded,
                  size: 18, color: isError ? OhtliColors.xoconostle : OhtliColors.cempasuchil),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13.5, height: 1.35))),
            ],
          ),
        );

    final bool? go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          errors.isNotEmpty ? 'Falta algo antes de publicar' : 'Revisa antes de publicar',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...errors.map((e) => row(e, true)),
              ...warnings.map((w) => row(w, false)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Revisar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          if (errors.isEmpty)
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
              child: Text('Publicar de todas formas', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
    return go == true;
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
    if (index < 0 || index >= _sections.length || _sections[index] is! PlaceSection) return;
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

    final newSection = current.copyWith(
      title: title,
      description: description,
      rating: rating,
      mainPhotoUrl: finalMainPhoto,
      secondaryPhotoUrls: finalSecondary,
      cost: cost,
      currency: currency,
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
    if (blockIndex < 0 || _sections[blockIndex] is! PlaceSection) return;
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
    if (blockIndex < 0 || _sections[blockIndex] is! PlaceSection) return;
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
    if (index < 0 || index >= _sections.length || _sections[index] is! TextSection) return;
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
    if (index < 0 || index >= _sections.length || _sections[index] is! TextImageSection) return;
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

  void _uploadImageForBlock(int startIndex, String type) {
    if (!kIsWeb) return;
    if (startIndex < 0 || startIndex >= _sections.length) return;
    // El usuario puede reordenar mientras elige o recorta la foto: se resuelve por id al final.
    final String sectionId = _sections[startIndex].id;

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
                      final int index = _idx(sectionId);
                      if (index < 0) return;
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
    List<String> tempCoAuthorIds = List.from(_coAuthorIds);
    List<String> tempCoAuthorNames = List.from(_coAuthorNames);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isSurpriseInvalid = _isSurprise && (_surpriseTargetIds.isEmpty || (!_unlockOnPublish && _surpriseTargetIds.any((id) => _surpriseUnlockDates[id] == null)));
            final isSaveDisabled = tempDate == null || isSurpriseInvalid;

            return AlertDialog(
              backgroundColor: OhtliColors.cloudDancer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Publicar Viaje',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
              ),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Para publicar esta historia, la fecha del viaje es obligatoria.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withOpacity(0.7)),
                      ),
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 14),
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
                          border: Border.all(color: OhtliColors.cantera.withOpacity(0.5)),
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
                              child: Text('Privado (solo autores)', style: GoogleFonts.inter(fontSize: 12.5)),
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
                      const SizedBox(height: 14),
                      Text(
                        'Co-autores (Opcional):',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          final actualFriends = _friendsList.where((f) => f['isFriend'] == true).toList();
                          if (actualFriends.isEmpty) {
                            return Text(
                              'Aún no tienes amigos para agregar como co-autor.',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                            );
                          }
                          return Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: OhtliColors.cantera.withOpacity(0.5)),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              itemCount: actualFriends.length,
                              itemBuilder: (context, idx) {
                                final friend = actualFriends[idx];
                                final String friendId = friend['uid'];
                                final String friendName = friend['displayName'];
                                final bool isSelected = tempCoAuthorIds.contains(friendId);
                                
                                return CheckboxListTile(
                                  title: Text(friendName, style: GoogleFonts.inter(fontSize: 12.5)),
                                  value: isSelected,
                                  activeColor: OhtliColors.stormyTeal,
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (_status == 'published' && _originalCoAuthorIds.contains(friendId))
                                      ? null
                                      : (val) {
                                          setStateDialog(() {
                                            if (val == true) {
                                              tempCoAuthorIds.add(friendId);
                                              tempCoAuthorNames.add(friendName);
                                            } else {
                                              tempCoAuthorIds.remove(friendId);
                                              tempCoAuthorNames.remove(friendName);
                                            }
                                          });
                                        },
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx.withOpacity(0.6),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaveDisabled
                      ? null
                      : () async {
                          Navigator.pop(dialogContext);
                          setState(() {
                            _isPublishing = true;
                            _travelDate = tempDate;
                            _visibility = tempVisibility;
                            _status = 'published';
                            _coAuthorIds = tempCoAuthorIds;
                            _coAuthorNames = tempCoAuthorNames;
                          });

                          _syncAllTables();
                          try {
                            await _saveToCloudFirestore().timeout(const Duration(minutes: 2));
                            if (mounted) {
                              setState(() {
                                _isPublishing = false;
                              });
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
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _isPublishing = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    friendlyError(e, fallback: 'No pudimos publicar el viaje. Intenta de nuevo.'),
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
                            _isPublishing = true;
                            _errataHistory.add(newErrata);
                          });

                          _syncAllTables();
                          try {
                            await _saveToCloudFirestore().timeout(const Duration(minutes: 2));
                            if (mounted) {
                              setState(() {
                                _isPublishing = false;
                              });
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
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _isPublishing = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    friendlyError(e, fallback: 'No pudimos publicar la errata. Intenta de nuevo.'),
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

  bool get _isOwner {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.uid == widget.trip.userId;
  }

  Widget _buildCoAuthorsAvatarStack() {
    if (_coAuthorIds.isEmpty) return const SizedBox.shrink();

    final int maxVisible = 3;
    final List<Widget> avatarWidgets = [];

    for (int i = 0; i < _coAuthorIds.length; i++) {
      if (i >= maxVisible) {
        final int remaining = _coAuthorIds.length - maxVisible;
        avatarWidgets.add(
          Align(
            widthFactor: 0.6,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: OhtliColors.stormyTeal,
              child: Text(
                '+$remaining',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
        break;
      }

      final String uid = _coAuthorIds[i];
      final friend = _friendsList.firstWhere(
        (f) => f['uid'] == uid,
        orElse: () => <String, dynamic>{'displayName': _coAuthorNames[i], 'photoURL': null},
      );

      final String? photoURL = friend['photoURL'];
      final String name = friend['displayName'] ?? 'Viajero';
      final String initials = name.isNotEmpty ? name[0].toUpperCase() : '';

      avatarWidgets.add(
        Align(
          widthFactor: 0.6,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: CircleAvatar(
              radius: 12,
              backgroundColor: OhtliColors.stormyTeal,
              backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                  ? NetworkImage(photoURL)
                  : null,
              child: (photoURL == null || photoURL.isEmpty)
                  ? Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: avatarWidgets,
    );
  }

  void _showCoAuthorsSelectionDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return CoAuthorsModal(
          initialCoAuthorIds: _coAuthorIds,
          originalCoAuthorIds: _originalCoAuthorIds,
          initialCoAuthorNames: _coAuthorNames,
          initialIsSurprise: _isSurprise,
          initialSurpriseTargetIds: _surpriseTargetIds,
          initialSurpriseTargetNames: _surpriseTargetNames,
          initialSurpriseUnlockDates: _surpriseUnlockDates,
          initialUnlockOnPublish: _unlockOnPublish,
          friendsList: _friendsList,
          status: _status,
        );
      },
    );

    if (result != null) {
      setState(() {
        _coAuthorIds = result['coAuthorIds'];
        _coAuthorNames = result['coAuthorNames'];
        _isSurprise = result['isSurprise'];
        _surpriseTargetIds = result['surpriseTargetIds'];
        _surpriseTargetNames = result['surpriseTargetNames'];
        _surpriseUnlockDates = result['surpriseUnlockDates'];
        _unlockOnPublish = result['unlockOnPublish'];
      });
      await _saveToCloudFirestore();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Co-autores actualizados y sincronizados con éxito.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.stormyTeal,
        ),
      );
    }
  }

  Future<void> _handlePublishAction() async {
    if (_status == 'published') {
      await _showErrataDialog();
    } else {
      if (!await _confirmPublishChecklist()) return;
      await _showPublishOptionsDialog();
    }
  }

  // Exit checking
  Future<bool> _onWillPop() async {
    _debounceTimer?.cancel();
    _syncAllTables();
    if (!_hasPendingCloudChanges && _cloudSaveError == null && !_isSavingCloud) return true;

    // Guarda antes de salir, pero sin dejar el botón "atrás" colgado si no hay conexión
    try {
      // Si ya hay un guardado en curso, espera a que termine antes de lanzar otro
      final waitUntil = DateTime.now().add(const Duration(seconds: 12));
      while (_isSavingCloud && DateTime.now().isBefore(waitUntil)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (_hasPendingCloudChanges || _cloudSaveError != null) {
        await _saveToCloudFirestore().timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      if (mounted) setState(() => _cloudSaveError ??= 'La conexión está tardando demasiado.');
    }
    if (!mounted) return true;
    if (_cloudSaveError == null && !_hasPendingCloudChanges) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cambios sin subir a la nube', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'No pudimos guardar tus últimos cambios en la nube. Siguen guardados en este dispositivo y podrás recuperarlos al volver a abrir el viaje aquí.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Quedarme e intentar de nuevo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.xoconostle, foregroundColor: Colors.white),
            child: Text('Salir de todas formas', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (leave != true) {
      _saveToCloudFirestore();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;

    String syncStatusText = "Cambios guardados en este dispositivo";
    IconData syncIcon = Icons.cloud_queue_rounded;
    Color syncColor = OhtliColors.stormyTeal;

    if (_isSavingCloud) {
      syncStatusText = "Guardando en la nube...";
      syncIcon = Icons.sync_rounded;
      syncColor = OhtliColors.cempasuchil;
    } else if (_cloudSaveError != null) {
      syncStatusText = "Sin guardar en la nube · Toca para reintentar";
      syncIcon = Icons.cloud_off_rounded;
      syncColor = OhtliColors.xoconostle;
    } else if (_hasPendingCloudChanges) {
      syncStatusText = "Cambios sin subir...";
      syncIcon = Icons.cloud_upload_outlined;
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

              if (_canPublishReleaseNotes || _kind == kTripKindReleaseNotes) ...[
                const SizedBox(height: 16),
                _buildKindSelector(isDark),
              ],

              const Divider(height: 48, color: OhtliColors.cantera),

              // Blocks List Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Bitácora del Viaje',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_sections.whereType<PlaceSection>().length >= 2)
                        TextButton.icon(
                          onPressed: _fillAllTransfers,
                          style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal, visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.add_road_rounded, size: 16),
                          label: Text('Completar traslados', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      if (_sections.any((s) => s is PlaceSection))
                        TextButton.icon(
                          onPressed: _recalculateTimes,
                          style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal, visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.schedule_rounded, size: 16),
                          label: Text('Ajustar horarios', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        '${_sections.length} bloques',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: OhtliColors.onyx.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
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
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: _sections.length,
                      onReorder: _reorderBlocks,
                      proxyDecorator: (child, index, animation) => Material(
                        color: Colors.transparent,
                        elevation: 10,
                        shadowColor: OhtliColors.onyx.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final section = _sections[index];
                        final bool needsTransfer = section is PlaceSection &&
                            _sections.take(index).any((s) => s is PlaceSection) &&
                            transferBefore(_sections, index) == null;
                        return KeyedSubtree(
                          key: ValueKey('${section.id}_$_editorGeneration'),
                          child: needsTransfer
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMissingTransferConnector(section.id),
                                    _buildBlockCard(index, section, isDark),
                                  ],
                                )
                              : _buildBlockCard(index, section, isDark),
                        );
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
                  _buildAddBlockButton(
                    label: 'Traslado',
                    icon: Icons.add_road_rounded,
                    onTap: () => _addBlock('transfer'),
                    width: 105,
                  ),
                ],
              ),
            ],
          );

    final Widget mainWidgetTree = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (_isPublishing) return;
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
              if (_isPublishing) return;
              final bool shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          title: InkWell(
            onTap: _cloudSaveError != null && !_isSavingCloud ? _saveToCloudFirestore : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(syncIcon, color: syncColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  syncStatusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _cloudSaveError != null ? OhtliColors.xoconostle : OhtliColors.onyx.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          ),
          actions: [
            // 0. Deshacer / rehacer, índice y vista previa (E4–E6)
            if (MediaQuery.of(context).size.width >= 760) ...[
              IconButton(
                tooltip: 'Deshacer (Ctrl+Z)',
                icon: const Icon(Icons.undo_rounded, size: 20),
                color: OhtliColors.stormyTeal,
                onPressed: _undoStack.isEmpty ? null : _undo,
              ),
              IconButton(
                tooltip: 'Rehacer (Ctrl+Shift+Z)',
                icon: const Icon(Icons.redo_rounded, size: 20),
                color: OhtliColors.stormyTeal,
                onPressed: _redoStack.isEmpty ? null : _redo,
              ),
              if (MediaQuery.of(context).size.width < _outlinePanelMinWidth)
                IconButton(
                  tooltip: 'Índice de bloques',
                  icon: const Icon(Icons.toc_rounded, size: 20),
                  color: OhtliColors.stormyTeal,
                  onPressed: _sections.isEmpty ? null : () => _showOutlineSheet(isDark),
                ),
              IconButton(
                tooltip: 'Vista previa',
                icon: const Icon(Icons.visibility_outlined, size: 20),
                color: OhtliColors.stormyTeal,
                onPressed: _isLoadingContent ? null : _openPreview,
              ),
              const SizedBox(width: 4),
            ] else
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                icon: const Icon(Icons.more_vert_rounded, color: OhtliColors.stormyTeal),
                onSelected: (v) {
                  if (v == 'undo') _undo();
                  if (v == 'redo') _redo();
                  if (v == 'outline') _showOutlineSheet(isDark);
                  if (v == 'preview') _openPreview();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'undo',
                    enabled: _undoStack.isNotEmpty,
                    child: const ListTile(dense: true, leading: Icon(Icons.undo_rounded), title: Text('Deshacer')),
                  ),
                  PopupMenuItem(
                    value: 'redo',
                    enabled: _redoStack.isNotEmpty,
                    child: const ListTile(dense: true, leading: Icon(Icons.redo_rounded), title: Text('Rehacer')),
                  ),
                  PopupMenuItem(
                    value: 'outline',
                    enabled: _sections.isNotEmpty,
                    child: const ListTile(dense: true, leading: Icon(Icons.toc_rounded), title: Text('Índice de bloques')),
                  ),
                  PopupMenuItem(
                    value: 'preview',
                    enabled: !_isLoadingContent,
                    child: const ListTile(dense: true, leading: Icon(Icons.visibility_outlined), title: Text('Vista previa')),
                  ),
                ],
              ),
            // 1. Co-authors button for plans (drafts) - ONLY for the owner/creator
            if (_isOwner) ...[
              _buildCoAuthorsAvatarStack(),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.people_outline_rounded, color: OhtliColors.stormyTeal, size: 20),
                tooltip: 'Co-autores del Plan',
                onPressed: _showCoAuthorsSelectionDialog,
              ),
              const SizedBox(width: 4),
            ],
            // 2. Publish / Errata action button
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
                  : (_isOwner
                      ? ElevatedButton.icon(
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
                        )
                      : const SizedBox.shrink()),
            ),
            // 3. Visibility Dropdown - ONLY for the owner/creator
            if (_isOwner)
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
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _EditorUndoIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, control: true): _EditorUndoIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _EditorRedoIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _EditorRedoIntent(),
              SingleActivator(LogicalKeyboardKey.keyY, control: true): _EditorRedoIntent(),
            },
            child: Actions(
              actions: {
                _EditorUndoIntent: _UnlessTypingAction<_EditorUndoIntent>(_undo),
                _EditorRedoIntent: _UnlessTypingAction<_EditorRedoIntent>(_redo),
              },
              child: Focus(
                autofocus: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final Widget editorColumn = Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: mainContent,
                        ),
                      ),
                    );
                    if (constraints.maxWidth < _outlinePanelMinWidth || _isLoadingContent || _sections.isEmpty) {
                      return editorColumn;
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 260,
                          margin: const EdgeInsets.fromLTRB(16, 24, 0, 24),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4),
                            ),
                          ),
                          child: _buildOutline(isDark),
                        ),
                        Expanded(child: editorColumn),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (_isPublishing) {
      return Stack(
        children: [
          mainWidgetTree,
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Subiendo imágenes y preparando tu aventura...",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return mainWidgetTree;
  }

  Widget _buildBlockCard(int index, TripSection section, bool isDark) {
    String typeLabel = "Bloque";
    IconData typeIcon = Icons.article_outlined;
    Widget blockContent = const SizedBox();

    if (section is TransferSection) {
      typeLabel = "Traslado";
      typeIcon = transferModeOf(section.mode).icon;
      blockContent = _buildTransferEditor(section, isDark);
    } else if (section is UnknownSection) {
      typeLabel = "Bloque no compatible";
      typeIcon = Icons.help_outline_rounded;
      blockContent = Text(
        'Este bloque se creó con una versión más nueva de Ohtli. Se conserva sin cambios.',
        style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.6)),
      );
    } else if (section is PlaceSection) {
      typeLabel = "Lugar Visitado";
      typeIcon = Icons.location_on_rounded;
      
      final titleController = _blockControllers.putIfAbsent(
        '${section.id}_title',
        () {
          final c = TextEditingController(text: section.title);
          c.addListener(() {
            _updatePlaceBlock(_idx(section.id), title: c.text);
          });
          return c;
        },
      );

      final controller = _blockControllers.putIfAbsent(
        '${section.id}_desc',
        () {
          final c = MarkdownRichTextController(text: section.description, context: context);
          c.addListener(() {
            _updatePlaceBlock(_idx(section.id), description: c.markdownText);
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
            _updatePlaceBlock(_idx(section.id), cost: parsed ?? 0.0);
          });
          return c;
        },
      );

      final List<Map<String, dynamic>> slots = [
        {
          'url': section.mainPhotoUrl,
          'label': 'Principal',
          'type': 'place_main',
          'onTap': () => _uploadImageForBlock(_idx(section.id), 'place_main'),
          'onDelete': () => _updatePlaceBlock(_idx(section.id), mainPhoto: ''),
        },
        {
          'url': section.secondaryPhotoUrls.isNotEmpty ? section.secondaryPhotoUrls[0] : '',
          'label': 'Foto 2',
          'type': 'place_sec_0',
          'onTap': () => _uploadImageForBlock(_idx(section.id), 'place_sec_0'),
          'onDelete': () => _deletePlaceSecondaryPhoto(_idx(section.id), 0),
        },
        {
          'url': section.secondaryPhotoUrls.length > 1 ? section.secondaryPhotoUrls[1] : '',
          'label': 'Foto 3',
          'type': 'place_sec_1',
          'onTap': () => _uploadImageForBlock(_idx(section.id), 'place_sec_1'),
          'onDelete': () => _deletePlaceSecondaryPhoto(_idx(section.id), 1),
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
                      _updatePlaceBlock(_idx(section.id), rating: starIndex + 1);
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
                        _updatePlaceBlock(_idx(section.id), currency: val);
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
          const SizedBox(height: 12),
          // Horarios y ubicación (E3)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildTimeChip(section, arrival: true, isDark: isDark),
              _buildTimeChip(section, arrival: false, isDark: isDark),
              _buildLocationChip(section, isDark),
            ],
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
                    onTap: () => _uploadImageForBlock(_idx(section.id), 'place_main'),
                    onDelete: () => _updatePlaceBlock(_idx(section.id), mainPhoto: ''),
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
          onChanged: (newMarkdown) => _updateTextBlock(_idx(section.id), markdown: newMarkdown),
        );
      } else if (tableData != null) {
        typeLabel = "Tabla";
        typeIcon = Icons.table_chart_rounded;
        blockContent = OhtliTableBlockEditor(
          tableMarkdown: section.markdownText,
          isDark: isDark,
          onChanged: (newMarkdown) => _updateTextBlock(_idx(section.id), markdown: newMarkdown),
        );
      } else {
        typeLabel = "Nota / Historia";
        typeIcon = Icons.notes_rounded;
        
        final controller = _blockControllers.putIfAbsent(
          section.id,
          () {
            final c = MarkdownRichTextController(text: section.markdownText, context: context);
            c.addListener(() {
              _updateTextBlock(_idx(section.id), markdown: c.markdownText);
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
            _updateTextImageBlock(_idx(section.id), markdown: c.markdownText);
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
                    onTap: () => _uploadImageForBlock(_idx(section.id), 'text_image'),
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
                                onTap: () => _uploadImageForBlock(_idx(section.id), 'text_image'),
                                behavior: HitTestBehavior.opaque,
                                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 11),
                              ),
                              Container(width: 1, height: 10, color: Colors.white24),
                              GestureDetector(
                                onTap: () => _updateTextImageBlock(_idx(section.id), photo: ''),
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
                      if (val) _updateTextImageBlock(_idx(section.id), layout: 'left');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    checkmarkColor: Colors.white,
                    label: Text('Derecha', style: GoogleFonts.inter(fontSize: 11)),
                    selected: section.layout == 'right',
                    onSelected: (val) {
                      if (val) _updateTextImageBlock(_idx(section.id), layout: 'right');
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
      key: _blockKeys.putIfAbsent(section.id, () => GlobalKey()),
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
                // Asa para arrastrar el bloque (E2)
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: 'Arrastra para reordenar',
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.drag_indicator_rounded, size: 18, color: OhtliColors.onyx.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                ),
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
                // Duplicate Button (E5)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Duplicar bloque',
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  color: OhtliColors.stormyTeal,
                  onPressed: () => _duplicateBlock(index),
                ),
                const SizedBox(width: 12),
                // Delete Button
                IconButton(
                  tooltip: 'Eliminar bloque',
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


  static const double _outlinePanelMinWidth = 1240;

  /// Selector "Viaje / Notas de versión" (solo cuentas del equipo editorial).
  Widget _buildKindSelector(bool isDark) {
    final bool isNotes = _kind == kTripKindReleaseNotes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isNotes
            ? OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.18 : 0.06)
            : (isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: isNotes ? 0.35 : 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Tipo de publicación',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx.withValues(alpha: 0.7))),
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: OhtliColors.stormyTeal,
                  selectedForegroundColor: Colors.white,
                  textStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: kTripKindTrip, icon: Icon(Icons.map_outlined, size: 16), label: Text('Viaje')),
                  ButtonSegment(value: kTripKindReleaseNotes, icon: Icon(Icons.new_releases_outlined, size: 16), label: Text('Notas de versión')),
                ],
                selected: {_kind},
                onSelectionChanged: _canPublishReleaseNotes
                    ? (v) {
                        setState(() => _kind = v.first);
                        _forceNewUndoStep = true;
                        _onDataChanged();
                      }
                    : null,
              ),
              if (isNotes)
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _versionController,
                    enabled: _canPublishReleaseNotes,
                    onChanged: (_) => _onDataChanged(),
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Versión',
                      hintText: '1.4.0',
                      prefixText: 'v',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
          ),
          if (isNotes) ...[
            const SizedBox(height: 8),
            Text(
              'Al publicarlas (públicas) aparecen como historia destacada en Explorar y no en el feed de la comunidad. '
              'Usa bloques de texto, notas, tablas e imágenes para contar qué hay de nuevo.',
              style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: OhtliColors.onyx.withValues(alpha: 0.6)),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Traslados entre paradas
  // ---------------------------------------------------------------------------
  String _newSectionId() => 'sec_${DateTime.now().microsecondsSinceEpoch}_${_sections.length}';

  void _replaceTransfer(String id, TransferSection Function(TransferSection) change, {bool structural = true}) {
    final i = _idx(id);
    if (i < 0 || _sections[i] is! TransferSection) return;
    final next = change(_sections[i] as TransferSection);
    setState(() {
      _sections[i] = next;
      if (structural) _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  /// Paradas vecinas de un traslado (la anterior y la siguiente en la bitácora).
  (PlaceSection?, PlaceSection?) _placesAround(int index) {
    PlaceSection? before;
    PlaceSection? after;
    for (int i = index - 1; i >= 0; i--) {
      if (_sections[i] is PlaceSection) {
        before = _sections[i] as PlaceSection;
        break;
      }
    }
    for (int i = index + 1; i < _sections.length; i++) {
      if (_sections[i] is PlaceSection) {
        after = _sections[i] as PlaceSection;
        break;
      }
    }
    return (before, after);
  }

  void _estimateTransfer(String id) {
    final i = _idx(id);
    if (i < 0) return;
    final t = _sections[i] as TransferSection;
    final (a, b) = _placesAround(i);
    final est = (a != null && b != null) ? estimateTransfer(a, b, t.mode, id: t.id) : null;
    if (est == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Para estimarlo, las paradas de antes y después deben tener ubicación.', style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.xoconostle,
      ));
      return;
    }
    _replaceTransfer(id, (_) => est.copyWith(notes: t.notes));
    _resetBlockEditors();
  }

  /// Inserta un traslado estimado justo antes de la parada [placeId].
  void _insertTransferBefore(String placeId) {
    final i = _idx(placeId);
    if (i < 0) return;
    final (prev, _) = _placesAround(i);
    final place = _sections[i] as PlaceSection;
    final id = _newSectionId();
    final t = (prev != null ? estimateTransfer(prev, place, 'walking', id: id) : null) ?? TransferSection(id: id);
    setState(() {
      _sections.insert(i, t);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  Future<void> _fillAllTransfers() async {
    final String? mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('¿Cómo te vas a mover?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Se añadirá un traslado estimado entre cada par de paradas que no tenga uno. Luego puedes cambiar cada tramo.',
              style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.65)),
            ),
          ),
          ...kTransferModes.where((m) => m.id != 'other').map((m) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(m.id),
                child: Row(children: [
                  Icon(m.icon, color: OhtliColors.stormyTeal, size: 20),
                  const SizedBox(width: 12),
                  Text(m.label, style: GoogleFonts.inter(fontSize: 14)),
                ]),
              )),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    final (list, added) = fillMissingTransfers(_sections, mode, _newSectionId);
    if (added > 0) {
      setState(() {
        _sections = list;
        _forceNewUndoStep = true;
        _onDataChanged();
      });
    }
    final places = _sections.whereType<PlaceSection>().where((p) => p.lat == null || p.lng == null).length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        added == 0
            ? (places > 0
                ? 'No se añadió nada: faltan ubicaciones en $places ${places == 1 ? 'parada' : 'paradas'}.'
                : 'Todas las paradas ya tienen traslado.')
            : 'Se añadieron $added ${added == 1 ? 'traslado' : 'traslados'} estimados.',
        style: GoogleFonts.inter(),
      ),
      backgroundColor: OhtliColors.stormyTeal,
      action: added > 0 ? SnackBarAction(label: 'Deshacer', textColor: OhtliColors.cempasuchil, onPressed: _undo) : null,
    ));
  }

  Future<void> _recalculateTimes() async {
    final places = _sections.whereType<PlaceSection>().toList();
    if (places.isEmpty) return;
    String start = places.first.arrivalTime ?? '';
    if (parseClockMinutes(start) == null) {
      final picked = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 10, minute: 0),
        helpText: '¿A qué hora empiezas?',
        cancelText: 'Cancelar',
        confirmText: 'Listo',
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked == null || !mounted) return;
      start = _formatTime(picked);
    }
    setState(() {
      _sections = recalculateSchedule(_sections, startTime: start);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Horarios ajustados con las estancias y los traslados.', style: GoogleFonts.inter()),
      backgroundColor: OhtliColors.stormyTeal,
      action: SnackBarAction(label: 'Deshacer', textColor: OhtliColors.cempasuchil, onPressed: _undo),
    ));
  }

  Widget _buildTransferEditor(TransferSection t, bool isDark) {
    final sid = t.id;
    TextEditingController ctrl(String suffix, String initial, void Function(String) onChange) {
      return _blockControllers.putIfAbsent('${sid}_$suffix', () {
        final c = TextEditingController(text: initial);
        String last = initial;
        c.addListener(() {
          if (c.text == last) return;
          last = c.text;
          onChange(c.text);
        });
        return c;
      });
    }

    final minsCtrl = ctrl('mins', t.durationMins?.toString() ?? '', (v) {
      final n = int.tryParse(v);
      _replaceTransfer(sid, (x) => n == null ? x.copyWith(clearDuration: true, isEstimated: false) : x.copyWith(durationMins: n, isEstimated: false),
          structural: false);
    });
    final kmCtrl = ctrl('km', t.distanceKm?.toString() ?? '', (v) {
      final n = double.tryParse(v);
      _replaceTransfer(sid, (x) => n == null ? x.copyWith(clearDistance: true, isEstimated: false) : x.copyWith(distanceKm: n, isEstimated: false),
          structural: false);
    });
    final costCtrl = ctrl('cost', t.cost > 0 ? t.cost.toStringAsFixed(t.cost % 1 == 0 ? 0 : 2) : '', (v) {
      _replaceTransfer(sid, (x) => x.copyWith(cost: double.tryParse(v) ?? 0), structural: false);
    });
    final notesCtrl = ctrl('notes', t.notes, (v) {
      _replaceTransfer(sid, (x) => x.copyWith(notes: v), structural: false);
    });

    InputDecoration deco(String label, {String? suffix}) => InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
          labelStyle: GoogleFonts.inter(fontSize: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );

    final i = _idx(sid);
    final (a, b) = i >= 0 ? _placesAround(i) : (null, null);
    final mode = transferModeOf(t.mode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a != null || b != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${a?.title.isNotEmpty == true ? a!.title : 'Inicio'}  →  ${b?.title.isNotEmpty == true ? b!.title : 'Siguiente parada'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx.withValues(alpha: 0.7)),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kTransferModes.map((m) {
            final selected = m.id == t.mode;
            return ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(m.icon, size: 16, color: selected ? Colors.white : OhtliColors.stormyTeal),
              label: Text(m.label,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : OhtliColors.onyx)),
              selectedColor: OhtliColors.stormyTeal,
              backgroundColor: isDark ? const Color(0xFF25252A) : OhtliColors.stormyTeal.withValues(alpha: 0.06),
              side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: selected ? 1 : 0.2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (_) {
                // Si el tramo era estimado, se vuelve a estimar con el nuevo modo.
                if (t.isEstimated && a != null && b != null) {
                  final est = estimateTransfer(a, b, m.id, id: sid);
                  if (est != null) {
                    _replaceTransfer(sid, (_) => est.copyWith(notes: t.notes));
                    _resetBlockEditors();
                    return;
                  }
                }
                _replaceTransfer(sid, (x) => x.copyWith(mode: m.id));
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: minsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.inter(fontSize: 13),
                decoration: deco('Duración', suffix: 'min'),
              ),
            ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                style: GoogleFonts.inter(fontSize: 13),
                decoration: deco('Distancia', suffix: 'km'),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                style: GoogleFonts.inter(fontSize: 13),
                decoration: deco('Costo', suffix: t.currency),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: notesCtrl,
          minLines: 1,
          maxLines: 3,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: deco(mode.id == 'walking'
              ? 'Indicaciones (ej. sube por Madero hasta el Zócalo)'
              : 'Indicaciones (ej. Línea 2 dirección Taxqueña, baja en Zócalo)'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _estimateTransfer(sid),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: Text('Estimar con el mapa', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (t.isEstimated)
              Tooltip(
                message: 'Calculado por Ohtli a partir de la ubicación de las paradas. Puedes corregirlo.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: OhtliColors.cempasuchil.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Estimado por Ohtli',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OhtliColors.cempasuchil)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Conector "+ Añadir traslado" entre dos paradas seguidas que no tienen uno.
  Widget _buildMissingTransferConnector(String placeId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(width: 22),
          Container(width: 2, height: 22, color: OhtliColors.stormyTeal.withValues(alpha: 0.25)),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () => _insertTransferBefore(placeId),
            style: TextButton.styleFrom(
              foregroundColor: OhtliColors.stormyTeal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.add_road_rounded, size: 16),
            label: Text('Añadir traslado', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Índice de bloques (E5): toca para ir al bloque, arrastra para reordenar.
  Widget _buildOutline(bool isDark, {VoidCallback? onNavigate, VoidCallback? onReordered}) {
    int placeNumber = 0;
    final numbers = <String, int>{};
    for (final s in _sections) {
      if (s is PlaceSection) numbers[s.id] = ++placeNumber;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.toc_rounded, size: 18, color: OhtliColors.stormyTeal),
              const SizedBox(width: 8),
              Text('Índice', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: OhtliColors.onyx)),
              const Spacer(),
              Text('${_sections.length}', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withValues(alpha: 0.4))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Toca para ir · arrastra para mover',
            style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.onyx.withValues(alpha: 0.45)),
          ),
        ),
        Flexible(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: _sections.length,
            onReorder: (a, b) {
              _reorderBlocks(a, b);
              onReordered?.call();
            },
            proxyDecorator: (child, index, animation) => Material(
              color: isDark ? const Color(0xFF25252A) : Colors.white,
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: child,
            ),
            itemBuilder: (context, i) {
              final s = _sections[i];
              final (label, icon) = _blockOutlineInfo(s);
              final n = numbers[s.id];
              return ReorderableDragStartListener(
                key: ValueKey('outline_${s.id}'),
                index: i,
                child: InkWell(
                  onTap: () {
                    onNavigate?.call();
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(s.id));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: n != null
                              ? CircleAvatar(
                                  radius: 11,
                                  backgroundColor: OhtliColors.xoconostle,
                                  child: Text('$n', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                )
                              : Icon(icon, size: 16, color: OhtliColors.stormyTeal),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: s is PlaceSection ? FontWeight.w600 : FontWeight.w400,
                              color: OhtliColors.onyx.withValues(alpha: s is PlaceSection ? 0.9 : 0.65),
                            ),
                          ),
                        ),
                        if (s is PlaceSection && (s.lat == null || s.lng == null))
                          const Tooltip(
                            message: 'Sin ubicación',
                            child: Icon(Icons.location_off_outlined, size: 14, color: OhtliColors.xoconostle),
                          ),
                        const SizedBox(width: 4),
                        Icon(Icons.drag_indicator_rounded, size: 16, color: OhtliColors.onyx.withValues(alpha: 0.3)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showOutlineSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: SafeArea(
            child: _buildOutline(
              isDark,
              onNavigate: () => Navigator.of(sheetCtx).pop(),
              onReordered: () => setSheet(() {}),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChip(PlaceSection place, {required bool arrival, required bool isDark}) {
    final String? value = arrival ? place.arrivalTime : place.departureTime;
    final bool hasValue = value != null && value.trim().isNotEmpty;
    final String label = arrival ? 'Llegada' : 'Salida';
    return InputChip(
      avatar: Icon(arrival ? Icons.login_rounded : Icons.logout_rounded, size: 15, color: OhtliColors.stormyTeal),
      label: Text(
        hasValue ? '$label · $value' : '+ $label',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: hasValue ? OhtliColors.onyx : OhtliColors.onyx.withValues(alpha: 0.55),
        ),
      ),
      tooltip: hasValue ? 'Cambiar hora de ${label.toLowerCase()}' : 'Añadir hora de ${label.toLowerCase()}',
      backgroundColor: isDark ? const Color(0xFF25252A) : OhtliColors.stormyTeal.withValues(alpha: 0.06),
      side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: hasValue ? 0.35 : 0.15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onPressed: () => _pickPlaceTime(place.id, arrival: arrival),
      onDeleted: hasValue
          ? () => _replacePlace(
                place.id,
                (p) => arrival ? p.copyWith(clearArrivalTime: true) : p.copyWith(clearDepartureTime: true),
              )
          : null,
      deleteIcon: const Icon(Icons.close_rounded, size: 14),
      deleteButtonTooltipMessage: 'Quitar hora',
    );
  }

  Widget _buildLocationChip(PlaceSection place, bool isDark) {
    final bool located = place.lat != null && place.lng != null;
    final Color tone = located ? OhtliColors.stormyTeal : OhtliColors.xoconostle;
    return ActionChip(
      avatar: Icon(located ? Icons.where_to_vote_rounded : Icons.travel_explore_rounded, size: 15, color: tone),
      label: Text(
        located ? 'En el mapa · Cambiar lugar' : 'Sin ubicación · Buscar en el catálogo',
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: tone),
      ),
      tooltip: 'Vincular con un lugar del catálogo de Ohtli',
      backgroundColor: tone.withValues(alpha: isDark ? 0.18 : 0.07),
      side: BorderSide(color: tone.withValues(alpha: 0.3)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onPressed: () => _linkPlaceFromCatalog(place.id),
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

// -----------------------------------------------------------------------------
// Atajos de deshacer: si el foco está en un campo de texto, se deja pasar el
// atajo para que el campo use su propio deshacer.
// -----------------------------------------------------------------------------
class _EditorUndoIntent extends Intent {
  const _EditorUndoIntent();
}

class _EditorRedoIntent extends Intent {
  const _EditorRedoIntent();
}

class _UnlessTypingAction<T extends Intent> extends Action<T> {
  _UnlessTypingAction(this.onInvoke);
  final VoidCallback onInvoke;

  bool get _isTyping {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool isEnabled(T intent) => !_isTyping;

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}

// -----------------------------------------------------------------------------
// Buscador del catálogo de lugares (E3)
// -----------------------------------------------------------------------------
class _CatalogPickerDialog extends StatefulWidget {
  final bool isDark;
  final String Function(String) normalize;

  const _CatalogPickerDialog({required this.isDark, required this.normalize});

  @override
  State<_CatalogPickerDialog> createState() => _CatalogPickerDialogState();
}

class _CatalogPickerDialogState extends State<_CatalogPickerDialog> {
  late final Future<List<Poi>> _catalog = PlacesPage.loadCatalog();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vincular con un lugar',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                'Toma la ubicación, la foto y el costo del catálogo de Ohtli.',
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx),
                decoration: InputDecoration(
                  hintText: 'Busca por nombre o colonia…',
                  prefixIcon: const Icon(Icons.search_rounded, color: OhtliColors.stormyTeal),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.15),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<Poi>>(
                  future: _catalog,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
                    }
                    if (snap.hasError || (snap.data ?? []).isEmpty) {
                      return Center(
                        child: Text(
                          'No pudimos cargar el catálogo. Revisa tu conexión e intenta de nuevo.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.6)),
                        ),
                      );
                    }
                    final q = widget.normalize(_query.trim());
                    final all = snap.data!;
                    final results = (q.isEmpty
                            ? all
                            : all.where((p) => widget.normalize('${p.name} ${p.coloniaAlcaldiaDisplay}').contains(q)))
                        .take(40)
                        .toList();
                    if (results.isEmpty) {
                      return Center(
                        child: Text('Sin resultados para "$_query".',
                            style: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.6))),
                      );
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: OhtliColors.cantera.withValues(alpha: 0.3)),
                      itemBuilder: (context, i) {
                        final p = results[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: p.imageUrl.isNotEmpty
                                  ? Image.network(
                                      p.imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.place_rounded, color: OhtliColors.stormyTeal),
                                    )
                                  : const Icon(Icons.place_rounded, color: OhtliColors.stormyTeal),
                            ),
                          ),
                          title: Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: OhtliColors.onyx)),
                          subtitle: Text(
                            '${p.categoryDisplay} · ${p.coloniaAlcaldiaDisplay}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withValues(alpha: 0.55)),
                          ),
                          trailing: p.location.isValid
                              ? null
                              : const Tooltip(
                                  message: 'Sin coordenadas',
                                  child: Icon(Icons.location_off_outlined, size: 16, color: OhtliColors.xoconostle),
                                ),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

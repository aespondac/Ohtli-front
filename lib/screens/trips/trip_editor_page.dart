import '../../services/social_graph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/place_feedback_sheets.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../services/photo_storage.dart';
import '../../theme/colors.dart';
import '../../theme/release_tags.dart';
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
import '../../services/section_merge.dart';
import '../../services/trip_changes.dart';
import '../../services/proposal_votes.dart';
import '../../widgets/ohtli_ui.dart';
import 'widgets/proposal_block.dart';
import 'widgets/trip_branch_ui.dart';
import 'trip_sample.dart' show TripSample, kSampleMyUid, kSampleMyName;
import '../../services/trip_branches.dart';
import '../../widgets/transfer_mode_picker.dart';
import '../../theme/cdmx_photos.dart';
import '../../config/editorial.dart';
import '../../services/poi_suggestion_service.dart';
import '../../widgets/place_details_form.dart';
import 'package:http/http.dart' as http;
import '../../utils/web_helpers.dart';
import '../../services/feedback_service.dart';
import '../../services/labs_invite.dart';
import '../../utils/current_location.dart';
import '../../services/trip_endpoints.dart';
import '../../widgets/route_endpoint_pin.dart';
import '../../widgets/trip_mini_map.dart';
import '../../widgets/place_search_field.dart';

class TripEditorPage extends StatefulWidget {
  final Trip trip;

  /// Editor de muestra: abre con estos bloques y no guarda nada (ni en la nube ni en el
  /// dispositivo). Lo usa el viaje de muestra (/muestra).
  final List<TripSection>? sampleSections;

  const TripEditorPage({super.key, required this.trip, this.sampleSections});

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

  // Inicio y fin del recorrido ({name, lat, lng}); null = se deducen de las paradas.
  late Map<String, dynamic>? _startPoint = widget.trip.startPoint;
  late Map<String, dynamic>? _endPoint = widget.trip.endPoint;
  late String? _routeShape = widget.trip.routeShape;
  
  List<TripSection> _sections = [];

  /// Paradas del catálogo (id de sección -> poiId) en la última versión guardada: al guardar se
  /// comparan con las actuales para reportar qué se quitó, cambió o agregó (retroalimentación).
  /// Se compara al guardar y no en cada clic para que "Deshacer" no cuente como cambio.
  Map<String, String>? _feedbackBaseline;
  bool _feedbackReorderSent = false;
  // Estado de las sugerencias de lugar usadas en este viaje (id → pending/approved/rejected)
  final Map<String, String> _suggestionStatus = {};
  bool _isLoadingContent = true;
  bool _isSavingCloud = false;
  bool _isPublishing = false;
  
  Timer? _debounceTimer;

  // --- Edición en vivo: el dueño y los coautores editan a la vez ---
  // Lo último sincronizado con la nube (la "base" del merge a 3 vías): lo que este editor
  // vio por última vez allá. Lo local es _sections y el estado de los campos del viaje.
  List<TripSection> _baseSections = [];
  late Map<String, dynamic> _baseTrip = TripService.editorTripFields(widget.trip);
  // Último documento del viaje visto en la nube (campos que el editor no edita, como
  // quién abrió la sorpresa, se toman de aquí y no del viaje con el que se abrió).
  late Trip _liveTrip = widget.trip;
  // Revisión de lo sincronizado: los avisos del listener con una revisión menor son viejos.
  int _contentRev = 0;
  int _tripRev = 0;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _contentSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tripSub;
  StreamSubscription<List<EditorPresence>>? _presenceSub;
  // Avisos que llegaron mientras se guardaba: se aplican al terminar.
  DocumentSnapshot<Map<String, dynamic>>? _pendingContentSnap;
  DocumentSnapshot<Map<String, dynamic>>? _pendingTripSnap;
  // Al aplicar cambios ajenos, los listeners de los controladores no cuentan como edición.
  bool _applyingRemote = false;
  // Bloques donde los dos cambiaron lo mismo y se quedó la versión local
  // (id → versión ajena; null = el otro lo borró) y quién hizo el otro cambio.
  final Map<String, TripSection?> _conflicts = {};
  final Map<String, String> _conflictBy = {};
  // Generación de cada bloque: al cambiar desde fuera se recrean sus editores.
  final Map<String, int> _blockGen = {};
  // Bloque donde está el foco (también se publica en la presencia).
  String? _focusedBlockId;
  List<EditorPresence> _presence = [];
  Timer? _presenceTimer;
  Timer? _presenceDebounce;

  // Votos de las propuestas de lugares (id del bloque → uid → lugar). Viven aparte del
  // contenido, así que se escuchan por separado.
  final Map<String, Map<String, String>> _votes = {};
  final Map<String, StreamSubscription<Map<String, String>>> _voteSubs = {};
  // Nombre de quien organiza cuando lo abre un coautor (para votos y ramas).
  String? _ownerName;

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
  late final String _kind = widget.trip.kind;
  late final TextEditingController _versionController =
      TextEditingController(text: widget.trip.version ?? (widget.trip.isReleaseNotes ? kAppVersion : ''));

  /// Editor de notas de versión: se crean desde Administración, no desde aquí. Las "paradas"
  /// son novedades (sin horario, costo ni traslados) y no hay fe de erratas.
  bool get _isNotes => _kind == kTripKindReleaseNotes;

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

  // Fe de erratas: contenido y datos del viaje al abrir el editor (o al último registro).
  // Después del viaje, al salir se registra quién cambió qué y cuándo.
  List<TripSection>? _errataBaseline;
  Trip? _errataBaselineTrip;

  bool get _isPostTrip {
    if (_isNotes) return false;
    if (_liveTrip.finishedAt != null) return true;
    final d = _travelDate;
    if (d == null) return false;
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Lo que cambió desde la referencia, como entrada de la fe de erratas (o null si nada).
  ErrataEntry? _errataSinceBaseline({String note = ''}) {
    final base = _errataBaseline, baseTrip = _errataBaselineTrip;
    if (base == null || baseTrip == null) return null;
    final changes = [...describeTripInfoChanges(baseTrip, _buildCurrentTrip()), ...describeTripChanges(base, _sections)];
    if (changes.isEmpty && note.trim().isEmpty) return null;
    final u = FirebaseAuth.instance.currentUser;
    final name = (u?.displayName ?? '').trim().isNotEmpty ? u!.displayName!.trim() : ((u?.email ?? '').split('@').first);
    return ErrataEntry(
      id: const Uuid().v4(),
      note: note.trim(),
      date: DateTime.now(),
      authorId: u?.uid ?? '',
      authorName: name.isEmpty ? 'Viajero' : name,
      changes: changes,
    );
  }

  void _resetErrataBaseline() {
    _errataBaseline = List.of(_sections);
    _errataBaselineTrip = _buildCurrentTrip();
  }

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
    _rememberDescription(widget.trip.description);
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
    _loadOwnerName();
  }

  Future<void> _loadFriends() async {
    if (mounted) setState(() => _isLoadingFriends = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Mis listas sociales (users/{uid}/social/*): amigos, mejores amigos y quién me
        // tiene como mejor amigo (para saber si es mutuo sin leer las listas ajenas).
        final social = await SocialGraph.getGraph(user.uid, includeClose: true);
        {
          final List<dynamic> friendsUids = social.friends;
          final List<dynamic> myCloseFriends = social.closeFriends;
          final List<String> closeFriendOf = social.closeFriendOf;
          
          final Set<String> uidsToFetch = {
            ...friendsUids.cast<String>(),
            ..._coAuthorIds,
          };

          if (uidsToFetch.isNotEmpty) {
            final List<String> uidsList = uidsToFetch.take(30).toList();
            final friendsSnapshot = await FirebaseFirestore.instance
                .collection('public_profiles')
                .where(FieldPath.documentId, whereIn: uidsList)
                .get();
            
            final List<Map<String, dynamic>> fetched = [];
            for (var doc in friendsSnapshot.docs) {
              final dName = doc.data()['displayName'] ?? 'Viajero Ohtli';
              final bool isMutualCloseFriend = closeFriendOf.contains(doc.id) &&
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

  // Navegador raíz, guardado para invitar a Labs al cerrar el editor (en dispose ya no hay context).
  NavigatorState? _rootNavigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
  }

  /// Al cerrar el editor de su primer viaje armado con la IA: invitación a Labs (una vez).
  void _maybeInviteToLabs() {
    final nav = _rootNavigator;
    final t = widget.trip;
    if (nav == null || widget.sampleSections != null || t.kind != kTripKindTrip) return;
    if (t.userId != FirebaseAuth.instance.currentUser?.uid) return;
    if (!LabsInvite.isAiTrip(recommendationJobId: t.recommendationJobId, recommendedPoiIds: t.recommendedPoiIds)) return;
    unawaited(LabsInvite.maybeShow(nav, LabsInviteMoment.aiTrip));
  }

  @override
  void dispose() {
    _maybeInviteToLabs();
    _debounceTimer?.cancel();
    _stopLive();
    for (final s in _voteSubs.values) {
      s.cancel();
    }
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
    if (_isSampleEditor) {
      setState(() {
        _sections = List.of(widget.sampleSections!);
        _isLoadingContent = false;
      });
      _resetUndoBaseline();
      _resetErrataBaseline();
      return;
    }
    try {
      final cloudContent = await TripService().getTripContent(widget.trip.userId, widget.trip.id);
      if (cloudContent != null) {
        if (mounted) {
          setState(() {
            _sections = cloudContent.sections;
            _baseSections = List.of(cloudContent.sections);
            _isLoadingContent = false;
          });
          _feedbackBaseline = _catalogStops(cloudContent.sections);
          _resetErrataBaseline();
        }
      } else {
        _resetErrataBaseline();
        if (mounted) {
          setState(() {
            _isLoadingContent = false;
          });
        }
      }

      _resetUndoBaseline();
      // Check browser localStorage for newer local cache
      _checkLocalCache();
      _syncSuggestionStatuses();
      if (mounted) _startLive();
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

  // ---------------------------------------------------------------------------
  // Edición en vivo: cambios de los demás, conflictos y presencia
  // ---------------------------------------------------------------------------
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _myName {
    final u = FirebaseAuth.instance.currentUser;
    final name = (u?.displayName ?? '').trim().isNotEmpty ? u!.displayName!.trim() : ((u?.email ?? '').split('@').first);
    return name.isEmpty ? 'Viajero' : name;
  }

  /// Los demás que tienen el editor abierto ahora.
  List<EditorPresence> get _othersHere {
    final now = DateTime.now();
    return [for (final p in _presence) if (p.uid != _myUid && p.isActive(now)) p];
  }

  bool get _othersEditing => _othersHere.isNotEmpty;

  // Un listener de Firestore se detiene para siempre si falla (p. ej. la sesión se cayó un
  // momento): se vuelve a conectar con espera creciente (5 s, 10 s… hasta 60 s).
  Timer? _liveRetryTimer;
  int _liveRetries = 0;

  void _startLive() {
    if (_isSampleEditor || _myUid.isEmpty || _contentSub != null) return;
    final service = TripService();
    final owner = widget.trip.userId, id = widget.trip.id;
    _contentSub = service.watchTripContent(owner, id).listen((s) {
      _liveRetries = 0;
      _onContentSnapshot(s);
    }, onError: (e) => _onLiveError('contenido', e));
    _tripSub = service.watchTripDoc(owner, id).listen(_onTripSnapshot, onError: (e) => _onLiveError('viaje', e));
    _presenceSub = service.watchPresence(owner, id).listen((list) {
      if (mounted) setState(() => _presence = list);
    }, onError: (e) => debugPrint('Editor en vivo (presencia): $e'));
    _sendPresence();
    // Latido: dice que sigo aquí y, de paso, retira a quien dejó de latir.
    _presenceTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      _sendPresence();
      if (mounted) setState(() {});
    });
  }

  void _onLiveError(String what, Object e) {
    debugPrint('Editor en vivo ($what): $e');
    if (!mounted || _liveRetryTimer?.isActive == true) return;
    final seconds = math.min(60, 5 << math.min(_liveRetries, 4));
    _liveRetries++;
    _liveRetryTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      _contentSub?.cancel();
      _tripSub?.cancel();
      _presenceSub?.cancel();
      _contentSub = _tripSub = null;
      _presenceSub = null;
      _startLive();
    });
  }

  void _stopLive() {
    final wasLive = _contentSub != null;
    _contentSub?.cancel();
    _tripSub?.cancel();
    _presenceSub?.cancel();
    _presenceTimer?.cancel();
    _presenceDebounce?.cancel();
    _liveRetryTimer?.cancel();
    if (wasLive && _myUid.isNotEmpty) {
      TripService().clearPresence(widget.trip.userId, widget.trip.id, _myUid).catchError((_) {});
    }
  }

  void _sendPresence() {
    if (_isSampleEditor || _myUid.isEmpty) return;
    TripService()
        .setPresence(widget.trip.userId, widget.trip.id, _myUid,
            name: _myName, photo: FirebaseAuth.instance.currentUser?.photoURL, blockId: _focusedBlockId)
        .catchError((e) => debugPrint('Presencia: $e'));
  }

  void _setFocusedBlock(String? id) {
    if (_focusedBlockId == id) return;
    _focusedBlockId = id;
    _presenceDebounce?.cancel();
    _presenceDebounce = Timer(const Duration(milliseconds: 400), _sendPresence);
  }

  void _onContentSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted || snap.metadata.hasPendingWrites) return;
    final data = snap.data();
    if (data == null) return;
    final rev = (data['rev'] as num?)?.toInt();
    if (rev != null && rev < _contentRev) return; // aviso viejo: ya está incorporado
    if (_isSavingCloud) {
      _pendingContentSnap = snap;
      return;
    }
    if (rev != null) _contentRev = rev;
    final who = data['updatedBy'] == _myUid ? '' : (data['updatedByName'] ?? '').toString();
    _syncAllTables();
    final remote = TripContent.fromMap(data).sections;
    final oldBase = _baseSections;
    final m = mergeSections(oldBase, _sections, remote);
    _baseSections = remote;
    _rebaseHistory(oldBase, remote);
    _applyMerge(m, who: who);
  }

  void _onTripSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted || snap.metadata.hasPendingWrites) return;
    final data = snap.data();
    if (data == null) return;
    final rev = (data['editRev'] as num?)?.toInt();
    if (rev != null && rev < _tripRev) return;
    if (_isSavingCloud) {
      _pendingTripSnap = snap;
      return;
    }
    if (rev != null) _tripRev = rev;
    final remote = TripService.editorTripFieldsFromDoc(data, widget.trip.id);
    final oldBase = _baseTrip;
    final local = TripService.editorTripFields(_buildCurrentTrip());
    final m = mergeFields(oldBase, local, remote);
    _baseTrip = remote;
    _rebaseHistoryTrip(oldBase, remote);
    if (!deepEquals(m.value, local)) _applyTripFields(m.value);
    _offerTripConflicts(m.conflicts, remote, data['editedBy'] == _myUid ? '' : (data['editedByName'] ?? '').toString());
  }

  /// Aplica a la pantalla el resultado de un merge de bloques.
  void _applyMerge(SectionMergeResult m, {required String who}) {
    final sections = List<TripSection>.of(m.sections);
    final conflicts = Map<String, TripSection?>.of(m.conflicts);
    // Si se está escribiendo con acento (composición del teclado) en un bloque que cambió
    // fuera, no se le cambia el texto bajo el cursor: se queda lo local y se marca.
    final changed = Set<String>.of(m.changedIds);
    for (final id in changed.where(_blockIsComposing).toList()) {
      final i = sections.indexWhere((s) => s.id == id);
      final j = _idx(id);
      if (i >= 0 && j >= 0) {
        conflicts[id] = sections[i];
        sections[i] = _sections[j];
        changed.remove(id);
      }
    }
    if (!m.touchesLocal && conflicts.isEmpty && m.deletedHereChangedThere.isEmpty) return;
    _applyingRemote = true;
    try {
      setState(() {
        _sections = sections;
        for (final e in conflicts.entries) {
          _conflicts[e.key] = e.value;
          _conflictBy[e.key] = who;
        }
        for (final id in m.removedIds) {
          _conflicts.remove(id);
        }
      });
      for (final id in changed) {
        _refreshBlockEditors(id);
      }
      for (final id in m.removedIds) {
        _dropBlockEditors(id);
      }
    } finally {
      _applyingRemote = false;
    }
    _currentSnapshot = _buildSnapshot();
    if (m.deletedHereChangedThere.isNotEmpty) _offerRestore(m.deletedHereChangedThere, who);
  }

  bool _blockIsComposing(String id) {
    if (_focusedBlockId != id) return false;
    for (final e in _blockControllers.entries) {
      if (e.key == id || e.key.startsWith('${id}_')) {
        final c = e.value.value.composing;
        if (c.isValid && !c.isCollapsed) return true;
      }
    }
    return false;
  }

  /// Textos que deben mostrar los editores de un bloque (llave del controlador → texto).
  Map<String, String> _blockTexts(TripSection s) {
    String num(double v, {bool fixed = false}) =>
        v > 0 ? (fixed ? v.toStringAsFixed(v % 1 == 0 ? 0 : 2) : v.toString()) : '';
    if (s is PlaceSection) {
      return {'${s.id}_title': s.title, '${s.id}_desc': s.description, '${s.id}_cost': num(s.cost)};
    }
    if (s is TextSection) return {s.id: s.markdownText};
    if (s is TextImageSection) return {s.id: s.markdownText};
    if (s is ProposalSection) return {'${s.id}_question': s.question};
    if (s is SplitSection) return {for (final b in s.branches) '${s.id}_branch_${b.id}': b.name};
    if (s is TransferSection) {
      return {
        '${s.id}_mins': s.durationMins?.toString() ?? '',
        '${s.id}_km': s.distanceKm?.toString() ?? '',
        '${s.id}_cost': num(s.cost, fixed: true),
        '${s.id}_notes': s.notes,
      };
    }
    return const {};
  }

  static bool _isNumericKey(String key) => key.endsWith('_cost') || key.endsWith('_mins') || key.endsWith('_km');

  /// Pone [text] en un controlador sin mover el cursor de lugar (si alguien escribe antes
  /// del cursor, el cursor se recorre con el texto).
  void _setControllerText(TextEditingController c, String text, {bool numeric = false}) {
    final current = c is MarkdownRichTextController ? c.markdownText : c.text;
    if (current == text) return;
    if (numeric && double.tryParse(current) == double.tryParse(text)) return;
    final oldPlain = c.text;
    final sel = c.selection;
    c.text = text;
    final newPlain = c.text;
    if (sel.isValid) {
      int map(int o) => mapTextOffset(oldPlain, newPlain, o).clamp(0, newPlain.length);
      c.selection = TextSelection(baseOffset: map(sel.baseOffset), extentOffset: map(sel.extentOffset));
    }
  }

  /// Un bloque cambió fuera: si no tiene el foco se recrean sus editores con el contenido
  /// nuevo; si lo tiene, se actualiza el texto en su lugar sin mover el cursor.
  void _refreshBlockEditors(String id) {
    final i = _idx(id);
    if (i < 0) return;
    if (_focusedBlockId == id) {
      _blockTexts(_sections[i]).forEach((key, text) {
        final c = _blockControllers[key];
        if (c != null) _setControllerText(c, text, numeric: _isNumericKey(key));
      });
    } else {
      _dropBlockEditors(id);
      _blockGen[id] = (_blockGen[id] ?? 0) + 1;
    }
  }

  void _dropBlockEditors(String id) {
    final keys = [for (final k in _blockControllers.keys) if (k == id || k.startsWith('${id}_')) k];
    final old = [for (final k in keys) _blockControllers.remove(k)!];
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  /// Los cambios ajenos (de [oldBase] a [remote]) también entran en el historial para
  /// deshacer, en la referencia de la fe de erratas y en la de retroalimentación: así
  /// "Deshacer" no borra lo que escribió otro ni se atribuyen sus cambios a quien edita aquí.
  void _rebaseHistory(List<TripSection> oldBase, List<TripSection> remote) {
    if (deepEquals([for (final s in oldBase) s.toMap()], [for (final s in remote) s.toMap()])) return;
    String rebase(String snap) {
      final d = jsonDecode(snap) as Map<String, dynamic>;
      final secs = [for (final m in (d['sections'] as List)) TripSection.fromMap(Map<String, dynamic>.from(m as Map))];
      d['sections'] = [for (final s in mergeSections(oldBase, secs, remote).sections) s.toMap()];
      return jsonEncode(d);
    }

    for (int i = 0; i < _undoStack.length; i++) {
      _undoStack[i] = rebase(_undoStack[i]);
    }
    for (int i = 0; i < _redoStack.length; i++) {
      _redoStack[i] = rebase(_redoStack[i]);
    }
    if (_errataBaseline != null) _errataBaseline = mergeSections(oldBase, _errataBaseline!, remote).sections;
    final baseline = _feedbackBaseline;
    if (baseline != null) {
      final before = _catalogStops(oldBase), after = _catalogStops(remote);
      for (final id in {...before.keys, ...after.keys}) {
        if (before[id] == after[id]) continue;
        if (after[id] == null) {
          baseline.remove(id);
        } else {
          baseline[id] = after[id]!;
        }
      }
    }
  }

  void _rebaseHistoryTrip(Map<String, dynamic> oldBase, Map<String, dynamic> remote) {
    const keys = ['title', 'description', 'coverUrl'];
    if (keys.every((k) => deepEquals(oldBase[k], remote[k]))) return;
    String rebase(String snap) {
      final d = jsonDecode(snap) as Map<String, dynamic>;
      for (final k in keys) {
        final l = d[k] ?? '', b = oldBase[k] ?? '', r = remote[k] ?? '';
        d[k] = (k == 'coverUrl') ? (l == b ? r : l) : mergeText(b.toString(), l.toString(), r.toString()).text;
      }
      return jsonEncode(d);
    }

    for (int i = 0; i < _undoStack.length; i++) {
      _undoStack[i] = rebase(_undoStack[i]);
    }
    for (int i = 0; i < _redoStack.length; i++) {
      _redoStack[i] = rebase(_redoStack[i]);
    }
    final baseTrip = _errataBaselineTrip;
    if (baseTrip != null) {
      final m = mergeFields(oldBase, TripService.editorTripFields(baseTrip), remote);
      _errataBaselineTrip = Trip.fromMap({...baseTrip.toMap(), ...m.value}, baseTrip.id);
    }
  }

  /// Pone en el editor los campos del viaje combinados (título, descripción, fecha, portada…).
  void _applyTripFields(Map<String, dynamic> fields) {
    final t = Trip.fromMap({..._liveTrip.toMap(), ...fields}, widget.trip.id);
    _applyingRemote = true;
    try {
      setState(() {
        _liveTrip = t;
        _setControllerText(_titleController, t.title);
        if (t.description != _descriptionMarkdown) {
          _setControllerText(_descriptionController, t.description);
          _rememberDescription(t.description);
        }
        if (_isNotes && (t.version ?? '').isNotEmpty) _setControllerText(_versionController, t.version!);
        _coverUrl = t.coverUrl;
        _travelDate = t.travelDate;
        _startPoint = t.startPoint;
        _endPoint = t.endPoint;
        _routeShape = t.routeShape;
        _status = t.status;
        _visibility = t.visibility;
        _errataHistory = List.of(t.errataHistory);
        _coAuthorIds = List.of(t.coAuthorIds);
        _coAuthorNames = List.of(t.coAuthorNames);
        _isSurprise = t.isSurprise;
        _surpriseTargetIds = List.of(t.surpriseTargetIds);
        _surpriseTargetNames = List.of(t.surpriseTargetNames);
        _surpriseUnlockDates = Map.of(t.surpriseUnlockDates);
        _unlockOnPublish = t.unlockOnPublish;
      });
    } finally {
      _applyingRemote = false;
    }
    _currentSnapshot = _buildSnapshot();
  }

  // El editor enriquecido puede escribir el mismo markdown de otra forma. Mientras la
  // descripción no se toque, se reporta tal como vino (si no, contaría como cambio local
  // y le ganaría a lo que otro escriba en ella).
  String _descLoadedFrom = '';
  String _descLoadedAs = '';

  void _rememberDescription(String markdown) {
    _descLoadedFrom = markdown;
    _descLoadedAs = _descriptionController.markdownText;
  }

  String get _descriptionMarkdown {
    final md = _descriptionController.markdownText;
    return md == _descLoadedAs ? _descLoadedFrom : md;
  }

  static const Map<String, String> _tripFieldLabels = {
    'title': 'el título',
    'description': 'la descripción',
    'travelDate': 'la fecha',
    'coverUrl': 'la portada',
  };

  /// Los dos cambiaron el mismo dato del viaje: se quedó el de aquí; se ofrece tomar el otro.
  void _offerTripConflicts(Set<String> conflicts, Map<String, dynamic>? remote, String who) {
    final keys = [for (final k in _tripFieldLabels.keys) if (conflicts.contains(k)) k];
    if (keys.isEmpty || remote == null || !mounted) return;
    final name = who.isEmpty ? 'Otra persona' : who;
    final what = keys.map((k) => _tripFieldLabels[k]!).join(' y ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name también cambió $what al mismo tiempo. Se quedó lo tuyo.', style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.onyx,
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Usar lo suyo',
          textColor: OhtliColors.accent,
          onPressed: () {
            if (!mounted) return;
            final local = TripService.editorTripFields(_buildCurrentTrip());
            _applyTripFields({...local, for (final k in keys) k: remote[k]});
            _forceNewUndoStep = true;
            _onDataChanged();
          },
        ),
      ),
    );
  }

  void _offerRestore(Map<String, TripSection> deleted, String who) {
    if (!mounted) return;
    final n = deleted.length;
    final name = who.isEmpty ? 'Otra persona' : who;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 1 ? 'Borraste un bloque que $name acababa de cambiar.' : 'Borraste $n bloques que $name acababa de cambiar.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.onyx,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Restaurar',
          textColor: OhtliColors.accent,
          onPressed: () {
            if (!mounted) return;
            setState(() {
              for (final s in deleted.values) {
                if (_idx(s.id) < 0) _sections.add(s);
              }
              _forceNewUndoStep = true;
            });
            _onDataChanged();
          },
        ),
      ),
    );
  }

  /// "Usar la suya": cambia el bloque por la versión de la otra persona.
  void _resolveConflict(String id, {required bool useTheirs}) {
    final theirs = _conflicts[id];
    setState(() {
      _conflicts.remove(id);
      _conflictBy.remove(id);
      if (!useTheirs) return;
      final i = _idx(id);
      if (i < 0) return;
      if (theirs == null) {
        _sections.removeAt(i);
      } else {
        _sections[i] = theirs;
      }
      _dropBlockEditors(id);
      _blockGen[id] = (_blockGen[id] ?? 0) + 1;
      _forceNewUndoStep = true;
    });
    if (useTheirs) _onDataChanged();
  }

  void _checkLocalCache() {
    if (!kIsWeb) return;

    try {
      final String? cachedStr = web.window.localStorage.getItem('ohtli_trip_draft_${widget.trip.id}');
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
                  color: OhtliColors.accent,
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
        _rememberDescription(cache['trip']['description'] ?? '');
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
      web.window.localStorage.removeItem('ohtli_trip_draft_${widget.trip.id}');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Borrador local descartado.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.warning,
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

  // ---------------------------------------------------------------------------
  // Fotos: se suben a Storage en cuanto se recortan, no hasta guardar
  // ---------------------------------------------------------------------------
  /// Subidas en curso o hechas en esta sesión: data URI → URL (null si falló).
  final Map<String, Future<String?>> _photoUploads = {};

  /// Avance (0 a 1) de las que siguen subiendo, para el indicador de guardado.
  final Map<String, double> _photoUploadProgress = {};

  /// Fotos de bloques subidas aquí; las que se reemplacen antes de guardar se borran.
  final Set<String> _uploadedHere = {};

  String get _tripStoragePath => 'users/${widget.trip.userId}/trips/${widget.trip.id}';

  /// Sube ya la foto recién recortada [dataUrl] (a sections/[fileName], o a la portada del viaje
  /// con [cover]) y, al terminar, cambia el data URI por la URL donde aparezca. Si falla, el data
  /// URI se queda y el guardado lo vuelve a intentar.
  Future<String?> _uploadPhotoNow(String dataUrl, String fileName, {bool cover = false}) {
    if (!dataUrl.startsWith('data:') || _isSampleEditor) return Future.value(null);
    final pending = _photoUploads[dataUrl];
    if (pending != null) return pending;
    final future = () async {
      if (mounted) setState(() => _photoUploadProgress[dataUrl] = 0);
      try {
        final url = await PhotoStorage.uploadDataUrl(
          cover ? '$_tripStoragePath/cover.jpg' : '$_tripStoragePath/sections/$fileName',
          dataUrl,
          replaces: cover,
          onProgress: (p) {
            if (mounted && _photoUploadProgress.containsKey(dataUrl)) setState(() => _photoUploadProgress[dataUrl] = p);
          },
        );
        if (!cover) _uploadedHere.add(url);
        // La vista previa ya está en memoria: no se vuelve a descargar
        final cached = _imageProvidersCache[dataUrl];
        if (cached != null) _imageProvidersCache[url] = cached;
        if (mounted) _swapPhotoUrl(dataUrl, url);
        return url;
      } catch (e) {
        debugPrint('No se pudo subir la foto ahora: $e');
        _photoUploads.remove(dataUrl);
        return null;
      } finally {
        if (mounted) setState(() => _photoUploadProgress.remove(dataUrl));
      }
    }();
    _photoUploads[dataUrl] = future;
    return future;
  }

  /// Cambia la foto [from] por [to] en la portada y en los bloques donde siga.
  void _swapPhotoUrl(String from, String to) {
    var changed = false;
    String swap(String u) {
      if (u != from) return u;
      changed = true;
      return to;
    }

    setState(() {
      _coverUrl = swap(_coverUrl);
      for (var i = 0; i < _sections.length; i++) {
        final s = _sections[i];
        if (s is PlaceSection) {
          final before = changed;
          changed = false;
          final main = swap(s.mainPhotoUrl);
          final sec = s.secondaryPhotoUrls.map(swap).toList();
          final cov = s.coverUrl == null ? null : swap(s.coverUrl!);
          if (changed) _sections[i] = s.copyWith(mainPhotoUrl: main, secondaryPhotoUrls: sec, coverUrl: cov);
          changed = changed || before;
        } else if (s is TextImageSection && s.imageUrl == from) {
          changed = true;
          _sections[i] = TextImageSection(id: s.id, markdownText: s.markdownText, imageUrl: to, layout: s.layout);
        }
      }
    });
    if (changed) _saveToLocalCache();
  }

  /// Para el guardado: la URL de [url] si todavía es un data URI (espera la subida en curso o la
  /// reintenta). Si no se puede, se queda el data URI y cuenta en [_failedUploads].
  Future<String> _persistPhoto(String url, String fileName, {bool cover = false}) async {
    if (!url.startsWith('data:') || _isSampleEditor) return url;
    final uploaded = await _uploadPhotoNow(url, fileName, cover: cover);
    if (uploaded != null) return uploaded;
    _failedUploads++;
    return url;
  }

  /// Fotos subidas aquí que ya no usa nadie: ni el viaje guardado ni este editor, ni lo que se
  /// puede recuperar con deshacer/rehacer.
  Set<String> _abandonedUploads(List<TripSection> written) {
    final inUse = {...sectionPhotoUrls(written), ...sectionPhotoUrls(_sections)};
    final abandoned = <String>{};
    for (final url in _uploadedHere) {
      if (inUse.contains(url)) continue;
      final name = _storageFileName(url);
      if (name == null) continue;
      if ([..._undoStack, ..._redoStack].any((snap) => snap.contains(name))) continue;
      abandoned.add(url);
    }
    _uploadedHere.removeAll(abandoned);
    return abandoned;
  }

  // Local caching & debounced auto-save triggers
  void _onDataChanged() {
    if (_applyingRemote) return;
    _saveToLocalCache();
    _recordUndoStep();
  }

  // ---------------------------------------------------------------------------
  // Deshacer / rehacer
  // ---------------------------------------------------------------------------
  String _buildSnapshot() => jsonEncode({
        'title': _titleController.text,
        'description': _descriptionMarkdown,
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
      _rememberDescription(data['description'] ?? '');
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
      description: _descriptionMarkdown,
      coverUrl: coverUrl ?? _coverUrl,
      status: _status,
      visibility: _visibility,
      createdAt: _liveTrip.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      travelDate: _travelDate,
      errataHistory: _errataHistory,
      // Las notas de versión solo las escribe el administrador: nunca llevan coautores.
      coAuthorIds: _isNotes ? const [] : _coAuthorIds,
      coAuthorNames: _isNotes ? const [] : _coAuthorNames,
      isSurprise: _isSurprise,
      surpriseTargetIds: _surpriseTargetIds,
      surpriseTargetNames: _surpriseTargetNames,
      surpriseUnlockDates: _surpriseUnlockDates,
      unlockOnPublish: _unlockOnPublish,
      surpriseOpenedBy: _liveTrip.surpriseOpenedBy,
      reviewedAt: _liveTrip.reviewedAt,
      finishedAt: _liveTrip.finishedAt,
      kind: _kind,
      version: _kind == kTripKindReleaseNotes && _versionController.text.trim().isNotEmpty
          ? _versionController.text.trim()
          : null,
      recommendedPoiIds: _liveTrip.recommendedPoiIds,
      recommendationJobId: _liveTrip.recommendationJobId,
      routeShape: _routeShape,
      startPoint: _startPoint,
      endPoint: _endPoint,
      groupTripId: _liveTrip.groupTripId,
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
    if (_isSampleEditor) {
      _triggerCloudAutoSaveDebounce();
      return;
    }

    try {
      final now = DateTime.now();
      final cacheData = {
        'updatedAt': now.millisecondsSinceEpoch,
        'trip': {
          'title': _titleController.text,
          'description': _descriptionMarkdown,
          'coverUrl': _coverUrl,
          'visibility': _visibility,
          'status': _status,
        },
        'content': {
          'sections': _sections.map((s) => s.toMap()).toList(),
        }
      };

      web.window.localStorage.setItem('ohtli_trip_draft_${widget.trip.id}', jsonEncode(cacheData));

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
    // Con alguien más en el editor se guarda casi enseguida, para que vea los cambios en vivo.
    _debounceTimer = Timer(Duration(milliseconds: _othersEditing ? 1000 : 4000), () {
      _saveToCloudFirestore();
    });
  }

  static Map<String, String> _catalogStops(List<TripSection> sections) => {
        for (final s in sections)
          if (s is PlaceSection && s.isLinkedToCatalog && s.poiId!.isNotEmpty) s.id: s.poiId!,
      };

  /// Compara lo guardado antes con lo que se guarda ahora y manda los cambios de paradas.
  void _reportStopChanges(List<TripSection> saved) {
    if (_isNotes) return;
    final now = _catalogStops(saved);
    final before = _feedbackBaseline;
    _feedbackBaseline = now;
    if (before == null) return;
    final recommended = widget.trip.recommendedPoiIds.toSet();
    final tripId = widget.trip.id;
    String origin(String poiId) => recommended.contains(poiId) ? 'engine' : 'manual';
    final nowPois = now.values.toSet();
    final beforePois = before.values.toSet();
    final replacedTargets = <String>{};
    before.forEach((secId, oldPoi) {
      final newPoi = now[secId];
      if (newPoi == oldPoi || nowPois.contains(oldPoi)) return; // sigue en el viaje (quizá en otra parada)
      if (newPoi != null) {
        FeedbackService.stopReplaced(oldPoi, newPoi, tripId: tripId, origin: origin(oldPoi));
        replacedTargets.add(newPoi);
      } else {
        FeedbackService.stopRemoved(oldPoi, tripId: tripId, origin: origin(oldPoi));
      }
    });
    for (final poi in nowPois.difference(beforePois)) {
      // Volver a poner una recomendación (p. ej. tras deshacer) no es un lugar nuevo
      if (replacedTargets.contains(poi) || recommended.contains(poi)) continue;
      FeedbackService.stopAdded(poi, tripId: tripId);
    }
    if (!_feedbackReorderSent) {
      final common = [for (final p in before.values) if (nowPois.contains(p)) p];
      final commonNow = [for (final p in now.values) if (beforePois.contains(p)) p];
      if (common.length > 1 && common.join('|') != commonNow.join('|')) {
        _feedbackReorderSent = true;
        FeedbackService.stopReordered(tripId: tripId);
      }
    }
  }

  Future<void> _saveToCloudFirestore() async {
    if (_isSampleEditor) {
      if (mounted) setState(() => _savedEditVersion = _editVersion);
      return;
    }
    if (_isSavingCloud) return;
    _syncAllTables();

    setState(() {
      _isSavingCloud = true;
    });
    final versionAtStart = _editVersion;
    // Copia de lo que se guarda: lo que se edite mientras tanto no se pisa al terminar.
    final List<TripSection> sectionsAtStart = List<TripSection>.of(_sections);
    final String coverAtStart = _coverUrl;
    _failedUploads = 0;

    final now = DateTime.now();

    // 1. Fotos que siguen en data URI: se espera la subida que empezó al recortarlas (o se
    // reintenta si falló). Sin conexión se quedan en base64 hasta el siguiente guardado.
    final String finalCoverUrl = await _persistPhoto(coverAtStart, 'cover.jpg', cover: true);
    final List<TripSection> updatedSections = [];
    final int timestamp = now.millisecondsSinceEpoch;
    for (final section in sectionsAtStart) {
      if (section is PlaceSection) {
        final main = await _persistPhoto(section.mainPhotoUrl, '${section.id}_main_$timestamp.jpg');
        final sec = <String>[];
        for (var i = 0; i < section.secondaryPhotoUrls.length; i++) {
          sec.add(await _persistPhoto(section.secondaryPhotoUrls[i], '${section.id}_sec_${timestamp}_$i.jpg'));
        }
        final cov = section.coverUrl == null ? null : await _persistPhoto(section.coverUrl!, '${section.id}_cover_$timestamp.jpg');
        updatedSections.add(section.copyWith(mainPhotoUrl: main, secondaryPhotoUrls: sec, coverUrl: cov));
      } else if (section is TextImageSection) {
        final img = await _persistPhoto(section.imageUrl, '${section.id}_image_$timestamp.jpg');
        updatedSections.add(TextImageSection(
          id: section.id,
          markdownText: section.markdownText,
          imageUrl: img,
          layout: section.layout,
        ));
      } else {
        updatedSections.add(section);
      }
    }

    final updatedTrip = _buildCurrentTrip(coverUrl: finalCoverUrl, updatedAt: now);
    final tripFieldsSent = TripService.editorTripFields(updatedTrip);
    final baseSectionsAtStart = _baseSections;
    final baseTripAtStart = _baseTrip;

    try {
      // Transacción: lee lo que hay en la nube, lo combina con lo local y escribe el
      // resultado (antes era un set() completo y ganaba el último en guardar).
      final r = await TripService().saveTripLive(
        ownerId: widget.trip.userId,
        localTrip: updatedTrip,
        baseTrip: baseTripAtStart,
        baseSections: baseSectionsAtStart,
        localSections: updatedSections,
        baseRev: math.max(_contentRev, _tripRev),
        editorUid: _myUid,
        editorName: _myName,
      );
      _contentRev = math.max(_contentRev, r.rev);
      _tripRev = math.max(_tripRev, r.rev);

      // Lo que otros habían guardado y entró en esta escritura también va al historial
      // para deshacer y a las referencias (fe de erratas, retroalimentación).
      _rebaseHistory(baseSectionsAtStart, r.remoteSections);
      if (r.remoteTripFields != null) _rebaseHistoryTrip(baseTripAtStart, r.remoteTripFields!);
      _reportStopChanges(r.sections);

      // De Storage solo se borran las fotos que quitó este editor, nunca las de otros.
      await _cleanupStoragePhotos(widget.trip.userId, widget.trip.id,
          {...photosRemovedHere(base: baseSectionsAtStart, local: updatedSections, written: r.sections), ..._abandonedUploads(r.sections)});

      if (mounted) {
        final who = r.remoteEditorUid == _myUid ? '' : r.remoteEditorName;
        setState(() {
          // Solo se cambian las fotos recién subidas; los textos editados durante el guardado se quedan.
          _sections = mergeUploadedPhotos(_sections, sectionsAtStart, updatedSections);
          if (_coverUrl == coverAtStart) _coverUrl = finalCoverUrl;
          _baseSections = r.sections;
          _baseTrip = r.tripFields;
          for (final e in r.conflicts.entries) {
            _conflicts[e.key] = e.value;
            _conflictBy[e.key] = who;
          }
          _isSavingCloud = false;
          _lastSavedCloudTime = now;
          _cloudSaveError = null;
          // Si hubo fotos sin subir, el cambio sigue pendiente para reintentarlo
          _savedEditVersion = _failedUploads > 0 ? versionAtStart - 1 : versionAtStart;
        });
        // Lo que entró de otros al escribir se muestra, sin tocar lo editado mientras tanto.
        _applyMerge(mergeSections(updatedSections, _sections, r.sections), who: who);
        final localFields = TripService.editorTripFields(_buildCurrentTrip());
        final tm = mergeFields(tripFieldsSent, localFields, r.tripFields);
        if (!deepEquals(tm.value, localFields)) _applyTripFields(tm.value);
        _offerTripConflicts({...r.tripConflicts, ...tm.conflicts}, r.remoteTripFields, who);
        if (r.deletedHereChangedThere.isNotEmpty) _offerRestore(r.deletedHereChangedThere, who);
        _drainPendingSnapshots();
        // Lo que se editó mientras se guardaba se sube enseguida en otro guardado.
        if (_editVersion != versionAtStart && _debounceTimer?.isActive != true) {
          _debounceTimer = Timer(Duration(seconds: _othersEditing ? 1 : 2), _saveToCloudFirestore);
        }
        if (_failedUploads > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _failedUploads == 1
                    ? 'Una foto no se pudo subir. La volveremos a intentar en el siguiente guardado.'
                    : '$_failedUploads fotos no se pudieron subir. Las volveremos a intentar en el siguiente guardado.',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: OhtliColors.accentFill,
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
        _drainPendingSnapshots();
      }
    }
  }

  /// Aplica los avisos del listener que llegaron mientras se guardaba.
  void _drainPendingSnapshots() {
    final c = _pendingContentSnap, t = _pendingTripSnap;
    _pendingContentSnap = null;
    _pendingTripSnap = null;
    if (c != null) _onContentSnapshot(c);
    if (t != null) _onTripSnapshot(t);
  }

  /// Nombre del archivo en Storage de una URL de descarga de Firebase (o null si no es de Storage).
  static String? _storageFileName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.contains('firebasestorage')) return null;
    // pathSegments ya viene decodificado: el último es "users/…/sections/archivo.jpg".
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.split('/').last;
    return name.isEmpty ? null : name;
  }

  /// Borra de Storage las fotos de bloques que quitó este editor ([removedUrls], ver
  /// [photosRemovedHere]). Las que no conoce (p. ej. las que acaba de subir otro coautor)
  /// nunca se tocan, aunque todavía no lleguen a esta pantalla.
  Future<void> _cleanupStoragePhotos(String userId, String tripId, Set<String> removedUrls) async {
    final names = {for (final u in removedUrls) _storageFileName(u)}..remove(null);
    if (names.isEmpty) return;
    try {
      final listResult = await FirebaseStorage.instance.ref('users/$userId/trips/$tripId/sections').listAll();
      for (final item in listResult.items) {
        if (!names.contains(item.name)) continue;
        debugPrint("Borrando foto quitada en este editor: ${item.name}");
        await item.delete();
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
  /// Agrega un bloque al final, en la posición [at] o en lugar del bloque [replaceId].
  void _addBlock(String type, {int? at, String? replaceId}) {
    final String id = 'sec_${DateTime.now().millisecondsSinceEpoch}_${_sections.length}';
    final added = <TripSection>[];
    void add(TripSection s) => added.add(s);
    _buildNewBlock(type, id, add);
    if (added.isEmpty) return;
    setState(() {
      final int replaceAt = replaceId == null ? -1 : _sections.indexWhere((s) => s.id == replaceId);
      if (replaceAt >= 0) {
        _sections[replaceAt] = added.first;
      } else if (at != null && at >= 0 && at <= _sections.length) {
        _sections.insert(at, added.first);
      } else {
        _sections.add(added.first);
      }
      _assignDefaultBranch(id);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
    if (type == 'transfer') _openTransfers.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(id));
  }

  void _buildNewBlock(String type, String id, void Function(TripSection) add) {
    {
      if (type == 'place') {
        add(PlaceSection(
          id: id,
          title: '',
          description: '',
          rating: 0,
          mainPhotoUrl: '',
          secondaryPhotoUrls: [],
          changeTag: _isNotes ? 'nuevo' : null,
        ));
      } else if (type == 'detour') {
        // En las notas de versión, un desvío cuenta algo que viene en camino.
        add(PlaceSection(
          id: id,
          title: '',
          description: '',
          rating: 0,
          mainPhotoUrl: '',
          secondaryPhotoUrls: [],
          unplanned: true,
        ));
      } else if (type == 'text') {
        add(TextSection(
          id: id,
          markdownText: '',
        ));
      } else if (type == 'text_image') {
        add(TextImageSection(
          id: id,
          markdownText: '',
          imageUrl: '',
          layout: 'left',
        ));
      } else if (type == 'table') {
        add(TextSection(
          id: id,
          markdownText: '| Columna 1 | Columna 2 |\n|---|---|\n| Celda 1 | Celda 2 |',
        ));
      } else if (type == 'notes') {
        add(TextSection(
          id: id,
          markdownText: '> [!NOTE]\n> Escribe tu nota aquí',
        ));
      } else if (type == 'transfer') {
        add(TransferSection(id: id));
      } else if (type == 'proposal') {
        add(ProposalSection(id: id, question: ''));
      } else if (type == 'split') {
        final stamp = DateTime.now().microsecondsSinceEpoch;
        add(SplitSection(id: id, branches: [
          TripBranch(id: 'br_${stamp}_1', name: 'Grupo 1'),
          TripBranch(id: 'br_${stamp}_2', name: 'Grupo 2'),
        ]));
      }
    }
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
          textColor: OhtliColors.accent,
          onPressed: _undo,
        ),
      ),
    );
  }

  void _duplicateBlock(int index) {
    final map = Map<String, dynamic>.from(_sections[index].toMap());
    map['id'] = 'sec_${DateTime.now().millisecondsSinceEpoch}_${_sections.length}';
    if (map['type'] == 'split' && map['branches'] is List) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final list = map['branches'] as List;
      map['branches'] = [for (int k = 0; k < list.length; k++) {...Map<String, dynamic>.from(list[k] as Map), 'id': 'br_${stamp}_$k'}];
    }
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
      if (_isNotes && s.unplanned) return (t.isEmpty ? 'Próximamente sin título' : t, Icons.alt_route_rounded);
      if (_isNotes) return (t.isEmpty ? 'Novedad sin título' : t, Icons.new_releases_rounded);
      return (t.isEmpty ? 'Lugar sin nombre' : t, Icons.location_on_rounded);
    }
    if (s is ProposalSection) {
      return (s.question.trim().isEmpty ? 'Propuesta de lugares' : s.question.trim(), Icons.how_to_vote_rounded);
    }
    if (s is SplitSection) {
      final names = [for (int i = 0; i < s.branches.length; i++) branchName(s.branches[i], i)];
      return (names.isEmpty ? 'El grupo se separa' : 'Se separan: ${names.join(' · ')}', Icons.call_split_rounded);
    }
    // Cualquier otro tipo que no sea texto se nombra genérico (no truena con bloques nuevos).
    if (s is! TextSection && s is! TextImageSection) return ('Bloque', Icons.article_outlined);
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
    if (_applyingRemote) return;
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

  /// Revisa en qué quedaron las sugerencias de lugar usadas en el viaje: las aprobadas
  /// pasan a ser lugares del catálogo (mismo id) y las demás muestran su estado.
  Future<void> _syncSuggestionStatuses() async {
    final ids = _sections.whereType<PlaceSection>().where((p) => p.isSuggestion).map((p) => p.poiId!).toSet();
    if (ids.isEmpty) return;
    final statuses = await PoiSuggestionService.statuses(ids);
    if (!mounted || statuses.isEmpty) return;
    setState(() => _suggestionStatus.addAll(statuses));
    for (final place in _sections.whereType<PlaceSection>().toList()) {
      if (place.isSuggestion && statuses[place.poiId] == kSuggestionApproved) {
        _replacePlace(place.id, (p) => p.copyWith(poiSource: kPlaceSourceCatalog));
      }
    }
  }

  /// Vincula la parada con un lugar de la base de Ohtli, o crea una sugerencia de
  /// lugar nuevo si no está en el catálogo.
  Future<void> _linkPlaceFromCatalog(String sectionId) async {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final i = _idx(sectionId);
    if (i < 0 || _sections[i] is! PlaceSection) return;
    final current = _sections[i] as PlaceSection;
    final Object? choice = await showDialog<Object>(
      context: context,
      builder: (ctx) => _CatalogPickerDialog(isDark: isDark, normalize: _normalize, initialQuery: current.title),
    );
    if (choice == null || !mounted) return;

    if (choice is _SuggestNewPlace) {
      await _suggestNewPlace(sectionId, choice.name);
      return;
    }
    final poi = choice as Poi;
    _replacePlace(
      sectionId,
      (p) => p.copyWith(
        title: poi.name,
        description: p.description.trim().isEmpty ? poi.cleanNarrative : null,
        mainPhotoUrl: p.mainPhotoUrl.isEmpty && poi.imageUrl.isNotEmpty ? poi.imageUrl : null,
        cost: p.cost <= 0 ? (poi.priceMxnAvg ?? (poi.priceLevel * 60.0)) : null,
        lat: poi.location.isValid ? poi.location.lat : null,
        lng: poi.location.isValid ? poi.location.lng : null,
        poiId: poi.poiId,
        poiSource: kPlaceSourceCatalog,
      ),
      resetEditors: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          poi.location.isValid
              ? '${poi.name} ya aparece en el mapa.'
              : 'Elegiste ${poi.name}, pero no tiene coordenadas en el catálogo.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.stormyTeal,
      ),
    );
  }

  Future<void> _suggestNewPlace(String sectionId, String name) async {
    final i = _idx(sectionId);
    if (i < 0 || _sections[i] is! PlaceSection) return;
    final place = _sections[i] as PlaceSection;
    final result = await showDialog<_SuggestedPlace>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SuggestPlaceDialog(
        initialName: name.trim().isNotEmpty ? name.trim() : place.title,
        initialDescription: place.description,
        initialLat: place.lat,
        initialLng: place.lng,
        photoUrl: place.mainPhotoUrl.startsWith('http') ? place.mainPhotoUrl : '',
        priceMxnAvg: place.cost > 0 ? place.cost : null,
        tripId: widget.trip.id,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _suggestionStatus[result.id] = kSuggestionPending);
    _replacePlace(
      sectionId,
      (p) => p.copyWith(
        title: result.name,
        description: p.description.trim().isEmpty && result.description.isNotEmpty ? result.description : null,
        lat: result.lat,
        lng: result.lng,
        poiId: result.id,
        poiSource: kPlaceSourceSuggestion,
      ),
      resetEditors: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Enviamos "${result.name}" para revisión. Ya puedes usarlo en tu viaje; '
          'cuando se apruebe, otras personas también podrán encontrarlo.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.stormyTeal,
        duration: const Duration(seconds: 6),
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
    if (_kind == kTripKindReleaseNotes) {
      final version = _versionController.text.trim();
      if (!isSuperUser()) {
        errors.add('Solo el administrador de Ohtli puede publicar notas de versión.');
      } else if (version.isEmpty) {
        errors.add('Estas notas no tienen versión.');
      } else {
        // Una sola nota por versión
        try {
          final existing = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.trip.userId)
              .collection('trips')
              .where('kind', isEqualTo: kTripKindReleaseNotes)
              .where('version', isEqualTo: version)
              .get();
          if (existing.docs.any((d) => d.id != widget.trip.id)) {
            errors.add('Ya existen notas de la versión v$version. Edita esas en lugar de crear otras.');
          }
        } catch (_) {}
      }
    }
    if (_sections.isEmpty) errors.add('La bitácora está vacía: añade al menos un bloque.');
    final unnamed = places.where((p) => p.title.trim().isEmpty).length;
    if (_isNotes) {
      if (unnamed > 0) errors.add(unnamed == 1 ? 'Hay 1 novedad sin título.' : 'Hay $unnamed novedades sin título.');
    } else if (unnamed > 0) {
      errors.add(unnamed == 1 ? 'Hay 1 lugar sin nombre.' : 'Hay $unnamed lugares sin nombre.');
    }
    if (_coverUrl.isEmpty) warnings.add('No tiene imagen de portada.');
    if (_descriptionController.markdownText.trim().isEmpty) warnings.add('No tiene descripción.');
    if (_isNotes) places.clear(); // Las novedades no llevan ubicación ni foto obligatoria
    final noLocation = places.where((p) => p.lat == null || p.lng == null).length;
    if (noLocation > 0) {
      warnings.add(noLocation == 1
          ? '1 lugar no tiene ubicación y no saldrá bien en el mapa.'
          : '$noLocation lugares no tienen ubicación y no saldrán bien en el mapa.');
    }
    final noPhoto = places.where((p) => p.mainPhotoUrl.isEmpty).length;
    if (noPhoto > 0) warnings.add(noPhoto == 1 ? '1 lugar no tiene foto.' : '$noPhoto lugares no tienen foto.');
    final undecided = _sections.whereType<ProposalSection>().length;
    if (undecided > 0) {
      warnings.add(undecided == 1 ? 'Hay una votación de lugares sin decidir.' : 'Hay $undecided votaciones de lugares sin decidir.');
    }
    if (errors.isEmpty && warnings.isEmpty) return true;

    Widget row(String text, bool isError) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isError ? Icons.error_rounded : Icons.warning_amber_rounded,
                  size: 18, color: OhtliColors.warning),
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
    if (_applyingRemote) return;
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
    if (_applyingRemote) return;
    if (index < 0 || index >= _sections.length || _sections[index] is! TextSection) return;
    final current = _sections[index] as TextSection;
    if (markdown != null && markdown.trim() == '/' && current.markdownText.trim().isEmpty) {
      final id = current.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showInsertMenu(replaceId: id));
    }
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
    if (_applyingRemote) return;
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
      pickFile(accept: 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw').then((picked) {
        if (picked == null || picked.bytes.isEmpty || !mounted) return;
              try {
                final Uint8List bytes = picked.bytes;
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
                      _uploadPhotoNow(finalPhotoUrl, '${sectionId}_${type}_${DateTime.now().millisecondsSinceEpoch}.jpg');
                      if (type == 'place_main') {
                        _updatePlaceBlock(index, mainPhoto: finalPhotoUrl);
                      } else if (type == 'place_sec_0') {
                        _updatePlaceSecondaryPhoto(index, 0, finalPhotoUrl);
                      } else if (type == 'place_sec_1') {
                        _updatePlaceSecondaryPhoto(index, 1, finalPhotoUrl);
                      } else if (type == 'text_image') {
                        _updateTextImageBlock(index, photo: finalPhotoUrl);
                      }
                      // Foto de un lugar del catálogo: se ofrece donarla para que sea la del lugar
                      final placed = _sections[index];
                      if (type.startsWith('place_') && placed is PlaceSection && (placed.poiId ?? '').isNotEmpty) {
                        Future.delayed(const Duration(milliseconds: 250), () {
                          if (mounted) {
                            offerPhotoDonation(this.context,
                                poiId: placed.poiId!, poiName: placed.title, dataUrl: finalPhotoUrl, tripId: widget.trip.id);
                          }
                        });
                      }
                    },
                  ),
                );
              } catch (err) {
                print("Error decodando imagen: $err");
              }
      });
    } catch (err) {
      print("Error abriendo selector de imágenes: $err");
    }
  }

  void _uploadCoverImage() {
    if (!kIsWeb) return;

    try {
      pickFile(accept: 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw').then((picked) {
        if (picked == null || picked.bytes.isEmpty || !mounted) return;
              try {
                final Uint8List bytes = picked.bytes;
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
                      _uploadPhotoNow(base64String, 'cover.jpg', cover: true);
                    },
                  ),
                );
              } catch (err) {
                print("Error decodando portada: $err");
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
                  backgroundColor: OhtliColors.accentFill,
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
                      if (!_isNotes) ...[
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
                            // Éxito de la recomendación: publicarlo (no privado) cuenta como compartirlo.
                            if (_visibility != 'private') {
                              FeedbackService.itineraryShared(
                                  tripId: widget.trip.id, jobId: widget.trip.recommendationJobId, channel: 'publicar');
                            }
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
                                  backgroundColor: OhtliColors.warning,
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
                  Icon(Icons.history_edu_rounded, color: OhtliColors.accent, size: 20),
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
                        borderSide: BorderSide(color: OhtliColors.accent, width: 1.2),
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

                          _syncAllTables();
                          final newErrata = _errataSinceBaseline(note: noteText) ??
                              ErrataEntry(id: const Uuid().v4(), note: noteText, date: DateTime.now());
                          _resetErrataBaseline();

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
                                  backgroundColor: OhtliColors.accentFill,
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
                                  backgroundColor: OhtliColors.warning,
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
                    backgroundColor: OhtliColors.accentFill,
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

  bool get _isSampleEditor => widget.sampleSections != null;

  /// Los controles del dueño también se ven en la muestra (sin guardar).
  bool get _ownerUi => _isOwner || _isSampleEditor;

  void _sampleNotice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: GoogleFonts.inter())));
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
    if (_isSampleEditor) {
      _sampleNotice('En la muestra no se invitan coautores.');
      return;
    }
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
    if (_isSampleEditor) {
      _sampleNotice('Es el editor de muestra: aquí no se publica.');
      return;
    }
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
    if (_isSampleEditor) return true;
    _syncAllTables();
    if (_isPostTrip) {
      final entry = _errataSinceBaseline();
      if (entry != null) {
        _errataHistory.add(entry);
        _resetErrataBaseline();
        _editVersion++; // queda pendiente: se guarda abajo antes de salir
      }
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.accentFill, foregroundColor: Colors.white),
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

    String syncStatusText = "Guardado en este dispositivo";
    IconData syncIcon = Icons.cloud_queue_rounded;
    Color syncColor = OhtliColors.stormyTeal;

    if (_isSampleEditor) {
      syncStatusText = "Editor de muestra · no se guarda";
      syncIcon = Icons.science_outlined;
      syncColor = OhtliColors.accent;
    } else if (_photoUploadProgress.isNotEmpty) {
      final n = _photoUploadProgress.length;
      final pct = (_photoUploadProgress.values.fold<double>(0, (a, b) => a + b) / n * 100).round();
      syncStatusText = n == 1 ? "Subiendo foto… $pct %" : "Subiendo $n fotos… $pct %";
      syncIcon = Icons.cloud_upload_rounded;
      syncColor = OhtliColors.accent;
    } else if (_isSavingCloud) {
      syncStatusText = "Guardando…";
      syncIcon = Icons.sync_rounded;
      syncColor = OhtliColors.accent;
    } else if (_cloudSaveError != null) {
      syncStatusText = "Sin guardar · toca para reintentar";
      syncIcon = Icons.cloud_off_rounded;
      syncColor = OhtliColors.warning;
    } else if (_hasPendingCloudChanges) {
      syncStatusText = "Cambios sin subir…";
      syncIcon = Icons.cloud_upload_outlined;
    } else if (_lastSavedCloudTime != null) {
      syncStatusText = "Guardado";
      syncIcon = Icons.cloud_done_rounded;
    }

    final double screenW = MediaQuery.of(context).size.width;
    final bool wide = screenW >= 1180;
    final bool compactBar = screenW < 760;
    const double panelW = 300;
    final double panelInset = (wide && !_isLoadingContent) ? panelW + 28 : 0;

    final Widget canvas = _isLoadingContent
        ? const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
          )
        : _buildCanvas(isDark, screenW);

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
        backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
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
                child: Stack(
                  children: [
                    // Lienzo: se ve como el viaje publicado y se edita en el lugar.
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 84, 16 + panelInset, 140),
                        child: Center(
                          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: canvas),
                        ),
                      ),
                    ),
                    // Barra flotante: volver, guardado, deshacer, vista previa y publicar.
                    Positioned(
                      top: 12,
                      left: 16,
                      right: 16,
                      child: _buildTopBar(isDark, compact: compactBar, wide: wide, syncText: syncStatusText, syncIcon: syncIcon, syncColor: syncColor),
                    ),
                    // Bloques flotantes: datos del viaje, antes de publicar e índice.
                    if (wide && !_isLoadingContent)
                      Positioned(top: 76, right: 16, bottom: 0, width: panelW, child: _buildSidePanel(isDark)),
                  ],
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
                      const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      const SizedBox(height: 24),
                      Text(
                        "Subiendo imágenes y preparando tu aventura...",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
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

  // ---------------------------------------------------------------------------
  // Lienzo del editor
  // ---------------------------------------------------------------------------
  static const double _kSpineX = 21;
  static const double _kSpineIndent = 46;

  List<BoxShadow> _floatShadow(bool isDark) => [
        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.10), blurRadius: 22, offset: const Offset(0, 8)),
        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04), blurRadius: 3, offset: const Offset(0, 1)),
      ];

  BoxDecoration _floatBlock(bool isDark, {double radius = 20}) => BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder.withValues(alpha: 0.7)),
        boxShadow: _floatShadow(isDark),
      );

  static String _fmtDate(DateTime d) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickTravelDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _travelDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      helpText: 'Fecha del viaje',
    );
    if (picked == null || !mounted) return;
    setState(() => _travelDate = picked);
    _onDataChanged();
  }

  Widget _buildTopBar(bool isDark,
      {required bool compact, required bool wide, required String syncText, required IconData syncIcon, required Color syncColor}) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    Widget iconBtn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          color: OhtliColors.stormyTeal,
          disabledColor: isDark ? Colors.white24 : Colors.black26,
        );
    final bool published = _status == 'published';
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: _floatBlock(isDark, radius: 18),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            icon: Icon(Icons.arrow_back_rounded, color: fg),
            onPressed: () async {
              if (_isPublishing) return;
              final bool shouldPop = await _onWillPop();
              if (shouldPop && mounted) Navigator.pop(context);
            },
          ),
          Flexible(
            child: InkWell(
              onTap: _cloudSaveError != null && !_isSavingCloud ? _saveToCloudFirestore : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(syncIcon, color: syncColor, size: 17),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(syncText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: _cloudSaveError != null ? OhtliColors.warningText : fg.withValues(alpha: 0.65))),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildPresenceBar(isDark, compact: compact),
          const Spacer(),
          if (!compact) ...[
            iconBtn(Icons.undo_rounded, 'Deshacer (Ctrl+Z)', _undoStack.isEmpty ? null : _undo),
            iconBtn(Icons.redo_rounded, 'Rehacer (Ctrl+Shift+Z)', _redoStack.isEmpty ? null : _redo),
            iconBtn(Icons.visibility_outlined, 'Vista previa', _isLoadingContent ? null : _openPreview),
          ] else
            PopupMenuButton<String>(
              tooltip: 'Más acciones',
              icon: const Icon(Icons.more_horiz_rounded, color: OhtliColors.stormyTeal),
              onSelected: (v) {
                if (v == 'undo') _undo();
                if (v == 'redo') _redo();
                if (v == 'preview') _openPreview();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'undo', enabled: _undoStack.isNotEmpty, child: const ListTile(dense: true, leading: Icon(Icons.undo_rounded), title: Text('Deshacer'))),
                PopupMenuItem(value: 'redo', enabled: _redoStack.isNotEmpty, child: const ListTile(dense: true, leading: Icon(Icons.redo_rounded), title: Text('Rehacer'))),
                PopupMenuItem(value: 'preview', enabled: !_isLoadingContent, child: const ListTile(dense: true, leading: Icon(Icons.visibility_outlined), title: Text('Vista previa'))),
              ],
            ),
          if (!wide) iconBtn(Icons.tune_rounded, 'Datos, revisión e índice', _isLoadingContent ? null : () => _showPanelSheet(isDark)),
          const SizedBox(width: 4),
          if (published || _ownerUi)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.icon(
                onPressed: _handlePublishAction,
                style: FilledButton.styleFrom(
                  backgroundColor: published ? OhtliColors.accentFill : OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                  shape: const StadiumBorder(),
                ),
                icon: Icon(published ? Icons.history_edu_rounded : Icons.publish_rounded, size: 17),
                label: Text(published ? 'Fe de errata' : 'Publicar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  /// En pantallas angostas, los bloques del panel se abren en una hoja.
  void _showPanelSheet(bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _buildSidePanel(isDark, controller: scroll, onNavigate: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  /// Lo que falta antes de publicar: (texto, bloque al que lleva).
  List<(String, String?)> _publishIssues() {
    final out = <(String, String?)>[];
    if (_titleController.text.trim().isEmpty) out.add(('Ponle un título al viaje', null));
    if (_coverUrl.isEmpty) out.add(('Agrega una portada', null));
    if (_descriptionController.markdownText.trim().isEmpty) out.add(('Escribe una descripción', null));
    if (_sections.isEmpty) out.add(('Agrega al menos un bloque', null));
    if (_isNotes) {
      for (final s in _sections.whereType<PlaceSection>()) {
        if (s.title.trim().isEmpty) out.add(('Una novedad no tiene título', s.id));
      }
      return out;
    }
    bool seenPlace = false;
    for (int i = 0; i < _sections.length; i++) {
      final s = _sections[i];
      if (s is! PlaceSection || s.unplanned) continue;
      final name = s.title.trim().isEmpty ? 'Una parada' : '«${s.title.trim()}»';
      if (s.title.trim().isEmpty) out.add(('Una parada no tiene nombre', s.id));
      if ((s.arrivalTime ?? '').trim().isEmpty) out.add(('$name no tiene hora', s.id));
      if (seenPlace && transferBefore(_sections, i) == null) out.add(('Falta el traslado a $name', s.id));
      seenPlace = true;
    }
    return out;
  }

  Widget _buildSidePanel(bool isDark, {ScrollController? controller, VoidCallback? onNavigate}) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    Widget title(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: OhtliColors.stormyTeal),
              const SizedBox(width: 7),
              Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: sub)),
            ],
          ),
        );
    Widget row(IconData icon, String label, Widget trailing) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 16, color: sub),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.inter(fontSize: 13, color: sub)),
              const Spacer(),
              trailing,
            ],
          ),
        );

    final issues = _publishIssues();
    final places = _sections.whereType<PlaceSection>().length;

    final datos = Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _floatBlock(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title(Icons.tune_rounded, _isNotes ? 'DATOS DE LA VERSIÓN' : 'DATOS DEL VIAJE'),
          if (_isNotes)
            row(
              Icons.new_releases_outlined,
              'Versión',
              Text('v${_versionController.text.trim().isEmpty ? kAppVersion : _versionController.text.trim()}',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
            ),
          row(
            Icons.flag_outlined,
            'Estado',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: (_status == 'published' ? OhtliColors.stormyTeal : OhtliColors.accentFill).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_status == 'published' ? 'Publicado' : 'Borrador',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _status == 'published' ? OhtliColors.stormyTeal : OhtliColors.accent)),
            ),
          ),
          row(
            Icons.event_rounded,
            'Fecha',
            TextButton(
              onPressed: _pickTravelDate,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: OhtliColors.stormyTeal),
              child: Text(_travelDate == null ? 'Elegir' : _fmtDate(_travelDate!), style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ),
          if (_ownerUi)
            row(
              _visibility == 'public' ? Icons.public_rounded : Icons.lock_outline_rounded,
              'Visibilidad',
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: OhtliColors.stormyTeal,
                  selectedForegroundColor: Colors.white,
                  textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                segments: const [
                  ButtonSegment(value: 'private', label: Text('Privado')),
                  ButtonSegment(value: 'public', label: Text('Público')),
                ],
                selected: {_visibility},
                onSelectionChanged: (v) => _changeVisibility(v.first),
              ),
            ),
          if (_ownerUi && !_isNotes)
            row(
              Icons.group_outlined,
              'Coautores',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCoAuthorsAvatarStack(),
                  TextButton(
                    onPressed: _showCoAuthorsSelectionDialog,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: OhtliColors.stormyTeal),
                    child: Text(_coAuthorIds.isEmpty ? 'Invitar' : 'Gestionar', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final revision = Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _floatBlock(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title(Icons.fact_check_outlined, 'ANTES DE PUBLICAR'),
          if (issues.isEmpty)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: OhtliColors.stormyTeal),
                const SizedBox(width: 8),
                Text('Todo listo para publicar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              ],
            )
          else ...[
            for (final it in issues.take(6))
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: it.$2 == null
                    ? null
                    : () {
                        onNavigate?.call();
                        _scrollToBlock(it.$2!);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: OhtliColors.warning),
                      const SizedBox(width: 8),
                      Expanded(child: Text(it.$1, style: GoogleFonts.inter(fontSize: 12.5, color: fg))),
                      if (it.$2 != null) Icon(Icons.chevron_right_rounded, size: 16, color: sub),
                    ],
                  ),
                ),
              ),
            if (issues.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('y ${issues.length - 6} más', style: GoogleFonts.inter(fontSize: 12, color: sub)),
              ),
          ],
          if (places > 0 && !_isNotes) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (places >= 2)
                  ActionChip(
                    avatar: const Icon(Icons.add_road_rounded, size: 16, color: OhtliColors.stormyTeal),
                    label: Text('Completar traslados', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    onPressed: _fillAllTransfers,
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 16, color: OhtliColors.stormyTeal),
                  label: Text('Ajustar horarios', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: _recalculateTimes,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final indice = Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: _floatBlock(isDark),
      clipBehavior: Clip.antiAlias,
      child: _sections.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('El índice aparece al agregar bloques.', style: GoogleFonts.inter(fontSize: 12.5, color: sub)),
            )
          : _buildOutline(isDark, onNavigate: onNavigate),
    );

    return ListView(
      controller: controller,
      clipBehavior: Clip.none,
      padding: EdgeInsets.fromLTRB(controller != null ? 16 : 0, controller != null ? 20 : 0, controller != null ? 16 : 0, 28),
      children: [datos, if (!_isNotes) _buildRouteCard(isDark), revision, indice],
    );
  }

  // ---------------------------------------------------------------------------
  // Inicio y fin del recorrido
  // ---------------------------------------------------------------------------
  /// Inicio y fin: los del viaje o, si no los guarda, los que se deducen de las paradas.
  RouteEndpoints get _routeEnds => _isNotes
      ? const RouteEndpoints(null, null)
      : routeEndpointsOf(startPoint: _startPoint, endPoint: _endPoint, sections: _sections);

  /// Pide el lugar del inicio o el fin (buscador de lugar o dirección, o la ubicación actual)
  /// y lo guarda en el viaje.
  Future<void> _editEndpoint({required bool start}) async {
    final ends = _routeEnds;
    final current = start ? ends.start : ends.end;
    final res = await showDialog<_EndpointChoice>(
      context: context,
      builder: (_) => _EndpointDialog(
        start: start,
        current: current,
        startPoint: ends.start,
        roundTrip: ends.roundTrip || ends.end == null,
      ),
    );
    if (res == null || !mounted) return;
    final point = {'name': res.name, 'lat': res.lat, 'lng': res.lng};
    Map<String, dynamic>? newStart = start ? point : (ends.start?.toPoint());
    Map<String, dynamic>? newEnd = start ? (res.sameForEnd ? point : ends.end?.toPoint()) : (res.sameForEnd ? ends.start?.toPoint() : point);
    // Si no hay inicio, el fin "en el mismo lugar" también lo fija.
    newStart ??= newEnd;
    newEnd ??= newStart;
    final bool same = newStart != null &&
        newEnd != null &&
        metersBetween(newStart['lat'] as double, newStart['lng'] as double, newEnd['lat'] as double, newEnd['lng'] as double) < kSameEndpointMeters;

    // Las paradas de punto de partida / llegada de un plan hecho a mano se mueven con él.
    final changed = <String>[];
    final sections = List<TripSection>.of(_sections);
    void moveTagged(String tag, Map<String, dynamic>? to, String description) {
      if (to == null) return;
      final i = sections.indexWhere((x) => x is PlaceSection && x.id.endsWith('_$tag') && x.isGeneric);
      if (i < 0) return;
      final p = sections[i] as PlaceSection;
      final title = (to['name'] as String).trim();
      final keepDescription = p.description.trim().isNotEmpty &&
          !const ['Punto de partida', 'Punto de llegada', 'Regreso al punto de partida'].contains(p.description.trim());
      sections[i] = p.copyWith(
        title: title.isEmpty ? p.title : title,
        lat: to['lat'] as double,
        lng: to['lng'] as double,
        description: keepDescription ? null : description,
      );
      changed.add(p.id);
    }

    moveTagged('start', newStart, 'Punto de partida');
    moveTagged('end', newEnd, same ? 'Regreso al punto de partida' : 'Punto de llegada');

    _forceNewUndoStep = true;
    setState(() {
      _startPoint = newStart;
      _endPoint = newEnd;
      _routeShape = same ? 'anillo' : 'ambos';
      _sections = sections;
    });
    for (final id in changed) {
      _refreshBlockEditors(id);
    }
    _onDataChanged();
  }

  /// Ficha del inicio o el fin para la cabecera del editor: toca para cambiarlo.
  Widget _endpointFact(EndpointKind kind, RouteEndpoint? e, bool isDark, {required VoidCallback onTap}) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final String label = e == null ? 'Marcar ${kind == EndpointKind.end ? 'fin' : 'inicio'}' : '${endpointLabel(kind)}: ${e.name}';
    return Tooltip(
      message: e == null ? 'Elige dónde ${kind == EndpointKind.end ? 'termina' : 'empieza'} el recorrido' : 'Cambiar',
      child: Material(
        color: endpointColor(kind).withValues(alpha: isDark ? 0.16 : 0.07),
        shape: StadiumBorder(side: BorderSide(color: endpointColor(kind).withValues(alpha: 0.35))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RouteEndpointPin(kind: kind, height: 20),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: e == null ? endpointInk(kind, isDark) : fg)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_rounded, size: 13, color: endpointInk(kind, isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Fila del inicio o el fin en la línea de tiempo cuando no coincide con una parada.
  Widget _buildEndpointRow(RouteEndpoint e, {required bool start, required bool roundTrip, required bool isDark}) {
    final kind = start ? EndpointKind.start : EndpointKind.end;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final caption = start ? (roundTrip ? 'INICIO · IDA Y VUELTA' : 'INICIO') : (roundTrip ? 'FIN · REGRESO AL INICIO' : 'FIN');
    return Padding(
      padding: EdgeInsets.only(top: start ? 4 : 10, bottom: start ? 6 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kSpineIndent,
            child: Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.topLeft, child: _endpointSpinePin(kind))),
          ),
          Expanded(
            child: Material(
              color: endpointColor(kind).withValues(alpha: isDark ? 0.14 : 0.06),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _editEndpoint(start: start),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(caption,
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: endpointInk(kind, isDark))),
                            const SizedBox(height: 2),
                            Text(e.name, style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w700, color: fg)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editEndpoint(start: start),
                        style: TextButton.styleFrom(foregroundColor: endpointInk(kind, isDark), visualDensity: VisualDensity.compact),
                        child: Text('Cambiar', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pin del inicio o el fin sobre la línea de tiempo (se dibuja encima de la línea).
  Widget _endpointSpinePin(EndpointKind kind) {
    const double pinH = 30;
    return Padding(
      padding: const EdgeInsets.only(left: _kSpineX - pinH * RouteEndpointPin.aspect / 2),
      child: RouteEndpointPin(kind: kind, height: pinH),
    );
  }

  /// Tarjeta del panel: mini mapa del recorrido con el inicio y el fin, para cambiarlos.
  Widget _buildRouteCard(bool isDark) {
    final ends = _routeEnds;
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final places = [
      for (final p in _sections.whereType<PlaceSection>())
        if (p.lat != null && p.lng != null) p,
    ];
    final planned = _sections.whereType<PlaceSection>().where((x) => !x.unplanned).toList();
    Widget line(EndpointKind kind, RouteEndpoint? e, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 18, child: Center(child: RouteEndpointPin(kind: kind, height: 24))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(endpointLabel(kind), style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: endpointInk(kind, isDark))),
                      Text(e?.name ?? 'Sin marcar', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: e == null ? sub : fg)),
                    ],
                  ),
                ),
                Text(e == null ? 'Elegir' : 'Cambiar',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
              ],
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: _floatBlock(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.route_rounded, size: 16, color: OhtliColors.stormyTeal),
                const SizedBox(width: 7),
                Text('RECORRIDO', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: sub)),
              ],
            ),
          ),
          if (places.isNotEmpty || !ends.isEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 150,
                child: TripMiniMap(
                  isDark: isDark,
                  startPoint: ends.start?.toPoint(),
                  endPoint: ends.end?.toPoint(),
                  stops: [
                    for (final p in places)
                      MiniMapStop(
                        lat: p.lat!,
                        lng: p.lng!,
                        number: p.unplanned ? 0 : planned.indexOf(p) + 1,
                        unplanned: p.unplanned,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (ends.roundTrip)
            line(EndpointKind.both, ends.start, () => _editEndpoint(start: true))
          else ...[
            line(EndpointKind.start, ends.start, () => _editEndpoint(start: true)),
            line(EndpointKind.end, ends.end, () => _editEndpoint(start: false)),
          ],
        ],
      ),
    );
  }

  Widget _buildCanvas(bool isDark, double screenW) {
    final bool isDesktop = screenW >= 700;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final places = _sections.whereType<PlaceSection>().toList();
    final starts = places.map((p) => _hm(p.arrivalTime)).whereType<int>().toList();
    final ends = places.map((p) => _hm(p.departureTime) ?? _hm(p.arrivalTime)).whereType<int>().toList();
    String hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final double budget = places.fold<double>(0, (a, p) => a + p.cost) + _sections.whereType<TransferSection>().fold<double>(0, (a, t) => a + t.cost);
    final route = _routeEnds;
    final bool startRow = route.start != null && route.start!.sectionId == null;
    final bool endRow = route.end != null && route.end!.sectionId == null;

    Widget fact(IconData icon, String text, {VoidCallback? onTap}) => Material(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          shape: StadiumBorder(side: BorderSide(color: isDark ? Colors.white12 : OhtliColors.cardBorder)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: OhtliColors.stormyTeal),
                  const SizedBox(width: 6),
                  Text(text, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
                ],
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isPostTrip && !_isSampleEditor)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: OhtliColors.accent.withValues(alpha: isDark ? 0.18 : 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(Icons.history_edu_rounded, size: 18, color: OhtliColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Después del viaje: lo que cambies quedará en la fe de erratas con tu nombre.',
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: fg)),
                ),
              ],
            ),
          ),
        _buildCoverEditor(isDark, isDesktop: isDesktop),
        const SizedBox(height: 14),
        OhtliMarkdownEditor(
          controller: _descriptionController,
          focusNode: _getFocusNode('trip_description'),
          hintText: _isNotes ? 'Cuenta qué trae esta versión…' : 'Cuenta de qué va el viaje…',
          minLines: 2,
          maxLines: null,
          onChanged: _onDataChanged,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            fact(Icons.event_rounded, _travelDate == null ? 'Sin fecha' : _fmtDate(_travelDate!), onTap: _pickTravelDate),
            if (!_isNotes) ...[
              if (route.roundTrip)
                _endpointFact(EndpointKind.both, route.start, isDark, onTap: () => _editEndpoint(start: true))
              else ...[
                _endpointFact(EndpointKind.start, route.start, isDark, onTap: () => _editEndpoint(start: true)),
                _endpointFact(EndpointKind.end, route.end, isDark, onTap: () => _editEndpoint(start: false)),
              ],
            ],
            if (_isNotes) ...[
              fact(Icons.new_releases_outlined, 'v${_versionController.text.trim().isEmpty ? kAppVersion : _versionController.text.trim()}'),
              fact(Icons.auto_awesome_rounded, () {
                final n = places.where((p) => !p.unplanned).length;
                return '$n ${n == 1 ? 'novedad' : 'novedades'}';
              }()),
              if (places.any((p) => p.unplanned))
                fact(Icons.alt_route_rounded, '${places.where((p) => p.unplanned).length} en camino'),
            ] else
              fact(Icons.place_rounded, '${places.length} ${places.length == 1 ? 'parada' : 'paradas'}'),
            if (starts.isNotEmpty && !_isNotes) fact(Icons.schedule_rounded, '${hhmm(starts.reduce(math.min))}–${hhmm(ends.reduce(math.max))}'),
            if (budget > 0 && !_isNotes) fact(Icons.account_balance_wallet_rounded, '\$${budget.toStringAsFixed(0)} MXN'),
          ],
        ),
        const SizedBox(height: 26),
        if (_sections.isEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showInsertMenu(at: 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Column(
                children: [
                  const Icon(Icons.add_circle_outline_rounded, size: 34, color: OhtliColors.stormyTeal),
                  const SizedBox(height: 10),
                  Text(_isNotes ? 'Agrega la primera novedad o un texto' : 'Agrega la primera parada o un texto', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 4),
                  Text('También puedes escribir «/» en un texto vacío para elegir el tipo de bloque.',
                      textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12.5, color: sub)),
                ],
              ),
            ),
          )
        else
          Stack(
            children: [
              Positioned(
                left: _kSpineX - 1,
                top: 14,
                bottom: 24,
                child: CustomPaint(size: const Size(2, double.infinity), painter: _EditorSpinePainter(isDark ? Colors.white24 : OhtliColors.onyx.withValues(alpha: 0.22))),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              if (startRow) _buildEndpointRow(route.start!, start: true, roundTrip: route.roundTrip, isDark: isDark),
              ReorderableListView.builder(
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
                  final bool needsTransfer = !_isNotes &&
                      section is PlaceSection &&
                      !section.unplanned &&
                      _sections.take(index).any((s) => s is PlaceSection) &&
                      transferBefore(_sections, index) == null;
                  return KeyedSubtree(
                    key: ValueKey('${section.id}_${_editorGeneration}_${_blockGen[section.id] ?? 0}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InsertLine(spineX: _kSpineX, isDark: isDark, onTap: () => _showInsertMenu(at: index)),
                        if (needsTransfer)
                          Padding(padding: const EdgeInsets.only(left: _kSpineIndent), child: _buildMissingTransferConnector(section.id)),
                        _buildTimelineRow(index, section, isDark),
                      ],
                    ),
                  );
                },
              ),
                ],
              ),
            ],
          ),
        if (_sections.isNotEmpty) ...[
          _InsertLine(spineX: _kSpineX, isDark: isDark, onTap: () => _showInsertMenu(at: _sections.length)),
          if (endRow) _buildEndpointRow(route.end!, start: false, roundTrip: route.roundTrip, isDark: isDark),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: _kSpineIndent),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showInsertMenu(at: _sections.length, askWhere: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OhtliColors.stormyTeal,
                  side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Agregar bloque', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static int? _hm(String? t) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t ?? '');
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  /// Portada grande con el título encima, como en el viaje publicado.
  Widget _buildCoverEditor(bool isDark, {required bool isDesktop}) {
    final bool has = _coverUrl.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: isDesktop ? 300 : 230,
        decoration: BoxDecoration(
          color: has ? Colors.black : OhtliColors.stormyTeal,
          image: has ? DecorationImage(image: _getImageProvider(_coverUrl), fit: BoxFit.cover) : null,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.45, 1],
                    colors: [Colors.black.withValues(alpha: has ? 0.25 : 0), Colors.transparent, Colors.black.withValues(alpha: has ? 0.75 : 0.2)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Row(
                children: [
                  if (has)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton.filledTonal(
                        tooltip: 'Quitar portada',
                        onPressed: () {
                          setState(() => _coverUrl = '');
                          _onDataChanged();
                        },
                        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.9), foregroundColor: const Color(0xFF1F2A2A)),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _uploadCoverImage,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      foregroundColor: const Color(0xFF1F2A2A),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.photo_camera_back_rounded, size: 17),
                    label: Text(has ? 'Cambiar portada' : 'Agregar portada', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 16,
              child: TextFormField(
                controller: _titleController,
                maxLines: 2,
                minLines: 1,
                onChanged: (_) => _onDataChanged(),
                cursorColor: Colors.white,
                style: GoogleFonts.outfit(fontSize: isDesktop ? 36 : 27, fontWeight: FontWeight.bold, height: 1.1, color: Colors.white),
                decoration: InputDecoration(
                  hintText: _isNotes ? 'Título de la versión' : 'Título de tu viaje',
                  hintStyle: GoogleFonts.outfit(fontSize: isDesktop ? 36 : 27, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.55)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fila de la línea de tiempo: marcador sobre la línea punteada y el bloque.
  Widget _buildTimelineRow(int index, TripSection section, bool isDark) {
    Widget marker;
    if (section is PlaceSection && section.unplanned) {
      marker = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: OhtliColors.accentFill,
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
        ),
        child: const Icon(Icons.alt_route_rounded, size: 13, color: Colors.white),
      );
    } else if (section is PlaceSection && _isNotes) {
      marker = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: releaseTagColor(section.changeTag),
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
        ),
        child: Icon(releaseTagIcon(section.changeTag), size: 12, color: Colors.white),
      );
    } else if (section is PlaceSection && endpointKindOf(_routeEnds.labelFor(section.id)) != null) {
      // La parada donde empieza o termina el recorrido lleva el pin de Ohtli.
      marker = SizedBox(
        width: 26,
        height: 30,
        child: Center(child: RouteEndpointPin(kind: endpointKindOf(_routeEnds.labelFor(section.id))!, height: 30)),
      );
    } else if (section is PlaceSection) {
      int n = 0;
      for (int i = 0; i <= index; i++) {
        final x = _sections[i];
        if (x is PlaceSection && !x.unplanned) n++;
      }
      final lane = _branchAt(index);
      marker = Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: lane != null ? _branchColorOf(lane) : OhtliColors.stormyTeal,
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
        ),
        child: Text('$n', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
      );
    } else if (section is TransferSection) {
      final lane = _branchAt(index);
      final Color c = lane != null ? _branchColorOf(lane) : OhtliColors.stormyTeal;
      marker = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: c.withValues(alpha: lane != null ? 0.8 : 0.5)),
        ),
        child: Icon(transferModeOf(section.mode).icon, size: 14, color: lane != null ? branchInk(c, isDark) : OhtliColors.stormyTeal),
      );
    } else if (section is ProposalSection) {
      marker = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: OhtliColors.accentFill,
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
        ),
        child: const Icon(Icons.how_to_vote_rounded, size: 13, color: Colors.white),
      );
    } else if (section is SplitSection) {
      marker = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: OhtliColors.accentFill,
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
        ),
        child: const Icon(Icons.call_split_rounded, size: 13, color: Colors.white),
      );
    } else {
      marker = Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A3A3E) : OhtliColors.cantera,
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 2),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _kSpineIndent,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Align(alignment: const Alignment(-1, -1), child: Padding(padding: const EdgeInsets.only(left: _kSpineX - 13), child: marker)),
          ),
        ),
        Expanded(child: _buildBlockCard(index, section, isDark)),
      ],
    );
  }

  /// Portada de la parada: la elegida, o una de referencia (tenue) para invitar a elegirla.
  Widget _buildPlaceCoverStrip(PlaceSection p, bool isDark) {
    final bool has = (p.coverUrl ?? '').isNotEmpty;
    final seed = p.id.codeUnits.fold<int>(0, (a, c) => a + c);
    final String url = has ? p.coverUrl! : CdmxPhotos.forCategory(p.title, seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 116,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: has ? 1 : 0.45,
              child: Image(
                image: _getImageProvider(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(color: isDark ? const Color(0xFF26343A) : OhtliColors.cantera.withValues(alpha: 0.4)),
              ),
            ),
            if (!has)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                  child: Text('Foto de referencia', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  if (has)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton.filledTonal(
                        tooltip: 'Quitar portada',
                        onPressed: () => _replacePlace(p.id, (x) => x.copyWith(clearCoverUrl: true)),
                        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.9), foregroundColor: const Color(0xFF1F2A2A)),
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => _pickPlaceCover(p.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      foregroundColor: const Color(0xFF1F2A2A),
                      visualDensity: VisualDensity.compact,
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.wallpaper_rounded, size: 16),
                    label: Text(has ? 'Cambiar portada' : 'Elegir portada', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickPlaceCover(String sectionId) {
    pickFile(accept: 'image/*').then((picked) {
      if (picked == null || picked.bytes.isEmpty || !mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => OhtliImageCropperDialog(
          imageBytes: picked.bytes,
          isCircle: false,
          aspectRatio: 16 / 9,
          onCropped: (String dataUrl) {
            _replacePlace(sectionId, (p) => p.copyWith(coverUrl: dataUrl));
            _uploadPhotoNow(dataUrl, '${sectionId}_cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
          },
        ),
      );
    });
  }

  Future<double?> _askAmount(String title, {double? initial, String? helper}) async {
    final ctrl = TextEditingController(text: initial != null && initial > 0 ? initial.toStringAsFixed(0) : '');
    final r = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                decoration: const InputDecoration(prefixText: '\$ ', hintText: '0'),
                onSubmitted: (_) => Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? -1),
              ),
              if (helper != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(helper, style: GoogleFonts.inter(fontSize: 12))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal),
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? -1),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _editPlaceCost(PlaceSection p, TextEditingController costController) async {
    final v = await _askAmount('Costo estimado', initial: p.cost, helper: 'Cuánto calculan gastar en «${p.title}» (${p.currency}).');
    if (v == null || !mounted) return;
    final value = v < 0 ? 0.0 : v;
    costController.text = value > 0 ? value.toString() : '';
    _updatePlaceBlock(_idx(p.id), cost: value);
  }

  Future<void> _editPlaceRealCost(PlaceSection p) async {
    final v = await _askAmount('Gasto real', initial: p.realCost, helper: 'Lo que realmente gastaron. Déjalo vacío para quitarlo.');
    if (v == null || !mounted) return;
    _replacePlace(p.id, (x) => v <= 0 ? x.copyWith(clearRealCost: true) : x.copyWith(realCost: v));
  }

  Future<void> _editPlaceRealTimes(PlaceSection p) async {
    final arrived = await showTimePicker(context: context, initialTime: _parseTime(p.arrivedAt) ?? const TimeOfDay(hour: 10, minute: 0), helpText: 'Llegaron a las');
    if (arrived == null || !mounted) return;
    final left = await showTimePicker(context: context, initialTime: _parseTime(p.leftAt) ?? arrived, helpText: 'Se fueron a las (cancela si siguen ahí)');
    if (!mounted) return;
    _replacePlace(
      p.id,
      (x) => left == null ? x.copyWith(arrivedAt: _formatTime(arrived), clearLeftAt: true) : x.copyWith(arrivedAt: _formatTime(arrived), leftAt: _formatTime(left)),
    );
  }

  /// Menú de bloques: insertar en [at] o cambiar el tipo del texto vacío [replaceId] ("/").
  /// Con [askWhere], una parada nueva pregunta antes en qué lugar del recorrido va.
  Future<void> _showInsertMenu({int? at, String? replaceId, bool askWhere = false}) async {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final options = <(String, IconData, String, String)>[
      if (_isNotes) ...[
        ('place', Icons.new_releases_rounded, 'Novedad', 'Algo nuevo, una mejora o un arreglo'),
        ('detour', Icons.alt_route_rounded, 'Próximamente', 'Un desvío: lo que viene en camino'),
      ] else ...[
        ('place', Icons.place_rounded, 'Parada', 'Un lugar del recorrido'),
        ('transfer', Icons.route_rounded, 'Traslado', 'Cómo van de un lugar a otro'),
        ('proposal', Icons.how_to_vote_rounded, 'Propuesta de lugares', 'El grupo propone lugares y vota cuál se queda'),
        ('split', Icons.call_split_rounded, 'Separar al grupo', 'Cada quien por su lado; se reencuentran si quieren'),
      ],
      ('text', Icons.notes_rounded, 'Texto', _isNotes ? 'Cuenta algo de la versión' : 'Cuenta algo del viaje'),
      ('text_image', Icons.image_rounded, 'Imagen', 'Una foto con texto al lado'),
      ('table', Icons.table_chart_rounded, 'Tabla', 'Cuentas, horarios o listas'),
      ('notes', Icons.sticky_note_2_rounded, 'Nota', 'Un aviso destacado'),
    ];
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(replaceId != null ? 'Convertir en…' : 'Agregar bloque',
                          style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: fg)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.6,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final o in options)
                      Material(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F6F5),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(ctx, o.$1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(o.$2, color: OhtliColors.stormyTeal, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(o.$3, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
                                      Text(o.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, color: sub)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (replaceId != null) {
      final i = _sections.indexWhere((s) => s.id == replaceId);
      if (i < 0) return;
      if (type == null || type == 'text') {
        // Se queda como texto: solo se borra la "/".
        final c = _blockControllers[replaceId];
        if (c is MarkdownRichTextController) c.text = '';
        _updateTextBlock(i, markdown: '');
        return;
      }
      _blockControllers.remove(replaceId)?.dispose();
      _addBlock(type, replaceId: replaceId);
      return;
    }
    if (type == null) return;
    if (askWhere && (type == 'place' || type == 'detour') && _sections.any((s) => s is PlaceSection)) {
      final where = await _askPlacePosition(isNotes: _isNotes);
      if (where == null || !mounted) return;
      _addBlock(type, at: where);
      return;
    }
    _addBlock(type, at: at);
  }

  /// Pregunta en qué punto del recorrido va una parada nueva. Devuelve el índice donde
  /// insertarla (o null si se cancela).
  Future<int?> _askPlacePosition({bool isNotes = false}) async {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final places = <(int, PlaceSection)>[
      for (var i = 0; i < _sections.length; i++)
        if (_sections[i] is PlaceSection) (i, _sections[i] as PlaceSection),
    ];
    String name(PlaceSection p, int n) => p.title.trim().isNotEmpty ? p.title.trim() : '${isNotes ? 'Novedad' : 'Parada'} $n';
    // (índice de inserción, título, detalle, número que llevará la parada nueva)
    final options = <(int, String, String, int)>[
      (places.first.$1, 'Al inicio', 'Antes de ${name(places.first.$2, 1)}', 1),
      for (var k = 0; k < places.length - 1; k++)
        (places[k].$1 + 1, 'Después de ${name(places[k].$2, k + 1)}', 'Antes de ${name(places[k + 1].$2, k + 2)}', k + 2),
      (_sections.length, 'Al final', 'Después de ${name(places.last.$2, places.length)}', places.length + 1),
    ];
    int selected = options.length - 1;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(isNotes ? '¿Dónde va la novedad?' : '¿Dónde va la parada?',
                            style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: fg)),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  Text('Elige en qué punto del recorrido la agregamos.', style: GoogleFonts.inter(fontSize: 13, color: sub)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final o = options[i];
                        final on = i == selected;
                        return Material(
                          color: on
                              ? OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.28 : 0.10)
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F6F5)),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setLocal(() => selected = i),
                            onDoubleTap: () => Navigator.pop(ctx, o.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: on ? OhtliColors.stormyTeal : Colors.transparent, width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: on ? OhtliColors.stormyTeal : OhtliColors.stormyTeal.withValues(alpha: 0.12),
                                    ),
                                    child: Text('${o.$4}',
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: on ? Colors.white : OhtliColors.stormyTeal)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(o.$2,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
                                        Text(o.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, color: sub)),
                                      ],
                                    ),
                                  ),
                                  if (on) const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: GoogleFonts.inter(color: sub))),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, options[selected].$1),
                        icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                        label: Text('Agregar aquí', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
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

    if (section is TransferSection) {
      typeLabel = "Traslado";
      typeIcon = transferModeOf(section.mode).icon;
      blockContent = _buildTransferEditor(section, isDark);
    } else if (section is ProposalSection) {
      typeLabel = "Propuesta de lugares";
      typeIcon = Icons.how_to_vote_rounded;
      blockContent = _buildProposalEditor(section, isDark);
    } else if (section is SplitSection) {
      typeLabel = "Separar al grupo";
      typeIcon = Icons.call_split_rounded;
      blockContent = _buildSplitEditor(section, isDark);
    } else if (section is UnknownSection) {
      typeLabel = "Bloque no compatible";
      typeIcon = Icons.help_outline_rounded;
      blockContent = Text(
        'Este bloque se creó con una versión más nueva de Ohtli. Se conserva sin cambios.',
        style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.6)),
      );
    } else if (section is PlaceSection) {
      typeLabel = _isNotes ? (section.unplanned ? "Próximamente" : "Novedad") : (section.unplanned ? "Desvío" : "Parada");
      typeIcon = section.unplanned ? Icons.alt_route_rounded : (_isNotes ? Icons.new_releases_rounded : Icons.location_on_rounded);
      
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

      // Parada compacta: portada arriba; fotos reales y nombre juntos; detalles en chips.
      final nextEmptySlot = slots.firstWhere((s) => (s['url'] as String).isEmpty, orElse: () => {});
      final VoidCallback? nextEmptySlotOnTap = nextEmptySlot.isNotEmpty ? nextEmptySlot['onTap'] as VoidCallback? : null;
      // Calificación, gasto real, hora real y desvío son de después del viaje.
      final bool post = !_isNotes && (_isPostTrip || section.rating > 0 || section.realCost != null || section.arrivedAt != null || section.unplanned);
      final Color fgP = isDark ? Colors.white : const Color(0xFF1F2A2A);
      final Color subP = isDark ? Colors.white60 : OhtliColors.subtleText;
      // Después de separarse, cada parada dice quién va (o si es el reencuentro).
      final SplitSection? splitHere = splitBefore(_sections, index);

      final Widget photos = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          uploadedSlots.isNotEmpty
              ? _buildPhotoStack(uploadedSlots, isDark)
              : SizedBox(
                  width: 104,
                  height: 132,
                  child: _buildPlacePhotoSlot(
                    blockIndex: index,
                    photoUrl: '',
                    label: 'Foto',
                    onTap: () => _uploadImageForBlock(_idx(section.id), 'place_main'),
                    onDelete: () => _updatePlaceBlock(_idx(section.id), mainPhoto: ''),
                    isDark: isDark,
                  ),
                ),
          if (nextEmptySlotOnTap != null && uploadedSlots.isNotEmpty)
            TextButton.icon(
              onPressed: nextEmptySlotOnTap,
              style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal, visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
              label: Text('Foto', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      );

      final Widget nameAndText = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: titleController,
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 19, color: fgP),
            decoration: InputDecoration(
              hintText: _isNotes ? (section.unplanned ? '¿Qué viene en camino?' : '¿Qué hay de nuevo?') : 'Nombre del lugar',
              hintStyle: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: subP.withValues(alpha: 0.6)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
            ),
          ),
          if (post)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (starIndex) {
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '${starIndex + 1} ${starIndex == 0 ? 'estrella' : 'estrellas'}',
                  icon: Icon(
                    starIndex < section.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: starIndex < section.rating ? OhtliColors.rating : subP,
                    size: 20,
                  ),
                  onPressed: () => _updatePlaceBlock(_idx(section.id), rating: starIndex + 1),
                );
              }),
            ),
          const SizedBox(height: 4),
          OhtliMarkdownEditor(
            controller: controller,
            focusNode: focusNode,
            hintText: _isNotes ? 'Qué cambia y por qué importa, en pocas palabras…' : 'Qué hay aquí, qué pedir, qué no perderse…',
            minLines: 2,
            maxLines: null,
          ),
        ],
      );

      Widget pill(IconData icon, String text, VoidCallback onTap, {Color? color, bool strong = false}) => Material(
            color: (color ?? OhtliColors.stormyTeal).withValues(alpha: strong ? 0.14 : (isDark ? 0.10 : 0.06)),
            shape: StadiumBorder(side: BorderSide(color: (color ?? OhtliColors.stormyTeal).withValues(alpha: 0.25))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: color ?? OhtliColors.stormyTeal),
                    const SizedBox(width: 6),
                    Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white : (color ?? OhtliColors.stormyTeal))),
                  ],
                ),
              ),
            ),
          );

      final Widget chips = _isNotes
          ? (section.unplanned
              ? Text('Se verá como un desvío del recorrido: algo que todavía no llega.',
                  style: GoogleFonts.inter(fontSize: 12, color: subP))
              : _buildReleaseTagPicker(section, isDark))
          : Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (endpointKindOf(_routeEnds.labelFor(section.id)) case final EndpointKind k)
            Tooltip(
              message: k == EndpointKind.end ? 'Aquí termina el recorrido' : 'Aquí empieza el recorrido',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _editEndpoint(start: k != EndpointKind.end),
                child: EndpointTag(kind: k, isDark: isDark),
              ),
            ),
          _buildTimeChip(section, arrival: true, isDark: isDark),
          _buildTimeChip(section, arrival: false, isDark: isDark),
          pill(
            Icons.payments_rounded,
            section.cost > 0 ? '\$${section.cost.toStringAsFixed(0)} ${section.currency}' : 'Costo',
            () => _editPlaceCost(section, costController),
            color: const Color(0xFFB45309),
          ),
          _buildLocationChip(section, isDark),
          if (post) ...[
            pill(
              Icons.receipt_long_rounded,
              section.realCost != null ? 'Gasto real \$${section.realCost!.toStringAsFixed(0)}' : 'Gasto real',
              () => _editPlaceRealCost(section),
            ),
            pill(
              Icons.schedule_rounded,
              section.arrivedAt != null ? 'Real ${section.arrivedAt}${section.leftAt != null ? '–${section.leftAt}' : ''}' : 'Hora real',
              () => _editPlaceRealTimes(section),
            ),
            FilterChip(
              selected: section.unplanned,
              showCheckmark: false,
              avatar: Icon(Icons.alt_route_rounded, size: 16, color: section.unplanned ? Colors.white : OhtliColors.accent),
              label: Text('Desvío', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: section.unplanned ? Colors.white : OhtliColors.accent)),
              selectedColor: OhtliColors.accentFill,
              side: BorderSide(color: OhtliColors.accent.withValues(alpha: 0.4)),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _replacePlace(section.id, (p) => p.copyWith(unplanned: !p.unplanned)),
            ),
          ],
        ],
      );

      blockContent = LayoutBuilder(
        builder: (context, constraints) {
          final bool roomy = constraints.maxWidth >= 430;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isNotes) ...[
                _buildPlaceCoverStrip(section, isDark),
                const SizedBox(height: 12),
              ],
              if (roomy)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [photos, const SizedBox(width: 14), Expanded(child: nameAndText)],
                )
              else ...[
                Align(alignment: Alignment.centerLeft, child: photos),
                const SizedBox(height: 10),
                nameAndText,
              ],
              const SizedBox(height: 10),
              chips,
              if (!_isNotes && splitHere != null) _buildWhoGoes(section.id, splitHere, section.branchId, isDark),
            ],
          );
        },
      );
    } else if (section is TextSection) {
      final alertData = parseAlertMarkdown(section.markdownText);
      final tableData = parseTableMarkdown(section.markdownText);

      if (alertData != null) {
        typeLabel = "Nota";
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
        typeLabel = "Texto";
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
          hintText: 'Escribe aquí… o «/» para elegir otro tipo de bloque',
          minLines: 4,
          maxLines: null,
        );
      }
    } else if (section is TextImageSection) {
      typeLabel = "Imagen y texto";
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

    final Color fgLabel = isDark ? Colors.white60 : OhtliColors.subtleText;
    // Rama del bloque cuando el grupo va separado, o el punto de reencuentro.
    final TripBranch? lane = _branchAt(index);
    final Widget? laneTag = lane != null
        ? BranchTag(label: _branchLabel(lane), color: _branchColorOf(lane), isDark: isDark)
        : (_isMeetupAt(index) ? BranchTag(label: 'Reencuentro', icon: Icons.call_merge_rounded, color: OhtliColors.stormyTeal, isDark: isDark) : null);
    // Quién más está escribiendo en este bloque (presencia).
    final editingHere = [for (final p in _othersHere) if (p.blockId == section.id) p];
    final Color? editingColor = editingHere.isEmpty ? null : _presenceColor(editingHere.first.uid);
    // Si el foco entra a cualquier campo del bloque, se avisa a los demás.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has) {
          _setFocusedBlock(section.id);
        } else if (_focusedBlockId == section.id) {
          _setFocusedBlock(null);
        }
      },
      child: Container(
      key: _blockKeys.putIfAbsent(section.id, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: editingColor != null
            ? Border.all(color: editingColor.withValues(alpha: 0.75), width: 1.5)
            : Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado discreto: asa para arrastrar, tipo y menú del bloque.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: 'Arrastra para mover',
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.drag_indicator_rounded, size: 18, color: fgLabel.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(typeIcon, size: 15, color: OhtliColors.stormyTeal),
                const SizedBox(width: 6),
                Text(typeLabel, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: fgLabel)),
                if (laneTag != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: laneTag),
                ],
                if (editingHere.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(child: _buildEditingBadge(editingHere, isDark)),
                ],
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Opciones del bloque',
                  icon: Icon(Icons.more_horiz_rounded, size: 20, color: fgLabel),
                  onSelected: (v) {
                    // Por id: en vivo, otro pudo mover o agregar bloques con el menú abierto.
                    final i = _idx(section.id);
                    if (i < 0) return;
                    switch (v) {
                      case 'up':
                        _moveUp(i);
                      case 'down':
                        _moveDown(i);
                      case 'dup':
                        _duplicateBlock(i);
                      case 'above':
                        _showInsertMenu(at: i);
                      case 'below':
                        _showInsertMenu(at: i + 1);
                      case 'delete':
                        _deleteBlock(i);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'above', child: ListTile(dense: true, leading: const Icon(Icons.vertical_align_top_rounded), title: Text('Agregar arriba', style: GoogleFonts.inter()))),
                    PopupMenuItem(value: 'below', child: ListTile(dense: true, leading: const Icon(Icons.vertical_align_bottom_rounded), title: Text('Agregar abajo', style: GoogleFonts.inter()))),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'up', enabled: index > 0, child: ListTile(dense: true, leading: const Icon(Icons.arrow_upward_rounded), title: Text('Subir', style: GoogleFonts.inter()))),
                    PopupMenuItem(value: 'down', enabled: index < _sections.length - 1, child: ListTile(dense: true, leading: const Icon(Icons.arrow_downward_rounded), title: Text('Bajar', style: GoogleFonts.inter()))),
                    PopupMenuItem(value: 'dup', child: ListTile(dense: true, leading: const Icon(Icons.copy_all_rounded), title: Text('Duplicar', style: GoogleFonts.inter()))),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.delete_outline_rounded, color: OhtliColors.warning),
                        title: Text('Eliminar', style: GoogleFonts.inter(color: OhtliColors.warningText)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_conflicts.containsKey(section.id)) _buildConflictBanner(section.id, isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: blockContent,
          ),
        ],
      ),
      ),
    );
  }

  /// Color estable para cada persona en el editor.
  static Color _presenceColor(String uid) {
    const palette = [Color(0xFFD9480F), Color(0xFF2B8A3E), Color(0xFF5F3DC4), Color(0xFFC2255C), Color(0xFF1971C2), Color(0xFFE67700)];
    return palette[uid.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff) % palette.length];
  }

  Widget _presenceAvatar(EditorPresence p, {double radius = 13, bool ring = false, bool isDark = false}) {
    final color = _presenceColor(p.uid);
    final initial = p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring ? (isDark ? const Color(0xFF1E1E22) : Colors.white) : Colors.transparent),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: color,
        foregroundImage: p.photo != null ? NetworkImage(p.photo!) : null,
        child: Text(initial, style: GoogleFonts.inter(fontSize: radius * 0.85, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }

  /// "Ana está editando" en el encabezado del bloque.
  Widget _buildEditingBadge(List<EditorPresence> people, bool isDark) {
    final color = _presenceColor(people.first.uid);
    final names = people.map((p) => p.firstName).toList();
    final text = names.length == 1 ? '${names.first} está editando' : '${names.join(' y ')} están editando';
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 2, 9, 2),
        decoration: BoxDecoration(color: color.withValues(alpha: isDark ? 0.25 : 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _presenceAvatar(people.first, radius: 8),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white : color)),
            ),
          ],
        ),
      ),
    );
  }

  /// Los dos cambiaron el mismo bloque: se quedó la versión de aquí; se puede tomar la otra.
  Widget _buildConflictBanner(String id, bool isDark) {
    final theirs = _conflicts[id];
    final who = (_conflictBy[id] ?? '').trim();
    final name = who.isEmpty ? 'Otra persona' : who;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final String text = theirs == null
        ? '$name borró este bloque mientras lo editabas. Se quedó porque tenía cambios tuyos.'
        : '$name también cambió este bloque al mismo tiempo. Se quedó tu versión.';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: OhtliColors.accent.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OhtliColors.accent.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_split_rounded, size: 16, color: OhtliColors.accent),
              const SizedBox(width: 8),
              Flexible(child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: fg))),
            ],
          ),
          TextButton(
            onPressed: () => _resolveConflict(id, useTheirs: true),
            child: Text(theirs == null ? 'Borrarlo' : 'Usar la suya', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => _resolveConflict(id, useTheirs: false),
            child: Text(theirs == null ? 'Mantenerlo' : 'Dejar la mía', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Arriba del editor: quién más lo tiene abierto.
  Widget _buildPresenceBar(bool isDark, {required bool compact}) {
    final others = _othersHere;
    if (others.isEmpty) return const SizedBox.shrink();
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final names = others.map((p) => p.firstName).toList();
    final String label = names.length == 1
        ? '${names.first} está aquí'
        : names.length == 2
            ? '${names[0]} y ${names[1]} están aquí'
            : '${names[0]} y ${names.length - 1} más están aquí';
    String where(EditorPresence p) {
      final i = p.blockId == null ? -1 : _idx(p.blockId!);
      if (i < 0) return '${p.name}: viendo el viaje';
      final (title, _) = _blockOutlineInfo(_sections[i]);
      return '${p.name}: editando «$title»';
    }

    final shown = others.take(3).toList();
    return Tooltip(
      message: others.map(where).join('\n'),
      child: Semantics(
        label: label,
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24.0 + (shown.length - 1) * 16,
                height: 30,
                child: Stack(
                  children: [
                    for (int i = 0; i < shown.length; i++)
                      Positioned(left: i * 16.0, top: 1, child: _presenceAvatar(shown[i], radius: 12.5, ring: true, isDark: isDark)),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75))),
              ],
            ],
          ),
        ),
      ),
    );
  }



  /// Tipo de novedad: Nuevo, Mejora o Corrección.
  Widget _buildReleaseTagPicker(PlaceSection section, bool isDark) {
    final String current = section.changeTag ?? 'nuevo';
    // Sin elegir, el color se aclara en modo oscuro para que se lea.
    Color soft(String tag) => isDark ? Color.lerp(releaseTagColor(tag), Colors.white, 0.45)! : releaseTagColor(tag);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in kReleaseTags.entries)
          ChoiceChip(
            selected: current == e.key,
            showCheckmark: false,
            avatar: Icon(releaseTagIcon(e.key), size: 15, color: current == e.key ? Colors.white : soft(e.key)),
            label: Text(e.value,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: current == e.key ? Colors.white : soft(e.key))),
            selectedColor: releaseTagColor(e.key),
            backgroundColor: releaseTagColor(e.key).withValues(alpha: isDark ? 0.14 : 0.07),
            side: BorderSide(color: releaseTagColor(e.key).withValues(alpha: 0.35)),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => _replacePlace(section.id, (p) => p.copyWith(changeTag: e.key)),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Propuestas de lugares: el grupo propone y vota cuál se queda
  // ---------------------------------------------------------------------------
  /// Cambia un bloque por id con los mismos caminos que el resto del editor. No hace nada
  /// mientras se aplican cambios ajenos, si el bloque ya no está o si no cambió nada.
  void _replaceSection<T extends TripSection>(String id, T Function(T) change, {bool structural = true}) {
    if (_applyingRemote) return;
    final i = _idx(id);
    if (i < 0 || _sections[i] is! T) return;
    final next = change(_sections[i] as T);
    if (deepEquals(next.toMap(), _sections[i].toMap())) return;
    setState(() {
      _sections[i] = next;
      if (structural) _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  Future<void> _loadOwnerName() async {
    final owner = widget.trip.userId;
    if (_isSampleEditor || owner.isEmpty || owner == _myUid) return;
    try {
      final d = await FirebaseFirestore.instance.collection('public_profiles').doc(owner).get();
      final n = (d.data()?['displayName'] ?? '').toString().trim();
      if (n.isNotEmpty && mounted) setState(() => _ownerName = n);
    } catch (e) {
      debugPrint('Nombre de quien organiza: $e');
    }
  }

  /// Quienes editan el viaje (votan y se reparten en las ramas): el dueño y los coautores.
  List<(String, String)> get _editorPeople {
    final owner = widget.trip.userId;
    String ownerName() {
      if (_isSampleEditor) return (TripSample.author['displayName'] ?? 'Ana').toString();
      if (owner == _myUid) return _myName;
      if (_ownerName != null) return _ownerName!;
      for (final p in _presence) {
        if (p.uid == owner) return p.name;
      }
      return 'Quien organiza';
    }

    return [
      (owner, ownerName()),
      for (int i = 0; i < _coAuthorIds.length; i++)
        if (_coAuthorIds[i] != owner)
          (
            _coAuthorIds[i],
            _coAuthorIds[i] == _myUid
                ? _myName
                : (i < _coAuthorNames.length && _coAuthorNames[i].trim().isNotEmpty ? _coAuthorNames[i].trim() : 'Coautor'),
          ),
    ];
  }

  /// Quien vota y se reparte desde este editor (en la muestra, «Tú», el coautor de muestra).
  String get _voterUid => _isSampleEditor ? kSampleMyUid : (_myUid.isNotEmpty ? _myUid : 'anonimo');
  String get _voterName => _isSampleEditor ? kSampleMyName : _myName;

  void _watchVotes(String proposalId) {
    if (_isSampleEditor || _myUid.isEmpty || _voteSubs.containsKey(proposalId)) return;
    _voteSubs[proposalId] = ProposalVotes.watch(widget.trip.userId, widget.trip.id, proposalId).listen(
      (v) {
        if (mounted) setState(() => _votes[proposalId] = v);
      },
      onError: (Object e) => debugPrint('Votos de $proposalId: $e'),
    );
  }

  Future<void> _voteOn(String proposalId, String? candidateId) async {
    final me = _voterUid;
    final before = _votes[proposalId];
    // Se ve al instante; el listener confirma lo que quedó guardado.
    setState(() {
      final v = Map<String, String>.from(before ?? const <String, String>{});
      if (candidateId == null) {
        v.remove(me);
      } else {
        v[me] = candidateId;
      }
      _votes[proposalId] = v;
    });
    if (_isSampleEditor || _myUid.isEmpty) return;
    try {
      await ProposalVotes.vote(widget.trip.userId, widget.trip.id, proposalId, candidateId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (before == null) {
          _votes.remove(proposalId);
        } else {
          _votes[proposalId] = before;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e, fallback: 'No se pudo guardar tu voto. Intenta de nuevo.'), style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.warning,
      ));
    }
  }

  /// Propone un lugar con el mismo buscador que usan las paradas (catálogo o sugerencia nueva).
  Future<void> _addProposalCandidate(String sectionId) async {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Object? choice = await showDialog<Object>(
      context: context,
      builder: (ctx) => _CatalogPickerDialog(isDark: isDark, normalize: _normalize),
    );
    if (choice == null || !mounted) return;
    final String id = 'cand_${DateTime.now().microsecondsSinceEpoch}';
    final ProposalCandidate cand;
    if (choice is _SuggestNewPlace) {
      final result = await showDialog<_SuggestedPlace>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SuggestPlaceDialog(initialName: choice.name.trim(), initialDescription: '', tripId: widget.trip.id),
      );
      if (result == null || !mounted) return;
      setState(() => _suggestionStatus[result.id] = kSuggestionPending);
      cand = ProposalCandidate(
        id: id,
        title: result.name,
        description: result.description,
        lat: result.lat,
        lng: result.lng,
        poiId: result.id,
        poiSource: kPlaceSourceSuggestion,
        proposedBy: _voterUid,
        proposedByName: _voterName,
      );
    } else {
      final poi = choice as Poi;
      cand = ProposalCandidate(
        id: id,
        title: poi.name,
        description: poi.cleanNarrative,
        photoUrl: poi.imageUrl,
        lat: poi.location.isValid ? poi.location.lat : null,
        lng: poi.location.isValid ? poi.location.lng : null,
        cost: poi.priceMxnAvg ?? (poi.priceLevel * 60.0),
        poiId: poi.poiId,
        poiSource: kPlaceSourceCatalog,
        proposedBy: _voterUid,
        proposedByName: _voterName,
      );
    }
    final i = _idx(sectionId);
    if (i < 0 || _sections[i] is! ProposalSection) return;
    final current = _sections[i] as ProposalSection;
    if (cand.poiId != null && current.candidates.any((c) => c.poiId == cand.poiId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${cand.title} ya está en la propuesta.', style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.stormyTeal,
      ));
      return;
    }
    _replaceSection<ProposalSection>(sectionId, (p) => p.copyWith(candidates: [...p.candidates, cand]));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Propusiste ${cand.title}. Ya pueden votar por él.', style: GoogleFonts.inter()),
      backgroundColor: OhtliColors.stormyTeal,
    ));
  }

  void _removeProposalCandidate(String sectionId, ProposalCandidate cand) {
    _replaceSection<ProposalSection>(sectionId, (p) => p.copyWith(candidates: [for (final c in p.candidates) if (c.id != cand.id) c]));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Quitaste ${cand.title.trim().isEmpty ? 'el lugar' : cand.title.trim()} de la propuesta.', style: GoogleFonts.inter()),
      backgroundColor: OhtliColors.onyx,
      action: SnackBarAction(label: 'Deshacer', textColor: OhtliColors.accent, onPressed: _undo),
    ));
  }

  /// El más votado se queda: la propuesta se vuelve una parada en el mismo lugar del viaje.
  void _pickProposalWinner(String sectionId) {
    if (_applyingRemote) return;
    final i = _idx(sectionId);
    if (i < 0 || _sections[i] is! ProposalSection) return;
    final p = _sections[i] as ProposalSection;
    final votes = validVotes(_votes[sectionId] ?? const <String, String>{}, p.candidates);
    final winner = proposalWinner(p.candidates, votes, tieBreakerUid: widget.trip.userId);
    if (winner == null) return;
    final newId = _newSectionId();
    setState(() {
      _sections[i] = winner.toPlace(newId, branchId: p.branchId);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
    _dropBlockEditors(sectionId);
    _voteSubs.remove(sectionId)?.cancel();
    final name = winner.title.trim().isEmpty ? 'el lugar más votado' : winner.title.trim();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Ganó $name. Ya es una parada del viaje.', style: GoogleFonts.inter()),
      backgroundColor: OhtliColors.stormyTeal,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Deshacer', textColor: OhtliColors.accent, onPressed: _undo),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(newId));
  }

  Widget _buildProposalEditor(ProposalSection section, bool isDark) {
    _watchVotes(section.id);
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final sid = section.id;
    final questionController = _blockControllers.putIfAbsent('${sid}_question', () {
      final c = TextEditingController(text: section.question);
      c.addListener(() => _replaceSection<ProposalSection>(sid, (p) => p.copyWith(question: c.text), structural: false));
      return c;
    });
    final votes = validVotes(_votes[sid] ?? const <String, String>{}, section.candidates);
    final people = _editorPeople;
    final editors = [for (final p in people) p.$1];
    final names = {for (final p in people) p.$1: p.$2};
    final me = _voterUid;
    final bool isOwner = _isSampleEditor || widget.trip.userId == _myUid;
    final bool everyone = everyoneVotedOn(votes, editors);
    final winner = proposalWinner(section.candidates, votes, tieBreakerUid: widget.trip.userId);
    final bool canPick = winner != null && (isOwner || everyone);
    final int at = _idx(sid);
    final SplitSection? proposalSplit = at >= 0 ? splitBefore(_sections, at) : null;
    final String pickHint = winner == null
        ? 'Elige cuando haya votos'
        : (canPick ? 'Se queda ${winner.title.trim().isEmpty ? 'el más votado' : winner.title.trim()}' : 'Cuando voten todos, cualquiera puede elegirlo');

    final Widget pickButton = OhtliPrimaryButton(
      compact: true,
      highlight: true,
      icon: Icons.emoji_events_rounded,
      label: 'Elegir el ganador',
      onPressed: canPick ? () => _pickProposalWinner(sid) : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: questionController,
          focusNode: _getFocusNode('${sid}_question'),
          style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: fg),
          decoration: InputDecoration(
            hintText: '¿Dónde comemos?',
            hintStyle: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: sub.withValues(alpha: 0.6)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: InputBorder.none,
          ),
        ),
        Text(
          isOwner
              ? 'Propongan lugares y voten. Tú eliges el ganador cuando quieras; en empate cuenta tu voto.'
              : 'Propongan lugares y voten. Cuando voten todos, cualquiera puede elegir el ganador.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: sub),
        ),
        const SizedBox(height: 12),
        ProposalCandidateList(
          candidates: section.candidates,
          votes: votes,
          names: names,
          myUid: me,
          canVote: true,
          isDark: isDark,
          onVote: (cid) => _voteOn(sid, cid),
          onRemove: (c) => _removeProposalCandidate(sid, c),
          canRemove: (c) => c.proposedBy == me,
        ),
        if (section.candidates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(proposalTally(votes, editors, names, myUid: me), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OhtliSecondaryButton(
              compact: true,
              icon: Icons.add_location_alt_rounded,
              label: 'Agregar un lugar',
              onPressed: () => _addProposalCandidate(sid),
            ),
            if (votes.containsKey(me))
              TextButton.icon(
                onPressed: () => _voteOn(sid, null),
                style: TextButton.styleFrom(foregroundColor: sub),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text('Quitar mi voto', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            if (section.candidates.isNotEmpty) Tooltip(message: pickHint, child: pickButton),
          ],
        ),
        if (proposalSplit != null) _buildWhoGoes(sid, proposalSplit, section.branchId, isDark),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Separarse en ramas: cada quien por su lado y, si quieren, se reencuentran
  // ---------------------------------------------------------------------------
  /// Rama del bloque en [index] cuando el grupo va separado (null si va con todos).
  TripBranch? _branchAt(int index) {
    if (index < 0 || index >= _sections.length) return null;
    final split = splitBefore(_sections, index);
    if (split == null) return null;
    final lane = laneOf(_sections[index]);
    return split.branch(lane.isEmpty ? null : lane);
  }

  /// ¿La parada en [index] es donde el grupo se reencuentra?
  bool _isMeetupAt(int index) {
    if (index < 0 || index >= _sections.length) return false;
    final s = _sections[index];
    if (s is! PlaceSection) return false;
    final split = splitBefore(_sections, index);
    return split != null && split.branch(s.branchId) == null;
  }

  Color _branchColorOf(TripBranch b) => branchColor(branchIndexes(_sections)[b.id] ?? 0);

  String _branchLabel(TripBranch b) => branchName(b, branchIndexes(_sections)[b.id] ?? 0);

  /// Lo nuevo que se agrega después de separarse sigue la rama de lo anterior (o la primera);
  /// un traslado toma la de la parada a la que llega. Se llama dentro de setState.
  void _assignDefaultBranch(String id) {
    final i = _idx(id);
    if (i < 0) return;
    final s = _sections[i];
    final split = splitBefore(_sections, i);
    if (split == null || split.branches.isEmpty) return;
    if (s is TransferSection) {
      final lane = transferBranchFor(_sections, i);
      if (lane != null) _sections[i] = s.copyWith(branchId: lane);
      return;
    }
    String lane = split.branches.first.id;
    for (int j = i - 1; j >= 0; j--) {
      final x = _sections[j];
      if (identical(x, split)) break;
      final l = laneOf(x);
      if (l.isNotEmpty && split.branch(l) != null) {
        lane = l;
        break;
      }
    }
    if (s is PlaceSection && !s.unplanned) _sections[i] = s.copyWith(branchId: lane);
    if (s is ProposalSection) _sections[i] = s.copyWith(branchId: lane);
  }

  /// «¿Quién va?»: pone la rama de una parada, propuesta o traslado (null = punto de
  /// reencuentro). Los traslados que llegan a la parada se van con ella.
  void _setBlockBranch(String id, String? branchId) {
    if (_applyingRemote) return;
    final i = _idx(id);
    if (i < 0) return;
    final s = _sections[i];
    final draft = List<TripSection>.of(_sections);
    if (s is PlaceSection) {
      draft[i] = branchId == null ? s.copyWith(clearBranch: true, meetup: true) : s.copyWith(branchId: branchId, meetup: false);
      for (int j = i - 1; j >= 0 && draft[j] is TransferSection; j--) {
        final t = draft[j] as TransferSection;
        // Rumbo a una rama: van por ella. Rumbo al reencuentro: cada uno sale de su rama.
        final String? lane = branchId ?? t.branchId ?? transferBranchFor(draft, j);
        if (lane != t.branchId) draft[j] = lane == null ? t.copyWith(clearBranch: true) : t.copyWith(branchId: lane);
      }
    } else if (s is ProposalSection) {
      draft[i] = s.copyWith(branchId: branchId, clearBranch: branchId == null);
    } else if (s is TransferSection) {
      draft[i] = s.copyWith(branchId: branchId, clearBranch: branchId == null);
    } else {
      return;
    }
    // Al cambiar una parada puede cambiar cuál es el reencuentro: los traslados sin rama que
    // quedan dentro de la separación toman la de la parada a la que llegan (o de la que salen).
    for (int k = 0; k < draft.length; k++) {
      final t = draft[k];
      if (t is! TransferSection || t.branchId != null || splitBefore(draft, k) == null) continue;
      final lane = transferBranchFor(draft, k);
      if (lane != null) draft[k] = t.copyWith(branchId: lane);
    }
    final changed = [for (int k = 0; k < draft.length; k++) if (!identical(draft[k], _sections[k])) k];
    if (changed.isEmpty) return;
    setState(() {
      for (final k in changed) {
        _sections[k] = draft[k];
      }
      _forceNewUndoStep = true;
      _onDataChanged();
    });
  }

  void _updateBranch(String splitId, String branchId, TripBranch Function(TripBranch) change, {bool structural = true}) {
    _replaceSection<SplitSection>(
      splitId,
      (s) => s.copyWith(branches: [for (final b in s.branches) b.id == branchId ? change(b) : b]),
      structural: structural,
    );
  }

  /// Una persona va en un solo grupo: al ponerla en uno sale de los demás.
  void _toggleBranchMember(String splitId, String branchId, String uid) {
    _replaceSection<SplitSection>(splitId, (s) {
      final already = s.branch(branchId)?.memberIds.contains(uid) ?? false;
      return s.copyWith(branches: [
        for (final b in s.branches)
          if (b.id == branchId)
            b.copyWith(memberIds: already ? [for (final m in b.memberIds) if (m != uid) m] : [...b.memberIds, uid])
          else if (b.memberIds.contains(uid))
            b.copyWith(memberIds: [for (final m in b.memberIds) if (m != uid) m])
          else
            b,
      ]);
    });
  }

  void _addBranch(String splitId) {
    _replaceSection<SplitSection>(splitId, (s) {
      final used = {for (final b in s.branches) b.name.trim()};
      int n = s.branches.length + 1;
      while (used.contains('Grupo $n')) {
        n++;
      }
      return s.copyWith(branches: [...s.branches, TripBranch(id: 'br_${DateTime.now().microsecondsSinceEpoch}_$n', name: 'Grupo $n')]);
    });
  }

  /// Quita una rama (siempre quedan al menos dos). Lo que iba por ella se queda sin grupo.
  void _removeBranch(String splitId, String branchId) {
    if (_applyingRemote) return;
    final i = _idx(splitId);
    if (i < 0 || _sections[i] is! SplitSection) return;
    final split = _sections[i] as SplitSection;
    final gone = split.branch(branchId);
    if (gone == null || split.branches.length <= 2) return;
    final name = branchName(gone, split.branches.indexOf(gone));
    setState(() {
      _sections[i] = split.copyWith(branches: [for (final b in split.branches) if (b.id != branchId) b]);
      for (int k = 0; k < _sections.length; k++) {
        final s = _sections[k];
        if (s is PlaceSection && s.branchId == branchId) {
          _sections[k] = s.copyWith(clearBranch: true);
        } else if (s is TransferSection && s.branchId == branchId) {
          _sections[k] = s.copyWith(clearBranch: true);
        } else if (s is ProposalSection && s.branchId == branchId) {
          _sections[k] = s.copyWith(clearBranch: true);
        }
      }
      _forceNewUndoStep = true;
      _onDataChanged();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Quitaste $name. Sus paradas quedaron sin grupo: elige «¿Quién va?» en cada una.', style: GoogleFonts.inter()),
      backgroundColor: OhtliColors.onyx,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Deshacer', textColor: OhtliColors.accent, onPressed: _undo),
    ));
  }

  /// «¿Quién va?» con un chip por rama y, en paradas, el punto de reencuentro.
  Widget _buildWhoGoes(String id, SplitSection split, String? current, bool isDark, {bool allowMeetup = true, double top = 12}) {
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final bool none = split.branch(current) == null;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text('¿Quién va?', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: sub)),
          ),
          for (int i = 0; i < split.branches.length; i++)
            BranchChoiceChip(
              label: branchName(split.branches[i], i),
              color: branchColor(i),
              selected: current == split.branches[i].id,
              isDark: isDark,
              onTap: () => _setBlockBranch(id, split.branches[i].id),
            ),
          if (allowMeetup)
            Tooltip(
              message: 'Aquí se juntan los grupos que se reencuentran',
              child: BranchChoiceChip(
                label: 'Punto de reencuentro',
                icon: Icons.call_merge_rounded,
                color: OhtliColors.stormyTeal,
                selected: none,
                isDark: isDark,
                onTap: () => _setBlockBranch(id, null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSplitEditor(SplitSection section, bool isDark) {
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final people = _editorPeople;
    final assigned = {for (final b in section.branches) ...b.memberIds};
    final unassigned = [for (final p in people) if (!assigned.contains(p.$1)) p.$1 == _voterUid ? 'tú' : p.$2];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cada quien por su lado. Reparte al grupo y luego, en cada parada de abajo, elige «¿Quién va?». '
          'La primera parada de todo el grupo es el punto de reencuentro.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: sub),
        ),
        const SizedBox(height: 12),
        for (int bi = 0; bi < section.branches.length; bi++) _buildBranchEditor(section, bi, people, isDark),
        if (unassigned.isNotEmpty && people.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Sin grupo: ${unassigned.join(', ')}. En el modo viaje ve${unassigned.length == 1 ? '' : 'n'} todas las ramas.',
              style: GoogleFonts.inter(fontSize: 12, color: sub),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OhtliSecondaryButton(
            compact: true,
            icon: Icons.group_add_rounded,
            label: 'Agregar grupo',
            onPressed: () => _addBranch(section.id),
          ),
        ),
      ],
    );
  }

  Widget _buildBranchEditor(SplitSection section, int bi, List<(String, String)> people, bool isDark) {
    final b = section.branches[bi];
    final color = branchColor(bi);
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final sid = section.id;
    final bid = b.id;
    final nameController = _blockControllers.putIfAbsent('${sid}_branch_$bid', () {
      final c = TextEditingController(text: b.name);
      c.addListener(() => _updateBranch(sid, bid, (x) => x.copyWith(name: c.text), structural: false));
      return c;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: color.withValues(alpha: isDark ? 0.12 : 0.06),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameController,
                            focusNode: _getFocusNode('${sid}_branch_$bid'),
                            style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.bold, color: branchInk(color, isDark)),
                            decoration: InputDecoration(
                              hintText: 'Grupo ${bi + 1}',
                              hintStyle: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.bold, color: branchInk(color, isDark).withValues(alpha: 0.5)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (section.branches.length > 2)
                          IconButton(
                            tooltip: 'Quitar este grupo',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeBranch(sid, bid),
                            icon: Icon(Icons.close_rounded, size: 18, color: sub),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in people)
                          OhtliChoiceChip(
                            label: p.$1 == _voterUid && p.$2 != 'Tú' ? '${p.$2} (tú)' : p.$2,
                            icon: b.memberIds.contains(p.$1) ? Icons.check_rounded : Icons.person_outline_rounded,
                            selected: b.memberIds.contains(p.$1),
                            onTap: () => _toggleBranchMember(sid, bid, p.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Switch(
                          value: b.rejoins,
                          onChanged: (v) => _updateBranch(sid, bid, (x) => x.copyWith(rejoins: v)),
                          activeThumbColor: Colors.white,
                          activeTrackColor: OhtliColors.stormyTeal,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            b.rejoins ? 'Se reencuentran con el grupo' : 'No se reencuentran: terminan por su lado',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Traslados entre paradas
  // ---------------------------------------------------------------------------
  String _newSectionId() => 'sec_${DateTime.now().microsecondsSinceEpoch}_${_sections.length}';

  void _replaceTransfer(String id, TransferSection Function(TransferSection) change, {bool structural = true}) {
    if (_applyingRemote) return;
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
  /// Si el grupo va separado, la anterior es la de la misma rama.
  (PlaceSection?, PlaceSection?) _placesAround(int index) => transferEnds(_sections, index);

  void _estimateTransfer(String id) {
    final i = _idx(id);
    if (i < 0) return;
    final t = _sections[i] as TransferSection;
    final (a, b) = _placesAround(i);
    final est = (a != null && b != null) ? estimateTransfer(a, b, t.mode, id: t.id) : null;
    if (est == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Para estimarlo, las paradas de antes y después deben tener ubicación.', style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.warning,
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
    final place = _sections[i] as PlaceSection;
    final id = _newSectionId();
    // Se calcula sobre la lista con el traslado ya puesto: así sale de la parada de su rama.
    final draft = List<TripSection>.of(_sections)..insert(i, TransferSection(id: id));
    final lane = transferBranchFor(draft, i);
    final (prev, _) = transferEnds(draft, i);
    final t = ((prev != null ? estimateTransfer(prev, place, 'walking', id: id) : null) ?? TransferSection(id: id)).copyWith(branchId: lane);
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
    // Ids únicos aunque se creen varios en el mismo milisegundo.
    int k = 0;
    String nextId() => '${_newSectionId()}_${k++}';
    final (list, added) = hasBranches(_sections)
        ? fillMissingTransfersByBranch(_sections, mode, nextId)
        : fillMissingTransfers(_sections, mode, nextId);
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
      action: added > 0 ? SnackBarAction(label: 'Deshacer', textColor: OhtliColors.accent, onPressed: _undo) : null,
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
      _sections = hasBranches(_sections)
          ? recalculateScheduleByBranch(_sections, startTime: start)
          : recalculateSchedule(_sections, startTime: start);
      _forceNewUndoStep = true;
      _onDataChanged();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Horarios ajustados con las estancias y los traslados.', style: GoogleFonts.inter()),
      backgroundColor: OhtliColors.stormyTeal,
      action: SnackBarAction(label: 'Deshacer', textColor: OhtliColors.accent, onPressed: _undo),
    ));
  }

  /// Traslados abiertos para editarse; cerrados se ven en una línea.
  final Set<String> _openTransfers = {};

  /// Traslado en una línea ("A pie · 13 min · 1 km"); al tocarlo se despliega para editarlo.
  Widget _buildTransferEditor(TransferSection t, bool isDark) {
    final bool open = _openTransfers.contains(t.id);
    final mode = transferModeOf(t.mode);
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final String costText = t.cost > 0 ? ' · \$${t.cost.toStringAsFixed(0)}' : '';
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => open ? _openTransfers.remove(t.id) : _openTransfers.add(t.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(mode.icon, size: 20, color: OhtliColors.stormyTeal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${describeTransfer(t)}$costText',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
                  ),
                  if (t.isEstimated)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: OhtliColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      child: Text('Estimado', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: OhtliColors.accent)),
                    ),
                  const SizedBox(width: 6),
                  Text(open ? 'Listo' : 'Editar', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: sub),
                ],
              ),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.only(top: 10), child: _buildTransferEditorFull(t, isDark)),
        ],
      ),
    );
  }

  Widget _buildTransferEditorFull(TransferSection t, bool isDark) {
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
    final SplitSection? transferSplit = i >= 0 ? splitBefore(_sections, i) : null;
    final mode = transferModeOf(t.mode);

    // Elegir modo: si el tramo era estimado, se vuelve a estimar con el nuevo modo.
    void changeMode(String id) {
      if (t.isEstimated && a != null && b != null) {
        final est = estimateTransfer(a, b, id, id: sid);
        if (est != null) {
          _replaceTransfer(sid, (_) => est.copyWith(notes: t.notes));
          _resetBlockEditors();
          return;
        }
      }
      _replaceTransfer(sid, (x) => x.copyWith(mode: id));
    }

    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (transferSplit != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildWhoGoes(sid, transferSplit, t.branchId, isDark, allowMeetup: false, top: 0)),
        if (a != null || b != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${a?.title.isNotEmpty == true ? a!.title : 'Inicio'}  →  ${b?.title.isNotEmpty == true ? b!.title : 'Siguiente parada'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: sub),
            ),
          ),
        // Un solo botón para el modo (abre el selector agrupado) y "Estimar" como acción principal.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TransferModeButton(mode: t.mode, isDark: isDark, onChanged: changeMode),
            FilledButton.tonalIcon(
              onPressed: () => _estimateTransfer(sid),
              style: FilledButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.25 : 0.12),
                foregroundColor: isDark ? Colors.white : OhtliColors.stormyTeal,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
              label: Text('Estimar con el mapa', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            if (t.isEstimated)
              Tooltip(
                message: 'Calculado por Ohtli a partir de la ubicación de las paradas. Puedes corregirlo.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: OhtliColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('Estimado por Ohtli', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OhtliColors.accent)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Minutos, distancia y costo en una fila.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: minsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.inter(fontSize: 13),
                decoration: deco('Tiempo', suffix: 'min'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                style: GoogleFonts.inter(fontSize: 13),
                decoration: deco('Distancia', suffix: 'km'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
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
        const SizedBox(height: 8),
        TextField(
          controller: notesCtrl,
          minLines: 1,
          maxLines: 2,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: deco(mode.id == 'walking' ? 'Indicaciones (opcional)' : 'Línea, dirección o dónde bajar (opcional)'),
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
      if (s is PlaceSection && !s.unplanned) numbers[s.id] = ++placeNumber;
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
                                  backgroundColor: OhtliColors.accentFill,
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
                            child: Icon(Icons.location_off_outlined, size: 14, color: OhtliColors.warning),
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

  /// Acción para elegir el lugar de la parada en la base de Ohtli. No muestra estados
  /// internos (catálogo/sugerencia): solo avisa si a la parada le falta ubicación.
  Widget _buildLocationChip(PlaceSection place, bool isDark) {
    final bool located = place.lat != null && place.lng != null;
    final bool chosen = place.isLinkedToCatalog || place.isSuggestion;
    final IconData icon = chosen ? Icons.where_to_vote_rounded : (located ? Icons.travel_explore_rounded : Icons.location_off_outlined);
    final String label = chosen
        ? 'Cambiar lugar'
        : (located ? 'Buscar en los lugares de Ohtli' : 'Sin ubicación · Buscar lugar');
    Color tone = located || chosen ? OhtliColors.stormyTeal : OhtliColors.warning;
    // En modo oscuro los tonos de marca se aclaran para que se lean sobre fondo oscuro
    if (isDark) tone = Color.lerp(tone, Colors.white, 0.45)!;
    return ActionChip(
      avatar: Icon(icon, size: 15, color: tone),
      label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: tone)),
      tooltip: 'Elige un lugar o sugiere uno nuevo',
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
                                foregroundColor: OhtliColors.warningText,
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
/// Resultado del buscador cuando la persona quiere sugerir un lugar que no está.
class _SuggestNewPlace {
  final String name;
  const _SuggestNewPlace(this.name);
}

class _CatalogPickerDialog extends StatefulWidget {
  final bool isDark;
  final String Function(String) normalize;
  final String initialQuery;

  const _CatalogPickerDialog({required this.isDark, required this.normalize, this.initialQuery = ''});

  @override
  State<_CatalogPickerDialog> createState() => _CatalogPickerDialogState();
}

class _CatalogPickerDialogState extends State<_CatalogPickerDialog> {
  late final Future<List<Poi>> _catalog = PlacesPage.loadCatalog();
  late String _query = widget.initialQuery.trim();
  late final TextEditingController _queryController = TextEditingController(text: _query);

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Widget _suggestButton({bool prominent = false}) {
    final name = _query.trim();
    final label = name.isEmpty ? 'Sugerir un lugar nuevo' : 'Sugerir "$name" como lugar nuevo';
    final child = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700));
    final onPressed = () => Navigator.of(context).pop(_SuggestNewPlace(name));
    if (prominent) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_location_alt_rounded, size: 18),
        label: child,
        style: ElevatedButton.styleFrom(
          backgroundColor: OhtliColors.stormyTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_location_alt_outlined, size: 18),
      label: child,
      style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
    );
  }

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
                      'Elegir un lugar',
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
                'Busca el lugar para tomar su ubicación, foto y costo. Si no está, sugiérelo.',
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                controller: _queryController,
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.travel_explore_rounded, size: 40, color: OhtliColors.stormyTeal.withValues(alpha: 0.6)),
                            const SizedBox(height: 10),
                            Text('"$_query" todavía no está en Ohtli.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                            const SizedBox(height: 4),
                            Text('Puedes sugerirlo: lo usarás en tu viaje de inmediato y,\nsi se aprueba, otras personas también podrán encontrarlo.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.6))),
                            const SizedBox(height: 14),
                            _suggestButton(prominent: true),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
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
                                  child: Icon(Icons.location_off_outlined, size: 16, color: OhtliColors.warning),
                                ),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                          ),
                        ),
                        const Divider(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text('¿No lo encuentras?',
                                  style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.6))),
                            ),
                            Flexible(flex: 3, child: _suggestButton()),
                          ],
                        ),
                      ],
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


/// Lugar que la persona sugirió (ya guardado en `poi_suggestions`).
class _SuggestedPlace {
  final String id;
  final String name;
  final String description;
  final double lat;
  final double lng;
  const _SuggestedPlace({required this.id, required this.name, required this.description, required this.lat, required this.lng});
}

/// Formulario para sugerir un lugar que no está en la base de Ohtli.
class _SuggestPlaceDialog extends StatefulWidget {
  final String initialName;
  final String initialDescription;
  final double? initialLat;
  final double? initialLng;
  final String photoUrl;
  final double? priceMxnAvg;
  final String tripId;

  const _SuggestPlaceDialog({
    required this.initialName,
    required this.initialDescription,
    this.initialLat,
    this.initialLng,
    this.photoUrl = '',
    this.priceMxnAvg,
    required this.tripId,
  });

  @override
  State<_SuggestPlaceDialog> createState() => _SuggestPlaceDialogState();
}

class _SuggestPlaceDialogState extends State<_SuggestPlaceDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late final PlaceDetailsDraft _details = PlaceDetailsDraft()..description = widget.initialDescription;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _coords = TextEditingController();
  String _category = 'attraction';
  double? _lat;
  double? _lng;
  String _address = '';
  List<Map<String, dynamic>> _results = [];
  bool _locating = false;
  bool _searching = false;
  String? _searchError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _lat = widget.initialLat;
      _lng = widget.initialLng;
      _address = 'Ubicación actual de la parada';
    }
    _search.text = widget.initialName;
    // El costo que ya puso en la parada sugiere el rango de precio
    final cost = widget.priceMxnAvg;
    if (cost != null) {
      _details.priceLevel = cost <= 0 ? 0 : (cost <= 100 ? 1 : (cost <= 300 ? 2 : (cost <= 600 ? 3 : 4)));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    _coords.dispose();
    super.dispose();
  }

  // Búsqueda de direcciones en OpenStreetMap (Nominatim), limitada al Valle de México.
  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'jsonv2',
        'countrycodes': 'mx',
        'viewbox': '-99.40,19.62,-98.90,19.02',
        'bounded': '1',
        'limit': '6',
        'accept-language': 'es',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _results = list;
        if (list.isEmpty) _searchError = 'Sin resultados. Prueba con la calle y la colonia, o pega las coordenadas.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchError = 'No pudimos buscar la dirección. Revisa tu conexión o pega las coordenadas.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Llena la ubicación con la posición actual del dispositivo.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _searchError = null;
      _results = [];
    });
    try {
      final here = await getCurrentLocation();
      if (!mounted) return;
      if (!here.inCdmx) {
        setState(() => _searchError = 'Tu ubicación actual queda fuera de la Ciudad de México. Busca la dirección del lugar.');
        return;
      }
      setState(() {
        _lat = here.lat;
        _lng = here.lng;
        _address = here.address.isNotEmpty ? here.address : 'Coordenadas ${here.lat.toStringAsFixed(5)}, ${here.lng.toStringAsFixed(5)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchError = e is CurrentLocationException ? e.message : 'No pudimos obtener tu ubicación. Busca la dirección.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyCoords(String text) {
    // Acepta "19.4326, -99.1332" o un enlace de Google Maps con "@19.43,-99.13"
    final m = RegExp(r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)').firstMatch(text);
    if (m == null) {
      setState(() => _searchError = 'No reconocimos las coordenadas. Usa el formato 19.4326, -99.1332.');
      return;
    }
    final lat = double.parse(m.group(1)!);
    final lng = double.parse(m.group(2)!);
    if (lat < 18.8 || lat > 20.0 || lng < -99.7 || lng > -98.6) {
      setState(() => _searchError = 'Esas coordenadas quedan fuera de la Ciudad de México.');
      return;
    }
    setState(() {
      _lat = lat;
      _lng = lng;
      _address = 'Coordenadas $lat, $lng';
      _searchError = null;
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'Escribe el nombre del lugar (al menos 3 letras).');
      return;
    }
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Indica dónde está el lugar: busca su dirección o pega sus coordenadas.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await PoiSuggestionService.create(
        name: name,
        category: _category,
        lat: _lat,
        lng: _lng,
        address: _address.startsWith('Ubicación actual') || _address.startsWith('Coordenadas') ? '' : _address,
        description: _details.description,
        photoUrl: widget.photoUrl,
        tripId: widget.tripId,
        details: _details.toMap(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(_SuggestedPlace(id: id, name: name, description: _details.description.trim(), lat: _lat!, lng: _lng!));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e, fallback: 'No pudimos enviar la sugerencia. Intenta de nuevo.');
      });
    }
  }

  InputDecoration _decoration(String label, {String? hint, Widget? prefix, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  // ---------------------------------------------------------------------------
  // Asistente por pasos: una pregunta a la vez para que no se sienta como un formulario
  // ---------------------------------------------------------------------------
  int _step = 0;
  static const int _steps = 5;

  static const Map<String, IconData> _categoryIcons = {
    'museum': Icons.museum_outlined,
    'gallery': Icons.palette_outlined,
    'artwork': Icons.account_balance_outlined,
    'theatre': Icons.theater_comedy_outlined,
    'cinema': Icons.movie_outlined,
    'arts_centre': Icons.groups_outlined,
    'park': Icons.park_outlined,
    'cafe': Icons.local_cafe_outlined,
    'restaurant': Icons.restaurant_outlined,
    'bar': Icons.local_bar_outlined,
    'marketplace': Icons.storefront_outlined,
    'place_of_worship': Icons.church_outlined,
    'attraction': Icons.camera_alt_outlined,
    'other': Icons.more_horiz_rounded,
  };

  String get _placeName => _name.text.trim().isEmpty ? 'este lugar' : _name.text.trim();

  bool get _canContinue => switch (_step) {
        0 => _name.text.trim().length >= 3,
        1 => _lat != null && _lng != null,
        _ => true,
      };

  void _go(int step) => setState(() {
        _error = null;
        _step = step.clamp(0, _steps - 1);
        if (_step == 1 && _search.text.trim().isEmpty) _search.text = _name.text.trim();
      });

  ({String title, String subtitle}) get _stepCopy => switch (_step) {
        0 => (title: '¿Qué lugar quieres sugerir?', subtitle: 'Empecemos por su nombre y qué tipo de lugar es.'),
        1 => (title: '¿Dónde está $_placeName?', subtitle: 'Búscalo por su dirección para ubicarlo en el mapa.'),
        2 => (title: '¿Cómo se siente estar ahí?', subtitle: 'Elige lo que mejor lo describa. Puedes omitir este paso.'),
        3 => (title: 'Lo práctico', subtitle: 'Si lo sabes, ayuda a quien quiera ir. Si no, omítelo.'),
        _ => (title: '¿Qué lo hace especial?', subtitle: 'Cuéntalo con tus palabras. Es lo último.'),
      };

  Widget _stepBody(bool isDark) {
    final muted = OhtliColors.onyx.withValues(alpha: 0.6);
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
              decoration: InputDecoration(
                hintText: 'Ej. Café La Habana',
                hintStyle: GoogleFonts.outfit(fontSize: 20, color: OhtliColors.onyx.withValues(alpha: 0.3)),
                border: UnderlineInputBorder(borderSide: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.4))),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: OhtliColors.stormyTeal, width: 2)),
              ),
            ),
            const SizedBox(height: 22),
            Text('Es un…', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 460 ? 4 : 3;
              const gap = 8.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: kSuggestionCategories.entries.map((e) {
                  final selected = _category == e.key;
                  return SizedBox(
                    width: w,
                    child: Material(
                      color: selected
                          ? OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.35 : 0.14)
                          : (isDark ? const Color(0xFF26262B) : OhtliColors.cantera.withValues(alpha: 0.18)),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _category = e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: selected ? OhtliColors.stormyTeal : Colors.transparent, width: 1.5),
                          ),
                          child: Column(
                            children: [
                              Icon(_categoryIcons[e.key] ?? Icons.place_outlined,
                                  size: 22, color: selected ? (isDark ? Colors.white : OhtliColors.stormyTeal) : muted),
                              const SizedBox(height: 6),
                              Text(e.value,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      fontSize: 11.5, height: 1.2, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: OhtliColors.onyx)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        );
      case 1:
        final hasLocation = _lat != null && _lng != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasLocation)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.18 : 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.where_to_vote_rounded, color: OhtliColors.stormyTeal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('¡Listo! Ya está en el mapa', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                          const SizedBox(height: 2),
                          Text(_address, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: muted)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _lat = null;
                        _lng = null;
                        _address = '';
                      }),
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: _decoration(
                  'Dirección o nombre',
                  hint: 'Calle, número y colonia',
                  prefix: const Icon(Icons.search_rounded),
                  suffix: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _runSearch),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: Text(_locating ? 'Buscando tu ubicación…' : 'Estoy aquí: usar mi ubicación actual',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OhtliColors.stormyTeal,
                  side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 6),
              ..._results.map((r) => Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      leading: const Icon(Icons.place_outlined, color: OhtliColors.stormyTeal),
                      title: Text((r['display_name'] ?? '').toString(),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx)),
                      onTap: () => setState(() {
                        _lat = double.tryParse('${r['lat']}');
                        _lng = double.tryParse('${r['lon']}');
                        _address = (r['display_name'] ?? '').toString();
                        _results = [];
                      }),
                    ),
                  )),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_searchError!,
                      style: GoogleFonts.inter(fontSize: 12, color: isDark ? const Color(0xFFFF9E9E) : OhtliColors.warningText)),
                ),
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('¿No aparece? Pega sus coordenadas', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: muted)),
                  children: [
                    TextField(
                      controller: _coords,
                      onSubmitted: _applyCoords,
                      decoration: _decoration(
                        'Coordenadas',
                        hint: '19.4326, -99.1332 o un enlace de Google Maps',
                        prefix: const Icon(Icons.my_location_rounded),
                        suffix: IconButton(icon: const Icon(Icons.check_rounded), onPressed: () => _applyCoords(_coords.text)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ],
        );
      case 2:
        return PlaceDetailsFields(
          draft: _details,
          compact: true,
          sections: const {PlaceDetailsSection.vibes, PlaceDetailsSection.idealFor},
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Cuánto se gasta por persona?', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            const SizedBox(height: 8),
            PlaceDetailsFields(
              draft: _details,
              compact: true,
              sections: const {PlaceDetailsSection.price, PlaceDetailsSection.hours, PlaceDetailsSection.yesNo},
            ),
          ],
        );
      default:
        final answered = _details.toMap().keys.where((k) => k != 'description').length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlaceDetailsFields(
              draft: _details,
              compact: true,
              sections: const {PlaceDetailsSection.description, PlaceDetailsSection.offers, PlaceDetailsSection.tip},
            ),
            const SizedBox(height: 18),
            // Resumen antes de enviar
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF26262B) : OhtliColors.cantera.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_categoryIcons[_category] ?? Icons.place_outlined, color: OhtliColors.stormyTeal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_placeName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                        Text(
                          '${kSuggestionCategories[_category]} · ${answered == 0 ? 'sin detalles extra' : (answered == 1 ? '1 detalle' : '$answered detalles')}',
                          style: GoogleFonts.inter(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lo usarás en tu viaje de inmediato. Para que otras personas lo encuentren y Ohtli lo pueda '
                    'recomendar, un administrador lo revisará.',
                    style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: muted),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final isLast = _step == _steps - 1;
    final optional = _step >= 2 && !isLast;
    final copy = _stepCopy;
    final muted = OhtliColors.onyx.withValues(alpha: 0.6);
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(12),
      // Altura fija: el asistente no "brinca" de tamaño al pasar de un paso a otro
      child: SizedBox(
        width: 560,
        height: (MediaQuery.of(context).size.height * 0.88).clamp(420.0, 640.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progreso
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Text('Paso ${_step + 1} de $_steps',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: (_step + 1) / _steps),
                        duration: const Duration(milliseconds: 300),
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 5,
                          backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation(OhtliColors.stormyTeal),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancelar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(copy.title, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.15)),
                      const SizedBox(height: 4),
                      Text(copy.subtitle, style: GoogleFonts.inter(fontSize: 13, color: muted)),
                      const SizedBox(height: 18),
                      _stepBody(isDark),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                child: Text(_error!,
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFFFF9E9E) : OhtliColors.warningText)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 18, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton.icon(
                      onPressed: _saving ? null : () => _go(_step - 1),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Atrás'),
                    ),
                  const Spacer(),
                  if (optional)
                    TextButton(
                      onPressed: () => _go(_step + 1),
                      child: Text('Omitir', style: GoogleFonts.inter(color: muted, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: _saving || !_canContinue ? null : (isLast ? _submit : () => _go(_step + 1)),
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 18),
                    label: Text(isLast ? (_saving ? 'Enviando…' : 'Usar este lugar') : 'Siguiente',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



/// Línea punteada del lienzo del editor (como la del viaje publicado).
class _EditorSpinePainter extends CustomPainter {
  final Color color;
  const _EditorSpinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, math.min(y + 5, size.height)), paint);
      y += 11;
    }
  }

  @override
  bool shouldRepaint(covariant _EditorSpinePainter old) => old.color != color;
}

/// "+" entre bloques: tenue hasta pasar el cursor; al tocarlo abre el menú de bloques.
class _InsertLine extends StatefulWidget {
  final VoidCallback onTap;
  final double spineX;
  final bool isDark;
  const _InsertLine({required this.onTap, required this.spineX, required this.isDark});

  @override
  State<_InsertLine> createState() => _InsertLineState();
}

class _InsertLineState extends State<_InsertLine> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = OhtliColors.stormyTeal;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 30,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: widget.spineX + 22,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hover ? 1 : 0,
                  child: Container(height: 1.5, color: accent.withValues(alpha: 0.5)),
                ),
              ),
              Positioned(
                left: widget.spineX - 11,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 150),
                  scale: _hover ? 1.15 : 1,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hover ? 1 : 0.45,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _hover ? accent : (widget.isDark ? const Color(0xFF1E1E22) : Colors.white),
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 1.5),
                      ),
                      child: Icon(Icons.add_rounded, size: 15, color: _hover ? Colors.white : accent),
                    ),
                  ),
                ),
              ),
              if (_hover)
                Positioned(
                  left: widget.spineX + 22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    color: widget.isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
                    child: Text('Agregar aquí', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lugar elegido para el inicio o el fin del recorrido.
class _EndpointChoice {
  final String name;
  final double lat;
  final double lng;

  /// Al cambiar el inicio: el fin queda en el mismo lugar (ida y vuelta). Al cambiar el fin:
  /// termina donde empieza (y [name]/[lat]/[lng] son los del inicio).
  final bool sameForEnd;

  const _EndpointChoice(this.name, this.lat, this.lng, {this.sameForEnd = false});
}

/// Diálogo para elegir dónde empieza o termina el recorrido: buscador de lugar o dirección
/// (el mismo del planificador) o la ubicación actual.
class _EndpointDialog extends StatefulWidget {
  final bool start;
  final RouteEndpoint? current;
  final RouteEndpoint? startPoint;
  final bool roundTrip;

  const _EndpointDialog({required this.start, required this.current, required this.startPoint, required this.roundTrip});

  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  final _search = TextEditingController();
  String? _name;
  double? _lat, _lng;
  late bool _same = widget.start && widget.roundTrip;
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final here = await getCurrentLocation();
      if (!mounted) return;
      if (!here.inCdmx) {
        setState(() => _error = 'Tu ubicación actual queda fuera de la Ciudad de México. Busca la dirección.');
        return;
      }
      final name = here.address.isNotEmpty ? here.address.split(',').first.trim() : 'Mi ubicación';
      setState(() {
        _name = name;
        _lat = here.lat;
        _lng = here.lng;
        _search.text = name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is CurrentLocationException ? e.message : 'No pudimos obtener tu ubicación. Busca la dirección.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color fg = isDark ? Colors.white : OhtliColors.onyx;
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final kind = widget.start ? (widget.roundTrip ? EndpointKind.both : EndpointKind.start) : EndpointKind.end;
    final title = switch (kind) {
      EndpointKind.start => '¿Dónde empieza el recorrido?',
      EndpointKind.end => '¿Dónde termina el recorrido?',
      EndpointKind.both => '¿Dónde empieza y termina?',
    };
    final bool picked = _lat != null && _lng != null;
    final RouteEndpoint? home = widget.startPoint;
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : OhtliColors.cloudDancer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  RouteEndpointPin(kind: kind, height: 34),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w700, color: fg))),
                ],
              ),
              if (widget.current != null) ...[
                const SizedBox(height: 8),
                Text('Ahora: ${widget.current!.name}${widget.current!.derived ? ' (la ${widget.start ? 'primera' : 'última'} parada)' : ''}',
                    style: GoogleFonts.inter(fontSize: 13, color: sub)),
              ],
              const SizedBox(height: 16),
              PlaceSearchField(
                controller: _search,
                hintText: 'Busca un lugar o una dirección…',
                onSelected: (name, lat, lng) => setState(() {
                  _name = name;
                  _lat = lat;
                  _lng = lng;
                  _error = null;
                }),
                onCleared: () => setState(() {
                  _name = null;
                  _lat = null;
                  _lng = null;
                }),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _locating ? null : _useCurrentLocation,
                  style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
                  icon: _locating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(_locating ? 'Buscando tu ubicación…' : 'Usar mi ubicación actual',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.warningText)),
                ),
              if (widget.start)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _same,
                  activeThumbColor: OhtliColors.stormyTeal,
                  onChanged: (v) => setState(() => _same = v),
                  title: Text('Termina en el mismo lugar', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
                  subtitle: Text('Ida y vuelta', style: GoogleFonts.inter(fontSize: 12.5, color: sub)),
                )
              else if (home != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, _EndpointChoice(home.name, home.lat, home.lng, sameForEnd: true)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OhtliColors.stormyTeal,
                      side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.5)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const RouteEndpointPin(kind: EndpointKind.both, height: 20),
                    label: Text('Terminar donde empieza (${home.name})',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: sub),
                    child: Text('Cancelar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: picked
                        ? () => Navigator.pop(
                            context,
                            _EndpointChoice((_name ?? '').trim().isEmpty ? 'Punto elegido' : _name!.trim(), _lat!, _lng!,
                                sameForEnd: widget.start && _same))
                        : null,
                    style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, shape: const StadiumBorder()),
                    child: Text('Guardar', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

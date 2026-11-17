import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../config/admin.dart' show isSuperUser;
import '../labs/research/lab_models.dart';

/// Clave de la funcionalidad en prueba "Logros" (los títulos) en `lab_features`.
const kFeatureLogros = 'logros';

/// Lo que la sesión puede ver de las funcionalidades en prueba de Ohtli Labs.
class FeatureAccess {
  final Map<String, LabFeature> features;
  final Set<String> enrolledStudyIds;
  final Map<String, LabResearchStudy> enrolledStudies;
  final bool isLabMember;
  final bool isTester;

  /// El tester activó Ohtli Insider en Cuenta (`users/{uid}.insiderEnabled`).
  final bool insiderEnabled;
  const FeatureAccess({
    this.features = const {},
    this.enrolledStudyIds = const {},
    this.enrolledStudies = const {},
    this.isLabMember = false,
    this.isTester = false,
    this.insiderEnabled = false,
  });

  /// Ohtli Insider se ve en el menú solo si es tester y lo activó.
  bool get showInsider => isTester && insiderEnabled;

  Set<String> get liveStudyIds => {
        for (final e in enrolledStudies.entries)
          if (e.value.status.featuresLive) e.key,
      };

  bool isOn(String key) {
    final f = features[key];
    if (f == null) return false;
    return featureVisible(feature: f, isLabMember: isLabMember, enrolledStudyIds: enrolledStudyIds, liveStudyIds: liveStudyIds);
  }

  /// Funciones en prueba que la persona tiene por sus estudios (para Logros).
  List<LabFeature> get myBetaFeatures => [
        for (final f in features.values)
          if (f.studyIds.any(enrolledStudyIds.contains) && f.stage != FeatureStage.desarrollo) f,
      ];
}

/// Puerta de las funcionalidades en prueba (docs/labs_estructura.md). La UI la usa para mostrar
/// u ocultar; las reglas de Firestore (`featureOn`) y el motor son los que protegen de verdad.
class OhtliFeatures {
  OhtliFeatures._();
  static final OhtliFeatures instance = OhtliFeatures._();

  final ValueNotifier<FeatureAccess> access = ValueNotifier(const FeatureAccess());
  final _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subs = [];
  final Map<String, StreamSubscription> _studySubs = {};
  String? _uid;
  bool _started = false;

  bool isOn(String key) => access.value.isOn(key);

  /// Activa u oculta Ohtli Insider para la cuenta.
  Future<void> setInsider(bool on) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({'insiderEnabled': on}, SetOptions(merge: true));
  }

  /// Se llama una vez al iniciar la app; sigue la sesión por su cuenta.
  void start() {
    if (_started) return;
    _started = true;
    FirebaseAuth.instance.authStateChanges().listen(_bind);
  }

  void _bind(User? user) {
    if (user?.uid == _uid && _subs.isNotEmpty) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final s in _studySubs.values) {
      s.cancel();
    }
    _studySubs.clear();
    _uid = user?.uid;
    access.value = FeatureAccess(isLabMember: user != null && isSuperUser(user));

    _subs.add(_db.collection('lab_features').snapshots().listen((s) {
      access.value = _copy(features: {for (final d in s.docs) d.id: LabFeature.fromDoc(d.id, d.data())});
    }, onError: (_) {}));
    if (user == null) return;

    _subs.add(_db.collection('lab_members').doc(user.uid).snapshots().listen((d) {
      final role = d.data()?['role'];
      access.value = _copy(
        isLabMember: isSuperUser(user) || role == 'researcher' || role == 'admin',
        isTester: role == 'tester' || role == 'researcher' || role == 'admin' || isSuperUser(user),
      );
    }, onError: (_) {}));

    _subs.add(_db.collection('users').doc(user.uid).snapshots().listen((d) {
      access.value = _copy(insiderEnabled: d.data()?['insiderEnabled'] == true);
    }, onError: (_) {}));

    _subs.add(_db
        .collection('lab_enrollments')
        .where('uid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((s) {
      final ids = {for (final d in s.docs) (d.data()['studyId'] ?? '').toString()};
      for (final gone in _studySubs.keys.where((k) => !ids.contains(k)).toList()) {
        _studySubs.remove(gone)?.cancel();
      }
      final studies = {...access.value.enrolledStudies}..removeWhere((k, _) => !ids.contains(k));
      access.value = _copy(enrolledStudyIds: ids, enrolledStudies: studies);
      for (final id in ids) {
        _studySubs.putIfAbsent(
          id,
          () => _db.collection('lab_studies').doc(id).snapshots().listen((d) {
            if (!d.exists) return;
            access.value = _copy(enrolledStudies: {...access.value.enrolledStudies, id: LabResearchStudy.fromDoc(id, d.data()!)});
          }, onError: (_) {}),
        );
      }
    }, onError: (_) {}));
  }

  FeatureAccess _copy({
    Map<String, LabFeature>? features,
    Set<String>? enrolledStudyIds,
    Map<String, LabResearchStudy>? enrolledStudies,
    bool? isLabMember,
    bool? isTester,
    bool? insiderEnabled,
  }) {
    final a = access.value;
    return FeatureAccess(
      features: features ?? a.features,
      enrolledStudyIds: enrolledStudyIds ?? a.enrolledStudyIds,
      enrolledStudies: enrolledStudies ?? a.enrolledStudies,
      isLabMember: isLabMember ?? a.isLabMember,
      isTester: isTester ?? a.isTester,
      insiderEnabled: insiderEnabled ?? a.insiderEnabled,
    );
  }
}

/// Muestra [child] solo si la funcionalidad [featureKey] está disponible para la sesión.
///
///   FeatureGate(featureKey: 'viaje_con_ia', child: BotonNuevo(), fallback: BotonActual())
class FeatureGate extends StatelessWidget {
  final String featureKey;
  final Widget child;
  final Widget fallback;
  const FeatureGate({super.key, required this.featureKey, required this.child, this.fallback = const SizedBox.shrink()});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FeatureAccess>(
        valueListenable: OhtliFeatures.instance.access,
        builder: (_, a, _) => a.isOn(featureKey) ? child : fallback,
      );
}

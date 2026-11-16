import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/editorial.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import 'trip_editor_page.dart';
import 'trip_viewer_page.dart';

/// Administración de las notas de versión: el superusuario las crea, edita y ve aquí
/// (ya no desde el editor de viajes). Cada nota se cuenta como una crónica de viaje.
class ReleaseNotesAdminPage extends StatefulWidget {
  const ReleaseNotesAdminPage({super.key});

  @override
  State<ReleaseNotesAdminPage> createState() => _ReleaseNotesAdminPageState();
}

class _ReleaseNotesAdminPageState extends State<ReleaseNotesAdminPage> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  bool _busy = false;

  Stream<List<Trip>> get _notes => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('trips')
      .where('kind', isEqualTo: kTripKindReleaseNotes)
      .snapshots()
      .map((s) => s.docs.map((d) => Trip.fromMap(d.data(), d.id)).toList()..sort(_byVersionDesc));

  static int _byVersionDesc(Trip a, Trip b) {
    final c = compareVersions(b.version ?? '', a.version ?? '');
    return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
  }

  bool get _isDark => OhtliSettings.instance.isDarkMode;

  @override
  void initState() {
    super.initState();
    _clearCoAuthors();
  }

  /// Las notas de versión solo las escribe el administrador. Si alguna quedó con
  /// coautores (p. ej. copiados de un borrador), se le quitan.
  Future<void> _clearCoAuthors() async {
    if (_uid == null || !isSuperUser()) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('trips')
          .where('kind', isEqualTo: kTripKindReleaseNotes)
          .get();
      for (final d in snap.docs) {
        final ids = d.data()['coAuthorIds'];
        if (ids is List && ids.isNotEmpty) {
          await d.reference.update({'coAuthorIds': <String>[], 'coAuthorNames': <String>[]});
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Crear
  // ---------------------------------------------------------------------------
  Future<void> _newNote(List<Trip> existing) async {
    final current = existing.where((t) => t.version == kAppVersion).toList();
    if (current.isNotEmpty) {
      // Una nota por versión: se edita la que ya existe.
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Ya existe la nota de la v$kAppVersion', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Text(
              'Solo hay una nota por versión. Para contar algo más de esta versión, edita «${current.first.title.trim().isEmpty ? 'Sin título' : current.first.title.trim()}». '
              'Al subir la versión de la app (config/app_version.dart) podrás crear la siguiente.',
              style: GoogleFonts.inter(fontSize: 13.5, height: 1.4),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Editarla'),
            ),
          ],
        ),
      );
      if (open == true && mounted) _edit(current.first);
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewNoteSheet(isDark: _isDark),
    );
    if (!mounted || choice == null) return;
    if (choice == 'blank') {
      await _createBlank();
    } else {
      final source = await _pickSource();
      if (source != null && mounted) await _createFrom(source);
    }
  }

  Trip _baseNote(String id, {String title = '', String description = '', String coverUrl = '', DateTime? date}) {
    final now = DateTime.now();
    return Trip(
      id: id,
      userId: _uid!,
      title: title,
      description: description,
      coverUrl: coverUrl,
      status: 'draft',
      visibility: 'private',
      createdAt: now,
      updatedAt: now,
      travelDate: date ?? now,
      kind: kTripKindReleaseNotes,
      version: kAppVersion,
    );
  }

  DocumentReference<Map<String, dynamic>> _ref(String id) =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection('trips').doc(id);

  Future<void> _createBlank() async {
    setState(() => _busy = true);
    try {
      final id = _ref('x').parent.doc().id;
      final note = _baseNote(id, title: 'Novedades de Ohtli v$kAppVersion');
      await _ref(id).set(note.toMap());
      if (mounted) _edit(note);
    } catch (e) {
      _error(e, 'No se pudo crear la nota.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Viajes propios y en los que eres coautor, para partir de su texto.
  Future<List<Trip>> _loadSources() async {
    final uid = _uid!;
    final own = await TripService().getTripsStream(uid).first;
    List<Trip> shared = [];
    try {
      final snap = await FirebaseFirestore.instance.collectionGroup('trips').where('coAuthorIds', arrayContains: uid).get();
      shared = snap.docs.map((d) => Trip.fromMap(d.data(), d.id)).toList();
    } catch (_) {}
    final all = {for (final t in [...own, ...shared]) '${t.userId}/${t.id}': t}.values.where((t) => !t.isReleaseNotes).toList();
    all.sort((a, b) {
      final da = a.status == 'published' ? 1 : 0, db = b.status == 'published' ? 1 : 0;
      return da != db ? da.compareTo(db) : b.updatedAt.compareTo(a.updatedAt);
    });
    return all;
  }

  Future<Trip?> _pickSource() {
    final future = _loadSources();
    final bool isDark = _isDark;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    return showDialog<Trip>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('¿De qué borrador partimos?', style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: fg))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                Text('Se copia su portada, texto e imágenes a una nota nueva de la v$kAppVersion. El original no cambia.',
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: sub)),
                const SizedBox(height: 12),
                Flexible(
                  child: FutureBuilder<List<Trip>>(
                    future: future,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(30),
                          child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
                        );
                      }
                      final trips = snap.data!;
                      if (trips.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No tienes borradores ni viajes.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: sub)),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: trips.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final t = trips[i];
                          return Material(
                            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF3F6F5),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(ctx, t),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 64,
                                        height: 48,
                                        child: t.coverUrl.startsWith('http')
                                            ? Image.network(t.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: OhtliColors.stormyTeal))
                                            : const ColoredBox(color: OhtliColors.stormyTeal, child: Icon(Icons.map_rounded, color: Colors.white70)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(t.title.trim().isEmpty ? 'Sin título' : t.title.trim(),
                                              maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                                          const SizedBox(height: 2),
                                          Text('${t.status == 'published' ? 'Publicado' : 'Borrador'} · ${_fmtDate(t.updatedAt)}',
                                              style: GoogleFonts.inter(fontSize: 12, color: sub)),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded, color: sub),
                                  ],
                                ),
                              ),
                            ),
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
      ),
    );
  }

  /// Copia una imagen de Storage a la carpeta de la nota; si no se puede, deja la original.
  Future<String> _copyImage(String url, String noteId, String name) async {
    if (!url.startsWith('http') || !url.contains('firebasestorage')) return url;
    try {
      final src = FirebaseStorage.instance.refFromURL(url);
      final bytes = await src.getData(15 * 1024 * 1024);
      if (bytes == null) return url;
      String type = 'image/jpeg';
      try {
        type = (await src.getMetadata()).contentType ?? type;
      } catch (_) {}
      if (!type.startsWith('image/')) type = 'image/jpeg';
      final dst = FirebaseStorage.instance.ref('users/$_uid/trips/$noteId/$name');
      await dst.putData(bytes, SettableMetadata(contentType: type));
      return await dst.getDownloadURL();
    } catch (_) {
      return url;
    }
  }

  Future<void> _createFrom(Trip source) async {
    setState(() => _busy = true);
    try {
      final id = _ref('x').parent.doc().id;
      final content = await TripService().getTripContent(source.userId, source.id);
      int n = 0;
      String file(String url) {
        final m = RegExp(r'\.(png|webp|gif|jpe?g)(\?|$)', caseSensitive: false).firstMatch(url);
        return 'sections/copia_${DateTime.now().millisecondsSinceEpoch}_${n++}.${m?.group(1)?.toLowerCase() ?? 'jpg'}';
      }

      final sections = <TripSection>[];
      for (final s in content?.sections ?? const <TripSection>[]) {
        final map = Map<String, dynamic>.from(s.toMap());
        for (final key in ['imageUrl', 'mainPhotoUrl', 'coverUrl']) {
          final v = map[key];
          if (v is String && v.isNotEmpty) map[key] = await _copyImage(v, id, file(v));
        }
        final extra = map['secondaryPhotoUrls'];
        if (extra is List) {
          map['secondaryPhotoUrls'] = [for (final u in extra) u is String && u.isNotEmpty ? await _copyImage(u, id, file(u)) : u];
        }
        sections.add(TripSection.fromMap(map));
      }
      final cover = source.coverUrl.isEmpty ? '' : await _copyImage(source.coverUrl, id, 'cover.jpg');
      final base = _baseNote(id, title: source.title, description: source.description, coverUrl: cover, date: source.travelDate);
      // Sin coautores: las notas de versión solo las escribe el administrador.
      final note = base;
      await _ref(id).set(note.toMap());
      await TripService().updateTripContent(_uid!, id, TripContent(sections: sections));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nota de la v$kAppVersion creada a partir de «${source.title.trim()}».', style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.stormyTeal,
        behavior: SnackBarBehavior.floating,
      ));
      _edit(note);
    } catch (e) {
      _error(e, 'No se pudo crear la nota a partir del borrador.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(Object e, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(e, fallback: fallback), style: GoogleFonts.inter()), backgroundColor: OhtliColors.warning),
    );
  }

  void _edit(Trip t) => Navigator.push(context, MaterialPageRoute(builder: (_) => TripEditorPage(trip: t)));
  void _view(Trip t) => Navigator.push(context, MaterialPageRoute(builder: (_) => TripViewerPage(trip: t, tripId: t.id, authorId: t.userId)));

  // ---------------------------------------------------------------------------
  // Vista
  // ---------------------------------------------------------------------------
  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  static String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String _plain(String md) => md
      .replaceAll(RegExp(r'\[![A-Z]+\]'), '')
      .replaceAll(RegExp(r'[#>*_`~|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final bool isDark = _isDark;
    final Color bg = isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    if (!isSuperUser() || _uid == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(child: Text('Esta sección es solo para el administrador de Ohtli.', style: GoogleFonts.inter(color: fg))),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: fg,
        title: Text('Notas de versión', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: fg)),
      ),
      body: StreamBuilder<List<Trip>>(
        stream: _notes,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(friendlyError(snap.error!, fallback: 'No se pudieron cargar las notas.'), style: GoogleFonts.inter(color: sub)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          final notes = snap.data!;
          final bool hasCurrent = notes.any((t) => t.version == kAppVersion);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                children: [
                  _buildIntro(notes, hasCurrent, fg, sub, isDark),
                  const SizedBox(height: 18),
                  if (notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text('Todavía no hay notas de versión.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: sub)),
                    ),
                  for (final t in notes) ...[
                    _buildNoteCard(t, isDark, fg, sub),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIntro(List<Trip> notes, bool hasCurrent, Color fg, Color sub, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OhtliColors.stormyTeal, OhtliColors.stormyTeal.withValues(alpha: 0.82), OhtliColors.accent.withValues(alpha: 0.9)],
        ),
        boxShadow: [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.luggage_rounded, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text('BITÁCORA DE OHTLI · VERSIÓN ACTUAL v$kAppVersion',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white70)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Cada versión es un tramo del viaje',
                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, height: 1.15)),
                const SizedBox(height: 4),
                Text(
                  hasCurrent
                      ? 'La nota de la v$kAppVersion ya está en marcha. Al publicarla (pública) aparece destacada en Explorar.'
                      : 'Aún no hay nota para la v$kAppVersion. Escríbela como una crónica: portada, un texto que la cuente y sus novedades.',
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: Colors.white.withValues(alpha: 0.88)),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _newNote(notes),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: OhtliColors.stormyTeal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: const StadiumBorder(),
            ),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal))
                : const Icon(Icons.add_rounded, size: 18),
            label: Text(hasCurrent ? 'Nota de la v$kAppVersion' : 'Nueva nota de versión', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(Trip t, bool isDark, Color fg, Color sub) {
    final bool published = t.status == 'published';
    final bool public = published && t.visibility == 'public';
    final bool current = t.version == kAppVersion;
    final String excerpt = _plain(t.description);
    final bool hasCover = t.coverUrl.startsWith('http');
    Widget pill(String text, Color color, {IconData? icon, bool solid = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: solid ? color : Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: solid ? null : Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 5)],
              Text(text, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        );

    return Material(
      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => _view(t),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover)
                    Image.network(t.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: OhtliColors.stormyTeal))
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [OhtliColors.stormyTeal, OhtliColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.45, 1],
                        colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    right: 14,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        pill('Notas de versión · v${t.version ?? '—'}', OhtliColors.stormyTeal, icon: Icons.new_releases_rounded, solid: true),
                        if (current) pill('Versión actual', OhtliColors.accent, solid: true),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 14,
                    child: Text(
                      t.title.trim().isEmpty ? 'Sin título' : t.title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (excerpt.isNotEmpty) ...[
                    Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: fg.withValues(alpha: 0.85))),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (public ? OhtliColors.stormyTeal : OhtliColors.accent).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          public ? 'Publicada · en Explorar' : (published ? 'Publicada · privada' : 'Borrador'),
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: public ? OhtliColors.stormyTeal : OhtliColors.accent),
                        ),
                      ),
                      Text('Actualizada el ${_fmtDate(t.updatedAt)}', style: GoogleFonts.inter(fontSize: 12, color: sub)),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: () => _view(t),
                        style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.visibility_outlined, size: 17),
                        label: Text('Ver', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                      ),
                      FilledButton.icon(
                        onPressed: () => _edit(t),
                        style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: Text('Editar', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                      ),
                    ],
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

/// Hoja "Nueva nota de versión": en blanco o a partir de un borrador.
class _NewNoteSheet extends StatelessWidget {
  final bool isDark;
  const _NewNoteSheet({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    Widget option(String value, IconData icon, String title, String text) => Material(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F6F5),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(context, value),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(icon, color: OhtliColors.stormyTeal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: fg)),
                        const SizedBox(height: 2),
                        Text(text, style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: sub)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: sub),
                ],
              ),
            ),
          ),
        );
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E22) : Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Nueva nota · v$kAppVersion', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: fg)),
                const SizedBox(height: 12),
                option('draft', Icons.history_edu_rounded, 'A partir de un borrador', 'Usa el texto, la portada y las imágenes de un viaje o borrador tuyo.'),
                const SizedBox(height: 8),
                option('blank', Icons.note_add_outlined, 'En blanco', 'Empieza con la portada y el texto vacíos.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compara versiones "1.10.0" > "1.9.2" (las partes que no son número cuentan como 0).
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (int i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

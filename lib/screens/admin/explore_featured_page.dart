import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/admin.dart';
import '../../services/explore_config_service.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../explore/explore_page.dart' show kPinnedStories;

/// El superusuario elige qué viajes públicos aparecen en el bloque principal de Explorar
/// y si la nota de versión actual se muestra ahí para todos.
class ExploreFeaturedPage extends StatefulWidget {
  const ExploreFeaturedPage({super.key});

  @override
  State<ExploreFeaturedPage> createState() => _ExploreFeaturedPageState();
}

class _ExploreFeaturedPageState extends State<ExploreFeaturedPage> {
  List<FeaturedTrip> _pinned = [];
  bool _showReleaseNotes = true;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  late final Future<List<FeaturedTrip>> _candidates = _loadPublicTrips();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ExploreConfigService.load();
    var pinned = config.pinned;
    // Primera vez: parte de los destacados que hoy ve la gente
    pinned ??= await Future.wait(kPinnedStories.map((p) async {
      String title = '';
      try {
        final d = await FirebaseFirestore.instance.collection('users').doc(p.authorId).collection('trips').doc(p.tripId).get();
        title = (d.data()?['title'] ?? '').toString();
      } catch (_) {}
      return FeaturedTrip(tripId: p.tripId, authorId: p.authorId, title: title);
    }));
    if (!mounted) return;
    setState(() {
      _pinned = List.of(pinned!);
      _showReleaseNotes = config.showReleaseNotes;
      _loading = false;
    });
  }

  /// Viajes públicos más recientes (misma consulta que el feed de Explorar).
  Future<List<FeaturedTrip>> _loadPublicTrips() async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('trips')
        .where('status', isEqualTo: 'published')
        .where('visibility', isEqualTo: 'public')
        .orderBy('updatedAt', descending: true)
        .limit(40)
        .get()
        .timeout(const Duration(seconds: 15));
    return snap.docs
        .where((d) => d.data()['isSurprise'] != true && d.data()['kind'] != 'release_notes')
        .map((d) => FeaturedTrip(
              tripId: d.id,
              authorId: (d.data()['userId'] ?? d.reference.parent.parent?.id ?? '').toString(),
              title: (d.data()['title'] ?? 'Viaje sin título').toString(),
            ))
        .where((t) => t.authorId.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ExploreConfigService.save(pinned: _pinned, showReleaseNotes: _showReleaseNotes);
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Explorar se actualizó para todos.', style: GoogleFonts.inter()), backgroundColor: OhtliColors.stormyTeal),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo guardar.'), style: GoogleFonts.inter()), backgroundColor: OhtliColors.warning),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _change(VoidCallback fn) => setState(() {
        fn();
        _dirty = true;
      });

  Widget _section(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.6))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final bg = isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer;
    final card = isDark ? const Color(0xFF1E1E22) : Colors.white;
    if (!isSuperUser()) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(child: Text('Esta sección es solo para el administrador de Ohtli.', style: GoogleFonts.inter(color: OhtliColors.onyx))),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OhtliColors.onyx,
        title: Text('Destacados de Explorar', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _dirty && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.publish_rounded, size: 18),
              label: Text(_dirty ? 'Publicar cambios' : 'Sin cambios'),
              style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white, elevation: 0),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  children: [
                    Container(
                      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                      child: SwitchListTile(
                        value: _showReleaseNotes,
                        onChanged: (v) => _change(() => _showReleaseNotes = v),
                        activeColor: OhtliColors.stormyTeal,
                        title: Text('Mostrar la nota de versión', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                        subtitle: Text('Va primero en el bloque principal de Explorar para todos los usuarios.',
                            style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.6))),
                      ),
                    ),
                    _section('Viajes destacados', 'Aparecen en este orden después de la nota de versión.'),
                    if (_pinned.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No hay viajes destacados. Elige alguno de la lista de abajo.',
                            style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withValues(alpha: 0.6))),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            for (int i = 0; i < _pinned.length; i++)
                              ListTile(
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
                                  child: Text('${i + 1}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
                                ),
                                title: Text(_pinned[i].title.isEmpty ? 'Viaje ${_pinned[i].tripId.substring(0, 6)}' : _pinned[i].title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Subir',
                                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                                      onPressed: i == 0 ? null : () => _change(() => _pinned.insert(i - 1, _pinned.removeAt(i))),
                                    ),
                                    IconButton(
                                      tooltip: 'Bajar',
                                      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                      onPressed: i == _pinned.length - 1 ? null : () => _change(() => _pinned.insert(i + 1, _pinned.removeAt(i))),
                                    ),
                                    IconButton(
                                      tooltip: 'Quitar de destacados',
                                      icon: const Icon(Icons.close_rounded, size: 18, color: OhtliColors.warning),
                                      onPressed: () => _change(() => _pinned.removeAt(i)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    _section('Viajes públicos recientes', 'Elige cuáles destacar.'),
                    FutureBuilder<List<FeaturedTrip>>(
                      future: _candidates,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Text(friendlyError(snap.error!, fallback: 'No se pudieron cargar los viajes públicos.'),
                              style: GoogleFonts.inter(color: OhtliColors.warningText));
                        }
                        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                        final pinnedIds = _pinned.map((p) => p.tripId).toSet();
                        final available = snap.data!.where((t) => !pinnedIds.contains(t.tripId)).toList();
                        if (available.isEmpty) {
                          return Text('No hay más viajes públicos por destacar.', style: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.6)));
                        }
                        return Container(
                          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: available
                                .map((t) => ListTile(
                                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: OhtliColors.onyx)),
                                      trailing: TextButton.icon(
                                        onPressed: () => _change(() => _pinned.add(t)),
                                        icon: const Icon(Icons.push_pin_outlined, size: 16),
                                        label: const Text('Destacar'),
                                      ),
                                    ))
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

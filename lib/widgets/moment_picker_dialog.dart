import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/profile_moment.dart';
import '../models/trip_model.dart';
import '../services/trip_service.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';
import 'trip_polaroid.dart';

/// Elegir las fotos de tus viajes que se muestran como «Momentos» en tu perfil.
/// Devuelve la lista nueva o null si se cancela.
class MomentPickerDialog extends StatefulWidget {
  final List<Trip> trips;
  final List<ProfileMoment> current;

  const MomentPickerDialog({super.key, required this.trips, required this.current});

  static Future<List<ProfileMoment>?> show(BuildContext context, {required List<Trip> trips, required List<ProfileMoment> current}) {
    return showDialog<List<ProfileMoment>>(
      context: context,
      builder: (_) => MomentPickerDialog(trips: trips, current: current),
    );
  }

  @override
  State<MomentPickerDialog> createState() => _MomentPickerDialogState();
}

class _MomentPickerDialogState extends State<MomentPickerDialog> {
  late final List<ProfileMoment> _selected = [...widget.current];
  final Map<String, List<({String url, String caption})>> _photos = {};

  @override
  void initState() {
    super.initState();
    for (final t in widget.trips.take(30)) {
      _photos[t.id] = momentCandidates(t, null);
      TripService().getTripContent(t.userId, t.id).then((content) {
        if (mounted) setState(() => _photos[t.id] = momentCandidates(t, content));
      }).catchError((Object e) {
        debugPrint('[Momentos] fotos de ${t.id}: $e');
      });
    }
  }

  bool _isSelected(String url) => _selected.any((m) => m.url == url);

  void _toggle(Trip trip, ({String url, String caption}) photo) {
    setState(() {
      if (_isSelected(photo.url)) {
        _selected.removeWhere((m) => m.url == photo.url);
      } else if (_selected.length < ProfileMoment.maxMoments) {
        _selected.add(ProfileMoment(
          url: photo.url,
          tripId: trip.id,
          tripTitle: trip.title,
          caption: photo.caption == trip.title ? '' : photo.caption,
          date: trip.travelDate ?? trip.createdAt,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final full = _selected.length >= ProfileMoment.maxMoments;
    return Dialog(
      backgroundColor: OhtliColors.cloudDancer,
      insetPadding: EdgeInsets.all(size.width < 600 ? 12 : 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OhtliUi.radiusLarge)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 820, maxHeight: size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: OhtliSectionHeader(
                      eyebrow: 'Momentos',
                      icon: Icons.favorite_rounded,
                      color: OhtliColors.cempasuchil,
                      title: 'Elige lo que quieres atesorar',
                      subtitle: 'Si el viaje es privado, en tu perfil solo se verá la foto.',
                    ),
                  ),
                  IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: widget.trips.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: OhtliEmptyState(
                        icon: Icons.photo_library_outlined,
                        title: 'Aún no tienes viajes',
                        message: 'Cuando armes o publiques un viaje podrás elegir sus fotos como momentos.',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      children: [
                        for (final trip in widget.trips.take(30))
                          if ((_photos[trip.id] ?? const []).isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 14, bottom: 10),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(trip.title.isEmpty ? 'Viaje sin título' : trip.title,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!(trip.status == 'published' && trip.visibility == 'public'))
                                    const OhtliMetaPill(icon: Icons.lock_outline_rounded, label: 'Privado'),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final p in _photos[trip.id]!)
                                  _Thumb(
                                    url: p.url,
                                    selected: _isSelected(p.url),
                                    disabled: full && !_isSelected(p.url),
                                    onTap: () => _toggle(trip, p),
                                  ),
                              ],
                            ),
                          ],
                      ],
                    ),
            ),
            // Orden en el perfil: se arrastran para acomodarlos.
            if (_selected.length > 1)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: OhtliColors.cardBorder))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ORDEN EN TU PERFIL · ARRASTRA PARA ACOMODAR', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 72,
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemCount: _selected.length,
                        onReorderItem: (from, to) => setState(() => _selected.insert(to, _selected.removeAt(from))),
                        proxyDecorator: (child, _, _) => Material(color: Colors.transparent, elevation: 6, borderRadius: BorderRadius.circular(12), child: child),
                        itemBuilder: (context, i) {
                          final m = _selected[i];
                          return ReorderableDragStartListener(
                            key: ValueKey(m.url),
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Stack(
                                  children: [
                                    ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 72, height: 72, child: OhtliPhoto(m.url))),
                                    Positioned(
                                      left: 4,
                                      top: 4,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                                        child: Text('${i + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: OhtliColors.cardBorder))),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_selected.length} de ${ProfileMoment.maxMoments} momentos',
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
                  ),
                  OhtliSecondaryButton(compact: true, label: 'Cancelar', onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  OhtliPrimaryButton(compact: true, highlight: true, label: 'Guardar', icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, _selected)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _Thumb({required this.url, required this.selected, required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? 'Quitar de momentos' : 'Agregar a momentos',
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: MouseRegion(
          cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: disabled ? 0.4 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 112,
              height: 112,
              padding: EdgeInsets.all(selected ? 4 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? OhtliColors.cempasuchil : Colors.transparent, width: 3),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: OhtliPhoto(url)),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: OhtliColors.cempasuchil, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

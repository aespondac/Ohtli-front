import '../models/poi_model.dart';
import '../models/trip_model.dart';

/// Forma de la ruta a partir de lo elegido en el asistente: 'anillo' (ida y vuelta) o, en la
/// abierta, los extremos que se fijaron ('inicio', 'fin' o 'ambos').
String routeShapeOf(String topology, String openEnds) => topology == 'anillo' ? 'anillo' : openEnds;

/// Paradas con las que arranca un plan hecho a mano: el punto de partida y, según la forma,
/// el regreso al mismo punto (ida y vuelta) o el punto de llegada. Las demás las agrega la
/// persona en el editor.
List<TripSection> manualPlanSections({
  required String routeShape,
  String originName = '',
  Map<String, double>? origin,
  String destinationName = '',
  Map<String, double>? destination,
  Poi? originPoi,
  required String Function(String tag) newId,
}) {
  final out = <TripSection>[];
  final bool fixesStart = routeShape != 'fin';
  final bool fixesEnd = routeShape == 'fin' || routeShape == 'ambos';
  final name = originName.trim();

  PlaceSection point(String tag, String title, Map<String, double> c, String description) => PlaceSection(
        id: newId(tag),
        title: title,
        description: description,
        rating: 0,
        mainPhotoUrl: '',
        secondaryPhotoUrls: const [],
        lat: c['lat'],
        lng: c['lng'],
      );

  PlaceSection? start;
  if (fixesStart && origin != null) {
    final poi = originPoi;
    if (poi != null && poi.name == name) {
      // Si se empieza en un lugar del catálogo, la parada trae su ficha.
      start = PlaceSection(
        id: newId('start'),
        title: poi.name,
        description: poi.cleanNarrative,
        rating: 0,
        mainPhotoUrl: poi.imageUrl,
        secondaryPhotoUrls: const [],
        cost: poi.priceMxnAvg ?? (poi.priceLevel * 60.0),
        currency: 'MXN',
        lat: poi.location.isValid ? poi.location.lat : origin['lat'],
        lng: poi.location.isValid ? poi.location.lng : origin['lng'],
        poiId: poi.poiId.isNotEmpty ? poi.poiId : null,
        poiSource: poi.poiId.isNotEmpty ? kPlaceSourceCatalog : null,
      );
    } else {
      start = point('start', name.isEmpty ? 'Punto de partida' : name, origin, 'Punto de partida');
    }
    out.add(start);
  }

  if (routeShape == 'anillo' && start != null && origin != null) {
    out.add(point('end', start.title, origin, 'Regreso al punto de partida'));
  } else if (fixesEnd && destination != null) {
    final d = destinationName.trim();
    out.add(point('end', d.isEmpty ? 'Punto de llegada' : d, destination, 'Punto de llegada'));
  }
  return out;
}

/// Título inicial de un plan hecho a mano.
String manualPlanTitle({required String routeShape, String originName = '', String destinationName = ''}) {
  final o = originName.trim();
  final d = destinationName.trim();
  if (routeShape != 'fin' && o.isNotEmpty) return 'Ruta desde $o';
  if (d.isNotEmpty) return 'Ruta hacia $d';
  return 'Nuevo viaje';
}

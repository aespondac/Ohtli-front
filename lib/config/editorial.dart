/// Configuración editorial de Ohtli.
///
/// Cuentas del equipo que pueden publicar notas de versión. Solo sus
/// publicaciones de tipo 'release_notes' se destacan en Explorar, así nadie más
/// puede colarse en la portada marcando un viaje como "notas de versión".
const List<String> kEditorialTeamUids = [
  '4cavo5EKn6Vvuoo2s46VokEj7lE3',
];

bool isEditorialTeam(String? uid) => uid != null && kEditorialTeamUids.contains(uid);

/// Cuántas notas de versión recientes se muestran en el carrusel de Explorar.
const int kFeaturedReleaseNotes = 2;

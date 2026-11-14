/// Configuración editorial de Ohtli.
///
/// Las notas de versión solo las publica el superusuario (ver config/admin.dart y
/// firestore.rules), y solo para la versión actual de la app (config/app_version.dart).
/// En Explorar solo se destacan las suyas, así nadie más puede colarse en la portada
/// marcando un viaje como "notas de versión".
library;

export 'admin.dart' show isSuperUser, kSuperUserEmail, SuperUserDirectory;
export 'app_version.dart' show kAppVersion;

/// Cuántas notas de versión recientes se muestran en el carrusel de Explorar.
const int kFeaturedReleaseNotes = 2;

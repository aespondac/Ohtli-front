/// Pantallas de viajes (editor, viaje publicado, Mis viajes y planificador). Son lo más
/// pesado de la app, así que el resto la importa con `deferred as trips`: su código se
/// descarga la primera vez que se abre una de ellas (o en la precarga tras el arranque).
library;

export 'group_trip_page.dart' show GroupTripPage;
export 'release_notes_admin_page.dart' show ReleaseNotesAdminPage;
export 'trip_editor_page.dart' show TripEditorPage;
export 'trip_planner_page.dart' show TripPlannerPage;
export 'trip_viewer_page.dart' show TripViewerPage;
export 'trips_dashboard_page.dart' show TripsDashboardPage;

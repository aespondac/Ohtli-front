/// Ruteo por segmentos de la URL (web).
///
/// Antes las rutas se detectaban con `path.contains('/eval')`, así que
/// `/news/evaluacion-con-usuarios` abría la pantalla de evaluación y `/news/lugares-…`
/// la de lugares. Aquí una ruta coincide solo si sus segmentos son el inicio exacto de
/// la ruta de la URL (o del fragmento, para los enlaces antiguos con `#/`).
library;

List<String> _segments(String raw) {
  var p = raw;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  return p.split('/').where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
}

/// `route` (p. ej. `/news` o `/labs/osrm`) coincide con `path` o con `fragment` si sus
/// segmentos son prefijo: `/news` coincide con `/news` y `/news/mi-articulo`, no con
/// `/newsletter` ni con `/labs/news`.
bool routeMatches(String route, {required String path, String fragment = ''}) {
  final want = _segments(route);
  if (want.isEmpty) return false;
  bool prefixOf(String raw) {
    final segs = _segments(raw);
    if (segs.length < want.length) return false;
    for (var i = 0; i < want.length; i++) {
      if (segs[i] != want[i]) return false;
    }
    return true;
  }

  return prefixOf(path) || prefixOf(fragment);
}

/// Ruta del artículo en `/news/<ruta>` (o `#/news/<ruta>`), o null.
String? newsSlugFrom({required String path, String fragment = ''}) {
  for (final raw in [path, fragment]) {
    final segs = raw.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length >= 2 && segs[0].toLowerCase() == 'news' && RegExp(r'^[A-Za-z0-9-]+$').hasMatch(segs[1])) {
      return segs[1];
    }
  }
  return null;
}

/// Título de la pestaña según el sitio.
String appTitleForHost(String host) {
  final h = host.toLowerCase();
  if (h == 'labs.ohtli.quest' || h == 'lab.ohtli.quest') return 'Ohtli Labs';
  if (h == 'api.ohtli.quest') return 'Ohtli API';
  return 'Ohtli | El viaje empieza aquí';
}

/// Nombre legible de un subdominio de Ohtli (para "Inicia sesión para continuar en …").
String siteNameForHost(String host) {
  final h = host.toLowerCase();
  if (h == 'labs.ohtli.quest' || h == 'lab.ohtli.quest') return 'Ohtli Labs';
  if (h == 'api.ohtli.quest') return 'Ohtli API';
  return h;
}

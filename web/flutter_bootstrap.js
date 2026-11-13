{{flutter_js}}
{{flutter_build_config}}

// Sin serviceWorkerSettings: el flutter_service_worker.js de Flutter 3.44 solo se desregistra
// y eliminaría el service worker propio de Ohtli (ohtli_sw.js), que es el que da soporte sin conexión.
_flutter.loader.load();

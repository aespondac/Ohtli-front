// Service worker de Ohtli: permite abrir la PWA sin conexión (CA-05).
// Flutter 3.44 ya no genera un service worker con caché (su flutter_service_worker.js solo se
// desregistra), por lo que la app no cargaba al recargarla sin red.
//
// Estrategias:
//  - Contenido propio del sitio (HTML, JS, assets): red primero; sin conexión, la copia en caché.
//  - CanvasKit y fuentes (CDNs de Google): caché primero, porque no cambian entre versiones.
//  - Firestore, Auth, App Check, la API del motor y mapas: nunca se cachean aquí; los datos
//    sin conexión los provee la persistencia de Firestore en IndexedDB.
'use strict';

const SHELL_CACHE = 'ohtli-shell-v1';
const CDN_CACHE = 'ohtli-cdn-v1';
const PRECACHE = ['/', '/index.html', '/flutter_bootstrap.js', '/main.dart.js', '/manifest.json', '/favicon.png'];
const CDN_HOSTS = ['www.gstatic.com', 'fonts.gstatic.com', 'fonts.googleapis.com'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((cache) => cache.addAll(PRECACHE))
      .catch((e) => console.warn('[ohtli_sw] precache incompleto', e))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keep = new Set([SHELL_CACHE, CDN_CACHE]);
    for (const key of await caches.keys()) {
      if (!keep.has(key)) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

async function networkFirst(request, cacheKey) {
  const cache = await caches.open(SHELL_CACHE);
  try {
    const response = await fetch(request);
    if (response && response.ok) cache.put(cacheKey || request, response.clone());
    return response;
  } catch (err) {
    const cached = await cache.match(cacheKey || request, { ignoreSearch: true });
    if (cached) return cached;
    throw err;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CDN_CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && (response.ok || response.type === 'opaque')) cache.put(request, response.clone());
  return response;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (request.mode === 'navigate') {
    // Toda navegación (incluidas rutas con parámetros, p. ej. ?tripId=...) sirve index.html sin red
    event.respondWith(networkFirst(request, '/index.html'));
    return;
  }
  if (url.origin === self.location.origin) {
    event.respondWith(networkFirst(request));
    return;
  }
  if (CDN_HOSTS.includes(url.hostname)) {
    event.respondWith(cacheFirst(request));
  }
  // Cualquier otro origen (Firestore, Auth, App Check, api.ohtli.quest, mapas) pasa directo a la red
});

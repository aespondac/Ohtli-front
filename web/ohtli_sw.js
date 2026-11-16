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
// main.dart.js no se precarga: los navegadores con WebAssembly usan main.dart.wasm. El código
// que sí se usa (wasm o js) se guarda solo con "red primero" la primera vez que se carga.
const PRECACHE = ['/', '/index.html', '/flutter_bootstrap.js', '/manifest.json', '/favicon.png'];
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

// Avisos push (FCM) con Ohtli cerrado o en segundo plano. Los manda functions/index.js como
// mensajes solo de datos: { title, body, url, tag, kind, icon, badge } (todo texto).
// Safari (WebKit) exige mostrar un aviso por cada push; los demás navegadores no lo piden si hay
// una pestaña de Ohtli a la vista, y ahí ya se ve el aviso flotante de la app (OhtliLiveAlerts).
const IS_WEBKIT = /Safari/.test(self.navigator.userAgent) && !/Chrome|Chromium|Edg|Android/.test(self.navigator.userAgent);

function pushData(event) {
  if (!event.data) return {};
  try {
    const raw = event.data.json();
    // FCM entrega { data: {...}, notification?: {...}, from, fcmMessageId }.
    const data = Object.assign({}, raw.data || {});
    if (raw.notification) {
      data.title = data.title || raw.notification.title;
      data.body = data.body || raw.notification.body;
    }
    return data;
  } catch (_) {
    return { body: event.data.text() };
  }
}

self.addEventListener('push', (event) => {
  const data = pushData(event);
  event.waitUntil((async () => {
    if (!IS_WEBKIT) {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      if (windows.some((c) => c.visibilityState === 'visible' && c.focused)) return;
    }
    const url = new URL(data.url || '/', self.location.origin).href;
    await self.registration.showNotification(data.title || 'Ohtli', {
      body: data.body || '',
      icon: data.icon || '/icons/Icon-192.png',
      badge: data.badge || '/icons/Icon-maskable-192.png',
      tag: data.tag || undefined,
      renotify: Boolean(data.tag),
      data: { url, kind: data.kind || '' },
    });
  })());
});

// Al tocar un aviso (push, llegada, salida, hora de salir): vuelve a la pestaña de Ohtli o la abre.
// Si Ohtli ya está abierto en otra pantalla, se le pide que vaya a la del aviso (PushService lo
// escucha) en lugar de recargar la pestaña, para no perder lo que se esté editando.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const same = windows.find((c) => c.url === url);
    if (same && 'focus' in same) return same.focus();
    const any = windows.find((c) => new URL(c.url).origin === self.location.origin);
    if (any && 'focus' in any) {
      any.postMessage({ type: 'ohtli:open', url });
      return any.focus();
    }
    return self.clients.openWindow(url);
  })());
});

// Bar Room Trivia - Progressive Web App Service Worker
const CACHE_NAME = 'bar-room-trivia-v2.1.0';
const STATIC_ASSETS = [
  './',
  './index.html',
  './app_logo.png',
  './manifest.webmanifest'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn('[PWA SW] Pre-cache partial fail (offline fallback still active):', err);
      });
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // 1. NEVER cache non-HTTP(S), WebSockets, realtime subscriptions, Supabase API, MQTT, or live Trivia APIs
  if (
    (url.protocol !== 'http:' && url.protocol !== 'https:') ||
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('emqx.io') ||
    url.hostname.includes('opentdb.com') ||
    url.hostname.includes('the-trivia-api.com') ||
    url.hostname.includes('googleapis.com') ||
    url.hostname.includes('gstatic.com') ||
    url.pathname.includes('/rest/v1/') ||
    url.pathname.includes('/realtime/v1/') ||
    url.pathname.includes('/auth/v1/') ||
    event.request.method !== 'GET'
  ) {
    return;
  }

  // 2. Network-first strategy for navigation, HTML, JS, and CSS so updates load immediately
  const isCodeOrDocument = (
    event.request.mode === 'navigate' ||
    event.request.destination === 'document' ||
    event.request.destination === 'script' ||
    event.request.destination === 'style' ||
    url.pathname.endsWith('.html') ||
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.css')
  );

  if (isCodeOrDocument) {
    event.respondWith(
      fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200 && networkResponse.type !== 'opaque') {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone)).catch(() => {});
          }
          return networkResponse;
        })
        .catch(() => {
          return caches.match(event.request).then((cached) =>
            cached || caches.match('./index.html').then((fallback) => fallback || new Response('Offline', { status: 503 }))
          );
        })
    );
    return;
  }

  // 3. Stale-While-Revalidate for images, icons, and static data
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200 && networkResponse.type !== 'opaque') {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone)).catch(() => {});
        }
        return networkResponse;
      }).catch(() => {
        return cachedResponse || new Response('', { status: 503 });
      });

      return cachedResponse || fetchPromise;
    })
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

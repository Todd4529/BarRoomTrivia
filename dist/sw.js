// Bar Room Trivia - Progressive Web App Service Worker
const CACHE_NAME = 'bar-room-trivia-v2.0.0';
const STATIC_ASSETS = [
  './',
  './index.html',
  './app_logo.png',
  './manifest.webmanifest'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[PWA SW] Pre-caching core UI shell');
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
            console.log('[PWA SW] Removing obsolete cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // 1. NEVER cache WebSockets, realtime subscriptions, Supabase API, or cross-origin external APIs
  if (
    url.protocol === 'ws:' ||
    url.protocol === 'wss:' ||
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('googleapis.com') ||
    url.hostname.includes('gstatic.com') ||
    url.pathname.includes('/rest/v1/') ||
    url.pathname.includes('/realtime/v1/') ||
    event.request.method !== 'GET'
  ) {
    return; // Pass through directly to live network
  }

  // 2. Network-first strategy for navigation, HTML, JS, and CSS so code updates load immediately
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
          if (networkResponse && networkResponse.status === 200) {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
          }
          return networkResponse;
        })
        .catch(() => {
          return caches.match(event.request).then((cached) => cached || caches.match('./index.html'));
        })
    );
    return;
  }

  // 3. Stale-While-Revalidate for images, icons, and fonts
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
        }
        return networkResponse;
      }).catch(() => {
        return cachedResponse;
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

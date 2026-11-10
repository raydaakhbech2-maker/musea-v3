const CACHE = 'musea-final-v22';
const CACHE_PREFIX = 'musea-final-';
const APP_SHELL = './index.html';

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    try {
      const response = await fetch(APP_SHELL, { cache: 'no-store' });
      if (response.ok) {
        const cache = await caches.open(CACHE);
        await cache.put(APP_SHELL, response);
      }
    } catch (error) {
      console.warn('MUSEA: cache initial indisponible, le réseau sera utilisé.', error);
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const freshRequest = new Request(request, { cache: 'no-store' });
        const response = await fetch(freshRequest);
        if (response && response.ok) {
          const cache = await caches.open(CACHE);
          await cache.put(APP_SHELL, response.clone());
        }
        return response;
      } catch (error) {
        const cached = await caches.match(APP_SHELL);
        if (cached) return cached;
        return new Response('MUSEA est temporairement indisponible. Vérifie ta connexion puis actualise la page.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' }
        });
      }
    })());
  }
});

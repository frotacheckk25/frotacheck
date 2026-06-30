'use strict';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // 1. Collect window clients BEFORE unregistering — after unregister the SW no
      //    longer controls clients, so matchAll() (without includeUncontrolled) returns [].
      let windowClients = [];
      try {
        windowClients = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true,
        });
      } catch (e) {
        console.warn('[SW] Failed to get clients:', e);
      }

      // 2. Clear ALL caches so stale main.dart.js is removed from CacheStorage.
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((k) => caches.delete(k)));
      } catch (e) {
        console.warn('[SW] Failed to clear caches:', e);
      }

      // 3. Unregister this service worker so future loads go straight to the network.
      try {
        await self.registration.unregister();
      } catch (e) {
        console.warn('[SW] Failed to unregister:', e);
      }

      // 4. Reload all open windows — they now have no SW, so Cache-Control: no-store
      //    applies and the browser fetches fresh assets from Vercel.
      try {
        windowClients.forEach((client) => {
          if (client.url && 'navigate' in client) {
            client.navigate(client.url);
          }
        });
      } catch (e) {
        console.warn('[SW] Failed to navigate clients:', e);
      }
    })()
  );
});

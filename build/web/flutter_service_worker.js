'use strict';
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    let windowClients = [];
    try { windowClients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true }); } catch (e) {}
    try { const keys = await caches.keys(); await Promise.all(keys.map((k) => caches.delete(k))); } catch (e) {}
    try { await self.registration.unregister(); } catch (e) {}
    try { windowClients.forEach((client) => { if (client.url && 'navigate' in client) client.navigate(client.url); }); } catch (e) {}
  })());
});

// Kill-switch: unregisters this service worker and clears all caches.
// The browser always fetches this file from the network to check for SW updates,
// bypassing the cache. When it detects this changed content, it installs this SW,
// which then clears everything and unregisters itself — breaking the stale-cache cycle.
self.addEventListener('install', function(e) {
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys()
      .then(function(keys) {
        return Promise.all(keys.map(function(key) { return caches.delete(key); }));
      })
      .then(function() { return self.clients.claim(); })
      .then(function() { return self.registration.unregister(); })
      .then(function() { return self.clients.matchAll({ type: 'window' }); })
      .then(function(clients) {
        clients.forEach(function(client) { client.navigate(client.url); });
      })
  );
});

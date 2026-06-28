// Kill-switch service worker: immediately clears all caches, serves network-only,
// then unregisters itself so future visits load fresh content without any SW.
self.addEventListener('install', function() {
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
        clients.forEach(function(client) {
          if ('navigate' in client) client.navigate(client.url);
        });
      })
  );
});

// Serve everything from network while active — never from cache
self.addEventListener('fetch', function(e) {
  e.respondWith(fetch(e.request));
});

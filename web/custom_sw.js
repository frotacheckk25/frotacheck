// FrotaCheck — service worker customizado (PWA).
//
// Flutter's own generated flutter_service_worker.js is deprecated and, in
// this SDK version, self-destructs on activate (calls
// self.registration.unregister() and navigates every open tab) — it does
// NOT actually precache anything anymore. So real offline support + a safe
// auto-update-on-deploy story has to be hand-rolled here instead of relying
// on Flutter's own service worker.
//
// Strategy: network-first for every same-origin GET request, with
// `cache: 'no-store'` on the fetch itself so no intermediary HTTP cache can
// serve a stale main.dart.js — this is what makes "always get the newest
// deploy when online" true without any content-hash/version bookkeeping.
// Falls back to the cached copy (or the cached app shell for navigations)
// only when the network request fails, which is what gives the offline
// support. Cross-origin requests (Supabase, CanvasKit CDN, etc.) are left
// completely untouched.

const CACHE_NAME = 'frotacheck-cache-v1';
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    (async () => {
      try {
        const networkResponse = await fetch(request, { cache: 'no-store' });
        if (networkResponse && networkResponse.ok) {
          const cache = await caches.open(CACHE_NAME);
          cache.put(request, networkResponse.clone()).catch((e) => {
            console.error('[custom_sw] cache.put failed for', request.url, e);
          });
        }
        return networkResponse;
      } catch (err) {
        const cached = await caches.match(request, { ignoreSearch: true });
        if (cached) return cached;
        if (request.mode === 'navigate') {
          const shell = await caches.match('/index.html');
          if (shell) return shell;
        }
        throw err;
      }
    })()
  );
});

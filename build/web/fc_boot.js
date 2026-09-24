// FrotaCheck — scripts de boot da página, externalizados de index.html para
// que o CSP possa usar script-src 'self' sem 'unsafe-inline' (ver vercel.json).

// Stub for PasskeyAuthenticator (required by passkeys_web, a transitive dependency of
// supabase_flutter). Without it, window.PasskeyAuthenticator.init() throws a TypeError
// during Flutter plugin registration and the app never renders (white screen).
window.PasskeyAuthenticator = {
  init: function() {},
  register: function() { return Promise.reject('Passkeys not configured'); },
  login: function() { return Promise.reject('Passkeys not configured'); },
  cancelCurrentAuthenticatorOperation: function() {},
  isUserVerifyingPlatformAuthenticatorAvailable: function() { return Promise.resolve(false); },
  isConditionalMediationAvailable: function() { return Promise.resolve(false); },
  hasPasskeySupport: function() { return false; }
};

// Removes the splash screen once Flutter paints its first frame, with a
// safety-net timeout so the app is never stuck hidden behind it.
(function () {
  var removed = false;
  function removeSplash() {
    if (removed) return;
    removed = true;
    var el = document.getElementById('fc-splash');
    if (!el) return;
    el.classList.add('fc-splash-hidden');
    setTimeout(function () { el.remove(); }, 400);
  }
  window.addEventListener('flutter-first-frame', removeSplash);
  setTimeout(removeSplash, 6000);
})();

// Captures the browser's native "add to home screen" prompt so our own
// Dart-side banner can trigger it on demand (see lib/core/utils/
// pwa_install_web.dart), instead of only relying on each browser's own
// passive install UI (which varies a lot and is easy to miss).
window.__fcInstallPrompt = null;
window.addEventListener('beforeinstallprompt', function (e) {
  e.preventDefault();
  window.__fcInstallPrompt = e;
});
window.addEventListener('appinstalled', function () {
  window.__fcInstallPrompt = null;
});

// iOS/Safari nunca dispara beforeinstallprompt (a Apple não implementa
// essa API) — a única forma de saber que estamos lá é checar a UA, para
// mostrar instruções manuais ("Compartilhar > Adicionar à Tela de
// Início") em vez de um botão de instalação que nunca funcionaria.
var ua = navigator.userAgent.toLowerCase();
window.__fcIsIos = /iphone|ipad|ipod/.test(ua) && !window.MSStream;
window.__fcIsStandalone =
  (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
  navigator.standalone === true;

// Download direto via <a download>, sem depender do Web Share API (que
// não é suportado de forma confiável em navegadores desktop).
window.__fcDownloadDataUrl = function (dataUrl, filename) {
  var a = document.createElement('a');
  a.href = dataUrl;
  a.download = filename;
  a.style.display = 'none';
  document.body.appendChild(a);
  a.click();
  a.remove();
};

// Service worker: registers our own custom_sw.js (network-first with
// offline cache fallback + auto-update — see web/custom_sw.js for why
// this replaces Flutter's own generated service worker, which is
// deprecated and self-unregisters in this SDK version) and blocks
// flutter_bootstrap.js from registering its own on top of it.
(function () {
  if (!('serviceWorker' in navigator)) return;

  var nativeRegister = navigator.serviceWorker.register.bind(navigator.serviceWorker);
  navigator.serviceWorker.register = function (url, options) {
    // Chromium's Trusted Types policy (flutter_bootstrap.js creates one
    // named "flutter-js") wraps this URL in a TrustedScriptURL object,
    // not a plain string — String(url) normalizes both cases.
    var urlStr = url == null ? '' : String(url);
    if (urlStr.indexOf('flutter_service_worker') !== -1) {
      return Promise.reject(new Error('Flutter service worker disabled — using custom_sw.js instead'));
    }
    return nativeRegister(url, options);
  };

  window.addEventListener('load', function () {
    // A page's very first-ever visit has no controller yet; the SW
    // claiming it right after activation also fires 'controllerchange',
    // but that's not an update to reload for — only reload when a
    // controller that was ALREADY there gets replaced by a new one.
    var hadControllerAtLoad = !!navigator.serviceWorker.controller;
    var refreshing = false;

    nativeRegister('/custom_sw.js').then(function (registration) {
      navigator.serviceWorker.addEventListener('controllerchange', function () {
        if (!hadControllerAtLoad) {
          hadControllerAtLoad = true;
          return;
        }
        if (refreshing) return;
        refreshing = true;
        window.location.reload();
      });

      // Long-lived open tabs still pick up new deploys reasonably
      // promptly by re-checking whenever the tab regains focus.
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') registration.update();
      });
    }).catch(function (err) {
      console.warn('custom_sw registration failed:', err);
    });
  });
})();

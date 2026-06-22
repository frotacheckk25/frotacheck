// Cache busting for frotacheck web - disable service worker to ensure fresh main.dart.js

// Unregister all service workers on page load
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function(registrations) {
    registrations.forEach(function(r) { r.unregister(); });
  });
}

// Override Flutter loader's load to disable service worker settings
var originalLoad = null;
var interval = setInterval(function() {
  if (window._flutter && window._flutter.loader) {
    originalLoad = window._flutter.loader.load;
    if (originalLoad) {
      window._flutter.loader.load = function(config) {
        // Disable service worker caching
        config.serviceWorkerSettings = null;
        return originalLoad.call(this, config);
      };
    }
    clearInterval(interval);
  }
}, 50);
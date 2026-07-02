{{flutter_js}}
{{flutter_build_config}}

// Force HTML renderer — CanvasKit fails to render specific MaterialIcon glyphs.
// HTML renderer uses browser CSS font-face which renders all icons correctly.
(function() {
  var bc = window._flutter && window._flutter.buildConfig;
  if (bc && bc.builds) {
    bc.builds.forEach(function(b) {
      if (b.renderer) b.renderer = 'html';
    });
  }
})();

_flutter.loader.load({
  config: { renderer: 'html' }
});

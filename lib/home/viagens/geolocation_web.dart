import 'dart:async';
import 'dart:js_interop';

extension type _GeoPosition(JSObject _) implements JSObject {
  external _GeoCoords get coords;
}

extension type _GeoCoords(JSObject _) implements JSObject {
  external double get latitude;
  external double get longitude;
}

@JS('navigator.geolocation.getCurrentPosition')
external void _jsGetPosition(JSFunction success, JSFunction error);

/// Lê a localização atual via Geolocation API.
/// Best-effort: retorna null se indisponível, sem permissão, ou expirar.
Future<String?> obterLocalizacao() async {
  try {
    final completer = Completer<String?>();
    void onSuccess(JSAny? pos) {
      try {
        final p = pos as _GeoPosition;
        completer.complete('${p.coords.latitude},${p.coords.longitude}');
      } catch (_) {
        completer.complete(null);
      }
    }
    void onError(JSAny? _) => completer.complete(null);
    _jsGetPosition(onSuccess.toJS, onError.toJS);
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);
  } catch (_) {
    return null;
  }
}

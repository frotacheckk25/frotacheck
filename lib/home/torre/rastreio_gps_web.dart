import 'dart:async';
import 'dart:js_interop';

import 'leitura_gps.dart';

export 'leitura_gps.dart';

extension type _Posicao(JSObject _) implements JSObject {
  external _Coordenadas get coords;
  external double get timestamp;
}

extension type _Coordenadas(JSObject _) implements JSObject {
  external double get latitude;
  external double get longitude;
  external double? get accuracy;
  external double? get speed;
  external double? get heading;
}

extension type _Opcoes._(JSObject _) implements JSObject {
  external factory _Opcoes({bool enableHighAccuracy, int maximumAge, int timeout});
}

@JS('navigator.geolocation.watchPosition')
external int _observar(JSFunction sucesso, JSFunction erro, _Opcoes opcoes);

@JS('navigator.geolocation.clearWatch')
external void _pararDeObservar(int id);

/// Posições contínuas no navegador (Geolocation API). Só funcionam com o
/// FrotaCheck aberto na tela — por isso a viagem também pede a tela acesa.
Stream<LeituraGps> fluxoGps() {
  int? id;
  late final StreamController<LeituraGps> c;
  c = StreamController<LeituraGps>(
    onListen: () {
      void ok(JSAny? pos) {
        try {
          final p = pos as _Posicao;
          final v = p.coords.speed;
          final r = p.coords.heading;
          c.add(LeituraGps(
            latitude: p.coords.latitude,
            longitude: p.coords.longitude,
            velocidadeKmh: v == null || v.isNaN ? null : v * 3.6,
            precisaoM: p.coords.accuracy,
            rumo: r == null || r.isNaN ? null : r,
            quando: DateTime.fromMillisecondsSinceEpoch(p.timestamp.round()),
          ));
        } catch (_) {}
      }

      void falha(JSAny? _) {
        if (!c.isClosed) c.addError(Exception('Sem acesso à localização'));
      }

      id = _observar(ok.toJS, falha.toJS, _Opcoes(enableHighAccuracy: true, maximumAge: 30000, timeout: 60000));
    },
    onCancel: () {
      if (id != null) _pararDeObservar(id!);
    },
  );
  return c.stream;
}

// ── Tela acesa (Screen Wake Lock API) ───────────────────────────────────────
extension type _WakeLock(JSObject _) implements JSObject {
  external JSPromise<_Sentinela> request(String tipo);
}

extension type _Sentinela(JSObject _) implements JSObject {
  external bool get released;
  external JSPromise<JSAny?> release();
}

@JS('navigator.wakeLock')
external _WakeLock? get _wakeLock;

_Sentinela? _sentinela;

/// Mantém a tela do celular acesa enquanto o FrotaCheck estiver aberto na
/// viagem (o navegador solta sozinho ao trocar de app; pedimos de novo a
/// cada minuto). Navegador sem suporte: ignora.
Future<void> manterTelaAcesa(bool ligar) async {
  try {
    if (!ligar) {
      final s = _sentinela;
      _sentinela = null;
      if (s != null && !s.released) await s.release().toDart;
      return;
    }
    if (_sentinela != null && !_sentinela!.released) return;
    final w = _wakeLock;
    if (w == null) return;
    _sentinela = await w.request('screen').toDart;
  } catch (_) {}
}

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'leitura_gps.dart';

export 'leitura_gps.dart';

/// Posições contínuas no app nativo (Android/iOS) via package:geolocator.
/// No Android roda como serviço em primeiro plano, com aviso fixo na barra:
/// continua enviando com a tela apagada. Sem GPS ou sem permissão, o fluxo
/// termina com erro (quem escuta mostra o aviso ao motorista).
Stream<LeituraGps> fluxoGps() async* {
  if (!await Geolocator.isLocationServiceEnabled()) throw Exception('GPS desligado');
  var permissao = await Geolocator.checkPermission();
  if (permissao == LocationPermission.denied) permissao = await Geolocator.requestPermission();
  if (permissao == LocationPermission.denied || permissao == LocationPermission.deniedForever) {
    throw Exception('Sem permissão de localização');
  }
  final ajustes = defaultTargetPlatform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 30,
          intervalDuration: const Duration(seconds: 30),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'FrotaCheck — viagem em andamento',
            notificationText: 'Sua localização está indo para a torre de controle até o fim da viagem.',
            enableWakeLock: true,
            setOngoing: true,
          ),
        )
      : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 30);
  yield* Geolocator.getPositionStream(locationSettings: ajustes).map((p) => LeituraGps(
        latitude: p.latitude,
        longitude: p.longitude,
        velocidadeKmh: p.speed >= 0 ? p.speed * 3.6 : null,
        precisaoM: p.accuracy,
        rumo: p.heading >= 0 ? p.heading : null,
        quando: p.timestamp,
      ));
}

/// No app nativo o serviço em primeiro plano já mantém o envio; nada a fazer.
Future<void> manterTelaAcesa(bool ligar) async {}

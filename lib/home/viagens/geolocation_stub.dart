import 'package:geolocator/geolocator.dart';

/// Implementação usada em plataformas nativas (Android/iOS/desktop) via
/// package:geolocator. Best-effort: retorna null se o serviço de
/// localização estiver desligado, a permissão for negada, ou a leitura
/// expirar — mesmo contrato da versão Web (nunca lança exceção para quem
/// chama, "localização indisponível" já é tratado no viagens_page.dart).
Future<String?> obterLocalizacao() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.denied ||
        permissao == LocationPermission.deniedForever) {
      return null;
    }

    final posicao = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );

    return '${posicao.latitude},${posicao.longitude}';
  } catch (_) {
    return null;
  }
}

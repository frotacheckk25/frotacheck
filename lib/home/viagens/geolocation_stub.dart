// Implementação usada em plataformas nativas (Android/iOS/desktop). A API
// Geolocation do navegador não existe fora da Web — best-effort, retorna
// sempre null (mesmo comportamento de "localização indisponível" já previsto
// pelo chamador).
Future<String?> obterLocalizacao() async => null;

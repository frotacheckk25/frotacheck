// Implementação usada em plataformas nativas (Android/iOS/desktop). O
// evento beforeinstallprompt é exclusivo de navegadores — no app nativo o
// "instalar" já é o próprio APK, então isso é sempre indisponível.
bool isInstallAvailable() => false;

Future<bool> promptInstall() async => false;

Stream<bool> installAvailabilityStream() => const Stream.empty();

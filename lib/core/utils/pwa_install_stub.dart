// Implementação usada em plataformas nativas (Android/iOS/desktop). O
// evento beforeinstallprompt é exclusivo de navegadores — no app nativo o
// "instalar" já é o próprio APK, então isso é sempre indisponível.
import 'install_banner_kind.dart';

bool isInstallAvailable() => false;

Future<bool> promptInstall() async => false;

Stream<InstallBannerKind> installBannerKindStream() => Stream.value(InstallBannerKind.none);

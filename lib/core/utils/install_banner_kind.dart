/// `native`: o navegador dispara beforeinstallprompt e o botão "Instalar"
/// pode acionar o prompt nativo diretamente (Chrome/Edge Android/Desktop).
/// `iosManual`: Safari/iOS nunca dispara beforeinstallprompt (a Apple não
/// implementa essa API) — só resta orientar o usuário a instalar via
/// Compartilhar → Adicionar à Tela de Início.
enum InstallBannerKind { none, native, iosManual }

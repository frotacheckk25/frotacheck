// Implementação Web do banner "Instalar FrotaCheck" — lê o evento
// beforeinstallprompt capturado em web/index.html (window.__fcInstallPrompt)
// e expõe um jeito de disparar o prompt nativo do navegador sob demanda.
import 'dart:js_interop';

import 'install_banner_kind.dart';

@JS('window.__fcInstallPrompt')
external JSObject? get _installPromptEvent;

// window.__fcIsIos / window.__fcIsStandalone são computados em web/index.html,
// pois iOS/Safari nunca dispara beforeinstallprompt (não é implementado pela
// Apple) — é a única forma de detectar "deveria mostrar instrução manual".
@JS('window.__fcIsIos')
external bool? get _isIosFlag;

@JS('window.__fcIsStandalone')
external bool? get _isStandaloneFlag;

extension type _BeforeInstallPromptEvent(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prompt();
  external JSPromise<JSAny?> get userChoice;
}

extension type _UserChoice(JSObject _) implements JSObject {
  external String? get outcome;
}

bool isInstallAvailable() => _installPromptEvent != null;

/// Dispara o prompt nativo de instalação do navegador. Retorna true se o
/// usuário aceitou instalar.
Future<bool> promptInstall() async {
  final evt = _installPromptEvent;
  if (evt == null) return false;
  try {
    final promptable = evt as _BeforeInstallPromptEvent;
    await promptable.prompt().toDart;
    final choice = await promptable.userChoice.toDart;
    if (choice == null) return false;
    return (choice as _UserChoice).outcome == 'accepted';
  } catch (_) {
    return false;
  }
}

InstallBannerKind _computeBannerKind() {
  if (_isStandaloneFlag ?? false) return InstallBannerKind.none;
  if (isInstallAvailable()) return InstallBannerKind.native;
  if (_isIosFlag ?? false) return InstallBannerKind.iosManual;
  return InstallBannerKind.none;
}

/// beforeinstallprompt dispara de forma assíncrona e imprevisível (o
/// navegador decide quando) — este stream avisa quando o estado muda, via
/// polling simples (custo desprezível para um toggle de banner).
Stream<InstallBannerKind> installBannerKindStream() async* {
  var last = _computeBannerKind();
  yield last;
  while (true) {
    await Future.delayed(const Duration(milliseconds: 700));
    final now = _computeBannerKind();
    if (now != last) {
      last = now;
      yield now;
    }
  }
}

// Implementação Web do banner "Instalar FrotaCheck" — lê o evento
// beforeinstallprompt capturado em web/index.html (window.__fcInstallPrompt)
// e expõe um jeito de disparar o prompt nativo do navegador sob demanda.
import 'dart:js_interop';

@JS('window.__fcInstallPrompt')
external JSObject? get _installPromptEvent;

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

/// beforeinstallprompt dispara de forma assíncrona e imprevisível (o
/// navegador decide quando) — este stream avisa quando a disponibilidade
/// muda, via polling simples (custo desprezível para um toggle de banner).
Stream<bool> installAvailabilityStream() async* {
  var last = isInstallAvailable();
  yield last;
  while (true) {
    await Future.delayed(const Duration(milliseconds: 700));
    final now = isInstallAvailable();
    if (now != last) {
      last = now;
      yield now;
    }
  }
}

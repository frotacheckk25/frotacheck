// Implementação Web do "Lembrar minha senha" — grava direto em
// window.localStorage via JS-interop. package:flutter_secure_storage tem
// suporte Web "experimental" (WebCrypto), mas seu registro de plugin se
// mostrou instável neste projeto (MissingPluginException apontando para o
// canal nativo antigo em vez da implementação Web) — e mesmo quando
// funciona, a chave de criptografia fica salva no próprio localStorage ao
// lado do valor cifrado, então não há ganho real de segurança sobre
// localStorage puro nesse cenário. A prioridade aqui é apenas conveniência
// (não redigitar email/senha), não um cofre à prova de XSS.
import 'dart:js_interop';

@JS('window.localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('window.localStorage.setItem')
external void _setItem(JSString key, JSString value);

@JS('window.localStorage.removeItem')
external void _removeItem(JSString key);

const _kEmail = 'frotacheck_saved_email';
const _kSenha = 'frotacheck_saved_password';

Future<void> salvarCredenciais({required String email, required String senha}) async {
  try {
    _setItem(_kEmail.toJS, email.toJS);
    _setItem(_kSenha.toJS, senha.toJS);
  } catch (_) {
    // localStorage indisponível (ex.: modo privado) — segue sem salvar.
  }
}

Future<void> limparCredenciaisSalvas() async {
  try {
    _removeItem(_kEmail.toJS);
    _removeItem(_kSenha.toJS);
  } catch (_) {}
}

Future<Map<String, String>?> lerCredenciaisSalvas() async {
  try {
    final email = _getItem(_kEmail.toJS)?.toDart;
    final senha = _getItem(_kSenha.toJS)?.toDart;
    if (email == null || senha == null) return null;
    return {'email': email, 'senha': senha};
  } catch (_) {
    return null;
  }
}

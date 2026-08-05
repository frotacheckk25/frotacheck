// Implementação Web do "Lembrar minha senha" — grava direto em
// window.localStorage via JS-interop. package:flutter_secure_storage tem
// suporte Web "experimental" (WebCrypto), mas seu registro de plugin se
// mostrou instável neste projeto (MissingPluginException apontando para o
// canal nativo antigo em vez da implementação Web) — e mesmo quando
// funciona, a chave de criptografia fica salva no próprio localStorage ao
// lado do valor cifrado, então não há ganho real de segurança sobre
// localStorage puro nesse cenário.
//
// F-02 (auditoria de segurança 2026-07-29): no Web NÃO guardamos mais a
// senha em si — só o email, por conveniência de preencher o formulário.
// Um XSS ou extensão de navegador maliciosa lendo localStorage não deve
// conseguir extrair a senha em texto plano. "Continuar logado" já é
// resolvido pelo persistSession do próprio Supabase (token de sessão, não
// a senha); isto aqui é só preenchimento automático do campo de email.
import 'dart:js_interop';

@JS('window.localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('window.localStorage.setItem')
external void _setItem(JSString key, JSString value);

@JS('window.localStorage.removeItem')
external void _removeItem(JSString key);

const _kEmail = 'frotacheck_saved_email';
const _kSenhaLegado = 'frotacheck_saved_password';

Future<void> salvarCredenciais({required String email, required String senha}) async {
  try {
    _setItem(_kEmail.toJS, email.toJS);
    // Remove qualquer senha em texto plano salva por uma versão anterior
    // do app neste navegador.
    _removeItem(_kSenhaLegado.toJS);
  } catch (_) {
    // localStorage indisponível (ex.: modo privado) — segue sem salvar.
  }
}

Future<void> limparCredenciaisSalvas() async {
  try {
    _removeItem(_kEmail.toJS);
    _removeItem(_kSenhaLegado.toJS);
  } catch (_) {}
}

Future<Map<String, String>?> lerCredenciaisSalvas() async {
  try {
    final email = _getItem(_kEmail.toJS)?.toDart;
    // Limpeza best-effort de instalações antigas que ainda tenham a senha
    // em texto plano salva neste navegador.
    _removeItem(_kSenhaLegado.toJS);
    if (email == null) return null;
    return {'email': email};
  } catch (_) {
    return null;
  }
}

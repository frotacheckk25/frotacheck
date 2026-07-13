// Implementação usada em plataformas nativas (Android/iOS/desktop) para o
// recurso "Lembrar minha senha" — usa o Keystore/Keychain do sistema via
// package:flutter_secure_storage (funciona nativamente nessas plataformas,
// diferente da Web, onde o registro do plugin desse pacote é instável —
// ver credential_storage_web.dart).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kEmail = 'frotacheck_saved_email';
const _kSenha = 'frotacheck_saved_password';

Future<void> salvarCredenciais({required String email, required String senha}) async {
  await _storage.write(key: _kEmail, value: email);
  await _storage.write(key: _kSenha, value: senha);
}

Future<void> limparCredenciaisSalvas() async {
  await _storage.delete(key: _kEmail);
  await _storage.delete(key: _kSenha);
}

Future<Map<String, String>?> lerCredenciaisSalvas() async {
  final email = await _storage.read(key: _kEmail);
  final senha = await _storage.read(key: _kSenha);
  if (email == null || senha == null) return null;
  return {'email': email, 'senha': senha};
}

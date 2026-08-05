import 'package:shared_preferences/shared_preferences.dart';

/// F-07 da auditoria de segurança: o rate-limit real (por IP) já existe no
/// próprio Supabase Auth, mas nada no client impunha fricção contra alguém
/// tentando senhas repetidamente pela UI numa única conta. Isto é defesa em
/// profundidade complementar (client-side, portanto contornável por quem
/// bate direto na API) — não substitui um rate-limit/captcha no servidor.
const _kThreshold = 5;
const _kBaseSeconds = 30;
const _kMaxSeconds = 300;

String _key(String email) => 'login_fail_${email.trim().toLowerCase()}';

Future<int> _secondsRemaining(String email) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_key(email));
  if (raw == null) return 0;
  final parts = raw.split('|');
  if (parts.length != 2) return 0;
  final lockUntilMs = int.tryParse(parts[1]) ?? 0;
  final remaining = ((lockUntilMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
  return remaining > 0 ? remaining : 0;
}

/// Retorna quantos segundos faltam de bloqueio para este e-mail, ou 0 se
/// pode tentar normalmente.
Future<int> checarBloqueio(String email) => _secondsRemaining(email);

/// Chamar após uma tentativa de login que falhou por credencial incorreta.
Future<void> registrarTentativaFalha(String email) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_key(email));
  var count = 0;
  if (raw != null) {
    final parts = raw.split('|');
    count = int.tryParse(parts[0]) ?? 0;
  }
  count++;

  var lockUntilMs = 0;
  if (count >= _kThreshold) {
    // extra limitado a 10 antes do shift — 30s * 2^10 já estoura o teto de
    // _kMaxSeconds de sobra, e evita um shift gigante em contas atacadas
    // por muito tempo (comportamento de << com expoente grande não é
    // garantido igual entre VM nativa e compilação para JS/Web).
    final extra = (count - _kThreshold).clamp(0, 10);
    final seconds = (_kBaseSeconds * (1 << extra)).clamp(_kBaseSeconds, _kMaxSeconds);
    lockUntilMs = DateTime.now().millisecondsSinceEpoch + seconds * 1000;
  }

  await prefs.setString(_key(email), '$count|$lockUntilMs');
}

/// Chamar após um login bem-sucedido para zerar o contador desta conta.
Future<void> limparTentativasFalhas(String email) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_key(email));
}

/// Formatação de números no padrão brasileiro: milhar com ponto e decimal com
/// vírgula (1.254.321,87). Antes cada tela fazia `toStringAsFixed(2)` +
/// troca do ponto, e valores grandes saíam como "R$ 1254321,87".
String numeroBr(num v, {int casas = 2}) {
  final negativo = v < 0;
  final s = v.abs().toStringAsFixed(casas);
  final partes = s.split('.');
  final inteiro = partes[0];
  final buf = StringBuffer();
  for (var i = 0; i < inteiro.length; i++) {
    if (i > 0 && (inteiro.length - i) % 3 == 0) buf.write('.');
    buf.write(inteiro[i]);
  }
  final dec = partes.length > 1 ? ',${partes[1]}' : '';
  return '${negativo ? '-' : ''}$buf$dec';
}

/// Valor em reais: "R$ 1.254.321,87".
String moedaBr(num v) => 'R\$ ${numeroBr(v)}';

/// Litros com até 2 casas, sem zeros sobrando: "312,5 L", "45,37 L", "300 L".
String litrosBr(dynamic v) {
  var s = numeroBr(paraDouble(v));
  if (s.endsWith(',00')) return '${s.substring(0, s.length - 3)} L';
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return '$s L';
}

/// Aceita num, String ou null (valores vindos do banco).
double paraDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

/// Número digitado no padrão brasileiro: "1.234,56", "1234,56", "1234.56",
/// "2,5" e também "12.000" (milhar, como o próprio app mostra os números) —
/// antes "12.000" virava 12. Vazio ou inválido devolve null.
double? lerNumeroBr(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(t)) return double.tryParse(t.replaceAll('.', ''));
  return double.tryParse(t);
}

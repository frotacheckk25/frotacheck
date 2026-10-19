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

/// Aceita num, String ou null (valores vindos do banco).
double paraDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

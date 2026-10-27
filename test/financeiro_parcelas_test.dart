import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/financeiro/financeiro_comum.dart';

void main() {
  test('parcelas somam exatamente o total (centavos vão para a última)', () {
    final p = gerarParcelas(1000, 3, DateTime(2026, 11, 10));
    expect(p.map((x) => x.$1), [333.33, 333.33, 333.34]);
    expect(p.fold<double>(0, (s, x) => s + x.$1), closeTo(1000, 0.0001));
    expect(p.map((x) => x.$2), [DateTime(2026, 11, 10), DateTime(2026, 12, 10), DateTime(2027, 1, 10)]);
  });

  test('vencimento dia 31 cai no último dia dos meses curtos', () {
    final p = gerarParcelas(300, 3, DateTime(2027, 1, 31));
    expect(p.map((x) => x.$2), [DateTime(2027, 1, 31), DateTime(2027, 2, 28), DateTime(2027, 3, 31)]);
  });

  test('parcela única', () {
    final p = gerarParcelas(1234.56, 1, DateTime(2026, 10, 30));
    expect(p.single.$1, 1234.56);
  });

  test('dias para vencer (negativo = vencida)', () {
    final hoje = DateTime(2026, 10, 27);
    expect(diasParaVencer('2026-10-30', hoje: hoje), 3);
    expect(diasParaVencer('2026-10-27', hoje: hoje), 0);
    expect(diasParaVencer('2026-10-20', hoje: hoje), -7);
  });
}

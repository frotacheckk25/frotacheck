import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/pneus/pneu_comum.dart';

void main() {
  test('pneu montado: km das montagens anteriores + km da montagem atual', () {
    final a = analisarPneu(
      {'situacao': 'em_uso', 'km_acumulado': 40000, 'km_instalacao': 100000, 'valor': 2000},
      125000, // odômetro atual do veículo
      [],
    );
    expect(a.kmMontagemAtual, 25000);
    expect(a.kmTotal, 65000);
    expect(a.custoTotal, 2000);
    expect(a.custoPorKm, closeTo(2000 / 65000, 1e-9));
  });

  test('custo soma compra + recapagens + consertos (o cadastro não conta duas vezes)', () {
    final a = analisarPneu(
      {'situacao': 'estoque', 'km_acumulado': 80000, 'cost': 1800},
      null,
      [
        {'tipo': 'cadastro', 'custo': 1800},
        {'tipo': 'recapagem', 'custo': 600},
        {'tipo': 'conserto', 'custo': 80},
        {'tipo': 'medicao', 'custo': null},
      ],
    );
    expect(a.kmTotal, 80000); // no estoque não soma km da montagem
    expect(a.custoTotal, 2480);
    expect(a.custoPorKm, closeTo(2480 / 80000, 1e-9));
  });

  test('sem km rodado não calcula custo por km', () {
    final a = analisarPneu({'situacao': 'estoque', 'km_acumulado': 0, 'valor': 1500}, null, []);
    expect(a.custoPorKm, isNull);
  });

  test('odômetro menor que o km da montagem não gera km negativo', () {
    final a = analisarPneu({'situacao': 'em_uso', 'km_acumulado': 0, 'km_instalacao': 50000}, 49000, []);
    expect(a.kmTotal, 0);
  });

  test('alerta de sulco: até 3 mm crítico, até 5 mm baixo', () {
    expect(alertaSulco(2.5)!.$1, 'Sulco crítico');
    expect(alertaSulco(4)!.$1, 'Sulco baixo');
    expect(alertaSulco(9), isNull);
    expect(alertaSulco(null), isNull);
  });
}

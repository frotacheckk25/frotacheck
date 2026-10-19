import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/core/utils/formato_br.dart';

void main() {
  test('moeda no padrão brasileiro', () {
    expect(moedaBr(1254321.87), 'R\$ 1.254.321,87');
    expect(moedaBr(999.5), 'R\$ 999,50');
    expect(moedaBr(0), 'R\$ 0,00');
    expect(moedaBr(-1500), 'R\$ -1.500,00');
  });

  test('número com casas configuráveis', () {
    expect(numeroBr(182340.5, casas: 1), '182.340,5');
    expect(numeroBr(1000000, casas: 0), '1.000.000');
    expect(paraDouble('12.5'), 12.5);
    expect(paraDouble(null), 0.0);
  });
}

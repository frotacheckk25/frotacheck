import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/core/utils/formato_br.dart';

void main() {
  test('valores das telas antigas aceitam ponto de milhar', () {
    // abastecimento, multa, viagem, troca de óleo: antes "1.800,00" virava "1.800.00" e era recusado
    expect(lerNumeroBr('1.800,00'), 1800.0);
    expect(lerNumeroBr('312,5'), 312.5);
    // km da viagem: antes "125.000" era gravado como 125
    expect(lerNumeroBr('125.000'), 125000.0);
    expect(lerNumeroBr('7,8'), 7.8); // sulco do pneu em mm
  });

  test('inteiros (km, ano, volumes) com ou sem milhar', () {
    expect(lerInteiroBr('125.000'), 125000);
    expect(lerInteiroBr('125000'), 125000);
    expect(lerInteiroBr('125 000'), 125000);
    expect(lerInteiroBr(' 2024 '), 2024);
    expect(lerInteiroBr('1.234.567'), 1234567);
    expect(lerInteiroBr(''), isNull);
    expect(lerInteiroBr('abc'), isNull);
  });
}

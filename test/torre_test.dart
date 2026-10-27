import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/torre/torre_comum.dart';

void main() {
  final agora = DateTime(2026, 10, 27, 15, 0);

  test('situação do veículo na torre', () {
    expect(situacaoVeiculo(emViagem: false, ultimaPosicao: agora, agora: agora), SituacaoVeiculo.foraDeViagem);
    expect(situacaoVeiculo(emViagem: true, agora: agora), SituacaoVeiculo.semSinal); // nunca mandou posição
    expect(situacaoVeiculo(emViagem: true, ultimaPosicao: agora.subtract(const Duration(minutes: 16)), agora: agora), SituacaoVeiculo.semSinal);
    expect(situacaoVeiculo(emViagem: true, ultimaPosicao: agora.subtract(const Duration(minutes: 3)), agora: agora), SituacaoVeiculo.emMovimento);
    expect(
      situacaoVeiculo(
        emViagem: true,
        ultimaPosicao: agora.subtract(const Duration(minutes: 2)),
        paradoDesde: agora.subtract(const Duration(minutes: 45)),
        agora: agora,
      ),
      SituacaoVeiculo.parado,
    );
    // parado há pouco tempo ainda conta como em movimento
    expect(
      situacaoVeiculo(
        emViagem: true,
        ultimaPosicao: agora.subtract(const Duration(minutes: 2)),
        paradoDesde: agora.subtract(const Duration(minutes: 10)),
        agora: agora,
      ),
      SituacaoVeiculo.emMovimento,
    );
  });

  test('distância entre dois pontos (haversine)', () {
    // São Gonçalo do Sapucaí → Pouso Alegre: ~51 km em linha reta
    final d = distanciaMetros(-21.8918, -45.5953, -22.2302, -45.9364);
    expect(d, inInclusiveRange(48000, 52000));
    expect(distanciaMetros(-21.89, -45.59, -21.89, -45.59), 0);
    // 0,001 grau de latitude ≈ 111 m
    expect(distanciaMetros(-21.890, -45.59, -21.891, -45.59), closeTo(111, 1));
  });

  test('há quanto tempo', () {
    expect(haQuanto(null), 'sem posição');
    expect(haQuanto(agora.subtract(const Duration(seconds: 20)), agora: agora), 'agora');
    expect(haQuanto(agora.subtract(const Duration(minutes: 5)), agora: agora), 'há 5 min');
    expect(haQuanto(agora.subtract(const Duration(minutes: 130)), agora: agora), 'há 2 h 10 min');
    expect(haQuanto(agora.subtract(const Duration(hours: 3)), agora: agora), 'há 3 h');
    expect(haQuanto(agora.subtract(const Duration(days: 1, hours: 2)), agora: agora), 'há 1 dia');
    expect(haQuanto(agora.subtract(const Duration(days: 4)), agora: agora), 'há 4 dias');
  });

  test('quando o celular manda a posição (poupa bateria e dados)', () {
    expect(deveEnviarPosicao(agora: agora), isTrue); // primeira
    // andando: a cada 2 min
    expect(deveEnviarPosicao(agora: agora, ultimoEnvio: agora.subtract(const Duration(seconds: 90)), metrosDesdeUltimo: 2000), isFalse);
    expect(deveEnviarPosicao(agora: agora, ultimoEnvio: agora.subtract(const Duration(minutes: 2)), metrosDesdeUltimo: 2000), isTrue);
    // parado (menos de 150 m): a cada 5 min
    expect(deveEnviarPosicao(agora: agora, ultimoEnvio: agora.subtract(const Duration(minutes: 3)), metrosDesdeUltimo: 40), isFalse);
    expect(deveEnviarPosicao(agora: agora, ultimoEnvio: agora.subtract(const Duration(minutes: 5)), metrosDesdeUltimo: 40), isTrue);
  });

  test('link do Google Maps', () {
    expect(linkMapa(-21.89, -45.59).toString(), 'https://www.google.com/maps?q=-21.89,-45.59');
  });
}

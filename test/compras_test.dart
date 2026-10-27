import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/core/utils/formato_br.dart';
import 'package:frotacheck/home/compras/compras_comum.dart';

void main() {
  test('número digitado no padrão brasileiro, inclusive milhar sem vírgula', () {
    expect(lerNumeroBr('1.234,56'), 1234.56);
    expect(lerNumeroBr('1234,56'), 1234.56);
    expect(lerNumeroBr('1234.56'), 1234.56);
    expect(lerNumeroBr('2,5'), 2.5);
    expect(lerNumeroBr('1.5'), 1.5);
    expect(lerNumeroBr('12.000'), 12000); // como o app mostra 12000 kg — antes virava 12
    expect(lerNumeroBr('1.000.000'), 1000000);
    expect(lerNumeroBr('  300 '), 300);
    expect(lerNumeroBr(''), isNull);
    expect(lerNumeroBr('abc'), isNull);
  });

  test('sugestão de compra leva o estoque ao dobro do mínimo', () {
    expect(quantidadeSugerida(3, 4), 5);
    expect(quantidadeSugerida(0, 10), 20);
    expect(quantidadeSugerida(2.5, 4), 6); // 5,5 arredonda para cima
    expect(quantidadeSugerida(8, 4), 1); // nunca menos que 1
  });

  test('quanto falta receber de cada item', () {
    expect(pendenteItem({'quantidade': 10, 'quantidade_recebida': 4}), 6);
    expect(pendenteItem({'quantidade': 10, 'quantidade_recebida': 10}), 0);
    expect(pendenteItem({'quantidade': 3}), 3);
  });

  test('texto do pedido para o fornecedor', () {
    final t = textoPedidoFornecedor(
      pedido: {'numero': 12, 'valor_total': 1234.5, 'parcelas': 3, 'prazo_dias': 30, 'previsao_entrega': '2026-11-05'},
      itens: [
        {'quantidade': 10, 'unidade': 'un', 'descricao': 'Filtro de óleo', 'valor_unitario': 25},
        {'quantidade': 2.5, 'unidade': 'L', 'descricao': 'Aditivo', 'valor_unitario': 40},
      ],
      empresa: 'Transportes Horizonte',
      contato: 'Carlos',
    );
    expect(t, contains('Olá, Carlos!'));
    expect(t, contains('pedido de compra nº 12 da Transportes Horizonte'));
    expect(t, contains('• 10 un — Filtro de óleo (R\$ 25,00 cada)'));
    expect(t, contains('• 2,5 L — Aditivo (R\$ 40,00 cada)'));
    expect(t, contains('Total: R\$ 1.234,50'));
    expect(t, contains('Pagamento: 3x, 1º vencimento em 30 dias'));
    expect(t, contains('Entrega até: 05/11/2026'));
  });

  test('data e hora no horário local', () {
    expect(dataHoraBr(null), '-');
    expect(dataHoraBr(DateTime(2026, 10, 27, 14, 5).toIso8601String()), '27/10/2026 14:05');
  });
}

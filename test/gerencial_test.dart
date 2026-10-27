import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/gerencial/gerencial_comum.dart';

void main() {
  // Outubro/2026 com dois veículos (A e B); valores escolhidos para dar conta redonda
  PainelGerencial painel() => calcularPainel(
        mes: DateTime(2026, 10),
        idsVeiculos: ['A', 'B'],
        abastecimentos: [
          {'vehicle_id': 'A', 'fuel_date': '2026-09-28', 'odometer': 1000, 'liters': 100, 'total_value': 600},
          {'vehicle_id': 'A', 'fuel_date': '2026-10-10', 'odometer': 1300, 'liters': 100, 'total_value': 620},
          {'vehicle_id': 'A', 'fuel_date': '2026-10-20', 'odometer': 1600, 'liters': 120, 'total_value': 744},
          {'vehicle_id': 'B', 'fuel_date': '2026-10-05', 'odometer': 500, 'liters': 40, 'total_value': 250},
        ],
        manutencoes: [
          {'vehicle_id': 'A', 'data': '2026-10-15', 'valor': 1000},
          {'vehicle_id': 'B', 'data': '2026-09-03', 'cost': 400}, // registro antigo só com "cost"
        ],
        pneus: [
          {'vehicle_id': 'B', 'data_instalacao': '2026-10-02', 'valor': 2400},
        ],
        multas: [
          {'vehicle_id': 'A', 'data': '2026-10-08', 'valor': 195.23},
          {'veiculo_id': 'B', 'data': '2026-10-09', 'valor': 130.16}, // coluna antiga
        ],
        contasPagar: [
          {'categoria': 'salarios', 'vencimento': '2026-10-05', 'valor': 7600, 'status': 'aberta'},
          {'categoria': 'pedagio', 'vencimento': '2026-10-12', 'valor': 300, 'status': 'paga', 'vehicle_id': 'A'},
          {'categoria': 'combustivel', 'vencimento': '2026-10-10', 'valor': 9999, 'status': 'paga'}, // já está nos abastecimentos
          {'categoria': 'pecas', 'vencimento': '2026-10-10', 'valor': 9999, 'status': 'paga'}, // estoque, não custo
          {'categoria': 'outros', 'vencimento': '2026-10-10', 'valor': 300, 'status': 'cancelada'},
          {'categoria': 'seguros', 'vencimento': '2026-09-01', 'valor': 500, 'status': 'paga'},
        ],
        coletas: [
          {'veiculo_id': 'A', 'status': 'coletada', 'valor_frete': 5000, 'coletada_em': '2026-10-11T15:00:00Z', 'clientes': {'nome': 'Laticínios Serra'}},
          {'veiculo_id': 'B', 'status': 'coletada', 'valor_frete': 3500, 'coletada_em': '2026-10-14T15:00:00Z', 'clientes': {'nome': 'Agro Sul'}},
          {'veiculo_id': 'A', 'status': 'programada', 'valor_frete': 9999, 'data_programada': '2026-10-30'},
          {'veiculo_id': 'A', 'status': 'coletada', 'valor_frete': 4000, 'coletada_em': '2026-09-20T15:00:00Z', 'clientes': {'nome': 'Laticínios Serra'}},
        ],
        ctes: [
          {'veiculo_id': 'B', 'status': 'autorizado', 'valor_frete': 2000, 'autorizado_em': '2026-10-20T13:00:00Z', 'remetente_nome': 'Agro Sul'},
          {'veiculo_id': 'A', 'status': 'autorizado', 'valor_frete': 5000, 'coleta_id': 'c1', 'autorizado_em': '2026-10-11T16:00:00Z'}, // já contado na coleta
        ],
        outrasReceitas: [
          {'vencimento': '2026-10-25', 'valor': 100, 'status': 'aberta'},
          {'vencimento': '2026-10-25', 'valor': 999, 'status': 'cancelada'},
        ],
      );

  test('resultado do mês sem contar nada duas vezes', () {
    final a = painel().atual;
    expect(a.mes, '2026-10');
    expect(a.receita, 10600); // 5000 + 3500 + 2000 (CT-e sem coleta) + 100
    expect(a.fretes, 3);
    expect(a.combustivel, 1614);
    expect(a.manutencao, 1000);
    expect(a.pneus, 2400);
    expect(a.multas, closeTo(325.39, 0.001));
    expect(a.despesas, {'salarios': 7600, 'pedagio': 300}); // combustível, peças e cancelada ficam de fora
    expect(a.custos, closeTo(13239.39, 0.001));
    expect(a.resultado, closeTo(-2639.39, 0.001));
    expect(a.margem, closeTo(-2639.39 / 10600, 1e-9));
  });

  test('km, consumo e custo por km pelo odômetro dos abastecimentos', () {
    final a = painel().atual;
    expect(a.km, 600); // dois trechos de 300 km do veículo A
    expect(a.litros, 220);
    expect(a.kmL, closeTo(600 / 220, 1e-9));
    expect(a.custoKm, closeTo(5339.39 / 600, 1e-9)); // só custos da frota
  });

  test('evolução de 6 meses e comparação com o mês anterior', () {
    final p = painel();
    expect(p.meses.map((m) => m.mes), ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10']);
    final set = p.anterior!;
    expect(set.receita, 4000);
    expect(set.combustivel, 600);
    expect(set.manutencao, 400);
    expect(set.custos, 1500); // 600 + 400 + seguro 500
    expect(variacao(p.atual.receita, set.receita), closeTo(1.65, 1e-9));
    expect(variacao(10, 0), isNull);
  });

  test('ranking por veículo e maiores clientes', () {
    final p = painel();
    expect(p.veiculos.map((v) => v.vehicleId), ['B', 'A']); // maior resultado primeiro
    final b = p.veiculos.first, a = p.veiculos.last;
    expect(b.receita, 5500);
    expect(b.fretes, 2);
    expect(b.custo, closeTo(2780.16, 0.001)); // 250 + 2400 + 130,16
    expect(b.resultado, closeTo(2719.84, 0.001));
    expect(a.km, 600);
    expect(a.custo, closeTo(2859.23, 0.001)); // 1364 + 1000 + 195,23 + pedágio 300
    expect(a.resultado, closeTo(2140.77, 0.001));
    expect(p.clientes.first, ('Agro Sul', 5500.0));
    expect(p.clientes.last, ('Laticínios Serra', 5000.0));
  });

  test('custos por categoria do maior para o menor', () {
    final itens = painel().atual.custosPorCategoria;
    expect(itens.first, ('Salários', 7600.0));
    expect(itens.map((e) => e.$1), ['Salários', 'Pneus', 'Combustível', 'Manutenção', 'Multas', 'Pedágio']);
  });
}

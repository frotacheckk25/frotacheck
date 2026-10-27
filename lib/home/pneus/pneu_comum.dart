import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Peças comuns da gestão de pneus (lista, cadastro e detalhe).

/// Posições: as de carro que já existiam + as de caminhão (tração, truck,
/// interno/externo). Os nomes antigos continuam valendo para os pneus já cadastrados.
const posicoesPneu = [
  'Dianteiro Esquerdo',
  'Dianteiro Direito',
  'Tração Esquerdo Externo',
  'Tração Esquerdo Interno',
  'Tração Direito Interno',
  'Tração Direito Externo',
  'Truck Esquerdo Externo',
  'Truck Esquerdo Interno',
  'Truck Direito Interno',
  'Truck Direito Externo',
  'Traseiro Esquerdo',
  'Traseiro Direito',
  'Traseiro Interno Esquerdo',
  'Traseiro Interno Direito',
  'Estepe',
  'Estepe 2',
];

const situacoesPneu = {
  'em_uso': ('Em uso', AppColors.success),
  'estoque': ('Em estoque', AppColors.info),
  'recapagem': ('Na recapagem', AppColors.warning),
  'descartado': ('Descartado', AppColors.muted),
};

const movimentacoesPneu = {
  'cadastro': ('Cadastro', Icons.add_circle_outline),
  'montagem': ('Montagem', Icons.build_circle_outlined),
  'desmontagem': ('Desmontagem', Icons.remove_circle_outline),
  'rodizio': ('Rodízio', Icons.swap_horiz),
  'medicao': ('Medição de sulco', Icons.straighten),
  'recapagem_envio': ('Enviado para recapagem', Icons.local_shipping_outlined),
  'recapagem': ('Recapagem', Icons.autorenew),
  'conserto': ('Conserto', Icons.handyman_outlined),
  'descarte': ('Descarte', Icons.delete_forever_outlined),
};

class AnalisePneu {
  const AnalisePneu({required this.kmTotal, required this.kmMontagemAtual, required this.custoTotal});
  final double kmTotal;
  final double kmMontagemAtual;
  final double custoTotal;
  double? get custoPorKm => kmTotal > 0 && custoTotal > 0 ? custoTotal / kmTotal : null;
}

/// Km rodado = km das montagens anteriores + (odômetro atual − km da montagem atual).
/// Custo = compra + recapagens + consertos (o "cadastro" não entra de novo).
AnalisePneu analisarPneu(Map<String, dynamic> pneu, num? odometroVeiculo, List<Map<String, dynamic>> movimentacoes) {
  final acumulado = (pneu['km_acumulado'] as num?)?.toDouble() ?? 0;
  var atual = 0.0;
  final kmInst = (pneu['km_instalacao'] as num?)?.toDouble();
  if (pneu['situacao'] == 'em_uso' && odometroVeiculo != null && kmInst != null && odometroVeiculo >= kmInst) {
    atual = odometroVeiculo.toDouble() - kmInst;
  }
  final compra = ((pneu['valor'] ?? pneu['cost']) as num?)?.toDouble() ?? 0;
  final extras = movimentacoes
      .where((m) => m['tipo'] == 'recapagem' || m['tipo'] == 'conserto')
      .fold<double>(0, (s, m) => s + ((m['custo'] as num?)?.toDouble() ?? 0));
  return AnalisePneu(kmTotal: acumulado + atual, kmMontagemAtual: atual, custoTotal: compra + extras);
}

/// Situação do sulco: até 3 mm trocar, até 5 mm revisar (mesma regra do banco).
(String, Color)? alertaSulco(num? sulco) {
  if (sulco == null) return null;
  if (sulco <= 3) return ('Sulco crítico', AppColors.danger);
  if (sulco <= 5) return ('Sulco baixo', AppColors.warning);
  return null;
}

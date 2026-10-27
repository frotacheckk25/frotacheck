import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Peças comuns do módulo Financeiro (contas a pagar/receber e fornecedores).

const categoriasPagar = {
  'combustivel': ('Combustível', Icons.local_gas_station),
  'manutencao': ('Manutenção', Icons.build),
  'pneus': ('Pneus', Icons.tire_repair),
  'pecas': ('Peças', Icons.settings),
  'salarios': ('Salários', Icons.groups),
  'impostos': ('Impostos', Icons.account_balance),
  'seguros': ('Seguros', Icons.verified_user),
  'pedagio': ('Pedágio', Icons.toll),
  'financiamento': ('Financiamento', Icons.request_quote),
  'aluguel': ('Aluguel', Icons.home_work),
  'administrativo': ('Administrativo', Icons.business_center),
  'outros': ('Outros', Icons.more_horiz),
};

const statusPagar = {
  'aberta': ('Em aberto', AppColors.info),
  'paga': ('Paga', AppColors.success),
  'cancelada': ('Cancelada', AppColors.muted),
};

const statusReceber = {
  'aberta': ('Em aberto', AppColors.info),
  'recebida': ('Recebida', AppColors.success),
  'cancelada': ('Cancelada', AppColors.muted),
};

const formasPagamento = ['Pix', 'Boleto', 'Transferência', 'Dinheiro', 'Cartão', 'Cheque', 'Débito automático'];

/// Mesmo dia nos meses seguintes; dia 31 vira o último dia de meses mais curtos.
DateTime somarMeses(DateTime d, int meses) {
  final alvo = DateTime(d.year, d.month + meses, 1);
  final ultimoDia = DateTime(alvo.year, alvo.month + 1, 0).day;
  return DateTime(alvo.year, alvo.month, d.day > ultimoDia ? ultimoDia : d.day);
}

/// Divide o total em [n] parcelas mensais. Os centavos que sobram da divisão
/// vão para a última parcela, então a soma bate exatamente com o total.
List<(double, DateTime)> gerarParcelas(double total, int n, DateTime primeiroVencimento) {
  if (n < 1) n = 1;
  final totalCentavos = (total * 100).round();
  final base = totalCentavos ~/ n;
  return [
    for (var i = 0; i < n; i++)
      ((i == n - 1 ? totalCentavos - base * (n - 1) : base) / 100, somarMeses(primeiroVencimento, i)),
  ];
}

/// Dias até o vencimento (negativo = vencida).
int diasParaVencer(String? vencimentoIso, {DateTime? hoje}) {
  final v = DateTime.tryParse(vencimentoIso ?? '');
  if (v == null) return 0;
  final h = hoje ?? DateTime.now();
  return DateTime(v.year, v.month, v.day).difference(DateTime(h.year, h.month, h.day)).inDays;
}

/// Cálculos financeiros derivados da tabela `assinaturas` — usados tanto no
/// painel principal do Master quanto na tela "Planos", para as duas nunca
/// divergirem sobre o que é MRR/ARR/ticket médio.
class PlanoFinanceiro {
  final double mrr;
  final double arr;
  final int empresasAtivas;
  final int empresasInadimplentes;
  final int empresasCanceladas;
  final double ticketMedio;

  const PlanoFinanceiro({
    required this.mrr,
    required this.arr,
    required this.empresasAtivas,
    required this.empresasInadimplentes,
    required this.empresasCanceladas,
    required this.ticketMedio,
  });

  static const zero = PlanoFinanceiro(
    mrr: 0, arr: 0, empresasAtivas: 0, empresasInadimplentes: 0,
    empresasCanceladas: 0, ticketMedio: 0,
  );
}

double _valorAssinatura(Map<String, dynamic> a) => (a['valor_mensal'] as num?)?.toDouble() ?? 0;

PlanoFinanceiro calcularFinanceiroPlanos(List<Map<String, dynamic>> assinaturas) {
  double mrr = 0;
  int ativas = 0, inadimplentes = 0, canceladas = 0;
  for (final a in assinaturas) {
    final status = (a['status'] ?? 'ativo').toString();
    if (status == 'ativo') {
      mrr += _valorAssinatura(a);
      ativas++;
    } else if (status == 'inadimplente') {
      inadimplentes++;
    } else if (status == 'cancelado') {
      canceladas++;
    }
  }
  return PlanoFinanceiro(
    mrr: mrr,
    arr: mrr * 12,
    empresasAtivas: ativas,
    empresasInadimplentes: inadimplentes,
    empresasCanceladas: canceladas,
    ticketMedio: ativas > 0 ? mrr / ativas : 0,
  );
}

/// Reconstrói o MRR "como estava" numa data de corte: soma o valor de
/// assinaturas ativas cujo início (`data_inicio`) já tinha ocorrido antes do
/// corte. Aproximação real (sem histórico de faturas), mas baseada na data de
/// início de cada assinatura em vez de um número inventado.
double mrrAteData(List<Map<String, dynamic>> assinaturas, DateTime corte) {
  double soma = 0;
  for (final a in assinaturas) {
    if ((a['status'] ?? 'ativo').toString() != 'ativo') continue;
    final inicio = DateTime.tryParse(a['data_inicio']?.toString() ?? '');
    if (inicio != null && inicio.isBefore(corte)) soma += _valorAssinatura(a);
  }
  return soma;
}

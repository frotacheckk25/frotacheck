import '../abastecimentos/consumo_frota_page.dart' show calcularConsumo;
import '../financeiro/financeiro_comum.dart' show categoriasPagar;

/// Contas da Visão gerencial (resultado do mês, evolução, ranking por veículo).
///
/// Nada é contado duas vezes: combustível, manutenção, pneus e multas vêm dos
/// registros da frota; do contas a pagar entram só as OUTRAS despesas
/// (salários, pedágio, seguros...). Compra de peças é estoque, não custo —
/// vira custo quando a peça é usada na OS (manutenção).

/// Categorias do contas a pagar que entram como despesa no resultado.
const categoriasDespesa = ['salarios', 'impostos', 'seguros', 'pedagio', 'financiamento', 'aluguel', 'administrativo', 'outros'];

String chaveMes(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Mês ("2026-10") de uma data ("2026-10-05") ou data e hora (vai para o horário local).
String? mesDe(Object? iso) {
  final s = iso?.toString() ?? '';
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return chaveMes(s.length > 10 ? d.toLocal() : d);
}

double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

class ResumoMes {
  ResumoMes(this.mes);
  final String mes;
  double receita = 0, combustivel = 0, manutencao = 0, pneus = 0, multas = 0, km = 0, litros = 0;
  final despesas = <String, double>{}; // categoria do contas a pagar → valor
  int fretes = 0;

  double get custoFrota => combustivel + manutencao + pneus + multas;
  double get outrasDespesas => despesas.values.fold(0, (s, v) => s + v);
  double get custos => custoFrota + outrasDespesas;
  double get resultado => receita - custos;
  double? get margem => receita > 0 ? resultado / receita : null;
  double? get custoKm => km > 0 ? custoFrota / km : null;
  double? get kmL => litros > 0 ? km / litros : null;

  /// Custos por categoria, do maior para o menor (nome legível → valor).
  List<(String, double)> get custosPorCategoria {
    final l = <(String, double)>[
      ('Combustível', combustivel),
      ('Manutenção', manutencao),
      ('Pneus', pneus),
      ('Multas', multas),
      for (final e in despesas.entries) (categoriasPagar[e.key]?.$1 ?? e.key, e.value),
    ]..removeWhere((x) => x.$2 <= 0);
    l.sort((a, b) => b.$2.compareTo(a.$2));
    return l;
  }
}

class LinhaVeiculo {
  LinhaVeiculo(this.vehicleId);
  final String vehicleId;
  double km = 0, litros = 0, combustivel = 0, manutencao = 0, pneus = 0, multas = 0, outras = 0, receita = 0;
  int fretes = 0;
  double get custo => combustivel + manutencao + pneus + multas + outras;
  double get resultado => receita - custo;
  double? get custoKm => km > 0 ? (combustivel + manutencao + pneus + multas) / km : null;
  double? get kmL => litros > 0 ? km / litros : null;
}

class PainelGerencial {
  PainelGerencial({required this.meses, required this.veiculos, required this.clientes});
  /// Do mais antigo ao mês escolhido (o último).
  final List<ResumoMes> meses;
  /// Ranking do mês escolhido: um por veículo da empresa.
  final List<LinhaVeiculo> veiculos;
  /// Receita do mês escolhido por cliente, da maior para a menor.
  final List<(String, double)> clientes;
  ResumoMes get atual => meses.last;
  ResumoMes? get anterior => meses.length > 1 ? meses[meses.length - 2] : null;
}

/// Variação percentual (0,12 = +12%); null sem base de comparação.
double? variacao(double atual, double? anterior) =>
    anterior == null || anterior == 0 ? null : (atual - anterior) / anterior.abs();

PainelGerencial calcularPainel({
  required DateTime mes,
  int quantosMeses = 6,
  required List<String> idsVeiculos,
  List<Map<String, dynamic>> abastecimentos = const [],
  List<Map<String, dynamic>> manutencoes = const [],
  List<Map<String, dynamic>> pneus = const [],
  List<Map<String, dynamic>> multas = const [],
  List<Map<String, dynamic>> contasPagar = const [],
  List<Map<String, dynamic>> coletas = const [],
  List<Map<String, dynamic>> ctes = const [],
  List<Map<String, dynamic>> outrasReceitas = const [],
}) {
  final chaves = [for (var i = quantosMeses - 1; i >= 0; i--) chaveMes(DateTime(mes.year, mes.month - i))];
  final porMes = {for (final k in chaves) k: ResumoMes(k)};
  final atual = chaves.last;
  final linhas = {for (final id in idsVeiculos) id: LinhaVeiculo(id)};
  final clientes = <String, double>{};
  LinhaVeiculo? linha(Object? vid, String? k) => k == atual && vid != null ? linhas[vid.toString()] : null;

  // Km e litros: trechos entre abastecimentos (mesma conta do Consumo da frota)
  calcularConsumo(abastecimentos).trechos.forEach((vid, trechos) {
    for (final t in trechos) {
      final k = mesDe(t.abastecimento['fuel_date']);
      final r = porMes[k];
      if (r == null) continue;
      r.km += t.km;
      r.litros += t.litros;
      final l = linha(vid, k);
      if (l != null) {
        l.km += t.km;
        l.litros += t.litros;
      }
    }
  });
  for (final a in abastecimentos) {
    final k = mesDe(a['fuel_date']);
    final v = _n(a['total_value']);
    porMes[k]?.combustivel += v;
    linha(a['vehicle_id'], k)?.combustivel += v;
  }
  for (final m in manutencoes) {
    final k = mesDe(m['data']);
    final v = _n(m['valor'] ?? m['cost']);
    porMes[k]?.manutencao += v;
    linha(m['vehicle_id'], k)?.manutencao += v;
  }
  for (final p in pneus) {
    final k = mesDe(p['data_instalacao']);
    final v = _n(p['valor'] ?? p['cost']);
    porMes[k]?.pneus += v;
    linha(p['vehicle_id'], k)?.pneus += v;
  }
  for (final m in multas) {
    final k = mesDe(m['data']);
    final v = _n(m['valor']);
    porMes[k]?.multas += v;
    linha(m['vehicle_id'] ?? m['veiculo_id'], k)?.multas += v;
  }
  for (final c in contasPagar) {
    final cat = (c['categoria'] ?? 'outros').toString();
    if (!categoriasDespesa.contains(cat) || c['status'] == 'cancelada') continue;
    final k = mesDe(c['vencimento']);
    final r = porMes[k];
    if (r == null) continue;
    final v = _n(c['valor']);
    r.despesas[cat] = (r.despesas[cat] ?? 0) + v;
    linha(c['vehicle_id'], k)?.outras += v;
  }
  void receita(Object? vid, String? k, double v, String? cliente) {
    final r = porMes[k];
    if (r == null || v <= 0) return;
    r.receita += v;
    r.fretes++;
    final l = linha(vid, k);
    if (l != null) {
      l.receita += v;
      l.fretes++;
    }
    if (k == atual && cliente != null) clientes[cliente] = (clientes[cliente] ?? 0) + v;
  }
  for (final c in coletas) {
    if (c['status'] != 'coletada') continue;
    receita(c['veiculo_id'], mesDe(c['coletada_em'] ?? c['data_programada']), _n(c['valor_frete']), c['clientes']?['nome']?.toString());
  }
  // CT-e sem coleta (os que têm coleta já entraram pela coleta)
  for (final c in ctes) {
    if (c['status'] != 'autorizado' || c['coleta_id'] != null) continue;
    receita(c['veiculo_id'], mesDe(c['autorizado_em']), _n(c['valor_frete']), c['remetente_nome']?.toString());
  }
  for (final r in outrasReceitas) {
    if (r['status'] == 'cancelada') continue;
    final k = mesDe(r['vencimento']);
    porMes[k]?.receita += _n(r['valor']);
  }

  final ranking = linhas.values.toList()..sort((a, b) => b.resultado.compareTo(a.resultado));
  final topo = clientes.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  return PainelGerencial(meses: [for (final k in chaves) porMes[k]!], veiculos: ranking, clientes: topo);
}

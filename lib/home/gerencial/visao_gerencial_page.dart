import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../compras/compras_page.dart';
import '../contabil/contabil_comum.dart' show competenciaRotulo, faixaUtcDoMes, nomesMes;
import '../financeiro/financeiro_page.dart';
import '../manutencoes/manutencao_comum.dart';
import '../torre/torre_controle_page.dart';
import 'gerencial_comum.dart';

/// Visão gerencial: um painel só com o resultado do mês, a evolução de 6
/// meses, o ranking dos veículos, comercial, financeiro, suprimentos e os
/// alertas — sem Power BI nem planilha. Só leitura (as contas ficam em
/// gerencial_comum.dart).
class VisaoGerencialPage extends StatefulWidget {
  const VisaoGerencialPage({super.key});

  @override
  State<VisaoGerencialPage> createState() => _VisaoGerencialPageState();
}

class _VisaoGerencialPageState extends State<VisaoGerencialPage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  DateTime mes = DateTime(DateTime.now().year, DateTime.now().month);
  bool carregando = true;
  String? erro;
  PainelGerencial? painel;
  Map<String, Map<String, dynamic>> veiculos = {}, motoristas = {};
  // comercial
  int cotacoes = 0, cotacoesAprovadas = 0;
  double valorAprovado = 0;
  // financeiro
  double receberVencido = 0, pagarVencido = 0, entra30 = 0, sai30 = 0;
  int qtdReceberVencido = 0, qtdPagarVencido = 0;
  // suprimentos
  double valorEstoque = 0, valorComprasAguardando = 0;
  int abaixoMinimo = 0, comprasAguardando = 0;
  // alertas
  List<Map<String, dynamic>> cnhVencendo = [], documentosVencendo = [];
  int osAbertas = 0, ocorrenciasAbertas = 0, viagensAndamento = 0;
  String ordem = 'resultado';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<List<Map<String, dynamic>>> _seguro(Future<List<Map<String, dynamic>>> f) async {
    try {
      return await f;
    } catch (e) {
      debugPrint('Visão gerencial (consulta opcional): $e');
      return [];
    }
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      await prepararEmpresa();
      final eid = empresaAtual;
      if (eid == null) throw Exception('sem empresa');
      final inicio = DateTime(mes.year, mes.month - 5); // 6 meses
      final fim = DateTime(mes.year, mes.month + 1);
      final ini = isoDia(inicio), fimIso = isoDia(fim);
      final iniUtc = faixaUtcDoMes(inicio).$1, fimUtc = faixaUtcDoMes(mes).$2;
      final (mesIniUtc, _) = faixaUtcDoMes(mes);
      final hoje = DateTime.now();
      final hojeIso = isoDia(hoje), daqui30 = isoDia(hoje.add(const Duration(days: 30)));
      // abastecimentos: um mês antes, para o 1º trecho de cada veículo ter de onde partir
      final iniAbast = isoDia(DateTime(inicio.year, inicio.month - 1));

      final r = await Future.wait([
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate, brand, model, driver_id').eq('empresa_id', eid).order('plate', ascending: true).order('id').range(a, b)), // 0
        fetchAllRows((a, b) => supabase.from('drivers').select('id, name, cnh_expiration').eq('empresa_id', eid).order('name', ascending: true).order('id').range(a, b)), // 1
        fetchAllRows((a, b) => supabase.from('fuelings').select('vehicle_id, fuel_date, fuel_time, liters, total_value, odometer').eq('empresa_id', eid).gte('fuel_date', iniAbast).lt('fuel_date', fimIso).order('fuel_date', ascending: true).order('id').range(a, b)), // 2
        fetchAllRows((a, b) => supabase.from('manutencoes').select('vehicle_id, data, valor, cost').eq('empresa_id', eid).gte('data', ini).lt('data', fimIso).order('id').range(a, b)), // 3
        _seguro(fetchAllRows((a, b) => supabase.from('pneus').select('vehicle_id, data_instalacao, valor, cost').eq('empresa_id', eid).gte('data_instalacao', ini).lt('data_instalacao', fimIso).order('id').range(a, b))), // 4
        _seguro(fetchAllRows((a, b) => supabase.from('multas').select('vehicle_id, veiculo_id, data, valor').eq('empresa_id', eid).gte('data', ini).lt('data', fimIso).order('id').range(a, b))), // 5
        _seguro(fetchAllRows((a, b) => supabase.from('contas_pagar').select('categoria, valor, vencimento, status, vehicle_id').eq('empresa_id', eid).gte('vencimento', ini).lt('vencimento', fimIso).neq('status', 'cancelada').order('id').range(a, b))), // 6
        _seguro(fetchAllRows((a, b) => supabase.from('coletas').select('veiculo_id, valor_frete, status, coletada_em, data_programada, clientes(nome)').eq('empresa_id', eid).eq('status', 'coletada').gte('coletada_em', iniUtc).lt('coletada_em', fimUtc).order('id').range(a, b))), // 7
        _seguro(fetchAllRows((a, b) => supabase.from('cte_documentos').select('veiculo_id, valor_frete, status, coleta_id, autorizado_em, remetente_nome, ambiente').eq('empresa_id', eid).eq('status', 'autorizado').eq('ambiente', 'producao').gte('autorizado_em', iniUtc).lt('autorizado_em', fimUtc).order('id').range(a, b))), // 8
        _seguro(fetchAllRows((a, b) => supabase.from('contas_receber').select('valor, vencimento, status').eq('empresa_id', eid).eq('categoria', 'outros').gte('vencimento', ini).lt('vencimento', fimIso).order('id').range(a, b))), // 9
        _seguro(fetchAllRows((a, b) => supabase.from('contas_receber').select('valor, vencimento').eq('empresa_id', eid).eq('status', 'aberta').lte('vencimento', daqui30).order('id').range(a, b))), // 10
        _seguro(fetchAllRows((a, b) => supabase.from('contas_pagar').select('valor, vencimento').eq('empresa_id', eid).eq('status', 'aberta').lte('vencimento', daqui30).order('id').range(a, b))), // 11
        _seguro(fetchAllRows((a, b) => supabase.from('cotacoes').select('status, valor_frete').eq('empresa_id', eid).gte('created_at', mesIniUtc).lt('created_at', fimUtc).order('id').range(a, b))), // 12
        _seguro(fetchAllRows((a, b) => supabase.from('materiais').select('estoque_atual, estoque_minimo, custo_medio').eq('empresa_id', eid).eq('ativo', true).order('id').range(a, b))), // 13
        _seguro(fetchAllRows((a, b) => supabase.from('pedidos_compra').select('valor_total').eq('empresa_id', eid).eq('status', 'aguardando').order('id').range(a, b))), // 14
        _seguro(fetchAllRows((a, b) => supabase.from('documentos').select('id, tipo, descricao, vehicle_id, driver_id, data_vencimento, validade, ativo').eq('empresa_id', eid).order('id').range(a, b))), // 15
        _seguro(fetchAllRows((a, b) => supabase.from('ordens_servico').select('id').eq('empresa_id', eid).inFilter('status', ['aberta', 'em_execucao']).order('id').range(a, b))), // 16
        _seguro(fetchAllRows((a, b) => supabase.from('occurrences').select('id').eq('empresa_id', eid).inFilter('status', ['Aberto', 'Em andamento', 'Em Andamento', 'aberto', 'em_andamento']).order('id').range(a, b))), // 17
        _seguro(fetchAllRows((a, b) => supabase.from('viagens').select('id').eq('empresa_id', eid).eq('status', 'em_progresso').order('id').range(a, b))), // 18
      ]);
      if (!mounted) return;

      final p = calcularPainel(
        mes: mes,
        idsVeiculos: [for (final v in r[0]) v['id'].toString()],
        abastecimentos: r[2],
        manutencoes: r[3],
        pneus: r[4],
        multas: r[5],
        contasPagar: r[6],
        coletas: r[7],
        ctes: r[8],
        outrasReceitas: r[9],
      );
      double soma(Iterable<Map<String, dynamic>> l, String c) => l.fold<double>(0, (s, x) => s + ((x[c] as num?) ?? 0));
      final recVencidas = r[10].where((x) => (x['vencimento'] ?? '').toString().compareTo(hojeIso) < 0);
      final pagVencidas = r[11].where((x) => (x['vencimento'] ?? '').toString().compareTo(hojeIso) < 0);
      final limiteCnh = isoDia(hoje.add(const Duration(days: 60)));
      final limiteDoc = isoDia(hoje.add(const Duration(days: 30)));
      setState(() {
        painel = p;
        veiculos = {for (final v in r[0]) v['id'].toString(): v};
        motoristas = {for (final m in r[1]) m['id'].toString(): m};
        cotacoes = r[12].length;
        cotacoesAprovadas = r[12].where((c) => c['status'] == 'aprovada').length;
        valorAprovado = soma(r[12].where((c) => c['status'] == 'aprovada'), 'valor_frete');
        receberVencido = soma(recVencidas, 'valor');
        qtdReceberVencido = recVencidas.length;
        pagarVencido = soma(pagVencidas, 'valor');
        qtdPagarVencido = pagVencidas.length;
        entra30 = soma(r[10].where((x) => (x['vencimento'] ?? '').toString().compareTo(hojeIso) >= 0), 'valor');
        sai30 = soma(r[11].where((x) => (x['vencimento'] ?? '').toString().compareTo(hojeIso) >= 0), 'valor');
        valorEstoque = r[13].fold<double>(0, (s, m) => s + ((m['estoque_atual'] as num?) ?? 0) * ((m['custo_medio'] as num?) ?? 0));
        abaixoMinimo = r[13].where((m) => ((m['estoque_minimo'] as num?) ?? 0) > 0 && ((m['estoque_atual'] as num?) ?? 0) <= ((m['estoque_minimo'] as num?) ?? 0)).length;
        comprasAguardando = r[14].length;
        valorComprasAguardando = soma(r[14], 'valor_total');
        cnhVencendo = r[1].where((d) => d['cnh_expiration'] != null && d['cnh_expiration'].toString().compareTo(limiteCnh) <= 0).toList()
          ..sort((a, b) => a['cnh_expiration'].toString().compareTo(b['cnh_expiration'].toString()));
        documentosVencendo = r[15].where((d) {
          final v = (d['data_vencimento'] ?? d['validade'])?.toString();
          return d['ativo'] != false && v != null && v.compareTo(limiteDoc) <= 0;
        }).toList();
        osAbertas = r[16].length;
        ocorrenciasAbertas = r[17].length;
        viagensAndamento = r[18].length;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro na visão gerencial: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível montar a visão gerencial.';
      });
    }
  }

  void _mudarMes(int delta) {
    final novo = DateTime(mes.year, mes.month + delta);
    if (novo.isAfter(DateTime.now())) return;
    setState(() => mes = novo);
    _carregar();
  }

  String _pct(double? v, {bool sinal = true}) =>
      v == null ? '—' : '${sinal && v > 0 ? '+' : ''}${numeroBr(v * 100, casas: 1)}%';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (auth.isMotorista || !auth.can(AppPermission.viewReports)) {
      return Scaffold(appBar: AppBar(title: const Text('Visão gerencial')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso à visão gerencial.'));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Visão gerencial'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null || painel == null
              ? vazioManut(Icons.error_outline, erro ?? 'Sem dados.')
              : RefreshIndicator(onRefresh: _carregar, child: _conteudo(auth)),
    );
  }

  Widget _conteudo(AppAuthProvider auth) {
    final p = painel!;
    final a = p.atual, ant = p.anterior;
    Widget kpi(String t, String v, String sub, Color cor) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12)),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: TextStyle(color: cor, fontSize: 19, fontWeight: FontWeight.bold))),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          ]),
        );
    final secoes = <Widget>[
      _secao('Evolução — últimos 6 meses', Icons.show_chart, _grafico(p)),
      _secao('Para onde foi o dinheiro', Icons.pie_chart_outline, _custos(a)),
      _secao('Ranking dos ${p.veiculos.length} veículos', Icons.leaderboard, _ranking(p), largo: true),
      if (auth.can(AppPermission.viewCommercial)) _secao('Comercial', Icons.handshake, _comercial(p)),
      if (auth.can(AppPermission.viewFinance)) _secao('Financeiro', Icons.account_balance_wallet, _financeiro(auth)),
      if (auth.can(AppPermission.viewSupplies)) _secao('Suprimentos', Icons.inventory_2, _suprimentos()),
      _secao('Atenção', Icons.warning_amber_rounded, _alertas()),
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
      const SizedBox(height: 10),
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Mês anterior', onPressed: () => _mudarMes(-1)),
        Expanded(child: Text(competenciaRotulo(mes), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Próximo mês',
          onPressed: DateTime(mes.year, mes.month + 1).isAfter(DateTime.now()) ? null : () => _mudarMes(1),
        ),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (ctx, c) {
        final col = c.maxWidth > 1000 ? 6 : (c.maxWidth > 620 ? 3 : 2);
        final w = (c.maxWidth - (col - 1) * 10) / col;
        final dRec = variacao(a.receita, ant?.receita), dCus = variacao(a.custos, ant?.custos);
        return Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: w, child: kpi('Receita de fretes', moedaBr(a.receita), '${a.fretes} frete(s) · ${_pct(dRec)} vs mês anterior', AppColors.success)),
          SizedBox(width: w, child: kpi('Custos', moedaBr(a.custos), '${_pct(dCus)} vs mês anterior', AppColors.danger)),
          SizedBox(width: w, child: kpi('Resultado', moedaBr(a.resultado), 'margem ${_pct(a.margem, sinal: false)}', a.resultado >= 0 ? AppColors.neon : AppColors.danger)),
          SizedBox(width: w, child: kpi('Custo por km', a.custoKm == null ? '—' : moedaBr(a.custoKm!), 'combustível + manutenção + pneus + multas', AppColors.warning)),
          SizedBox(width: w, child: kpi('Km rodados', a.km > 0 ? kmBr(a.km) : '—', 'pelo odômetro dos abastecimentos', AppColors.info)),
          SizedBox(width: w, child: kpi('Consumo médio', a.kmL == null ? '—' : '${numeroBr(a.kmL!, casas: 2)} km/l', '${numeroBr(a.litros, casas: 0)} litros', AppColors.secondary)),
        ]);
      }),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (ctx, c) {
        if (c.maxWidth < 1000) return Column(children: secoes);
        // duas colunas; o ranking ocupa a linha toda
        final linhas = <Widget>[];
        final pendentes = <Widget>[];
        void fechar() {
          if (pendentes.isEmpty) return;
          linhas.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: pendentes[0]),
            const SizedBox(width: 12),
            Expanded(child: pendentes.length > 1 ? pendentes[1] : const SizedBox()),
          ]));
          pendentes.clear();
        }
        for (final s in secoes) {
          if (s is _Secao && s.largo) {
            fechar();
            linhas.add(s);
          } else {
            pendentes.add(s);
            if (pendentes.length == 2) fechar();
          }
        }
        fechar();
        return Column(children: linhas);
      }),
      const Text(
        'Como as contas são feitas: receita = fretes das coletas realizadas e CT-e sem coleta, mais outras receitas. '
        'Combustível, manutenção, pneus e multas vêm dos registros da frota; do contas a pagar entram só as outras despesas '
        '(salários, pedágio, seguros...), para nada ser contado duas vezes. Compra de peças é estoque e vira custo quando usada na OS.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ]);
  }

  Widget _secao(String titulo, IconData icone, Widget corpo, {bool largo = false}) => _Secao(titulo: titulo, icone: icone, largo: largo, child: corpo);

  // ── Gráfico de 6 meses ────────────────────────────────────────────────────
  Widget _grafico(PainelGerencial p) {
    final maximo = p.meses.fold<double>(0, (m, r) => math.max(m, math.max(r.receita, r.custos)));
    if (maximo <= 0) return const Text('Sem lançamentos nestes meses.', style: TextStyle(color: AppColors.textSecondary));
    String rotulo(String chave) {
      final m = int.parse(chave.substring(5));
      return '${nomesMes[m - 1].substring(0, 3)}/${chave.substring(2, 4)}';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          maxY: maximo * 1.15,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.6)),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                '${ri == 0 ? 'Receita' : 'Custos'}\n${moedaBr(rod.toY)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(v >= 1000 ? '${numeroBr(v / 1000, casas: 0)} mil' : numeroBr(v, casas: 0), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(rotulo(p.meses[v.toInt()].mes), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < p.meses.length; i++)
              BarChartGroupData(x: i, barsSpace: 3, barRods: [
                BarChartRodData(toY: p.meses[i].receita, color: AppColors.success, width: 12, borderRadius: BorderRadius.circular(3)),
                BarChartRodData(toY: p.meses[i].custos, color: AppColors.danger, width: 12, borderRadius: BorderRadius.circular(3)),
              ]),
          ],
        )),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        _legenda(AppColors.success, 'Receita'),
        _legenda(AppColors.danger, 'Custos'),
        for (final r in p.meses)
          if (r.receita > 0 || r.custos > 0)
            Text('${rotulo(r.mes)}: ${moedaBr(r.resultado)}', style: TextStyle(color: r.resultado >= 0 ? AppColors.neon : AppColors.danger, fontSize: 12)),
      ]),
    ]);
  }

  Widget _legenda(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);

  // ── Custos por categoria ──────────────────────────────────────────────────
  Widget _custos(ResumoMes a) {
    final itens = a.custosPorCategoria;
    if (itens.isEmpty) return const Text('Nenhum custo lançado no mês.', style: TextStyle(color: AppColors.textSecondary));
    final total = a.custos;
    return Column(children: [
      for (final (nome, valor) in itens)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(nome)),
              Text('${moedaBr(valor)} · ${numeroBr(valor / total * 100, casas: 1)}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: valor / total, minHeight: 7, backgroundColor: AppColors.border, color: AppColors.secondary),
            ),
          ]),
        ),
    ]);
  }

  // ── Ranking por veículo ───────────────────────────────────────────────────
  Widget _ranking(PainelGerencial p) {
    final lista = [...p.veiculos];
    switch (ordem) {
      case 'custoKm':
        lista.sort((a, b) => (b.custoKm ?? -1).compareTo(a.custoKm ?? -1));
      case 'custo':
        lista.sort((a, b) => b.custo.compareTo(a.custo));
      default:
        lista.sort((a, b) => b.resultado.compareTo(a.resultado));
    }
    final semDados = lista.every((l) => l.custo == 0 && l.receita == 0 && l.km == 0);
    if (semDados) return const Text('Sem lançamentos dos veículos neste mês.', style: TextStyle(color: AppColors.textSecondary));
    TextStyle cab = const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: [
        for (final o in [('resultado', 'Maior resultado'), ('custoKm', 'Maior custo/km'), ('custo', 'Maior custo')])
          ChoiceChip(label: Text(o.$2), selected: ordem == o.$1, onSelected: (_) => setState(() => ordem = o.$1)),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columnSpacing: 22,
          columns: [
            DataColumn(label: Text('Veículo · motorista', style: cab)),
            DataColumn(label: Text('Km', style: cab), numeric: true),
            DataColumn(label: Text('km/l', style: cab), numeric: true),
            DataColumn(label: Text('Combustível', style: cab), numeric: true),
            DataColumn(label: Text('Manutenção', style: cab), numeric: true),
            DataColumn(label: Text('Custo/km', style: cab), numeric: true),
            DataColumn(label: Text('Fretes', style: cab), numeric: true),
            DataColumn(label: Text('Receita', style: cab), numeric: true),
            DataColumn(label: Text('Resultado', style: cab), numeric: true),
          ],
          rows: [
            for (final l in lista)
              DataRow(cells: [
                DataCell(Text('${veiculos[l.vehicleId]?['plate'] ?? '-'} · ${motoristas[veiculos[l.vehicleId]?['driver_id']?.toString()]?['name'] ?? 'sem motorista'}',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(l.km > 0 ? numeroBr(l.km, casas: 0) : '—')),
                DataCell(Text(l.kmL == null ? '—' : numeroBr(l.kmL!, casas: 2))),
                DataCell(Text(moedaBr(l.combustivel))),
                DataCell(Text(moedaBr(l.manutencao))),
                DataCell(Text(l.custoKm == null ? '—' : moedaBr(l.custoKm!))),
                DataCell(Text('${l.fretes}')),
                DataCell(Text(moedaBr(l.receita))),
                DataCell(Text(moedaBr(l.resultado), style: TextStyle(color: l.resultado >= 0 ? AppColors.success : AppColors.danger, fontWeight: FontWeight.bold))),
              ]),
          ],
        ),
      ),
      const SizedBox(height: 6),
      const Text('Resultado do veículo = fretes dele − custos dele (combustível, manutenção, pneus, multas e despesas lançadas no veículo). '
          'Salários e despesas sem veículo ficam no resultado geral.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
    ]);
  }

  // ── Comercial ─────────────────────────────────────────────────────────────
  Widget _comercial(PainelGerencial p) {
    final a = p.atual;
    final taxa = cotacoes > 0 ? cotacoesAprovadas / cotacoes : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _linha('Cotações no mês', '$cotacoes'),
      _linha('Aprovadas', '$cotacoesAprovadas (${_pct(taxa, sinal: false)})'),
      _linha('Valor aprovado', moedaBr(valorAprovado)),
      _linha('Fretes realizados', '${a.fretes}'),
      _linha('Ticket médio do frete', a.fretes > 0 ? moedaBr(a.receita / a.fretes) : '—'),
      if (p.clientes.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Maiores clientes do mês', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        for (final (nome, valor) in p.clientes.take(5)) _linha(nome, moedaBr(valor)),
      ],
    ]);
  }

  // ── Financeiro ────────────────────────────────────────────────────────────
  Widget _financeiro(AppAuthProvider auth) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _linha('A receber vencido', '$qtdReceberVencido · ${moedaBr(receberVencido)}', cor: receberVencido > 0 ? AppColors.danger : null),
        _linha('A pagar vencido', '$qtdPagarVencido · ${moedaBr(pagarVencido)}', cor: pagarVencido > 0 ? AppColors.warning : null),
        const Divider(color: AppColors.border),
        const Text('Próximos 30 dias', style: TextStyle(fontWeight: FontWeight.bold)),
        _linha('Entra (a receber)', moedaBr(entra30)),
        _linha('Sai (a pagar)', moedaBr(sai30)),
        _linha('Saldo previsto', moedaBr(entra30 - sai30), cor: entra30 - sai30 >= 0 ? AppColors.success : AppColors.danger),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: botaoAcao('Abrir o financeiro', Icons.open_in_new, AppColors.info,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceiroPage()))),
        ),
      ]);

  // ── Suprimentos ───────────────────────────────────────────────────────────
  Widget _suprimentos() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _linha('Valor em estoque', moedaBr(valorEstoque)),
        _linha('Materiais abaixo do mínimo', '$abaixoMinimo', cor: abaixoMinimo > 0 ? AppColors.warning : null),
        _linha('Compras aguardando aprovação', '$comprasAguardando · ${moedaBr(valorComprasAguardando)}', cor: comprasAguardando > 0 ? AppColors.warning : null),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: botaoAcao('Abrir compras', Icons.open_in_new, AppColors.info,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComprasPage()))),
        ),
      ]);

  // ── Alertas ───────────────────────────────────────────────────────────────
  Widget _alertas() {
    final hoje = isoDia(DateTime.now());
    final itens = <(bool, String)>[
      for (final d in cnhVencendo)
        (d['cnh_expiration'].toString().compareTo(hoje) < 0,
            'CNH de ${d['name']} ${d['cnh_expiration'].toString().compareTo(hoje) < 0 ? 'vencida em' : 'vence em'} ${dataBrManut(d['cnh_expiration'].toString())}'),
      for (final d in documentosVencendo)
        (((d['data_vencimento'] ?? d['validade']).toString()).compareTo(hoje) < 0,
            '${d['tipo'] ?? 'Documento'}${veiculos[d['vehicle_id']?.toString()] != null ? ' do ${veiculos[d['vehicle_id'].toString()]!['plate']}' : ''}'
                ' ${((d['data_vencimento'] ?? d['validade']).toString()).compareTo(hoje) < 0 ? 'vencido em' : 'vence em'} ${dataBrManut((d['data_vencimento'] ?? d['validade']).toString())}'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _linha('Viagens em andamento agora', '$viagensAndamento'),
      _linha('Ordens de serviço abertas', '$osAbertas', cor: osAbertas > 0 ? AppColors.warning : null),
      _linha('Ocorrências abertas', '$ocorrenciasAbertas', cor: ocorrenciasAbertas > 0 ? AppColors.warning : null),
      if (itens.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Nenhuma CNH ou documento vencendo.', style: TextStyle(color: AppColors.success))),
      for (final (vencido, texto) in itens.take(8))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: vencido ? AppColors.danger : AppColors.warning),
            const SizedBox(width: 6),
            Expanded(child: Text(texto, style: TextStyle(color: vencido ? AppColors.danger : AppColors.warning, fontSize: 13))),
          ]),
        ),
      if (itens.length > 8) Text('e mais ${itens.length - 8}...', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: botaoAcao('Abrir a torre de controle', Icons.satellite_alt_rounded, AppColors.info,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TorreControlePage()))),
      ),
    ]);
  }

  Widget _linha(String t, String v, {Color? cor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: cor)),
        ]),
      );
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.icone, required this.child, this.largo = false});
  final String titulo;
  final IconData icone;
  final Widget child;
  final bool largo;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icone, size: 18, color: AppColors.secondary),
            const SizedBox(width: 8),
            Expanded(child: Text(titulo, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15))),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

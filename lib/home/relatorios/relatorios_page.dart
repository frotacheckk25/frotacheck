import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frotacheck/core/auth/app_auth_provider.dart';
import 'package:frotacheck/core/theme/app_theme.dart';
import 'package:frotacheck/core/utils/snackbar_utils.dart';
import 'package:printing/printing.dart';
import 'relatorio_pdf_layout.dart';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  final supabase = Supabase.instance.client;

  // ── Combustível ──────────────────────────────────────────────────────────────
  double totalGastoFuel = 0;
  double totalLitros = 0;
  int qtdAbastecimentos = 0;
  double precoMedioLitro = 0;

  // ── Multas ───────────────────────────────────────────────────────────────────
  double totalMultasAbertas = 0;
  int qtdMultasAbertas = 0;
  double totalMultasTotal = 0; // abertas + pagas (exclui contestadas) — usado no Total Geral

  // ── Manutenção ───────────────────────────────────────────────────────────────
  int qtdTrocasOleo = 0;
  double totalGastoManutencao = 0;

  // ── Total Geral ──────────────────────────────────────────────────────────────
  double totalGeral = 0;

  // ── Período do relatório (para o cabeçalho do PDF) ──────────────────────────
  DateTime periodoInicio = DateTime.now();
  DateTime periodoFim = DateTime.now();

  // ── Gráfico mensal ───────────────────────────────────────────────────────────
  List<String> months = [];
  List<FlSpot> monthlyValues = [];
  double chartMaxY = 100;

  // ── Rankings ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> topVeiculos = [];
  List<Map<String, dynamic>> topMotoristas = [];

  bool carregando = true;
  bool visaoAgregada = false;

  @override
  void initState() {
    super.initState();
    _carregarRelatorio();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _shortMonth(int m) {
    const n = [
      '',
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
    ];
    return n[m.clamp(1, 12)];
  }

  String _fmtR(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _fmtChartVal(double v) {
    if (v == 0) return '';
    if (v >= 1000) return 'R\$${(v / 1000).toStringAsFixed(1)}k';
    return 'R\$${v.toInt()}';
  }

  // ── Carregamento ─────────────────────────────────────────────────────────────
  Future<void> _carregarRelatorio() async {
    setState(() => carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      visaoAgregada = eid == null && auth.isMaster;
      var fuelQ = supabase
          .from('fuelings')
          .select('liters, total_value, fuel_date, vehicles(plate), drivers(name)');
      var multaQ = supabase.from('multas').select('valor, status');
      var oilQ = supabase.from('oil_changes').select('id');
      var manutQ = supabase.from('manutencoes').select('cost, valor');
      if (eid != null) {
        fuelQ  = fuelQ.eq('empresa_id', eid);
        multaQ = multaQ.eq('empresa_id', eid);
        oilQ   = oilQ.eq('empresa_id', eid);
        manutQ = manutQ.eq('empresa_id', eid);
      }
      final results = await Future.wait([
        // Mais recentes primeiro: se o limite truncar, descarta os mais antigos,
        // não os mais recentes (bug anterior fazia o oposto).
        fuelQ.order('fuel_date', ascending: false).limit(1000),
        multaQ.limit(1000),
        oilQ.limit(1000),
        manutQ.limit(1000),
      ]);

      final fuelings = List<Map<String, dynamic>>.from(results[0]);
      final multas = List<Map<String, dynamic>>.from(results[1]);
      final oilChanges = List<Map<String, dynamic>>.from(results[2]);
      final manutencoes = List<Map<String, dynamic>>.from(results[3]);

      // ── Fuel KPIs ────────────────────────────────────────────────────────────
      double gasto = 0;
      double litros = 0;
      final Map<String, double> spendByVehicle = {};
      final Map<String, double> spendByDriver = {};
      final Map<String, double> monthlySpend = {};

      final now = DateTime.now();
      months = List.generate(6, (i) {
        final d = DateTime(now.year, now.month - 5 + i);
        return '${_shortMonth(d.month)} ${d.year.toString().substring(2)}';
      });

      DateTime? menorDataAbastecimento;
      for (final item in fuelings) {
        final v = _toDouble(item['total_value']);
        final l = _toDouble(item['liters']);
        gasto += v;
        litros += l;

        final plate = item['vehicles']?['plate']?.toString() ?? 'Sem placa';
        final driver = item['drivers']?['name']?.toString() ?? 'Sem motorista';
        spendByVehicle[plate] = (spendByVehicle[plate] ?? 0) + v;
        spendByDriver[driver] = (spendByDriver[driver] ?? 0) + v;

        final dt = DateTime.tryParse(item['fuel_date']?.toString() ?? '');
        if (dt != null) {
          final key =
              '${_shortMonth(dt.month)} ${dt.year.toString().substring(2)}';
          monthlySpend[key] = (monthlySpend[key] ?? 0) + v;
          if (menorDataAbastecimento == null || dt.isBefore(menorDataAbastecimento)) {
            menorDataAbastecimento = dt;
          }
        }
      }

      // Monthly spots — sem divisão por 1000; escala dinâmica
      final rawValues = months.map((m) => monthlySpend[m] ?? 0).toList();
      final maxVal = rawValues.isEmpty
          ? 100.0
          : rawValues.reduce((a, b) => a > b ? a : b);

      monthlyValues = List.generate(months.length, (i) {
        return FlSpot(i.toDouble(), rawValues[i]);
      });
      chartMaxY = maxVal > 0 ? maxVal * 1.3 : 100;

      // Rankings
      topVeiculos = spendByVehicle.entries
          .map((e) => {'plate': e.key, 'value': e.value})
          .toList()
        ..sort((a, b) =>
            (b['value'] as double).compareTo(a['value'] as double));

      topMotoristas = spendByDriver.entries
          .map((e) => {'name': e.key, 'value': e.value})
          .toList()
        ..sort((a, b) =>
            (b['value'] as double).compareTo(a['value'] as double));

      // ── Multas KPIs ──────────────────────────────────────────────────────────
      double multasAbertas = 0;
      int qtdAbertas = 0;
      double multasTotal = 0; // abertas + pagas — contestadas ficam de fora
      for (final m in multas) {
        final status = (m['status']?.toString() ?? 'aberta').toLowerCase();
        final valor = _toDouble(m['valor']);
        if (status == 'aberta') {
          multasAbertas += valor;
          qtdAbertas++;
        }
        if (status == 'aberta' || status == 'paga') {
          multasTotal += valor;
        }
      }

      // ── Manutenção KPIs ──────────────────────────────────────────────────────
      // Mesmo fallback já usado no dashboard principal (home_page.dart):
      // "Aberto" tem cost/valor = 0 e não distorce a soma.
      double gastoManutencao = 0;
      for (final m in manutencoes) {
        final cost = _toDouble(m['cost']);
        final valor = _toDouble(m['valor']);
        gastoManutencao += cost > 0 ? cost : valor;
      }

      if (mounted) {
        setState(() {
          totalGastoFuel = gasto;
          totalLitros = litros;
          qtdAbastecimentos = fuelings.length;
          precoMedioLitro = litros > 0 ? gasto / litros : 0;
          totalMultasAbertas = multasAbertas;
          qtdMultasAbertas = qtdAbertas;
          totalMultasTotal = multasTotal;
          qtdTrocasOleo = oilChanges.length;
          totalGastoManutencao = gastoManutencao;
          totalGeral = gasto + multasTotal + gastoManutencao;
          periodoInicio = menorDataAbastecimento ?? DateTime(now.year, now.month, 1);
          periodoFim = now;
          carregando = false;
        });
      }
    } catch (e) {
      debugPrint('Erro relatório: $e');
      if (mounted) {
        showError(context, friendlyError(e));
        setState(() => carregando = false);
      }
    }
  }

  // ── PDF ──────────────────────────────────────────────────────────────────────
  Future<Uint8List> _buildPdfBytes() async {
    final auth = context.read<AppAuthProvider>();
    final companyName = visaoAgregada
        ? 'Todas as empresas (visão agregada)'
        : (auth.empresaNome ?? 'FrotaCheck');

    return buildRelatorioPdfBytes(
      companyName: companyName,
      visaoAgregada: visaoAgregada,
      totalGeral: totalGeral,
      totalGastoFuel: totalGastoFuel,
      totalMultasTotal: totalMultasTotal,
      totalGastoManutencao: totalGastoManutencao,
      totalLitros: totalLitros,
      qtdAbastecimentos: qtdAbastecimentos,
      precoMedioLitro: precoMedioLitro,
      qtdMultasAbertas: qtdMultasAbertas,
      totalMultasAbertas: totalMultasAbertas,
      qtdManutencoes: qtdTrocasOleo,
      months: months,
      monthlyValues: monthlyValues.map((s) => s.y).toList(),
      topVeiculos: topVeiculos,
      topMotoristas: topMotoristas,
      periodoInicio: periodoInicio,
      periodoFim: periodoFim,
    );
  }

  Future<void> _exportarPDF() async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => _buildPdfBytes(),
        name:
            'Relatorio_FrotaCheck_${DateTime.now().year}.pdf',
      );
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _compartilhar() async {
    try {
      final bytes = await _buildPdfBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Relatorio_FrotaCheck_${DateTime.now().year}.pdf',
      );
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Relatórios'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarRelatorio,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarRelatorio,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (visaoAgregada)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Visão agregada Master: estes dados somam TODAS as empresas da plataforma, não uma empresa específica.',
                            style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                  // ── Header ──────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.secondary
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.analytics,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Relatórios Executivos',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Visão estratégica de consumo, custo e performance.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Total Geral (combustível + multas + manutenção) ──────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Geral',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(_fmtR(totalGeral),
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(
                                'Combustível ${_fmtR(totalGastoFuel)} · Multas ${_fmtR(totalMultasTotal)} · Manutenção ${_fmtR(totalGastoManutencao)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── KPIs Combustível ─────────────────────────────────────────
                  _sectionTitle(
                      'Combustível', Icons.local_gas_station, AppColors.secondary),
                  const SizedBox(height: 10),
                  Row(children: [
                    _kpi('Gasto Total', _fmtR(totalGastoFuel),
                        AppColors.info, Icons.attach_money),
                    const SizedBox(width: 10),
                    _kpi('Total Litros',
                        '${totalLitros.toStringAsFixed(1)} L',
                        AppColors.success, Icons.local_gas_station),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _kpi('Abastecimentos', '$qtdAbastecimentos',
                        AppColors.secondary, Icons.receipt_long),
                    const SizedBox(width: 10),
                    _kpi('Preço Médio/L',
                        _fmtR(precoMedioLitro),
                        AppColors.warning, Icons.analytics),
                  ]),
                  const SizedBox(height: 16),

                  // ── KPIs Multas + Manutenção ─────────────────────────────────
                  _sectionTitle(
                      'Multas & Manutenção', Icons.gavel, AppColors.danger),
                  const SizedBox(height: 10),
                  Row(children: [
                    _kpi(
                        'Multas Abertas',
                        '$qtdMultasAbertas multa(s) · ${_fmtR(totalMultasAbertas)}',
                        AppColors.danger,
                        Icons.gavel),
                    const SizedBox(width: 10),
                    _kpi('Manutenção', '$qtdTrocasOleo registro(s) · ${_fmtR(totalGastoManutencao)}',
                        AppColors.warning, Icons.oil_barrel),
                  ]),
                  const SizedBox(height: 16),

                  // ── Gráfico mensal ───────────────────────────────────────────
                  _sectionTitle('Tendência Mensal (Combustível)',
                      Icons.show_chart, AppColors.primary),
                  const SizedBox(height: 10),
                  _buildChart(),
                  const SizedBox(height: 16),

                  // ── Top Veículos ─────────────────────────────────────────────
                  if (topVeiculos.isNotEmpty) ...[
                    _sectionTitle('Top Veículos (por gasto em combustível)',
                        Icons.directions_car, AppColors.secondary),
                    const SizedBox(height: 10),
                    _buildRankingList(topVeiculos, 'plate'),
                    const SizedBox(height: 16),
                  ],

                  // ── Top Motoristas ───────────────────────────────────────────
                  if (topMotoristas.isNotEmpty) ...[
                    _sectionTitle('Top Motoristas (por gasto em combustível)',
                        Icons.person, AppColors.secondary),
                    const SizedBox(height: 10),
                    _buildRankingList(topMotoristas, 'name'),
                    const SizedBox(height: 16),
                  ],

                  // ── Botões PDF / Share ────────────────────────────────────────
                  _sectionTitle(
                      'Exportar', Icons.download, AppColors.textSecondary),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportarPDF,
                          icon: const Icon(Icons.picture_as_pdf,
                              color: Colors.white, size: 18),
                          label: const Text('Exportar PDF',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _compartilhar,
                          icon: const Icon(Icons.share,
                              color: AppColors.secondary, size: 18),
                          label: const Text('Compartilhar',
                              style: TextStyle(
                                  color: AppColors.secondary)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.secondary),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, IconData icon, Color color) => Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      );

  Widget _kpi(
          String label, String value, Color color, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 10),
              Text(label,
                  style: TextStyle(
                      color: color.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

  Widget _buildChart() {
    if (monthlyValues.every((s) => s.y == 0)) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart,
                  size: 40, color: AppColors.textSecondary),
              SizedBox(height: 8),
              Text('Sem dados de abastecimento',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    final double gridInterval =
        chartMaxY > 0 ? (chartMaxY / 5).ceilToDouble() : 100.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gasto em combustível por mês',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: chartMaxY,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= months.length) {
                          return const SizedBox();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(months[i],
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: gridInterval,
                      getTitlesWidget: (v, meta) {
                        if (v == 0) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(_fmtChartVal(v),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 9)),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: gridInterval,
                  getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppColors.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.backgroundSoft,
                    getTooltipItems: (spots) => spots.map((s) {
                      return LineTooltipItem(
                        '${months[s.x.toInt()]}\n${_fmtR(s.y)}',
                        const TextStyle(
                            color: Colors.white, fontSize: 11),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: monthlyValues,
                    isCurved: true,
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary]),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.15),
                          AppColors.secondary.withOpacity(0.04),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingList(
      List<Map<String, dynamic>> items, String key) {
    final colors = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
      AppColors.textSecondary,
      AppColors.textSecondary,
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.take(5).toList().asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          final cor = colors[i];
          final isLast =
              i == items.take(5).length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: cor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: cor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item[key].toString(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                    Text(_fmtR(item['value'] as double),
                        style: TextStyle(
                            color: cor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(height: 1, color: AppColors.border),
            ],
          );
        }).toList(),
      ),
    );
  }
}

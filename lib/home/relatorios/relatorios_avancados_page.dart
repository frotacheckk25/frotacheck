import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class RelatoriosAvancadosPage extends StatefulWidget {
  const RelatoriosAvancadosPage({super.key});

  @override
  State<RelatoriosAvancadosPage> createState() =>
      _RelatoriosAvancadosPageState();
}

class _RelatoriosAvancadosPageState
    extends State<RelatoriosAvancadosPage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;

  // KPIs
  double consumoMesAtual = 0;
  double gastoMesAtual = 0;
  double custoDiario = 0;
  int qtdOcorrencias = 0;

  // Gráficos
  List<String> meses = [];
  List<double> consumoPorMes = [];
  List<double> gastoPorMes = [];
  double totalFuel = 0;
  double totalMultas = 0;
  Map<String, int> ocorrenciasPorTipo = {};

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

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        supabase
            .from('fuelings')
            .select('liters, total_value, fuel_date'),
        supabase.from('multas').select('valor'),
        // Tabela correta: occurrences (não ocorrencias)
        supabase.from('occurrences').select('problem_type, status'),
      ]);

      final fuelings = List<Map<String, dynamic>>.from(results[0]);
      final multas = List<Map<String, dynamic>>.from(results[1]);
      final ocorrencias = List<Map<String, dynamic>>.from(results[2]);

      final now = DateTime.now();

      // ── Agregação mensal dos últimos 6 meses ─────────────────────────────
      final Map<String, double> consumoMes = {};
      final Map<String, double> gastoMes = {};

      for (final item in fuelings) {
        final dt =
            DateTime.tryParse(item['fuel_date']?.toString() ?? '');
        if (dt == null) continue;
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        consumoMes[key] = (consumoMes[key] ?? 0) +
            _toDouble(item['liters']);
        gastoMes[key] = (gastoMes[key] ?? 0) +
            _toDouble(item['total_value']);
      }

      final mesesLabels = <String>[];
      final consumoList = <double>[];
      final gastoList = <double>[];

      for (int i = 5; i >= 0; i--) {
        final d = DateTime(now.year, now.month - i);
        final key =
            '${d.year}-${d.month.toString().padLeft(2, '0')}';
        mesesLabels.add(_shortMonth(d.month));
        consumoList.add(consumoMes[key] ?? 0);
        gastoList.add(gastoMes[key] ?? 0);
      }

      // Mês atual
      final currentKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final gastoAtual = gastoMes[currentKey] ?? 0;
      final consumoAtual = consumoMes[currentKey] ?? 0;
      final diasPassados = now.day;
      final custoDiarioCalc =
          diasPassados > 0 ? gastoAtual / diasPassados : 0.0;

      // ── Total combustível (histórico) ─────────────────────────────────────
      double totalFuelCalc = 0;
      for (final item in fuelings) {
        totalFuelCalc += _toDouble(item['total_value']);
      }

      // ── Total multas (histórico) ──────────────────────────────────────────
      double totalMultasCalc = 0;
      for (final m in multas) {
        totalMultasCalc += _toDouble(m['valor']);
      }

      // ── Ocorrências por tipo ──────────────────────────────────────────────
      // Usa problem_type (campo correto na tabela occurrences)
      final Map<String, int> tiposMap = {};
      for (final o in ocorrencias) {
        final tipo =
            o['problem_type']?.toString().trim() ?? 'Outros';
        final label = tipo.isNotEmpty ? tipo : 'Outros';
        tiposMap[label] = (tiposMap[label] ?? 0) + 1;
      }

      // Limitar a top 6 para o gráfico
      final sortedTipos = tiposMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top6 = Map.fromEntries(sortedTipos.take(6));

      if (mounted) {
        setState(() {
          meses = mesesLabels;
          consumoPorMes = consumoList;
          gastoPorMes = gastoList;
          consumoMesAtual = consumoAtual;
          gastoMesAtual = gastoAtual;
          custoDiario = custoDiarioCalc;
          totalFuel = totalFuelCalc;
          totalMultas = totalMultasCalc;
          qtdOcorrencias = ocorrencias.length;
          ocorrenciasPorTipo = top6;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro relatórios avançados: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Relatórios Avançados'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarDados,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── KPIs ──────────────────────────────────────────────────
                  _sectionTitle('Resumo do Período',
                      Icons.dashboard_outlined, AppColors.secondary),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.8,
                    children: [
                      _buildCard(
                        'Consumo Mês Atual',
                        '${consumoMesAtual.toStringAsFixed(1)} L',
                        AppColors.secondary,
                        Icons.local_gas_station,
                      ),
                      _buildCard(
                        'Gasto Mês Atual',
                        _fmtR(gastoMesAtual),
                        AppColors.danger,
                        Icons.attach_money,
                      ),
                      _buildCard(
                        'Custo Diário',
                        _fmtR(custoDiario),
                        AppColors.warning,
                        Icons.calendar_today,
                        subtitle:
                            'Baseado em ${DateTime.now().day} dias',
                      ),
                      _buildCard(
                        'Ocorrências',
                        '$qtdOcorrencias total',
                        const Color(0xFF8B5CF6),
                        Icons.warning_amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Gráfico consumo mensal ────────────────────────────────
                  _sectionTitle('Consumo Mensal (Litros)',
                      Icons.bar_chart, AppColors.secondary),
                  const SizedBox(height: 10),
                  _buildConsumoMensal(),
                  const SizedBox(height: 20),

                  // ── Gráfico gasto mensal ──────────────────────────────────
                  _sectionTitle('Gasto Mensal em Combustível (R\$)',
                      Icons.show_chart, AppColors.info),
                  const SizedBox(height: 10),
                  _buildGastoMensal(),
                  const SizedBox(height: 20),

                  // ── Pie chart distribuição ────────────────────────────────
                  if (totalFuel > 0 || totalMultas > 0) ...[
                    _sectionTitle(
                        'Distribuição de Gastos (histórico)',
                        Icons.pie_chart,
                        AppColors.warning),
                    const SizedBox(height: 10),
                    _buildDistribuicao(),
                    const SizedBox(height: 20),
                  ],

                  // ── Gráfico ocorrências ───────────────────────────────────
                  if (ocorrenciasPorTipo.isNotEmpty) ...[
                    _sectionTitle('Ocorrências por Tipo',
                        Icons.bug_report, const Color(0xFF8B5CF6)),
                    const SizedBox(height: 10),
                    _buildOcorrencias(),
                    const SizedBox(height: 20),
                  ] else
                    _emptyCard('Nenhuma ocorrência registrada',
                        Icons.bug_report),
                ],
              ),
            ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, IconData icon, Color color) =>
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ]);

  Widget _buildCard(
    String label,
    String value,
    Color color,
    IconData icon, {
    String? subtitle,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: color.withOpacity(0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (subtitle != null)
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 9),
                  maxLines: 1),
          ],
        ),
      );

  Widget _buildConsumoMensal() {
    final maxConsumo = consumoPorMes.isEmpty
        ? 1.0
        : consumoPorMes.reduce((a, b) => a > b ? a : b);
    final hasData = consumoPorMes.any((v) => v > 0);

    if (!hasData) {
      return _emptyCard('Sem dados de consumo nos últimos 6 meses',
          Icons.local_gas_station);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxConsumo > 0 ? maxConsumo * 1.25 : 10,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.backgroundSoft,
                getTooltipItem: (group, _, rod, _) =>
                    BarTooltipItem(
                  '${meses[group.x]}\n${rod.toY.toStringAsFixed(1)} L',
                  const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (v, meta) {
                    if (v == 0) return const SizedBox();
                    return Text('${v.toInt()}L',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9));
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= meses.length) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(meses[i],
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => const FlLine(
                  color: AppColors.border, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(
              meses.length,
              (i) => BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: consumoPorMes[i],
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.secondary,
                        AppColors.info,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    width: 22,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGastoMensal() {
    final maxGasto = gastoPorMes.isEmpty
        ? 1.0
        : gastoPorMes.reduce((a, b) => a > b ? a : b);
    final hasData = gastoPorMes.any((v) => v > 0);

    if (!hasData) {
      return _emptyCard('Sem dados de gasto nos últimos 6 meses',
          Icons.attach_money);
    }

    String fmtAxis(double v) {
      if (v >= 1000) return 'R\$${(v / 1000).toStringAsFixed(1)}k';
      return 'R\$${v.toInt()}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxGasto > 0 ? maxGasto * 1.25 : 100,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.backgroundSoft,
                getTooltipItem: (group, _, rod, _) =>
                    BarTooltipItem(
                  '${meses[group.x]}\n${_fmtR(rod.toY)}',
                  const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 46,
                  getTitlesWidget: (v, meta) {
                    if (v == 0) return const SizedBox();
                    return Text(fmtAxis(v),
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9));
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= meses.length) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(meses[i],
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => const FlLine(
                  color: AppColors.border, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(
              meses.length,
              (i) => BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: gastoPorMes[i],
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.danger,
                        AppColors.warning,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    width: 22,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistribuicao() {
    final total = totalFuel + totalMultas;
    if (total == 0) {
      return _emptyCard('Sem dados para distribuição', Icons.pie_chart);
    }

    final pctFuel = totalFuel / total * 100;
    final pctMultas = totalMultas / total * 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: [
                  if (totalFuel > 0)
                    PieChartSectionData(
                      value: totalFuel,
                      title: 'Comb.\n${pctFuel.toStringAsFixed(1)}%',
                      color: AppColors.secondary,
                      radius: 55,
                      titleStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  if (totalMultas > 0)
                    PieChartSectionData(
                      value: totalMultas,
                      title:
                          'Multas\n${pctMultas.toStringAsFixed(1)}%',
                      color: AppColors.danger,
                      radius: 55,
                      titleStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                ],
                pieTouchData: PieTouchData(
                  touchCallback: (_, _) {},
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legenda
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (totalFuel > 0) ...[
                _legendItem(AppColors.secondary, 'Combustível',
                    _fmtR(totalFuel)),
                const SizedBox(width: 20),
              ],
              if (totalMultas > 0)
                _legendItem(
                    AppColors.danger, 'Multas', _fmtR(totalMultas)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label, String value) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      );

  Widget _buildOcorrencias() {
    final tipos = ocorrenciasPorTipo.keys.toList();
    final valores = ocorrenciasPorTipo.values.toList();
    final maxValor = valores.isEmpty
        ? 1.0
        : valores.reduce((a, b) => a > b ? a : b).toDouble();

    final barColors = [
      AppColors.danger,
      AppColors.warning,
      const Color(0xFF8B5CF6),
      AppColors.secondary,
      AppColors.success,
      AppColors.info,
    ];

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
          SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValor + 2,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.backgroundSoft,
                    getTooltipItem: (group, _, rod, _) =>
                        BarTooltipItem(
                      '${tipos[group.x]}\n${rod.toY.toInt()} ocorrências',
                      const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        if (v == 0 || v != v.roundToDouble()) {
                          return const SizedBox();
                        }
                        return Text('${v.toInt()}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= tipos.length) {
                          return const SizedBox();
                        }
                        final label = tipos[i];
                        final short = label.length > 10
                            ? '${label.substring(0, 9)}…'
                            : label;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(short,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 9),
                              textAlign: TextAlign.center),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppColors.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  tipos.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: valores[i].toDouble(),
                        color: barColors[i % barColors.length],
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legenda
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: List.generate(tipos.length, (i) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: barColors[i % barColors.length],
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                      '${tipos[i]} (${valores[i]})',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String message, IconData icon) => Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: AppColors.textSecondary),
              const SizedBox(height: 8),
              Text(message,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
}

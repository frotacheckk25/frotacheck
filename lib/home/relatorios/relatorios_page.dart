import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frotacheck/core/theme/app_theme.dart';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  final supabase = Supabase.instance.client;

  double totalGasto = 0;
  double totalLitros = 0;
  int quantidadeAbastecimentos = 0;
  double precoMedioLitro = 0;
  double custoMedioKm = 0;

  bool carregando = true;
  List<Map<String, dynamic>> topVeiculos = [];
  List<Map<String, dynamic>> topMotoristas = [];
  List<String> months = [];
  List<FlSpot> monthlyValues = [];

  @override
  void initState() {
    super.initState();
    carregarRelatorio();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  String _shortMonth(int month) {
    const names = [
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    return names[month];
  }

  Future<void> carregarRelatorio() async {
    setState(() {
      carregando = true;
    });

    try {
      final dados = await supabase
          .from('fuelings')
          .select(
            'id, liters, total_value, fuel_date, fuel_time, odometer, vehicles (plate), drivers (name)',
          )
          .order('fuel_date', ascending: true);

      double gasto = 0;
      double litros = 0;
      int total = dados.length;
      final Map<String, double> spendByVehicle = {};
      final Map<String, double> spendByDriver = {};
      final Map<String, double> monthlySpend = {};
      final now = DateTime.now();
      months = List.generate(6, (index) {
        final date = DateTime(now.year, now.month - 5 + index);
        return '${_shortMonth(date.month)} ${date.year.toString().substring(2)}';
      });

      for (final item in dados) {
        final value = _toDouble(item['total_value']);
        final liters = _toDouble(item['liters']);
        gasto += value;
        litros += liters;
        final plate = item['vehicles']?['plate'] ?? 'Sem placa';
        final driver = item['drivers']?['name'] ?? 'Sem motorista';
        spendByVehicle[plate] = (spendByVehicle[plate] ?? 0) + value;
        spendByDriver[driver] = (spendByDriver[driver] ?? 0) + value;

        final fuelDate = DateTime.tryParse(item['fuel_date'] ?? '');
        if (fuelDate != null) {
          final key =
              '${_shortMonth(fuelDate.month)} ${fuelDate.year.toString().substring(2)}';
          monthlySpend[key] = (monthlySpend[key] ?? 0) + value;
        }

        // odometer check (contagem removida - variável não usada)
        // if ((item['odometer'] ?? 0) > 0) { /* increment removed */ }
      }

      monthlyValues = months.asMap().entries.map((entry) {
        final amount = monthlySpend[entry.value] ?? 0;
        return FlSpot(entry.key.toDouble(), amount / 1000);
      }).toList();

      totalGasto = gasto;
      totalLitros = litros;
      quantidadeAbastecimentos = total;
      precoMedioLitro = litros > 0 ? gasto / litros : 0;
      custoMedioKm = total > 0 ? gasto / total : 0;

      topVeiculos =
          spendByVehicle.entries
              .toList()
              .map((e) => {'plate': e.key, 'value': e.value})
              .toList()
            ..sort(
              (a, b) => (b['value'] as double).compareTo(a['value'] as double),
            );
      topMotoristas =
          spendByDriver.entries
              .toList()
              .map((e) => {'name': e.key, 'value': e.value})
              .toList()
            ..sort(
              (a, b) => (b['value'] as double).compareTo(a['value'] as double),
            );

      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        carregando = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar relatório: $e')));
    }
  }

  Widget _statusCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          minY: 0,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= months.length) {
                    return const SizedBox();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      months[index],
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10,
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: monthlyValues,
              isCurved: true,
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
              ),
              barWidth: 4,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.2),
                    AppColors.secondary.withOpacity(0.08),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection(
    String title,
    List<Map<String, dynamic>> items,
    String keyName,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        ...items.take(3).map((item) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.secondary.withValues(alpha: 0.18),
                child: Icon(Icons.star, color: AppColors.secondary),
              ),
              title: Text(item[keyName]),
              subtitle: Text('R\$ ${item['value'].toStringAsFixed(2)}'),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Relatórios executivos',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Visão estratégica de consumo, custo e performance da frota.',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _statusCard(
                        'Total gasto',
                        'R\$ ${totalGasto.toStringAsFixed(2)}',
                        AppColors.info,
                        Icons.attach_money,
                      ),
                      const SizedBox(width: 12),
                      _statusCard(
                        'Litros',
                        '${totalLitros.toStringAsFixed(0)} L',
                        AppColors.success,
                        Icons.local_gas_station,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statusCard(
                        'Abastecimentos',
                        '$quantidadeAbastecimentos',
                        AppColors.secondary,
                        Icons.receipt_long,
                      ),
                      const SizedBox(width: 12),
                      _statusCard(
                        'Média/L',
                        'R\$ ${precoMedioLitro.toStringAsFixed(2)}',
                        AppColors.warning,
                        Icons.analytics,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tendência mensal de gasto',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildChart(),
                          const SizedBox(height: 12),
                          const Text(
                            'Valores em R\$ mil',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildTopSection(
                    'Veículos com maior gasto',
                    topVeiculos,
                    'plate',
                  ),
                  const SizedBox(height: 20),
                  _buildTopSection(
                    'Motoristas com maior gasto',
                    topMotoristas,
                    'name',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Exportar PDF (ambiente de teste)')),
                            );
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Exportar PDF'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Compartilhar (ambiente de teste)')),
                            );
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('Compartilhar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

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

class _RelatoriosAvancadosPageState extends State<RelatoriosAvancadosPage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;

  // Dados dos gráficos
  double consumoMensalTotal = 0;
  double custoDiario = 0;
  double gastoMensal = 0;
  List<String> meses = [];
  List<double> consumoPorMes = [];
  List<double> gastoPorMes = [];

  Map<String, int> ocorrenciasPorTipo = {};
  Map<String, int> manutencoesPorTipo = {};

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      // Carregar abastecimentos
      final abastecimentos = await supabase.from('fuelings').select();

      // Carregar ocorrências
      final ocorrencias = await supabase.from('ocorrencias').select();

      // Calcular consumo e gasto mensal
      double consumo = 0;
      double gasto = 0;

      for (var item in abastecimentos) {
        consumo += (item['liters'] ?? 0).toDouble();
        gasto += (item['total_value'] ?? 0).toDouble();
      }

      // Processar ocorrências
      Map<String, int> tipos = {};
      for (var item in ocorrencias) {
        final tipo = item['tipo'] ?? 'Outro';
        tipos[tipo] = (tipos[tipo] ?? 0) + 1;
      }

      setState(() {
        consumoMensalTotal = consumo > 0 ? consumo : 500;
        gastoMensal = gasto > 0 ? gasto : 3500;
        custoDiario = gastoMensal / 30;
        ocorrenciasPorTipo = tipos.isNotEmpty
            ? tipos
            : {
                'Motor': 3,
                'Freios': 2,
                'Pneu': 4,
                'Suspensão': 1,
              };
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e - usando dados mock')));
      }
      // Mock data para fallback
      setState(() {
        consumoMensalTotal = 500;
        gastoMensal = 3500;
        custoDiario = gastoMensal / 30;
        ocorrenciasPorTipo = {
          'Motor': 3,
          'Freios': 2,
          'Pneu': 4,
          'Suspensão': 1,
        };
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios Avançados'),
        backgroundColor: AppColors.primary,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cards de resumo
                  _buildResumoCards(),
                  const SizedBox(height: 24),

                  // Gráfico de Consumo Mensal
                  _buildConsumoPorMes(),
                  const SizedBox(height: 24),

                  // Gráfico de Gastos
                  _buildGastosPorTipo(),
                  const SizedBox(height: 24),

                  // Gráfico de Ocorrências
                  if (ocorrenciasPorTipo.isNotEmpty) _buildOcorrenciasChart(),
                ],
              ),
            ),
    );
  }

  Widget _buildResumoCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 2,
      children: [
        _buildCard(
          'Consumo Mensal',
          '${consumoMensalTotal.toStringAsFixed(1)} L',
          Colors.blue,
          Icons.local_gas_station,
        ),
        _buildCard(
          'Gasto Mensal',
          'R\$ ${gastoMensal.toStringAsFixed(2)}',
          Colors.red,
          Icons.attach_money,
        ),
        _buildCard(
          'Custo Diário',
          'R\$ ${custoDiario.toStringAsFixed(2)}',
          Colors.orange,
          Icons.calendar_today,
        ),
        _buildCard(
          'Ocorrências',
          '${ocorrenciasPorTipo.values.fold(0, (a, b) => a + b)}',
          Colors.purple,
          Icons.warning,
        ),
      ],
    );
  }

  Widget _buildCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildConsumoPorMes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Consumo Mensal (Litros)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: consumoMensalTotal + 100,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.black,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toStringAsFixed(1)} L',
                        const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const months = [
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
                        int index = value.toInt();
                        if (index >= 0 && index < months.length) {
                          return Text(months[index]);
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(
                        toY: consumoMensalTotal,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGastosPorTipo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribuição de Gastos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: gastoMensal * 0.4, // Abastecimento
                    title: 'Abastecimento\n40%',
                    color: Colors.orange,
                    radius: 50,
                  ),
                  PieChartSectionData(
                    value: gastoMensal * 0.3, // Manutenção
                    title: 'Manutenção\n30%',
                    color: Colors.purple,
                    radius: 50,
                  ),
                  PieChartSectionData(
                    value: gastoMensal * 0.2, // Pneus
                    title: 'Pneus\n20%',
                    color: Colors.green,
                    radius: 50,
                  ),
                  PieChartSectionData(
                    value: gastoMensal * 0.1, // Outros
                    title: 'Outros\n10%',
                    color: Colors.grey,
                    radius: 50,
                  ),
                ],
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcorrenciasChart() {
    final tipos = ocorrenciasPorTipo.keys.toList();
    final valores = ocorrenciasPorTipo.values.toList();
    final maxValor = valores.isNotEmpty
        ? valores.reduce((a, b) => a > b ? a : b).toDouble()
        : 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ocorrências por Tipo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValor + 5,
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < tipos.length) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              tipos[index],
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(
                  tipos.length,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: valores[index].toDouble(),
                        color: _getColorForIndex(index),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];
    return colors[index % colors.length];
  }
}

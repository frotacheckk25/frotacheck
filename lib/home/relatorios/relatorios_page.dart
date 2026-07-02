import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frotacheck/core/auth/app_auth_provider.dart';
import 'package:frotacheck/core/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  // ── Manutenção ───────────────────────────────────────────────────────────────
  int qtdTrocasOleo = 0;

  // ── Gráfico mensal ───────────────────────────────────────────────────────────
  List<String> months = [];
  List<FlSpot> monthlyValues = [];
  double chartMaxY = 100;

  // ── Rankings ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> topVeiculos = [];
  List<Map<String, dynamic>> topMotoristas = [];

  bool carregando = true;

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

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
      var fuelQ = supabase
          .from('fuelings')
          .select('liters, total_value, fuel_date, vehicles(plate), drivers(name)');
      var multaQ = supabase.from('multas').select('valor, status');
      var oilQ = supabase.from('oil_changes').select('id');
      if (eid != null) {
        fuelQ  = fuelQ.eq('empresa_id', eid);
        multaQ = multaQ.eq('empresa_id', eid);
        oilQ   = oilQ.eq('empresa_id', eid);
      }
      final results = await Future.wait([
        fuelQ.order('fuel_date', ascending: true),
        multaQ,
        oilQ,
      ]);

      final fuelings = List<Map<String, dynamic>>.from(results[0]);
      final multas = List<Map<String, dynamic>>.from(results[1]);
      final oilChanges = List<Map<String, dynamic>>.from(results[2]);

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
      for (final m in multas) {
        if ((m['status']?.toString() ?? 'aberta').toLowerCase() == 'aberta') {
          multasAbertas += _toDouble(m['valor']);
          qtdAbertas++;
        }
      }

      if (mounted) {
        setState(() {
          totalGastoFuel = gasto;
          totalLitros = litros;
          qtdAbastecimentos = fuelings.length;
          precoMedioLitro = litros > 0 ? gasto / litros : 0;
          totalMultasAbertas = multasAbertas;
          qtdMultasAbertas = qtdAbertas;
          qtdTrocasOleo = oilChanges.length;
          carregando = false;
        });
      }
    } catch (e) {
      debugPrint('Erro relatório: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
        setState(() => carregando = false);
      }
    }
  }

  // ── PDF ──────────────────────────────────────────────────────────────────────
  Future<Uint8List> _buildPdfBytes() async {
    final doc = pw.Document();

    pw.TextStyle bold(double size) =>
        pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size);
    pw.TextStyle normal(double size) => pw.TextStyle(fontSize: size);
    pw.TextStyle grey(double size) =>
        pw.TextStyle(fontSize: size, color: PdfColors.grey700);

    pw.Widget kpiRow(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            children: [
              pw.Expanded(child: pw.Text(label, style: normal(11))),
              pw.Text(value, style: bold(11)),
            ],
          ),
        );

    pw.Widget rankRow(int pos, String name, double value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            children: [
              pw.SizedBox(
                  width: 20,
                  child: pw.Text('$pos.', style: grey(10))),
              pw.Expanded(child: pw.Text(name, style: normal(10))),
              pw.Text(_fmtR(value), style: bold(10)),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey400))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('FrotaCheck — Relatório de Frota', style: bold(16)),
              pw.Text('Gerado em ${_fmtDate(DateTime.now())}',
                  style: grey(10)),
            ],
          ),
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: grey(9)),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 18),

          // ── KPIs Combustível ────────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Combustível', style: bold(14)),
                pw.SizedBox(height: 8),
                kpiRow('Total gasto em combustível',
                    _fmtR(totalGastoFuel)),
                kpiRow('Total de litros abastecidos',
                    '${totalLitros.toStringAsFixed(1)} L'),
                kpiRow('Número de abastecimentos',
                    '$qtdAbastecimentos'),
                kpiRow('Preço médio por litro',
                    _fmtR(precoMedioLitro)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // ── Multas + Manutenção ─────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Multas & Manutenção', style: bold(14)),
                pw.SizedBox(height: 8),
                kpiRow('Multas abertas (qtd)', '$qtdMultasAbertas'),
                kpiRow('Valor total de multas abertas',
                    _fmtR(totalMultasAbertas)),
                kpiRow('Trocas de óleo registradas',
                    '$qtdTrocasOleo'),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // ── Gasto mensal ────────────────────────────────────────────────────
          pw.Text('Gasto mensal (combustível)', style: bold(14)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Mês', style: bold(10))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Valor', style: bold(10))),
                ],
              ),
              ...List.generate(months.length, (i) {
                return pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(months[i], style: normal(10))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                          _fmtR(monthlyValues.isNotEmpty
                              ? monthlyValues[i].y
                              : 0),
                          style: normal(10))),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 12),

          // ── Top Veículos ────────────────────────────────────────────────────
          if (topVeiculos.isNotEmpty) ...[
            pw.Text('Top veículos por gasto em combustível',
                style: bold(14)),
            pw.SizedBox(height: 8),
            ...topVeiculos.take(5).toList().asMap().entries.map((e) {
              return rankRow(e.key + 1,
                  e.value['plate'].toString(),
                  e.value['value'] as double);
            }),
            pw.SizedBox(height: 12),
          ],

          // ── Top Motoristas ──────────────────────────────────────────────────
          if (topMotoristas.isNotEmpty) ...[
            pw.Text('Top motoristas por gasto em combustível',
                style: bold(14)),
            pw.SizedBox(height: 8),
            ...topMotoristas.take(5).toList().asMap().entries.map((e) {
              return rankRow(e.key + 1,
                  e.value['name'].toString(),
                  e.value['value'] as double);
            }),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _exportarPDF() async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => _buildPdfBytes(),
        name:
            'Relatorio_FrotaCheck_${DateTime.now().year}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao exportar PDF: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao compartilhar: $e')));
      }
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
                        '$qtdMultasAbertas multa(s)\n${_fmtR(totalMultasAbertas)}',
                        AppColors.danger,
                        Icons.gavel),
                    const SizedBox(width: 10),
                    _kpi('Trocas de Óleo', '$qtdTrocasOleo registros',
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/relatorios/relatorio_pdf_layout.dart';

/// Gera o PDF do relatório com dados de uma frota grande e confere que sai
/// um PDF válido (o botão "Exportar PDF" usa exatamente esta função).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('texto do PDF troca caracteres fora da fonte e mantém acentos', () {
    expect(pdfTextoSeguro('Horizonte — Logística “Sul” 🚚'), 'Horizonte - Logística "Sul" ');
    expect(pdfTextoSeguro('Manutenção São João'), 'Manutenção São João');
  });

  test('relatório PDF é gerado com dados de frota grande', () async {
    final meses = ['Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out'];
    final bytes = await buildRelatorioPdfBytes(
      companyName: 'Transportes Horizonte — Logística & Distribuição',
      visaoAgregada: false,
      totalGeral: 1254321.87,
      totalGastoFuel: 1102345.10,
      totalMultasTotal: 12450.00,
      totalGastoManutencao: 139526.77,
      totalLitros: 182340.5,
      qtdAbastecimentos: 8500,
      precoMedioLitro: 6.05,
      qtdMultasAbertas: 14,
      totalMultasAbertas: 4870.50,
      qtdManutencoes: 1500,
      months: meses,
      monthlyValues: [180000, 195000, 210500, 220000, 205321.87, 243500],
      topVeiculos: [
        for (var i = 0; i < 500; i++) {'plate': 'LTA${i.toString().padLeft(4, '0')}', 'value': 5000.0 - i},
      ],
      topMotoristas: [
        {'name': 'João Batista Silva', 'value': 4200.0},
        {'name': 'Marcos Antônio Rocha', 'value': 3900.0},
        {'name': 'Fernanda Costa', 'value': 3100.0},
      ],
      periodoInicio: DateTime(2026, 5, 1),
      periodoFim: DateTime(2026, 10, 19),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000));
    final out = Platform.environment['RELATORIO_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}

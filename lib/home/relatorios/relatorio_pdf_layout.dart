import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Visual layout for the "Relatório Executivo de Frota" PDF, modeled on the
// reference design supplied by the client. Deliberately avoids embedding any
// icon font: Google Fonts' hosted "Material Icons" TTF uses GSUB ligatures
// (type the name, not a codepoint) while Flutter's bundled Material Icons
// font is CFF-flavored OTF, which the `pdf` package's unicode/TTF detection
// (sfnt magic check) treats as non-unicode and crashes on any codepoint
// above 0xFF. Hand-drawn shapes sidestep both problems entirely.

PdfColor _c(int argb) => PdfColor.fromInt(argb);

final _navy = _c(0xFF0D1B3A);
final _blueBrand = _c(0xFF2563EB);
final _primary = _c(0xFF0D47A1);
final _secondary = _c(0xFF00B8D4);
final _success = _c(0xFF1AA251);
final _warning = _c(0xFFF59E0B);
final _info = _c(0xFF2563EB);
final _slate = _c(0xFF64748B);
final _slateLight = _c(0xFF94A3B8);

PdfColor _tint(PdfColor base, double towardsWhite) {
  double mix(double channel) => channel + (1 - channel) * towardsWhite;
  return PdfColor(mix(base.red), mix(base.green), mix(base.blue));
}

String _fmtR(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtDateTime(DateTime d) =>
    '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// ── Hand-drawn glyphs ────────────────────────────────────────────────────

pw.Widget _glyphCalendar(double size, PdfColor color) {
  return pw.Container(
    width: size,
    height: size,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: size * 0.09),
      borderRadius: pw.BorderRadius.circular(size * 0.16),
    ),
    child: pw.Column(children: [
      pw.Container(
        height: size * 0.32,
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.only(
            topLeft: pw.Radius.circular(size * 0.10),
            topRight: pw.Radius.circular(size * 0.10),
          ),
        ),
      ),
    ]),
  );
}

pw.Widget _glyphFuel(double size, PdfColor color) {
  return pw.SizedBox(
    width: size,
    height: size,
    child: pw.Stack(children: [
      pw.Positioned(
        left: size * 0.12,
        top: size * 0.08,
        child: pw.Container(
          width: size * 0.52,
          height: size * 0.84,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(size * 0.12),
          ),
        ),
      ),
      pw.Positioned(
        right: size * 0.10,
        top: size * 0.30,
        child: pw.Container(
          width: size * 0.26,
          height: size * 0.26,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
      ),
    ]),
  );
}

pw.Widget _glyphDoc(double size, PdfColor color) {
  return pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    children: [
      pw.Container(
        width: size * 0.34,
        height: size * 0.12,
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(size * 0.04),
        ),
      ),
      pw.SizedBox(height: size * 0.04),
      pw.Container(
        width: size * 0.72,
        height: size * 0.66,
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(size * 0.10),
        ),
      ),
    ],
  );
}

pw.Widget _glyphWallet(double size, PdfColor color) {
  return pw.Stack(children: [
    pw.Container(
      width: size * 0.82,
      height: size * 0.62,
      margin: pw.EdgeInsets.only(top: size * 0.19),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(size * 0.10),
      ),
    ),
    pw.Positioned(
      right: size * 0.02,
      top: size * 0.36,
      child: pw.Container(
        width: size * 0.20,
        height: size * 0.20,
        decoration: pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
      ),
    ),
  ]);
}

pw.Widget _glyphCar(double size, PdfColor color) {
  return pw.SizedBox(
    width: size,
    height: size,
    child: pw.Stack(children: [
      pw.Positioned(
        left: size * 0.06,
        top: size * 0.28,
        child: pw.Container(
          width: size * 0.88,
          height: size * 0.34,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(size * 0.16),
          ),
        ),
      ),
      pw.Positioned(
        left: size * 0.24,
        top: size * 0.14,
        child: pw.Container(
          width: size * 0.52,
          height: size * 0.24,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.only(
              topLeft: pw.Radius.circular(size * 0.14),
              topRight: pw.Radius.circular(size * 0.14),
            ),
          ),
        ),
      ),
      pw.Positioned(
        left: size * 0.14,
        bottom: size * 0.10,
        child: pw.Container(
          width: size * 0.20,
          height: size * 0.20,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
      ),
      pw.Positioned(
        right: size * 0.14,
        bottom: size * 0.10,
        child: pw.Container(
          width: size * 0.20,
          height: size * 0.20,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
      ),
    ]),
  );
}

pw.Widget _glyphPerson(double size, PdfColor color) {
  return pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    children: [
      pw.Container(
        width: size * 0.36,
        height: size * 0.36,
        decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
      ),
      pw.SizedBox(height: size * 0.06),
      pw.Container(
        width: size * 0.7,
        height: size * 0.32,
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.only(
            topLeft: pw.Radius.circular(size * 0.35),
            topRight: pw.Radius.circular(size * 0.35),
          ),
        ),
      ),
    ],
  );
}

pw.Widget _glyphChart(double size, PdfColor color) {
  const heights = [0.45, 0.75, 1.0];
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: heights.map((h) {
      return pw.Container(
        width: size * 0.16,
        height: size * 0.8 * h,
        margin: pw.EdgeInsets.symmetric(horizontal: size * 0.05),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(size * 0.04),
        ),
      );
    }).toList(),
  );
}

pw.Widget _glyphTruck(double size, PdfColor color) {
  return pw.Center(
    child: pw.Text('F',
        style:
            pw.TextStyle(fontSize: size * 0.62, fontWeight: pw.FontWeight.bold, color: color)),
  );
}

pw.Widget _iconBadge(pw.Widget Function(double, PdfColor) glyph, PdfColor color,
    {double size = 26}) {
  return pw.Container(
    width: size,
    height: size,
    decoration: pw.BoxDecoration(
      color: _tint(color, 0.85),
      borderRadius: pw.BorderRadius.circular(size * 0.32),
    ),
    alignment: pw.Alignment.center,
    child: glyph(size * 0.56, color),
  );
}

pw.Widget _logoMark({double boxSize = 24, double fontSize = 13}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(
        width: boxSize,
        height: boxSize,
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(colors: [_primary, _secondary]),
          borderRadius: pw.BorderRadius.circular(boxSize * 0.3),
        ),
        child: _glyphTruck(boxSize, PdfColors.white),
      ),
      pw.SizedBox(width: 8),
      pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
              text: 'Frota',
              style:
                  pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: _navy)),
          pw.TextSpan(
              text: 'Check',
              style: pw.TextStyle(
                  fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: _primary)),
        ]),
      ),
    ],
  );
}

pw.Widget _infoChip(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: _slate)),
      pw.SizedBox(height: 2),
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(value,
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _navy)),
          pw.SizedBox(width: 5),
          pw.Container(
            width: 16,
            height: 16,
            decoration: pw.BoxDecoration(
              color: _c(0xFFEFF3FB),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            alignment: pw.Alignment.center,
            child: _glyphCalendar(9, _primary),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _headerBanner({
  required pw.ImageProvider bannerImage,
  required String companyName,
  required DateTime generatedAt,
  required DateTime periodoInicio,
  required DateTime periodoFim,
}) {
  return pw.ClipRRect(
    horizontalRadius: 14,
    verticalRadius: 14,
    child: pw.Container(
      height: 96,
      color: PdfColors.white,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(child: pw.Image(bannerImage, fit: pw.BoxFit.cover)),
          pw.Positioned.fill(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: [PdfColors.white, PdfColors.white, _c(0x00FFFFFF)],
                  stops: const [0, 0.58, 0.8],
                ),
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _logoMark(),
                    pw.Row(children: [
                      _infoChip('Relatório gerado em', _fmtDateTime(generatedAt)),
                      pw.SizedBox(width: 16),
                      _infoChip('Período do relatório',
                          '${_fmtDate(periodoInicio)} a ${_fmtDate(periodoFim)}'),
                    ]),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('RELATÓRIO EXECUTIVO DE FROTA',
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy,
                            letterSpacing: 0.2)),
                    pw.SizedBox(height: 3),
                    pw.Text(companyName,
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold, color: _blueBrand)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _footerBanner(pw.ImageProvider footerImage, int pageNumber, int pagesCount) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.ClipRRect(
      horizontalRadius: 14,
      verticalRadius: 14,
      child: pw.Column(
        children: [
          pw.SizedBox(
            height: 46,
            width: double.infinity,
            child:
                pw.Image(footerImage, fit: pw.BoxFit.cover, alignment: pw.Alignment.topCenter),
          ),
          pw.Container(
            height: 30,
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(colors: [_c(0xFF0B1E45), _c(0xFF15295E)]),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 18,
                      height: 18,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: _glyphTruck(18, _primary),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text('FrotaCheck',
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ],
                ),
                pw.Text('Página $pageNumber de $pagesCount',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.white)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _totalGeralCard(double totalGeral) {
  return pw.Container(
    width: 150,
    height: 102,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(
          colors: [_primary, _c(0xFF123B85)],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight),
      borderRadius: pw.BorderRadius.circular(12),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Container(
          width: 22,
          height: 22,
          decoration:
              pw.BoxDecoration(color: _c(0x33FFFFFF), borderRadius: pw.BorderRadius.circular(7)),
          child: _glyphWallet(22, PdfColors.white),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('TOTAL GERAL',
                style: pw.TextStyle(
                    fontSize: 8,
                    color: _c(0xCCFFFFFF),
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.5)),
            pw.SizedBox(height: 3),
            pw.Text(_fmtR(totalGeral),
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            pw.SizedBox(height: 3),
            pw.Text('Total geral (combustível + multas + manutenção)',
                maxLines: 2, style: pw.TextStyle(fontSize: 6.6, color: _c(0xB3FFFFFF))),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _statCard(
    String label, String value, pw.Widget Function(double, PdfColor) glyph, PdfColor color) {
  return pw.Expanded(
    child: pw.Container(
      height: 102,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _c(0xFFE5E9F2)),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _iconBadge(glyph, color),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 7.5, color: _slate, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3)),
              pw.SizedBox(height: 3),
              pw.Text(value,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _navy)),
            ],
          ),
        ],
      ),
    ),
  );
}

pw.Widget _sectionCard({
  required String title,
  required pw.Widget Function(double, PdfColor) glyph,
  required PdfColor color,
  required List<pw.Widget> rows,
}) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _c(0xFFE5E9F2)),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            _iconBadge(glyph, color, size: 22),
            pw.SizedBox(width: 8),
            pw.Text(title,
                style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _navy)),
          ]),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Divider(color: _c(0xFFEEF1F7), height: 1),
          ),
          ...rows,
        ],
      ),
    ),
  );
}

pw.Widget _kpiRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _slate)),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _navy)),
      ],
    ),
  );
}

pw.Widget _monthlyChartCard(List<String> months, List<double> values) {
  final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
  final safeMax = maxV <= 0 ? 1.0 : maxV;

  return pw.Expanded(
    flex: 3,
    child: pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _c(0xFFE5E9F2)),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            _iconBadge(_glyphChart, _primary, size: 22),
            pw.SizedBox(width: 8),
            pw.Text('GASTO MENSAL (COMBUSTÍVEL)',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _navy)),
          ]),
          pw.SizedBox(height: 10),
          pw.SizedBox(
            height: 92,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: List.generate(months.length, (i) {
                final v = values[i];
                final h = (v / safeMax) * 66.0;
                final isLast = i == months.length - 1;
                return pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Container(
                        height: h < 2 ? 2 : h,
                        margin: const pw.EdgeInsets.symmetric(horizontal: 5),
                        decoration: pw.BoxDecoration(
                          color: isLast ? _primary : _c(0xFFBFD4F5),
                          borderRadius: const pw.BorderRadius.only(
                            topLeft: pw.Radius.circular(3),
                            topRight: pw.Radius.circular(3),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(months[i], style: pw.TextStyle(fontSize: 7.5, color: _slate)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _monthlyTableCard(List<String> months, List<double> values) {
  return pw.Expanded(
    flex: 2,
    child: pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _c(0xFFE5E9F2)),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Expanded(
                child: pw.Text('MÊS',
                    style:
                        pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _slate))),
            pw.Text('VALOR',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _slate)),
          ]),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Divider(color: _c(0xFFEEF1F7), height: 1),
          ),
          ...List.generate(months.length, (i) {
            final isLast = i == months.length - 1;
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              margin: const pw.EdgeInsets.only(bottom: 2),
              decoration: pw.BoxDecoration(
                color: isLast ? _c(0xFFEAF1FE) : PdfColors.white,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Text(months[i],
                          style: pw.TextStyle(
                              fontSize: 9,
                              color: isLast ? _primary : _navy,
                              fontWeight: isLast ? pw.FontWeight.bold : pw.FontWeight.normal))),
                  pw.Text(_fmtR(values[i]),
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold, color: isLast ? _primary : _navy)),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}

pw.Widget _rankCard({
  required String title,
  required pw.Widget Function(double, PdfColor) glyph,
  required PdfColor color,
  required List<MapEntry<String, double>> items,
}) {
  final maxV = items.isEmpty ? 1.0 : items.map((e) => e.value).reduce((a, b) => a > b ? a : b);
  final medalColors = [_c(0xFFF5B301), _c(0xFFB0B7C3), _c(0xFFC97A3D)];

  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _c(0xFFE5E9F2)),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            _iconBadge(glyph, color, size: 22),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(title,
                  maxLines: 2,
                  style: pw.TextStyle(fontSize: 9.8, fontWeight: pw.FontWeight.bold, color: _navy)),
            ),
          ]),
          pw.SizedBox(height: 10),
          if (items.isEmpty)
            pw.Text('Sem dados no período.',
                style: pw.TextStyle(fontSize: 9, color: _slate)),
          ...items.asMap().entries.map((entry) {
            final pos = entry.key;
            final item = entry.value;
            final frac = (item.value / maxV).clamp(0.0, 1.0);
            final fracInt = (frac * 1000).round().clamp(0, 1000);
            final badgeColor = pos < 3 ? medalColors[pos] : _slateLight;
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 16,
                        height: 16,
                        decoration: pw.BoxDecoration(
                          color: _tint(badgeColor, 0.78),
                          borderRadius: pw.BorderRadius.circular(5),
                        ),
                        alignment: pw.Alignment.center,
                        child: pw.Text('${pos + 1}',
                            style: pw.TextStyle(
                                fontSize: 8, fontWeight: pw.FontWeight.bold, color: badgeColor)),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                          child:
                              pw.Text(item.key, style: pw.TextStyle(fontSize: 9, color: _navy))),
                      pw.Text(_fmtR(item.value),
                          style:
                              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: fracInt == 0 ? 1 : fracInt,
                        child: pw.Container(
                          height: 4,
                          decoration:
                              pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2)),
                        ),
                      ),
                      if (1000 - fracInt > 0)
                        pw.Expanded(
                          flex: 1000 - fracInt,
                          child: pw.Container(
                            height: 4,
                            decoration: pw.BoxDecoration(
                                color: _c(0xFFEEF1F7), borderRadius: pw.BorderRadius.circular(2)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}

pw.Widget _avisoAgregado() {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      color: _c(0xFFFFF7E6),
      border: pw.Border.all(color: _c(0xFFD99A2B)),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Text(
      'VISÃO AGREGADA MASTER — dados de TODAS as empresas cadastradas na plataforma, não de uma empresa específica.',
      style: pw.TextStyle(color: _c(0xFF8A5A00), fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
  );
}

/// Builds the full "Relatório Executivo de Frota" PDF document, matching the
/// client-supplied visual reference. All figures are pre-computed by the
/// caller — this only handles layout/presentation.
Future<Uint8List> buildRelatorioPdfBytes({
  required String companyName,
  required bool visaoAgregada,
  required double totalGeral,
  required double totalGastoFuel,
  required double totalMultasTotal,
  required double totalGastoManutencao,
  required double totalLitros,
  required int qtdAbastecimentos,
  required double precoMedioLitro,
  required int qtdMultasAbertas,
  required double totalMultasAbertas,
  required int qtdManutencoes,
  required List<String> months,
  required List<double> monthlyValues,
  required List<Map<String, dynamic>> topVeiculos,
  required List<Map<String, dynamic>> topMotoristas,
  required DateTime periodoInicio,
  required DateTime periodoFim,
}) async {
  final headerBytes = await rootBundle.load('assets/images/Parte_cima_projeto.jpeg');
  final footerBytes = await rootBundle.load('assets/images/Parte_baixo_projeto.jpeg');
  final headerImg = pw.MemoryImage(headerBytes.buffer.asUint8List());
  final footerImg = pw.MemoryImage(footerBytes.buffer.asUint8List());

  final veiculosItems = topVeiculos
      .take(5)
      .map((e) => MapEntry(e['plate'].toString(), e['value'] as double))
      .toList();
  final motoristasItems = topMotoristas
      .take(5)
      .map((e) => MapEntry(e['name'].toString(), e['value'] as double))
      .toList();

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      footer: (ctx) => _footerBanner(footerImg, ctx.pageNumber, ctx.pagesCount),
      build: (ctx) => [
        if (visaoAgregada) _avisoAgregado(),
        _headerBanner(
          bannerImage: headerImg,
          companyName: companyName,
          generatedAt: DateTime.now(),
          periodoInicio: periodoInicio,
          periodoFim: periodoFim,
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _totalGeralCard(totalGeral),
            pw.SizedBox(width: 10),
            _statCard('Combustível', _fmtR(totalGastoFuel), _glyphFuel, _info),
            pw.SizedBox(width: 10),
            _statCard('Multas (abertas + pagas)', _fmtR(totalMultasTotal), _glyphDoc, _warning),
            pw.SizedBox(width: 10),
            _statCard('Manutenção', _fmtR(totalGastoManutencao), _glyphDoc, _success),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionCard(
              title: 'COMBUSTÍVEL',
              glyph: _glyphFuel,
              color: _info,
              rows: [
                _kpiRow('Total gasto em combustível', _fmtR(totalGastoFuel)),
                _kpiRow('Total de litros abastecidos', '${totalLitros.toStringAsFixed(1)} L'),
                _kpiRow('Número de abastecimentos', '$qtdAbastecimentos'),
                _kpiRow('Preço médio por litro', _fmtR(precoMedioLitro)),
              ],
            ),
            pw.SizedBox(width: 12),
            _sectionCard(
              title: 'MULTAS & MANUTENÇÃO',
              glyph: _glyphDoc,
              color: _warning,
              rows: [
                _kpiRow('Multas abertas (qtd)', '$qtdMultasAbertas'),
                _kpiRow('Valor total de multas abertas', _fmtR(totalMultasAbertas)),
                _kpiRow('Valor total de multas (abertas + pagas)', _fmtR(totalMultasTotal)),
                _kpiRow('Manutenções registradas', '$qtdManutencoes'),
                _kpiRow('Valor total de manutenção', _fmtR(totalGastoManutencao)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _monthlyChartCard(months, monthlyValues),
            pw.SizedBox(width: 12),
            _monthlyTableCard(months, monthlyValues),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _rankCard(
              title: 'TOP VEÍCULOS POR GASTO EM COMBUSTÍVEL',
              glyph: _glyphCar,
              color: _secondary,
              items: veiculosItems,
            ),
            pw.SizedBox(width: 12),
            _rankCard(
              title: 'TOP MOTORISTAS POR GASTO EM COMBUSTÍVEL',
              glyph: _glyphPerson,
              color: _secondary,
              items: motoristasItems,
            ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

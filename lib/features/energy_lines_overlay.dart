import 'dart:math';
import 'package:flutter/material.dart';

/// Overlay de energia digital — linhas luminosas dos cards KPI ao painel central.
///
/// Design:
///   • Canal de campo (gradiente fino e estático) — "duto" da energia
///   • 3 fótons por linha, velocidades e fases únicas — nunca sincronizados
///   • Fade quadrático nas extremidades — nasce/morre organicamente
///   • Desaparece antes de tocar o conteúdo central
///   • IgnorePointer → nenhuma interação bloqueada
class EnergyLinesOverlay extends StatefulWidget {
  final List<Color> leftCardColors;   // 4 cores — coluna esquerda, de cima a baixo
  final List<Color> rightCardColors;  // 4 cores — coluna direita, de cima a baixo

  const EnergyLinesOverlay({
    super.key,
    required this.leftCardColors,
    required this.rightCardColors,
  });

  @override
  State<EnergyLinesOverlay> createState() => _EnergyLinesOverlayState();
}

class _EnergyLinesOverlayState extends State<EnergyLinesOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Loop de 9 segundos — energía lenta e contemplativa
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => CustomPaint(
          painter: _EnergyPainter(
            t: _ctrl.value,
            leftColors: widget.leftCardColors,
            rightColors: widget.rightCardColors,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
//  Fótons — 3 por linha com velocidades incomensúráveis → nunca sincronizam
//  (phase_offset, speed_in_loops_per_cycle, glow_radius_px)
// ════════════════════════════════════════════════════════════════════════════════

const _kPhotons = [
  (0.000, 1.35, 2.1), // 6.7 s / traversal
  (0.330, 1.10, 1.8), // 8.2 s / traversal
  (0.670, 1.55, 2.0), // 5.8 s / traversal
];

// Offset de fase por linha — evita que linhas diferentes estejam em sincronia
const _kLeftLineOffsets  = [0.00, 0.13, 0.26, 0.39];
const _kRightLineOffsets = [0.07, 0.20, 0.33, 0.46];

// ════════════════════════════════════════════════════════════════════════════════

class _EnergyPainter extends CustomPainter {
  final double t;
  final List<Color> leftColors;
  final List<Color> rightColors;

  const _EnergyPainter({
    required this.t,
    required this.leftColors,
    required this.rightColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;

    // ── Proporções do layout (flex 15 | 24 | 45 | 24 | 15 | 24 | 25) ─────────
    // 3 SizedBox(24) = 72px fixos; Expanded divide o restante pelo flex total
    final flex  = W - 72.0;
    final leftW  = flex * 0.15;
    final ctrW   = flex * 0.45;

    final xLeftEdge  = leftW;              // borda direita da coluna esquerda
    final xCtrLeft   = leftW + 24.0;      // borda esquerda do painel central
    final xCtrRight  = leftW + 24 + ctrW; // borda direita do painel central
    final xRightEdge = leftW + 48 + ctrW; // borda esquerda da coluna direita KPI

    // Penetração no centro (% da largura): onde a energia se dissolve
    final penetration = ctrW * 0.175;

    // ── Centros Y das colunas laterais (4 cards iguais, 3 gaps de 24px) ──────
    final cardH = (H - 72.0) / 4.0;
    final leftYs  = List.generate(4, (i) => i * (cardH + 24.0) + cardH / 2.0);
    final rightYs = List.generate(4, (i) => i * (cardH + 24.0) + cardH / 2.0);

    // ── Linhas da esquerda → centro ──────────────────────────────────────────
    for (int i = 0; i < leftColors.length && i < leftYs.length; i++) {
      _drawLine(
        canvas: canvas,
        xFrom: xLeftEdge,
        xTo:   xCtrLeft + penetration,
        y:     leftYs[i],
        color: leftColors[i],
        lineOffset: _kLeftLineOffsets[i],
        rtl: false,
      );
    }

    // ── Linhas da direita → centro ────────────────────────────────────────────
    for (int i = 0; i < rightColors.length && i < rightYs.length; i++) {
      _drawLine(
        canvas: canvas,
        xFrom: xRightEdge,
        xTo:   xCtrRight - penetration,
        y:     rightYs[i],
        color: rightColors[i],
        lineOffset: _kRightLineOffsets[i],
        rtl: true,
      );
    }
  }

  /// Desenha uma linha de energia de [xFrom] (card edge) até [xTo] (ponto de dissolução).
  /// [rtl]: direção direita→esquerda (coluna direita em direção ao centro).
  void _drawLine({
    required Canvas canvas,
    required double xFrom, // borda do card — onde a energia nasce
    required double xTo,   // ponto de dissolução — nunca toca o conteúdo
    required double y,
    required Color color,
    required double lineOffset,
    required bool rtl,
  }) {
    final xMin   = rtl ? xTo   : xFrom;
    final xMax   = rtl ? xFrom : xTo;
    final lineW  = (xMax - xMin).abs();
    if (lineW < 4) return;

    final Alignment gradA = rtl ? Alignment.centerRight : Alignment.centerLeft;
    final Alignment gradB = rtl ? Alignment.centerLeft  : Alignment.centerRight;

    // Respiração do canal: cada linha pulsa ligeiramente fora de fase com as demais
    final energyBreath = 0.80 + 0.20 * sin(t * 0.448 + lineOffset * pi); // ~14 s / ciclo

    // Gradiente de campo: nasce fraco na borda do card, pico no gap, dissolve antes do centro
    final fieldColors = [
      color.withOpacity(0.055 * energyBreath),
      color.withOpacity(0.165 * energyBreath),
      color.withOpacity(0.110 * energyBreath),
      color.withOpacity(0.028 * energyBreath),
      Colors.transparent,
    ];
    const fieldStops = [0.0, 0.30, 0.52, 0.80, 1.0];

    final glowRect = Rect.fromLTWH(xMin, y - 5.0, lineW, 10.0);
    final lineRect = Rect.fromLTWH(xMin, y - 0.5, lineW,  1.0);

    final gradient = LinearGradient(
      begin: gradA, end: gradB,
      colors: fieldColors, stops: fieldStops,
    );

    // ── Campo suave (10px) — duto energético ─────────────────────────────────
    canvas.drawRect(glowRect, Paint()
        ..shader = gradient.createShader(glowRect));

    // ── Linha central (1px) ────────────────────────────────────────────────
    canvas.drawRect(lineRect, Paint()
        ..shader = gradient.createShader(lineRect));

    // ── Fótons — partículas de informação em trânsito ─────────────────────
    final p = Paint()..style = PaintingStyle.fill;

    for (final (phase, speed, gr) in _kPhotons) {
      // Posição: 0 = borda do card → 1 = ponto de dissolução
      final rawPos = (phase + lineOffset + t * speed) % 1.0;

      // Envelope: nasce suave (ease-in quadrático) e dissolve suave (ease-out quadrático)
      const zi = 0.10; // zona de fade-in
      const zo = 0.85; // início do fade-out
      final fo = rawPos < zi
          ? (rawPos / zi) * (rawPos / zi)
          : rawPos > zo
              ? ((1.0 - rawPos) / (1.0 - zo)) * ((1.0 - rawPos) / (1.0 - zo))
              : 1.0;

      if (fo < 0.015) continue;

      // Coordenada X: esquerda→direita ou direita→esquerda conforme direção
      final px = rtl ? (xFrom - rawPos * lineW) : (xFrom + rawPos * lineW);

      // Halo exterior (difuso, grande)
      p.color = color.withOpacity(fo * 0.20);
      canvas.drawCircle(Offset(px, y), gr * 2.8, p);

      // Corpo do fóton
      p.color = color.withOpacity(fo * 0.48);
      canvas.drawCircle(Offset(px, y), gr, p);

      // Núcleo (branco brilhante)
      p.color = Colors.white.withOpacity(fo * 0.76);
      canvas.drawCircle(Offset(px, y), gr * 0.38, p);
    }
  }

  @override
  bool shouldRepaint(_EnergyPainter old) => old.t != t;
}

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

// ── KPI Card — glass premium, border interna, hover elegante, linha inferior ────

class KpiCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? badge;
  final Color? badgeColor;
  final String trend;
  final String? unit;
  final List<double> sparkData;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.badge,
    this.badgeColor,
    this.trend = '',
    this.unit,
    this.sparkData = const [],
    this.onTap,
  });

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> with SingleTickerProviderStateMixin {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()..translate(0.0, _hovered ? -3.0 : 0.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // Borda externa — muda para cor do card no hover
            border: Border.all(
              color: _hovered ? c.withOpacity(0.70) : c.withOpacity(0.18),
              width: _hovered ? 1.2 : 1.0,
            ),
            boxShadow: _hovered
                ? [
                    // Glow colorido suave — muito discreto
                    BoxShadow(
                      color: c.withOpacity(0.18),
                      blurRadius: 44,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: c.withOpacity(0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [
                    // Shadow azul extremamente suave — sempre presente
                    BoxShadow(
                      color: const Color(0xFF1A3A6B).withOpacity(0.14),
                      blurRadius: 20,
                      spreadRadius: -2,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  gradient: LinearGradient(
                    colors: [
                      c.withOpacity(_hovered ? 0.10 : 0.050),
                      const Color(0xFF050B16).withOpacity(0.93),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  // Borda interna — reflexo de luz que cria o efeito glass
                  border: Border(
                    top:  BorderSide(
                      color: Colors.white.withOpacity(_hovered ? 0.10 : 0.055),
                      width: 0.8,
                    ),
                    left: BorderSide(
                      color: Colors.white.withOpacity(_hovered ? 0.06 : 0.030),
                      width: 0.6,
                    ),
                    right:  BorderSide.none,
                    bottom: BorderSide.none,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── Conteúdo do card ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(c),
                          const SizedBox(height: 10),
                          _buildValue(c),
                          if (widget.trend.isNotEmpty) _buildTrend(),
                          const Spacer(),
                          if (widget.sparkData.length >= 2) _buildSpark(c),
                        ],
                      ),
                    ),

                    // ── Linha inferior animada ────────────────────────────────
                    // Gradiente da cor do card deslizando de transparente para
                    // brilhante e voltando — representa a energia digital do card
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        opacity: _hovered ? 1.0 : 0.0,
                        child: Container(
                          height: 2.0,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                c.withOpacity(0.88),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.50, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color c) {
    final badgeC = widget.badgeColor ?? c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Ícone maior, container mais arredondado
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: c.withOpacity(_hovered ? 0.52 : 0.18),
                blurRadius: _hovered ? 22 : 7,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(widget.icon, color: c, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.title,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              letterSpacing: 0.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: badgeC.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: badgeC.withOpacity(0.34),
                width: 0.8,
              ),
            ),
            child: Text(
              widget.badge!,
              style: TextStyle(
                color: badgeC,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildValue(Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: -1.0,
            shadows: _hovered
                ? [Shadow(color: c.withOpacity(0.42), blurRadius: 18)]
                : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.unit != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              widget.unit!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTrend() {
    final isNeutral = widget.trend.startsWith('sem') ||
        widget.trend.startsWith('estável') ||
        widget.trend.startsWith('índice');
    final up = !widget.trend.startsWith('-') && !isNeutral;
    final tc = isNeutral
        ? AppColors.textSecondary
        : up
            ? const Color(0xFF34D399)
            : const Color(0xFFF87171);
    final icon = isNeutral
        ? Icons.remove_rounded
        : up
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tc),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              widget.trend,
              style: TextStyle(
                color: tc,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.05,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpark(Color c) {
    return SizedBox(
      height: 34,
      child: _AnimatedSparkLine(data: widget.sparkData, color: c),
    );
  }
}

// ── Animated Sparkline ─────────────────────────────────────────────────────────

class _AnimatedSparkLine extends StatefulWidget {
  final List<double> data;
  final Color color;

  const _AnimatedSparkLine({required this.data, required this.color});

  @override
  State<_AnimatedSparkLine> createState() => _AnimatedSparkLineState();
}

class _AnimatedSparkLineState extends State<_AnimatedSparkLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SparkPainter(
          data: widget.data,
          color: widget.color,
          progress: _ctrl.value,
        ),
        size: const Size(double.infinity, 34),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double progress;

  const _SparkPainter({
    required this.data,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final maxV = data.reduce((a, b) => a > b ? a : b);
    final minV = data.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    final h = size.height;
    final w = size.width;

    Offset pt(int i) {
      final x = (i / (data.length - 1)) * w;
      final norm = (data[i] - minV) / range;
      return Offset(x, h - norm * h * 0.78 - h * 0.10);
    }

    final pts = List.generate(data.length, pt);

    Path smoothPath(List<Offset> points) {
      final p = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final cpx = (prev.dx + curr.dx) / 2;
        p.cubicTo(cpx, prev.dy, cpx, curr.dy, curr.dx, curr.dy);
      }
      return p;
    }

    final linePath = smoothPath(pts);

    // Gradient fill
    final fill = Path.from(linePath)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withOpacity(0.28), color.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Line
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color.withOpacity(0.88)
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Travelling dot
    final rawIdx = progress * (pts.length - 1);
    final i = rawIdx.floor().clamp(0, pts.length - 2);
    final f = rawIdx - i;
    final Offset dotPos;

    final prev = pts[i], next = pts[i + 1];
    final cpx = (prev.dx + next.dx) / 2;
    final t = f;
    final mt = 1 - t;
    dotPos = Offset(
      mt * mt * mt * prev.dx + 3 * mt * mt * t * cpx + 3 * mt * t * t * cpx + t * t * t * next.dx,
      mt * mt * mt * prev.dy + 3 * mt * mt * t * prev.dy + 3 * mt * t * t * next.dy + t * t * t * next.dy,
    );

    canvas.drawCircle(
      dotPos, 6.0,
      Paint()
        ..color = color.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      dotPos, 3.0,
      Paint()
        ..color = color.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );
    canvas.drawCircle(dotPos, 2.2, Paint()..color = color);
    canvas.drawCircle(dotPos, 1.1, Paint()..color = Colors.white.withOpacity(0.90));
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || old.data != data || old.color != color;
}

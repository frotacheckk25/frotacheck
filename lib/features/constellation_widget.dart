import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Painel central — galáxia tecnológica com sistema de partículas profissional.
///
/// Arquitetura:
///  • Ticker contínuo (≡ requestAnimationFrame) sem resets — posições nunca saltam
///  • ~440 partículas em 4 camadas de profundidade + 22 tons de acento
///  • Constelação de inteligência (nós, arestas, partículas de dados) em sobrecamada
///  • Sem MaskFilter.blur por partícula — brilho simulado em círculos concêntricos
///  • Único CustomPainter por frame (~1.400 drawCircle/frame — <16ms)
class ConstellationPanel extends StatefulWidget {
  const ConstellationPanel({super.key});

  @override
  State<ConstellationPanel> createState() => _CPState();
}

class _CPState extends State<ConstellationPanel>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0.0);

  late final _GalaxyData _galaxy;
  late final _ConstellationData _constellation;

  @override
  void initState() {
    super.initState();
    _galaxy = _GalaxyData._build();
    _constellation = _ConstellationData._build();
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1e6;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Canvas principal (GPU layer isolado) ─────────────────────────────
        Positioned.fill(
          child: RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: _time,
              builder: (context, t, child) => CustomPaint(
                painter: _UnifiedPainter(
                  galaxy: _galaxy,
                  constellation: _constellation,
                  t: t,
                ),
              ),
            ),
          ),
        ),

        // ── UI estática — nunca rebuildada por frame ──────────────────────────
        Positioned(
          top: 22, left: 0, right: 0,
          child: Center(
            child: Text(
              'NÚCLEO DIGITAL DA FROTA',
              style: TextStyle(
                color: Colors.white.withOpacity(0.33),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.8,
              ),
            ),
          ),
        ),
        Positioned(bottom: 36, left: 0, right: 0, child: _buildLegend()),
        Positioned(bottom: 10, left: 20, right: 20, child: _buildStatusBar()),
      ],
    );
  }

  Widget _buildLegend() {
    const items = [
      ('Veículos',   Color(0xFF3B82F6)),
      ('Motoristas', Color(0xFF10B981)),
      ('Operações',  Color(0xFFF97316)),
      ('Alertas',    Color(0xFFEF4444)),
      ('IA',         Color(0xFF8B5CF6)),
      ('Dados',      Color(0xFF06B6D4)),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: item.$2, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: item.$2.withOpacity(0.72), blurRadius: 5)],
              ),
            ),
            const SizedBox(width: 5),
            Text(item.$1,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.33),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildStatusBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          _PulseDot(color: const Color(0xFF10B981)),
          const SizedBox(width: 6),
          Text('Última atualização: em tempo real',
              style: TextStyle(color: Colors.white.withOpacity(0.20), fontSize: 9)),
        ]),
        Row(children: [
          Icon(Icons.check_circle_outline_rounded,
              color: const Color(0xFF10B981).withOpacity(0.52), size: 10),
          const SizedBox(width: 4),
          Text('Sincronizado com sucesso',
              style: TextStyle(
                  color: const Color(0xFF10B981).withOpacity(0.48), fontSize: 9)),
        ]),
      ],
    );
  }
}

// ── Dot pulsante ───────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = 0.38 + 0.62 * sin(_c.value * pi * 2);
        return Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(v),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(v * 0.65), blurRadius: 5)
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
//  SISTEMA DE PARTÍCULAS — GALÁXIA TECNOLÓGICA
// ════════════════════════════════════════════════════════════════════════════════

/// Uma partícula de galáxia — posição, velocidade e ritmo biológico pré-computados.
class _GP {
  final double x0, y0;     // posição inicial (0..1 normalizado)
  final double vx, vy;     // velocidade de deriva (unidades/segundo, extremamente lenta)
  final double wFreq;      // frequência de oscilação orgânica (rad/s)
  final double wPhase;     // fase da oscilação
  final double wAmp;       // amplitude da oscilação (negligenciável — torna partícula "viva")
  final double r;          // raio base em pixels
  final double bOp;        // opacidade base
  final double bPeriod;    // período de respiração em segundos
  final double bPhase;     // fase da respiração
  final Color color;
  final int layer;         // 0 = fundo distante … 3 = primeiro plano

  const _GP({
    required this.x0, required this.y0,
    required this.vx, required this.vy,
    required this.wFreq, required this.wPhase, required this.wAmp,
    required this.r, required this.bOp,
    required this.bPeriod, required this.bPhase,
    required this.color, required this.layer,
  });
}

class _GalaxyData {
  final List<_GP> particles;
  const _GalaxyData(this.particles);

  static _GalaxyData _build() {
    final rng = Random(137);
    final out = <_GP>[];

    void fill({
      required int n,
      required double rMin, required double rMax,
      required double opMin, required double opMax,
      required double sScale,        // escala de velocidade
      required List<Color> cols,
      required int layer,
    }) {
      for (int i = 0; i < n; i++) {
        final angle = rng.nextDouble() * 2 * pi;
        // Velocidade extremamente lenta: 0.00003 .. 0.00016 u/s (escalada por camada)
        final speed = (0.000030 + rng.nextDouble() * 0.000130) * sScale;
        out.add(_GP(
          x0: rng.nextDouble(),
          y0: rng.nextDouble(),
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          wFreq:  0.040 + rng.nextDouble() * 0.090,   // período 70-160 s
          wPhase: rng.nextDouble() * 2 * pi,
          wAmp:   0.00018 + rng.nextDouble() * 0.00095, // oscilação imperceptível isolada
          r: rMin + rng.nextDouble() * (rMax - rMin),
          bOp: opMin + rng.nextDouble() * (opMax - opMin),
          bPeriod: 8.0 + rng.nextDouble() * 18.0,      // respiração: 8-26 s por ciclo
          bPhase: rng.nextDouble() * 2 * pi,
          color: cols[rng.nextInt(cols.length)],
          layer: layer,
        ));
      }
    }

    // ── Camada 0 — fundo profundo (pontos microscópicos, quase estáticos) ─────
    fill(n: 170,
        rMin: 0.25, rMax: 0.65,
        opMin: 0.055, opMax: 0.190,
        sScale: 0.26,
        cols: const [Color(0xFF30486A), Color(0xFF3A5478), Color(0xFF284060)],
        layer: 0);

    // ── Camada 1 — fundo médio ────────────────────────────────────────────────
    fill(n: 130,
        rMin: 0.48, rMax: 1.02,
        opMin: 0.100, opMax: 0.285,
        sScale: 0.50,
        cols: const [Color(0xFF4C6A90), Color(0xFF587AA0), Color(0xFF446080)],
        layer: 1);

    // ── Camada 2 — plano médio ────────────────────────────────────────────────
    fill(n: 90,
        rMin: 0.72, rMax: 1.50,
        opMin: 0.150, opMax: 0.430,
        sScale: 0.72,
        cols: const [
          Color(0xFF7090B8), Color(0xFF80A0C8), Color(0xFF90B0D0),
          Color(0xFF9CA8C0),
        ],
        layer: 2);

    // ── Camada 3 — primeiro plano (maiores, mais brilhantes) ──────────────────
    fill(n: 48,
        rMin: 1.05, rMax: 2.55,
        opMin: 0.240, opMax: 0.640,
        sScale: 1.00,
        cols: const [
          Color(0xFFB0C8DE), Color(0xFFC0D4EC),
          Color(0xFFD0E2F6), Color(0xFFE8F0FC), Colors.white,
        ],
        layer: 3);

    // ── Acentos — pigmentos raros: lavanda fria, âmbar distante, azul gelo ───
    fill(n: 22,
        rMin: 0.50, rMax: 1.20,
        opMin: 0.080, opMax: 0.240,
        sScale: 0.55,
        cols: const [
          Color(0xFFA898C8), Color(0xFFB8A8D8),
          Color(0xFFD0C8A8), Color(0xFF88B4CC),
        ],
        layer: 1);

    // Ordenar fundo → primeiro plano (garante rendering correto sem z-buffer)
    out.sort((a, b) => a.layer.compareTo(b.layer));
    return _GalaxyData(out);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
//  CAMADA 1 — CAMPO ESTELAR PROFUNDO
//  Estrelas ultra-distantes, monochromáticas, quase estáticas.
//  Criam o plano de referência mais recuado da cena.
// ════════════════════════════════════════════════════════════════════════════════

class _TinyStar {
  final double x, y;
  final double r;           // raio: 0.18–0.52 px — menores que qualquer partícula
  final double brightness;  // opacidade base: 0.030–0.115 — quase invisíveis isoladas
  final double phase;
  final double speed;       // respiração muito lenta (0.008–0.032 ciclos/s)
  final Color color;        // azul-acinzentado dessaturado — distância atmosférica

  const _TinyStar({
    required this.x, required this.y,
    required this.r, required this.brightness,
    required this.phase, required this.speed,
    required this.color,
  });
}

// ════════════════════════════════════════════════════════════════════════════════
//  CAMADA 3–5 — CONSTELAÇÃO DE INTELIGÊNCIA
// ════════════════════════════════════════════════════════════════════════════════

class _StarNode {
  final double x, y, r, brightness, phase, speed;
  final Color color;
  final bool isCenter, isHub;

  const _StarNode({
    required this.x, required this.y,
    required this.r, required this.brightness,
    required this.phase, required this.speed,
    required this.color,
    this.isCenter = false,
    this.isHub = false,
  });
}

/// Pulso de dados — foton de informação que percorre uma aresta.
/// Cada instância é independente: velocidade, fase e sentido únicos.
class _DataPulse {
  final int edgeIdx;
  final double offset;   // posição inicial na aresta (0..1) — nunca dois iguais
  final double speed;    // travessias/segundo — 0.036..0.126 (8-28s por cruzamento)
  final bool forward;    // sentido de percurso (A→B ou B→A)
  final double peak;     // brilho de pico (0.62..1.0)
  final double glowR;    // raio do halo externo em px (1.0..2.4)
  final Color color;     // tom do pulso — predominante branco, variações raras

  const _DataPulse({
    required this.edgeIdx,
    required this.offset,
    required this.speed,
    required this.forward,
    required this.peak,
    required this.glowR,
    required this.color,
  });
}

class _ConstellationData {
  final List<_TinyStar> deepStars; // Camada 1 — campo estelar profundo
  final List<_StarNode> stars;
  final List<(int, int)> edges;
  final List<_DataPulse> pulses;

  const _ConstellationData({
    required this.deepStars,
    required this.stars,
    required this.edges,
    required this.pulses,
  });

  static _ConstellationData _build() {
    final rng = Random(42);
    final stars = <_StarNode>[];

    // Estrela central — bloom + espinhos de difração
    stars.add(const _StarNode(
      x: 0.500, y: 0.468,
      r: 5.8, brightness: 1.0,
      color: Colors.white,
      phase: 0, speed: 0.25,
      isCenter: true,
    ));

    // Hubs — anel interno
    const inner = [
      (0.500, 0.285, 3.0, Color(0xFF8B5CF6)),
      (0.658, 0.338, 2.8, Color(0xFF06B6D4)),
      (0.705, 0.512, 3.1, Color(0xFF3B82F6)),
      (0.622, 0.672, 2.6, Color(0xFF10B981)),
      (0.378, 0.672, 2.8, Color(0xFFF97316)),
      (0.295, 0.512, 2.6, Color(0xFFEF4444)),
      (0.342, 0.338, 2.8, Color(0xFF8B5CF6)),
    ];

    // Hubs — anel externo
    const outer = [
      (0.500, 0.122, 2.1, Color(0xFF06B6D4)),
      (0.720, 0.185, 1.9, Color(0xFF3B82F6)),
      (0.838, 0.392, 2.2, Color(0xFF10B981)),
      (0.818, 0.610, 1.9, Color(0xFFF97316)),
      (0.660, 0.792, 2.1, Color(0xFFEF4444)),
      (0.430, 0.838, 1.9, Color(0xFF8B5CF6)),
      (0.218, 0.730, 2.1, Color(0xFF06B6D4)),
      (0.148, 0.490, 2.3, Color(0xFF3B82F6)),
      (0.202, 0.268, 1.9, Color(0xFF10B981)),
      (0.388, 0.118, 2.1, Color(0xFFF97316)),
    ];

    for (final h in [...inner, ...outer]) {
      stars.add(_StarNode(
        x: h.$1, y: h.$2, r: h.$3,
        brightness: 0.62 + rng.nextDouble() * 0.38,
        color: h.$4,
        phase: rng.nextDouble() * pi * 2,
        speed: 0.35 + rng.nextDouble() * 0.55,
        isHub: true,
      ));
    }

    // Nós pequenos espalhados
    const smallCols = [
      Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF97316),
      Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF06B6D4),
    ];
    for (int i = 0; i < 95; i++) {
      stars.add(_StarNode(
        x: rng.nextDouble(), y: rng.nextDouble(),
        r: 0.55 + rng.nextDouble() * 0.85,
        brightness: 0.12 + rng.nextDouble() * 0.42,
        color: smallCols[rng.nextInt(smallCols.length)],
        phase: rng.nextDouble() * pi * 2,
        speed: 0.50 + rng.nextDouble() * 0.90,
      ));
    }

    // Arestas
    final edges = <(int, int)>[];
    const thresh2 = 0.23 * 0.23;
    const maxConn = 4;
    final cnt = List.filled(stars.length, 0);
    for (int i = 0; i < stars.length; i++) {
      if (cnt[i] >= maxConn) continue;
      for (int j = i + 1; j < stars.length; j++) {
        if (cnt[j] >= maxConn) continue;
        final dx = stars[i].x - stars[j].x;
        final dy = stars[i].y - stars[j].y;
        if (dx * dx + dy * dy < thresh2) {
          edges.add((i, j));
          cnt[i]++;
          cnt[j]++;
          if (cnt[i] >= maxConn) break;
        }
      }
    }

    // ── Pulsos de dados — fluxo permanente de informação na rede ─────────────
    // Paleta: predominantemente branco, variações cromáticas raras e discretas
    const pulseColors = [
      Colors.white, Colors.white, Colors.white, Colors.white, Colors.white,
      Color(0xFFCCE4FF), // gelo azul
      Color(0xFFE8EEFF), // lavanda pálida
      Color(0xFFCCFFEE), // menta fria
      Color(0xFFFFF2CC), // âmbar distante
    ];

    final pulses = <_DataPulse>[];

    for (int i = 0; i < edges.length; i++) {
      final nA = stars[edges[i].$1];
      final nB = stars[edges[i].$2];

      // Densidade de pulsos por tipo de aresta:
      //   centro → 3 pulsos bidirecional
      //   hub    → 1 ou 2 (55% de chance de ter 2)
      //   demais → 0 ou 1 (45% de chance de ter 1)
      final count = (nA.isCenter || nB.isCenter) ? 3
                  : (nA.isHub   || nB.isHub)     ? (rng.nextDouble() < 0.55 ? 2 : 1)
                  :                                 (rng.nextDouble() < 0.45 ? 1 : 0);

      for (int j = 0; j < count; j++) {
        // Spread de offset entre múltiplos pulsos da mesma aresta:
        // garante que nunca se alinham visualmente
        final offset = (rng.nextDouble() + j * (1.0 / count)) % 1.0;
        pulses.add(_DataPulse(
          edgeIdx: i,
          offset:  offset,
          speed:   0.036 + rng.nextDouble() * 0.090, // 8–28 s por travessia
          forward: rng.nextBool(),
          peak:    0.62  + rng.nextDouble() * 0.38,
          glowR:   1.0   + rng.nextDouble() * 1.4,
          color:   pulseColors[rng.nextInt(pulseColors.length)],
        ));
      }
    }

    // ── Camada 1 — Campo estelar profundo ────────────────────────────────────
    // Seed diferente do restante → independência visual garantida
    final rng2 = Random(999);
    const deepCols = [
      Color(0xFF22304A), Color(0xFF283848), Color(0xFF1E2C42),
      Color(0xFF2C3A50), Color(0xFF20303C),
    ];
    final deepStars = List<_TinyStar>.generate(340, (_) => _TinyStar(
      x:          rng2.nextDouble(),
      y:          rng2.nextDouble(),
      r:          0.18 + rng2.nextDouble() * 0.34,
      brightness: 0.030 + rng2.nextDouble() * 0.085,
      phase:      rng2.nextDouble() * 2 * pi,
      speed:      0.008 + rng2.nextDouble() * 0.024, // período ~40–125 s
      color:      deepCols[rng2.nextInt(deepCols.length)],
    ));

    return _ConstellationData(
        deepStars: deepStars, stars: stars, edges: edges, pulses: pulses);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
//  PAINTER UNIFICADO — tudo em um único pass por frame
// ════════════════════════════════════════════════════════════════════════════════

class _UnifiedPainter extends CustomPainter {
  final _GalaxyData galaxy;
  final _ConstellationData constellation;
  final double t; // segundos contínuos — nunca reseta

  const _UnifiedPainter({
    required this.galaxy,
    required this.constellation,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final W  = size.width;
    final H  = size.height;
    final cx = W * 0.500;
    final cy = H * 0.468;
    final p  = Paint()..style = PaintingStyle.fill;

    // ════════════════════════════════════════════════════════════════════════
    //  BASE — nebulosa escura com gradiente radial
    // ════════════════════════════════════════════════════════════════════════
    _paintNebula(canvas, size, cx, cy, W, H, p);

    // ════════════════════════════════════════════════════════════════════════
    //  CAMADA 1 — Campo estelar profundo
    //  Estrelas ultra-diminutas, dessaturadas, quase estáticas.
    //  Criam o plano de fundo mais distante — referência de profundidade.
    // ════════════════════════════════════════════════════════════════════════
    _paintLayer1DeepStars(canvas, p, W, H);

    // Névoa atmosférica: véu escuro entre Camada 1 e Camada 2.
    // Empurra ainda mais as estrelas de fundo, aumentando percepção de distância.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000B1C).withOpacity(0.30),
    );

    // ════════════════════════════════════════════════════════════════════════
    //  CAMADA 2 — Partículas em 4 sub-planos
    //  Profundidade interna via tamanho, opacidade e camadas de brilho.
    // ════════════════════════════════════════════════════════════════════════
    _paintGalaxy(canvas, p, W, H);

    // Vignetagem: bordas mais escuras empurram o olhar ao centro.
    // Posicionada após partículas para que Camadas 3-5 "flutuem" acima da névoa.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.70,
          colors: [Colors.transparent, const Color(0xFF000B1E).withOpacity(0.60)],
          stops: const [0.58, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, W, H)),
    );

    // ════════════════════════════════════════════════════════════════════════
    //  CAMADA 3 — Linhas da rede + anéis orbitais
    //  Aparecem "sobre" as partículas — malha de conexões do plano médio.
    // ════════════════════════════════════════════════════════════════════════
    _paintLayer3Lines(canvas, p, W, H, cx, cy);

    // ════════════════════════════════════════════════════════════════════════
    //  CAMADA 4 — Pulsos de dados
    //  Flutuam sobre as linhas — informação em trânsito no primeiro plano.
    // ════════════════════════════════════════════════════════════════════════
    _paintLayer4Pulses(canvas, p, W, H);

    // ════════════════════════════════════════════════════════════════════════
    //  CAMADA 5 — Nós + glow de primeiro plano
    //  Objetos mais próximos. Bloom largo e suave cria sensação de foco.
    //  Drawn last → tudo mais fica "atrás" deles.
    // ════════════════════════════════════════════════════════════════════════
    _paintLayer5Nodes(canvas, p, W, H);
    _paintLayer5ForegroundGlow(canvas, p, W, H);
  }

  // ── Camada 1 ──────────────────────────────────────────────────────────────

  void _paintLayer1DeepStars(Canvas canvas, Paint p, double W, double H) {
    for (final s in constellation.deepStars) {
      // Surgimento/desaparecimento orgânico: seno mapeado para [0,1] com ease quadrático.
      // Período 31–125 s → estrelas somem e reaparecem quase imperceptivelmente.
      final sv = 0.5 + 0.5 * sin(2 * pi * t * s.speed + s.phase); // [0..1]
      final op = (s.brightness * pow(sv, 1.5)).clamp(0.0, 1.0);   // ease suave
      if (op < 0.012) continue;
      p.color = s.color.withOpacity(op);
      canvas.drawCircle(Offset(s.x * W, s.y * H), s.r, p);
    }
  }

  // ── Camada 3 ──────────────────────────────────────────────────────────────

  void _paintLayer3Lines(
      Canvas canvas, Paint p, double W, double H, double cx, double cy) {
    p.style = PaintingStyle.stroke;

    // Arestas da constelação — linhas finas na camada média
    p.strokeWidth = 0.52;
    // Distribuição de fase pelo ângulo de ouro (2.399 rad) — evita clusters harmônicos
    for (int ei = 0; ei < constellation.edges.length; ei++) {
      final e  = constellation.edges[ei];
      final a  = constellation.stars[e.$1];
      final b  = constellation.stars[e.$2];
      final isHubEdge = a.isCenter || a.isHub || b.isCenter || b.isHub;
      // Variação de intensidade por aresta: período ~15.7 s, fase única
      final edgeMod = 0.74 + 0.26 * sin(t * 0.40 + ei * 2.399);
      p.color = Colors.white.withOpacity((isHubEdge ? 0.090 : 0.055) * edgeMod);
      canvas.drawLine(Offset(a.x * W, a.y * H), Offset(b.x * W, b.y * H), p);
    }

    // Anéis orbitais — cada um respira com período independente
    p.strokeWidth = 0.65;
    final ringR = [W * 0.152, W * 0.268, W * 0.385];
    final ringO = [0.115, 0.070, 0.042];
    final ringBreath = [
      0.84 + 0.16 * sin(t * 0.280),          // interno:  ~22.4 s / ciclo
      0.86 + 0.14 * sin(t * 0.220 + 2.094),  // médio:    ~28.6 s / ciclo
      0.88 + 0.12 * sin(t * 0.170 + 4.189),  // externo:  ~36.9 s / ciclo
    ];
    for (int i = 0; i < 3; i++) {
      p.color = Colors.white.withOpacity(ringO[i] * ringBreath[i]);
      canvas.drawCircle(Offset(cx, cy), ringR[i], p);
    }

    p.style = PaintingStyle.fill;
  }

  // ── Camada 4 ──────────────────────────────────────────────────────────────

  void _paintLayer4Pulses(Canvas canvas, Paint p, double W, double H) {
    for (final pulse in constellation.pulses) {
      if (pulse.edgeIdx >= constellation.edges.length) continue;
      final e  = constellation.edges[pulse.edgeIdx];
      final nA = constellation.stars[e.$1];
      final nB = constellation.stars[e.$2];

      final dir    = pulse.forward ? 1.0 : -1.0;
      final rawPos = (pulse.offset + dir * pulse.speed * t) % 1.0;
      final pos    = (rawPos + 1.0) % 1.0;

      // Fade suave nas extremidades (ease quadrático — nascimento/morte orgânicos)
      const zone   = 0.13;
      final f      = pos < zone
          ? pos / zone
          : pos > 1.0 - zone
              ? (1.0 - pos) / zone
              : 1.0;
      final op = pulse.peak * f * f;
      if (op < 0.018) continue;

      final srcX = pulse.forward ? nA.x : nB.x;
      final srcY = pulse.forward ? nA.y : nB.y;
      final dstX = pulse.forward ? nB.x : nA.x;
      final dstY = pulse.forward ? nB.y : nA.y;
      final px   = (srcX + (dstX - srcX) * pos) * W;
      final py   = (srcY + (dstY - srcY) * pos) * H;
      final gr   = pulse.glowR;

      // Halo difuso → halo médio → núcleo — 3 camadas de profundidade no próprio pulso
      p.color = pulse.color.withOpacity(op * 0.10);
      canvas.drawCircle(Offset(px, py), gr * 2.8, p);
      p.color = pulse.color.withOpacity(op * 0.35);
      canvas.drawCircle(Offset(px, py), gr * 1.4, p);
      p.color = pulse.color.withOpacity(op * 0.92);
      canvas.drawCircle(Offset(px, py), gr * 0.50, p);
    }
  }

  // ── Camada 5 — Nós ────────────────────────────────────────────────────────

  void _paintLayer5Nodes(Canvas canvas, Paint p, double W, double H) {
    for (final star in constellation.stars) {
      final tw = 0.55 + 0.45 * sin(t * pi * 2 * star.speed + star.phase);
      final op = (star.brightness * tw).clamp(0.0, 1.0);
      final px = star.x * W;
      final py = star.y * H;

      if (star.isCenter) {
        _paintCentral(canvas, p, Offset(px, py), star.r, op, t);
      } else if (star.isHub) {
        p.color = star.color.withOpacity(op * 0.12);
        canvas.drawCircle(Offset(px, py), star.r * 3.0, p);
        p.color = star.color.withOpacity(op * 0.54);
        canvas.drawCircle(Offset(px, py), star.r, p);
        p.color = Colors.white.withOpacity(op * 0.80);
        canvas.drawCircle(Offset(px, py), star.r * 0.40, p);
      } else {
        p.color = star.color.withOpacity(op * 0.46);
        canvas.drawCircle(Offset(px, py), star.r, p);
        if (op > 0.44) {
          p.color = Colors.white.withOpacity(op * 0.28);
          canvas.drawCircle(Offset(px, py), star.r * 0.38, p);
        }
      }
    }
  }

  // ── Camada 5 — Glow de primeiro plano ─────────────────────────────────────
  // Desenhado APÓS os nós: bloom largo e suave que "sangra" para o espaço ao
  // redor, criando a sensação de que esses objetos estão na frente de tudo.

  void _paintLayer5ForegroundGlow(Canvas canvas, Paint p, double W, double H) {
    for (final star in constellation.stars) {
      if (!star.isCenter && !star.isHub) continue;
      final tw = 0.55 + 0.45 * sin(t * pi * 2 * star.speed + star.phase);
      final op = (star.brightness * tw).clamp(0.0, 1.0);
      final px = star.x * W;
      final py = star.y * H;

      if (star.isCenter) {
        // Bloom central sincronizado com _paintCentral
        final bloomPulse = 1.0 + 0.10 * sin(t * 0.220);
        p.color = const Color(0xFF93C5FD).withOpacity(op * 0.048);
        canvas.drawCircle(Offset(px, py), star.r * 10.0 * bloomPulse, p);
        p.color = Colors.white.withOpacity(op * 0.062);
        canvas.drawCircle(Offset(px, py), star.r * 6.5 * bloomPulse, p);
      } else {
        // Cada hub respira com fase única derivada de star.phase
        final hb1 = 1.0 + 0.14 * sin(t * 0.300 + star.phase * 0.70);
        final hb2 = 1.0 + 0.10 * sin(t * 0.240 + star.phase * 0.70 + 1.571);
        p.color = star.color.withOpacity(op * 0.030);
        canvas.drawCircle(Offset(px, py), star.r * 7.0 * hb1, p);
        p.color = star.color.withOpacity(op * 0.044);
        canvas.drawCircle(Offset(px, py), star.r * 4.0 * hb2, p);
      }
    }
  }

  void _paintNebula(Canvas canvas, Size size, double cx, double cy,
      double W, double H, Paint p) {
    // Base escura espacial
    canvas.drawRect(Offset.zero & size, p..color = const Color(0xFF000B1E));

    // Respiração da nebulosa — brilho central pulsa muito lentamente
    final nebulaBreath = 0.82 + 0.18 * sin(t * 0.180);        // ~34.9 s / ciclo
    final tintBreath   = 0.74 + 0.26 * sin(t * 0.140 + 1.90); // ~44.9 s / ciclo

    // Brilho central azul-profundo — expande e contrai com a respiração
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.60,
          colors: [
            const Color(0xFF162C70).withOpacity(0.28 * nebulaBreath),
            const Color(0xFF0A1A4E).withOpacity(0.14 * nebulaBreath),
            const Color(0xFF040A20).withOpacity(0.06 * nebulaBreath),
            Colors.transparent,
          ],
          stops: const [0.0, 0.44, 0.72, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: W * 0.60)),
    );

    // Toque roxo frio (superior-direito) — respiração independente
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.52, -0.62),
          radius: 0.46,
          colors: [
            const Color(0xFF22125A).withOpacity(0.10 * tintBreath),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, W, H)),
    );
  }

  void _paintGalaxy(Canvas canvas, Paint p, double W, double H) {
    for (final gp in galaxy.particles) {
      // Posição contínua: deriva linear + oscilação orgânica
      final wobX = gp.wAmp * sin(gp.wFreq * t + gp.wPhase);
      final wobY = gp.wAmp * cos(gp.wFreq * t + gp.wPhase);
      final nx = ((gp.x0 + gp.vx * t + wobX) % 1.0 + 1.0) % 1.0;
      final ny = ((gp.y0 + gp.vy * t + wobY) % 1.0 + 1.0) % 1.0;

      // Pulso cósmico: toda a galáxia respira levemente em uníssono (~57 s / ciclo)
      final cosmicPulse = 1.0 + 0.055 * sin(t * 0.110);
      // Respiração individual: per-partícula (8–26 s)
      final op = (gp.bOp * (0.58 + 0.42 * sin(2 * pi * t / gp.bPeriod + gp.bPhase))
              * cosmicPulse)
          .clamp(0.0, 1.0);

      if (op < 0.018) continue; // partícula quase invisível — pular

      final x = nx * W;
      final y = ny * H;
      final r = gp.r;

      switch (gp.layer) {
        case 0:
          // Fundo distante — ponto único, sem brilho
          p.color = gp.color.withOpacity(op);
          canvas.drawCircle(Offset(x, y), r, p);

        case 1:
          // Fundo — brilho mínimo (2 círculos)
          p.color = gp.color.withOpacity(op * 0.13);
          canvas.drawCircle(Offset(x, y), r * 2.1, p);
          p.color = gp.color.withOpacity(op * 0.84);
          canvas.drawCircle(Offset(x, y), r, p);

        case 2:
          // Plano médio — brilho suave (3 círculos)
          p.color = gp.color.withOpacity(op * 0.09);
          canvas.drawCircle(Offset(x, y), r * 2.8, p);
          p.color = gp.color.withOpacity(op * 0.52);
          canvas.drawCircle(Offset(x, y), r * 1.2, p);
          p.color = gp.color.withOpacity(op * 0.88);
          canvas.drawCircle(Offset(x, y), r * 0.52, p);

        default:
          // Primeiro plano — brilho elegante em camadas (4 círculos)
          p.color = gp.color.withOpacity(op * 0.06);
          canvas.drawCircle(Offset(x, y), r * 3.6, p);
          p.color = gp.color.withOpacity(op * 0.20);
          canvas.drawCircle(Offset(x, y), r * 2.0, p);
          p.color = gp.color.withOpacity(op * 0.70);
          canvas.drawCircle(Offset(x, y), r, p);
          p.color = Colors.white.withOpacity(op * 0.84);
          canvas.drawCircle(Offset(x, y), r * 0.40, p);
      }
    }
  }

  void _paintCentral(Canvas canvas, Paint p, Offset pos, double r, double op, double t) {
    // Bloom e espinhos respiram com períodos distintos — nunca sincronizados
    final bloomPulse = 1.0 + 0.10 * sin(t * 0.220);        // ~28.6 s / ciclo
    final spikePulse = 1.0 + 0.08 * sin(t * 0.190 + 1.05); // ~33.1 s / ciclo

    // Bloom externo
    p.color = Colors.white.withOpacity(op * 0.050);
    canvas.drawCircle(pos, r * 5.2 * bloomPulse, p);
    // Halo azul
    p.color = const Color(0xFF93C5FD).withOpacity(op * 0.18);
    canvas.drawCircle(pos, r * 2.8 * bloomPulse, p);
    // Corpo branco
    p.color = Colors.white.withOpacity(op * 0.92);
    canvas.drawCircle(pos, r, p);
    // Ponto central
    p.color = Colors.white;
    canvas.drawCircle(pos, r * 0.36, p);
    // Espinhos de difração — comprimento oscila independentemente
    p
      ..color = Colors.white.withOpacity(op * 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    final sl = r * 3.8 * spikePulse;
    canvas.drawLine(Offset(pos.dx - sl, pos.dy), Offset(pos.dx + sl, pos.dy), p);
    canvas.drawLine(Offset(pos.dx, pos.dy - sl), Offset(pos.dx, pos.dy + sl), p);
    p.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(_UnifiedPainter old) => old.t != t;
}

import 'dart:math';
import 'package:flutter/material.dart';

/// Globo Holográfico — iluminação solar, coastlines, rede densa, atmosfera premium.
class AnimatedBrainWidget extends StatefulWidget {
  const AnimatedBrainWidget({super.key});
  @override
  State<AnimatedBrainWidget> createState() => _State();
}

// Tipo dos pontos de terra
enum _DotType { interior, coast, hub }

class _Dot {
  final double x, y, z, brightness;
  final _DotType type;
  const _Dot(this.x, this.y, this.z, this.brightness, [this.type = _DotType.interior]);
}

class _State extends State<AnimatedBrainWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  // Estrelas
  late final List<double> _sX, _sY, _sR, _sPh;
  // Terra
  late final List<_Dot> _dots;
  // Conexões pré-computadas (feitas 1× no init)
  late final List<(int, int)> _connHub;   // hub ↔ hub   ≤3000km
  late final List<(int, int)> _connLand;  // terra local ≤450km (subconjunto)
  // Tabela de cores da iluminação solar (evita Color.lerp por frame)
  late final List<Color> _colorTable;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 32))
      ..repeat();
    _buildColorTable();
    _buildStars();
    _buildDots();
    _buildConnections();
  }

  // ── Tabela de 128 cores (sombra azul → ciano → branco brilhante) ──────────

  void _buildColorTable() {
    _colorTable = List.generate(128, (i) {
      final t = i / 127.0;
      // 0.0-0.42 → azul-escuro → ciano
      // 0.42-1.0 → ciano → branco
      if (t < 0.42) {
        return Color.lerp(const Color(0xFF002D6A), const Color(0xFF00C8FF), t / 0.42)!;
      }
      return Color.lerp(const Color(0xFF00C8FF), Colors.white, (t - 0.42) / 0.58)!;
    });
  }

  // ── Estrelas ──────────────────────────────────────────────────────────────

  void _buildStars() {
    final rng = Random(9001);
    const n   = 280;
    _sX  = List.generate(n, (_) => rng.nextDouble());
    _sY  = List.generate(n, (_) => rng.nextDouble());
    _sR  = List.generate(n, (_) => 0.28 + rng.nextDouble() * 1.55);
    _sPh = List.generate(n, (_) => rng.nextDouble() * pi * 2);
  }

  // ── Terra ─────────────────────────────────────────────────────────────────

  void _buildDots() {
    final rng  = Random(1987);
    final list = <_Dot>[];

    // Converte (lat°, lon°) → coordenada 3D unitária e adiciona
    void pt(double latDeg, double lonDeg, double b, [_DotType tp = _DotType.interior]) {
      final lat = latDeg * pi / 180;
      final lon = lonDeg * pi / 180;
      list.add(_Dot(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon), b, tp));
    }

    // Preenche uma sub-região com pontos aleatórios
    void fill(double la0, double la1, double lo0, double lo1, int n,
              {double b = 1.0, _DotType tp = _DotType.interior}) {
      for (int i = 0; i < n; i++) {
        pt(la0 + rng.nextDouble() * (la1 - la0),
           lo0 + rng.nextDouble() * (lo1 - lo0), b, tp);
      }
    }

    // Traça pontos ao longo de uma poligonal de coastline com passo ~0.7°
    void coast(List<List<double>> poly, {double b = 1.1}) {
      for (int i = 0; i < poly.length - 1; i++) {
        final lat1 = poly[i][0],     lon1 = poly[i][1];
        final lat2 = poly[i + 1][0], lon2 = poly[i + 1][1];
        final dist  = sqrt((lat2-lat1)*(lat2-lat1) + (lon2-lon1)*(lon2-lon1));
        final steps = max(2, (dist / 0.26).round()); // ~3× mais denso → linhas contínuas
        for (int s = 0; s <= steps; s++) {
          final t = s / steps;
          pt(lat1 + (lat2 - lat1) * t, lon1 + (lon2 - lon1) * t, b, _DotType.coast);
        }
      }
    }

    // Adiciona hub de cidade
    void hub(double lat, double lon) => pt(lat, lon, 1.0, _DotType.hub);

    // ══════════════════════════════════════════════════════════════════════
    // AFRICA  ── coastline + interior + cidades
    // ══════════════════════════════════════════════════════════════════════
    coast([
      [35.8,-5.9],[36.0,3.0],[37.2,9.8],[36.5,11.0],[33.0,12.0],
      [32.5,15.0],[31.8,20.0],[31.0,25.0],[31.0,32.0],[30.1,33.0],
      [29.0,34.5],[27.5,34.5],[24.0,36.5],[22.0,37.5],[17.0,39.5],
      [15.0,41.5],[12.5,43.5],[12.0,44.0],[11.8,51.0],[10.5,51.5],
      [4.5,48.0],[1.5,42.0],[-1.0,40.5],[-4.5,39.7],[-7.0,39.7],
      [-11.0,40.5],[-15.0,40.2],[-18.0,37.5],[-22.0,35.5],
      [-26.0,33.5],[-30.0,30.5],[-34.0,26.0],[-34.5,20.5],
      [-29.0,17.0],[-22.0,14.5],[-17.0,12.0],[-12.0,13.5],
      [-6.0,12.0],[-1.0,9.5],[1.0,9.8],[3.5,9.0],[5.0,5.0],
      [5.5,2.0],[5.2,-2.0],[4.7,-5.5],[4.5,-8.5],
      [6.0,-11.0],[8.5,-13.5],[10.5,-15.0],[14.7,-17.5],
      [16.5,-16.5],[20.0,-17.0],[22.0,-16.0],[27.5,-13.0],
      [31.0,-9.0],[35.0,-6.5],[35.8,-5.9],
    ]);
    fill( 14, 37,-10, 37,145, b:0.85); // N Africa / Sahara
    fill( 10, 14,-16, 38, 75, b:0.90); // Sahel
    fill(  3, 12,-16,  5, 65, b:0.95); // W Africa
    fill( -6,  5,  5, 28, 62, b:0.92); // C Africa
    fill(  0, 12, 38, 51, 50, b:0.90); // Horn
    fill(-12,  0, 28, 40, 48, b:0.90); // E Africa
    fill(-18, -5, 12, 25, 50, b:0.88); // Angola/Zâmbia
    fill(-34,-12, 15, 36, 65, b:0.90); // S Africa
    fill(-25,-12, 43, 50, 14, b:0.88); // Madagascar
    hub(30.1, 31.2); hub(6.5, 3.4); hub(9.0, 38.7);
    hub(-1.3,36.8); hub(-26.2,28.0); hub(33.6,-7.6);
    hub(-6.8,39.3); hub(14.7,-17.2); hub(-25.9,32.6);

    // ══════════════════════════════════════════════════════════════════════
    // EUROPA  ── muito densa, aparece branca/brilhante na imagem
    // ══════════════════════════════════════════════════════════════════════
    coast([
      [36.5,-9.0],[37.5,-9.0],[38.5,-9.5],[41.0,-8.7],[43.6,-8.8],
      [43.8,-7.0],[43.5,-2.0],[43.5,3.5],[43.3,5.5],[43.5,8.0],
      [44.0,8.5],[43.5,10.5],[40.8,14.0],[37.5,15.5],[38.5,15.8],
      [40.5,18.0],[41.5,15.5],[44.5,14.0],[45.6,13.8],
      [44.5,15.5],[43.5,16.5],[42.5,18.5],[40.0,20.0],[39.5,20.0],
      [37.8,22.0],[37.9,24.0],[38.5,26.2],[39.5,26.5],
      [40.5,27.0],[41.0,29.0],[43.0,28.5],[44.0,29.5],[46.0,30.5],
      [46.5,31.0],[46.7,31.9],[45.0,33.5],[45.5,35.0],
      [47.0,37.5],[46.5,38.0],[47.5,40.0],[46.5,41.0],
      [43.5,40.0],[41.5,41.5],[42.5,45.0],[43.5,47.0],[44.5,48.0],
      [51.5,29.0],[52.5,21.0],[54.5,18.5],[54.5,14.5],[54.5,12.5],
      [55.5,12.5],[56.0,10.5],[57.5,8.0],[58.0,6.5],[58.5,5.0],
      [60.0,5.0],[62.0,5.5],[63.0,8.0],[65.0,14.0],[69.0,18.0],
      [71.0,26.0],[70.5,28.5],[68.5,28.5],[65.5,24.5],[63.5,21.5],
      [60.5,22.5],[59.5,22.0],[58.5,21.5],[58.0,23.0],[56.5,21.0],
      [56.0,18.5],[55.5,14.5],[55.0,13.0],[54.5,11.0],
      [54.0,8.0],[53.5,8.5],[53.0,9.0],[52.5,8.0],
      [51.5,4.5],[51.0,3.5],[50.5,2.5],[50.5,1.5],
      [50.5,-1.0],[49.5,-2.5],[48.0,-4.8],[47.5,-3.0],[47.2,-2.0],
      [46.5,-2.0],[45.5,-1.5],[43.8,-1.8],[43.5,-2.0],[36.5,-9.0],
    ]);
    fill( 36, 44, -9,  3,110); // Ibéria
    fill( 42, 52, -5,  8,135); // França
    fill( 50, 61, -8,  2, 85); // Reino Unido / Irlanda
    fill( 49, 55,  2,  8, 48); // Benelux
    fill( 46, 55,  8, 18, 95); // Alemanha / Áustria
    fill( 37, 47,  7, 18, 90); // Itália
    fill( 36, 48, 13, 28, 92); // Bálcãs / Grécia
    fill( 55, 71,  4, 32,130); // Escandinávia
    fill( 50, 57, 14, 25, 60); // Polônia / Bálticos
    fill( 44, 52, 22, 38, 65); // Ucrânia
    fill( 42, 52, 38, 50, 18); // Cáucaso / Rússia SW
    hub(51.5,-0.1); hub(48.9,2.3); hub(52.5,13.4);
    hub(41.4,2.2); hub(55.8,37.6); hub(41.0,29.0);
    hub(59.9,10.7); hub(60.2,25.0); hub(47.5,19.0); hub(50.1,14.4);
    hub(45.5,9.2); hub(48.2,16.4); hub(52.2,21.0);

    // ══════════════════════════════════════════════════════════════════════
    // ÁSIA
    // ══════════════════════════════════════════════════════════════════════
    coast([
      [36.0,26.0],[36.5,28.0],[37.5,36.0],[37.0,36.5],
      [36.5,36.2],[36.8,36.5],[37.5,40.0],[38.5,42.0],
      [40.0,40.0],[40.5,38.5],[41.0,41.5],[41.5,41.5],
      [41.5,49.5],[40.5,50.0],[38.5,49.0],[37.5,49.5],
      [36.5,52.0],[37.0,54.0],[37.5,57.0],[37.5,57.5],
      [38.5,57.0],[39.0,56.5],[40.5,56.0],[41.0,52.0],
      [42.5,50.5],[43.5,51.0],[44.0,50.5],
    ], b:0.95);
    coast([
      [23.5,57.5],[23.0,58.5],[22.5,59.5],[22.0,59.8],
      [22.5,60.0],[23.5,58.5],[24.0,57.5],[24.5,56.5],
      [24.0,56.0],[23.5,57.5],
    ], b:0.95);
    coast([
      [8.0,77.5],[7.0,77.8],[6.5,80.0],[7.0,81.5],[8.5,81.5],
      [9.5,80.5],[9.5,79.5],[9.0,78.5],[8.0,77.5],
    ], b:0.95); // Sri Lanka
    coast([
      [1.5,103.5],[1.2,104.0],[1.5,104.5],[1.8,104.2],[1.5,103.5],
    ], b:1.0); // Singapura
    fill( 36, 42, 26, 44, 32); // Turquia
    fill( 12, 28, 38, 58, 62); // Arábia
    fill( 28, 37, 34, 48, 28); // Oriente Médio
    fill( 26, 40, 44, 64, 44); // Irã
    fill( 37, 55, 50, 88, 52, b:0.78); // Ásia Central
    fill( 55, 75, 28, 70, 40, b:0.65); // Rússia ocidental
    fill( 55, 75, 70,130, 62, b:0.55); // Sibéria (muito esparsa)
    fill( 23, 37, 60, 77, 36); // Paquistão
    fill(  6, 23, 68, 82, 52); // Índia centro-sul
    fill( 23, 35, 78, 88, 40); // Índia norte / Nepal
    fill( 20, 27, 88, 93, 14); // Bangladesh
    fill(  8, 28, 92,108, 48); // Myanmar / Tailândia / Vietnã
    fill(  1,  8, 99,119, 18); // Malásia
    fill( -8,  6, 95,141, 52); // Indonésia
    fill(  5, 20,117,127, 20); // Filipinas
    fill( 20, 42, 73,125, 96); // China continental
    fill( 42, 52, 87,120, 24); // Mongólia
    fill( 34, 42,126,130, 14); // Coreia
    fill( 30, 46,130,145, 24); // Japão
    hub(35.7,51.4); hub(24.7,46.7); hub(25.2,55.3);
    hub(28.6,77.2); hub(19.1,72.8); hub(23.7,90.4);
    hub(13.8,100.5); hub(1.4,103.8); hub(-6.2,106.8);
    hub(14.6,121.0); hub(22.3,114.2); hub(31.2,121.5);
    hub(39.9,116.4); hub(35.7,139.7); hub(37.6,127.0);
    hub(34.5,69.2); hub(24.9,67.0); hub(3.1,101.7);

    // ══════════════════════════════════════════════════════════════════════
    // AMÉRICAS
    // ══════════════════════════════════════════════════════════════════════
    coast([
      [71.0,-156.0],[71.0,-140.0],[69.5,-141.0],[60.0,-141.0],
      [60.0,-140.5],[59.5,-139.5],[59.0,-138.0],[57.5,-137.5],
      [56.5,-134.0],[54.5,-132.0],[54.5,-130.5],[51.5,-128.0],
      [50.5,-127.5],[49.5,-124.0],[48.5,-124.5],[48.0,-124.5],
      [47.0,-124.2],[46.5,-124.0],[45.5,-124.0],[44.0,-124.5],
      [42.0,-124.5],[40.5,-124.5],[38.0,-122.5],[37.5,-122.5],
      [35.0,-120.5],[34.0,-119.5],[32.5,-117.0],[32.5,-117.0],
      [31.5,-116.5],[28.0,-114.0],[23.0,-110.0],[22.5,-109.5],
      [22.5,-105.5],[20.5,-105.0],[19.5,-105.0],[18.5,-104.0],
      [16.0,-98.0],[15.5,-96.5],[15.5,-92.0],[15.5,-91.5],
      [16.0,-90.0],[16.5,-89.5],[16.5,-88.5],[16.0,-88.0],
      [15.5,-87.0],[15.0,-85.5],[14.5,-85.0],[12.5,-84.0],
      [12.0,-83.5],[11.0,-84.0],[10.0,-85.5],[9.5,-85.0],
      [8.5,-83.5],[8.0,-82.5],[8.0,-80.0],[8.0,-80.0],
      [9.0,-79.5],[9.5,-79.5],[9.5,-79.0],[10.0,-77.5],
      [11.0,-74.0],[12.0,-72.0],[12.5,-72.0],[12.0,-70.5],
      [11.5,-70.0],[11.0,-63.5],[10.5,-63.0],[10.5,-62.0],
      [11.0,-61.5],[11.5,-61.5],[11.0,-60.0],[10.5,-61.5],
      [10.0,-62.0],[10.0,-63.5],[10.5,-64.0],[11.0,-65.0],
      [11.5,-68.0],[12.0,-70.0],[12.5,-72.0],
    ], b:0.92);
    coast([
      [71.0,-156.0],[73.0,-155.0],[71.5,-152.0],[71.5,-150.0],
      [71.0,-148.0],[70.0,-148.5],[69.5,-148.0],[70.0,-146.0],
      [70.5,-145.5],[71.0,-145.5],[71.5,-144.5],[71.5,-143.5],
      [70.5,-143.0],[70.5,-142.5],[71.0,-141.5],[71.0,-140.5],
      [71.0,-156.0],
    ], b:0.65);
    // E coast USA + Canada
    coast([
      [24.5,-81.5],[25.5,-80.0],[27.0,-80.0],[29.0,-81.0],
      [30.5,-81.5],[31.5,-80.5],[32.5,-80.0],[33.5,-79.0],
      [34.5,-77.5],[35.5,-76.5],[36.5,-76.0],[37.5,-75.5],
      [38.5,-75.0],[39.5,-74.0],[40.5,-74.0],[41.5,-71.5],
      [42.0,-70.0],[43.0,-70.5],[44.5,-67.0],[44.5,-66.5],
      [45.0,-66.5],[46.0,-64.0],[46.5,-65.0],[47.0,-64.5],
      [47.5,-60.5],[46.5,-60.5],[46.0,-61.0],[45.5,-61.5],
      [45.0,-61.0],[44.5,-61.0],[44.0,-66.0],[43.5,-66.5],
      [43.0,-70.5],[42.0,-70.0],
    ], b:0.92);
    // Gulf of Mexico / Caribbean
    coast([
      [29.0,-89.0],[29.5,-89.5],[29.5,-90.5],[29.0,-90.0],
      [29.0,-89.0],[29.5,-88.0],[30.0,-87.5],[30.5,-87.5],
      [30.0,-89.0],
    ], b:0.88);
    fill( 48, 70,-140, -52, 80, b:0.78); // Canadá
    fill( 55, 72,-170,-120, 24, b:0.62); // Alasca / NW Canadá
    fill( 26, 50,-125, -65, 98); // EUA
    fill( 14, 30,-118, -86, 36); // México
    fill(  7, 16, -92, -77, 20); // América Central
    hub(40.7,-74.0); hub(34.1,-118.2); hub(41.9,-87.6);
    hub(43.7,-79.4); hub(45.5,-73.6); hub(19.4,-99.1);

    // South America coast
    coast([
      [12.0,-72.0],[11.0,-63.5],[8.0,-62.5],[6.0,-60.5],
      [4.5,-58.0],[3.0,-52.0],[2.0,-50.0],[1.5,-48.5],
      [0.5,-48.5],[-0.5,-48.5],[-1.5,-48.5],[-3.0,-44.5],
      [-2.5,-44.5],[-2.0,-43.5],[-1.0,-44.5],[-1.5,-46.0],
      [-2.0,-42.5],[-2.5,-44.0],[-3.0,-44.5],[-3.5,-38.5],
      [-4.0,-37.5],[-5.0,-35.0],[-5.5,-35.0],[-8.0,-35.0],
      [-10.0,-37.0],[-12.0,-37.5],[-13.0,-39.0],[-15.0,-39.0],
      [-16.0,-39.0],[-18.0,-39.5],[-19.0,-39.5],[-21.0,-41.0],
      [-23.0,-43.0],[-23.0,-43.5],[-23.5,-46.5],[-24.0,-46.5],
      [-25.5,-48.5],[-27.5,-48.5],[-29.5,-50.0],[-32.0,-52.0],
      [-34.0,-53.0],[-34.5,-54.0],[-35.5,-54.0],[-36.0,-55.0],
      [-37.0,-57.0],[-38.0,-57.5],[-38.5,-60.0],[-40.0,-62.0],
      [-41.0,-63.5],[-42.0,-63.5],[-43.0,-65.0],[-45.0,-65.5],
      [-46.0,-67.0],[-47.0,-65.5],[-48.0,-65.5],[-49.0,-68.5],
      [-52.0,-69.5],[-54.5,-65.5],[-55.0,-66.5],[-55.5,-67.5],
      [-54.5,-70.5],[-53.0,-70.5],[-55.0,-68.5],[-54.5,-65.0],
      [-52.0,-69.0],[-53.5,-72.5],[-52.5,-73.5],[-51.0,-75.0],
      [-48.5,-75.5],[-47.0,-74.5],[-45.5,-74.0],[-44.0,-74.0],
      [-43.5,-74.0],[-42.5,-73.5],[-40.0,-73.0],[-38.0,-73.5],
      [-36.0,-73.0],[-34.0,-72.0],[-32.0,-71.5],[-30.0,-71.5],
      [-28.0,-71.5],[-26.0,-71.0],[-24.0,-70.5],[-22.0,-70.5],
      [-20.0,-70.0],[-18.0,-70.5],[-16.0,-75.0],[-15.0,-76.0],
      [-13.0,-77.0],[-12.0,-77.0],[-11.0,-78.0],[-10.0,-78.5],
      [-8.5,-79.5],[-6.5,-80.5],[-4.5,-81.5],[-3.5,-81.0],
      [-1.5,-80.5],[0.0,-80.0],[1.0,-79.5],[1.5,-78.5],[2.0,-77.5],
      [3.0,-77.5],[4.0,-77.0],[5.5,-77.5],[7.0,-77.0],[8.5,-77.5],
      [9.0,-77.5],[9.5,-79.5],[8.0,-80.0],[7.0,-78.0],[5.5,-77.5],
    ], b:0.92);
    fill(  0, 12,-80,-60, 28); // Colômbia/Venezuela
    fill( -8,  0,-78,-35, 42); // Brasil norte
    fill(-28, -8,-58,-35, 48); // Brasil sul
    fill(-35,-28,-73,-52, 20); // Argentina norte
    fill(-55,-35,-75,-52, 30); // Patagônia
    hub(-23.5,-46.6); hub(-34.6,-58.4); hub(4.7,-74.1);
    hub(-12.0,-77.0); hub(-33.5,-70.7); hub(-22.9,-43.2);

    // ══════════════════════════════════════════════════════════════════════
    // AUSTRÁLIA
    // ══════════════════════════════════════════════════════════════════════
    coast([
      [-13.5,135.0],[-12.5,136.0],[-12.0,136.5],[-12.0,137.5],
      [-12.5,139.0],[-13.5,140.0],[-14.5,141.5],[-15.5,145.0],
      [-17.0,146.0],[-18.5,146.5],[-19.5,147.5],[-20.5,148.5],
      [-22.0,150.0],[-23.5,151.5],[-25.0,152.5],[-26.5,153.5],
      [-28.5,153.5],[-30.5,153.0],[-32.0,152.5],[-33.5,151.5],
      [-34.0,151.0],[-35.5,150.5],[-37.0,149.5],[-38.0,148.0],
      [-38.5,147.0],[-39.5,146.5],[-39.5,146.0],[-38.5,145.5],
      [-38.5,145.0],[-38.0,144.5],[-38.5,143.5],[-38.5,143.0],
      [-38.0,141.0],[-37.5,140.0],[-36.5,136.5],[-35.5,136.5],
      [-35.0,135.5],[-34.5,135.5],[-33.5,134.5],[-32.5,133.5],
      [-32.5,133.5],[-32.0,132.5],[-31.5,132.5],[-32.5,131.5],
      [-33.5,115.0],[-32.0,115.5],[-31.5,115.5],[-31.0,115.5],
      [-29.5,115.0],[-28.0,114.5],[-26.5,114.0],[-25.5,113.5],
      [-22.0,114.0],[-21.5,114.5],[-21.0,115.5],[-20.5,116.5],
      [-20.0,118.0],[-19.5,120.5],[-18.5,121.5],[-17.5,122.0],
      [-16.5,122.5],[-15.5,124.5],[-15.0,127.0],[-14.5,128.0],
      [-13.5,130.0],[-12.5,131.5],[-12.5,132.5],[-12.5,133.0],
      [-12.5,135.0],[-13.5,135.0],
    ]);
    fill(-43,-11, 113, 153, 68);
    hub(-33.9,151.2); hub(-37.8,145.0); hub(-27.5,153.0);

    // ══════════════════════════════════════════════════════════════════════
    // GROENLÂNDIA / ANTÁRTICA / OCEANO
    // ══════════════════════════════════════════════════════════════════════
    fill( 60, 83,-55,-15, 32, b:0.50);
    fill(-90,-65,-180,180, 44, b:0.35);
    // Oceano — pontos muito sutis para profundidade
    for (int i = 0; i < 60; i++) {
      final lat = (rng.nextDouble() * 180 - 90) * pi / 180;
      final lon = (rng.nextDouble() * 360 - 180) * pi / 180;
      list.add(_Dot(cos(lat)*sin(lon), sin(lat), cos(lat)*cos(lon), 0.09));
    }

    _dots = list;
  }

  // ── Conexões (1× no init) ─────────────────────────────────────────────────

  void _buildConnections() {
    // Hub-to-hub: dentro de ~3000km
    const hD2 = 0.46 * 0.46;
    // Terra-to-terra local: apenas interior, dentro de ~380km
    const lD2 = 0.060 * 0.060;

    final hubs  = <int>[];
    final lands = <int>[];
    for (int i = 0; i < _dots.length; i++) {
      if (_dots[i].type == _DotType.hub)      hubs.add(i);
      if (_dots[i].type == _DotType.interior) lands.add(i);
    }

    // Hub ↔ Hub
    final cHub = <(int, int)>[];
    for (int i = 0; i < hubs.length - 1; i++) {
      final a = _dots[hubs[i]];
      for (int j = i + 1; j < hubs.length; j++) {
        final b = _dots[hubs[j]];
        final d2 = _d2(a, b);
        if (d2 < hD2) cHub.add((hubs[i], hubs[j]));
      }
    }

    // Terra local (subconjunto de interior — conexões muito curtas)
    final cLand = <(int, int)>[];
    // Para performance: só checa cada ponto com os próximos 80 no array
    // (os pontos foram inseridos por região geográfica, então estão próximos)
    for (int i = 0; i < lands.length - 1; i++) {
      final a = _dots[lands[i]];
      final lim = min(lands.length, i + 80);
      for (int j = i + 1; j < lim; j++) {
        final b = _dots[lands[j]];
        if (_d2(a, b) < lD2) cLand.add((lands[i], lands[j]));
      }
    }

    _connHub  = cHub;
    _connLand = cLand;
  }

  static double _d2(_Dot a, _Dot b) {
    final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return dx*dx + dy*dy + dz*dz;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _GlobePainter(
            time: _ctrl.value,
            sX: _sX, sY: _sY, sR: _sR, sPh: _sPh,
            dots: _dots,
            connHub: _connHub, connLand: _connLand,
            colorTable: _colorTable,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _GlobePainter extends CustomPainter {
  final double time;
  final List<double> sX, sY, sR, sPh;
  final List<_Dot> dots;
  final List<(int, int)> connHub, connLand;
  final List<Color> colorTable;

  // Direção solar fixa no espaço de visão (superior-esquerda → viewer)
  // Sol ligeiramente mais alto-esquerdo para Europa brilhar mais
  static const _sunX = -0.40, _sunY = 0.54, _sunZ = 0.74;

  static const _bg   = Color(0xFF010C18);
  static const _glow = Color(0xFF00B4FF);

  const _GlobePainter({
    required this.time,
    required this.sX, required this.sY,
    required this.sR, required this.sPh,
    required this.dots,
    required this.connHub, required this.connLand,
    required this.colorTable,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    final W  = size.width;
    final H  = size.height;
    final cx = W * 0.500;
    final cy = H * 0.458;
    final r  = min(W * 0.500, H * 0.415);

    final rotY = time * pi * 2;
    final cosR = cos(rotY);
    final sinR = sin(rotY);

    _stars(canvas, W, H);
    _atmOuter(canvas, cx, cy, r);
    _ocean(canvas, cx, cy, r);
    _connections(canvas, cx, cy, r, cosR, sinR);
    _land(canvas, cx, cy, r, cosR, sinR);
    _atmLimb(canvas, cx, cy, r);
    _specular(canvas, cx, cy, r);
    _ring(canvas, cx, cy, r);
    _labels(canvas, size, cx, cy, r);
  }

  // ── Estrelas ──────────────────────────────────────────────────────────────

  void _stars(Canvas canvas, double W, double H) {
    final t = time * pi * 2;
    final p = Paint();
    for (int i = 0; i < sX.length; i++) {
      final tw = 0.42 + 0.58 * sin(t * 0.52 + sPh[i]);
      p.color = Colors.white.withOpacity(0.58 * tw);
      canvas.drawCircle(Offset(sX[i] * W, sY[i] * H), sR[i] * tw, p);
    }
  }

  // ── Halos externos ────────────────────────────────────────────────────────

  void _atmOuter(Canvas canvas, double cx, double cy, double r) {
    // Halo exterior muito amplo
    canvas.drawCircle(Offset(cx, cy), r * 1.90,
      Paint()
        ..color = _glow.withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 75));
    // Halo médio
    canvas.drawCircle(Offset(cx, cy), r * 1.44,
      Paint()
        ..color = _glow.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38));
    // Halo próximo (sutil)
    canvas.drawCircle(Offset(cx, cy), r * 1.18,
      Paint()
        ..color = _glow.withOpacity(0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
  }

  // ── Oceano ────────────────────────────────────────────────────────────────

  void _ocean(Canvas canvas, double cx, double cy, double r) {
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.36),
          colors: [
            const Color(0xFF0C3060),
            const Color(0xFF051838),
            const Color(0xFF02091C),
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
  }

  // ── Conexões ──────────────────────────────────────────────────────────────

  void _connections(Canvas canvas, double cx, double cy, double r,
                    double cosR, double sinR) {
    final pl = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.85;
    final ps = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.45;

    // Rede local de terra
    for (final (i, j) in connLand) {
      final a = dots[i], b = dots[j];
      final azr = a.z * cosR - a.x * sinR;
      final bzr = b.z * cosR - b.x * sinR;
      if (azr < 0.06 || bzr < 0.06) continue;
      final avg = (azr + bzr) * 0.5;
      ps.color = _glow.withOpacity((avg * 0.36).clamp(0.0, 0.32));
      canvas.drawLine(
        Offset(cx + (a.x * cosR + a.z * sinR) * r, cy - a.y * r),
        Offset(cx + (b.x * cosR + b.z * sinR) * r, cy - b.y * r),
        ps);
    }

    // Hub ↔ Hub (linhas mais visíveis e brilhantes)
    for (final (i, j) in connHub) {
      final a = dots[i], b = dots[j];
      final azr = a.z * cosR - a.x * sinR;
      final bzr = b.z * cosR - b.x * sinR;
      if (azr < 0.06 || bzr < 0.06) continue;
      final avg = (azr + bzr) * 0.5;
      final lit = ((a.x * cosR + a.z * sinR) * _sunX + a.y * _sunY + azr * _sunZ)
              .clamp(0.0, 1.0);
      pl.color = colorTable[(lit * 127).round()]
                   .withOpacity((avg * 0.62).clamp(0.0, 0.55));
      canvas.drawLine(
        Offset(cx + (a.x * cosR + a.z * sinR) * r, cy - a.y * r),
        Offset(cx + (b.x * cosR + b.z * sinR) * r, cy - b.y * r),
        pl);
    }
  }

  // ── Pontos de terra com iluminação solar ──────────────────────────────────

  void _land(Canvas canvas, double cx, double cy, double r, double cosR, double sinR) {
    final p = Paint();
    for (final d in dots) {
      final xr = d.x * cosR + d.z * sinR;
      final yr = d.y;
      final zr = d.z * cosR - d.x * sinR;

      // Cull: descarta face traseira
      final minZ = d.type == _DotType.hub ? 0.02 : 0.04;
      if (zr < minZ) continue;

      // Iluminação solar
      final lit = (xr * _sunX + yr * _sunY + zr * _sunZ).clamp(0.0, 1.0);
      final col = colorTable[(lit * 127).round()];

      // Opacidade: profundidade × brilho do dot × fator de iluminação
      final depth = (zr * 1.12).clamp(0.0, 1.0);
      final op    = (depth * d.brightness * (0.42 + lit * 0.64)).clamp(0.0, 1.0);

      final sx = cx + xr * r;
      final sy = cy - yr * r;

      switch (d.type) {
        case _DotType.hub:
          // Halo externo largo — aparece como estrela brilhante
          p.color = col.withOpacity(op * 0.15);
          canvas.drawCircle(Offset(sx, sy), 8.5 + zr * 4.0, p);
          // Halo médio
          p.color = col.withOpacity(op * 0.32);
          canvas.drawCircle(Offset(sx, sy), 4.8 + zr * 2.4, p);
          // Ponto central branco
          p.color = Colors.white.withOpacity(op * 0.96);
          canvas.drawCircle(Offset(sx, sy), 1.8 + zr * 1.0, p);

        case _DotType.coast:
          // Pontos de costa menores mas mais brilhantes → linhas contínuas
          final dr = 0.78 + zr * 0.55;
          p.color = col.withOpacity(op * 0.98);
          canvas.drawCircle(Offset(sx, sy), dr, p);
          if (lit > 0.48 && zr > 0.35) {
            p.color = Colors.white.withOpacity(op * 0.50);
            canvas.drawCircle(Offset(sx, sy), dr * 0.42, p);
          }

        case _DotType.interior:
          // Interior: menor e mais sutil que costa
          final dr = 0.52 + zr * 0.68;
          p.color = col.withOpacity(op * 0.78);
          canvas.drawCircle(Offset(sx, sy), dr, p);
          if (lit > 0.58 && zr > 0.45) {
            p.color = Colors.white.withOpacity(op * 0.28);
            canvas.drawCircle(Offset(sx, sy), dr * 0.38, p);
          }
      }
    }
  }

  // ── Limbo atmosférico ─────────────────────────────────────────────────────

  void _atmLimb(Canvas canvas, double cx, double cy, double r) {
    // Limbo principal — anel brilhante na borda (como na referência)
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            _glow.withOpacity(0.03),
            _glow.withOpacity(0.62),
            _glow.withOpacity(0.96),
            Colors.white.withOpacity(0.18),
          ],
          stops: const [0.0, 0.62, 0.78, 0.91, 0.97, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
  }

  // ── Destaque especular ────────────────────────────────────────────────────

  void _specular(Canvas canvas, double cx, double cy, double r) {
    final sc = Offset(cx - r * 0.28, cy - r * 0.36);
    canvas.drawCircle(sc, r * 0.54,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.24),
            Colors.white.withOpacity(0.07),
            Colors.transparent,
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(Rect.fromCircle(center: sc, radius: r * 0.54)));
  }

  // ── Anel de brilho ────────────────────────────────────────────────────────

  void _ring(Canvas canvas, double cx, double cy, double r) {
    final p = 0.93 + 0.07 * sin(time * pi * 2 * 0.9);
    // Anel nítido mais próximo
    canvas.drawCircle(Offset(cx, cy), r * 1.007 * p,
      Paint()
        ..color = _glow.withOpacity(0.90)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // Segundo anel difuso
    canvas.drawCircle(Offset(cx, cy), r * 1.022,
      Paint()
        ..color = _glow.withOpacity(0.42)
        ..strokeWidth = 10.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    // Terceiro anel — halo largo externo
    canvas.drawCircle(Offset(cx, cy), r * 1.048,
      Paint()
        ..color = _glow.withOpacity(0.15)
        ..strokeWidth = 22.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
  }

  // ── Labels ────────────────────────────────────────────────────────────────

  void _labels(Canvas canvas, Size size, double cx, double cy, double r) {
    void t(String s, double y, double op, double fs, double ls, Color c) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(
          color: c.withOpacity(op), fontSize: fs,
          fontWeight: FontWeight.w700, letterSpacing: ls,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, y));
    }
    final bot = cy + r + size.height * 0.026;
    t('NÚCLEO DE INTELIGÊNCIA', bot, 0.95, 14.0, 3.8, Colors.white);
    t('Análise em tempo real  •  Conectando toda a frota',
      bot + 24, 0.50, 9.2, 1.3, _glow);
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.time != time;
}

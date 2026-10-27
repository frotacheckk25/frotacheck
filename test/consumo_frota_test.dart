import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/abastecimentos/consumo_frota_page.dart';

Map<String, dynamic> abast(String data, num odo, num litros, {String vid = 'v1', num valor = 300}) =>
    {'vehicle_id': vid, 'fuel_date': data, 'fuel_time': '08:00', 'odometer': odo, 'liters': litros, 'total_value': valor};

void main() {
  test('km/l por trecho e média do veículo', () {
    final r = calcularConsumo([
      abast('2026-10-01', 1000, 40),
      abast('2026-10-05', 1500, 50), // 500 km / 50 L = 10 km/l
      abast('2026-10-09', 2100, 50), // 600 / 50 = 12
    ]);
    final t = r.trechos['v1']!;
    expect(t.length, 2);
    expect(t[0].kmPorLitro, 10);
    expect(t[1].kmPorLitro, 12);
    expect(mediaKmL(t), closeTo(1100 / 100, 0.0001)); // soma dos km ÷ soma dos litros
  });

  test('odômetro que volta é apontado e não distorce a média', () {
    final r = calcularConsumo([
      abast('2026-10-01', 1000, 40),
      abast('2026-10-05', 1500, 50), // 10 km/l
      abast('2026-10-09', 1400, 50), // voltou: inconsistente
      abast('2026-10-13', 2000, 50), // recomeça daqui (sem trecho)
      abast('2026-10-17', 2500, 50), // 10 km/l
    ]);
    expect(r.inconsistentes.length, 1);
    expect(r.inconsistentes.first['odometer'], 1400);
    expect(r.trechos['v1']!.map((t) => t.kmPorLitro), [10, 10]);
  });

  test('salto grande de km (erro de digitação) é apontado', () {
    final r = calcularConsumo([
      abast('2026-10-01', 1000, 40),
      abast('2026-10-05', 91000, 50), // 90.000 km em um tanque: erro
      abast('2026-10-09', 91500, 50), // recomeça
      abast('2026-10-13', 92000, 50), // 10 km/l
    ]);
    expect(r.inconsistentes.length, 1);
    expect(r.trechos['v1']!.map((t) => t.kmPorLitro), [10]);
  });

  test('abastecimento sem odômetro é ignorado e veículos não se misturam', () {
    final r = calcularConsumo([
      abast('2026-10-01', 1000, 40),
      abast('2026-10-03', 0, 30), // sem odômetro
      abast('2026-10-05', 1500, 50),
      abast('2026-10-01', 5000, 100, vid: 'v2'),
      abast('2026-10-04', 5300, 100, vid: 'v2'), // 3 km/l (caminhão)
    ]);
    expect(r.trechos['v1']!.single.kmPorLitro, 10);
    expect(r.trechos['v2']!.single.kmPorLitro, 3);
    expect(r.inconsistentes, isEmpty);
  });
}

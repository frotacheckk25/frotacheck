/// Uma leitura do GPS do celular (mesmo formato no app e no navegador).
class LeituraGps {
  const LeituraGps({
    required this.latitude,
    required this.longitude,
    this.velocidadeKmh,
    this.precisaoM,
    this.rumo,
    required this.quando,
  });
  final double latitude, longitude;
  final double? velocidadeKmh, precisaoM, rumo;
  final DateTime quando;
}

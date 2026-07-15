import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

/// Versão do app (de pubspec.yaml, via package_info_plus) + data da última
/// publicação (de assets/build_info.json — não existe um jeito automático
/// de saber isso em runtime, então esse arquivo precisa ser regravado com a
/// data atual antes de cada build/deploy).
class AppBuildInfo {
  final String version;
  final String buildNumber;
  final DateTime? publishedAt;

  const AppBuildInfo({
    required this.version,
    required this.buildNumber,
    required this.publishedAt,
  });
}

Future<AppBuildInfo> loadAppBuildInfo() async {
  final pkg = await PackageInfo.fromPlatform();

  DateTime? publishedAt;
  try {
    final raw = await rootBundle.loadString('assets/build_info.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    publishedAt = DateTime.tryParse(json['publishedAt']?.toString() ?? '');
  } catch (_) {
    // Sem assets/build_info.json (ou mal-formado) — segue sem data.
  }

  return AppBuildInfo(
    version: pkg.version,
    buildNumber: pkg.buildNumber,
    publishedAt: publishedAt,
  );
}

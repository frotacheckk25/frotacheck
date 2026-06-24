import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Runtime config (Web friendly).
///
/// IMPORTANTE:
/// - Não usar String.fromEnvironment aqui, porque plataformas como Vercel/Netlify
///   não injetam automaticamente dart-define durante o build do Flutter Web.
/// - Este arquivo carrega [web/config.json] em runtime.
class SupabaseConfig {
  static const _configAssetPath = 'web/config.json';

  static Future<String> getUrl() async {
    final config = await _loadConfig();
    return (config['SUPABASE_URL'] ?? '').toString().trim();
  }

  static Future<String> getPublishableKey() async {
    final config = await _loadConfig();
    return (config['SUPABASE_KEY'] ?? '').toString().trim();
  }

  static Future<Map<String, dynamic>> getConfigForDebug() async {
    return _loadConfig();
  }

  static Future<Map<String, dynamic>> _loadConfig() async {
    final raw = await rootBundle.loadString(_configAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const {};
  }
}

import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rseefinwtlrjhzosvmgt.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_nX6Q8wyti_TP_ImjCUXyXg_Knlko9CZ',
  );
}

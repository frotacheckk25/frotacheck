import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/login_page.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const FrotaCheckApp());
}

class FrotaCheckApp extends StatelessWidget {
  const FrotaCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FrotaCheck',

      theme: AppTheme.darkTheme,

      home: const LoginPage(),
    );
  }
}

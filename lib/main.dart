import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/login_page.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (e, st) {
    debugPrint('Supabase initialization error: $e');
    debugPrint('Stack trace: $st');
  }

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

class ErrorBoundary extends StatelessWidget {
  final Widget child;
  const ErrorBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (e, st) {
      debugPrint('Widget error: $e\n$st');
      return Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Text(
            'Erro na aplicação: ${e.toString()}',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }
}

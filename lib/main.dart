import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'features/auth/login_page.dart';
import 'features/home_page.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/auth/app_auth_provider.dart';
import 'core/guards/app_guard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
  };

  runZonedGuarded(
    () async {
      bool supabaseReady = false;
      String? supabaseError;

      try {
        final url = (await SupabaseConfig.getUrl()).trim();
        final key = (await SupabaseConfig.getPublishableKey()).trim();

        // Guardrails: evita inicializar o plugin com credenciais inválidas.
        if (url.isEmpty || key.isEmpty) {
          throw StateError(
            'Supabase URL/KEY ausentes. Verifique SUPABASE_URL e SUPABASE_KEY no build.',
          );
        }

        if (key.startsWith('sb_publishable_') == false) {
          debugPrint(
            'Warning: publishableKey não parece válida: ${key.substring(0, key.length < 8 ? key.length : 8)}...',
          );
        }

        await Supabase.initialize(url: url, publishableKey: key);
        supabaseReady = true;
      } catch (e, st) {
        supabaseError = e.toString();
        debugPrint('Supabase initialization error: $e');
        debugPrint('Stack trace: $st');
      }

      runApp(
        supabaseReady
            ? const FrotaCheckApp()
            : FrotaCheckAppSupabaseError(
                errorMessage:
                    supabaseError ??
                    'Erro desconhecido ao inicializar Supabase',
              ),
      );
    },
    (Object error, StackTrace stack) {
      debugPrint('Zoned error: $error');
      debugPrint('$stack');

      runApp(FrotaCheckAppSupabaseError(errorMessage: error.toString()));
    },
  );
}

class FrotaCheckApp extends StatelessWidget {
  const FrotaCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppAuthProvider()..initialize(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FrotaCheck',
        theme: AppTheme.darkTheme,
        home: AppGuard(
          authenticated: const HomePage(),
          unauthenticated: const LoginPage(),
        ),
      ),
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

class FrotaCheckAppSupabaseError extends StatelessWidget {
  final String errorMessage;

  const FrotaCheckAppSupabaseError({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FrotaCheck - Erro',
      theme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: Colors.black87,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFef4444),
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Falha ao inicializar Supabase no Web',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      errorMessage,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Verifique as env vars: SUPABASE_URL e SUPABASE_KEY (Vercel/Build settings).',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
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
}

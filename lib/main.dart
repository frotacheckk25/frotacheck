import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';

import 'features/auth/login_page.dart';
import 'features/home_page.dart';
import 'home/master/master_dashboard_page.dart';
import 'home/motorista/motorista_home_page.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/auth/app_auth_provider.dart';
import 'core/enums/app_role.dart';
import 'core/guards/app_guard.dart';
import 'core/utils/page_reload.dart';
import 'core/services/push_notification_service.dart';

Future<void> _initFirebaseIfSupported() async {
  if (!pushNotificationsSupported) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
  } catch (e) {
    // Comum antes do google-services.json existir — não deve derrubar o app.
    debugPrint('Firebase indisponível (notificações push desativadas): $e');
  }
}

void main() {
  bool zoneErrorHandled = false;
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        debugPrint('FlutterError: ${details.exception}');
        debugPrint('${details.stack}');
      };

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

      await _initFirebaseIfSupported();

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
      if (!zoneErrorHandled) {
        zoneErrorHandled = true;
        runApp(FrotaCheckAppSupabaseError(errorMessage: error.toString()));
      }
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
          authenticated: const _MasterAwareRouter(),
          unauthenticated: const LoginPage(),
        ),
      ),
    );
  }
}

class _MasterAwareRouter extends StatefulWidget {
  const _MasterAwareRouter();

  @override
  State<_MasterAwareRouter> createState() => _MasterAwareRouterState();
}

class _MasterAwareRouterState extends State<_MasterAwareRouter> {
  String? _pushInitDoneForUser;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();

    // Só ADMIN_EMPRESA/GESTOR recebem push de eventos da frota — evita pedir
    // permissão de notificação de quem nunca vai receber nada (motorista).
    final wantsPush = auth.role == AppRole.adminEmpresa || auth.role == AppRole.gestor;
    final userId = auth.profile?.userId;
    if (wantsPush && userId != null && _pushInitDoneForUser != userId && pushNotificationsSupported) {
      _pushInitDoneForUser = userId;
      PushNotificationService.instance.init();
    }

    if (auth.isMaster && !auth.isImpersonating) {
      return const MasterDashboardPage();
    }
    if (auth.role == AppRole.motorista && !auth.isImpersonating) {
      return const MotoristaHomePage();
    }
    return const HomePage();
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
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => reloadPage(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar Novamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Se o erro persistir, pressione Ctrl+Shift+R para forçar recarregamento sem cache.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
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

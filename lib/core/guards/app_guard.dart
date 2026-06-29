import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/app_auth_provider.dart';
import '../theme/app_theme.dart';

/// Guard raiz: decide o que exibir com base no estado de autenticação.
/// Toda lógica de redirecionamento fica aqui — as telas não precisam saber.
class AppGuard extends StatelessWidget {
  final Widget authenticated;   // exibido quando logado e ativo
  final Widget unauthenticated; // exibido quando não logado

  const AppGuard({
    required this.authenticated,
    required this.unauthenticated,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();

    if (auth.loading)     return const _SplashScreen();
    if (auth.isBlocked)   return const _BlockedScreen();
    if (auth.isPending)   return const _PendingScreen();
    if (!auth.isAuthenticated) return unauthenticated;

    // Key garante que toda a subárvore é recriada do zero quando
    // um usuário diferente faz login (userId muda → dispose + initState completo).
    return KeyedSubtree(
      key: ValueKey(auth.profile?.userId),
      child: authenticated,
    );
  }
}

// ── Telas internas ────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.secondary),
            SizedBox(height: 24),
            Text(
              'Carregando...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingScreen extends StatelessWidget {
  const _PendingScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AppAuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pending_actions,
                  color: AppColors.warning, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Aguardando aprovação',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sua conta foi criada e está aguardando\num administrador vincular sua empresa e papel.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: auth.reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Verificar novamente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: auth.signOut,
                child: const Text(
                  'Sair',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AppAuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, color: AppColors.danger, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Conta bloqueada',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sua conta foi bloqueada. Entre em contato\ncom o administrador da sua empresa.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: auth.signOut,
                child: const Text(
                  'Sair',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

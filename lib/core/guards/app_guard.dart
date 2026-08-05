import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/app_auth_provider.dart';
import '../theme/app_theme.dart';
import '../../shared/widgets/install_app_banner.dart';

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
    if (auth.needsPasswordReset) return const _PasswordRecoveryScreen();
    if (auth.isBlocked)   return const _BlockedScreen();
    if (auth.isPending)   return const _PendingScreen();
    if (auth.isInactive)  return const _InactiveScreen();
    if (!auth.isAuthenticated) return unauthenticated;
    if (auth.needsMfaChallenge) return const _MfaChallengeScreen();

    // Key garante que toda a subárvore é recriada do zero quando
    // um usuário diferente faz login (userId muda → dispose + initState completo).
    // Column (não Stack) para o banner empurrar o conteúdo em vez de cobri-lo.
    return Column(
      children: [
        const InstallAppBanner(),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(auth.profile?.userId),
            child: authenticated,
          ),
        ),
      ],
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

class _InactiveScreen extends StatelessWidget {
  const _InactiveScreen();

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
              const Icon(Icons.pause_circle_outline,
                  color: AppColors.warning, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Conta inativa',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sua conta está marcada como inativa.\nEntre em contato com o administrador da sua empresa.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
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

class _MfaChallengeScreen extends StatefulWidget {
  const _MfaChallengeScreen();

  @override
  State<_MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<_MfaChallengeScreen> {
  final _codeCtrl = TextEditingController();
  bool _verificando = false;
  String? _erro;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _erro = 'Digite os 6 dígitos do código.');
      return;
    }
    setState(() {
      _verificando = true;
      _erro = null;
    });
    try {
      final mfa = Supabase.instance.client.auth.mfa;
      final factors = await mfa.listFactors();
      if (factors.totp.isEmpty) {
        setState(() => _erro = 'Nenhum fator de autenticação encontrado. Contate o suporte.');
        return;
      }
      await mfa.challengeAndVerify(factorId: factors.totp.first.id, code: code);
      // challengeAndVerify dispara AuthChangeEvent.mfaChallengeVerified —
      // AppAuthProvider reage e o AppGuard reconstrói sozinho, sem precisar
      // de navegação manual aqui.
    } catch (_) {
      if (mounted) setState(() => _erro = 'Código inválido ou expirado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AppAuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: AppColors.secondary, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Verificação em duas etapas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Digite o código de 6 dígitos do seu aplicativo autenticador.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(color: AppColors.textSecondary, letterSpacing: 8),
                  ),
                  onSubmitted: (_) => _verificar(),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(_erro!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verificando ? null : _verificar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _verificando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Verificar'),
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
      ),
    );
  }
}

class _PasswordRecoveryScreen extends StatefulWidget {
  const _PasswordRecoveryScreen();

  @override
  State<_PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<_PasswordRecoveryScreen> {
  final _novaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _obscureNova = true;
  bool _obscureConfirmar = true;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _novaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  String _erroAmigavel(Object e) {
    final r = e.toString().toLowerCase();
    if (r.contains('should be at least') || r.contains('password should')) {
      return 'A senha é muito curta.';
    }
    if (r.contains('same as') || r.contains('same_password')) {
      return 'A nova senha precisa ser diferente da atual.';
    }
    if (r.contains('network') || r.contains('socketexception')) {
      return 'Sem conexão. Verifique sua internet.';
    }
    return 'Não foi possível salvar a nova senha. Tente novamente.';
  }

  Future<void> _salvar() async {
    final nova = _novaCtrl.text;
    final confirmar = _confirmarCtrl.text;
    if (nova.length < 6) {
      setState(() => _erro = 'A senha precisa ter pelo menos 6 caracteres.');
      return;
    }
    if (nova != confirmar) {
      setState(() => _erro = 'As senhas não coincidem.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: nova));
      if (!mounted) return;
      await context.read<AppAuthProvider>().clearPasswordRecovery();
    } catch (e) {
      if (mounted) setState(() => _erro = _erroAmigavel(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AppAuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_reset_rounded,
                    color: AppColors.secondary, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Definir nova senha',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Escolha uma nova senha para acessar sua conta no FrotaCheck.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _novaCtrl,
                  autofocus: true,
                  obscureText: _obscureNova,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nova senha',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNova ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary),
                      onPressed: () => setState(() => _obscureNova = !_obscureNova),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmarCtrl,
                  obscureText: _obscureConfirmar,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Confirmar nova senha',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmar ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary),
                      onPressed: () => setState(() => _obscureConfirmar = !_obscureConfirmar),
                    ),
                  ),
                  onSubmitted: (_) => _salvar(),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(_erro!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _salvando ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _salvando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Salvar e entrar'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: auth.signOut,
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
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

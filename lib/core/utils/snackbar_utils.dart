import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Traduz erros técnicos (PostgrestException, AuthException, SocketException, etc.)
/// em mensagens curtas e compreensíveis para o usuário final, evitando vazar
/// detalhes de schema/SQL/stack em snackbars.
String friendlyError(Object e, {String fallback = 'Não foi possível concluir a operação. Tente novamente.'}) {
  final raw = e.toString().toLowerCase();
  if (raw.contains('violates row-level security') || raw.contains('rls') || raw.contains('permission denied')) {
    return 'Você não tem permissão para realizar esta ação.';
  }
  if (raw.contains('duplicate key') || raw.contains('23505') || raw.contains('already exists')) {
    return 'Este registro já existe.';
  }
  if (raw.contains('foreign key') || raw.contains('23503') || raw.contains('violates foreign key constraint')) {
    return 'Não é possível concluir: este registro está vinculado a outro dado do sistema.';
  }
  if (raw.contains('violates not-null constraint') || raw.contains('23502')) {
    return 'Preencha todos os campos obrigatórios.';
  }
  if (raw.contains('invalid login credentials')) return 'E-mail ou senha incorretos.';
  if (raw.contains('email not confirmed')) return 'Confirme seu e-mail antes de entrar.';
  if (raw.contains('too many requests') || raw.contains('rate limit')) return 'Muitas tentativas. Aguarde alguns minutos.';
  if (raw.contains('user not found')) return 'Usuário não encontrado.';
  if (raw.contains('jwt') || raw.contains('session') || raw.contains('not authenticated')) {
    return 'Sua sessão expirou. Faça login novamente.';
  }
  if (raw.contains('network') || raw.contains('socketexception') || raw.contains('failed host lookup') || raw.contains('connection')) {
    return 'Sem conexão com o servidor. Verifique sua internet.';
  }
  if (raw.contains('timeout')) return 'A operação demorou demais. Tente novamente.';
  if (raw.contains('storage') && raw.contains('not found')) return 'Arquivo não encontrado.';
  return fallback;
}

/// Atalho: mostra um snackbar de erro já traduzido a partir de uma exceção crua.
void showErrorFrom(BuildContext context, Object e, {String? prefix}) {
  final msg = friendlyError(e);
  showError(context, prefix != null ? '$prefix $msg' : msg);
}

void showSuccess(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
}

// Alerta de atividade da frota (nova notificação chegando em tempo real) —
// mais chamativo que showSuccess/showError: fica mais tempo na tela e mostra
// título + corpo da notificação, para o admin/gestor/dono perceber mesmo
// sem estar olhando o sino.
void showNotificationToast(BuildContext context, {required String titulo, required String corpo}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              if (corpo.isNotEmpty)
                Text(corpo, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ]),
      backgroundColor: AppColors.secondary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 5),
    ));
}

void showError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
}

class ConnectionErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const ConnectionErrorWidget({super.key, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFF475569), size: 52),
            const SizedBox(height: 14),
            Text(
              message ?? 'Sem conexão com o servidor',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6),
                side: const BorderSide(color: Color(0xFF1E3A5F)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

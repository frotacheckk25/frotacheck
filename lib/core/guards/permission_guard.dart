import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/app_auth_provider.dart';
import '../enums/app_permission.dart';
import '../enums/app_role.dart';
import '../theme/app_theme.dart';

/// Guard de permissão: centraliza a lógica de acesso.
/// Use [permission] OU [roles] para definir o critério de acesso.
class PermissionGuard extends StatelessWidget {
  final AppPermission? permission;
  final List<AppRole>? roles;
  final Widget child;
  final Widget? fallback;

  const PermissionGuard({
    super.key,
    this.permission,
    this.roles,
    required this.child,
    this.fallback,
  }) : assert(
          permission != null || roles != null,
          'PermissionGuard requer pelo menos permission ou roles',
        );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();

    final allowed = (permission != null && auth.can(permission!)) ||
        (roles != null && auth.hasAnyRole(roles!));

    if (allowed) return child;
    return fallback ?? const AccessDeniedPage();
  }
}

/// Tela padrão exibida quando acesso é negado.
class AccessDeniedPage extends StatelessWidget {
  final String? message;
  const AccessDeniedPage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: AppColors.danger, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Acesso Negado',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ??
                    'Você não tem permissão para acessar esta área.\nContate o administrador da sua empresa.',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
                label: const Text(
                  'Voltar',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/enums/app_role.dart';
import '../../core/guards/permission_guard.dart';
import '../../core/theme/app_theme.dart';

class AdminUsuariosPage extends StatelessWidget {
  const AdminUsuariosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: AppPermission.viewUsers,
      child: const _AdminUsuariosView(),
    );
  }
}

class _AdminUsuariosView extends StatefulWidget {
  const _AdminUsuariosView();

  @override
  State<_AdminUsuariosView> createState() => _AdminUsuariosViewState();
}

class _AdminUsuariosViewState extends State<_AdminUsuariosView> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _empresas = [];
  bool _loading = true;
  String? _erro;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _carregar();
    _setupRealtime();
  }

  void _setupRealtime() {
    _channel = _supabase
        .channel('admin_usuarios_rt')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_profiles',
          callback: (_) => _carregar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'empresas',
          callback: (_) => _carregar(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() { _loading = true; _erro = null; });
    try {
      final auth = context.read<AppAuthProvider>();

      // MASTER vê todos os usuários; demais papéis veem apenas a própria empresa (RLS garante)
      var query = _supabase
          .from('user_profiles')
          .select('*, empresas(nome)')
          .order('created_at', ascending: false);

      final res = await query;
      final lista = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      List<Map<String, dynamic>> empresas = [];
      if (auth.isMaster) {
        final empRes = await _supabase
            .from('empresas')
            .select('id, nome')
            .order('nome');
        empresas = (empRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _usuarios = lista;
        _empresas = empresas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _erro = e.toString(); _loading = false; });
    }
  }

  Future<void> _alterarRole(String userId, AppRole novoRole) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({'role': novoRole.label})
          .eq('user_id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _alterarStatus(String userId, String novoStatus) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({'status': novoStatus})
          .eq('user_id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _alterarEmpresa(String userId, String empresaId) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({'empresa_id': empresaId})
          .eq('user_id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final canManage = auth.can(AppPermission.manageUsers);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestão de Usuários'),
        backgroundColor: AppColors.surface,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
          : _erro != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_erro!, style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _carregar, child: const Text('Tentar novamente')),
                    ],
                  ),
                )
              : _buildLista(auth, canManage),
    );
  }

  Widget _buildLista(AppAuthProvider auth, bool canManage) {
    if (_usuarios.isEmpty) {
      return const Center(
        child: Text('Nenhum usuário encontrado.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _usuarios.length,
      itemBuilder: (_, i) => _buildCard(_usuarios[i], auth, canManage),
    );
  }

  Widget _buildCard(
    Map<String, dynamic> u,
    AppAuthProvider auth,
    bool canManage,
  ) {
    final userId = u['user_id']?.toString() ?? '';
    final nome = u['nome']?.toString() ?? u['email']?.toString() ?? 'Sem nome';
    final email = u['email']?.toString() ?? '';
    final status = u['status']?.toString() ?? 'ativo';
    final roleStr = u['role']?.toString() ?? 'MOTORISTA';
    final role = AppRole.fromString(roleStr);
    final empresaNome = (u['empresas'] is Map)
        ? (u['empresas'] as Map)['nome']?.toString()
        : null;
    final lastAccess = u['last_access'] != null
        ? DateTime.tryParse(u['last_access'].toString())?.toLocal()
        : null;

    final isMe = userId == auth.profile?.userId;
    final isMasterUser = role == AppRole.master;
    final canEdit = canManage && !isMe && !(isMasterUser && !auth.isMaster);

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'ativo':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_outline;
        break;
      case 'bloqueado':
        statusColor = AppColors.danger;
        statusIcon = Icons.block;
        break;
      case 'pendente':
        statusColor = AppColors.warning;
        statusIcon = Icons.pending_actions;
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.circle_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Avatar
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: role.color.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: role.color.withOpacity(0.40)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(nome),
                    style: TextStyle(
                      color: role.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nome,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Você',
                                style: TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.30)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Info row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(role.displayName, role.color),
                if (empresaNome != null) _chip(empresaNome, AppColors.primary),
                if (lastAccess != null)
                  _chip(
                    'Último acesso: ${_fmtDate(lastAccess)}',
                    AppColors.textSecondary,
                  ),
              ],
            ),

            // Actions (only if canEdit)
            if (canEdit) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Role dropdown
                  Expanded(
                    child: _ActionDropdown<AppRole>(
                      label: 'Papel',
                      value: role,
                      items: _rolesDisponiveis(auth),
                      itemLabel: (r) => r.displayName,
                      onChanged: (r) => _alterarRole(userId, r),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status dropdown
                  Expanded(
                    child: _ActionDropdown<String>(
                      label: 'Status',
                      value: status,
                      items: const ['ativo', 'pendente', 'bloqueado', 'inativo'],
                      itemLabel: (s) => s,
                      onChanged: (s) => _alterarStatus(userId, s),
                    ),
                  ),
                  // Empresa dropdown (MASTER only)
                  if (auth.isMaster && _empresas.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _EmpresaDropdown(
                        empresas: _empresas,
                        currentId: u['empresa_id']?.toString(),
                        onChanged: (id) => _alterarEmpresa(userId, id),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<AppRole> _rolesDisponiveis(AppAuthProvider auth) {
    if (auth.isMaster) return AppRole.values;
    return [AppRole.adminEmpresa, AppRole.gestor, AppRole.motorista];
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _ActionDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T) onChanged;

  const _ActionDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          dropdownColor: const Color(0xFF0B1528),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          icon: const Icon(Icons.unfold_more_rounded, color: AppColors.textSecondary, size: 14),
          items: items.map((t) => DropdownMenuItem<T>(
            value: t,
            child: Text(itemLabel(t)),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

class _EmpresaDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> empresas;
  final String? currentId;
  final void Function(String) onChanged;

  const _EmpresaDropdown({
    required this.empresas,
    required this.currentId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final validId = empresas.any((e) => e['id']?.toString() == currentId)
        ? currentId
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validId,
          isExpanded: true,
          hint: const Text('Empresa', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          dropdownColor: const Color(0xFF0B1528),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          icon: const Icon(Icons.unfold_more_rounded, color: AppColors.textSecondary, size: 14),
          items: empresas.map((e) => DropdownMenuItem<String>(
            value: e['id']?.toString(),
            child: Text(e['nome']?.toString() ?? '—', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

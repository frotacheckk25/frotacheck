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
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = true;
  String? _erro;
  bool _isEditing = false; // BUG-17: suppresses realtime rebuild during active edits
  RealtimeChannel? _channel;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
          // BUG-17: don't rebuild while a dialog/form is being edited
          callback: (_) { if (!_isEditing) _carregar(); },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'empresas',
          callback: (_) { if (!_isEditing) _carregar(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final auth = context.read<AppAuthProvider>();

      // Defense-in-depth: filtra por empresa_id para não-MASTER (RLS é fallback, não única camada)
      List<Map<String, dynamic>> res;
      if (auth.isMaster) {
        res = await _supabase
            .from('user_profiles')
            .select('*, empresas(nome)')
            .order('created_at', ascending: false)
            .limit(200);
      } else {
        final minhaEmpresa = auth.empresaId;
        if (minhaEmpresa != null) {
          res = await _supabase
              .from('user_profiles')
              .select('*, empresas(nome)')
              .eq('empresa_id', minhaEmpresa)
              .order('created_at', ascending: false)
              .limit(200);
        } else {
          res = await _supabase
              .from('user_profiles')
              .select('*, empresas(nome)')
              .order('created_at', ascending: false)
              .limit(200);
        }
      }
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

      List<Map<String, dynamic>> drivers = [];
      try {
        var drQuery = _supabase
            .from('drivers')
            .select('id, name');
        if (!auth.isMaster) {
          final minhaEmpresa = auth.empresaId;
          if (minhaEmpresa != null) {
            drQuery = drQuery.eq('empresa_id', minhaEmpresa);
          }
        }
        final drRes = await drQuery.order('name');
        drivers = (drRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}

      List<Map<String, dynamic>> vehicles = [];
      try {
        var vQuery = _supabase
            .from('vehicles')
            .select('id, plate, model, brand, driver_id');
        if (!auth.isMaster) {
          final minhaEmpresa = auth.empresaId;
          if (minhaEmpresa != null) {
            vQuery = vQuery.eq('empresa_id', minhaEmpresa);
          }
        }
        final vRes = await vQuery.order('plate');
        vehicles = (vRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _usuarios = lista;
        _empresas = empresas;
        _drivers = drivers;
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _alterarRole(String userId, AppRole novoRole) async {
    // Ao atribuir admin_empresa a usuário sem empresa → criar empresa automaticamente
    if (novoRole == AppRole.adminEmpresa) {
      final perfil = _usuarios.firstWhere(
        (u) => u['user_id']?.toString() == userId,
        orElse: () => <String, dynamic>{},
      );
      if (perfil['empresa_id'] == null) {
        await _criarEmpresaParaAdmin(userId, perfil);
        return;
      }
    }
    try {
      await _supabase
          .from('user_profiles')
          .update({'role': novoRole.label})
          .eq('user_id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _criarEmpresaParaAdmin(
      String userId, Map<String, dynamic> perfil) async {
    final nomeInicial =
        perfil['nome']?.toString() ?? perfil['email']?.toString() ?? '';
    final controller = TextEditingController(text: nomeInicial);

    setState(() => _isEditing = true);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Criar empresa',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uma empresa será criada para este admin. '
              'O admin poderá editar o nome depois.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nome da empresa',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Criar e vincular'),
          ),
        ],
      ),
    );

    final nomeEmpresa = controller.text.trim();
    controller.dispose();
    setState(() => _isEditing = false);
    if (confirmed != true || nomeEmpresa.isEmpty) return;

    try {
      final novaEmpresa = await _supabase
          .from('empresas')
          .insert({'nome': nomeEmpresa})
          .select('id')
          .single();

      await _supabase.from('user_profiles').update({
        'role': AppRole.adminEmpresa.label,
        'empresa_id': novaEmpresa['id'],
      }).eq('user_id', userId);

      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Empresa "$nomeEmpresa" criada e admin vinculado!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar empresa: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Vincula diretamente um veículo a um motorista.
  /// Cria o registro de driver automaticamente se ainda não existir.
  Future<void> _vincularVeiculoDireto(
      String userId, String? vehicleId, Map<String, dynamic> perfil) async {
    try {
      final currentDriverId = perfil['driver_id']?.toString();
      final empresaId = perfil['empresa_id']?.toString();
      final userName =
          perfil['nome']?.toString().isNotEmpty == true
              ? perfil['nome'].toString()
              : perfil['email']?.toString() ?? 'Motorista';

      if (vehicleId == null) {
        // Desvincular veículo
        if (currentDriverId != null) {
          await _supabase
              .from('vehicles')
              .update({'driver_id': null})
              .eq('driver_id', currentDriverId);
        }
        await _supabase
            .from('user_profiles')
            .update({'driver_id': null})
            .eq('user_id', userId);
        await _carregar();
        return;
      }

      // Obter ou criar driver para este usuário
      String driverId;
      if (currentDriverId != null) {
        driverId = currentDriverId;
      } else {
        // Antes de criar, tenta achar um driver existente para este usuário
        String? existingId;
        try {
          final byUid = await _supabase
              .from('drivers')
              .select('id')
              .eq('user_id', userId)
              .maybeSingle();
          if (byUid != null) existingId = byUid['id']?.toString();
        } catch (_) {}

        if (existingId == null) {
          final userEmail = perfil['email']?.toString() ?? '';
          if (userEmail.isNotEmpty) {
            try {
              final byEmail = await _supabase
                  .from('drivers')
                  .select('id')
                  .eq('email', userEmail)
                  .maybeSingle();
              if (byEmail != null) existingId = byEmail['id']?.toString();
            } catch (_) {}
          }
        }

        if (existingId != null) {
          driverId = existingId;
        } else {
          // Criar apenas se realmente não existe
          final driverInsert = <String, dynamic>{'name': userName};
          if (empresaId != null) driverInsert['empresa_id'] = empresaId;
          final novoDriver = await _supabase
              .from('drivers')
              .insert(driverInsert)
              .select('id')
              .single();
          driverId = novoDriver['id'].toString();
        }

        // Sincronizar user_profiles.driver_id e drivers.user_id
        await _supabase
            .from('user_profiles')
            .update({'driver_id': driverId})
            .eq('user_id', userId);
        try {
          await _supabase
              .from('drivers')
              .update({'user_id': userId})
              .eq('id', driverId);
        } catch (_) {}
      }

      // Remover este driver de qualquer outro veículo antes de vincular
      await _supabase
          .from('vehicles')
          .update({'driver_id': null})
          .eq('driver_id', driverId);

      // Vincular o veículo ao driver
      await _supabase
          .from('vehicles')
          .update({'driver_id': driverId})
          .eq('id', vehicleId);

      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veículo vinculado com sucesso!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao vincular veículo: $e'),
            backgroundColor: AppColors.danger,
          ),
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
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: AppColors.danger,
          ),
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

  Future<void> _editarNome(String userId, String nomeAtual) async {
    final ctrl = TextEditingController(text: nomeAtual);
    setState(() => _isEditing = true);
    final salvo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar nome', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Nome completo',
            labelStyle: TextStyle(color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.secondary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    setState(() => _isEditing = false);
    if (salvo == null || salvo.isEmpty) return;
    try {
      await _supabase.from('user_profiles').update({'nome': salvo}).eq('user_id', userId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }


  Future<void> _vincularPorEmail(AppAuthProvider auth) async {
    final emailCtrl = TextEditingController();
    setState(() => _isEditing = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Map<String, dynamic>? encontrado;
        String? selectedVehicleId;
        String? erroBusca;
        bool buscou = false;

        return StatefulBuilder(
          builder: (ctx, setDialog) {
            Future<void> buscar() async {
              final email = emailCtrl.text.trim().toLowerCase();
              if (email.isEmpty) return;

              // Busca primeiro na lista já carregada
              final localIdx = _usuarios.indexWhere(
                (u) => (u['email']?.toString().toLowerCase() ?? '') == email,
              );
              Map<String, dynamic>? perfil = localIdx >= 0 ? _usuarios[localIdx] : null;

              // Se não achou localmente, consulta o banco
              if (perfil == null) {
                try {
                  final res = await _supabase
                      .from('user_profiles')
                      .select('*, empresas(nome)')
                      .eq('email', email)
                      .maybeSingle();
                  if (res != null) perfil = Map<String, dynamic>.from(res as Map);
                } catch (_) {}
              }

              // Descobre veículo atual do motorista (se houver driver_id)
              String? veiculoAtual;
              if (perfil?['driver_id'] != null) {
                final dId = perfil!['driver_id'].toString();
                final vIdx = _vehicles.indexWhere((v) => v['driver_id']?.toString() == dId);
                if (vIdx >= 0) veiculoAtual = _vehicles[vIdx]['id']?.toString();
              }

              setDialog(() {
                encontrado = perfil;
                selectedVehicleId = veiculoAtual;
                erroBusca = perfil == null ? 'Nenhum usuário encontrado com esse e-mail.' : null;
                buscou = true;
              });
            }

            final roleEncontrado = encontrado != null
                ? AppRole.fromString(encontrado!['role']?.toString() ?? 'MOTORISTA')
                : null;

            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('Vincular veículo por e-mail',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Digite o e-mail da conta do motorista para vincular um veículo.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: emailCtrl,
                            autofocus: true,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'motorista@email.com',
                              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
                              labelText: 'E-mail do motorista',
                              labelStyle: const TextStyle(color: AppColors.textSecondary),
                              prefixIcon: const Icon(Icons.email_outlined,
                                  color: AppColors.secondary, size: 18),
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.secondary, width: 2),
                              ),
                            ),
                            onSubmitted: (_) => buscar(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: buscar,
                          child: const Icon(Icons.search, size: 20, color: Colors.white),
                        ),
                      ],
                    ),
                    if (buscou && erroBusca != null) ...[
                      const SizedBox(height: 12),
                      Text(erroBusca!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    ],
                    if (encontrado != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: roleEncontrado!.color.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _initials(encontrado!['nome']?.toString() ??
                                    encontrado!['email']?.toString() ?? '?'),
                                style: TextStyle(
                                    color: roleEncontrado.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    encontrado!['nome']?.toString().isNotEmpty == true
                                        ? encontrado!['nome'].toString()
                                        : encontrado!['email']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                  ),
                                  Text(roleEncontrado.label,
                                      style: TextStyle(
                                          color: roleEncontrado.color, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (roleEncontrado != AppRole.motorista) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Este usuário não é motorista. Apenas motoristas podem ser vinculados a veículos.',
                          style: TextStyle(color: AppColors.warning, fontSize: 12),
                        ),
                      ] else if (_vehicles.isEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Nenhum veículo cadastrado para esta empresa.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        const Text('Selecionar veículo:',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String?>(
                          value: selectedVehicleId,
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.secondary)),
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('— Nenhum veículo —',
                                  style: TextStyle(color: AppColors.textSecondary)),
                            ),
                            ..._vehicles.map((v) => DropdownMenuItem<String?>(
                                  value: v['id']?.toString(),
                                  child: Text(
                                    '${v['plate']}  ${v['brand'] ?? ''} ${v['model'] ?? ''}',
                                    style: const TextStyle(color: AppColors.textPrimary),
                                  ),
                                )),
                          ],
                          onChanged: (v) => setDialog(() => selectedVehicleId = v),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                if (encontrado != null && roleEncontrado == AppRole.motorista)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _vincularVeiculoDireto(
                        encontrado!['user_id'].toString(),
                        selectedVehicleId,
                        encontrado!,
                      );
                    },
                    child: Text(
                      selectedVehicleId == null ? 'Desvincular veículo' : 'Vincular',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
    emailCtrl.dispose();
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final canManage = auth.can(AppPermission.manageUsers);
    final canVincular = auth.isMaster ||
        auth.hasAnyRole([AppRole.adminEmpresa, AppRole.gestor]);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestão de Usuários'),
        backgroundColor: AppColors.surface,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (canVincular)
            IconButton(
              icon: const Icon(Icons.link, color: AppColors.secondary),
              tooltip: 'Vincular motorista por e-mail',
              onPressed: () => _vincularPorEmail(auth),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            )
          : _erro != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_erro!, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _carregar,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            )
          : _buildLista(auth, canManage),
    );
  }

  Widget _buildLista(AppAuthProvider auth, bool canManage) {
    // Separa pendentes (sem empresa) dos demais — visível apenas ao MASTER
    final pendentes = auth.isMaster
        ? _usuarios.where((u) => u['empresa_id'] == null).toList()
        : <Map<String, dynamic>>[];
    final ativos = auth.isMaster
        ? _usuarios.where((u) => u['empresa_id'] != null).toList()
        : _usuarios;

    // Aplica filtro de busca por nome ou e-mail
    List<Map<String, dynamic>> filtrar(List<Map<String, dynamic>> lista) {
      if (_searchQuery.trim().isEmpty) return lista;
      final q = _searchQuery.toLowerCase().trim();
      return lista.where((u) {
        final nome = (u['nome']?.toString() ?? '').toLowerCase();
        final email = (u['email']?.toString() ?? '').toLowerCase();
        return nome.contains(q) || email.contains(q);
      }).toList();
    }

    final pendentesFiltrados = filtrar(pendentes);
    final ativosFiltrados = filtrar(ativos);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou e-mail...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.secondary),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Expanded(
          child: (pendentesFiltrados.isEmpty && ativosFiltrados.isEmpty)
              ? Center(
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'Nenhum usuário encontrado para "$_searchQuery".'
                        : 'Nenhum usuário encontrado.',
                    style: const TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (pendentesFiltrados.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withOpacity(0.30)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.pending_actions, color: AppColors.warning, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Aguardando atribuição de empresa (${pendentesFiltrados.length})',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...pendentesFiltrados.map((u) => _buildCard(u, auth, canManage, _drivers, _vehicles)),
                      const Divider(color: AppColors.border, height: 24),
                    ],
                    ...ativosFiltrados.map((u) => _buildCard(u, auth, canManage, _drivers, _vehicles)),
                    // BUG-19: note when limit reached
                    if (_usuarios.length >= 200)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Exibindo primeiros 200 usuários.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCard(
    Map<String, dynamic> u,
    AppAuthProvider auth,
    bool canManage,
    List<Map<String, dynamic>> drivers,
    List<Map<String, dynamic>> vehicles,
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
                          if (canEdit) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _editarNome(userId, u['nome']?.toString() ?? ''),
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.edit_rounded,
                                    size: 14, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                      items: const [
                        'ativo',
                        'pendente',
                        'bloqueado',
                        'inativo',
                      ],
                      itemLabel: (s) => s,
                      onChanged: (s) => _alterarStatus(userId, s),
                    ),
                  ),
                  // Empresa dropdown — apenas para motorista/gestor (admin_empresa cria a própria)
                  if (auth.isMaster &&
                      _empresas.isNotEmpty &&
                      role != AppRole.adminEmpresa) ...[
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
              // Vinculação direta de veículo (para role MOTORISTA com empresa atribuída)
              if (role == AppRole.motorista && u['empresa_id'] != null) ...[
                const SizedBox(height: 8),
                _VehicleDirectDropdown(
                  vehicles: vehicles,
                  currentDriverId: u['driver_id']?.toString(),
                  onChanged: (vId) => _vincularVeiculoDireto(userId, vId, u),
                ),
              ],
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
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
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
          hint: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          dropdownColor: const Color(0xFF0B1528),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          icon: const Icon(
            Icons.unfold_more_rounded,
            color: AppColors.textSecondary,
            size: 14,
          ),
          items: items
              .map(
                (t) => DropdownMenuItem<T>(value: t, child: Text(itemLabel(t))),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
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
          hint: const Text(
            'Empresa',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          dropdownColor: const Color(0xFF0B1528),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          icon: const Icon(
            Icons.unfold_more_rounded,
            color: AppColors.textSecondary,
            size: 14,
          ),
          items: empresas
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e['id']?.toString(),
                  child: Text(
                    e['nome']?.toString() ?? '—',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _VehicleDirectDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> vehicles;
  final String? currentDriverId;
  final void Function(String?) onChanged;

  const _VehicleDirectDropdown({
    required this.vehicles,
    required this.currentDriverId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Veículo atualmente atribuído a este motorista
    String? currentVehicleId;
    for (final v in vehicles) {
      if (v['driver_id']?.toString() == currentDriverId) {
        currentVehicleId = v['id']?.toString();
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: currentVehicleId != null
              ? const Color(0xFF3B82F6).withOpacity(0.45)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_rounded, color: Color(0xFF3B82F6), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: currentVehicleId,
                isExpanded: true,
                hint: const Text(
                  'Vincular veículo ao motorista',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                dropdownColor: const Color(0xFF0B1528),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                icon: const Icon(Icons.unfold_more_rounded,
                    color: AppColors.textSecondary, size: 14),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— Nenhum veículo —',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  ...vehicles.map(
                    (v) => DropdownMenuItem<String?>(
                      value: v['id']?.toString(),
                      child: Text(
                        '${v['plate'] ?? '—'}  ${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

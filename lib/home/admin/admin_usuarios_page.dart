import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/config/supabase_config.dart';
import '../../core/enums/app_permission.dart';
import '../../core/enums/app_role.dart';
import '../../core/guards/permission_guard.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/driver_account_link.dart';
import '../../core/widgets/signed_network_image.dart';

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

enum _Aba { gestores, motoristas }

class _AdminUsuariosView extends StatefulWidget {
  const _AdminUsuariosView();

  @override
  State<_AdminUsuariosView> createState() => _AdminUsuariosViewState();
}

class _AdminUsuariosViewState extends State<_AdminUsuariosView> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = true;
  String? _erro;
  bool _isEditing = false; // BUG-17: suppresses realtime rebuild during active edits
  RealtimeChannel? _channel;
  Timer? _realtimeDebounce;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String? _empresaSelecionadaId;
  _Aba _aba = _Aba.motoristas;

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
          callback: (_) { if (!_isEditing) _debouncedCarregar(); },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'empresas',
          callback: (_) { if (!_isEditing) _debouncedCarregar(); },
        )
        .subscribe();
  }

  // Coalesce bursts of changes (ex.: last_access sendo tocado por vários usuários
  // ao mesmo tempo) em um único recarregamento, em vez de um por evento.
  void _debouncedCarregar() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isEditing) _carregar();
    });
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
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
            .limit(400);
      } else {
        final minhaEmpresa = auth.empresaId;
        if (minhaEmpresa != null) {
          res = await _supabase
              .from('user_profiles')
              .select('*, empresas(nome)')
              .eq('empresa_id', minhaEmpresa)
              .order('created_at', ascending: false)
              .limit(400);
        } else {
          res = await _supabase
              .from('user_profiles')
              .select('*, empresas(nome)')
              .order('created_at', ascending: false)
              .limit(400);
        }
      }
      final lista = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Empresas — MASTER vê todas, demais só a própria (para o cabeçalho/sidebar)
      List<Map<String, dynamic>> empresas = [];
      try {
        var empQuery = _supabase.from('empresas').select('id, nome, status');
        if (!auth.isMaster) {
          final minhaEmpresa = auth.empresaId;
          if (minhaEmpresa != null) empQuery = empQuery.eq('id', minhaEmpresa);
        }
        final empRes = await empQuery.order('nome');
        empresas = (empRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}

      List<Map<String, dynamic>> vehicles = [];
      try {
        var vQuery = _supabase
            .from('vehicles')
            .select('id, plate, model, brand, driver_id, empresa_id');
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
        _vehicles = vehicles;
        _loading = false;

        // Seleciona automaticamente uma empresa se ainda não houver seleção
        // válida (primeira carga, ou empresa selecionada deixou de existir).
        // "__pendentes__" é uma seleção especial (não uma empresa real) e não
        // deve ser resetada a cada recarregamento.
        final aindaExiste = _empresaSelecionadaId == '__pendentes__' ||
            (_empresaSelecionadaId != null &&
                empresas.any((e) => e['id']?.toString() == _empresaSelecionadaId));
        if (!aindaExiste) {
          if (!auth.isMaster) {
            _empresaSelecionadaId = auth.empresaId;
          } else if (empresas.isNotEmpty) {
            _empresaSelecionadaId = empresas.first['id']?.toString();
          } else {
            _empresaSelecionadaId = null;
          }
        }
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
      if (mounted) showError(context, friendlyError(e));
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
        showSuccess(context, 'Empresa "$nomeEmpresa" criada e admin vinculado!');
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
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
        await linkUserToDriver(_supabase, userId: userId, driverId: driverId);
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
      if (mounted) showSuccess(context, 'Veículo vinculado com sucesso!');
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
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
      if (mounted) showError(context, friendlyError(e));
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
      if (mounted) showError(context, friendlyError(e));
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
      if (mounted) showError(context, friendlyError(e));
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
                            _avatar(encontrado!, size: 36),
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
                                  Text(roleEncontrado!.label,
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

  // ── Criação de novo usuário (Gestor ou Motorista) ─────────────────────────
  // Mesmo padrão já usado em master_dashboard_page.dart: cria a conta com uma
  // senha aleatória descartada e envia convite por e-mail (resetPasswordForEmail)
  // — quem administra nunca sabe/define a senha do novo usuário.
  Future<void> _showNovoUsuarioDialog(
    AppAuthProvider auth, {
    AppRole papelInicial = AppRole.motorista,
  }) async {
    final nomeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final telefoneCtrl = TextEditingController();
    AppRole papel = papelInicial;
    String? empresaId = auth.isMaster ? _empresaSelecionadaId : auth.effectiveEmpresaId;
    bool criarConta = true;
    bool saving = false;
    String? error;
    String? successMsg;

    setState(() => _isEditing = true);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text(
            papel == AppRole.motorista ? 'Novo Motorista' : 'Novo Usuário',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.report_problem_rounded, color: AppColors.danger, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (successMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(successMsg!, style: const TextStyle(color: AppColors.success, fontSize: 12))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _dialogField('Nome completo *', nomeCtrl),
                  const SizedBox(height: 12),
                  _dialogField('E-mail *', emailCtrl, hint: 'usuario@email.com'),
                  const SizedBox(height: 12),
                  _dialogField('Telefone', telefoneCtrl, hint: '(11) 99999-9999'),
                  const SizedBox(height: 12),
                  const Text('Papel', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AppRole>(
                        value: papel,
                        isExpanded: true,
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: [AppRole.motorista, AppRole.gestor]
                            .map((r) => DropdownMenuItem(value: r, child: Text(r.displayName)))
                            .toList(),
                        onChanged: (r) => setS(() => papel = r ?? papel),
                      ),
                    ),
                  ),
                  if (auth.isMaster) ...[
                    const SizedBox(height: 12),
                    const Text('Empresa', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _empresas.any((e) => e['id']?.toString() == empresaId) ? empresaId : null,
                          isExpanded: true,
                          hint: const Text('Selecionar empresa', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: _empresas
                              .map((e) => DropdownMenuItem(
                                    value: e['id']?.toString(),
                                    child: Text(e['nome']?.toString() ?? '—', overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setS(() => empresaId = v),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: CheckboxListTile(
                      value: criarConta,
                      onChanged: (v) => setS(() => criarConta = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.secondary,
                      title: const Text('Criar conta de acesso',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: const Text(
                        'Envia um e-mail para a pessoa definir a própria senha.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final nome = nomeCtrl.text.trim();
                      final email = emailCtrl.text.trim().toLowerCase();

                      if (nome.isEmpty) { setS(() => error = 'Nome é obrigatório'); return; }
                      if (email.isEmpty) { setS(() => error = 'E-mail é obrigatório'); return; }
                      if (auth.isMaster && empresaId == null) { setS(() => error = 'Selecione uma empresa'); return; }

                      setS(() { saving = true; error = null; });

                      try {
                        String? userId;

                        if (criarConta) {
                          final url = await SupabaseConfig.getUrl();
                          final key = await SupabaseConfig.getPublishableKey();
                          final tmpClient = SupabaseClient(url, key);
                          try {
                            final tempPassword = '${DateTime.now().microsecondsSinceEpoch}${UniqueKey().hashCode}Aa1!';
                            final signUpRes = await tmpClient.auth.signUp(email: email, password: tempPassword);
                            userId = signUpRes.user?.id;
                            if (userId == null) {
                              await tmpClient.dispose();
                              setS(() { saving = false; error = 'Falha ao criar conta. Verifique se o e-mail já está cadastrado.'; });
                              return;
                            }
                            try {
                              await tmpClient.auth.resetPasswordForEmail(email);
                            } catch (_) {}
                          } finally {
                            await tmpClient.dispose();
                          }

                          await _supabase.from('user_profiles').upsert({
                            'user_id': userId,
                            'email': email,
                            'nome': nome,
                            'role': papel.label,
                            'empresa_id': empresaId,
                            'status': 'ativo',
                          }, onConflict: 'user_id');
                        } else {
                          final existing = await _supabase
                              .from('user_profiles')
                              .select('user_id')
                              .eq('email', email)
                              .maybeSingle();
                          if (existing == null) {
                            setS(() { saving = false; error = 'Conta não encontrada para esse e-mail.'; });
                            return;
                          }
                          userId = existing['user_id']?.toString();
                          await _supabase.from('user_profiles').update({
                            'role': papel.label,
                            'empresa_id': empresaId,
                            'nome': nome,
                          }).eq('user_id', userId!);
                        }

                        if (papel == AppRole.motorista) {
                          final driverPayload = <String, dynamic>{
                            'name': nome,
                            'email': email,
                            if (telefoneCtrl.text.trim().isNotEmpty) 'phone': telefoneCtrl.text.trim(),
                          };
                          if (empresaId != null) driverPayload['empresa_id'] = empresaId;
                          driverPayload['user_id'] = userId;
                          final driverRes = await _supabase.from('drivers').insert(driverPayload).select('id').single();
                          final driverId = driverRes['id']?.toString();
                          if (driverId != null) {
                            await linkUserToDriver(_supabase, userId: userId, driverId: driverId);
                          }
                        }

                        final msg = criarConta
                            ? '$nome cadastrado! Convite enviado para $email.'
                            : '$nome vinculado com sucesso!';

                        if (ctx.mounted) {
                          setS(() { saving = false; successMsg = msg; });
                          await Future.delayed(const Duration(seconds: 2));
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                        _carregar();
                      } catch (e) {
                        setS(() { saving = false; error = friendlyError(e); });
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(papel == AppRole.motorista ? 'Cadastrar Motorista' : 'Cadastrar Usuário'),
            ),
          ],
        ),
      ),
    );
    nomeCtrl.dispose();
    emailCtrl.dispose();
    telefoneCtrl.dispose();
    setState(() => _isEditing = false);
  }

  Widget _dialogField(String label, TextEditingController ctrl, {String? hint}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.secondary)),
      ),
    );
  }

  // ── Agrupamento / lookups ──────────────────────────────────────────────────

  Map<String, List<Map<String, dynamic>>> _agruparPorEmpresa() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final u in _usuarios) {
      final eid = u['empresa_id']?.toString();
      if (eid == null) continue;
      map.putIfAbsent(eid, () => []).add(u);
    }
    return map;
  }

  Map<String, dynamic>? _veiculoDoMotorista(Map<String, dynamic> u) {
    final driverId = u['driver_id']?.toString();
    if (driverId == null) return null;
    for (final v in _vehicles) {
      if (v['driver_id']?.toString() == driverId) return v;
    }
    return null;
  }

  DateTime? _ultimoAcesso(List<Map<String, dynamic>> usuarios) {
    DateTime? maisRecente;
    for (final u in usuarios) {
      final raw = u['last_access']?.toString();
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) continue;
      if (maisRecente == null || dt.isAfter(maisRecente)) maisRecente = dt;
    }
    return maisRecente;
  }

  List<AppRole> _rolesDisponiveis(AppAuthProvider auth) {
    if (auth.isMaster) return AppRole.values;
    return [AppRole.adminEmpresa, AppRole.gestor, AppRole.motorista];
  }

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _fmtAcesso(DateTime? dt) {
    if (dt == null) return 'Nunca acessou';
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    final data = DateTime(dt.year, dt.month, dt.day);
    final hhmm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (data == hoje) return 'Hoje $hhmm';
    if (data == hoje.subtract(const Duration(days: 1))) return 'Ontem $hhmm';
    return '${_fmtDate(dt)} $hhmm';
  }

  Widget _avatar(Map<String, dynamic> u, {double size = 40}) {
    final url = u['avatar_url']?.toString();
    final nome = u['nome']?.toString().isNotEmpty == true
        ? u['nome'].toString()
        : (u['email']?.toString() ?? '?');
    final role = AppRole.fromString(u['role']?.toString() ?? 'MOTORISTA');
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: SignedNetworkImage(
          url: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _avatarInitials(nome, role, size),
        ),
      );
    }
    return _avatarInitials(nome, role, size);
  }

  Widget _avatarInitials(String nome, AppRole role, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: role.color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: role.color.withOpacity(0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(nome),
        style: TextStyle(color: role.color, fontWeight: FontWeight.w700, fontSize: size * 0.32),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final canManage = auth.can(AppPermission.manageUsers);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      return Column(
                        children: [
                          _buildTopBar(auth, canManage, wide),
                          Expanded(
                            child: wide
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(width: 300, child: _buildSidebar(auth)),
                                      const VerticalDivider(width: 1, color: AppColors.border),
                                      Expanded(child: _buildMainContent(auth, canManage, wide: true)),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _buildSeletorEmpresaMobile(auth),
                                      Expanded(child: _buildMainContent(auth, canManage, wide: false)),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildTopBar(AppAuthProvider auth, bool canManage, bool wide) {
    final canVincular = auth.isMaster || auth.hasAnyRole([AppRole.adminEmpresa, AppRole.gestor]);
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.people_alt_rounded, color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          if (wide)
            const Padding(
              padding: EdgeInsets.only(right: 24),
              child: Text(
                'Gestão de Usuários',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            )
          else
            const Expanded(
              child: Text(
                'Gestão de Usuários',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          if (wide)
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Buscar usuário, empresa ou veículo...',
                          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 12),
          if (canManage)
            ElevatedButton.icon(
              onPressed: () => _showNovoUsuarioDialog(auth, papelInicial: AppRole.motorista),
              icon: const Icon(Icons.add, size: 18),
              label: Text(wide ? 'Novo Usuário' : 'Novo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          if (canVincular) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.link, color: AppColors.secondary),
              tooltip: 'Vincular motorista por e-mail',
              onPressed: () => _vincularPorEmail(auth),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
        ],
      ),
    );
  }

  Widget _buildSeletorEmpresaMobile(AppAuthProvider auth) {
    if (!auth.isMaster) return const SizedBox.shrink();
    final grupos = _agruparPorEmpresa();
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: _empresas.map((e) {
          final id = e['id']?.toString();
          final selecionada = id == _empresaSelecionadaId;
          final qtd = grupos[id]?.length ?? 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${e['nome']} ($qtd)'),
              selected: selecionada,
              onSelected: (_) => setState(() => _empresaSelecionadaId = id),
              selectedColor: AppColors.secondary.withOpacity(0.25),
              backgroundColor: AppColors.background,
              labelStyle: TextStyle(
                color: selecionada ? AppColors.secondary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(color: selecionada ? AppColors.secondary : AppColors.border),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSidebar(AppAuthProvider auth) {
    final grupos = _agruparPorEmpresa();
    final pendentesReais = auth.isMaster ? _usuarios.where((u) => u['empresa_id'] == null).toList() : <Map<String, dynamic>>[];

    final query = _searchQuery.trim().toLowerCase();
    final empresasFiltradas = query.isEmpty
        ? _empresas
        : _empresas.where((e) => (e['nome']?.toString() ?? '').toLowerCase().contains(query)).toList();

    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Empresas',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Text('${empresasFiltradas.length}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (auth.isMaster && pendentesReais.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _empresaSelecionadaId = '__pendentes__'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _empresaSelecionadaId == '__pendentes__'
                          ? AppColors.warning
                          : AppColors.warning.withOpacity(0.35),
                      width: _empresaSelecionadaId == '__pendentes__' ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions, color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Pendentes',
                            style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text('${pendentesReais.length}',
                          style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: empresasFiltradas.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma empresa encontrada.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: empresasFiltradas.length,
                    itemBuilder: (context, index) {
                      final empresa = empresasFiltradas[index];
                      final id = empresa['id']?.toString();
                      final nome = empresa['nome']?.toString() ?? '—';
                      final usuariosDaEmpresa = grupos[id] ?? [];
                      final gestores = usuariosDaEmpresa.where((u) => AppRole.fromString(u['role']?.toString()) != AppRole.motorista).length;
                      final motoristas = usuariosDaEmpresa.where((u) => AppRole.fromString(u['role']?.toString()) == AppRole.motorista).length;
                      final selecionada = id == _empresaSelecionadaId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _empresaSelecionadaId = id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: selecionada ? AppColors.secondary.withOpacity(0.14) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selecionada ? AppColors.secondary.withOpacity(0.5) : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: (selecionada ? AppColors.secondary : AppColors.primary).withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _initials(nome),
                                    style: TextStyle(
                                      color: selecionada ? AppColors.secondary : AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nome,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selecionada ? Colors.white : AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Gestores: $gestores | Motoristas: $motoristas',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(AppAuthProvider auth, bool canManage, {required bool wide}) {
    if (_empresaSelecionadaId == '__pendentes__') {
      return _buildPendentesView(auth, canManage, wide);
    }

    final empresa = _empresas.firstWhere(
      (e) => e['id']?.toString() == _empresaSelecionadaId,
      orElse: () => <String, dynamic>{},
    );
    if (empresa.isEmpty) {
      return const Center(
        child: Text('Selecione uma empresa.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final usuariosDaEmpresa = _usuarios.where((u) => u['empresa_id']?.toString() == _empresaSelecionadaId).toList();
    final gestores = usuariosDaEmpresa.where((u) => AppRole.fromString(u['role']?.toString()) != AppRole.motorista).toList();
    final motoristas = usuariosDaEmpresa.where((u) => AppRole.fromString(u['role']?.toString()) == AppRole.motorista).toList();
    final veiculos = _vehicles.where((v) => v['empresa_id']?.toString() == _empresaSelecionadaId).toList();
    final ultimoAcesso = _ultimoAcesso(usuariosDaEmpresa);
    final status = (empresa['status']?.toString() ?? 'ativo');
    final ativa = status == 'ativo';

    final query = _searchQuery.trim().toLowerCase();
    List<Map<String, dynamic>> filtrar(List<Map<String, dynamic>> lista) {
      if (query.isEmpty) return lista;
      return lista.where((u) {
        final nome = (u['nome']?.toString() ?? '').toLowerCase();
        final email = (u['email']?.toString() ?? '').toLowerCase();
        final veiculo = _veiculoDoMotorista(u);
        final placa = (veiculo?['plate']?.toString() ?? '').toLowerCase();
        return nome.contains(query) || email.contains(query) || placa.contains(query);
      }).toList();
    }

    final gestoresF = filtrar(gestores);
    final motoristasF = filtrar(motoristas);

    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(empresa['nome']?.toString() ?? '—'),
                  style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  (empresa['nome']?.toString() ?? '—').toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (ativa ? AppColors.success : AppColors.danger).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: (ativa ? AppColors.success : AppColors.danger).withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: ativa ? AppColors.success : AppColors.danger),
                    const SizedBox(width: 6),
                    Text(
                      ativa ? 'Ativa' : status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(
                        color: ativa ? AppColors.success : AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final cols = wide ? 4 : 2;
            final cards = [
              _statCard('Gestores', '${gestores.length}', Icons.shield_outlined, AppColors.info),
              _statCard('Motoristas', '${motoristas.length}', Icons.groups_rounded, AppColors.secondary),
              _statCard('Veículos', '${veiculos.length}', Icons.directions_car_rounded, AppColors.warning),
              _statCard('Último acesso', _fmtAcesso(ultimoAcesso), Icons.schedule_rounded, AppColors.success, small: true),
            ];
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: wide ? 2.1 : 1.7,
              children: cards,
            );
          }),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _tabButton('Gestores', _Aba.gestores, gestores.length),
                    const SizedBox(width: 8),
                    _tabButton('Motoristas', _Aba.motoristas, motoristas.length),
                  ],
                ),
              ),
              if (canManage)
                OutlinedButton.icon(
                  onPressed: () => _showNovoUsuarioDialog(
                    auth,
                    papelInicial: _aba == _Aba.gestores ? AppRole.gestor : AppRole.motorista,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(_aba == _Aba.gestores ? 'Novo Gestor' : 'Novo Motorista'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTabela(
            _aba == _Aba.gestores ? gestoresF : motoristasF,
            auth,
            canManage,
            mostraVeiculo: _aba == _Aba.motoristas,
            wide: wide,
          ),
        ],
      ),
    );
  }

  Widget _buildPendentesView(AppAuthProvider auth, bool canManage, bool wide) {
    final pendentes = _usuarios.where((u) => u['empresa_id'] == null).toList();
    final query = _searchQuery.trim().toLowerCase();
    final filtrados = query.isEmpty
        ? pendentes
        : pendentes.where((u) {
            final nome = (u['nome']?.toString() ?? '').toLowerCase();
            final email = (u['email']?.toString() ?? '').toLowerCase();
            return nome.contains(query) || email.contains(query);
          }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const Icon(Icons.pending_actions, color: AppColors.warning),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('AGUARDANDO ATRIBUIÇÃO DE EMPRESA',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTabela(filtrados, auth, canManage, mostraVeiculo: false, wide: wide),
        ],
      ),
    );
  }

  Widget _tabButton(String label, _Aba aba, int count) {
    final selecionada = _aba == aba;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _aba = aba),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selecionada ? AppColors.secondary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selecionada ? AppColors.secondary : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selecionada ? AppColors.secondary : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: (selecionada ? AppColors.secondary : AppColors.textSecondary).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selecionada ? AppColors.secondary : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, {bool small = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(color: Colors.white, fontSize: small ? 14 : 20, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTabela(
    List<Map<String, dynamic>> usuarios,
    AppAuthProvider auth,
    bool canManage, {
    required bool mostraVeiculo,
    required bool wide,
  }) {
    if (usuarios.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          _searchQuery.isNotEmpty ? 'Nenhum usuário encontrado para "$_searchQuery".' : 'Nenhum usuário nesta lista.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (!wide) {
      return Column(
        children: usuarios.map((u) => _buildCardMobile(u, auth, canManage, mostraVeiculo)).toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _tabelaHeader(mostraVeiculo),
          ...usuarios.asMap().entries.map((entry) {
            final isLast = entry.key == usuarios.length - 1;
            return _tabelaLinha(entry.value, auth, canManage, mostraVeiculo, isLast);
          }),
        ],
      ),
    );
  }

  Widget _tabelaHeader(bool mostraVeiculo) {
    TextStyle style = const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('USUÁRIO', style: style)),
          Expanded(flex: 2, child: Text('FUNÇÃO', style: style)),
          if (mostraVeiculo) ...[
            Expanded(flex: 2, child: Text('VEÍCULO', style: style)),
            Expanded(flex: 1, child: Text('PLACA', style: style)),
          ],
          Expanded(flex: 2, child: Text('ACESSO', style: style)),
          Expanded(flex: 1, child: Text('STATUS', style: style)),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _tabelaLinha(
    Map<String, dynamic> u,
    AppAuthProvider auth,
    bool canManage,
    bool mostraVeiculo,
    bool isLast,
  ) {
    final userId = u['user_id']?.toString() ?? '';
    final nome = u['nome']?.toString().isNotEmpty == true ? u['nome'].toString() : (u['email']?.toString() ?? 'Sem nome');
    final email = u['email']?.toString() ?? '';
    final role = AppRole.fromString(u['role']?.toString() ?? 'MOTORISTA');
    final status = u['status']?.toString() ?? 'ativo';
    final lastAccess = u['last_access'] != null ? DateTime.tryParse(u['last_access'].toString())?.toLocal() : null;
    final veiculo = mostraVeiculo ? _veiculoDoMotorista(u) : null;
    final isMe = userId == auth.profile?.userId;
    final isMasterUser = role == AppRole.master;
    final canEdit = canManage && !isMe && !(isMasterUser && !auth.isMaster);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _avatar(u, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Você',
                                  style: TextStyle(color: AppColors.secondary, fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      if (email.isNotEmpty)
                        Text(email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: role.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: role.color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(role.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: role.color, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          if (mostraVeiculo) ...[
            Expanded(
              flex: 2,
              child: Text(
                veiculo != null ? '${veiculo['brand'] ?? ''} ${veiculo['model'] ?? ''}'.trim() : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                veiculo?['plate']?.toString() ?? '—',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ],
          Expanded(
            flex: 2,
            child: Text(
              _fmtAcesso(lastAccess),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 1,
            child: _statusPill(status),
          ),
          SizedBox(
            width: 44,
            child: canEdit
                ? IconButton(
                    icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 18),
                    onPressed: () => _abrirGerenciarUsuario(u, auth),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMobile(Map<String, dynamic> u, AppAuthProvider auth, bool canManage, bool mostraVeiculo) {
    final userId = u['user_id']?.toString() ?? '';
    final nome = u['nome']?.toString().isNotEmpty == true ? u['nome'].toString() : (u['email']?.toString() ?? 'Sem nome');
    final email = u['email']?.toString() ?? '';
    final role = AppRole.fromString(u['role']?.toString() ?? 'MOTORISTA');
    final status = u['status']?.toString() ?? 'ativo';
    final lastAccess = u['last_access'] != null ? DateTime.tryParse(u['last_access'].toString())?.toLocal() : null;
    final veiculo = mostraVeiculo ? _veiculoDoMotorista(u) : null;
    final isMe = userId == auth.profile?.userId;
    final isMasterUser = role == AppRole.master;
    final canEdit = canManage && !isMe && !(isMasterUser && !auth.isMaster);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(u, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    if (email.isNotEmpty)
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              _statusPill(status),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 18),
                  onPressed: () => _abrirGerenciarUsuario(u, auth),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(role.displayName, role.color),
              if (veiculo != null) _chip('${veiculo['plate']} · ${veiculo['brand'] ?? ''} ${veiculo['model'] ?? ''}'.trim(), AppColors.primary),
              _chip(_fmtAcesso(lastAccess), AppColors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _statusPill(String status) {
    Color cor;
    switch (status) {
      case 'ativo': cor = AppColors.success; break;
      case 'bloqueado': cor = AppColors.danger; break;
      case 'pendente': cor = AppColors.warning; break;
      default: cor = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(status, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Modal "Gerenciar usuário" — reaproveita os mesmos controles/ações já existentes ──
  void _abrirGerenciarUsuario(Map<String, dynamic> u, AppAuthProvider auth) {
    final userId = u['user_id']?.toString() ?? '';
    final role = AppRole.fromString(u['role']?.toString() ?? 'MOTORISTA');
    final status = u['status']?.toString() ?? 'ativo';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _avatar(u, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u['nome']?.toString().isNotEmpty == true ? u['nome'].toString() : (u['email']?.toString() ?? ''),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(u['email']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 18),
                    tooltip: 'Editar nome',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editarNome(userId, u['nome']?.toString() ?? '');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ActionDropdown<AppRole>(
                      label: 'Papel',
                      value: role,
                      items: _rolesDisponiveis(auth),
                      itemLabel: (r) => r.displayName,
                      onChanged: (r) {
                        Navigator.pop(ctx);
                        _alterarRole(userId, r);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionDropdown<String>(
                      label: 'Status',
                      value: status,
                      items: const ['ativo', 'pendente', 'bloqueado', 'inativo'],
                      itemLabel: (s) => s,
                      onChanged: (s) {
                        Navigator.pop(ctx);
                        _alterarStatus(userId, s);
                      },
                    ),
                  ),
                ],
              ),
              if (auth.isMaster && _empresas.isNotEmpty && role != AppRole.adminEmpresa) ...[
                const SizedBox(height: 10),
                _EmpresaDropdown(
                  empresas: _empresas,
                  currentId: u['empresa_id']?.toString(),
                  onChanged: (id) {
                    Navigator.pop(ctx);
                    _alterarEmpresa(userId, id);
                  },
                ),
              ],
              if (role == AppRole.motorista && u['empresa_id'] != null) ...[
                const SizedBox(height: 10),
                _VehicleDirectDropdown(
                  vehicles: _vehicles.where((v) => v['empresa_id']?.toString() == u['empresa_id']?.toString()).toList(),
                  currentDriverId: u['driver_id']?.toString(),
                  onChanged: (vId) {
                    Navigator.pop(ctx);
                    _vincularVeiculoDireto(userId, vId, u);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
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

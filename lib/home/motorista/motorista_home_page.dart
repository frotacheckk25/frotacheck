import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../abastecimentos/abastecimentos_page.dart';
import '../checklists/selecionar_veiculo_checklist.dart';
import '../checklists/historico_checklist_page.dart';
import '../documentos/documentos_page.dart';
import '../manutencoes/manutencoes_page.dart';
import '../multas/multas_page.dart';
import '../pneus/pneus_page.dart';
import '../viagens/viagens_page.dart';
import '../../pages/lista_ocorrencias_page.dart';

class MotoristaHomePage extends StatefulWidget {
  const MotoristaHomePage({super.key});

  @override
  State<MotoristaHomePage> createState() => _MotoristaHomePageState();
}

class _MotoristaHomePageState extends State<MotoristaHomePage> {
  final _supabase = Supabase.instance.client;

  _Sec _activeSection = _Sec.dashboard;
  _MobileTab _activeTab = _MobileTab.dashboard;

  bool _loadingVeiculo = true;
  Map<String, dynamic>? _veiculo;
  int _ocorrenciasAbertas = 0;
  List<Map<String, dynamic>> _alertas = [];
  Map<String, dynamic>? _ultimoAbastecimento;
  Map<String, dynamic>? _ultimaManutencao;

  // Tarefas de hoje
  bool _checklistSaidaHoje = false;
  bool _checklistRetornoHoje = false;
  int _abastecimentosHoje = 0;
  String _manutencaoStatus = 'Verificar';

  // Resumo do dia
  int _viagensHoje = 0;
  double _distanciaHoje = 0;
  int _tempoTransitoMin = 0;

  // Perfil — dados do driver record e avatar
  Map<String, dynamic>? _driverRecord;
  String? _avatarUrl;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loadingVeiculo = true);
    final auth = context.read<AppAuthProvider>();
    final empresaId = auth.empresaId;
    String? driverId = auth.profile?.driverId;
    final userId = _supabase.auth.currentUser?.id;

    try {
      if (userId != null) {
        final fresh = await _supabase
            .from('user_profiles')
            .select('driver_id')
            .eq('user_id', userId)
            .maybeSingle();
        if (fresh != null) driverId = fresh['driver_id']?.toString();
      }
    } catch (_) {}

    if (driverId == null && userId != null) {
      try {
        final driverRow = await _supabase
            .from('drivers')
            .select('id')
            .eq('user_id', userId)
            .maybeSingle();
        final fallbackId = driverRow?['id']?.toString();
        if (fallbackId != null) {
          driverId = fallbackId;
          await _supabase
              .from('user_profiles')
              .update({'driver_id': fallbackId})
              .eq('user_id', userId)
              .catchError((_) => null);
        }
      } catch (_) {}
    }

    try {
      final hoje = DateTime.now();
      final inicioHoje =
          DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();

      // ── Veículo ───────────────────────────────────────────────────────────
      Map<String, dynamic>? veiculo;
      try {
        final rpcResult = await _supabase.rpc('get_my_vehicle') as List?;
        if (rpcResult != null && rpcResult.isNotEmpty) {
          veiculo = Map<String, dynamic>.from(rpcResult.first as Map);
        }
      } catch (_) {}

      final vehicleId = veiculo?['id']?.toString();

      // Accumulators
      int ocorrenciasAbertas = 0;
      List<Map<String, dynamic>> alertas = [];
      Map<String, dynamic>? abastRes;
      Map<String, dynamic>? ultManut;
      bool checklistSaida = false;
      bool checklistRetorno = false;
      int abastecimentosHoje = 0;
      int viagensHoje = 0;
      double distanciaHoje = 0;
      int tempoTransitoMin = 0;
      String manutencaoStatus = 'Verificar';

      // ── Queries que precisam de driverId + empresaId ──────────────────────
      if (driverId != null && empresaId != null) {
        // Checklist saída hoje
        try {
          final res = await _supabase
              .from('checklists')
              .select('id')
              .eq('empresa_id', empresaId)
              .eq('motorista_id', driverId)
              .eq('tipo', 'saida')
              .gte('created_at', inicioHoje)
              .count();
          checklistSaida = res.count > 0;
        } catch (_) {}

        // Checklist retorno hoje
        try {
          final res = await _supabase
              .from('checklists')
              .select('id')
              .eq('empresa_id', empresaId)
              .eq('motorista_id', driverId)
              .eq('tipo', 'retorno')
              .gte('created_at', inicioHoje)
              .count();
          checklistRetorno = res.count > 0;
        } catch (_) {}

        // Ocorrências abertas
        try {
          final res = await _supabase
              .from('occurrences')
              .select('id')
              .eq('empresa_id', empresaId)
              .eq('driver_id', driverId)
              .eq('status', 'aberto')
              .count();
          ocorrenciasAbertas = res.count;
        } catch (_) {}

        // Último abastecimento (para atividade recente)
        try {
          abastRes = await _supabase
              .from('fuelings')
              .select('id, created_at, liters, total_value, vehicles(plate)')
              .eq('empresa_id', empresaId)
              .eq('driver_id', driverId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (_) {}

        // Abastecimentos hoje (contagem)
        try {
          final res = await _supabase
              .from('fuelings')
              .select('id')
              .eq('empresa_id', empresaId)
              .eq('driver_id', driverId)
              .gte('created_at', inicioHoje)
              .count();
          abastecimentosHoje = res.count;
        } catch (_) {}
      }

      // ── Viagens hoje (só precisa de driverId) ─────────────────────────────
      if (driverId != null) {
        try {
          final viaRes = await _supabase
              .from('viagens')
              .select('quilometragem_percorrida, duracao_minutos, status')
              .eq('motorista_id', driverId)
              .gte('data_inicio', inicioHoje)
              .neq('status', 'cancelada');
          for (final v in viaRes as List) {
            viagensHoje++;
            if (v['status'] == 'concluida') {
              distanciaHoje +=
                  (v['quilometragem_percorrida'] as num?)?.toDouble() ?? 0;
              tempoTransitoMin +=
                  (v['duracao_minutos'] as num?)?.toInt() ?? 0;
            }
          }
        } catch (_) {}
      }

      // ── Alertas do veículo ────────────────────────────────────────────────
      if (vehicleId != null && empresaId != null) {
        try {
          final alertRes = await _supabase
              .from('alerts')
              .select('id, problem_type, priority, status')
              .eq('empresa_id', empresaId)
              .eq('vehicle_id', vehicleId)
              .neq('status', 'resolvido')
              .order('priority', ascending: false)
              .limit(5);
          alertas = List<Map<String, dynamic>>.from(alertRes);
        } catch (_) {}
      }

      // ── Última manutenção (oil_change) ────────────────────────────────────
      if (vehicleId != null) {
        try {
          ultManut = await _supabase
              .from('oil_changes')
              .select('id, created_at, vehicle_id, next_change_km')
              .eq('vehicle_id', vehicleId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (ultManut != null) {
            final dtManut = DateTime.tryParse(
                ultManut['created_at']?.toString() ?? '');
            if (dtManut != null &&
                DateTime.now().difference(dtManut).inDays < 90) {
              manutencaoStatus = 'Em dia';
            }
          }
        } catch (_) {}
      }

      // ── Dados do driver (CNH, telefone, categoria) ────────────────────────
      Map<String, dynamic>? driverRec;
      if (driverId != null) {
        try {
          driverRec = await _supabase
              .from('drivers')
              .select('name, cnh_number, cnh_expiration, cnh_category, phone')
              .eq('id', driverId)
              .maybeSingle();
        } catch (_) {}
      }

      // ── Avatar URL (da coluna avatar_url em user_profiles) ────────────────
      String? avatarUrl;
      if (userId != null) {
        try {
          final perfil = await _supabase
              .from('user_profiles')
              .select('avatar_url')
              .eq('user_id', userId)
              .maybeSingle();
          avatarUrl = perfil?['avatar_url']?.toString();
          // cache-bust para forçar reload após upload
          if (avatarUrl != null && avatarUrl.isNotEmpty) {
            avatarUrl = _addCacheBust(avatarUrl);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _veiculo = veiculo;
        _alertas = alertas;
        _ultimoAbastecimento = abastRes;
        _ultimaManutencao = ultManut;
        _ocorrenciasAbertas = ocorrenciasAbertas;
        _checklistSaidaHoje = checklistSaida;
        _checklistRetornoHoje = checklistRetorno;
        _abastecimentosHoje = abastecimentosHoje;
        _viagensHoje = viagensHoje;
        _distanciaHoje = distanciaHoje;
        _tempoTransitoMin = tempoTransitoMin;
        _manutencaoStatus = manutencaoStatus;
        _driverRecord = driverRec;
        _avatarUrl = avatarUrl;
        _loadingVeiculo = false;
      });
    } catch (e) {
      debugPrint('MotoristaHomePage._carregar: $e');
      if (mounted) setState(() => _loadingVeiculo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final nome = auth.profile?.nome ?? auth.profile?.email ?? 'Motorista';
    final primeiroNome = nome.split(' ').first;
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (isMobile) return _buildMobileScaffold(auth, primeiroNome);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _buildSidebar(auth, primeiroNome),
          Expanded(child: _buildContent(auth, primeiroNome)),
        ],
      ),
    );
  }

  // ── Mobile scaffold ───────────────────────────────────────────────────────

  Widget _buildMobileScaffold(AppAuthProvider auth, String primeiroNome) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1AA251), Color(0xFF0D6B35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.local_shipping,
                  color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
            const Text('FrotaCheck',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          if (_alertas.isNotEmpty)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications,
                      color: AppColors.textSecondary, size: 20),
                  onPressed: _carregar,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFEF4444), shape: BoxShape.circle),
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh,
                  color: AppColors.textSecondary, size: 20),
              onPressed: _carregar,
            ),
        ],
      ),
      body: _buildMobileBody(auth, primeiroNome),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMobileBody(AppAuthProvider auth, String primeiroNome) {
    switch (_activeTab) {
      case _MobileTab.dashboard:
        return _buildMobileDashboard(auth, primeiroNome);
      case _MobileTab.veiculo:
        return _buildMeuVeiculo();
      case _MobileTab.atividades:
        return _buildMobileAtividades();
      case _MobileTab.perfil:
        return _buildPerfil(auth);
    }
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      backgroundColor: AppColors.surface,
      selectedItemColor: const Color(0xFF1AA251),
      unselectedItemColor: AppColors.textSecondary,
      currentIndex: _activeTab.index,
      type: BottomNavigationBarType.fixed,
      selectedFontSize: 10,
      unselectedFontSize: 10,
      onTap: (i) => setState(() => _activeTab = _MobileTab.values[i]),
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.dashboard, size: 22), label: 'Início'),
        BottomNavigationBarItem(
            icon: Icon(Icons.directions_car, size: 22),
            label: 'Veículo'),
        BottomNavigationBarItem(
            icon: Icon(Icons.apps, size: 22), label: 'Atividades'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person, size: 22), label: 'Perfil'),
      ],
    );
  }

  // ── Mobile dashboard ──────────────────────────────────────────────────────

  Widget _buildMobileDashboard(AppAuthProvider auth, String primeiroNome) {
    final hora = DateTime.now().hour;
    final saudacao =
        hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite';

    return RefreshIndicator(
      color: const Color(0xFF1AA251),
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$saudacao, $primeiroNome!',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _buildVeiculoBanner(),
            const SizedBox(height: 14),

            // Tarefas (scroll horizontal no mobile)
            _sectionHeader('Tarefas de Hoje'),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _taskCardMobile(Icons.checklist_rtl, 'Checklist\nSaída',
                      const Color(0xFF1AA251),
                      _checklistSaidaHoje ? 'Concluído' : 'Não iniciado',
                      _checklistSaidaHoje
                          ? const Color(0xFF1AA251)
                          : const Color(0xFF94A3B8),
                      () => _push(const SelecionarVeiculoChecklistPage())),
                  const SizedBox(width: 8),
                  _taskCardMobile(Icons.check_circle,
                      'Checklist\nRetorno', const Color(0xFF3B82F6),
                      _checklistRetornoHoje ? 'Concluído' : 'Não iniciado',
                      _checklistRetornoHoje
                          ? const Color(0xFF1AA251)
                          : const Color(0xFF94A3B8),
                      () => _push(const SelecionarVeiculoChecklistPage())),
                  const SizedBox(width: 8),
                  _taskCardMobile(Icons.local_gas_station_rounded,
                      'Abaste-\ncimento', const Color(0xFFF59E0B),
                      _abastecimentosHoje > 0
                          ? '$_abastecimentosHoje registrado(s)'
                          : 'Não registrado',
                      _abastecimentosHoje > 0
                          ? const Color(0xFF1AA251)
                          : const Color(0xFFF59E0B),
                      () => _push(const AbastecimentosPage())),
                  const SizedBox(width: 8),
                  _taskCardMobile(Icons.build_rounded, 'Manutenção',
                      const Color(0xFF8B5CF6), _manutencaoStatus,
                      _manutencaoStatus == 'Em dia'
                          ? const Color(0xFF1AA251)
                          : const Color(0xFFF59E0B),
                      () => _push(const ManutencoesPage())),
                  const SizedBox(width: 8),
                  _taskCardMobile(Icons.report_problem_rounded, 'Ocorrências',
                      const Color(0xFFEF4444),
                      _ocorrenciasAbertas == 0
                          ? 'Nenhuma'
                          : '$_ocorrenciasAbertas aberta(s)',
                      _ocorrenciasAbertas == 0
                          ? const Color(0xFF1AA251)
                          : const Color(0xFFEF4444),
                      () => _push(const ListaOcorrenciasPage())),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Resumo do dia (2x2 chips)
            _sectionHeader('Resumo do Dia'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _resumoChip(Icons.directions, 'Viagens',
                        '$_viagensHoje', const Color(0xFF3B82F6))),
                const SizedBox(width: 8),
                Expanded(
                    child: _resumoChip(Icons.place, 'Distância',
                        '${_distanciaHoje.toStringAsFixed(0)} km',
                        const Color(0xFF8B5CF6))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _resumoChip(Icons.schedule, 'Trânsito',
                        _fmtTempo(_tempoTransitoMin),
                        const Color(0xFF06B6D4))),
                const SizedBox(width: 8),
                Expanded(
                    child: _resumoChip(Icons.local_gas_station_rounded,
                        'Abastecimentos', '$_abastecimentosHoje',
                        const Color(0xFFF59E0B))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCardMobile(IconData icon, String titulo, Color cor,
      String status, Color statusCor, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 95,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.22)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconCircle(icon, cor, 40, 18),
              const SizedBox(height: 6),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.2)),
              const SizedBox(height: 3),
              Text(status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: statusCor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumoChip(
      IconData icon, String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: cor, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 9)),
                Text(valor,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile Atividades (grid) ──────────────────────────────────────────────

  Widget _buildMobileAtividades() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        const Text('Atividades',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: [
            _atividadeGrid(Icons.directions, 'Minha Viagem',
                const Color(0xFF8B5CF6), () => _push(const ViagensPage())),
            _atividadeGrid(
                Icons.checklist_rtl,
                'Checklist Saída',
                const Color(0xFF1AA251),
                () => _push(const SelecionarVeiculoChecklistPage())),
            _atividadeGrid(
                Icons.check_circle,
                'Checklist Retorno',
                const Color(0xFF3B82F6),
                () => _push(const SelecionarVeiculoChecklistPage())),
            _atividadeGrid(
                Icons.local_gas_station_rounded,
                'Abastecimentos',
                const Color(0xFFF59E0B),
                () => _push(const AbastecimentosPage())),
            _atividadeGrid(Icons.build_rounded, 'Manutenções',
                const Color(0xFFEC4899),
                () => _push(const ManutencoesPage())),
            _atividadeGrid(Icons.report_problem_rounded, 'Ocorrências',
                const Color(0xFFEF4444),
                () => _push(const ListaOcorrenciasPage())),
            _atividadeGrid(Icons.description, 'Documentos',
                const Color(0xFF06B6D4),
                () => _push(const DocumentosPage())),
            _atividadeGrid(Icons.settings, 'Pneus',
                const Color(0xFF10B981), () => _push(const PneusPage())),
            _atividadeGrid(Icons.gavel, 'Multas',
                const Color(0xFFDC2626), () => _push(const MultasPage())),
            _atividadeGrid(Icons.history, 'Histórico',
                const Color(0xFF6B7280),
                () => _push(const HistoricoChecklistPage())),
          ],
        ),
      ],
    );
  }

  Widget _atividadeGrid(
      IconData icon, String label, Color cor, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.22)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconCircle(icon, cor, 44, 22),
              const SizedBox(height: 7),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar(AppAuthProvider auth, String nome) {
    return Container(
      width: 200,
      color: AppColors.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1AA251), Color(0xFF0D6B35)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_shipping,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FrotaCheck',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Text('Motorista',
                          style: TextStyle(
                              color: Color(0xFF1AA251), fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFF0E1E33)),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _item(Icons.dashboard, 'Dashboard', _Sec.dashboard),
                  _item(Icons.directions_car, 'Meu Veículo',
                      _Sec.meuVeiculo),
                  const SizedBox(height: 4),
                  _label('OPERAÇÕES'),
                  _item(Icons.directions, 'Minha Viagem', _Sec.viagem),
                  _item(Icons.checklist_rtl, 'Checklist Saída',
                      _Sec.checklistSaida),
                  _item(Icons.check_circle,
                      'Checklist Retorno', _Sec.checklistRetorno),
                  _item(Icons.local_gas_station_rounded, 'Abastecimentos',
                      _Sec.abastecimentos),
                  _item(Icons.build_rounded, 'Manutenções', _Sec.manutencoes),
                  _item(Icons.report_problem_rounded, 'Ocorrências',
                      _Sec.ocorrencias),
                  const SizedBox(height: 4),
                  _label('DOCUMENTOS'),
                  _item(Icons.description, 'Documentos',
                      _Sec.documentos),
                  _item(Icons.settings, 'Controle de Pneus',
                      _Sec.pneus),
                  _item(Icons.gavel, 'Multas', _Sec.multas),
                  const SizedBox(height: 4),
                  _label('CONTA'),
                  _item(Icons.person, 'Meu Perfil', _Sec.perfil),
                ],
              ),
            ),
          ),
          Container(height: 1, color: const Color(0xFF0E1E33)),
          _buildLogout(auth),
          _buildProfileCard(auth, nome),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 0, 3),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Widget _item(IconData icon, String label, _Sec section) {
    final active = _activeSection == section;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTap(section),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: active
              ? BoxDecoration(
                  color: const Color(0xFF1AA251).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF1AA251).withOpacity(0.30)),
                )
              : null,
          child: Row(
            children: [
              Icon(icon,
                  color: active
                      ? const Color(0xFF1AA251)
                      : const Color(0xFF475569),
                  size: 15),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color:
                            active ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.w400)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogout(AppAuthProvider auth) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Finalizar Sessão'),
              content: const Text('Deseja realmente sair?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444)),
                  child: const Text('Sair'),
                ),
              ],
            ),
          );
          if (ok == true && mounted) await auth.signOut();
        },
        child: const Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 14),
              SizedBox(width: 8),
              Text('Sair',
                  style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(AppAuthProvider auth, String nome) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFF1AA251).withOpacity(0.18),
            child: Text(
              nome.isNotEmpty ? nome[0].toUpperCase() : 'M',
              style: const TextStyle(
                  color: Color(0xFF1AA251),
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1AA251).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('MOTORISTA',
                      style: TextStyle(
                          color: Color(0xFF1AA251),
                          fontSize: 8,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Roteamento ────────────────────────────────────────────────────────────

  void _onTap(_Sec section) {
    switch (section) {
      case _Sec.dashboard:
      case _Sec.meuVeiculo:
      case _Sec.perfil:
        setState(() => _activeSection = section);
        return;
      case _Sec.viagem:
        _push(const ViagensPage());
        return;
      case _Sec.checklistSaida:
      case _Sec.checklistRetorno:
        _push(const SelecionarVeiculoChecklistPage());
        return;
      case _Sec.abastecimentos:
        _push(const AbastecimentosPage());
        return;
      case _Sec.manutencoes:
        _push(const ManutencoesPage());
        return;
      case _Sec.ocorrencias:
        _push(const ListaOcorrenciasPage());
        return;
      case _Sec.documentos:
        _push(const DocumentosPage());
        return;
      case _Sec.pneus:
        _push(const PneusPage());
        return;
      case _Sec.multas:
        _push(const MultasPage());
        return;
    }
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page))
          .then((_) => _carregar());

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(AppAuthProvider auth, String primeiroNome) {
    switch (_activeSection) {
      case _Sec.dashboard:
        return _buildDashboard(auth, primeiroNome);
      case _Sec.meuVeiculo:
        return _buildMeuVeiculo();
      case _Sec.perfil:
        return _buildPerfil(auth);
      default:
        return _buildDashboard(auth, primeiroNome);
    }
  }

  // ── Dashboard Desktop (foco em tarefas) ───────────────────────────────────

  Widget _buildDashboard(AppAuthProvider auth, String primeiroNome) {
    final hora = DateTime.now().hour;
    final saudacao =
        hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite';
    final now = DateTime.now();
    final dataStr =
        '${_semana[now.weekday - 1]}, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return RefreshIndicator(
      color: const Color(0xFF1AA251),
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$saudacao, $primeiroNome!',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(dataStr,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                // Notification bell
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      onPressed: _carregar,
                      icon: const Icon(Icons.notifications,
                          color: AppColors.textSecondary, size: 22),
                      tooltip: 'Atualizar',
                    ),
                    if (_alertas.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildVeiculoBanner(),
            const SizedBox(height: 20),

            // ── Suas tarefas de hoje ──────────────────────────────────────
            _sectionHeader('Suas tarefas de hoje'),
            const SizedBox(height: 10),
            if (_loadingVeiculo)
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF1AA251), strokeWidth: 2),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _taskCard(
                      icon: Icons.checklist_rtl,
                      cor: const Color(0xFF1AA251),
                      titulo: 'Checklist Saída',
                      status: _checklistSaidaHoje ? 'Concluído' : 'Não iniciado',
                      statusCor: _checklistSaidaHoje
                          ? const Color(0xFF1AA251)
                          : const Color(0xFF94A3B8),
                      onTap: () => _onTap(_Sec.checklistSaida),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _taskCard(
                      icon: Icons.check_circle,
                      cor: const Color(0xFF3B82F6),
                      titulo: 'Checklist Retorno',
                      status:
                          _checklistRetornoHoje ? 'Concluído' : 'Não iniciado',
                      statusCor: _checklistRetornoHoje
                          ? const Color(0xFF1AA251)
                          : const Color(0xFF94A3B8),
                      onTap: () => _onTap(_Sec.checklistRetorno),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _taskCard(
                      icon: Icons.local_gas_station_rounded,
                      cor: const Color(0xFFF59E0B),
                      titulo: 'Abastecimento',
                      status: _abastecimentosHoje > 0
                          ? '$_abastecimentosHoje registrado(s)'
                          : 'Não registrado',
                      statusCor: _abastecimentosHoje > 0
                          ? const Color(0xFF1AA251)
                          : const Color(0xFFF59E0B),
                      onTap: () => _onTap(_Sec.abastecimentos),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _taskCard(
                      icon: Icons.build_rounded,
                      cor: const Color(0xFF8B5CF6),
                      titulo: 'Manutenção',
                      status: _manutencaoStatus,
                      statusCor: _manutencaoStatus == 'Em dia'
                          ? const Color(0xFF1AA251)
                          : const Color(0xFFF59E0B),
                      onTap: () => _onTap(_Sec.manutencoes),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _taskCard(
                      icon: Icons.report_problem_rounded,
                      cor: const Color(0xFFEF4444),
                      titulo: 'Ocorrências',
                      status: _ocorrenciasAbertas == 0
                          ? 'Nenhuma'
                          : '$_ocorrenciasAbertas aberta(s)',
                      statusCor: _ocorrenciasAbertas == 0
                          ? const Color(0xFF1AA251)
                          : const Color(0xFFEF4444),
                      onTap: () => _onTap(_Sec.ocorrencias),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),

            // ── Resumo do dia + Atividade recente (lado a lado) ───────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumo do dia
                Expanded(child: _buildResumoPanel()),
                const SizedBox(width: 16),
                // Atividade recente
                Expanded(child: _buildAtividadePanel()),
              ],
            ),
            const SizedBox(height: 20),

            // ── Banner segurança ──────────────────────────────────────────
            _buildSafetyBanner(),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => _push(const HistoricoChecklistPage()),
              icon: const Icon(Icons.history,
                  size: 13, color: Color(0xFF1AA251)),
              label: const Text('Ver histórico de checklists',
                  style:
                      TextStyle(color: Color(0xFF1AA251), fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Resumo do dia'),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          _resumoRow(Icons.directions, const Color(0xFF3B82F6),
              'Viagens', '$_viagensHoje'),
          const Divider(color: AppColors.border, height: 1),
          _resumoRow(Icons.place, const Color(0xFF8B5CF6),
              'Distância',
              '${_distanciaHoje.toStringAsFixed(1)} km'),
          const Divider(color: AppColors.border, height: 1),
          _resumoRow(Icons.schedule, const Color(0xFF06B6D4),
              'Tempo em trânsito', _fmtTempo(_tempoTransitoMin)),
          const Divider(color: AppColors.border, height: 1),
          _resumoRow(Icons.local_gas_station_rounded,
              const Color(0xFFF59E0B), 'Abastecimentos',
              '$_abastecimentosHoje'),
        ],
      ),
    );
  }

  Widget _resumoRow(IconData icon, Color cor, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: cor, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Text(valor,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildAtividadePanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Atividade recente'),
          const SizedBox(height: 12),
          if (_ultimoAbastecimento != null)
            _atividadeItem(
              icon: Icons.local_gas_station_rounded,
              cor: const Color(0xFFF59E0B),
              titulo: 'Último abastecimento',
              sub: _placaLabel(_ultimoAbastecimento!),
              extra: _ultimoAbastecimento!['liters'] != null
                  ? '${_ultimoAbastecimento!['liters']} L'
                  : null,
              data: _ultimoAbastecimento!['created_at']?.toString(),
            )
          else
            _vazioSmall('Nenhum abastecimento registrado.'),
          const SizedBox(height: 8),
          if (_ultimaManutencao != null)
            _atividadeItem(
              icon: Icons.build_rounded,
              cor: const Color(0xFFEC4899),
              titulo: 'Última troca de óleo',
              sub:
                  'Próxima troca: ${_ultimaManutencao!['next_change_km'] ?? '—'} km',
              data: _ultimaManutencao!['created_at']?.toString(),
            )
          else
            _vazioSmall('Nenhuma manutenção registrada.'),
        ],
      ),
    );
  }

  Widget _atividadeItem({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String sub,
    String? extra,
    String? data,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: cor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Text(sub,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (extra != null)
                Text(extra,
                    style: TextStyle(
                        color: cor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              if (data != null)
                Text(_dataCurta(data),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF071A0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1AA251).withOpacity(0.25)),
      ),
      // Usa spaceBetween + Row interno para evitar Expanded no Flutter web
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1AA251).withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Color(0xFF1AA251), size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Dirija com segurança!',
                      style: TextStyle(
                          color: Color(0xFF1AA251),
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('Seus registros fazem a diferença.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => _push(const HistoricoChecklistPage()),
            icon: const Icon(Icons.arrow_forward_rounded, size: 13),
            label: const Text('Ver dicas'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.22)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Meu Veículo ───────────────────────────────────────────────────────────

  Widget _buildMeuVeiculo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Meu Veículo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: _carregar,
                icon:
                    const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Atualizar',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildVeiculoCard(),
          if (_veiculo != null) ...[
            const SizedBox(height: 20),
            _sectionHeader('Última Manutenção'),
            const SizedBox(height: 10),
            if (_ultimaManutencao != null)
              _timelineItem(
                icon: Icons.build_rounded,
                cor: const Color(0xFFEC4899),
                titulo: 'Última Troca de Óleo',
                subtitulo:
                    'Próxima: ${_ultimaManutencao!['next_change_km'] ?? '—'} km',
                data: _ultimaManutencao!['created_at']?.toString(),
                isLast: true,
              )
            else
              _vazio('Nenhuma manutenção registrada para este veículo.'),
            const SizedBox(height: 20),
            _sectionHeader('Alertas Ativos'),
            const SizedBox(height: 10),
            if (_alertas.isNotEmpty)
              ..._alertas.map(_alertaBanner)
            else
              _vazio('Nenhum alerta ativo para este veículo.'),
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _onTap(_Sec.manutencoes),
                icon: const Icon(Icons.build_rounded, size: 14),
                label: const Text('Registrar Manutenção'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEC4899),
                  side: const BorderSide(color: Color(0xFFEC4899)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Meu Perfil ────────────────────────────────────────────────────────────

  Widget _buildPerfil(AppAuthProvider auth) {
    final p = auth.profile;
    final nome = p?.nome ?? _driverRecord?['name']?.toString() ?? 'Motorista';
    final email = p?.email ?? '';
    final status = p?.status ?? 'ativo';
    final statusCor = status == 'ativo'
        ? const Color(0xFF1AA251)
        : status == 'bloqueado'
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

    final cnhNumero = _driverRecord?['cnh_number']?.toString() ?? '—';
    final cnhCategoria = _driverRecord?['cnh_category']?.toString() ?? '—';
    final cnhValidade = _driverRecord?['cnh_expiration']?.toString();
    final telefone = _driverRecord?['phone']?.toString() ?? '—';

    final placa = _veiculo?['plate']?.toString() ?? '';
    final marca = _veiculo?['brand']?.toString() ?? '';
    final modelo = _veiculo?['model']?.toString() ?? '';
    final veiculoStr = _veiculo != null
        ? '$placa — $marca $modelo'.trim()
        : 'Não vinculado';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header card com imagem de fundo ──────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 185,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/meuperfilogo.jpeg'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF060F1C).withOpacity(0.88),
                      const Color(0xFF060F1C).withOpacity(0.55),
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                child: Stack(
                  children: [
                    // Sparkles
                    Positioned(
                        top: 22,
                        right: 30,
                        child: _sparkle(18, opacity: 0.80)),
                    Positioned(
                        top: 55,
                        right: 72,
                        child: _sparkle(9, opacity: 0.55)),
                    Positioned(
                        top: 14,
                        right: 110,
                        child: _sparkle(6, opacity: 0.40)),
                    Positioned(
                        top: 42,
                        right: 120,
                        child: _sparkle(5, opacity: 0.30)),
                    // Avatar + info
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1AA251),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.22),
                                        width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                          color: const Color(0xFF1AA251)
                                              .withOpacity(0.35),
                                          blurRadius: 14,
                                          spreadRadius: 2),
                                    ],
                                    image: (_avatarUrl != null &&
                                            _avatarUrl!.isNotEmpty)
                                        ? DecorationImage(
                                            image:
                                                NetworkImage(_avatarUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: (_avatarUrl == null ||
                                          _avatarUrl!.isEmpty)
                                      ? Text(
                                          nome.isNotEmpty
                                              ? nome[0].toUpperCase()
                                              : 'M',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 32,
                                              fontWeight: FontWeight.w800),
                                        )
                                      : null,
                                ),
                                // Câmera overlay
                                Positioned(
                                  bottom: 0,
                                  right: -2,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1AA251),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white.withOpacity(0.85),
                                          width: 2),
                                    ),
                                    alignment: Alignment.center,
                                    child: _uploadingAvatar
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2),
                                          )
                                        : const Icon(
                                            Icons.camera_alt_rounded,
                                            color: Colors.white,
                                            size: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nome.toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () =>
                                          _editarNome(auth, p?.nome ?? ''),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.08),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.edit,
                                            color: Colors.white54, size: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.60),
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1AA251)
                                        .withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: const Color(0xFF1AA251)
                                            .withOpacity(0.55)),
                                  ),
                                  child: const Text('MOTORISTA',
                                      style: TextStyle(
                                          color: Color(0xFF1AA251),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Informações da conta ──────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text('Informações da conta',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                const Divider(color: AppColors.border, height: 1),
                _perfilInfoRow('Empresa', p?.empresaNome ?? '—'),
                _perfilInfoRow('Veículo vinculado', veiculoStr),
                _perfilInfoRow('Status', _capitalize(status),
                    valueColor: statusCor),
                _perfilInfoRow('CNH', cnhNumero),
                _perfilInfoRow('Categoria', cnhCategoria),
                _perfilInfoRow(
                    'Validade da CNH', _fmtDataISO(cnhValidade)),
                _perfilInfoRow('Telefone',
                    (telefone.isEmpty || telefone == 'null') ? '—' : telefone),
                if (p?.lastAccess != null)
                  _perfilInfoRow('Último acesso',
                      _dataFull(p!.lastAccess!.toLocal()),
                      isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Botões de ação ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  Icons.edit,
                  'Editar dados',
                  const Color(0xFF3B82F6),
                  () => _editarNome(auth, p?.nome ?? ''),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  Icons.fingerprint,
                  'Alterar senha',
                  const Color(0xFFF59E0B),
                  _alterarSenha,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  Icons.notifications,
                  'Notificações',
                  const Color(0xFF8B5CF6),
                  _abrirNotificacoes,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  Icons.close,
                  'Sair da conta',
                  const Color(0xFFEF4444),
                  () => _sairDaConta(auth),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _perfilInfoRow(String label, String valor,
      {Color? valueColor, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text(valor,
                style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color cor, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _iconCircle(icon, cor, 48, 22),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: cor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconCircle(IconData icon, Color cor, double size, double iconSize) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  Widget _sparkle(double size, {double opacity = 0.70}) {
    return Opacity(
      opacity: opacity,
      child: Text('✦',
          style: TextStyle(
              color: Colors.white,
              fontSize: size,
              height: 1)),
    );
  }

  void _abrirNotificacoes() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.notifications,
                color: Color(0xFF8B5CF6), size: 20),
            SizedBox(width: 10),
            Text('Notificações',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 4),
            Icon(Icons.notifications_off_outlined,
                color: AppColors.textSecondary, size: 40),
            SizedBox(height: 12),
            Text(
              'Nenhuma notificação no momento.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            SizedBox(height: 6),
            Text(
              'Você será avisado sobre alertas do veículo, vencimento de documentos e tarefas pendentes.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar',
                style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );
  }

  Future<void> _alterarSenha() async {
    final email = _supabase.auth.currentUser?.email ?? '';
    if (email.isEmpty) return;
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Email de redefinição de senha enviado!'),
            backgroundColor: Color(0xFF1AA251)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _sairDaConta(AppAuthProvider auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sair da conta',
            style: TextStyle(color: Colors.white)),
        content: const Text('Tem certeza que deseja sair?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await auth.signOut();
  }

  String _fmtDataISO(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final parts = iso.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return iso;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // Adiciona ?t=timestamp à URL para forçar reload no browser após upload
  String _addCacheBust(String url) {
    final t = DateTime.now().millisecondsSinceEpoch;
    return url.contains('?') ? '$url&t=$t' : '$url?t=$t';
  }

  // ── Upload de foto de perfil ──────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    // Dialogo para escolher câmera ou galeria
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.add_a_photo_rounded,
                color: Color(0xFF1AA251), size: 20),
            SizedBox(width: 10),
            Text('Foto de perfil',
                style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: const Text(
          'Escolha a origem da foto.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded, size: 16),
            label: const Text('Câmera'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1AA251)),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_rounded, size: 16),
            label: const Text('Galeria'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6)),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() => _uploadingAvatar = true);

      final bytes = await picked.readAsBytes();
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final ext = picked.name.split('.').last.toLowerCase();
      final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
      final path = '$userId.$ext';

      // Upload para Supabase Storage bucket "avatars"
      await _supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );

      final rawUrl =
          _supabase.storage.from('avatars').getPublicUrl(path);

      // Salva URL em user_profiles
      await _supabase
          .from('user_profiles')
          .update({'avatar_url': rawUrl})
          .eq('user_id', userId);

      final urlComBust = _addCacheBust(rawUrl);
      if (mounted) {
        setState(() {
          _avatarUrl = urlComBust;
          _uploadingAvatar = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto atualizada com sucesso!'),
          backgroundColor: Color(0xFF1AA251),
        ));
      }
    } catch (e) {
      debugPrint('Avatar upload: $e');
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Erro ao enviar foto. Verifique se o bucket "avatars" existe no Supabase Storage.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  Future<void> _editarNome(AppAuthProvider auth, String nomeAtual) async {
    final ctrl = TextEditingController(text: nomeAtual);
    final salvo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar nome',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Seu nome completo',
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
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (salvo == null || salvo.isEmpty || !mounted) return;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase
          .from('user_profiles')
          .update({'nome': salvo})
          .eq('user_id', userId);
      await auth.reload();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Vehicle widgets ───────────────────────────────────────────────────────

  Widget _buildVeiculoBanner() {
    if (_loadingVeiculo) {
      return Container(
        height: 58,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF1AA251), strokeWidth: 2)),
      );
    }
    if (_veiculo == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.directions_car_outlined,
                color: Color(0xFF475569), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text('Nenhum veículo vinculado — solicite ao gestor.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ],
        ),
      );
    }
    final placa = _veiculo!['plate']?.toString() ?? '—';
    final modelo =
        '${_veiculo!['brand'] ?? ''} ${_veiculo!['model'] ?? ''}'.trim();
    final ano = _veiculo!['year']?.toString() ?? '';
    final status = _veiculo!['status']?.toString() ?? 'ativo';
    final cor = status == 'ativo'
        ? const Color(0xFF1AA251)
        : status == 'manutencao'
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: cor, width: 3),
          top: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(Icons.directions_car, color: cor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(placa,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
                if (modelo.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text('$modelo${ano.isNotEmpty ? '  ·  $ano' : ''}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cor.withOpacity(0.30)),
            ),
            child: Text(status.toUpperCase(),
                style: TextStyle(
                    color: cor, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
          if (_alertas.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_rounded,
                      color: Color(0xFFEF4444), size: 11),
                  const SizedBox(width: 3),
                  Text('${_alertas.length}',
                      style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVeiculoCard() {
    if (_loadingVeiculo) {
      return _cardBase(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(
                color: Color(0xFF1AA251), strokeWidth: 2),
          ),
        ),
      );
    }
    if (_veiculo == null) {
      return _cardBase(
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Nenhum veículo vinculado. Solicite ao gestor ou admin que vincule um veículo ao seu perfil.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    final placa = _veiculo!['plate']?.toString() ?? '—';
    final modelo =
        '${_veiculo!['brand'] ?? ''} ${_veiculo!['model'] ?? ''}'.trim();
    final ano = _veiculo!['year']?.toString() ?? '';
    final status = _veiculo!['status']?.toString() ?? 'ativo';
    final cor = status == 'ativo'
        ? const Color(0xFF1AA251)
        : status == 'manutencao'
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return _cardBase(
      border: cor.withOpacity(0.40),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(Icons.directions_car, color: cor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MEU VEÍCULO',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  Text(placa,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2)),
                  Text('$modelo${ano.isNotEmpty ? "  •  $ano" : ""}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cor.withOpacity(0.35)),
              ),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: cor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Timeline ──────────────────────────────────────────────────────────────

  Widget _timelineItem({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    String? data,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration:
                    BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
              if (!isLast)
                Container(width: 1.5, height: 38, color: AppColors.border),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: cor, width: 2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(subtitulo,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  if (data != null)
                    Text(_dataCurta(data),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Task card ─────────────────────────────────────────────────────────────

  Widget _taskCard({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String status,
    required Color statusCor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconCircle(icon, cor, 54, 26),
              const SizedBox(height: 10),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: statusCor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers visuais ───────────────────────────────────────────────────────

  Widget _cardBase({required Widget child, Color? border}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border ?? AppColors.border),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String t) => Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF1AA251),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(t,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      );

  Widget _alertaBanner(Map<String, dynamic> alerta) {
    final prioridade = alerta['priority']?.toString() ?? 'Media';
    final cor = prioridade == 'Alta'
        ? const Color(0xFFEF4444)
        : prioridade == 'Media'
            ? const Color(0xFFF59E0B)
            : const Color(0xFF3B82F6);
    final titulo = alerta['problem_type']?.toString() ?? 'Alerta';
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(color: cor, width: 3),
          top: BorderSide(color: cor.withOpacity(0.18)),
          right: BorderSide(color: cor.withOpacity(0.18)),
          bottom: BorderSide(color: cor.withOpacity(0.18)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: cor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(titulo,
                style: TextStyle(
                    color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Text(prioridade.toUpperCase(),
              style: TextStyle(
                  color: cor.withOpacity(0.70),
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _vazio(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(msg,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }

  Widget _vazioSmall(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(msg,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      );

  String _fmtTempo(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _placaLabel(Map<String, dynamic> r) {
    final v = r['vehicles'];
    if (v is Map && v['plate'] != null) return v['plate'].toString();
    return 'Veículo';
  }

  String _dataFull(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _dataCurta(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  static const List<String> _semana = [
    'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo',
  ];
}

enum _Sec {
  dashboard,
  meuVeiculo,
  viagem,
  checklistSaida,
  checklistRetorno,
  abastecimentos,
  manutencoes,
  ocorrencias,
  documentos,
  pneus,
  multas,
  perfil,
}

enum _MobileTab { dashboard, veiculo, atividades, perfil }

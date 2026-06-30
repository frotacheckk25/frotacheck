import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../abastecimentos/abastecimentos_page.dart';
import '../checklists/selecionar_veiculo_checklist.dart';
import '../checklists/historico_checklist_page.dart';
import '../documentos/documentos_page.dart';
import '../manutencoes/manutencoes_page.dart';
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

  bool _loadingVeiculo = true;
  Map<String, dynamic>? _veiculo;
  int _checklistsHoje = 0;
  int _ocorrenciasAbertas = 0;
  List<Map<String, dynamic>> _alertas = [];
  Map<String, dynamic>? _ultimoAbastecimento;
  Map<String, dynamic>? _ultimaManutencao;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loadingVeiculo = true);
    final auth = context.read<AppAuthProvider>();
    final empresaId = auth.empresaId;
    final driverId = auth.profile?.driverId;

    if (empresaId == null) {
      setState(() => _loadingVeiculo = false);
      return;
    }

    try {
      final hoje = DateTime.now();
      final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();

      // Veículo vinculado ao motorista (via vehicles.driver_id)
      Map<String, dynamic>? veiculo;
      if (driverId != null) {
        veiculo = await _supabase
            .from('vehicles')
            .select('id, plate, model, year, brand, status')
            .eq('empresa_id', empresaId)
            .eq('driver_id', driverId)
            .limit(1)
            .maybeSingle()
            .catchError((_) => null);
      }

      // KPIs do dia (filtrados pelo driverId do motorista)
      int checklistsHoje = 0;
      int ocorrenciasAbertas = 0;
      List<Map<String, dynamic>> alertas = [];
      Map<String, dynamic>? abastRes;
      Map<String, dynamic>? ultManut;
      String? vehicleId = veiculo?['id']?.toString();

      if (driverId != null) {
        try {
          final res = await _supabase
              .from('checklists')
              .select('id')
              .eq('empresa_id', empresaId)
              .eq('motorista_id', driverId)
              .gte('created_at', inicioHoje)
              .count();
          checklistsHoje = res.count;
        } catch (_) {}

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

        // Último abastecimento deste motorista
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
      }

      // Alertas do veículo vinculado
      if (vehicleId != null) {
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

        // Última manutenção do veículo vinculado
        try {
          ultManut = await _supabase
              .from('oil_changes')
              .select('id, created_at, vehicle_id, next_change_km')
              .eq('vehicle_id', vehicleId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _veiculo = veiculo;
        _alertas = alertas;
        _ultimoAbastecimento = abastRes;
        _ultimaManutencao = ultManut;
        _checklistsHoje = checklistsHoje;
        _ocorrenciasAbertas = ocorrenciasAbertas;
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

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar(AppAuthProvider auth, String nome) {
    return Container(
      width: 200,
      color: AppColors.surface,
      child: Column(
        children: [
          // Logo
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
                  child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FrotaCheck', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('Motorista', style: TextStyle(color: Color(0xFF1AA251), fontSize: 10)),
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
                  _item(Icons.dashboard_rounded, 'Dashboard', _Sec.dashboard),
                  _item(Icons.directions_car_rounded, 'Meu Veículo', _Sec.meuVeiculo),
                  const SizedBox(height: 4),
                  _label('OPERAÇÕES'),
                  _item(Icons.route_rounded, 'Minha Viagem', _Sec.viagem),
                  _item(Icons.checklist_rtl_rounded, 'Checklist Saída', _Sec.checklistSaida),
                  _item(Icons.assignment_turned_in_rounded, 'Checklist Retorno', _Sec.checklistRetorno),
                  _item(Icons.local_gas_station_rounded, 'Abastecimentos', _Sec.abastecimentos),
                  _item(Icons.build_rounded, 'Manutenções', _Sec.manutencoes),
                  _item(Icons.report_problem_rounded, 'Ocorrências', _Sec.ocorrencias),
                  _item(Icons.description_rounded, 'Documentos', _Sec.documentos),
                  const SizedBox(height: 4),
                  _label('CONTA'),
                  _item(Icons.person_rounded, 'Meu Perfil', _Sec.perfil),
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
        child: Text(text, style: const TextStyle(color: Color(0xFF475569), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
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
                  border: Border.all(color: const Color(0xFF1AA251).withOpacity(0.30)),
                )
              : null,
          child: Row(
            children: [
              Icon(icon, color: active ? const Color(0xFF1AA251) : const Color(0xFF475569), size: 15),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
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
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
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
              Text('Sair', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600)),
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
              style: const TextStyle(color: Color(0xFF1AA251), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1AA251).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('MOTORISTA',
                      style: TextStyle(color: Color(0xFF1AA251), fontSize: 8, fontWeight: FontWeight.w700)),
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
      case _Sec.viagem:
        _push(const ViagensPage());
      case _Sec.checklistSaida:
      case _Sec.checklistRetorno:
        _push(const SelecionarVeiculoChecklistPage());
      case _Sec.abastecimentos:
        _push(const AbastecimentosPage());
      case _Sec.manutencoes:
        _push(const ManutencoesPage());
      case _Sec.ocorrencias:
        _push(const ListaOcorrenciasPage());
      case _Sec.documentos:
        _push(const DocumentosPage());
    }
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => _carregar());

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

  // ── Dashboard ─────────────────────────────────────────────────────────────

  Widget _buildDashboard(AppAuthProvider auth, String primeiroNome) {
    final hora = DateTime.now().hour;
    final String saudacao;
    if (hora < 12) {
      saudacao = 'Bom dia';
    } else if (hora < 18) {
      saudacao = 'Boa tarde';
    } else {
      saudacao = 'Boa noite';
    }

    final now = DateTime.now();
    final dataStr =
        '${_semana[now.weekday - 1]}, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return RefreshIndicator(
      color: const Color(0xFF1AA251),
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$saudacao, $primeiroNome!',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(dataStr, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Cartão do Veículo (destaque máximo) ───────────────────────
            _buildVeiculoCard(destaque: true),
            const SizedBox(height: 16),

            // ── KPIs do dia ────────────────────────────────────────────────
            Row(
              children: [
                _kpi('Checklists Hoje', '$_checklistsHoje', Icons.checklist_rounded, const Color(0xFF1AA251)),
                const SizedBox(width: 12),
                _kpi('Ocorrências Abertas', '$_ocorrenciasAbertas', Icons.report_problem_rounded,
                    _ocorrenciasAbertas > 0 ? const Color(0xFFEF4444) : const Color(0xFF475569)),
              ],
            ),
            const SizedBox(height: 20),

            // ── Ações rápidas ──────────────────────────────────────────────
            _sectionTitle('Ações Rápidas'),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                _acao(Icons.checklist_rtl_rounded, 'Checklist\nSaída', const Color(0xFF1AA251), () => _onTap(_Sec.checklistSaida)),
                _acao(Icons.assignment_turned_in_rounded, 'Checklist\nRetorno', const Color(0xFF3B82F6), () => _onTap(_Sec.checklistRetorno)),
                _acao(Icons.route_rounded, 'Minha\nViagem', const Color(0xFF8B5CF6), () => _onTap(_Sec.viagem)),
                _acao(Icons.local_gas_station_rounded, 'Abastecer', const Color(0xFFF59E0B), () => _onTap(_Sec.abastecimentos)),
                _acao(Icons.build_rounded, 'Manutenção', const Color(0xFFEC4899), () => _onTap(_Sec.manutencoes)),
                _acao(Icons.report_problem_rounded, 'Ocorrência', const Color(0xFFEF4444), () => _onTap(_Sec.ocorrencias)),
              ],
            ),
            const SizedBox(height: 20),

            // ── Alertas do veículo ─────────────────────────────────────────
            if (_alertas.isNotEmpty) ...[
              _sectionTitle('Alertas do Meu Veículo'),
              const SizedBox(height: 10),
              ..._alertas.map(_alertaCard),
              const SizedBox(height: 20),
            ],

            // ── Atividade recente ──────────────────────────────────────────
            _sectionTitle('Atividade Recente'),
            const SizedBox(height: 10),
            if (_ultimoAbastecimento != null)
              _atividadeCard(
                icon: Icons.local_gas_station_rounded,
                cor: const Color(0xFFF59E0B),
                titulo: 'Último Abastecimento',
                subtitulo: _placaLabel(_ultimoAbastecimento!),
                extra: _ultimoAbastecimento!['liters'] != null ? '${_ultimoAbastecimento!['liters']} L' : null,
                data: _ultimoAbastecimento!['created_at']?.toString(),
              )
            else
              _vazio('Nenhum abastecimento registrado.'),
            const SizedBox(height: 6),
            if (_ultimaManutencao != null)
              _atividadeCard(
                icon: Icons.build_rounded,
                cor: const Color(0xFFEC4899),
                titulo: 'Última Troca de Óleo',
                subtitulo: 'Próxima troca: ${_ultimaManutencao!['next_change_km'] ?? '—'} km',
                extra: null,
                data: _ultimaManutencao!['created_at']?.toString(),
              )
            else
              _vazio('Nenhuma manutenção registrada.'),

            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () => _push(const HistoricoChecklistPage()),
                icon: const Icon(Icons.history_rounded, size: 14, color: Color(0xFF1AA251)),
                label: const Text('Ver histórico de checklists',
                    style: TextStyle(color: Color(0xFF1AA251), fontSize: 12)),
              ),
            ),
          ],
        ),
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
          const Text('Meu Veículo',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          _buildVeiculoCard(destaque: false),
          if (_veiculo != null) ...[
            const SizedBox(height: 20),
            _sectionTitle('Última Manutenção'),
            const SizedBox(height: 10),
            if (_ultimaManutencao != null)
              _atividadeCard(
                icon: Icons.build_rounded,
                cor: const Color(0xFFEC4899),
                titulo: 'Última Troca de Óleo',
                subtitulo: 'Próxima troca: ${_ultimaManutencao!['next_change_km'] ?? '—'} km',
                extra: null,
                data: _ultimaManutencao!['created_at']?.toString(),
              )
            else
              _vazio('Nenhuma manutenção registrada para este veículo.'),
            const SizedBox(height: 20),
            _sectionTitle('Alertas Ativos'),
            const SizedBox(height: 10),
            if (_alertas.isNotEmpty)
              ..._alertas.map(_alertaCard)
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Meu Perfil',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
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
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF1AA251).withOpacity(0.18),
                      child: Text(
                        ((p?.nome ?? p?.email) ?? 'M')[0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFF1AA251), fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p?.nome ?? 'Sem nome',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(p?.email ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1AA251).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF1AA251).withOpacity(0.30)),
                            ),
                            child: const Text('MOTORISTA',
                                style: TextStyle(color: Color(0xFF1AA251), fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(color: AppColors.border),
                const SizedBox(height: 10),
                _infoRow('Empresa', p?.empresaNome ?? '—'),
                _infoRow('Status', p?.status ?? '—'),
                _infoRow(
                  'Veículo Vinculado',
                  _veiculo != null
                      ? '${_veiculo!['plate'] ?? ''} — ${_veiculo!['brand'] ?? ''} ${_veiculo!['model'] ?? ''}'.trim()
                      : 'Nenhum',
                ),
                if (p?.lastAccess != null)
                  _infoRow('Último acesso', _dataFull(p!.lastAccess!.toLocal())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Cartão de Veículo ─────────────────────────────────────────────────────

  Widget _buildVeiculoCard({required bool destaque}) {
    if (_loadingVeiculo) {
      return _cardBase(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: Color(0xFF1AA251), strokeWidth: 2),
          ),
        ),
      );
    }

    if (_veiculo == null) {
      return _cardBase(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF475569).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_car_outlined, color: Color(0xFF475569), size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nenhum veículo vinculado',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(
                      'Solicite ao gestor ou admin da empresa que vincule um veículo ao seu perfil.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final placa = _veiculo!['plate']?.toString() ?? '—';
    final modelo = '${_veiculo!['brand'] ?? ''} ${_veiculo!['model'] ?? ''}'.trim();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.directions_car_rounded, color: cor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (destaque)
                        const Text('MEU VEÍCULO',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      Text(placa,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
                      Text('$modelo${ano.isNotEmpty ? "  •  $ano" : ""}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cor.withOpacity(0.35)),
                      ),
                      child: Text(status.toUpperCase(),
                          style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    if (_alertas.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.30)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_rounded, color: Color(0xFFEF4444), size: 11),
                            const SizedBox(width: 4),
                            Text('${_alertas.length} alerta(s)',
                                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (modelo.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.directions_car_outlined, color: AppColors.textSecondary, size: 13),
                  const SizedBox(width: 6),
                  Text(modelo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _activeSection = _Sec.meuVeiculo),
                    child: const Text('Ver detalhes →',
                        style: TextStyle(color: Color(0xFF1AA251), fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ],
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

  Widget _kpi(String label, String valor, IconData icon, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: cor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: cor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(valor, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _acao(IconData icon, String label, Color cor, VoidCallback onTap) {
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
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: cor.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, color: cor, size: 20),
              ),
              const SizedBox(height: 7),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertaCard(Map<String, dynamic> alerta) {
    final prioridade = alerta['priority']?.toString() ?? 'Media';
    final cor = prioridade == 'Alta'
        ? const Color(0xFFEF4444)
        : prioridade == 'Media'
            ? const Color(0xFFF59E0B)
            : const Color(0xFF3B82F6);
    final titulo = alerta['problem_type']?.toString() ?? 'Alerta';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: cor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(titulo,
                style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Text(prioridade.toUpperCase(),
              style: TextStyle(color: cor, fontSize: 9, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _atividadeCard({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    String? extra,
    String? data,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: cor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                if (subtitulo.isNotEmpty)
                  Text(subtitulo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (extra != null)
                Text(extra, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w600)),
              if (data != null)
                Text(_dataCurta(data), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ],
          ),
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
      child: Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700));

  Widget _infoRow(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          Expanded(child: Text(valor, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
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
  dashboard, meuVeiculo, viagem,
  checklistSaida, checklistRetorno,
  abastecimentos, manutencoes, ocorrencias,
  documentos, perfil,
}

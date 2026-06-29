import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';

class MasterDashboardPage extends StatefulWidget {
  const MasterDashboardPage({super.key});

  @override
  State<MasterDashboardPage> createState() => _MasterDashboardPageState();
}

class _MasterDashboardPageState extends State<MasterDashboardPage> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _timer;

  bool _loading = true;
  DateTime? _lastUpdated;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Métricas
  int _totalEmpresas = 0;
  int _empresasAtivas = 0;
  int _empresasBloqueadas = 0;
  int _empresasOnline = 0;
  int _totalUsuarios = 0;
  int _totalVeiculos = 0;
  int _totalMotoristas = 0;
  int _totalAbastecimentos = 0;
  int _totalChecklists = 0;
  int _totalOcorrencias = 0;
  int _totalManutencoes = 0;
  double _mrr = 0;

  List<Map<String, dynamic>> _empresas = [];

  static const _planoPrices = {
    'basico': 99.0,
    'profissional': 199.0,
    'enterprise': 499.0,
  };

  @override
  void initState() {
    super.initState();
    _loadAll();
    _setupRealtime();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadAll());
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        _supabase.from('empresas').select(),
        _supabase.from('user_profiles').select('user_id'),
        _supabase.from('vehicles').select('id'),
        _supabase.from('drivers').select('id'),
        _supabase.from('fuelings').select('id'),
        _supabase.from('checklists').select('id'),
        _supabase.from('occurrences').select('id'),
        _supabase.from('manutencoes').select('id'),
        _supabase
            .from('user_profiles')
            .select('empresa_id')
            .not('empresa_id', 'is', null)
            .gte(
              'last_access',
              DateTime.now()
                  .subtract(const Duration(minutes: 30))
                  .toIso8601String(),
            ),
      ]);

      final empresas = List<Map<String, dynamic>>.from(results[0] as List);
      final onlineProfiles = List<Map<String, dynamic>>.from(results[8] as List);

      final onlineIds = onlineProfiles
          .map((p) => p['empresa_id'])
          .whereType<String>()
          .toSet();

      double mrr = 0;
      for (final e in empresas) {
        if (e['status'] == 'ativo') {
          mrr += _planoPrices[e['plano'] ?? 'basico'] ?? 99.0;
        }
      }

      if (!mounted) return;
      setState(() {
        _empresas = empresas;
        _totalEmpresas = empresas.length;
        _empresasAtivas = empresas.where((e) => e['status'] == 'ativo').length;
        _empresasBloqueadas = empresas
            .where((e) => e['status'] == 'suspenso' || e['status'] == 'cancelado')
            .length;
        _empresasOnline = onlineIds.length;
        _totalUsuarios = (results[1] as List).length;
        _totalVeiculos = (results[2] as List).length;
        _totalMotoristas = (results[3] as List).length;
        _totalAbastecimentos = (results[4] as List).length;
        _totalChecklists = (results[5] as List).length;
        _totalOcorrencias = (results[6] as List).length;
        _totalManutencoes = (results[7] as List).length;
        _mrr = mrr;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      debugPrint('MasterDashboard._loadAll error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setupRealtime() {
    _channel = _supabase
        .channel('master_dashboard')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'empresas',
          callback: (_) => _loadAll(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_profiles',
          callback: (_) => _loadAll(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _timer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _empresasFiltradas {
    if (_searchQuery.isEmpty) return _empresas;
    final q = _searchQuery.toLowerCase();
    return _empresas
        .where((e) =>
            (e['nome'] as String? ?? '').toLowerCase().contains(q) ||
            (e['cnpj'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C18),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  // ── Sidebar ──────────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF080F1E),
        border: Border(right: BorderSide(color: Color(0xFF0E1E33))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FrotaCheck',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    Text('MASTER',
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFF0E1E33)),
          const SizedBox(height: 8),

          // Nav
          _sidebarItem(Icons.dashboard_rounded, 'Painel Geral', active: true),
          const Spacer(),

          // Stats resumidas
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1628),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resumo',
                    style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                _resumoItem(Icons.business_rounded, '$_empresasAtivas ativas',
                    const Color(0xFF22C55E)),
                const SizedBox(height: 4),
                _resumoItem(
                    Icons.wifi_rounded,
                    '$_empresasOnline online',
                    _empresasOnline > 0
                        ? const Color(0xFF10B981)
                        : const Color(0xFF334155)),
                const SizedBox(height: 4),
                _resumoItem(Icons.trending_up_rounded,
                    'R\$ ${_mrr.toStringAsFixed(0)}/mês', const Color(0xFF3B82F6)),
              ],
            ),
          ),

          Container(height: 1, color: const Color(0xFF0E1E33)),
          // Logout
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.read<AppAuthProvider>().signOut(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded,
                        color: Color(0xFFEF4444), size: 17),
                    SizedBox(width: 10),
                    Text('Sair',
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, {bool active = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: active
          ? BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: const Color(0xFFEF4444).withOpacity(0.22)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon,
                color: active
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF475569),
                size: 17),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }

  Widget _resumoItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ── Conteúdo principal ────────────────────────────────────────────────────────

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildKpiGrid(),
                const SizedBox(height: 32),
                _buildEmpresasSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final hora = _lastUpdated == null
        ? ''
        : '${_lastUpdated!.hour.toString().padLeft(2, '0')}:'
            '${_lastUpdated!.minute.toString().padLeft(2, '0')}:'
            '${_lastUpdated!.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF080F1E),
        border:
            Border(bottom: BorderSide(color: Color(0xFF0E1E33))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _empresasOnline > 0
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF334155),
                      shape: BoxShape.circle,
                      boxShadow: _empresasOnline > 0
                          ? [
                              BoxShadow(
                                color:
                                    const Color(0xFF22C55E).withOpacity(0.5),
                                blurRadius: 6,
                              )
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Painel Master',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 2),
              const Text('Visão global do sistema FrotaCheck',
                  style:
                      TextStyle(color: Color(0xFF475569), fontSize: 13)),
            ],
          ),
          const Spacer(),
          if (hora.isNotEmpty)
            Text('Atualizado $hora',
                style: const TextStyle(
                    color: Color(0xFF334155), fontSize: 11)),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF475569), size: 20),
            tooltip: 'Atualizar agora',
          ),
        ],
      ),
    );
  }

  // ── KPI Grid ─────────────────────────────────────────────────────────────────

  Widget _buildKpiGrid() {
    final cards = [
      _Kpi('Total Empresas', '$_totalEmpresas', Icons.business_rounded,
          const Color(0xFF3B82F6)),
      _Kpi('Empresas Ativas', '$_empresasAtivas', Icons.check_circle_rounded,
          const Color(0xFF22C55E)),
      _Kpi('Bloqueadas/Suspensas', '$_empresasBloqueadas',
          Icons.block_rounded, const Color(0xFFEF4444)),
      _Kpi('Online Agora', '$_empresasOnline', Icons.wifi_rounded,
          const Color(0xFF10B981),
          pulse: _empresasOnline > 0),
      _Kpi('Total Usuários', '$_totalUsuarios', Icons.people_rounded,
          const Color(0xFF8B5CF6)),
      _Kpi('Total Veículos', '$_totalVeiculos',
          Icons.directions_car_rounded, const Color(0xFFF59E0B)),
      _Kpi('Total Motoristas', '$_totalMotoristas', Icons.badge_rounded,
          const Color(0xFF06B6D4)),
      _Kpi('Abastecimentos', '$_totalAbastecimentos',
          Icons.local_gas_station_rounded, const Color(0xFFEC4899)),
      _Kpi('Checklists', '$_totalChecklists', Icons.checklist_rounded,
          const Color(0xFF14B8A6)),
      _Kpi('Ocorrências', '$_totalOcorrencias', Icons.warning_amber_rounded,
          const Color(0xFFF97316)),
      _Kpi('Manutenções', '$_totalManutencoes', Icons.build_rounded,
          const Color(0xFF64748B)),
      _Kpi('MRR', 'R\$ ${_mrr.toStringAsFixed(0)}',
          Icons.trending_up_rounded, const Color(0xFF22C55E)),
      _Kpi('Receita Anual',
          'R\$ ${(_mrr * 12).toStringAsFixed(0)}',
          Icons.account_balance_wallet_rounded, const Color(0xFF3B82F6)),
    ];

    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < 700
          ? 2
          : c.maxWidth < 1100
              ? 3
              : 4;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.85,
        ),
        itemCount: cards.length,
        itemBuilder: (_, i) => _buildKpiCard(cards[i]),
      );
    });
  }

  Widget _buildKpiCard(_Kpi k) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: k.color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: k.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(k.icon, color: k.color, size: 15),
              ),
              if (k.pulse) ...[
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: k.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: k.color.withOpacity(0.6),
                          blurRadius: 6)
                    ],
                  ),
                ),
              ],
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k.value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(k.label,
                  style: const TextStyle(
                      color: Color(0xFF64748B), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empresas ──────────────────────────────────────────────────────────────────

  Widget _buildEmpresasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Empresas',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFF3B82F6).withOpacity(0.3)),
              ),
              child: Text('$_totalEmpresas',
                  style: const TextStyle(
                      color: Color(0xFF3B82F6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Barra de pesquisa
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF080F1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            style:
                const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Pesquisar por nome ou CNPJ...',
              hintStyle:
                  TextStyle(color: Color(0xFF334155), fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Color(0xFF334155), size: 18),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Tabela
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF080F1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0E1E33)),
          ),
          child: Column(
            children: [
              _tableHeader(),
              Container(height: 1, color: const Color(0xFF0E1E33)),
              if (_empresasFiltradas.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'Nenhuma empresa cadastrada ainda.'
                        : 'Nenhuma empresa encontrada para "$_searchQuery".',
                    style: const TextStyle(
                        color: Color(0xFF334155), fontSize: 13),
                  ),
                )
              else
                ...List.generate(_empresasFiltradas.length, (i) {
                  final e = _empresasFiltradas[i];
                  return Column(
                    children: [
                      _companyRow(e),
                      if (i < _empresasFiltradas.length - 1)
                        Container(
                            height: 1,
                            color: const Color(0xFF0A1628)),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableHeader() {
    const style = TextStyle(
        color: Color(0xFF475569),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5);
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: const [
          Expanded(flex: 3, child: Text('EMPRESA', style: style)),
          Expanded(flex: 2, child: Text('PLANO', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          Expanded(flex: 2, child: Text('CADASTRO', style: style)),
          SizedBox(width: 150, child: Text('AÇÕES', style: style)),
        ],
      ),
    );
  }

  Widget _companyRow(Map<String, dynamic> empresa) {
    final nome = empresa['nome'] as String? ?? '—';
    final cnpj = empresa['cnpj'] as String? ?? '';
    final plano = empresa['plano'] as String? ?? 'basico';
    final status = empresa['status'] as String? ?? 'ativo';
    final createdAt = empresa['created_at'] as String?;

    DateTime? dt;
    if (createdAt != null) {
      try { dt = DateTime.parse(createdAt); } catch (_) {}
    }
    final dataCadastro = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
        : '—';

    final planoColor = _planoColor(plano);
    final statusColor = _statusColor(status);
    final inicial =
        nome.isNotEmpty ? nome[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Empresa
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        planoColor.withOpacity(0.3),
                        planoColor.withOpacity(0.1)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: planoColor.withOpacity(0.3)),
                  ),
                  alignment: Alignment.center,
                  child: Text(inicial,
                      style: TextStyle(
                          color: planoColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                      if (cnpj.isNotEmpty)
                        Text(cnpj,
                            style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Plano
          Expanded(
            flex: 2,
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: planoColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: planoColor.withOpacity(0.28)),
              ),
              child: Text(plano.toUpperCase(),
                  style: TextStyle(
                      color: planoColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
          ),

          // Status
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: statusColor.withOpacity(0.5),
                              blurRadius: 4)
                        ])),
                const SizedBox(width: 6),
                Text(status,
                    style: TextStyle(
                        color: statusColor, fontSize: 12)),
              ],
            ),
          ),

          // Cadastro
          Expanded(
            flex: 2,
            child: Text(dataCadastro,
                style: const TextStyle(
                    color: Color(0xFF64748B), fontSize: 12)),
          ),

          // Ações
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _enterAsEmpresa(empresa),
                    icon: const Icon(Icons.login_rounded, size: 13),
                    label: const Text('Entrar',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF3B82F6).withOpacity(0.15),
                      foregroundColor:
                          const Color(0xFF3B82F6),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                          side: BorderSide(
                              color: const Color(0xFF3B82F6)
                                  .withOpacity(0.3))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _enterAsEmpresa(Map<String, dynamic> empresa) {
    context.read<AppAuthProvider>().enterAsEmpresa(
          empresa['id'] as String,
          empresa['nome'] as String? ?? 'Empresa',
        );
    // _MasterAwareRouter detecta isImpersonating=true e exibe HomePage
  }

  Color _planoColor(String plano) => switch (plano) {
        'profissional' => const Color(0xFF3B82F6),
        'enterprise' => const Color(0xFF8B5CF6),
        _ => const Color(0xFF64748B),
      };

  Color _statusColor(String status) => switch (status) {
        'ativo' => const Color(0xFF22C55E),
        'suspenso' => const Color(0xFFF59E0B),
        'cancelado' || 'bloqueado' => const Color(0xFFEF4444),
        _ => const Color(0xFF64748B),
      };
}

// Data class
class _Kpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool pulse;

  const _Kpi(this.label, this.value, this.icon, this.color,
      {this.pulse = false});
}

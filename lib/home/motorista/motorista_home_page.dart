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
import '../viagens/viagens_page.dart';
import '../../pages/lista_ocorrencias_page.dart';

class MotoristaHomePage extends StatefulWidget {
  const MotoristaHomePage({super.key});

  @override
  State<MotoristaHomePage> createState() => _MotoristaHomePageState();
}

class _MotoristaHomePageState extends State<MotoristaHomePage> {
  final _supabase = Supabase.instance.client;

  _MenuSection _activeSection = _MenuSection.dashboard;

  // Dashboard state
  bool _loading = true;
  Map<String, dynamic>? _ultimoChecklist;
  Map<String, dynamic>? _ultimoAbastecimento;
  int _ocorrenciasAbertas = 0;
  int _checklistsHoje = 0;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    final auth = context.read<AppAuthProvider>();
    if (auth.empresaId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final hoje = DateTime.now();
      final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();

      final results = await Future.wait([
        // Último checklist deste usuário
        _supabase
            .from('checklists')
            .select('id, created_at, status, veiculo_id, veiculos(placa, modelo)')
            .eq('empresa_id', auth.empresaId!)
            .eq('motorista_id', auth.profile!.userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle()
            .catchError((_) => null),

        // Último abastecimento deste usuário
        _supabase
            .from('abastecimentos')
            .select('id, created_at, litros, valor_total, veiculo_id, veiculos(placa)')
            .eq('empresa_id', auth.empresaId!)
            .eq('motorista_id', auth.profile!.userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle()
            .catchError((_) => null),

        // Ocorrências abertas
        _supabase
            .from('ocorrencias')
            .select('id')
            .eq('empresa_id', auth.empresaId!)
            .eq('motorista_id', auth.profile!.userId)
            .eq('status', 'aberto')
            .count()
            .catchError((_) => null),

        // Checklists de hoje
        _supabase
            .from('checklists')
            .select('id')
            .eq('empresa_id', auth.empresaId!)
            .eq('motorista_id', auth.profile!.userId)
            .gte('created_at', inicioHoje)
            .count()
            .catchError((_) => null),
      ]);

      if (!mounted) return;
      setState(() {
        _ultimoChecklist = results[0] as Map<String, dynamic>?;
        _ultimoAbastecimento = results[1] as Map<String, dynamic>?;

        final occResult = results[2];
        if (occResult is Map && occResult['count'] != null) {
          _ocorrenciasAbertas = occResult['count'] as int? ?? 0;
        }

        final ckResult = results[3];
        if (ckResult is Map && ckResult['count'] != null) {
          _checklistsHoje = ckResult['count'] as int? ?? 0;
        }

        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

  // ── Sidebar ────────────────────────────────────────────────────────────────

  Widget _buildSidebar(AppAuthProvider auth, String nome) {
    return Container(
      width: 200,
      color: AppColors.surface,
      child: Column(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
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
                      Text('Motorista', style: TextStyle(color: Color(0xFF1AA251), fontSize: 10, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: const Color(0xFF0E1E33)),
          const SizedBox(height: 8),

          // Menu
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _menuItem(Icons.dashboard_rounded, 'Dashboard', _MenuSection.dashboard),
                  _menuItem(Icons.route_rounded, 'Minha Viagem', _MenuSection.viagem),
                  const SizedBox(height: 4),
                  _sectionLabel('OPERAÇÕES'),
                  _menuItem(Icons.checklist_rtl_rounded, 'Checklist Saída', _MenuSection.checklistSaida),
                  _menuItem(Icons.assignment_turned_in_rounded, 'Checklist Retorno', _MenuSection.checklistRetorno),
                  _menuItem(Icons.local_gas_station_rounded, 'Abastecimentos', _MenuSection.abastecimentos),
                  _menuItem(Icons.report_problem_rounded, 'Ocorrências', _MenuSection.ocorrencias),
                  _menuItem(Icons.description_rounded, 'Documentos', _MenuSection.documentos),
                  const Spacer(),
                  _menuItem(Icons.person_rounded, 'Meu Perfil', _MenuSection.perfil),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),

          // Footer
          Container(height: 1, color: const Color(0xFF0E1E33)),
          _buildLogoutButton(auth),
          _buildProfileCard(auth, nome),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 4),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFF475569), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }

  Widget _menuItem(IconData icon, String label, _MenuSection section) {
    final active = _activeSection == section;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onMenuTap(section),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: active
              ? BoxDecoration(
                  color: const Color(0xFF1AA251).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1AA251).withOpacity(0.30)),
                )
              : null,
          child: Row(
            children: [
              Icon(icon,
                  color: active ? const Color(0xFF1AA251) : const Color(0xFF475569),
                  size: 16),
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

  Widget _buildLogoutButton(AppAuthProvider auth) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final confirm = await showDialog<bool>(
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
          if (confirm == true && mounted) {
            await auth.signOut();
          }
        },
        child: const Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 15),
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
            radius: 14,
            backgroundColor: const Color(0xFF1AA251).withOpacity(0.18),
            child: Text(
              nome.isNotEmpty ? nome[0].toUpperCase() : 'M',
              style: const TextStyle(color: Color(0xFF1AA251), fontSize: 12, fontWeight: FontWeight.w700),
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
                  child: const Text('MOTORISTA', style: TextStyle(color: Color(0xFF1AA251), fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Content area ──────────────────────────────────────────────────────────

  Widget _buildContent(AppAuthProvider auth, String primeiroNome) {
    if (_activeSection == _MenuSection.dashboard) {
      return _buildDashboard(auth, primeiroNome);
    }
    // Perfil inline
    if (_activeSection == _MenuSection.perfil) {
      return _buildPerfil(auth);
    }
    return _buildDashboard(auth, primeiroNome);
  }

  void _onMenuTap(_MenuSection section) {
    switch (section) {
      case _MenuSection.dashboard:
      case _MenuSection.perfil:
        setState(() => _activeSection = section);

      case _MenuSection.viagem:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ViagensPage()))
            .then((_) => _carregarDados());

      case _MenuSection.checklistSaida:
      case _MenuSection.checklistRetorno:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SelecionarVeiculoChecklistPage()))
            .then((_) => _carregarDados());

      case _MenuSection.abastecimentos:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AbastecimentosPage()))
            .then((_) => _carregarDados());

      case _MenuSection.ocorrencias:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaOcorrenciasPage()))
            .then((_) => _carregarDados());

      case _MenuSection.documentos:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentosPage()))
            .then((_) => _carregarDados());
    }
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  Widget _buildDashboard(AppAuthProvider auth, String primeiroNome) {
    final now = DateTime.now();
    final hora = now.hour;
    final String saudacao;
    if (hora < 12) {
      saudacao = 'Bom dia';
    } else if (hora < 18) {
      saudacao = 'Boa tarde';
    } else {
      saudacao = 'Boa noite';
    }

    final dataStr =
        '${_diasSemana[now.weekday - 1]}, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$saudacao, $primeiroNome!',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(dataStr,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _carregarDados,
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                tooltip: 'Atualizar',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── KPI cards ───────────────────────────────────────────────────
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF1AA251)))
          else ...[
            Row(
              children: [
                _kpiCard('Checklists Hoje', '$_checklistsHoje', Icons.checklist_rounded, const Color(0xFF1AA251)),
                const SizedBox(width: 12),
                _kpiCard('Ocorrências Abertas', '$_ocorrenciasAbertas',
                    Icons.report_problem_rounded,
                    _ocorrenciasAbertas > 0 ? const Color(0xFFEF4444) : const Color(0xFF475569)),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ── Ações rápidas ────────────────────────────────────────────────
          const Text('Ações Rápidas',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _acaoCard(Icons.checklist_rtl_rounded, 'Checklist\nSaída', const Color(0xFF1AA251),
                  () => _onMenuTap(_MenuSection.checklistSaida)),
              _acaoCard(Icons.assignment_turned_in_rounded, 'Checklist\nRetorno', const Color(0xFF3B82F6),
                  () => _onMenuTap(_MenuSection.checklistRetorno)),
              _acaoCard(Icons.local_gas_station_rounded, 'Registrar\nAbastecimento', const Color(0xFFF59E0B),
                  () => _onMenuTap(_MenuSection.abastecimentos)),
              _acaoCard(Icons.report_problem_rounded, 'Registrar\nOcorrência', const Color(0xFFEF4444),
                  () => _onMenuTap(_MenuSection.ocorrencias)),
            ],
          ),
          const SizedBox(height: 24),

          // ── Último checklist ────────────────────────────────────────────
          const Text('Última Atividade',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_ultimoChecklist != null) ...[
            _atividadeCard(
              icon: Icons.checklist_rounded,
              cor: const Color(0xFF1AA251),
              titulo: 'Último Checklist',
              subtitulo: _veiculoLabel(_ultimoChecklist!),
              data: _ultimoChecklist!['created_at']?.toString(),
              status: _ultimoChecklist!['status']?.toString(),
            ),
            const SizedBox(height: 8),
          ] else
            _cardVazio('Nenhum checklist registrado ainda.'),

          if (_ultimoAbastecimento != null) ...[
            _atividadeCard(
              icon: Icons.local_gas_station_rounded,
              cor: const Color(0xFFF59E0B),
              titulo: 'Último Abastecimento',
              subtitulo: _veiculoLabel(_ultimoAbastecimento!),
              data: _ultimoAbastecimento!['created_at']?.toString(),
              status: _ultimoAbastecimento!['litros'] != null
                  ? '${_ultimoAbastecimento!['litros']} L'
                  : null,
            ),
          ] else if (_ultimoChecklist == null)
            const SizedBox.shrink()
          else
            _cardVazio('Nenhum abastecimento registrado ainda.'),

          const SizedBox(height: 32),

          // ── Link para histórico ──────────────────────────────────────────
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HistoricoChecklistPage())),
              icon: const Icon(Icons.history_rounded, size: 15, color: Color(0xFF1AA251)),
              label: const Text('Ver histórico completo de checklists',
                  style: TextStyle(color: Color(0xFF1AA251), fontSize: 12)),
            ),
          ),
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
          const SizedBox(height: 24),
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
                      radius: 30,
                      backgroundColor: const Color(0xFF1AA251).withOpacity(0.18),
                      child: Text(
                        (p?.nome ?? p?.email ?? 'M')[0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFF1AA251), fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p?.nome ?? 'Sem nome',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(p?.email ?? '',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1AA251).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF1AA251).withOpacity(0.30)),
                            ),
                            child: const Text('MOTORISTA',
                                style: TextStyle(color: Color(0xFF1AA251), fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: AppColors.border),
                const SizedBox(height: 12),
                _perfilInfo('Empresa', p?.empresaNome ?? '—'),
                _perfilInfo('Status', p?.status ?? '—'),
                if (p?.lastAccess != null)
                  _perfilInfo('Último acesso', _formatData(p!.lastAccess!.toLocal())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _kpiCard(String label, String valor, IconData icon, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: cor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(valor,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  Text(label,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _acaoCard(IconData icon, String label, Color cor, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.25)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: cor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _atividadeCard({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    String? data,
    String? status,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: cor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitulo,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (status != null)
                Text(status,
                    style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w600)),
              if (data != null)
                Text(_formatDataCurta(data),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardVazio(String msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }

  Widget _perfilInfo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _veiculoLabel(Map<String, dynamic> record) {
    final v = record['veiculos'];
    if (v is Map) {
      final placa = v['placa']?.toString() ?? '';
      final modelo = v['modelo']?.toString() ?? '';
      if (placa.isNotEmpty) return '$placa${modelo.isNotEmpty ? " — $modelo" : ""}';
    }
    return 'Veículo não identificado';
  }

  String _formatData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _formatDataCurta(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  static const List<String> _diasSemana = [
    'Segunda-feira', 'Terça-feira', 'Quarta-feira',
    'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo',
  ];
}

enum _MenuSection {
  dashboard,
  viagem,
  checklistSaida,
  checklistRetorno,
  abastecimentos,
  ocorrencias,
  documentos,
  perfil,
}

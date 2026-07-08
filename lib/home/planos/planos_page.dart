import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/plano_financeiro.dart';
import '../../core/utils/snackbar_utils.dart';

class PlanosPage extends StatefulWidget {
  const PlanosPage({super.key});

  @override
  State<PlanosPage> createState() => _PlanosPageState();
}

class _PlanosPageState extends State<PlanosPage> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _debounce;

  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _assinaturas = [];
  List<Map<String, dynamic>> _empresasSemAssinatura = [];
  bool _loading = true;

  String? _filtroPlanoId;
  String _filtroStatus = 'todos';
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    if (context.read<AppAuthProvider>().isMaster) {
      _carregar();
      _setupRealtime();
    } else {
      _loading = false;
    }
    _buscaCtrl.addListener(() => setState(() => _busca = _buscaCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _debounceCarregar() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _carregar);
  }

  void _setupRealtime() {
    _channel = _supabase
        .channel('planos_page_rt')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'assinaturas',
          callback: (_) => _debounceCarregar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'planos',
          callback: (_) => _debounceCarregar(),
        )
        .subscribe();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supabase.from('planos').select().order('ordem'),
        _supabase.from('assinaturas').select('*, empresas(nome), planos(id, codigo, nome, valor_mensal, limite_veiculos)'),
        _supabase.from('empresas').select('id, nome').order('nome'),
      ]);
      final planos = List<Map<String, dynamic>>.from((results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      final assinaturas = List<Map<String, dynamic>>.from((results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      final empresas = List<Map<String, dynamic>>.from((results[2] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      final comAssinatura = assinaturas.map((a) => a['empresa_id']?.toString()).whereType<String>().toSet();
      final semAssinatura = empresas.where((e) => !comAssinatura.contains(e['id']?.toString())).toList();

      if (!mounted) return;
      setState(() {
        _planos = planos;
        _assinaturas = assinaturas;
        _empresasSemAssinatura = semAssinatura;
        _loading = false;
      });
    } catch (e) {
      debugPrint('PlanosPage._carregar error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _assinaturasFiltradas {
    return _assinaturas.where((a) {
      if (_filtroPlanoId != null && a['plano_id']?.toString() != _filtroPlanoId) return false;
      if (_filtroStatus != 'todos' && (a['status'] ?? '').toString() != _filtroStatus) return false;
      if (_busca.isNotEmpty) {
        final nome = (a['empresas'] is Map ? (a['empresas'] as Map)['nome'] : '')?.toString().toLowerCase() ?? '';
        if (!nome.contains(_busca)) return false;
      }
      return true;
    }).toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.isMaster) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Acesso restrito ao MASTER', style: TextStyle(color: Colors.white))),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Planos'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.danger))
          : LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Assinaturas das empresas',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    const Text('Receita real dos planos vendidos, sincronizada com o painel principal.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 18),
                    _buildResumoFinanceiro(),
                    const SizedBox(height: 24),
                    const Text('Planos disponíveis',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    _buildPlanosGrid(),
                    if (_empresasSemAssinatura.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildEmpresasSemAssinatura(),
                    ],
                    const SizedBox(height: 24),
                    _buildFiltros(),
                    const SizedBox(height: 12),
                    isWide ? _buildTabelaDesktop() : _buildListaMobile(),
                  ],
                ),
              );
            }),
    );
  }

  // ── Resumo financeiro ─────────────────────────────────────────────────────
  Widget _buildResumoFinanceiro() {
    final fin = calcularFinanceiroPlanos(_assinaturas);
    final cards = [
      _ResumoCard('Receita Mensal', _fmtReal(fin.mrr), Icons.payments_outlined, const Color(0xFF22C55E)),
      _ResumoCard('Receita Anual', _fmtReal(fin.arr), Icons.bar_chart_rounded, const Color(0xFF3B82F6)),
      _ResumoCard('Empresas Ativas', '${fin.empresasAtivas}', Icons.group_rounded, const Color(0xFF8B5CF6)),
      _ResumoCard('Ticket Médio', _fmtReal(fin.ticketMedio), Icons.trending_up_rounded, const Color(0xFFF59E0B)),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) => Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: c.color.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Icon(c.icon, color: c.color, size: 17),
            ),
          ]),
          const SizedBox(height: 12),
          Text(c.value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(c.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      )).toList(),
    );
  }

  // ── Grid de planos ────────────────────────────────────────────────────────
  Widget _buildPlanosGrid() {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: _planos.map((p) {
        final planoId = p['id']?.toString();
        final codigo = (p['codigo'] ?? '').toString();
        final cor = _corPlano(codigo);
        final doPlano = _assinaturas.where((a) => a['plano_id']?.toString() == planoId).toList();
        final vinculadas = doPlano.where((a) => (a['status'] ?? '') != 'cancelado').length;
        final receita = doPlano
            .where((a) => (a['status'] ?? '') == 'ativo')
            .fold(0.0, (s, a) => s + ((a['valor_mensal'] as num?)?.toDouble() ?? 0));
        final valorCatalogo = (p['valor_mensal'] as num?)?.toDouble();
        final limite = (p['limite_veiculos'] as num?)?.toInt();
        final selecionado = _filtroPlanoId == planoId;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _filtroPlanoId = selecionado ? null : planoId),
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selecionado ? cor : AppColors.border, width: selecionado ? 1.6 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: cor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text((p['nome'] ?? codigo).toString(),
                      style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                const Spacer(),
                if (selecionado) Icon(Icons.filter_alt_rounded, color: cor, size: 15),
              ]),
              const SizedBox(height: 12),
              Text(
                valorCatalogo != null ? _fmtReal(valorCatalogo) : 'Sob consulta',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (valorCatalogo != null)
                const Text('/mês', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 8),
              Text(
                limite != null ? 'Até $limite veículos' : 'Veículos personalizado',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              if ((p['descricao'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text((p['descricao']).toString(),
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$vinculadas', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const Text('empresas vinculadas', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  ]),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_fmtReal(receita), style: const TextStyle(color: Color(0xFF22C55E), fontSize: 15, fontWeight: FontWeight.w700)),
                    const Text('receita gerada', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  ]),
                ),
              ]),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Empresas sem assinatura ───────────────────────────────────────────────
  Widget _buildEmpresasSemAssinatura() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.report_problem_rounded, color: Color(0xFFF59E0B), size: 16),
          const SizedBox(width: 8),
          Text('${_empresasSemAssinatura.length} empresa(s) sem plano atribuído',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        ..._empresasSemAssinatura.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text((e['nome'] ?? '—').toString(), style: const TextStyle(color: Colors.white, fontSize: 13))),
            TextButton(
              onPressed: () => _showAssinaturaDialog(empresaId: e['id'].toString(), empresaNome: (e['nome'] ?? '').toString()),
              child: const Text('Atribuir plano', style: TextStyle(color: Color(0xFFF59E0B))),
            ),
          ]),
        )),
      ]),
    );
  }

  // ── Filtros ────────────────────────────────────────────────────────────────
  Widget _buildFiltros() {
    Widget chip(String label, String value) {
      final ativo = _filtroStatus == value;
      return ChoiceChip(
        label: Text(label),
        selected: ativo,
        onSelected: (_) => setState(() => _filtroStatus = value),
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.danger.withOpacity(0.18),
        labelStyle: TextStyle(color: ativo ? Colors.white : AppColors.textSecondary, fontSize: 12),
        side: BorderSide(color: ativo ? AppColors.danger : AppColors.border),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _buscaCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar empresa...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 18),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.danger)),
            ),
          ),
        ),
        chip('Todos', 'todos'),
        chip('Ativo', 'ativo'),
        chip('Inadimplente', 'inadimplente'),
        chip('Cancelado', 'cancelado'),
        if (_filtroPlanoId != null)
          ActionChip(
            label: const Text('Limpar filtro de plano'),
            avatar: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
            backgroundColor: AppColors.danger.withOpacity(0.18),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
            onPressed: () => setState(() => _filtroPlanoId = null),
          ),
      ],
    );
  }

  // ── Tabela (desktop) ──────────────────────────────────────────────────────
  Widget _buildTabelaDesktop() {
    final lista = _assinaturasFiltradas;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('EMPRESA', style: _headStyle)),
            Expanded(flex: 2, child: Text('PLANO', style: _headStyle)),
            Expanded(flex: 2, child: Text('VALOR', style: _headStyle)),
            Expanded(flex: 2, child: Text('STATUS', style: _headStyle)),
            Expanded(flex: 2, child: Text('VENCIMENTO', style: _headStyle)),
            Expanded(flex: 2, child: Text('PRÓX. COBRANÇA', style: _headStyle)),
            SizedBox(width: 48),
          ]),
        ),
        if (lista.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text('Nenhuma assinatura encontrada.', style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...lista.map((a) => _linhaDesktop(a)),
      ]),
    );
  }

  Widget _linhaDesktop(Map<String, dynamic> a) {
    final empresaNome = (a['empresas'] is Map ? (a['empresas'] as Map)['nome'] : null)?.toString() ?? '—';
    final planoNome = (a['planos'] is Map ? (a['planos'] as Map)['nome'] : null)?.toString() ?? '—';
    final codigo = (a['planos'] is Map ? (a['planos'] as Map)['codigo'] : null)?.toString() ?? '';
    final valor = (a['valor_mensal'] as num?)?.toDouble() ?? 0;
    final status = (a['status'] ?? 'ativo').toString();
    final vencDia = a['vencimento_dia'];

    return InkWell(
      onTap: () => _showAssinaturaDialog(assinatura: a),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Expanded(flex: 3, child: Text(empresaNome, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _corPlano(codigo).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(planoNome, style: TextStyle(color: _corPlano(codigo), fontSize: 11, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          )),
          Expanded(flex: 2, child: Text(_fmtReal(valor), style: const TextStyle(color: Colors.white, fontSize: 13))),
          Expanded(flex: 2, child: _statusPill(status)),
          Expanded(flex: 2, child: Text(vencDia != null ? 'Dia $vencDia' : '—', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          Expanded(flex: 2, child: Text(_fmtData(a['proxima_cobranca']), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          SizedBox(width: 48, child: IconButton(
            icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF64748B)),
            onPressed: () => _showAssinaturaDialog(assinatura: a),
          )),
        ]),
      ),
    );
  }

  // ── Lista (mobile) ────────────────────────────────────────────────────────
  Widget _buildListaMobile() {
    final lista = _assinaturasFiltradas;
    if (lista.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: Text('Nenhuma assinatura encontrada.', style: TextStyle(color: AppColors.textSecondary))),
      );
    }
    return Column(children: lista.map((a) {
      final empresaNome = (a['empresas'] is Map ? (a['empresas'] as Map)['nome'] : null)?.toString() ?? '—';
      final planoNome = (a['planos'] is Map ? (a['planos'] as Map)['nome'] : null)?.toString() ?? '—';
      final codigo = (a['planos'] is Map ? (a['planos'] as Map)['codigo'] : null)?.toString() ?? '';
      final valor = (a['valor_mensal'] as num?)?.toDouble() ?? 0;
      final status = (a['status'] ?? 'ativo').toString();

      return InkWell(
        onTap: () => _showAssinaturaDialog(assinatura: a),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(empresaNome, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
              _statusPill(status),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _corPlano(codigo).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(planoNome, style: TextStyle(color: _corPlano(codigo), fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text(_fmtReal(valor), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Text('/mês', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            Text('Vencimento: dia ${a['vencimento_dia'] ?? '—'}  •  Próxima cobrança: ${_fmtData(a['proxima_cobranca'])}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
      );
    }).toList());
  }

  Widget _statusPill(String status) {
    final cor = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(_statusLabel(status), style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  // ── Dialog: criar/editar assinatura ───────────────────────────────────────
  void _showAssinaturaDialog({Map<String, dynamic>? assinatura, String? empresaId, String? empresaNome}) {
    final eid = assinatura != null ? assinatura['empresa_id']?.toString() : empresaId;
    final eNome = assinatura != null
        ? ((assinatura['empresas'] is Map ? (assinatura['empresas'] as Map)['nome'] : null)?.toString() ?? '—')
        : (empresaNome ?? '—');
    if (eid == null || _planos.isEmpty) return;

    String planoId = assinatura?['plano_id']?.toString() ?? _planos.first['id'].toString();
    final planoInicial = _planos.firstWhere((p) => p['id'].toString() == planoId, orElse: () => _planos.first);
    final valorInicial = (assinatura?['valor_mensal'] as num?)?.toDouble()
        ?? (planoInicial['valor_mensal'] as num?)?.toDouble()
        ?? 0;
    final valorCtrl = TextEditingController(text: valorInicial.toStringAsFixed(2));
    String status = (assinatura?['status'] ?? 'ativo').toString();
    DateTime? proximaCobranca = DateTime.tryParse(assinatura?['proxima_cobranca']?.toString() ?? '');
    final vencimentoCtrl = TextEditingController(text: (assinatura?['vencimento_dia'] ?? 5).toString());
    final obsCtrl = TextEditingController(text: (assinatura?['observacoes'] ?? '').toString());
    bool saving = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
          title: Text(assinatura == null ? 'Atribuir plano' : 'Editar assinatura',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(eNome, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                const Text('Plano', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFF060C18), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1E293B))),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: planoId,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0F1C30),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: _planos.map((p) => DropdownMenuItem(value: p['id'].toString(), child: Text((p['nome'] ?? '').toString()))).toList(),
                      onChanged: (v) => setS(() {
                        planoId = v ?? planoId;
                        final p = _planos.firstWhere((pp) => pp['id'].toString() == planoId, orElse: () => _planos.first);
                        final cat = (p['valor_mensal'] as num?)?.toDouble();
                        if (cat != null) valorCtrl.text = cat.toStringAsFixed(2);
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _campo('Valor mensal (R\$) *', valorCtrl, hint: '149.90'),
                const SizedBox(height: 12),
                const Text('Status', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFF060C18), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1E293B))),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: status,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0F1C30),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 'ativo', child: Text('Ativo')),
                        DropdownMenuItem(value: 'inadimplente', child: Text('Inadimplente')),
                        DropdownMenuItem(value: 'cancelado', child: Text('Cancelado')),
                      ],
                      onChanged: (v) => setS(() => status = v ?? status),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _campo('Dia do vencimento', vencimentoCtrl, hint: '5')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Próxima cobrança', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: proximaCobranca ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            builder: (c, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(primary: Color(0xFFEF4444), surface: Color(0xFF0A1628)),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) setS(() => proximaCobranca = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(color: const Color(0xFF060C18), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1E293B))),
                          child: Text(_fmtData(proximaCobranca?.toIso8601String()), style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                _campo('Observações', obsCtrl, hint: 'Opcional'),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B)))),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final valor = double.tryParse(valorCtrl.text.trim().replaceAll(',', '.'));
                final vencimento = int.tryParse(vencimentoCtrl.text.trim());
                if (valor == null || valor < 0) { setS(() => error = 'Valor mensal inválido'); return; }
                setS(() { saving = true; error = null; });
                try {
                  final payload = <String, dynamic>{
                    'empresa_id': eid,
                    'plano_id': planoId,
                    'valor_mensal': valor,
                    'status': status,
                    'vencimento_dia': vencimento,
                    'proxima_cobranca': proximaCobranca?.toIso8601String().split('T')[0],
                    'observacoes': obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
                  };
                  if (assinatura == null) {
                    await _supabase.from('assinaturas').insert(payload);
                  } else {
                    await _supabase.from('assinaturas').update(payload).eq('id', assinatura['id']);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _carregar();
                } catch (e) {
                  setS(() { saving = false; error = friendlyError(e); });
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, {String hint = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
          filled: true, fillColor: const Color(0xFF060C18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF4444))),
        ),
      ),
    ]);
  }
}

const _headStyle = TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6);

class _ResumoCard {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _ResumoCard(this.label, this.value, this.icon, this.color);
}

Color _corPlano(String codigo) {
  switch (codigo) {
    case 'START': return const Color(0xFF3B82F6);
    case 'PRO': return const Color(0xFF8B5CF6);
    case 'BUSINESS': return const Color(0xFFF59E0B);
    case 'ENTERPRISE': return const Color(0xFFEC4899);
    default: return const Color(0xFF64748B);
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'ativo': return 'Ativo';
    case 'inadimplente': return 'Inadimplente';
    case 'cancelado': return 'Cancelado';
    default: return status;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'ativo': return const Color(0xFF22C55E);
    case 'inadimplente': return const Color(0xFFF59E0B);
    case 'cancelado': return const Color(0xFFEF4444);
    default: return const Color(0xFF64748B);
  }
}

String _fmtReal(double v) {
  final negativo = v < 0;
  final s = v.abs().toStringAsFixed(2);
  final partes = s.split('.');
  final intPart = partes[0];
  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${negativo ? '-' : ''}R\$ ${buf.toString()},${partes[1]}';
}

String _fmtData(dynamic raw) {
  if (raw == null) return '—';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return '—';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

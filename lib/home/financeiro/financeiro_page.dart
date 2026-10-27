import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import '../manutencoes/manutencao_comum.dart';
import 'financeiro_comum.dart';

/// Financeiro: resumo (fluxo de caixa), contas a pagar, contas a receber e fornecedores.
/// Tabelas: contas_pagar, contas_receber, fornecedores (docs/MIGRATION_FINANCEIRO.sql).
class FinanceiroPage extends StatefulWidget {
  const FinanceiroPage({super.key, this.abaInicial = 0});
  final int abaInicial;

  @override
  State<FinanceiroPage> createState() => _FinanceiroPageState();
}

class _FinanceiroPageState extends State<FinanceiroPage> with SingleTickerProviderStateMixin, EmpresaDaTela {
  final supabase = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.abaInicial);
  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> pagar = [];
  List<Map<String, dynamic>> receber = [];
  List<Map<String, dynamic>> fornecedores = [];
  List<Map<String, dynamic>> clientes = [];
  List<Map<String, dynamic>> veiculos = [];
  String filtroPagar = 'aberta';
  String filtroReceber = 'aberta';
  String busca = '';

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      await prepararEmpresa();
      final eid = empresaAtual;
      if (eid == null) throw Exception('sem empresa');
      final r = await Future.wait([
        fetchAllRows((a, b) => supabase.from('contas_pagar').select('*, fornecedores(nome)').eq('empresa_id', eid)
            .order('vencimento', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('contas_receber').select('*, clientes(nome)').eq('empresa_id', eid)
            .order('vencimento', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('fornecedores').select('*').eq('empresa_id', eid).order('nome', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('clientes').select('id, nome, ativo').eq('empresa_id', eid).order('nome', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate').eq('empresa_id', eid).order('plate', ascending: true).order('id').range(a, b)),
      ]);
      if (!mounted) return;
      setState(() {
        pagar = r[0];
        receber = r[1];
        fornecedores = r[2];
        clientes = r[3];
        veiculos = r[4];
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar financeiro: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar o financeiro.';
      });
    }
  }

  double _soma(Iterable<Map<String, dynamic>> l, [String campo = 'valor']) =>
      l.fold<double>(0, (s, c) => s + ((c[campo] as num?)?.toDouble() ?? 0));

  // ── Resumo ───────────────────────────────────────────────────────────────
  Widget _abaResumo() {
    final hoje = DateTime.now();
    bool doMes(String? iso) {
      final d = DateTime.tryParse(iso ?? '');
      return d != null && d.year == hoje.year && d.month == hoje.month;
    }

    final pAbertas = pagar.where((c) => c['status'] == 'aberta').toList();
    final rAbertas = receber.where((c) => c['status'] == 'aberta').toList();
    final pVencidas = pAbertas.where((c) => diasParaVencer(c['vencimento']?.toString()) < 0).toList();
    final rVencidas = rAbertas.where((c) => diasParaVencer(c['vencimento']?.toString()) < 0).toList();
    final p30 = pAbertas.where((c) => diasParaVencer(c['vencimento']?.toString()) >= 0 && diasParaVencer(c['vencimento']?.toString()) <= 30);
    final r30 = rAbertas.where((c) => diasParaVencer(c['vencimento']?.toString()) >= 0 && diasParaVencer(c['vencimento']?.toString()) <= 30);
    final pagoMes = pagar.where((c) => c['status'] == 'paga' && doMes(c['data_pagamento']?.toString()));
    final recebidoMes = receber.where((c) => c['status'] == 'recebida' && doMes(c['data_recebimento']?.toString()));
    double saldo(int dias) =>
        _soma(rAbertas.where((c) => diasParaVencer(c['vencimento']?.toString()) <= dias)) -
        _soma(pAbertas.where((c) => diasParaVencer(c['vencimento']?.toString()) <= dias));

    final porCategoria = <String, double>{};
    for (final c in pagoMes) {
      final k = c['categoria']?.toString() ?? 'outros';
      porCategoria[k] = (porCategoria[k] ?? 0) + ((c['valor_pago'] as num?)?.toDouble() ?? 0);
    }
    final cats = porCategoria.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maior = cats.isEmpty ? 1.0 : cats.first.value;

    Widget card(String t, String v, String sub, Color cor) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12.5)),
            const SizedBox(height: 8),
            Text(v, style: TextStyle(color: cor, fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          ]),
        );
    Widget grade(List<Widget> filhos) => LayoutBuilder(builder: (ctx, c) {
          final col = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 2 : 1);
          final w = (c.maxWidth - (col - 1) * 10) / col;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final f in filhos) SizedBox(width: w, child: f)]);
        });
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(t, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
      grade([
        card('A pagar vencidas', moedaBr(_soma(pVencidas)), '${pVencidas.length} conta(s)', AppColors.danger),
        card('A pagar em 30 dias', moedaBr(_soma(p30)), '${p30.length} conta(s)', AppColors.warning),
        card('A receber vencidas', moedaBr(_soma(rVencidas)), '${rVencidas.length} cobrança(s)', AppColors.danger),
        card('A receber em 30 dias', moedaBr(_soma(r30)), '${r30.length} cobrança(s)', AppColors.info),
      ]),
      titulo('Este mês'),
      grade([
        card('Pago no mês', moedaBr(_soma(pagoMes, 'valor_pago')), '${pagoMes.length} pagamento(s)', AppColors.warning),
        card('Recebido no mês', moedaBr(_soma(recebidoMes, 'valor_recebido')), '${recebidoMes.length} recebimento(s)', AppColors.success),
      ]),
      titulo('Saldo previsto (a receber − a pagar, incluindo vencidas)'),
      grade([
        for (final d in const [30, 60, 90])
          card('Próximos $d dias', moedaBr(saldo(d)), saldo(d) >= 0 ? 'sobra no caixa' : 'falta no caixa', saldo(d) >= 0 ? AppColors.success : AppColors.danger),
      ]),
      titulo('Despesas pagas no mês por categoria'),
      if (cats.isEmpty) const Text('Nenhuma despesa paga neste mês.', style: TextStyle(color: AppColors.textSecondary)),
      for (final e in cats)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(categoriasPagar[e.key]?.$2 ?? Icons.more_horiz, size: 18, color: AppColors.secondary),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: Text(categoriasPagar[e.key]?.$1 ?? e.key)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: e.value / maior,
                  minHeight: 10,
                  backgroundColor: AppColors.surface,
                  color: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: Text(moedaBr(e.value), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }

  // ── Listas de contas ─────────────────────────────────────────────────────
  Widget _abaContas({required bool receberModo}) {
    final todas = receberModo ? receber : pagar;
    final filtro = receberModo ? filtroReceber : filtroPagar;
    final pago = receberModo ? 'recebida' : 'paga';
    final termo = busca.toLowerCase();
    final lista = todas.where((c) {
      final dias = diasParaVencer(c['vencimento']?.toString());
      final ok = switch (filtro) {
        'aberta' => c['status'] == 'aberta',
        'vencida' => c['status'] == 'aberta' && dias < 0,
        'pagas' => c['status'] == pago,
        'cancelada' => c['status'] == 'cancelada',
        _ => true,
      };
      if (!ok) return false;
      if (termo.isEmpty) return true;
      final nome = (receberModo ? (c['clientes']?['nome']) : (c['fornecedores']?['nome'])) ?? '';
      return '${c['descricao']} $nome ${c['documento'] ?? ''}'.toLowerCase().contains(termo);
    }).toList();
    final total = _soma(lista);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: receberModo ? 'Buscar por descrição, cliente ou documento' : 'Buscar por descrição, fornecedor ou documento'),
          onChanged: (v) => setState(() => busca = v),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          for (final f in [('aberta', 'Em aberto'), ('vencida', 'Vencidas'), ('pagas', receberModo ? 'Recebidas' : 'Pagas'), ('cancelada', 'Canceladas'), ('todas', 'Todas')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: filtro == f.$1,
                onSelected: (_) => setState(() {
                  if (receberModo) {
                    filtroReceber = f.$1;
                  } else {
                    filtroPagar = f.$1;
                  }
                }),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(children: [
          Text('${lista.length} conta(s)', style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text('Total: ${moedaBr(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
      Expanded(
        child: lista.isEmpty
            ? vazioManut(receberModo ? Icons.call_received : Icons.call_made, 'Nenhuma conta aqui.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: lista.length,
                itemBuilder: (_, i) => _cartaoConta(lista[i], receberModo),
              ),
      ),
    ]);
  }

  Widget _cartaoConta(Map<String, dynamic> c, bool receberModo) {
    final st = (receberModo ? statusReceber : statusPagar)[c['status']] ?? ('${c['status']}', AppColors.muted);
    final dias = diasParaVencer(c['vencimento']?.toString());
    final aberta = c['status'] == 'aberta';
    final vencida = aberta && dias < 0;
    final nome = receberModo ? (c['clientes']?['nome']) : (c['fornecedores']?['nome']);
    final cat = receberModo ? null : categoriasPagar[c['categoria']];
    final pode = context.read<AppAuthProvider>().can(AppPermission.manageFinance);
    final venceTxt = !aberta
        ? (receberModo ? 'recebida em ${dataBrManut(c['data_recebimento']?.toString())}' : 'paga em ${dataBrManut(c['data_pagamento']?.toString())}')
        : vencida
            ? 'venceu há ${-dias} dia(s)'
            : dias == 0
                ? 'vence hoje'
                : 'vence em $dias dia(s)';
    return cartaoManut(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (cat != null) ...[Icon(cat.$2, size: 18, color: AppColors.secondary), const SizedBox(width: 6), Text(cat.$1, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))],
          if ((c['parcelas'] as num? ?? 1) > 1) ...[const SizedBox(width: 8), chipStatus('Parcela ${c['parcela']}/${c['parcelas']}', AppColors.info)],
          const Spacer(),
          if (vencida) ...[chipStatus('Vencida', AppColors.danger), const SizedBox(width: 6)],
          chipStatus(st.$1, st.$2),
        ]),
        const SizedBox(height: 6),
        Text(c['descricao']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
        if (nome != null) Text(nome.toString(), style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Row(children: [
          Text(moedaBr((c['valor'] as num?) ?? 0), style: const TextStyle(color: AppColors.neon, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c['status'] == 'cancelada' ? 'cancelada · vencimento ${dataBrManut(c['vencimento']?.toString())}' : '${dataBrManut(c['vencimento']?.toString())} · $venceTxt',
              style: TextStyle(color: vencida ? AppColors.danger : AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ]),
        if ((c['documento'] ?? '').toString().isNotEmpty)
          Text('Documento: ${c['documento']}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if (pode) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (aberta) botaoAcao(receberModo ? 'Receber' : 'Pagar', Icons.check_circle, AppColors.success, () => _baixar(c, receberModo)),
            if (aberta) botaoAcao('Editar', Icons.edit, AppColors.info, () => _abrirConta(receberModo, conta: c)),
            if (aberta) botaoAcao('Cancelar', Icons.block, AppColors.warning, () => _mudarStatus(c, receberModo, 'cancelada')),
            if (aberta) botaoAcao('Excluir', Icons.delete_outline, AppColors.danger, () => _excluir(c, receberModo)),
            if (!aberta) botaoAcao('Estornar (voltar para aberta)', Icons.undo, AppColors.warning, () => _mudarStatus(c, receberModo, 'aberta')),
          ]),
        ],
      ]),
    );
  }

  Future<void> _baixar(Map<String, dynamic> c, bool receberModo) async {
    var data = DateTime.now();
    final valor = TextEditingController(text: numeroBr((c['valor'] as num?) ?? 0));
    String? forma;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(receberModo ? 'Registrar recebimento' : 'Registrar pagamento'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(c['descricao']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Data: ${dataBrManut(isoDia(data))}'),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: data, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (d != null) setD(() => data = d);
                },
              ),
              const SizedBox(height: 10),
              TextField(controller: valor, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: receberModo ? 'Valor recebido (R\$)' : 'Valor pago (R\$)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: forma,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Forma'),
                items: [for (final f in formasPagamento) DropdownMenuItem(value: f, child: Text(f))],
                onChanged: (v) => setD(() => forma = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = numeroBrDe(valor.text);
    if (v == null || v < 0) {
      if (mounted) showError(context, 'Valor inválido.');
      return;
    }
    final dados = receberModo
        ? {'status': 'recebida', 'data_recebimento': isoDia(data), 'valor_recebido': v, 'forma_recebimento': forma}
        : {'status': 'paga', 'data_pagamento': isoDia(data), 'valor_pago': v, 'forma_pagamento': forma};
    try {
      await supabase.from(receberModo ? 'contas_receber' : 'contas_pagar').update(dados).eq('id', c['id']);
      if (mounted) showSuccess(context, receberModo ? 'Recebimento registrado.' : 'Pagamento registrado.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível registrar.');
    }
  }

  Future<void> _mudarStatus(Map<String, dynamic> c, bool receberModo, String status) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(status == 'cancelada' ? 'Cancelar conta?' : 'Estornar conta?'),
        content: Text(status == 'cancelada'
            ? '"${c['descricao']}" fica cancelada e sai das previsões.'
            : '"${c['descricao']}" volta para "em aberto" e a baixa é desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from(receberModo ? 'contas_receber' : 'contas_pagar').update({'status': status}).eq('id', c['id']);
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível alterar.');
    }
  }

  Future<void> _excluir(Map<String, dynamic> c, bool receberModo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Excluir conta?'),
        content: Text('"${c['descricao']}" será apagada. Use "Cancelar" se quiser manter no histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from(receberModo ? 'contas_receber' : 'contas_pagar').delete().eq('id', c['id']);
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível excluir.');
    }
  }

  Future<void> _abrirConta(bool receberModo, {Map<String, dynamic>? conta}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContaFormPage(
          empresaId: empresaAtual!,
          receber: receberModo,
          conta: conta,
          fornecedores: fornecedores,
          clientes: clientes,
          veiculos: veiculos,
        ),
      ),
    );
    if (ok == true) _carregar();
  }

  // ── Fornecedores ─────────────────────────────────────────────────────────
  Widget _abaFornecedores() {
    final termo = busca.toLowerCase();
    final lista = fornecedores.where((f) => termo.isEmpty || '${f['nome']} ${f['documento'] ?? ''} ${f['categoria'] ?? ''}'.toLowerCase().contains(termo)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar fornecedor'),
          onChanged: (v) => setState(() => busca = v),
        ),
      ),
      Expanded(
        child: lista.isEmpty
            ? vazioManut(Icons.store, fornecedores.isEmpty ? 'Nenhum fornecedor cadastrado ainda.' : 'Nenhum fornecedor encontrado.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final f = lista[i];
                  final emAberto = _soma(pagar.where((c) => c['fornecedor_id'] == f['id'] && c['status'] == 'aberta'));
                  return cartaoManut(
                    onTap: () => _abrirFornecedor(f),
                    child: Row(children: [
                      const CircleAvatar(child: Icon(Icons.store)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(f['nome'].toString(), style: TextStyle(fontWeight: FontWeight.bold, color: f['ativo'] == false ? AppColors.muted : Colors.white)),
                          Text([
                            if ((f['categoria'] ?? '').toString().isNotEmpty) f['categoria'].toString(),
                            if ((f['telefone'] ?? '').toString().isNotEmpty) f['telefone'].toString(),
                            if (f['ativo'] == false) 'INATIVO',
                          ].join(' · '), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ]),
                      ),
                      if (emAberto > 0) Text('${moedaBr(emAberto)} em aberto', style: const TextStyle(color: AppColors.warning, fontSize: 13)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _abrirFornecedor([Map<String, dynamic>? f]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FornecedorFormPage(empresaId: empresaAtual!, fornecedor: f)));
    if (ok == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.can(AppPermission.viewFinance)) {
      return Scaffold(appBar: AppBar(title: const Text('Financeiro')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso ao Financeiro.'));
    }
    final pode = auth.can(AppPermission.manageFinance);
    final fab = switch (_tabs.index) {
      1 => ('Nova conta a pagar', () => _abrirConta(false)),
      2 => ('Nova conta a receber', () => _abrirConta(true)),
      3 => ('Novo fornecedor', () => _abrirFornecedor()),
      _ => null,
    };
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Financeiro'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          onTap: (_) => setState(() => busca = ''),
          tabs: [
            const Tab(text: 'Resumo'),
            Tab(text: 'A pagar (${pagar.where((c) => c['status'] == 'aberta').length})'),
            Tab(text: 'A receber (${receber.where((c) => c['status'] == 'aberta').length})'),
            Tab(text: 'Fornecedores (${fornecedores.length})'),
          ],
        ),
      ),
      floatingActionButton: pode && fab != null && !carregando && erro == null
          ? FloatingActionButton.extended(onPressed: fab.$2, icon: const Icon(Icons.add), label: Text(fab.$1))
          : null,
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : Column(children: [
                  if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
                  Expanded(
                    child: TabBarView(controller: _tabs, children: [
                      _abaResumo(),
                      _abaContas(receberModo: false),
                      _abaContas(receberModo: true),
                      _abaFornecedores(),
                    ]),
                  ),
                ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Formulário de conta (a pagar ou a receber), com parcelamento
// ═════════════════════════════════════════════════════════════════════════
class ContaFormPage extends StatefulWidget {
  const ContaFormPage({
    super.key,
    required this.empresaId,
    required this.receber,
    this.conta,
    this.inicial,
    required this.fornecedores,
    required this.clientes,
    required this.veiculos,
  });

  final String empresaId;
  final bool receber;
  final Map<String, dynamic>? conta;

  /// Pré-preenchimento (ex.: cobrança gerada a partir de uma coleta, conta da OS).
  final Map<String, dynamic>? inicial;
  final List<Map<String, dynamic>> fornecedores;
  final List<Map<String, dynamic>> clientes;
  final List<Map<String, dynamic>> veiculos;

  @override
  State<ContaFormPage> createState() => _ContaFormPageState();
}

class _ContaFormPageState extends State<ContaFormPage> {
  final _form = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  bool salvando = false;
  late final Map<String, dynamic> base = {...?widget.inicial, ...?widget.conta};
  late final descricao = TextEditingController(text: base['descricao']?.toString() ?? '');
  late final valor = TextEditingController(text: base['valor'] is num ? numeroBr(base['valor'] as num) : '');
  late final documento = TextEditingController(text: base['documento']?.toString() ?? '');
  late final obs = TextEditingController(text: base['observacoes']?.toString() ?? '');
  late final parcelas = TextEditingController(text: '1');
  late String categoria = base['categoria']?.toString() ?? (widget.receber ? 'frete' : 'outros');
  late String? pessoaId = (widget.receber ? base['cliente_id'] : base['fornecedor_id'])?.toString();
  late String? veiculoId = base['vehicle_id']?.toString();
  late DateTime vencimento = DateTime.tryParse(base['vencimento']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 30));

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final v = numeroBrDe(valor.text)!;
    final n = widget.conta != null ? 1 : (int.tryParse(parcelas.text.trim()) ?? 1);
    final comum = <String, dynamic>{
      'empresa_id': widget.empresaId,
      'categoria': categoria,
      'documento': documento.text.trim(),
      'observacoes': obs.text.trim(),
      if (widget.receber) ...{
        'cliente_id': pessoaId,
        if (base['coleta_id'] != null) 'coleta_id': base['coleta_id'],
        if (base['cotacao_id'] != null) 'cotacao_id': base['cotacao_id'],
      } else ...{
        'fornecedor_id': pessoaId,
        'vehicle_id': veiculoId,
        if (base['os_id'] != null) 'os_id': base['os_id'],
      },
    };
    final tabela = widget.receber ? 'contas_receber' : 'contas_pagar';
    setState(() => salvando = true);
    try {
      if (widget.conta != null) {
        await supabase.from(tabela).update({...comum, 'descricao': descricao.text.trim(), 'valor': v, 'vencimento': isoDia(vencimento)}).eq('id', widget.conta!['id']);
      } else {
        final grupo = n > 1 ? _uuid() : null;
        final linhas = [
          for (final (i, p) in gerarParcelas(v, n, vencimento).indexed)
            {
              ...comum,
              'descricao': n > 1 ? '${descricao.text.trim()} (${i + 1}/$n)' : descricao.text.trim(),
              'valor': p.$1,
              'vencimento': isoDia(p.$2),
              'parcela': i + 1,
              'parcelas': n,
              'grupo': grupo,
            },
        ];
        await supabase.from(tabela).insert(linhas);
      }
      if (!mounted) return;
      showSuccess(context, widget.conta != null ? 'Conta atualizada.' : (n > 1 ? '$n parcelas lançadas.' : 'Conta lançada.'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showErrorFrom(context, e, prefix: 'Não foi possível salvar.');
      setState(() => salvando = false);
    }
  }

  // identificador que agrupa as parcelas de um mesmo lançamento (uuid v4 aleatório)
  String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.conta != null;
    final pessoas = widget.receber ? widget.clientes : widget.fornecedores;
    final titulo = editando ? 'Editar conta' : (widget.receber ? 'Nova conta a receber' : 'Nova conta a pagar');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(titulo), backgroundColor: AppColors.surface),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              TextFormField(
                controller: descricao,
                decoration: InputDecoration(labelText: 'Descrição *', hintText: widget.receber ? 'Ex.: frete Pouso Alegre → Campinas' : 'Ex.: diesel posto BR, parcela do caminhão'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Descreva a conta' : null,
              ),
              const SizedBox(height: 14),
              if (!widget.receber) ...[
                DropdownButtonFormField<String>(
                  initialValue: categoria,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoria *'),
                  items: [for (final c in categoriasPagar.entries) DropdownMenuItem(value: c.key, child: Text(c.value.$1))],
                  onChanged: (v) => setState(() => categoria = v ?? 'outros'),
                ),
                const SizedBox(height: 14),
              ],
              DropdownButtonFormField<String?>(
                initialValue: pessoaId,
                isExpanded: true,
                decoration: InputDecoration(labelText: widget.receber ? 'Cliente' : 'Fornecedor'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Não informar')),
                  for (final p in pessoas.where((p) => p['ativo'] != false || p['id'].toString() == pessoaId))
                    DropdownMenuItem<String?>(value: p['id'].toString(), child: Text(p['nome'].toString(), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => pessoaId = v),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: valor,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: editando ? 'Valor (R\$) *' : 'Valor total (R\$) *'),
                    validator: (v) {
                      final n = numeroBrDe(v ?? '');
                      return n == null || n <= 0 ? 'Informe o valor' : null;
                    },
                  ),
                ),
                if (!editando) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      controller: parcelas,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Parcelas'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 1 || n > 120 ? '1 a 120' : null;
                      },
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${editando ? 'Vencimento' : 'Vencimento da 1ª parcela'}: ${dataBrManut(isoDia(vencimento))}'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: vencimento, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) setState(() => vencimento = d);
                },
              ),
              const SizedBox(height: 14),
              if (!widget.receber) ...[
                DropdownButtonFormField<String?>(
                  initialValue: veiculoId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Veículo (para o custo por veículo)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Não é de um veículo')),
                    for (final v in widget.veiculos) DropdownMenuItem<String?>(value: v['id'].toString(), child: Text(v['plate'].toString())),
                  ],
                  onChanged: (v) => setState(() => veiculoId = v),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(controller: documento, decoration: InputDecoration(labelText: widget.receber ? 'Documento (nº do CT-e, boleto...)' : 'Documento (nº da nota, boleto...)')),
              const SizedBox(height: 14),
              TextFormField(controller: obs, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: salvando ? null : _salvar,
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: Text(editando ? 'Salvar alterações' : 'Lançar'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Fornecedor ─────────────────────────────────────────────────────────────
class FornecedorFormPage extends StatefulWidget {
  const FornecedorFormPage({super.key, required this.empresaId, this.fornecedor});
  final String empresaId;
  final Map<String, dynamic>? fornecedor;

  @override
  State<FornecedorFormPage> createState() => _FornecedorFormPageState();
}

class _FornecedorFormPageState extends State<FornecedorFormPage> {
  final _form = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  bool salvando = false;
  late final Map<String, dynamic> f = widget.fornecedor ?? {};
  late String tipo = f['tipo']?.toString() ?? 'PJ';
  late bool ativo = f['ativo'] != false;
  late final nome = TextEditingController(text: f['nome']?.toString() ?? '');
  late final documento = TextEditingController(text: f['documento']?.toString() ?? '');
  late final categoria = TextEditingController(text: f['categoria']?.toString() ?? '');
  late final contato = TextEditingController(text: f['contato']?.toString() ?? '');
  late final telefone = TextEditingController(text: f['telefone']?.toString() ?? '');
  late final email = TextEditingController(text: f['email']?.toString() ?? '');
  late final cidade = TextEditingController(text: f['cidade']?.toString() ?? '');
  late final obs = TextEditingController(text: f['observacoes']?.toString() ?? '');

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final doc = documento.text.replaceAll(RegExp(r'\D'), '');
    final dados = {
      'tipo': tipo,
      'nome': nome.text.trim(),
      'documento': doc.isEmpty ? null : doc,
      'categoria': categoria.text.trim(),
      'contato': contato.text.trim(),
      'telefone': telefone.text.trim(),
      'email': email.text.trim(),
      'cidade': cidade.text.trim(),
      'observacoes': obs.text.trim(),
      'ativo': ativo,
    };
    setState(() => salvando = true);
    try {
      if (widget.fornecedor != null) {
        await supabase.from('fornecedores').update(dados).eq('id', f['id']);
      } else {
        await supabase.from('fornecedores').insert({...dados, 'empresa_id': widget.empresaId});
      }
      if (!mounted) return;
      showSuccess(context, widget.fornecedor != null ? 'Fornecedor atualizado.' : 'Fornecedor cadastrado.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('fornecedores_empresa_documento_uq')) {
        showError(context, 'Já existe um fornecedor com este CNPJ/CPF.');
      } else {
        showErrorFrom(context, e, prefix: 'Não foi possível salvar.');
      }
      setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.fornecedor != null;
    Widget campo(TextEditingController c, String l, {String? Function(String)? validar, TextInputType? teclado, String? dica, int linhas = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            controller: c,
            keyboardType: teclado,
            maxLines: linhas,
            decoration: InputDecoration(labelText: l, hintText: dica),
            validator: (v) => validar?.call((v ?? '').trim()),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(editando ? 'Editar fornecedor' : 'Novo fornecedor'), backgroundColor: AppColors.surface),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'PJ', label: Text('Empresa (CNPJ)'), icon: Icon(Icons.business)),
                  ButtonSegment(value: 'PF', label: Text('Pessoa (CPF)'), icon: Icon(Icons.person)),
                ],
                selected: {tipo},
                onSelectionChanged: (s) => setState(() => tipo = s.first),
              ),
              const SizedBox(height: 16),
              campo(nome, 'Nome / razão social *', validar: (t) => t.length < 2 ? 'Informe o nome' : null),
              campo(documento, tipo == 'PJ' ? 'CNPJ' : 'CPF', teclado: TextInputType.number, validar: (t) {
                final d = t.replaceAll(RegExp(r'\D'), '');
                if (d.isEmpty) return null;
                if (tipo == 'PJ' && d.length != 14) return 'CNPJ deve ter 14 números';
                if (tipo == 'PF' && d.length != 11) return 'CPF deve ter 11 números';
                return null;
              }),
              campo(categoria, 'O que fornece', dica: 'Ex.: combustível, peças, pneus, oficina'),
              campo(contato, 'Pessoa de contato'),
              campo(telefone, 'Telefone / WhatsApp', teclado: TextInputType.phone),
              campo(email, 'E-mail', teclado: TextInputType.emailAddress,
                  validar: (t) => t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'E-mail inválido'),
              campo(cidade, 'Cidade'),
              campo(obs, 'Observações', linhas: 3),
              if (editando)
                SwitchListTile(value: ativo, onChanged: (v) => setState(() => ativo = v), title: const Text('Fornecedor ativo')),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: salvando ? null : _salvar,
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: Text(editando ? 'Salvar alterações' : 'Cadastrar fornecedor'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

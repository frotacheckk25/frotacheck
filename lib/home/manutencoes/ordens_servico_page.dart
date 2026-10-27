import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import '../financeiro/financeiro_page.dart';
import 'manutencao_comum.dart';

/// Ordens de serviço de manutenção (preventiva/corretiva) com peças e serviços.
/// Tabelas: ordens_servico, ordem_servico_itens (docs/MIGRATION_MANUTENCAO_OS_PLANO.sql).
/// Ao concluir, o banco lança o custo em manutencoes e atualiza o plano preventivo.
class OrdensServicoPage extends StatefulWidget {
  const OrdensServicoPage({super.key});

  @override
  State<OrdensServicoPage> createState() => _OrdensServicoPageState();
}

class _OrdensServicoPageState extends State<OrdensServicoPage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> ordens = [];
  Map<String, Map<String, dynamic>> veiculos = {};
  String filtro = 'abertas';

  @override
  void initState() {
    super.initState();
    _carregar();
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
        fetchAllRows((a, b) => supabase.from('ordens_servico').select('*').eq('empresa_id', eid)
            .order('data_abertura', ascending: false).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate, brand, model, odometer').eq('empresa_id', eid)
            .order('plate', ascending: true).order('id').range(a, b)),
      ]);
      if (!mounted) return;
      setState(() {
        ordens = r[0];
        veiculos = {for (final v in r[1]) v['id'].toString(): v};
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar OS: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar as ordens de serviço.';
      });
    }
  }

  Future<void> _novaOs() async {
    if (veiculos.isEmpty) {
      showError(context, 'Cadastre um veículo antes de abrir a OS.');
      return;
    }
    final criada = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => OsFormPage(empresaId: empresaAtual!, veiculos: veiculos.values.toList())),
    );
    if (criada != null) {
      await _carregar();
      if (mounted) _abrir(criada);
    }
  }

  Future<void> _abrir(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OsDetalhePage(osId: id, veiculos: veiculos)),
    );
    _carregar();
  }

  Widget _indicadores() {
    final hoje = DateTime.now();
    final abertas = ordens.where((o) => o['status'] == 'aberta').length;
    final execucao = ordens.where((o) => o['status'] == 'em_execucao').length;
    final doMes = ordens.where((o) {
      final d = DateTime.tryParse(o['data_conclusao']?.toString() ?? '');
      return o['status'] == 'concluida' && d != null && d.year == hoje.year && d.month == hoje.month;
    }).toList();
    final custoMes = doMes.fold<double>(0, (s, o) => s + ((o['valor_total'] as num?)?.toDouble() ?? 0));
    Widget card(String t, String v, String sub, Color cor) => Container(
          width: 170,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(children: [
        card('Abertas', '$abertas', 'aguardando início', AppColors.info),
        const SizedBox(width: 10),
        card('Em execução', '$execucao', 'na oficina', AppColors.warning),
        const SizedBox(width: 10),
        card('Custo no mês', moedaBr(custoMes), '${doMes.length} OS concluídas', AppColors.success),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final pode = !auth.isMotorista && auth.can(AppPermission.manageMaintenance);
    if (!pode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ordens de serviço')),
        body: vazioManut(Icons.lock_outline, 'Você não tem acesso às ordens de serviço.'),
      );
    }
    final lista = ordens.where((o) {
      switch (filtro) {
        case 'abertas':
          return o['status'] == 'aberta' || o['status'] == 'em_execucao';
        case 'concluidas':
          return o['status'] == 'concluida';
        case 'canceladas':
          return o['status'] == 'cancelada';
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ordens de serviço'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
      ),
      floatingActionButton: carregando || erro != null
          ? null
          : FloatingActionButton.extended(onPressed: _novaOs, icon: const Icon(Icons.add), label: const Text('Nova OS')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                    if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
                    _indicadores(),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(children: [
                        for (final f in const {'abertas': 'Em aberto', 'concluidas': 'Concluídas', 'canceladas': 'Canceladas', 'todas': 'Todas'}.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(label: Text(f.value), selected: filtro == f.key, onSelected: (_) => setState(() => filtro = f.key)),
                          ),
                      ]),
                    ),
                    if (lista.isEmpty) vazioManut(Icons.build_circle_outlined, 'Nenhuma ordem de serviço aqui.'),
                    for (final o in lista) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _cartao(o)),
                  ]),
                ),
    );
  }

  Widget _cartao(Map<String, dynamic> o) {
    final st = statusOs[o['status']] ?? ('${o['status']}', AppColors.muted);
    final v = veiculos[o['vehicle_id']?.toString()];
    return cartaoManut(
      onTap: () => _abrir(o['id'].toString()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('OS nº ${o['numero'] ?? '-'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(width: 8),
          chipStatus(o['tipo'] == 'preventiva' ? 'Preventiva' : 'Corretiva', o['tipo'] == 'preventiva' ? AppColors.secondary : AppColors.danger),
          const Spacer(),
          chipStatus(st.$1, st.$2),
        ]),
        const SizedBox(height: 8),
        Text(o['descricao']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          [
            v == null ? 'sem veículo' : '${v['plate']}',
            if (o['km'] != null) kmBr(o['km'] as num),
            if ((o['oficina'] ?? '').toString().isNotEmpty) o['oficina'].toString(),
            'aberta em ${dataBrManut(o['data_abertura']?.toString())}',
          ].join(' · '),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(moedaBr((o['valor_total'] as num?) ?? 0),
            style: const TextStyle(color: AppColors.neon, fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    );
  }
}

// ── Formulário de abertura/edição ───────────────────────────────────────────
class OsFormPage extends StatefulWidget {
  const OsFormPage({super.key, required this.empresaId, required this.veiculos, this.os, this.inicial});
  final String empresaId;
  final List<Map<String, dynamic>> veiculos;
  final Map<String, dynamic>? os;

  /// Pré-preenchimento (ex.: OS aberta a partir de um item do plano preventivo).
  final Map<String, dynamic>? inicial;

  @override
  State<OsFormPage> createState() => _OsFormPageState();
}

class _OsFormPageState extends State<OsFormPage> {
  final _form = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  bool salvando = false;
  late final Map<String, dynamic> base = {...?widget.inicial, ...?widget.os};
  late String? veiculoId = base['vehicle_id']?.toString();
  late String tipo = base['tipo']?.toString() ?? 'corretiva';
  late String oficinaTipo = base['oficina_tipo']?.toString() ?? 'externa';
  late final descricao = TextEditingController(text: base['descricao']?.toString() ?? '');
  late final km = TextEditingController(text: base['km']?.toString() ?? '');
  late final oficina = TextEditingController(text: base['oficina']?.toString() ?? '');
  late final obs = TextEditingController(text: base['observacoes']?.toString() ?? '');

  void _escolherVeiculo(String? id) {
    setState(() => veiculoId = id);
    final v = widget.veiculos.where((x) => x['id'].toString() == id).firstOrNull;
    if (km.text.trim().isEmpty && v?['odometer'] != null) km.text = (v!['odometer'] as num).round().toString();
  }

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final kmNum = int.tryParse(km.text.trim());
    final dados = {
      'vehicle_id': veiculoId,
      'tipo': tipo,
      'descricao': descricao.text.trim(),
      'km': kmNum,
      'oficina': oficina.text.trim(),
      'oficina_tipo': oficinaTipo,
      'observacoes': obs.text.trim(),
      if (base['plano_item_id'] != null) 'plano_item_id': base['plano_item_id'],
    };
    setState(() => salvando = true);
    try {
      if (widget.os != null) {
        await supabase.from('ordens_servico').update(dados).eq('id', widget.os!['id']);
        if (!mounted) return;
        showSuccess(context, 'OS atualizada.');
        Navigator.pop(context, widget.os!['id'].toString());
      } else {
        final nova = await supabase
            .from('ordens_servico')
            .insert({...dados, 'empresa_id': widget.empresaId})
            .select('id, numero')
            .single();
        if (!mounted) return;
        showSuccess(context, 'OS nº ${nova['numero']} aberta. Agora inclua as peças e os serviços.');
        Navigator.pop(context, nova['id'].toString());
      }
    } catch (e) {
      if (!mounted) return;
      showErrorFrom(context, e, prefix: 'Não foi possível salvar a OS.');
      setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.os != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(editando ? 'Editar OS nº ${widget.os!['numero']}' : 'Nova ordem de serviço'), backgroundColor: AppColors.surface),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'corretiva', label: Text('Corretiva'), icon: Icon(Icons.build)),
                  ButtonSegment(value: 'preventiva', label: Text('Preventiva'), icon: Icon(Icons.event_repeat)),
                ],
                selected: {tipo},
                onSelectionChanged: (s) => setState(() => tipo = s.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: veiculoId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Veículo *'),
                items: [
                  for (final v in widget.veiculos)
                    DropdownMenuItem(value: v['id'].toString(), child: Text('${v['plate']} · ${v['brand'] ?? ''} ${v['model'] ?? ''}')),
                ],
                onChanged: _escolherVeiculo,
                validator: (v) => v == null ? 'Escolha o veículo' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: descricao,
                decoration: const InputDecoration(labelText: 'O que será feito? *', hintText: 'Ex.: troca das pastilhas de freio dianteiras'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Descreva o serviço' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: km,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Km do veículo'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  return n == null || n < 0 || n > 3000000 ? 'Km inválido (só números)' : null;
                },
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'externa', label: Text('Oficina de fora')),
                  ButtonSegment(value: 'interna', label: Text('Oficina própria')),
                ],
                selected: {oficinaTipo},
                onSelectionChanged: (s) => setState(() => oficinaTipo = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(controller: oficina, decoration: const InputDecoration(labelText: 'Nome da oficina / mecânico')),
              const SizedBox(height: 14),
              TextFormField(controller: obs, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: salvando ? null : _salvar,
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: Text(editando ? 'Salvar alterações' : 'Abrir OS'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Detalhe: peças e serviços, andamento ────────────────────────────────────
class OsDetalhePage extends StatefulWidget {
  const OsDetalhePage({super.key, required this.osId, required this.veiculos});
  final String osId;
  final Map<String, Map<String, dynamic>> veiculos;

  @override
  State<OsDetalhePage> createState() => _OsDetalhePageState();
}

class _OsDetalhePageState extends State<OsDetalhePage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? os;
  List<Map<String, dynamic>> itens = [];
  bool carregando = true;
  bool contaLancada = false; // já existe conta a pagar desta OS no Financeiro

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await Future.wait([
        supabase.from('ordens_servico').select('*').eq('id', widget.osId).single(),
        supabase.from('ordem_servico_itens').select('*').eq('os_id', widget.osId).order('created_at', ascending: true),
      ]);
      var lancada = false;
      try {
        final cp = await supabase.from('contas_pagar').select('id').eq('os_id', widget.osId).neq('status', 'cancelada').limit(1);
        lancada = (cp as List).isNotEmpty;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        os = Map<String, dynamic>.from(r[0] as Map);
        itens = List<Map<String, dynamic>>.from(r[1] as List);
        contaLancada = lancada;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => carregando = false);
      showErrorFrom(context, e, prefix: 'Não foi possível abrir a OS.');
    }
  }

  bool get editavel => os != null && (os!['status'] == 'aberta' || os!['status'] == 'em_execucao');

  Future<void> _item([Map<String, dynamic>? item]) async {
    final desc = TextEditingController(text: item?['descricao']?.toString() ?? '');
    final qtd = TextEditingController(text: item == null ? '1' : numeroBr(item['quantidade'] as num, casas: (item['quantidade'] as num) % 1 == 0 ? 0 : 2));
    final valor = TextEditingController(text: item == null ? '' : numeroBr(item['valor_unitario'] as num));
    var tipo = item?['tipo']?.toString() ?? 'peca';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(item == null ? 'Incluir peça ou serviço' : 'Editar item'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'peca', label: Text('Peça')), ButtonSegment(value: 'servico', label: Text('Serviço'))],
                selected: {tipo},
                onSelectionChanged: (s) => setD(() => tipo = s.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descrição *')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: qtd, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantidade'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: valor, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor unitário (R\$)'))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = numeroBrDe(qtd.text) ?? 0;
    final v = numeroBrDe(valor.text) ?? 0;
    if (desc.text.trim().length < 2) {
      if (mounted) showError(context, 'Descreva a peça ou o serviço.');
      return;
    }
    if (q <= 0 || v < 0) {
      if (mounted) showError(context, 'Quantidade e valor precisam ser números válidos.');
      return;
    }
    final dados = {'tipo': tipo, 'descricao': desc.text.trim(), 'quantidade': q, 'valor_unitario': v};
    try {
      if (item == null) {
        await supabase.from('ordem_servico_itens').insert({...dados, 'os_id': widget.osId, 'empresa_id': os!['empresa_id']});
      } else {
        await supabase.from('ordem_servico_itens').update(dados).eq('id', item['id']);
      }
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível salvar o item.');
    }
  }

  Future<void> _removerItem(Map<String, dynamic> item) async {
    try {
      await supabase.from('ordem_servico_itens').delete().eq('id', item['id']);
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível remover o item.');
    }
  }

  Future<void> _mudarStatus(String status) async {
    final textos = {
      'em_execucao': ('Iniciar execução?', 'A OS passa para "em execução".', 'Iniciar'),
      'concluida': (
        'Concluir a OS?',
        'O custo de ${moedaBr((os!['valor_total'] as num?) ?? 0)} entra nos relatórios de manutenção do veículo. '
            'Depois de concluída, a OS não pode mais ser alterada.',
        'Concluir'
      ),
      'cancelada': ('Cancelar a OS?', 'A OS fica cancelada e não entra nos custos.', 'Cancelar OS'),
    }[status]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(textos.$1),
        content: Text(textos.$2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: status == 'cancelada' ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(textos.$3),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('ordens_servico').update({'status': status}).eq('id', widget.osId);
      if (!mounted) return;
      showSuccess(context, switch (status) {
        'concluida' => 'OS concluída. O custo já entrou nos relatórios.',
        'cancelada' => 'OS cancelada.',
        _ => 'OS em execução.',
      });
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível mudar a OS.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (os == null) return Scaffold(appBar: AppBar(), body: vazioManut(Icons.error_outline, 'OS não encontrada.'));
    final o = os!;
    final st = statusOs[o['status']] ?? ('${o['status']}', AppColors.muted);
    final v = widget.veiculos[o['vehicle_id']?.toString()];
    final pecas = itens.where((i) => i['tipo'] == 'peca').fold<double>(0, (s, i) => s + (i['quantidade'] as num) * (i['valor_unitario'] as num));
    final servicos = itens.where((i) => i['tipo'] == 'servico').fold<double>(0, (s, i) => s + (i['quantidade'] as num) * (i['valor_unitario'] as num));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('OS nº ${o['numero']}'),
        backgroundColor: AppColors.surface,
        actions: [
          if (editavel)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar dados da OS',
              onPressed: () async {
                final r = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => OsFormPage(empresaId: o['empresa_id'].toString(), veiculos: widget.veiculos.values.toList(), os: o)),
                );
                if (r != null) _carregar();
              },
            ),
        ],
      ),
      floatingActionButton: editavel
          ? FloatingActionButton.extended(onPressed: () => _item(), icon: const Icon(Icons.add), label: const Text('Peça ou serviço'))
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
            cartaoManut(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  chipStatus(o['tipo'] == 'preventiva' ? 'Preventiva' : 'Corretiva', o['tipo'] == 'preventiva' ? AppColors.secondary : AppColors.danger),
                  const Spacer(),
                  chipStatus(st.$1, st.$2),
                ]),
                const SizedBox(height: 10),
                Text(o['descricao']?.toString() ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  [
                    v == null ? 'sem veículo' : '${v['plate']} · ${v['brand'] ?? ''} ${v['model'] ?? ''}',
                    if (o['km'] != null) kmBr(o['km'] as num),
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if ((o['oficina'] ?? '').toString().isNotEmpty)
                  Text('${o['oficina_tipo'] == 'interna' ? 'Oficina própria' : 'Oficina'}: ${o['oficina']}',
                      style: const TextStyle(color: AppColors.textSecondary)),
                Text('Aberta em ${dataBrManut(o['data_abertura']?.toString())}'
                    '${o['data_conclusao'] != null ? ' · concluída em ${dataBrManut(o['data_conclusao']?.toString())}' : ''}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                if ((o['observacoes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Obs.: ${o['observacoes']}', style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ]),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 10),
              child: Text('Peças e serviços', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            if (itens.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Nenhum item ainda. Toque em "Peça ou serviço" para incluir.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            for (final i in itens)
              cartaoManut(
                onTap: editavel ? () => _item(i) : null,
                child: Row(children: [
                  Icon(i['tipo'] == 'peca' ? Icons.settings : Icons.engineering, color: AppColors.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i['descricao'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${numeroBr(i['quantidade'] as num, casas: (i['quantidade'] as num) % 1 == 0 ? 0 : 2)} × ${moedaBr(i['valor_unitario'] as num)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ]),
                  ),
                  Text(moedaBr((i['quantidade'] as num) * (i['valor_unitario'] as num)), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (editavel)
                    IconButton(
                      tooltip: 'Remover item',
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () => _removerItem(i),
                    ),
                ]),
              ),
            cartaoManut(
              child: Column(children: [
                _linhaTotal('Peças', moedaBr(pecas)),
                _linhaTotal('Serviços', moedaBr(servicos)),
                const Divider(color: AppColors.border),
                _linhaTotal('Total da OS', moedaBr((o['valor_total'] as num?) ?? 0), destaque: true),
              ]),
            ),
            if (editavel)
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (context.read<AppAuthProvider>().can(AppPermission.manageSupplies))
                  botaoAcao('Peça do estoque', Icons.inventory_2, AppColors.secondary, _pecaDoEstoque),
                if (o['status'] == 'aberta') botaoAcao('Iniciar execução', Icons.play_arrow, AppColors.warning, () => _mudarStatus('em_execucao')),
                botaoAcao('Concluir OS', Icons.check_circle, AppColors.success, () => _mudarStatus('concluida')),
                botaoAcao('Cancelar OS', Icons.close, AppColors.danger, () => _mudarStatus('cancelada')),
              ]),
            if (o['status'] == 'concluida')
              const Text('✓ Custo lançado nos relatórios de manutenção do veículo.',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
            if (o['status'] == 'concluida' && context.read<AppAuthProvider>().can(AppPermission.manageFinance)) ...[
              const SizedBox(height: 10),
              if (contaLancada)
                const Text('✓ Lançada no contas a pagar do Financeiro.', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600))
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: botaoAcao('Lançar no contas a pagar', Icons.request_page, AppColors.warning, _lancarContaPagar),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Tira a peça do estoque e já inclui na OS pelo custo médio (função do banco).
  Future<void> _pecaDoEstoque() async {
    final o = os!;
    List<Map<String, dynamic>> mats;
    try {
      mats = List<Map<String, dynamic>>.from(await supabase
          .from('materiais')
          .select('id, codigo, nome, unidade, estoque_atual, custo_medio')
          .eq('empresa_id', o['empresa_id'])
          .eq('ativo', true)
          .gt('estoque_atual', 0)
          .order('nome', ascending: true));
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível carregar o estoque.');
      return;
    }
    if (!mounted) return;
    if (mats.isEmpty) {
      showError(context, 'Não há material com saldo no estoque.');
      return;
    }
    String? matId;
    final qtd = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final sel = mats.where((m) => m['id'].toString() == matId).firstOrNull;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Peça do estoque'),
            content: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<String>(
                  initialValue: matId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Material *'),
                  items: [
                    for (final m in mats)
                      DropdownMenuItem(
                        value: m['id'].toString(),
                        child: Text('${m['codigo'] != null ? '${m['codigo']} · ' : ''}${m['nome']} (${numeroBr(m['estoque_atual'] as num, casas: (m['estoque_atual'] as num) % 1 == 0 ? 0 : 3)} ${m['unidade']})',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setD(() => matId = v),
                ),
                const SizedBox(height: 10),
                TextField(controller: qtd, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantidade *')),
                if (sel != null) ...[
                  const SizedBox(height: 8),
                  Text('Custo médio: ${moedaBr(sel['custo_medio'] as num)} por ${sel['unidade']}', style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usar na OS')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final q = numeroBrDe(qtd.text);
    if (matId == null || q == null || q <= 0) {
      showError(context, 'Escolha o material e a quantidade.');
      return;
    }
    try {
      await supabase.rpc('baixar_estoque_para_os', params: {'p_os': widget.osId, 'p_material': matId, 'p_quantidade': q});
      if (mounted) showSuccess(context, 'Peça retirada do estoque e incluída na OS.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível usar a peça.');
    }
  }

  /// Conta a pagar da OS no Financeiro, já preenchida (oficina de fora a pagar).
  Future<void> _lancarContaPagar() async {
    final o = os!;
    try {
      final r = await Future.wait([
        supabase.from('fornecedores').select('id, nome, ativo').eq('empresa_id', o['empresa_id']).order('nome', ascending: true),
        supabase.from('vehicles').select('id, plate').eq('empresa_id', o['empresa_id']).order('plate', ascending: true),
      ]);
      if (!mounted) return;
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ContaFormPage(
            empresaId: o['empresa_id'].toString(),
            receber: false,
            inicial: {
              'descricao': 'OS nº ${o['numero']} · ${o['descricao']}',
              'categoria': 'manutencao',
              'vehicle_id': o['vehicle_id'],
              'os_id': o['id'],
              'valor': o['valor_total'],
              'vencimento': isoDia(DateTime.now()),
              if ((o['oficina'] ?? '').toString().isNotEmpty) 'observacoes': 'Oficina: ${o['oficina']}',
            },
            fornecedores: List<Map<String, dynamic>>.from(r[0] as List),
            clientes: const [],
            veiculos: List<Map<String, dynamic>>.from(r[1] as List),
          ),
        ),
      );
      if (ok == true) _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível abrir o lançamento.');
    }
  }

  Widget _linhaTotal(String t, String v, {bool destaque = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(t, style: TextStyle(color: destaque ? Colors.white : AppColors.textSecondary, fontWeight: destaque ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text(v, style: TextStyle(color: destaque ? AppColors.neon : Colors.white, fontWeight: FontWeight.bold, fontSize: destaque ? 18 : 14)),
        ]),
      );
}

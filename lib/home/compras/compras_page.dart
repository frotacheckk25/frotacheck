import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import '../comercial/comercial_page.dart' show soDigitos;
import '../estoque/estoque_page.dart' show qtdBr, unidadesMaterial;
import '../financeiro/financeiro_comum.dart';
import '../financeiro/financeiro_page.dart' show FornecedorFormPage;
import '../manutencoes/manutencao_comum.dart';
import 'compras_comum.dart';

/// Compras: pedido de compra → aprovação → recebimento (entrada no estoque e
/// contas a pagar numa transação só). As regras ficam no banco
/// (docs/MIGRATION_COMPRAS.sql); a tela conduz as etapas.
class ComprasPage extends StatefulWidget {
  const ComprasPage({super.key});

  @override
  State<ComprasPage> createState() => _ComprasPageState();
}

class _ComprasPageState extends State<ComprasPage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> pedidos = [];
  List<Map<String, dynamic>> fornecedores = [];
  List<Map<String, dynamic>> veiculos = [];
  List<Map<String, dynamic>> abaixoMinimo = [];
  double compradoMes = 0;
  String filtro = 'andamento';
  String busca = '';

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
      final hoje = DateTime.now();
      final r = await Future.wait([
        fetchAllRows((a, b) => supabase.from('pedidos_compra').select('*, fornecedores(nome)').eq('empresa_id', eid).order('numero', ascending: false).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('fornecedores').select('id, nome, ativo').eq('empresa_id', eid).order('nome', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate').eq('empresa_id', eid).order('plate', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('materiais')
            .select('id, codigo, nome, unidade, estoque_atual, estoque_minimo, custo_medio')
            .eq('empresa_id', eid)
            .eq('ativo', true)
            .gt('estoque_minimo', 0)
            .order('nome', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('compra_recebimentos')
            .select('id, valor')
            .eq('empresa_id', eid)
            .gte('data', isoDia(DateTime(hoje.year, hoje.month)))
            .order('id')
            .range(a, b)),
      ]);
      if (!mounted) return;
      setState(() {
        pedidos = r[0];
        fornecedores = r[1];
        veiculos = r[2];
        abaixoMinimo = r[3].where((m) => ((m['estoque_atual'] as num?) ?? 0) <= ((m['estoque_minimo'] as num?) ?? 0)).toList();
        compradoMes = r[4].fold<double>(0, (s, x) => s + ((x['valor'] as num?) ?? 0));
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar compras: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar as compras.';
      });
    }
  }

  Future<void> _novo() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => PedidoCompraFormPage(empresaId: empresaAtual!, fornecedores: fornecedores, veiculos: veiculos)),
    );
    if (id != null) {
      await _abrir(id);
    } else {
      _carregar(); // pode ter cadastrado fornecedor novo
    }
  }

  Future<void> _abrir(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PedidoCompraDetalhePage(pedidoId: id, fornecedores: fornecedores, veiculos: veiculos)),
    );
    _carregar();
  }

  /// Monta um rascunho com os materiais abaixo do mínimo (sugestão de compra).
  Future<void> _sugestao() async {
    final itens = [
      for (final m in abaixoMinimo) (m, quantidadeSugerida((m['estoque_atual'] as num?) ?? 0, (m['estoque_minimo'] as num?) ?? 0)),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Pedido com os itens abaixo do mínimo'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'A quantidade sugerida leva o estoque ao dobro do mínimo e o preço é o último custo médio. '
                'Você confere tudo no rascunho antes de enviar.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              for (final (m, q) in itens)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${qtdBr(q)} ${m['unidade']} — ${m['nome']} '
                      '(tem ${qtdBr(m['estoque_atual'] as num?)}, mínimo ${qtdBr(m['estoque_minimo'] as num?)})'),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Montar rascunho')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final eid = empresaAtual!;
    String? novoId;
    try {
      final novo = await supabase.from('pedidos_compra').insert({
        'empresa_id': eid,
        'categoria': 'pecas',
        'descricao': 'Reposição do estoque (abaixo do mínimo)',
        'data_pedido': isoDia(DateTime.now()),
      }).select('id').single();
      novoId = novo['id'].toString();
      await supabase.from('pedido_compra_itens').insert([
        for (final (m, q) in itens)
          {
            'empresa_id': eid,
            'pedido_id': novoId,
            'material_id': m['id'],
            'descricao': '${m['nome']}${m['codigo'] != null ? ' (${m['codigo']})' : ''}',
            'unidade': m['unidade'],
            'quantidade': q,
            'valor_unitario': (((m['custo_medio'] as num?) ?? 0) * 100).round() / 100,
          },
      ]);
      if (!mounted) return;
      showSuccess(context, 'Rascunho montado. Escolha o fornecedor e confira os preços.');
      await _abrir(novoId);
    } catch (e) {
      if (novoId != null) {
        try {
          await supabase.from('pedidos_compra').delete().eq('id', novoId);
        } catch (_) {}
      }
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível montar o pedido.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.can(AppPermission.viewSupplies)) {
      return Scaffold(appBar: AppBar(title: const Text('Compras')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso às compras.'));
    }
    final pode = auth.can(AppPermission.manageSupplies);
    final aguardando = pedidos.where((p) => p['status'] == 'aguardando').length;
    final aReceber = pedidos.where((p) => p['status'] == 'aprovado' || p['status'] == 'parcial').length;
    final termo = busca.toLowerCase();
    final lista = pedidos.where((p) {
      final s = p['status'];
      final ok = switch (filtro) {
        'andamento' => s != 'recebido' && s != 'cancelado',
        'aprovacao' => s == 'aguardando',
        'receber' => s == 'aprovado' || s == 'parcial',
        'recebidos' => s == 'recebido',
        'cancelados' => s == 'cancelado',
        _ => true,
      };
      return ok && (termo.isEmpty || 'nº ${p['numero']} ${p['fornecedores']?['nome'] ?? ''} ${p['descricao'] ?? ''}'.toLowerCase().contains(termo));
    }).toList();

    Widget card(String t, String v, Color cor) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12)),
            const SizedBox(height: 6),
            Text(v, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Compras'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
      ),
      floatingActionButton: pode && !carregando && erro == null
          ? FloatingActionButton.extended(onPressed: _novo, icon: const Icon(Icons.add_shopping_cart), label: const Text('Novo pedido'))
          : null,
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), children: [
                    if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (ctx, c) {
                      final col = c.maxWidth > 760 ? 4 : 2;
                      final w = (c.maxWidth - (col - 1) * 10) / col;
                      return Wrap(spacing: 10, runSpacing: 10, children: [
                        SizedBox(width: w, child: card('Aguardando aprovação', '$aguardando', aguardando > 0 ? AppColors.warning : AppColors.muted)),
                        SizedBox(width: w, child: card('A receber', '$aReceber', AppColors.info)),
                        SizedBox(width: w, child: card('Comprado no mês', moedaBr(compradoMes), AppColors.success)),
                        SizedBox(width: w, child: card('Abaixo do mínimo', '${abaixoMinimo.length}', abaixoMinimo.isNotEmpty ? AppColors.danger : AppColors.muted)),
                      ]);
                    }),
                    if (pode && abaixoMinimo.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      cartaoManut(
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              abaixoMinimo.length == 1
                                  ? '1 material está abaixo do mínimo no estoque.'
                                  : '${abaixoMinimo.length} materiais estão abaixo do mínimo no estoque.',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          botaoAcao('Montar pedido', Icons.playlist_add, AppColors.success, _sugestao),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por número, fornecedor ou descrição'),
                      onChanged: (v) => setState(() => busca = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final f in [
                        ('andamento', 'Em andamento'),
                        ('aprovacao', 'Aguardando aprovação ($aguardando)'),
                        ('receber', 'A receber ($aReceber)'),
                        ('recebidos', 'Recebidos'),
                        ('cancelados', 'Cancelados'),
                        ('todos', 'Todos'),
                      ])
                        ChoiceChip(label: Text(f.$2), selected: filtro == f.$1, onSelected: (_) => setState(() => filtro = f.$1)),
                    ]),
                    const SizedBox(height: 10),
                    if (lista.isEmpty)
                      vazioManut(Icons.shopping_cart_outlined, pedidos.isEmpty ? 'Nenhum pedido de compra ainda.' : 'Nenhum pedido aqui.'),
                    for (final p in lista) _cartao(p),
                  ]),
                ),
    );
  }

  Widget _cartao(Map<String, dynamic> p) {
    final st = statusCompra[p['status']] ?? ('${p['status']}', AppColors.muted);
    final forn = p['fornecedores']?['nome']?.toString();
    final emAberto = p['status'] == 'aprovado' || p['status'] == 'parcial';
    final atrasado = emAberto && p['previsao_entrega'] != null && diasParaVencer(p['previsao_entrega'].toString()) < 0;
    return cartaoManut(
      onTap: () => _abrir(p['id'].toString()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Pedido nº ${p['numero']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5))),
          if (atrasado) ...[chipStatus('Entrega atrasada', AppColors.danger), const SizedBox(width: 6)],
          chipStatus(st.$1, st.$2),
        ]),
        Text(forn ?? 'Fornecedor ainda não escolhido', style: TextStyle(color: forn == null ? AppColors.warning : AppColors.textSecondary)),
        if ((p['descricao'] ?? '').toString().isNotEmpty)
          Text(p['descricao'].toString(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        Row(children: [
          Text(moedaBr((p['valor_total'] as num?) ?? 0), style: const TextStyle(color: AppColors.neon, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                'pedido em ${dataBrManut(p['data_pedido']?.toString())}',
                if (emAberto && p['previsao_entrega'] != null) 'entrega até ${dataBrManut(p['previsao_entrega'].toString())}',
                if (p['data_recebimento'] != null) 'último recebimento ${dataBrManut(p['data_recebimento'].toString())}',
              ].join(' · '),
              style: TextStyle(color: atrasado ? AppColors.danger : AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Dados do pedido (novo ou rascunho) ──────────────────────────────────────
class PedidoCompraFormPage extends StatefulWidget {
  const PedidoCompraFormPage({super.key, required this.empresaId, required this.fornecedores, required this.veiculos, this.pedido});
  final String empresaId;
  final List<Map<String, dynamic>> fornecedores;
  final List<Map<String, dynamic>> veiculos;
  final Map<String, dynamic>? pedido;

  @override
  State<PedidoCompraFormPage> createState() => _PedidoCompraFormPageState();
}

class _PedidoCompraFormPageState extends State<PedidoCompraFormPage> {
  final _form = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  bool salvando = false;
  late final Map<String, dynamic> p = widget.pedido ?? {};
  late List<Map<String, dynamic>> forns = [...widget.fornecedores];
  late String? fornecedorId = p['fornecedor_id']?.toString();
  late String categoria = categoriasCompra.contains(p['categoria']) ? p['categoria'].toString() : 'pecas';
  late String? veiculoId = p['vehicle_id']?.toString();
  late DateTime? previsao = DateTime.tryParse(p['previsao_entrega']?.toString() ?? '');
  late final descricao = TextEditingController(text: p['descricao']?.toString() ?? '');
  late final parcelas = TextEditingController(text: '${p['parcelas'] ?? 1}');
  late final prazo = TextEditingController(text: '${p['prazo_dias'] ?? 30}');
  late final obs = TextEditingController(text: p['observacoes']?.toString() ?? '');

  Future<void> _novoFornecedor() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FornecedorFormPage(empresaId: widget.empresaId)));
    if (ok != true) return;
    try {
      final r = List<Map<String, dynamic>>.from(await supabase
          .from('fornecedores')
          .select('id, nome, ativo, created_at')
          .eq('empresa_id', widget.empresaId)
          .order('created_at', ascending: false));
      if (!mounted || r.isEmpty) return;
      setState(() {
        forns = [...r]..sort((a, b) => a['nome'].toString().toLowerCase().compareTo(b['nome'].toString().toLowerCase()));
        fornecedorId = r.first['id'].toString(); // o que acabou de ser cadastrado
      });
    } catch (_) {}
  }

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final dados = {
      'fornecedor_id': fornecedorId,
      'categoria': categoria,
      'vehicle_id': veiculoId,
      'descricao': descricao.text.trim(),
      'previsao_entrega': previsao == null ? null : isoDia(previsao!),
      'parcelas': int.parse(parcelas.text.trim()),
      'prazo_dias': int.parse(prazo.text.trim()),
      'observacoes': obs.text.trim(),
    };
    setState(() => salvando = true);
    try {
      String id;
      if (widget.pedido != null) {
        await supabase.from('pedidos_compra').update(dados).eq('id', p['id']);
        id = p['id'].toString();
      } else {
        final novo = await supabase
            .from('pedidos_compra')
            .insert({...dados, 'empresa_id': widget.empresaId, 'data_pedido': isoDia(DateTime.now())})
            .select('id')
            .single();
        id = novo['id'].toString();
      }
      if (!mounted) return;
      showSuccess(context, widget.pedido != null ? 'Pedido atualizado.' : 'Pedido criado. Agora inclua os itens.');
      Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      showErrorFrom(context, e, prefix: 'Não foi possível salvar.');
      setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.pedido != null;
    String? inteiro(String? v, int min, int max) {
      final n = int.tryParse((v ?? '').trim());
      return n == null || n < min || n > max ? '$min a $max' : null;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(editando ? 'Pedido nº ${p['numero']}' : 'Novo pedido de compra'), backgroundColor: AppColors.surface),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('forn-$fornecedorId-${forns.length}'),
                    initialValue: fornecedorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Fornecedor (obrigatório para enviar)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Escolher depois')),
                      for (final f in forns.where((f) => f['ativo'] != false || f['id'].toString() == fornecedorId))
                        DropdownMenuItem<String?>(value: f['id'].toString(), child: Text(f['nome'].toString(), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => fornecedorId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton.filledTonal(tooltip: 'Cadastrar fornecedor', icon: const Icon(Icons.person_add_alt_1), onPressed: _novoFornecedor),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: categoria,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Categoria (vai para o contas a pagar)'),
                    items: [
                      for (final c in categoriasCompra) DropdownMenuItem(value: c, child: Text(categoriasPagar[c]?.$1 ?? c)),
                    ],
                    onChanged: (v) => setState(() => categoria = v ?? 'pecas'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: veiculoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Veículo (custo por veículo)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Não é de um veículo')),
                      for (final v in widget.veiculos) DropdownMenuItem<String?>(value: v['id'].toString(), child: Text(v['plate'].toString())),
                    ],
                    onChanged: (v) => setState(() => veiculoId = v),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              TextFormField(controller: descricao, decoration: const InputDecoration(labelText: 'Descrição', hintText: 'Ex.: filtros para a revisão dos caminhões')),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(previsao == null ? 'Previsão de entrega: não informada' : 'Previsão de entrega: ${dataBrManut(isoDia(previsao!))}'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: previsao ?? DateTime.now().add(const Duration(days: 3)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (d != null) setState(() => previsao = d);
                },
              ),
              const SizedBox(height: 14),
              const Text('Condição de pagamento combinada', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: parcelas,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Parcelas'),
                    validator: (v) => inteiro(v, 1, 120),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: prazo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '1º vencimento em (dias)', hintText: '0 = à vista'),
                    validator: (v) => inteiro(v, 0, 365),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              TextFormField(controller: obs, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: salvando ? null : _salvar,
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: Text(editando ? 'Salvar alterações' : 'Criar pedido e incluir itens'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Detalhe do pedido: itens, etapas, recebimentos e histórico ──────────────
class PedidoCompraDetalhePage extends StatefulWidget {
  const PedidoCompraDetalhePage({super.key, required this.pedidoId, required this.fornecedores, required this.veiculos});
  final String pedidoId;
  final List<Map<String, dynamic>> fornecedores;
  final List<Map<String, dynamic>> veiculos;

  @override
  State<PedidoCompraDetalhePage> createState() => _PedidoCompraDetalhePageState();
}

class _PedidoCompraDetalhePageState extends State<PedidoCompraDetalhePage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? pedido;
  List<Map<String, dynamic>> itens = [];
  List<Map<String, dynamic>> recebimentos = [];
  List<Map<String, dynamic>> historico = [];
  List<Map<String, dynamic>> contas = [];
  List<Map<String, dynamic>>? materiais;
  String? empresaNome;
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await Future.wait([
        supabase.from('pedidos_compra').select('*, fornecedores(nome, telefone, contato), vehicles(plate)').eq('id', widget.pedidoId).single(),
        supabase.from('pedido_compra_itens').select('*').eq('pedido_id', widget.pedidoId).order('created_at', ascending: true),
        supabase.from('compra_recebimentos').select('*').eq('pedido_id', widget.pedidoId).order('created_at', ascending: true),
        supabase.from('pedido_compra_historico').select('*').eq('pedido_id', widget.pedidoId).order('created_at', ascending: true),
        supabase.from('contas_pagar').select('id, status').eq('pedido_compra_id', widget.pedidoId),
      ]);
      final p = Map<String, dynamic>.from(r[0] as Map);
      if (empresaNome == null) {
        try {
          final e = await supabase.from('empresas').select('nome').eq('id', p['empresa_id']).maybeSingle();
          empresaNome = e?['nome']?.toString();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        pedido = p;
        itens = List<Map<String, dynamic>>.from(r[1] as List);
        recebimentos = List<Map<String, dynamic>>.from(r[2] as List);
        historico = List<Map<String, dynamic>>.from(r[3] as List);
        contas = List<Map<String, dynamic>>.from(r[4] as List);
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => carregando = false);
      showErrorFrom(context, e, prefix: 'Não foi possível abrir o pedido.');
    }
  }

  Future<bool?> _confirmar(String titulo, String texto, String botao, {bool perigo = false}) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(
              style: perigo ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(botao),
            ),
          ],
        ),
      );

  Future<void> _item([Map<String, dynamic>? item]) async {
    final p = pedido!;
    if (materiais == null) {
      try {
        materiais = List<Map<String, dynamic>>.from(await supabase
            .from('materiais')
            .select('id, codigo, nome, unidade, custo_medio, estoque_atual')
            .eq('empresa_id', p['empresa_id'])
            .eq('ativo', true)
            .order('nome', ascending: true));
      } catch (_) {
        materiais = [];
      }
    }
    if (!mounted) return;
    final mats = materiais!;
    var doEstoque = item == null ? mats.isNotEmpty : item['material_id'] != null;
    String? matId = item?['material_id']?.toString();
    var unidade = item?['unidade']?.toString() ?? 'un';
    if (!unidadesMaterial.containsKey(unidade)) unidade = 'un';
    final desc = TextEditingController(text: item != null && item['material_id'] == null ? item['descricao'].toString() : '');
    final qtd = TextEditingController(text: item == null ? '1' : qtdBr(item['quantidade'] as num));
    final valor = TextEditingController(text: item == null ? '' : numeroBr(item['valor_unitario'] as num));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final sel = mats.where((m) => m['id'].toString() == matId).firstOrNull;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(item == null ? 'Incluir item' : 'Editar item'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Do estoque'), icon: Icon(Icons.inventory_2)),
                      ButtonSegment(value: false, label: Text('Avulso'), icon: Icon(Icons.receipt_long)),
                    ],
                    selected: {doEstoque},
                    onSelectionChanged: (s) => setD(() => doEstoque = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (doEstoque) ...[
                    if (mats.isEmpty)
                      const Text('Nenhum material cadastrado no estoque. Cadastre em Suprimentos → Estoque ou use "Avulso".',
                          style: TextStyle(color: AppColors.warning))
                    else
                      DropdownButtonFormField<String>(
                        initialValue: sel == null ? null : matId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Material *'),
                        items: [
                          for (final m in mats)
                            DropdownMenuItem(
                              value: m['id'].toString(),
                              child: Text(
                                '${m['codigo'] != null ? '${m['codigo']} · ' : ''}${m['nome']} (tem ${qtdBr(m['estoque_atual'] as num?)} ${m['unidade']})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setD(() {
                          matId = v;
                          final m = mats.where((x) => x['id'].toString() == v).firstOrNull;
                          final custo = (m?['custo_medio'] as num?) ?? 0;
                          if (valor.text.trim().isEmpty && custo > 0) valor.text = numeroBr(custo);
                        }),
                      ),
                    if (sel != null) ...[
                      const SizedBox(height: 6),
                      Text('Último custo médio: ${moedaBr((sel['custo_medio'] as num?) ?? 0)} por ${sel['unidade']}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ] else ...[
                    TextField(
                      controller: desc,
                      decoration: const InputDecoration(labelText: 'Descrição *', hintText: 'Ex.: frete, mão de obra, item sem controle de estoque'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: unidade,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unidade'),
                      items: [for (final u in unidadesMaterial.entries) DropdownMenuItem(value: u.key, child: Text('${u.key} (${u.value})'))],
                      onChanged: (v) => setD(() => unidade = v ?? 'un'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: qtd,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Quantidade${doEstoque && sel != null ? ' (${sel['unidade']})' : ''} *'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: valor,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Preço unitário (R\$) *'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final q = numeroBrDe(qtd.text);
    final v = numeroBrDe(valor.text);
    final sel = mats.where((m) => m['id'].toString() == matId).firstOrNull;
    if (doEstoque && sel == null) {
      showError(context, 'Escolha o material.');
      return;
    }
    if (!doEstoque && desc.text.trim().length < 2) {
      showError(context, 'Descreva o item.');
      return;
    }
    if (q == null || q <= 0) {
      showError(context, 'Informe a quantidade.');
      return;
    }
    if (v == null || v < 0) {
      showError(context, 'Informe o preço unitário.');
      return;
    }
    final dados = <String, dynamic>{
      'material_id': doEstoque ? sel!['id'] : null,
      'descricao': doEstoque ? '${sel!['nome']}${sel['codigo'] != null ? ' (${sel['codigo']})' : ''}' : desc.text.trim(),
      'unidade': doEstoque ? sel!['unidade'] : unidade,
      'quantidade': q,
      'valor_unitario': v,
    };
    try {
      if (item == null) {
        await supabase.from('pedido_compra_itens').insert({...dados, 'pedido_id': widget.pedidoId, 'empresa_id': p['empresa_id']});
      } else {
        await supabase.from('pedido_compra_itens').update(dados).eq('id', item['id']);
      }
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível salvar o item.');
    }
  }

  Future<void> _removerItem(Map<String, dynamic> item) async {
    try {
      await supabase.from('pedido_compra_itens').delete().eq('id', item['id']);
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível remover o item.');
    }
  }

  Future<void> _mudarStatus(String novo) async {
    final p = pedido!;
    final total = moedaBr((p['valor_total'] as num?) ?? 0);
    final textos = switch (novo) {
      'aguardando' => (
          'Enviar para aprovação?',
          'O pedido de $total vai para o administrador aprovar. Depois de enviado, os itens só mudam voltando para rascunho.',
          'Enviar'
        ),
      'aprovado' => (
          'Aprovar o pedido?',
          'Pedido de $total para ${p['fornecedores']?['nome'] ?? 'o fornecedor'}. Aprovado, ele já pode ser mandado ao fornecedor e recebido.',
          'Aprovar'
        ),
      'rascunho' => p['status'] == 'aprovado'
          ? ('Reabrir o pedido?', 'A aprovação é desfeita: depois de alterar, o pedido precisa ser aprovado de novo.', 'Reabrir')
          : ('Voltar para rascunho?', 'O pedido volta para edição.', 'Voltar para rascunho'),
      'cancelado' => ('Cancelar o pedido?', 'O pedido fica cancelado e não pode mais ser recebido.', 'Cancelar pedido'),
      _ => (
          'Encerrar o pedido?',
          'O que faltou entregar não será mais recebido neste pedido. O que já chegou continua no estoque e no contas a pagar.',
          'Encerrar'
        ),
    };
    final ok = await _confirmar(textos.$1, textos.$2, textos.$3, perigo: novo == 'cancelado');
    if (ok != true) return;
    try {
      await supabase.from('pedidos_compra').update({'status': novo}).eq('id', widget.pedidoId);
      if (!mounted) return;
      showSuccess(context, switch (novo) {
        'aguardando' => 'Pedido enviado para aprovação.',
        'aprovado' => 'Pedido aprovado.',
        'rascunho' => 'Pedido de volta ao rascunho.',
        'cancelado' => 'Pedido cancelado.',
        _ => 'Pedido encerrado.',
      });
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível mudar o pedido.');
    }
  }

  Future<void> _reprovar() async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reprovar o pedido?'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: motivo, maxLines: 3, decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ex.: preço acima do combinado')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reprovar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (motivo.text.trim().isEmpty) {
      showError(context, 'Informe o motivo da reprovação.');
      return;
    }
    try {
      await supabase.from('pedidos_compra').update({'status': 'reprovado', 'motivo_reprovacao': motivo.text.trim()}).eq('id', widget.pedidoId);
      if (mounted) showSuccess(context, 'Pedido reprovado.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível reprovar.');
    }
  }

  Future<void> _excluir() async {
    final ok = await _confirmar('Excluir o rascunho?', 'O pedido e os itens são apagados.', 'Excluir', perigo: true);
    if (ok != true) return;
    try {
      await supabase.from('pedidos_compra').delete().eq('id', widget.pedidoId);
      if (!mounted) return;
      showSuccess(context, 'Rascunho excluído.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível excluir.');
    }
  }

  Future<void> _editar() async {
    final r = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoCompraFormPage(
          empresaId: pedido!['empresa_id'].toString(),
          fornecedores: widget.fornecedores,
          veiculos: widget.veiculos,
          pedido: pedido,
        ),
      ),
    );
    if (r != null) _carregar();
  }

  Future<void> _mudarPrevisao() async {
    final atual = DateTime.tryParse(pedido!['previsao_entrega']?.toString() ?? '');
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: atual != null && atual.isAfter(DateTime(2020)) ? atual : hoje,
      firstDate: DateTime(2020),
      lastDate: hoje.add(const Duration(days: 730)),
    );
    if (d == null) return;
    try {
      await supabase.from('pedidos_compra').update({'previsao_entrega': isoDia(d)}).eq('id', widget.pedidoId);
      if (mounted) showSuccess(context, 'Previsão de entrega: ${dataBrManut(isoDia(d))}.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível mudar a previsão.');
    }
  }

  Future<void> _receber() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ReceberPedidoPage(pedido: pedido!, itens: itens)));
    if (ok == true) _carregar();
  }

  Future<void> _whatsapp() async {
    final f = pedido!['fornecedores'];
    var n = soDigitos(f?['telefone']?.toString() ?? '');
    if (n.isEmpty) {
      showError(context, 'O fornecedor não tem telefone cadastrado (Financeiro → Fornecedores).');
      return;
    }
    if (n.length == 10 || n.length == 11) n = '55$n';
    final texto = textoPedidoFornecedor(pedido: pedido!, itens: itens, empresa: empresaNome, contato: f?['contato']?.toString());
    final uri = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(texto)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showError(context, 'Não foi possível abrir o WhatsApp.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (pedido == null) return Scaffold(appBar: AppBar(), body: vazioManut(Icons.error_outline, 'Pedido não encontrado.'));
    final p = pedido!;
    final auth = context.read<AppAuthProvider>();
    final pode = auth.can(AppPermission.manageSupplies);
    final aprova = auth.can(AppPermission.approvePurchases);
    final status = p['status'].toString();
    final st = statusCompra[status] ?? (status, AppColors.muted);
    final rascunho = status == 'rascunho';
    final forn = p['fornecedores'];
    final recebido = recebimentos.fold<double>(0, (s, r) => s + ((r['valor'] as num?) ?? 0));
    final contasAtivas = contas.where((c) => c['status'] != 'cancelada').length;
    final contasPagas = contas.where((c) => c['status'] == 'paga').length;
    final emAberto = status == 'aprovado' || status == 'parcial';
    final atrasado = emAberto && p['previsao_entrega'] != null && diasParaVencer(p['previsao_entrega'].toString()) < 0;
    final parcelas = (p['parcelas'] as num?)?.toInt() ?? 1;
    final prazo = (p['prazo_dias'] as num?)?.toInt() ?? 30;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Pedido de compra nº ${p['numero']}'),
        backgroundColor: AppColors.surface,
        actions: [
          if (pode && rascunho) IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar dados do pedido', onPressed: _editar),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar),
        ],
      ),
      floatingActionButton: pode && rascunho
          ? FloatingActionButton.extended(onPressed: () => _item(), icon: const Icon(Icons.add), label: const Text('Incluir item'))
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
            cartaoManut(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  chipStatus(categoriasPagar[p['categoria']]?.$1 ?? '${p['categoria']}', AppColors.secondary),
                  const Spacer(),
                  if (atrasado) ...[chipStatus('Entrega atrasada', AppColors.danger), const SizedBox(width: 6)],
                  chipStatus(st.$1, st.$2),
                ]),
                const SizedBox(height: 10),
                Text(
                  forn?['nome']?.toString() ?? 'Fornecedor ainda não escolhido',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: forn == null ? AppColors.warning : null),
                ),
                if ((p['descricao'] ?? '').toString().isNotEmpty) Text(p['descricao'].toString(), style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  [
                    'pedido em ${dataBrManut(p['data_pedido']?.toString())}',
                    if (p['previsao_entrega'] != null) 'entrega até ${dataBrManut(p['previsao_entrega'].toString())}',
                    if (p['vehicles'] != null) 'veículo ${p['vehicles']['plate']}',
                  ].join(' · '),
                  style: TextStyle(color: atrasado ? AppColors.danger : AppColors.textSecondary),
                ),
                Text('Pagamento: ${parcelas > 1 ? '${parcelas}x, ' : ''}${prazo == 0 ? 'à vista' : '1º vencimento em $prazo dias'}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                if (p['aprovado_em'] != null)
                  Text('Aprovado por ${p['aprovado_por_nome'] ?? '-'} em ${dataHoraBr(p['aprovado_em'].toString())}',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                if ((p['motivo_reprovacao'] ?? '').toString().isNotEmpty && (status == 'reprovado' || rascunho))
                  Text('Reprovado: ${p['motivo_reprovacao']}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                if ((p['observacoes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Obs.: ${p['observacoes']}', style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ]),
            ),
            _titulo('Itens'),
            if (itens.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Nenhum item ainda. Toque em "Incluir item".', style: TextStyle(color: AppColors.textSecondary)),
              ),
            for (final i in itens) _cartaoItem(i, editavel: pode && rascunho),
            cartaoManut(
              child: Column(children: [
                _linhaTotal('Total do pedido', moedaBr((p['valor_total'] as num?) ?? 0), destaque: true),
                if (recebimentos.isNotEmpty) _linhaTotal('Já recebido', moedaBr(recebido)),
                if (contas.isNotEmpty)
                  _linhaTotal('Contas a pagar',
                      '$contasAtivas ${contasAtivas == 1 ? 'conta' : 'contas'} · $contasPagas ${contasPagas == 1 ? 'paga' : 'pagas'}'),
              ]),
            ),
            if (pode) _acoes(status, aprova),
            if (recebimentos.isNotEmpty) ...[
              _titulo('Recebimentos'),
              for (final r in recebimentos) _cartaoRecebimento(r),
            ],
            if (historico.isNotEmpty) ...[
              _titulo('Histórico'),
              cartaoManut(child: Column(children: [for (final h in historico) _linhaHistorico(h)])),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _acoes(String status, bool aprova) {
    final b = <Widget>[
      if (status == 'rascunho') ...[
        if (aprova)
          botaoAcao('Aprovar pedido', Icons.verified, AppColors.success, () => _mudarStatus('aprovado'))
        else
          botaoAcao('Enviar para aprovação', Icons.send, AppColors.info, () => _mudarStatus('aguardando')),
        botaoAcao('Excluir rascunho', Icons.delete_outline, AppColors.danger, _excluir),
      ],
      if (status == 'aguardando') ...[
        if (aprova) ...[
          botaoAcao('Aprovar', Icons.verified, AppColors.success, () => _mudarStatus('aprovado')),
          botaoAcao('Reprovar', Icons.block, AppColors.danger, _reprovar),
        ],
        botaoAcao('Voltar para rascunho', Icons.undo, AppColors.muted, () => _mudarStatus('rascunho')),
      ],
      if (status == 'reprovado') botaoAcao('Reabrir para corrigir', Icons.edit_note, AppColors.info, () => _mudarStatus('rascunho')),
      if (status == 'aprovado' || status == 'parcial') ...[
        botaoAcao(status == 'parcial' ? 'Receber o restante' : 'Receber mercadoria', Icons.move_to_inbox, AppColors.success, _receber),
        botaoAcao('Enviar ao fornecedor', Icons.chat, AppColors.secondary, _whatsapp),
        botaoAcao('Mudar previsão de entrega', Icons.event, AppColors.info, _mudarPrevisao),
      ],
      if (status == 'aprovado') botaoAcao('Reabrir para alterar', Icons.edit_note, AppColors.warning, () => _mudarStatus('rascunho')),
      if (status == 'parcial') botaoAcao('Encerrar com o que chegou', Icons.done_all, AppColors.warning, () => _mudarStatus('recebido')),
      if (status == 'aguardando' || status == 'reprovado' || status == 'aprovado')
        botaoAcao('Cancelar pedido', Icons.close, AppColors.danger, () => _mudarStatus('cancelado')),
    ];
    if (b.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Wrap(spacing: 8, runSpacing: 8, children: b));
  }

  Widget _cartaoItem(Map<String, dynamic> i, {required bool editavel}) {
    final q = (i['quantidade'] as num?) ?? 0;
    final rec = (i['quantidade_recebida'] as num?) ?? 0;
    final v = (i['valor_unitario'] as num?) ?? 0;
    final un = i['unidade']?.toString() ?? 'un';
    final mostrarRecebido = pedido!['status'] == 'aprovado' || pedido!['status'] == 'parcial' || pedido!['status'] == 'recebido' || rec > 0;
    return cartaoManut(
      onTap: editavel ? () => _item(i) : null,
      child: Row(children: [
        Icon(i['material_id'] != null ? Icons.inventory_2 : Icons.receipt_long, color: AppColors.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i['descricao'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${qtdBr(q)} $un × ${moedaBr(v)}${i['material_id'] == null ? ' · avulso (não entra no estoque)' : ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            if (mostrarRecebido)
              Text(
                rec >= q ? '✓ recebido' : 'recebido ${qtdBr(rec)} de ${qtdBr(q)} $un',
                style: TextStyle(color: rec >= q ? AppColors.success : AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600),
              ),
          ]),
        ),
        Text(moedaBr((q * v * 100).round() / 100), style: const TextStyle(fontWeight: FontWeight.bold)),
        if (editavel)
          IconButton(tooltip: 'Remover item', icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: () => _removerItem(i)),
      ]),
    );
  }

  Widget _cartaoRecebimento(Map<String, dynamic> r) {
    final itensR = (r['itens'] as List?) ?? const [];
    final valor = (r['valor'] as num?) ?? 0;
    final parcelas = (r['parcelas'] as num?)?.toInt() ?? 0;
    final forma = (r['forma_pagamento'] ?? '').toString();
    return cartaoManut(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.move_to_inbox, color: AppColors.success),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${dataBrManut(r['data']?.toString())}${(r['nota_fiscal'] ?? '').toString().isNotEmpty ? ' · NF ${r['nota_fiscal']}' : ''} · ${moedaBr(valor)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              valor <= 0
                  ? 'sem valor a pagar'
                  : r['pago'] == true
                      ? 'pago na entrega${forma.isNotEmpty ? ' ($forma)' : ''}'
                      : parcelas == 1
                          ? '1 parcela no contas a pagar · vencimento ${dataBrManut(r['primeiro_vencimento']?.toString())}'
                          : '$parcelas parcelas no contas a pagar · 1º vencimento ${dataBrManut(r['primeiro_vencimento']?.toString())}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            for (final i in itensR)
              Text('• ${qtdBr(i['quantidade'] as num?)} ${i['unidade'] ?? ''} ${i['descricao']}${i['estoque'] == true ? ' → estoque' : ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            if ((r['usuario_nome'] ?? '').toString().isNotEmpty)
              Text('por ${r['usuario_nome']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _linhaHistorico(Map<String, dynamic> h) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 10, color: statusCompra[h['status_para']]?.$2 ?? AppColors.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h['descricao'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${h['usuario_nome'] ?? '-'} · ${dataHoraBr(h['created_at']?.toString())}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            ]),
          ),
        ]),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(t, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _linhaTotal(String t, String v, {bool destaque = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(t, style: TextStyle(color: destaque ? Colors.white : AppColors.textSecondary, fontWeight: destaque ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text(v, style: TextStyle(color: destaque ? AppColors.neon : Colors.white, fontWeight: FontWeight.bold, fontSize: destaque ? 18 : 14)),
        ]),
      );
}

// ── Recebimento: quanto chegou, nota fiscal e pagamento ─────────────────────
class ReceberPedidoPage extends StatefulWidget {
  const ReceberPedidoPage({super.key, required this.pedido, required this.itens});
  final Map<String, dynamic> pedido;
  final List<Map<String, dynamic>> itens;

  @override
  State<ReceberPedidoPage> createState() => _ReceberPedidoPageState();
}

class _ReceberPedidoPageState extends State<ReceberPedidoPage> {
  final supabase = Supabase.instance.client;
  late final pendentes = widget.itens.where((i) => pendenteItem(i) > 0).toList();
  late final Map<String, TextEditingController> qtds = {
    for (final i in pendentes) i['id'].toString(): TextEditingController(text: qtdBr(pendenteItem(i))),
  };
  final nota = TextEditingController();
  late final parcelas = TextEditingController(text: '${widget.pedido['parcelas'] ?? 1}');
  DateTime data = DateTime.now();
  late DateTime vencimento = DateTime.now().add(Duration(days: (widget.pedido['prazo_dias'] as num?)?.toInt() ?? 30));
  String? forma;
  bool pago = false;
  bool salvando = false;

  double get total => pendentes.fold<double>(0, (s, i) {
        final q = numeroBrDe(qtds[i['id'].toString()]!.text) ?? 0;
        return s + (q * ((i['valor_unitario'] as num?) ?? 0) * 100).round() / 100;
      });

  Future<void> _confirmar() async {
    final itensRpc = <Map<String, dynamic>>[];
    for (final i in pendentes) {
      final q = numeroBrDe(qtds[i['id'].toString()]!.text) ?? 0;
      if (q < 0) {
        showError(context, 'Quantidade inválida em "${i['descricao']}".');
        return;
      }
      if (q > pendenteItem(i) + 0.0005) {
        showError(context, 'Em "${i['descricao']}" faltam só ${qtdBr(pendenteItem(i))} ${i['unidade']}.');
        return;
      }
      if (q > 0) itensRpc.add({'item_id': i['id'], 'quantidade': q});
    }
    if (itensRpc.isEmpty) {
      showError(context, 'Informe a quantidade de pelo menos um item.');
      return;
    }
    final n = int.tryParse(parcelas.text.trim());
    if (!pago && (n == null || n < 1 || n > 120)) {
      showError(context, 'Parcelas: de 1 a 120.');
      return;
    }
    setState(() => salvando = true);
    try {
      final r = await supabase.rpc('receber_pedido_compra', params: {
        'p_pedido': widget.pedido['id'],
        'p_itens': itensRpc,
        'p_nota': nota.text.trim(),
        'p_data': isoDia(data),
        'p_vencimento': isoDia(pago ? data : vencimento),
        'p_parcelas': pago ? 1 : n,
        'p_forma': forma,
        'p_pago': pago,
      });
      if (!mounted) return;
      showSuccess(
        context,
        (r is Map && r['status'] == 'recebido')
            ? 'Pedido recebido: estoque e contas a pagar atualizados.'
            : 'Recebimento registrado. O que falta continua pendente no pedido.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showErrorFrom(context, e, prefix: 'Não foi possível registrar o recebimento.');
      setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Receber pedido nº ${p['numero']}'), backgroundColor: AppColors.surface),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(p['fornecedores']?['nome']?.toString() ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Os materiais do estoque entram pelo preço do pedido (o custo médio é recalculado) e o valor vai para o contas a pagar. '
              'Se veio só uma parte, ajuste as quantidades: o resto fica pendente.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            if (pendentes.isEmpty) vazioManut(Icons.check_circle_outline, 'Nada pendente neste pedido.'),
            for (final i in pendentes)
              cartaoManut(
                child: Row(children: [
                  Icon(i['material_id'] != null ? Icons.inventory_2 : Icons.receipt_long, color: AppColors.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i['descricao'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        'pedido ${qtdBr(i['quantidade'] as num?)} ${i['unidade']} · já chegou ${qtdBr(i['quantidade_recebida'] as num?)} · '
                        '${moedaBr((i['valor_unitario'] as num?) ?? 0)} cada',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: qtds[i['id'].toString()],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Chegou (${i['unidade']})'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            const Text('Nota fiscal', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: nota, decoration: const InputDecoration(labelText: 'Número da NF'))),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('Chegou em ${dataBrManut(isoDia(data))}'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: data, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) setState(() => data = d);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Pagamento', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: pago,
              onChanged: (v) => setState(() => pago = v),
              title: const Text('Já foi pago na entrega (à vista)'),
              subtitle: const Text('A conta entra no contas a pagar já como paga.'),
            ),
            const SizedBox(height: 8),
            if (!pago)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: parcelas,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Parcelas'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('1º vencimento: ${dataBrManut(isoDia(vencimento))}'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: vencimento,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (d != null) setState(() => vencimento = d);
                    },
                  ),
                ),
              ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: forma,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Forma de pagamento'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Não informar')),
                for (final f in formasPagamento) DropdownMenuItem<String?>(value: f, child: Text(f)),
              ],
              onChanged: (v) => setState(() => forma = v),
            ),
            const SizedBox(height: 18),
            cartaoManut(
              child: Row(children: [
                const Text('Valor deste recebimento', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(moedaBr(total), style: const TextStyle(color: AppColors.neon, fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: salvando || pendentes.isEmpty ? null : _confirmar,
                icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.move_to_inbox),
                label: const Text('Confirmar recebimento'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

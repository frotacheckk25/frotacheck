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

/// Estoque de materiais (almoxarifado): materiais, entradas, saídas, ajustes e histórico.
/// Saldo e custo médio são calculados pelo banco (docs/MIGRATION_ESTOQUE.sql).
const categoriasMaterial = {
  'peca': 'Peça',
  'filtro': 'Filtro',
  'lubrificante': 'Lubrificante',
  'pneu': 'Pneu',
  'ferramenta': 'Ferramenta',
  'limpeza': 'Limpeza',
  'escritorio': 'Escritório',
  'outros': 'Outros',
};

const unidadesMaterial = {
  'un': 'unidade',
  'L': 'litro',
  'kg': 'quilo',
  'm': 'metro',
  'cx': 'caixa',
  'par': 'par',
  'jogo': 'jogo',
  'galão': 'galão',
  'balde': 'balde',
};

/// Quantidade sem zeros sobrando: "12", "2,5", "1.000,125".
String qtdBr(num? q) {
  if (q == null) return '-';
  if (q % 1 == 0) return numeroBr(q, casas: 0);
  var s = numeroBr(q, casas: 3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith(',') ? s.substring(0, s.length - 1) : s;
}

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> materiais = [];
  List<Map<String, dynamic>> fornecedores = [];
  List<Map<String, dynamic>> veiculos = [];
  int movimentosMes = 0;
  String filtro = 'ativos';
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
        fetchAllRows((a, b) => supabase.from('materiais').select('*').eq('empresa_id', eid).order('nome', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('fornecedores').select('id, nome, ativo').eq('empresa_id', eid).order('nome', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate').eq('empresa_id', eid).order('plate', ascending: true).order('id').range(a, b)),
      ]);
      final mov = await supabase.from('estoque_movimentos').select('id').eq('empresa_id', eid)
          .gte('data', isoDia(DateTime(hoje.year, hoje.month))).count();
      if (!mounted) return;
      setState(() {
        materiais = r[0];
        fornecedores = r[1];
        veiculos = r[2];
        movimentosMes = mov.count;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar estoque: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar o estoque.';
      });
    }
  }

  bool _abaixoMinimo(Map<String, dynamic> m) {
    final min = (m['estoque_minimo'] as num?) ?? 0;
    return min > 0 && ((m['estoque_atual'] as num?) ?? 0) <= min;
  }

  Future<void> _abrirMaterial([Map<String, dynamic>? m]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MaterialFormPage(empresaId: empresaAtual!, material: m, fornecedores: fornecedores)),
    );
    if (ok == true) _carregar();
  }

  Future<void> _movimentar(Map<String, dynamic> m, String tipo) async {
    final qtd = TextEditingController();
    final custo = TextEditingController(text: tipo == 'entrada' && ((m['custo_medio'] as num?) ?? 0) > 0 ? numeroBr(m['custo_medio'] as num) : '');
    final doc = TextEditingController();
    final obs = TextEditingController();
    String? fornecedorId;
    String? veiculoId;
    final un = m['unidade']?.toString() ?? 'un';
    final atual = (m['estoque_atual'] as num?) ?? 0;
    final titulo = switch (tipo) { 'entrada' => 'Entrada no estoque', 'saida' => 'Saída do estoque', _ => 'Ajuste de inventário' };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(titulo),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${m['nome']} · em estoque: ${qtdBr(atual)} $un', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: qtd,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tipo == 'ajuste' ? 'Quantidade contada no inventário ($un) *' : 'Quantidade ($un) *'),
                ),
                if (tipo == 'entrada') ...[
                  const SizedBox(height: 10),
                  TextField(controller: custo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Custo por $un (R\$) *')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: fornecedorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Fornecedor'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Não informar')),
                      for (final f in fornecedores.where((f) => f['ativo'] != false))
                        DropdownMenuItem<String?>(value: f['id'].toString(), child: Text(f['nome'].toString(), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setD(() => fornecedorId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: doc, decoration: const InputDecoration(labelText: 'Nota fiscal / documento')),
                ],
                if (tipo == 'saida') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: veiculoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Usado em qual veículo?'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Não é de um veículo')),
                      for (final v in veiculos) DropdownMenuItem<String?>(value: v['id'].toString(), child: Text(v['plate'].toString())),
                    ],
                    onChanged: (v) => setD(() => veiculoId = v),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(controller: obs, decoration: InputDecoration(labelText: tipo == 'ajuste' ? 'Motivo do ajuste *' : 'Observações')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final q = numeroBrDe(qtd.text);
    final c = numeroBrDe(custo.text);
    if (q == null || q < 0 || (tipo != 'ajuste' && q == 0)) {
      showError(context, 'Informe uma quantidade válida.');
      return;
    }
    if (tipo == 'entrada' && (c == null || c < 0)) {
      showError(context, 'Informe o custo unitário.');
      return;
    }
    if (tipo == 'ajuste' && obs.text.trim().isEmpty) {
      showError(context, 'Informe o motivo do ajuste.');
      return;
    }
    final quantidade = tipo == 'ajuste' ? q - atual : q;
    if (quantidade == 0) {
      showError(context, 'A contagem é igual ao estoque atual. Nada a ajustar.');
      return;
    }
    try {
      await supabase.from('estoque_movimentos').insert({
        'empresa_id': m['empresa_id'],
        'material_id': m['id'],
        'tipo': tipo,
        'quantidade': quantidade,
        if (tipo == 'entrada') 'custo_unitario': c,
        'fornecedor_id': ?fornecedorId,
        'vehicle_id': ?veiculoId,
        'documento': doc.text.trim(),
        'observacoes': obs.text.trim(),
      });
      if (mounted) showSuccess(context, '$titulo registrada.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível registrar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.can(AppPermission.viewSupplies)) {
      return Scaffold(appBar: AppBar(title: const Text('Estoque')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso ao estoque.'));
    }
    final pode = auth.can(AppPermission.manageSupplies);
    final ativos = materiais.where((m) => m['ativo'] != false).toList();
    final valorEstoque = ativos.fold<double>(0, (s, m) => s + ((m['estoque_atual'] as num?) ?? 0) * ((m['custo_medio'] as num?) ?? 0));
    final abaixo = ativos.where(_abaixoMinimo).length;
    final termo = busca.toLowerCase();
    final lista = materiais.where((m) {
      final ok = switch (filtro) {
        'ativos' => m['ativo'] != false,
        'abaixo' => m['ativo'] != false && _abaixoMinimo(m),
        _ => m['ativo'] == false,
      };
      return ok && (termo.isEmpty || '${m['codigo'] ?? ''} ${m['nome']} ${m['localizacao'] ?? ''}'.toLowerCase().contains(termo));
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
        title: const Text('Estoque de materiais'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
      ),
      floatingActionButton: pode && !carregando && erro == null
          ? FloatingActionButton.extended(onPressed: () => _abrirMaterial(), icon: const Icon(Icons.add), label: const Text('Novo material'))
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
                        SizedBox(width: w, child: card('Materiais ativos', '${ativos.length}', AppColors.info)),
                        SizedBox(width: w, child: card('Valor em estoque', moedaBr(valorEstoque), AppColors.success)),
                        SizedBox(width: w, child: card('Abaixo do mínimo', '$abaixo', abaixo > 0 ? AppColors.danger : AppColors.muted)),
                        SizedBox(width: w, child: card('Movimentos no mês', '$movimentosMes', AppColors.secondary)),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por código, nome ou local'),
                      onChanged: (v) => setState(() => busca = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final f in [('ativos', 'Ativos'), ('abaixo', 'Abaixo do mínimo ($abaixo)'), ('inativos', 'Inativos')])
                        ChoiceChip(label: Text(f.$2), selected: filtro == f.$1, onSelected: (_) => setState(() => filtro = f.$1)),
                    ]),
                    const SizedBox(height: 10),
                    if (lista.isEmpty)
                      vazioManut(Icons.inventory_2_outlined, materiais.isEmpty ? 'Nenhum material cadastrado ainda.' : 'Nenhum material aqui.'),
                    for (final m in lista) _cartao(m, pode),
                  ]),
                ),
    );
  }

  Widget _cartao(Map<String, dynamic> m, bool pode) {
    final un = m['unidade']?.toString() ?? 'un';
    final atual = (m['estoque_atual'] as num?) ?? 0;
    final custo = (m['custo_medio'] as num?) ?? 0;
    final baixo = _abaixoMinimo(m);
    return cartaoManut(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${m['codigo'] != null ? '${m['codigo']} · ' : ''}${m['nome']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
          ),
          if (baixo) chipStatus('Abaixo do mínimo', AppColors.danger),
        ]),
        Text(
          [
            categoriasMaterial[m['categoria']] ?? m['categoria'],
            if ((m['localizacao'] ?? '').toString().isNotEmpty) 'local: ${m['localizacao']}',
          ].join(' · '),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 18, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text('${qtdBr(atual)} $un', style: TextStyle(color: baixo ? AppColors.danger : AppColors.neon, fontSize: 20, fontWeight: FontWeight.bold)),
          Text('mínimo ${qtdBr(m['estoque_minimo'] as num?)} $un', style: const TextStyle(color: AppColors.textSecondary)),
          Text('custo médio ${moedaBr(custo)}', style: const TextStyle(color: AppColors.textSecondary)),
          Text('em estoque ${moedaBr(atual * custo)}', style: const TextStyle(color: AppColors.textSecondary)),
        ]),
        if (pode) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            botaoAcao('Entrada', Icons.add_box, AppColors.success, () => _movimentar(m, 'entrada')),
            botaoAcao('Saída', Icons.outbox, AppColors.warning, () => _movimentar(m, 'saida')),
            botaoAcao('Ajuste', Icons.fact_check, AppColors.info, () => _movimentar(m, 'ajuste')),
            botaoAcao('Histórico', Icons.history, AppColors.secondary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoricoMaterialPage(material: m)))),
            botaoAcao('Editar', Icons.edit, AppColors.muted, () => _abrirMaterial(m)),
          ]),
        ],
      ]),
    );
  }
}

// ── Cadastro de material ────────────────────────────────────────────────────
class MaterialFormPage extends StatefulWidget {
  const MaterialFormPage({super.key, required this.empresaId, this.material, required this.fornecedores});
  final String empresaId;
  final Map<String, dynamic>? material;
  final List<Map<String, dynamic>> fornecedores;

  @override
  State<MaterialFormPage> createState() => _MaterialFormPageState();
}

class _MaterialFormPageState extends State<MaterialFormPage> {
  final _form = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  bool salvando = false;
  late final Map<String, dynamic> m = widget.material ?? {};
  late String categoria = m['categoria']?.toString() ?? 'peca';
  late String unidade = m['unidade']?.toString() ?? 'un';
  late bool ativo = m['ativo'] != false;
  late final codigo = TextEditingController(text: m['codigo']?.toString() ?? '');
  late final nome = TextEditingController(text: m['nome']?.toString() ?? '');
  late final minimo = TextEditingController(text: m['estoque_minimo'] != null ? qtdBr(m['estoque_minimo'] as num) : '');
  late final local = TextEditingController(text: m['localizacao']?.toString() ?? '');
  late final obs = TextEditingController(text: m['observacoes']?.toString() ?? '');
  final inicial = TextEditingController();
  final custoInicial = TextEditingController();

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final dados = {
      'codigo': codigo.text.trim(),
      'nome': nome.text.trim(),
      'categoria': categoria,
      'unidade': unidade,
      'estoque_minimo': numeroBrDe(minimo.text) ?? 0,
      'localizacao': local.text.trim(),
      'observacoes': obs.text.trim(),
      'ativo': ativo,
    };
    final qIni = numeroBrDe(inicial.text);
    final cIni = numeroBrDe(custoInicial.text);
    setState(() => salvando = true);
    try {
      if (widget.material != null) {
        await supabase.from('materiais').update(dados).eq('id', m['id']);
      } else {
        final novo = await supabase.from('materiais').insert({...dados, 'empresa_id': widget.empresaId}).select('id').single();
        if (qIni != null && qIni > 0) {
          await supabase.from('estoque_movimentos').insert({
            'empresa_id': widget.empresaId,
            'material_id': novo['id'],
            'tipo': 'entrada',
            'quantidade': qIni,
            'custo_unitario': cIni ?? 0,
            'observacoes': 'Estoque inicial',
          });
        }
      }
      if (!mounted) return;
      showSuccess(context, widget.material != null ? 'Material atualizado.' : 'Material cadastrado.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('materiais_empresa_codigo_uq')) {
        showError(context, 'Já existe um material com este código.');
      } else {
        showErrorFrom(context, e, prefix: 'Não foi possível salvar.');
      }
      setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.material != null;
    String? numValido(String? v, {bool obrigatorio = false}) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return obrigatorio ? 'Obrigatório' : null;
      final n = numeroBrDe(t);
      return n == null || n < 0 ? 'Número inválido' : null;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(editando ? 'Editar material' : 'Novo material'), backgroundColor: AppColors.surface),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 170, child: TextFormField(controller: codigo, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Código'))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: nome,
                    decoration: const InputDecoration(labelText: 'Nome do material *', hintText: 'Ex.: filtro de óleo PSL 616'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o nome' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: categoria,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [for (final c in categoriasMaterial.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
                    onChanged: (v) => setState(() => categoria = v ?? 'peca'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: unidade,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: [for (final u in unidadesMaterial.entries) DropdownMenuItem(value: u.key, child: Text('${u.key} (${u.value})'))],
                    onChanged: (v) => setState(() => unidade = v ?? 'un'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: TextFormField(controller: minimo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Estoque mínimo (avisa quando chegar)'), validator: numValido)),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: local, decoration: const InputDecoration(labelText: 'Local (prateleira, galpão...)'))),
              ]),
              const SizedBox(height: 14),
              if (!editando) ...[
                const Text('Estoque inicial (opcional)', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: TextFormField(controller: inicial, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantidade que já tem'), validator: numValido)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: custoInicial, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Custo por unidade (R\$)'), validator: numValido)),
                ]),
                const SizedBox(height: 14),
              ],
              TextFormField(controller: obs, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
              if (editando)
                SwitchListTile(value: ativo, onChanged: (v) => setState(() => ativo = v), title: const Text('Material ativo')),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: salvando ? null : _salvar,
                  icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: Text(editando ? 'Salvar alterações' : 'Cadastrar material'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Histórico de um material ────────────────────────────────────────────────
class HistoricoMaterialPage extends StatefulWidget {
  const HistoricoMaterialPage({super.key, required this.material});
  final Map<String, dynamic> material;

  @override
  State<HistoricoMaterialPage> createState() => _HistoricoMaterialPageState();
}

class _HistoricoMaterialPageState extends State<HistoricoMaterialPage> {
  List<Map<String, dynamic>>? movs;

  @override
  void initState() {
    super.initState();
    Supabase.instance.client
        .from('estoque_movimentos')
        .select('*, vehicles(plate), fornecedores(nome), ordens_servico(numero)')
        .eq('material_id', widget.material['id'])
        .order('created_at', ascending: false)
        .limit(500)
        .then((r) {
      if (mounted) setState(() => movs = List<Map<String, dynamic>>.from(r));
    }).catchError((e) {
      if (mounted) {
        setState(() => movs = []);
        showErrorFrom(context, e, prefix: 'Não foi possível carregar o histórico.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final un = widget.material['unidade']?.toString() ?? 'un';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Histórico · ${widget.material['nome']}'), backgroundColor: AppColors.surface),
      body: movs == null
          ? const Center(child: CircularProgressIndicator())
          : movs!.isEmpty
              ? vazioManut(Icons.history, 'Sem movimentos ainda.')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final mv in movs!)
                    cartaoManut(
                      child: Row(children: [
                        Icon(
                          switch (mv['tipo']) { 'entrada' => Icons.add_box, 'saida' => Icons.outbox, _ => Icons.fact_check },
                          color: switch (mv['tipo']) { 'entrada' => AppColors.success, 'saida' => AppColors.warning, _ => AppColors.info },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '${switch (mv['tipo']) { 'entrada' => 'Entrada', 'saida' => 'Saída', _ => 'Ajuste' }} · '
                              '${(mv['tipo'] == 'saida' || ((mv['quantidade'] as num) < 0)) ? '−' : '+'}${qtdBr((mv['quantidade'] as num).abs())} $un · '
                              '${dataBrManut(mv['data']?.toString())}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              [
                                'saldo ${qtdBr(mv['saldo_apos'] as num?)} $un',
                                if (mv['valor_total'] != null) moedaBr(mv['valor_total'] as num),
                                if (mv['fornecedores'] != null) mv['fornecedores']['nome'].toString(),
                                if (mv['vehicles'] != null) 'veículo ${mv['vehicles']['plate']}',
                                if (mv['ordens_servico'] != null) 'OS nº ${mv['ordens_servico']['numero']}',
                                if ((mv['documento'] ?? '').toString().isNotEmpty) 'doc. ${mv['documento']}',
                                if ((mv['observacoes'] ?? '').toString().isNotEmpty) mv['observacoes'].toString(),
                              ].join(' · '),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                ]),
    );
  }
}

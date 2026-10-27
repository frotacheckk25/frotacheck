import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/snackbar_utils.dart';
import 'manutencao_comum.dart';
import 'ordens_servico_page.dart';

/// Plano de manutenção preventiva por veículo (óleo, filtros, freios...), com
/// intervalo em km e/ou dias. Mostra o que está vencido/próximo na frota toda
/// e abre a OS direto do item. Tabela: plano_preventivo.
class PlanoPreventivoPage extends StatefulWidget {
  const PlanoPreventivoPage({super.key});

  @override
  State<PlanoPreventivoPage> createState() => _PlanoPreventivoPageState();
}

class _PlanoPreventivoPageState extends State<PlanoPreventivoPage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> itens = [];
  Map<String, Map<String, dynamic>> veiculos = {};
  String? veiculoSel; // null = frota toda

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
        fetchAllRows((a, b) => supabase.from('plano_preventivo').select('*').eq('empresa_id', eid).order('nome', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate, brand, model, odometer').eq('empresa_id', eid)
            .order('plate', ascending: true).order('id').range(a, b)),
      ]);
      if (!mounted) return;
      setState(() {
        itens = r[0];
        veiculos = {for (final v in r[1]) v['id'].toString(): v};
        if (veiculoSel != null && !veiculos.containsKey(veiculoSel)) veiculoSel = null;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar plano preventivo: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar o plano preventivo.';
      });
    }
  }

  num? _odometro(Map<String, dynamic> item) => veiculos[item['vehicle_id']?.toString()]?['odometer'] as num?;

  Future<void> _abrirOs(Map<String, dynamic> item) async {
    final criada = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => OsFormPage(
          empresaId: empresaAtual!,
          veiculos: veiculos.values.toList(),
          inicial: {
            'vehicle_id': item['vehicle_id'],
            'tipo': 'preventiva',
            'descricao': item['nome'],
            'km': (_odometro(item))?.round(),
            'plano_item_id': item['id'],
          },
        ),
      ),
    );
    if (criada != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => OsDetalhePage(osId: criada, veiculos: veiculos)));
      _carregar();
    }
  }

  Future<void> _registrarRealizacao(Map<String, dynamic> item) async {
    final km = TextEditingController(text: (_odometro(item))?.round().toString() ?? '');
    var data = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Registrar: ${item['nome']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Use quando o serviço foi feito sem OS no sistema (ex.: antes de começar a usar o FrotaCheck).',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(controller: km, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Km em que foi feito')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Data: ${dataBrManut(isoDia(data))}'),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: data, firstDate: DateTime(2015), lastDate: DateTime.now());
                if (d != null) setD(() => data = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final kmNum = km.text.trim().isEmpty ? null : int.tryParse(km.text.trim());
    if (km.text.trim().isNotEmpty && (kmNum == null || kmNum < 0 || kmNum > 3000000)) {
      if (mounted) showError(context, 'Km inválido (só números).');
      return;
    }
    try {
      await supabase.from('plano_preventivo').update({'ultima_km': kmNum, 'ultima_data': isoDia(data)}).eq('id', item['id']);
      if (mounted) showSuccess(context, 'Realização registrada.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível registrar.');
    }
  }

  Future<void> _editarItem([Map<String, dynamic>? item]) async {
    final vid = item?['vehicle_id']?.toString() ?? veiculoSel;
    if (vid == null) return;
    final nome = TextEditingController(text: item?['nome']?.toString() ?? '');
    final km = TextEditingController(text: item?['intervalo_km']?.toString() ?? '');
    final dias = TextEditingController(text: item?['intervalo_dias']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(item == null ? 'Novo item do plano' : 'Editar item do plano'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Serviço *', hintText: 'Ex.: troca do filtro de ar')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: km, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'A cada (km)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: dias, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ou a cada (dias)'))),
            ]),
            const SizedBox(height: 8),
            const Text('Preencha km, dias ou os dois (vale o que vencer primeiro).', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final kmN = km.text.trim().isEmpty ? null : int.tryParse(km.text.trim());
    final diasN = dias.text.trim().isEmpty ? null : int.tryParse(dias.text.trim());
    if (nome.text.trim().length < 2) {
      if (mounted) showError(context, 'Informe o nome do serviço.');
      return;
    }
    if ((kmN == null && diasN == null) || (km.text.trim().isNotEmpty && (kmN == null || kmN < 100)) || (dias.text.trim().isNotEmpty && (diasN == null || diasN < 1))) {
      if (mounted) showError(context, 'Informe o intervalo em km (mínimo 100) ou em dias.');
      return;
    }
    final dados = {'nome': nome.text.trim(), 'intervalo_km': kmN, 'intervalo_dias': diasN};
    try {
      if (item == null) {
        await supabase.from('plano_preventivo').insert({...dados, 'vehicle_id': vid, 'empresa_id': empresaAtual});
      } else {
        await supabase.from('plano_preventivo').update(dados).eq('id', item['id']);
      }
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível salvar o item.');
    }
  }

  Future<void> _excluirItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Excluir item do plano?'),
        content: Text('"${item['nome']}" sai do plano deste veículo. As OS já feitas continuam no histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('plano_preventivo').delete().eq('id', item['id']);
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível excluir.');
    }
  }

  Future<void> _aplicarPadrao(String vid) async {
    try {
      await supabase.from('plano_preventivo').insert([
        for (final p in planoPadraoCaminhao)
          {'empresa_id': empresaAtual, 'vehicle_id': vid, 'nome': p.$1, 'intervalo_km': p.$2, 'intervalo_dias': p.$3},
      ]);
      if (mounted) showSuccess(context, 'Plano padrão aplicado. Ajuste os intervalos e registre a última realização de cada item.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível aplicar o plano.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (auth.isMotorista || !auth.can(AppPermission.manageMaintenance)) {
      return Scaffold(appBar: AppBar(title: const Text('Plano preventivo')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso ao plano preventivo.'));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Plano preventivo'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
      ),
      floatingActionButton: !carregando && erro == null && veiculoSel != null
          ? FloatingActionButton.extended(onPressed: () => _editarItem(), icon: const Icon(Icons.add), label: const Text('Novo item'))
          : null,
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                    if (mostrarSeletorEmpresa) seletorEmpresa(() {
                      veiculoSel = null;
                      _carregar();
                    }),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: DropdownButtonFormField<String?>(
                        initialValue: veiculoSel,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Veículo', prefixIcon: Icon(Icons.local_shipping)),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Toda a frota (o que precisa de atenção)')),
                          for (final v in veiculos.values)
                            DropdownMenuItem<String?>(value: v['id'].toString(), child: Text('${v['plate']} · ${v['brand'] ?? ''} ${v['model'] ?? ''}')),
                        ],
                        onChanged: (v) => setState(() => veiculoSel = v),
                      ),
                    ),
                    ...(veiculoSel == null ? _visaoFrota() : _visaoVeiculo(veiculoSel!)),
                  ]),
                ),
    );
  }

  List<Widget> _visaoFrota() {
    final analisados = [
      for (final i in itens.where((i) => i['ativo'] != false)) (i, analisarPlano(i, _odometro(i))),
    ];
    final atencao = analisados.where((x) => x.$2.situacao == SituacaoPlano.vencido || x.$2.situacao == SituacaoPlano.proximo).toList()
      ..sort((a, b) => a.$2.situacao.index.compareTo(b.$2.situacao.index));
    final vencidos = analisados.where((x) => x.$2.situacao == SituacaoPlano.vencido).length;
    final proximos = analisados.where((x) => x.$2.situacao == SituacaoPlano.proximo).length;
    final semRegistro = analisados.where((x) => x.$2.situacao == SituacaoPlano.semRegistro).length;
    final semPlano = veiculos.keys.where((id) => !itens.any((i) => i['vehicle_id']?.toString() == id)).length;

    Widget card(String t, String v, Color cor) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12)),
              const SizedBox(height: 6),
              Text(v, style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.bold)),
            ]),
          ),
        );

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          card('Vencidos', '$vencidos', AppColors.danger),
          const SizedBox(width: 8),
          card('Próximos', '$proximos', AppColors.warning),
          const SizedBox(width: 8),
          card('Sem registro', '$semRegistro', AppColors.muted),
        ]),
      ),
      if (semPlano > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('$semPlano veículo(s) ainda sem plano. Escolha o veículo acima e toque em "Aplicar plano padrão".',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
      if (atencao.isEmpty)
        vazioManut(Icons.verified, itens.isEmpty ? 'Nenhum plano cadastrado ainda. Escolha um veículo acima para começar.' : 'Nada vencido ou próximo. Frota em dia!'),
      for (final x in atencao) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _cartaoItem(x.$1, x.$2, mostrarVeiculo: true)),
    ];
  }

  List<Widget> _visaoVeiculo(String vid) {
    final v = veiculos[vid];
    final doVeiculo = itens.where((i) => i['vehicle_id']?.toString() == vid).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text('Odômetro atual: ${kmBr(v?['odometer'] as num?)}', style: const TextStyle(color: AppColors.textSecondary)),
      ),
      if (doVeiculo.isEmpty) ...[
        vazioManut(Icons.event_repeat, 'Este veículo ainda não tem plano preventivo.'),
        Center(child: botaoAcao('Aplicar plano padrão de caminhão', Icons.auto_fix_high, AppColors.secondary, () => _aplicarPadrao(vid))),
      ],
      for (final i in doVeiculo) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _cartaoItem(i, analisarPlano(i, v?['odometer'] as num?))),
    ];
  }

  Widget _cartaoItem(Map<String, dynamic> i, AnalisePlano a, {bool mostrarVeiculo = false}) {
    final v = veiculos[i['vehicle_id']?.toString()];
    final intervalo = [
      if (i['intervalo_km'] != null) 'a cada ${kmBr(i['intervalo_km'] as num)}',
      if (i['intervalo_dias'] != null) 'a cada ${i['intervalo_dias']} dias',
    ].join(' ou ');
    return cartaoManut(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(mostrarVeiculo ? '${v?['plate'] ?? '-'} · ${i['nome']}' : i['nome'].toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
          ),
          chipStatus(a.rotulo, a.cor),
        ]),
        const SizedBox(height: 4),
        Text(intervalo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(
          a.situacao == SituacaoPlano.semRegistro
              ? 'Última realização não informada'
              : 'Última: ${i['ultima_km'] != null ? kmBr(i['ultima_km'] as num) : ''}${i['ultima_data'] != null ? ' em ${dataBrManut(i['ultima_data'].toString())}' : ''}'
                  '${a.resumo.isNotEmpty ? ' · ${a.resumo}' : ''}',
          style: TextStyle(color: a.situacao == SituacaoPlano.vencido ? AppColors.danger : AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          botaoAcao('Abrir OS', Icons.build_circle, AppColors.secondary, () => _abrirOs(i)),
          botaoAcao('Registrar realização', Icons.check, AppColors.success, () => _registrarRealizacao(i)),
          if (!mostrarVeiculo) botaoAcao('Editar', Icons.edit, AppColors.info, () => _editarItem(i)),
          if (!mostrarVeiculo) botaoAcao('Excluir', Icons.delete_outline, AppColors.danger, () => _excluirItem(i)),
        ]),
      ]),
    );
  }
}

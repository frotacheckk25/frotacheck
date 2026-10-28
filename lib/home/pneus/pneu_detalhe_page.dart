import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import '../manutencoes/manutencao_comum.dart';
import 'pneu_comum.dart';

/// Detalhe de um pneu: dados, km rodado e custo por km, ações de movimentação
/// (montar, desmontar, rodízio, sulco, recapagem, conserto, descarte) e histórico.
/// As movimentações passam pela função movimentar_pneu do banco.
class PneuDetalhePage extends StatefulWidget {
  const PneuDetalhePage({super.key, required this.pneuId});
  final String pneuId;

  @override
  State<PneuDetalhePage> createState() => _PneuDetalhePageState();
}

class _PneuDetalhePageState extends State<PneuDetalhePage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? pneu;
  List<Map<String, dynamic>> movs = [];
  Map<String, Map<String, dynamic>> veiculos = {};
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final p = Map<String, dynamic>.from(await supabase.from('pneus').select('*').eq('id', widget.pneuId).single());
      final r = await Future.wait([
        supabase.from('pneu_movimentacoes').select('*').eq('pneu_id', widget.pneuId).order('created_at', ascending: false),
        supabase.from('vehicles').select('id, plate, brand, model, odometer').eq('empresa_id', p['empresa_id']).order('plate', ascending: true),
      ]);
      if (!mounted) return;
      setState(() {
        pneu = p;
        movs = List<Map<String, dynamic>>.from(r[0] as List);
        veiculos = {for (final v in r[1] as List) v['id'].toString(): Map<String, dynamic>.from(v as Map)};
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => carregando = false);
      showErrorFrom(context, e, prefix: 'Não foi possível abrir o pneu.');
    }
  }

  /// Ações disponíveis em cada situação.
  List<(String, String, IconData, Color)> get _acoes {
    switch (pneu?['situacao']) {
      case 'em_uso':
        return const [
          ('desmontagem', 'Desmontar', Icons.remove_circle_outline, AppColors.warning),
          ('rodizio', 'Rodízio', Icons.swap_horiz, AppColors.secondary),
          ('medicao', 'Medir sulco', Icons.straighten, AppColors.info),
          ('conserto', 'Conserto', Icons.handyman_outlined, AppColors.info),
        ];
      case 'estoque':
        return const [
          ('montagem', 'Montar', Icons.build_circle_outlined, AppColors.success),
          ('medicao', 'Medir sulco', Icons.straighten, AppColors.info),
          ('recapagem_envio', 'Enviar para recapagem', Icons.local_shipping_outlined, AppColors.warning),
          ('recapagem', 'Registrar recapagem', Icons.autorenew, AppColors.secondary),
          ('conserto', 'Conserto', Icons.handyman_outlined, AppColors.info),
          ('descarte', 'Descartar', Icons.delete_forever_outlined, AppColors.danger),
        ];
      case 'recapagem':
        return const [
          ('recapagem', 'Voltou da recapagem', Icons.autorenew, AppColors.success),
          ('descarte', 'Descartar', Icons.delete_forever_outlined, AppColors.danger),
        ];
      default:
        return const [];
    }
  }

  Future<void> _movimentar(String tipo, String rotulo) async {
    final p = pneu!;
    final veiculoAtual = veiculos[p['vehicle_id']?.toString()];
    String? veiculoId = tipo == 'montagem' ? null : p['vehicle_id']?.toString();
    String? posicao;
    final km = TextEditingController(
        text: tipo == 'montagem' ? '' : (veiculoAtual?['odometer'] as num?)?.round().toString() ?? '');
    final sulco = TextEditingController();
    final custo = TextEditingController();
    final obs = TextEditingController();

    final pedeVeiculo = tipo == 'montagem';
    final pedePosicao = tipo == 'montagem' || tipo == 'rodizio';
    final pedeKm = const {'montagem', 'desmontagem', 'rodizio', 'medicao', 'conserto'}.contains(tipo);
    final kmObrigatorio = tipo == 'montagem' || tipo == 'desmontagem';
    final pedeSulco = const {'montagem', 'desmontagem', 'rodizio', 'medicao', 'recapagem'}.contains(tipo);
    final sulcoObrigatorio = tipo == 'medicao' || tipo == 'recapagem';
    final pedeCusto = tipo == 'recapagem' || tipo == 'conserto';
    final obsObrigatoria = tipo == 'descarte';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(rotulo),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (pedeVeiculo) ...[
                  DropdownButtonFormField<String>(
                    initialValue: veiculoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Veículo *'),
                    items: [
                      for (final v in veiculos.values)
                        DropdownMenuItem(value: v['id'].toString(), child: Text('${v['plate']} · ${v['brand'] ?? ''} ${v['model'] ?? ''}')),
                    ],
                    onChanged: (v) => setD(() {
                      veiculoId = v;
                      final odo = (veiculos[v]?['odometer'] as num?)?.round();
                      if (odo != null) km.text = odo.toString();
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                if (pedePosicao) ...[
                  DropdownButtonFormField<String>(
                    initialValue: posicao,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tipo == 'rodizio' ? 'Nova posição *' : 'Posição *'),
                    items: [
                      for (final pos in posicoesPneu.where((x) => x != p['posicao'])) DropdownMenuItem(value: pos, child: Text(pos)),
                    ],
                    onChanged: (v) => setD(() => posicao = v),
                  ),
                  if (tipo == 'rodizio')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Se a posição já tiver pneu, os dois trocam de lugar.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  const SizedBox(height: 10),
                ],
                if (pedeKm) ...[
                  TextField(
                    controller: km,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: kmObrigatorio ? 'Km do veículo *' : 'Km do veículo'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (pedeSulco) ...[
                  TextField(
                    controller: sulco,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: sulcoObrigatorio ? 'Sulco (mm) *' : 'Sulco medido (mm)'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (pedeCusto) ...[
                  TextField(
                    controller: custo,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Custo (R\$)'),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: obs,
                  decoration: InputDecoration(
                    labelText: obsObrigatoria ? 'Motivo do descarte *' : (tipo == 'recapagem_envio' ? 'Recapadora' : 'Observações'),
                  ),
                ),
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

    final kmN = km.text.trim().isEmpty ? null : lerInteiroBr(km.text.trim());
    final sulcoN = numeroBrDe(sulco.text);
    final custoN = numeroBrDe(custo.text);
    String? erro;
    if (pedeVeiculo && veiculoId == null) erro = 'Escolha o veículo.';
    if (pedePosicao && posicao == null) erro = 'Escolha a posição.';
    if (km.text.trim().isNotEmpty && (kmN == null || kmN < 0)) erro = 'Km inválido (só números).';
    if (kmObrigatorio && kmN == null) erro = 'Informe o km do veículo.';
    if (sulco.text.trim().isNotEmpty && (sulcoN == null || sulcoN < 0 || sulcoN > 40)) erro = 'Sulco inválido (0 a 40 mm).';
    if (sulcoObrigatorio && sulcoN == null) erro = 'Informe o sulco em mm.';
    if (custo.text.trim().isNotEmpty && (custoN == null || custoN < 0)) erro = 'Custo inválido.';
    if (obsObrigatoria && obs.text.trim().isEmpty) erro = 'Informe o motivo do descarte.';
    if (erro != null) {
      showError(context, erro);
      return;
    }
    try {
      await supabase.rpc('movimentar_pneu', params: {
        'p_pneu': widget.pneuId,
        'p_tipo': tipo,
        'p_vehicle': veiculoId,
        'p_posicao': posicao,
        'p_km': kmN,
        'p_sulco': sulcoN,
        'p_custo': custoN,
        'p_obs': obs.text.trim(),
      });
      if (mounted) showSuccess(context, '$rotulo registrado.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível registrar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(pneu?['numero_fogo'] != null ? 'Pneu fogo nº ${pneu!['numero_fogo']}' : 'Pneu'),
        backgroundColor: AppColors.surface,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : pneu == null
              ? vazioManut(Icons.error_outline, 'Pneu não encontrado.')
              : _conteudo(),
    );
  }

  Widget _conteudo() {
    final p = pneu!;
    final st = situacoesPneu[p['situacao']] ?? ('${p['situacao']}', AppColors.muted);
    final v = veiculos[p['vehicle_id']?.toString()];
    final a = analisarPneu(p, v?['odometer'] as num?, movs);
    final alerta = alertaSulco(p['sulco_mm'] as num?);

    Widget info(String t, String valor) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            SizedBox(width: 150, child: Text(t, style: const TextStyle(color: AppColors.textSecondary))),
            Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          cartaoManut(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${p['marca'] ?? ''} ${p['modelo'] ?? ''}'.trim(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (alerta != null) ...[chipStatus(alerta.$1, alerta.$2), const SizedBox(width: 6)],
                chipStatus(st.$1, st.$2),
              ]),
              const SizedBox(height: 6),
              info('Número de fogo', p['numero_fogo']?.toString() ?? 'não informado'),
              info('Medida', p['medida']?.toString() ?? '-'),
              info('Onde está', p['situacao'] == 'em_uso' ? '${v?['plate'] ?? '-'} · ${p['posicao'] ?? '-'}' : st.$1),
              info('Sulco atual', p['sulco_mm'] != null ? '${numeroBr(p['sulco_mm'] as num, casas: 1)} mm' : '-'),
              info('Recapagens', '${p['recapagens'] ?? 0}'),
            ]),
          ),
          Row(children: [
            Expanded(child: _numero('Km rodado', '${numeroBr(a.kmTotal, casas: 0)} km', AppColors.info)),
            const SizedBox(width: 8),
            Expanded(child: _numero('Custo total', moedaBr(a.custoTotal), AppColors.warning)),
            const SizedBox(width: 8),
            Expanded(child: _numero('Custo por km', a.custoPorKm == null ? '-' : 'R\$ ${numeroBr(a.custoPorKm!, casas: 3)}', AppColors.success)),
          ]),
          const SizedBox(height: 4),
          const Text('Custo = compra + recapagens + consertos. Km = todas as montagens.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          if (_acoes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final ac in _acoes) botaoAcao(ac.$2, ac.$3, ac.$4, () => _movimentar(ac.$1, ac.$2)),
            ]),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 18, bottom: 8),
            child: Text('Histórico', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          if (movs.isEmpty) const Text('Sem movimentações registradas.', style: TextStyle(color: AppColors.textSecondary)),
          for (final m in movs) _linhaMov(m),
        ]),
      ),
    );
  }

  Widget _numero(String t, String v, Color cor) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12)),
          const SizedBox(height: 6),
          Text(v, style: TextStyle(color: cor, fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _linhaMov(Map<String, dynamic> m) {
    final tipo = movimentacoesPneu[m['tipo']] ?? ('${m['tipo']}', Icons.circle_outlined);
    final v = veiculos[m['vehicle_id']?.toString()];
    final detalhes = [
      if (v != null) '${v['plate']}${m['posicao'] != null ? ' · ${m['posicao']}' : ''}',
      if (m['km_veiculo'] != null) kmBr(m['km_veiculo'] as num),
      if (m['km_rodado'] != null) 'rodou ${kmBr(m['km_rodado'] as num)}',
      if (m['sulco_mm'] != null) 'sulco ${numeroBr(m['sulco_mm'] as num, casas: 1)} mm',
      if (m['custo'] != null) moedaBr(m['custo'] as num),
      if ((m['observacoes'] ?? '').toString().isNotEmpty) m['observacoes'].toString(),
    ].join(' · ');
    return cartaoManut(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(tipo.$2, color: AppColors.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tipo.$1} · ${dataBrManut(m['data']?.toString())}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (detalhes.isNotEmpty) Text(detalhes, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

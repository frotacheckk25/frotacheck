import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../manutencoes/manutencao_comum.dart';

/// Consumo da frota: km/l, custo por km e alertas, calculados a partir dos
/// abastecimentos já registrados (sem tabela nova).
///
/// Método do "tanque cheio": a distância entre dois abastecimentos do mesmo
/// veículo dividida pelos litros do segundo dá o km/l daquele trecho.
/// Cada veículo é comparado com a própria média (caminhão e carro gastam
/// diferente), e trechos com odômetro voltando ou pulando demais são
/// apontados como "odômetro inconsistente" em vez de entrar na conta.
class ConsumoFrotaPage extends StatefulWidget {
  const ConsumoFrotaPage({super.key});

  @override
  State<ConsumoFrotaPage> createState() => _ConsumoFrotaPageState();
}

/// Um trecho entre dois abastecimentos do mesmo veículo.
class TrechoConsumo {
  TrechoConsumo({required this.abastecimento, required this.km, required this.litros, required this.valor});
  final Map<String, dynamic> abastecimento; // o abastecimento que fecha o trecho
  final double km;
  final double litros;
  final double valor;
  double get kmPorLitro => litros > 0 ? km / litros : 0;
  DateTime? get data => DateTime.tryParse(abastecimento['fuel_date']?.toString() ?? '');
}

class ResultadoConsumo {
  final trechos = <String, List<TrechoConsumo>>{}; // por veículo
  final inconsistentes = <Map<String, dynamic>>[]; // odômetro voltou/pulou
}

/// Limite de km entre dois abastecimentos acima do qual o odômetro é tratado
/// como erro de digitação (nenhum tanque de caminhão roda tanto).
const kmMaximoTrecho = 5000;

ResultadoConsumo calcularConsumo(List<Map<String, dynamic>> abastecimentos) {
  final r = ResultadoConsumo();
  final porVeiculo = <String, List<Map<String, dynamic>>>{};
  for (final a in abastecimentos) {
    final vid = a['vehicle_id']?.toString();
    if (vid == null) continue;
    porVeiculo.putIfAbsent(vid, () => []).add(a);
  }
  porVeiculo.forEach((vid, lista) {
    lista.sort((a, b) {
      final d = (a['fuel_date'] ?? '').toString().compareTo((b['fuel_date'] ?? '').toString());
      if (d != 0) return d;
      final t = (a['fuel_time'] ?? '').toString().compareTo((b['fuel_time'] ?? '').toString());
      if (t != 0) return t;
      return ((a['odometer'] as num?) ?? 0).compareTo((b['odometer'] as num?) ?? 0);
    });
    Map<String, dynamic>? anterior;
    for (final a in lista) {
      final odo = (a['odometer'] as num?)?.toDouble() ?? 0;
      final litros = (a['liters'] as num?)?.toDouble() ?? 0;
      if (odo <= 0) continue; // sem odômetro: não dá para medir
      if (anterior != null) {
        final km = odo - ((anterior['odometer'] as num?)?.toDouble() ?? 0);
        if (km <= 0 || km > kmMaximoTrecho) {
          // Leitura suspeita: não serve de ponto de partida para o próximo
          // trecho (senão a média sai distorcida). Recomeça no próximo abastecimento.
          r.inconsistentes.add(a);
          anterior = null;
          continue;
        } else if (litros > 0) {
          r.trechos.putIfAbsent(vid, () => []).add(TrechoConsumo(
                abastecimento: a,
                km: km,
                litros: litros,
                valor: (a['total_value'] as num?)?.toDouble() ?? 0,
              ));
        }
      }
      anterior = a;
    }
  });
  return r;
}

double mediaKmL(Iterable<TrechoConsumo> t) {
  final km = t.fold<double>(0, (s, x) => s + x.km), l = t.fold<double>(0, (s, x) => s + x.litros);
  return l > 0 ? km / l : 0;
}

String kmL(double v) => v <= 0 ? '-' : '${numeroBr(v, casas: 2)} km/l';

class _ConsumoFrotaPageState extends State<ConsumoFrotaPage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> abastecimentos = [];
  Map<String, Map<String, dynamic>> veiculos = {};
  Map<String, String> motoristas = {};
  int dias = 90; // 0 = todo o histórico

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
        fetchAllRows((a, b) => supabase.from('fuelings').select('id, vehicle_id, driver_id, fuel_date, fuel_time, liters, total_value, odometer')
            .eq('empresa_id', eid).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate, brand, model').eq('empresa_id', eid).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('drivers').select('id, name').eq('empresa_id', eid).order('id').range(a, b)),
      ]);
      if (!mounted) return;
      setState(() {
        abastecimentos = r[0];
        veiculos = {for (final v in r[1]) v['id'].toString(): v};
        motoristas = {for (final m in r[2]) m['id'].toString(): m['name']?.toString() ?? ''};
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar consumo: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar os abastecimentos.';
      });
    }
  }

  bool _noPeriodo(DateTime? d) {
    if (dias == 0) return true;
    if (d == null) return false;
    return !d.isBefore(DateTime.now().subtract(Duration(days: dias)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (auth.isMotorista) {
      return Scaffold(appBar: AppBar(title: const Text('Consumo da frota')), body: vazioManut(Icons.lock_outline, 'Disponível para gestores.'));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Consumo da frota'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : RefreshIndicator(onRefresh: _carregar, child: _conteudo()),
    );
  }

  Widget _conteudo() {
    final r = calcularConsumo(abastecimentos);
    // média histórica de cada veículo (referência estável para os alertas)
    final mediaHist = {for (final e in r.trechos.entries) e.key: mediaKmL(e.value)};
    final noPeriodo = {
      for (final e in r.trechos.entries) e.key: e.value.where((t) => _noPeriodo(t.data)).toList(),
    };
    final todosTrechos = noPeriodo.values.expand((x) => x).toList();
    final kmTotal = todosTrechos.fold<double>(0, (s, t) => s + t.km);
    final valorTrechos = todosTrechos.fold<double>(0, (s, t) => s + t.valor);
    final abastPeriodo = abastecimentos.where((a) => _noPeriodo(DateTime.tryParse(a['fuel_date']?.toString() ?? ''))).toList();
    final litrosPeriodo = abastPeriodo.fold<double>(0, (s, a) => s + ((a['liters'] as num?)?.toDouble() ?? 0));
    final gastoPeriodo = abastPeriodo.fold<double>(0, (s, a) => s + ((a['total_value'] as num?)?.toDouble() ?? 0));

    // alertas: trecho 20% pior que a média do próprio veículo (com pelo menos 3 trechos de histórico)
    final alertas = <(TrechoConsumo, String, double)>[];
    noPeriodo.forEach((vid, lista) {
      final media = mediaHist[vid] ?? 0;
      if ((r.trechos[vid]?.length ?? 0) < 3 || media <= 0) return;
      for (final t in lista) {
        final dif = (t.kmPorLitro - media) / media;
        if (dif <= -0.20) alertas.add((t, vid, dif));
      }
    });
    alertas.sort((a, b) => a.$3.compareTo(b.$3));
    final inconsistentes = r.inconsistentes.where((a) => _noPeriodo(DateTime.tryParse(a['fuel_date']?.toString() ?? ''))).toList();

    // por motorista (quem abasteceu no fim do trecho)
    final porMotorista = <String, List<TrechoConsumo>>{};
    for (final t in todosTrechos) {
      final did = t.abastecimento['driver_id']?.toString();
      if (did == null) continue;
      porMotorista.putIfAbsent(did, () => []).add(t);
    }

    Widget card(String t, String v, String sub, Color cor) => Container(
          width: 175,
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

    Widget secao(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(s, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
        );

    final veiculosOrdenados = veiculos.values.toList()..sort((a, b) => (a['plate'] ?? '').toString().compareTo((b['plate'] ?? '').toString()));

    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          for (final p in const {30: '30 dias', 90: '90 dias', 180: '6 meses', 365: '12 meses', 0: 'Tudo'}.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(p.value), selected: dias == p.key, onSelected: (_) => setState(() => dias = p.key)),
            ),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          card('Média da frota', kmL(mediaKmL(todosTrechos)), '${numeroBr(kmTotal, casas: 0)} km medidos', AppColors.info),
          const SizedBox(width: 10),
          card('Custo por km', kmTotal > 0 ? moedaBr(valorTrechos / kmTotal) : '-', 'só combustível', AppColors.secondary),
          const SizedBox(width: 10),
          card('Litros', numeroBr(litrosPeriodo, casas: 0), '${abastPeriodo.length} abastecimentos', AppColors.success),
          const SizedBox(width: 10),
          card('Gasto', moedaBr(gastoPeriodo), 'no período', AppColors.warning),
        ]),
      ),

      secao('⚠ Consumo fora do normal (${alertas.length})'),
      if (alertas.isEmpty && inconsistentes.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Nenhum abastecimento fora do normal no período. 👍', style: TextStyle(color: AppColors.textSecondary)),
        ),
      for (final a in alertas)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: cartaoManut(
            child: Row(children: [
              const Icon(Icons.trending_down, color: AppColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${veiculos[a.$2]?['plate'] ?? '-'} · ${kmL(a.$1.kmPorLitro)} em ${dataBrManut(a.$1.abastecimento['fuel_date']?.toString())}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${numeroBr(-a.$3 * 100, casas: 0)}% abaixo da média do veículo (${kmL(mediaHist[a.$2] ?? 0)})'
                    '${motoristas[a.$1.abastecimento['driver_id']?.toString()]?.isNotEmpty == true ? ' · motorista: ${motoristas[a.$1.abastecimento['driver_id'].toString()]}' : ''}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const Text('Verifique: vazamento, manutenção, forma de dirigir ou tanque não completado.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      for (final a in inconsistentes)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: cartaoManut(
            child: Row(children: [
              const Icon(Icons.speed, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${veiculos[a['vehicle_id']?.toString()]?['plate'] ?? '-'} · odômetro inconsistente em ${dataBrManut(a['fuel_date']?.toString())} '
                  '(${kmBr(a['odometer'] as num?)}). Confira se o km foi digitado certo.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            ]),
          ),
        ),

      secao('Por veículo'),
      for (final v in veiculosOrdenados)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _cartaoVeiculo(v, noPeriodo[v['id'].toString()] ?? const [], mediaHist[v['id'].toString()] ?? 0)),

      if (porMotorista.isNotEmpty) ...[
        secao('Por motorista'),
        for (final e in (porMotorista.entries.toList()..sort((a, b) => mediaKmL(b.value).compareTo(mediaKmL(a.value)))))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: cartaoManut(
              child: Row(children: [
                const Icon(Icons.person, color: AppColors.secondary),
                const SizedBox(width: 12),
                Expanded(child: Text(motoristas[e.key]?.isNotEmpty == true ? motoristas[e.key]! : 'Motorista', style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${kmL(mediaKmL(e.value))} · ${numeroBr(e.value.fold<double>(0, (s, t) => s + t.km), casas: 0)} km',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ]),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text('Compare motoristas que dirigem o mesmo tipo de veículo.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      ],
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          'Como é calculado: distância entre dois abastecimentos ÷ litros do segundo (tanque cheio). '
          'Para medir certo, registre todo abastecimento com o km do odômetro.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    ]);
  }

  Widget _cartaoVeiculo(Map<String, dynamic> v, List<TrechoConsumo> trechos, double mediaHist) {
    final media = mediaKmL(trechos);
    final km = trechos.fold<double>(0, (s, t) => s + t.km);
    final valor = trechos.fold<double>(0, (s, t) => s + t.valor);
    final ultimo = trechos.isEmpty ? null : trechos.last;
    final variacao = (ultimo != null && mediaHist > 0) ? (ultimo.kmPorLitro - mediaHist) / mediaHist : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text('${v['plate']} · ${v['brand'] ?? ''} ${v['model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            trechos.isEmpty
                ? 'Sem trechos medidos no período'
                : '${kmL(media)} · ${moedaBr(km > 0 ? valor / km : 0)}/km · ${numeroBr(km, casas: 0)} km'
                    '${variacao != null ? ' · último ${variacao >= 0 ? '+' : ''}${numeroBr(variacao * 100, casas: 0)}%' : ''}',
            style: TextStyle(
              color: variacao != null && variacao <= -0.2 ? AppColors.danger : AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          children: [
            for (final t in trechos.reversed)
              ListTile(
                dense: true,
                leading: Icon(
                  mediaHist > 0 && t.kmPorLitro < mediaHist * 0.8 ? Icons.trending_down : Icons.local_gas_station,
                  color: mediaHist > 0 && t.kmPorLitro < mediaHist * 0.8 ? AppColors.danger : AppColors.muted,
                  size: 20,
                ),
                title: Text('${dataBrManut(t.abastecimento['fuel_date']?.toString())} · ${kmL(t.kmPorLitro)}'),
                subtitle: Text('${numeroBr(t.km, casas: 0)} km com ${numeroBr(t.litros, casas: 1)} L · ${moedaBr(t.valor)}',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

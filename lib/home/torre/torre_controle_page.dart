import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/config/supabase_config.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/snackbar_utils.dart';
import '../comercial/comercial_page.dart' show soDigitos, statusColeta;
import '../compras/compras_comum.dart' show dataHoraBr;
import '../manutencoes/manutencao_comum.dart';
import 'torre_comum.dart';

/// Torre de Controle: mapa com a última posição de cada veículo, viagens em
/// andamento com alertas (sem sinal, parado, excesso de velocidade), coletas
/// do dia e o trajeto da viagem. Atualiza sozinha a cada 30 segundos.
/// As posições vêm do celular do motorista na viagem ou do rastreador
/// (docs/MIGRATION_TORRE_CONTROLE.sql e a função rastreamento-receber).
class TorreControlePage extends StatefulWidget {
  const TorreControlePage({super.key});

  @override
  State<TorreControlePage> createState() => _TorreControlePageState();
}

class _TorreControlePageState extends State<TorreControlePage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  final mapa = MapController();
  Timer? _relogio;
  bool carregando = true;
  String? erro;
  DateTime? atualizadoEm;
  bool _mapaPronto = false, _enquadrado = false;
  bool mostrarForaDeViagem = true;
  Map<String, Map<String, dynamic>> veiculos = {}, motoristas = {}, ultimas = {}, viagemDoVeiculo = {};
  List<Map<String, dynamic>> viagens = [], coletas = [];
  Map<String, double> excessos = {}; // veículo → maior velocidade da última hora
  String? selecionado;
  List<LatLng> trajeto = [];

  @override
  void initState() {
    super.initState();
    _carregar();
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) => _carregar(silencioso: true));
  }

  @override
  void dispose() {
    _relogio?.cancel();
    mapa.dispose();
    super.dispose();
  }

  DateTime? _data(Object? iso) => DateTime.tryParse(iso?.toString() ?? '')?.toLocal();

  SituacaoVeiculo _situacao(String vid) {
    final u = ultimas[vid];
    return situacaoVeiculo(
      emViagem: viagemDoVeiculo.containsKey(vid),
      ultimaPosicao: _data(u?['registrado_em']),
      paradoDesde: _data(u?['parado_desde']),
      agora: DateTime.now(),
    );
  }

  LatLng? _ponto(String vid) {
    final u = ultimas[vid];
    if (u == null) return null;
    return LatLng((u['latitude'] as num).toDouble(), (u['longitude'] as num).toDouble());
  }

  String _placa(String? vid) => veiculos[vid]?['plate']?.toString() ?? 'sem veículo';

  Future<void> _carregar({bool silencioso = false}) async {
    if (!mounted) return;
    if (!silencioso) {
      setState(() {
        carregando = true;
        erro = null;
      });
    }
    try {
      await prepararEmpresa();
      final eid = empresaAtual;
      if (eid == null) throw Exception('sem empresa');
      final umaHora = DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String();
      final r = await Future.wait([
        fetchAllRows((a, b) => supabase.from('vehicles').select('id, plate, brand, model').eq('empresa_id', eid).order('plate', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('drivers').select('id, name, phone').eq('empresa_id', eid).order('name', ascending: true).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('rastreamento_ultima').select('*').eq('empresa_id', eid).order('vehicle_id').range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('viagens')
            .select('id, veiculo_id, motorista_id, origem, destino, data_inicio')
            .eq('empresa_id', eid)
            .eq('status', 'em_progresso')
            .order('data_inicio', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('coletas')
            .select('id, numero, cidade, uf, destino_cidade, destino_uf, status, hora_inicio, veiculo_id, clientes(nome)')
            .eq('empresa_id', eid)
            .eq('data_programada', isoDia(DateTime.now()))
            .neq('status', 'cancelada')
            .order('hora_inicio', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('rastreamento_posicoes')
            .select('vehicle_id, velocidade_kmh')
            .eq('empresa_id', eid)
            .gte('registrado_em', umaHora)
            .gt('velocidade_kmh', limiteVelocidade)
            .order('id')
            .range(a, b)),
      ]);
      final exc = <String, double>{};
      for (final p in r[5]) {
        final id = p['vehicle_id'].toString(), vel = (p['velocidade_kmh'] as num).toDouble();
        if (vel > (exc[id] ?? 0)) exc[id] = vel;
      }
      if (!mounted) return;
      setState(() {
        veiculos = {for (final v in r[0]) v['id'].toString(): v};
        motoristas = {for (final m in r[1]) m['id'].toString(): m};
        ultimas = {for (final u in r[2]) u['vehicle_id'].toString(): u};
        viagens = r[3];
        viagemDoVeiculo = {for (final v in r[3]) if (v['veiculo_id'] != null) v['veiculo_id'].toString(): v};
        coletas = r[4];
        excessos = exc;
        atualizadoEm = DateTime.now();
        carregando = false;
      });
      _enquadrar();
      if (selecionado != null) _carregarTrajeto(selecionado!);
    } catch (e) {
      debugPrint('Erro ao carregar a torre: $e');
      if (!mounted || silencioso) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar a torre de controle.';
      });
    }
  }

  /// Na primeira carga, enquadra o mapa em todos os veículos com posição.
  void _enquadrar() {
    if (_enquadrado || !_mapaPronto) return;
    final pontos = [for (final vid in ultimas.keys) _ponto(vid)!];
    if (pontos.isEmpty) return;
    _enquadrado = true;
    if (pontos.length == 1) {
      mapa.move(pontos.first, 12);
    } else {
      mapa.fitCamera(CameraFit.coordinates(coordinates: pontos, padding: const EdgeInsets.all(60), maxZoom: 13));
    }
  }

  void _selecionar(String vid) {
    setState(() {
      selecionado = vid;
      trajeto = [];
    });
    final p = _ponto(vid);
    if (p != null && _mapaPronto) mapa.move(p, math.max(mapa.camera.zoom, 11));
    _carregarTrajeto(vid);
  }

  /// Trajeto da viagem em andamento (ou das últimas 12 h, fora de viagem).
  Future<void> _carregarTrajeto(String vid) async {
    final viagem = viagemDoVeiculo[vid];
    try {
      var q = supabase.from('rastreamento_posicoes').select('latitude, longitude').eq('vehicle_id', vid);
      q = viagem != null
          ? q.eq('viagem_id', viagem['id'])
          : q.gte('registrado_em', DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String());
      final pts = await q.order('registrado_em', ascending: true).limit(1000);
      if (!mounted || selecionado != vid) return;
      setState(() => trajeto = [for (final p in pts) LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())]);
    } catch (_) {}
  }

  Future<void> _abrirIntegracao() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => IntegracaoRastreadorPage(empresaId: empresaAtual!)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (auth.isMotorista || !auth.can(AppPermission.viewVehicles)) {
      return Scaffold(appBar: AppBar(title: const Text('Torre de controle')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso à torre de controle.'));
    }
    final a = atualizadoEm;
    String dois(int n) => n.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Torre de controle'),
        backgroundColor: AppColors.surface,
        actions: [
          if (a != null)
            Center(
              child: Text('atualizado às ${dois(a.hour)}:${dois(a.minute)}:${dois(a.second)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          if (auth.can(AppPermission.manageSettings) && !carregando && erro == null)
            IconButton(icon: const Icon(Icons.settings_input_antenna), tooltip: 'Integração com rastreador', onPressed: _abrirIntegracao),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : LayoutBuilder(builder: (ctx, c) {
                  if (c.maxWidth > 980) {
                    return Row(children: [SizedBox(width: 400, child: _painel()), Expanded(child: _mapa())]);
                  }
                  return Column(children: [SizedBox(height: c.maxHeight * 0.48, child: _mapa()), Expanded(child: _painel())]);
                }),
    );
  }

  // ── Mapa ──────────────────────────────────────────────────────────────────
  Widget _mapa() {
    final marcadores = <Marker>[];
    for (final vid in ultimas.keys) {
      final s = _situacao(vid);
      if (s == SituacaoVeiculo.foraDeViagem && !mostrarForaDeViagem && selecionado != vid) continue;
      marcadores.add(Marker(
        point: _ponto(vid)!,
        width: 120,
        height: 46,
        alignment: Alignment.topCenter,
        child: GestureDetector(onTap: () => _selecionar(vid), child: _pino(_placa(vid), s, selecionado == vid)),
      ));
    }
    return Stack(children: [
      FlutterMap(
        mapController: mapa,
        options: MapOptions(
          initialCenter: const LatLng(-15.8, -47.9),
          initialZoom: 4,
          minZoom: 3,
          maxZoom: 18,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () {
            _mapaPronto = true;
            _enquadrar();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'br.com.frotacheck',
            tileBuilder: darkModeTileBuilder,
          ),
          if (trajeto.length > 1) PolylineLayer(polylines: [Polyline(points: trajeto, strokeWidth: 4, color: AppColors.neon)]),
          MarkerLayer(markers: marcadores),
          RichAttributionWidget(attributions: [
            TextSourceAttribution('OpenStreetMap', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'))),
          ]),
        ],
      ),
      if (ultimas.isEmpty)
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Material(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Nenhuma posição recebida ainda. Elas chegam pelo celular do motorista durante a viagem '
                'ou pelo rastreador do caminhão (integração).',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      if (selecionado != null) Positioned(left: 12, right: 12, bottom: 28, child: _cartaoSelecionado()),
    ]);
  }

  Widget _pino(String placa, SituacaoVeiculo s, bool sel) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: s.cor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? Colors.white : Colors.black54, width: sel ? 2 : 1),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.icone, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(placa, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ]),
        ),
        Icon(Icons.arrow_drop_down, color: s.cor, size: 20),
      ]);

  Widget _cartaoSelecionado() {
    final vid = selecionado!;
    final v = veiculos[vid];
    final u = ultimas[vid];
    final viagem = viagemDoVeiculo[vid];
    final s = _situacao(vid);
    final mot = motoristas[(viagem?['motorista_id'] ?? u?['driver_id'])?.toString()];
    final vel = (u?['velocidade_kmh'] as num?)?.round();
    final telefone = soDigitos((mot?['phone'] ?? '').toString());
    final p = _ponto(vid);
    return Material(
      color: AppColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            chipStatus(s.rotulo, s.cor),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${_placa(vid)} · ${v?['brand'] ?? ''} ${v?['model'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Fechar',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                selecionado = null;
                trajeto = [];
              }),
            ),
          ]),
          if (viagem != null) Text('${viagem['origem'] ?? '-'} → ${viagem['destino'] ?? '-'} · saiu ${dataHoraBr(viagem['data_inicio']?.toString())}'),
          if (mot != null) Text('Motorista: ${mot['name']}', style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            u == null
                ? 'Nenhuma posição recebida'
                : 'Última posição ${haQuanto(_data(u['registrado_em']))} (${u['origem'] == 'rastreador' ? 'rastreador' : 'celular do motorista'})'
                    '${vel != null ? ' · $vel km/h' : ''}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (s == SituacaoVeiculo.parado)
            Text('Parado no mesmo lugar ${haQuanto(_data(u?['parado_desde']))}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
          if (excessos[vid] != null)
            Text('Excesso de velocidade na última hora: ${excessos[vid]!.round()} km/h (limite $limiteVelocidade)',
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          if (trajeto.length > 1)
            Text('Trajeto ${viagem != null ? 'da viagem' : 'das últimas 12 h'}: ${trajeto.length} pontos', style: const TextStyle(color: AppColors.neon, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (p != null) botaoAcao('Abrir no Google Maps', Icons.map, AppColors.info, () => launchUrl(linkMapa(p.latitude, p.longitude), mode: LaunchMode.externalApplication)),
            if (telefone.isNotEmpty) botaoAcao('Ligar', Icons.phone, AppColors.success, () => launchUrl(Uri.parse('tel:$telefone'))),
          ]),
        ]),
      ),
    );
  }

  // ── Painel ────────────────────────────────────────────────────────────────
  Widget _painel() {
    int conta(SituacaoVeiculo s) => viagens.where((v) => v['veiculo_id'] != null && _situacao(v['veiculo_id'].toString()) == s).length;
    final alertas = <(Color, String, String)>[];
    for (final v in viagens) {
      final vid = v['veiculo_id']?.toString();
      if (vid == null) continue;
      final s = _situacao(vid);
      final u = ultimas[vid];
      if (s == SituacaoVeiculo.semSinal) {
        alertas.add((AppColors.danger, '${_placa(vid)} sem sinal: ${u == null ? 'nenhuma posição recebida' : 'última posição ${haQuanto(_data(u['registrado_em']))}'}', vid));
      } else if (s == SituacaoVeiculo.parado) {
        alertas.add((AppColors.warning, '${_placa(vid)} parado no mesmo lugar ${haQuanto(_data(u?['parado_desde']))}', vid));
      }
    }
    for (final e in excessos.entries) {
      alertas.add((AppColors.danger, '${_placa(e.key)} a ${e.value.round()} km/h na última hora (limite $limiteVelocidade)', e.key));
    }

    Widget kpi(String t, int n, Color cor) => Container(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text('$n', style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(t, textAlign: TextAlign.center, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 11)),
          ]),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
      if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        kpi('Em viagem', viagens.length, AppColors.info),
        kpi('Em movimento', conta(SituacaoVeiculo.emMovimento), AppColors.success),
        kpi('Parados', conta(SituacaoVeiculo.parado), AppColors.warning),
        kpi('Sem sinal', conta(SituacaoVeiculo.semSinal), AppColors.danger),
      ]),
      if (alertas.isNotEmpty) ...[
        _titulo('Alertas (${alertas.length})'),
        for (final a in alertas)
          InkWell(
            onTap: () => _selecionar(a.$3),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, color: a.$1, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(a.$2, style: TextStyle(color: a.$1, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
      ],
      _titulo('Viagens em andamento (${viagens.length})'),
      if (viagens.isEmpty) const Text('Nenhuma viagem em andamento agora.', style: TextStyle(color: AppColors.textSecondary)),
      for (final v in viagens) _cartaoViagem(v),
      _titulo('Coletas de hoje (${coletas.length})'),
      if (coletas.isEmpty) const Text('Nenhuma coleta programada para hoje.', style: TextStyle(color: AppColors.textSecondary)),
      for (final c in coletas) _linhaColeta(c),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: mostrarForaDeViagem,
        onChanged: (v) => setState(() => mostrarForaDeViagem = v),
        title: const Text('Mostrar no mapa os veículos fora de viagem', style: TextStyle(fontSize: 14)),
      ),
      const Text(
        'As posições chegam pelo celular do motorista durante a viagem (com o FrotaCheck aberto; no app Android, '
        'também com a tela apagada) ou pelo rastreador do caminhão, pela integração.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ]);
  }

  Widget _cartaoViagem(Map<String, dynamic> v) {
    final vid = v['veiculo_id']?.toString();
    final s = vid == null ? SituacaoVeiculo.semSinal : _situacao(vid);
    final u = vid == null ? null : ultimas[vid];
    final mot = motoristas[v['motorista_id']?.toString()]?['name'];
    final daViagem = u != null && u['viagem_id']?.toString() == v['id']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selecionado == vid && vid != null ? s.cor : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: vid == null ? null : () => _selecionar(vid),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s.icone, color: s.cor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${_placa(vid)}${mot != null ? ' · $mot' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              chipStatus(s.rotulo, s.cor),
            ]),
            const SizedBox(height: 4),
            Text('${v['origem'] ?? '-'} → ${v['destino'] ?? '-'}', style: const TextStyle(color: AppColors.textSecondary)),
            Text(
              u == null
                  ? 'nenhuma posição recebida'
                  : daViagem
                      ? 'última posição ${haQuanto(_data(u['registrado_em']))}${u['velocidade_kmh'] != null ? ' · ${(u['velocidade_kmh'] as num).round()} km/h' : ''}'
                      : 'sem posição nesta viagem ainda (a última foi ${haQuanto(_data(u['registrado_em']))})',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _linhaColeta(Map<String, dynamic> c) {
    final st = statusColeta[c['status']] ?? ('${c['status']}', AppColors.muted);
    final hora = (c['hora_inicio'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Coleta nº ${c['numero']}${hora.length >= 5 ? ' · ${hora.substring(0, 5)}' : ''}${c['clientes']?['nome'] != null ? ' · ${c['clientes']['nome']}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            Text('${c['cidade'] ?? '-'}/${c['uf'] ?? ''} → ${c['destino_cidade'] ?? '-'}/${c['destino_uf'] ?? ''}'
                '${c['veiculo_id'] != null ? ' · ${_placa(c['veiculo_id'].toString())}' : ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ]),
        ),
        chipStatus(st.$1, st.$2),
      ]),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
      );
}

// ── Integração com o rastreador ─────────────────────────────────────────────
class IntegracaoRastreadorPage extends StatefulWidget {
  const IntegracaoRastreadorPage({super.key, required this.empresaId});
  final String empresaId;

  @override
  State<IntegracaoRastreadorPage> createState() => _IntegracaoRastreadorPageState();
}

class _IntegracaoRastreadorPageState extends State<IntegracaoRastreadorPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>>? lista;
  String endereco = '';

  @override
  void initState() {
    super.initState();
    SupabaseConfig.getUrl().then((u) {
      if (mounted) setState(() => endereco = '$u/functions/v1/rastreamento-receber');
    });
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await supabase.from('rastreamento_integracoes').select('*').eq('empresa_id', widget.empresaId).order('criado_em', ascending: false);
      if (mounted) setState(() => lista = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (!mounted) return;
      setState(() => lista = []);
      showErrorFrom(context, e, prefix: 'Não foi possível carregar as integrações.');
    }
  }

  String _instrucoes(String token) => 'Integração FrotaCheck — Torre de controle\n\n'
      'Envie as posições dos veículos por POST para:\n$endereco\n\n'
      'Cabeçalho: Authorization: Bearer $token\n\n'
      'Corpo (JSON), até 1000 posições por envio:\n'
      '{"posicoes":[{"placa":"ABC1D23","latitude":-21.8910,"longitude":-45.5920,"velocidade":72,'
      '"data_hora":"2026-10-27T14:00:00-03:00","ignicao":true}]}\n\n'
      'A placa precisa estar cadastrada no FrotaCheck. Sugestão: enviar a cada 1 ou 2 minutos.';

  Future<void> _nova() async {
    final nome = TextEditingController(text: 'Rastreador');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Nova integração'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Sascar, Omnilink, central de rastreamento')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final token = (await supabase.rpc('criar_integracao_rastreamento', params: {'p_empresa': widget.empresaId, 'p_nome': nome.text.trim()})).toString();
      if (!mounted) return;
      await _carregar();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Integração criada'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Guarde o token agora: por segurança ele não aparece de novo.', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SelectableText(_instrucoes(token), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (ctx.mounted) showSuccess(ctx, 'Token copiado.');
              },
              child: const Text('Copiar token'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _instrucoes(token)));
                if (ctx.mounted) showSuccess(ctx, 'Instruções copiadas: mande ao fornecedor do rastreador.');
              },
              child: const Text('Copiar instruções'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível criar a integração.');
    }
  }

  Future<void> _revogar(Map<String, dynamic> i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Revogar "${i['nome']}"?'),
        content: const Text('O token para de funcionar na hora: o rastreador não envia mais posições com ele.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Revogar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('revogar_integracao_rastreamento', params: {'p_id': i['id']});
      if (mounted) showSuccess(context, 'Integração revogada.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível revogar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Integração com rastreador'), backgroundColor: AppColors.surface),
      floatingActionButton: FloatingActionButton.extended(onPressed: _nova, icon: const Icon(Icons.add_link), label: const Text('Nova integração')),
      body: lista == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
                  const Text(
                    'Se o caminhão tem rastreador, o sistema do rastreador (ou da central) pode mandar as posições direto para a '
                    'torre de controle. Crie uma integração e passe as instruções ao fornecedor do rastreador.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  if (lista!.isEmpty) vazioManut(Icons.settings_input_antenna, 'Nenhuma integração criada ainda.'),
                  for (final i in lista!)
                    cartaoManut(
                      child: Row(children: [
                        Icon(Icons.settings_input_antenna, color: i['ativo'] == true ? AppColors.success : AppColors.muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(i['nome'].toString(), style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              chipStatus(i['ativo'] == true ? 'Ativa' : 'Revogada', i['ativo'] == true ? AppColors.success : AppColors.muted),
                            ]),
                            Text('token terminado em ····${i['token_final']} · criada em ${dataHoraBr(i['criado_em']?.toString())}'
                                '${i['criado_por_nome'] != null ? ' por ${i['criado_por_nome']}' : ''}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                            Text(i['ultimo_uso'] == null ? 'ainda não recebeu posições' : 'último envio ${haQuanto(DateTime.tryParse(i['ultimo_uso'].toString())?.toLocal())}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          ]),
                        ),
                        if (i['ativo'] == true) botaoAcao('Revogar', Icons.link_off, AppColors.danger, () => _revogar(i)),
                      ]),
                    ),
                ]),
              ),
            ),
    );
  }
}

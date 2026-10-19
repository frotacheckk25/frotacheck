import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/models/checklist_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/widgets/signed_network_image.dart';
import 'vistoria_widgets.dart';

class HistoricoChecklistPage extends StatefulWidget {
  const HistoricoChecklistPage({super.key});

  @override
  State<HistoricoChecklistPage> createState() => _HistoricoChecklistPageState();
}

/// Períodos do filtro do histórico (dias para trás; null = todo o período).
const Map<String, int?> _kPeriodos = {
  'Hoje': 0,
  '7 dias': 7,
  '30 dias': 30,
  'Tudo': null,
};

class _HistoricoChecklistPageState extends State<HistoricoChecklistPage> {
  final supabase = Supabase.instance.client;

  /// Registros por página. Filtros (tipo, período, busca) rodam no banco, então
  /// o histórico funciona para qualquer tamanho de frota — antes vinham só os
  /// 500 mais recentes e a busca filtrava apenas dentro deles.
  static const int _pageSize = 100;

  /// Máximo de veículos/motoristas enviados no filtro da busca (limite de URL).
  static const int _maxIdsBusca = 150;

  List<Map<String, dynamic>> _registros = [];
  Map<String, Map<String, dynamic>> _veicMap = {};
  Map<String, Map<String, dynamic>> _motMap = {};
  bool _carregando = true;
  bool _carregandoMais = false;
  bool _temMais = false;
  int? _total;
  String _filtroTipo = 'todos';
  String _periodo = '7 dias';
  String _busca = '';
  bool _buscaAmpla = false;
  String? _erroCarregamento;
  final _buscaController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaController.dispose();
    super.dispose();
  }

  void _onBusca(String v) {
    setState(() => _busca = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _carregarPagina(reset: true));
  }

  void _setFiltro({String? tipo, String? periodo}) {
    setState(() {
      if (tipo != null) _filtroTipo = tipo;
      if (periodo != null) _periodo = periodo;
    });
    _carregarPagina(reset: true);
  }

  /// Carrega veículos e motoristas (para nomes/placas e busca) e a 1ª página.
  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => _carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      final results = await Future.wait([
        fetchAllRows((from, to) {
          var q = supabase.from('vehicles').select('id, plate, model, brand');
          if (auth.isMotorista && auth.driverId != null) {
            q = q.eq('driver_id', auth.driverId!);
          } else if (eid != null) {
            q = q.eq('empresa_id', eid);
          }
          return q.order('id').range(from, to);
        }),
        fetchAllRows((from, to) {
          var q = supabase.from('drivers').select('id, name');
          if (auth.isMotorista && auth.driverId != null) {
            q = q.eq('id', auth.driverId!);
          } else if (eid != null) {
            q = q.eq('empresa_id', eid);
          }
          return q.order('id').range(from, to);
        }),
      ]);
      if (!mounted) return;
      _veicMap = {for (final v in results[0]) v['id'].toString(): v};
      _motMap = {for (final m in results[1]) m['id'].toString(): m};
      await _carregarPagina(reset: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroCarregamento = 'Erro ao carregar checklists: ${e.toString()}';
        });
      }
    }
  }

  /// Busca uma página de checklists já filtrada no banco.
  Future<void> _carregarPagina({bool reset = false}) async {
    if (!mounted) return;
    final auth = context.read<AppAuthProvider>();
    final eid = auth.effectiveEmpresaId;
    final offset = reset ? 0 : _registros.length;
    setState(() => reset ? _carregando = true : _carregandoMais = true);

    try {
      var q = supabase.from('checklists').select();
      if (auth.isMotorista && auth.driverId != null) {
        q = q.eq('motorista_id', auth.driverId!);
      } else if (eid != null) {
        q = q.eq('empresa_id', eid);
      }
      if (_filtroTipo != 'todos') q = q.eq('tipo', _filtroTipo);

      final dias = _kPeriodos[_periodo];
      if (dias != null) {
        final hoje = DateTime.now();
        final inicio = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: dias));
        q = q.gte('criado_em', inicio.toUtc().toIso8601String());
      }

      var buscaAmpla = false;
      final termo = _busca.trim().toLowerCase();
      if (termo.isNotEmpty) {
        final vids = _veicMap.entries
            .where((e) => (e.value['plate'] ?? '').toString().toLowerCase().contains(termo))
            .map((e) => e.key)
            .toList();
        final mids = _motMap.entries
            .where((e) => (e.value['name'] ?? '').toString().toLowerCase().contains(termo))
            .map((e) => e.key)
            .toList();
        if (vids.isEmpty && mids.isEmpty) {
          if (!mounted) return;
          setState(() {
            _registros = [];
            _total = 0;
            _temMais = false;
            _buscaAmpla = false;
            _carregando = false;
            _carregandoMais = false;
            _erroCarregamento = null;
          });
          return;
        }
        buscaAmpla = vids.length > _maxIdsBusca || mids.length > _maxIdsBusca;
        final filtros = [
          if (vids.isNotEmpty) 'veiculo_id.in.(${vids.take(_maxIdsBusca).join(',')})',
          if (mids.isNotEmpty) 'motorista_id.in.(${mids.take(_maxIdsBusca).join(',')})',
        ];
        q = q.or(filtros.join(','));
      }

      final res = await q
          .order('criado_em', ascending: false)
          .order('id')
          .range(offset, offset + _pageSize - 1)
          .count(CountOption.exact);
      final pagina = res.data.map((e) => Map<String, dynamic>.from(e)).toList();

      if (!mounted) return;
      setState(() {
        _registros = reset ? pagina : [..._registros, ...pagina];
        _total = res.count;
        _temMais = _registros.length < res.count;
        _buscaAmpla = buscaAmpla;
        _carregando = false;
        _carregandoMais = false;
        _erroCarregamento = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _carregandoMais = false;
          _erroCarregamento = 'Erro ao carregar checklists: ${e.toString()}';
        });
      }
    }
  }

  int _itensOk(Map<String, dynamic> r) {
    final itens = r['itens'];
    if (itens == null) return 0;
    final map = itens is Map
        ? Map<String, dynamic>.from(itens)
        : Map<String, dynamic>.from(json.decode(itens.toString()) as Map);
    // Conta só os itens atuais (verificados ou "não se aplica").
    return Checklist.itensChecklist.where((i) => Checklist.itemOk(map[i])).length;
  }

  String _formatarData(Map<String, dynamic> r) {
    final raw = r['criado_em']?.toString() ?? r['data']?.toString();
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.substring(0, 10);
    }
  }

  void _abrirDetalhe(Map<String, dynamic> r) {
    final vid = r['veiculo_id']?.toString() ?? '';
    final mid = r['motorista_id']?.toString() ?? '';
    final veiculo = _veicMap[vid];
    final motorista = _motMap[mid];
    final aprovado = r['aprovado'] as bool? ?? false;
    final tipo = r['tipo']?.toString() ?? 'saida';
    final itensOk = _itensOk(r);
    final total = Checklist.itensChecklist.length;
    final itensMap = r['itens'] != null
        ? Map<String, dynamic>.from(r['itens'] as Map)
        : <String, dynamic>{};
    final fotos = r['foto_urls'] != null
        ? List<String>.from(r['foto_urls'] as List)
        : <String>[];
    final obs = r['observacoes']?.toString();
    final kmFinal = r['km_final'];
    final kmInicial = r['km_inicial'];
    final nivel = r['nivel_combustivel']?.toString();
    final destino = r['destino']?.toString();
    final finalidade = r['finalidade']?.toString();
    final avarias = r['avarias'] is Map
        ? Map<String, dynamic>.from(r['avarias'] as Map)
        : <String, dynamic>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                _tipoBadge(tipo, large: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        veiculo != null
                            ? '${veiculo['plate'] ?? ''} — ${veiculo['model'] ?? ''}'
                            : 'Veículo desconhecido',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        motorista?['name']?.toString() ?? 'Motorista desconhecido',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _statusBadge(aprovado),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatarData(r),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Progresso itens
            _detalheRow('Itens verificados', '$itensOk / $total'),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? itensOk / total : 0,
                backgroundColor: AppColors.backgroundSoft,
                valueColor: AlwaysStoppedAnimation(
                    aprovado ? AppColors.success : AppColors.danger),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),

            if (kmInicial != null) ...[
              _detalheRow('KM de saída', kmInicial.toString()),
              const SizedBox(height: 8),
            ],
            if (kmFinal != null) ...[
              _detalheRow('KM Final', kmFinal.toString()),
              const SizedBox(height: 8),
            ],
            if (nivel != null && nivel.isNotEmpty) ...[
              _detalheRow('Nível do tanque', nivel),
              const SizedBox(height: 8),
            ],
            if (destino != null && destino.isNotEmpty) ...[
              _detalheRow('Destino', destino),
              const SizedBox(height: 8),
            ],
            if (finalidade != null && finalidade.isNotEmpty) ...[
              _detalheRow('Finalidade', finalidade),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),

            // Avarias por posição (ficha de vistoria)
            if (avarias.isNotEmpty) ...[
              const Text('Avarias encontradas',
                  style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...avarias.entries.map((e) {
                final info = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{};
                final tipos = ((info['tipos'] as List?) ?? const []).map((t) => t.toString()).toList();
                final obsAv = info['obs']?.toString() ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tipos
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: corAvaria(t), borderRadius: BorderRadius.circular(6)),
                                  child: Text('$t · ${kTiposAvaria[t] ?? t}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ))
                            .toList(),
                      ),
                      if (obsAv.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(obsAv, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            if (obs != null && obs.isNotEmpty) ...[
              _detalheRow('Observações', ''),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(obs,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],

            // Lista de itens
            const Text('Itens do Checklist',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: List.generate(
                  Checklist.itensChecklist.length * 2 - 1,
                  (i) {
                    if (i.isOdd) {
                      return const Divider(
                          height: 1, color: AppColors.border);
                    }
                    final item = Checklist.itensChecklist[i ~/ 2];
                    final na = itensMap[item] == Checklist.naoSeAplica;
                    final ok = Checklist.itemOk(itensMap[item]);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            na
                                ? Icons.remove_circle_outline
                                : ok
                                    ? Icons.check_circle
                                    : Icons.cancel_outlined,
                            color: na
                                ? AppColors.textSecondary
                                : ok
                                    ? AppColors.success
                                    : AppColors.danger,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(na ? '$item — N/A' : item,
                                style: TextStyle(
                                    color: ok
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // Fotos
            if (fotos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Fotos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: fotos.length,
                itemBuilder: (_, idx) {
                  final posicao = _posicaoDaFoto(fotos[idx]);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SignedNetworkImage(
                          url: fotos[idx],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            color: AppColors.backgroundSoft,
                            child: const Icon(Icons.broken_image,
                                color: AppColors.textSecondary),
                          ),
                        ),
                        if (posicao != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                              color: Colors.black.withOpacity(0.55),
                              child: Text(posicao,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Posição da foto (ex.: "Vista de Cima") lida do nome do arquivo, que o
  /// checklist grava como `tipo_veiculoId_posicao_timestamp.jpg`.
  static String? _posicaoDaFoto(String url) {
    final nome = Uri.decodeFull(url.split('?').first.split('/').last);
    final semExt = nome.contains('.') ? nome.substring(0, nome.lastIndexOf('.')) : nome;
    for (final posicao in Checklist.fotosObrigatorias) {
      final chave = posicao.toLowerCase().replaceAll(' ', '_');
      if (semExt.contains('_${chave}_')) return posicao;
    }
    return null;
  }

  Widget _detalheRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _tipoBadge(String tipo, {bool large = false}) {
    final isSaida = tipo == 'saida';
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 10 : 7, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: (isSaida ? AppColors.secondary : AppColors.success)
            .withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isSaida ? AppColors.secondary : AppColors.success)
              .withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSaida
                ? Icons.arrow_circle_up_outlined
                : Icons.arrow_circle_down_outlined,
            color: isSaida ? AppColors.secondary : AppColors.success,
            size: large ? 14 : 11,
          ),
          const SizedBox(width: 4),
          Text(
            isSaida ? 'Saída' : 'Retorno',
            style: TextStyle(
              color: isSaida ? AppColors.secondary : AppColors.success,
              fontSize: large ? 12 : 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool aprovado) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (aprovado ? AppColors.success : AppColors.danger)
              .withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (aprovado ? AppColors.success : AppColors.danger)
                .withOpacity(0.4),
          ),
        ),
        child: Text(
          aprovado ? 'Aprovado' : 'Reprovado',
          style: TextStyle(
            color: aprovado ? AppColors.success : AppColors.danger,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lista = _registros;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Histórico de Checklists'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                // Busca
                TextField(
                  controller: _buscaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: _onBusca,
                  decoration: InputDecoration(
                    hintText: 'Buscar por placa ou motorista...',
                    hintStyle: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textSecondary, size: 18),
                    suffixIcon: _busca.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: AppColors.textSecondary, size: 16),
                            onPressed: () {
                              _buscaController.clear();
                              _onBusca('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.backgroundSoft,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.secondary)),
                  ),
                ),
                const SizedBox(height: 10),
                // Chips de tipo e de período
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _filterChip('Todos', _filtroTipo == 'todos', () => _setFiltro(tipo: 'todos')),
                    _filterChip('Saída', _filtroTipo == 'saida', () => _setFiltro(tipo: 'saida')),
                    _filterChip('Retorno', _filtroTipo == 'retorno', () => _setFiltro(tipo: 'retorno')),
                    Container(width: 1, height: 18, color: AppColors.border),
                    for (final p in _kPeriodos.keys)
                      _filterChip(p, _periodo == p, () => _setFiltro(periodo: p)),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _total == null
                        ? ''
                        : '${lista.length} de $_total registro${_total != 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
                if (_buscaAmpla)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Muitos veículos/motoristas correspondem à busca — digite mais letras para refinar.',
                      style: TextStyle(color: AppColors.warning, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _erroCarregamento != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.danger, size: 48),
                              const SizedBox(height: 12),
                              const Text(
                                'Erro ao carregar',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _erroCarregamento!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _carregar,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Tentar novamente'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.secondary),
                              ),
                            ],
                          ),
                        ),
                      )
                : lista.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.checklist_rtl,
                                size: 56,
                                color: Colors.grey.shade700),
                            const SizedBox(height: 12),
                            const Text(
                              'Nenhum checklist encontrado',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                          itemCount: lista.length + (_temMais ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == lista.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: _carregandoMais
                                      ? const CircularProgressIndicator()
                                      : OutlinedButton.icon(
                                          onPressed: () => _carregarPagina(),
                                          icon: const Icon(Icons.expand_more),
                                          label: Text('Carregar mais (${(_total ?? 0) - lista.length} restantes)'),
                                        ),
                                ),
                              );
                            }
                            return _buildCard(lista[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.secondary.withOpacity(0.15)
              : AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.secondary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.secondary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final vid = r['veiculo_id']?.toString() ?? '';
    final mid = r['motorista_id']?.toString() ?? '';
    final veiculo = _veicMap[vid];
    final motorista = _motMap[mid];
    final tipo = r['tipo']?.toString() ?? 'saida';
    final aprovado = r['aprovado'] as bool? ?? false;
    final itensOk = _itensOk(r);
    final total = Checklist.itensChecklist.length;
    final pct = total > 0 ? itensOk / total : 0.0;
    final kmFinal = r['km_final'];

    return GestureDetector(
      onTap: () => _abrirDetalhe(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: aprovado
                ? AppColors.success.withOpacity(0.25)
                : AppColors.danger.withOpacity(0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: tipo + status + data
            Row(
              children: [
                _tipoBadge(tipo),
                const SizedBox(width: 6),
                _statusBadge(aprovado),
                const Spacer(),
                Text(
                  _formatarData(r),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Veículo
            Row(
              children: [
                const Icon(Icons.directions_car,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    veiculo != null
                        ? '${veiculo['plate'] ?? ''} — ${veiculo['model'] ?? ''}'
                        : 'Veículo desconhecido',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Motorista
            Row(
              children: [
                const Icon(Icons.person_outline,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 6),
                Text(
                  motorista?['name']?.toString() ?? 'Motorista desconhecido',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Barra de progresso
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.backgroundSoft,
                      valueColor: AlwaysStoppedAnimation(
                          aprovado ? AppColors.success : AppColors.danger),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$itensOk/$total itens',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                if (kmFinal != null) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.speed,
                      color: AppColors.textSecondary, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    '$kmFinal km',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

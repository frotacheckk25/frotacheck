import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/signed_storage_url.dart';
import '../../core/utils/snackbar_utils.dart';
import '../veiculos/veiculo_tipo.dart';

/// Histórico completo de um motorista: veículos que já pilotou, registro de
/// saída/retorno, viagens e períodos de atribuição — espelha
/// VeiculoHistoricoPage, mas a partir do lado do motorista.
class MotoristaHistoricoPage extends StatefulWidget {
  final Map<String, dynamic> motorista;

  const MotoristaHistoricoPage({super.key, required this.motorista});

  @override
  State<MotoristaHistoricoPage> createState() => _MotoristaHistoricoPageState();
}

class _MotoristaHistoricoPageState extends State<MotoristaHistoricoPage> {
  final _supabase = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;

  List<Map<String, dynamic>> _checklists = [];
  List<Map<String, dynamic>> _viagens = [];
  List<Map<String, dynamic>> _atribuicoes = [];
  Map<String, Map<String, dynamic>> _veiculosPorId = {};
  Map<String, int> _manutencoesPorVeiculoId = {};
  Map<String, String> _fotosVeiculoPorId = {};
  String? _fotoMotoristaAssinada;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String get _motoristaId => widget.motorista['id'].toString();

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('checklists')
            .select('id, tipo, data, criado_em, veiculo_id, km_final, aprovado')
            .eq('motorista_id', _motoristaId)
            .order('criado_em', ascending: false)
            .limit(200),
        _supabase
            .from('viagens')
            .select('id, veiculo_id, data_inicio, origem, destino, quilometragem_percorrida, status')
            .eq('motorista_id', _motoristaId)
            .order('data_inicio', ascending: false)
            .limit(200),
        _supabase
            .from('atribuicoes_veiculo')
            .select('id, veiculo_id, data_inicio, data_fim')
            .eq('motorista_id', _motoristaId)
            .order('data_inicio', ascending: false)
            .limit(200),
        _supabase.from('vehicles').select('id, plate, brand, model, tipo, foto_url'),
        _supabase.from('manutencoes').select('vehicle_id'),
      ]);

      final checklists = List<Map<String, dynamic>>.from(results[0] as List);
      final viagens = List<Map<String, dynamic>>.from(results[1] as List);
      final atribuicoes = List<Map<String, dynamic>>.from(results[2] as List);
      final veiculos = List<Map<String, dynamic>>.from(results[3] as List);
      final manutencoes = List<Map<String, dynamic>>.from(results[4] as List);

      final manutPorVeiculo = <String, int>{};
      for (final m in manutencoes) {
        final vid = m['vehicle_id']?.toString();
        if (vid == null) continue;
        manutPorVeiculo[vid] = (manutPorVeiculo[vid] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() {
        _checklists = checklists;
        _viagens = viagens;
        _atribuicoes = atribuicoes;
        _veiculosPorId = {
          for (final v in veiculos) (v['id']?.toString() ?? ''): v,
        };
        _manutencoesPorVeiculoId = manutPorVeiculo;
        _carregando = false;
      });
      final fotoMotorista = widget.motorista['foto_url'] as String?;
      if (fotoMotorista != null && fotoMotorista.isNotEmpty) {
        final signed = await toSignedStorageUrl(fotoMotorista);
        if (mounted) setState(() => _fotoMotoristaAssinada = signed);
      }
      final fotosVeiculos = <String, String>{};
      for (final v in veiculos) {
        final id = v['id']?.toString();
        final foto = v['foto_url'] as String?;
        if (id != null && foto != null && foto.isNotEmpty) {
          final signed = await toSignedStorageUrl(foto);
          if (signed != null) fotosVeiculos[id] = signed;
        }
      }
      if (mounted) setState(() => _fotosVeiculoPorId = fotosVeiculos);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = friendlyError(e);
        _carregando = false;
      });
    }
  }

  String _nomeVeiculo(String? id) {
    if (id == null) return 'Sem veículo';
    final v = _veiculosPorId[id];
    if (v == null) return 'Veículo removido';
    return '${v['plate'] ?? '--'} • ${v['brand'] ?? ''} ${v['model'] ?? ''}';
  }

  String _fmtData(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDataCurta(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  /// Agrega veículos distintos que o motorista já pilotou (via checklists e
  /// viagens), com quantidade de usos, última data e manutenções do veículo.
  List<Map<String, dynamic>> get _veiculosAgregados {
    final Map<String, Map<String, dynamic>> agregados = {};

    void registrar(String? veiculoId, String? dataRef) {
      if (veiculoId == null) return;
      final atual = agregados[veiculoId];
      final dt = DateTime.tryParse(dataRef ?? '');
      if (atual == null) {
        agregados[veiculoId] = {'id': veiculoId, 'usos': 1, 'ultima': dt};
      } else {
        atual['usos'] = (atual['usos'] as int) + 1;
        final ultimaAtual = atual['ultima'] as DateTime?;
        if (dt != null && (ultimaAtual == null || dt.isAfter(ultimaAtual))) {
          atual['ultima'] = dt;
        }
      }
    }

    for (final c in _checklists) {
      registrar(c['veiculo_id']?.toString(), c['criado_em']?.toString() ?? c['data']?.toString());
    }
    for (final v in _viagens) {
      registrar(v['veiculo_id']?.toString(), v['data_inicio']?.toString());
    }

    final lista = agregados.values.toList();
    lista.sort((a, b) {
      final da = a['ultima'] as DateTime?;
      final db = b['ultima'] as DateTime?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.motorista;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${m['name'] ?? '--'} • Histórico'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar, tooltip: 'Atualizar'),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Text('Erro ao carregar histórico: $_erro',
                      style: const TextStyle(color: AppColors.danger)),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _cardMotorista(m),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Veículos que já pilotou',
                        icone: Icons.directions_car_filled_outlined,
                        vazio: 'Nenhum registro de uso ainda.',
                        itens: _veiculosAgregados.map((v) {
                          final ultima = v['ultima'] as DateTime?;
                          final vid = v['id']?.toString();
                          final qtdManut = _manutencoesPorVeiculoId[vid] ?? 0;
                          return _linhaHistorico(
                            titulo: _nomeVeiculo(vid),
                            subtitulo: '${v['usos']} uso(s) • último em ${ultima != null ? _fmtDataCurta(ultima.toIso8601String()) : '—'}'
                                '${qtdManut > 0 ? ' • $qtdManut manutenção(ões) no veículo' : ''}',
                            icone: iconeParaTipoVeiculo(_veiculosPorId[vid]?['tipo']?.toString()),
                            fotoUrl: _fotosVeiculoPorId[vid],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Atribuições (veículos sob sua responsabilidade)',
                        icone: Icons.assignment_ind_outlined,
                        vazio: 'Nenhuma atribuição registrada ainda.',
                        itens: _atribuicoes.map((a) {
                          final aberta = a['data_fim'] == null;
                          return _linhaHistorico(
                            titulo: _nomeVeiculo(a['veiculo_id']?.toString()),
                            subtitulo: aberta
                                ? 'Desde ${_fmtData(a['data_inicio']?.toString())} • atual'
                                : '${_fmtData(a['data_inicio']?.toString())} até ${_fmtData(a['data_fim']?.toString())}',
                            icone: Icons.assignment_ind_outlined,
                            corIcone: aberta ? AppColors.success : AppColors.textSecondary,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Registro de saída/retorno (${_checklists.length})',
                        icone: Icons.fact_check_outlined,
                        vazio: 'Nenhum checklist registrado ainda.',
                        itens: _checklists.map((c) {
                          final tipo = c['tipo']?.toString() ?? '';
                          final aprovado = c['aprovado'] == true;
                          return _linhaHistorico(
                            titulo: '${tipo == 'saida' ? 'Saída' : tipo == 'retorno' ? 'Retorno' : tipo} • ${_nomeVeiculo(c['veiculo_id']?.toString())}',
                            subtitulo: '${_fmtData(c['criado_em']?.toString() ?? c['data']?.toString())}'
                                '${c['km_final'] != null ? ' • Km: ${c['km_final']}' : ''}',
                            icone: tipo == 'saida' ? Icons.logout_rounded : Icons.login_rounded,
                            corIcone: aprovado ? AppColors.success : AppColors.warning,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Viagens (${_viagens.length})',
                        icone: Icons.alt_route_rounded,
                        vazio: 'Nenhuma viagem registrada ainda.',
                        itens: _viagens.map((viagem) {
                          return _linhaHistorico(
                            titulo: '${viagem['origem'] ?? '—'} → ${viagem['destino'] ?? '—'}',
                            subtitulo: '${_nomeVeiculo(viagem['veiculo_id']?.toString())} • '
                                '${_fmtData(viagem['data_inicio']?.toString())}'
                                '${viagem['quilometragem_percorrida'] != null ? ' • ${viagem['quilometragem_percorrida']} km' : ''}',
                            icone: Icons.route_outlined,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _cardMotorista(Map<String, dynamic> m) {
    final isAgregado = m['tipo_vinculo']?.toString() == 'agregado';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: _fotoMotoristaAssinada != null
                ? Image.network(
                    _fotoMotoristaAssinada!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.person, color: AppColors.secondary, size: 26),
                  )
                : const Icon(Icons.person, color: AppColors.secondary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(m['name']?.toString() ?? '--',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isAgregado) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Agregado',
                          style: TextStyle(color: AppColors.secondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text('CNH: ${m['cnh_number'] ?? '--'} ${m['cnh_category'] != null ? '• Cat. ${m['cnh_category']}' : ''}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secao({
    required String titulo,
    required IconData icone,
    required String vazio,
    required List<Widget> itens,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, size: 18, color: AppColors.secondary),
            const SizedBox(width: 8),
            Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (itens.isEmpty)
            Text(vazio, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
          else
            Column(children: itens),
        ],
      ),
    );
  }

  Widget _linhaHistorico({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    Color? corIcone,
    String? fotoUrl,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fotoUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(
                fotoUrl,
                width: 22,
                height: 22,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(icone, size: 16, color: corIcone ?? AppColors.textSecondary),
              ),
            )
          else
            Icon(icone, size: 16, color: corIcone ?? AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitulo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

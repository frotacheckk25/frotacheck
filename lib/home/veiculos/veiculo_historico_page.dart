import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/signed_storage_url.dart';
import '../../core/utils/snackbar_utils.dart';
import 'veiculo_tipo.dart';

/// Histórico completo de um veículo: motoristas que já dirigiram, registro
/// de saída/retorno (checklists), viagens e manutenções — tudo num só lugar,
/// a pedido do cliente.
class VeiculoHistoricoPage extends StatefulWidget {
  final Map<String, dynamic> veiculo;

  const VeiculoHistoricoPage({super.key, required this.veiculo});

  @override
  State<VeiculoHistoricoPage> createState() => _VeiculoHistoricoPageState();
}

class _VeiculoHistoricoPageState extends State<VeiculoHistoricoPage> {
  final _supabase = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;

  List<Map<String, dynamic>> _checklists = [];
  List<Map<String, dynamic>> _viagens = [];
  List<Map<String, dynamic>> _manutencoes = [];
  List<Map<String, dynamic>> _atribuicoes = [];
  Map<String, String> _nomesPorMotoristaId = {};
  Map<String, String> _fotosMotoristaPorId = {};
  String? _fotoUrlAssinada;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String get _veiculoId => widget.veiculo['id'].toString();

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('checklists')
            .select('id, tipo, data, criado_em, motorista_id, km_final, aprovado')
            .eq('veiculo_id', _veiculoId)
            .order('criado_em', ascending: false)
            .limit(200),
        _supabase
            .from('viagens')
            .select('id, motorista_id, data_inicio, data_fim, origem, destino, quilometragem_percorrida, status')
            .eq('veiculo_id', _veiculoId)
            .order('data_inicio', ascending: false)
            .limit(200),
        _supabase
            .from('manutencoes')
            .select('id, tipo, descricao, data, status, valor, cost, oficina, peca_trocada')
            .eq('vehicle_id', _veiculoId)
            .order('data', ascending: false)
            .limit(200),
        _supabase.from('drivers').select('id, name, foto_url'),
        _supabase
            .from('atribuicoes_veiculo')
            .select('id, motorista_id, data_inicio, data_fim')
            .eq('veiculo_id', _veiculoId)
            .order('data_inicio', ascending: false)
            .limit(200),
      ]);

      final checklists = List<Map<String, dynamic>>.from(results[0] as List);
      final viagens = List<Map<String, dynamic>>.from(results[1] as List);
      final manutencoes = List<Map<String, dynamic>>.from(results[2] as List);
      final drivers = List<Map<String, dynamic>>.from(results[3] as List);
      final atribuicoes = List<Map<String, dynamic>>.from(results[4] as List);

      if (!mounted) return;
      setState(() {
        _checklists = checklists;
        _viagens = viagens;
        _manutencoes = manutencoes;
        _atribuicoes = atribuicoes;
        _nomesPorMotoristaId = {
          for (final d in drivers) (d['id']?.toString() ?? ''): d['name']?.toString() ?? '—',
        };
        _carregando = false;
      });
      final fotoUrl = widget.veiculo['foto_url'] as String?;
      if (fotoUrl != null && fotoUrl.isNotEmpty) {
        final signed = await toSignedStorageUrl(fotoUrl);
        if (mounted) setState(() => _fotoUrlAssinada = signed);
      }
      final fotosMotoristas = <String, String>{};
      for (final d in drivers) {
        final id = d['id']?.toString();
        final foto = d['foto_url'] as String?;
        if (id != null && foto != null && foto.isNotEmpty) {
          final signed = await toSignedStorageUrl(foto);
          if (signed != null) fotosMotoristas[id] = signed;
        }
      }
      if (mounted) setState(() => _fotosMotoristaPorId = fotosMotoristas);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = friendlyError(e);
        _carregando = false;
      });
    }
  }

  String _nomeMotorista(String? id) {
    if (id == null) return 'Sem motorista';
    return _nomesPorMotoristaId[id] ?? 'Motorista removido';
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

  /// Agrega motoristas distintos que já usaram o veículo (via checklists e
  /// viagens), com quantidade de usos e a data mais recente de cada um.
  List<Map<String, dynamic>> get _motoristasAgregados {
    final Map<String, Map<String, dynamic>> agregados = {};

    void registrar(String? motoristaId, String? dataRef) {
      if (motoristaId == null) return;
      final atual = agregados[motoristaId];
      final dt = DateTime.tryParse(dataRef ?? '');
      if (atual == null) {
        agregados[motoristaId] = {'id': motoristaId, 'usos': 1, 'ultima': dt};
      } else {
        atual['usos'] = (atual['usos'] as int) + 1;
        final ultimaAtual = atual['ultima'] as DateTime?;
        if (dt != null && (ultimaAtual == null || dt.isAfter(ultimaAtual))) {
          atual['ultima'] = dt;
        }
      }
    }

    for (final c in _checklists) {
      registrar(c['motorista_id']?.toString(), c['criado_em']?.toString() ?? c['data']?.toString());
    }
    for (final v in _viagens) {
      registrar(v['motorista_id']?.toString(), v['data_inicio']?.toString());
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
    final v = widget.veiculo;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${v['plate'] ?? '--'} • Histórico'),
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
                      _cardVeiculo(v),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Motoristas que já dirigiram',
                        icone: Icons.people_alt_outlined,
                        vazio: 'Nenhum registro de uso ainda.',
                        itens: _motoristasAgregados.map((m) {
                          final ultima = m['ultima'] as DateTime?;
                          return _linhaHistorico(
                            titulo: _nomeMotorista(m['id']?.toString()),
                            subtitulo: '${m['usos']} uso(s) • último em ${ultima != null ? _fmtDataCurta(ultima.toIso8601String()) : '—'}',
                            icone: Icons.person_outline,
                            fotoUrl: _fotosMotoristaPorId[m['id']?.toString()],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Atribuições (quem pegou e quando)',
                        icone: Icons.assignment_ind_outlined,
                        vazio: 'Nenhuma atribuição de motorista registrada ainda.',
                        itens: _atribuicoes.map((a) {
                          final aberta = a['data_fim'] == null;
                          return _linhaHistorico(
                            titulo: _nomeMotorista(a['motorista_id']?.toString()),
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
                            titulo: '${tipo == 'saida' ? 'Saída' : tipo == 'retorno' ? 'Retorno' : tipo} • ${_nomeMotorista(c['motorista_id']?.toString())}',
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
                            subtitulo: '${_nomeMotorista(viagem['motorista_id']?.toString())} • '
                                '${_fmtData(viagem['data_inicio']?.toString())}'
                                '${viagem['quilometragem_percorrida'] != null ? ' • ${viagem['quilometragem_percorrida']} km' : ''}',
                            icone: Icons.route_outlined,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _secao(
                        titulo: 'Manutenções (${_manutencoes.length})',
                        icone: Icons.build_outlined,
                        vazio: 'Nenhuma manutenção registrada ainda.',
                        itens: _manutencoes.map((manut) {
                          final valor = manut['valor'] ?? manut['cost'];
                          final status = manut['status']?.toString() ?? '';
                          return _linhaHistorico(
                            titulo: manut['tipo']?.toString() ?? manut['descricao']?.toString() ?? 'Manutenção',
                            subtitulo: '${_fmtDataCurta(manut['data']?.toString())}'
                                '${valor != null ? ' • R\$ $valor' : ''}'
                                '${manut['oficina'] != null ? ' • ${manut['oficina']}' : ''}',
                            icone: Icons.build_circle_outlined,
                            corIcone: status == 'Resolvido' ? AppColors.success : AppColors.warning,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _cardVeiculo(Map<String, dynamic> v) {
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
            child: _fotoUrlAssinada != null
                ? Image.network(
                    _fotoUrlAssinada!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(iconeParaTipoVeiculo(v['tipo']?.toString()), color: AppColors.secondary, size: 26),
                  )
                : Icon(iconeParaTipoVeiculo(v['tipo']?.toString()), color: AppColors.secondary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${v['plate'] ?? '--'} • ${v['brand'] ?? ''} ${v['model'] ?? ''}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Ano: ${v['year'] ?? '--'} • Km atual: ${v['odometer'] ?? '--'} • Cor: ${v['color'] ?? '--'}',
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

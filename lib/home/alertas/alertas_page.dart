import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../pages/detalhe_ocorrencia_page.dart';

// Fontes de alerta sintético
const _srcAlert = 'alert';
const _srcMulta = 'multa';
const _srcDoc = 'documento';
const _srcOleo = 'oleo';
const _srcManut = 'manutencao';

class AlertasPage extends StatefulWidget {
  const AlertasPage({super.key});

  @override
  State<AlertasPage> createState() => _AlertasPageState();
}

class _AlertasPageState extends State<AlertasPage> {
  final supabase = Supabase.instance.client;

  // Lista unificada (alerts + sintéticos)
  List<Map<String, dynamic>> alertas = [];
  List<Map<String, dynamic>> ocorrenciasCriticas = [];
  bool carregando = true;
  String filtroStatus = 'todos';
  String filtroTipo = 'todos';
  String filtroFonte = 'todos';
  Timer? _timer;

  final Set<String> _processando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Carga de dados — cada query falha de forma isolada ────────────────────────
  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => carregando = true);

    // Dados base
    List<Map<String, dynamic>> rawAlertas = [];
    List<Map<String, dynamic>> rawMultas = [];
    List<Map<String, dynamic>> rawDocs = [];
    List<Map<String, dynamic>> rawOcorr = [];
    List<Map<String, dynamic>> rawOleos = [];
    List<Map<String, dynamic>> rawPlanos = [];
    Map<String, Map<String, dynamic>> veicMap = {};
    Map<String, Map<String, dynamic>> motMap = {};

    await Future.wait([
      // Tabela alerts (ocorrências, testes, etc.)
      supabase
          .from('alerts')
          .select()
          .order('created_at', ascending: false)
          .then((r) {
            rawAlertas = List<Map<String, dynamic>>.from(
              (r as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          })
          .catchError((e) {
            debugPrint('alerts query: $e');
          }),

      // Multas abertas
      supabase
          .from('multas')
          .select('id, vehicle_id, veiculo_id, tipo, valor, data, created_at')
          .eq('status', 'aberta')
          .order('created_at', ascending: false)
          .then((r) {
            rawMultas = List<Map<String, dynamic>>.from(
              (r as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          })
          .catchError((e) {
            debugPrint('multas query: $e');
          }),

      // Documentos (todos, para filtrar vencidos/vencendo)
      supabase
          .from('documentos')
          .select('id, vehicle_id, veiculo_id, tipo, descricao, data_vencimento, created_at')
          .then((r) {
            rawDocs = List<Map<String, dynamic>>.from(
              (r as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          })
          .catchError((e) {
            debugPrint('documentos query: $e');
          }),

      // Ocorrências críticas abertas
      supabase
          .from('occurrences')
          .select('id, problem_type, problem, priority, status, location, created_at, vehicle_id, driver_id')
          .neq('status', 'Resolvido')
          .eq('priority', 'Alta')
          .order('created_at', ascending: false)
          .limit(10)
          .then((r) {
            rawOcorr = List<Map<String, dynamic>>.from(
              (r as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          })
          .catchError((e) {
            debugPrint('occurrences query: $e');
          }),

      // Trocas de óleo recentes (últimos 30 registros, para detectar próximas trocas)
      supabase
          .from('oil_changes')
          .select('id, vehicle_id, service_type, oil_change_date, next_change_km, current_km, notes, created_at')
          .order('created_at', ascending: false)
          .limit(30)
          .then((r) {
            rawOleos = List<Map<String, dynamic>>.from(
              (r as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          })
          .catchError((e) {
            debugPrint('oil_changes query: $e');
          }),

      // Planos de manutenção
      supabase
          .from('maintenance_plans')
          .select('*')
          .then((r) {
            rawPlanos = List<Map<String, dynamic>>.from(
              (r as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          })
          .catchError((e) {
            debugPrint('maintenance_plans query: $e');
          }),

      // Veículos
      supabase
          .from('vehicles')
          .select('id, plate, brand, model, odometer')
          .then((r) {
            for (final v in (r as List)) {
              final row = Map<String, dynamic>.from(v as Map);
              veicMap[row['id'].toString()] = row;
            }
          })
          .catchError((e) {
            debugPrint('vehicles query: $e');
          }),

      // Motoristas
      supabase
          .from('drivers')
          .select('id, name')
          .then((r) {
            for (final m in (r as List)) {
              final row = Map<String, dynamic>.from(m as Map);
              motMap[row['id'].toString()] = row;
            }
          })
          .catchError((e) {
            debugPrint('drivers query: $e');
          }),
    ]);

    // ── Alertas da tabela alerts (marcar fonte) ───────────────────────────────
    final alertasTabela = rawAlertas.map((a) => <String, dynamic>{
          ...a,
          '_source': _srcAlert,
        }).toList();

    // ── Sintéticos: Multas abertas ────────────────────────────────────────────
    final alertasMultas = rawMultas.map((m) {
      final vid = m['vehicle_id']?.toString() ?? m['veiculo_id']?.toString();
      final veiculo = vid != null ? veicMap[vid] : null;
      final placa = veiculo?['plate']?.toString() ?? 'Veículo desconhecido';
      final v = m['valor'];
      final valor = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
      return <String, dynamic>{
        '_source': _srcMulta,
        '_ref_id': m['id']?.toString(),
        'title': 'Multa Aberta — $placa',
        'subtitle': '${m['tipo'] ?? 'Infração'} · R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}',
        'tipo': 'warning',
        'status': 'ativo',
        'created_at': m['data'] ?? m['created_at'],
      };
    }).toList();

    // ── Sintéticos: Documentos vencidos / vencendo ────────────────────────────
    final now = DateTime.now();
    final alertasDocs = <Map<String, dynamic>>[];
    for (final d in rawDocs) {
      final vencStr = d['data_vencimento']?.toString();
      if (vencStr == null) continue;
      final venc = DateTime.tryParse(vencStr);
      if (venc == null) continue;
      final dias = venc.difference(now).inDays;
      if (dias > 30) continue; // Apenas vencidos ou vencendo em 30 dias
      final vid = d['vehicle_id']?.toString() ?? d['veiculo_id']?.toString();
      final veiculo = vid != null ? veicMap[vid] : null;
      final placa = veiculo?['plate']?.toString() ?? 'Veículo desconhecido';
      final tipo = d['tipo']?.toString() ?? 'Documento';
      alertasDocs.add({
        '_source': _srcDoc,
        '_ref_id': d['id']?.toString(),
        'title': dias < 0
            ? 'Documento Vencido — $tipo · $placa'
            : 'Documento a Vencer — $tipo · $placa',
        'subtitle': dias < 0
            ? 'Venceu há ${(-dias)} dia(s)'
            : dias == 0
                ? 'Vence hoje!'
                : 'Vence em $dias dia(s)',
        'tipo': dias < 0 ? 'error' : 'warning',
        'status': 'ativo',
        'created_at': vencStr,
      });
    }

    // ── Sintéticos: Trocas de óleo (próxima troca iminente) ──────────────────
    // Agrupa por vehicle_id, pega a troca mais recente por veículo
    final oleoByVehicle = <String, Map<String, dynamic>>{};
    for (final o in rawOleos) {
      final vid = o['vehicle_id']?.toString() ?? '';
      if (vid.isEmpty) continue;
      if (!oleoByVehicle.containsKey(vid)) oleoByVehicle[vid] = o;
    }
    final alertasOleos = <Map<String, dynamic>>[];
    for (final entry in oleoByVehicle.entries) {
      final o = entry.value;
      final vid = entry.key;
      final veiculo = veicMap[vid];
      final placa = veiculo?['plate']?.toString() ?? 'Veículo desconhecido';
      final nextKm = o['next_change_km'];
      final currentKm = veiculo?['odometer'] ?? o['current_km'];
      if (nextKm == null) continue;
      final nextInt = (nextKm is num) ? nextKm.toInt() : int.tryParse(nextKm.toString()) ?? 0;
      final currInt = currentKm != null
          ? ((currentKm is num) ? currentKm.toInt() : int.tryParse(currentKm.toString()) ?? 0)
          : 0;
      final faltam = nextInt - currInt;
      if (faltam > 2000) continue; // Só mostra se faltam 2000 km ou menos
      final servico = o['service_type']?.toString() ?? 'Troca de óleo';
      alertasOleos.add({
        '_source': _srcOleo,
        '_ref_id': o['id']?.toString(),
        'title': '$servico — $placa',
        'subtitle': faltam <= 0
            ? 'Troca atrasada! Prevista em $nextInt km (atual: $currInt km)'
            : 'Faltam $faltam km · Prevista em $nextInt km',
        'tipo': faltam <= 0 ? 'error' : 'warning',
        'status': 'ativo',
        'created_at': o['created_at'],
      });
    }

    // ── Sintéticos: Planos de manutenção ─────────────────────────────────────
    final alertasManut = <Map<String, dynamic>>[];
    for (final p in rawPlanos) {
      final nextKm = p['next_service_km'];
      if (nextKm == null) continue;
      final nextInt = (nextKm is num) ? nextKm.toInt() : int.tryParse(nextKm.toString()) ?? 0;
      final plate = p['vehicle_plate']?.toString() ?? '-';
      // Tenta encontrar odômetro do veículo pela placa
      final veiculo = veicMap.values.firstWhere(
        (v) => v['plate']?.toString() == plate,
        orElse: () => {},
      );
      final currInt = veiculo.isNotEmpty
          ? ((veiculo['odometer'] is num)
              ? veiculo['odometer'].toInt()
              : int.tryParse(veiculo['odometer']?.toString() ?? '') ?? 0)
          : 0;
      final faltam = nextInt - currInt;
      if (faltam > 2000) continue;
      alertasManut.add({
        '_source': _srcManut,
        '_ref_id': p['id']?.toString(),
        'title': 'Manutenção Prevista — $plate',
        'subtitle': faltam <= 0
            ? 'Serviço atrasado! Previsto em $nextInt km'
            : 'Faltam $faltam km · Próximo serviço em $nextInt km',
        'tipo': faltam <= 0 ? 'error' : 'warning',
        'status': 'ativo',
        'created_at': null,
      });
    }

    // ── Ocorrências críticas para destaque visual ─────────────────────────────
    final ocorrComDados = rawOcorr.map((o) {
      final vid = o['vehicle_id']?.toString();
      final mid = o['driver_id']?.toString();
      final veiculo = vid != null ? veicMap[vid] : null;
      final motorista = mid != null ? motMap[mid] : null;
      return <String, dynamic>{
        ...o,
        '_placa': veiculo?['plate'] ?? '-',
        '_modelo': veiculo?['model'] ?? '',
        '_motorista': motorista?['name'] ?? '-',
      };
    }).toList();

    // ── Merge e ordenação ─────────────────────────────────────────────────────
    final todos = [
      ...alertasTabela,
      ...alertasMultas,
      ...alertasDocs,
      ...alertasOleos,
      ...alertasManut,
    ];

    // Ordena: resolvidos por último; dentro de cada grupo: error > warning > info; depois por data desc
    todos.sort((a, b) {
      const ordemTipo = {'error': 0, 'warning': 1, 'info': 2};
      final sa = (a['status'] ?? 'ativo') == 'resolvido' ? 1 : 0;
      final sb = (b['status'] ?? 'ativo') == 'resolvido' ? 1 : 0;
      if (sa != sb) return sa.compareTo(sb);
      final ta = ordemTipo[a['tipo'] ?? 'info'] ?? 2;
      final tb = ordemTipo[b['tipo'] ?? 'info'] ?? 2;
      if (ta != tb) return ta.compareTo(tb);
      final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
      return db.compareTo(da);
    });

    if (!mounted) return;
    setState(() {
      alertas = todos;
      ocorrenciasCriticas = ocorrComDados;
      carregando = false;
    });
  }

  // ── Resolver alerta (apenas da tabela alerts) ─────────────────────────────
  Future<void> _marcarResolvido(Map<String, dynamic> alerta) async {
    final id = alerta['id']?.toString();
    if (id == null) return;

    setState(() {
      _processando.add(id);
      final idx = alertas.indexWhere((a) => a['id']?.toString() == id);
      if (idx != -1) alertas[idx] = {...alertas[idx], 'status': 'resolvido'};
    });

    try {
      await supabase.from('alerts').update({'status': 'resolvido'}).eq('id', id);

      // Se o alerta tem ocorrência vinculada, resolve também
      final occId = alerta['occurrence_id']?.toString();
      if (occId != null && occId.isNotEmpty) {
        try {
          await supabase.from('occurrences').update({'status': 'Resolvido'}).eq('id', occId);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Alerta marcado como resolvido'),
            ]),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
      _carregar();
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = alertas.indexWhere((a) => a['id']?.toString() == id);
          if (idx != -1) alertas[idx] = {...alertas[idx], 'status': 'ativo'};
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando.remove(id));
    }
  }

  Future<void> _verOcorrencia(String? occId) async {
    if (occId == null || occId.isEmpty) return;
    try {
      final result = await supabase
          .from('occurrences')
          .select('*')
          .eq('id', occId)
          .maybeSingle();
      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ocorrência não encontrada')));
        }
        return;
      }
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetalheOcorrenciaPage(
              ocorrencia: result,
              onStatusChanged: _carregar,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  // ── Filtros ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtrados => alertas.where((a) {
        final status = (a['status'] ?? 'ativo').toString();
        final tipo = (a['tipo'] ?? 'info').toString();
        final fonte = (a['_source'] ?? _srcAlert).toString();
        if (filtroStatus != 'todos' && status != filtroStatus) return false;
        if (filtroTipo != 'todos' && tipo != filtroTipo) return false;
        if (filtroFonte != 'todos' && fonte != filtroFonte) return false;
        return true;
      }).toList();

  int get _pendentes => alertas.where((a) => (a['status'] ?? 'ativo') == 'ativo').length;
  int get _criticos =>
      alertas.where((a) => a['tipo'] == 'error' && (a['status'] ?? 'ativo') == 'ativo').length;
  int get _resolvidos => alertas.where((a) => a['status'] == 'resolvido').length;

  // ── Helpers visuais ───────────────────────────────────────────────────────
  Color _tipoColor(String? tipo) => switch (tipo) {
        'error' => AppColors.danger,
        'warning' => AppColors.warning,
        _ => AppColors.secondary,
      };

  IconData _fonteIcon(Map<String, dynamic> alerta) {
    final fonte = alerta['_source']?.toString() ?? _srcAlert;
    final titulo = (alerta['title'] ?? '').toString().toLowerCase();
    return switch (fonte) {
      _srcMulta => Icons.gavel,
      _srcDoc => Icons.description,
      _srcOleo => Icons.opacity,
      _srcManut => Icons.build,
      _ => _tituloIcon(titulo, alerta['tipo']),
    };
  }

  IconData _tituloIcon(String t, String? tipo) {
    if (t.contains('óleo') || t.contains('oleo')) return Icons.opacity;
    if (t.contains('cnh')) return Icons.badge;
    if (t.contains('licen')) return Icons.assignment;
    if (t.contains('checklist')) return Icons.checklist;
    if (t.contains('seguro')) return Icons.security;
    if (t.contains('pneu')) return Icons.tire_repair;
    if (t.contains('ocorrência') || t.contains('ocorr')) return Icons.report_problem;
    if (t.contains('manut')) return Icons.build;
    if (t.contains('document')) return Icons.description;
    if (t.contains('multa')) return Icons.gavel;
    return switch (tipo) {
      'error' => Icons.error_outline,
      'warning' => Icons.warning_amber,
      _ => Icons.info_outline,
    };
  }

  String _fonteLabel(String? fonte) => switch (fonte) {
        _srcMulta => 'Multa',
        _srcDoc => 'Documento',
        _srcOleo => 'Troca de Óleo',
        _srcManut => 'Manutenção',
        _ => 'Alerta',
      };

  String _fmtDate(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Alertas'),
        backgroundColor: AppColors.surface,
        actions: [
          if (carregando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregar,
              tooltip: 'Atualizar',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFf59e0b), Color(0xFFef4444)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.notifications_active,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Alertas da Frota',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  '$_pendentes pendente(s) · $_resolvidos resolvido(s) · auto-atualiza 30s',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // KPIs
                    Row(
                      children: [
                        _kpi('Total', '${alertas.length}', Icons.notifications,
                            AppColors.secondary),
                        const SizedBox(width: 8),
                        _kpi('Pendentes', '$_pendentes', Icons.pending, AppColors.warning),
                        const SizedBox(width: 8),
                        _kpi('Críticos', '$_criticos', Icons.priority_high, AppColors.danger),
                        const SizedBox(width: 8),
                        _kpi('Resolvidos', '$_resolvidos', Icons.check_circle, AppColors.success),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Ocorrências críticas em destaque
                    if (ocorrenciasCriticas.isNotEmpty) ...[
                      Row(children: [
                        const Icon(Icons.warning_amber, color: AppColors.danger, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${ocorrenciasCriticas.length} ocorrência(s) crítica(s) em aberto',
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      ...ocorrenciasCriticas.take(3).map(_buildOcorrenciaCriticaCard),
                      if (ocorrenciasCriticas.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            '+${ocorrenciasCriticas.length - 3} outras ocorrências críticas',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 8),
                    ],

                    // Filtros: Status
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip('Todos', filtroStatus, 'todos',
                              (v) => setState(() => filtroStatus = v)),
                          const SizedBox(width: 8),
                          _chip('Pendentes', filtroStatus, 'ativo',
                              (v) => setState(() => filtroStatus = v),
                              color: AppColors.warning),
                          const SizedBox(width: 8),
                          _chip('Resolvidos', filtroStatus, 'resolvido',
                              (v) => setState(() => filtroStatus = v),
                              color: AppColors.success),
                          const SizedBox(width: 16),
                          Container(width: 1, height: 20, color: AppColors.border),
                          const SizedBox(width: 16),
                          _chip('Todos tipos', filtroTipo, 'todos',
                              (v) => setState(() => filtroTipo = v)),
                          const SizedBox(width: 8),
                          _chip('Crítico', filtroTipo, 'error',
                              (v) => setState(() => filtroTipo = v),
                              color: AppColors.danger),
                          const SizedBox(width: 8),
                          _chip('Aviso', filtroTipo, 'warning',
                              (v) => setState(() => filtroTipo = v),
                              color: AppColors.warning),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Filtros: Fonte
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        const Text('Fonte: ',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(width: 4),
                        _chip('Todos', filtroFonte, 'todos',
                            (v) => setState(() => filtroFonte = v)),
                        const SizedBox(width: 8),
                        _chip('Alertas', filtroFonte, _srcAlert,
                            (v) => setState(() => filtroFonte = v)),
                        const SizedBox(width: 8),
                        _chip('Multas', filtroFonte, _srcMulta,
                            (v) => setState(() => filtroFonte = v),
                            color: AppColors.danger),
                        const SizedBox(width: 8),
                        _chip('Documentos', filtroFonte, _srcDoc,
                            (v) => setState(() => filtroFonte = v),
                            color: const Color(0xFF0ea5e9)),
                        const SizedBox(width: 8),
                        _chip('Óleo', filtroFonte, _srcOleo,
                            (v) => setState(() => filtroFonte = v),
                            color: const Color(0xFFf97316)),
                        const SizedBox(width: 8),
                        _chip('Manutenção', filtroFonte, _srcManut,
                            (v) => setState(() => filtroFonte = v),
                            color: const Color(0xFF8B5CF6)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text('${filtrados.length} alerta(s)',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Lista
            if (carregando)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (filtrados.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_off, size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        alertas.isEmpty
                            ? 'Nenhum alerta registrado'
                            : 'Nenhum alerta para este filtro',
                        style: const TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _alertaCard(filtrados[i]),
                    ),
                    childCount: filtrados.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────
  Widget _buildOcorrenciaCriticaCard(Map<String, dynamic> o) {
    final placa = o['_placa']?.toString() ?? '-';
    final modelo = o['_modelo']?.toString() ?? '';
    final tipo = o['problem_type']?.toString() ?? 'Ocorrência';
    final local = o['location']?.toString() ?? '';
    final status = o['status']?.toString() ?? 'Aberto';
    final id = o['id']?.toString() ?? '';

    return GestureDetector(
      onTap: id.isNotEmpty ? () => _verOcorrencia(id) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.danger.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppColors.danger, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$tipo — $placa${modelo.isNotEmpty ? ' ($modelo)' : ''}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (local.isNotEmpty)
                    Text(local,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(status,
                  style: const TextStyle(
                      color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _alertaCard(Map<String, dynamic> alerta) {
    final id = alerta['id']?.toString() ?? '';
    final titulo = alerta['title']?.toString() ?? alerta['titulo']?.toString() ?? 'Alerta';
    final descricao = alerta['subtitle']?.toString() ?? alerta['descricao']?.toString() ?? '';
    final tipo = alerta['tipo']?.toString() ?? 'info';
    final status = alerta['status']?.toString() ?? 'ativo';
    final resolvido = status == 'resolvido';
    final fonte = alerta['_source']?.toString() ?? _srcAlert;
    final isDaTabela = fonte == _srcAlert;
    final occId = alerta['occurrence_id']?.toString();
    final temOcorrencia = occId != null && occId.isNotEmpty;
    final cor = resolvido ? AppColors.success : _tipoColor(tipo);
    final data = _fmtDate(alerta['created_at']?.toString());
    final processando = _processando.contains(id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: resolvido ? AppColors.success.withOpacity(0.25) : cor.withOpacity(0.35),
          width: resolvido ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  resolvido ? Icons.check_circle : _fonteIcon(alerta),
                  color: cor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: resolvido ? AppColors.textSecondary : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        decoration: resolvido ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textSecondary,
                      ),
                    ),
                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(descricao,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botão resolver — só para alertas da tabela
              if (isDaTabela)
                if (resolvido)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withOpacity(0.4)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle, color: AppColors.success, size: 12),
                      SizedBox(width: 4),
                      Text('Resolvido',
                          style: TextStyle(
                              color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  )
                else if (processando)
                  const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success))
                else
                  Tooltip(
                    message: 'Marcar como resolvido',
                    child: GestureDetector(
                      onTap: () => _marcarResolvido(alerta),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 18),
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Badge tipo
              _badge(
                resolvido
                    ? 'Resolvido'
                    : tipo == 'error'
                        ? 'Crítico'
                        : tipo == 'warning'
                            ? 'Aviso'
                            : 'Info',
                cor,
              ),
              const SizedBox(width: 6),
              // Badge fonte
              _badge(_fonteLabel(fonte), _fonteColor(fonte)),
              if (data.isNotEmpty) ...[
                const SizedBox(width: 6),
                _badge(data, AppColors.textSecondary),
              ],
              const Spacer(),
              if (temOcorrencia)
                GestureDetector(
                  onTap: () => _verOcorrencia(occId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_new, color: AppColors.secondary, size: 11),
                      SizedBox(width: 4),
                      Text('Ver ocorrência',
                          style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _fonteColor(String? fonte) => switch (fonte) {
        _srcMulta => AppColors.danger,
        _srcDoc => const Color(0xFF0ea5e9),
        _srcOleo => const Color(0xFFf97316),
        _srcManut => const Color(0xFF8B5CF6),
        _ => AppColors.secondary,
      };

  Widget _kpi(String label, String value, IconData icon, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );

  Widget _chip(String label, String current, String value, ValueChanged<String> onTap,
      {Color? color}) {
    final selected = current == value;
    final c = color ?? AppColors.secondary;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? c : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

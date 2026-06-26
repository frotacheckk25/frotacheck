import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../pages/detalhe_ocorrencia_page.dart';

class AlertasPage extends StatefulWidget {
  const AlertasPage({super.key});

  @override
  State<AlertasPage> createState() => _AlertasPageState();
}

class _AlertasPageState extends State<AlertasPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> alertas = [];
  List<Map<String, dynamic>> ocorrenciasCriticas = [];
  bool carregando = true;
  String filtroStatus = 'todos';
  String filtroTipo = 'todos';
  Timer? _timer;

  final Set<String> _processando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
    // Auto-refresh a cada 30 segundos
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    if (!carregando) setState(() => carregando = true);
    try {
      final results = await Future.wait([
        // Alertas ordenados: erro primeiro, depois warning, depois info; mais recentes primeiro
        supabase.from('alerts').select().order('created_at', ascending: false),
        // Ocorrências críticas abertas (Alta prioridade, não resolvidas)
        supabase
            .from('occurrences')
            .select(
              'id, problem_type, problem, priority, status, location, created_at, vehicle_id, driver_id',
            )
            .neq('status', 'Resolvido')
            .eq('priority', 'Alta')
            .order('created_at', ascending: false)
            .limit(10),
        supabase.from('vehicles').select('id, plate, model'),
        supabase.from('drivers').select('id, name'),
      ]);

      final rawAlertas = List<Map<String, dynamic>>.from(
        (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final rawOcorr = List<Map<String, dynamic>>.from(
        (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final veicMap = <String, Map<String, dynamic>>{};
      for (final v in (results[2] as List)) {
        final m = Map<String, dynamic>.from(v as Map);
        veicMap[m['id'].toString()] = m;
      }
      final motMap = <String, Map<String, dynamic>>{};
      for (final m in (results[3] as List)) {
        final row = Map<String, dynamic>.from(m as Map);
        motMap[row['id'].toString()] = row;
      }

      // Resolve placa/motorista nas ocorrências
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

      // Ordena alertas: error > warning > info, depois por data
      rawAlertas.sort((a, b) {
        final ordemTipo = {'error': 0, 'warning': 1, 'info': 2};
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
        alertas = rawAlertas;
        ocorrenciasCriticas = ocorrComDados;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar alertas: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _marcarResolvido(Map<String, dynamic> alerta) async {
    final id = alerta['id']?.toString();
    if (id == null) return;

    setState(() {
      _processando.add(id);
      final idx = alertas.indexWhere((a) => a['id']?.toString() == id);
      if (idx != -1) alertas[idx] = {...alertas[idx], 'status': 'resolvido'};
    });

    try {
      await supabase
          .from('alerts')
          .update({'status': 'resolvido'})
          .eq('id', id);

      final occId = alerta['occurrence_id']?.toString();
      if (occId != null && occId.isNotEmpty) {
        try {
          await supabase
              .from('occurrences')
              .update({'status': 'Resolvido'})
              .eq('id', occId);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Alerta marcado como resolvido'),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Recarrega para atualizar a lista de ocorrências críticas
      _carregar();
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = alertas.indexWhere((a) => a['id']?.toString() == id);
          if (idx != -1) alertas[idx] = {...alertas[idx], 'status': 'ativo'};
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando.remove(id));
    }
  }

  Future<void> _verOcorrencia(String occId) async {
    try {
      final result = await supabase
          .from('occurrences')
          .select('*')
          .eq('id', occId)
          .maybeSingle();

      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ocorrência não encontrada')),
          );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    return alertas.where((a) {
      final status = (a['status'] ?? 'ativo').toString();
      final tipo = (a['tipo'] ?? 'info').toString();
      if (filtroStatus != 'todos' && status != filtroStatus) return false;
      if (filtroTipo != 'todos' && tipo != filtroTipo) return false;
      return true;
    }).toList();
  }

  int get _pendentes =>
      alertas.where((a) => (a['status'] ?? 'ativo') == 'ativo').length;
  int get _criticos => alertas
      .where((a) => a['tipo'] == 'error' && (a['status'] ?? 'ativo') == 'ativo')
      .length;
  int get _resolvidos =>
      alertas.where((a) => a['status'] == 'resolvido').length;

  Color _tipoColor(String? tipo) => switch (tipo) {
    'error' => AppColors.danger,
    'warning' => AppColors.warning,
    _ => AppColors.secondary,
  };

  IconData _tipoIcon(String? titulo, String? tipo) {
    final t = (titulo ?? '').toLowerCase();
    if (t.contains('óleo') || t.contains('oleo')) return Icons.opacity;
    if (t.contains('cnh')) return Icons.badge;
    if (t.contains('licen')) return Icons.assignment;
    if (t.contains('checklist')) return Icons.checklist;
    if (t.contains('seguro')) return Icons.security;
    if (t.contains('pneu')) return Icons.tire_repair;
    if (t.contains('ocorrência') || t.contains('ocorr'))
      return Icons.report_problem;
    if (t.contains('manutenção') || t.contains('manutencao'))
      return Icons.build;
    if (t.contains('document')) return Icons.description;
    if (t.contains('multa')) return Icons.gavel;
    return switch (tipo) {
      'error' => Icons.error_outline,
      'warning' => Icons.warning_amber,
      _ => Icons.info_outline,
    };
  }

  String _fmtDate(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
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
                            child: const Icon(
                              Icons.notifications_active,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Alertas da Frota',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$_pendentes pendente(s) · $_resolvidos resolvido(s) • auto-atualiza a cada 30s',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
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
                        _kpi(
                          'Total',
                          '${alertas.length}',
                          Icons.notifications,
                          AppColors.secondary,
                        ),
                        const SizedBox(width: 8),
                        _kpi(
                          'Pendentes',
                          '$_pendentes',
                          Icons.pending,
                          AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        _kpi(
                          'Críticos',
                          '$_criticos',
                          Icons.priority_high,
                          AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        _kpi(
                          'Resolvidos',
                          '$_resolvidos',
                          Icons.check_circle,
                          AppColors.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Ocorrências críticas em destaque
                    if (ocorrenciasCriticas.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: AppColors.danger,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${ocorrenciasCriticas.length} ocorrência(s) crítica(s) em aberto',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...ocorrenciasCriticas
                          .take(3)
                          .map(_buildOcorrenciaCriticaCard),
                      if (ocorrenciasCriticas.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            '+${ocorrenciasCriticas.length - 3} outras ocorrências críticas',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 8),
                    ],

                    // Filtros
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip(
                            'Todos',
                            filtroStatus,
                            'todos',
                            (v) => setState(() => filtroStatus = v),
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            'Pendentes',
                            filtroStatus,
                            'ativo',
                            (v) => setState(() => filtroStatus = v),
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            'Resolvidos',
                            filtroStatus,
                            'resolvido',
                            (v) => setState(() => filtroStatus = v),
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: 1,
                            height: 20,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 16),
                          _chip(
                            'Todos tipos',
                            filtroTipo,
                            'todos',
                            (v) => setState(() => filtroTipo = v),
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            'Crítico',
                            filtroTipo,
                            'error',
                            (v) => setState(() => filtroTipo = v),
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            'Aviso',
                            filtroTipo,
                            'warning',
                            (v) => setState(() => filtroTipo = v),
                            color: AppColors.warning,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${filtrados.length} alerta(s)',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Lista de alertas
            if (carregando)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtrados.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.notifications_off,
                        size: 64,
                        color: AppColors.textSecondary,
                      ),
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
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (local.isNotEmpty)
                    Text(
                      local,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertaCard(Map<String, dynamic> alerta) {
    final id = alerta['id']?.toString() ?? '';
    final titulo =
        alerta['title']?.toString() ?? alerta['titulo']?.toString() ?? 'Alerta';
    final descricao =
        alerta['subtitle']?.toString() ?? alerta['descricao']?.toString() ?? '';
    final tipo = alerta['tipo']?.toString() ?? 'info';
    final status = alerta['status']?.toString() ?? 'ativo';
    final resolvido = status == 'resolvido';
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
          color: resolvido
              ? AppColors.success.withOpacity(0.25)
              : cor.withOpacity(0.35),
          width: resolvido ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
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
                  resolvido ? Icons.check_circle : _tipoIcon(titulo, tipo),
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
                        color: resolvido
                            ? AppColors.textSecondary
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        decoration: resolvido
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppColors.textSecondary,
                      ),
                    ),
                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        descricao,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botão resolver
              if (resolvido)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Resolvido',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else if (processando)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.success,
                  ),
                )
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
                        border: Border.all(
                          color: AppColors.success.withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
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
              if (data.isNotEmpty) ...[
                const SizedBox(width: 6),
                _badge(data, AppColors.textSecondary),
              ],
              const Spacer(),
              if (temOcorrencia)
                GestureDetector(
                  onTap: () => _verOcorrencia(occId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.secondary.withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new,
                          color: AppColors.secondary,
                          size: 11,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Ver ocorrência',
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) {
    return Expanded(
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
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    String current,
    String value,
    ValueChanged<String> onTap, {
    Color? color,
  }) {
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
          border: Border.all(
            color: selected ? c : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

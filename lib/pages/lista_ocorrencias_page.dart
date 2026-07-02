import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth/app_auth_provider.dart';
import '../core/theme/app_theme.dart';
import 'detalhe_ocorrencia_page.dart';

class ListaOcorrenciasPage extends StatefulWidget {
  const ListaOcorrenciasPage({super.key});

  @override
  State<ListaOcorrenciasPage> createState() => _ListaOcorrenciasPageState();
}

class _ListaOcorrenciasPageState extends State<ListaOcorrenciasPage> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<Map<String, dynamic>> ocorrencias = [];
  Map<String, Map<String, dynamic>> veiculosMap = {};
  Map<String, Map<String, dynamic>> motoristasMap = {};

  bool carregando = true;
  String? erroMsg;
  String statusFiltro = 'Todos';
  String prioridadeFiltro = 'Todos';

  @override
  void initState() {
    super.initState();
    carregarTudo();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> carregarTudo() async {
    if (!mounted) return;
    setState(() {
      carregando = true;
      erroMsg = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var ocorrQ = supabase.from('occurrences').select('*');
      if (auth.isMotorista && auth.driverId != null) {
        ocorrQ = ocorrQ.eq('driver_id', auth.driverId!);
      } else if (eid != null) {
        ocorrQ = ocorrQ.eq('empresa_id', eid);
      }

      var veicQ = supabase.from('vehicles').select('id, plate, brand, model');
      var drivQ = supabase.from('drivers').select('id, name');
      if (eid != null) {
        veicQ = veicQ.eq('empresa_id', eid);
        drivQ = drivQ.eq('empresa_id', eid);
      }
      final results = await Future.wait([
        ocorrQ.order('created_at', ascending: false),
        veicQ,
        drivQ,
      ]);

      if (!mounted) return;

      final rawOcorr = List<Map<String, dynamic>>.from(
        (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final veicMap = <String, Map<String, dynamic>>{};
      for (final v in (results[1] as List)) {
        final m = Map<String, dynamic>.from(v as Map);
        final id = m['id']?.toString();
        if (id != null) veicMap[id] = m;
      }

      final motMap = <String, Map<String, dynamic>>{};
      for (final m in (results[2] as List)) {
        final row = Map<String, dynamic>.from(m as Map);
        final id = row['id']?.toString();
        if (id != null) motMap[id] = row;
      }

      setState(() {
        ocorrencias = rawOcorr;
        veiculosMap = veicMap;
        motoristasMap = motMap;
        carregando = false;
        erroMsg = null;
      });
    } catch (e) {
      debugPrint('ERRO LISTA OCORRÊNCIAS: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erroMsg = e.toString();
      });
    }
  }

  // Resolução client-side sem depender de join do Supabase
  String _placa(Map<String, dynamic> o) {
    final vid = o['vehicle_id']?.toString();
    if (vid != null && veiculosMap.containsKey(vid)) {
      return veiculosMap[vid]!['plate']?.toString() ?? '-';
    }
    return o['vehicle_plate']?.toString() ?? '-';
  }

  String _modelo(Map<String, dynamic> o) {
    final vid = o['vehicle_id']?.toString();
    if (vid != null && veiculosMap.containsKey(vid)) {
      final v = veiculosMap[vid]!;
      return '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
    }
    return '';
  }

  String _motoristaNome(Map<String, dynamic> o) {
    final mid = o['driver_id']?.toString();
    if (mid != null && motoristasMap.containsKey(mid)) {
      return motoristasMap[mid]!['name']?.toString() ?? '-';
    }
    return o['driver_name']?.toString() ?? '-';
  }

  Future<void> _avancarStatus(Map<String, dynamic> item) async {
    final atualRaw = (item['status']?.toString() ?? 'Aberto').trim();
    final atual = switch (atualRaw.toLowerCase()) {
      'aberto' => 'Aberto',
      'em andamento' || 'em_andamento' => 'Em andamento',
      'resolvido' => 'Resolvido',
      _ => 'Aberto',
    };
    final proximo = switch (atual) {
      'Aberto' => 'Em andamento',
      'Em andamento' => 'Resolvido',
      _ => 'Aberto',
    };
    try {
      await supabase
          .from('occurrences')
          .update({'status': proximo})
          .eq('id', item['id']);
      if (!mounted) return;
      setState(() {
        final idx = ocorrencias.indexWhere((o) => o['id'] == item['id']);
        if (idx >= 0) ocorrencias[idx] = {...ocorrencias[idx], 'status': proximo};
      });
      if (proximo == 'Resolvido') {
        try {
          await supabase
              .from('alerts')
              .update({'status': 'resolvido'})
              .eq('occurrence_id', item['id']);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  // Normaliza string para comparação: minúsculas + remove acentos de vogais comuns
  String _norm(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('è', 'e')
      .replaceAll('á', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('í', 'i')
      .replaceAll('ç', 'c');

  List<Map<String, dynamic>> get filtradas {
    final query = searchController.text.toLowerCase().trim();
    return ocorrencias.where((o) {
      final status = o['status']?.toString() ?? 'Aberto';
      final priority = o['priority']?.toString() ?? '';

      if (statusFiltro != 'Todos' &&
          _norm(status) != _norm(statusFiltro)) { return false; }
      if (prioridadeFiltro != 'Todos' &&
          _norm(priority) != _norm(prioridadeFiltro)) { return false; }

      if (query.isNotEmpty) {
        final searchable = [
          _motoristaNome(o),
          _placa(o),
          _modelo(o),
          o['location'] ?? '',
          o['problem_type'] ?? '',
          o['problem'] ?? '',
          status,
          priority,
        ].join(' ').toLowerCase();
        if (!searchable.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  int _count(String status) => ocorrencias
      .where((o) => _norm((o['status'] ?? 'Aberto').toString()) == _norm(status))
      .length;

  Color _statusColor(String? s) => switch ((s ?? 'Aberto').toLowerCase()) {
        'resolvido' => AppColors.success,
        'em andamento' => AppColors.secondary,
        _ => AppColors.danger,
      };

  Color _priorityColor(String? p) => switch ((p ?? '').toLowerCase()) {
        'alta' => AppColors.danger,
        'média' || 'media' => AppColors.warning,
        _ => AppColors.success,
      };

  IconData _problemIcon(String? t) => switch ((t ?? '').toLowerCase()) {
        'motor' => Icons.settings,
        'freios' => Icons.disc_full,
        'pneu' => Icons.tire_repair,
        'suspensão' || 'suspensao' => Icons.car_repair,
        'elétrica' || 'eletrica' => Icons.electric_bolt,
        'ar condicionado' => Icons.ac_unit,
        'lataria' => Icons.directions_car,
        'acidente' => Icons.car_crash,
        _ => Icons.report_problem,
      };

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Widget _chip(String label, String current, ValueChanged<String> onTap,
      {Color? activeColor}) {
    final selected = current == label;
    final color = activeColor ?? AppColors.secondary;
    return GestureDetector(
      onTap: () => onTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = filtradas;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lista de Ocorrências'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: carregarTudo,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: carregarTudo,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // KPIs
                    Row(
                      children: [
                        _kpi('Abertas', '${_count('Aberto')}', AppColors.danger),
                        const SizedBox(width: 10),
                        _kpi('Andamento', '${_count('Em andamento')}', AppColors.warning),
                        const SizedBox(width: 10),
                        _kpi('Resolvidas', '${_count('Resolvido')}', AppColors.success),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Erro visível na tela (não só snackbar)
                    if (erroMsg != null) ...[
                      _buildErroCard(),
                      const SizedBox(height: 14),
                    ],

                    // Busca
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar por motorista, veículo, local, tipo...',
                        hintStyle:
                            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textSecondary, size: 20),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    color: AppColors.textSecondary, size: 18),
                                onPressed: () {
                                  searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.secondary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Filtros de status
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Text('Status:',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(width: 8),
                          _chip('Todos', statusFiltro,
                              (v) => setState(() => statusFiltro = v)),
                          const SizedBox(width: 6),
                          _chip('Aberto', statusFiltro,
                              (v) => setState(() => statusFiltro = v),
                              activeColor: AppColors.danger),
                          const SizedBox(width: 6),
                          _chip('Em andamento', statusFiltro,
                              (v) => setState(() => statusFiltro = v),
                              activeColor: AppColors.warning),
                          const SizedBox(width: 6),
                          _chip('Resolvido', statusFiltro,
                              (v) => setState(() => statusFiltro = v),
                              activeColor: AppColors.success),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Filtros de prioridade
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Text('Prioridade:',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(width: 8),
                          _chip('Todos', prioridadeFiltro,
                              (v) => setState(() => prioridadeFiltro = v)),
                          const SizedBox(width: 6),
                          _chip('Alta', prioridadeFiltro,
                              (v) => setState(() => prioridadeFiltro = v),
                              activeColor: AppColors.danger),
                          const SizedBox(width: 6),
                          _chip('Média', prioridadeFiltro,
                              (v) => setState(() => prioridadeFiltro = v),
                              activeColor: AppColors.warning),
                          const SizedBox(width: 6),
                          _chip('Baixa', prioridadeFiltro,
                              (v) => setState(() => prioridadeFiltro = v),
                              activeColor: AppColors.success),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Text(
                          '${lista.length} de ${ocorrencias.length} ocorrência(s)',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const Spacer(),
                        if (statusFiltro != 'Todos' || prioridadeFiltro != 'Todos')
                          TextButton(
                            onPressed: () => setState(() {
                              statusFiltro = 'Todos';
                              prioridadeFiltro = 'Todos';
                            }),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Limpar filtros',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Conteúdo
            if (carregando)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (erroMsg != null && ocorrencias.isEmpty)
              const SliverFillRemaining(child: SizedBox())
            else if (lista.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        ocorrencias.isEmpty ? Icons.report_problem_outlined : Icons.search_off,
                        size: 56,
                        color: AppColors.textSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ocorrencias.isEmpty
                            ? 'Nenhuma ocorrência registrada ainda'
                            : 'Nenhuma ocorrência encontrada com os filtros atuais',
                        style: const TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      if (statusFiltro != 'Todos' || prioridadeFiltro != 'Todos') ...[
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => setState(() {
                            statusFiltro = 'Todos';
                            prioridadeFiltro = 'Todos';
                            searchController.clear();
                          }),
                          child: const Text('Limpar filtros'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildCard(lista[i]),
                    childCount: lista.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErroCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.danger, size: 18),
              SizedBox(width: 8),
              Text('Erro ao carregar ocorrências',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            erroMsg ?? '',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          const Text(
            'Verifique se as políticas RLS do Supabase estão configuradas para a tabela "occurrences".',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: carregarTudo,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> o) {
    final placa = _placa(o);
    final modelo = _modelo(o);
    final motorista = _motoristaNome(o);
    final tipo = o['problem_type']?.toString() ?? 'Ocorrência';
    final problema = o['problem']?.toString() ?? '';
    final local = o['location']?.toString() ?? '';
    final status = o['status']?.toString() ?? 'Aberto';
    final prioridade = o['priority']?.toString() ?? '-';
    final data = _fmtDate(o['created_at']?.toString());
    final resolvida = status.toLowerCase() == 'resolvido';
    final priCor = _priorityColor(prioridade);
    final stCor = _statusColor(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetalheOcorrenciaPage(
              ocorrencia: {
                ...o,
                // Injeta dados resolvidos para a página de detalhe
                'vehicle_plate_resolved': placa,
                'vehicle_model_resolved': modelo,
                'driver_name_resolved': motorista,
              },
              onStatusChanged: carregarTudo,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: resolvida ? AppColors.border : priCor.withOpacity(0.3),
              width: resolvida ? 1 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha principal
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: priCor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_problemIcon(tipo), color: priCor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tipo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        Text(
                          placa != '-'
                              ? '$placa${modelo.isNotEmpty ? ' — $modelo' : ''}'
                              : motorista,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Badge status
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: stCor.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: stCor.withOpacity(0.4)),
                    ),
                    child: Text(status,
                        style: TextStyle(
                            color: stCor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),

              // Descrição
              if (problema.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(problema,
                    style:
                        const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],

              // Badges de info
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (motorista != '-') _badge('👤 $motorista', AppColors.textSecondary),
                  if (local.isNotEmpty) _badge('📍 $local', AppColors.secondary),
                  _badge(
                    prioridade,
                    priCor,
                    icon: switch (prioridade.toLowerCase()) {
                      'alta' => Icons.priority_high,
                      'média' || 'media' => Icons.remove,
                      _ => Icons.arrow_downward,
                    },
                  ),
                  _badge(data, AppColors.textSecondary),
                ],
              ),

              // Botão avançar status
              if (!resolvida) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Indicador de progresso
                    Row(
                      children: [
                        _stepDot(true, AppColors.danger, 'Aberto'),
                        _stepLine(),
                        _stepDot(status == 'Em andamento' || status == 'Resolvido',
                            AppColors.warning, 'Andamento'),
                        _stepLine(),
                        _stepDot(status == 'Resolvido', AppColors.success, 'Resolvido'),
                      ],
                    ),
                    // Botão avançar
                    GestureDetector(
                      onTap: () => _avancarStatus(o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (status == 'Aberto' ? AppColors.warning : AppColors.success)
                              .withOpacity(0.13),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (status == 'Aberto'
                                    ? AppColors.warning
                                    : AppColors.success)
                                .withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_forward,
                                color: status == 'Aberto'
                                    ? AppColors.warning
                                    : AppColors.success,
                                size: 13),
                            const SizedBox(width: 4),
                            Text(
                              status == 'Aberto'
                                  ? 'Iniciar atendimento'
                                  : 'Marcar resolvido',
                              style: TextStyle(
                                color: status == 'Aberto'
                                    ? AppColors.warning
                                    : AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success, size: 14),
                    const SizedBox(width: 4),
                    Text('Resolvida em $data',
                        style: const TextStyle(
                            color: AppColors.success, fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepDot(bool active, Color color, String label) {
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? color : AppColors.border,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: active ? color : AppColors.textSecondary,
                fontSize: 9,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 20,
      height: 1.5,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.border,
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 10),
            const SizedBox(width: 3),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

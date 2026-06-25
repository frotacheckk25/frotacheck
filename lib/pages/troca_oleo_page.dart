import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';

class TrocaOleoPage extends StatefulWidget {
  const TrocaOleoPage({super.key});

  @override
  State<TrocaOleoPage> createState() => _TrocaOleoPageState();
}

class _TrocaOleoPageState extends State<TrocaOleoPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final kmController = TextEditingController();
  final observacoesController = TextEditingController();

  List<Map<String, dynamic>> veiculos = [];
  List<Map<String, dynamic>> historico = [];

  bool carregando = true;
  bool isSaving = false;

  String? selectedVehicleId;
  String? selectedServiceType;
  String selectedInterval = '10000';
  DateTime? dataTroca;

  final List<String> tiposServico = [
    'Troca de óleo',
    'Filtro de óleo',
    'Revisão geral',
    'Inspeção preventiva',
    'Troca de filtro de ar',
    'Manutenção preventiva',
  ];

  final List<Map<String, String>> intervalOptions = [
    {'value': '5000', 'label': '5.000 km'},
    {'value': '8000', 'label': '8.000 km'},
    {'value': '10000', 'label': '10.000 km'},
    {'value': '12000', 'label': '12.000 km'},
    {'value': '15000', 'label': '15.000 km'},
    {'value': '20000', 'label': '20.000 km'},
  ];

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  @override
  void dispose() {
    kmController.dispose();
    observacoesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> carregarDados() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      final results = await Future.wait([
        supabase.from('vehicles').select('id, plate, brand, model, odometer').order('plate'),
        supabase
            .from('oil_changes')
            .select('*, vehicles(plate, model)')
            .order('created_at', ascending: false)
            .limit(100),
      ]);

      if (!mounted) return;
      setState(() {
        veiculos = List<Map<String, dynamic>>.from(
          (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        historico = List<Map<String, dynamic>>.from(
          (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  void _onVeiculoChanged(String? id) {
    if (id == null) return;
    final v = veiculos.firstWhere(
      (v) => v['id']?.toString() == id,
      orElse: () => {},
    );
    setState(() {
      selectedVehicleId = id;
      final km = v['odometer'];
      if (km != null) kmController.text = km.toString();
    });
  }

  Future<void> _pickData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dataTroca ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Data da troca',
    );
    if (d != null) setState(() => dataTroca = d);
  }

  Future<void> salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (dataTroca == null) {
      _snackErro('Selecione a data da troca');
      return;
    }

    setState(() => isSaving = true);

    final kmAtual = int.tryParse(kmController.text.trim()) ?? 0;
    final intervalo = int.tryParse(selectedInterval) ?? 10000;
    final proximoKm = kmAtual + intervalo;

    final veiculo = veiculos.firstWhere(
      (v) => v['id']?.toString() == selectedVehicleId,
      orElse: () => {},
    );
    final placa = veiculo['plate']?.toString() ?? '';

    try {
      final payload = <String, dynamic>{
        'vehicle_id': selectedVehicleId,
        'current_km': kmAtual,
        'service_type': selectedServiceType,
        'oil_change_date': dataTroca!.toIso8601String().split('T')[0],
        'next_change_km': proximoKm,
      };
      if (observacoesController.text.trim().isNotEmpty) {
        payload['notes'] = observacoesController.text.trim();
      }

      final result = await supabase.from('oil_changes').insert(payload).select('*, vehicles(plate, model)');

      if (!mounted) return;

      // Atualiza histórico imediatamente
      if (result.isNotEmpty) {
        final novo = Map<String, dynamic>.from(result.first as Map);
        setState(() => historico = [novo, ...historico]);
      }

      // Cria alerta de próxima troca (silencioso se falhar)
      try {
        await supabase.from('alerts').insert({
          'title': 'Próxima Troca de Óleo: $placa',
          'subtitle': '$selectedServiceType — próxima em $proximoKm km',
          'tipo': 'warning',
          'status': 'ativo',
        });
      } catch (_) {}

      _snackSucesso('Troca registrada! Próxima em $proximoKm km');
      _limparFormulario();
    } catch (e) {
      if (!mounted) return;
      _snackErro('Erro ao salvar: $e');
      debugPrint('ERRO TROCA DE ÓLEO: $e');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _limparFormulario() {
    kmController.clear();
    observacoesController.clear();
    _formKey.currentState?.reset();
    setState(() {
      selectedVehicleId = null;
      selectedServiceType = null;
      selectedInterval = '10000';
      dataTroca = null;
    });
  }

  void _snackSucesso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _snackErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _fmtDatetime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color _serviceColor(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('óleo') || t.contains('oleo')) return AppColors.warning;
    if (t.contains('revisão') || t.contains('revisao')) return AppColors.secondary;
    if (t.contains('filtro')) return const Color(0xFF8B5CF6);
    return AppColors.success;
  }

  IconData _serviceIcon(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('óleo') || t.contains('oleo')) return Icons.opacity;
    if (t.contains('filtro')) return Icons.filter_alt;
    if (t.contains('revisão') || t.contains('revisao')) return Icons.build;
    return Icons.check_circle;
  }

  int get _proximoKmPreview {
    final km = int.tryParse(kmController.text) ?? 0;
    return km + (int.tryParse(selectedInterval) ?? 10000);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Troca de Óleo'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: carregarDados,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildStats(),
                const SizedBox(height: 20),
                if (isWide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 420, child: _buildForm()),
                        const SizedBox(width: 20),
                        Expanded(child: _buildHistorico()),
                      ],
                    ),
                  )
                else ...[
                  _buildForm(),
                  const SizedBox(height: 20),
                  _buildHistorico(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
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
            child: const Icon(Icons.opacity, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Troca de Óleo e Manutenções',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${historico.length} registro(s) • ${veiculos.length} veículo(s) disponível(eis)',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        _statCard('Registros', '${historico.length}', Icons.history, AppColors.secondary),
        const SizedBox(width: 12),
        _statCard('Veículos', '${veiculos.length}', Icons.directions_car, AppColors.success),
        const SizedBox(width: 12),
        _statCard('Este mês', _countThisMonth().toString(), Icons.calendar_today, AppColors.warning),
      ],
    );
  }

  int _countThisMonth() {
    final now = DateTime.now();
    return historico.where((h) {
      final raw = h['oil_change_date']?.toString() ?? h['created_at']?.toString() ?? '';
      final dt = DateTime.tryParse(raw);
      return dt != null && dt.month == now.month && dt.year == now.year;
    }).length;
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w600)),
                Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      elevation: 4,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: AppColors.secondary, size: 22),
                  SizedBox(width: 8),
                  Text('Registrar Troca / Manutenção',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 18),

              // Veículo — carrega lista diretamente
              if (carregando)
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else if (veiculos.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: AppColors.warning, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nenhum veículo cadastrado. Cadastre um veículo primeiro.',
                          style: TextStyle(color: AppColors.warning, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: selectedVehicleId,
                  decoration: _dec('Veículo *', Icons.directions_car_outlined),
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white),
                  isExpanded: true,
                  hint: const Text('Selecione o veículo', style: TextStyle(color: AppColors.textSecondary)),
                  items: veiculos.map((v) {
                    final placa = v['plate'] ?? '--';
                    final modelo = v['model'] ?? '';
                    final marca = v['brand'] ?? '';
                    return DropdownMenuItem<String>(
                      value: v['id']?.toString(),
                      child: Text(
                        '$placa — $marca $modelo'.trim(),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  validator: (v) => v == null ? 'Selecione um veículo' : null,
                  onChanged: _onVeiculoChanged,
                ),
              const SizedBox(height: 12),

              // KM Atual
              TextFormField(
                controller: kmController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: _dec('KM Atual do Veículo *', Icons.speed_outlined),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o KM atual';
                  if (int.tryParse(v.trim()) == null) return 'Somente números';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Tipo de serviço
              DropdownButtonFormField<String>(
                value: selectedServiceType,
                decoration: _dec('Tipo de serviço *', Icons.build_outlined),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                hint: const Text('Selecione o tipo', style: TextStyle(color: AppColors.textSecondary)),
                items: tiposServico.map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(t, style: const TextStyle(color: Colors.white)),
                )).toList(),
                validator: (v) => v == null ? 'Selecione o tipo de serviço' : null,
                onChanged: (v) => setState(() {
                  selectedServiceType = v;
                  selectedInterval = switch (v) {
                    'Troca de óleo' => '10000',
                    'Filtro de óleo' => '12000',
                    'Revisão geral' => '15000',
                    'Inspeção preventiva' => '8000',
                    _ => '10000',
                  };
                }),
              ),
              const SizedBox(height: 12),

              // Intervalo próxima troca
              DropdownButtonFormField<String>(
                value: selectedInterval,
                decoration: _dec('Intervalo próxima troca *', Icons.replay_outlined),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                items: intervalOptions.map((o) => DropdownMenuItem(
                  value: o['value'],
                  child: Text(o['label']!, style: const TextStyle(color: Colors.white)),
                )).toList(),
                onChanged: (v) { if (v != null) setState(() => selectedInterval = v); },
              ),
              const SizedBox(height: 12),

              // Preview: próximo km calculado
              if (kmController.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Próxima troca em $_proximoKmPreview km',
                        style: const TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Data da troca
              GestureDetector(
                onTap: _pickData,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: dataTroca == null ? AppColors.border : AppColors.success.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: dataTroca == null ? AppColors.textSecondary : AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dataTroca != null
                              ? 'Data da troca: ${_fmtDatetime(dataTroca!)}'
                              : 'Data da troca *  (toque para selecionar)',
                          style: TextStyle(
                            color: dataTroca != null ? Colors.white : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit_calendar, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Observações
              TextFormField(
                controller: observacoesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _dec('Observações (opcional)', Icons.notes_outlined),
              ),
              const SizedBox(height: 24),

              // Botão salvar
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : salvar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.save_alt_rounded, size: 20),
                  label: Text(
                    isSaving ? 'Salvando...' : 'SALVAR TROCA DE ÓLEO',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _limparFormulario,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Limpar campos'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistorico() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Histórico de Trocas',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Text('${historico.length} registro(s)',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        if (carregando)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (historico.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(Icons.opacity, size: 48, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('Nenhuma troca registrada ainda',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: historico.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildHistoricoCard(historico[i]),
          ),
      ],
    );
  }

  Widget _buildHistoricoCard(Map<String, dynamic> item) {
    final placa = item['vehicles']?['plate'] ?? item['vehicle_plate'] ?? '-';
    final modelo = item['vehicles']?['model'] ?? '';
    final tipo = item['service_type'] ?? 'Serviço';
    final data = _fmtDate(item['oil_change_date']?.toString() ?? item['created_at']?.toString());
    final kmAtual = item['current_km'];
    final proximoKm = item['next_change_km'];
    final notas = item['notes']?.toString() ?? '';
    final cor = _serviceColor(tipo);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_serviceIcon(tipo), color: cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(placa,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    if (modelo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('— $modelo',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(tipo, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _badge(data, AppColors.textSecondary),
                    if (kmAtual != null) _badge('$kmAtual km', AppColors.secondary),
                    if (proximoKm != null) _badge('Próx. $proximoKm km', AppColors.warning),
                  ],
                ),
                if (notas.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(notas,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
    filled: true,
    fillColor: AppColors.backgroundSoft,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.secondary)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.danger)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );
}

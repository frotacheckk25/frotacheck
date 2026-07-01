import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth/app_auth_provider.dart';
import '../core/theme/app_theme.dart';

class OcorrenciasPage extends StatefulWidget {
  const OcorrenciasPage({super.key});

  @override
  State<OcorrenciasPage> createState() => _OcorrenciasPageState();
}

class _OcorrenciasPageState extends State<OcorrenciasPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final descricaoController = TextEditingController();
  final locationController = TextEditingController();

  List<Map<String, dynamic>> ocorrencias = [];
  List<Map<String, dynamic>> veiculos = [];
  List<Map<String, dynamic>> motoristas = [];
  Map<String, Map<String, dynamic>> veiculosMap = {};
  Map<String, Map<String, dynamic>> motoristasMap = {};

  bool carregando = true;
  bool isSaving = false;

  String? selectedVehicleId;
  String? selectedDriverId;
  String? selectedProblem;
  String? selectedPriority;
  String selectedStatus = 'Aberto';

  final List<String> problemTypes = [
    'Motor',
    'Freios',
    'Pneu',
    'Suspensão',
    'Elétrica',
    'Ar Condicionado',
    'Lataria',
    'Acidente',
    'Outro',
  ];

  final List<String> priorities = ['Alta', 'Média', 'Baixa'];
  final List<String> statuses = ['Aberto', 'Em andamento', 'Resolvido'];

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  @override
  void dispose() {
    descricaoController.dispose();
    locationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> carregarDados() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var ocorrQ = supabase.from('occurrences').select('*');
      if (auth.isMotorista && auth.driverId != null) {
        ocorrQ = ocorrQ.eq('driver_id', auth.driverId!);
      } else if (eid != null) {
        ocorrQ = ocorrQ.eq('empresa_id', eid);
      }

      // Sem filtro Dart: RLS retorna apenas veículos/motoristas acessíveis.
      var veicQ = supabase.from('vehicles').select('id, plate, brand, model');
      var drivQ = supabase.from('drivers').select('id, name');
      final results = await Future.wait([
        ocorrQ.order('created_at', ascending: false).limit(100),
        veicQ.order('plate'),
        drivQ.order('name'),
      ]);
      if (!mounted) return;
      final vList = List<Map<String, dynamic>>.from(
        (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final mList = List<Map<String, dynamic>>.from(
        (results[2] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final vMap = <String, Map<String, dynamic>>{};
      final mMap = <String, Map<String, dynamic>>{};
      for (final v in vList) { vMap[v['id'].toString()] = v; }
      for (final m in mList) { mMap[m['id'].toString()] = m; }
      setState(() {
        ocorrencias = List<Map<String, dynamic>>.from(
          (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        veiculos = vList;
        motoristas = mList;
        veiculosMap = vMap;
        motoristasMap = mMap;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar ocorrências: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => isSaving = true);
    final injetar = context.read<AppAuthProvider>().inject;

    // Monta payload apenas com colunas que existem na tabela occurrences
    final payload = <String, dynamic>{
      'problem_type': selectedProblem,
      'problem': descricaoController.text.trim(),
      'priority': selectedPriority,
      'location': locationController.text.trim(),
      'status': selectedStatus,
    };
    if (selectedVehicleId != null) payload['vehicle_id'] = selectedVehicleId;
    if (selectedDriverId != null) payload['driver_id'] = selectedDriverId;

    // Resolve info do veículo/motorista a partir da memória (antes do insert)
    final veiculo = veiculos.firstWhere(
      (v) => v['id']?.toString() == selectedVehicleId,
      orElse: () => {},
    );
    final motorista = motoristas.firstWhere(
      (m) => m['id']?.toString() == selectedDriverId,
      orElse: () => {},
    );

    try {
      final result = await supabase
          .from('occurrences')
          .insert(injetar(payload))
          .select();

      if (!mounted) return;

      Map<String, dynamic>? novaOcorrencia;
      if (result.isNotEmpty) {
        novaOcorrencia = Map<String, dynamic>.from(result.first as Map);
        // Enriquece com dados já em memória para não depender de FK join
        novaOcorrencia['vehicles'] = {'plate': veiculo['plate'], 'model': veiculo['model']};
        novaOcorrencia['drivers']  = {'name': motorista['name']};
        setState(() => ocorrencias = [novaOcorrencia!, ...ocorrencias]);
      }
      _snackSucesso('Ocorrência registrada!');
      _limparFormulario();
    } catch (e) {
      if (!mounted) return;
      _snackErro('Erro ao registrar: $e');
      debugPrint('ERRO OCORRÊNCIA: $e');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _deletar(String id) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir ocorrência', style: TextStyle(color: Colors.white)),
        content: const Text('Excluir esta ocorrência permanentemente?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (!mounted || conf != true) return;
    try {
      await supabase.from('occurrences').delete().eq('id', id);
      if (mounted) setState(() => ocorrencias.removeWhere((o) => o['id']?.toString() == id));
      if (mounted) _snackSucesso('Ocorrência excluída');
    } catch (e) {
      if (mounted) _snackErro('Erro ao excluir: $e');
    }
  }

  Future<void> _resolver(String id) async {
    try {
      await supabase.from('occurrences').update({'status': 'Resolvido'}).eq('id', id);
      if (!mounted) return;
      setState(() {
        final idx = ocorrencias.indexWhere((o) => o['id']?.toString() == id);
        if (idx >= 0) ocorrencias[idx] = {...ocorrencias[idx], 'status': 'Resolvido'};
      });
      // Tenta resolver alerta vinculado (silencioso)
      try {
        await supabase.from('alerts').update({'status': 'resolvido'}).eq('occurrence_id', id);
      } catch (_) {}
    } catch (e) {
      if (mounted) _snackErro('Erro ao resolver: $e');
    }
  }

  void _limparFormulario() {
    descricaoController.clear();
    locationController.clear();
    _formKey.currentState?.reset();
    setState(() {
      selectedVehicleId = null;
      selectedDriverId = null;
      selectedProblem = null;
      selectedPriority = null;
      selectedStatus = 'Aberto';
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

  Color _priorityColor(String? p) => switch ((p ?? '').toLowerCase()) {
        'alta' => AppColors.danger,
        'média' || 'media' => AppColors.warning,
        _ => AppColors.success,
      };

  Color _statusColor(String? s) => switch ((s ?? '').toLowerCase()) {
        'resolvido' => AppColors.success,
        'em andamento' => AppColors.secondary,
        _ => AppColors.warning,
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

  int get _abertas =>
      ocorrencias.where((o) => (o['status'] ?? '').toString().toLowerCase() != 'resolvido').length;
  int get _altas => ocorrencias
      .where((o) =>
          (o['priority'] ?? '').toString().toLowerCase() == 'alta' &&
          (o['status'] ?? '').toString().toLowerCase() != 'resolvido')
      .length;
  int get _resolvidas =>
      ocorrencias.where((o) => (o['status'] ?? '').toString().toLowerCase() == 'resolvido').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Registro de Ocorrências'),
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
                        Expanded(child: _buildLista()),
                      ],
                    ),
                  )
                else ...[
                  _buildForm(),
                  const SizedBox(height: 20),
                  _buildLista(),
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
          colors: [Color(0xFFef4444), Color(0xFFf97316)],
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
            child: const Icon(Icons.report_problem, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Registro de Ocorrências',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${ocorrencias.length} registro(s) • $_abertas em aberto',
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
        _statCard('Em Aberto', '$_abertas', Icons.pending_outlined, AppColors.warning),
        const SizedBox(width: 12),
        _statCard('Alta Prioridade', '$_altas', Icons.priority_high, AppColors.danger),
        const SizedBox(width: 12),
        _statCard('Resolvidas', '$_resolvidas', Icons.check_circle_outline, AppColors.success),
      ],
    );
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
                  Icon(Icons.add_alert, color: AppColors.danger, size: 22),
                  SizedBox(width: 8),
                  Text('Nova Ocorrência',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 18),

              // Veículo
              if (carregando)
                _loadingField()
              else
                _dropdown(
                  label: 'Veículo *',
                  icon: Icons.directions_car_outlined,
                  value: selectedVehicleId,
                  hint: veiculos.isEmpty ? 'Nenhum veículo cadastrado' : 'Selecione o veículo',
                  items: veiculos.map((v) {
                    final txt = '${v['plate'] ?? '--'} — ${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
                    return DropdownMenuItem(value: v['id']?.toString(), child: Text(txt, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  validator: (v) => v == null ? 'Selecione um veículo' : null,
                  onChanged: (v) => setState(() => selectedVehicleId = v),
                ),
              const SizedBox(height: 12),

              // Motorista
              if (carregando)
                _loadingField()
              else
                _dropdown(
                  label: 'Motorista',
                  icon: Icons.person_outline,
                  value: selectedDriverId,
                  hint: motoristas.isEmpty ? 'Nenhum motorista cadastrado' : 'Selecione o motorista (opcional)',
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sem motorista')),
                    ...motoristas.map((m) => DropdownMenuItem(
                          value: m['id']?.toString(),
                          child: Text(m['name']?.toString() ?? ''),
                        )),
                  ],
                  onChanged: (v) => setState(() => selectedDriverId = v),
                ),
              const SizedBox(height: 12),

              // Tipo de problema
              _dropdown(
                label: 'Tipo de problema *',
                icon: Icons.build_outlined,
                value: selectedProblem,
                hint: 'Selecione o tipo',
                items: problemTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                validator: (v) => v == null ? 'Selecione o tipo de problema' : null,
                onChanged: (v) => setState(() => selectedProblem = v),
              ),
              const SizedBox(height: 12),

              // Prioridade
              _dropdown(
                label: 'Prioridade *',
                icon: Icons.flag_outlined,
                value: selectedPriority,
                hint: 'Selecione a prioridade',
                items: priorities.map((p) {
                  final cor = _priorityColor(p);
                  return DropdownMenuItem(
                    value: p,
                    child: Row(children: [
                      Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
                      Text(p),
                    ]),
                  );
                }).toList(),
                validator: (v) => v == null ? 'Selecione a prioridade' : null,
                onChanged: (v) => setState(() => selectedPriority = v),
              ),
              const SizedBox(height: 12),

              // Status
              _dropdown(
                label: 'Status',
                icon: Icons.info_outline,
                value: selectedStatus,
                items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) { if (v != null) setState(() => selectedStatus = v); },
              ),
              const SizedBox(height: 12),

              // Localização
              _campo(
                controller: locationController,
                label: 'Localização *',
                icon: Icons.location_on_outlined,
                hint: 'Ex: Rodovia BR-101, Km 45',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a localização' : null,
              ),
              const SizedBox(height: 12),

              // Descrição
              TextFormField(
                controller: descricaoController,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Descrição da ocorrência *',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 56),
                    child: Icon(Icons.notes_outlined, size: 20, color: AppColors.textSecondary),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.danger)),
                  filled: true,
                  fillColor: AppColors.backgroundSoft,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Descreva a ocorrência' : null,
              ),
              const SizedBox(height: 16),

              // Banner: alerta automático
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.notifications_active, color: AppColors.warning, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Um alerta será gerado automaticamente no painel de alertas.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Botão salvar
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : salvar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  icon: isSaving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.report_problem, size: 20),
                  label: Text(
                    isSaving ? 'Registrando...' : 'REGISTRAR OCORRÊNCIA',
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

  Widget _loadingField() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.backgroundSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required dynamic value,
    String? hint,
    required List<DropdownMenuItem> items,
    String? Function(dynamic)? validator,
    required void Function(dynamic) onChanged,
  }) {
    return DropdownButtonFormField(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.danger)),
        filled: true,
        fillColor: AppColors.backgroundSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      dropdownColor: AppColors.surface,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      isExpanded: true,
      hint: hint != null ? Text(hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)) : null,
      items: items,
      validator: validator,
      onChanged: onChanged,
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.danger)),
        filled: true,
        fillColor: AppColors.backgroundSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      validator: validator,
    );
  }

  Widget _buildLista() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Histórico de Ocorrências',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Text('${ocorrencias.length} registro(s)',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        if (carregando)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (ocorrencias.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              children: [
                Icon(Icons.report_problem_outlined, size: 48, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('Nenhuma ocorrência registrada',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ocorrencias.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildCard(ocorrencias[i]),
          ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> o) {
    final vid = o['vehicle_id']?.toString() ?? '';
    final did = o['driver_id']?.toString() ?? '';
    final placa = veiculosMap[vid]?['plate']?.toString() ?? '-';
    final modelo = veiculosMap[vid]?['model']?.toString() ?? '';
    final motorista = motoristasMap[did]?['name']?.toString() ?? '-';
    final tipo = o['problem_type']?.toString() ?? 'Ocorrência';
    final problema = o['problem']?.toString() ?? '';
    final prioridade = o['priority']?.toString() ?? '-';
    final status = o['status']?.toString() ?? 'Aberto';
    final local = o['location']?.toString() ?? '';
    final data = _fmtDate(o['created_at']?.toString());
    final id = o['id']?.toString() ?? '';
    final resolvida = status.toLowerCase() == 'resolvido';
    final priCor = _priorityColor(prioridade);
    final stCor = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: resolvida ? AppColors.border : priCor.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(
                      placa == '-' ? motorista : '$placa${modelo.isNotEmpty ? ' — $modelo' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stCor.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status,
                    style: TextStyle(color: stCor, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (problema.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(problema,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _badge(motorista, AppColors.textSecondary),
              _badge(prioridade, priCor),
              if (local.isNotEmpty) _badge(local, AppColors.secondary),
              _badge(data, AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!resolvida)
                TextButton.icon(
                  onPressed: id.isNotEmpty ? () => _resolver(id) : null,
                  icon: const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                  label: const Text('Marcar resolvido',
                      style: TextStyle(color: AppColors.success, fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                tooltip: 'Excluir',
                onPressed: id.isNotEmpty ? () => _deletar(id) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
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
}

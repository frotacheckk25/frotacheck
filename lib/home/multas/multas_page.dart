import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class MultasPage extends StatefulWidget {
  const MultasPage({super.key});

  @override
  State<MultasPage> createState() => _MultasPageState();
}

class _MultasPageState extends State<MultasPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> multas = [];
  Map<String, Map<String, dynamic>> veiculosMap = {};
  Map<String, Map<String, dynamic>> motoristasMap = {};
  bool carregando = true;
  String filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      // Queries separadas — sem FK join
      final results = await Future.wait([
        supabase.from('multas').select('*').order('created_at', ascending: false),
        supabase.from('vehicles').select('id, plate, brand, model').order('plate'),
        supabase.from('drivers').select('id, name').order('name'),
      ]);

      final rawMultas = List<Map<String, dynamic>>.from(
        (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final vMap = <String, Map<String, dynamic>>{};
      for (final v in (results[1] as List)) {
        final row = Map<String, dynamic>.from(v as Map);
        vMap[row['id'].toString()] = row;
      }
      final mMap = <String, Map<String, dynamic>>{};
      for (final m in (results[2] as List)) {
        final row = Map<String, dynamic>.from(m as Map);
        mMap[row['id'].toString()] = row;
      }

      if (!mounted) return;
      setState(() {
        multas = rawMultas;
        veiculosMap = vMap;
        motoristasMap = mMap;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar multas: $e');
      if (!mounted) return;
      setState(() => carregando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
    }
  }

  void _abrirNovaMulta() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NovaMultaForm(
        onSaved: () {
          Navigator.pop(ctx);
          _carregarDados();
        },
      ),
    );
  }

  void _abrirDetalhe(Map<String, dynamic> multa) {
    final vid = multa['vehicle_id']?.toString() ?? multa['veiculo_id']?.toString();
    final mid = multa['driver_id']?.toString() ?? multa['motorista_id']?.toString();
    final veiculo = vid != null ? veiculosMap[vid] : null;
    final motorista = mid != null ? motoristasMap[mid] : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalheMultaPage(
          multa: {
            ...multa,
            '_veiculo_label': _veiculoLabel(multa),
            '_motorista_label': _motoristaLabel(multa),
            '_veiculo': veiculo,
            '_motorista': motorista,
          },
          onAtualizada: _carregarDados,
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _veiculoLabel(Map<String, dynamic> m) {
    final vid = m['vehicle_id']?.toString() ?? m['veiculo_id']?.toString();
    if (vid != null && veiculosMap.containsKey(vid)) {
      final v = veiculosMap[vid]!;
      final plate = v['plate']?.toString() ?? '';
      final brand = v['brand']?.toString() ?? '';
      final model = v['model']?.toString() ?? '';
      final desc = '$brand $model'.trim();
      return desc.isNotEmpty ? '$plate — $desc' : plate;
    }
    return '-';
  }

  String _motoristaLabel(Map<String, dynamic> m) {
    final mid = m['driver_id']?.toString() ?? m['motorista_id']?.toString();
    if (mid != null && motoristasMap.containsKey(mid)) {
      return motoristasMap[mid]!['name']?.toString() ?? '-';
    }
    return '-';
  }

  List<Map<String, dynamic>> get _filtradas {
    if (filtro == 'todos') return multas;
    return multas.where((m) => (m['status'] ?? 'aberta').toString() == filtro).toList();
  }

  int _count(String status) =>
      multas.where((m) => (m['status'] ?? 'aberta').toString() == status).length;

  double _totalAberto() => multas
      .where((m) => (m['status'] ?? 'aberta') == 'aberta')
      .fold(0.0, (sum, m) {
    final v = m['valor'];
    return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0);
  });

  Color _statusColor(String? s) => switch ((s ?? 'aberta').toLowerCase()) {
        'paga' => AppColors.success,
        'contestada' => const Color(0xFF8B5CF6),
        _ => AppColors.warning,
      };

  String _statusLabel(String? s) => switch ((s ?? 'aberta').toLowerCase()) {
        'paga' => 'Paga',
        'contestada' => 'Contestada',
        _ => 'Aberta',
      };

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _fmtValue(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
    return 'R\$ ${d.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtradas;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestão de Multas'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            color: AppColors.secondary,
            onPressed: _abrirNovaMulta,
            tooltip: 'Nova Multa',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovaMulta,
        backgroundColor: AppColors.danger,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nova Multa', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarDados,
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
                      padding: const EdgeInsets.all(18),
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
                            child: const Icon(Icons.gavel, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Gestão de Multas',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(
                                  '${_count('aberta')} aberta(s) · ${_fmtValue(_totalAberto())} a pagar',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                        _kpi('Total', '${multas.length}', Icons.receipt_long, AppColors.secondary),
                        const SizedBox(width: 8),
                        _kpi('Abertas', '${_count('aberta')}', Icons.pending, AppColors.warning),
                        const SizedBox(width: 8),
                        _kpi('Pagas', '${_count('paga')}', Icons.check_circle, AppColors.success),
                        const SizedBox(width: 8),
                        _kpi('Contest.', '${_count('contestada')}', Icons.balance,
                            const Color(0xFF8B5CF6)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filtros
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip('Todas', 'todos'),
                          const SizedBox(width: 8),
                          _chip('Abertas', 'aberta', color: AppColors.warning),
                          const SizedBox(width: 8),
                          _chip('Pagas', 'paga', color: AppColors.success),
                          const SizedBox(width: 8),
                          _chip('Contestadas', 'contestada', color: const Color(0xFF8B5CF6)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${filtradas.length} multa(s)',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            if (carregando)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (filtradas.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long, size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        multas.isEmpty ? 'Nenhuma multa registrada' : 'Nenhuma multa neste filtro',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _abrirNovaMulta,
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar Multa'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final m = filtradas[i];
                      final status = m['status']?.toString() ?? 'aberta';
                      final cor = _statusColor(status);
                      final veiculo = _veiculoLabel(m);
                      final motorista = _motoristaLabel(m);
                      final valor = m['valor'];
                      final tipo = m['tipo']?.toString() ?? '-';
                      final descricao = m['descricao']?.toString() ?? '';
                      final data = _fmtDate(m['data']?.toString() ?? m['created_at']?.toString());
                      final paga = status == 'paga';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => _abrirDetalhe(m),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cor.withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: cor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.gavel, color: cor, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(veiculo,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14)),
                                          Text(tipo,
                                              style: const TextStyle(
                                                  color: AppColors.textSecondary, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(_fmtValue(valor),
                                            style: TextStyle(
                                                color: paga ? AppColors.success : AppColors.danger,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: cor.withOpacity(0.13),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(_statusLabel(status),
                                              style: TextStyle(
                                                  color: cor,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (descricao.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(descricao,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    if (motorista != '-')
                                      _badge('👤 $motorista', AppColors.textSecondary),
                                    _badge(data, AppColors.textSecondary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: filtradas.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
              Icon(icon, color: color, size: 15),
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

  Widget _chip(String label, String value, {Color? color}) {
    final selected = filtro == value;
    final c = color ?? AppColors.secondary;
    return GestureDetector(
      onTap: () => setState(() => filtro = value),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      );
}

// ─── Formulário — carrega veículos e motoristas internamente ──────────────────

class _NovaMultaForm extends StatefulWidget {
  final VoidCallback onSaved;
  const _NovaMultaForm({required this.onSaved});

  @override
  State<_NovaMultaForm> createState() => _NovaMultaFormState();
}

class _NovaMultaFormState extends State<_NovaMultaForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final imagePicker = ImagePicker();

  List<Map<String, dynamic>> veiculos = [];
  List<Map<String, dynamic>> motoristas = [];
  bool carregandoDados = true;
  bool isSaving = false;

  String? selectedVehicle;
  String? selectedDriver;
  String? selectedTipo;
  DateTime? dataMulta;
  Uint8List? fotoBytes;

  final valorController = TextEditingController();
  final descricaoController = TextEditingController();

  static const tipos = [
    {'value': 'Infração de Trânsito', 'label': 'Infração de Trânsito'},
    {'value': 'Estacionamento Proibido', 'label': 'Estacionamento Proibido'},
    {'value': 'Excesso de Velocidade', 'label': 'Excesso de Velocidade'},
    {'value': 'Avanço de Sinal', 'label': 'Avanço de Sinal'},
    {'value': 'Documentação Irregular', 'label': 'Documentação Irregular'},
    {'value': 'Outros', 'label': 'Outros'},
  ];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    valorController.dispose();
    descricaoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() => carregandoDados = true);
    try {
      final results = await Future.wait([
        supabase.from('vehicles').select('id, plate, brand, model').order('plate'),
        supabase.from('drivers').select('id, name').order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        veiculos = List<Map<String, dynamic>>.from(
          (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        motoristas = List<Map<String, dynamic>>.from(
          (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        carregandoDados = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => carregandoDados = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
    }
  }

  String _veiculoLabel(Map<String, dynamic> v) {
    final plate = v['plate']?.toString() ?? '';
    final brand = v['brand']?.toString() ?? '';
    final model = v['model']?.toString() ?? '';
    final desc = '$brand $model'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      helpText: 'Data da multa',
    );
    if (d != null) setState(() => dataMulta = d);
  }

  Future<void> _pickFoto() async {
    try {
      XFile? img;
      try {
        img = await imagePicker.pickImage(
            source: ImageSource.camera, imageQuality: 70, maxWidth: 1000);
      } catch (_) {
        img = await imagePicker.pickImage(
            source: ImageSource.gallery, imageQuality: 70, maxWidth: 1000);
      }
      if (img != null) {
        final bytes = await img.readAsBytes();
        if (mounted) setState(() => fotoBytes = bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao selecionar foto: $e')));
      }
    }
  }

  Future<void> _salvar() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => isSaving = true);
    try {
      // Upload foto (silencioso se bucket não existir)
      String? fotoUrl;
      if (fotoBytes != null) {
        try {
          final fileName = 'multa_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await supabase.storage.from('multas').uploadBinary(
                fileName,
                fotoBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
          fotoUrl = supabase.storage.from('multas').getPublicUrl(fileName);
        } catch (_) {}
      }

      final payload = <String, dynamic>{
        'vehicle_id': selectedVehicle,
        'tipo': selectedTipo,
        'valor': double.tryParse(valorController.text.trim().replaceAll(',', '.')) ?? 0,
        'descricao': descricaoController.text.trim(),
        'status': 'aberta',
        'data': (dataMulta ?? DateTime.now()).toIso8601String().split('T')[0],
        if (selectedDriver != null) 'driver_id': selectedDriver,
        if (fotoUrl case final url?) 'foto_url': url,
      };

      await supabase.from('multas').insert(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Multa registrada com sucesso!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.gavel, color: AppColors.danger, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Registrar Multa',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Veículo ──────────────────────────────────────────────────
              if (carregandoDados)
                _loadingField('Carregando veículos e motoristas...')
              else ...[
                if (veiculos.isEmpty)
                  _avisoSemDados('Nenhum veículo cadastrado', Icons.directions_car_outlined)
                else
                  DropdownButtonFormField<String>(
                    value: selectedVehicle,
                    decoration: _dec('Veículo *', Icons.directions_car_outlined),
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    isExpanded: true,
                    hint: const Text('Selecione o veículo',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    items: veiculos
                        .map((v) => DropdownMenuItem<String>(
                              value: v['id']?.toString(),
                              child: Text(_veiculoLabel(v),
                                  style: const TextStyle(color: Colors.white),
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    validator: (v) => v == null ? 'Selecione um veículo' : null,
                    onChanged: (v) => setState(() => selectedVehicle = v),
                  ),
                const SizedBox(height: 14),

                // ── Motorista ──────────────────────────────────────────────
                if (motoristas.isEmpty)
                  _avisoSemDados('Nenhum motorista cadastrado (opcional)', Icons.person_outline)
                else
                  DropdownButtonFormField<String>(
                    value: selectedDriver,
                    decoration: _dec('Motorista (opcional)', Icons.person_outline),
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    isExpanded: true,
                    hint: const Text('Selecione o motorista',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Sem motorista',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      ...motoristas.map((m) => DropdownMenuItem<String>(
                            value: m['id']?.toString(),
                            child: Text(m['name']?.toString() ?? '-',
                                style: const TextStyle(color: Colors.white)),
                          )),
                    ],
                    onChanged: (v) => setState(() => selectedDriver = v),
                  ),
                const SizedBox(height: 14),
              ],

              // ── Tipo ──────────────────────────────────────────────────────
              DropdownButtonFormField<String>(
                value: selectedTipo,
                decoration: _dec('Tipo de Infração *', Icons.category_outlined),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                isExpanded: true,
                hint: const Text('Selecione o tipo',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                items: tipos
                    .map((t) => DropdownMenuItem(
                          value: t['value'],
                          child: Text(t['label']!,
                              style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                validator: (v) => v == null ? 'Selecione o tipo' : null,
                onChanged: (v) => setState(() => selectedTipo = v),
              ),
              const SizedBox(height: 14),

              // ── Valor ─────────────────────────────────────────────────────
              TextFormField(
                controller: valorController,
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Valor da Multa (R\$) *', Icons.attach_money),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o valor';
                  if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Data ──────────────────────────────────────────────────────
              GestureDetector(
                onTap: _pickData,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          color: AppColors.textSecondary, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dataMulta != null
                              ? 'Data: ${_fmtDate(dataMulta!)}'
                              : 'Data da Multa (toque para selecionar)',
                          style: TextStyle(
                              color: dataMulta != null ? Colors.white : AppColors.textSecondary,
                              fontSize: 14),
                        ),
                      ),
                      const Icon(Icons.edit_calendar, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Descrição ─────────────────────────────────────────────────
              TextFormField(
                controller: descricaoController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration:
                    _dec('Descrição *', Icons.notes_outlined).copyWith(alignLabelWithHint: true),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Descreva a multa' : null,
              ),
              const SizedBox(height: 14),

              // ── Foto ──────────────────────────────────────────────────────
              if (fotoBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(fotoBytes!,
                      height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _pickFoto,
                icon: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.textSecondary, size: 18),
                label: Text(
                  fotoBytes != null ? 'Trocar Foto' : 'Adicionar Foto (opcional)',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),

              // ── Botão salvar ──────────────────────────────────────────────
              ElevatedButton(
                onPressed: (isSaving || carregandoDados) ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Registrar Multa',
                        style: TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingField(String msg) => Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );

  Widget _avisoSemDados(String msg, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 10),
            Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        filled: true,
        fillColor: AppColors.backgroundSoft,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger)),
      );
}

// ─── Detalhe da multa ─────────────────────────────────────────────────────────

class _DetalheMultaPage extends StatefulWidget {
  final Map<String, dynamic> multa;
  final VoidCallback onAtualizada;

  const _DetalheMultaPage({required this.multa, required this.onAtualizada});

  @override
  State<_DetalheMultaPage> createState() => _DetalheMultaPageState();
}

class _DetalheMultaPageState extends State<_DetalheMultaPage> {
  final supabase = Supabase.instance.client;
  late Map<String, dynamic> multa;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    multa = Map<String, dynamic>.from(widget.multa);
  }

  String get _status => multa['status']?.toString() ?? 'aberta';
  bool get _paga => _status == 'paga';

  Color _statusColor(String s) => switch (s.toLowerCase()) {
        'paga' => AppColors.success,
        'contestada' => const Color(0xFF8B5CF6),
        _ => AppColors.warning,
      };

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _fmtValue(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
    return 'R\$ ${d.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String get _veiculoLabel =>
      multa['_veiculo_label']?.toString() ??
      multa['vehicles']?['plate']?.toString() ??
      '-';

  String get _motoristaLabel =>
      multa['_motorista_label']?.toString() ??
      multa['drivers']?['name']?.toString() ??
      '-';

  Future<void> _atualizarStatus(String novoStatus) async {
    final id = multa['id']?.toString();
    if (id == null) return;

    if (novoStatus == 'paga') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirmar pagamento',
              style: TextStyle(color: Colors.white)),
          content: const Text('Marcar esta multa como paga?',
              style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => salvando = true);
    try {
      await supabase.from('multas').update({'status': novoStatus}).eq('id', id);
      if (novoStatus == 'paga') {
        try {
          await supabase.from('multas').update({
            'data_pagamento': DateTime.now().toIso8601String().split('T')[0],
          }).eq('id', id);
        } catch (_) {}
      }
      setState(() => multa = {...multa, 'status': novoStatus});
      widget.onAtualizada();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(novoStatus == 'paga'
                ? 'Multa marcada como paga!'
                : 'Multa marcada como contestada.'),
            backgroundColor: novoStatus == 'paga' ? AppColors.success : const Color(0xFF8B5CF6),
          ),
        );
        if (novoStatus == 'paga') Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  Future<void> _deletar() async {
    final id = multa['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final conf = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir multa', style: TextStyle(color: Colors.white)),
        content: const Text('Excluir esta multa permanentemente?',
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
      await supabase.from('multas').delete().eq('id', id);
      widget.onAtualizada();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = _statusColor(_status);
    final valor = multa['valor'];
    final tipo = multa['tipo']?.toString() ?? '-';
    final descricao = multa['descricao']?.toString() ?? '-';
    final data = _fmtDate(multa['data']?.toString() ?? multa['created_at']?.toString());
    final fotoUrl = multa['foto_url']?.toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalhe da Multa'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            tooltip: 'Excluir multa',
            onPressed: _deletar,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.gavel, color: cor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tipo,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(data,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_fmtValue(valor),
                          style: TextStyle(
                              color: _paga ? AppColors.success : AppColors.danger,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cor.withOpacity(0.13),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cor.withOpacity(0.4)),
                        ),
                        child: Text(_status.toUpperCase(),
                            style: TextStyle(
                                color: cor, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Informações
            _section('Informações', [
              _infoRow(Icons.directions_car_outlined, 'Veículo', _veiculoLabel),
              _infoRow(Icons.person_outline, 'Motorista', _motoristaLabel),
              _infoRow(Icons.category_outlined, 'Tipo', tipo),
              _infoRow(Icons.calendar_today_outlined, 'Data', data),
            ]),
            const SizedBox(height: 14),

            // Descrição
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Descrição',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(descricao, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),

            // Foto
            if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  fotoUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 80,
                    color: AppColors.backgroundSoft,
                    child: const Center(
                        child: Icon(Icons.broken_image, color: AppColors.textSecondary)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Ações
            if (!_paga) ...[
              ElevatedButton.icon(
                onPressed: salvando ? null : () => _atualizarStatus('paga'),
                icon: salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle, color: Colors.white),
                label: const Text('Marcar como Paga',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_status != 'contestada') ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: salvando ? null : () => _atualizarStatus('contestada'),
                  icon: const Icon(Icons.balance, color: Color(0xFF8B5CF6), size: 18),
                  label: const Text('Contestar Multa',
                      style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF8B5CF6)),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ] else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Text('Multa paga',
                        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(title,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4)),
            ),
            const Divider(height: 1, color: AppColors.border),
            ...rows,
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 16),
            const SizedBox(width: 10),
            SizedBox(
                width: 80,
                child: Text(label,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

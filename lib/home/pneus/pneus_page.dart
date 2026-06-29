import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';

class PneusPage extends StatefulWidget {
  const PneusPage({super.key});

  @override
  State<PneusPage> createState() => _PneusPageState();
}

class _PneusPageState extends State<PneusPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> pneus = [];
  Map<String, Map<String, dynamic>> veiculosMap = {};
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      // Queries separadas — sem depender de FK configurada
      final results = await Future.wait([
        supabase.from('pneus').select('*').order('created_at', ascending: false),
        supabase.from('vehicles').select('id, plate, brand, model').order('plate'),
      ]);

      final rawPneus = List<Map<String, dynamic>>.from(
        (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final map = <String, Map<String, dynamic>>{};
      for (final v in (results[1] as List)) {
        final row = Map<String, dynamic>.from(v as Map);
        map[row['id'].toString()] = row;
      }

      if (!mounted) return;
      setState(() {
        pneus = rawPneus;
        veiculosMap = map;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar pneus: $e');
      if (!mounted) return;
      setState(() => carregando = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
      }
    }
  }

  Future<void> _deletarPneu(Map<String, dynamic> p) async {
    final id = p['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final conf = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir pneu', style: TextStyle(color: Colors.white)),
        content: const Text('Excluir este registro permanentemente?',
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
      await supabase.from('pneus').delete().eq('id', id);
      if (mounted) setState(() => pneus.removeWhere((x) => x['id']?.toString() == id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pneu excluído'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  void _editarStatusPneu(Map<String, dynamic> p) {
    final id = p['id']?.toString() ?? '';
    String statusAtual = p['status']?.toString() ?? 'bom';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Alterar Status do Pneu',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...['bom', 'revisar', 'troca'].map((s) {
                final cor = _statusColor(s);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () async {
                      setLocal(() => statusAtual = s);
                      Navigator.pop(ctx);
                      try {
                        await supabase.from('pneus').update({'status': s}).eq('id', id);
                        if (mounted) {
                          setState(() {
                            final idx = pneus.indexWhere((x) => x['id']?.toString() == id);
                            if (idx >= 0) { pneus[idx] = {...pneus[idx], 'status': s}; }
                          });
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Status atualizado: ${_statusLabel(s)}'), backgroundColor: AppColors.success),
                          );
                        }
                      } catch (e) {
                        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'))); }
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: statusAtual == s ? cor.withOpacity(0.2) : AppColors.backgroundSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusAtual == s ? cor : AppColors.border),
                      ),
                      child: Row(children: [
                        Icon(statusAtual == s ? Icons.radio_button_checked : Icons.radio_button_off, color: cor, size: 18),
                        const SizedBox(width: 12),
                        Text(_statusLabel(s), style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirNovoPneu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NovoPneuForm(
        onSaved: () {
          Navigator.pop(ctx);
          _carregarDados();
        },
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  Color _statusColor(String? s) => switch ((s ?? '').toLowerCase()) {
        'bom' => AppColors.success,
        'revisar' => AppColors.warning,
        'troca' => AppColors.danger,
        _ => AppColors.textSecondary,
      };

  String _statusLabel(String? s) => switch ((s ?? '').toLowerCase()) {
        'bom' => 'Bom',
        'revisar' => 'Revisar',
        'troca' => 'Trocar',
        _ => s ?? '-',
      };

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _veiculoLabel(Map<String, dynamic> p) {
    final vid = p['vehicle_id']?.toString() ?? p['veiculo_id']?.toString();
    if (vid != null && veiculosMap.containsKey(vid)) {
      final v = veiculosMap[vid]!;
      final plate = v['plate']?.toString() ?? '';
      final brand = v['brand']?.toString() ?? '';
      final model = v['model']?.toString() ?? '';
      return '$plate${brand.isNotEmpty || model.isNotEmpty ? ' — $brand $model' : ''}'.trim();
    }
    return '-';
  }

  int _count(String status) =>
      pneus.where((p) => (p['status'] ?? '').toString().toLowerCase() == status).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Controle de Pneus'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            onPressed: _abrirNovoPneu,
            tooltip: 'Novo Pneu',
            color: AppColors.secondary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovoPneu,
        backgroundColor: AppColors.secondary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Novo Pneu', style: TextStyle(color: Colors.white)),
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
                          colors: [Color(0xFF0ea5e9), Color(0xFF6366f1)],
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
                            child: const Icon(Icons.tire_repair, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Controle de Pneus',
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text('${pneus.length} pneu(s) cadastrado(s)',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                        _kpi('Total', '${pneus.length}', Icons.tire_repair, AppColors.secondary),
                        const SizedBox(width: 8),
                        _kpi('Bom', '${_count('bom')}', Icons.check_circle, AppColors.success),
                        const SizedBox(width: 8),
                        _kpi('Revisar', '${_count('revisar')}', Icons.warning, AppColors.warning),
                        const SizedBox(width: 8),
                        _kpi('Trocar', '${_count('troca')}', Icons.cancel, AppColors.danger),
                      ],
                    ),
                    const SizedBox(height: 14),

                    const Text('Pneus Cadastrados',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Lista
            if (carregando)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (pneus.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tire_repair, size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      const Text('Nenhum pneu cadastrado',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _abrirNovoPneu,
                        icon: const Icon(Icons.add),
                        label: const Text('Cadastrar Pneu'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
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
                      final p = pneus[i];
                      final status = p['status']?.toString();
                      final cor = _statusColor(status);
                      final veiculo = _veiculoLabel(p);
                      final marca = p['marca']?.toString() ?? p['brand']?.toString() ?? '-';
                      final modelo = p['modelo']?.toString() ?? p['model_tire']?.toString() ?? '';
                      final posicao = p['posicao']?.toString() ?? p['position']?.toString() ?? '-';
                      final kmInst = p['km_instalacao'] ?? p['km_installation'];
                      final dataInst = _fmtDate(
                          p['data_instalacao']?.toString() ?? p['installation_date']?.toString());
                      final obs = p['observacoes']?.toString() ?? p['notes']?.toString() ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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
                                    child: Icon(Icons.tire_repair, color: cor, size: 18),
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
                                        Text(
                                          '$marca${modelo.isNotEmpty ? ' · $modelo' : ''} — $posicao',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cor.withOpacity(0.13),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: cor.withOpacity(0.3)),
                                    ),
                                    child: Text(_statusLabel(status),
                                        style: TextStyle(
                                            color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (kmInst != null) _badge('KM: $kmInst', AppColors.secondary),
                                  if (dataInst != '-')
                                    _badge('Inst: $dataInst', AppColors.textSecondary),
                                  if (obs.isNotEmpty) _badge(obs, AppColors.textSecondary),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _editarStatusPneu(p),
                                    icon: const Icon(Icons.edit_outlined, size: 14, color: AppColors.secondary),
                                    label: const Text('Editar status', style: TextStyle(color: AppColors.secondary, fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                                    tooltip: 'Excluir',
                                    onPressed: () => _deletarPneu(p),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: pneus.length,
                  ),
                ),
              ),
          ],
        ),
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

// ─── Formulário — carrega veículos internamente ───────────────────────────────

class _NovoPneuForm extends StatefulWidget {
  final VoidCallback onSaved;

  const _NovoPneuForm({required this.onSaved});

  @override
  State<_NovoPneuForm> createState() => _NovoPneuFormState();
}

class _NovoPneuFormState extends State<_NovoPneuForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> veiculos = [];
  bool carregandoVeiculos = true;
  bool isSaving = false;

  String? veiculoSelecionado;
  String? posicaoSelecionada;
  String? statusSelecionado = 'bom';
  DateTime? dataInstalacao;

  final marcaController = TextEditingController();
  final modeloController = TextEditingController();
  final kmController = TextEditingController();
  final observacoesController = TextEditingController();

  static const posicoes = [
    'Dianteiro Esquerdo',
    'Dianteiro Direito',
    'Traseiro Esquerdo',
    'Traseiro Direito',
    'Estepe',
    'Traseiro Interno Esquerdo',
    'Traseiro Interno Direito',
  ];

  static const statuses = [
    {'value': 'bom', 'label': 'Bom'},
    {'value': 'revisar', 'label': 'Revisar'},
    {'value': 'troca', 'label': 'Trocar'},
  ];

  @override
  void initState() {
    super.initState();
    _carregarVeiculos();
  }

  @override
  void dispose() {
    marcaController.dispose();
    modeloController.dispose();
    kmController.dispose();
    observacoesController.dispose();
    super.dispose();
  }

  Future<void> _carregarVeiculos() async {
    try {
      final res = await supabase
          .from('vehicles')
          .select('id, plate, brand, model')
          .order('plate');
      if (!mounted) return;
      setState(() {
        veiculos = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        carregandoVeiculos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => carregandoVeiculos = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao carregar veículos: $e')));
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _veiculoLabel(Map<String, dynamic> v) {
    final plate = v['plate']?.toString() ?? '';
    final brand = v['brand']?.toString() ?? '';
    final model = v['model']?.toString() ?? '';
    final desc = '$brand $model'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  Future<void> _pickData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      helpText: 'Data de instalação',
    );
    if (d != null) setState(() => dataInstalacao = d);
  }

  Future<void> _salvar() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => isSaving = true);
    final injetar = context.read<AppAuthProvider>().inject;
    try {
      final payload = <String, dynamic>{
        'vehicle_id': veiculoSelecionado,
        'marca': marcaController.text.trim(),
        'posicao': posicaoSelecionada,
        'status': statusSelecionado ?? 'bom',
        if (modeloController.text.trim().isNotEmpty)
          'modelo': modeloController.text.trim(),
        if (kmController.text.trim().isNotEmpty)
          'km_instalacao': int.tryParse(kmController.text.trim()),
        if (dataInstalacao != null)
          'data_instalacao': dataInstalacao!.toIso8601String().split('T')[0],
        if (observacoesController.text.trim().isNotEmpty)
          'observacoes': observacoesController.text.trim(),
      };

      await supabase.from('pneus').insert(injetar(payload));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pneu cadastrado com sucesso!'),
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
                      color: AppColors.secondary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tire_repair, color: AppColors.secondary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Cadastrar Pneu',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Veículo ───────────────────────────────────────────────────
              if (carregandoVeiculos)
                _loadingField('Carregando veículos...')
              else if (veiculos.isEmpty)
                _erroVeiculos()
              else
                DropdownButtonFormField<String>(
                  value: veiculoSelecionado,
                  decoration: _dec('Veículo *', Icons.directions_car_outlined),
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  isExpanded: true,
                  hint: const Text('Selecione o veículo',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  items: veiculos
                      .map((v) => DropdownMenuItem<String>(
                            value: v['id']?.toString(),
                            child: Text(
                              _veiculoLabel(v),
                              style: const TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  validator: (v) => v == null ? 'Selecione um veículo' : null,
                  onChanged: (v) => setState(() => veiculoSelecionado = v),
                ),
              const SizedBox(height: 14),

              // ── Marca ─────────────────────────────────────────────────────
              TextFormField(
                controller: marcaController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: _dec('Marca *', Icons.branding_watermark_outlined),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a marca' : null,
              ),
              const SizedBox(height: 14),

              // ── Modelo ────────────────────────────────────────────────────
              TextFormField(
                controller: modeloController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: _dec('Modelo (ex: Ecopia EP150)', Icons.label_outline),
              ),
              const SizedBox(height: 14),

              // ── Posição ───────────────────────────────────────────────────
              DropdownButtonFormField<String>(
                value: posicaoSelecionada,
                decoration: _dec('Posição *', Icons.rotate_90_degrees_ccw_outlined),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                isExpanded: true,
                hint: const Text('Selecione a posição',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                items: posicoes
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                validator: (v) => v == null ? 'Selecione a posição' : null,
                onChanged: (v) => setState(() => posicaoSelecionada = v),
              ),
              const SizedBox(height: 14),

              // ── KM ────────────────────────────────────────────────────────
              TextFormField(
                controller: kmController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: _dec('KM na Instalação', Icons.speed_outlined),
              ),
              const SizedBox(height: 14),

              // ── Data Instalação ───────────────────────────────────────────
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
                          dataInstalacao != null
                              ? 'Data de instalação: ${_fmtDate(dataInstalacao!)}'
                              : 'Data de Instalação (toque para selecionar)',
                          style: TextStyle(
                            color: dataInstalacao != null ? Colors.white : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit_calendar, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Status ────────────────────────────────────────────────────
              DropdownButtonFormField<String>(
                value: statusSelecionado,
                decoration: _dec('Status do Pneu *', Icons.info_outline),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: statuses
                    .map((s) => DropdownMenuItem(
                          value: s['value'],
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: switch (s['value']) {
                                    'bom' => AppColors.success,
                                    'revisar' => AppColors.warning,
                                    _ => AppColors.danger,
                                  },
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(s['label']!,
                                  style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => statusSelecionado = v),
              ),
              const SizedBox(height: 14),

              // ── Observações ───────────────────────────────────────────────
              TextFormField(
                controller: observacoesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration:
                    _dec('Observações (opcional)', Icons.notes_outlined).copyWith(
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // ── Botão salvar ──────────────────────────────────────────────
              ElevatedButton(
                onPressed: (isSaving || carregandoVeiculos) ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Salvar Pneu',
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
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );

  Widget _erroVeiculos() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppColors.warning, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Nenhum veículo cadastrado. Cadastre um veículo antes de registrar o pneu.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: _carregarVeiculos,
              child: const Text('Tentar novamente',
                  style: TextStyle(color: AppColors.secondary, fontSize: 11)),
            ),
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
            borderSide: const BorderSide(color: AppColors.secondary)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger)),
      );
}

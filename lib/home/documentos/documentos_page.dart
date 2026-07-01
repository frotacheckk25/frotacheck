import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/app_auth_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class DocumentosPage extends StatefulWidget {
  const DocumentosPage({super.key});

  @override
  State<DocumentosPage> createState() => _DocumentosPageState();
}

class _DocumentosPageState extends State<DocumentosPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> documentos = [];
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
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var docQ  = supabase.from('documentos').select('*');
      var veicQ = supabase.from('vehicles').select('id, plate, brand, model, driver_id');
      var drivQ = supabase.from('drivers').select('id, name');
      if (eid != null) {
        docQ  = docQ.eq('empresa_id', eid);
        veicQ = veicQ.eq('empresa_id', eid);
        drivQ = drivQ.eq('empresa_id', eid);
      }
      // Queries separadas — sem FK join
      final results = await Future.wait([
        docQ.order('data_vencimento', ascending: true),
        veicQ.order('plate'),
        drivQ.order('name'),
      ]);

      final rawDocs = List<Map<String, dynamic>>.from(
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
        documentos = rawDocs;
        veiculosMap = vMap;
        motoristasMap = mMap;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar documentos: $e');
      if (!mounted) return;
      setState(() => carregando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
    }
  }

  void _abrirNovoDocumento() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NovoDocumentoForm(
        veiculosMap: veiculosMap,
        motoristasMap: motoristasMap,
        onSaved: () {
          Navigator.pop(ctx);
          _carregarDados();
        },
      ),
    );
  }

  void _abrirDetalhe(Map<String, dynamic> doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalheDocumentoPage(
          documento: {
            ...doc,
            '_veiculo_label': _veiculoLabel(doc),
            '_motorista_label': _motoristaLabel(doc),
          },
          onAtualizado: _carregarDados,
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _vid(Map<String, dynamic> d) =>
      d['vehicle_id']?.toString() ?? d['veiculo_id']?.toString() ?? '';

  String _mid(Map<String, dynamic> d) =>
      d['driver_id']?.toString() ?? d['motorista_id']?.toString() ?? '';

  String _veiculoLabel(Map<String, dynamic> d) {
    final vid = _vid(d);
    if (vid.isEmpty) return '-';
    final v = veiculosMap[vid];
    if (v == null) return '-';
    final plate = v['plate']?.toString() ?? '';
    final brand = v['brand']?.toString() ?? '';
    final model = v['model']?.toString() ?? '';
    final desc = '$brand $model'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  String _motoristaLabel(Map<String, dynamic> d) {
    final mid = _mid(d);
    if (mid.isEmpty) return '-';
    return motoristasMap[mid]?['name']?.toString() ?? '-';
  }

  List<Map<String, dynamic>> get _filtrados {
    switch (filtro) {
      case 'vencidos':
        return documentos.where(_isVencido).toList();
      case 'vencer_30':
        return documentos
            .where((d) => _isVencer30(d) && !_isVencido(d))
            .toList();
      case 'ativos':
        return documentos
            .where((d) => !_isVencido(d) && !_isVencer30(d))
            .toList();
      default:
        return documentos;
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  bool _isVencido(Map<String, dynamic> d) {
    final dt = _parseDate(d['data_vencimento']);
    if (dt == null) return false;
    return DateTime.now().isAfter(dt);
  }

  bool _isVencer30(Map<String, dynamic> d) {
    final dt = _parseDate(d['data_vencimento']);
    if (dt == null) return false;
    final dias = dt.difference(DateTime.now()).inDays;
    return dias >= 0 && dias <= 30;
  }

  Color _statusColor(Map<String, dynamic> d) {
    if (_isVencido(d)) return AppColors.danger;
    if (_isVencer30(d)) return AppColors.warning;
    return AppColors.success;
  }

  String _statusLabel(Map<String, dynamic> d) {
    if (_isVencido(d)) return 'Vencido';
    if (_isVencer30(d)) {
      final dt = _parseDate(d['data_vencimento']);
      if (dt == null) return 'Vence em breve';
      return 'Vence em ${dt.difference(DateTime.now()).inDays}d';
    }
    return 'Ativo';
  }

  String _fmtDate(dynamic v) {
    final dt = _parseDate(v);
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  int _count(String tipo) {
    switch (tipo) {
      case 'vencidos':
        return documentos.where(_isVencido).length;
      case 'vencer_30':
        return documentos.where((d) => _isVencer30(d) && !_isVencido(d)).length;
      case 'ativos':
        return documentos
            .where((d) => !_isVencido(d) && !_isVencer30(d))
            .length;
      default:
        return documentos.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestão de Documentos'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            color: AppColors.secondary,
            onPressed: _abrirNovoDocumento,
            tooltip: 'Novo Documento',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovoDocumento,
        backgroundColor: const Color(0xFF0ea5e9),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Novo Documento',
          style: TextStyle(color: Colors.white),
        ),
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
                            child: const Icon(
                              Icons.folder_special,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Documentos da Frota',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_count('vencidos')} vencido(s) · ${_count('vencer_30')} vencendo em breve',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
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
                          '${documentos.length}',
                          Icons.description,
                          AppColors.secondary,
                        ),
                        const SizedBox(width: 8),
                        _kpi(
                          'Ativos',
                          '${_count('ativos')}',
                          Icons.check_circle,
                          AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        _kpi(
                          'Vencer',
                          '${_count('vencer_30')}',
                          Icons.schedule,
                          AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        _kpi(
                          'Vencidos',
                          '${_count('vencidos')}',
                          Icons.warning_amber,
                          AppColors.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filtros
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip('Todos', 'todos'),
                          const SizedBox(width: 8),
                          _chip('Ativos', 'ativos', color: AppColors.success),
                          const SizedBox(width: 8),
                          _chip(
                            'Vencer em 30d',
                            'vencer_30',
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          _chip(
                            'Vencidos',
                            'vencidos',
                            color: AppColors.danger,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${filtrados.length} documento(s)',
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
                        Icons.folder_open,
                        size: 64,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        documentos.isEmpty
                            ? 'Nenhum documento cadastrado'
                            : 'Nenhum documento neste filtro',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _abrirNovoDocumento,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar Documento'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0ea5e9),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final doc = filtrados[i];
                    final cor = _statusColor(doc);
                    final tipo = doc['tipo']?.toString() ?? '-';
                    final descricao = doc['descricao']?.toString() ?? '';
                    final vencimento = _fmtDate(doc['data_vencimento']);
                    final emissao = _fmtDate(doc['data_emissao']);
                    final veiculo = _veiculoLabel(doc);
                    final motorista = _motoristaLabel(doc);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _abrirDetalhe(doc),
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
                                offset: const Offset(0, 2),
                              ),
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
                                    child: Icon(
                                      Icons.description,
                                      color: cor,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tipo,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          veiculo,
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cor.withOpacity(0.13),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: cor.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      _statusLabel(doc),
                                      style: TextStyle(
                                        color: cor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (descricao.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  descricao,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (motorista != '-')
                                    _badge(
                                      '👤 $motorista',
                                      AppColors.textSecondary,
                                    ),
                                  if (emissao != '-')
                                    _badge(
                                      'Emissão: $emissao',
                                      AppColors.textSecondary,
                                    ),
                                  _badge('Vence: $vencimento', cor),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: filtrados.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Expanded(
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
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

// ─── Formulário — carrega veículos e motoristas internamente ──────────────────

class _NovoDocumentoForm extends StatefulWidget {
  final Map<String, Map<String, dynamic>> veiculosMap;
  final Map<String, Map<String, dynamic>> motoristasMap;
  final VoidCallback onSaved;

  const _NovoDocumentoForm({
    required this.veiculosMap,
    required this.motoristasMap,
    required this.onSaved,
  });

  @override
  State<_NovoDocumentoForm> createState() => _NovoDocumentoFormState();
}

class _NovoDocumentoFormState extends State<_NovoDocumentoForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool isSaving = false;

  // Listas resolvidas a partir dos maps do pai
  late List<Map<String, dynamic>> veiculos;
  late List<Map<String, dynamic>> motoristas;

  String? tipoSelecionado;
  String? veiculoId;
  String? motoristaAutoId;
  String? motoristaAutoNome;
  String? motoristaManualId;
  PlatformFile? arquivo;

  DateTime? dataEmissao;
  DateTime dataVencimento = DateTime.now().add(const Duration(days: 365));
  DateTime? dataPagamento;

  final descricaoCtrl = TextEditingController();

  static const tipos = [
    'CRLV',
    'Licenciamento',
    'Seguro',
    'CNH - Frente',
    'CNH - Verso',
    'Certificado',
    'Apólice',
    'Outros',
  ];

  @override
  void initState() {
    super.initState();
    veiculos = widget.veiculosMap.values.toList()
      ..sort((a, b) => (a['plate'] ?? '').compareTo(b['plate'] ?? ''));
    motoristas = widget.motoristasMap.values.toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
  }

  @override
  void dispose() {
    descricaoCtrl.dispose();
    super.dispose();
  }

  String _veiculoLabel(Map<String, dynamic> v) {
    final plate = v['plate']?.toString() ?? '';
    final brand = v['brand']?.toString() ?? '';
    final model = v['model']?.toString() ?? '';
    final desc = '$brand $model'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<DateTime?> _pickDate({
    required DateTime initial,
    DateTime? firstDate,
    DateTime? lastDate,
    String helpText = 'Selecionar data',
  }) async {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(2015),
      lastDate: lastDate ?? DateTime(2040),
      helpText: helpText,
      builder: (c, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.secondary,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: AppColors.backgroundSoft,
          ),
        ),
        child: child!,
      ),
    );
  }

  void _aoSelecionarVeiculo(String? id) {
    setState(() {
      veiculoId = id;
      motoristaAutoId = null;
      motoristaAutoNome = null;
      motoristaManualId = null;
    });

    if (id == null) return;

    // Tenta auto-preencher motorista a partir do veiculos map
    final v = widget.veiculosMap[id];
    if (v == null) return;
    final driverId = v['driver_id']?.toString();
    if (driverId == null || driverId.isEmpty) return;

    final driver = widget.motoristasMap[driverId];
    if (driver != null) {
      setState(() {
        motoristaAutoId = driverId;
        motoristaAutoNome = driver['name']?.toString();
      });
    }
  }

  Future<void> _selecionarArquivo() async {
    final resultado = await FilePicker.platform.pickFiles(
      withData: true,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      type: FileType.custom,
    );
    if (resultado != null && resultado.files.isNotEmpty) {
      if (mounted) setState(() => arquivo = resultado.files.single);
    }
  }

  Future<void> _salvar() async {
    if (_formKey.currentState?.validate() != true) return;
    if (dataEmissao != null && dataVencimento.isBefore(dataEmissao!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data de vencimento não pode ser anterior à data de emissão'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => isSaving = true);
    final injetar = context.read<AppAuthProvider>().inject;
    try {
      // Upload arquivo (silencioso se bucket não existir)
      String? fileUrl;
      if (arquivo != null && arquivo!.bytes != null) {
        try {
          final ext = arquivo!.extension ?? 'pdf';
          final fileName =
              'documento_${DateTime.now().millisecondsSinceEpoch}.$ext';
          await supabase.storage
              .from('documentos')
              .uploadBinary(
                fileName,
                arquivo!.bytes!,
                fileOptions: const FileOptions(upsert: true),
              );
          fileUrl = supabase.storage.from('documentos').getPublicUrl(fileName);
        } catch (_) {}
      }

      final motoristaId = motoristaAutoId ?? motoristaManualId;

      final payload = <String, dynamic>{
        'tipo': tipoSelecionado,
        'descricao': descricaoCtrl.text.trim(),
        'data_vencimento': dataVencimento.toIso8601String().split('T')[0],
        'ativo': true,
        // ignore: use_null_aware_elements
        if (veiculoId != null) 'vehicle_id': veiculoId,
        // ignore: use_null_aware_elements
        if (motoristaId != null) 'driver_id': motoristaId,
        // ignore: use_null_aware_elements
        if (fileUrl != null) 'file_url': fileUrl,
        if (dataEmissao != null)
          'data_emissao': dataEmissao!.toIso8601String().split('T')[0],
        if (dataPagamento != null)
          'data_pagamento': dataPagamento!.toIso8601String().split('T')[0],
      };

      await supabase.from('documentos').insert(injetar(payload));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento registrado com sucesso!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final temAutoDriver = motoristaAutoId != null && motoristaAutoNome != null;

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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0ea5e9).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_special,
                      color: Color(0xFF0ea5e9),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Novo Documento',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Tipo ──────────────────────────────────────────────────────
              DropdownButtonFormField<String>(
                value: tipoSelecionado,
                decoration: _dec(
                  'Tipo de Documento *',
                  Icons.category_outlined,
                ),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                isExpanded: true,
                hint: const Text(
                  'Selecione o tipo',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                items: tipos
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                validator: (v) => v == null ? 'Selecione o tipo' : null,
                onChanged: (v) => setState(() => tipoSelecionado = v),
              ),
              const SizedBox(height: 14),

              // ── Veículo ──────────────────────────────────────────────────
              if (veiculos.isEmpty)
                _avisoSemDados(
                  'Nenhum veículo cadastrado',
                  Icons.directions_car_outlined,
                )
              else
                DropdownButtonFormField<String>(
                  value: veiculoId,
                  decoration: _dec('Veículo *', Icons.directions_car_outlined),
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  isExpanded: true,
                  hint: const Text(
                    'Selecione o veículo',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  items: veiculos
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v['id']?.toString(),
                          child: Text(
                            _veiculoLabel(v),
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (v) => v == null ? 'Selecione um veículo' : null,
                  onChanged: _aoSelecionarVeiculo,
                ),
              const SizedBox(height: 14),

              // ── Motorista — auto detectado ou manual ──────────────────────
              if (temAutoDriver)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_pin,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Motorista vinculado ao veículo',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              motoristaAutoNome!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          motoristaAutoId = null;
                          motoristaAutoNome = null;
                        }),
                        child: const Icon(
                          Icons.edit,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                )
              else if (motoristas.isEmpty)
                _avisoSemDados(
                  'Nenhum motorista cadastrado (opcional)',
                  Icons.person_outline,
                )
              else
                DropdownButtonFormField<String>(
                  value: motoristaManualId,
                  decoration: _dec(
                    'Motorista (opcional)',
                    Icons.person_outline,
                  ),
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  isExpanded: true,
                  hint: const Text(
                    'Selecione o motorista',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Sem motorista',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    ...motoristas.map(
                      (m) => DropdownMenuItem<String>(
                        value: m['id']?.toString(),
                        child: Text(
                          m['name']?.toString() ?? '-',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => motoristaManualId = v),
                ),
              const SizedBox(height: 14),

              // ── Descrição ─────────────────────────────────────────────────
              TextFormField(
                controller: descricaoCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: _dec(
                  'Descrição *',
                  Icons.notes_outlined,
                ).copyWith(alignLabelWithHint: true),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe a descrição'
                    : null,
              ),
              const SizedBox(height: 14),

              // ── Data de Emissão ───────────────────────────────────────────
              _datePicker(
                label: 'Data de Emissão',
                icon: Icons.calendar_today_outlined,
                value: dataEmissao,
                placeholder: 'Toque para selecionar (opcional)',
                onTap: () async {
                  final d = await _pickDate(
                    initial: dataEmissao ?? DateTime.now(),
                    lastDate: DateTime.now(),
                    helpText: 'Data de emissão',
                  );
                  if (d != null) setState(() => dataEmissao = d);
                },
              ),
              const SizedBox(height: 14),

              // ── Data de Vencimento ────────────────────────────────────────
              _datePicker(
                label: 'Data de Vencimento *',
                icon: Icons.event_outlined,
                value: dataVencimento,
                required: true,
                onTap: () async {
                  final d = await _pickDate(
                    initial: dataVencimento,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2040),
                    helpText: 'Data de vencimento',
                  );
                  if (d != null) setState(() => dataVencimento = d);
                },
              ),
              const SizedBox(height: 14),

              // ── Data de Pagamento ─────────────────────────────────────────
              _datePicker(
                label: 'Data de Pagamento',
                icon: Icons.payments_outlined,
                value: dataPagamento,
                placeholder: 'Toque para selecionar (opcional)',
                onTap: () async {
                  final d = await _pickDate(
                    initial: dataPagamento ?? DateTime.now(),
                    helpText: 'Data de pagamento',
                  );
                  if (d != null) setState(() => dataPagamento = d);
                },
              ),
              const SizedBox(height: 14),

              // ── Arquivo ───────────────────────────────────────────────────
              GestureDetector(
                onTap: _selecionarArquivo,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: arquivo != null
                        ? AppColors.success.withOpacity(0.08)
                        : AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: arquivo != null
                          ? AppColors.success.withOpacity(0.4)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        arquivo != null ? Icons.attach_file : Icons.upload_file,
                        color: arquivo != null
                            ? AppColors.success
                            : AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          arquivo != null
                              ? arquivo!.name
                              : 'Selecionar arquivo (opcional)',
                          style: TextStyle(
                            color: arquivo != null
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (arquivo != null)
                        GestureDetector(
                          onTap: () => setState(() => arquivo = null),
                          child: const Icon(
                            Icons.close,
                            color: AppColors.textSecondary,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Botão salvar ──────────────────────────────────────────────
              ElevatedButton(
                onPressed: isSaving ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0ea5e9),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Registrar Documento',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        Text(
          msg,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _datePicker({
    required String label,
    required IconData icon,
    required DateTime? value,
    required VoidCallback onTap,
    String placeholder = 'Não informado',
    bool required = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value != null ? _fmt(value) : placeholder,
                    style: TextStyle(
                      color: value != null
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_calendar,
              color: AppColors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
    filled: true,
    fillColor: AppColors.backgroundSoft,
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
      borderSide: const BorderSide(color: Color(0xFF0ea5e9)),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.danger),
    ),
  );
}

// ─── Detalhe do documento ─────────────────────────────────────────────────────

class _DetalheDocumentoPage extends StatefulWidget {
  final Map<String, dynamic> documento;
  final VoidCallback onAtualizado;

  const _DetalheDocumentoPage({
    required this.documento,
    required this.onAtualizado,
  });

  @override
  State<_DetalheDocumentoPage> createState() => _DetalheDocumentoPageState();
}

class _DetalheDocumentoPageState extends State<_DetalheDocumentoPage> {
  final supabase = Supabase.instance.client;

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  String _fmtDate(dynamic v) {
    final dt = _parseDate(v);
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  bool get _isVencido {
    final dt = _parseDate(widget.documento['data_vencimento']);
    if (dt == null) return false;
    return DateTime.now().isAfter(dt);
  }

  bool get _isVencer30 {
    final dt = _parseDate(widget.documento['data_vencimento']);
    if (dt == null) return false;
    final dias = dt.difference(DateTime.now()).inDays;
    return dias >= 0 && dias <= 30;
  }

  Color get _cor {
    if (_isVencido) return AppColors.danger;
    if (_isVencer30) return AppColors.warning;
    return AppColors.success;
  }

  String get _status {
    if (_isVencido) return 'Vencido';
    if (_isVencer30) {
      final dt = _parseDate(widget.documento['data_vencimento']);
      return 'Vence em ${dt?.difference(DateTime.now()).inDays ?? 0} dias';
    }
    return 'Ativo';
  }

  String get _veiculo =>
      widget.documento['_veiculo_label']?.toString() ??
      widget.documento['vehicles']?['plate']?.toString() ??
      '-';

  String get _motorista =>
      widget.documento['_motorista_label']?.toString() ??
      widget.documento['drivers']?['name']?.toString() ??
      '-';

  Future<void> _deletar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Excluir Documento?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Esta ação é irreversível. Deseja continuar?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      // Apaga o arquivo do Storage se existir
      final fileUrl = widget.documento['file_url']?.toString() ?? '';
      if (fileUrl.isNotEmpty) {
        try {
          final uri = Uri.tryParse(fileUrl);
          if (uri != null) {
            final segments = uri.pathSegments;
            final bucketIndex = segments.indexOf('documentos');
            if (bucketIndex >= 0 && bucketIndex + 1 < segments.length) {
              final filePath = segments.sublist(bucketIndex + 1).join('/');
              await supabase.storage.from('documentos').remove([filePath]);
            }
          }
        } catch (_) {}
      }

      await supabase
          .from('documentos')
          .delete()
          .eq('id', widget.documento['id']);
      widget.onAtualizado();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Documento excluído.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  void _abrirEdicao() {
    final doc = widget.documento;
    final descController = TextEditingController(
      text: doc['descricao']?.toString() ?? '',
    );
    DateTime? vencimento = _parseDate(doc['data_vencimento']);
    String tipo = doc['tipo']?.toString() ?? 'CNH';
    final tipos = ['CNH', 'CRLV', 'Seguro', 'Licença', 'Outros'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Editar Documento',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: tipos.contains(tipo) ? tipo : tipos.last,
                decoration: InputDecoration(
                  labelText: 'Tipo',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundSoft,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                items: tipos
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocal(() => tipo = v ?? tipo),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundSoft,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: vencimento ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (picked != null) setLocal(() => vencimento = picked);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        vencimento != null
                            ? '${vencimento!.day.toString().padLeft(2, '0')}/${vencimento!.month.toString().padLeft(2, '0')}/${vencimento!.year}'
                            : 'Vencimento (opcional)',
                        style: TextStyle(
                          color: vencimento != null
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await supabase
                        .from('documentos')
                        .update({
                          'tipo': tipo,
                          'descricao': descController.text.trim(),
                          if (vencimento != null)
                            'data_vencimento': vencimento!
                                .toIso8601String()
                                .split('T')[0],
                        })
                        .eq('id', widget.documento['id']);
                    widget.onAtualizado();
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Documento atualizado'),
                          backgroundColor: AppColors.success,
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
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Salvar alterações',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.documento;
    final tipo = doc['tipo']?.toString() ?? '-';
    final descricao = doc['descricao']?.toString() ?? '-';
    final fileUrl = doc['file_url']?.toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalhe do Documento'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: _abrirEdicao,
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
                border: Border.all(color: _cor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _cor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description, color: _cor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tipo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          descricao,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _cor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _cor.withOpacity(0.4)),
                    ),
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _cor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Informações
            _section('Informações', [
              _infoRow(Icons.directions_car_outlined, 'Veículo', _veiculo),
              _infoRow(Icons.person_outline, 'Motorista', _motorista),
              _infoRow(
                Icons.calendar_today_outlined,
                'Emissão',
                _fmtDate(doc['data_emissao']),
              ),
              _infoRow(
                Icons.event_outlined,
                'Vencimento',
                _fmtDate(doc['data_vencimento']),
              ),
              _infoRow(
                Icons.payments_outlined,
                'Pagamento',
                _fmtDate(doc['data_pagamento']),
              ),
            ]),
            const SizedBox(height: 14),

            // Arquivo
            if (fileUrl != null && fileUrl.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.attach_file,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Arquivo anexado',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Visualizar',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Botão excluir
            OutlinedButton.icon(
              onPressed: _deletar,
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.danger,
                size: 18,
              ),
              label: const Text(
                'Excluir Documento',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
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
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

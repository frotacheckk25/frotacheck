import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frotacheck/core/theme/app_theme.dart';

class VeiculosPage extends StatefulWidget {
  const VeiculosPage({super.key});

  @override
  State<VeiculosPage> createState() => _VeiculosPageState();
}

class _VeiculosPageState extends State<VeiculosPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final searchController = TextEditingController();

  final placaController = TextEditingController();
  final marcaController = TextEditingController();
  final modeloController = TextEditingController();
  final anoController = TextEditingController();
  final corController = TextEditingController();
  final kmController = TextEditingController();

  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> motoristas = [];
  List<Map<String, dynamic>> veiculos = [];
  String? motoristaSelecionado;
  bool isSaving = false;
  bool carregandoVeiculos = true;
  String? erroMsg;
  String? editingId;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    await Future.wait([carregarMotoristas(), carregarVeiculos()]);
  }

  Future<void> carregarMotoristas() async {
    try {
      final response = await supabase
          .from('drivers')
          .select('id, name')
          .order('name');
      if (!mounted) return;
      setState(() {
        motoristas = List<Map<String, dynamic>>.from(
          (response as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
    } catch (e) {
      debugPrint('Erro motoristas: $e');
    }
  }

  Future<void> carregarVeiculos() async {
    if (!mounted) return;
    setState(() => carregandoVeiculos = true);
    try {
      final response = await supabase
          .from('vehicles')
          .select('id, plate, brand, model, year, color, odometer, driver_id')
          .order('plate');
      if (!mounted) return;
      setState(() {
        veiculos = List<Map<String, dynamic>>.from(
          (response as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        erroMsg = null;
        carregandoVeiculos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erroMsg = e.toString();
        carregandoVeiculos = false;
      });
    }
  }

  String _nomeMotorista(Map<String, dynamic> veiculo) {
    final id = veiculo['driver_id']?.toString();
    if (id == null) return 'Sem motorista';
    try {
      final m = motoristas.firstWhere(
        (d) => d['id']?.toString() == id,
        orElse: () => {},
      );
      return m['name']?.toString() ?? 'Sem motorista';
    } catch (_) {
      return 'Sem motorista';
    }
  }

  Future<void> salvarVeiculo() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => isSaving = true);

    final payload = {
      'plate': placaController.text.trim().toUpperCase(),
      'brand': marcaController.text.trim(),
      'model': modeloController.text.trim(),
      'year': int.tryParse(anoController.text.trim()),
      'color': corController.text.trim(),
      'odometer': int.tryParse(kmController.text.trim()) ?? 0,
      'driver_id': motoristaSelecionado,
    };

    try {
      final isNew = editingId == null;

      if (isNew) {
        // Insert e retorna a linha criada para atualizar a lista imediatamente
        final result = await supabase.from('vehicles').insert(payload).select();
        if (!mounted) return;
        if (result.isNotEmpty) {
          final novoVeiculo = Map<String, dynamic>.from(result.first as Map);
          setState(() {
            veiculos = [novoVeiculo, ...veiculos];
            veiculos.sort(
              (a, b) => (a['plate'] ?? '').toString().compareTo(
                (b['plate'] ?? '').toString(),
              ),
            );
          });
        }
      } else {
        await supabase.from('vehicles').update(payload).eq('id', editingId!);
        if (!mounted) return;
        // Atualiza localmente
        setState(() {
          final idx = veiculos.indexWhere(
            (v) => v['id']?.toString() == editingId,
          );
          if (idx >= 0) {
            veiculos[idx] = {...veiculos[idx], ...payload, 'id': editingId};
          }
        });
      }

      if (!mounted) return;
      _mostrarSucesso(
        isNew ? 'Veículo cadastrado com sucesso!' : 'Veículo atualizado!',
      );
      _limparFormulario();
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _mostrarSucesso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Text(msg),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _limparFormulario() {
    placaController.clear();
    marcaController.clear();
    modeloController.clear();
    anoController.clear();
    corController.clear();
    kmController.clear();
    setState(() {
      motoristaSelecionado = null;
      editingId = null;
    });
    _formKey.currentState?.reset();
  }

  void editarVeiculo(Map<String, dynamic> v) {
    setState(() {
      editingId = v['id']?.toString();
      placaController.text = v['plate']?.toString() ?? '';
      marcaController.text = v['brand']?.toString() ?? '';
      modeloController.text = v['model']?.toString() ?? '';
      anoController.text = v['year']?.toString() ?? '';
      corController.text = v['color']?.toString() ?? '';
      kmController.text = v['odometer']?.toString() ?? '';
      motoristaSelecionado = v['driver_id']?.toString();
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  Future<void> deletarVeiculo(String id, String placa) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Excluir veículo',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja excluir o veículo $placa permanentemente?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
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
      await supabase.from('vehicles').delete().eq('id', id);
      if (!mounted) return;
      setState(() => veiculos.removeWhere((v) => v['id']?.toString() == id));
      _mostrarSucesso('Veículo $placa excluído');
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Erro ao excluir: $e');
    }
  }

  List<Map<String, dynamic>> get veiculosFiltrados {
    final q = searchController.text.toLowerCase();
    if (q.isEmpty) return veiculos;
    return veiculos.where((v) {
      final nome = _nomeMotorista(v);
      return '${v['plate']} ${v['brand']} ${v['model']} $nome'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  @override
  void dispose() {
    placaController.dispose();
    marcaController.dispose();
    modeloController.dispose();
    anoController.dispose();
    corController.dispose();
    kmController.dispose();
    searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Frota de Veículos'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar lista',
            onPressed: carregarVeiculos,
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
                        SizedBox(width: 400, child: _buildForm()),
                        const SizedBox(width: 20),
                        Expanded(child: _buildListaSection()),
                      ],
                    ),
                  )
                else ...[
                  _buildForm(),
                  const SizedBox(height: 20),
                  _buildListaSection(),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_shipping,
              color: AppColors.secondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestão da Frota',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Cadastre, edite e gerencie todos os veículos da frota.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final atribuidos = veiculos.where((v) => v['driver_id'] != null).length;
    return Row(
      children: [
        _statCard(
          'Total de veículos',
          veiculos.length.toString(),
          Icons.directions_car,
          AppColors.secondary,
        ),
        const SizedBox(width: 12),
        _statCard(
          'Atribuídos',
          atribuidos.toString(),
          Icons.person_pin_circle,
          AppColors.success,
        ),
        const SizedBox(width: 12),
        _statCard(
          'Sem motorista',
          (veiculos.length - atribuidos).toString(),
          Icons.warning_amber,
          AppColors.warning,
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color.withOpacity(0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
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
              Row(
                children: [
                  Icon(
                    editingId != null
                        ? Icons.edit_note
                        : Icons.add_circle_outline,
                    color: editingId != null
                        ? AppColors.warning
                        : AppColors.secondary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    editingId != null
                        ? 'Editar Veículo'
                        : 'Registrar Novo Veículo',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _campo(
                controller: placaController,
                label: 'Placa *',
                icon: Icons.credit_card,
                hint: 'Ex: ABC-1234',
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a placa' : null,
              ),
              const SizedBox(height: 12),
              _campo(
                controller: marcaController,
                label: 'Marca *',
                icon: Icons.branding_watermark,
                hint: 'Ex: Volkswagen',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a marca' : null,
              ),
              const SizedBox(height: 12),
              _campo(
                controller: modeloController,
                label: 'Modelo *',
                icon: Icons.directions_car_filled,
                hint: 'Ex: Gol',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o modelo' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _campo(
                      controller: anoController,
                      label: 'Ano *',
                      icon: Icons.calendar_today,
                      hint: '2024',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Informe o ano';
                        final ano = int.tryParse(v.trim());
                        if (ano == null || ano < 1900 || ano > 2100)
                          return 'Ano inválido';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campo(
                      controller: kmController,
                      label: 'Km atual *',
                      icon: Icons.speed,
                      hint: '0',
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Informe o Km'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _campo(
                controller: corController,
                label: 'Cor *',
                icon: Icons.color_lens,
                hint: 'Ex: Branco',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a cor' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: motoristaSelecionado,
                decoration: InputDecoration(
                  labelText: 'Motorista responsável',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                hint: const Text('Selecionar motorista (opcional)'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Sem motorista'),
                  ),
                  ...motoristas.map(
                    (m) => DropdownMenuItem<String>(
                      value: m['id']?.toString(),
                      child: Text(m['name']?.toString() ?? ''),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => motoristaSelecionado = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : salvarVeiculo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: editingId != null
                        ? AppColors.warning
                        : AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Icon(
                          editingId != null
                              ? Icons.save
                              : Icons.save_alt_rounded,
                          size: 20,
                        ),
                  label: Text(
                    isSaving
                        ? 'Salvando...'
                        : (editingId != null
                              ? 'ATUALIZAR VEÍCULO'
                              : 'SALVAR VEÍCULO'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              if (editingId != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _limparFormulario,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancelar edição'),
                ),
              ] else ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _limparFormulario,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Limpar campos'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      validator: validator,
    );
  }

  Widget _buildListaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho da lista
        Row(
          children: [
            const Expanded(
              child: Text(
                'Veículos Cadastrados',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!carregandoVeiculos)
              Text(
                '${veiculosFiltrados.length} de ${veiculos.length}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Busca
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: 'Buscar por placa, marca, modelo ou motorista...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        // Lista
        if (carregandoVeiculos)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (erroMsg != null)
          _buildErroCard()
        else if (veiculosFiltrados.isEmpty)
          _buildListaVazia()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: veiculosFiltrados.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _buildVeiculoCard(veiculosFiltrados[i]),
          ),
      ],
    );
  }

  Widget _buildErroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 32),
          const SizedBox(height: 8),
          const Text(
            'Erro ao carregar veículos',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            erroMsg ?? '',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: carregarVeiculos,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildListaVazia() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 48,
            color: AppColors.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nenhum veículo encontrado',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          if (searchController.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() => searchController.clear()),
              child: const Text('Limpar busca'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVeiculoCard(Map<String, dynamic> v) {
    final nomeMotorista = _nomeMotorista(v);
    final temMotorista = v['driver_id'] != null;
    final isEditing = editingId == v['id']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: isEditing
            ? AppColors.warning.withOpacity(0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEditing ? AppColors.warning : AppColors.border,
          width: isEditing ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.secondary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.directions_car,
            color: AppColors.secondary,
            size: 22,
          ),
        ),
        title: Text(
          '${v['plate'] ?? '--'} • ${v['brand'] ?? ''} ${v['model'] ?? ''}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  temMotorista ? Icons.person : Icons.person_off,
                  size: 13,
                  color: temMotorista
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    nomeMotorista,
                    style: TextStyle(
                      color: temMotorista
                          ? AppColors.success
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Ano: ${v['year'] ?? '--'} • Km: ${v['odometer'] ?? '--'} • Cor: ${v['color'] ?? '--'}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (action) {
            if (action == 'edit') editarVeiculo(v);
            if (action == 'delete') {
              final id = v['id']?.toString();
              final placa = v['plate']?.toString() ?? '';
              if (id != null) deletarVeiculo(id, placa);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                  SizedBox(width: 8),
                  Text('Editar', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('Excluir', style: TextStyle(color: AppColors.danger)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

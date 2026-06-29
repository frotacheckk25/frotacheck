import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class ViagensPage extends StatefulWidget {
  const ViagensPage({super.key});

  @override
  State<ViagensPage> createState() => _ViagensPageState();
}

class _ViagensPageState extends State<ViagensPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> viagens = [];
  Map<String, Map<String, dynamic>> veiculosMap = {};
  Map<String, Map<String, dynamic>> motoristasMap = {};
  bool isLoading = true;
  String filtroStatus = 'todas';

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        supabase.from('vehicles').select('id, plate, brand, model').order('plate'),
        supabase.from('drivers').select('id, name').order('name'),
      ]);

      final vMap = <String, Map<String, dynamic>>{};
      for (final v in (results[0] as List)) {
        final row = Map<String, dynamic>.from(v as Map);
        vMap[row['id'].toString()] = row;
      }
      final mMap = <String, Map<String, dynamic>>{};
      for (final m in (results[1] as List)) {
        final row = Map<String, dynamic>.from(m as Map);
        mMap[row['id'].toString()] = row;
      }

      List<Map<String, dynamic>> viaList = [];
      try {
        final viaResp = await supabase
            .from('viagens')
            .select()
            .order('data_inicio', ascending: false);
        viaList = List<Map<String, dynamic>>.from(
          (viaResp as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } catch (_) {
        // tabela viagens não existe ainda
      }

      if (!mounted) return;
      setState(() {
        viagens = viaList;
        veiculosMap = vMap;
        motoristasMap = mMap;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar viagens: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filtradas() {
    if (filtroStatus == 'todas') return viagens;
    return viagens.where((v) => v['status'] == filtroStatus).toList();
  }

  String _veiculoLabel(String? id) {
    if (id == null || id.isEmpty) return 'N/A';
    final v = veiculosMap[id];
    if (v == null) return 'Desconhecido';
    final plate = v['plate']?.toString() ?? '';
    final desc = '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  String _motoristaLabel(String? id) {
    if (id == null || id.isEmpty) return 'N/A';
    return motoristasMap[id]?['name']?.toString() ?? 'Desconhecido';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'em_progresso':
        return AppColors.info;
      case 'concluida':
        return AppColors.success;
      case 'cancelada':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'em_progresso':
        return 'Em Progresso';
      case 'concluida':
        return 'Concluída';
      case 'cancelada':
        return 'Cancelada';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtradas();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Controle de Viagens'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregarDados),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovaViagem,
        backgroundColor: AppColors.secondary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nova Viagem', style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _chip('Todas', 'todas'),
                      const SizedBox(width: 8),
                      _chip('Em Progresso', 'em_progresso'),
                      const SizedBox(width: 8),
                      _chip('Concluídas', 'concluida'),
                      const SizedBox(width: 8),
                      _chip('Canceladas', 'cancelada'),
                    ],
                  ),
                ),
                Expanded(
                  child: lista.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.directions, size: 64, color: AppColors.textSecondary),
                              const SizedBox(height: 16),
                              const Text(
                                'Nenhuma viagem encontrada',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _abrirNovaViagem,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                                child: const Text('Registrar Viagem', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _carregarDados,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: lista.length,
                            itemBuilder: (_, i) => _buildCard(lista[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _chip(String label, String value) {
    final sel = filtroStatus == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => filtroStatus = value),
      selectedColor: AppColors.secondary.withValues(alpha: 0.25),
      backgroundColor: AppColors.surface,
      checkmarkColor: AppColors.secondary,
      labelStyle: TextStyle(
        color: sel ? AppColors.secondary : AppColors.textSecondary,
        fontSize: 13,
      ),
      side: BorderSide(color: sel ? AppColors.secondary : AppColors.border),
    );
  }

  Widget _buildCard(Map<String, dynamic> v) {
    final status = v['status']?.toString() ?? 'desconhecido';
    final cor = _statusColor(status);
    final kmPerc = (v['quilometragem_percorrida'] as num?)?.toDouble();

    return GestureDetector(
      onTap: () => _abrirDetalhe(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.directions, color: cor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${v['origem'] ?? '-'} → ${v['destino'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Veículo: ${_veiculoLabel(v['veiculo_id']?.toString())}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  Text(
                    'Motorista: ${_motoristaLabel(v['motorista_id']?.toString())}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (kmPerc != null)
                    Text(
                      'KM percorrido: ${kmPerc.toStringAsFixed(1)} km',
                      style: const TextStyle(color: AppColors.secondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            Chip(
              label: Text(_statusLabel(status), style: const TextStyle(fontSize: 11)),
              backgroundColor: cor.withValues(alpha: 0.15),
              labelStyle: TextStyle(color: cor, fontWeight: FontWeight.bold),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  void _abrirNovaViagem() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NovaViagemPage(
          veiculosMap: veiculosMap,
          motoristasMap: motoristasMap,
          onSalva: _carregarDados,
        ),
      ),
    );
  }

  void _abrirDetalhe(Map<String, dynamic> viagem) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalheViagemPage(
          viagem: viagem,
          veiculoLabel: _veiculoLabel(viagem['veiculo_id']?.toString()),
          motoristaLabel: _motoristaLabel(viagem['motorista_id']?.toString()),
          onAtualizada: _carregarDados,
        ),
      ),
    );
  }
}

// ── Nova Viagem ────────────────────────────────────────────────────────────────

class _NovaViagemPage extends StatefulWidget {
  final Map<String, Map<String, dynamic>> veiculosMap;
  final Map<String, Map<String, dynamic>> motoristasMap;
  final VoidCallback onSalva;

  const _NovaViagemPage({
    required this.veiculosMap,
    required this.motoristasMap,
    required this.onSalva,
  });

  @override
  State<_NovaViagemPage> createState() => _NovaViagemPageState();
}

class _NovaViagemPageState extends State<_NovaViagemPage> {
  final supabase = Supabase.instance.client;

  String? veiculoId;
  String? motoristaId;
  bool isLoading = false;

  final origemCtrl = TextEditingController();
  final destinoCtrl = TextEditingController();
  final kmInicioCtrl = TextEditingController();

  @override
  void dispose() {
    origemCtrl.dispose();
    destinoCtrl.dispose();
    kmInicioCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (veiculoId == null ||
        motoristaId == null ||
        origemCtrl.text.isEmpty ||
        destinoCtrl.text.isEmpty ||
        kmInicioCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await supabase.from('viagens').insert({
        'veiculo_id': veiculoId,
        'motorista_id': motoristaId,
        'data_inicio': DateTime.now().toIso8601String(),
        'origem': origemCtrl.text.trim(),
        'destino': destinoCtrl.text.trim(),
        'quilometragem_inicio': double.parse(kmInicioCtrl.text),
        'status': 'em_progresso',
        'fotos_rota': [],
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viagem iniciada com sucesso!')),
      );
      widget.onSalva();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar viagem: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final veiculos = widget.veiculosMap.entries.toList();
    final motoristas = widget.motoristasMap.entries.toList();

    InputDecoration field(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.secondary),
          ),
          filled: true,
          fillColor: AppColors.backgroundSoft,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Nova Viagem'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: veiculoId,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: Colors.white),
              decoration: field('Veículo *', Icons.directions_car),
              items: veiculos.map((e) {
                final v = e.value;
                final plate = v['plate']?.toString() ?? '';
                final desc = '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
                return DropdownMenuItem(
                  value: e.key,
                  child: Text('$plate${desc.isNotEmpty ? ' — $desc' : ''}'),
                );
              }).toList(),
              onChanged: (val) => setState(() => veiculoId = val),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: motoristaId,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: Colors.white),
              decoration: field('Motorista *', Icons.person),
              items: motoristas
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value['name']?.toString() ?? ''),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => motoristaId = val),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: origemCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: field('Origem *', Icons.location_on),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: destinoCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: field('Destino *', Icons.flag),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: kmInicioCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: field('Quilometragem Inicial (KM) *', Icons.speed),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isLoading ? null : _salvar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Iniciar Viagem',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detalhe Viagem ─────────────────────────────────────────────────────────────

class _DetalheViagemPage extends StatefulWidget {
  final Map<String, dynamic> viagem;
  final String veiculoLabel;
  final String motoristaLabel;
  final VoidCallback onAtualizada;

  const _DetalheViagemPage({
    required this.viagem,
    required this.veiculoLabel,
    required this.motoristaLabel,
    required this.onAtualizada,
  });

  @override
  State<_DetalheViagemPage> createState() => _DetalheViagemPageState();
}

class _DetalheViagemPageState extends State<_DetalheViagemPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  final kmFimCtrl = TextEditingController();
  final obsCtrl = TextEditingController();

  @override
  void dispose() {
    kmFimCtrl.dispose();
    obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _concluir() async {
    if (kmFimCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a quilometragem final')),
      );
      return;
    }
    setState(() => isLoading = true);
    try {
      final kmFim = double.parse(kmFimCtrl.text);
      final kmInicio = (widget.viagem['quilometragem_inicio'] as num?)?.toDouble() ?? 0;
      final kmPerc = kmFim - kmInicio;

      await supabase.from('viagens').update({
        'data_fim': DateTime.now().toIso8601String(),
        'quilometragem_fim': kmFim,
        'quilometragem_percorrida': kmPerc,
        'status': 'concluida',
        'observacoes': obsCtrl.text,
      }).eq('id', widget.viagem['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Viagem concluída! ${kmPerc.toStringAsFixed(1)} km percorridos.')),
      );
      widget.onAtualizada();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao concluir viagem: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '--';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'em_progresso':
        return AppColors.info;
      case 'concluida':
        return AppColors.success;
      case 'cancelada':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viagem;
    final status = v['status']?.toString() ?? 'desconhecido';
    final kmPerc = (v['quilometragem_percorrida'] as num?)?.toDouble();

    InputDecoration field(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.secondary),
          ),
          filled: true,
          fillColor: AppColors.backgroundSoft,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalhe da Viagem'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${v['origem'] ?? '-'} → ${v['destino'] ?? '-'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Chip(
                        label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: _statusColor(status)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Veículo', widget.veiculoLabel),
                  _infoRow('Motorista', widget.motoristaLabel),
                  _infoRow('Início', _fmt(v['data_inicio']?.toString())),
                  _infoRow('KM Inicial',
                      '${(v['quilometragem_inicio'] as num?)?.toStringAsFixed(1) ?? '--'} km'),
                  if (kmPerc != null)
                    _infoRow('KM Percorrido', '${kmPerc.toStringAsFixed(1)} km',
                        color: AppColors.secondary),
                  if (v['data_fim'] != null) _infoRow('Fim', _fmt(v['data_fim']?.toString())),
                  if (v['observacoes'] != null && v['observacoes'].toString().isNotEmpty)
                    _infoRow('Observações', v['observacoes'].toString()),
                ],
              ),
            ),
            if (status == 'em_progresso') ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Concluir Viagem',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: kmFimCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: field('Quilometragem Final (KM) *', Icons.speed),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: obsCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: field('Observações', Icons.notes),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isLoading ? null : _concluir,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Concluir Viagem',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 14, color: color ?? Colors.white)),
        ],
      ),
    );
  }
}

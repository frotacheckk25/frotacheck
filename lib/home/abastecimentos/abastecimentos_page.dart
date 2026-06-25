import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';

class AbastecimentosPage extends StatefulWidget {
  const AbastecimentosPage({super.key});

  @override
  State<AbastecimentosPage> createState() => _AbastecimentosPageState();
}

class _AbastecimentosPageState extends State<AbastecimentosPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> fuelings = [];
  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> drivers = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  Future<void> carregarDados() async {
    setState(() => carregando = true);
    try {
      final results = await Future.wait([
        supabase
            .from('fuelings')
            .select('*, vehicles (plate, model), drivers (name)')
            .order('created_at', ascending: false)
            .limit(50),
        supabase.from('vehicles').select('id, plate, model').order('plate'),
        supabase.from('drivers').select('id, name').order('name'),
      ]);
      if (mounted) {
        setState(() {
          fuelings = List<Map<String, dynamic>>.from(results[0]);
          vehicles = List<Map<String, dynamic>>.from(results[1]);
          drivers = List<Map<String, dynamic>>.from(results[2]);
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar abastecimentos: $e');
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  void _abrirFormulario() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AbastecimentoForm(
        vehicles: vehicles,
        drivers: drivers,
        onSaved: () {
          Navigator.pop(ctx);
          carregarDados();
        },
      ),
    );
  }

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

  double _totalGasto() => fuelings.fold(0.0, (sum, f) {
        final v = f['total_value'];
        return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Abastecimentos'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        backgroundColor: AppColors.secondary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Novo Abastecimento', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: carregarDados,
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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFf59e0b), Color(0xFFef4444)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_gas_station, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Controle de Abastecimento',
                                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                                Text('${fuelings.length} registro(s) • ${_fmtValue(_totalGasto())} total',
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
                        _kpi('Registros', '${fuelings.length}', Icons.local_gas_station, AppColors.warning),
                        const SizedBox(width: 10),
                        _kpi('Total Gasto', _fmtValue(_totalGasto()), Icons.account_balance_wallet, AppColors.danger),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Histórico', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            if (carregando)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (fuelings.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_gas_station, size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      const Text('Nenhum abastecimento registrado',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _abrirFormulario,
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar Abastecimento'),
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
                      final f = fuelings[i];
                      final placa = f['vehicles']?['plate'] ?? '-';
                      final modelo = f['vehicles']?['model'] ?? '';
                      final motorista = f['drivers']?['name'] ?? '-';
                      final litros = f['liters'];
                      final valor = f['total_value'];
                      final odometro = f['odometer'];
                      final data = _fmtDate(f['fuel_date']?.toString() ?? f['created_at']?.toString());

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.local_gas_station, color: AppColors.warning, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(placa,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                        if (modelo.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text('— $modelo',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text('Motorista: $motorista',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _badge('${litros ?? '-'} L', AppColors.secondary),
                                        _badge(_fmtValue(valor), AppColors.success),
                                        if (odometro != null) _badge('$odometro km', AppColors.warning),
                                        _badge(data, AppColors.textSecondary),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: fuelings.length,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Text(value,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
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

// ─── Formulário de Abastecimento ─────────────────────────────────────────────

class _AbastecimentoForm extends StatefulWidget {
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> drivers;
  final VoidCallback onSaved;

  const _AbastecimentoForm({
    required this.vehicles,
    required this.drivers,
    required this.onSaved,
  });

  @override
  State<_AbastecimentoForm> createState() => _AbastecimentoFormState();
}

class _AbastecimentoFormState extends State<_AbastecimentoForm> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final picker = ImagePicker();
  bool isSaving = false;

  final litrosController = TextEditingController();
  final valorController = TextEditingController();
  final odometroController = TextEditingController();

  String? selectedVehicle;
  String? selectedDriver;

  XFile? odometroPhoto;
  XFile? pumpPhoto;
  XFile? receiptPhoto;

  @override
  void dispose() {
    litrosController.dispose();
    valorController.dispose();
    odometroController.dispose();
    super.dispose();
  }

  Future<XFile?> _pickImage() async {
    try {
      final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      if (img != null) return img;
    } catch (_) {}
    try {
      return await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _upload(XFile? img, String bucket) async {
    if (img == null) return null;
    try {
      final nome = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(img.path)}';
      final bytes = await img.readAsBytes();
      await supabase.storage
          .from(bucket)
          .uploadBinary(nome, bytes, fileOptions: const FileOptions(upsert: true));
      return supabase.storage.from(bucket).getPublicUrl(nome);
    } catch (e) {
      debugPrint('Erro no upload: $e');
      return null;
    }
  }

  Future<void> _salvar() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => isSaving = true);
    try {
      final odometroUrl = await _upload(odometroPhoto, 'fuelings');
      final bombaUrl = await _upload(pumpPhoto, 'fuelings');
      final cupomUrl = await _upload(receiptPhoto, 'fuelings');

      final payload = <String, dynamic>{
        'vehicle_id': selectedVehicle,
        'driver_id': selectedDriver,
        'fuel_date': DateTime.now().toIso8601String().split('T')[0],
        'liters': double.tryParse(litrosController.text.replaceAll(',', '.')) ?? 0,
        'total_value': double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0,
        'odometer': int.tryParse(odometroController.text) ?? 0,
      };

      if (odometroUrl != null) payload['odometer_photo'] = odometroUrl;
      if (bombaUrl != null) payload['pump_photo'] = bombaUrl;
      if (cupomUrl != null) payload['receipt_photo'] = cupomUrl;

      await supabase.from('fuelings').insert(payload);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
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
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Novo Abastecimento',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Veículo
              DropdownButtonFormField<String>(
                value: selectedVehicle,
                decoration: _dec('Veículo *', Icons.directions_car_outlined),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                items: widget.vehicles.map((v) => DropdownMenuItem(
                  value: v['id']?.toString(),
                  child: Text('${v['plate'] ?? ''} — ${v['model'] ?? ''}',
                      style: const TextStyle(color: Colors.white)),
                )).toList(),
                validator: (v) => v == null ? 'Selecione um veículo' : null,
                onChanged: (v) => setState(() => selectedVehicle = v),
              ),
              const SizedBox(height: 14),

              // Motorista
              DropdownButtonFormField<String>(
                value: selectedDriver,
                decoration: _dec('Motorista *', Icons.person_outline),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                items: widget.drivers.map((d) => DropdownMenuItem(
                  value: d['id']?.toString(),
                  child: Text(d['name'] ?? '', style: const TextStyle(color: Colors.white)),
                )).toList(),
                validator: (v) => v == null ? 'Selecione um motorista' : null,
                onChanged: (v) => setState(() => selectedDriver = v),
              ),
              const SizedBox(height: 14),

              // Litros
              TextFormField(
                controller: litrosController,
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Litros abastecidos *', Icons.water_drop_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe a quantidade de litros';
                  if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Valor Total
              TextFormField(
                controller: valorController,
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Valor total (R\$) *', Icons.attach_money),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o valor total';
                  if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Odômetro
              TextFormField(
                controller: odometroController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: _dec('Odômetro (km) *', Icons.speed_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o odômetro';
                  if (int.tryParse(v) == null) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Fotos
              const Text('Fotos (opcional)',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _fotoBtn('Hodômetro', Icons.speed, odometroPhoto, () async {
                    final f = await _pickImage();
                    if (f != null) setState(() => odometroPhoto = f);
                  })),
                  const SizedBox(width: 10),
                  Expanded(child: _fotoBtn('Bomba', Icons.local_gas_station, pumpPhoto, () async {
                    final f = await _pickImage();
                    if (f != null) setState(() => pumpPhoto = f);
                  })),
                  const SizedBox(width: 10),
                  Expanded(child: _fotoBtn('Cupom', Icons.receipt_long, receiptPhoto, () async {
                    final f = await _pickImage();
                    if (f != null) setState(() => receiptPhoto = f);
                  })),
                ],
              ),
              const SizedBox(height: 24),

              // Botão salvar
              ElevatedButton(
                onPressed: isSaving ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Salvar Abastecimento',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fotoBtn(String label, IconData icon, XFile? foto, VoidCallback onTap) {
    final ok = foto != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: ok ? AppColors.success.withOpacity(0.15) : AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ok ? AppColors.success : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(ok ? Icons.check_circle : icon,
                color: ok ? AppColors.success : AppColors.textSecondary, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  color: ok ? AppColors.success : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                )),
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
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.secondary)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger)),
  );
}

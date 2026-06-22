import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OcorrenciasPage extends StatefulWidget {
  const OcorrenciasPage({super.key});

  @override
  State<OcorrenciasPage> createState() => _OcorrenciasPageState();
}

class _OcorrenciasPageState extends State<OcorrenciasPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final descricaoController = TextEditingController();
  final locationController = TextEditingController();

  bool isSaving = false;
  List<Map<String, dynamic>> drivers = [];

  String? selectedDriver;
  String? selectedProblem;
  String? selectedPriority;
  String? selectedStatus = 'Aberto';

  final problemTypes = [
    'Motor',
    'Freios',
    'Pneu',
    'Suspensão',
    'Elétrica',
    'Ar Condicionado',
    'Lataria',
    'Outro',
  ];
  final priorities = ['Alta', 'Média', 'Baixa'];
  final statuses = ['Aberto', 'Em andamento', 'Resolvido'];

  @override
  void initState() {
    super.initState();
    carregarMotoristas();
  }

  static final List<Map<String, dynamic>> motoristasMock = [
    {'id': '1', 'name': 'João Silva'},
    {'id': '2', 'name': 'Maria Oliveira'},
  ];

  Future<void> carregarMotoristas() async {
    try {
      final response = await supabase
          .from('drivers')
          .select('id, name')
          .order('name');
      setState(() {
        drivers = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Erro ao carregar motoristas: $e - usando dados mock');
      setState(() {
        drivers = motoristasMock;
      });
    }
  }

  Future<void> salvarOcorrencia() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      isSaving = true;
    });

    try {
      await supabase.from('occurrences').insert({
        'driver_name': selectedDriver,
        'problem_type': selectedProblem,
        'problem': descricaoController.text.trim(),
        'priority': selectedPriority,
        'location': locationController.text.trim(),
        'status': selectedStatus,
        'created_at': DateTime.now().toIso8601String(),
      });

      descricaoController.clear();
      locationController.clear();
      setState(() {
        selectedDriver = null;
        selectedProblem = null;
        selectedPriority = null;
        selectedStatus = 'Aberto';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ocorrência registrada com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    descricaoController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF00B8D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Registro de ocorrências',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Cadastre e classifique problemas operacionais com prioridade e localização.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: items
          .map(
            (item) =>
                DropdownMenuItem<T>(value: item, child: Text(item.toString())),
          )
          .toList(),
      validator: (value) {
        if (value == null) return 'Selecione $label';
        return null;
      },
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Ocorrência')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDropdown<String>(
                        label: 'Motorista',
                        value: selectedDriver,
                        items: drivers
                            .map((driver) => driver['name']?.toString() ?? '')
                            .toList(),
                        onChanged: (value) =>
                            setState(() => selectedDriver = value),
                      ),
                      const SizedBox(height: 16),
                      _buildDropdown<String>(
                        label: 'Tipo de problema',
                        value: selectedProblem,
                        items: problemTypes,
                        onChanged: (value) =>
                            setState(() => selectedProblem = value),
                      ),
                      const SizedBox(height: 16),
                      _buildDropdown<String>(
                        label: 'Prioridade',
                        value: selectedPriority,
                        items: priorities,
                        onChanged: (value) =>
                            setState(() => selectedPriority = value),
                      ),
                      const SizedBox(height: 16),
                      _buildDropdown<String>(
                        label: 'Status inicial',
                        value: selectedStatus,
                        items: statuses,
                        onChanged: (value) =>
                            setState(() => selectedStatus = value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Localização',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe a localização';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descricaoController,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Descrição completa',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Descreva a ocorrência';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text('Salvar Ocorrência'),
                          onPressed: isSaving ? null : salvarOcorrencia,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

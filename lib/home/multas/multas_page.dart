import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/multa_model.dart';
import '../../core/models/veiculo_model.dart';
import '../../core/models/motorista_model.dart';
import '../../core/theme/app_theme.dart';

class MultasPage extends StatefulWidget {
  const MultasPage({super.key});

  @override
  State<MultasPage> createState() => _MultasPageState();
}

class _MultasPageState extends State<MultasPage> {
  final supabase = Supabase.instance.client;
  List<Multa> multas = [];
  List<Veiculo> veiculos = [];
  List<Motorista> motoristas = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      final multasResponse = await supabase
          .from('multas')
          .select()
          .order('data', ascending: false);

      final veiculosResponse = await supabase.from('veiculos').select();
      final motoristasResponse = await supabase.from('motoristas').select();

      if (!mounted) return;
      setState(() {
        multas = (multasResponse as List).isEmpty
            ? multasMock
            : (multasResponse)
                .map((e) => Multa.fromJson(e))
                .toList();
        veiculos = (veiculosResponse as List).isEmpty
            ? veiculosMock
            : (veiculosResponse)
                .map((e) => Veiculo.fromJson(e))
                .toList();
        motoristas = (motoristasResponse as List).isEmpty
            ? motoristasMock
            : (motoristasResponse)
                .map((e) => Motorista.fromJson(e))
                .toList();
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar multas: $e - usando dados mock');
      if (mounted) {
        setState(() {
          multas = multasMock;
          veiculos = veiculosMock;
          motoristas = motoristasMock;
          isLoading = false;
        });
      }
    }
  }

  static final List<Multa> multasMock = [
    Multa(
      id: '1',
      veiculoId: 'v1',
      motoristaId: 'm1',
      data: DateTime.now().subtract(const Duration(days: 10)),
      valor: 180.00,
      tipo: 'infraçao',
      descricao: 'Estacionamento proibido',
      status: 'aberta',
    ),
    Multa(
      id: '2',
      veiculoId: 'v2',
      motoristaId: 'm2',
      data: DateTime.now().subtract(const Duration(days: 5)),
      valor: 250.00,
      tipo: 'infraçao',
      descricao: 'Excesso de velocidade',
      status: 'paga',
    ),
  ];

  static final List<Veiculo> veiculosMock = [
    Veiculo(id: 'v1', placa: 'ABC-1234', modelo: 'Fiesta'),
    Veiculo(id: 'v2', placa: 'XYZ-9999', modelo: 'Civic'),
  ];

  static final List<Motorista> motoristasMock = [
    Motorista(id: 'm1', nome: 'João Silva'),
    Motorista(id: 'm2', nome: 'Maria Oliveira'),
  ];

  String _getNomeVeiculo(String? id) {
    if (id == null) return 'N/A';
    try {
      return veiculos.firstWhere((v) => v.id == id).placa ?? 'Desconhecido';
    } catch (e) {
      return 'Desconhecido';
    }
  }

  String _getNomeMotorista(String? id) {
    if (id == null) return 'N/A';
    try {
      return motoristas.firstWhere((m) => m.id == id).nome ?? 'Desconhecido';
    } catch (e) {
      return 'Desconhecido';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'aberta':
        return Colors.orange;
      case 'paga':
        return Colors.green;
      case 'contestada':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'aberta':
        return 'Aberta';
      case 'paga':
        return 'Paga';
      case 'contestada':
        return 'Contestada';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Multas'),
        backgroundColor: AppColors.primary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirNovaMulta(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : multas.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Nenhuma multa registrada'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _abrirNovaMulta(),
                    child: const Text('Registrar Multa'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: multas.length,
              itemBuilder: (context, index) {
                final multa = multas[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          multa.status,
                        ).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.receipt_long,
                        color: _getStatusColor(multa.status),
                      ),
                    ),
                    title: Text(_getNomeVeiculo(multa.veiculoId)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Motorista: ${_getNomeMotorista(multa.motoristaId)}',
                        ),
                        Text('Tipo: ${multa.tipo}'),
                        Text(
                          'Valor: R\$ ${multa.valor.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(_getStatusLabel(multa.status)),
                      backgroundColor: _getStatusColor(
                        multa.status,
                      ).withValues(alpha: 0.3),
                      labelStyle: TextStyle(
                        color: _getStatusColor(multa.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () => _abrirDetalheMulta(multa),
                  ),
                );
              },
            ),
    );
  }

  void _abrirNovaMulta() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NovaMultaPage(
          onMultaSalva: () {
            _carregarDados();
          },
        ),
      ),
    );
  }

  void _abrirDetalheMulta(Multa multa) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalheMultaPage(
          multa: multa,
          onMultaAtualizada: () {
            _carregarDados();
          },
        ),
      ),
    );
  }
}

class NovaMultaPage extends StatefulWidget {
  final VoidCallback onMultaSalva;

  const NovaMultaPage({required this.onMultaSalva, super.key});

  @override
  State<NovaMultaPage> createState() => _NovaMultaPageState();
}

class _NovaMultaPageState extends State<NovaMultaPage> {
  final supabase = Supabase.instance.client;
  final imagePicker = ImagePicker();

  String? veiculoSelecionado;
  String? motoristaSelecioando;
  String? tipoSelecionado;
  Uint8List? fotoBytes;
  bool isLoading = false;

  final valorkController = TextEditingController();
  final descricaoController = TextEditingController();
  final dataController = TextEditingController();

  List<Veiculo> veiculos = [];
  List<Motorista> motoristas = [];

  @override
  void initState() {
    super.initState();
    _carregarVeiculosMotoristas();
    dataController.text = DateTime.now().toString().split(' ')[0];
  }

  Future<void> _carregarVeiculosMotoristas() async {
    try {
      final veiculosResponse = await supabase.from('veiculos').select();
      final motoristasResponse = await supabase.from('motoristas').select();

      setState(() {
        veiculos = (veiculosResponse as List)
            .map((e) => Veiculo.fromJson(e as Map<String, dynamic>))
            .toList();
        motoristas = (motoristasResponse as List)
            .map((e) => Motorista.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
    }
  }

  Future<void> _selecionarFoto() async {
    final foto = await imagePicker.pickImage(source: ImageSource.camera);
    if (foto != null) {
      final bytes = await foto.readAsBytes();
      if (!mounted) return;
      setState(() {
        fotoBytes = bytes;
      });
    }
  }

  Future<void> _salvarMulta() async {
    if (veiculoSelecionado == null ||
        tipoSelecionado == null ||
        valorkController.text.isEmpty ||
        descricaoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      String? fotoUrl;
      if (fotoBytes != null) {
        final fileName = 'multa_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage
            .from('multas')
            .uploadBinary(
              fileName,
              fotoBytes!,
              fileOptions: const FileOptions(upsert: true),
            );
        fotoUrl = supabase.storage.from('multas').getPublicUrl(fileName);
      }

      final multaData = {
        'veiculo_id': veiculoSelecionado,
        'motorista_id': motoristaSelecioando,
        'data': dataController.text,
        'valor': double.parse(valorkController.text),
        'tipo': tipoSelecionado,
        'descricao': descricaoController.text,
        'foto_url': fotoUrl,
        'status': 'aberta',
        'criado_em': DateTime.now().toIso8601String(),
      };

      await supabase.from('multas').insert(multaData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Multa registrada com sucesso!')),
      );

      widget.onMultaSalva();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar multa: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    valorkController.dispose();
    descricaoController.dispose();
    dataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Multa'),
        backgroundColor: AppColors.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Veículo
            DropdownButtonFormField<String>(
              initialValue: veiculoSelecionado,
              decoration: InputDecoration(
                labelText: 'Veículo *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.directions_car),
              ),
              items: veiculos
                  .map(
                    (v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.placa ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => veiculoSelecionado = value);
              },
            ),
            const SizedBox(height: 16),

            // Motorista
            DropdownButtonFormField<String>(
              initialValue: motoristaSelecioando,
              decoration: InputDecoration(
                labelText: 'Motorista (Opcional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.person),
              ),
              items: motoristas
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(m.nome ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => motoristaSelecioando = value);
              },
            ),
            const SizedBox(height: 16),

            // Data
            TextField(
              controller: dataController,
              decoration: InputDecoration(
                labelText: 'Data da Multa',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),

            // Tipo
            DropdownButtonFormField<String>(
              initialValue: tipoSelecionado,
              decoration: InputDecoration(
                labelText: 'Tipo de Multa *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'infraçao', child: Text('Infração')),
                DropdownMenuItem(value: 'juizado', child: Text('Juizado')),
              ],
              onChanged: (value) {
                setState(() => tipoSelecionado = value);
              },
            ),
            const SizedBox(height: 16),

            // Valor
            TextField(
              controller: valorkController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Valor da Multa (R\$) *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.attach_money),
              ),
            ),
            const SizedBox(height: 16),

            // Descrição
            TextField(
              controller: descricaoController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Descrição da Multa *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText:
                    'Ex: Estacionamento proibido, excesso de velocidade...',
              ),
            ),
            const SizedBox(height: 16),

            // Foto
            if (fotoBytes != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Image.memory(fotoBytes!, height: 200, fit: BoxFit.cover),
              ),
            ElevatedButton.icon(
              onPressed: _selecionarFoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(fotoBytes != null ? 'Trocar Foto' : 'Adicionar Foto'),
            ),
            const SizedBox(height: 24),

            // Botão Salvar
            ElevatedButton(
              onPressed: isLoading ? null : _salvarMulta,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Registrar Multa'),
            ),
          ],
        ),
      ),
    );
  }
}

class DetalheMultaPage extends StatefulWidget {
  final Multa multa;
  final VoidCallback onMultaAtualizada;

  const DetalheMultaPage({
    required this.multa,
    required this.onMultaAtualizada,
    super.key,
  });

  @override
  State<DetalheMultaPage> createState() => _DetalheMultaPageState();
}

class _DetalheMultaPageState extends State<DetalheMultaPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  Future<void> _marcarComoPaga() async {
    final confirmacao = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como Paga?'),
        content: const Text('Deseja realmente marcar esta multa como paga?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmacao != true) return;
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      await supabase
          .from('multas')
          .update({
            'status': 'paga',
            'data_pagamento': DateTime.now().toIso8601String(),
            'atualizado_em': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.multa.id);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Multa marcada como paga!')));

      widget.onMultaAtualizada();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhe da Multa'),
        backgroundColor: AppColors.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Status',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Chip(
                        label: Text(widget.multa.status.toUpperCase()),
                        backgroundColor: Colors.orange.withOpacity(0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Valor',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    'R\$ ${widget.multa.valor.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tipo',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(widget.multa.tipo, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  const Text(
                    'Descrição',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    widget.multa.descricao,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (widget.multa.fotoUrl != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Foto',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Image.network(
                      widget.multa.fotoUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (widget.multa.status != 'paga')
              ElevatedButton(
                onPressed: isLoading ? null : _marcarComoPaga,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Marcar como Paga'),
              ),
          ],
        ),
      ),
    );
  }
}

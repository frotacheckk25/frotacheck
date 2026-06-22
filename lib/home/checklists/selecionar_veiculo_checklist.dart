import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/veiculo_model.dart';
import '../../core/models/motorista_model.dart';
import '../../core/theme/app_theme.dart';
import './checklist_saida_page.dart';
import './checklist_retorno_page.dart';

class SelecionarVeiculoChecklistPage extends StatefulWidget {
  const SelecionarVeiculoChecklistPage({super.key});

  @override
  State<SelecionarVeiculoChecklistPage> createState() =>
      _SelecionarVeiculoChecklistPageState();
}

class _SelecionarVeiculoChecklistPageState
    extends State<SelecionarVeiculoChecklistPage> {
  final supabase = Supabase.instance.client;
  List<Veiculo> veiculos = [];
  List<Motorista> motoristas = [];
  bool isLoading = true;
  String? veiculoSelecionado;
  String? motoristaSelecioando;
  String tipoChecklist = 'saida';

  static final List<Veiculo> veiculosMock = [
    Veiculo(id: '1', placa: 'ABC-1234', modelo: 'Fiesta'),
    Veiculo(id: '2', placa: 'XYZ-9999', modelo: 'Civic'),
  ];

  static final List<Motorista> motoristasMock = [
    Motorista(id: '1', nome: 'João Silva'),
    Motorista(id: '2', nome: 'Maria Oliveira'),
  ];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      final veiculosResponse = await supabase.from('veiculos').select();
      final motoristasResponse = await supabase.from('motoristas').select();

      if (!mounted) return;
      setState(() {
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e - usando dados mock')));
      }
      if (mounted) {
        setState(() {
          veiculos = veiculosMock;
          motoristas = motoristasMock;
          isLoading = false;
        });
      }
    }
  }

  Future<void> _iniciarChecklist() async {
    if (veiculoSelecionado == null || motoristaSelecioando == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um veículo e motorista')),
      );
      return;
    }

    final veiculo = veiculos.firstWhere((v) => v.id == veiculoSelecionado);

    if (!mounted) return;

    if (tipoChecklist == 'saida') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChecklistSaidaPage(
            veiculoId: veiculoSelecionado!,
            veiculoPlaca: veiculo.placa ?? '',
            motoristaId: motoristaSelecioando!,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChecklistRetornoPage(
            veiculoId: veiculoSelecionado!,
            veiculoPlaca: veiculo.placa ?? '',
            motoristaId: motoristaSelecioando!,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleção de Veículo - Checklist'),
        backgroundColor: AppColors.primary,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tipo de Checklist
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
                        const Text(
                          'Tipo de Checklist',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Saída'),
                                value: 'saida',
                                groupValue: tipoChecklist,
                                onChanged: (value) {
                                  setState(
                                    () => tipoChecklist = value ?? 'saida',
                                  );
                                },
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Retorno'),
                                value: 'retorno',
                                groupValue: tipoChecklist,
                                onChanged: (value) {
                                  setState(
                                    () => tipoChecklist = value ?? 'saida',
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Veículo
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
                        const Text(
                          'Selecionar Veículo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(v.placa ?? ''),
                                      Text(
                                        v.modelo ?? '',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => veiculoSelecionado = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Motorista
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
                        const Text(
                          'Selecionar Motorista',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: motoristaSelecioando,
                          decoration: InputDecoration(
                            labelText: 'Motorista *',
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Botão Iniciar
                  ElevatedButton(
                    onPressed: _iniciarChecklist,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Iniciar Checklist',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/viagem_model.dart';
import '../../core/models/veiculo_model.dart';
import '../../core/models/motorista_model.dart';
import '../../core/theme/app_theme.dart';

class ViagensPage extends StatefulWidget {
  const ViagensPage({super.key});

  @override
  State<ViagensPage> createState() => _ViagensPageState();
}

class _ViagensPageState extends State<ViagensPage> {
  final supabase = Supabase.instance.client;
  List<Viagem> viagens = [];
  List<Veiculo> veiculos = [];
  List<Motorista> motoristas = [];
  bool isLoading = true;
  String filtroStatus = 'todas';

  static final List<Viagem> viagensMock = [
    Viagem(
      id: 'v1',
      veiculoId: '1',
      motoristaId: '1',
      origem: 'São Paulo',
      destino: 'Rio de Janeiro',
      quilometragemInicio: 50000,
      dataInicio: DateTime.now().subtract(const Duration(days: 2)),
      status: 'em_progresso',
      fotosRota: [],
    ),
    Viagem(
      id: 'v2',
      veiculoId: '2',
      motoristaId: '2',
      origem: 'Curitiba',
      destino: 'Florianópolis',
      quilometragemInicio: 30000,
      dataInicio: DateTime.now().subtract(const Duration(days: 5)),
      status: 'concluida',
      fotosRota: [],
    ),
  ];

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
      final viagensResponse = await supabase
          .from('viagens')
          .select()
          .order('data_inicio', ascending: false);

      final veiculosResponse = await supabase.from('veiculos').select();
      final motoristasResponse = await supabase.from('motoristas').select();

      if (!mounted) return;
      setState(() {
        viagens = (viagensResponse as List).isEmpty
            ? viagensMock
            : (viagensResponse)
                .map((e) => Viagem.fromJson(e))
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar viagens: $e - usando dados mock')));
      }
      if (mounted) {
        setState(() {
          viagens = viagensMock;
          veiculos = veiculosMock;
          motoristas = motoristasMock;
          isLoading = false;
        });
      }
    }
  }

  List<Viagem> _aplicarFiltro() {
    if (filtroStatus == 'todas') {
      return viagens;
    }
    return viagens.where((v) => v.status == filtroStatus).toList();
  }

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
      case 'em_progresso':
        return Colors.blue;
      case 'concluida':
        return Colors.green;
      case 'cancelada':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
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
    final viagensFiltradas = _aplicarFiltro();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Viagens'),
        backgroundColor: AppColors.primary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirNovaViagem(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtros
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildFilterChip('Todas', 'todas'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Em Progresso', 'em_progresso'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Concluídas', 'concluida'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Canceladas', 'cancelada'),
                    ],
                  ),
                ),

                // Lista de viagens
                Expanded(
                  child: viagensFiltradas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.directions,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text('Nenhuma viagem encontrada'),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () => _abrirNovaViagem(),
                                child: const Text('Registrar Viagem'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: viagensFiltradas.length,
                          itemBuilder: (context, index) {
                            final viagem = viagensFiltradas[index];
                            return _buildViagemCard(viagem);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return FilterChip(
      label: Text(label),
      selected: filtroStatus == value,
      onSelected: (selected) {
        setState(() => filtroStatus = value);
      },
      selectedColor: AppColors.primary,
    );
  }

  Widget _buildViagemCard(Viagem viagem) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getStatusColor(viagem.status).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.directions, color: _getStatusColor(viagem.status)),
        ),
        title: Text(
          '${viagem.origem} → ${viagem.destino}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Veículo: ${_getNomeVeiculo(viagem.veiculoId)}'),
            Text('Motorista: ${_getNomeMotorista(viagem.motoristaId)}'),
            if (viagem.quilometragemPercorrida != null)
              Text(
                'KM: ${viagem.quilometragemPercorrida!.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        trailing: Chip(
          label: Text(_getStatusLabel(viagem.status)),
          backgroundColor: _getStatusColor(
            viagem.status,
          ).withValues(alpha: 0.3),
          labelStyle: TextStyle(
            color: _getStatusColor(viagem.status),
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () => _abrirDetalheViagem(viagem),
      ),
    );
  }

  void _abrirNovaViagem() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NovaViagemPage(
          veiculos: veiculos,
          motoristas: motoristas,
          onViagemSalva: () => _carregarDados(),
        ),
      ),
    );
  }

  void _abrirDetalheViagem(Viagem viagem) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalheViagemPage(
          viagem: viagem,
          nomeVeiculo: _getNomeVeiculo(viagem.veiculoId),
          nomeMotorista: _getNomeMotorista(viagem.motoristaId),
          onViagemAtualizada: () => _carregarDados(),
        ),
      ),
    );
  }
}

class NovaViagemPage extends StatefulWidget {
  final List<Veiculo> veiculos;
  final List<Motorista> motoristas;
  final VoidCallback onViagemSalva;

  const NovaViagemPage({
    required this.veiculos,
    required this.motoristas,
    required this.onViagemSalva,
    super.key,
  });

  @override
  State<NovaViagemPage> createState() => _NovaViagemPageState();
}

class _NovaViagemPageState extends State<NovaViagemPage> {
  final supabase = Supabase.instance.client;

  String? veiculoSelecionado;
  String? motoristaSelecioando;
  bool isLoading = false;

  final origemController = TextEditingController();
  final destinoController = TextEditingController();
  final quilometragemInicioController = TextEditingController();

  @override
  void dispose() {
    origemController.dispose();
    destinoController.dispose();
    quilometragemInicioController.dispose();
    super.dispose();
  }

  Future<void> _salvarViagem() async {
    if (veiculoSelecionado == null ||
        motoristaSelecioando == null ||
        origemController.text.isEmpty ||
        destinoController.text.isEmpty ||
        quilometragemInicioController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final viagemData = {
        'veiculo_id': veiculoSelecionado,
        'motorista_id': motoristaSelecioando,
        'data_inicio': DateTime.now().toIso8601String(),
        'origem': origemController.text,
        'destino': destinoController.text,
        'quilometragem_inicio': double.parse(
          quilometragemInicioController.text,
        ),
        'status': 'em_progresso',
        'fotos_rota': [],
        'criado_em': DateTime.now().toIso8601String(),
      };

      await supabase.from('viagens').insert(viagemData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viagem iniciada com sucesso!')),
      );

      widget.onViagemSalva();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar viagem: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Viagem'),
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
              items: widget.veiculos
                  .map(
                    (v) => DropdownMenuItem(
                      value: v.id ?? '',
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
                labelText: 'Motorista *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.person),
              ),
              items: widget.motoristas
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id ?? '',
                      child: Text(m.nome ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => motoristaSelecioando = value);
              },
            ),
            const SizedBox(height: 16),

            // Origem
            TextField(
              controller: origemController,
              decoration: InputDecoration(
                labelText: 'Origem *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 16),

            // Destino
            TextField(
              controller: destinoController,
              decoration: InputDecoration(
                labelText: 'Destino *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 16),

            // Quilometragem Inicial
            TextField(
              controller: quilometragemInicioController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quilometragem Inicial (KM) *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.speed),
              ),
            ),
            const SizedBox(height: 24),

            // Botão Salvar
            ElevatedButton(
              onPressed: isLoading ? null : _salvarViagem,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Iniciar Viagem'),
            ),
          ],
        ),
      ),
    );
  }
}

class DetalheViagemPage extends StatefulWidget {
  final Viagem viagem;
  final String nomeVeiculo;
  final String nomeMotorista;
  final VoidCallback onViagemAtualizada;

  const DetalheViagemPage({
    required this.viagem,
    required this.nomeVeiculo,
    required this.nomeMotorista,
    required this.onViagemAtualizada,
    super.key,
  });

  @override
  State<DetalheViagemPage> createState() => _DetalheViagemPageState();
}

class _DetalheViagemPageState extends State<DetalheViagemPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  final quilometragemFimController = TextEditingController();
  final observacoesController = TextEditingController();

  @override
  void dispose() {
    quilometragemFimController.dispose();
    observacoesController.dispose();
    super.dispose();
  }

  Future<void> _concluirViagem() async {
    if (quilometragemFimController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a quilometragem final')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final quilometragemFim = double.parse(quilometragemFimController.text);
      final quilometragemPercorrida =
          quilometragemFim - widget.viagem.quilometragemInicio;

      await supabase
          .from('viagens')
          .update({
            'data_fim': DateTime.now().toIso8601String(),
            'quilometragem_fim': quilometragemFim,
            'status': 'concluida',
            'observacoes': observacoesController.text,
            'atualizado_em': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.viagem.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Viagem concluída! $quilometragemPercorrida km percorridos.',
          ),
        ),
      );

      widget.onViagemAtualizada();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao concluir viagem: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhe da Viagem'),
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
                      Text(
                        '${widget.viagem.origem} → ${widget.viagem.destino}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Chip(
                        label: Text(widget.viagem.status.toUpperCase()),
                        backgroundColor: Colors.blue.withOpacity(0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfo('Veículo', widget.nomeVeiculo),
                  _buildInfo('Motorista', widget.nomeMotorista),
                  _buildInfo(
                    'Início',
                    widget.viagem.dataInicio.toString().split('.')[0],
                  ),
                  _buildInfo(
                    'KM Inicial',
                    '${widget.viagem.quilometragemInicio.toStringAsFixed(1)} km',
                  ),
                  if (widget.viagem.quilometragemPercorrida != null)
                    _buildInfo(
                      'KM Percorrido',
                      '${widget.viagem.quilometragemPercorrida!.toStringAsFixed(1)} km',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (widget.viagem.status == 'em_progresso') ...[
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: quilometragemFimController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quilometragem Final (KM) *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: Icon(Icons.speed),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: observacoesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Observações',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isLoading ? null : _concluirViagem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Concluir Viagem'),
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

  Widget _buildInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
      ],
    );
  }
}

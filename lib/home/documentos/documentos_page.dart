import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/documento_model.dart';
import '../../core/models/veiculo_model.dart';
import '../../core/models/motorista_model.dart';
import '../../core/theme/app_theme.dart';

class DocumentosPage extends StatefulWidget {
  const DocumentosPage({super.key});

  @override
  State<DocumentosPage> createState() => _DocumentosPageState();
}

class _DocumentosPageState extends State<DocumentosPage> {
  final supabase = Supabase.instance.client;
  List<Documento> documentos = [];
  List<Veiculo> veiculos = [];
  List<Motorista> motoristas = [];
  bool isLoading = true;
  String filtroSelecionado = 'todos';

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  static final List<Documento> documentosMock = [
    Documento(
      id: '1',
      tipo: 'Seguro',
      veiculoId: '1',
      descricao: 'Apólice anual do veículo',
      fileUrl: 'https://example.com/seguro.pdf',
      dataVencimento: DateTime.now().add(const Duration(days: 30)),
      dataPagamento: DateTime.now(),
      ativo: true,
    ),
    Documento(
      id: '2',
      tipo: 'CRLV',
      motoristaId: '1',
      descricao: 'Certificado de registro',
      fileUrl: 'https://example.com/crlv.pdf',
      dataVencimento: DateTime.now().add(const Duration(days: 60)),
      dataPagamento: DateTime.now(),
      ativo: true,
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

  Future<void> _carregarDados() async {
    try {
      final docsResponse = await supabase
          .from('documentos')
          .select()
          .order('data_vencimento', ascending: true);

      final veiculosResponse = await supabase.from('veiculos').select();
      final motoristasResponse = await supabase.from('motoristas').select();

      if (!mounted) return;
      setState(() {
        documentos = (docsResponse as List).isEmpty
            ? documentosMock
            : (docsResponse)
                .map((e) => Documento.fromJson(e))
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar documentos: $e - usando dados mock')),
        );
      }
      if (mounted) {
        setState(() {
          documentos = documentosMock;
          veiculos = veiculosMock;
          motoristas = motoristasMock;
          isLoading = false;
        });
      }
    }
  }

  List<Documento> _aplicarFiltro() {
    switch (filtroSelecionado) {
      case 'vencidos':
        return documentos.where((d) => d.vencido).toList();
      case 'vencer_30':
        return documentos
            .where((d) => d.vencidoEm30Dias && !d.vencido)
            .toList();
      case 'ativos':
        return documentos
            .where((d) => !d.vencido && !d.vencidoEm30Dias)
            .toList();
      default:
        return documentos;
    }
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

  Color _getStatusColor(Documento doc) {
    if (doc.vencido) return Colors.red;
    if (doc.vencidoEm30Dias) return Colors.orange;
    return Colors.green;
  }

  String _getStatusLabel(Documento doc) {
    if (doc.vencido) return 'Vencido';
    if (doc.vencidoEm30Dias) {
      final dias = doc.dataVencimento.difference(DateTime.now()).inDays;
      return 'Vence em $dias dias';
    }
    return 'Ativo';
  }

  @override
  Widget build(BuildContext context) {
    final documentosFiltrados = _aplicarFiltro();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Documentos'),
        backgroundColor: AppColors.primary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirNovoDocumento(),
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
                      _buildFilterChip('Todos', 'todos'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Vencidos', 'vencidos'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Vencer em 30 dias', 'vencer_30'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Ativos', 'ativos'),
                    ],
                  ),
                ),

                // Lista de documentos
                Expanded(
                  child: documentosFiltrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.description,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text('Nenhum documento encontrado'),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () => _abrirNovoDocumento(),
                                child: const Text('Adicionar Documento'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: documentosFiltrados.length,
                          itemBuilder: (context, index) {
                            final doc = documentosFiltrados[index];
                            return _buildDocumentoCard(doc);
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
      selected: filtroSelecionado == value,
      onSelected: (selected) {
        setState(() => filtroSelecionado = value);
      },
      selectedColor: AppColors.primary,
    );
  }

  Widget _buildDocumentoCard(Documento doc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getStatusColor(doc).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.description, color: _getStatusColor(doc)),
        ),
        title: Text(
          doc.tipo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Descrição: ${doc.descricao}'),
            if (doc.veiculoId != null)
              Text('Veículo: ${_getNomeVeiculo(doc.veiculoId!)}'),
            if (doc.motoristaId != null)
              Text('Motorista: ${_getNomeMotorista(doc.motoristaId)}'),
            Text(
              'Vence em: ${doc.dataVencimento.toString().split(' ')[0]}',
              style: TextStyle(
                color: _getStatusColor(doc),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        trailing: Chip(
          label: Text(_getStatusLabel(doc)),
          backgroundColor: _getStatusColor(doc).withValues(alpha: 0.3),
          labelStyle: TextStyle(
            color: _getStatusColor(doc),
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () => _abrirDetalheDocumento(doc),
      ),
    );
  }

  void _abrirNovoDocumento() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NovoDocumentoPage(
          veiculos: veiculos,
          motoristas: motoristas,
          onDocumentoSalvo: () => _carregarDados(),
        ),
      ),
    );
  }

  void _abrirDetalheDocumento(Documento doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalheDocumentoPage(
          documento: doc,
          onDocumentoAtualizado: () => _carregarDados(),
        ),
      ),
    );
  }
}

class NovoDocumentoPage extends StatefulWidget {
  final List<Veiculo> veiculos;
  final List<Motorista> motoristas;
  final VoidCallback onDocumentoSalvo;

  const NovoDocumentoPage({
    required this.veiculos,
    required this.motoristas,
    required this.onDocumentoSalvo,
    super.key,
  });

  @override
  State<NovoDocumentoPage> createState() => _NovoDocumentoPageState();
}

class _NovoDocumentoPageState extends State<NovoDocumentoPage> {
  final supabase = Supabase.instance.client;

  String? tipoSelecionado;
  String? veiculoSelecionado;
  String? motoristaSelecioando;
  PlatformFile? arquivoSelecionado;
  bool isLoading = false;

  final descricaoController = TextEditingController();
  final dataVencimentoController = TextEditingController();
  final dataPagamentoController = TextEditingController();

  final tiposDocumento = [
    'CRLV',
    'Licenciamento',
    'Seguro',
    'CNH_Frente',
    'CNH_Verso',
    'Certificado',
    'Outra',
  ];

  @override
  void initState() {
    super.initState();
    dataPagamentoController.text = DateTime.now().toString().split(' ')[0];
    dataVencimentoController.text = DateTime.now()
        .add(const Duration(days: 365))
        .toString()
        .split(' ')[0];
  }

  Future<void> _selecionarArquivo() async {
    final resultado = await FilePicker.platform.pickFiles(withData: true);
    if (resultado != null && resultado.files.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        arquivoSelecionado = resultado.files.single;
      });
    }
  }

  Future<void> _salvarDocumento() async {
    if (tipoSelecionado == null ||
        (veiculoSelecionado == null && motoristaSelecioando == null) ||
        arquivoSelecionado == null ||
        descricaoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Upload de arquivo
      final fileName = 'documento_${DateTime.now().millisecondsSinceEpoch}';
      await supabase.storage
          .from('documentos')
          .uploadBinary(
            fileName,
            arquivoSelecionado!.bytes!,
            fileOptions: const FileOptions(upsert: true),
          );
      final fileUrl = supabase.storage
          .from('documentos')
          .getPublicUrl(fileName);

      final docData = {
        'tipo': tipoSelecionado,
        'veiculo_id': veiculoSelecionado,
        'motorista_id': motoristaSelecioando,
        'descricao': descricaoController.text,
        'file_url': fileUrl,
        'data_vencimento': dataVencimentoController.text,
        'data_pagamento': dataPagamentoController.text,
        'ativo': true,
        'criado_em': DateTime.now().toIso8601String(),
      };

      await supabase.from('documentos').insert(docData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento registrado com sucesso!')),
      );

      widget.onDocumentoSalvo();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar documento: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    descricaoController.dispose();
    dataVencimentoController.dispose();
    dataPagamentoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Documento'),
        backgroundColor: AppColors.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tipo
            DropdownButtonFormField<String>(
              initialValue: tipoSelecionado,
              decoration: InputDecoration(
                labelText: 'Tipo de Documento *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: tiposDocumento
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (value) {
                setState(() => tipoSelecionado = value);
              },
            ),
            const SizedBox(height: 16),

            // Veículo
            DropdownButtonFormField<String>(
              initialValue: veiculoSelecionado,
              decoration: InputDecoration(
                labelText: 'Veículo (Opcional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.directions_car),
              ),
              items: widget.veiculos
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
              items: widget.motoristas
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

            // Descrição
            TextField(
              controller: descricaoController,
              decoration: InputDecoration(
                labelText: 'Descrição *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Data de Pagamento
            TextField(
              controller: dataPagamentoController,
              decoration: InputDecoration(
                labelText: 'Data de Pagamento',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),

            // Data de Vencimento
            TextField(
              controller: dataVencimentoController,
              decoration: InputDecoration(
                labelText: 'Data de Vencimento *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),

            // Seletor de arquivo
            if (arquivoSelecionado != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(child: Text(arquivoSelecionado!.name)),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.file_present, color: Colors.grey),
                    SizedBox(width: 12),
                    Text('Nenhum arquivo selecionado'),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _selecionarArquivo,
              icon: const Icon(Icons.attach_file),
              label: const Text('Selecionar Arquivo'),
            ),
            const SizedBox(height: 24),

            // Botão Salvar
            ElevatedButton(
              onPressed: isLoading ? null : _salvarDocumento,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Registrar Documento'),
            ),
          ],
        ),
      ),
    );
  }
}

class DetalheDocumentoPage extends StatefulWidget {
  final Documento documento;
  final VoidCallback onDocumentoAtualizado;

  const DetalheDocumentoPage({
    required this.documento,
    required this.onDocumentoAtualizado,
    super.key,
  });

  @override
  State<DetalheDocumentoPage> createState() => _DetalheDocumentoPageState();
}

class _DetalheDocumentoPageState extends State<DetalheDocumentoPage> {
  final supabase = Supabase.instance.client;

  Future<void> _deletarDocumento() async {
    final confirmacao = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Documento?'),
        content: const Text('Deseja realmente deletar este documento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirmacao != true) return;

    try {
      await supabase.from('documentos').delete().eq('id', widget.documento.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento deletado com sucesso!')),
      );

      widget.onDocumentoAtualizado();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao deletar documento: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhe do Documento'),
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
                  Text(
                    widget.documento.tipo,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Descrição',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(widget.documento.descricao),
                  const SizedBox(height: 16),
                  const Text(
                    'Vencimento',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    widget.documento.dataVencimento.toString().split(' ')[0],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Visualizar arquivo (ambiente de teste)')),
                      );
                    },
                    child: const Text('Visualizar Arquivo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _deletarDocumento,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Deletar Documento'),
            ),
          ],
        ),
      ),
    );
  }
}

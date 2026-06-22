import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// IMPORT DA SUA TELA DE DETALHES
import 'detalhe_ocorrencia_page.dart';

class ListaOcorrenciasPage extends StatefulWidget {
  const ListaOcorrenciasPage({super.key});

  @override
  State<ListaOcorrenciasPage> createState() => _ListaOcorrenciasPageState();
}

class _ListaOcorrenciasPageState extends State<ListaOcorrenciasPage> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<dynamic> ocorrencias = [];
  bool carregando = true;
  String statusFiltro = 'Todos';

  final List<dynamic> ocorrenciasMock = [
    {
      'id': '1',
      'driver_name': 'João Silva',
      'problem_type': 'Mecânica',
      'problem': 'Problema no freio dianteiro',
      'location': 'Rua das Flores, 123',
      'status': 'Aberto',
      'priority': 'Alta',
      'created_at': '2024-02-10',
    },
    {
      'id': '2',
      'driver_name': 'Maria Oliveira',
      'problem_type': 'Elétrica',
      'problem': 'Lanterna traseira queimada',
      'location': 'Av. Brasil, 456',
      'status': 'Em andamento',
      'priority': 'Média',
      'created_at': '2024-02-09',
    },
    {
      'id': '3',
      'driver_name': 'Carlos Souza',
      'problem_type': 'Pneu',
      'problem': 'Pneu traseiro furado',
      'location': 'Rod. Anhanguera',
      'status': 'Resolvido',
      'priority': 'Baixa',
      'created_at': '2024-02-08',
    },
  ];

  @override
  void initState() {
    super.initState();
    carregarOcorrencias();
  }

  Future<void> carregarOcorrencias() async {
    setState(() {
      carregando = true;
    });

    try {
      final response = await supabase
          .from('occurrences')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        ocorrencias = response;
      });
    } catch (e) {
      debugPrint('Erro ao carregar ocorrências: $e - usando dados mock');
      setState(() {
        ocorrencias = ocorrenciasMock;
      });
    } finally {
      setState(() {
        carregando = false;
      });
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'Resolvido':
        return Colors.green;
      case 'Em andamento':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  List<dynamic> get filteredOccorrencias {
    var filtered = ocorrencias;
    final query = searchController.text.toLowerCase();

    if (statusFiltro != 'Todos') {
      filtered = filtered
          .where((item) => item['status'] == statusFiltro)
          .toList();
    }

    if (query.isNotEmpty) {
      filtered = filtered.where((item) {
        final text =
            '${item['driver_name'] ?? ''} ${item['problem_type'] ?? ''} ${item['problem'] ?? ''} ${item['location'] ?? ''}'
                .toLowerCase();
        return text.contains(query);
      }).toList();
    }

    return filtered;
  }

  int countStatus(String status) {
    return ocorrencias.where((item) => item['status'] == status).length;
  }

  Widget _buildStatusChip(String label) {
    final selected = statusFiltro == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        if (value) {
          setState(() {
            statusFiltro = label;
          });
        }
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12), // ignore: deprecated_member_use
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.85), // ignore: deprecated_member_use
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de Ocorrências')),
      body: RefreshIndicator(
        onRefresh: carregarOcorrencias,
        child: carregando
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _buildStatCard(
                          'Abertas',
                          countStatus('Aberto').toString(),
                          Colors.red,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Em andamento',
                          countStatus('Em andamento').toString(),
                          Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Resolvidas',
                          countStatus('Resolvido').toString(),
                          Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por motorista, problema ou local',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildStatusChip('Todos'),
                        _buildStatusChip('Aberto'),
                        _buildStatusChip('Em andamento'),
                        _buildStatusChip('Resolvido'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: filteredOccorrencias.isEmpty
                          ? const Center(
                              child: Text('Nenhuma ocorrência encontrada.'),
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: filteredOccorrencias.length,
                              separatorBuilder: (context, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = filteredOccorrencias[index];
                                return Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DetalheOcorrenciaPage(
                                            ocorrencia: item,
                                          ),
                                        ),
                                      );
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: getStatusColor(
                                        item['status'] ?? 'Aberto',
                                      ).withValues(alpha: 0.18),
                                      child: Icon(
                                        Icons.report_problem,
                                        color: getStatusColor(
                                          item['status'] ?? 'Aberto',
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      item['driver_name'] ?? 'Sem motorista',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 6),
                                        Text(
                                          'Problema: ${item['problem_type'] ?? '--'}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item['problem'] ?? '--',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Local: ${item['location'] ?? '--'}',
                                        ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Chip(
                                          backgroundColor: getStatusColor(
                                            item['status'] ?? 'Aberto',
                                          ),
                                          label: Text(
                                            item['status'] ?? 'Aberto',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final futurosStatus =
                                                item['status'] == 'Aberto'
                                                ? 'Em andamento'
                                                : item['status'] ==
                                                      'Em andamento'
                                                ? 'Resolvido'
                                                : 'Aberto';
                                            await supabase
                                                .from('occurrences')
                                                .update({
                                                  'status': futurosStatus,
                                                })
                                                .eq('id', item['id']);
                                            carregarOcorrencias();
                                          },
                                          child: const Text('Próx.'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

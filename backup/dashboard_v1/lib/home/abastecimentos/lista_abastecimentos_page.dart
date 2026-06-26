import 'package:flutter/material.dart';
import 'package:frotacheck/home/abastecimentos/detalhe_abastecimento_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ListaAbastecimentosPage extends StatefulWidget {
  const ListaAbastecimentosPage({super.key});

  @override
  State<ListaAbastecimentosPage> createState() =>
      _ListaAbastecimentosPageState();
}

class _ListaAbastecimentosPageState extends State<ListaAbastecimentosPage> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<dynamic> abastecimentos = [];
  bool carregando = true;
  String periodoFiltro = 'Este mês';

  @override
  void initState() {
    super.initState();
    carregarAbastecimentos();
  }

  Future<void> carregarAbastecimentos() async {
    setState(() {
      carregando = true;
    });

    try {
      final dados = await supabase
          .from('fuelings')
          .select('''
            *,
            vehicles (
              plate
            ),
            drivers (
              name
            )
          ''')
          .order('created_at', ascending: false);

      setState(() {
        abastecimentos = dados;
      });
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() {
        carregando = false;
      });
    }
  }

  List<dynamic> get filteredAbastecimentos {
    final query = searchController.text.toLowerCase();
    final hoje = DateTime.now();

    return abastecimentos.where((item) {
      if (query.isNotEmpty) {
        final term =
            '${item['vehicles']?['plate'] ?? ''} ${item['drivers']?['name'] ?? ''} ${item['fuel_date'] ?? ''}'
                .toLowerCase();
        if (!term.contains(query)) return false;
      }
      if (periodoFiltro == 'Hoje') {
        return item['fuel_date']?.toString().startsWith(
              '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}',
            ) ??
            false;
      }
      if (periodoFiltro == 'Última semana') {
        final data = DateTime.tryParse(item['fuel_date'] ?? '');
        return data != null && hoje.difference(data).inDays <= 7;
      }
      if (periodoFiltro == 'Este mês') {
        final data = DateTime.tryParse(item['fuel_date'] ?? '');
        return data != null &&
            data.year == hoje.year &&
            data.month == hoje.month;
      }
      return true;
    }).toList();
  }

  double get totalLitros {
    return filteredAbastecimentos.fold(
      0.0,
      (sum, item) => sum + (item['liters'] ?? 0).toDouble(),
    );
  }

  double get totalValor {
    return filteredAbastecimentos.fold(
      0.0,
      (sum, item) => sum + (item['total_value'] ?? 0).toDouble(),
    );
  }

  int get veiculosUnicos {
    return filteredAbastecimentos
        .map((item) => item['vehicles']?['plate'] ?? '')
        .toSet()
        .length;
  }

  Widget _cardsResumo() {
    return Row(
      children: [
        Expanded(
          child: _infoCard(
            'Total de litros',
            '${totalLitros.toStringAsFixed(0)} L',
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            'Total gasto',
            'R\$ ${totalValor.toStringAsFixed(2)}',
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            'Veículos usados',
            '$veiculosUnicos',
            Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget _infoCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color.withOpacity(0.88))),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label) {
    final selected = periodoFiltro == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        if (value) {
          setState(() {
            periodoFiltro = label;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Abastecimentos')),
      body: RefreshIndicator(
        onRefresh: carregarAbastecimentos,
        child: carregando
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _cardsResumo(),
                    const SizedBox(height: 20),
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Pesquisar por veículo, motorista ou data',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _buildFiltroChip('Hoje'),
                        _buildFiltroChip('Última semana'),
                        _buildFiltroChip('Este mês'),
                        _buildFiltroChip('Todos'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filteredAbastecimentos.isEmpty
                          ? const Center(
                              child: Text('Nenhum abastecimento encontrado.'),
                            )
                          : ListView.builder(
                              itemCount: filteredAbastecimentos.length,
                              itemBuilder: (context, index) {
                                final item = filteredAbastecimentos[index];
                                final motorista =
                                    item['drivers']?['name'] ?? 'Não informado';
                                final veiculo =
                                    item['vehicles']?['plate'] ?? 'Sem placa';
                                return Card(
                                  elevation: 4,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              DetalheAbastecimentoPage(
                                                abastecimento: item,
                                              ),
                                        ),
                                      );
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue.withOpacity(
                                        0.18,
                                      ),
                                      child: const Icon(
                                        Icons.local_gas_station,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    title: Text(
                                      '${item['liters']} L · R\$ ${item['total_value']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 6),
                                        Text('Veículo: $veiculo'),
                                        Text('Motorista: $motorista'),
                                        Text(
                                          'Data: ${item['fuel_date'] ?? '--'} • ${item['fuel_time'] ?? '--'}',
                                        ),
                                      ],
                                    ),
                                    trailing: const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 18,
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

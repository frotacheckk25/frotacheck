import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frotacheck/home/abastecimentos/detalhe_abastecimento_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';

class ListaAbastecimentosPage extends StatefulWidget {
  const ListaAbastecimentosPage({super.key});

  @override
  State<ListaAbastecimentosPage> createState() =>
      _ListaAbastecimentosPageState();
}

class _ListaAbastecimentosPageState extends State<ListaAbastecimentosPage> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<Map<String, dynamic>> abastecimentos = [];
  bool carregando = true;
  String periodoFiltro = 'Este mês';

  @override
  void initState() {
    super.initState();
    carregarAbastecimentos();
  }

  Future<void> carregarAbastecimentos() async {
    setState(() => carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var q = supabase
          .from('fuelings')
          .select('*, vehicles (plate), drivers (name)');
      if (eid != null) q = q.eq('empresa_id', eid);
      final dados = await q.order('fuel_date', ascending: false);

      setState(() {
        abastecimentos = List<Map<String, dynamic>>.from(
          (dados as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
    } catch (e) {
      debugPrint('Erro ao carregar abastecimentos: $e');
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  List<Map<String, dynamic>> get filteredAbastecimentos {
    final query = searchController.text.toLowerCase();
    final hoje = DateTime.now();

    return abastecimentos.where((item) {
      if (query.isNotEmpty) {
        final term =
            '${item['vehicles']?['plate'] ?? ''} ${item['drivers']?['name'] ?? ''} ${item['fuel_date'] ?? ''}'
                .toLowerCase();
        if (!term.contains(query)) return false;
      }
      if (periodoFiltro == 'Todos') return true;
      final data = DateTime.tryParse(item['fuel_date'] ?? '');
      if (data == null) return false;
      if (periodoFiltro == 'Hoje') {
        return data.year == hoje.year && data.month == hoje.month && data.day == hoje.day;
      }
      if (periodoFiltro == 'Última semana') {
        return hoje.difference(data).inDays <= 7;
      }
      if (periodoFiltro == 'Este mês') {
        return data.year == hoje.year && data.month == hoje.month;
      }
      return true;
    }).toList();
  }

  double get totalLitros => filteredAbastecimentos.fold(
        0.0, (sum, item) => sum + (item['liters'] as num? ?? 0).toDouble());

  double get totalValor => filteredAbastecimentos.fold(
        0.0, (sum, item) => sum + (item['total_value'] as num? ?? 0).toDouble());

  int get veiculosUnicos => filteredAbastecimentos
      .map((item) => item['vehicles']?['plate']?.toString() ?? '')
      .where((p) => p.isNotEmpty)
      .toSet()
      .length;

  Widget _cardsResumo() {
    return Row(
      children: [
        Expanded(child: _infoCard('Total de litros', '${totalLitros.toStringAsFixed(0)} L', AppColors.info)),
        const SizedBox(width: 12),
        Expanded(child: _infoCard('Total gasto', 'R\$ ${totalValor.toStringAsFixed(2)}', AppColors.success)),
        const SizedBox(width: 12),
        Expanded(child: _infoCard('Veículos usados', '$veiculosUnicos', AppColors.secondary)),
      ],
    );
  }

  Widget _infoCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label) {
    final selected = periodoFiltro == label;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => periodoFiltro = label),
      selectedColor: AppColors.secondary.withValues(alpha: 0.25),
      backgroundColor: AppColors.surface,
      checkmarkColor: AppColors.secondary,
      labelStyle: TextStyle(
        color: selected ? AppColors.secondary : AppColors.textSecondary,
        fontSize: 13,
      ),
      side: BorderSide(color: selected ? AppColors.secondary : AppColors.border),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredAbastecimentos;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Histórico de Abastecimentos'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: carregarAbastecimentos),
        ],
      ),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Pesquisar por veículo, motorista ou data',
                        labelStyle: const TextStyle(color: AppColors.textSecondary),
                        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.secondary),
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
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
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum abastecimento encontrado.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final motorista = item['drivers']?['name']?.toString() ?? 'Não informado';
                                final veiculo = item['vehicles']?['plate']?.toString() ?? 'Sem placa';
                                return GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DetalheAbastecimentoPage(abastecimento: item),
                                    ),
                                  ).then((_) => carregarAbastecimentos()),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
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
                                            color: AppColors.info.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.local_gas_station, color: AppColors.info, size: 22),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${item['liters']} L · R\$ ${item['total_value']}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                              const SizedBox(height: 4),
                                              Text('Veículo: $veiculo', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                              Text('Motorista: $motorista', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                              Text(
                                                'Data: ${item['fuel_date'] ?? '--'} · ${item['fuel_time'] ?? '--'}',
                                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
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

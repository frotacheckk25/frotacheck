import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanoManutencaoPage extends StatefulWidget {
  const PlanoManutencaoPage({super.key});

  @override
  State<PlanoManutencaoPage> createState() => _PlanoManutencaoPageState();
}

class _PlanoManutencaoPageState extends State<PlanoManutencaoPage> {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  List<Map<String, dynamic>> planos = [];

  @override
  void initState() {
    super.initState();
    carregarPlanos();
  }

  Future<void> carregarPlanos() async {
    setState(() {
      carregando = true;
    });

    try {
      final response = await supabase
          .from('maintenance_plans')
          .select()
          .order('next_service_km');
      final parsed = List<Map<String, dynamic>>.from(
        (response as List<dynamic>).map(
          (item) => Map<String, dynamic>.from(item as Map<String, dynamic>),
        ),
      );
      setState(() {
        planos = parsed;
      });
    } catch (e) {
      debugPrint('Erro ao carregar planos: $e');
    } finally {
      setState(() {
        carregando = false;
      });
    }
  }

  Widget _buildPlanCard(Map<String, dynamic> plano) {
    final nextKm = plano['next_service_km'] ?? 0;
    final plate = plano['vehicle_plate'] ?? '--';
    final status = planStatus(nextKm as int);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plate,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(status),
                  backgroundColor: status == 'Atenção'
                      ? Colors.orange
                      : status == 'Atrasado'
                      ? Colors.red
                      : Colors.green,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Próxima revisão em $nextKm km'),
            const SizedBox(height: 6),
            Text('Serviço: ${plano['service_type'] ?? 'Revisão'}'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Detalhar (ambiente de teste)')),
                      );
                    },
                    child: const Text('Detalhar'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Agendar (ambiente de teste)')),
                    );
                  },
                  child: const Text('Agendar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String planStatus(int nextKm) {
    if (nextKm <= 0) return 'Atrasado';
    if (nextKm <= 500) return 'Atenção';
    return 'OK';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plano de Manutenção')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: carregando
            ? const Center(child: CircularProgressIndicator())
            : planos.isEmpty
            ? const Center(
                child: Text('Nenhum plano de manutenção encontrado.'),
              )
            : ListView.separated(
                itemCount: planos.length,
                separatorBuilder: (context, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  return _buildPlanCard(planos[index]);
                },
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PneusPage extends StatefulWidget {
  const PneusPage({super.key});

  @override
  State<PneusPage> createState() => _PneusPageState();
}

class _PneusPageState extends State<PneusPage> {
  bool carregando = false;

  final List<Map<String, dynamic>> pneusMock = [
    {
      'id': '1',
      'veiculo': 'ABC-1234',
      'posicao': 'Dianteiro Esquerdo',
      'marca': 'Pirelli',
      'pressao': '32 PSI',
      'status': 'bom',
    },
    {
      'id': '2',
      'veiculo': 'XYZ-9999',
      'posicao': 'Traseiro Direito',
      'marca': 'Michelin',
      'pressao': '30 PSI',
      'status': 'revisar',
    },
  ];

  Color _getStatusColor(String status) {
    switch (status) {
      case 'bom':
        return Colors.green;
      case 'revisar':
        return Colors.orange;
      case 'troca':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pneus'),
        backgroundColor: AppColors.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Controle de Pneus',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Gestão de pneus, rodízio e inspeções para manter a frota segura e eficiente.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: pneusMock.length,
                separatorBuilder: (context, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final pneu = pneusMock[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getStatusColor(pneu['status']).withOpacity(0.2),
                        child: const Icon(Icons.tire_repair),
                      ),
                      title: Text('${pneu['veiculo']} - ${pneu['posicao']}'),
                      subtitle: Text('${pneu['marca']} • Pressão: ${pneu['pressao']}'),
                      trailing: Chip(
                        label: Text(pneu['status'].toUpperCase()),
                        backgroundColor: _getStatusColor(pneu['status']).withOpacity(0.3),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

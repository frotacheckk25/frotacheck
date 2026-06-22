import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AlertasPage extends StatefulWidget {
  const AlertasPage({super.key});

  @override
  State<AlertasPage> createState() => _AlertasPageState();
}

class _AlertasPageState extends State<AlertasPage> {
  bool carregando = false;

  final List<Map<String, dynamic>> alertasMock = [
    {
      'id': '1',
      'titulo': 'Vencimento de CNH',
      'descricao': 'João Silva - CNH vence em 5 dias',
      'tipo': 'warning',
      'data': '2024-02-15',
    },
    {
      'id': '2',
      'titulo': 'Manutenção preventiva',
      'descricao': 'ABC-123 - Revisão programada para amanhã',
      'tipo': 'info',
      'data': '2024-02-10',
    },
    {
      'id': '3',
      'titulo': 'Seguro vencido',
      'descricao': 'XYZ-999 - Seguro venceu há 3 dias',
      'tipo': 'error',
      'data': '2024-02-01',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Alertas'),
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
                    'Alertas da frota',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Acompanhe avisos de vencimento, inspeções e notificações críticas da frota.',
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
                itemCount: alertasMock.length,
                separatorBuilder: (context, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final alerta = alertasMock[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: Icon(
                        alerta['tipo'] == 'error'
                            ? Icons.error
                            : alerta['tipo'] == 'warning'
                                ? Icons.warning
                                : Icons.info,
                        color: alerta['tipo'] == 'error'
                            ? Colors.red
                            : alerta['tipo'] == 'warning'
                                ? Colors.orange
                                : AppColors.primary,
                      ),
                      title: Text(alerta['titulo']),
                      subtitle: Text(alerta['descricao']),
                      trailing: IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Alerta resolvido (ambiente de teste)'),
                            ),
                          );
                        },
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

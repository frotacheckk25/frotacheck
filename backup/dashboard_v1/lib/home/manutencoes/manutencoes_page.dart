import 'package:flutter/material.dart';

import '../../../pages/ocorrencias_page.dart';
import '../../../pages/lista_ocorrencias_page.dart';
import '../../../pages/plano_manutencao_page.dart';
import '../../../pages/troca_oleo_page.dart';

class ManutencoesPage extends StatelessWidget {
  const ManutencoesPage({super.key});

  Widget _buildCard(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
    Color color,
  ) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(icon, size: 26, color: color),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: color.withValues(alpha: 0.88))),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manutenções')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF00B8D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Central de manutenção',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Gerencie serviços, ocorrências e inspeções em um único lugar.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _buildStatisticCard(
                  'Serviços agendados',
                  '18',
                  const Color(0xFF0D47A1),
                ),
                const SizedBox(width: 12),
                _buildStatisticCard(
                  'Ocorrências abertas',
                  '6',
                  const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 12),
                _buildStatisticCard(
                  'Próxima troca',
                  '2 veículos',
                  const Color(0xFF1AA251),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _buildCard(
              context,
              Icons.oil_barrel,
              'Troca de óleo',
              'Registre e acompanhe intervalos de troca de óleo.',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrocaOleoPage()),
                );
              },
              const Color(0xFF0D47A1),
            ),
            _buildCard(
              context,
              Icons.warning,
              'Registrar ocorrência',
              'Reporte problemas em tempo real com prioridade.',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OcorrenciasPage()),
                );
              },
              const Color(0xFFF59E0B),
            ),
            _buildCard(
              context,
              Icons.list_alt,
              'Lista de ocorrências',
              'Acompanhe o status e resoluções recentes.',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ListaOcorrenciasPage(),
                  ),
                );
              },
              const Color(0xFF1AA251),
            ),
            _buildCard(
              context,
              Icons.insights,
              'Plano de manutenção',
              'Confira a próxima revisão por quilometragem.',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlanoManutencaoPage(),
                  ),
                );
              },
              const Color(0xFF7C3AED),
            ),
          ],
        ),
      ),
    );
  }
}

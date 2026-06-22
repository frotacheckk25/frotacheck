import 'package:flutter/material.dart';

class DetalheOcorrenciaPage extends StatelessWidget {
  final Map<String, dynamic> ocorrencia;

  const DetalheOcorrenciaPage({super.key, required this.ocorrencia});

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

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ocorrencia['status'] ?? 'Aberto';
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes da Ocorrência')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ocorrencia['driver_name'] ?? 'Sem motorista',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Chip(
                    backgroundColor: getStatusColor(status),
                    label: Text(
                      status,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _infoTile('Problema', ocorrencia['problem_type'] ?? '--'),
                  _infoTile('Localização', ocorrencia['location'] ?? '--'),
                  _infoTile('Prioridade', ocorrencia['priority'] ?? '--'),
                  _infoTile('Data', ocorrencia['created_at'] ?? '--'),
                  const Divider(height: 36),
                  const Text(
                    'Descrição detalhada',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(ocorrencia['problem'] ?? '--'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Compartilhar ocorrência (ambiente de teste)')),
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Compartilhar ocorrência'),
            ),
          ],
        ),
      ),
    );
  }
}

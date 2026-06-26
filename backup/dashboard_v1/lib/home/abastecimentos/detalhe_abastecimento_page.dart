import 'package:flutter/material.dart';

class DetalheAbastecimentoPage extends StatelessWidget {
  final Map abastecimento;

  const DetalheAbastecimentoPage({super.key, required this.abastecimento});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do Abastecimento')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              'Litros: ${abastecimento['liters']}',
              style: const TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 10),

            Text(
              'Valor Total: R\$ ${abastecimento['total_value']}',
              style: const TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 10),

            Text(
              'Odômetro: ${abastecimento['odometer']}',
              style: const TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 10),

            Text(
              'Data: ${abastecimento['fuel_date']}',
              style: const TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 10),

            Text(
              'Horário: ${abastecimento['fuel_time']}',
              style: const TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 20),

            if (abastecimento['odometer_photo'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Foto do Odômetro',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Image.network(abastecimento['odometer_photo']),
                ],
              ),

            const SizedBox(height: 20),

            if (abastecimento['pump_photo'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Foto da Bomba',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Image.network(abastecimento['pump_photo']),
                ],
              ),

            const SizedBox(height: 20),

            if (abastecimento['receipt_photo'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cupom Fiscal',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Image.network(abastecimento['receipt_photo']),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

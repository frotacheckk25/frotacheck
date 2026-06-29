import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class DetalheAbastecimentoPage extends StatelessWidget {
  final Map<String, dynamic> abastecimento;

  const DetalheAbastecimentoPage({super.key, required this.abastecimento});

  String _fmt(dynamic v) => v?.toString() ?? '--';

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalhes do Abastecimento'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_gas_station, color: AppColors.info, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_fmt(abastecimento['liters'])} L',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              'R\$ ${_fmt(abastecimento['total_value'])}',
                              style: const TextStyle(fontSize: 16, color: AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.border, height: 32),
                  _row('Odômetro', '${_fmt(abastecimento['odometer'])} km'),
                  _row('Data', _fmt(abastecimento['fuel_date'])),
                  _row('Horário', _fmt(abastecimento['fuel_time'])),
                  if (abastecimento['vehicles']?['plate'] != null)
                    _row('Veículo', _fmt(abastecimento['vehicles']['plate'])),
                  if (abastecimento['drivers']?['name'] != null)
                    _row('Motorista', _fmt(abastecimento['drivers']['name'])),
                ],
              ),
            ),
            if (abastecimento['odometer_photo'] != null) ...[
              const SizedBox(height: 20),
              _fotoSection('Foto do Odômetro', abastecimento['odometer_photo'].toString()),
            ],
            if (abastecimento['pump_photo'] != null) ...[
              const SizedBox(height: 20),
              _fotoSection('Foto da Bomba', abastecimento['pump_photo'].toString()),
            ],
            if (abastecimento['receipt_photo'] != null) ...[
              const SizedBox(height: 20),
              _fotoSection('Cupom Fiscal', abastecimento['receipt_photo'].toString()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fotoSection(String titulo, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, errorBuilder: (_, _, _) =>
              Container(
                height: 120,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Icon(Icons.broken_image, color: AppColors.textSecondary)),
              )),
        ),
      ],
    );
  }
}

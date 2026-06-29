import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';
import 'troca_oleo_page.dart';

class PlanoManutencaoPage extends StatefulWidget {
  const PlanoManutencaoPage({super.key});

  @override
  State<PlanoManutencaoPage> createState() => _PlanoManutencaoPageState();
}

class _PlanoManutencaoPageState extends State<PlanoManutencaoPage> {
  final supabase = Supabase.instance.client;
  bool carregando = true;

  // Lista consolidada: um item por veículo com o último oil_change
  List<Map<String, dynamic>> planos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      final results = await Future.wait([
        supabase
            .from('oil_changes')
            .select('id, vehicle_id, change_date, oil_type, next_change_km, created_at')
            .order('created_at', ascending: false),
        supabase.from('vehicles').select('id, plate, brand, model, odometer'),
      ]);

      final trocas = List<Map<String, dynamic>>.from(
        (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final veiculosMap = <String, Map<String, dynamic>>{};
      for (final v in (results[1] as List)) {
        final row = Map<String, dynamic>.from(v as Map);
        veiculosMap[row['id'].toString()] = row;
      }

      // Agrupa por veículo, mantém apenas o último registro
      final latestByVehicle = <String, Map<String, dynamic>>{};
      for (final t in trocas) {
        final vid = t['vehicle_id']?.toString() ?? '';
        if (vid.isEmpty) continue;
        if (!latestByVehicle.containsKey(vid)) {
          latestByVehicle[vid] = {
            ...t,
            '_veiculo': veiculosMap[vid],
          };
        }
      }

      // Inclui veículos sem registros de troca
      for (final v in veiculosMap.values) {
        final vid = v['id'].toString();
        if (!latestByVehicle.containsKey(vid)) {
          latestByVehicle[vid] = {
            'vehicle_id': vid,
            '_veiculo': v,
          };
        }
      }

      if (!mounted) return;
      setState(() {
        planos = latestByVehicle.values.toList()
          ..sort((a, b) {
            final kmA = _kmRestante(a);
            final kmB = _kmRestante(b);
            return kmA.compareTo(kmB);
          });
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar plano de manutenção: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  int _kmRestante(Map<String, dynamic> plano) {
    final nextKm = (plano['next_change_km'] as num?)?.toInt() ?? 0;
    if (nextKm <= 0) return 999999;
    final v = plano['_veiculo'] as Map<String, dynamic>?;
    final odom = (v?['odometer'] as num?)?.toInt() ?? 0;
    return nextKm - odom;
  }

  String _statusLabel(Map<String, dynamic> plano) {
    final nextKm = (plano['next_change_km'] as num?)?.toInt() ?? 0;
    if (nextKm <= 0) return 'Sem registro';
    final km = _kmRestante(plano);
    if (km <= 0) return 'Atrasado';
    if (km <= 500) return 'Atenção';
    return 'OK';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Atrasado': return AppColors.danger;
      case 'Atenção': return AppColors.warning;
      case 'Sem registro': return AppColors.textSecondary;
      default: return AppColors.success;
    }
  }

  String _veiculoLabel(Map<String, dynamic>? v) {
    if (v == null) return '--';
    final plate = v['plate']?.toString() ?? '';
    final brand = v['brand']?.toString() ?? '';
    final model = v['model']?.toString() ?? '';
    final desc = '$brand $model'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Plano de Manutenção'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : planos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.build_circle_outlined, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum veículo encontrado.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: planos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (_, index) => _buildPlanCard(planos[index]),
              ),
            ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plano) {
    final v = plano['_veiculo'] as Map<String, dynamic>?;
    final nextKm = (plano['next_change_km'] as num?)?.toInt() ?? 0;
    final odom = (v?['odometer'] as num?)?.toInt() ?? 0;
    final kmRestante = _kmRestante(plano);
    final status = _statusLabel(plano);
    final cor = _statusColor(status);
    final oilType = plano['oil_type']?.toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _veiculoLabel(v),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Chip(
                label: Text(status),
                backgroundColor: cor.withValues(alpha: 0.15),
                labelStyle: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12),
                side: BorderSide(color: cor.withValues(alpha: 0.4)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (nextKm > 0) ...[
            _infoRow('Odômetro atual', '$odom km'),
            _infoRow('Próxima troca em', '$nextKm km'),
            _infoRow(
              'Km restante',
              kmRestante <= 0 ? 'Atrasado ${(-kmRestante).abs()} km' : '$kmRestante km',
              color: cor,
            ),
          ] else
            Text('Nenhuma troca de óleo registrada', style: TextStyle(color: AppColors.textSecondary)),
          if (oilType != null) _infoRow('Óleo', oilType),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrocaOleoPage()),
              ).then((_) => _carregar()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.oil_barrel, color: Colors.white, size: 18),
              label: const Text('Ver Trocas de Óleo', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

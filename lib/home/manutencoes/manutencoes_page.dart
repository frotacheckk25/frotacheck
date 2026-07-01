import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';

import '../../../pages/ocorrencias_page.dart';
import '../../../pages/lista_ocorrencias_page.dart';
import '../../../pages/plano_manutencao_page.dart';
import '../../../pages/troca_oleo_page.dart';

class ManutencoesPage extends StatefulWidget {
  const ManutencoesPage({super.key});

  @override
  State<ManutencoesPage> createState() => _ManutencoesPageState();
}

class _ManutencoesPageState extends State<ManutencoesPage> {
  final supabase = Supabase.instance.client;

  bool carregando = true;
  int totalServicos = 0;
  int ocorrenciasAbertas = 0;
  int proximaTroca = 0;

  @override
  void initState() {
    super.initState();
    _carregarStats();
  }

  Future<void> _carregarStats() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final isMotorista = auth.isMotorista;
      final driverId = auth.driverId;

      // Motorista: estatísticas limitadas ao próprio veículo/driver
      String? vehicleId;
      if (isMotorista && driverId != null) {
        final v = await supabase
            .from('vehicles')
            .select('id')
            .eq('driver_id', driverId)
            .limit(1)
            .maybeSingle();
        vehicleId = v?['id']?.toString();
      }

      final eid = auth.effectiveEmpresaId;

      var oilQ  = supabase.from('oil_changes').select('id, vehicle_id, next_change_km, created_at');
      var ocorrQ = supabase.from('occurrences').select('id, status');
      var veicQ  = supabase.from('vehicles').select('id, odometer');

      if (isMotorista) {
        if (vehicleId != null) {
          oilQ  = oilQ.eq('vehicle_id', vehicleId);
          veicQ = veicQ.eq('id', vehicleId);
        } else {
          // Motorista sem veículo vinculado: força queries a retornarem vazio
          oilQ  = oilQ.eq('vehicle_id', '');
          veicQ = veicQ.eq('id', '');
        }
        if (driverId != null) ocorrQ = ocorrQ.eq('driver_id', driverId);
      } else if (eid != null) {
        oilQ  = oilQ.eq('empresa_id', eid);
        ocorrQ = ocorrQ.eq('empresa_id', eid);
        veicQ  = veicQ.eq('empresa_id', eid);
      }

      final results = await Future.wait([
        oilQ.order('created_at', ascending: false),
        ocorrQ,
        veicQ,
      ]);

      final trocas = List<Map<String, dynamic>>.from(
        ((results[0] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final ocorr = List<Map<String, dynamic>>.from(
        ((results[1] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final veiculos = List<Map<String, dynamic>>.from(
        ((results[2] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      // Monta mapa de odômetro por vehicle_id
      final odomMap = <String, int>{};
      for (final v in veiculos) {
        final id = v['id']?.toString() ?? '';
        final km = (v['odometer'] as num?)?.toInt() ?? 0;
        odomMap[id] = km;
      }

      // Veículos com próxima troca dentro de 2000 km do odômetro atual
      // Pega o mais recente por veículo
      final latestByVehicle = <String, Map<String, dynamic>>{};
      for (final t in trocas) {
        final vid = t['vehicle_id']?.toString() ?? '';
        if (!latestByVehicle.containsKey(vid)) latestByVehicle[vid] = t;
      }

      int precisamTroca = 0;
      for (final entry in latestByVehicle.entries) {
        final vid = entry.key;
        final nextKm = (entry.value['next_change_km'] as num?)?.toInt() ?? 0;
        final atualKm = odomMap[vid] ?? 0;
        if (nextKm > 0 && atualKm >= nextKm - 2000) precisamTroca++;
      }

      // Ocorrências não resolvidas
      final abertas = ocorr.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase().trim();
        return s != 'resolvido';
      }).length;

      if (!mounted) return;
      setState(() {
        totalServicos = trocas.length;
        ocorrenciasAbertas = abertas;
        proximaTroca = precisamTroca;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro stats manutenções: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  Widget _buildCard(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
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
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: AppColors.textSecondary,
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
            carregando
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Text(
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
    final trocaLabel = proximaTroca == 1 ? '1 veículo' : '$proximaTroca veículos';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manutenções'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregarStats,
          ),
        ],
      ),
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
                  'Serviços registrados',
                  '$totalServicos',
                  const Color(0xFF0D47A1),
                ),
                const SizedBox(width: 12),
                _buildStatisticCard(
                  'Ocorrências abertas',
                  '$ocorrenciasAbertas',
                  const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 12),
                _buildStatisticCard(
                  'Próxima troca',
                  trocaLabel,
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
                ).then((_) => _carregarStats());
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
                ).then((_) => _carregarStats());
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
                ).then((_) => _carregarStats());
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

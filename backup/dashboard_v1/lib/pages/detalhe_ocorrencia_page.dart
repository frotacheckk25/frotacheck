import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';

class DetalheOcorrenciaPage extends StatefulWidget {
  final Map<String, dynamic> ocorrencia;
  final VoidCallback? onStatusChanged;

  const DetalheOcorrenciaPage({
    super.key,
    required this.ocorrencia,
    this.onStatusChanged,
  });

  @override
  State<DetalheOcorrenciaPage> createState() => _DetalheOcorrenciaPageState();
}

class _DetalheOcorrenciaPageState extends State<DetalheOcorrenciaPage> {
  final supabase = Supabase.instance.client;
  late Map<String, dynamic> ocorrencia;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    ocorrencia = Map<String, dynamic>.from(widget.ocorrencia);
  }

  // Suporta tanto dados resolvidos (passados pela lista) quanto campos diretos
  String get _motorista =>
      ocorrencia['driver_name_resolved']?.toString() ??
      ocorrencia['drivers']?['name']?.toString() ??
      ocorrencia['driver_name']?.toString() ??
      'Não informado';

  String get _placa =>
      ocorrencia['vehicle_plate_resolved']?.toString() ??
      ocorrencia['vehicles']?['plate']?.toString() ??
      ocorrencia['vehicle_plate']?.toString() ??
      'Não informado';

  String get _modelo =>
      ocorrencia['vehicle_model_resolved']?.toString() ??
      ocorrencia['vehicles']?['model']?.toString() ??
      '';

  String get _status => ocorrencia['status']?.toString() ?? 'Aberto';

  String get _proximoStatus => switch (_status) {
        'Aberto' => 'Em andamento',
        'Em andamento' => 'Resolvido',
        _ => 'Aberto',
      };

  Color _statusColor(String s) => switch (s.toLowerCase()) {
        'resolvido' => AppColors.success,
        'em andamento' => AppColors.secondary,
        _ => AppColors.danger,
      };

  Color _priorityColor(String? p) => switch ((p ?? '').toLowerCase()) {
        'alta' => AppColors.danger,
        'média' || 'media' => AppColors.warning,
        _ => AppColors.success,
      };

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _avancarStatus() async {
    setState(() => salvando = true);
    try {
      await supabase
          .from('occurrences')
          .update({'status': _proximoStatus})
          .eq('id', ocorrencia['id']);

      if (_proximoStatus == 'Resolvido') {
        try {
          await supabase
              .from('alerts')
              .update({'status': 'resolvido'})
              .eq('occurrence_id', ocorrencia['id']);
        } catch (_) {}
      }

      setState(() => ocorrencia['status'] = _proximoStatus);
      widget.onStatusChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status atualizado para: $_status'),
            backgroundColor: _statusColor(_status),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipo = ocorrencia['problem_type']?.toString() ?? 'Ocorrência';
    final problema = ocorrencia['problem']?.toString() ?? '-';
    final local = ocorrencia['location']?.toString() ?? '-';
    final prioridade = ocorrencia['priority']?.toString() ?? '-';
    final data = _fmtDate(ocorrencia['created_at']?.toString());
    final statusCor = _statusColor(_status);
    final prioCor = _priorityColor(prioridade);
    final resolvida = _status == 'Resolvido';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalhes da Ocorrência'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: prioCor.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: prioCor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.report_problem, color: prioCor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tipo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(data,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusCor.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusCor.withOpacity(0.4)),
                    ),
                    child: Text(_status,
                        style: TextStyle(
                            color: statusCor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Info rows
            _section('Informações', [
              _infoRow(Icons.directions_car_outlined, 'Veículo',
                  _modelo.isNotEmpty ? '$_placa — $_modelo' : _placa),
              _infoRow(Icons.person_outline, 'Motorista', _motorista),
              _infoRow(Icons.location_on_outlined, 'Localização', local),
              _infoRow(Icons.flag_outlined, 'Prioridade', prioridade,
                  valueColor: prioCor),
              _infoRow(Icons.info_outline, 'Status', _status,
                  valueColor: statusCor),
            ]),
            const SizedBox(height: 14),

            // Descrição
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Descrição',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(problema,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Botão avançar status
            if (!resolvida)
              ElevatedButton.icon(
                onPressed: salvando ? null : _avancarStatus,
                icon: salvando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Icon(
                        _proximoStatus == 'Em andamento'
                            ? Icons.play_arrow
                            : Icons.check_circle,
                        color: Colors.white,
                      ),
                label: Text(
                  _proximoStatus == 'Em andamento'
                      ? 'Iniciar atendimento'
                      : 'Marcar como resolvido',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _proximoStatus == 'Em andamento'
                      ? AppColors.warning
                      : AppColors.success,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Text('Ocorrência resolvida',
                        style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          const Divider(height: 1, color: AppColors.border),
          ...rows,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/auth/app_auth_provider.dart';

class TimelineVeiculoPage extends StatefulWidget {
  final String veiculoId;
  final String veiculoPlaca;

  const TimelineVeiculoPage({
    required this.veiculoId,
    required this.veiculoPlaca,
    super.key,
  });

  @override
  State<TimelineVeiculoPage> createState() => _TimelineVeiculoPageState();
}

class _TimelineVeiculoPageState extends State<TimelineVeiculoPage> {
  final supabase = Supabase.instance.client;
  List<TimelineEvent> eventos = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarTimeline();
  }

  Future<void> _carregarTimeline() async {
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;

      // Carregar abastecimentos
      var qAbastecimentos = supabase
          .from('fuelings')
          .select()
          .eq('vehicle_id', widget.veiculoId);
      if (eid != null) qAbastecimentos = qAbastecimentos.eq('empresa_id', eid);
      final abastecimentos = await qAbastecimentos
          .order('created_at', ascending: false);

      // Carregar trocas de óleo
      var qManutencoes = supabase
          .from('oil_changes')
          .select()
          .eq('vehicle_id', widget.veiculoId);
      if (eid != null) qManutencoes = qManutencoes.eq('empresa_id', eid);
      final manutencoes = await qManutencoes
          .order('created_at', ascending: false);

      // Carregar checklists
      var qChecklists = supabase
          .from('checklists')
          .select()
          .eq('veiculo_id', widget.veiculoId);
      if (eid != null) qChecklists = qChecklists.eq('empresa_id', eid);
      final checklists = await qChecklists
          .order('data', ascending: false);

      // Carregar multas
      var qMultas = supabase
          .from('multas')
          .select()
          .eq('veiculo_id', widget.veiculoId);
      if (eid != null) qMultas = qMultas.eq('empresa_id', eid);
      final multas = await qMultas
          .order('data', ascending: false);

      List<TimelineEvent> eventos = [];

      // Processar abastecimentos
      for (var item in abastecimentos) {
        eventos.add(
          TimelineEvent(
            data: DateTime.parse(
              item['created_at'] ?? DateTime.now().toString(),
            ),
            tipo: 'abastecimento',
            titulo: 'Abastecimento',
            descricao:
                '${item['liters'] ?? 0}L - R\$ ${item['total_value'] ?? 0}',
            icone: Icons.local_gas_station,
            cor: Colors.orange,
          ),
        );
      }

      // Processar trocas de óleo
      for (var item in manutencoes) {
        final oilType = item['oil_type']?.toString() ?? 'Óleo';
        final nextKm = item['next_change_km']?.toString() ?? '?';
        eventos.add(
          TimelineEvent(
            data: DateTime.parse(
              item['created_at'] ?? DateTime.now().toString(),
            ),
            tipo: 'troca_oleo',
            titulo: 'Troca de Óleo',
            descricao: '$oilType · Próxima em $nextKm km',
            icone: Icons.oil_barrel,
            cor: AppColors.secondary,
          ),
        );
      }

      // Processar checklists
      for (var item in checklists) {
        final tipo = item['tipo'] == 'saida'
            ? 'Checklist Saída'
            : 'Checklist Retorno';
        eventos.add(
          TimelineEvent(
            data: DateTime.parse(item['data'] ?? DateTime.now().toString()),
            tipo: 'checklist',
            titulo: tipo,
            descricao: item['aprovado'] == true ? 'Aprovado' : 'Pendente',
            icone: Icons.checklist,
            cor: Colors.green,
          ),
        );
      }

      // Processar multas
      for (var item in multas) {
        eventos.add(
          TimelineEvent(
            data: DateTime.parse(item['data'] ?? DateTime.now().toString()),
            tipo: 'multa',
            titulo: 'Multa - ${item['tipo']}',
            descricao: 'R\$ ${item['valor']} - ${item['status']}',
            icone: Icons.receipt_long,
            cor: Colors.red,
          ),
        );
      }

      // Ordenar por data decrescente
      eventos.sort((a, b) => b.data.compareTo(a.data));

      if (!mounted) return;
      setState(() {
        this.eventos = eventos;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar timeline: $e')),
        );
      }
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Timeline - ${widget.veiculoPlaca}'),
        backgroundColor: AppColors.surface,
      ),
      backgroundColor: AppColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : eventos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Nenhum evento registrado'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _carregarTimeline,
                    child: const Text('Recarregar'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: eventos.length,
              itemBuilder: (context, index) {
                final evento = eventos[index];
                return SizedBox(
                  height: 120,
                  child: Row(
                    children: [
                      // Timeline vertical line e círculo
                      SizedBox(
                        width: 50,
                        child: Column(
                          children: [
                            if (index > 0)
                              Expanded(
                                child: VerticalDivider(
                                  color: Colors.grey.withOpacity(0.3),
                                  thickness: 2,
                                  indent: 0,
                                  endIndent: 0,
                                ),
                              ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: evento.cor.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: evento.cor, width: 2),
                              ),
                              child: Icon(
                                evento.icone,
                                color: evento.cor,
                                size: 20,
                              ),
                            ),
                            if (index < eventos.length - 1)
                              Expanded(
                                child: VerticalDivider(
                                  color: Colors.grey.withOpacity(0.3),
                                  thickness: 2,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Conteúdo do evento
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    evento.titulo,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    _formatarData(evento.data),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                evento.descricao,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Chip(
                                label: Text(
                                  evento.tipo.toUpperCase(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                                backgroundColor: evento.cor.withOpacity(0.2),
                                labelStyle: TextStyle(
                                  color: evento.cor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _formatarData(DateTime data) {
    final agora = DateTime.now();
    final diferenca = agora.difference(data);

    if (diferenca.inDays == 0) {
      if (diferenca.inHours == 0) {
        return '${diferenca.inMinutes}m atrás';
      }
      return '${diferenca.inHours}h atrás';
    } else if (diferenca.inDays == 1) {
      return 'Ontem';
    } else if (diferenca.inDays < 7) {
      return '${diferenca.inDays}d atrás';
    } else {
      return '${data.day}/${data.month}/${data.year}';
    }
  }
}

class TimelineEvent {
  final DateTime data;
  final String tipo;
  final String titulo;
  final String descricao;
  final IconData icone;
  final Color cor;

  TimelineEvent({
    required this.data,
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.cor,
  });
}

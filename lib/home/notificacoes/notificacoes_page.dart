import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';

class NotificacoesPage extends StatefulWidget {
  const NotificacoesPage({super.key});

  @override
  State<NotificacoesPage> createState() => _NotificacoesPageState();
}

class _NotificacoesPageState extends State<NotificacoesPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> notificacoes = [];
  bool carregando = true;

  RealtimeChannel? _channel;
  Timer? _fallbackTimer;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _carregar();
    _setupRealtime();
    _fallbackTimer = Timer.periodic(const Duration(minutes: 2), (_) => _carregar());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _fallbackTimer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _setupRealtime() {
    _channel = supabase
        .channel('notificacoes_rt')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificacoes',
          callback: (_) => _debounceCarregar(),
        )
        .subscribe();
  }

  void _debounceCarregar() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _carregar);
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var q = supabase
          .from('notificacoes')
          .select('*, vehicles(plate), drivers(name)');
      if (eid != null) q = q.eq('empresa_id', eid);

      final res = await q.order('created_at', ascending: false).limit(100);
      final lista = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      if (!mounted) return;
      setState(() {
        notificacoes = lista;
        carregando = false;
      });

      if (lista.isNotEmpty) {
        await _marcarComoLidas(lista.first['created_at']?.toString());
      }
    } catch (e) {
      debugPrint('Erro ao carregar notificações: $e');
      if (!mounted) return;
      setState(() => carregando = false);
      showError(context, friendlyError(e));
    }
  }

  // Usa o created_at (gerado pelo servidor) da notificação mais recente já
  // carregada, em vez do relógio do aparelho — evita marcar como "lido"
  // de menos (ou de mais) por causa de diferença de horário entre o
  // celular e o servidor.
  Future<void> _marcarComoLidas(String? maisRecenteCreatedAt) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || maisRecenteCreatedAt == null) return;
    try {
      await supabase
          .from('user_profiles')
          .update({'notificacoes_lidas_em': maisRecenteCreatedAt})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Erro ao marcar notificações como lidas: $e');
    }
  }

  // ── Helpers visuais ──────────────────────────────────────────────────────────
  IconData _icone(String tipo) => switch (tipo) {
    'fuelings' => Icons.local_gas_station,
    'manutencoes' => Icons.build_circle_outlined,
    'viagens' => Icons.route_outlined,
    'checklists' => Icons.fact_check_outlined,
    'occurrences' => Icons.warning_amber_rounded,
    'multas' => Icons.gavel,
    _ => Icons.notifications_none,
  };

  Color _cor(String tipo) => switch (tipo) {
    'fuelings' => AppColors.secondary,
    'manutencoes' => AppColors.warning,
    'viagens' => AppColors.info,
    'checklists' => AppColors.success,
    'occurrences' => AppColors.danger,
    'multas' => const Color(0xFF8B5CF6),
    _ => AppColors.textSecondary,
  };

  String _fmtRelativo(String? raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '-';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora mesmo';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays < 7) return 'há ${diff.inDays}d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notificações'),
        backgroundColor: AppColors.surface,
        actions: [
          if (carregando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregar,
              tooltip: 'Atualizar',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Atividade da Frota',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${notificacoes.length} registro(s) · tempo real',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!carregando && notificacoes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_off_outlined,
                        color: AppColors.textSecondary,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhuma notificação ainda',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _notificacaoCard(notificacoes[i]),
                    ),
                    childCount: notificacoes.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notificacaoCard(Map<String, dynamic> n) {
    final tipo = n['tipo']?.toString() ?? '';
    final titulo = n['titulo']?.toString() ?? 'Notificação';
    final corpo = n['corpo']?.toString() ?? '';
    final placa = n['vehicles']?['plate']?.toString();
    final motorista = n['drivers']?['name']?.toString();
    final cor = _cor(tipo);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_icone(tipo), color: cor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (corpo.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    corpo,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (placa != null || motorista != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (placa != null) 'Veículo $placa',
                      if (motorista != null) 'Motorista $motorista',
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtRelativo(n['created_at']?.toString()),
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

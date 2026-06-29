import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/abastecimentos/abastecimentos_page.dart';
import '../home/alertas/alertas_page.dart';
import '../home/checklists/selecionar_veiculo_checklist.dart';
import '../home/checklists/historico_checklist_page.dart';
import '../home/configuracoes/configuracoes_page.dart';
import '../home/documentos/documentos_page.dart';
import '../home/manutencoes/manutencoes_page.dart';
import '../home/motoristas/motoristas_page.dart';
import '../home/multas/multas_page.dart';
import '../home/pneus/pneus_page.dart';
import '../home/relatorios/relatorios_page.dart';
import '../home/viagens/viagens_page.dart';
import '../home/veiculos/veiculos_page.dart';
import '../pages/ocorrencias_page.dart';
import '../pages/lista_ocorrencias_page.dart';
// animated_brain_widget removed — conceito de globo substituído pelo painel premium
import 'kpi_card_widget.dart';
import '../pages/troca_oleo_page.dart';
import '../shared/widgets/frota_logo.dart';
import '../shared/widgets/menu_card.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_utils.dart' as app_date_utils;

// Utilities extracted for testing and reuse
String getProfileDisplayName({
  Map<String, dynamic>? authServiceUser,
  Map<String, dynamic>? metadata,
  String? supaEmail,
}) {
  final candidates = <dynamic>[];

  // Prioritize explicit auth service fields
  if (authServiceUser != null) {
    candidates.addAll([
      authServiceUser['nome'],
      authServiceUser['name'],
      authServiceUser['fullName'],
      authServiceUser['full_name'],
      authServiceUser['displayName'],
      authServiceUser['username'],
    ]);
  }

  // Then metadata fields
  if (metadata != null) {
    candidates.addAll([
      metadata['nome'],
      metadata['name'],
      metadata['fullName'],
      metadata['full_name'],
      metadata['displayName'],
      metadata['username'],
    ]);
  }

  // Finally email
  candidates.add(supaEmail);

  for (final c in candidates) {
    if (c != null) {
      final s = c.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return 'Usuário';
}

String? getProfilePhotoUrl(
  Map<String, dynamic>? metadata, {
  String? Function(String path)? resolveStoragePath,
  dynamic supabaseClient,
}) {
  if (metadata == null) return null;
  final keys = [
    'avatar_url',
    'avatar',
    'photo',
    'picture',
    'foto_url',
    'foto',
    'photo_url',
    'profile_picture',
    'image',
    'img',
    'avatar_path',
    'photo_path',
  ];

  for (final key in keys) {
    final v = metadata[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty) continue;
    // If seems like an HTTP URL, return directly
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    // If callback provided, let caller resolve storage path
    if (resolveStoragePath != null) {
      final resolved = resolveStoragePath(s);
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }

    // Try to generate a public URL via Supabase Storage using common buckets
    try {
      final supa = supabaseClient ?? Supabase.instance.client;
      final bucketCandidates = <String>[];
      if (metadata.containsKey('avatar_bucket')) {
        bucketCandidates.add(metadata['avatar_bucket'].toString());
      }
      if (metadata.containsKey('bucket')) {
        bucketCandidates.add(metadata['bucket'].toString());
      }
      bucketCandidates.addAll([
        'avatars',
        'profile',
        'profiles',
        'public',
        'users',
        'user-avatars',
      ]);

      for (final bucket in bucketCandidates) {
        if (bucket.isEmpty) continue;
        try {
          final pub = supa.storage.from(bucket).getPublicUrl(s);
          if (pub != null) {
            final url = pub is String
                ? pub
                : (pub is Map && pub['publicUrl'] != null)
                ? pub['publicUrl'].toString()
                : pub.toString();
            if (url.isNotEmpty) return url;
          }
        } catch (_) {
          // ignore and try next bucket
        }
      }

      // If public URL not found, attempt to create a signed URL as fallback
      for (final bucket in bucketCandidates) {
        if (bucket.isEmpty) {
          continue;
        }
        try {
          final signedRaw = supa.storage
              .from(bucket)
              .createSignedUrl(s, 60 * 60);
          final signed = signedRaw;
          if (signed != null) {
            String signedUrl = '';
            if (signed is String) {
              signedUrl = signed;
            } else if (signed is Map) {
              if (signed['signedURL'] != null) {
                signedUrl = signed['signedURL'].toString();
              } else if (signed['signedUrl'] != null) {
                signedUrl = signed['signedUrl'].toString();
              } else if (signed['signed_url'] != null) {
                signedUrl = signed['signed_url'].toString();
              } else if (signed['data'] != null && signed['data'] is Map) {
                final d = signed['data'] as Map;
                if (d['signedURL'] != null) {
                  signedUrl = d['signedURL'].toString();
                } else if (d['signedUrl'] != null) {
                  signedUrl = d['signedUrl'].toString();
                } else if (d['signed_url'] != null) {
                  signedUrl = d['signed_url'].toString();
                }
              }
            }
            if (signedUrl.isNotEmpty) {
              return signedUrl;
            }
          }
        } catch (_) {
          // ignore and try next bucket
        }
      }
    } catch (_) {
      // ignore any supabase/storage errors
    }

    // Otherwise return raw string (may be a public URL or path)
    return s;
  }
  return null;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  int mobileIndex = 0;
  Timer? _refreshTimer;

  // Date range filter
  DateTime _filterStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _filterEnd = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  int totalVeiculos = 0;
  int totalMotoristas = 0;
  int totalAbastecimentos = 0;
  int totalEmManutencao = 0;
  int _veiculosEmManutencaoAtiva = 0;
  int totalOcorrenciasAbertas = 0; // total geral (mostra no KPI)
  int _ocorrenciasAbertasCount = 0; // só as não resolvidas (badge + insights)
  double totalGasto = 0;
  List<Map<String, dynamic>> recentFuelings = [];
  List<FlSpot> monthlyFuelSpots = [];
  Map<String, int> ocorrenciasPorCategoria = {};
  List<Map<String, dynamic>> topCostVehicles = [];
  List<Map<String, dynamic>> rankingMotoristas = [];
  List<Map<String, String>> alertasImportantes = [];
  List<Map<String, dynamic>> ocorrenciasCriticasDash = [];
  List<String> monthlyFuelLabels = [];
  Map<String, double> custosPorCategoria = {};
  int totalMultas = 0;
  List<Map<String, dynamic>> pneusData = [];
  List<int> _modulePulseVersions = List.filled(10, 0);

  // Sparkline state — 6-month buckets, loaded async after main data
  List<double> sparkVeiculos = [];
  List<double> sparkMotoristas = [];
  List<double> sparkManutencoes = [];
  List<double> sparkOcorrencias = [];
  List<double> sparkAbastecimentos = [];
  List<double> sparkMultas = [];
  List<double> sparkGasto = [];
  List<double> sparkFleet = [];

  static const _rankingColors = [
    Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF8B5CF6),
    Color(0xFF10B981), Color(0xFF0EA5E9),
  ];

  // ── KPI getters — always show real data; 0 / R$ 0,00 when no records ──────
  int get _kpiTotalVeiculos  => totalVeiculos;
  int get _kpiVeiculosAtivos => (totalVeiculos - _veiculosEmManutencaoAtiva).clamp(0, totalVeiculos);
  int get _kpiEmManutencao   => totalEmManutencao;
  int get _kpiMotoristas     => totalMotoristas;
  String get _kpiGastoMensal => 'R\$ ${_fmt(totalGasto)}';
  int get _kpiOcorrencias    => totalOcorrenciasAbertas;
  int get _kpiMultas         => totalMultas;
  int get _kpiFleetIndex {
    if (totalVeiculos <= 0) return 0;
    return ((_kpiVeiculosAtivos / totalVeiculos) * 100).round().clamp(0, 100);
  }
  String get _kpiFleetLabel {
    final i = _kpiFleetIndex;
    if (i == 0) return '—';
    if (i >= 90) return 'Excelente';
    if (i >= 75) return 'Bom';
    if (i >= 60) return 'Regular';
    return 'Atenção';
  }
  Color get _kpiFleetColor {
    final i = _kpiFleetIndex;
    if (i == 0) return AppColors.textSecondary;
    if (i >= 90) return AppColors.success;
    if (i >= 75) return AppColors.secondary;
    if (i >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  // ── Chart getters — return real data, empty collection when no records ─────
  List<FlSpot> get _chartFuelSpots  => monthlyFuelSpots;
  List<String> get _chartFuelLabels => monthlyFuelLabels;
  Map<String, double> get _chartCustos      => custosPorCategoria;
  Map<String, int>    get _chartOcorrencias => ocorrenciasPorCategoria;

  // ── Panel getters — return real data, empty when no records ───────────────
  List<Map<String, dynamic>> get _panelRanking      => rankingMotoristas;
  List<Map<String, dynamic>> get _panelVehicleCosts => topCostVehicles;
  List<Map<String, String>>  get _panelAlertas      => alertasImportantes;

  // ── Sparkline trend label helpers ──────────────────────────────────────────

  String _sparkTrend(List<double> bins, String unit) {
    if (bins.length < 2) return '';
    final last = bins.last;
    final prev = bins[bins.length - 2];
    if (prev == 0 && last == 0) return 'sem registros';
    if (prev == 0) return '+${last.toInt()} $unit(s) este mês';
    final delta = last - prev;
    final pct = (delta / prev * 100).round();
    if (delta == 0) return 'estável vs mês anterior';
    return '${delta > 0 ? '+' : ''}$pct% vs mês anterior';
  }

  String _sparkCostTrend(List<double> bins) {
    if (bins.length < 2) return '';
    final last = bins.last;
    final prev = bins[bins.length - 2];
    if (prev == 0 && last == 0) return 'sem gastos no período';
    if (prev == 0) return '+R\$ ${_fmt(last)} este mês';
    final delta = last - prev;
    final pct = (delta / prev * 100).round().abs();
    return '${delta > 0 ? '+' : '-'}$pct% vs mês anterior';
  }

  String _sparkFleetTrend(List<double> bins) {
    if (bins.length < 2) return '';
    final last = bins.last;
    final prev = bins[bins.length - 2];
    if (prev == 0) return '';
    final delta = (last - prev).round();
    if (delta == 0) return 'índice estável';
    return '${delta > 0 ? '+' : ''}$delta% vs mês anterior';
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    final parts = s.split(',');
    final intPart = parts[0];
    final dec = parts[1];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
      buf.write(intPart[i]);
    }
    return '${buf.toString()},$dec';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  Color _alertColor(String title) {
    final t = title.toLowerCase();
    if (t.contains('óleo') || t.contains('manutenção') || t.contains('manutencao')) return AppColors.warning;
    if (t.contains('seguro') || t.contains('vistoria')) return AppColors.success;
    if (t.contains('cnh') || t.contains('licenciamento')) return const Color(0xFFF97316);
    if (t.contains('checklist')) return AppColors.secondary;
    return AppColors.danger;
  }

  IconData _alertIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('óleo')) return Icons.opacity;
    if (t.contains('cnh')) return Icons.badge;
    if (t.contains('licenciamento')) return Icons.assignment;
    if (t.contains('checklist')) return Icons.checklist;
    if (t.contains('seguro')) return Icons.security;
    if (t.contains('pneu')) return Icons.tire_repair;
    if (t.contains('multa')) return Icons.gavel_rounded;
    if (t.contains('documento')) return Icons.description_rounded;
    if (t.contains('manutenção') || t.contains('manutencao')) return Icons.build_rounded;
    if (t.contains('abastecimento')) return Icons.local_gas_station_rounded;
    return Icons.warning_amber_rounded;
  }

  String _relTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'Agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 7) return 'há ${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  List<_InsightData> _buildInsights() {
    final items = <_InsightData>[];

    // ── Ocorrências críticas (prioridade máxima) ──────────────────────────
    if (ocorrenciasCriticasDash.isNotEmpty) {
      items.add(_InsightData(
        icon: Icons.report_problem_rounded,
        color: AppColors.danger,
        title: 'Ocorrências Críticas',
        text:
            '${ocorrenciasCriticasDash.length} ocorrência(s) de alta prioridade sem resolução. '
            'Atue imediatamente para evitar riscos.',
        actionLabel: 'Resolver agora',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AlertasPage()),
        ).then((_) => carregarDashboard()),
        priority: 0,
      ));
    }

    // ── Documentos e CNH vencendo ─────────────────────────────────────────
    final docsAlerts = alertasImportantes.where((a) {
      final t = (a['title'] ?? '').toLowerCase();
      return t.contains('documento') ||
          t.contains('cnh') ||
          t.contains('licenciamento') ||
          t.contains('seguro');
    }).toList();
    if (docsAlerts.isNotEmpty) {
      items.add(_InsightData(
        icon: Icons.assignment_late_rounded,
        color: const Color(0xFFF97316),
        title: 'Documentos Vencendo',
        text:
            '${docsAlerts.length} documento(s) próximo(s) do vencimento. '
            'Regularize para evitar autuações e multas.',
        actionLabel: 'Ver documentos',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocumentosPage()),
        ).then((_) => carregarDashboard()),
        priority: 1,
      ));
    }

    // ── Pneus que precisam de atenção ─────────────────────────────────────
    final pneusAtencao =
        pneusData.where((p) {
          final s = (p['status'] ?? '').toString().toLowerCase();
          return s == 'troca' || s == 'revisar';
        }).toList();
    if (pneusAtencao.isNotEmpty) {
      final precisamTroca =
          pneusData.where((p) => (p['status'] ?? '') == 'troca').length;
      final precisamRevisar =
          pneusData.where((p) => (p['status'] ?? '') == 'revisar').length;
      final color =
          precisamTroca > 0 ? AppColors.danger : const Color(0xFFF97316);
      items.add(_InsightData(
        icon: Icons.tire_repair_rounded,
        color: color,
        title: 'Pneus Desgastados',
        text: '${[
          if (precisamTroca > 0) '$precisamTroca pneu(s) para troca imediata.',
          if (precisamRevisar > 0) '$precisamRevisar pneu(s) precisam de revisão.',
        ].join(' ')} Garanta a segurança da frota.',
        actionLabel: 'Ver pneus',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PneusPage()),
        ).then((_) => carregarDashboard()),
        priority: 1,
      ));
    }

    // ── Multas recentes ───────────────────────────────────────────────────
    if (totalMultas > 0) {
      items.add(_InsightData(
        icon: Icons.gavel_rounded,
        color: AppColors.danger,
        title: 'Multas no Período',
        text:
            '$totalMultas multa(s) registrada(s) no período. '
            'Analise os motoristas e reforce treinamentos.',
        actionLabel: 'Ver multas',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MultasPage()),
        ).then((_) => carregarDashboard()),
        priority: 2,
      ));
    }

    // ── Manutenção preventiva ─────────────────────────────────────────────
    if (totalEmManutencao > 0) {
      items.add(_InsightData(
        icon: Icons.build_rounded,
        color: const Color(0xFF7C3AED),
        title: 'Manutenção Preventiva',
        text:
            '$totalEmManutencao serviço(s) de manutenção registrado(s). '
            'Acompanhe o andamento para minimizar o tempo parado.',
        actionLabel: 'Ver manutenções',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManutencoesPage()),
        ).then((_) => carregarDashboard()),
        priority: 2,
      ));
    } else {
      items.add(_InsightData(
        icon: Icons.build_rounded,
        color: AppColors.success,
        title: 'Manutenção em Dia',
        text:
            'Nenhum serviço de manutenção registrado. '
            'Programe revisões preventivas para manter a disponibilidade.',
        actionLabel: 'Registrar',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManutencoesPage()),
        ).then((_) => carregarDashboard()),
        priority: 4,
      ));
    }

    // ── Economia de combustível ───────────────────────────────────────────
    if (totalGasto > 0 && totalAbastecimentos > 0) {
      final media = totalGasto / totalAbastecimentos;
      final economia = totalGasto * 0.08;
      items.add(_InsightData(
        icon: Icons.local_gas_station_rounded,
        color: const Color(0xFFEAB308),
        title: 'Economia de Combustível',
        text:
            'Custo médio de R\$ ${_fmt(media)}/abastecimento. '
            'Otimização de rotas pode economizar até R\$ ${_fmt(economia)} no período.',
        actionLabel: 'Ver abastecimentos',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AbastecimentosPage()),
        ).then((_) => carregarDashboard()),
        priority: 3,
      ));
    }

    // ── Baixa utilização ──────────────────────────────────────────────────
    final inativos = _kpiTotalVeiculos - _kpiVeiculosAtivos;
    if (inativos > 0 && _kpiTotalVeiculos > 0) {
      final pct = (inativos / _kpiTotalVeiculos * 100).round();
      items.add(_InsightData(
        icon: Icons.garage_rounded,
        color: const Color(0xFF64748B),
        title: 'Baixa Utilização',
        text:
            '$inativos veículo(s) ($pct% da frota) sem atividade no período. '
            'Avalie remanejo, locação ou alienação desses ativos.',
        actionLabel: 'Ver relatório',
        action: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RelatoriosPage()),
        ).then((_) => carregarDashboard()),
        priority: 3,
      ));
    }

    items.sort((a, b) => a.priority.compareTo(b.priority));
    return items.take(5).toList();
  }

  static const List<Color> _dashboardPieColors = [
    AppColors.secondary,
    AppColors.success,
    AppColors.warning,
    AppColors.danger,
    AppColors.primary,
  ];

  @override
  void initState() {
    super.initState();
    carregarDashboard();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) carregarDashboard();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> carregarDashboard() async {
    setState(() => carregando = true);

    // Snapshot antes do carregamento para detectar mudanças por módulo
    final prevVeiculos        = totalVeiculos;
    final prevManutencao      = totalEmManutencao;
    final prevAbastecimentos  = totalAbastecimentos;
    final prevGasto           = totalGasto;
    final prevMotoristas      = totalMotoristas;
    final prevOcorrencias     = totalOcorrenciasAbertas;
    final prevMultas          = totalMultas;
    final prevAlertas         = alertasImportantes.length;
    final prevCriticas        = ocorrenciasCriticasDash.length;

    final dateStart = _filterStart.toIso8601String().split('T')[0];
    final dateEnd = _filterEnd.toIso8601String().split('T')[0];

    try {
      final results = await Future.wait([
        _safeSelect('vehicles'), // 0
        _safeSelect('drivers'), // 1
        _fuelingsInRange(dateStart, dateEnd), // 2
        _safeSelectFiltered('manutencoes', dateStart, dateEnd), // 3
        _safeSelectFiltered('multas', dateStart, dateEnd), // 4
        _safeSelect('pneus'), // 5
        _safeSelectFiltered('occurrences', dateStart, dateEnd), // 6
        _safeSelectFiltered('ocorrencias', dateStart, dateEnd), // 7
        _safeSelect('documentos'), // 8
        _safeQueryDirect(
          supabase
              .from('fuelings')
              .select('id, liters, total_value, fuel_date, fuel_time, vehicles (plate), drivers (name)')
              .gte('fuel_date', dateStart)
              .lte('fuel_date', dateEnd)
              .order('created_at', ascending: false)
              .limit(3),
          'fuelings-recent',
        ), // 9
        _safeQueryDirect(
          supabase.from('oil_changes').select('id,service_type,created_at').gte('created_at', '2020-01-01').order('created_at', ascending: false),
          'oil_changes-alltime',
        ), // 10
        _safeQueryDirect(
          supabase.from('occurrences').select('id,status,created_at').gte('created_at', '2020-01-01').order('created_at', ascending: false),
          'occurrences-alltime',
        ), // 11
        _safeQueryDirect(
          supabase.from('ocorrencias').select('id,status,created_at').gte('created_at', '2020-01-01').order('created_at', ascending: false),
          'ocorrencias-alltime',
        ), // 12
        _safeQueryDirect(
          supabase.from('manutencoes').select('id,status,created_at').gte('created_at', '2020-01-01').order('created_at', ascending: false),
          'manutencoes-alltime',
        ), // 13
      ]);

      final veiculos = results[0];
      final motoristas = results[1];
      final abastecimentos = results[2]
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final manutencoes = results[3];
      final multas = results[4];
      final pneus = results[5];
      final occurrences = results[6];
      final ocorrencias = results[7];
      final documentos = results[8];
      final recents = results[9]
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final allTimeOilChanges  = results[10];
      final allTimeOccurrences = results[11];
      final allTimeOcorrencias = results[12];


      // Período filtrado — gráficos e custo
      final allOcorrencias = [...occurrences, ...ocorrencias];

      // All-time — KPI cards (sem recorte de data)
      final allTimeAllOcorrencias = [...allTimeOccurrences, ...allTimeOcorrencias];

      final dashboardTotalGasto = _calculateTotalCost(
        abastecimentos,
        manutencoes,
        pneus,
        multas,
      );

      final dashboardMonthlyFuelSpots = _buildMonthlyFuelSpots(abastecimentos);
      final categorias = _formatOcorrenciaCategorias(allOcorrencias);
      final ranking = _formatRankingMotoristas(motoristas, abastecimentos);
      final topVehicles = _buildTopCostVehicles(abastecimentos);
      final costByCategory = _buildCostByCategory(
        abastecimentos,
        manutencoes,
        pneus,
        multas,
      );
      // Total geral de ocorrências (todas as situações)
      final totalOcorrenciasCount = allTimeAllOcorrencias.length;
      // Ocorrências não resolvidas — base do card "Em Manutenção" e badge
      final openOcorrenciasCount = allTimeAllOcorrencias
          .where((e) => _isOpenStatus(e))
          .length;
      // Fleet Index: veículos com manutenção ativa no período (tabela manutencoes filtrada)
      final veiculosEmManutencaoCount = _countActiveMaintenance(manutencoes);
      // "Em Manutenção": total de registros em oil_changes (fonte real dos dados de manutenção)
      final activeMaintenanceCount = allTimeOilChanges.length;
      final alerts = await _loadAlertas(
        occurrences: occurrences,
        ocorrencias: ocorrencias,
        documentos: documentos,
        motoristas: motoristas,
      );

      // Carrega ocorrências críticas (Alta prioridade, não resolvidas)
      List<Map<String, dynamic>> criticas = [];
      try {
        final critRes = await supabase
            .from('occurrences')
            .select('id, problem_type, priority, status, location, vehicle_id, created_at')
            .neq('status', 'Resolvido')
            .eq('priority', 'Alta')
            .order('created_at', ascending: false)
            .limit(5);
        criticas = List<Map<String, dynamic>>.from(
          (critRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        // Resolve placa
        for (final c in criticas) {
          final vid = c['vehicle_id']?.toString();
          if (vid != null) {
            try {
              final v = await supabase.from('vehicles').select('plate').eq('id', vid).maybeSingle();
              c['_placa'] = v?['plate'] ?? '-';
            } catch (_) {}
          }
        }
      } catch (_) {}

      setState(() {
        totalVeiculos = veiculos.length;
        totalMotoristas = motoristas.length;
        totalAbastecimentos = abastecimentos.length;
        totalEmManutencao = activeMaintenanceCount;
        _veiculosEmManutencaoAtiva = veiculosEmManutencaoCount;
        totalOcorrenciasAbertas = totalOcorrenciasCount;
        _ocorrenciasAbertasCount = openOcorrenciasCount;
        totalGasto = dashboardTotalGasto;
        totalMultas = multas.length;
        recentFuelings = recents;
        monthlyFuelSpots = dashboardMonthlyFuelSpots;
        ocorrenciasPorCategoria = categorias;
        rankingMotoristas = ranking;
        topCostVehicles = topVehicles;
        alertasImportantes = alerts;
        ocorrenciasCriticasDash = criticas;
        custosPorCategoria = costByCategory;
        pneusData = pneus.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Pulso individual por módulo — só dispara se o valor mudou
        final next = List<int>.from(_modulePulseVersions);
        if (veiculos.length          != prevVeiculos)        next[0]++;
        if (activeMaintenanceCount   != prevManutencao)      next[1]++;
        if (abastecimentos.length    != prevAbastecimentos)  next[2]++;
        if (dashboardTotalGasto      != prevGasto)           next[3]++;
        if (motoristas.length        != prevMotoristas)      next[4]++;
        if (openOcorrenciasCount     != prevOcorrencias)     next[5]++;
        if (multas.length            != prevMultas)          next[6]++;
        if (veiculos.length != prevVeiculos || activeMaintenanceCount != prevManutencao) next[7]++;
        if (alerts.length   != prevAlertas  || criticas.length != prevCriticas)         next[8]++;
        if (dashboardTotalGasto != prevGasto || openOcorrenciasCount != prevOcorrencias) next[9]++;
        _modulePulseVersions = next;
      });
      // Load sparklines independently so they don't delay the main render
      _loadSparklines(veiculos);
    } catch (e) {
      debugPrint('Erro ao carregar dashboard: ${e.toString()}');
    } finally {
      setState(() => carregando = false);
    }
  }

  Future<List<Map<String, dynamic>>> _safeSelect(String table) async {
    try {
      final response = await supabase.from(table).select() as List;
      return response
          .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Falha ao carregar $table: $e');
    }
    return [];
  }

  // Envolve qualquer Future direta em try/catch para não derrubar o Future.wait
  Future<List<Map<String, dynamic>>> _safeQueryDirect(Future<dynamic> query, String label) async {
    try {
      final r = await query;
      return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Dashboard [$label] erro: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fuelingsInRange(
    String dateStart,
    String dateEnd,
  ) async {
    try {
      final response = await supabase
          .from('fuelings')
          .select('*, vehicles (plate), drivers (name)')
          .gte('fuel_date', dateStart)
          .lte('fuel_date', dateEnd) as List;
      return response
          .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      try {
        final response = await supabase
            .from('fuelings')
            .select('*, vehicles (plate), drivers (name)') as List;
        return response
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _safeSelectFiltered(
    String table,
    String dateStart,
    String dateEnd, {
    String dateCol = 'created_at',
  }) async {
    try {
      final response = await supabase
          .from(table)
          .select()
          .gte(dateCol, dateStart)
          .lte(dateCol, '${dateEnd}T23:59:59') as List;
      return response
          .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _safeSelect(table);
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  // ── Sparkline helpers ─────────────────────────────────────────────────────

  static DateTime _mOff(int back) {
    final n = DateTime.now();
    int m = n.month - back, y = n.year;
    while (m <= 0) { m += 12; y--; }
    return DateTime(y, m);
  }

  List<double> _monthCountBins(
    List<Map<String, dynamic>> items, {
    String dateField = 'created_at',
  }) =>
      List.generate(6, (i) {
        final mo = _mOff(5 - i);
        return items.where((e) {
          final dt = DateTime.tryParse(e[dateField]?.toString() ?? '')?.toLocal();
          return dt != null && dt.year == mo.year && dt.month == mo.month;
        }).length.toDouble();
      });

  List<double> _monthCostBins(
    List<Map<String, dynamic>> items, {
    String dateField = 'created_at',
    List<String> costFields = const ['total_value', 'amount', 'cost', 'valor'],
  }) =>
      List.generate(6, (i) {
        final mo = _mOff(5 - i);
        double t = 0;
        for (final e in items) {
          final dt = DateTime.tryParse(e[dateField]?.toString() ?? '')?.toLocal();
          if (dt == null || dt.year != mo.year || dt.month != mo.month) continue;
          for (final f in costFields) {
            final v = _toDouble(e[f]);
            if (v > 0) { t += v; break; }
          }
        }
        return t;
      });

  Future<List<Map<String, dynamic>>> _sparkSelect(
    String table,
    String start,
    String end, {
    String dateCol = 'created_at',
    String cols = 'created_at',
  }) async {
    try {
      final r = await supabase
          .from(table)
          .select(cols)
          .gte(dateCol, start)
          .lte(dateCol, '${end}T23:59:59') as List;
      return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadSparklines(List<Map<String, dynamic>> veiculos) async {
    final now = DateTime.now();
    final mo = _mOff(5);
    final start =
        '${mo.year.toString().padLeft(4, '0')}-${mo.month.toString().padLeft(2, '0')}-01';
    final end = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final rs = await Future.wait([
        _sparkSelect('fuelings', start, end,
            dateCol: 'fuel_date',
            cols: 'fuel_date,total_value,vehicle_id,driver_id'),
        _sparkSelect('manutencoes', start, end, cols: 'created_at,cost,valor'),
        _sparkSelect('occurrences', start, end, cols: 'created_at'),
        _sparkSelect('multas', start, end, cols: 'created_at,amount,valor'),
      ]);

      final fuel = rs[0], maint = rs[1], occ = rs[2], mult = rs[3];

      final fuelBins  = _monthCountBins(fuel, dateField: 'fuel_date');
      final maintBins = _monthCountBins(maint);
      final occBins   = _monthCountBins(occ);
      final multBins  = _monthCountBins(mult);

      // Unique active vehicles per month (vehicles with at least 1 fueling)
      final vBins = List<double>.generate(6, (i) {
        final mo2 = _mOff(5 - i);
        return fuel.where((f) {
          final dt = DateTime.tryParse(f['fuel_date']?.toString() ?? '')?.toLocal();
          return dt != null && dt.year == mo2.year && dt.month == mo2.month;
        }).map((f) => f['vehicle_id']).whereType<Object>().toSet().length.toDouble();
      });

      // Unique active drivers per month
      final drBins = List<double>.generate(6, (i) {
        final mo2 = _mOff(5 - i);
        return fuel.where((f) {
          final dt = DateTime.tryParse(f['fuel_date']?.toString() ?? '')?.toLocal();
          return dt != null && dt.year == mo2.year && dt.month == mo2.month;
        }).map((f) => f['driver_id']).whereType<Object>().toSet().length.toDouble();
      });

      // Total monthly cost (fuel + maintenance + fines)
      final fuelCost  = _monthCostBins(fuel,  dateField: 'fuel_date', costFields: ['total_value']);
      final maintCost = _monthCostBins(maint, costFields: ['cost', 'valor']);
      final multCost  = _monthCostBins(mult,  costFields: ['amount', 'valor']);
      final gastoBins = List<double>.generate(6, (i) => fuelCost[i] + maintCost[i] + multCost[i]);

      // Fleet index = (total_vehicles - vehicles_in_maintenance_that_month) / total * 100
      final vTotal = veiculos.length;
      final fleetBins = List<double>.generate(6, (i) {
        if (vTotal == 0) return 0.0;
        final inMaint = maintBins[i].clamp(0, vTotal.toDouble());
        return ((vTotal - inMaint) / vTotal * 100).clamp(0.0, 100.0);
      });

      if (!mounted) return;
      setState(() {
        sparkVeiculos       = vBins;
        sparkMotoristas     = drBins;
        sparkManutencoes    = maintBins;
        sparkOcorrencias    = occBins;
        sparkAbastecimentos = fuelBins;
        sparkMultas         = multBins;
        sparkGasto          = gastoBins;
        sparkFleet          = fleetBins;
      });
    } catch (e) {
      debugPrint('Sparklines error: $e');
    }
  }

  // Denylist: tudo que NÃO é explicitamente concluído/cancelado é considerado aberto.
  // Cobre status com maiúscula, acentos, variações de digitação.
  bool _isOpenStatus(dynamic item) {
    final s = (item['status'] ?? item['estado'] ?? 'aberto')
        .toString()
        .toLowerCase()
        .trim();
    return s != 'resolvido' && s != 'resolved' &&
           s != 'concluido' && s != 'concluído' &&
           s != 'fechado'   && s != 'closed'    &&
           s != 'cancelado' && s != 'canceled';
  }

  // Conta registros ativos na tabela manutencoes usando a mesma denylist.
  int _countActiveMaintenance(List<Map<String, dynamic>> manutencoes) {
    return manutencoes.where(_isOpenStatus).length;
  }

  double _calculateTotalCost(
    List<Map<String, dynamic>> abastecimentos,
    List<Map<String, dynamic>> manutencoes,
    List<Map<String, dynamic>> pneus,
    List<Map<String, dynamic>> multas,
  ) {
    final categoryCosts = _buildCostByCategory(
      abastecimentos,
      manutencoes,
      pneus,
      multas,
    );
    return categoryCosts.values.fold(0.0, (sum, value) => sum + value);
  }

  Future<List<Map<String, String>>> _loadAlertas({
    required List<Map<String, dynamic>> occurrences,
    required List<Map<String, dynamic>> ocorrencias,
    required List<Map<String, dynamic>> documentos,
    required List<Map<String, dynamic>> motoristas,
  }) async {
    try {
      final supAlerts = await supabase
          .from('alerts')
          .select()
          .eq('status', 'ativo')
          .order('created_at', ascending: false)
          .limit(8);
      final supAlertsList = supAlerts as List;
      if (supAlertsList.isNotEmpty) {
        // Ordena: error (crítico) primeiro, depois warning, depois info
        final sorted = List<Map<String, dynamic>>.from(
          supAlertsList.map((e) => Map<String, dynamic>.from(e as Map)),
        );
        const ordemTipo = {'error': 0, 'warning': 1, 'info': 2};
        sorted.sort((a, b) {
          final ta = ordemTipo[a['tipo'] ?? 'info'] ?? 2;
          final tb = ordemTipo[b['tipo'] ?? 'info'] ?? 2;
          return ta.compareTo(tb);
        });
        return sorted.map<Map<String, String>>((a) {
          return {
            'title': (a['title'] ?? a['titulo'] ?? '').toString(),
            'subtitle': (a['subtitle'] ?? a['descricao'] ?? a['detail'] ?? '').toString(),
            'tipo': (a['tipo'] ?? 'info').toString(),
            'time': (a['created_at'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Falha ao carregar alertas diretos: $e');
    }

    final built = <Map<String, String>>[];
    final combinedOccurrences = [...occurrences, ...ocorrencias];

    for (final o in combinedOccurrences.where(_isOpenStatus).take(5)) {
      final tipo =
          o['problem_type'] ?? o['type'] ?? o['category'] ?? 'Ocorrência';
      built.add({
        'title': 'Ocorrência: ${tipo.toString()}',
        'subtitle': '${o['vehicles']?['plate'] ?? ''} - ${o['status'] ?? ''}',
        'time': (o['created_at'] ?? '').toString(),
        'tipo': 'warning',
      });
    }

    final now = DateTime.now();
    for (final doc in documentos) {
      final raw =
          doc['data_vencimento']?.toString() ??
          doc['vencimento']?.toString() ??
          '';
      final dt = _parseDate(raw) ?? DateTime.tryParse(raw);
      if (dt != null) {
        final diff = dt.difference(now).inDays;
        if (diff <= 30 && diff >= 0) {
          built.add({
            'title':
                'Documento vencendo: ${doc['tipo'] ?? doc['name'] ?? 'Documento'}',
            'subtitle': 'Vence em $diff dias',
          });
        }
      }
    }

    for (final m in motoristas) {
      final raw =
          m['cnh_vencimento'] ??
          m['cnh_expiration'] ??
          m['cnh_due'] ??
          m['cnh_validade'];
      final dt = raw != null
          ? _parseDate(raw.toString()) ?? DateTime.tryParse(raw.toString())
          : null;
      if (dt != null) {
        final diff = dt.difference(now).inDays;
        if (diff <= 30 && diff >= 0) {
          built.add({
            'title': 'CNH vencendo: ${m['name'] ?? m['nome'] ?? 'Motorista'}',
            'subtitle': 'Vence em $diff dias',
          });
        }
      }
    }

    if (built.isEmpty) {
      return built;
    }

    return built.take(6).toList();
  }

  List<FlSpot> _buildMonthlyFuelSpots(List<dynamic> abastecimentos) {
    final months = <int, double>{};
    final labels = <String>[];

    for (var item in abastecimentos) {
      final rawDate = item['fuel_date']?.toString() ?? '';
      final date = _parseDate(rawDate);
      if (date == null) continue;
      final key = date.year * 100 + date.month;
      months[key] = (months[key] ?? 0) + _toDouble(item['liters']);
    }

    // Build month list within the selected filter range
    final rangeStart = DateTime(_filterStart.year, _filterStart.month);
    final rangeEnd = DateTime(_filterEnd.year, _filterEnd.month);
    final monthList = <DateTime>[];
    var cur = rangeStart;
    while (!cur.isAfter(rangeEnd)) {
      monthList.add(cur);
      cur = DateTime(cur.year, cur.month + 1);
    }
    // Cap at 12 months to keep chart readable
    final display = monthList.length > 12
        ? monthList.sublist(monthList.length - 12)
        : monthList;

    final spots = <FlSpot>[];
    for (var i = 0; i < display.length; i++) {
      final m = display[i];
      final key = m.year * 100 + m.month;
      spots.add(FlSpot(i.toDouble(), months[key] ?? 0));
      labels.add('${_shortMonth(m.month)}/${m.year.toString().substring(2)}');
    }

    monthlyFuelLabels = List.unmodifiable(labels);
    return spots;
  }

  DateTime? _parseDate(String rawDate) {
    if (rawDate.isEmpty) return null;

    return app_date_utils.DateUtils.parseDate(rawDate);
  }

  String _shortMonth(int month) {
    const names = [
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    return names[month.clamp(1, 12)];
  }

  Map<String, double> _buildCostByCategory(
    List<dynamic> abastecimentos,
    List<dynamic> manutencoes,
    List<dynamic> pneus,
    List<dynamic> multas,
  ) {
    double abastecimentoTotal = 0;
    double manutencaoTotal = 0;
    double pneuTotal = 0;
    double multaTotal = 0;

    for (var item in abastecimentos) {
      abastecimentoTotal += _toDouble(item['total_value']);
    }

    for (var item in manutencoes) {
      final cost = _toDouble(item['cost']);
      final valor = _toDouble(item['valor']);
      final totalValue = _toDouble(item['total_value']);
      manutencaoTotal += cost > 0 ? cost : (valor > 0 ? valor : totalValue);
    }

    for (var item in pneus) {
      final cost = _toDouble(item['cost']);
      final valor = _toDouble(item['valor']);
      pneuTotal += cost > 0 ? cost : valor;
    }

    for (var item in multas) {
      final amount = _toDouble(item['amount']);
      final valor = _toDouble(item['valor']);
      final fineValue = _toDouble(item['fine_value']);
      multaTotal += amount > 0 ? amount : (valor > 0 ? valor : fineValue);
    }

    return {
      'Abastecimento': abastecimentoTotal,
      'Manutenção': manutencaoTotal,
      'Pneus': pneuTotal,
      'Multas': multaTotal,
    };
  }

  Map<String, int> _formatOcorrenciaCategorias(List<dynamic> ocorrencias) {
    final categorias = <String, int>{};
    for (final raw in ocorrencias) {
      final tipo =
          raw['problem_type'] ??
          raw['category'] ??
          raw['type'] ??
          raw['problem'] ??
          'Outros';
      final chave = tipo.toString().isEmpty ? 'Outros' : tipo.toString();
      categorias[chave] = (categorias[chave] ?? 0) + 1;
    }
    if (categorias.isEmpty) {
      return categorias;
    }
    return categorias;
  }

  List<Map<String, dynamic>> _formatRankingMotoristas(
    List<dynamic> motoristas,
    List<Map<String, dynamic>> fuelings,
  ) {
    final countsByDriverId = <dynamic, int>{};
    for (final item in fuelings) {
      final driverId =
          item['driver_id'] ?? item['drivers']?['id'] ?? item['drivers']?['id'];
      if (driverId != null) {
        countsByDriverId[driverId] = (countsByDriverId[driverId] ?? 0) + 1;
      }
    }

    final ranking = motoristas.map((item) {
      final name =
          item['name']?.toString() ?? item['nome']?.toString() ?? 'Motorista';
      final id = item['id'] ?? item['driver_id'];
      final score = id != null ? (countsByDriverId[id] ?? 0) : 0;
      return {'name': name, 'score': score};
    }).toList();

    ranking.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return ranking.take(5).toList();
  }

  List<Map<String, dynamic>> _buildTopCostVehicles(
    List<Map<String, dynamic>> fuelings,
  ) {
    final costs = <String, double>{};
    for (final item in fuelings) {
      final placa =
          item['vehicles']?['plate']?.toString() ??
          item['vehicle_id']?.toString() ??
          'Sem placa';
      final valor = _toDouble(item['total_value']);
      costs[placa] = (costs[placa] ?? 0) + valor;
    }
    final sorted = costs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map((e) => {'plate': e.key, 'value': e.value})
        .take(5)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width <= 760) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const FrotaLogo(compact: false),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Busca ativada (ambiente de teste)')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notificações (ambiente de teste)')),
                );
              },
            ),
          ],
          elevation: 0,
          backgroundColor: AppColors.surface,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              _buildMobileContent(width),
              if (carregando)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.32),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _buildMobileBottomNavigationBar(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final showSidebar = constraints.maxWidth > 1100;
                final width = constraints.maxWidth;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showSidebar) _buildDesktopSidebar(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Header premium — glass + linha inferior iluminada ─
                          SizedBox(
                            height: 64,
                            child: Stack(
                              children: [
                                // Frosted glass — blur vertical discreto
                                Positioned.fill(
                                  child: ClipRect(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 16),
                                      child: Container(
                                        color: const Color(0xFF04080F).withOpacity(0.94),
                                      ),
                                    ),
                                  ),
                                ),
                                // Conteúdo do header
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: _buildHeader(width),
                                ),
                                // Inner glow ascendente — luz do fundo que sobe
                                Positioned(
                                  bottom: 0, left: 0, right: 0,
                                  child: Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          const Color(0xFF1E4080).withOpacity(0.045),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ),
                                // Linha inferior iluminada — gradiente centrado
                                Positioned(
                                  bottom: 0, left: 0, right: 0,
                                  child: Container(
                                    height: 1,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          Color(0xFF0E2650),
                                          Color(0xFF1A4A96),
                                          Color(0xFF0E2650),
                                          Colors.transparent,
                                        ],
                                        stops: [0.0, 0.22, 0.50, 0.78, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ── Main body: premium 3-column grid ────────────
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: carregarDashboard,
                              child: _buildV2ContentArea(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            // ── Loading overlay ──────────────────────────────────────────
            if (carregando)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    color: Colors.black.withOpacity(0.40),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1528).withOpacity(0.90),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF3B82F6).withOpacity(0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.15),
                              blurRadius: 30,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDashboard() {
    final width = MediaQuery.of(context).size.width;
    return RefreshIndicator(
      onRefresh: carregarDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(width),
            const SizedBox(height: 20),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildMobileStatCard(
                    'Veículos',
                    '$totalVeiculos',
                    AppColors.primary,
                  ),
                  _buildMobileStatCard(
                    'Motoristas',
                    '$totalMotoristas',
                    AppColors.success,
                  ),
                  _buildMobileStatCard(
                    'Abastecimentos',
                    '$totalAbastecimentos',
                    AppColors.warning,
                  ),
                  _buildMobileStatCard(
                    'Gasto total',
                    'R\$ ${totalGasto.toStringAsFixed(2)}',
                    AppColors.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildTopKpiRow(width),
            const SizedBox(height: 20),
            _buildChartsRow(width),
            const SizedBox(height: 20),
            _buildBottomPanels(width),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileVehiclesTab() {
    return RefreshIndicator(
      onRefresh: carregarDashboard,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          const Text(
            'Veículos',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Acesse a lista completa de veículos cadastrados e mantenha a frota atualizada.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          MenuCard(
            icon: Icons.directions_car,
            title: 'Ver todos os veículos',
            color: const Color(0xFF0D47A1),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VeiculosPage()),
              );
              carregarDashboard();
            },
          ),
          const SizedBox(height: 20),
          _buildMobileInfoTile('Total de veículos', '$totalVeiculos'),
          const SizedBox(height: 12),
          _buildMobileInfoTile('Em manutenção', '$totalEmManutencao'),
        ],
      ),
    );
  }

  Widget _buildMobileQuickActions() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        const Text(
          'Ações',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        MenuCard(
          icon: Icons.directions_car,
          title: 'Veículos',
          color: const Color(0xFF0D47A1),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VeiculosPage()),
            );
            carregarDashboard();
          },
        ),
        const SizedBox(height: 12),
        MenuCard(
          icon: Icons.local_gas_station,
          title: 'Abastecimentos',
          color: const Color(0xFFF7B500),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AbastecimentosPage()),
            );
            carregarDashboard();
          },
        ),
        const SizedBox(height: 12),
        MenuCard(
          icon: Icons.build,
          title: 'Manutenções',
          color: const Color(0xFF7C3AED),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManutencoesPage()),
            );
            carregarDashboard();
          },
        ),
        const SizedBox(height: 12),
        MenuCard(
          icon: Icons.warning,
          title: 'Ocorrências',
          color: const Color(0xFFF97316),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ListaOcorrenciasPage()),
            );
            carregarDashboard();
          },
        ),
        const SizedBox(height: 12),
        MenuCard(
          icon: Icons.tire_repair,
          title: 'Pneus',
          color: const Color(0xFF64748B),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PneusPage()),
            );
            carregarDashboard();
          },
        ),
        const SizedBox(height: 12),
        MenuCard(
          icon: Icons.notification_important,
          title: 'Alertas',
          color: const Color(0xFFF97316),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertasPage()),
            );
            carregarDashboard();
          },
        ),
      ],
    );
  }

  Widget _buildMobileAlertsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        const Text(
          'Alertas',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        _buildAlertCard(
          'Manutenção agendada',
          'Verifique o checklist do veículo X.',
        ),
        const SizedBox(height: 12),
        _buildAlertCard(
          'Ocorrência aberta',
          'Novo registro de ocorrência em viagem.',
        ),
        const SizedBox(height: 12),
        _buildAlertCard(
          'Combustível baixo',
          'Abastecer veículo Y nas próximas 24h.',
        ),
      ],
    );
  }

  Widget _buildMobileMenuTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        const Text(
          'Menu',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        _buildMenuOption(Icons.person, 'Motoristas', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MotoristasPage()),
          );
          carregarDashboard();
        }),
        _buildMenuOption(Icons.receipt_long, 'Multas', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MultasPage()),
          );
          carregarDashboard();
        }),
        _buildMenuOption(Icons.tire_repair, 'Pneus', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PneusPage()),
          );
          carregarDashboard();
        }),
        _buildMenuOption(Icons.notification_important, 'Alertas', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AlertasPage()),
          );
          carregarDashboard();
        }),
        _buildMenuOption(Icons.description, 'Documentos', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DocumentosPage()),
          );
          carregarDashboard();
        }),
        _buildMenuOption(Icons.directions, 'Viagens', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ViagensPage()),
          );
          carregarDashboard();
        }),
        _buildMenuOption(Icons.settings, 'Configurações', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
          );
          carregarDashboard();
        }),
      ],
    );
  }

  // ── V2 Desktop Layout ────────────────────────────────────────────────────

  // ── PREMIUM LAYOUT — 3 colunas: KPI esq | Centro 60% | KPI dir + alertas ──

  Widget _buildV2ContentArea() {
    return Stack(
      children: [
        // ── Base escura ──────────────────────────────────────────────────────
        Positioned.fill(
          child: Container(color: const Color(0xFF020810)),
        ),

        // ── Imagem dos 3 veículos — fundo de todo o dashboard ────────────────
        Positioned.fill(
          child: Image.asset(
            'assets/images/frotacheckkk.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            alignment: Alignment.center,
          ),
        ),

        // ── Overlay lateral esquerdo — escurece atrás dos KPI cards ──────────
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF020810).withOpacity(0.78),
                    Colors.transparent,
                    Colors.transparent,
                    const Color(0xFF020810).withOpacity(0.78),
                  ],
                  stops: const [0.0, 0.24, 0.76, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ── Overlay superior e inferior — integra com header e rodapé ────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: IgnorePointer(
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF020810),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: IgnorePointer(
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFF020810),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ),

        // ── Colunas de conteúdo — flutuam sobre a imagem ─────────────────────
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 15, child: _buildLeftKpiColumn()),
              const SizedBox(width: 24),
              // Centro transparente — veículos ficam à mostra
              const Expanded(flex: 45, child: SizedBox()),
              const SizedBox(width: 24),
              Expanded(flex: 15, child: _buildRightColumn()),
              const SizedBox(width: 24),
              // Painel Alertas + Insights com glass para legibilidade
              Expanded(
                flex: 25,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF020810).withOpacity(0.80),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF0E1E33),
                        width: 1,
                      ),
                    ),
                    child: _buildV2RightPanel(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftKpiColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: KpiCard(
          title: 'Veículos Ativos',
          value: '$_kpiVeiculosAtivos',
          icon: Icons.directions_car_rounded,
          color: const Color(0xFF6366F1),
          trend: _sparkTrend(sparkVeiculos, 'veículo'),
          sparkData: sparkVeiculos,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage())).then((_) => carregarDashboard()),
        )),
        const SizedBox(height: 24),
        Expanded(child: KpiCard(
          title: 'Em Manutenção',
          value: '$_kpiEmManutencao',
          unit: 'serviços registrados',
          icon: Icons.build_rounded,
          color: const Color(0xFF0EA5E9),
          trend: _sparkTrend(sparkManutencoes, 'serviço'),
          sparkData: sparkManutencoes,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManutencoesPage())).then((_) => carregarDashboard()),
        )),
        const SizedBox(height: 24),
        Expanded(child: KpiCard(
          title: 'Abastecimentos',
          value: '$totalAbastecimentos',
          unit: 'registros no período',
          icon: Icons.local_gas_station_rounded,
          color: const Color(0xFFF97316),
          trend: _sparkTrend(sparkAbastecimentos, 'registro'),
          sparkData: sparkAbastecimentos,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AbastecimentosPage())).then((_) => carregarDashboard()),
        )),
        const SizedBox(height: 24),
        Expanded(child: KpiCard(
          title: 'Gasto do Mês',
          value: _kpiGastoMensal,
          unit: 'combustível + manutenção',
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF7C3AED),
          trend: _sparkCostTrend(sparkGasto),
          sparkData: sparkGasto,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RelatoriosPage())).then((_) => carregarDashboard()),
        )),
      ],
    );
  }

  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: KpiCard(
          title: 'Motoristas Ativos',
          value: '$_kpiMotoristas',
          icon: Icons.person_rounded,
          color: const Color(0xFF10B981),
          trend: _sparkTrend(sparkMotoristas, 'motorista'),
          sparkData: sparkMotoristas,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage())).then((_) => carregarDashboard()),
        )),
        const SizedBox(height: 24),
        Expanded(child: KpiCard(
          title: 'Ocorrências',
          value: '$_kpiOcorrencias',
          unit: _ocorrenciasAbertasCount > 0
              ? '$_ocorrenciasAbertasCount em aberto'
              : 'total de registros',
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFEF4444),
          badge: _ocorrenciasAbertasCount > 0 ? 'Abertas' : null,
          trend: _sparkTrend(sparkOcorrencias, 'ocorrência'),
          sparkData: sparkOcorrencias,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaOcorrenciasPage())).then((_) => carregarDashboard()),
        )),
        const SizedBox(height: 24),
        Expanded(child: KpiCard(
          title: 'Multas',
          value: '$_kpiMultas',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFFF59E0B),
          badge: _kpiMultas > 0 ? 'Pendentes' : null,
          trend: _sparkTrend(sparkMultas, 'multa'),
          sparkData: sparkMultas,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultasPage())).then((_) => carregarDashboard()),
        )),
        const SizedBox(height: 24),
        Expanded(child: KpiCard(
          title: 'Índice da Frota',
          value: '$_kpiFleetIndex%',
          unit: 'disponibilidade operacional',
          icon: Icons.speed_rounded,
          color: _kpiFleetColor,
          badge: _kpiFleetLabel,
          badgeColor: _kpiFleetColor,
          trend: _sparkFleetTrend(sparkFleet),
          sparkData: sparkFleet,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RelatoriosPage())).then((_) => carregarDashboard()),
        )),
      ],
    );
  }

  Widget _buildV2RightPanel() {
    // ── Build unified alert list from real data only ────────────────────────
    final List<_AlertaData> alertas = [
      // Ocorrências críticas abertas (Alta prioridade)
      ...ocorrenciasCriticasDash.map((o) => _AlertaData(
        icon: _alertIcon(o['problem_type']?.toString() ?? ''),
        title: o['problem_type']?.toString() ?? 'Ocorrência',
        veiculo: o['_placa']?.toString() ?? '-',
        horario: _relTime(o['created_at']?.toString()),
        color: AppColors.danger,
        prioridade: 'Crítico',
        pulse: true,
      )),
      // Alertas da tabela alerts / alertas sintéticos
      ...alertasImportantes.map((a) {
        final tipo = a['tipo'] ?? 'info';
        final color = tipo == 'error'
            ? AppColors.danger
            : tipo == 'warning'
                ? AppColors.warning
                : AppColors.secondary;
        final label = tipo == 'error'
            ? 'Crítico'
            : tipo == 'warning'
                ? 'Atenção'
                : 'Info';
        return _AlertaData(
          icon: _alertIcon(a['title'] ?? ''),
          title: a['title'] ?? '',
          veiculo: a['subtitle'] ?? '',
          horario: _relTime(a['time']),
          color: color,
          prioridade: label,
          pulse: tipo == 'error',
        );
      }),
    ];

    final totalAlertas = alertas.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Alertas Críticos ──────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (ocorrenciasCriticasDash.isNotEmpty) ...[
                _PulsingDot(color: AppColors.danger),
                const SizedBox(width: 8),
              ],
              const Text(
                'Alertas Críticos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              if (totalAlertas > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.danger.withOpacity(0.30)),
                  ),
                  child: Text(
                    '$totalAlertas',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Alert cards ───────────────────────────────────
          if (alertas.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF060B14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A2A40)),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      color: AppColors.success.withOpacity(0.65), size: 26),
                  const SizedBox(height: 8),
                  const Text(
                    'Nenhum alerta ativo',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Frota operando normalmente',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...alertas.take(6).map((a) => _AlertaCriticoCard(data: a)),
          ],

          const SizedBox(height: 8),
          // Ver todos link
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertasPage()),
            ).then((_) => carregarDashboard()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ver todos os alertas',
                    style: TextStyle(
                      color: AppColors.secondary.withOpacity(0.80),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      color: AppColors.secondary.withOpacity(0.80), size: 11),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Neon gradient section divider
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFF1E3A5F),
                  Color(0xFF3B82F6),
                  Color(0xFF1E3A5F),
                  Colors.transparent,
                ],
                stops: [0.0, 0.2, 0.5, 0.8, 1.0],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Insights da IA ──────────────────────────────
          Builder(builder: (_) {
            final insights = _buildInsights();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF60A5FA), Color(0xFFA78BFA)],
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'Insights da IA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (insights.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1D4ED8), Color(0xFF4338CA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.25),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Text(
                          '${insights.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Insight cards
                if (insights.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF060B14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1A2A40)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded,
                            color: Color(0xFF334155), size: 22),
                        SizedBox(height: 8),
                        Text(
                          'Sem recomendações no momento',
                          style: TextStyle(color: Color(0xFF475569), fontSize: 11),
                        ),
                      ],
                    ),
                  )
                else
                  ...insights.map((i) => _InsightCard(data: i)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── End V2 Desktop Layout ─────────────────────────────────────────────────

  Widget _buildMobileContent(double width) {
    return IndexedStack(
      index: mobileIndex,
      children: [
        _buildMobileDashboard(),
        _buildMobileVehiclesTab(),
        _buildMobileQuickActions(),
        _buildMobileAlertsTab(),
        _buildMobileMenuTab(),
      ],
    );
  }

  Widget _buildMobileBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: mobileIndex,
      onTap: (index) => setState(() => mobileIndex = index),
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.secondary,
      unselectedItemColor: AppColors.textSecondary,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_car),
          label: 'Veículos',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: 'Ações'),
        BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Alertas'),
        BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
      ],
    );
  }

  // ── Desktop Sidebar ──────────────────────────────────────────────────────────

  Widget _buildDesktopSidebar() {
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: Color(0xFF050C17),
        border: Border(right: BorderSide(color: Color(0xFF0E1E33), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Logo area ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withOpacity(0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FrotaCheck',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Gestão Inteligente',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.38),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Separator after logo
          Container(height: 1, color: const Color(0xFF0E1E33)),
          const SizedBox(height: 10),

          // ── Nav items (scrollable) ─────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ─ Principal ──
                  _sidebarSection('PRINCIPAL'),
                  _buildSidebarItem(Icons.dashboard_rounded,    'Dashboard',           () {}, active: true),
                  const SizedBox(height: 6),

                  // ─ Frota ──
                  _sidebarSection('FROTA'),
                  _buildSidebarItem(Icons.directions_car_rounded, 'Veículos', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.person_rounded,       'Motoristas', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.local_gas_station_rounded, 'Abastecimentos', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AbastecimentosPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.build_rounded,        'Manutenções', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManutencoesPage()));
                    carregarDashboard();
                  }),
                  const SizedBox(height: 6),

                  // ─ Operações ──
                  _sidebarSection('OPERAÇÕES'),
                  _buildSidebarItem(Icons.checklist_rounded,    'Checklists', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SelecionarVeiculoChecklistPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.history_rounded,      'Histórico Checklist', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoricoChecklistPage()));
                  }),
                  _buildSidebarItem(Icons.report_problem_rounded, 'Ocorrências', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaOcorrenciasPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.tire_repair_rounded,  'Pneus', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PneusPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.receipt_long_rounded, 'Multas', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MultasPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.description_rounded,  'Documentos', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentosPage()));
                    carregarDashboard();
                  }),
                  const SizedBox(height: 6),

                  // ─ Gestão ──
                  _sidebarSection('GESTÃO'),
                  _buildSidebarItem(Icons.bar_chart_rounded,    'Relatórios', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const RelatoriosPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.notifications_active_rounded, 'Alertas', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertasPage()));
                    carregarDashboard();
                  }),
                  _buildSidebarItem(Icons.settings_rounded,     'Configurações', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfiguracoesPage()));
                    carregarDashboard();
                  }),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // ── Bottom: profile + badge ────────────────────────────────────────
          Container(height: 1, color: const Color(0xFF0E1E33)),
          _buildProfileCard(),
          _buildProBadge(),
        ],
      ),
    );
  }

  Widget _sidebarSection(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF2D4A6A),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return _SidebarNavItem(icon: icon, label: label, onTap: onTap, active: active);
  }

  Widget _buildProfileCard() {
    final user = supabase.auth.currentUser;
    final metadata = user?.userMetadata ?? {};
    final email = user?.email ?? '';
    final displayName = getProfileDisplayName(metadata: metadata, supaEmail: email);
    final initials = _getInitials(displayName);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
          );
          carregarDashboard();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(
            children: [
              // Avatar with neon ring
              Stack(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withOpacity(0.45),
                          blurRadius: 10,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF060C18), width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      email.isNotEmpty ? email : 'Administrador',
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more_rounded, color: Color(0xFF334155), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProBadge() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF070D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF0E1E33), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.35),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FrotaCheck Pro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Versão 3.0.0',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.30),
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.30)),
            ),
            child: const Text(
              'ATIVO',
              style: TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    BorderRadiusGeometry borderRadius = const BorderRadius.all(
      Radius.circular(12),
    ),
    Color? glowColor,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF070D1A),
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0xFF0E1E33), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (glowColor != null)
            BoxShadow(
              color: glowColor.withOpacity(0.06),
              blurRadius: 24,
              spreadRadius: 0,
            ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMobileStatCard(String title, String value, Color color) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileInfoTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuOption(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.secondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertCard(String title, String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  String _currentDateRangeLabel() {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(_filterStart.day)}/${pad(_filterStart.month)}/${_filterStart.year} - ${pad(_filterEnd.day)}/${pad(_filterEnd.month)}/${_filterEnd.year}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _filterStart, end: _filterEnd),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.secondary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _filterStart = picked.start;
        _filterEnd = picked.end;
      });
      carregarDashboard();
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _GlobalSearchDialog(
        onNavigate: (page) {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(builder: (_) => page))
              .then((_) => carregarDashboard());
        },
      ),
    );
  }

  void _showAlertsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AlertsPanelSheet(
        onViewAll: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertasPage()))
              .then((_) => carregarDashboard());
        },
      ),
    );
  }

  void _showNovoRegistroMenu(BuildContext context) {
    final items = [
      _RegistroOption(Icons.directions_car, 'Novo Veículo', const Color(0xFF0ea5e9), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.person, 'Novo Motorista', const Color(0xFF22c55e), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.local_gas_station, 'Novo Abastecimento', const Color(0xFFeab308), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AbastecimentosPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.receipt_long, 'Nova Multa', const Color(0xFFef4444), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultasPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.build, 'Nova Manutenção', const Color(0xFF7C3AED), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManutencoesPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.opacity, 'Nova Troca de Óleo', const Color(0xFF8B5CF6), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrocaOleoPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.warning_amber, 'Nova Ocorrência', const Color(0xFFF97316), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OcorrenciasPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.description, 'Novo Documento', const Color(0xFF0ea5e9), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentosPage())).then((_) => carregarDashboard())),
      _RegistroOption(Icons.tire_repair, 'Novo Controle de Pneu', const Color(0xFF64748B), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PneusPage())).then((_) => carregarDashboard())),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Novo Registro', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 1.1,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: items.map((opt) => InkWell(
                onTap: () { Navigator.pop(ctx); opt.action(); },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: opt.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(opt.icon, color: opt.color, size: 20),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(opt.label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Estilo de botão compacto — sobrescreve minimumSize do tema global (Size.fromHeight = infinito)

  Widget _buildHeader(double width) {
    final compact = width < 900;
    final user = supabase.auth.currentUser;
    final meta = user?.userMetadata ?? {};
    final email = user?.email ?? '';
    final name = getProfileDisplayName(metadata: meta, supaEmail: email);
    final initials = _getInitials(name);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Title block ────────────────────────────────────────────────────
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Color(0xFFBAE6FD)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds),
                child: Text(
                  'Inteligência da Frota',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 14 : 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Análises e insights em tempo real',
                style: TextStyle(
                  color: const Color(0xFF566880),
                  fontSize: compact ? 10 : 11,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),

        // ── Date picker ───────────────────────────────────────────────────
        _HeaderDateBtn(label: _currentDateRangeLabel(), onTap: _pickDateRange),
        const SizedBox(width: 8),

        // ── Filtros ───────────────────────────────────────────────────────
        if (!compact) ...[
          _HeaderBtn(
            icon: Icons.tune_rounded,
            label: 'Filtros',
            tooltip: 'Filtrar período',
            onTap: _pickDateRange,
          ),
          const SizedBox(width: 10),
        ],

        // ── + Novo Registro ───────────────────────────────────────────────
        _HeaderPrimaryBtn(
          label: compact ? 'Novo' : 'Novo Registro',
          onPressed: () => _showNovoRegistroMenu(context),
        ),
        const SizedBox(width: 12),

        // Separador vertical
        Container(width: 1, height: 20, color: const Color(0xFF182235)),
        const SizedBox(width: 12),

        // ── Search ────────────────────────────────────────────────────────
        _HeaderBtn(
          icon: Icons.search_rounded,
          tooltip: 'Busca',
          onTap: _showSearchDialog,
        ),
        const SizedBox(width: 8),

        // ── Notifications ─────────────────────────────────────────────────
        _HeaderBtn(
          icon: Icons.notifications_outlined,
          tooltip: 'Alertas',
          onTap: _showAlertsPanel,
          badgeCount: _kpiOcorrencias,
        ),
        const SizedBox(width: 10),

        // ── Avatar ────────────────────────────────────────────────────────
        _HeaderAvatarBtn(
          initials: initials,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
            );
            carregarDashboard();
          },
        ),
      ],
    );
  }

  Widget _buildTopKpiRow(double width) {
    final cards = [
      _buildKpiTile('Total de Veículos',   '$_kpiTotalVeiculos',  Icons.local_shipping,        const Color(0xFF0ea5e9), subtitle: 'Todos os veículos',    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage())).then((_) => carregarDashboard())),
      _buildKpiTile('Veículos Ativos',     '$_kpiVeiculosAtivos', Icons.directions_car,         const Color(0xFF22c55e), subtitle: 'Em operação',          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage())).then((_) => carregarDashboard())),
      _buildKpiTile('Em Manutenção',       '$_kpiEmManutencao',   Icons.build,                  const Color(0xFFeab308), subtitle: 'Indisponíveis',         onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManutencoesPage())).then((_) => carregarDashboard())),
      _buildKpiTile('Motoristas Ativos',   '$_kpiMotoristas',     Icons.person,                 const Color(0xFF0ea5e9), subtitle: 'Motoristas',            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage())).then((_) => carregarDashboard())),
      _buildKpiTile('Gasto Mensal',        _kpiGastoMensal,       Icons.account_balance_wallet, const Color(0xFF7C3AED), subtitle: 'Total de gastos',      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RelatoriosPage())).then((_) => carregarDashboard())),
      _buildKpiTile('Ocorrências Abertas', '$_kpiOcorrencias',    Icons.notifications_none,     const Color(0xFFef4444), subtitle: 'Aguardando resolução', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OcorrenciasPage())).then((_) => carregarDashboard())),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final cols = constraints.maxWidth > 900 ? 6 : constraints.maxWidth > 600 ? 3 : 2;
        final itemW = (constraints.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((c) => SizedBox(width: itemW, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildKpiTile(String title, String value, IconData icon, Color color, {String? subtitle, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFF9ca3af), fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF6b7280), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildChartsRow(double width) {
    final showRow = width > 1000;
    final children = [
      Expanded(child: SizedBox(height: 370, child: _buildConsumptionChart())),
      const SizedBox(width: 12),
      Expanded(child: SizedBox(height: 370, child: _buildCostPieChart())),
      const SizedBox(width: 12),
      Expanded(
        child: SizedBox(height: 370, child: _buildOccurrencesBarChart()),
      ),
    ];
    return showRow
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 440, child: _buildConsumptionChart()),
              const SizedBox(height: 16),
              SizedBox(height: 440, child: _buildCostPieChart()),
              const SizedBox(height: 16),
              SizedBox(height: 440, child: _buildOccurrencesBarChart()),
            ],
          );
  }

  Widget _panelHeader(String title, IconData icon, Color color, {VoidCallback? onTap}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        if (onTap != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: const Text('Ver todos'),
          ),
      ],
    );
  }

  Widget _cardHeader(String title, String subtitle, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConsumptionChart() {
    final spots = _chartFuelSpots;
    final labels = _chartFuelLabels;
    if (spots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            'Nenhum dado de combustivel registrado',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.25;
    final yInterval = (maxY / 4).ceilToDouble().clamp(100.0, double.infinity);
    return _buildDashboardCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Consumo de Combustível', 'Litros por mês', Icons.local_gas_station, AppColors.secondary),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border.withOpacity(0.7),
                    strokeWidth: 1,
                    dashArray: [4, 6],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yInterval,
                      reservedSize: 40,
                      getTitlesWidget: (value, _) => Text(
                        value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString(),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 24,
                      getTitlesWidget: (value, _) => Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          labels[value.toInt().clamp(0, labels.length - 1)],
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                clipData: FlClipData.all(),
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.backgroundSoft,
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(0)} L',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    )).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    curveSmoothness: 0.35,
                    isStrokeCapRound: true,
                    color: AppColors.secondary,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.secondary,
                        strokeWidth: 2,
                        strokeColor: AppColors.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.secondary.withOpacity(0.22),
                          AppColors.secondary.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    spots: spots,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostPieChart() {
    final costs = _chartCustos;
    final totalCost = costs.values.fold<double>(0, (sum, val) => sum + val);

    final entries = costs.entries.toList();
    final sections = entries.isNotEmpty
        ? entries.asMap().entries.map((entry) {
            final index = entry.key;
            final value = entry.value.value;
            return PieChartSectionData(
              value: value,
              color: _dashboardPieColors[index % _dashboardPieColors.length],
              title: '',
              radius: 58,
              showTitle: false,
            );
          }).toList()
        : [
            PieChartSectionData(
              value: 1,
              color: AppColors.secondary,
              title: '',
              radius: 58,
              showTitle: false,
            ),
          ];

    final legendItems = entries.isNotEmpty
        ? entries.asMap().entries.map((entry) {
            final index = entry.key;
            final value = entry.value.value;
            final percent = totalCost > 0 ? (value / totalCost) * 100 : 0;
            return {
              'color': _dashboardPieColors[index % _dashboardPieColors.length],
              'label':
                  '${entry.value.key} — ${percent.toStringAsFixed(0)}% - R\$ ${value.toStringAsFixed(2)}',
            };
          }).toList()
        : <Map<String, dynamic>>[];

    return _buildDashboardCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      glowColor: _dashboardPieColors[0],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Custos da Frota', 'Distribuição por categoria', Icons.pie_chart_outline, _dashboardPieColors[0]),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 44,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'R\$${_fmt(totalCost / 1000)}k',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text('total', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: legendItems.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PieLegend(
                          color: item['color'] as Color,
                          label: item['label'] as String,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOccurrencesBarChart() {
    final categories = _chartOcorrencias.entries.toList();
    if (categories.isEmpty) {
      return _buildDashboardCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        glowColor: AppColors.secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader('Ocorrências por Categoria', 'Quantidade registrada', Icons.bar_chart, AppColors.secondary),
            const Expanded(
              child: Center(
                child: Text('Nenhuma ocorrência no período', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      );
    }
    final maxValue = categories.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    final barColors = [
      AppColors.secondary,
      const Color(0xFF6366F1),
      const Color(0xFF22c55e),
      AppColors.warning,
      AppColors.danger,
    ];
    return _buildDashboardCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Ocorrências por Categoria', 'Quantidade registrada', Icons.bar_chart, AppColors.secondary),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: categories.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final widthFraction = maxValue > 0
                    ? (e.value / maxValue).clamp(0.04, 1.0)
                    : 0.04;
                final barColor = barColors[i % barColors.length];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        e.key,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 17,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: widthFraction,
                            child: Container(
                              height: 17,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [barColor.withOpacity(0.7), barColor],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${e.value}',
                        style: TextStyle(color: barColor, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanels(double width) {
    final showRow = width > 1000;
    final panels = [
      Expanded(child: _buildAlertsPanel()),
      const SizedBox(width: 12),
      Expanded(child: _buildRankingPanel()),
      const SizedBox(width: 12),
      Expanded(child: _buildTopCostPanel()),
    ];
    return showRow
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: panels)
        : Column(
            children: [
              _buildAlertsPanel(),
              const SizedBox(height: 16),
              _buildRankingPanel(),
              const SizedBox(height: 16),
              _buildTopCostPanel(),
            ],
          );
  }

  Widget _buildAlertsPanel() {
    return _buildDashboardCard(
      padding: const EdgeInsets.all(16),
      glowColor: ocorrenciasCriticasDash.isNotEmpty ? AppColors.danger : AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('Alertas & Ocorrências', Icons.warning_amber_rounded, AppColors.warning, onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertasPage()));
            carregarDashboard();
          }),
          const SizedBox(height: 12),

          // Ocorrências críticas em destaque
          if (ocorrenciasCriticasDash.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppColors.danger, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${ocorrenciasCriticasDash.length} ocorrência(s) crítica(s) em aberto',
                    style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...ocorrenciasCriticasDash.take(3).map((o) {
              final tipo = o['problem_type']?.toString() ?? 'Ocorrência';
              final placa = o['_placa']?.toString() ?? '-';
              final local = o['location']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertasPage()));
                    carregarDashboard();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.danger.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.report_problem, color: AppColors.danger, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$tipo - $placa',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              if (local.isNotEmpty)
                                Text(local, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 14),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),
          ],

          ..._panelAlertas.map(
            (alerta) {
              final title = alerta['title'] ?? '';
              final tipo = alerta['tipo'] ?? 'info';
              final iconData = _alertIcon(title);
              final iconColor = tipo == 'error'
                  ? AppColors.danger
                  : tipo == 'warning'
                      ? AppColors.warning
                      : _alertColor(title);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: iconColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(iconData, color: iconColor, size: 15),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              alerta['subtitle'] ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRankingPanel() {
    return _buildDashboardCard(
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('Ranking de Motoristas', Icons.emoji_events_outlined, const Color(0xFFFFD700), onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage()));
            carregarDashboard();
          }),
          const SizedBox(height: 12),
          if (_panelRanking.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Sem abastecimentos no período', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
            ),
          if (_panelRanking.isNotEmpty)
          ..._panelRanking.asMap().entries.map((entry) {
            final i = entry.key;
            final driver = entry.value;
            final name = driver['name']?.toString() ?? '';
            final score = driver['score'];
            final avatarColor = _rankingColors[i % _rankingColors.length];
            final initials = _getInitials(name);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i == 0 ? const Color(0xFFFFD700) : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: avatarColor,
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$score pts',
                      style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopCostPanel() {
    return _buildDashboardCard(
      padding: const EdgeInsets.all(16),
      glowColor: const Color(0xFF7C3AED),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('Veículos com Maior Custo', Icons.account_balance_wallet_outlined, const Color(0xFF7C3AED), onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AbastecimentosPage()));
            carregarDashboard();
          }),
          const SizedBox(height: 12),
          if (_panelVehicleCosts.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Sem registros no período', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
            ),
          if (_panelVehicleCosts.isNotEmpty)
          ..._panelVehicleCosts.asMap().entries.map((entry) {
            final i = entry.key;
            final vehicle = entry.value;
            final plate = vehicle['plate']?.toString() ?? 'Sem placa';
            final cost = _toDouble(vehicle['value']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plate,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const Text(
                          'Custo no mês',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'R\$${_fmt(cost)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ??? Alerts Panel Sheet ??????????????????????????????????????????????????????

class _AlertsPanelSheet extends StatefulWidget {
  final VoidCallback onViewAll;
  const _AlertsPanelSheet({required this.onViewAll});

  @override
  State<_AlertsPanelSheet> createState() => _AlertsPanelSheetState();
}

class _AlertsPanelSheetState extends State<_AlertsPanelSheet> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> alertas = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await supabase
          .from('alerts')
          .select()
          .eq('status', 'ativo')
          .order('created_at', ascending: false)
          .limit(8);
      if (mounted) setState(() { alertas = List<Map<String, dynamic>>.from(res); loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Color _color(String? tipo) {
    switch (tipo) {
      case 'error': return AppColors.danger;
      case 'warning': return AppColors.warning;
      default: return AppColors.secondary;
    }
  }

  IconData _icon(String? title) {
    final t = (title ?? '').toLowerCase();
    if (t.contains('óleo') || t.contains('oleo')) return Icons.opacity;
    if (t.contains('cnh')) return Icons.badge;
    if (t.contains('licen')) return Icons.assignment;
    if (t.contains('pneu')) return Icons.tire_repair;
    if (t.contains('ocorrência') || t.contains('ocorr')) return Icons.report_problem;
    if (t.contains('seguro')) return Icons.security;
    return Icons.warning_amber;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Alertas Pendentes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                if (!loading)
                  Text('${alertas.length}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : alertas.isEmpty
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Nenhum alerta pendente', style: TextStyle(color: AppColors.textSecondary)),
                      ))
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: alertas.length,
                        separatorBuilder: (context, i) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final a = alertas[i];
                          final title = a['title'] ?? a['titulo'] ?? 'Alerta';
                          final sub = a['subtitle'] ?? a['descricao'] ?? '';
                          final cor = _color(a['tipo']?.toString());
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSoft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cor.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(color: cor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                  child: Icon(_icon(title), color: cor, size: 16),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onViewAll,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Ver todos os alertas'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ??? Global Search Dialog ????????????????????????????????????????????????????

class _GlobalSearchDialog extends StatefulWidget {
  final void Function(Widget page) onNavigate;
  const _GlobalSearchDialog({required this.onNavigate});

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final supabase = Supabase.instance.client;
  final _ctrl = TextEditingController();
  List<_SearchResult> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final term = q.trim().toLowerCase();
    final out = <_SearchResult>[];

    try {
      // Vehicles by plate or model
      final vehicles = await supabase
          .from('vehicles')
          .select('id, plate, model')
          .or('plate.ilike.%$term%,model.ilike.%$term%')
          .limit(5);
      for (final v in vehicles as List) {
        out.add(_SearchResult(
          icon: Icons.directions_car,
          title: v['plate']?.toString() ?? '',
          subtitle: v['model']?.toString() ?? 'Veículo',
          color: const Color(0xFF0ea5e9),
          page: const VeiculosPage(),
        ));
      }
    } catch (_) {}

    try {
      // Drivers by name
      final drivers = await supabase
          .from('drivers')
          .select('id, name')
          .ilike('name', '%$term%')
          .limit(5);
      for (final d in drivers as List) {
        out.add(_SearchResult(
          icon: Icons.person,
          title: d['name']?.toString() ?? '',
          subtitle: 'Motorista',
          color: const Color(0xFF22c55e),
          page: const MotoristasPage(),
        ));
      }
    } catch (_) {}

    try {
      // Occurrences by problem or driver name
      final occs = await supabase
          .from('occurrences')
          .select('id, problem_type, driver_name, status')
          .or('problem_type.ilike.%$term%,driver_name.ilike.%$term%')
          .limit(4);
      for (final o in occs as List) {
        out.add(_SearchResult(
          icon: Icons.report_problem,
          title: o['problem_type']?.toString() ?? 'Ocorrência',
          subtitle: o['driver_name']?.toString() ?? '',
          color: const Color(0xFFF97316),
          page: const OcorrenciasPage(),
        ));
      }
    } catch (_) {}

    try {
      // Multas by vehicle plate
      final multas = await supabase
          .from('multas')
          .select('id, placa, descricao')
          .ilike('placa', '%$term%')
          .limit(4);
      for (final m in multas as List) {
        out.add(_SearchResult(
          icon: Icons.receipt_long,
          title: m['placa']?.toString() ?? 'Multa',
          subtitle: m['descricao']?.toString() ?? 'Infração',
          color: const Color(0xFFef4444),
          page: const MultasPage(),
        ));
      }
    } catch (_) {}

    if (mounted) setState(() { _results = out; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar placa, motorista, ocorrência...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _ctrl.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18), onPressed: () { _ctrl.clear(); setState(() => _results = []); })
                          : null,
                  filled: true,
                  fillColor: AppColors.backgroundSoft,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: _search,
              ),
            ),
            if (_results.isEmpty && _ctrl.text.length >= 2 && !_searching)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhum resultado encontrado', style: TextStyle(color: AppColors.textSecondary)),
              )
            else if (_results.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    return InkWell(
                      onTap: () => widget.onNavigate(r.page),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: r.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(r.icon, color: r.color, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                  if (r.subtitle.isNotEmpty)
                                    Text(r.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: AppColors.textSecondary, size: 13),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResult {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget page;
  const _SearchResult({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.page,
  });
}

class _RegistroOption {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback action;
  const _RegistroOption(this.icon, this.label, this.color, this.action);
}

class _PieLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _PieLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

// ── Sidebar Navigation Item ────────────────────────────────────────────────────

class _SidebarNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final hovered = _hovered && !active;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF1E3A5F)
                : hovered
                    ? const Color(0xFF111C30)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active
                  ? const Color(0xFF3B82F6).withOpacity(0.35)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Left neon accent bar (active only)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 3 : 0,
                height: 18,
                margin: EdgeInsets.only(right: active ? 8 : 0),
                decoration: BoxDecoration(
                  color: const Color(0xFF60A5FA),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: const Color(0xFF60A5FA).withOpacity(0.70),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
              ),
              // Icon
              Icon(
                widget.icon,
                size: 17,
                color: active
                    ? const Color(0xFF93C5FD)
                    : hovered
                        ? Colors.white.withOpacity(0.65)
                        : const Color(0xFF475569),
              ),
              const SizedBox(width: 9),
              // Label
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : hovered
                            ? Colors.white.withOpacity(0.72)
                            : const Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: active ? 0.1 : 0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Active dot indicator
              if (active)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFF60A5FA),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF60A5FA).withOpacity(0.80),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header Widgets ─────────────────────────────────────────────────────────────

/// Date-range picker button with hover glow.
class _HeaderDateBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _HeaderDateBtn({required this.label, required this.onTap});

  @override
  State<_HeaderDateBtn> createState() => _HeaderDateBtnState();
}

class _HeaderDateBtnState extends State<_HeaderDateBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: _h ? const Color(0xFF0D1A2E) : const Color(0xFF07090F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _h
                  ? const Color(0xFF2563EB).withOpacity(0.45)
                  : const Color(0xFF172030),
            ),
            boxShadow: _h
                ? [BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.12),
                    blurRadius: 16,
                  )]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 14,
                  color: _h ? const Color(0xFF60A5FA) : const Color(0xFF4A6070)),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _h
                      ? Colors.white.withOpacity(0.90)
                      : const Color(0xFF7A90A8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: _h ? const Color(0xFF60A5FA) : const Color(0xFF475569)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic header button — icon-only or icon + label (Filtros style).
class _HeaderBtn extends StatefulWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onTap;
  final int badgeCount;

  const _HeaderBtn({
    required this.icon,
    this.label,
    required this.tooltip,
    this.onTap,
    this.badgeCount = 0,
  });

  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final hasLabel = widget.label != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 38,
            width: hasLabel ? null : 38,
            padding: hasLabel
                ? const EdgeInsets.symmetric(horizontal: 14)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: _h ? const Color(0xFF0D1A2E) : const Color(0xFF07090F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _h
                    ? const Color(0xFF2563EB).withOpacity(0.40)
                    : const Color(0xFF172030),
              ),
              boxShadow: _h
                  ? [BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.12),
                      blurRadius: 16,
                    )]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 18,
                      color: _h
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF526070),
                    ),
                    if (hasLabel) ...[
                      const SizedBox(width: 7),
                      Text(
                        widget.label!,
                        style: TextStyle(
                          color: _h
                              ? Colors.white.withOpacity(0.88)
                              : const Color(0xFF7A90A8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ],
                ),
                // Badge de notificação
                if (widget.badgeCount > 0)
                  Positioned(
                    right: hasLabel ? 7 : 8,
                    top: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF07090F), width: 1.3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withOpacity(0.55),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient primary action button (+ Novo Registro).
class _HeaderPrimaryBtn extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _HeaderPrimaryBtn({required this.label, required this.onPressed});

  @override
  State<_HeaderPrimaryBtn> createState() => _HeaderPrimaryBtnState();
}

class _HeaderPrimaryBtnState extends State<_HeaderPrimaryBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _h
                  ? const [Color(0xFF1D52CE), Color(0xFF4338CA)]
                  : const [Color(0xFF2563EB), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withOpacity(_h ? 0.42 : 0.16),
                blurRadius: _h ? 24 : 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 17),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular avatar button (opens profile/settings).
class _HeaderAvatarBtn extends StatefulWidget {
  final String initials;
  final VoidCallback onTap;

  const _HeaderAvatarBtn({required this.initials, required this.onTap});

  @override
  State<_HeaderAvatarBtn> createState() => _HeaderAvatarBtnState();
}

class _HeaderAvatarBtnState extends State<_HeaderAvatarBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: Tooltip(
        message: 'Perfil',
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(_h ? 0.52 : 0.20),
                  blurRadius: _h ? 24 : 10,
                ),
              ],
              border: Border.all(
                color: _h
                    ? Colors.white.withOpacity(0.30)
                    : Colors.white.withOpacity(0.08),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Alertas Críticos Widgets ───────────────────────────────────────────────────

/// Data model for a single alert card.
class _AlertaData {
  final IconData icon;
  final String title;
  final String veiculo;
  final String horario;
  final Color color;
  final String prioridade;
  final bool pulse;

  const _AlertaData({
    required this.icon,
    required this.title,
    required this.veiculo,
    required this.horario,
    required this.color,
    required this.prioridade,
    this.pulse = false,
  });
}

/// Premium alert card with left accent bar, icon, vehicle, time, priority badge.
/// Pulses the accent bar and icon glow when [data.pulse] is true.
class _AlertaCriticoCard extends StatefulWidget {
  final _AlertaData data;
  const _AlertaCriticoCard({required this.data});

  @override
  State<_AlertaCriticoCard> createState() => _AlertaCriticoCardState();
}

class _AlertaCriticoCardState extends State<_AlertaCriticoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _glow = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.data.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, _) {
          final glowOpacity = d.pulse ? _glow.value : 1.0;
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF060B14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: d.color.withOpacity(d.pulse ? _glow.value * 0.38 : 0.20),
              ),
              boxShadow: d.pulse
                  ? [
                      BoxShadow(
                        color: d.color.withOpacity(_glow.value * 0.12),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left accent bar
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: d.color.withOpacity(glowOpacity),
                        boxShadow: [
                          BoxShadow(
                            color: d.color.withOpacity(glowOpacity * 0.55),
                            blurRadius: 6,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Icon box
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: d.color.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: d.color.withOpacity(glowOpacity * 0.25),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(d.icon, color: d.color, size: 16),
                            ),
                            const SizedBox(width: 10),
                            // Text content
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          d.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                            letterSpacing: -0.1,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (d.horario.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          d.horario,
                                          style: const TextStyle(
                                            color: Color(0xFF475569),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (d.veiculo.isNotEmpty)
                                        Expanded(
                                          child: Text(
                                            d.veiculo,
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontSize: 10.5,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: d.color.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: d.color.withOpacity(0.30),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          d.prioridade,
                                          style: TextStyle(
                                            color: d.color,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Small pulsing dot indicator shown next to "Alertas Críticos" header.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_scale.value),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(_scale.value * 0.6),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Insights da IA Widgets ─────────────────────────────────────────────────────

/// Data model for a single AI insight recommendation.
class _InsightData {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback action;
  final int priority;

  const _InsightData({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.action,
    required this.priority,
  });
}

/// Premium insight card with icon, title, description and action button.
class _InsightCard extends StatefulWidget {
  final _InsightData data;
  const _InsightCard({required this.data});

  @override
  State<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<_InsightCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: d.action,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            transform: Matrix4.identity()
              ..translate(0.0, _hovered ? -2.0 : 0.0),
            decoration: BoxDecoration(
              color: const Color(0xFF060B14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? d.color.withOpacity(0.40)
                    : d.color.withOpacity(0.15),
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: d.color.withOpacity(0.12),
                        blurRadius: 14,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left accent bar
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 2.5,
                      color: d.color.withOpacity(_hovered ? 0.95 : 0.50),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon + Title row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: d.color.withOpacity(
                                        _hovered ? 0.18 : 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _hovered
                                        ? [
                                            BoxShadow(
                                              color: d.color.withOpacity(0.28),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Icon(d.icon, color: d.color, size: 15),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    d.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                      letterSpacing: -0.1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              d.text,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                height: 1.45,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 9),
                            Align(
                              alignment: Alignment.centerRight,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _hovered
                                      ? d.color.withOpacity(0.16)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: d.color.withOpacity(
                                        _hovered ? 0.60 : 0.28),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      d.actionLabel,
                                      style: TextStyle(
                                        color: d.color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_rounded,
                                        color: d.color, size: 10),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dashboard Animated Background ─────────────────────────────────────────────

/// Subtle mesh-dot grid + slowly pulsing ambient glow orbs.
/// Drawn behind all content; repaint is cheap (3 radial gradients + dots).
class _DashboardBackground extends StatefulWidget {
  const _DashboardBackground();

  @override
  State<_DashboardBackground> createState() => _DashboardBackgroundState();
}

class _DashboardBackgroundState extends State<_DashboardBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => RepaintBoundary(
        child: CustomPaint(
          painter: _MeshPainter(pulse: _pulse.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final double pulse;
  const _MeshPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    // ── Dot grid ────────────────────────────────────────────────────────────
    final dotPaint = Paint()
      ..color = const Color(0xFF1A3050).withOpacity(0.35);
    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.75, dotPaint);
      }
    }

    // ── Ambient orb 1 — top-left blue ───────────────────────────────────────
    final r1 = size.width * 0.40;
    final c1 = Offset(size.width * 0.18, size.height * 0.22);
    canvas.drawCircle(
      c1,
      r1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF3B82F6).withOpacity(0.10 + pulse * 0.06),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c1, radius: r1)),
    );

    // ── Ambient orb 2 — center indigo ───────────────────────────────────────
    final r2 = size.width * 0.45;
    final c2 = Offset(size.width * 0.52, size.height * 0.50);
    canvas.drawCircle(
      c2,
      r2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF6366F1).withOpacity(0.07 + pulse * 0.04),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c2, radius: r2)),
    );

    // ── Ambient orb 3 — bottom-right cyan ───────────────────────────────────
    final r3 = size.width * 0.30;
    final c3 = Offset(size.width * 0.88, size.height * 0.80);
    canvas.drawCircle(
      c3,
      r3,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF00D4FF).withOpacity(0.06 + pulse * 0.03),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c3, radius: r3)),
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.pulse != pulse;
}


// ── Global Connection Layer — covers full Row (content + right panel) ───────────

class _GlobalConnectionLayer extends StatefulWidget {
  final List<int> pulseVersions; // 10 values: 8 KPI + Alertas + Insights
  const _GlobalConnectionLayer({required this.pulseVersions});

  @override
  State<_GlobalConnectionLayer> createState() => _GlobalConnectionLayerState();
}

class _GlobalConnectionLayerState extends State<_GlobalConnectionLayer>
    with TickerProviderStateMixin {
  late AnimationController _flowCtrl;
  late AnimationController _heartbeatCtrl;
  late List<AnimationController> _pulseCtrls; // 10 controllers
  late List<int> _lastVersions;

  @override
  void initState() {
    super.initState();
    _flowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _heartbeatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _pulseCtrls = List.generate(
      10,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      ),
    );

    _lastVersions = List<int>.from(widget.pulseVersions);
  }

  @override
  void didUpdateWidget(_GlobalConnectionLayer old) {
    super.didUpdateWidget(old);
    for (int i = 0; i < 10; i++) {
      if (widget.pulseVersions[i] != _lastVersions[i]) {
        _lastVersions[i] = widget.pulseVersions[i];
        _pulseCtrls[i].forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _flowCtrl.dispose();
    _heartbeatCtrl.dispose();
    for (final c in _pulseCtrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final listenables = <Listenable>[_flowCtrl, _heartbeatCtrl, ..._pulseCtrls];
      return AnimatedBuilder(
        animation: Listenable.merge(listenables),
        builder: (_, _) => CustomPaint(
          painter: _GlobalConnectionPainter(
            flow:         _flowCtrl.value,
            heartbeat:    _heartbeatCtrl.value,
            modulePulses: List.generate(10, (i) => _pulseCtrls[i].value),
          ),
          size: constraints.biggest,
        ),
      );
    });
  }
}

// ── Global Connection Painter — 8 KPI + Alertas + Insights ──────────────────────

class _GlobalConnectionPainter extends CustomPainter {
  final double flow;
  final double heartbeat;
  final List<double> modulePulses; // 10 values

  const _GlobalConnectionPainter({
    required this.flow,
    required this.heartbeat,
    required this.modulePulses,
  });

  static const _panelW = 280.0;

  // Cor única para todos os filamentos — combina com o vórtice central
  static const _wire = Color(0xFF9B6FFF);

  @override
  void paint(Canvas canvas, Size size) {
    return; // conexões desativadas — globo holográfico não usa filamentos
    // ignore: dead_code
    final W  = size.width;
    final H  = size.height;
    final cW = W - _panelW;

    // Pontos de emissão dentro do volume do cérebro neural 3D.
    // Cérebro centrado em (cW*0.50, H*0.49), range vertical H*0.224–H*0.715.
    final brainEmitL = [
      Offset(cW * 0.412, H * 0.280),  // Veículos Ativos
      Offset(cW * 0.402, H * 0.420),  // Em Manutenção
      Offset(cW * 0.402, H * 0.560),  // Abastecimentos
      Offset(cW * 0.412, H * 0.685),  // Gasto do Mês
    ];
    final brainEmitR = [
      Offset(cW * 0.588, H * 0.280),  // Motoristas Ativos
      Offset(cW * 0.598, H * 0.420),  // Ocorrências
      Offset(cW * 0.598, H * 0.560),  // Multas
      Offset(cW * 0.588, H * 0.685),  // Índice da Frota
    ];

    // Card centers
    final leftCardX  = cW * 0.132;
    final rightCardX = cW * 0.868;
    final cardYs = [H * 0.125, H * 0.375, H * 0.625, H * 0.875];

    // Painel direito
    final brainAlertasSrc  = Offset(cW * 0.590, H * 0.360);
    final brainInsightsSrc = Offset(cW * 0.590, H * 0.670);
    final alertasDst  = Offset(cW + 40, H * 0.285);
    final insightsDst = Offset(cW + 40, H * 0.702);

    final maxPulse = modulePulses.fold(0.0, (a, b) => a > b ? a : b);
    _drawBrainGlow(canvas, Offset(cW * 0.5, H * 0.47), cW, maxPulse);

    // 8 filamentos — cor única roxa combinando com o vórtice
    for (int i = 0; i < 4; i++) {
      _drawConnection(canvas, brainEmitL[i], Offset(leftCardX,  cardYs[i]), _wire, i,     modulePulses[i],     toLeft: true);
      _drawConnection(canvas, brainEmitR[i], Offset(rightCardX, cardYs[i]), _wire, i + 4, modulePulses[i + 4], toLeft: false);
    }

    // Right-panel connections
    _drawPanelConnection(canvas, brainAlertasSrc, alertasDst,  _wire, 8, modulePulses[8]);
    _drawPanelConnection(canvas, brainInsightsSrc, insightsDst, _wire, 9, modulePulses[9]);

    // Nós de emissão (origem de cada linha)
    for (int i = 0; i < 4; i++) {
      _drawNode(canvas, brainEmitL[i], _wire, 1.8);
      _drawNode(canvas, brainEmitR[i], _wire, 1.8);
    }
    _drawNode(canvas, brainAlertasSrc,  _wire, 1.4);
    _drawNode(canvas, brainInsightsSrc, _wire, 1.4);
    // Nós de terminação nos cards e painel
    for (int i = 0; i < 4; i++) {
      _drawNode(canvas, Offset(leftCardX,  cardYs[i]), _wire, 0.9);
      _drawNode(canvas, Offset(rightCardX, cardYs[i]), _wire, 0.9);
    }
    _drawNode(canvas, alertasDst,  _wire, 0.9);
    _drawNode(canvas, insightsDst, _wire, 0.9);
  }

  // ── Brain glow ───────────────────────────────────────────────────────────────

  void _drawBrainGlow(Canvas canvas, Offset center, double cW, double maxPulse) {
    canvas.drawCircle(
      center, cW * 0.120,
      Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.022 + heartbeat * 0.020 + maxPulse * 0.050)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50),
    );
    canvas.drawCircle(
      center, cW * 0.055,
      Paint()
        ..color = const Color(0xFF6366F1).withOpacity(0.035 + heartbeat * 0.018)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
    if (maxPulse > 0) {
      final fade = (1 - maxPulse).clamp(0.0, 1.0);
      canvas.drawCircle(
        center, cW * 0.068 * (1 + maxPulse * 0.24),
        Paint()
          ..color = const Color(0xFF00D4FF).withOpacity(0.12 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
    }
  }

  // ── KPI connection (card → brain perimeter) ──────────────────────────────────

  void _drawConnection(
    Canvas canvas, Offset src, Offset dst, Color color, int idx, double pulse,
    {required bool toLeft}
  ) {
    final path   = _buildPath(src, dst, toLeft);
    final mets   = path.computeMetrics().toList();
    if (mets.isEmpty) return;
    final metric = mets.first;
    final length = metric.length;

    canvas.drawPath(path,
      Paint()
        ..color       = color.withOpacity(0.09 + pulse * 0.06)
        ..strokeWidth = 1.0
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round,
    );
    canvas.drawPath(path,
      Paint()
        ..color       = color.withOpacity(0.14 + pulse * 0.08)
        ..strokeWidth = 2.4
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    _drawNode(canvas, src, color, 1.0);

    // Partículas viajam do card (t=1) em direção ao rosto (t=0)
    final phase = idx * 0.125;
    for (int p = 0; p < 3; p++) {
      final t       = 1.0 - (flow + phase + p / 3.0) % 1.0;
      final tangent = metric.getTangentForOffset((t * length).clamp(0.5, length - 0.5));
      if (tangent != null) _drawParticle(canvas, tangent.position, color);
    }

    if (pulse > 0) {
      final travelT   = 1.0 - (pulse / 0.65).clamp(0.0, 1.0);
      final pulseTang = metric.getTangentForOffset((travelT * length).clamp(0.5, length - 0.5));
      if (pulseTang != null) {
        final intensity = pulse < 0.28
            ? pulse / 0.28
            : pulse < 0.65 ? 1.0
            : (1 - (pulse - 0.65) / 0.35).clamp(0.0, 1.0);
        _drawPulsePacket(canvas, pulseTang.position, color, intensity);
      }
    }
  }

  // ── Right-panel connection (brain perimeter → panel item) ────────────────────

  void _drawPanelConnection(
    Canvas canvas, Offset src, Offset dst, Color color, int idx, double pulse,
  ) {
    final path   = _buildPanelPath(src, dst);
    final mets   = path.computeMetrics().toList();
    if (mets.isEmpty) return;
    final metric = mets.first;
    final length = metric.length;

    canvas.drawPath(path,
      Paint()
        ..color       = color.withOpacity(0.12 + pulse * 0.08)
        ..strokeWidth = 1.0
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round,
    );
    canvas.drawPath(path,
      Paint()
        ..color       = color.withOpacity(0.18 + pulse * 0.10)
        ..strokeWidth = 2.4
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Partículas viajam do painel (t=1) em direção ao rosto (t=0)
    final phase = idx * 0.125;
    for (int p = 0; p < 2; p++) {
      final t       = 1.0 - (flow + phase + p / 2.0) % 1.0;
      final tangent = metric.getTangentForOffset((t * length).clamp(0.5, length - 0.5));
      if (tangent != null) _drawParticle(canvas, tangent.position, color);
    }

    if (pulse > 0) {
      final travelT   = 1.0 - (pulse / 0.65).clamp(0.0, 1.0);
      final pulseTang = metric.getTangentForOffset((travelT * length).clamp(0.5, length - 0.5));
      if (pulseTang != null) {
        final intensity = pulse < 0.28
            ? pulse / 0.28
            : pulse < 0.65 ? 1.0
            : (1 - (pulse - 0.65) / 0.35).clamp(0.0, 1.0);
        _drawPulsePacket(canvas, pulseTang.position, color, intensity);
      }
    }
  }

  // ── Drawing primitives ───────────────────────────────────────────────────────

  void _drawParticle(Canvas canvas, Offset pos, Color color) {
    canvas.drawCircle(pos, 4.0,
      Paint()
        ..color      = color.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(pos, 1.8,
      Paint()
        ..color       = color.withOpacity(0.50)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.65,
    );
    canvas.drawCircle(pos, 1.2, Paint()..color = color.withOpacity(0.86));
    canvas.drawCircle(pos, 0.60, Paint()..color = Colors.white.withOpacity(0.76));
  }

  void _drawPulsePacket(Canvas canvas, Offset pos, Color color, double intensity) {
    canvas.drawCircle(pos, 12.0,
      Paint()
        ..color      = color.withOpacity(0.24 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(pos, 5.5,
      Paint()
        ..color      = color.withOpacity(0.48 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(pos, 2.6, Paint()..color = Colors.white.withOpacity(0.95 * intensity));
  }

  void _drawNode(Canvas canvas, Offset pos, Color color, double scale) {
    canvas.drawCircle(pos, 4.5 * scale,
      Paint()
        ..color      = color.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(pos, 2.1 * scale,
      Paint()
        ..color       = color.withOpacity(0.48)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.65,
    );
    canvas.drawCircle(pos, 1.3 * scale, Paint()..color = color.withOpacity(0.78));
  }

  // ── Bezier paths ─────────────────────────────────────────────────────────────

  Path _buildPath(Offset src, Offset dst, bool toLeft) {
    final dx = (dst.dx - src.dx).abs();
    final Offset cp1, cp2;
    if (toLeft) {
      // Brain left hemisphere → left card (line sweeps left)
      cp1 = Offset(src.dx - dx * 0.52, src.dy);
      cp2 = Offset(dst.dx + dx * 0.26, dst.dy);
    } else {
      // Brain right hemisphere → right card (line sweeps right)
      cp1 = Offset(src.dx + dx * 0.52, src.dy);
      cp2 = Offset(dst.dx - dx * 0.26, dst.dy);
    }
    return Path()
      ..moveTo(src.dx, src.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, dst.dx, dst.dy);
  }

  Path _buildPanelPath(Offset src, Offset dst) {
    final dx  = (dst.dx - src.dx).abs();
    final dyV = dst.dy - src.dy;
    final cp1 = Offset(src.dx + dx * 0.60, src.dy);
    final cp2 = Offset(dst.dx - dx * 0.20, dst.dy - dyV * 0.15);
    return Path()
      ..moveTo(src.dx, src.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, dst.dx, dst.dy);
  }

  @override
  bool shouldRepaint(_GlobalConnectionPainter old) {
    if (old.flow != flow || old.heartbeat != heartbeat) return true;
    for (int i = 0; i < 10; i++) {
      if (old.modulePulses[i] != modulePulses[i]) return true;
    }
    return false;
  }
}

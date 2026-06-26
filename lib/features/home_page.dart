import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/abastecimentos/abastecimentos_page.dart';
import '../home/alertas/alertas_page.dart';
import '../home/checklists/selecionar_veiculo_checklist.dart';
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
import '../pages/troca_oleo_page.dart';
import '../shared/widgets/app_logo.dart';
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
  int totalOcorrenciasAbertas = 0;
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

  // ??? Mock data fallbacks (shown when Supabase tables are empty) ????????????
  static const _mockRanking = [
    {'name': 'Marcos Silva', 'score': 98},
    {'name': 'João Santos', 'score': 92},
    {'name': 'Carlos Lima', 'score': 87},
    {'name': 'Pedro Oliveira', 'score': 75},
    {'name': 'Lucas Almeida', 'score': 70},
  ];
  static const _mockVehicleCosts = [
    {'plate': 'ABC-1234', 'value': 8452.00},
    {'plate': 'DEF-5678', 'value': 7245.30},
    {'plate': 'GHI-9012', 'value': 6870.20},
    {'plate': 'JKL-3456', 'value': 6120.10},
    {'plate': 'MNO-7890', 'value': 5980.40},
  ];
  static const _mockAlertas = [
    {'title': 'Troca de óleo vencida', 'subtitle': '3 veículos'},
    {'title': 'CNH vencendo em 30 dias', 'subtitle': '5 motoristas'},
    {'title': 'Licenciamento vencendo', 'subtitle': '2 veículos'},
    {'title': 'Checklists pendentes', 'subtitle': '7 veículos'},
    {'title': 'Seguro vencendo em 15 dias', 'subtitle': '4 veículos'},
  ];
  static const _rankingColors = [
    Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF8B5CF6),
    Color(0xFF10B981), Color(0xFF0EA5E9),
  ];

  bool get _hasRealData => totalVeiculos > 0 || totalMotoristas > 0;

  int get _kpiTotalVeiculos       => _hasRealData ? totalVeiculos : 128;
  int get _kpiVeiculosAtivos      => _hasRealData ? (totalVeiculos - totalEmManutencao).clamp(0, totalVeiculos) : 96;
  int get _kpiEmManutencao        => _hasRealData ? totalEmManutencao : 12;
  int get _kpiMotoristas          => _hasRealData ? totalMotoristas : 78;
  String get _kpiGastoMensal      => _hasRealData && totalGasto > 0 ? 'R\$ ${_fmt(totalGasto)}' : 'R\$ 98.765,40';
  int get _kpiOcorrencias         => _hasRealData ? totalOcorrenciasAbertas : 7;

  List<FlSpot> get _chartFuelSpots {
    if (monthlyFuelSpots.isNotEmpty && monthlyFuelSpots.any((s) => s.y > 0)) return monthlyFuelSpots;
    return const [
      FlSpot(0, 2200), FlSpot(1, 2550), FlSpot(2, 2380),
      FlSpot(3, 2800), FlSpot(4, 3150), FlSpot(5, 3450),
    ];
  }
  List<String> get _chartFuelLabels => monthlyFuelLabels.isNotEmpty ? monthlyFuelLabels : ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun'];
  Map<String, double> get _chartCustos => custosPorCategoria.values.any((v) => v > 0) ? custosPorCategoria : {
    'Abastecimento': 59125.30, 'Manutenção': 19755.40, 'Pneus': 9876.50, 'Multas': 6172.20, 'Outros': 3704.00,
  };
  Map<String, int> get _chartOcorrencias => ocorrenciasPorCategoria.isNotEmpty ? ocorrenciasPorCategoria : {
    'Acidente': 3, 'Falha Mecânica': 2, 'Pane': 1, 'Multa': 1, 'Outros': 1,
  };
  List<Map<String, dynamic>> get _panelRanking => rankingMotoristas.isNotEmpty ? rankingMotoristas : List<Map<String, dynamic>>.from(_mockRanking);
  List<Map<String, dynamic>> get _panelVehicleCosts => topCostVehicles.isNotEmpty ? topCostVehicles : List<Map<String, dynamic>>.from(_mockVehicleCosts);
  List<Map<String, String>> get _panelAlertas => alertasImportantes.isNotEmpty ? alertasImportantes : List<Map<String, String>>.from(
    _mockAlertas.map((e) => Map<String, String>.from(e)),
  );

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
    return Icons.warning_amber;
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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
        supabase
            .from('fuelings')
            .select(
              'id, liters, total_value, fuel_date, fuel_time, vehicles (plate), drivers (name)',
            )
            .gte('fuel_date', dateStart)
            .lte('fuel_date', dateEnd)
            .order('created_at', ascending: false)
            .limit(3), // 9
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

      final allOcorrencias = [...occurrences, ...ocorrencias];

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
      final openOcorrenciasCount = allOcorrencias.where(_isOpenStatus).length;
      final activeMaintenanceCount = _countActiveMaintenance(manutencoes);
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
            .select('id, problem_type, priority, status, location, vehicle_id')
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
        totalOcorrenciasAbertas = openOcorrenciasCount;
        totalGasto = dashboardTotalGasto;
        recentFuelings = recents;
        monthlyFuelSpots = dashboardMonthlyFuelSpots;
        ocorrenciasPorCategoria = categorias;
        rankingMotoristas = ranking;
        topCostVehicles = topVehicles;
        alertasImportantes = alerts;
        ocorrenciasCriticasDash = criticas;
        custosPorCategoria = costByCategory;
      });
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

  bool _isOpenStatus(dynamic item) {
    final status = (item['status'] ?? item['estado'] ?? '')
        .toString()
        .toLowerCase();
    return status == 'aberto' ||
        status == 'open' ||
        status == 'em andamento' ||
        status == 'pendente';
  }

  int _countActiveMaintenance(List<Map<String, dynamic>> manutencoes) {
    final active = manutencoes.where((item) {
      final status = (item['status'] ?? item['estado'] ?? '')
          .toString()
          .toLowerCase();
      return status == 'aberto' ||
          status == 'em andamento' ||
          status == 'pendente' ||
          status == 'ativo';
    }).length;
    return active > 0 ? active : 0;
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
                final showSidebar = constraints.maxWidth > 1200;
                final width = constraints.maxWidth;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showSidebar)
                      Container(
                        width: 210,
                        color: AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppLogo(compact: false),
                            const SizedBox(height: 16),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildSidebarItem(
                                      Icons.dashboard,
                                      'Dashboard',
                                      () {},
                                      active: true,
                                    ),
                                    _buildSidebarItem(
                                      Icons.directions_car,
                                      'Veículos',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const VeiculosPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.person,
                                      'Motoristas',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const MotoristasPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.local_gas_station,
                                      'Abastecimentos',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AbastecimentosPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.build,
                                      'Manutenções',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ManutencoesPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.checklist,
                                      'Checklists',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SelecionarVeiculoChecklistPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.report_gmailerrorred,
                                      'Ocorrências',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const AlertasPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.tire_repair,
                                      'Pneus',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const PneusPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.receipt_long,
                                      'Multas',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const MultasPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.description,
                                      'Documentos',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const DocumentosPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.bar_chart,
                                      'Relatórios',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RelatoriosPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.notification_important,
                                      'Alertas',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const AlertasPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                    _buildSidebarItem(
                                      Icons.settings,
                                      'Configurações',
                                      () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ConfiguracoesPage(),
                                          ),
                                        );
                                        carregarDashboard();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Divider(color: AppColors.border, height: 1),
                            const SizedBox(height: 6),
                            _buildProfileCard(),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: RefreshIndicator(
                          onRefresh: carregarDashboard,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildHeader(width),
                                  const SizedBox(height: 16),
                                  _buildTopKpiRow(width),
                                  const SizedBox(height: 14),
                                  _buildChartsRow(width),
                                  const SizedBox(height: 14),
                                  _buildBottomPanels(width),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
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
              MaterialPageRoute(builder: (_) => const AlertasPage()),
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

  Widget _buildSidebarItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: active ? Colors.white : AppColors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final user = supabase.auth.currentUser;
    final metadata = user?.userMetadata ?? {};
    final email = user?.email ?? '';
    final displayName = getProfileDisplayName(metadata: metadata, supaEmail: email);
    final initials = _getInitials(displayName);

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
        );
        carregarDashboard();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary,
              child: Text(
                initials,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
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
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    email.isNotEmpty ? email : 'Administrador',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    BorderRadiusGeometry borderRadius = const BorderRadius.all(
      Radius.circular(14),
    ),
    Color? glowColor,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          if (glowColor != null)
            BoxShadow(
              color: glowColor.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 2,
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
  static final _compactBtn = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(const Size(0, 36)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: WidgetStatePropertyAll(
      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    textStyle: WidgetStatePropertyAll(
      const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    elevation: WidgetStatePropertyAll(0),
  );

  Widget _buildHeader(double width) {
    final compact = width < 900;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              const Text(
                'Visão geral da frota',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Date range — clickable to open date range picker
        GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  _currentDateRangeLabel(),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _iconBtn(Icons.search_outlined, 'Busca', onTap: _showSearchDialog),
        const SizedBox(width: 6),
        _iconBtn(Icons.notifications_none_outlined, 'Alertas', onTap: _showAlertsPanel),
        const SizedBox(width: 8),
        if (!compact) ...[
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('Filtros'),
            style: _compactBtn.copyWith(
              foregroundColor: const WidgetStatePropertyAll(AppColors.textSecondary),
              side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
              backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          onPressed: () => _showNovoRegistroMenu(context),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Novo registro'),
          style: _compactBtn.copyWith(
            backgroundColor: const WidgetStatePropertyAll(AppColors.secondary),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, {VoidCallback? onTap}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
      ),
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
    final maxValue = categories.isEmpty
        ? 5
        : categories.map((e) => e.value).reduce((a, b) => a > b ? a : b);

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

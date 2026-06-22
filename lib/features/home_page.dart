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
  List<String> monthlyFuelLabels = [];
  Map<String, double> custosPorCategoria = {};

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
  }

  Future<void> carregarDashboard() async {
    setState(() => carregando = true);

    try {
      final results = await Future.wait([
        _safeSelect('vehicles'), // 0
        _safeSelect('drivers'), // 1
        supabase
            .from('fuelings')
            .select('*, vehicles (plate), drivers (name)'), // 2
        _safeSelect('manutencoes'), // 3
        _safeSelect('multas'), // 4
        _safeSelect('pneus'), // 5
        _safeSelect('occurrences'), // 6
        _safeSelect('ocorrencias'), // 7
        _safeSelect('documentos'), // 8
        supabase
            .from('fuelings')
            .select(
              'id, liters, total_value, fuel_date, fuel_time, vehicles (plate), drivers (name)',
            )
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
          .from('alertas')
          .select()
          .order('created_at', ascending: false)
          .limit(8);
      final supAlertsList = supAlerts as List;
      if (supAlertsList.isNotEmpty) {
        return supAlertsList.map<Map<String, String>>((a) {
          return {
            'title': (a['title'] ?? a['titulo'] ?? '').toString(),
            'subtitle': (a['subtitle'] ?? a['descricao'] ?? a['detail'] ?? '')
                .toString(),
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
        'subtitle': '${o['vehicles']?['plate'] ?? ''} • ${o['status'] ?? ''}',
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
    final now = DateTime.now();
    final labels = <String>[];

    for (var item in abastecimentos) {
      final rawDate = item['fuel_date']?.toString() ?? '';
      final date = _parseDate(rawDate);
      if (date == null) continue;
      final key = date.year * 100 + date.month;
      months[key] = (months[key] ?? 0) + _toDouble(item['liters']);
    }

    final spots = <FlSpot>[];
    for (var i = 0; i <= 5; i++) {
      final monthOffset = 5 - i;
      final date = DateTime(now.year, now.month - monthOffset);
      final adjustedDate = date.month <= 0
          ? DateTime(date.year - 1, date.month + 12)
          : date;
      final key = adjustedDate.year * 100 + adjustedDate.month;
      final total = months[key] ?? 0;
      spots.add(FlSpot(i.toDouble(), total));
      labels.add(
        '${_shortMonth(adjustedDate.month)} ${adjustedDate.year.toString().substring(2)}',
      );
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
      manutencaoTotal += _toDouble(item['cost']);
      manutencaoTotal += _toDouble(item['valor']);
      manutencaoTotal += _toDouble(item['total_value']);
    }

    for (var item in pneus) {
      pneuTotal += _toDouble(item['cost']);
      pneuTotal += _toDouble(item['valor']);
    }

    for (var item in multas) {
      multaTotal += _toDouble(item['amount']);
      multaTotal += _toDouble(item['valor']);
      multaTotal += _toDouble(item['fine_value']);
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
                        width: 300,
                        color: AppColors.surface,
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppLogo(compact: false),
                            const SizedBox(height: 18),
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
                            const SizedBox(height: 12),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 12),
                            _buildProfileCard(),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: RefreshIndicator(
                            onRefresh: carregarDashboard,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildHeader(width),
                                    const SizedBox(height: 24),
                                    _buildTopKpiRow(width),
                                    const SizedBox(height: 24),
                                    _buildChartsRow(width),
                                    const SizedBox(height: 24),
                                    _buildBottomPanels(width),
                                  ],
                                ),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: active ? AppColors.secondary : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.secondary.withOpacity(0.9)
                  : AppColors.border,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.secondary.withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    // Perfil fixo conforme especificação
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.secondary,
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Fernando Admin',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Administrador',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    BorderRadiusGeometry borderRadius = const BorderRadius.all(
      Radius.circular(12),
    ),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.border.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 8),
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
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(firstDay.day)}/${pad(firstDay.month)}/${firstDay.year} - ${pad(lastDay.day)}/${pad(lastDay.month)}/${lastDay.year}';
  }

  Widget _buildHeader(double width) {
    return _buildDashboardCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Visão geral da frota',
                style: TextStyle(
                  color: Color(0xFF9ca3af),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Color(0xFF0d1f3c),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFF1e293b)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Color(0xFF9ca3af),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _currentDateRangeLabel(),
                      style: const TextStyle(
                        color: Color(0xFF9ca3af),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Filtros ativados (ambiente de teste)')),
                  );
                },
                icon: const Icon(Icons.filter_alt, size: 16),
                label: const Text('Filtros'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF0ea5e9)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Novo registro (ambiente de teste)')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0ea5e9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                child: const Text('+ Novo registro'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopKpiRow(double width) {
    final isMobile = width <= 600;
    final children = [
      _buildKpiTile(
        'Total de Veículos',
        '$totalVeiculos',
        Icons.local_shipping,
        const Color(0xFF0ea5e9),
      ),
      SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 8 : 0),
      _buildKpiTile(
        'Veículos Ativos',
        '${(totalVeiculos - totalEmManutencao).clamp(0, totalVeiculos)}',
        Icons.local_shipping,
        const Color(0xFF0ea5e9),
      ),
      SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 8 : 0),
      _buildKpiTile(
        'Em Manutenção',
        '$totalEmManutencao',
        Icons.build,
        const Color(0xFFeab308),
      ),
      SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 8 : 0),
      _buildKpiTile(
        'Motoristas Ativos',
        '$totalMotoristas',
        Icons.person,
        const Color(0xFF0ea5e9),
      ),
      SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 8 : 0),
      _buildKpiTile(
        'Gasto Mensal',
        'R\$ ${totalGasto.toStringAsFixed(2)}',
        Icons.attach_money,
        const Color(0xFF22c55e),
      ),
      SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 8 : 0),
      _buildKpiTile(
        'Ocorrências Abertas',
        '$totalOcorrenciasAbertas',
        Icons.warning,
        const Color(0xFFef4444),
      ),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: children);
  }

  Widget _buildKpiTile(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0d1f3c),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: BorderSide(color: color, width: 4),
          left: const BorderSide(color: Color(0xFF1e293b)),
          right: const BorderSide(color: Color(0xFF1e293b)),
          bottom: const BorderSide(color: Color(0xFF1e293b)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF9ca3af),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsRow(double width) {
    final showRow = width > 1000;
    final children = [
      Expanded(child: SizedBox(height: 440, child: _buildConsumptionChart())),
      const SizedBox(width: 16),
      Expanded(child: SizedBox(height: 440, child: _buildCostPieChart())),
      const SizedBox(width: 16),
      Expanded(
        child: SizedBox(height: 440, child: _buildOccurrencesBarChart()),
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

  Widget _buildConsumptionChart() {
    final spots = monthlyFuelSpots;
    final labels = monthlyFuelLabels.isNotEmpty
        ? monthlyFuelLabels
        : ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun'];
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
    final maxY = spots.isNotEmpty
        ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2
        : 5.0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Consumo de Combustível',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Litros por mês',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.white12, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[value.toInt().clamp(0, labels.length - 1)],
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                clipData: FlClipData.all(),
                minX: 0,
                maxX: spots.length > 1 ? spots.last.x : 5,
                minY: 0,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    isStrokeCapRound: true,
                    color: AppColors.secondary,
                    barWidth: 4,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.secondary.withOpacity(0.26),
                          Colors.transparent,
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
    final costs = custosPorCategoria;
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
                  '${entry.value.key} — ${percent.toStringAsFixed(0)}% • R\$ ${value.toStringAsFixed(2)}',
            };
          }).toList()
        : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Custos da Frota',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Principais veículos por custo',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 40,
                      sectionsSpace: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: legendItems.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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
    final categories = ocorrenciasPorCategoria.entries.toList();
    final maxValue = categories.isEmpty
        ? 5
        : categories.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ocorrências por Categoria',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quantidade',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nenhuma ocorrência registrada',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            Column(
              children: categories.map((entry) {
                final widthFraction = maxValue > 0
                    ? (entry.value / maxValue).clamp(0.05, 1.0)
                    : 0.05;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: widthFraction,
                              child: Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.secondary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        entry.value.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomPanels(double width) {
    final showRow = width > 1000;
    final panels = [
      Expanded(child: _buildAlertsPanel()),
      const SizedBox(width: 16),
      Expanded(child: _buildRankingPanel()),
      const SizedBox(width: 16),
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
    return Container(
      padding: const EdgeInsets.all(22),
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
              const Expanded(
                child: Text(
                  'Alertas Importantes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AlertasPage()),
                  );
                  carregarDashboard();
                },
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    'Ver todos',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (alertasImportantes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nenhum alerta no momento',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...alertasImportantes.map(
              (alerta) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSoft,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: AppColors.warning),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alerta['title'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              alerta['subtitle'] ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
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
        ],
      ),
    );
  }

  Widget _buildRankingPanel() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ranking de Motoristas (Score)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          if (rankingMotoristas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nenhum motorista cadastrado',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...rankingMotoristas.map((driver) {
              final rank = rankingMotoristas.indexOf(driver) + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      '$rank',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        driver['name']?.toString() ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${driver['score']}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
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
    return Container(
      padding: const EdgeInsets.all(22),
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
              const Expanded(
                child: Text(
                  'Veículos com Maior Custo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AbastecimentosPage(),
                    ),
                  );
                  carregarDashboard();
                },
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    'Ver todos',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (topCostVehicles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nenhum dado de custo disponível',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...topCostVehicles.map((vehicle) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        vehicle['plate']?.toString() ?? 'Sem placa',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      'R\$ ${_toDouble(vehicle['value']).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
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

class _PieLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _PieLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

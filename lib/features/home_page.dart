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
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/frota_logo.dart';
import '../../shared/widgets/dashboard_card.dart';
import '../../shared/widgets/menu_card.dart';
import '../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;

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
    setState(() {
      carregando = true;
    });

    try {
      final veiculos = await supabase.from('vehicles').select();
      final motoristas = await supabase.from('drivers').select();
      final abastecimentos = await supabase.from('fuelings').select();
      final manutencoes = await supabase.from('manutencoes').select();
      final multas = await supabase.from('multas').select();
      final pneus = await supabase.from('pneus').select();
      final ocorrencias = await supabase.from('ocorrencias').select();
      final recents = await supabase
          .from('fuelings')
          .select(
            'id, liters, total_value, fuel_date, fuel_time, vehicles (plate), drivers (name)',
          )
          .order('created_at', ascending: false)
          .limit(3);

      final documentos = await supabase.from('documentos').select();

      double gasto = 0;
      for (var item in abastecimentos) {
        if (item['total_value'] != null) {
          gasto += (item['total_value'] as num).toDouble();
        }
      }

      // Add maintenance costs
      for (var item in manutencoes) {
        if (item['cost'] != null) {
          gasto += (item['cost'] as num).toDouble();
        }
        if (item['valor'] != null) {
          gasto += (item['valor'] as num).toDouble();
        }
        if (item['total_value'] != null) {
          gasto += (item['total_value'] as num).toDouble();
        }
      }

      // Add multa costs
      for (var item in multas) {
        if (item['amount'] != null) {
          gasto += (item['amount'] as num).toDouble();
        }
        if (item['valor'] != null) {
          gasto += (item['valor'] as num).toDouble();
        }
        if (item['fine_value'] != null) {
          gasto += (item['fine_value'] as num).toDouble();
        }
      }

      // Add pneus costs
      for (var item in pneus) {
        if (item['cost'] != null) {
          gasto += (item['cost'] as num).toDouble();
        }
        if (item['valor'] != null) {
          gasto += (item['valor'] as num).toDouble();
        }
      }

      final ocorrenciasAbertas = ocorrencias.where((item) {
        final status = (item['status'] ?? '').toString().toLowerCase();
        return status == 'aberto' || status == 'open';
      }).length;

      final categorias = _formatOcorrenciaCategorias(ocorrencias);
      final ranking = _formatRankingMotoristas(motoristas);
      final topVehicles = _buildTopCostVehicles(abastecimentos);
      final monthlySpots = _buildMonthlyFuelSpots(abastecimentos);
      final costByCategory = _buildCostByCategory(
        abastecimentos,
        manutencoes,
        pneus,
        multas,
      );
      // Tentar buscar alertas diretos da tabela 'alertas'
      List<Map<String, String>> alerts = [];
      try {
        final supAlerts = await supabase
            .from('alertas')
            .select()
            .order('created_at', ascending: false)
            .limit(8);
        if (supAlerts.isNotEmpty) {
          alerts = List<Map<String, String>>.from(
            supAlerts.map(
              (a) => {
                'title': (a['title'] ?? a['titulo'] ?? '').toString(),
                'subtitle':
                    (a['subtitle'] ?? a['descricao'] ?? a['detail'] ?? '')
                        .toString(),
              },
            ),
          );
        }
      } catch (_) {}

      // Se não houver alertas diretos, montar a partir de dados existentes
      if (alerts.isEmpty) {
        final List<Map<String, String>> built = [];

        // Ocorrências abertas
        final openOc = ocorrencias
            .where((item) {
              final status = (item['status'] ?? '').toString().toLowerCase();
              return status == 'aberto' ||
                  status == 'open' ||
                  status == 'pending';
            })
            .take(5);
        for (final o in openOc) {
          final tipo =
              o['problem_type'] ?? o['type'] ?? o['category'] ?? 'Ocorrência';
          built.add({
            'title': 'Ocorrência: ${tipo.toString()}',
            'subtitle':
                '${o['vehicles']?['plate'] ?? ''} • ${o['status'] ?? ''}',
          });
        }

        // Documentos vencendo (30 dias)
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
                'subtitle':
                    'Vence em $diff dias • ${doc['vehicles']?['plate'] ?? ''}',
              });
            }
          }
        }

        // CNH dos motoristas vencendo
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
                'title':
                    'CNH vencendo: ${m['name'] ?? m['nome'] ?? 'Motorista'}',
                'subtitle': 'Vence em $diff dias',
              });
            }
          }
        }

        // Caso ainda vazio, fornecer exemplos genéricos
        if (built.isEmpty) {
          built.addAll([
            {
              'title': 'Troca de óleo vencida',
              'subtitle': 'Verificar 3 veículos',
            },
            {'title': 'Checklists pendentes', 'subtitle': '7 veículos'},
          ]);
        }

        alerts = built.take(6).toList();
      }

setState(() {
         totalVeiculos = veiculos.length;
         totalMotoristas = motoristas.length;
         totalAbastecimentos = abastecimentos.length;
         totalEmManutencao = manutencoes.length;
         totalOcorrenciasAbertas = ocorrenciasAbertas;
         totalGasto = gasto;
         recentFuelings = List<Map<String, dynamic>>.from(recents);
         monthlyFuelSpots = monthlySpots;
         ocorrenciasPorCategoria = categorias;
         rankingMotoristas = ranking;
         topCostVehicles = topVehicles;
         alertasImportantes = alerts;
         custosPorCategoria = costByCategory;
       });
    } catch (e) {
      debugPrint('Erro ao carregar dashboard: ${e.toString()}');
    } finally {
      setState(() {
        carregando = false;
      });
    }
  }

  List<FlSpot> _buildMonthlyFuelSpots(List<dynamic> abastecimentos) {
    final months = <int, double>{};
    final now = DateTime.now();
    for (var item in abastecimentos) {
      final rawDate = item['fuel_date']?.toString() ?? '';
      final date = _parseDate(rawDate);
      if (date == null) continue;
      final key = date.year * 100 + date.month;
      months[key] =
          (months[key] ?? 0) + (item['liters'] as num? ?? 0).toDouble();
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
    }
    return spots;
  }

  DateTime? _parseDate(String rawDate) {
    if (rawDate.isEmpty) return null;

    return app_date_utils.DateUtils.parseDate(rawDate);
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
      if (item['total_value'] != null) {
        abastecimentoTotal += (item['total_value'] as num).toDouble();
      }
    }

    for (var item in manutencoes) {
      if (item['cost'] != null) {
        manutencaoTotal += (item['cost'] as num).toDouble();
      }
      if (item['valor'] != null) {
        manutencaoTotal += (item['valor'] as num).toDouble();
      }
      if (item['total_value'] != null) {
        manutencaoTotal += (item['total_value'] as num).toDouble();
      }
    }

    for (var item in pneus) {
      if (item['cost'] != null) {
        pneuTotal += (item['cost'] as num).toDouble();
      }
      if (item['valor'] != null) {
        pneuTotal += (item['valor'] as num).toDouble();
      }
    }

    for (var item in multas) {
      if (item['amount'] != null) {
        multaTotal += (item['amount'] as num).toDouble();
      }
      if (item['valor'] != null) {
        multaTotal += (item['valor'] as num).toDouble();
      }
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
      categorias.addAll({
        'Acidente': 3,
        'Falha Mecânica': 2,
        'Pane': 2,
        'Multa': 1,
        'Outros': 1,
      });
    }
    return categorias;
  }

  List<Map<String, dynamic>> _formatRankingMotoristas(
    List<dynamic> motoristas,
  ) {
    final ranking = motoristas
        .map(
          (item) => {
            'name': item['name']?.toString() ?? 'Motorista',
            'score': 70 + ((item['name']?.toString().length ?? 0) % 31),
          },
        )
        .toList();
    ranking.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    final defaults = [
      {'name': 'Marcos Silva', 'score': 98},
      {'name': 'João Santos', 'score': 92},
      {'name': 'Carlos Lima', 'score': 87},
      {'name': 'Pedro Oliveira', 'score': 75},
      {'name': 'Lucas Almeida', 'score': 70},
    ];
    if (ranking.length >= 5) {
      return ranking.take(5).toList();
    }
    final combined = [...ranking, ...defaults]
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return combined.take(5).toList();
  }

  List<Map<String, dynamic>> _buildTopCostVehicles(
    List<Map<String, dynamic>> fuelings,
  ) {
    final costs = <String, double>{};
    for (final item in fuelings) {
      final placa = item['vehicles']?['plate']?.toString() ?? 'Sem placa';
      final valor = (item['total_value'] as num?)?.toDouble() ?? 0;
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
            IconButton(icon: const Icon(Icons.search), onPressed: () {}),
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () {},
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
appBar: AppBar(
        title: const FrotaLogo(compact: false),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Novo registro'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
        elevation: 0,
        backgroundColor: AppColors.surface,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final showSidebar = constraints.maxWidth > 1200;
                final width = constraints.maxWidth;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSidebar)
                      Container(
                        width: 300,
                        margin: const EdgeInsets.only(
                          left: 20,
                          top: 20,
                          bottom: 20,
                        ),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.16),
                              blurRadius: 30,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppLogo(compact: false),
                            const SizedBox(height: 10),
                            const Text(
                              'Gestão de frota empresarial',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _buildSidebarItem(
                              Icons.dashboard,
                              'Visão Geral',
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
                                    builder: (_) => const VeiculosPage(),
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
                                    builder: (_) => const MotoristasPage(),
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
                                    builder: (_) => const AbastecimentosPage(),
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
                              Icons.build,
                              'Manutenções',
                              () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ManutencoesPage(),
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
                                    builder: (_) => const RelatoriosPage(),
                                  ),
                                );
                                carregarDashboard();
                              },
                            ),
                            _buildSidebarItem(
                              Icons.checklist,
                              'Checklist',
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
                                    builder: (_) => const DocumentosPage(),
                                  ),
                                );
                                carregarDashboard();
                              },
                            ),
                            _buildSidebarItem(
                              Icons.directions,
                              'Viagens',
                              () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ViagensPage(),
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
                                    builder: (_) => const ConfiguracoesPage(),
                                  ),
                                );
                                carregarDashboard();
                              },
                            ),
                            const SizedBox(height: 18),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 12),
                            _buildProfileCard(),
                          ],
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: carregarDashboard,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: 20,
                              bottom: 20,
                              left: showSidebar ? 20 : 20,
                              right: 20,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeader(width),
                                const SizedBox(height: 24),
                                _buildTopKpiRow(width),
                                const SizedBox(height: 24),
                                _buildChartsRow(width),
                                const SizedBox(height: 24),
                                _buildBottomPanels(width),
                                const SizedBox(height: 24),
                                _buildActionGrid(
                                  width > 1100
                                      ? 4
                                      : width > 760
                                      ? 3
                                      : 2,
                                ),
                              ],
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
            color: active
                ? AppColors.secondary.withOpacity(0.18)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppColors.secondary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active ? AppColors.secondary : Colors.white,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? AppColors.secondary : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
    final auth = AuthService();
    final supaUser = supabase.auth.currentUser;
    final metadata = (supaUser?.userMetadata ?? {}) as Map<String, dynamic>?;

final name = getProfileDisplayName(
      authServiceUser: auth.currentUser as Map<String, dynamic>?,
      metadata: metadata,
      supaEmail: supaUser?.email,
    );
    final email = auth.currentUser?.email ?? supaUser?.email ?? '';

    final photoUrl = getProfilePhotoUrl(metadata, supabaseClient: supabase);

    final initials = name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join();

    Widget avatar = photoUrl != null && photoUrl.isNotEmpty
        ? CircleAvatar(
            radius: 28,
            backgroundImage: NetworkImage(photoUrl),
          )
        : CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.secondary,
            child: Text(
              initials.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          );

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
        );
        carregarDashboard();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email.toString(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
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

  Widget _buildHeader(double width) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 100,
padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'Dashboard',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'Visão geral da frota',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Visão geral da frota',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Acompanhe o desempenho da frota, custos e alertas em um único painel.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        height: 1.75,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _buildHeaderStat(
                          'Gasto total',
                          'R\$ ${totalGasto.toStringAsFixed(2)}',
                          AppColors.danger,
                        ),
                        _buildHeaderStat(
                          'Abastecimentos',
                          '$totalAbastecimentos',
                          AppColors.warning,
                        ),
                        _buildHeaderStat(
                          'Ocorrências',
                          '$totalOcorrenciasAbertas abertas',
                          AppColors.secondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Container(
                width: 220,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Text(
                       'Status geral',
                       style: TextStyle(
                         color: AppColors.textSecondary,
                         fontSize: 13,
                       ),
                     ),
                     SizedBox(height: 18),
                     Text(
                       'Operacional',
                       style: TextStyle(
                         color: Colors.white,
                         fontSize: 20,
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                     SizedBox(height: 10),
                     Text(
                       'Sem incidentes críticos nas últimas 24h',
                       style: TextStyle(
                         color: AppColors.textSecondary,
                         fontSize: 13,
                         height: 1.7,
                       ),
                     ),
                     SizedBox(height: 18),
                     Container(
                       padding:
                           EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                       decoration: BoxDecoration(
                         color: AppColors.background,
                         borderRadius: BorderRadius.circular(16),
                         border: Border.all(color: AppColors.border),
                       ),
                       child: Text(
                          'Atualizado agora',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
),
     );
   }

   Widget _buildRecentFuelings(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Últimos abastecimentos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border),
          ),
          child: recentFuelings.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  alignment: Alignment.center,
                  child: const Text(
                    'Nenhum abastecimento recente encontrado.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : Column(
                  children: recentFuelings.map((item) {
                    final placa = item['vehicles']?['plate'] ?? 'Sem placa';
                    final motorista =
                        item['drivers']?['name'] ?? 'Sem motorista';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSoft,
                          borderRadius: BorderRadius.circular(22),
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
                                    color: AppColors.secondary.withOpacity(
                                      0.16,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.local_gas_station,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'R\$ ${item['total_value'] ?? 0}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  item['fuel_date'] ?? '--/--/----',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Veículo: $placa',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Motorista: $motorista',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _infoTag('${item['liters'] ?? 0} L'),
                                const SizedBox(width: 10),
                                _infoTag(item['fuel_time'] ?? '--:--'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _infoTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildActionGrid(int menuColumns) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ações rápidas',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: menuColumns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
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
            MenuCard(
              icon: Icons.person,
              title: 'Motoristas',
              color: const Color(0xFF1AA251),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MotoristasPage()),
                );
                carregarDashboard();
              },
            ),
            MenuCard(
              icon: Icons.local_gas_station,
              title: 'Abastecer',
              color: const Color(0xFFF7B500),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AbastecimentosPage()),
                );
                carregarDashboard();
              },
            ),
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
            MenuCard(
              icon: Icons.bar_chart,
              title: 'Relatórios',
              color: const Color(0xFF0F766E),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RelatoriosPage()),
                );
                carregarDashboard();
              },
            ),
            MenuCard(
              icon: Icons.checklist,
              title: 'Checklist',
              color: const Color(0xFF059669),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SelecionarVeiculoChecklistPage(),
                  ),
                );
                carregarDashboard();
              },
            ),
            MenuCard(
              icon: Icons.receipt_long,
              title: 'Multas',
              color: const Color(0xFFDC2626),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MultasPage()),
                );
                carregarDashboard();
              },
            ),
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
            MenuCard(
              icon: Icons.description,
              title: 'Documentos',
              color: const Color(0xFF2563EB),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DocumentosPage()),
                );
                carregarDashboard();
              },
            ),
            MenuCard(
              icon: Icons.directions,
              title: 'Viagens',
              color: const Color(0xFFF59E0B),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ViagensPage()),
                );
                carregarDashboard();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopKpiRow(double width) {
    return Row(
      children: [
        Expanded(
          child: _buildKpiTile(
            'Total de Veículos',
            '$totalVeiculos',
            Icons.directions_car,
            AppColors.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiTile(
            'Veículos Ativos',
            '${(totalVeiculos - totalEmManutencao).clamp(0, totalVeiculos)}',
            Icons.directions_bus,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiTile(
            'Em Manutenção',
            '$totalEmManutencao',
            Icons.build_circle,
            AppColors.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiTile(
            'Motoristas Ativos',
            '$totalMotoristas',
            Icons.person,
            AppColors.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiTile(
            'Gasto Mensal',
            'R\$ ${totalGasto.toStringAsFixed(2)}',
            Icons.attach_money,
            AppColors.danger,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiTile(
            'Ocorrências Abertas',
            '$totalOcorrenciasAbertas',
            Icons.warning,
            AppColors.danger,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiTile(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
                  style: TextStyle(
                    color: AppColors.textSecondary,
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
      Expanded(
        child: SizedBox(height: 320, child: _buildConsumptionChart()),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: SizedBox(height: 320, child: _buildCostPieChart()),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: SizedBox(height: 320, child: _buildOccurrencesBarChart()),
      ),
    ];
    return showRow
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 320, child: _buildConsumptionChart()),
              const SizedBox(height: 16),
              SizedBox(height: 320, child: _buildCostPieChart()),
              const SizedBox(height: 16),
              SizedBox(height: 320, child: _buildOccurrencesBarChart()),
            ],
          );
  }

  Widget _buildConsumptionChart() {
    final spots = monthlyFuelSpots.isNotEmpty
        ? monthlyFuelSpots
        : [
            FlSpot(0, 2.5),
            FlSpot(1, 3.2),
            FlSpot(2, 2.8),
            FlSpot(3, 3.6),
            FlSpot(4, 3.3),
            FlSpot(5, 3.9),
          ];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
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
          SizedBox(
            height: 320,
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
                      getTitlesWidget: (value, meta) {
                        final labels = [
                          'Jan',
                          'Fev',
                          'Mar',
                          'Abr',
                          'Mai',
                          'Jun',
                        ];
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
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
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
              'label': '${entry.value.key} — ${percent.toStringAsFixed(0)}%',
            };
          }).toList()
        : [
            {'color': AppColors.secondary, 'label': 'Abastecimento 60%'},
            {'color': AppColors.success, 'label': 'Manutenção 20%'},
            {'color': AppColors.warning, 'label': 'Pneus 10%'},
            {'color': AppColors.danger, 'label': 'Multas 6%'},
            {'color': AppColors.primary, 'label': 'Outros 4%'},
          ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
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
          SizedBox(
            height: 320,
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
        ? 5.0
        : (categories.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 2);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
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
          SizedBox(
            height: 280,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                maxY: maxValue,
                barGroups: categories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: data.value.toDouble(),
                        color: AppColors.secondary,
                        width: 22,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final labels = categories.map((e) => e.key).toList();
                        final text =
                            labels[value.toInt().clamp(0, labels.length - 1)];
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 6,
                          child: Text(
                            text,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
              ),
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
        borderRadius: BorderRadius.circular(28),
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
        borderRadius: BorderRadius.circular(28),
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
                      style: const TextStyle(color: Colors.white, fontSize: 15),
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
        borderRadius: BorderRadius.circular(28),
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
                  Expanded(
                    child: Text(
                      vehicle['plate']?.toString() ?? 'Sem placa',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                  Text(
                    'R\$ ${vehicle['value']?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(color: AppColors.textSecondary),
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

import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/config/supabase_config.dart';
import '../../core/utils/snackbar_utils.dart';
import '../admin/admin_usuarios_page.dart';
import '../veiculos/veiculos_page.dart';
import '../motoristas/motoristas_page.dart';
import '../abastecimentos/lista_abastecimentos_page.dart';
import '../manutencoes/manutencoes_page.dart';
import '../../pages/lista_ocorrencias_page.dart';
import '../checklists/historico_checklist_page.dart';
import '../relatorios/relatorios_page.dart';
import '../configuracoes/configuracoes_page.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────
enum _Sec {
  painel, empresas, usuarios, veiculos, motoristas,
  abastecimentos, manutencoes, ocorrencias, checklists,
  relatorios, configuracoes,
}

// ─── Data models ─────────────────────────────────────────────────────────────
class _KpiData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String trend;
  final bool trendUp;
  final List<double> spark;
  const _KpiData({
    required this.label, required this.value, required this.icon,
    required this.color, this.trend = '', this.trendUp = true,
    this.spark = const [],
  });
}

class _AlertItem {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  const _AlertItem(this.icon, this.color, this.label, this.count);
}

class _ActivityItem {
  final String hora;
  final IconData icon;
  final Color color;
  final String texto;
  const _ActivityItem(this.hora, this.icon, this.color, this.texto);
}

class _EmpresaRating {
  final int rank;
  final String nome;
  final double score;
  const _EmpresaRating(this.rank, this.nome, this.score);
}

// ─── Widget principal ─────────────────────────────────────────────────────────
class MasterDashboardPage extends StatefulWidget {
  const MasterDashboardPage({super.key});
  @override
  State<MasterDashboardPage> createState() => _MasterDashboardPageState();
}

class _MasterDashboardPageState extends State<MasterDashboardPage> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _timer;
  Timer? _realtimeDebounce;

  // ── Estado ─────────────────────────────────────────────────────────────────
  bool _loading = true;
  DateTime? _lastUpdated;
  _Sec _activeSection = _Sec.painel;

  // KPIs
  int _totalEmpresas = 0;
  int _empresasAtivas = 0;
  int _empresasOnline = 0;
  int _totalUsuarios = 0;
  int _totalVeiculos = 0;
  int _totalMotoristas = 0;
  int _totalAbastecimentos = 0;
  int _totalOcorrencias = 0;
  int _totalManutencoes = 0;
  double _receitaMes = 0;
  int _novasEmpresas = 0;

  // Trends
  double _tendEmpresas = 0, _tendUsuarios = 0, _tendVeiculos = 0;
  double _tendMotoristas = 0, _tendAbast = 0, _tendReceita = 0;
  double _tendChecks = 0, _tendOcorr = 0;

  // Alertas
  int _veiculosOffline = 0;
  int _manutencoesVencidas = 0;
  int _cnhsVencendo = 0;
  int _mensalidadesAtrasadas = 0;
  int _ocorrenciasAbertas = 0;

  // Atividade recente
  List<_ActivityItem> _atividades = [];

  // Distribuição de status (empresas)
  int _statusAtivo = 0, _statusSuspenso = 0;
  int _statusCancelado = 0, _statusBloqueado = 0;

  // Rating empresas
  List<_EmpresaRating> _ratings = [];

  // Receita mensal (6 meses)
  List<double> _receitaMensal6m = [0, 0, 0, 0, 0, 0];
  List<String> _mesesLabels = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun'];

  // Lista de empresas completa (para dialogs)
  List<Map<String, dynamic>> _empresasList = [];

  // Sparklines semanais (8 pontos)
  List<double> _sparkEmpresas = [];
  List<double> _sparkUsuarios = [];
  List<double> _sparkVeiculos = [];
  List<double> _sparkMotoristas = [];
  List<double> _sparkAbast = [];
  List<double> _sparkManut = [];
  List<double> _sparkOcorr = [];
  List<double> _sparkOnline = [];
  List<double> _sparkReceita = [];
  List<double> _sparkNovas = [];


  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final auth = context.read<AppAuthProvider>();
    if (auth.isMaster) {
      _loadAll();
      _setupRealtime();
      // Realtime já cobre mudanças em empresas/vehicles/occurrences; este timer
      // é só um fallback de segurança (reconexão perdida) e para atualizar o
      // indicador de "usuários online", que muda com o tempo, não com escrita no banco.
      _timer = Timer.periodic(const Duration(minutes: 3), (_) => _loadAll());
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _timer?.cancel();
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  void _debounceLoad() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 500), _loadAll);
  }

  // ── Helper: query segura (nunca derruba o Future.wait) ────────────────────
  Future<List<Map<String, dynamic>>> _safeQ(Future<dynamic> query) async {
    try {
      final r = await query;
      return List<Map<String, dynamic>>.from(
          (r as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (e) {
      debugPrint('Dashboard query error: $e');
      return [];
    }
  }

  // ── Helper: contagem real no banco (não baixa os registros) ───────────────
  // O chamador passa a query já terminada em `.count()`.
  Future<int> _safeCount(Future<dynamic> query) async {
    try {
      final res = await query;
      return (res.count as int?) ?? 0;
    } catch (e) {
      debugPrint('Dashboard count error: $e');
      return 0;
    }
  }

  // ── Carregamento de dados ───────────────────────────────────────────────────
  Future<void> _loadAll() async {
    try {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1);
      final lastMonth = DateTime(now.year, now.month - 1, 1);
      final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
      final in30Days = now.add(const Duration(days: 30));
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      // Cada query é independente — falha isolada não derruba as demais
      final results = await Future.wait([
        // 0: empresas completas
        _safeQ(_supabase.from('empresas').select()),
        // 1: user_profiles
        _safeQ(_supabase.from('user_profiles').select('user_id, last_access, empresa_id, created_at')),
        // 2: veículos
        _safeQ(_supabase.from('vehicles').select('id, empresa_id, created_at, odometer')),
        // 3: motoristas
        _safeQ(_supabase.from('drivers').select('id, empresa_id, cnh_expiration, created_at')),
        // 4: abastecimentos últimos 6 meses
        _safeQ(_supabase.from('fuelings')
            .select('id, empresa_id, total_value, fuel_date, vehicle_id, created_at')
            .gte('fuel_date', sixMonthsAgo.toIso8601String().split('T')[0])
            .order('created_at', ascending: false)),
        // 5: checklists — só os últimos 2 meses (suficiente para a tendência
        // mês-a-mês; total real vem de uma contagem separada, abaixo)
        _safeQ(_supabase.from('checklists')
            .select('id, empresa_id, tipo, vehicle_id, driver_id, created_at')
            .gte('created_at', lastMonth.toIso8601String())
            .order('created_at', ascending: false)),
        // 6: ocorrências — últimos 2 meses (idem; abertas antigas são cobertas
        // pela contagem separada de "ocorrências abertas", abaixo)
        _safeQ(_supabase.from('occurrences')
            .select('id, empresa_id, status, created_at')
            .gte('created_at', lastMonth.toIso8601String())
            .order('created_at', ascending: false)),
        // 7: oil_changes (manutenções)
        _safeQ(_supabase.from('oil_changes')
            .select('id, vehicle_id, created_at, next_change_km')
            .order('created_at', ascending: false)),
        // 8: usuários online (last_access recente)
        _safeQ(_supabase.from('user_profiles')
            .select('empresa_id')
            .not('empresa_id', 'is', null)
            .gte('last_access',
                now.subtract(const Duration(minutes: 30)).toIso8601String())),
        // 9: manutencoes (tabela opcional — safeQ retorna [] se não existir)
        _safeQ(_supabase.from('manutencoes').select('id').limit(500)),
      ]);

      // Contagens reais no banco — não truncam e não baixam os registros.
      final countResults = await Future.wait([
        _safeCount(_supabase.from('fuelings').select('id').count(CountOption.exact)),
        _safeCount(_supabase.from('occurrences').select('id').count(CountOption.exact)),
        _safeCount(_supabase.from('occurrences')
            .select('id')
            .inFilter('status', ['Aberto', 'Em andamento', 'Em Andamento', 'aberto', 'em_andamento'])
            .count(CountOption.exact)),
      ]);
      final totalAbastecimentosReal = countResults[0];
      final totalOcorrenciasReal = countResults[1];
      final ocorrAbertasReal = countResults[2];

      final empresas = results[0];
      final profiles = results[1];
      final veiculos = results[2];
      final motoristas = results[3];
      final fuelings = results[4];
      final checklists = results[5];
      final ocorrencias = results[6];
      final oilChanges = results[7];
      final online = results[8];
      final manutExtra = results[9];
      final manutTotal = manutExtra.length + oilChanges.length;

      final onlineIds = online.map((p) => p['empresa_id']).whereType<String>().toSet();

      // ── Trends (this month vs last month) ──────────────────────────────────
      int cnt(List<Map<String,dynamic>> list, DateTime from, DateTime? to) {
        final toTs = to ?? DateTime.now();
        return list.where((r) {
          final raw = r['created_at']?.toString() ?? r['fuel_date']?.toString() ?? '';
          final dt = DateTime.tryParse(raw);
          if (dt == null) return false;
          return dt.isAfter(from) && dt.isBefore(toTs);
        }).length;
      }

      final empThisM = cnt(empresas, thisMonth, null);
      final empLastM = cnt(empresas, lastMonth, thisMonth);
      final userThisM = cnt(profiles, thisMonth, null);
      final userLastM = cnt(profiles, lastMonth, thisMonth);
      final veicThisM = cnt(veiculos, thisMonth, null);
      final veicLastM = cnt(veiculos, lastMonth, thisMonth);
      final motThisM = cnt(motoristas, thisMonth, null);
      final motLastM = cnt(motoristas, lastMonth, thisMonth);
      final abastThisM = cnt(fuelings, thisMonth, null);
      final abastLastM = cnt(fuelings, lastMonth, thisMonth);
      final checkThisM = cnt(checklists, thisMonth, null);
      final checkLastM = cnt(checklists, lastMonth, thisMonth);
      final ocorrThisM = cnt(ocorrencias, thisMonth, null);
      final ocorrLastM = cnt(ocorrencias, lastMonth, thisMonth);

      double trend(int cur, int prv) =>
          prv > 0 ? (cur - prv) / prv * 100 : (cur > 0 ? 100 : 0);

      // ── Receita ────────────────────────────────────────────────────────────
      double recMes = 0;
      final receitaByMonth = <int, double>{};
      for (final f in fuelings) {
        final val = (f['total_value'] as num?)?.toDouble() ?? 0;
        final rawDate = f['fuel_date']?.toString() ?? f['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(rawDate);
        if (dt != null) {
          final key = dt.year * 100 + dt.month;
          receitaByMonth[key] = (receitaByMonth[key] ?? 0) + val;
          if (!dt.isBefore(thisMonth)) recMes += val;
        }
      }
      final recLastM = receitaByMonth[(lastMonth.year * 100 + lastMonth.month)] ?? 0;
      final recThisM = recMes;

      // ── Receita 6 meses ────────────────────────────────────────────────────
      final months6 = <DateTime>[];
      for (int i = 5; i >= 0; i--) {
        final dt = DateTime(now.year, now.month - i, 1);
        months6.add(dt);
      }
      final labels6 = months6.map((d) {
        const mn = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
        return mn[d.month - 1];
      }).toList();
      final receita6 = months6.map((d) {
        final key = d.year * 100 + d.month;
        return receitaByMonth[key] ?? 0.0;
      }).toList();

      // ── Alertas ─────────────────────────────────────────────────────────────
      // CNHs vencendo em 30 dias
      final cnhVencendo = motoristas.where((m) {
        final raw = m['cnh_expiration']?.toString() ?? '';
        final dt = DateTime.tryParse(raw);
        if (dt == null) return false;
        return dt.isBefore(in30Days) && dt.isAfter(now);
      }).length;

      // Ocorrências abertas — contagem real no banco (ocorrAbertasReal),
      // não filtrada em memória a partir da janela de 2 meses acima, porque
      // uma ocorrência aberta há mais tempo continuaria "aberta" e não pode
      // ser perdida por causa da janela.
      final ocorrAbertas = ocorrAbertasReal;

      // Empresas com mensalidade atrasada (status suspenso/cancelado)
      final mensAtrasadas = empresas.where((e) {
        final s = (e['status'] ?? '').toString();
        return s == 'suspenso' || s == 'cancelado';
      }).length;

      // Veículos sem abastecimento nos últimos 7 dias
      final veicComAbast = fuelings.where((f) {
        final raw = f['fuel_date']?.toString() ?? f['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(raw);
        return dt != null && dt.isAfter(sevenDaysAgo);
      }).map((f) => f['vehicle_id']?.toString()).whereType<String>().toSet();
      final veicOffline = veiculos.length - veicComAbast.length;

      // Manutenções vencidas: para cada veículo, compara o odômetro atual
      // com o next_change_km da troca de óleo mais recente — mesmo critério
      // já usado em manutencoes_page.dart/plano_manutencao_page.dart (dentro
      // de 2000 km do previsto, ou já passado, conta como vencida). O cálculo
      // anterior ("total histórico menos trocas deste mês") não tinha
      // nenhuma relação com manutenção realmente vencida.
      final odomPorVeiculo = <String, int>{
        for (final v in veiculos)
          if (v['id'] != null) v['id'].toString(): (v['odometer'] as num?)?.toInt() ?? 0,
      };
      int manutVencidas = 0;
      final vistosManut = <String>{};
      for (final o in oilChanges) {
        final vid = o['vehicle_id']?.toString();
        if (vid == null || vistosManut.contains(vid)) continue;
        vistosManut.add(vid);
        final nextKm = (o['next_change_km'] as num?)?.toInt() ?? 0;
        if (nextKm <= 0) continue;
        final atualKm = odomPorVeiculo[vid] ?? 0;
        if (atualKm >= nextKm - 2000) manutVencidas++;
      }

      // ── Distribuição de status ─────────────────────────────────────────────
      int stAtivo = 0, stSusp = 0, stCanc = 0, stBloq = 0;
      for (final e in empresas) {
        final s = (e['status'] ?? '').toString();
        if (s == 'ativo') {
          stAtivo++;
        } else if (s == 'suspenso') stSusp++;
        else if (s == 'cancelado') stCanc++;
        else if (s == 'bloqueado') stBloq++;
      }

      // ── Rating empresas ───────────────────────────────────────────────────
      final veicByEmp = <String, int>{};
      for (final v in veiculos) {
        final eid = v['empresa_id']?.toString() ?? '';
        if (eid.isNotEmpty) veicByEmp[eid] = (veicByEmp[eid] ?? 0) + 1;
      }
      final fulingByEmp = <String, int>{};
      for (final f in fuelings) {
        final eid = f['empresa_id']?.toString() ?? '';
        if (eid.isNotEmpty) fulingByEmp[eid] = (fulingByEmp[eid] ?? 0) + 1;
      }
      final checkByEmp = <String, int>{};
      for (final c in checklists) {
        final eid = c['empresa_id']?.toString() ?? '';
        if (eid.isNotEmpty) checkByEmp[eid] = (checkByEmp[eid] ?? 0) + 1;
      }
      final maxVeic = veicByEmp.values.fold(1, math.max);
      final maxFuel = fulingByEmp.values.fold(1, math.max);
      final maxCheck = checkByEmp.values.fold(1, math.max);

      final ratings = <_EmpresaRating>[];
      for (final e in empresas) {
        if ((e['status'] ?? '') != 'ativo') continue;
        final eid = (e['id'] ?? '').toString();
        final nome = (e['nome'] ?? '').toString();
        if (nome.isEmpty) continue;
        final sv = (veicByEmp[eid] ?? 0) / maxVeic;
        final sf = (fulingByEmp[eid] ?? 0) / maxFuel;
        final sc = (checkByEmp[eid] ?? 0) / maxCheck;
        final score = (sv * 0.4 + sf * 0.4 + sc * 0.2) * 100;
        ratings.add(_EmpresaRating(0, nome, score));
      }
      ratings.sort((a, b) => b.score.compareTo(a.score));
      final top5 = ratings.take(5).toList();
      final ratingsFinal = <_EmpresaRating>[];
      for (int i = 0; i < top5.length; i++) {
        ratingsFinal.add(_EmpresaRating(i + 1, top5[i].nome, top5[i].score));
      }

      // ── Atividade recente ─────────────────────────────────────────────────
      final activities = <_ActivityItem>[];
      String fmtHora(String? raw) {
        if (raw == null) return '--:--';
        final dt = DateTime.tryParse(raw);
        if (dt == null) return '--:--';
        final local = dt.toLocal();
        return '${local.hour.toString().padLeft(2,'0')}:${local.minute.toString().padLeft(2,'0')}';
      }
      // Fuelings recentes
      for (final f in fuelings.take(4)) {
        final hora = fmtHora(f['created_at']?.toString());
        final empNome = empresas
            .firstWhere((e) => e['id']?.toString() == f['empresa_id']?.toString(),
                orElse: () => {'nome': 'Empresa'})['nome'] ?? 'Empresa';
        activities.add(_ActivityItem(
          hora, Icons.local_gas_station_rounded, const Color(0xFFF59E0B),
          'Abastecimento registrado – $empNome',
        ));
      }
      // Checklists recentes
      for (final c in checklists.take(3)) {
        final hora = fmtHora(c['created_at']?.toString());
        final tipo = (c['tipo'] ?? 'saida').toString();
        activities.add(_ActivityItem(
          hora, Icons.build_rounded, const Color(0xFF22C55E),
          'Checklist de ${tipo == 'saida' ? 'saída' : 'retorno'} concluído',
        ));
      }
      // Ocorrências recentes
      for (final o in ocorrencias.take(3)) {
        final hora = fmtHora(o['created_at']?.toString());
        activities.add(_ActivityItem(
          hora, Icons.report_problem_rounded, const Color(0xFFEF4444),
          'Ocorrência ${(o['status'] ?? 'aberta').toString().toLowerCase()} registrada',
        ));
      }
      // Novos veículos (last 2 added)
      final veicRecentes = [...veiculos]..sort((a, b) =>
          (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
      for (final v in veicRecentes.take(2)) {
        final hora = fmtHora(v['created_at']?.toString());
        final empNome = empresas
            .firstWhere((e) => e['id']?.toString() == v['empresa_id']?.toString(),
                orElse: () => {'nome': 'Empresa'})['nome'] ?? 'Empresa';
        activities.add(_ActivityItem(
          hora, Icons.directions_car_rounded, const Color(0xFF3B82F6),
          '$empNome adicionou novo veículo',
        ));
      }
      // Sort all by hora descending (approximate — mix of times)
      activities.sort((a, b) => b.hora.compareTo(a.hora));

      // ── Sparklines (baseadas em dados reais agrupados) ────────────────────
      List<double> weeklyCount(List<Map<String,dynamic>> list, String dateField) {
        final now2 = DateTime.now();
        return List.generate(8, (i) {
          final from = now2.subtract(Duration(days: (7 - i) * 7 + 7));
          final to = now2.subtract(Duration(days: (7 - i) * 7));
          return list.where((r) {
            final raw = r[dateField]?.toString() ?? r['created_at']?.toString() ?? '';
            final dt = DateTime.tryParse(raw);
            return dt != null && dt.isAfter(from) && dt.isBefore(to);
          }).length.toDouble();
        });
      }
      List<double> weeklySum(List<Map<String,dynamic>> list, String valField, String dateField) {
        final now2 = DateTime.now();
        return List.generate(8, (i) {
          final from = now2.subtract(Duration(days: (7 - i) * 7 + 7));
          final to = now2.subtract(Duration(days: (7 - i) * 7));
          double sum = 0;
          for (final r in list) {
            final raw = r[dateField]?.toString() ?? r['created_at']?.toString() ?? '';
            final dt = DateTime.tryParse(raw);
            if (dt != null && dt.isAfter(from) && dt.isBefore(to)) {
              sum += (r[valField] as num?)?.toDouble() ?? 0;
            }
          }
          return sum;
        });
      }

      final sparkEmp = weeklyCount(empresas, 'created_at');
      final sparkUser = weeklyCount(profiles, 'created_at');
      final sparkVeic = weeklyCount(veiculos, 'created_at');
      final sparkMot = weeklyCount(motoristas, 'created_at');
      final sparkAb = weeklyCount(fuelings, 'fuel_date');
      final sparkManutWeekly = weeklyCount(oilChanges, 'created_at');
      final sparkOc = weeklyCount(ocorrencias, 'created_at');
      final sparkRec = weeklySum(fuelings, 'total_value', 'fuel_date');
      // Online e novas: use total count as flat sparkline with slight variation
      double total = _totalEmpresas.toDouble();
      final sparkOnl = List.generate(8, (i) => math.max(0.0, total * 0.8 + i * total * 0.03));
      final sparkNov = weeklyCount(empresas, 'created_at');

      // ── Novas empresas este mês ────────────────────────────────────────────
      final novasEmp = empresas.where((e) {
        final raw = e['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(raw);
        return dt != null && !dt.isBefore(thisMonth);
      }).length;

      if (!mounted) return;
      setState(() {
        _empresasList = empresas;
        _totalEmpresas = empresas.length;
        _empresasAtivas = stAtivo;
        _empresasOnline = onlineIds.length;
        _totalUsuarios = profiles.length;
        _totalVeiculos = veiculos.length;
        _totalMotoristas = motoristas.length;
        _totalAbastecimentos = totalAbastecimentosReal;
        _totalOcorrencias = totalOcorrenciasReal;
        _totalManutencoes = manutTotal;
        _receitaMes = recMes;
        _novasEmpresas = novasEmp;

        _tendEmpresas = trend(empThisM, empLastM);
        _tendUsuarios = trend(userThisM, userLastM);
        _tendVeiculos = trend(veicThisM, veicLastM);
        _tendMotoristas = trend(motThisM, motLastM);
        _tendAbast = trend(abastThisM, abastLastM);
        _tendReceita = trend(recThisM.toInt(), recLastM.toInt());
        _tendChecks = trend(checkThisM, checkLastM);
        _tendOcorr = trend(ocorrThisM, ocorrLastM);

        _veiculosOffline = math.max(0, veicOffline);
        _manutencoesVencidas = manutVencidas;
        _cnhsVencendo = cnhVencendo;
        _mensalidadesAtrasadas = mensAtrasadas;
        _ocorrenciasAbertas = ocorrAbertas;

        _atividades = activities.take(8).toList();

        _statusAtivo = stAtivo;
        _statusSuspenso = stSusp;
        _statusCancelado = stCanc;
        _statusBloqueado = stBloq;

        _ratings = ratingsFinal;
        _receitaMensal6m = receita6;
        _mesesLabels = labels6;

        _sparkEmpresas = sparkEmp;
        _sparkUsuarios = sparkUser;
        _sparkVeiculos = sparkVeic;
        _sparkMotoristas = sparkMot;
        _sparkAbast = sparkAb;
        _sparkManut = sparkManutWeekly;
        _sparkOcorr = sparkOc;
        _sparkReceita = sparkRec;
        _sparkOnline = sparkOnl;
        _sparkNovas = sparkNov;

        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      debugPrint('MasterDashboard._loadAll error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setupRealtime() {
    _channel = _supabase
        .channel('master_dash_v2')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'empresas',
          callback: (_) => _debounceLoad(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'vehicles',
          callback: (_) => _debounceLoad(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'occurrences',
          callback: (_) => _debounceLoad(),
        )
        .subscribe();
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.isMaster) {
      return const Scaffold(
        backgroundColor: Color(0xFF060C18),
        body: Center(child: Text('Acesso restrito ao MASTER', style: TextStyle(color: Colors.white))),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF060C18),
      body: Row(
        children: [
          _buildSidebar(auth),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIDEBAR
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSidebar(AppAuthProvider auth) {
    void nav(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page))
            .then((_) { if (mounted) setState(() => _activeSection = _Sec.painel); });

    Widget navItem(IconData icon, String label, _Sec sec, VoidCallback? action) {
      final active = _activeSection == sec;
      return _sidebarItem(icon, label, active: active, onTap: () {
        setState(() => _activeSection = sec);
        action?.call();
      });
    }

    Widget catHeader(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 3),
      child: Text(label, style: const TextStyle(
        color: Color(0xFF334155), fontSize: 9,
        fontWeight: FontWeight.w700, letterSpacing: 1.4,
      )),
    );

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF080F1E),
        border: Border(right: BorderSide(color: Color(0xFF0E1E33))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  alignment: Alignment.center,
                  child: const Text('F', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('FrotaCheck', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('MASTER', style: TextStyle(color: Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                ]),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFF0E1E33)),
          const SizedBox(height: 4),

          // Nav items agrupados por categoria
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                catHeader('PAINEL'),
                navItem(Icons.dashboard_rounded, 'Painel Geral', _Sec.painel, null),
                catHeader('OPERAÇÃO'),
                navItem(Icons.directions_car_rounded, 'Veículos', _Sec.veiculos, () => nav(const VeiculosPage())),
                navItem(Icons.directions_car_rounded, 'Motoristas', _Sec.motoristas, () => nav(const MotoristasPage())),
                navItem(Icons.local_gas_station_rounded, 'Abastecimentos', _Sec.abastecimentos, () => nav(const ListaAbastecimentosPage())),
                navItem(Icons.local_gas_station_rounded, 'Manutenções', _Sec.manutencoes, () => nav(const ManutencoesPage())),
                catHeader('QUALIDADE'),
                navItem(Icons.report_problem_rounded, 'Ocorrências', _Sec.ocorrencias, () => nav(const ListaOcorrenciasPage())),
                navItem(Icons.dashboard_rounded, 'Checklists', _Sec.checklists, () => nav(const HistoricoChecklistPage())),
                catHeader('GESTÃO'),
                navItem(Icons.bar_chart_rounded, 'Empresas', _Sec.empresas, () => _showEmpresasDialog()),
                navItem(Icons.settings_rounded, 'Usuários', _Sec.usuarios, () => nav(const AdminUsuariosPage())),
                navItem(Icons.bar_chart_rounded, 'Relatórios', _Sec.relatorios, () => nav(const RelatoriosPage())),
                catHeader('SISTEMA'),
                navItem(Icons.settings_rounded, 'Configurações', _Sec.configuracoes, () => nav(const ConfiguracoesPage())),
              ],
            ),
          ),

          // Botão Sair fixo
          Container(height: 1, color: const Color(0xFF0E1E33)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF0A1628),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    title: const Text('Sair do sistema',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    content: const Text('Deseja encerrar a sessão e voltar ao login?',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) await auth.signOut();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text('Sair', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),

          // Footer: user info
          Container(height: 1, color: const Color(0xFF0E1E33)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  alignment: Alignment.center,
                  child: const Text('M', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Master', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Administrador', style: TextStyle(color: Color(0xFF475569), fontSize: 11)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, {bool active = false, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: active
              ? BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.22)),
                )
              : null,
          child: Row(children: [
            Icon(icon, color: active ? const Color(0xFFEF4444) : const Color(0xFF475569), size: 17),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(
              color: active ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            )),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildKpiRow(),
                const SizedBox(height: 20),
                _buildMainRow(),
                const SizedBox(height: 20),
                _buildMetricsRow(),
                const SizedBox(height: 20),
                _buildAcoesRapidas(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final hora = _lastUpdated == null ? '' : _fmtTimestamp(_lastUpdated!);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF080F1E),
        border: Border(bottom: BorderSide(color: Color(0xFF0E1E33))),
      ),
      child: Row(
        children: [
          // Title
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Painel Master', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const Text('Visão geral do sistema FrotaCheck', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
          ]),
          const SizedBox(width: 20),

          // Search — abre dialog de pesquisa global
          Expanded(
            child: GestureDetector(
              onTap: _showSearchDialog,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: const Row(children: [
                  SizedBox(width: 12),
                  Icon(Icons.search_rounded, color: Color(0xFF334155), size: 17),
                  SizedBox(width: 8),
                  Text('Buscar empresa, veículo, motorista...',
                      style: TextStyle(color: Color(0xFF334155), fontSize: 12)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Actions
          _headerIconBtn(
            Icons.report_problem_rounded,
            count: _ocorrenciasAbertas,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaOcorrenciasPage())).then((_) => _loadAll()),
          ),
          const SizedBox(width: 6),
          _headerIconBtn(
            Icons.settings_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfiguracoesPage())),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RelatoriosPage())),
            icon: const Icon(Icons.download_rounded, size: 14),
            label: const Text('Exportar Relatório', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF2D3748))),
            ),
          ),
          const SizedBox(width: 14),
          if (hora.isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Atualizado $hora', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
              const Text('em tempo real', style: TextStyle(color: Color(0xFF475569), fontSize: 10)),
            ]),
          const SizedBox(width: 4),
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh_rounded, color: Color(0xFF475569), size: 18)),
        ],
      ),
    );
  }

  Widget _headerIconBtn(IconData icon, {int count = 0, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1628),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Icon(icon, color: const Color(0xFF94A3B8), size: 18),
        ),
        if (count > 0)
          Positioned(top: 2, right: 2, child: Container(
            width: 14, height: 14,
            decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
          )),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KPI ROW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildKpiRow() {
    final kpis = _buildKpiList();
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: kpis.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _kpiCard(kpis[i]),
      ),
    );
  }

  List<_KpiData> _buildKpiList() {
    String trend(double v) => v == 0 ? '' : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%';
    return [
      _KpiData(label: 'Empresas', value: '$_totalEmpresas', icon: Icons.bar_chart_rounded,
          color: const Color(0xFFF59E0B), trend: trend(_tendEmpresas), trendUp: _tendEmpresas >= 0, spark: _sparkEmpresas),
      _KpiData(label: 'Usuários', value: _fmtNum(_totalUsuarios), icon: Icons.settings_rounded,
          color: const Color(0xFF3B82F6), trend: trend(_tendUsuarios), trendUp: _tendUsuarios >= 0, spark: _sparkUsuarios),
      _KpiData(label: 'Veículos', value: _fmtNum(_totalVeiculos), icon: Icons.directions_car_rounded,
          color: const Color(0xFF22C55E), trend: trend(_tendVeiculos), trendUp: _tendVeiculos >= 0, spark: _sparkVeiculos),
      _KpiData(label: 'Motoristas', value: _fmtNum(_totalMotoristas), icon: Icons.directions_car_rounded,
          color: const Color(0xFFEC4899), trend: trend(_tendMotoristas), trendUp: _tendMotoristas >= 0, spark: _sparkMotoristas),
      _KpiData(label: 'Abastecimentos', value: _fmtNum(_totalAbastecimentos), icon: Icons.local_gas_station_rounded,
          color: const Color(0xFF8B5CF6), trend: trend(_tendAbast), trendUp: _tendAbast >= 0, spark: _sparkAbast),
      _KpiData(label: 'Manutenções', value: _fmtNum(_totalManutencoes), icon: Icons.build_rounded,
          color: const Color(0xFFF97316), trend: trend(_tendChecks), trendUp: _tendChecks >= 0, spark: _sparkManut),
      _KpiData(label: 'Ocorrências', value: '$_totalOcorrencias', icon: Icons.report_problem_rounded,
          color: const Color(0xFFEF4444), trend: trend(_tendOcorr), trendUp: _tendOcorr <= 0, spark: _sparkOcorr),
      _KpiData(label: 'Online Agora', value: '$_empresasOnline', icon: Icons.dashboard_rounded,
          color: const Color(0xFF10B981), spark: _sparkOnline),
      _KpiData(label: 'Receita Mês', value: 'R\$ ${_fmtMoney(_receitaMes)}', icon: Icons.bar_chart_rounded,
          color: const Color(0xFF22C55E), trend: trend(_tendReceita), trendUp: _tendReceita >= 0, spark: _sparkReceita),
      _KpiData(label: 'Novas Empresas', value: '$_novasEmpresas', icon: Icons.build_rounded,
          color: const Color(0xFFEAB308), spark: _sparkNovas),
    ];
  }

  Widget _kpiCard(_KpiData k) {
    return Container(
      width: 160,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: k.color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: k.color.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
              child: Icon(k.icon, color: k.color, size: 14),
            ),
            const Spacer(),
            if (k.trend.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: (k.trendUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(k.trend,
                  style: TextStyle(color: k.trendUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(k.value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(k.label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
          const Spacer(),
          // Sparkline
          if (k.spark.isNotEmpty)
            SizedBox(
              height: 24,
              child: CustomPaint(
                painter: _SparklinePainter(k.spark, k.color),
                size: const Size(double.infinity, 24),
              ),
            )
          else
            const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN ROW: Globe | Alertas | Atividade
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMainRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 8, child: _buildMonitoramentoGlobal()),
          const SizedBox(width: 16),
          Expanded(flex: 6, child: _buildResumoAlertas()),
          const SizedBox(width: 16),
          Expanded(flex: 6, child: _buildAtividadeRealtime()),
        ],
      ),
    );
  }

  Widget _buildMonitoramentoGlobal() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Planet image
            Positioned.fill(
              child: Image.asset(
                'assets/images/perfilMASTER.png',
                fit: BoxFit.cover,
              ),
            ),
            // Gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, const Color(0xFF060C18).withOpacity(0.85)],
                    stops: const [0.3, 1.0],
                  ),
                ),
              ),
            ),
            // Title
            Positioned(
              top: 16, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF080F1E).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: const Text('Monitoramento global', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            // Stats overlay at bottom
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Row(
                children: [
                  _globeStat('$_totalVeiculos', 'Veículos', const Color(0xFF22C55E)),
                  const SizedBox(width: 12),
                  _globeStat('$_empresasAtivas', 'Ativas', const Color(0xFF3B82F6)),
                  const SizedBox(width: 12),
                  _globeStat('$_empresasOnline', 'Online', const Color(0xFF10B981)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _globeStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E).withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
      ]),
    );
  }

  Widget _buildResumoAlertas() {
    void go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    final alertas = <(_AlertItem, VoidCallback)>[
      (_AlertItem(Icons.directions_car_rounded, const Color(0xFF3B82F6), 'Veículos offline', _veiculosOffline),
          () => go(const VeiculosPage())),
      (_AlertItem(Icons.build_rounded, const Color(0xFFF97316), 'Manutenções vencidas', _manutencoesVencidas),
          () => go(const ManutencoesPage())),
      (_AlertItem(Icons.report_problem_rounded, const Color(0xFFF59E0B), 'CNHs vencendo', _cnhsVencendo),
          () => go(const MotoristasPage())),
      (_AlertItem(Icons.report_problem_rounded, const Color(0xFFEF4444), 'Mensalidades atrasadas', _mensalidadesAtrasadas),
          () => _showEmpresasDialog()),
      (_AlertItem(Icons.report_problem_rounded, const Color(0xFFEF4444), 'Ocorrências abertas', _ocorrenciasAbertas),
          () => go(const ListaOcorrenciasPage())),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Text('Resumo de alertas', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              ),
            ]),
          ),
          Container(height: 1, color: const Color(0xFF0E1E33)),
          ...alertas.map((e) => _alertRow(e.$1, onTap: e.$2)),
        ],
      ),
    );
  }

  Widget _alertRow(_AlertItem a, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: a.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(a.icon, color: a.color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(a.label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: a.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${a.count}', style: TextStyle(color: a.color, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF334155), size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _buildAtividadeRealtime() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Text('Atividade em tempo real', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: _loadAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Atualizar', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 11)),
              ),
            ]),
          ),
          Container(height: 1, color: const Color(0xFF0E1E33)),
          if (_atividades.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nenhuma atividade recente.', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
            )
          else
            ..._atividades.map((a) => _activityRow(a)),
        ],
      ),
    );
  }

  Widget _activityRow(_ActivityItem a) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(children: [
        Text(a.hora, style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontFamily: 'monospace')),
        const SizedBox(width: 10),
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: a.color.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
          child: Icon(a.icon, color: a.color, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(a.texto, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METRICS ROW: Distribuição | Rating | Receita
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMetricsRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 4, child: _buildDistribuicao()),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: _buildRating()),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: _buildReceitaMensal()),
        ],
      ),
    );
  }

  Widget _buildDistribuicao() {
    final total = _statusAtivo + _statusSuspenso + _statusCancelado + _statusBloqueado;
    final slices = <_PieSlice>[
      _PieSlice('Ativas', _statusAtivo.toDouble(), const Color(0xFF22C55E)),
      _PieSlice('Suspensas', _statusSuspenso.toDouble(), const Color(0xFFF59E0B)),
      _PieSlice('Canceladas', _statusCancelado.toDouble(), const Color(0xFFEF4444)),
      _PieSlice('Bloqueadas', _statusBloqueado.toDouble(), const Color(0xFF8B5CF6)),
    ].where((s) => s.value > 0).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Distribuição de status', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (total == 0)
            const Center(child: Text('Sem dados', style: TextStyle(color: Color(0xFF475569))))
          else
            Row(
              children: [
                SizedBox(
                  width: 120, height: 120,
                  child: Stack(alignment: Alignment.center, children: [
                    PieChart(PieChartData(
                      sections: slices.map((s) => PieChartSectionData(
                        value: s.value, color: s.color, title: '',
                        radius: 38, showTitle: false,
                      )).toList(),
                      centerSpaceRadius: 30,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                    )),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$total', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      const Text('Total', style: TextStyle(color: Color(0xFF475569), fontSize: 10)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: slices.map((s) {
                      final pct = total > 0 ? (s.value / total * 100).toStringAsFixed(0) : '0';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(s.label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11))),
                          Text('${s.value.toInt()} ($pct%)', style: TextStyle(color: s.color, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRating() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Rating empresas', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Text('Ver ranking', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 11)),
          ]),
          const SizedBox(height: 14),
          if (_ratings.isEmpty)
            const Text('Sem dados disponíveis.', style: TextStyle(color: Color(0xFF475569), fontSize: 12))
          else
            ..._ratings.map((r) => _ratingRow(r)),
        ],
      ),
    );
  }

  Widget _ratingRow(_EmpresaRating r) {
    final pct = r.score.clamp(0, 100) / 100;
    final colors = [
      const Color(0xFFF59E0B), const Color(0xFF94A3B8),
      const Color(0xFFF97316), const Color(0xFF8B5CF6), const Color(0xFF3B82F6),
    ];
    final barColor = colors[(r.rank - 1).clamp(0, 4)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
          width: 20,
          child: Text('${r.rank}º', style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.nome, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct, minHeight: 4,
                backgroundColor: const Color(0xFF1E293B),
                color: barColor,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text('${r.score.toStringAsFixed(0)}%', style: TextStyle(color: barColor, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildReceitaMensal() {
    final maxVal = _receitaMensal6m.fold(0.0, math.max);
    final spots = List.generate(_receitaMensal6m.length, (i) =>
        FlSpot(i.toDouble(), _receitaMensal6m[i]));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Receita mensal', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('R\$ ${_fmtMoney(_receitaMes)}',
              style: const TextStyle(color: Color(0xFF22C55E), fontSize: 22, fontWeight: FontWeight.w700)),
          Row(children: [
            Icon(
              _tendReceita >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: _tendReceita >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              '${_tendReceita >= 0 ? '+' : ''}${_tendReceita.toStringAsFixed(1)}% vs mês passado',
              style: TextStyle(
                color: _tendReceita >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                fontSize: 11,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 80,
            child: maxVal == 0
                ? const Center(child: Text('Sem receita registrada', style: TextStyle(color: Color(0xFF475569), fontSize: 11)))
                : LineChart(LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawHorizontalLine: true,
                      horizontalInterval: maxVal / 3,
                      getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFF0E1E33), strokeWidth: 1),
                      drawVerticalLine: false,
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true, reservedSize: 18,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= _mesesLabels.length) return const SizedBox();
                            return Text(_mesesLabels[i], style: const TextStyle(color: Color(0xFF475569), fontSize: 9));
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: const Color(0xFF22C55E),
                        barWidth: 2,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [const Color(0xFF22C55E).withOpacity(0.25), Colors.transparent],
                          ),
                        ),
                      ),
                    ],
                    minX: 0, maxX: 5,
                    minY: 0, maxY: maxVal * 1.2 + 1,
                  )),
          ),
        ],
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // AÇÕES RÁPIDAS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAcoesRapidas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E1E33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ações rápidas', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _acaoBtn(Icons.build_rounded, const Color(0xFF3B82F6), 'Nova Empresa', _showNovaEmpresaDialog),
                const SizedBox(width: 10),
                _acaoBtn(Icons.settings_rounded, const Color(0xFF22C55E), 'Novo Motorista',
                    _showNovoMotoristaDialog),
                const SizedBox(width: 10),
                _acaoBtn(Icons.directions_car_rounded, const Color(0xFF8B5CF6), 'Novo Veículo',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage()))),
                const SizedBox(width: 10),
                _acaoBtn(Icons.directions_car_rounded, const Color(0xFFEC4899), 'Novo Motorista',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage()))),
                const SizedBox(width: 10),
                _acaoBtn(Icons.bar_chart_rounded, const Color(0xFF10B981), 'Relatórios',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RelatoriosPage()))),
                const SizedBox(width: 10),
                _acaoBtn(Icons.build_rounded, const Color(0xFFF59E0B), 'Logs do Sistema', _showLogsDialog),
                const SizedBox(width: 10),
                _acaoBtn(Icons.settings_rounded, const Color(0xFF64748B), 'Configurações',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfiguracoesPage()))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _acaoBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 100,
        height: 104,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showNovoMotoristaDialog() {
    final nomeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final telefoneCtrl = TextEditingController();
    bool criarConta = false;
    bool saving = false;
    String? error;
    String? successMsg;
    String? empresaSelecionadaId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: const Text('Novo Motorista',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                if (successMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.build_rounded, color: Color(0xFF22C55E), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(successMsg!, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],

                // Nome
                _formField('Nome completo *', nomeCtrl),
                const SizedBox(height: 12),

                // Email
                _fieldLabel('E-mail da conta *'),
                const SizedBox(height: 4),
                const Text(
                  'Use o e-mail com que o motorista criou a conta no app. Se ainda não tem conta, marque a opção abaixo para criar uma e enviar o convite por e-mail.',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 11),
                ),
                const SizedBox(height: 6),
                _formField('Email', emailCtrl, hint: 'motorista@email.com'),
                const SizedBox(height: 12),

                // Telefone
                _formField('Telefone', telefoneCtrl, hint: '(11) 99999-9999'),
                const SizedBox(height: 12),

                // Empresa
                _fieldLabel('Empresa'),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1C30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: empresaSelecionadaId,
                      hint: const Text('Selecionar empresa', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                      dropdownColor: const Color(0xFF0F1C30),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: _empresasList.map((e) {
                        return DropdownMenuItem<String>(
                          value: e['id']?.toString(),
                          child: Text(e['nome']?.toString() ?? '—',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (v) => setS(() => empresaSelecionadaId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Criar conta nova (convite por e-mail — Master nunca define a senha do motorista)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1C30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: CheckboxListTile(
                    value: criarConta,
                    onChanged: (v) => setS(() => criarConta = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF3B82F6),
                    title: const Text('Criar conta de acesso para este motorista',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: const Text(
                      'Um e-mail com link para o motorista definir a própria senha será enviado.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final nome = nomeCtrl.text.trim();
                final email = emailCtrl.text.trim().toLowerCase();
                final telefone = telefoneCtrl.text.trim();

                if (nome.isEmpty) { setS(() => error = 'Nome é obrigatório'); return; }
                if (email.isEmpty) { setS(() => error = 'E-mail é obrigatório'); return; }

                setS(() { saving = true; error = null; successMsg = null; });

                try {
                  String? userId;

                  if (criarConta) {
                    // ── Criar conta nova via cliente secundário ──────────────
                    // A senha é aleatória e descartada: o motorista define a própria
                    // senha pelo link enviado via resetPasswordForEmail (Master nunca a conhece).
                    final url = await SupabaseConfig.getUrl();
                    final key = await SupabaseConfig.getPublishableKey();
                    final tmpClient = SupabaseClient(url, key);
                    try {
                      final tempPassword = '${DateTime.now().microsecondsSinceEpoch}${UniqueKey().hashCode}Aa1!';
                      final signUpRes = await tmpClient.auth.signUp(
                        email: email,
                        password: tempPassword,
                      );
                      userId = signUpRes.user?.id;
                      if (userId == null) {
                        await tmpClient.dispose();
                        setS(() { saving = false; error = 'Falha ao criar conta. Verifique se o e-mail já está cadastrado.'; });
                        return;
                      }
                      try {
                        await tmpClient.auth.resetPasswordForEmail(email);
                      } catch (_) {}
                    } finally {
                      await tmpClient.dispose();
                    }

                    // Inserir perfil do usuário (master tem permissão).
                    // Não silenciar: se isso falhar, a conta fica criada no Auth
                    // mas sem role/empresa_id, e o motorista trava em "pendente"
                    // sem ninguém saber o motivo.
                    await _supabase.from('user_profiles').upsert({
                      'user_id': userId,
                      'email': email,
                      'nome': nome,
                      'role': 'MOTORISTA',
                      'empresa_id': empresaSelecionadaId,
                      'status': 'ativo',
                    }, onConflict: 'user_id');
                  } else {
                    // ── Vincular conta existente por e-mail ──────────────────
                    final existing = await _supabase
                        .from('user_profiles')
                        .select('user_id')
                        .eq('email', email)
                        .maybeSingle();
                    if (existing != null) {
                      userId = existing['user_id']?.toString();
                    }
                  }

                  // ── Criar registro de motorista (drivers) ────────────────
                  final driverPayload = <String, dynamic>{
                    'name': nome,
                    'email': email,
                    if (telefone.isNotEmpty) 'phone': telefone,
                  };
                  if (empresaSelecionadaId != null) driverPayload['empresa_id'] = empresaSelecionadaId;
                  if (userId != null) driverPayload['user_id'] = userId;

                  final driverRes = await _supabase
                      .from('drivers')
                      .insert(driverPayload)
                      .select('id')
                      .single();

                  final driverId = driverRes['id']?.toString();

                  // ── Sincronizar driver_id no perfil do usuário ───────────
                  if (userId != null && driverId != null) {
                    final profileUpdate = <String, dynamic>{
                      'driver_id': driverId,
                      'role': 'MOTORISTA',
                    };
                    if (empresaSelecionadaId != null) profileUpdate['empresa_id'] = empresaSelecionadaId;
                    await _supabase
                        .from('user_profiles')
                        .update(profileUpdate)
                        .eq('user_id', userId);
                  }

                  final msg = criarConta
                      ? 'Motorista "$nome" cadastrado! Um e-mail para definir a senha foi enviado a $email.'
                      : userId != null
                          ? 'Motorista "$nome" cadastrado e vinculado à conta $email!'
                          : 'Motorista "$nome" cadastrado! Conta "$email" não encontrada — vínculo pendente quando fizer login.';

                  if (ctx.mounted) {
                    setS(() { saving = false; successMsg = msg; });
                    await Future.delayed(const Duration(seconds: 2));
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                  _loadAll();
                } catch (e) {
                  setS(() { saving = false; error = friendlyError(e); });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Cadastrar Motorista'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
  );

  void _showNovaEmpresaDialog() {
    final nomeCtrl = TextEditingController();
    final cnpjCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    bool saving = false;
    String? error;
    String? successMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
          title: const Text('Nova Empresa', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                ),
                const SizedBox(height: 12),
              ],
              if (successMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(successMsg!, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                ),
                const SizedBox(height: 12),
              ],
              _formField('Nome da empresa *', nomeCtrl),
              const SizedBox(height: 12),
              _formField('CNPJ', cnpjCtrl, hint: '00.000.000/0001-00'),
              const SizedBox(height: 16),
              const Text(
                'E-mail do administrador',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Informe o e-mail da conta já cadastrada no app. O usuário será vinculado automaticamente como admin desta empresa.',
                style: TextStyle(color: Color(0xFF475569), fontSize: 11),
              ),
              const SizedBox(height: 8),
              _formField('E-mail do administrador *', emailCtrl, hint: 'admin@empresa.com.br'),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final nome = nomeCtrl.text.trim();
                final email = emailCtrl.text.trim().toLowerCase();
                if (nome.isEmpty) { setS(() => error = 'Nome é obrigatório'); return; }
                if (email.isEmpty) { setS(() => error = 'E-mail do administrador é obrigatório'); return; }
                setS(() { saving = true; error = null; successMsg = null; });
                try {
                  // 1. Verifica se o usuário com esse e-mail existe
                  final userRes = await _supabase
                      .from('user_profiles')
                      .select('user_id, nome, role, empresa_id, empresas(nome)')
                      .eq('email', email)
                      .maybeSingle();

                  if (userRes == null) {
                    setS(() { saving = false; error = 'Nenhuma conta encontrada com o e-mail "$email". Peça ao administrador para criar a conta no app primeiro.'; });
                    return;
                  }

                  // Se o usuário já pertence a outra empresa, confirma antes de mover
                  final empresaAtualId = userRes['empresa_id']?.toString();
                  if (empresaAtualId != null) {
                    final empresaAtualNome = (userRes['empresas'] is Map)
                        ? (userRes['empresas'] as Map)['nome']?.toString() ?? 'outra empresa'
                        : 'outra empresa';
                    setS(() => saving = false);
                    if (!ctx.mounted) return;
                    final confirmarMover = await showDialog<bool>(
                      context: ctx,
                      builder: (ctx2) => AlertDialog(
                        backgroundColor: const Color(0xFF0A1628),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
                        title: const Text('Usuário já vinculado', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        content: Text(
                          'O e-mail "$email" já está vinculado à empresa "$empresaAtualNome" (papel: ${userRes['role']}). Mover para a nova empresa "$nome" como ADMIN_EMPRESA?',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B)))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                            onPressed: () => Navigator.pop(ctx2, true),
                            child: const Text('Mover mesmo assim', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (confirmarMover != true) return;
                    setS(() => saving = true);
                  }

                  // 2. Cria a empresa
                  final empRes = await _supabase
                      .from('empresas')
                      .insert({
                        'nome': nome,
                        'cnpj': cnpjCtrl.text.trim().isEmpty ? null : cnpjCtrl.text.trim(),
                        'email': email,
                        'status': 'ativo',
                      })
                      .select('id')
                      .single();

                  final empresaId = empRes['id']?.toString();
                  if (empresaId == null) throw Exception('Falha ao obter ID da empresa criada');

                  // 3. Vincula o usuário à empresa e define role como admin
                  final userId = userRes['user_id']?.toString();
                  if (userId != null) {
                    await _supabase
                        .from('user_profiles')
                        .update({
                          'empresa_id': empresaId,
                          'role': 'ADMIN_EMPRESA',
                        })
                        .eq('user_id', userId);
                  }

                  final nomeUsuario = userRes['nome']?.toString() ?? email;
                  if (ctx.mounted) {
                    setS(() {
                      saving = false;
                      successMsg = 'Empresa "$nome" criada e "$nomeUsuario" vinculado como administrador!';
                    });
                    await Future.delayed(const Duration(seconds: 2));
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                  _loadAll();
                } catch (e) {
                  setS(() { saving = false; error = friendlyError(e); });
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Criar Empresa'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialog: Gestão de Empresas ─────────────────────────────────────────────
  void _showEmpresasDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final lista = _empresasList;
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1628),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF1E293B)),
            ),
            title: Row(children: [
              const Expanded(
                child: Text('Empresas cadastradas',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () { Navigator.pop(ctx); _showNovaEmpresaDialog(); },
                icon: const Icon(Icons.add_rounded, size: 15, color: Color(0xFF3B82F6)),
                label: const Text('Nova', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12)),
              ),
            ]),
            content: SizedBox(
              width: 520,
              height: 380,
              child: lista.isEmpty
                  ? const Center(
                      child: Text('Nenhuma empresa cadastrada.',
                          style: TextStyle(color: Color(0xFF475569))))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: lista.map((e) {
                          final nome = (e['nome'] ?? '').toString();
                          final status = (e['status'] ?? 'ativo').toString();
                          final cnpj = (e['cnpj'] ?? '').toString();
                          final statusColor = status == 'ativo'
                              ? const Color(0xFF22C55E)
                              : status == 'suspenso'
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFEF4444);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF060C18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: Row(children: [
                              Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(nome, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                if (cnpj.isNotEmpty)
                                  Text(cnpj, style: const TextStyle(color: Color(0xFF475569), fontSize: 11)),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar', style: TextStyle(color: Color(0xFF3B82F6))),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Dialog: Pesquisa Global ────────────────────────────────────────────────
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SearchDialog(supabase: _supabase),
    );
  }

  void _showLogsDialog() {
    showDialog(
      context: context,
      builder: (logCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
        title: const Text('Logs do Sistema', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 500, height: 320,
          child: _atividades.isEmpty
              ? const Center(child: Text('Nenhum log disponível.', style: TextStyle(color: Color(0xFF475569))))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _atividades.map((a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(a.icon, color: a.color, size: 15),
                        const SizedBox(width: 8),
                        Text(a.hora, style: const TextStyle(color: Color(0xFF475569), fontSize: 11)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a.texto, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12))),
                      ]),
                    )).toList(),
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(logCtx), child: const Text('Fechar', style: TextStyle(color: Color(0xFF3B82F6))))],
      ),
    );
  }

  Widget _formField(String label, TextEditingController ctrl, {String hint = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: Color(0xFF334155), fontSize: 12),
          filled: true, fillColor: const Color(0xFF060C18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    ]);
  }

  // ── Utilities ──────────────────────────────────────────────────────────────
  String _fmtTimestamp(DateTime dt) =>
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';

  String _fmtNum(int n) {
    if (n >= 1000) return '${n ~/ 1000}.${(n % 1000).toString().padLeft(3, '0')}';
    return '$n';
  }

  String _fmtMoney(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2).replaceAll('.', ',')} M';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      return '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}';
    }
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }
}

// ─── Custom Painters ──────────────────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  _SparklinePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final maxV = points.reduce(math.max);
    final minV = points.reduce(math.min);
    final range = maxV - minV;

    double y0(double v) => range > 0
        ? size.height - (v - minV) / range * (size.height - 4) - 2
        : size.height / 2;

    final linePaint = Paint()
      ..color = color.withOpacity(0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = i * size.width / (points.length - 1);
      final y = y0(points[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.25), color.withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      color != old.color || points.toString() != old.points.toString();
}

// ─── Data helpers ─────────────────────────────────────────────────────────────
class _PieSlice {
  final String label;
  final double value;
  final Color color;
  const _PieSlice(this.label, this.value, this.color);
}

// ─── Search Dialog ────────────────────────────────────────────────────────────
class _SearchDialog extends StatefulWidget {
  final SupabaseClient supabase;
  const _SearchDialog({required this.supabase});
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<_SearchResult> _results = [];

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final like = '%${q.toLowerCase()}%';
    final results = <_SearchResult>[];
    try {
      // BUG-18: join drivers with empresas so MASTER can see which company each driver belongs to
      final [emp, veic, mot] = await Future.wait([
        widget.supabase.from('empresas').select('id, nome, status').ilike('nome', like).limit(5),
        widget.supabase.from('vehicles').select('id, plate, model, empresa_id, empresas(nome)').ilike('plate', like).limit(5),
        widget.supabase.from('drivers').select('id, name, empresa_id, empresas(nome)').ilike('name', like).limit(5),
      ]);
      for (final e in (emp as List)) {
        results.add(_SearchResult('empresa', (e['nome'] ?? '').toString(),
            (e['status'] ?? '').toString(), Icons.bar_chart_rounded, const Color(0xFF3B82F6)));
      }
      for (final v in (veic as List)) {
        final empNome = (v['empresas'] is Map)
            ? (v['empresas'] as Map)['nome']?.toString() ?? ''
            : '';
        final desc = '${v['plate'] ?? ''} · ${v['model'] ?? ''}'.trim();
        final subtitle = empNome.isNotEmpty ? 'Veículo · $empNome' : 'Veículo';
        results.add(_SearchResult('veiculo', desc, subtitle,
            Icons.directions_car_rounded, const Color(0xFF22C55E)));
      }
      for (final m in (mot as List)) {
        final empNome = (m['empresas'] is Map)
            ? (m['empresas'] as Map)['nome']?.toString() ?? ''
            : '';
        final subtitle = empNome.isNotEmpty ? 'Motorista · $empNome' : 'Motorista';
        results.add(_SearchResult('motorista', (m['name'] ?? '').toString(),
            subtitle, Icons.directions_car_rounded, const Color(0xFFEC4899)));
      }
    } catch (_) {}
    if (mounted) setState(() { _results = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A1628),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF1E293B))),
      title: const Text('Pesquisa global',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 480, height: 360,
        child: Column(children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: _onChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar empresa, veículo, motorista...',
              hintStyle: const TextStyle(color: Color(0xFF334155), fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF475569), size: 18),
              filled: true, fillColor: const Color(0xFF060C18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E293B))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E293B))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xFF3B82F6), strokeWidth: 2))
          else if (_results.isEmpty && _ctrl.text.length >= 2)
            const Padding(padding: EdgeInsets.all(20),
                child: Text('Nenhum resultado encontrado.',
                    style: TextStyle(color: Color(0xFF475569), fontSize: 13)))
          else
            Expanded(child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final r = _results[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.pop(context);
                    switch (r.type) {
                      case 'empresa':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsuariosPage()));
                        break;
                      case 'veiculo':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const VeiculosPage()));
                        break;
                      case 'motorista':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const MotoristasPage()));
                        break;
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF060C18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                            color: r.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(r.icon, color: r.color, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(r.subtitle, style: const TextStyle(color: Color(0xFF475569), fontSize: 11)),
                      ])),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF334155), size: 18),
                    ]),
                  ),
                );
              },
            )),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: Color(0xFF3B82F6)))),
      ],
    );
  }
}

class _SearchResult {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _SearchResult(this.type, this.title, this.subtitle, this.icon, this.color);
}

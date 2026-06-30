import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/app_auth_provider.dart';
import '../../core/models/checklist_model.dart';
import '../../core/theme/app_theme.dart';

class HistoricoChecklistPage extends StatefulWidget {
  const HistoricoChecklistPage({super.key});

  @override
  State<HistoricoChecklistPage> createState() => _HistoricoChecklistPageState();
}

class _HistoricoChecklistPageState extends State<HistoricoChecklistPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _registros = [];
  Map<String, Map<String, dynamic>> _veicMap = {};
  Map<String, Map<String, dynamic>> _motMap = {};
  bool _carregando = true;
  String _filtroTipo = 'todos';
  String _busca = '';
  final _buscaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => _carregando = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final eid = auth.effectiveEmpresaId;
      var checkQ = supabase.from('checklists').select();
      if (auth.isMotorista && auth.driverId != null) {
        checkQ = checkQ.eq('motorista_id', auth.driverId!);
      } else if (eid != null) {
        checkQ = checkQ.eq('empresa_id', eid);
      }

      var veicQ = supabase.from('vehicles').select('id, plate, model, brand');
      var drivQ = supabase.from('drivers').select('id, name');
      if (eid != null) {
        veicQ = veicQ.eq('empresa_id', eid);
        drivQ = drivQ.eq('empresa_id', eid);
      }
      final results = await Future.wait([
        checkQ.order('criado_em', ascending: false).limit(200),
        veicQ,
        drivQ,
      ]);

      final veicMap = <String, Map<String, dynamic>>{};
      for (final v in (results[1] as List)) {
        final row = Map<String, dynamic>.from(v as Map);
        veicMap[row['id'].toString()] = row;
      }

      final motMap = <String, Map<String, dynamic>>{};
      for (final m in (results[2] as List)) {
        final row = Map<String, dynamic>.from(m as Map);
        motMap[row['id'].toString()] = row;
      }

      if (!mounted) return;
      setState(() {
        _registros = List<Map<String, dynamic>>.from(
          (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _veicMap = veicMap;
        _motMap = motMap;
        _carregando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    return _registros.where((r) {
      if (_filtroTipo != 'todos' && r['tipo'] != _filtroTipo) return false;
      if (_busca.isNotEmpty) {
        final vid = r['veiculo_id']?.toString() ?? '';
        final mid = r['motorista_id']?.toString() ?? '';
        final placa = (_veicMap[vid]?['plate'] ?? '').toString().toLowerCase();
        final motor = (_motMap[mid]?['name'] ?? '').toString().toLowerCase();
        final q = _busca.toLowerCase();
        if (!placa.contains(q) && !motor.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  int _itensOk(Map<String, dynamic> r) {
    final itens = r['itens'];
    if (itens == null) return 0;
    final map = Map<String, dynamic>.from(itens as Map);
    return map.values.where((v) => v == true).length;
  }

  String _formatarData(Map<String, dynamic> r) {
    final raw = r['criado_em']?.toString() ?? r['data']?.toString();
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.substring(0, 10);
    }
  }

  void _abrirDetalhe(Map<String, dynamic> r) {
    final vid = r['veiculo_id']?.toString() ?? '';
    final mid = r['motorista_id']?.toString() ?? '';
    final veiculo = _veicMap[vid];
    final motorista = _motMap[mid];
    final aprovado = r['aprovado'] as bool? ?? false;
    final tipo = r['tipo']?.toString() ?? 'saida';
    final itensOk = _itensOk(r);
    final total = Checklist.itensChecklist.length;
    final itensMap = r['itens'] != null
        ? Map<String, dynamic>.from(r['itens'] as Map)
        : <String, dynamic>{};
    final fotos = r['foto_urls'] != null
        ? List<String>.from(r['foto_urls'] as List)
        : <String>[];
    final obs = r['observacoes']?.toString();
    final kmFinal = r['km_final'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                _tipoBadge(tipo, large: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        veiculo != null
                            ? '${veiculo['plate'] ?? ''} — ${veiculo['model'] ?? ''}'
                            : 'Veículo desconhecido',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        motorista?['name']?.toString() ?? 'Motorista desconhecido',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _statusBadge(aprovado),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatarData(r),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Progresso itens
            _detalheRow('Itens verificados', '$itensOk / $total'),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? itensOk / total : 0,
                backgroundColor: AppColors.backgroundSoft,
                valueColor: AlwaysStoppedAnimation(
                    aprovado ? AppColors.success : AppColors.danger),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),

            if (kmFinal != null) ...[
              _detalheRow('KM Final', kmFinal.toString()),
              const SizedBox(height: 12),
            ],

            if (obs != null && obs.isNotEmpty) ...[
              _detalheRow('Observações', ''),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(obs,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],

            // Lista de itens
            const Text('Itens do Checklist',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: List.generate(
                  Checklist.itensChecklist.length * 2 - 1,
                  (i) {
                    if (i.isOdd) {
                      return const Divider(
                          height: 1, color: AppColors.border);
                    }
                    final item = Checklist.itensChecklist[i ~/ 2];
                    final ok = itensMap[item] == true;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            ok
                                ? Icons.check_circle
                                : Icons.cancel_outlined,
                            color: ok
                                ? AppColors.success
                                : AppColors.danger,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item,
                                style: TextStyle(
                                    color: ok
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // Fotos
            if (fotos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Fotos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: fotos.length,
                itemBuilder: (_, idx) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    fotos[idx],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                      color: AppColors.backgroundSoft,
                      child: const Icon(Icons.broken_image,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detalheRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _tipoBadge(String tipo, {bool large = false}) {
    final isSaida = tipo == 'saida';
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 10 : 7, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: (isSaida ? AppColors.secondary : AppColors.success)
            .withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isSaida ? AppColors.secondary : AppColors.success)
              .withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSaida
                ? Icons.arrow_circle_up_outlined
                : Icons.arrow_circle_down_outlined,
            color: isSaida ? AppColors.secondary : AppColors.success,
            size: large ? 14 : 11,
          ),
          const SizedBox(width: 4),
          Text(
            isSaida ? 'Saída' : 'Retorno',
            style: TextStyle(
              color: isSaida ? AppColors.secondary : AppColors.success,
              fontSize: large ? 12 : 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool aprovado) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (aprovado ? AppColors.success : AppColors.danger)
              .withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (aprovado ? AppColors.success : AppColors.danger)
                .withOpacity(0.4),
          ),
        ),
        child: Text(
          aprovado ? 'Aprovado' : 'Reprovado',
          style: TextStyle(
            color: aprovado ? AppColors.success : AppColors.danger,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Histórico de Checklists'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                // Busca
                TextField(
                  controller: _buscaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (v) => setState(() => _busca = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por placa ou motorista...',
                    hintStyle: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textSecondary, size: 18),
                    suffixIcon: _busca.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: AppColors.textSecondary, size: 16),
                            onPressed: () {
                              _buscaController.clear();
                              setState(() => _busca = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.backgroundSoft,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.secondary)),
                  ),
                ),
                const SizedBox(height: 10),
                // Chips de tipo
                Row(
                  children: [
                    _filterChip('Todos', 'todos'),
                    const SizedBox(width: 8),
                    _filterChip('Saída', 'saida'),
                    const SizedBox(width: 8),
                    _filterChip('Retorno', 'retorno'),
                    const Spacer(),
                    Text(
                      '${lista.length} registro${lista.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : lista.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.checklist_rtl,
                                size: 56,
                                color: Colors.grey.shade700),
                            const SizedBox(height: 12),
                            const Text(
                              'Nenhum checklist encontrado',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                          itemCount: lista.length,
                          itemBuilder: (_, i) => _buildCard(lista[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filtroTipo == value;
    return GestureDetector(
      onTap: () => setState(() => _filtroTipo = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.secondary.withOpacity(0.15)
              : AppColors.backgroundSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.secondary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.secondary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final vid = r['veiculo_id']?.toString() ?? '';
    final mid = r['motorista_id']?.toString() ?? '';
    final veiculo = _veicMap[vid];
    final motorista = _motMap[mid];
    final tipo = r['tipo']?.toString() ?? 'saida';
    final aprovado = r['aprovado'] as bool? ?? false;
    final itensOk = _itensOk(r);
    final total = Checklist.itensChecklist.length;
    final pct = total > 0 ? itensOk / total : 0.0;
    final kmFinal = r['km_final'];

    return GestureDetector(
      onTap: () => _abrirDetalhe(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: aprovado
                ? AppColors.success.withOpacity(0.25)
                : AppColors.danger.withOpacity(0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: tipo + status + data
            Row(
              children: [
                _tipoBadge(tipo),
                const SizedBox(width: 6),
                _statusBadge(aprovado),
                const Spacer(),
                Text(
                  _formatarData(r),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Veículo
            Row(
              children: [
                const Icon(Icons.directions_car,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    veiculo != null
                        ? '${veiculo['plate'] ?? ''} — ${veiculo['model'] ?? ''}'
                        : 'Veículo desconhecido',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Motorista
            Row(
              children: [
                const Icon(Icons.person_outline,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 6),
                Text(
                  motorista?['name']?.toString() ?? 'Motorista desconhecido',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Barra de progresso
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.backgroundSoft,
                      valueColor: AlwaysStoppedAnimation(
                          aprovado ? AppColors.success : AppColors.danger),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$itensOk/$total itens',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                if (kmFinal != null) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.speed,
                      color: AppColors.textSecondary, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    '$kmFinal km',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

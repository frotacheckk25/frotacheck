import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';

/// Lê a localização atual via API de geolocalização do navegador.
/// Best-effort: retorna null se indisponível, sem permissão, ou expirar —
/// nunca deve bloquear o fluxo de iniciar/concluir viagem.
Future<String?> _obterLocalizacao() async {
  try {
    final pos = await html.window.navigator.geolocation
        .getCurrentPosition(enableHighAccuracy: true)
        .timeout(const Duration(seconds: 5));
    final lat = pos.coords?.latitude;
    final lng = pos.coords?.longitude;
    if (lat == null || lng == null) return null;
    return '$lat,$lng';
  } catch (_) {
    return null;
  }
}

class ViagensPage extends StatefulWidget {
  const ViagensPage({super.key});

  @override
  State<ViagensPage> createState() => _ViagensPageState();
}

class _ViagensPageState extends State<ViagensPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> viagens = [];
  Map<String, Map<String, dynamic>> veiculosMap = {};
  Map<String, Map<String, dynamic>> motoristasMap = {};
  bool isLoading = true;
  String filtroStatus = 'todas';

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final auth = context.read<AppAuthProvider>();
      final isMotorista = auth.isMotorista;
      final eid = auth.effectiveEmpresaId;

      // Busca driverId fresco para motorista (cache pode estar desatualizado)
      String? driverId = auth.driverId;
      if (isMotorista && driverId == null) {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          final fresh = await supabase.from('user_profiles')
              .select('driver_id').eq('user_id', uid).maybeSingle();
          driverId = fresh?['driver_id']?.toString();
        }
      }

      final vMap = <String, Map<String, dynamic>>{};
      final mMap = <String, Map<String, dynamic>>{};

      if (isMotorista) {
        // MOTORISTA: veículo via RPC SECURITY DEFINER (burla RLS)
        try {
          final res = await supabase.rpc('get_my_vehicle') as List?;
          if (res != null && res.isNotEmpty) {
            final v = Map<String, dynamic>.from(res.first as Map);
            vMap[v['id'].toString()] = v;
          }
        } catch (_) {}
        // Fallback: query direta por empresa
        if (vMap.isEmpty && eid != null) {
          try {
            final vs = await supabase.from('vehicles')
                .select('id, plate, brand, model').eq('empresa_id', eid);
            for (final v in vs as List) {
              final row = Map<String, dynamic>.from(v as Map);
              vMap[row['id'].toString()] = row;
            }
          } catch (_) {}
        }
        // Próprio motorista: query por ID específico (RLS permite)
        if (driverId != null) {
          try {
            final dr = await supabase.from('drivers')
                .select('id, name').eq('id', driverId).maybeSingle();
            if (dr != null) mMap[driverId] = Map<String, dynamic>.from(dr as Map);
          } catch (_) {}
        }
      } else if (eid != null) {
        // ADMIN/GESTOR: veículos por empresa
        try {
          final vs = await supabase.from('vehicles')
              .select('id, plate, brand, model').eq('empresa_id', eid).order('plate');
          for (final v in vs as List) {
            final row = Map<String, dynamic>.from(v as Map);
            vMap[row['id'].toString()] = row;
          }
        } catch (_) {}
        // Motoristas: via user_profiles (não depende de drivers.empresa_id)
        try {
          final profiles = await supabase.from('user_profiles')
              .select('driver_id, nome, email')
              .eq('empresa_id', eid)
              .eq('role', 'MOTORISTA')
              .not('driver_id', 'is', null);
          for (final p in profiles as List) {
            final dId = p['driver_id']?.toString();
            if (dId == null) continue;
            try {
              final dr = await supabase.from('drivers')
                  .select('id, name').eq('id', dId).maybeSingle();
              mMap[dId] = dr != null
                  ? Map<String, dynamic>.from(dr as Map)
                  : {'id': dId, 'name': p['nome'] ?? p['email'] ?? dId};
            } catch (_) {
              mMap[dId] = {'id': dId, 'name': p['nome'] ?? p['email'] ?? dId};
            }
          }
        } catch (_) {}
      }

      var viaQ = supabase.from('viagens').select();
      if (isMotorista && driverId != null) {
        viaQ = viaQ.eq('motorista_id', driverId);
      } else if (eid != null) {
        viaQ = viaQ.eq('empresa_id', eid);
      }
      final viaResp = await viaQ.order('data_inicio', ascending: false);
      final viaList = List<Map<String, dynamic>>.from(
        (viaResp as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      if (!mounted) return;
      setState(() {
        viagens = viaList;
        veiculosMap = vMap;
        motoristasMap = mMap;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar viagens: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar viagens: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _filtradas() {
    if (filtroStatus == 'todas') return viagens;
    return viagens.where((v) => v['status'] == filtroStatus).toList();
  }

  String _veiculoLabel(String? id) {
    if (id == null || id.isEmpty) return 'N/A';
    final v = veiculosMap[id];
    if (v == null) return 'Desconhecido';
    final plate = v['plate']?.toString() ?? '';
    final desc = '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
    return desc.isNotEmpty ? '$plate — $desc' : plate;
  }

  String _motoristaLabel(String? id) {
    if (id == null || id.isEmpty) return 'N/A';
    return motoristasMap[id]?['name']?.toString() ?? 'Desconhecido';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'em_progresso':
        return AppColors.info;
      case 'concluida':
        return AppColors.success;
      case 'cancelada':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'em_progresso':
        return 'Em Progresso';
      case 'concluida':
        return 'Concluída';
      case 'cancelada':
        return 'Cancelada';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtradas();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Controle de Viagens'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregarDados),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovaViagem,
        backgroundColor: AppColors.secondary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nova Viagem', style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _chip('Todas', 'todas'),
                      const SizedBox(width: 8),
                      _chip('Em Progresso', 'em_progresso'),
                      const SizedBox(width: 8),
                      _chip('Concluídas', 'concluida'),
                      const SizedBox(width: 8),
                      _chip('Canceladas', 'cancelada'),
                    ],
                  ),
                ),
                Expanded(
                  child: lista.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.directions, size: 64, color: AppColors.textSecondary),
                              const SizedBox(height: 16),
                              const Text(
                                'Nenhuma viagem encontrada',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _abrirNovaViagem,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                                child: const Text('Registrar Viagem', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _carregarDados,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: lista.length,
                            itemBuilder: (_, i) => _buildCard(lista[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _chip(String label, String value) {
    final sel = filtroStatus == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => filtroStatus = value),
      selectedColor: AppColors.secondary.withValues(alpha: 0.25),
      backgroundColor: AppColors.surface,
      checkmarkColor: AppColors.secondary,
      labelStyle: TextStyle(
        color: sel ? AppColors.secondary : AppColors.textSecondary,
        fontSize: 13,
      ),
      side: BorderSide(color: sel ? AppColors.secondary : AppColors.border),
    );
  }

  Widget _buildCard(Map<String, dynamic> v) {
    final status = v['status']?.toString() ?? 'desconhecido';
    final cor = _statusColor(status);
    final kmPerc = (v['quilometragem_percorrida'] as num?)?.toDouble();

    return GestureDetector(
      onTap: () => _abrirDetalhe(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.directions, color: cor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${v['origem'] ?? '-'} → ${v['destino'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Veículo: ${_veiculoLabel(v['veiculo_id']?.toString())}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  Text(
                    'Motorista: ${_motoristaLabel(v['motorista_id']?.toString())}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (kmPerc != null)
                    Text(
                      'KM percorrido: ${kmPerc.toStringAsFixed(1)} km',
                      style: const TextStyle(color: AppColors.secondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            Chip(
              label: Text(_statusLabel(status), style: const TextStyle(fontSize: 11)),
              backgroundColor: cor.withValues(alpha: 0.15),
              labelStyle: TextStyle(color: cor, fontWeight: FontWeight.bold),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  void _abrirNovaViagem() {
    final auth = context.read<AppAuthProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NovaViagemPage(
          veiculosMap: veiculosMap,
          motoristasMap: motoristasMap,
          onSalva: _carregarDados,
          isMotorista: auth.isMotorista,
          ownDriverId: auth.driverId,
        ),
      ),
    );
  }

  void _abrirDetalhe(Map<String, dynamic> viagem) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalheViagemPage(
          viagem: viagem,
          veiculoLabel: _veiculoLabel(viagem['veiculo_id']?.toString()),
          motoristaLabel: _motoristaLabel(viagem['motorista_id']?.toString()),
          onAtualizada: _carregarDados,
        ),
      ),
    );
  }
}

// ── Nova Viagem ────────────────────────────────────────────────────────────────

class _NovaViagemPage extends StatefulWidget {
  final Map<String, Map<String, dynamic>> veiculosMap;
  final Map<String, Map<String, dynamic>> motoristasMap;
  final VoidCallback onSalva;
  final bool isMotorista;
  final String? ownDriverId;

  const _NovaViagemPage({
    required this.veiculosMap,
    required this.motoristasMap,
    required this.onSalva,
    this.isMotorista = false,
    this.ownDriverId,
  });

  @override
  State<_NovaViagemPage> createState() => _NovaViagemPageState();
}

class _NovaViagemPageState extends State<_NovaViagemPage> {
  final supabase = Supabase.instance.client;

  String? veiculoId;
  String? motoristaId;
  bool isLoading = false;

  final origemCtrl = TextEditingController();
  final destinoCtrl = TextEditingController();
  final kmInicioCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // MOTORISTA: auto-preenche com seu próprio driver e único veículo
    if (widget.isMotorista) {
      if (widget.ownDriverId != null) motoristaId = widget.ownDriverId;
      if (widget.veiculosMap.length == 1) veiculoId = widget.veiculosMap.keys.first;
    }
  }

  @override
  void dispose() {
    origemCtrl.dispose();
    destinoCtrl.dispose();
    kmInicioCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (veiculoId == null ||
        motoristaId == null ||
        origemCtrl.text.isEmpty ||
        destinoCtrl.text.isEmpty ||
        kmInicioCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    final kmInicio = double.tryParse(kmInicioCtrl.text.replaceAll(',', '.'));
    if (kmInicio == null || kmInicio < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quilometragem inicial inválida')),
      );
      return;
    }

    setState(() => isLoading = true);
    final injetar = context.read<AppAuthProvider>().inject;
    final localizacao = await _obterLocalizacao();
    if (!mounted) return;
    try {
      await supabase.from('viagens').insert(injetar({
        'veiculo_id': veiculoId,
        'motorista_id': motoristaId,
        'data_inicio': DateTime.now().toIso8601String(),
        'origem': origemCtrl.text.trim(),
        'destino': destinoCtrl.text.trim(),
        'quilometragem_inicio': kmInicio,
        'status': 'em_progresso',
        'fotos_rota': [],
        // ignore: use_null_aware_elements
        if (localizacao != null) 'localizacao_inicio': localizacao,
      }));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viagem iniciada com sucesso!')),
      );
      widget.onSalva();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar viagem: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final veiculos = widget.veiculosMap.entries.toList();
    final motoristas = widget.motoristasMap.entries.toList();

    InputDecoration field(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.secondary),
          ),
          filled: true,
          fillColor: AppColors.backgroundSoft,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Nova Viagem'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Veículo: dropdown editável para admin/gestor, readonly para motorista
            if (widget.isMotorista && veiculoId != null)
              _ReadonlyField(
                label: 'Veículo',
                value: () {
                  final v = widget.veiculosMap[veiculoId];
                  if (v == null) return veiculoId!;
                  final plate = v['plate']?.toString() ?? '';
                  final desc = '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
                  return '$plate${desc.isNotEmpty ? ' — $desc' : ''}';
                }(),
                icon: Icons.directions_car,
              )
            else
              DropdownButtonFormField<String>(
                value: veiculoId,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                decoration: field('Veículo *', Icons.directions_car),
                items: veiculos.map((e) {
                  final v = e.value;
                  final plate = v['plate']?.toString() ?? '';
                  final desc = '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text('$plate${desc.isNotEmpty ? ' — $desc' : ''}'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => veiculoId = val),
              ),
            const SizedBox(height: 16),
            // Motorista: readonly para motorista (sempre é ele mesmo), dropdown para admin
            if (widget.isMotorista)
              _ReadonlyField(
                label: 'Motorista',
                value: widget.motoristasMap[motoristaId]?['name']?.toString()
                    ?? motoristaId ?? 'Você',
                icon: Icons.person,
              )
            else
              DropdownButtonFormField<String>(
                value: motoristaId,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                decoration: field('Motorista *', Icons.person),
                items: motoristas
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value['name']?.toString() ?? ''),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => motoristaId = val),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: origemCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: field('Origem *', Icons.location_on),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: destinoCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: field('Destino *', Icons.flag),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: kmInicioCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: field('Quilometragem Inicial (KM) *', Icons.speed),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isLoading ? null : _salvar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Iniciar Viagem',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detalhe Viagem ─────────────────────────────────────────────────────────────

class _DetalheViagemPage extends StatefulWidget {
  final Map<String, dynamic> viagem;
  final String veiculoLabel;
  final String motoristaLabel;
  final VoidCallback onAtualizada;

  const _DetalheViagemPage({
    required this.viagem,
    required this.veiculoLabel,
    required this.motoristaLabel,
    required this.onAtualizada,
  });

  @override
  State<_DetalheViagemPage> createState() => _DetalheViagemPageState();
}

class _DetalheViagemPageState extends State<_DetalheViagemPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = false;

  final kmFimCtrl = TextEditingController();
  final obsCtrl = TextEditingController();

  @override
  void dispose() {
    kmFimCtrl.dispose();
    obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _concluir() async {
    if (kmFimCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a quilometragem final')),
      );
      return;
    }
    final kmFim = double.tryParse(kmFimCtrl.text.replaceAll(',', '.'));
    if (kmFim == null || kmFim < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quilometragem final inválida')),
      );
      return;
    }
    final kmInicio = (widget.viagem['quilometragem_inicio'] as num?)?.toDouble() ?? 0;
    if (kmFim < kmInicio) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Quilometragem final não pode ser menor que a inicial ($kmInicio km)')),
      );
      return;
    }
    final kmPerc = kmFim - kmInicio;

    setState(() => isLoading = true);
    final localizacao = await _obterLocalizacao();
    if (!mounted) return;
    try {
      final dataInicio = DateTime.tryParse(widget.viagem['data_inicio']?.toString() ?? '');
      final dataFim = DateTime.now();
      final duracaoMinutos = dataInicio != null ? dataFim.difference(dataInicio).inMinutes : null;

      await supabase.from('viagens').update({
        'data_fim': dataFim.toIso8601String(),
        'quilometragem_fim': kmFim,
        'quilometragem_percorrida': kmPerc,
        'duracao_minutos': duracaoMinutos,
        'status': 'concluida',
        'observacoes': obsCtrl.text,
        // ignore: use_null_aware_elements
        if (localizacao != null) 'localizacao_fim': localizacao,
      }).eq('id', widget.viagem['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Viagem concluída! ${kmPerc.toStringAsFixed(1)} km percorridos.')),
      );
      widget.onAtualizada();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao concluir viagem: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _cancelar() async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancelar viagem', style: TextStyle(color: Colors.white)),
        content: const Text('Deseja realmente cancelar esta viagem?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar viagem', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (conf != true || !mounted) return;
    setState(() => isLoading = true);
    try {
      await supabase.from('viagens').update({
        'status': 'cancelada',
        'data_fim': DateTime.now().toIso8601String(),
      }).eq('id', widget.viagem['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viagem cancelada'), backgroundColor: AppColors.success),
      );
      widget.onAtualizada();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cancelar viagem: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '--';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDuracao(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    if (h == 0) return '${m}min';
    return '${h}h ${m}min';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'em_progresso':
        return AppColors.info;
      case 'concluida':
        return AppColors.success;
      case 'cancelada':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viagem;
    final status = v['status']?.toString() ?? 'desconhecido';
    final kmPerc = (v['quilometragem_percorrida'] as num?)?.toDouble();

    InputDecoration field(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.secondary),
          ),
          filled: true,
          fillColor: AppColors.backgroundSoft,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detalhe da Viagem'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${v['origem'] ?? '-'} → ${v['destino'] ?? '-'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Chip(
                        label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: _statusColor(status)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Veículo', widget.veiculoLabel),
                  _infoRow('Motorista', widget.motoristaLabel),
                  _infoRow('Início', _fmt(v['data_inicio']?.toString())),
                  _infoRow('KM Inicial',
                      '${(v['quilometragem_inicio'] as num?)?.toStringAsFixed(1) ?? '--'} km'),
                  if (kmPerc != null)
                    _infoRow('KM Percorrido', '${kmPerc.toStringAsFixed(1)} km',
                        color: AppColors.secondary),
                  if (v['data_fim'] != null) _infoRow('Fim', _fmt(v['data_fim']?.toString())),
                  if (v['duracao_minutos'] != null)
                    _infoRow('Duração', _fmtDuracao((v['duracao_minutos'] as num).toInt())),
                  if (v['localizacao_inicio'] != null)
                    _infoRow('Localização Início', v['localizacao_inicio'].toString()),
                  if (v['localizacao_fim'] != null)
                    _infoRow('Localização Fim', v['localizacao_fim'].toString()),
                  if (v['observacoes'] != null && v['observacoes'].toString().isNotEmpty)
                    _infoRow('Observações', v['observacoes'].toString()),
                ],
              ),
            ),
            if (status == 'em_progresso') ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Concluir Viagem',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: kmFimCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: field('Quilometragem Final (KM) *', Icons.speed),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: obsCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: field('Observações', Icons.notes),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _cancelar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.danger,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Cancelar Viagem',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _concluir,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Concluir Viagem',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 14, color: color ?? Colors.white)),
        ],
      ),
    );
  }
}

// Campo readonly estilizado para exibir veículo/motorista fixo do MOTORISTA
class _ReadonlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ReadonlyField({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.backgroundSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

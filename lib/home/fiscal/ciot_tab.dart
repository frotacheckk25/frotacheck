import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';

/// Aba CIOT dos Documentos Fiscais: cadastro e acompanhamento do CIOT gerado
/// na operadora de pagamento de frete (Pamcard, Repom, e-Frete...). A emissão
/// automática pela API da operadora entra depois do contrato com ela; até lá
/// o número gerado no portal da operadora é registrado aqui e fica ligado à
/// viagem, ao veículo e ao motorista.
class CiotTab extends StatefulWidget {
  const CiotTab({super.key, required this.empresaId, required this.podeGerenciar});

  final String? empresaId;
  final bool podeGerenciar;

  @override
  State<CiotTab> createState() => CiotTabState();
}

const _statusCiot = {
  'pendente': ('Pendente', AppColors.warning),
  'registrado': ('Registrado', AppColors.success),
  'encerrado': ('Encerrado', AppColors.info),
  'cancelado': ('Cancelado', AppColors.muted),
  'erro': ('Erro', AppColors.danger),
};

String _soDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

String _dataBr(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class CiotTabState extends State<CiotTab> {
  final _supabase = Supabase.instance.client;
  bool _carregando = true;
  List<Map<String, dynamic>> _ciots = [];
  Map<String, Map<String, dynamic>> _veiculos = {};
  Map<String, Map<String, dynamic>> _motoristas = {};
  List<Map<String, dynamic>> _viagens = [];

  @override
  void initState() {
    super.initState();
    carregar();
  }

  @override
  void didUpdateWidget(CiotTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) carregar();
  }

  Future<void> carregar() async {
    final eid = widget.empresaId;
    if (eid == null) {
      setState(() {
        _ciots = [];
        _carregando = false;
      });
      return;
    }
    setState(() => _carregando = true);
    try {
      final r = await Future.wait([
        _supabase.from('ciot_registros').select('*').eq('empresa_id', eid).order('criado_em', ascending: false).limit(300),
        _supabase.from('vehicles').select('id, plate').eq('empresa_id', eid).order('plate', ascending: true),
        _supabase.from('drivers').select('id, name').eq('empresa_id', eid).order('name', ascending: true),
        _supabase.from('viagens').select('id, origem, destino, data_inicio, status, veiculo_id, motorista_id')
            .eq('empresa_id', eid).order('data_inicio', ascending: false).limit(100),
      ]);
      if (!mounted) return;
      setState(() {
        _ciots = List<Map<String, dynamic>>.from(r[0] as List);
        _veiculos = {for (final v in r[1] as List) v['id'].toString(): Map<String, dynamic>.from(v as Map)};
        _motoristas = {for (final m in r[2] as List) m['id'].toString(): Map<String, dynamic>.from(m as Map)};
        _viagens = List<Map<String, dynamic>>.from(r[3] as List);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      showError(context, friendlyError(e));
    }
  }

  Future<void> abrirFormulario([Map<String, dynamic>? ciot]) async {
    if (widget.empresaId == null) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CiotFormPage(
          empresaId: widget.empresaId!,
          ciot: ciot,
          veiculos: _veiculos.values.toList(),
          motoristas: _motoristas.values.toList(),
          viagens: _viagens,
        ),
      ),
    );
    if (ok == true) carregar();
  }

  Future<void> _mudarStatus(Map<String, dynamic> c, String status) async {
    final rotulo = status == 'encerrado' ? 'Encerrar' : 'Cancelar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('$rotulo CIOT?'),
        content: Text(status == 'encerrado'
            ? 'Marque como encerrado depois de encerrar a operação no portal da operadora.'
            : 'Marque como cancelado depois de cancelar no portal da operadora.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(rotulo)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('ciot_registros').update({'status': status}).eq('id', c['id']);
      if (mounted) showSuccess(context, 'CIOT ${status == 'encerrado' ? 'encerrado' : 'cancelado'}.');
      carregar();
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    final aviso = Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Registre aqui o CIOT gerado na operadora de pagamento de frete. '
        'A geração automática pela API da operadora é ativada após o contrato com ela.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
      ),
    );
    if (_ciots.isEmpty) {
      return ListView(children: [
        aviso,
        const SizedBox(height: 60),
        const Center(child: Text('Nenhum CIOT registrado ainda.', style: TextStyle(color: AppColors.textSecondary))),
      ]);
    }
    return RefreshIndicator(
      onRefresh: carregar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          aviso,
          for (final c in _ciots) _cartao(c),
        ],
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> c) {
    final st = _statusCiot[c['status']] ?? ('${c['status']}', AppColors.muted);
    final v = _veiculos[c['veiculo_id']?.toString()];
    final m = _motoristas[c['motorista_id']?.toString()];
    final viagem = _viagens.where((x) => x['id'].toString() == c['viagem_id']?.toString()).firstOrNull;
    Widget linha(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            Icon(i, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
          ]),
        );
    final ativo = c['status'] == 'registrado' || c['status'] == 'pendente';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('CIOT ${c['numero_ciot'] ?? '(sem número)'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: st.$2.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(st.$1, style: TextStyle(color: st.$2, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 4),
        if ((c['operadora'] ?? '').toString().isNotEmpty) linha(Icons.account_balance, 'Operadora: ${c['operadora']}'),
        if ((c['contratado_nome'] ?? '').toString().isNotEmpty)
          linha(Icons.person, 'Contratado: ${c['contratado_nome']}${(c['rntrc'] ?? '').toString().isNotEmpty ? ' · RNTRC ${c['rntrc']}' : ''}'),
        if (c['valor_frete'] != null) linha(Icons.payments, 'Frete contratado: ${moedaBr(c['valor_frete'] as num)}'),
        if (v != null || m != null) linha(Icons.local_shipping, '${v?['plate'] ?? 'sem veículo'} · ${m?['name'] ?? 'sem motorista'}'),
        if (viagem != null) linha(Icons.directions, 'Viagem: ${viagem['origem']} → ${viagem['destino']}'),
        if (c['data_inicio'] != null)
          linha(Icons.event, 'Período: ${_dataBr(c['data_inicio']?.toString())} a ${_dataBr(c['data_fim']?.toString())}'),
        if (widget.podeGerenciar && ativo) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _botao('Editar', Icons.edit, AppColors.info, () => abrirFormulario(c)),
            if (c['status'] == 'registrado') _botao('Encerrar', Icons.flag, AppColors.success, () => _mudarStatus(c, 'encerrado')),
            _botao('Cancelar', Icons.close, AppColors.danger, () => _mudarStatus(c, 'cancelado')),
          ]),
        ],
      ]),
    );
  }

  Widget _botao(String t, IconData i, Color cor, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(i, size: 15, color: cor),
        label: Text(t, style: TextStyle(color: cor, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          side: BorderSide(color: cor.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

// ── Formulário ──────────────────────────────────────────────────────────────
class CiotFormPage extends StatefulWidget {
  const CiotFormPage({
    super.key,
    required this.empresaId,
    this.ciot,
    required this.veiculos,
    required this.motoristas,
    required this.viagens,
  });

  final String empresaId;
  final Map<String, dynamic>? ciot;
  final List<Map<String, dynamic>> veiculos;
  final List<Map<String, dynamic>> motoristas;
  final List<Map<String, dynamic>> viagens;

  @override
  State<CiotFormPage> createState() => _CiotFormPageState();
}

class _CiotFormPageState extends State<CiotFormPage> {
  final _form = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  bool _salvando = false;

  late final Map<String, dynamic> c = widget.ciot ?? {};
  late final _numero = TextEditingController(text: c['numero_ciot']?.toString() ?? '');
  late final _operadora = TextEditingController(text: c['operadora']?.toString() ?? '');
  late final _contratado = TextEditingController(text: c['contratado_nome']?.toString() ?? '');
  late final _doc = TextEditingController(text: c['contratado_doc']?.toString() ?? '');
  late final _rntrc = TextEditingController(text: c['rntrc']?.toString() ?? '');
  late final _valor = TextEditingController(text: c['valor_frete'] is num ? numeroBr(c['valor_frete'] as num) : '');
  late final _obs = TextEditingController(text: c['observacoes']?.toString() ?? '');
  late String? _viagemId = c['viagem_id']?.toString();
  late String? _veiculoId = c['veiculo_id']?.toString();
  late String? _motoristaId = c['motorista_id']?.toString();
  late DateTime? _inicio = DateTime.tryParse(c['data_inicio']?.toString() ?? '') ?? DateTime.now();
  late DateTime? _fim = DateTime.tryParse(c['data_fim']?.toString() ?? '');

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _campo(TextEditingController ctrl, String rotulo,
          {bool obrigatorio = false, TextInputType? teclado, String? dica, String? Function(String)? validar, int linhas = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl,
          keyboardType: teclado,
          maxLines: linhas,
          decoration: InputDecoration(labelText: obrigatorio ? '$rotulo *' : rotulo, hintText: dica),
          validator: (v) {
            final t = (v ?? '').trim();
            if (obrigatorio && t.isEmpty) return 'Obrigatório';
            return validar?.call(t);
          },
        ),
      );

  Widget _data(String rotulo, DateTime? valor, ValueChanged<DateTime?> onSel) => Expanded(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text('$rotulo: ${valor == null ? '—' : _dataBr(_iso(valor))}'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: valor ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null) onSel(d);
          },
        ),
      );

  void _escolherViagem(String? id) {
    setState(() {
      _viagemId = id;
      final v = widget.viagens.where((x) => x['id'].toString() == id).firstOrNull;
      if (v != null) {
        _veiculoId = v['veiculo_id']?.toString() ?? _veiculoId;
        _motoristaId = v['motorista_id']?.toString() ?? _motoristaId;
        final m = widget.motoristas.where((x) => x['id'].toString() == _motoristaId).firstOrNull;
        if (_contratado.text.trim().isEmpty && m != null) _contratado.text = m['name'].toString();
      }
    });
  }

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_inicio != null && _fim != null && _fim!.isBefore(_inicio!)) {
      showError(context, 'A data final deve ser depois da inicial.');
      return;
    }
    final numero = _soDigitos(_numero.text);
    final valor = lerNumeroBr(_valor.text);
    final dados = {
      'numero_ciot': numero.isEmpty ? null : numero,
      'status': numero.isEmpty ? 'pendente' : (c['status'] == 'pendente' || c['status'] == null ? 'registrado' : c['status']),
      'operadora': _operadora.text.trim(),
      'contratado_nome': _contratado.text.trim(),
      'contratado_doc': _doc.text.trim().isEmpty ? null : _soDigitos(_doc.text),
      'rntrc': _soDigitos(_rntrc.text),
      'valor_frete': valor,
      'viagem_id': _viagemId,
      'veiculo_id': _veiculoId,
      'motorista_id': _motoristaId,
      'data_inicio': _inicio == null ? null : _iso(_inicio!),
      'data_fim': _fim == null ? null : _iso(_fim!),
      'observacoes': _obs.text.trim(),
    };
    setState(() => _salvando = true);
    try {
      if (widget.ciot != null) {
        await _supabase.from('ciot_registros').update(dados).eq('id', c['id']);
      } else {
        final auth = context.read<AppAuthProvider>();
        await _supabase.from('ciot_registros').insert(auth.inject({...dados, 'empresa_id': widget.empresaId}));
      }
      if (!mounted) return;
      showSuccess(context, numero.isEmpty ? 'CIOT salvo como pendente (sem número).' : 'CIOT registrado.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showError(context, friendlyError(e));
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.ciot != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(editando ? 'Editar CIOT' : 'Registrar CIOT'), backgroundColor: AppColors.surface),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              _campo(_numero, 'Número do CIOT', teclado: TextInputType.number,
                  dica: 'Deixe em branco se ainda vai gerar na operadora',
                  validar: (t) {
                    final d = _soDigitos(t);
                    return t.isEmpty || (d.length >= 12 && d.length <= 16) ? null : 'O CIOT tem de 12 a 16 números';
                  }),
              _campo(_operadora, 'Operadora de pagamento', obrigatorio: true, dica: 'Ex.: Pamcard, Repom, e-Frete'),
              DropdownButtonFormField<String?>(
                initialValue: _viagemId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Viagem'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sem viagem')),
                  for (final v in widget.viagens)
                    DropdownMenuItem<String?>(
                      value: v['id'].toString(),
                      child: Text('${_dataBr(v['data_inicio']?.toString())} · ${v['origem']} → ${v['destino']}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _escolherViagem,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _veiculoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Veículo'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      for (final v in widget.veiculos) DropdownMenuItem<String?>(value: v['id'].toString(), child: Text(v['plate'].toString())),
                    ],
                    onChanged: (v) => setState(() => _veiculoId = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _motoristaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Motorista'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      for (final m in widget.motoristas)
                        DropdownMenuItem<String?>(value: m['id'].toString(), child: Text(m['name'].toString(), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _motoristaId = v),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              const Text('Contratado (transportador que recebe o frete)',
                  style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _campo(_contratado, 'Nome do contratado', obrigatorio: true),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _campo(_doc, 'CPF/CNPJ', teclado: TextInputType.number, validar: (t) {
                    final d = _soDigitos(t);
                    return t.isEmpty || d.length == 11 || d.length == 14 ? null : 'CPF (11) ou CNPJ (14)';
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(child: _campo(_rntrc, 'RNTRC', teclado: TextInputType.number)),
              ]),
              _campo(_valor, 'Valor do frete contratado (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true),
                  validar: (t) {
                    if (t.isEmpty) return null;
                    final n = lerNumeroBr(t);
                    return n == null || n < 0 ? 'Valor inválido' : null;
                  }),
              Row(children: [
                _data('Início', _inicio, (d) => setState(() => _inicio = d)),
                const SizedBox(width: 10),
                _data('Fim', _fim, (d) => setState(() => _fim = d)),
              ]),
              const SizedBox(height: 14),
              _campo(_obs, 'Observações', linhas: 3),
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(editando ? 'Salvar alterações' : 'Registrar CIOT'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

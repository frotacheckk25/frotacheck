import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';

/// Formulário de emissão de um novo MDF-e, agrupando um ou mais CT-e já
/// autorizados da empresa. Cobre o caso comum: modal rodoviário, carga
/// lotação (um único veículo, uma viagem).
class NovoMdfePage extends StatefulWidget {
  final String empresaId;

  const NovoMdfePage({super.key, required this.empresaId});

  @override
  State<NovoMdfePage> createState() => _NovoMdfePageState();
}

class _NovoMdfePageState extends State<NovoMdfePage> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  bool _enviando = false;
  bool _carregandoCtes = true;

  List<Map<String, dynamic>> _ctesDisponiveis = [];
  final Set<String> _ctesSelecionados = {};

  // Veículo de tração
  final _placaCtrl = TextEditingController();
  final _veiculoUfCtrl = TextEditingController();
  final _renavamCtrl = TextEditingController();

  // Motorista
  final _motoristaNomeCtrl = TextEditingController();
  final _motoristaCpfCtrl = TextEditingController();

  // Rota
  final _ufIniCtrl = TextEditingController();
  final _ufFimCtrl = TextEditingController();
  final _munCarregaNomeCtrl = TextEditingController();
  final _munCarregaCodigoCtrl = TextEditingController();
  final _munCarregaCepCtrl = TextEditingController();
  final _munDescarregaNomeCtrl = TextEditingController();
  final _munDescarregaCodigoCtrl = TextEditingController();
  final _munDescarregaCepCtrl = TextEditingController();

  // Carga
  final _produtoCtrl = TextEditingController();
  final _ncmCtrl = TextEditingController();
  final _valorCargaCtrl = TextEditingController();
  final _pesoBrutoCtrl = TextEditingController();

  // Seguro
  final _seguradoraNomeCtrl = TextEditingController();
  final _seguradoraCnpjCtrl = TextEditingController();
  final _apoliceCtrl = TextEditingController();
  final _averbacaoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarCtesDisponiveis();
  }

  @override
  void dispose() {
    for (final c in [
      _placaCtrl, _veiculoUfCtrl, _renavamCtrl,
      _motoristaNomeCtrl, _motoristaCpfCtrl,
      _ufIniCtrl, _ufFimCtrl,
      _munCarregaNomeCtrl, _munCarregaCodigoCtrl, _munCarregaCepCtrl,
      _munDescarregaNomeCtrl, _munDescarregaCodigoCtrl, _munDescarregaCepCtrl,
      _produtoCtrl, _ncmCtrl, _valorCargaCtrl, _pesoBrutoCtrl,
      _seguradoraNomeCtrl, _seguradoraCnpjCtrl, _apoliceCtrl, _averbacaoCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarCtesDisponiveis() async {
    setState(() => _carregandoCtes = true);
    try {
      final res = await _supabase
          .from('cte_documentos')
          .select('id, numero_cte, serie, destinatario_nome, chave_acesso')
          .eq('empresa_id', widget.empresaId)
          .eq('status', 'autorizado')
          .order('criado_em', ascending: false);
      setState(() => _ctesDisponiveis = List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _carregandoCtes = false);
    }
  }

  Future<void> _emitir() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_ctesSelecionados.isEmpty) {
      showError(context, 'Selecione ao menos um CT-e autorizado para incluir no MDF-e');
      return;
    }

    setState(() => _enviando = true);
    try {
      final resposta = await _supabase.functions.invoke('fiscal-mdfe-emitir', body: {
        'empresa_id': widget.empresaId,
        'cte_ids': _ctesSelecionados.toList(),
        'uf_ini': _ufIniCtrl.text.trim().toUpperCase(),
        'uf_fim': _ufFimCtrl.text.trim().toUpperCase(),
        'veiculo_tracao': {
          'placa': _placaCtrl.text.trim().toUpperCase(),
          'uf': _veiculoUfCtrl.text.trim().toUpperCase(),
          'renavam': _renavamCtrl.text.trim(),
        },
        'motorista': {
          'nome': _motoristaNomeCtrl.text.trim(),
          'cpf': _motoristaCpfCtrl.text.trim(),
        },
        'municipio_carregamento': {
          'codigo_ibge': _munCarregaCodigoCtrl.text.trim(),
          'nome': _munCarregaNomeCtrl.text.trim(),
          'cep': _munCarregaCepCtrl.text.trim(),
        },
        'municipio_descarregamento': {
          'codigo_ibge': _munDescarregaCodigoCtrl.text.trim(),
          'nome': _munDescarregaNomeCtrl.text.trim(),
          'cep': _munDescarregaCepCtrl.text.trim(),
        },
        'carga': {
          'produto_predominante': _produtoCtrl.text.trim(),
          'ncm': _ncmCtrl.text.trim(),
          'valor': _valorCargaCtrl.text.trim(),
          'peso_bruto': _pesoBrutoCtrl.text.trim(),
        },
        'seguro': {
          'seguradora_nome': _seguradoraNomeCtrl.text.trim(),
          'seguradora_cnpj': _seguradoraCnpjCtrl.text.trim(),
          'numero_apolice': _apoliceCtrl.text.trim(),
          'numero_averbacao': _averbacaoCtrl.text.trim(),
        },
      });

      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] == true) {
        if (mounted) {
          showSuccess(context, 'MDF-e autorizado! Chave: ${data['chave_acesso']}');
          Navigator.pop(context, true);
        }
      } else if (data['status'] == 'rejeitado') {
        if (mounted) showError(context, 'Rejeitado pela SEFAZ: ${data['motivo']}');
      } else {
        if (mounted) showError(context, data['erro']?.toString() ?? 'Falha ao emitir MDF-e');
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Emitir MDF-e'), backgroundColor: AppColors.surface),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _secao('CT-e a incluir', [
              if (_carregandoCtes)
                const Center(child: CircularProgressIndicator())
              else if (_ctesDisponiveis.isEmpty)
                const Text('Nenhum CT-e autorizado disponível. Emita um CT-e primeiro.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
              else
                ..._ctesDisponiveis.map((c) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      value: _ctesSelecionados.contains(c['id']),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _ctesSelecionados.add(c['id']);
                        } else {
                          _ctesSelecionados.remove(c['id']);
                        }
                      }),
                      title: Text('CT-e nº ${c['numero_cte']} / série ${c['serie']}',
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text('Destinatário: ${c['destinatario_nome'] ?? '—'}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    )),
            ]),
            const SizedBox(height: 16),
            _secao('Rota', [
              _linha([
                _campo(_ufIniCtrl, 'UF início', required: true, flex: 1),
                _campo(_ufFimCtrl, 'UF fim', required: true, flex: 1),
              ]),
              _linha([
                _campo(_munCarregaNomeCtrl, 'Município de carregamento', flex: 2, required: true),
                _campo(_munCarregaCodigoCtrl, 'Cód. IBGE', required: true),
              ]),
              _campo(_munCarregaCepCtrl, 'CEP do carregamento', required: true),
              _linha([
                _campo(_munDescarregaNomeCtrl, 'Município de descarregamento', flex: 2, required: true),
                _campo(_munDescarregaCodigoCtrl, 'Cód. IBGE', required: true),
              ]),
              _campo(_munDescarregaCepCtrl, 'CEP do descarregamento', required: true),
            ]),
            const SizedBox(height: 16),
            _secao('Veículo de Tração', [
              _linha([
                _campo(_placaCtrl, 'Placa', required: true),
                _campo(_veiculoUfCtrl, 'UF', required: true, flex: 1),
              ]),
              _campo(_renavamCtrl, 'RENAVAM', required: true, numeric: true),
            ]),
            const SizedBox(height: 16),
            _secao('Motorista', [
              _campo(_motoristaNomeCtrl, 'Nome', required: true),
              _campo(_motoristaCpfCtrl, 'CPF', required: true, numeric: true),
            ]),
            const SizedBox(height: 16),
            _secao('Carga', [
              _campo(_produtoCtrl, 'Produto predominante', required: true),
              _linha([
                _campo(_ncmCtrl, 'NCM', required: true),
                _campo(_valorCargaCtrl, 'Valor da carga (R\$)', required: true, numeric: true),
                _campo(_pesoBrutoCtrl, 'Peso bruto (kg)', required: true, numeric: true),
              ]),
            ]),
            const SizedBox(height: 16),
            _secao('Seguro da Carga (exigido pela SEFAZ)', [
              _campo(_seguradoraNomeCtrl, 'Seguradora', required: true),
              _linha([
                _campo(_seguradoraCnpjCtrl, 'CNPJ da seguradora', required: true, numeric: true),
                _campo(_apoliceCtrl, 'Nº da apólice', required: true),
                _campo(_averbacaoCtrl, 'Nº da averbação', required: true),
              ]),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enviando ? null : _emitir,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.all(16)),
                child: _enviando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Emitir MDF-e', style: TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _secao(String titulo, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          ...children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c)),
        ],
      ),
    );
  }

  Widget _linha(List<Widget> campos) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < campos.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(flex: 1, child: campos[i]),
        ],
      ],
    );
  }

  Widget _campo(TextEditingController ctrl, String label, {bool required = false, bool numeric = false, int flex = 1}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null : null,
    );
  }
}

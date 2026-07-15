import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';

/// Formulário de emissão de um novo CT-e. Cobre o caso comum de Fase 1:
/// modal rodoviário, frota própria, um documento fiscal (NF ou NF-e)
/// vinculado à carga.
class NovoCtePage extends StatefulWidget {
  final String empresaId;
  final String? viagemId;

  const NovoCtePage({super.key, required this.empresaId, this.viagemId});

  @override
  State<NovoCtePage> createState() => _NovoCtePageState();
}

class _NovoCtePageState extends State<NovoCtePage> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  bool _enviando = false;

  // Remetente
  final _remDocCtrl = TextEditingController();
  final _remNomeCtrl = TextEditingController();
  final _remLogradouroCtrl = TextEditingController();
  final _remNumeroCtrl = TextEditingController();
  final _remBairroCtrl = TextEditingController();
  final _remMunicipioCodigoCtrl = TextEditingController();
  final _remMunicipioNomeCtrl = TextEditingController();
  final _remUfCtrl = TextEditingController();
  final _remCepCtrl = TextEditingController();

  // Destinatário
  final _destDocCtrl = TextEditingController();
  final _destNomeCtrl = TextEditingController();
  final _destLogradouroCtrl = TextEditingController();
  final _destNumeroCtrl = TextEditingController();
  final _destBairroCtrl = TextEditingController();
  final _destMunicipioCodigoCtrl = TextEditingController();
  final _destMunicipioNomeCtrl = TextEditingController();
  final _destUfCtrl = TextEditingController();
  final _destCepCtrl = TextEditingController();

  // Carga e valores
  final _naturezaCtrl = TextEditingController();
  final _produtoCtrl = TextEditingController();
  final _valorCargaCtrl = TextEditingController();
  final _pesoBrutoCtrl = TextEditingController();
  final _valorFreteCtrl = TextEditingController();

  // Documento fiscal (NF referenciada)
  String _tipoDocFiscal = 'nf';
  final _nfNumeroCtrl = TextEditingController();
  final _nfSerieCtrl = TextEditingController();
  final _nfDataCtrl = TextEditingController();
  final _nfeChaveCtrl = TextEditingController();

  // Veículo (opcional)
  final _placaCtrl = TextEditingController();
  final _veiculoUfCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _remDocCtrl, _remNomeCtrl, _remLogradouroCtrl, _remNumeroCtrl, _remBairroCtrl,
      _remMunicipioCodigoCtrl, _remMunicipioNomeCtrl, _remUfCtrl, _remCepCtrl,
      _destDocCtrl, _destNomeCtrl, _destLogradouroCtrl, _destNumeroCtrl, _destBairroCtrl,
      _destMunicipioCodigoCtrl, _destMunicipioNomeCtrl, _destUfCtrl, _destCepCtrl,
      _naturezaCtrl, _produtoCtrl, _valorCargaCtrl, _pesoBrutoCtrl, _valorFreteCtrl,
      _nfNumeroCtrl, _nfSerieCtrl, _nfDataCtrl, _nfeChaveCtrl, _placaCtrl, _veiculoUfCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _emitir() async {
    if (_formKey.currentState?.validate() != true) return;

    Map<String, dynamic> documentoFiscal;
    if (_tipoDocFiscal == 'nfe') {
      if (_nfeChaveCtrl.text.trim().length != 44) {
        showError(context, 'Chave da NF-e precisa ter 44 dígitos');
        return;
      }
      documentoFiscal = {'tipo': 'nfe', 'chave': _nfeChaveCtrl.text.trim()};
    } else {
      documentoFiscal = {
        'tipo': 'nf',
        'numero': _nfNumeroCtrl.text.trim(),
        'serie': _nfSerieCtrl.text.trim(),
        'data_emissao': _nfDataCtrl.text.trim(),
        'valor': _valorCargaCtrl.text.trim(),
      };
    }

    setState(() => _enviando = true);
    try {
      final resposta = await _supabase.functions.invoke('fiscal-cte-emitir', body: {
        'empresa_id': widget.empresaId,
        'viagem_id': widget.viagemId,
        'remetente': {
          'documento': _remDocCtrl.text.trim(),
          'nome': _remNomeCtrl.text.trim(),
          'endereco': {
            'logradouro': _remLogradouroCtrl.text.trim(),
            'numero': _remNumeroCtrl.text.trim(),
            'bairro': _remBairroCtrl.text.trim(),
            'municipio_codigo_ibge': _remMunicipioCodigoCtrl.text.trim(),
            'municipio_nome': _remMunicipioNomeCtrl.text.trim(),
            'uf': _remUfCtrl.text.trim().toUpperCase(),
            'cep': _remCepCtrl.text.trim(),
          },
        },
        'destinatario': {
          'documento': _destDocCtrl.text.trim(),
          'nome': _destNomeCtrl.text.trim(),
          'endereco': {
            'logradouro': _destLogradouroCtrl.text.trim(),
            'numero': _destNumeroCtrl.text.trim(),
            'bairro': _destBairroCtrl.text.trim(),
            'municipio_codigo_ibge': _destMunicipioCodigoCtrl.text.trim(),
            'municipio_nome': _destMunicipioNomeCtrl.text.trim(),
            'uf': _destUfCtrl.text.trim().toUpperCase(),
            'cep': _destCepCtrl.text.trim(),
          },
        },
        'carga': {
          'natureza': _naturezaCtrl.text.trim(),
          'produto_predominante': _produtoCtrl.text.trim(),
          'valor': _valorCargaCtrl.text.trim(),
          'peso_bruto': _pesoBrutoCtrl.text.trim(),
        },
        'valores': {'valor_frete': _valorFreteCtrl.text.trim()},
        'documento_fiscal': documentoFiscal,
        'municipio_inicio': {
          'codigo_ibge': _remMunicipioCodigoCtrl.text.trim(),
          'nome': _remMunicipioNomeCtrl.text.trim(),
          'uf': _remUfCtrl.text.trim().toUpperCase(),
        },
        'municipio_fim': {
          'codigo_ibge': _destMunicipioCodigoCtrl.text.trim(),
          'nome': _destMunicipioNomeCtrl.text.trim(),
          'uf': _destUfCtrl.text.trim().toUpperCase(),
        },
        if (_placaCtrl.text.trim().isNotEmpty)
          'veiculo': {'placa': _placaCtrl.text.trim(), 'uf': _veiculoUfCtrl.text.trim().toUpperCase()},
      });

      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] == true) {
        if (mounted) {
          showSuccess(context, 'CT-e autorizado! Chave: ${data['chave_acesso']}');
          Navigator.pop(context, true);
        }
      } else if (data['status'] == 'rejeitado') {
        if (mounted) showError(context, 'Rejeitado pela SEFAZ: ${data['motivo']}');
      } else {
        if (mounted) showError(context, data['erro']?.toString() ?? 'Falha ao emitir CT-e');
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
      appBar: AppBar(title: const Text('Emitir CT-e'), backgroundColor: AppColors.surface),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _secao('Remetente', [
              _campo(_remDocCtrl, 'CNPJ/CPF', required: true),
              _campo(_remNomeCtrl, 'Nome / Razão Social', required: true),
              _linha([
                _campo(_remLogradouroCtrl, 'Logradouro', flex: 2),
                _campo(_remNumeroCtrl, 'Número'),
              ]),
              _linha([
                _campo(_remBairroCtrl, 'Bairro'),
                _campo(_remCepCtrl, 'CEP'),
              ]),
              _linha([
                _campo(_remMunicipioNomeCtrl, 'Município', flex: 2, required: true),
                _campo(_remMunicipioCodigoCtrl, 'Cód. IBGE', required: true),
                _campo(_remUfCtrl, 'UF', flex: 1),
              ]),
            ]),
            const SizedBox(height: 16),
            _secao('Destinatário', [
              _campo(_destDocCtrl, 'CNPJ/CPF', required: true),
              _campo(_destNomeCtrl, 'Nome / Razão Social', required: true),
              _linha([
                _campo(_destLogradouroCtrl, 'Logradouro', flex: 2),
                _campo(_destNumeroCtrl, 'Número'),
              ]),
              _linha([
                _campo(_destBairroCtrl, 'Bairro'),
                _campo(_destCepCtrl, 'CEP'),
              ]),
              _linha([
                _campo(_destMunicipioNomeCtrl, 'Município', flex: 2, required: true),
                _campo(_destMunicipioCodigoCtrl, 'Cód. IBGE', required: true),
                _campo(_destUfCtrl, 'UF', flex: 1),
              ]),
            ]),
            const SizedBox(height: 16),
            _secao('Carga e Frete', [
              _campo(_naturezaCtrl, 'Natureza da carga', required: true),
              _campo(_produtoCtrl, 'Produto predominante'),
              _linha([
                _campo(_valorCargaCtrl, 'Valor da carga (R\$)', required: true, numeric: true),
                _campo(_pesoBrutoCtrl, 'Peso bruto (kg)', numeric: true),
                _campo(_valorFreteCtrl, 'Valor do frete (R\$)', required: true, numeric: true),
              ]),
            ]),
            const SizedBox(height: 16),
            _secao('Documento Fiscal da Carga', [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'nf', label: Text('NF (papel/modelo 1)')),
                  ButtonSegment(value: 'nfe', label: Text('NF-e (chave)')),
                ],
                selected: {_tipoDocFiscal},
                onSelectionChanged: (s) => setState(() => _tipoDocFiscal = s.first),
              ),
              const SizedBox(height: 12),
              if (_tipoDocFiscal == 'nfe')
                _campo(_nfeChaveCtrl, 'Chave da NF-e (44 dígitos)', required: true)
              else
                _linha([
                  _campo(_nfNumeroCtrl, 'Número', required: true),
                  _campo(_nfSerieCtrl, 'Série', required: true),
                  _campo(_nfDataCtrl, 'Data emissão (dd/mm/aaaa)', required: true),
                ]),
            ]),
            const SizedBox(height: 16),
            _secao('Veículo (opcional)', [
              _linha([
                _campo(_placaCtrl, 'Placa'),
                _campo(_veiculoUfCtrl, 'UF', flex: 1),
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
                    : const Text('Emitir CT-e', style: TextStyle(color: Colors.white, fontSize: 15)),
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

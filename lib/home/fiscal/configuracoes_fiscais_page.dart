import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';

/// Configurações fiscais de uma empresa (certificado digital, CNPJ/IE/RNTRC,
/// endereço fiscal, ambiente e habilitação de CT-e). Acessada via card em
/// ConfiguracoesPage (ADMIN_EMPRESA, própria empresa) ou a partir da tela de
/// Documentos Fiscais quando o MASTER está gerenciando outra empresa.
class ConfiguracoesFiscaisPage extends StatefulWidget {
  final String? empresaId;
  final String? empresaNome;

  const ConfiguracoesFiscaisPage({super.key, this.empresaId, this.empresaNome});

  @override
  State<ConfiguracoesFiscaisPage> createState() => _ConfiguracoesFiscaisPageState();
}

class _ConfiguracoesFiscaisPageState extends State<ConfiguracoesFiscaisPage> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _savingEmpresa = false;
  bool _savingEndereco = false;
  bool _uploadingCert = false;
  late String _empresaId;

  // Dados fiscais da empresa
  final _razaoSocialCtrl = TextEditingController();
  final _ieCtrl = TextEditingController();
  final _rntrcCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();

  // Endereço fiscal
  final _logradouroCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complementoCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _municipioCodigoCtrl = TextEditingController();
  final _municipioNomeCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _foneCtrl = TextEditingController();

  String _regimeTributario = 'simples_nacional';
  String _ambienteFiscal = 'homologacao';
  bool _cteHabilitado = false;

  String _certificadoStatus = 'nao_configurado';
  String? _certificadoCn;
  String? _certificadoValidade;

  PlatformFile? _arquivoCert;
  final _senhaCertCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AppAuthProvider>();
    _empresaId = widget.empresaId ?? auth.effectiveEmpresaId ?? '';
    _carregar();
  }

  @override
  void dispose() {
    _razaoSocialCtrl.dispose();
    _ieCtrl.dispose();
    _rntrcCtrl.dispose();
    _ufCtrl.dispose();
    _logradouroCtrl.dispose();
    _numeroCtrl.dispose();
    _complementoCtrl.dispose();
    _bairroCtrl.dispose();
    _municipioCodigoCtrl.dispose();
    _municipioNomeCtrl.dispose();
    _cepCtrl.dispose();
    _foneCtrl.dispose();
    _senhaCertCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_empresaId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supabase
            .from('empresas')
            .select('razao_social, inscricao_estadual, rntrc, uf')
            .eq('id', _empresaId)
            .maybeSingle(),
        _supabase.from('company_settings').select('*').eq('empresa_id', _empresaId).maybeSingle(),
      ]);

      final empresa = results[0];
      final settings = results[1];

      _razaoSocialCtrl.text = empresa?['razao_social']?.toString() ?? '';
      _ieCtrl.text = empresa?['inscricao_estadual']?.toString() ?? '';
      _rntrcCtrl.text = empresa?['rntrc']?.toString() ?? '';
      _ufCtrl.text = empresa?['uf']?.toString() ?? '';

      if (settings != null) {
        _logradouroCtrl.text = settings['fiscal_logradouro']?.toString() ?? '';
        _numeroCtrl.text = settings['fiscal_numero']?.toString() ?? '';
        _complementoCtrl.text = settings['fiscal_complemento']?.toString() ?? '';
        _bairroCtrl.text = settings['fiscal_bairro']?.toString() ?? '';
        _municipioCodigoCtrl.text = settings['fiscal_municipio_codigo_ibge']?.toString() ?? '';
        _municipioNomeCtrl.text = settings['fiscal_municipio_nome']?.toString() ?? '';
        _cepCtrl.text = settings['fiscal_cep']?.toString() ?? '';
        _foneCtrl.text = settings['fiscal_fone']?.toString() ?? '';
        _regimeTributario = settings['fiscal_regime_tributario']?.toString() ?? 'simples_nacional';
        _ambienteFiscal = settings['ambiente_fiscal']?.toString() ?? 'homologacao';
        _cteHabilitado = settings['cte_habilitado'] == true;
        _certificadoStatus = settings['certificado_status']?.toString() ?? 'nao_configurado';
        _certificadoCn = settings['certificado_cn']?.toString();
        _certificadoValidade = settings['certificado_validade']?.toString();
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _salvarDadosFiscais() async {
    setState(() => _savingEmpresa = true);
    try {
      await _supabase.from('empresas').update({
        'razao_social': _razaoSocialCtrl.text.trim(),
        'inscricao_estadual': _ieCtrl.text.trim(),
        'rntrc': _rntrcCtrl.text.trim(),
        'uf': _ufCtrl.text.trim().toUpperCase(),
      }).eq('id', _empresaId);

      await _upsertCompanySettings({
        'fiscal_regime_tributario': _regimeTributario,
        'cte_habilitado': _cteHabilitado,
      });

      if (mounted) showSuccess(context, 'Dados fiscais salvos!');
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingEmpresa = false);
    }
  }

  Future<void> _salvarEndereco() async {
    setState(() => _savingEndereco = true);
    try {
      await _upsertCompanySettings({
        'fiscal_logradouro': _logradouroCtrl.text.trim(),
        'fiscal_numero': _numeroCtrl.text.trim(),
        'fiscal_complemento': _complementoCtrl.text.trim(),
        'fiscal_bairro': _bairroCtrl.text.trim(),
        'fiscal_municipio_codigo_ibge': _municipioCodigoCtrl.text.trim(),
        'fiscal_municipio_nome': _municipioNomeCtrl.text.trim(),
        'fiscal_cep': _cepCtrl.text.trim(),
        'fiscal_fone': _foneCtrl.text.trim(),
      });
      if (mounted) showSuccess(context, 'Endereço fiscal salvo!');
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingEndereco = false);
    }
  }

  Future<void> _salvarAmbiente(String novoAmbiente) async {
    if (novoAmbiente == 'producao') {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Mudar para Produção?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Documentos emitidos em produção têm valor fiscal real perante a SEFAZ. '
            'Só mude para produção depois de validar a emissão em homologação.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (confirmou != true) return;
    }
    setState(() => _ambienteFiscal = novoAmbiente);
    try {
      await _upsertCompanySettings({'ambiente_fiscal': novoAmbiente});
      if (mounted) showSuccess(context, 'Ambiente atualizado!');
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _upsertCompanySettings(Map<String, dynamic> patch) async {
    final existente = await _supabase
        .from('company_settings')
        .select('empresa_id')
        .eq('empresa_id', _empresaId)
        .maybeSingle();
    if (existente != null) {
      await _supabase.from('company_settings').update(patch).eq('empresa_id', _empresaId);
    } else {
      await _supabase.from('company_settings').insert({'empresa_id': _empresaId, ...patch});
    }
  }

  Future<void> _selecionarCertificado() async {
    final resultado = await FilePicker.pickFiles(
      withData: true,
      allowedExtensions: ['pfx', 'p12'],
      type: FileType.custom,
    );
    if (resultado != null && resultado.files.isNotEmpty) {
      setState(() => _arquivoCert = resultado.files.single);
    }
  }

  Future<void> _enviarCertificado() async {
    if (_arquivoCert == null || _arquivoCert!.bytes == null) {
      showError(context, 'Selecione o arquivo .pfx primeiro');
      return;
    }
    if (_senhaCertCtrl.text.isEmpty) {
      showError(context, 'Informe a senha do certificado');
      return;
    }
    setState(() => _uploadingCert = true);
    try {
      final resposta = await _supabase.functions.invoke(
        'fiscal-cert-upload',
        body: {
          'empresa_id': _empresaId,
          'arquivo_base64': base64Encode(_arquivoCert!.bytes!),
          'nome_arquivo': _arquivoCert!.name,
          'senha': _senhaCertCtrl.text,
        },
      );
      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] != true) {
        throw Exception(data['erro'] ?? 'Falha ao validar certificado');
      }
      setState(() {
        _certificadoStatus = 'ativo';
        _certificadoCn = data['cn']?.toString();
        _certificadoValidade = data['validade']?.toString();
        _arquivoCert = null;
        _senhaCertCtrl.clear();
      });
      if (mounted) showSuccess(context, 'Certificado configurado com sucesso!');
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploadingCert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Configurações Fiscais${widget.empresaNome != null ? " — ${widget.empresaNome}" : ""}'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar, tooltip: 'Atualizar'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _empresaId.isEmpty
              ? const Center(
                  child: Text('Nenhuma empresa selecionada.', style: TextStyle(color: AppColors.textSecondary)),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _certificadoCard(),
                      const SizedBox(height: 16),
                      _dadosFiscaisCard(),
                      const SizedBox(height: 16),
                      _enderecoCard(),
                      const SizedBox(height: 16),
                      _ambienteCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Color color, required Widget child}) {
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
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, {String? hint}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _certificadoCard() {
    Color statusColor;
    String statusLabel;
    switch (_certificadoStatus) {
      case 'ativo':
        statusColor = AppColors.success;
        statusLabel = 'Ativo';
        break;
      case 'vencido':
        statusColor = AppColors.danger;
        statusLabel = 'Vencido';
        break;
      case 'erro':
        statusColor = AppColors.danger;
        statusLabel = 'Erro';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = 'Não configurado';
    }

    return _sectionCard(
      title: 'Certificado Digital',
      icon: Icons.badge_rounded,
      color: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, color: statusColor, size: 8),
              const SizedBox(width: 8),
              Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12)),
              if (_certificadoCn != null) ...[
                const SizedBox(width: 10),
                Text(_certificadoCn!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
              if (_certificadoValidade != null) ...[
                const SizedBox(width: 10),
                Text('Válido até ${_certificadoValidade!.split("T").first}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selecionarCertificado,
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: Text(_arquivoCert?.name ?? 'Selecionar .pfx', overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _senhaCertCtrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Senha do certificado',
              labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _uploadingCert ? null : _enviarCertificado,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: _uploadingCert
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enviar Certificado', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dadosFiscaisCard() {
    return _sectionCard(
      title: 'Dados Fiscais',
      icon: Icons.apartment_rounded,
      color: AppColors.primary,
      child: Column(children: [
        _textField(_razaoSocialCtrl, 'Razão Social'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(flex: 2, child: _textField(_ieCtrl, 'Inscrição Estadual')),
          const SizedBox(width: 10),
          Expanded(child: _textField(_rntrcCtrl, 'RNTRC')),
          const SizedBox(width: 10),
          SizedBox(width: 70, child: _textField(_ufCtrl, 'UF')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Regime tributário', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _regimeTributario,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'simples_nacional', child: Text('Simples Nacional')),
                DropdownMenuItem(value: 'normal', child: Text('Regime Normal')),
              ],
              onChanged: (v) => setState(() => _regimeTributario = v ?? 'simples_nacional'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Habilitar emissão de CT-e', style: TextStyle(color: Colors.white, fontSize: 13)),
          value: _cteHabilitado,
          activeThumbColor: AppColors.success,
          onChanged: (v) => setState(() => _cteHabilitado = v),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingEmpresa ? null : _salvarDadosFiscais,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: _savingEmpresa
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar Dados Fiscais', style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _enderecoCard() {
    return _sectionCard(
      title: 'Endereço Fiscal (emitente do CT-e)',
      icon: Icons.location_on_rounded,
      color: AppColors.info,
      child: Column(children: [
        Row(children: [
          Expanded(flex: 3, child: _textField(_logradouroCtrl, 'Logradouro')),
          const SizedBox(width: 10),
          Expanded(child: _textField(_numeroCtrl, 'Número')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _textField(_complementoCtrl, 'Complemento')),
          const SizedBox(width: 10),
          Expanded(child: _textField(_bairroCtrl, 'Bairro')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(flex: 2, child: _textField(_municipioNomeCtrl, 'Município')),
          const SizedBox(width: 10),
          Expanded(child: _textField(_municipioCodigoCtrl, 'Cód. IBGE')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _textField(_cepCtrl, 'CEP')),
          const SizedBox(width: 10),
          Expanded(child: _textField(_foneCtrl, 'Telefone')),
        ]),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'O código IBGE do município é obrigatório para o XML do CT-e '
            '(consulte em ibge.gov.br/explica/codigos-dos-municipios.php).',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingEndereco ? null : _salvarEndereco,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: _savingEndereco
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar Endereço', style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _ambienteCard() {
    final isProducao = _ambienteFiscal == 'producao';
    return _sectionCard(
      title: 'Ambiente',
      icon: Icons.dns_rounded,
      color: isProducao ? AppColors.danger : AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isProducao)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Homologação: documentos emitidos aqui NÃO têm valor fiscal. '
                'Use para testar antes de liberar produção.',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'homologacao', label: Text('Homologação')),
              ButtonSegment(value: 'producao', label: Text('Produção')),
            ],
            selected: {_ambienteFiscal},
            onSelectionChanged: (s) => _salvarAmbiente(s.first),
          ),
        ],
      ),
    );
  }
}

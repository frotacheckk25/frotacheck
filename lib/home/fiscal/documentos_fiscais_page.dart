import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import 'ciot_tab.dart';
import 'configuracoes_fiscais_page.dart';
import 'novo_cte_page.dart';
import 'novo_mdfe_page.dart';

/// Lista de Documentos Fiscais (CT-e/MDF-e/CIOT). CIOT ainda não tem
/// emissão implementada (Fase 3) — a aba existe desde já para não exigir
/// retrabalho de navegação depois.
class DocumentosFiscaisPage extends StatefulWidget {
  const DocumentosFiscaisPage({super.key});

  @override
  State<DocumentosFiscaisPage> createState() => _DocumentosFiscaisPageState();
}

class _DocumentosFiscaisPageState extends State<DocumentosFiscaisPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _loading = true;
  bool _isMaster = false;
  List<Map<String, dynamic>> _empresas = [];
  String? _selectedEmpresaId;
  String? _selectedEmpresaNome;

  List<Map<String, dynamic>> _cteDocs = [];
  List<Map<String, dynamic>> _mdfeDocs = [];
  final _ciotKey = GlobalKey<CiotTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // o botão flutuante muda conforme a aba (Emitir CT-e / MDF-e / Registrar CIOT)
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final auth = context.read<AppAuthProvider>();
    _isMaster = auth.isMaster;

    try {
      if (_isMaster) {
        final res = await _supabase.from('empresas').select('id, nome').order('nome');
        _empresas = List<Map<String, dynamic>>.from(res as List);
        if (_selectedEmpresaId == null && _empresas.isNotEmpty) {
          _selectedEmpresaId = _empresas.first['id']?.toString();
          _selectedEmpresaNome = _empresas.first['nome']?.toString();
        }
      } else {
        _selectedEmpresaId = auth.effectiveEmpresaId;
        _selectedEmpresaNome = auth.empresaNome;
      }

      await Future.wait([_carregarCte(), _carregarMdfe()]);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _carregarCte() async {
    if (_selectedEmpresaId == null) {
      setState(() => _cteDocs = []);
      return;
    }
    final res = await _supabase
        .from('cte_documentos')
        .select('*')
        .eq('empresa_id', _selectedEmpresaId!)
        .order('criado_em', ascending: false)
        .limit(200);
    setState(() => _cteDocs = List<Map<String, dynamic>>.from(res as List));
  }

  Future<void> _carregarMdfe() async {
    if (_selectedEmpresaId == null) {
      setState(() => _mdfeDocs = []);
      return;
    }
    final res = await _supabase
        .from('mdfe_documentos')
        .select('*')
        .eq('empresa_id', _selectedEmpresaId!)
        .order('criado_em', ascending: false)
        .limit(200);
    setState(() => _mdfeDocs = List<Map<String, dynamic>>.from(res as List));
  }

  Future<void> _abrirNovoCte() async {
    if (_selectedEmpresaId == null) return;
    final criado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NovoCtePage(empresaId: _selectedEmpresaId!)),
    );
    if (criado == true) _carregarCte();
  }

  Future<void> _abrirNovoMdfe() async {
    if (_selectedEmpresaId == null) return;
    final criado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NovoMdfePage(empresaId: _selectedEmpresaId!)),
    );
    if (criado == true) _carregarMdfe();
  }

  Future<void> _abrirConfiguracoes() async {
    if (_selectedEmpresaId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfiguracoesFiscaisPage(
          empresaId: _selectedEmpresaId,
          empresaNome: _selectedEmpresaNome,
        ),
      ),
    );
    _carregar();
  }

  Future<void> _verXml(String path) async {
    try {
      final url = await _supabase.storage.from('documentos-fiscais').createSignedUrl(path, 3600);
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _cancelar(Map<String, dynamic> doc) async {
    final justificativaCtrl = TextEditingController();
    final justificativa = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancelar CT-e', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: justificativaCtrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Justificativa (mínimo 15 caracteres, exigência da SEFAZ)',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, justificativaCtrl.text),
            child: const Text('Confirmar Cancelamento', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (justificativa == null || justificativa.length < 15) {
      if (justificativa != null && mounted) {
        showError(context, 'Justificativa precisa ter no mínimo 15 caracteres');
      }
      return;
    }

    try {
      final resposta = await _supabase.functions.invoke('fiscal-cte-cancelar', body: {
        'empresa_id': _selectedEmpresaId,
        'chave_acesso': doc['chave_acesso'],
        'justificativa': justificativa,
      });
      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] != true) throw Exception(data['erro'] ?? 'Falha ao cancelar');
      if (mounted) showSuccess(context, 'CT-e cancelado!');
      _carregarCte();
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _consultar(Map<String, dynamic> doc) async {
    try {
      final resposta = await _supabase.functions.invoke('fiscal-cte-consultar', body: {
        'empresa_id': _selectedEmpresaId,
        'chave_acesso': doc['chave_acesso'],
      });
      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] != true) throw Exception(data['erro'] ?? 'Falha ao consultar');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Situação na SEFAZ', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Text(data['resposta_acbr']?.toString() ?? '—',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _cancelarMdfe(Map<String, dynamic> doc) async {
    final justificativaCtrl = TextEditingController();
    final justificativa = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancelar MDF-e', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: justificativaCtrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Justificativa (mínimo 15 caracteres, exigência da SEFAZ)',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, justificativaCtrl.text),
            child: const Text('Confirmar Cancelamento', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (justificativa == null || justificativa.length < 15) {
      if (justificativa != null && mounted) {
        showError(context, 'Justificativa precisa ter no mínimo 15 caracteres');
      }
      return;
    }

    try {
      final resposta = await _supabase.functions.invoke('fiscal-mdfe-cancelar', body: {
        'empresa_id': _selectedEmpresaId,
        'chave_acesso': doc['chave_acesso'],
        'justificativa': justificativa,
      });
      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] != true) throw Exception(data['erro'] ?? 'Falha ao cancelar');
      if (mounted) showSuccess(context, 'MDF-e cancelado!');
      _carregarMdfe();
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _consultarMdfe(Map<String, dynamic> doc) async {
    try {
      final resposta = await _supabase.functions.invoke('fiscal-mdfe-consultar', body: {
        'empresa_id': _selectedEmpresaId,
        'chave_acesso': doc['chave_acesso'],
      });
      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] != true) throw Exception(data['erro'] ?? 'Falha ao consultar');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Situação na SEFAZ', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Text(data['resposta_acbr']?.toString() ?? '—',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _encerrarMdfe(Map<String, dynamic> doc) async {
    final municipioCtrl = TextEditingController();
    final municipio = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Encerrar MDF-e', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: municipioCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Código IBGE do município de encerramento',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, municipioCtrl.text),
            child: const Text('Confirmar Encerramento'),
          ),
        ],
      ),
    );
    if (municipio == null || municipio.trim().isEmpty) return;

    try {
      final resposta = await _supabase.functions.invoke('fiscal-mdfe-encerrar', body: {
        'empresa_id': _selectedEmpresaId,
        'chave_acesso': doc['chave_acesso'],
        'municipio_codigo_ibge': municipio.trim(),
      });
      final data = Map<String, dynamic>.from(resposta.data as Map);
      if (data['ok'] != true) throw Exception(data['erro'] ?? 'Falha ao encerrar');
      if (mounted) showSuccess(context, 'MDF-e encerrado!');
      _carregarMdfe();
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final permitido = auth.can(AppPermission.viewFiscalDocs);
    final podeGerenciar = auth.can(AppPermission.manageFiscalDocs);
    final podeConfigurar = auth.can(AppPermission.manageFiscalSettings);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Documentos Fiscais'),
        backgroundColor: AppColors.surface,
        actions: [
          if (podeConfigurar)
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              onPressed: _abrirConfiguracoes,
              tooltip: 'Configurações Fiscais',
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar, tooltip: 'Atualizar'),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'CT-e'), Tab(text: 'MDF-e'), Tab(text: 'CIOT')],
        ),
      ),
      floatingActionButton: (permitido && podeGerenciar && _selectedEmpresaId != null)
          ? FloatingActionButton.extended(
              onPressed: [_abrirNovoCte, _abrirNovoMdfe, () => _ciotKey.currentState?.abrirFormulario()][_tabController.index],
              icon: const Icon(Icons.add),
              label: Text(const ['Emitir CT-e', 'Emitir MDF-e', 'Registrar CIOT'][_tabController.index]),
              backgroundColor: AppColors.primary,
            )
          : null,
      body: !permitido
          ? const Center(
              child: Text('Você não tem acesso a esta área.', style: TextStyle(color: AppColors.textSecondary)),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_isMaster) ...[
                      const SizedBox(height: 12),
                      _empresaSelector(),
                    ],
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _cteList(),
                          _mdfeList(),
                          CiotTab(key: _ciotKey, empresaId: _selectedEmpresaId, podeGerenciar: podeGerenciar),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _empresaSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Icon(Icons.apartment_rounded, color: AppColors.secondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedEmpresaId,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: _empresas
                  .map((e) => DropdownMenuItem(
                        value: e['id']?.toString(),
                        child: Text(e['nome']?.toString() ?? '—', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                final emp = _empresas.firstWhere((e) => e['id']?.toString() == v, orElse: () => {});
                setState(() {
                  _selectedEmpresaId = v;
                  _selectedEmpresaNome = emp['nome']?.toString();
                });
                _carregarCte();
                _carregarMdfe();
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cteList() {
    if (_cteDocs.isEmpty) {
      return const Center(
        child: Text('Nenhum CT-e emitido ainda.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    final semAverbacao = _cteDocs.where((d) => d['status'] == 'autorizado' && d['averbacao_numero'] == null).length;
    return RefreshIndicator(
      onRefresh: _carregarCte,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _cteDocs.length + (semAverbacao > 0 ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (semAverbacao > 0 && i == 0) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
              ),
              child: Text(
                semAverbacao == 1
                    ? '1 CT-e autorizado ainda sem averbação do seguro da carga.'
                    : '$semAverbacao CT-e autorizados ainda sem averbação do seguro da carga.',
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            );
          }
          return _cteCard(_cteDocs[i - (semAverbacao > 0 ? 1 : 0)]);
        },
      ),
    );
  }

  Future<void> _continuarRascunho(Map<String, dynamic> doc) async {
    if (_selectedEmpresaId == null) return;
    final criado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoCtePage(
          empresaId: _selectedEmpresaId!,
          viagemId: doc['viagem_id']?.toString(),
          cteDocumentoId: doc['id'].toString(),
          inicial: doc,
        ),
      ),
    );
    if (criado == true) _carregarCte();
  }

  /// Averbação do seguro da carga (RCTR-C): o número vem da averbadora/seguradora.
  /// Grava pela função registrar_averbacao — a RLS só deixa o app mexer em rascunho.
  Future<void> _registrarAverbacao(Map<String, dynamic> doc) async {
    final numero = TextEditingController();
    final protocolo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Averbação do CT-e nº ${doc['numero_cte'] ?? '—'}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Informe o número de averbação recebido da seguradora/averbadora.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(controller: numero, decoration: const InputDecoration(labelText: 'Número da averbação *')),
          const SizedBox(height: 10),
          TextField(controller: protocolo, decoration: const InputDecoration(labelText: 'Protocolo (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true) return;
    if (numero.text.trim().length < 3) {
      if (mounted) showError(context, 'Informe o número da averbação.');
      return;
    }
    try {
      await _supabase.rpc('registrar_averbacao', params: {
        'p_cte_id': doc['id'],
        'p_numero': numero.text.trim(),
        'p_protocolo': protocolo.text.trim(),
      });
      if (mounted) showSuccess(context, 'Averbação registrada.');
      _carregarCte();
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Widget _cteCard(Map<String, dynamic> doc) {
    final status = doc['status']?.toString() ?? 'rascunho';
    final podeGerenciar = context.read<AppAuthProvider>().can(AppPermission.manageFiscalDocs);
    final (statusColor, statusLabel) = switch (status) {
      'autorizado' => (AppColors.success, 'Autorizado'),
      'rejeitado' => (AppColors.danger, 'Rejeitado'),
      'cancelado' => (AppColors.textSecondary, 'Cancelado'),
      'erro' => (AppColors.danger, 'Erro'),
      'enviando' => (AppColors.warning, 'Enviando'),
      _ => (AppColors.info, 'Rascunho'),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('CT-e nº ${doc['numero_cte'] ?? '—'} / série ${doc['serie'] ?? '—'}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Destinatário: ${doc['destinatario_nome'] ?? '—'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text('Frete: ${moedaBr(paraDouble(doc['valor_frete']))}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          if (doc['chave_acesso'] != null)
            Text('Chave: ${doc['chave_acesso']}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
          if (status == 'rejeitado' || status == 'erro')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(doc['motivo_rejeicao']?.toString() ?? '',
                  style: const TextStyle(color: AppColors.danger, fontSize: 11.5)),
            ),
          if (status == 'autorizado')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: doc['averbacao_numero'] != null
                  ? Text('✓ Seguro averbado · nº ${doc['averbacao_numero']}',
                      style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600))
                  : const Text('⚠ Pendente de averbação do seguro da carga',
                      style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (status == 'rascunho' && podeGerenciar)
              OutlinedButton.icon(
                onPressed: () => _continuarRascunho(doc),
                icon: const Icon(Icons.send_rounded, size: 14, color: AppColors.secondary),
                label: const Text('Continuar e emitir', style: TextStyle(fontSize: 12, color: AppColors.secondary)),
              ),
            if (status == 'autorizado' && doc['averbacao_numero'] == null && podeGerenciar)
              OutlinedButton.icon(
                onPressed: () => _registrarAverbacao(doc),
                icon: const Icon(Icons.verified_user_rounded, size: 14, color: AppColors.warning),
                label: const Text('Registrar averbação', style: TextStyle(fontSize: 12, color: AppColors.warning)),
              ),
            if (doc['xml_autorizado_url'] != null)
              OutlinedButton.icon(
                onPressed: () => _verXml(doc['xml_autorizado_url']),
                icon: const Icon(Icons.description_rounded, size: 14),
                label: const Text('Ver XML', style: TextStyle(fontSize: 12)),
              ),
            if (status == 'autorizado')
              OutlinedButton.icon(
                onPressed: () => _cancelar(doc),
                icon: const Icon(Icons.cancel_rounded, size: 14, color: AppColors.danger),
                label: const Text('Cancelar', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              ),
            if (status == 'erro' || status == 'enviando')
              OutlinedButton.icon(
                onPressed: () => _consultar(doc),
                icon: const Icon(Icons.search_rounded, size: 14),
                label: const Text('Consultar situação', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _mdfeList() {
    if (_mdfeDocs.isEmpty) {
      return const Center(
        child: Text('Nenhum MDF-e emitido ainda.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregarMdfe,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _mdfeDocs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _mdfeCard(_mdfeDocs[i]),
      ),
    );
  }

  Widget _mdfeCard(Map<String, dynamic> doc) {
    final status = doc['status']?.toString() ?? 'rascunho';
    final (statusColor, statusLabel) = switch (status) {
      'autorizado' => (AppColors.success, 'Autorizado'),
      'encerrado' => (AppColors.info, 'Encerrado'),
      'rejeitado' => (AppColors.danger, 'Rejeitado'),
      'cancelado' => (AppColors.textSecondary, 'Cancelado'),
      'erro' => (AppColors.danger, 'Erro'),
      'enviando' => (AppColors.warning, 'Enviando'),
      _ => (AppColors.info, 'Rascunho'),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('MDF-e nº ${doc['numero_mdfe'] ?? '—'} / série ${doc['serie'] ?? '—'}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          if (doc['chave_acesso'] != null)
            Text('Chave: ${doc['chave_acesso']}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
          if (status == 'rejeitado' || status == 'erro')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(doc['motivo_rejeicao']?.toString() ?? '',
                  style: const TextStyle(color: AppColors.danger, fontSize: 11.5)),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (doc['xml_autorizado_url'] != null)
              OutlinedButton.icon(
                onPressed: () => _verXml(doc['xml_autorizado_url']),
                icon: const Icon(Icons.description_rounded, size: 14),
                label: const Text('Ver XML', style: TextStyle(fontSize: 12)),
              ),
            if (status == 'autorizado')
              OutlinedButton.icon(
                onPressed: () => _encerrarMdfe(doc),
                icon: const Icon(Icons.flag_rounded, size: 14),
                label: const Text('Encerrar viagem', style: TextStyle(fontSize: 12)),
              ),
            if (status == 'autorizado')
              OutlinedButton.icon(
                onPressed: () => _cancelarMdfe(doc),
                icon: const Icon(Icons.cancel_rounded, size: 14, color: AppColors.danger),
                label: const Text('Cancelar', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              ),
            if (status == 'erro' || status == 'enviando')
              OutlinedButton.icon(
                onPressed: () => _consultarMdfe(doc),
                icon: const Icon(Icons.search_rounded, size: 14),
                label: const Text('Consultar situação', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ),
    );
  }
}

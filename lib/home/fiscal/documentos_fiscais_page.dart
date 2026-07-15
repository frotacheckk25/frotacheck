import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_utils.dart';
import 'configuracoes_fiscais_page.dart';
import 'novo_cte_page.dart';

/// Lista de Documentos Fiscais (CT-e/MDF-e/CIOT). MDF-e e CIOT ainda não têm
/// emissão implementada (Fases 2/3) — a aba existe desde já para não exigir
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

      await _carregarCte();
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

  Future<void> _abrirNovoCte() async {
    if (_selectedEmpresaId == null) return;
    final criado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NovoCtePage(empresaId: _selectedEmpresaId!)),
    );
    if (criado == true) _carregarCte();
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
      floatingActionButton: (permitido && podeGerenciar && _tabController.index == 0 && _selectedEmpresaId != null)
          ? FloatingActionButton.extended(
              onPressed: _abrirNovoCte,
              icon: const Icon(Icons.add),
              label: const Text('Emitir CT-e'),
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
                          const Center(
                            child: Text('MDF-e — em breve', style: TextStyle(color: AppColors.textSecondary)),
                          ),
                          const Center(
                            child: Text('CIOT — em breve', style: TextStyle(color: AppColors.textSecondary)),
                          ),
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
    return RefreshIndicator(
      onRefresh: _carregarCte,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _cteDocs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _cteCard(_cteDocs[i]),
      ),
    );
  }

  Widget _cteCard(Map<String, dynamic> doc) {
    final status = doc['status']?.toString() ?? 'rascunho';
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
          Text('Frete: R\$ ${doc['valor_frete'] ?? '0,00'}',
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
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/web_download.dart';
import '../comercial/comercial_page.dart' show soDigitos;
import '../compras/compras_comum.dart' show dataHoraBr;
import '../financeiro/financeiro_comum.dart';
import '../manutencoes/manutencao_comum.dart';
import 'contabil_comum.dart';

/// Contabilidade: resumo e pendências do mês, pacote do contador (XML +
/// planilhas + lançamentos) e fechamento do mês. As travas do mês fechado
/// ficam no banco (docs/MIGRATION_CONTABIL.sql).
class ContabilidadePage extends StatefulWidget {
  const ContabilidadePage({super.key});

  @override
  State<ContabilidadePage> createState() => _ContabilidadePageState();
}

class _ContabilidadePageState extends State<ContabilidadePage> with EmpresaDaTela {
  final supabase = Supabase.instance.client;
  DateTime competencia = DateTime(DateTime.now().year, DateTime.now().month - 1); // mês passado
  bool carregando = true;
  String? erro;
  Map<String, dynamic>? empresa;
  Map<String, dynamic>? config;
  Map<String, dynamic>? fechamento;
  bool seguroConfigurado = false;
  List<Map<String, dynamic>> ctes = [], mdfes = [], compras = [], pagamentos = [], recebimentos = [], eventos = [];
  List<Map<String, dynamic>> pagarVencidas = [], receberVencidas = [];
  int ctesIndefinidos = 0, mdfesAbertos = 0;
  bool gerando = false;
  String progresso = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  DateTime get _proximoMes => DateTime(competencia.year, competencia.month + 1);
  bool get _mesTerminou => !_proximoMes.isAfter(DateTime.now());

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      await prepararEmpresa();
      final eid = empresaAtual;
      if (eid == null) throw Exception('sem empresa');
      final (iniUtc, fimUtc) = faixaUtcDoMes(competencia);
      final ini = isoDia(competencia), fim = isoDia(_proximoMes);
      // vencida = venceu antes do fim do mês (no mês atual, antes de hoje)
      final limiteVencidas = _mesTerminou ? fim : isoDia(DateTime.now());
      final r = await Future.wait([
        fetchAllRows((a, b) => supabase
            .from('cte_documentos')
            .select('id, numero_cte, serie, chave_acesso, ambiente, status, remetente_nome, remetente_doc, destinatario_nome, '
                'destinatario_doc, valor_frete, protocolo_autorizacao, xml_autorizado_url, autorizado_em, averbado_em')
            .eq('empresa_id', eid)
            .inFilter('status', ['autorizado', 'cancelado'])
            .gte('autorizado_em', iniUtc)
            .lt('autorizado_em', fimUtc)
            .order('autorizado_em', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('mdfe_documentos')
            .select('id, numero_mdfe, serie, chave_acesso, ambiente, status, protocolo_autorizacao, xml_autorizado_url, autorizado_em, encerrado_em')
            .eq('empresa_id', eid)
            .inFilter('status', ['autorizado', 'encerrado', 'cancelado'])
            .gte('autorizado_em', iniUtc)
            .lt('autorizado_em', fimUtc)
            .order('autorizado_em', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('compra_recebimentos')
            .select('*, pedidos_compra(numero, fornecedores(nome, documento))')
            .eq('empresa_id', eid)
            .gte('data', ini)
            .lt('data', fim)
            .order('data', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('contas_pagar')
            .select('*, fornecedores(nome, documento), vehicles(plate)')
            .eq('empresa_id', eid)
            .eq('status', 'paga')
            .gte('data_pagamento', ini)
            .lt('data_pagamento', fim)
            .order('data_pagamento', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('contas_receber')
            .select('*, clientes(nome, documento)')
            .eq('empresa_id', eid)
            .eq('status', 'recebida')
            .gte('data_recebimento', ini)
            .lt('data_recebimento', fim)
            .order('data_recebimento', ascending: true)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase.from('contas_pagar').select('id, valor').eq('empresa_id', eid).eq('status', 'aberta').lt('vencimento', limiteVencidas).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('contas_receber').select('id, valor').eq('empresa_id', eid).eq('status', 'aberta').lt('vencimento', limiteVencidas).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase
            .from('cte_documentos')
            .select('id')
            .eq('empresa_id', eid)
            .inFilter('status', ['erro', 'enviando'])
            .gte('criado_em', iniUtc)
            .lt('criado_em', fimUtc)
            .order('id')
            .range(a, b)),
        fetchAllRows((a, b) => supabase.from('mdfe_documentos').select('id').eq('empresa_id', eid).eq('status', 'autorizado').lt('autorizado_em', fimUtc).order('id').range(a, b)),
        fetchAllRows((a, b) => supabase.from('contabil_eventos').select('*').eq('empresa_id', eid).eq('competencia', ini).order('created_at', ascending: false).order('id').range(a, b)),
      ]);
      final fech = await supabase.from('periodos_fechados').select('*').eq('empresa_id', eid).eq('competencia', ini).maybeSingle();
      final cfg = await supabase.from('contabil_config').select('*').eq('empresa_id', eid).maybeSingle();
      Map<String, dynamic>? emp;
      var seguro = false;
      try {
        emp = await supabase.from('empresas').select('nome, razao_social, cnpj').eq('id', eid).maybeSingle();
        final s = await supabase.from('company_settings').select('seguradora_cnpj').eq('empresa_id', eid).limit(1).maybeSingle();
        seguro = (s?['seguradora_cnpj'] ?? '').toString().isNotEmpty;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        ctes = r[0];
        mdfes = r[1];
        compras = r[2];
        pagamentos = r[3];
        recebimentos = r[4];
        pagarVencidas = r[5];
        receberVencidas = r[6];
        ctesIndefinidos = r[7].length;
        mdfesAbertos = r[8].length;
        eventos = r[9];
        fechamento = fech;
        config = cfg;
        empresa = emp;
        seguroConfigurado = seguro;
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar contabilidade: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar a contabilidade.';
      });
    }
  }

  void _mudarMes(int delta) {
    final novo = DateTime(competencia.year, competencia.month + delta);
    if (novo.isAfter(DateTime.now())) return;
    setState(() => competencia = novo);
    _carregar();
  }

  DadosMes _dados({
    Map<String, Uint8List> xmlCte = const {},
    Map<String, Uint8List> xmlMdfe = const {},
    String geradoPor = '',
    String? empresaReserva,
  }) =>
      DadosMes(
        competencia: competencia,
        empresaNome: (empresa?['razao_social'] ?? empresa?['nome'] ?? empresaReserva ?? '').toString(),
        empresaCnpj: empresa?['cnpj']?.toString(),
        ctes: ctes,
        mdfes: mdfes,
        compras: compras,
        pagamentos: pagamentos,
        recebimentos: recebimentos,
        config: config,
        xmlCte: xmlCte,
        xmlMdfe: xmlMdfe,
        fechado: fechamento != null,
        geradoPor: geradoPor,
      );

  Future<void> _abrirConfig() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ContabilConfigPage(empresaId: empresaAtual!, config: config)),
    );
    if (ok == true) _carregar();
  }

  // ── Pacote do contador ────────────────────────────────────────────────────
  Future<void> _gerarPacote() async {
    final eid = empresaAtual!;
    final auth = context.read<AppAuthProvider>();
    setState(() {
      gerando = true;
      progresso = 'Preparando...';
    });
    try {
      final xmlCte = <String, Uint8List>{}, xmlMdfe = <String, Uint8List>{};
      final docs = [
        for (final c in ctes)
          if (c['ambiente'] == 'producao' && c['xml_autorizado_url'] != null && c['chave_acesso'] != null) (xmlCte, c),
        for (final m in mdfes)
          if (m['ambiente'] == 'producao' && m['xml_autorizado_url'] != null && m['chave_acesso'] != null) (xmlMdfe, m),
      ];
      final arquivos = supabase.storage.from('documentos-fiscais');
      for (var i = 0; i < docs.length; i++) {
        if (mounted) setState(() => progresso = 'Baixando XML ${i + 1} de ${docs.length}...');
        final (destino, doc) = docs[i];
        try {
          destino[doc['chave_acesso'].toString()] = await arquivos.download(doc['xml_autorizado_url'].toString());
        } catch (e) {
          debugPrint('XML não baixado (${doc['chave_acesso']}): $e'); // a planilha marca "XML no pacote: não"
        }
      }
      if (mounted) setState(() => progresso = 'Montando o pacote...');
      final zip = montarPacote(_dados(xmlCte: xmlCte, xmlMdfe: xmlMdfe, geradoPor: auth.profile?.nome ?? '', empresaReserva: auth.empresaNome));
      final nome = nomePacote(competencia);
      if (kIsWeb) {
        downloadBytes(zip, nome, 'application/zip');
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile.fromData(zip, name: nome, mimeType: 'application/zip')], subject: nome));
      }

      // Link temporário para o contador baixar (7 dias)
      String? link;
      try {
        final caminho = '$eid/${competenciaChave(competencia)}/$nome';
        await supabase.storage.from('pacotes-contabeis').uploadBinary(caminho, zip,
            fileOptions: const FileOptions(contentType: 'application/zip', upsert: true));
        link = await supabase.storage.from('pacotes-contabeis').createSignedUrl(caminho, 7 * 24 * 3600);
      } catch (e) {
        debugPrint('Link do pacote não criado: $e');
      }
      try {
        await supabase.rpc('registrar_pacote_contabil', params: {
          'p_empresa': eid,
          'p_competencia': isoDia(competencia),
          'p_detalhe': '${xmlCte.length} XML de CT-e, ${xmlMdfe.length} de MDF-e, ${compras.length} compra(s), '
              '${pagamentos.length} pagamento(s), ${recebimentos.length} recebimento(s)',
        });
      } catch (_) {}
      if (!mounted) return;
      setState(() => gerando = false);
      await _mostrarEnvio(nome, zip.length, link);
      _carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => gerando = false);
      showErrorFrom(context, e, prefix: 'Não foi possível gerar o pacote.');
    }
  }

  Future<void> _mostrarEnvio(String nome, int tamanho, String? link) async {
    final contador = (config?['contador_nome'] ?? '').toString().trim();
    final empresaNome = _dados(empresaReserva: context.read<AppAuthProvider>().empresaNome).empresaNome;
    final mensagem = 'Olá${contador.isEmpty ? '' : ', $contador'}! Segue o pacote contábil de ${competenciaRotulo(competencia)}'
        '${empresaNome.isEmpty ? '' : ' da $empresaNome'}: XML dos CT-e e MDF-e, compras, pagamentos, recebimentos e lançamentos contábeis.'
        '${link == null ? '' : '\n\nBaixe aqui (o link vale por 7 dias):\n$link'}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Pacote de ${competenciaRotulo(competencia)} pronto'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('O arquivo $nome (${numeroBr(tamanho / 1024, casas: 0)} KB) foi ${kIsWeb ? 'baixado' : 'gerado'}.'),
            const SizedBox(height: 12),
            if (link != null) ...[
              const Text('Mande o link para o contador baixar (vale por 7 dias):', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                botaoAcao('WhatsApp', Icons.chat, AppColors.success, () async {
                  var n = soDigitos((config?['contador_whatsapp'] ?? '').toString());
                  if (n.length == 10 || n.length == 11) n = '55$n';
                  final uri = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(mensagem)}');
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && ctx.mounted) showError(ctx, 'Não foi possível abrir o WhatsApp.');
                }),
                botaoAcao('E-mail', Icons.email_outlined, AppColors.info, () async {
                  final email = (config?['contador_email'] ?? '').toString().trim();
                  final uri = Uri.parse('mailto:$email?subject=${Uri.encodeComponent('Pacote contábil de ${competenciaRotulo(competencia)} - $empresaNome')}'
                      '&body=${Uri.encodeComponent(mensagem)}');
                  if (!await launchUrl(uri) && ctx.mounted) showError(ctx, 'Não foi possível abrir o e-mail.');
                }),
                botaoAcao('Copiar mensagem', Icons.copy, AppColors.secondary, () async {
                  await Clipboard.setData(ClipboardData(text: mensagem));
                  if (ctx.mounted) showSuccess(ctx, 'Mensagem com o link copiada.');
                }),
              ]),
            ] else
              const Text('Não foi possível criar o link agora: envie o arquivo baixado ao contador.', style: TextStyle(color: AppColors.warning)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
      ),
    );
  }

  // ── Fechar e reabrir ──────────────────────────────────────────────────────
  Future<void> _fechar(int pendencias) async {
    final obs = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Fechar ${competenciaRotulo(competencia)}?'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Com o mês fechado, nenhuma conta paga ou recebida com data nele muda (nem estorno), e não entram '
                'movimentos de estoque nem recebimentos de compra com essas datas. Só o administrador reabre, com motivo.'),
            if (pendencias > 0) ...[
              const SizedBox(height: 10),
              Text('Atenção: ainda há $pendencias pendência(s) na lista.', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 12),
            TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observação (opcional)', hintText: 'Ex.: pacote enviado ao contador em 05/11')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fechar o mês')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('fechar_mes_contabil', params: {'p_empresa': empresaAtual, 'p_competencia': isoDia(competencia), 'p_observacoes': obs.text.trim()});
      if (mounted) showSuccess(context, '${competenciaRotulo(competencia)} fechado.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível fechar o mês.');
    }
  }

  Future<void> _reabrir() async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reabrir ${competenciaRotulo(competencia)}?'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Depois de corrigir, gere o pacote de novo e avise o contador. A reabertura fica registrada com o seu nome.'),
            const SizedBox(height: 12),
            TextField(controller: motivo, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ex.: pagamento lançado com a data errada')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (motivo.text.trim().isEmpty) {
      showError(context, 'Informe o motivo da reabertura.');
      return;
    }
    try {
      await supabase.rpc('reabrir_mes_contabil', params: {'p_empresa': empresaAtual, 'p_competencia': isoDia(competencia), 'p_motivo': motivo.text.trim()});
      if (mounted) showSuccess(context, '${competenciaRotulo(competencia)} reaberto.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Não foi possível reabrir o mês.');
    }
  }

  // ── Tela ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.can(AppPermission.viewFinance)) {
      return Scaffold(appBar: AppBar(title: const Text('Contabilidade')), body: vazioManut(Icons.lock_outline, 'Você não tem acesso à contabilidade.'));
    }
    final podeGerar = auth.can(AppPermission.manageFinance);
    final podeGerir = auth.can(AppPermission.manageAccounting);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Contabilidade'),
        backgroundColor: AppColors.surface,
        actions: [
          if (podeGerir && !carregando && erro == null)
            IconButton(icon: const Icon(Icons.tune), tooltip: 'Contador e plano de contas', onPressed: _abrirConfig),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? vazioManut(Icons.error_outline, erro!)
              : RefreshIndicator(onRefresh: _carregar, child: _conteudo(podeGerar, podeGerir)),
    );
  }

  Widget _conteudo(bool podeGerar, bool podeGerir) {
    final r = resumirMes(_dados());
    final faltam = contasFaltando(config, pagamentos, recebimentos);
    final semAverbacao = seguroConfigurado
        ? ctes.where((c) => c['ambiente'] == 'producao' && c['status'] == 'autorizado' && c['averbado_em'] == null).length
        : 0;
    final comprasSemNota = compras.where((c) => (c['nota_fiscal'] ?? '').toString().trim().isEmpty).length;
    final homologacao = ctes.where((c) => c['ambiente'] != 'producao').length + mdfes.where((m) => m['ambiente'] != 'producao').length;
    double soma(List<Map<String, dynamic>> l) => l.fold<double>(0, (s, x) => s + ((x['valor'] as num?) ?? 0));
    final pendencias = [ctesIndefinidos, semAverbacao, mdfesAbertos, pagarVencidas.length, receberVencidas.length, comprasSemNota, faltam.length]
        .where((n) => n > 0)
        .length;

    Widget card(String t, String v, String sub, Color cor) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12)),
            const SizedBox(height: 6),
            Text(v, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
      if (mostrarSeletorEmpresa) seletorEmpresa(_carregar),
      const SizedBox(height: 12),
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Mês anterior', onPressed: () => _mudarMes(-1)),
        Expanded(
          child: Text(competenciaRotulo(competencia),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Próximo mês',
          onPressed: _proximoMes.isAfter(DateTime.now()) ? null : () => _mudarMes(1),
        ),
      ]),
      const SizedBox(height: 8),
      _cartaoSituacao(podeGerir, pendencias),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (ctx, c) {
        final col = c.maxWidth > 760 ? 4 : 2;
        final w = (c.maxWidth - (col - 1) * 10) / col;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: w, child: card('Fretes (CT-e)', moedaBr(r.valorFretes), '${r.ctesAutorizados} autorizado(s) · ${r.ctesCancelados} cancelado(s)', AppColors.info)),
          SizedBox(width: w, child: card('Compras recebidas', moedaBr(r.comprasValor), '${r.comprasNotas} recebimento(s)', AppColors.secondary)),
          SizedBox(width: w, child: card('Recebido no mês', moedaBr(r.recebido), '${recebimentos.length} baixa(s)', AppColors.success)),
          SizedBox(width: w, child: card('Pago no mês', moedaBr(r.pago), '${pagamentos.length} baixa(s)', AppColors.danger)),
        ]);
      }),
      const SizedBox(height: 8),
      Text('Saldo de caixa do mês: ${moedaBr(r.saldoCaixa)}',
          style: TextStyle(color: r.saldoCaixa >= 0 ? AppColors.success : AppColors.danger, fontWeight: FontWeight.bold)),
      _titulo('Antes de fechar o mês'),
      cartaoManut(
        child: Column(children: [
          _pendencia(ctesIndefinidos == 0, ctesIndefinidos == 0 ? 'Nenhum CT-e com situação indefinida' : '$ctesIndefinidos CT-e com erro ou ainda em envio',
              detalhe: ctesIndefinidos == 0 ? null : 'Confira em Documentos Fiscais (Consultar situação).'),
          if (seguroConfigurado)
            _pendencia(semAverbacao == 0, semAverbacao == 0 ? 'Todos os CT-e averbados no seguro' : '$semAverbacao CT-e sem averbação do seguro'),
          _pendencia(mdfesAbertos == 0, mdfesAbertos == 0 ? 'Nenhum MDF-e aberto' : '$mdfesAbertos MDF-e autorizado(s) e ainda não encerrado(s)'),
          _pendencia(pagarVencidas.isEmpty, pagarVencidas.isEmpty ? 'Nenhuma conta a pagar vencida sem baixa'
              : '${pagarVencidas.length} conta(s) a pagar vencida(s) sem baixa (${moedaBr(soma(pagarVencidas))})',
              detalhe: pagarVencidas.isEmpty ? null : 'Baixe no Financeiro as que já foram pagas.'),
          _pendencia(receberVencidas.isEmpty, receberVencidas.isEmpty ? 'Nenhuma conta a receber vencida sem baixa'
              : '${receberVencidas.length} conta(s) a receber vencida(s) sem baixa (${moedaBr(soma(receberVencidas))})',
              detalhe: receberVencidas.isEmpty ? null : 'Baixe no Financeiro as que já foram recebidas.'),
          _pendencia(comprasSemNota == 0, comprasSemNota == 0 ? 'Todas as compras recebidas têm nota fiscal' : '$comprasSemNota recebimento(s) de compra sem nota fiscal'),
          _pendencia(faltam.isEmpty, faltam.isEmpty ? 'Plano de contas completo para os lançamentos do mês' : 'Falta o código da conta: ${faltam.join(', ')}',
              acao: faltam.isNotEmpty && podeGerir ? _abrirConfig : null, rotuloAcao: 'Configurar'),
          if (homologacao > 0)
            _pendencia(true, '$homologacao documento(s) de homologação (teste) no mês', detalhe: 'Não têm valor fiscal e ficam fora do pacote.', info: true),
        ]),
      ),
      if (r.pagoPorCategoria.isNotEmpty) ...[
        _titulo('Pagamentos por categoria'),
        cartaoManut(
          child: Column(children: [
            for (final e in (r.pagoPorCategoria.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [Text(e.key), const Spacer(), Text(moedaBr(e.value), style: const TextStyle(fontWeight: FontWeight.bold))]),
              ),
          ]),
        ),
      ],
      _titulo('Pacote do contador'),
      cartaoManut(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'Um arquivo ZIP com os XML dos CT-e e MDF-e de produção, planilhas (CT-e com CFOP e ICMS, MDF-e, compras, '
            'pagamentos e recebimentos) e os lançamentos contábeis prontos para importar.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          if ((config?['contador_nome'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Contador: ${config!['contador_nome']}${(config!['contador_escritorio'] ?? '').toString().isNotEmpty ? ' · ${config!['contador_escritorio']}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          if (podeGerar)
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: gerando ? null : _gerarPacote,
                icon: gerando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.folder_zip),
                label: Text(gerando ? progresso : 'Gerar pacote de ${competenciaRotulo(competencia)}'),
              ),
            ),
        ]),
      ),
      if (eventos.isNotEmpty) ...[
        _titulo('Histórico do mês'),
        cartaoManut(
          child: Column(children: [
            for (final e in eventos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    switch (e['acao']) { 'fechado' => Icons.lock, 'reaberto' => Icons.lock_open, _ => Icons.folder_zip },
                    size: 18,
                    color: switch (e['acao']) { 'fechado' => AppColors.success, 'reaberto' => AppColors.warning, _ => AppColors.info },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${switch (e['acao']) { 'fechado' => 'Mês fechado', 'reaberto' => 'Mês reaberto', _ => 'Pacote gerado' }}'
                        '${(e['detalhe'] ?? '').toString().isNotEmpty ? ': ${e['detalhe']}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('${e['usuario_nome'] ?? '-'} · ${dataHoraBr(e['created_at']?.toString())}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _cartaoSituacao(bool podeGerir, int pendencias) {
    final f = fechamento;
    return cartaoManut(
      child: Row(children: [
        Icon(f != null ? Icons.lock : Icons.lock_open, color: f != null ? AppColors.success : AppColors.warning, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f != null ? 'Mês fechado' : 'Mês aberto', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              f != null
                  ? 'Fechado em ${dataHoraBr(f['fechado_em']?.toString())} por ${f['fechado_por_nome'] ?? '-'}'
                      '${(f['observacoes'] ?? '').toString().isNotEmpty ? ' · ${f['observacoes']}' : ''}'
                  : _mesTerminou
                      ? 'Os lançamentos ainda podem mudar. Feche depois de conferir e mandar o pacote ao contador.'
                      : 'O mês ainda não terminou: dá para fechar a partir de 1º de ${competenciaRotulo(_proximoMes)}.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ]),
        ),
        if (podeGerir) ...[
          const SizedBox(width: 10),
          if (f != null)
            botaoAcao('Reabrir', Icons.lock_open, AppColors.warning, _reabrir)
          else if (_mesTerminou)
            botaoAcao('Fechar o mês', Icons.lock, AppColors.success, () => _fechar(pendencias)),
        ],
      ]),
    );
  }

  Widget _pendencia(bool ok, String texto, {String? detalhe, VoidCallback? acao, String? rotuloAcao, bool info = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            info ? Icons.info_outline : (ok ? Icons.check_circle : Icons.warning_amber_rounded),
            color: info ? AppColors.info : (ok ? AppColors.success : AppColors.warning),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(texto, style: TextStyle(fontWeight: ok ? FontWeight.normal : FontWeight.w600)),
              if (detalhe != null) Text(detalhe, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ]),
          ),
          if (acao != null) TextButton(onPressed: acao, child: Text(rotuloAcao ?? 'Ver')),
        ]),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 10),
        child: Text(t, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
      );
}

// ── Contador e plano de contas ──────────────────────────────────────────────
class ContabilConfigPage extends StatefulWidget {
  const ContabilConfigPage({super.key, required this.empresaId, this.config});
  final String empresaId;
  final Map<String, dynamic>? config;

  @override
  State<ContabilConfigPage> createState() => _ContabilConfigPageState();
}

class _ContabilConfigPageState extends State<ContabilConfigPage> {
  final supabase = Supabase.instance.client;
  bool salvando = false;
  late final Map<String, dynamic> c = widget.config ?? {};
  late final Map<String, dynamic> porCategoria = Map<String, dynamic>.from((c['contas_categoria'] as Map?) ?? const {});
  late final campos = {
    for (final k in [
      'contador_nome', 'contador_escritorio', 'contador_crc', 'contador_email', 'contador_whatsapp',
      'conta_caixa', 'conta_receita_frete', 'conta_outras_receitas',
    ])
      k: TextEditingController(text: c[k]?.toString() ?? ''),
  };
  late final contas = {for (final k in categoriasPagar.keys) k: TextEditingController(text: porCategoria[k]?.toString() ?? '')};

  Future<void> _salvar() async {
    setState(() => salvando = true);
    try {
      await supabase.from('contabil_config').upsert({
        'empresa_id': widget.empresaId,
        for (final e in campos.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
        'contas_categoria': {
          for (final e in contas.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        },
      }, onConflict: 'empresa_id');
      if (!mounted) return;
      showSuccess(context, 'Contabilidade configurada.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showErrorFrom(context, e, prefix: 'Não foi possível salvar.');
      setState(() => salvando = false);
    }
  }

  Widget _campo(String chave, String rotulo, {String? dica, TextInputType? teclado}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: campos[chave], keyboardType: teclado, decoration: InputDecoration(labelText: rotulo, hintText: dica)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Contador e plano de contas'), backgroundColor: AppColors.surface),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Contador', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            _campo('contador_nome', 'Nome do contador'),
            _campo('contador_escritorio', 'Escritório de contabilidade'),
            Row(children: [
              Expanded(child: _campo('contador_crc', 'CRC')),
              const SizedBox(width: 12),
              Expanded(child: _campo('contador_whatsapp', 'WhatsApp', dica: '(35) 99999-0000', teclado: TextInputType.phone)),
            ]),
            _campo('contador_email', 'E-mail', teclado: TextInputType.emailAddress),
            const SizedBox(height: 8),
            const Text('Plano de contas', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text(
              'Use os códigos do plano de contas do escritório. Pagamento: débito na conta da categoria e crédito em Caixa/Bancos. '
              'Recebimento: débito em Caixa/Bancos e crédito na receita. Conta em branco sai marcada na planilha para o contador completar.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _campo('conta_caixa', 'Caixa / Bancos', dica: 'Ex.: 1.1.1.01'),
            Row(children: [
              Expanded(child: _campo('conta_receita_frete', 'Receita de fretes', dica: 'Ex.: 3.1.1.01')),
              const SizedBox(width: 12),
              Expanded(child: _campo('conta_outras_receitas', 'Outras receitas')),
            ]),
            const SizedBox(height: 4),
            const Text('Despesas e custos por categoria', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (final e in categoriasPagar.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(e.value.$2, size: 20, color: AppColors.secondary),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: Text(e.value.$1)),
                  Expanded(child: TextField(controller: contas[e.key], decoration: const InputDecoration(labelText: 'Código da conta', isDense: true))),
                ]),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: salvando ? null : _salvar,
                icon: salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: const Text('Salvar'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

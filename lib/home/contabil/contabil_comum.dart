import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../core/utils/formato_br.dart';
import '../financeiro/financeiro_comum.dart' show categoriasPagar;

/// Peças comuns da Contabilidade: competência, planilhas CSV, leitura do XML
/// do CT-e/MDF-e, lançamentos contábeis e o ZIP do pacote do contador.

const nomesMes = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String competenciaRotulo(DateTime c) => '${nomesMes[c.month - 1]} de ${c.year}';

/// "2026-10" (nome de arquivo e pasta do pacote).
String competenciaChave(DateTime c) => '${c.year}-${c.month.toString().padLeft(2, '0')}';

/// Limites do mês (início incluso, fim excluso) no horário local, em UTC —
/// para filtrar colunas com data e hora (autorizado_em) pelo mês do Brasil.
(String, String) faixaUtcDoMes(DateTime c) =>
    (DateTime(c.year, c.month).toUtc().toIso8601String(), DateTime(c.year, c.month + 1).toUtc().toIso8601String());

// ── Planilhas no padrão do Excel brasileiro: ";" e vírgula decimal ──────────
String campoCsv(Object? v) {
  final s = v == null ? '' : v.toString();
  if (s.contains(';') || s.contains('"') || s.contains('\n') || s.contains('\r')) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String linhaCsv(List<Object?> campos) => campos.map(campoCsv).join(';');

/// Arquivo CSV em UTF-8 com BOM (o Excel abre com os acentos certos).
List<int> arquivoCsv(List<String> cabecalho, List<List<Object?>> linhas) {
  final b = StringBuffer('﻿${linhaCsv(cabecalho)}\r\n');
  for (final l in linhas) {
    b.write('${linhaCsv(l)}\r\n');
  }
  return utf8.encode(b.toString());
}

/// 1234.5 → "1234,50" (sem ponto de milhar: a planilha lê como número).
String valorCsv(num? v) => v == null ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

/// "2026-10-05" → "05/10/2026"; data e hora vêm para o horário local.
String dataCsv(Object? iso) {
  final s = iso?.toString() ?? '';
  final d = DateTime.tryParse(s);
  if (d == null) return '';
  final l = s.length > 10 ? d.toLocal() : d;
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

// ── Leitura do XML autorizado ───────────────────────────────────────────────
class DadosCte {
  const DadosCte({
    this.chave, this.numero, this.serie, this.emissao, this.cfop, this.natureza,
    this.ufInicio, this.municipioInicio, this.ufFim, this.municipioFim,
    this.tomador, this.tomadorDoc, this.remetente, this.remetenteDoc, this.destinatario, this.destinatarioDoc,
    this.valorPrestacao, this.valorReceber, this.cst, this.baseIcms, this.aliquotaIcms, this.valorIcms, this.protocolo,
  });
  final String? chave, numero, serie, emissao, cfop, natureza, ufInicio, municipioInicio, ufFim, municipioFim;
  final String? tomador, tomadorDoc, remetente, remetenteDoc, destinatario, destinatarioDoc, cst, protocolo;
  final double? valorPrestacao, valorReceber, baseIcms, aliquotaIcms, valorIcms;
}

XmlElement? _el(XmlNode raiz, String nome) => raiz.findAllElements(nome, namespace: '*').firstOrNull;

String? _txt(XmlNode? raiz, String nome) {
  if (raiz == null) return null;
  final t = _el(raiz, nome)?.innerText.trim();
  return (t == null || t.isEmpty) ? null : t;
}

double? _num(String? s) => s == null ? null : double.tryParse(s);

String? _doc(XmlElement? e) => _txt(e, 'CNPJ') ?? _txt(e, 'CPF');

/// Lê do XML do CT-e (versão 3.00 ou 4.00) o que o contador precisa para a
/// escrituração: CFOP, UFs, tomador, valores da prestação e ICMS (qualquer
/// grupo: 00, 20, 45, 60, 90, outra UF ou Simples Nacional). XML inválido → null.
DadosCte? lerXmlCte(String xml) {
  try {
    final doc = XmlDocument.parse(xml);
    final inf = _el(doc, 'infCte');
    final ide = _el(doc, 'ide');
    if (inf == null || ide == null) return null;
    final rem = _el(inf, 'rem'), dest = _el(inf, 'dest'), exped = _el(inf, 'exped'), receb = _el(inf, 'receb');
    final toma3 = _el(ide, 'toma3') ?? _el(ide, 'toma03');
    final toma4 = _el(ide, 'toma4') ?? _el(ide, 'toma04');
    final codTomador = _txt(toma4 ?? toma3, 'toma');
    final tomadorEl = switch (codTomador) {
      '0' => rem,
      '1' => exped,
      '2' => receb,
      '3' => dest,
      _ => toma4,
    };
    final vPrest = _el(inf, 'vPrest');
    final icms = _el(inf, 'imp') == null ? null : _el(_el(inf, 'imp')!, 'ICMS');
    final grupo = icms?.childElements.firstOrNull;
    return DadosCte(
      chave: inf.getAttribute('Id')?.replaceFirst('CTe', '') ?? _txt(doc, 'chCTe'),
      numero: _txt(ide, 'nCT'),
      serie: _txt(ide, 'serie'),
      emissao: _txt(ide, 'dhEmi'),
      cfop: _txt(ide, 'CFOP'),
      natureza: _txt(ide, 'natOp'),
      ufInicio: _txt(ide, 'UFIni'),
      municipioInicio: _txt(ide, 'xMunIni'),
      ufFim: _txt(ide, 'UFFim'),
      municipioFim: _txt(ide, 'xMunFim'),
      tomador: _txt(tomadorEl, 'xNome'),
      tomadorDoc: _doc(tomadorEl),
      remetente: _txt(rem, 'xNome'),
      remetenteDoc: _doc(rem),
      destinatario: _txt(dest, 'xNome'),
      destinatarioDoc: _doc(dest),
      valorPrestacao: _num(_txt(vPrest, 'vTPrest')),
      valorReceber: _num(_txt(vPrest, 'vRec')),
      cst: _txt(grupo, 'CST'),
      baseIcms: _num(_txt(grupo, 'vBC') ?? _txt(grupo, 'vBCOutraUF') ?? _txt(grupo, 'vBCSTRet')),
      aliquotaIcms: _num(_txt(grupo, 'pICMS') ?? _txt(grupo, 'pICMSOutraUF') ?? _txt(grupo, 'pICMSSTRet')),
      valorIcms: _num(_txt(grupo, 'vICMS') ?? _txt(grupo, 'vICMSOutraUF') ?? _txt(grupo, 'vICMSSTRet')),
      protocolo: _txt(doc, 'nProt'),
    );
  } catch (_) {
    return null;
  }
}

class DadosMdfe {
  const DadosMdfe({this.ufInicio, this.ufFim, this.quantidadeCte, this.valorCarga});
  final String? ufInicio, ufFim;
  final int? quantidadeCte;
  final double? valorCarga;
}

DadosMdfe? lerXmlMdfe(String xml) {
  try {
    final doc = XmlDocument.parse(xml);
    if (_el(doc, 'infMDFe') == null) return null;
    return DadosMdfe(
      ufInicio: _txt(doc, 'UFIni'),
      ufFim: _txt(doc, 'UFFim'),
      quantidadeCte: int.tryParse(_txt(doc, 'qCTe') ?? ''),
      valorCarga: _num(_txt(doc, 'vCarga')),
    );
  } catch (_) {
    return null;
  }
}

// ── Lançamentos contábeis (regime de caixa) ─────────────────────────────────
class Lancamento {
  const Lancamento({
    required this.data, required this.debito, required this.credito, required this.valor, required this.historico,
    this.documento = '', this.participante = '', this.categoria = '',
  });
  final String data; // aaaa-mm-dd
  final String debito, credito, historico, documento, participante, categoria;
  final double valor;
  bool get semConta => debito.isEmpty || credito.isEmpty;
}

String _conta(Object? v) => (v ?? '').toString().trim();

/// Pagamento: débito na conta da categoria, crédito em caixa/bancos.
/// Recebimento: débito em caixa/bancos, crédito em receita de fretes (ou outras).
List<Lancamento> montarLancamentos({
  required List<Map<String, dynamic>> pagamentos,
  required List<Map<String, dynamic>> recebimentos,
  Map<String, dynamic>? config,
}) {
  final cfg = config ?? const <String, dynamic>{};
  final caixa = _conta(cfg['conta_caixa']);
  final porCategoria = (cfg['contas_categoria'] as Map?) ?? const {};
  final l = <Lancamento>[
    for (final p in pagamentos)
      Lancamento(
        data: (p['data_pagamento'] ?? '').toString(),
        debito: _conta(porCategoria[p['categoria'] ?? 'outros']),
        credito: caixa,
        valor: (((p['valor_pago'] ?? p['valor']) as num?) ?? 0).toDouble(),
        historico: 'Pagamento: ${p['descricao'] ?? ''}${p['fornecedores']?['nome'] != null ? ' - ${p['fornecedores']['nome']}' : ''}',
        documento: (p['documento'] ?? '').toString(),
        participante: (p['fornecedores']?['documento'] ?? '').toString(),
        categoria: categoriasPagar[p['categoria']]?.$1 ?? (p['categoria'] ?? 'Outros').toString(),
      ),
    for (final r in recebimentos)
      Lancamento(
        data: (r['data_recebimento'] ?? '').toString(),
        debito: caixa,
        credito: _conta((r['categoria'] ?? 'frete') == 'frete' ? cfg['conta_receita_frete'] : cfg['conta_outras_receitas']),
        valor: (((r['valor_recebido'] ?? r['valor']) as num?) ?? 0).toDouble(),
        historico: 'Recebimento: ${r['descricao'] ?? ''}${r['clientes']?['nome'] != null ? ' - ${r['clientes']['nome']}' : ''}',
        documento: (r['documento'] ?? '').toString(),
        participante: (r['clientes']?['documento'] ?? '').toString(),
        categoria: (r['categoria'] ?? 'frete') == 'frete' ? 'Receita de fretes' : 'Outras receitas',
      ),
  ]..sort((a, b) => a.data.compareTo(b.data));
  return l;
}

/// Contas do plano que faltam para lançar o mês (para o aviso de pendência).
List<String> contasFaltando(Map<String, dynamic>? config, List<Map<String, dynamic>> pagamentos, List<Map<String, dynamic>> recebimentos) {
  final cfg = config ?? const <String, dynamic>{};
  final porCategoria = (cfg['contas_categoria'] as Map?) ?? const {};
  final faltam = <String>[];
  if ((pagamentos.isNotEmpty || recebimentos.isNotEmpty) && _conta(cfg['conta_caixa']).isEmpty) faltam.add('Caixa/Bancos');
  if (recebimentos.any((r) => (r['categoria'] ?? 'frete') == 'frete') && _conta(cfg['conta_receita_frete']).isEmpty) faltam.add('Receita de fretes');
  if (recebimentos.any((r) => (r['categoria'] ?? 'frete') != 'frete') && _conta(cfg['conta_outras_receitas']).isEmpty) faltam.add('Outras receitas');
  for (final cat in {for (final p in pagamentos) (p['categoria'] ?? 'outros').toString()}) {
    if (_conta(porCategoria[cat]).isEmpty) faltam.add(categoriasPagar[cat]?.$1 ?? cat);
  }
  return faltam;
}

// ── Dados e resumo do mês ───────────────────────────────────────────────────
class DadosMes {
  DadosMes({
    required this.competencia,
    required this.empresaNome,
    this.empresaCnpj,
    this.ctes = const [],
    this.mdfes = const [],
    this.compras = const [],
    this.pagamentos = const [],
    this.recebimentos = const [],
    this.config,
    this.xmlCte = const {},
    this.xmlMdfe = const {},
    this.fechado = false,
    this.geradoPor = '',
    DateTime? geradoEm,
  }) : geradoEm = geradoEm ?? DateTime.now();

  final DateTime competencia;
  final String empresaNome;
  final String? empresaCnpj;
  final List<Map<String, dynamic>> ctes, mdfes, compras, pagamentos, recebimentos;
  final Map<String, dynamic>? config;
  /// XML guardado de cada documento, pela chave de acesso.
  final Map<String, Uint8List> xmlCte, xmlMdfe;
  final bool fechado;
  final String geradoPor;
  final DateTime geradoEm;

  /// Só documentos de produção entram no pacote (homologação não vale fiscalmente).
  List<Map<String, dynamic>> get ctesProducao => ctes.where((c) => c['ambiente'] == 'producao').toList();
  List<Map<String, dynamic>> get mdfesProducao => mdfes.where((m) => m['ambiente'] == 'producao').toList();

  DadosCte? cte(Map<String, dynamic> c) {
    final x = xmlCte[c['chave_acesso']];
    return x == null ? null : lerXmlCte(utf8.decode(x, allowMalformed: true));
  }
}

class ResumoMes {
  const ResumoMes({
    required this.ctesAutorizados, required this.ctesCancelados, required this.valorFretes, this.valorIcms,
    required this.mdfes, required this.comprasNotas, required this.comprasValor, required this.recebido, required this.pago,
    required this.pagoPorCategoria,
  });
  final int ctesAutorizados, ctesCancelados, mdfes, comprasNotas;
  final double valorFretes, comprasValor, recebido, pago;
  /// null quando os XML não foram lidos (a tela não baixa os arquivos)
  final double? valorIcms;
  final Map<String, double> pagoPorCategoria;
  double get saldoCaixa => recebido - pago;
}

ResumoMes resumirMes(DadosMes d, {bool lerXml = false}) {
  final autorizados = d.ctesProducao.where((c) => c['status'] == 'autorizado').toList();
  var fretes = 0.0;
  var icms = 0.0;
  for (final c in autorizados) {
    final x = lerXml ? d.cte(c) : null;
    fretes += x?.valorPrestacao ?? ((c['valor_frete'] as num?) ?? 0).toDouble();
    icms += x?.valorIcms ?? 0;
  }
  final porCategoria = <String, double>{};
  for (final p in d.pagamentos) {
    final nome = categoriasPagar[p['categoria']]?.$1 ?? (p['categoria'] ?? 'Outros').toString();
    porCategoria[nome] = (porCategoria[nome] ?? 0) + (((p['valor_pago'] ?? p['valor']) as num?) ?? 0).toDouble();
  }
  double soma(List<Map<String, dynamic>> l, String campo, [String? alternativo]) =>
      l.fold<double>(0, (s, x) => s + (((x[campo] ?? (alternativo == null ? null : x[alternativo])) as num?) ?? 0).toDouble());
  return ResumoMes(
    ctesAutorizados: autorizados.length,
    ctesCancelados: d.ctesProducao.where((c) => c['status'] == 'cancelado').length,
    valorFretes: fretes,
    valorIcms: lerXml ? icms : null,
    mdfes: d.mdfesProducao.where((m) => m['status'] != 'cancelado').length,
    comprasNotas: d.compras.length,
    comprasValor: soma(d.compras, 'valor'),
    recebido: soma(d.recebimentos, 'valor_recebido', 'valor'),
    pago: soma(d.pagamentos, 'valor_pago', 'valor'),
    pagoPorCategoria: porCategoria,
  );
}

// ── Pacote do contador (ZIP) ────────────────────────────────────────────────
String nomePacote(DateTime competencia) => 'pacote-contabil-${competenciaChave(competencia)}.zip';

const _situacao = {'autorizado': 'Autorizado', 'cancelado': 'Cancelado', 'encerrado': 'Encerrado'};

Uint8List montarPacote(DadosMes d) {
  final zip = Archive();
  void arquivo(String nome, List<int> bytes) => zip.addFile(ArchiveFile.bytes(nome, bytes));

  // XML dos documentos de produção
  for (final c in d.ctesProducao) {
    final x = d.xmlCte[c['chave_acesso']];
    if (x != null) arquivo('cte/${c['chave_acesso']}.xml', x);
  }
  for (final m in d.mdfesProducao) {
    final x = d.xmlMdfe[m['chave_acesso']];
    if (x != null) arquivo('mdfe/${m['chave_acesso']}.xml', x);
  }

  // CT-e (saídas)
  arquivo('planilhas/ctes.csv', arquivoCsv([
    'Número', 'Série', 'Chave de acesso', 'Emissão', 'Situação', 'CFOP', 'Natureza da operação',
    'UF início', 'Município início', 'UF fim', 'Município fim', 'Tomador', 'CNPJ/CPF tomador',
    'Remetente', 'CNPJ/CPF remetente', 'Destinatário', 'CNPJ/CPF destinatário',
    'Valor da prestação', 'Valor a receber', 'CST ICMS', 'Base ICMS', 'Alíquota ICMS (%)', 'Valor ICMS', 'Protocolo', 'XML no pacote',
  ], [for (final c in d.ctesProducao) _linhaCte(d, c)]));

  // MDF-e
  arquivo('planilhas/mdfes.csv', arquivoCsv([
    'Número', 'Série', 'Chave de acesso', 'Situação', 'Autorizado em', 'Encerrado em', 'UF início', 'UF fim', 'Qtd. CT-e', 'Valor da carga', 'Protocolo', 'XML no pacote',
  ], [for (final m in d.mdfesProducao) _linhaMdfe(d, m)]));

  // Entradas: recebimentos de compra
  arquivo('planilhas/compras.csv', arquivoCsv([
    'Data', 'Nota fiscal', 'Pedido nº', 'Fornecedor', 'CNPJ/CPF fornecedor', 'Valor', 'Parcelas', 'Pago na entrega', 'Itens',
  ], [
    for (final r in d.compras)
      [
        dataCsv(r['data']), r['nota_fiscal'], r['pedidos_compra']?['numero'], r['pedidos_compra']?['fornecedores']?['nome'],
        r['pedidos_compra']?['fornecedores']?['documento'], valorCsv(r['valor'] as num?), r['parcelas'], r['pago'] == true ? 'sim' : 'não',
        ((r['itens'] as List?) ?? const []).map((i) => '${_qtd(i['quantidade'] as num?)} ${i['unidade'] ?? ''} ${i['descricao']}').join(' | '),
      ],
  ]));

  // Caixa: pagamentos e recebimentos do mês
  arquivo('planilhas/pagamentos.csv', arquivoCsv([
    'Data do pagamento', 'Descrição', 'Categoria', 'Fornecedor', 'CNPJ/CPF', 'Documento', 'Valor', 'Valor pago', 'Forma', 'Vencimento', 'Parcela', 'Veículo',
  ], [
    for (final p in d.pagamentos)
      [
        dataCsv(p['data_pagamento']), p['descricao'], categoriasPagar[p['categoria']]?.$1 ?? p['categoria'], p['fornecedores']?['nome'],
        p['fornecedores']?['documento'], p['documento'], valorCsv(p['valor'] as num?), valorCsv((p['valor_pago'] ?? p['valor']) as num?),
        p['forma_pagamento'], dataCsv(p['vencimento']), '${p['parcela'] ?? 1}/${p['parcelas'] ?? 1}', p['vehicles']?['plate'],
      ],
  ]));
  arquivo('planilhas/recebimentos.csv', arquivoCsv([
    'Data do recebimento', 'Descrição', 'Categoria', 'Cliente', 'CNPJ/CPF', 'Documento', 'Valor', 'Valor recebido', 'Forma', 'Vencimento', 'Parcela',
  ], [
    for (final r in d.recebimentos)
      [
        dataCsv(r['data_recebimento']), r['descricao'], (r['categoria'] ?? 'frete') == 'frete' ? 'Frete' : 'Outros', r['clientes']?['nome'],
        r['clientes']?['documento'], r['documento'], valorCsv(r['valor'] as num?), valorCsv((r['valor_recebido'] ?? r['valor']) as num?),
        r['forma_recebimento'], dataCsv(r['vencimento']), '${r['parcela'] ?? 1}/${r['parcelas'] ?? 1}',
      ],
  ]));

  // Lançamentos contábeis
  final lanc = montarLancamentos(pagamentos: d.pagamentos, recebimentos: d.recebimentos, config: d.config);
  arquivo('planilhas/lancamentos.csv', arquivoCsv([
    'Data', 'Conta débito', 'Conta crédito', 'Valor', 'Histórico', 'Documento', 'CNPJ/CPF', 'Categoria', 'Observação',
  ], [
    for (final l in lanc)
      [
        dataCsv(l.data), l.debito, l.credito, valorCsv(l.valor), l.historico, l.documento, l.participante, l.categoria,
        l.semConta ? 'sem conta contábil definida' : '',
      ],
  ]));

  arquivo('LEIA-ME.txt', utf8.encode(textoLeiaMe(d, resumirMes(d, lerXml: true), lanc)));
  return ZipEncoder().encodeBytes(zip);
}

String _qtd(num? q) => q == null ? '' : (q % 1 == 0 ? q.toInt().toString() : q.toString().replaceAll('.', ','));

List<Object?> _linhaCte(DadosMes d, Map<String, dynamic> c) {
  final x = d.cte(c);
  return [
    x?.numero ?? c['numero_cte'], x?.serie ?? c['serie'], c['chave_acesso'], dataCsv(x?.emissao ?? c['autorizado_em']),
    _situacao[c['status']] ?? c['status'], x?.cfop, x?.natureza, x?.ufInicio, x?.municipioInicio, x?.ufFim, x?.municipioFim,
    x?.tomador, x?.tomadorDoc, x?.remetente ?? c['remetente_nome'], x?.remetenteDoc ?? c['remetente_doc'],
    x?.destinatario ?? c['destinatario_nome'], x?.destinatarioDoc ?? c['destinatario_doc'],
    valorCsv(x?.valorPrestacao ?? (c['valor_frete'] as num?)), valorCsv(x?.valorReceber), x?.cst,
    valorCsv(x?.baseIcms), valorCsv(x?.aliquotaIcms), valorCsv(x?.valorIcms), x?.protocolo ?? c['protocolo_autorizacao'],
    d.xmlCte.containsKey(c['chave_acesso']) ? 'sim' : 'não',
  ];
}

List<Object?> _linhaMdfe(DadosMes d, Map<String, dynamic> m) {
  final bytes = d.xmlMdfe[m['chave_acesso']];
  final x = bytes == null ? null : lerXmlMdfe(utf8.decode(bytes, allowMalformed: true));
  return [
    m['numero_mdfe'], m['serie'], m['chave_acesso'], _situacao[m['status']] ?? m['status'], dataCsv(m['autorizado_em']),
    dataCsv(m['encerrado_em']), x?.ufInicio, x?.ufFim, x?.quantidadeCte, valorCsv(x?.valorCarga), m['protocolo_autorizacao'],
    bytes != null ? 'sim' : 'não',
  ];
}

String textoLeiaMe(DadosMes d, ResumoMes r, List<Lancamento> lanc) {
  String dois(int n) => n.toString().padLeft(2, '0');
  final g = d.geradoEm;
  final semXml = d.ctesProducao.where((c) => !d.xmlCte.containsKey(c['chave_acesso'])).length +
      d.mdfesProducao.where((m) => !d.xmlMdfe.containsKey(m['chave_acesso'])).length;
  final homologacao = d.ctes.length - d.ctesProducao.length + d.mdfes.length - d.mdfesProducao.length;
  final semConta = lanc.where((l) => l.semConta).length;
  final linhas = <String>[
    'PACOTE CONTÁBIL — ${competenciaRotulo(d.competencia).toUpperCase()}',
    'Empresa: ${d.empresaNome}${(d.empresaCnpj ?? '').isNotEmpty ? ' — CNPJ ${d.empresaCnpj}' : ''}',
    'Gerado em ${dois(g.day)}/${dois(g.month)}/${g.year} ${dois(g.hour)}:${dois(g.minute)}${d.geradoPor.isNotEmpty ? ' por ${d.geradoPor}' : ''} (FrotaCheck)',
    d.fechado ? 'Situação do mês: FECHADO — estes valores não mudam mais no sistema.' : 'Situação do mês: ABERTO — os valores ainda podem mudar até o fechamento.',
    '',
    'RESUMO',
    'CT-e autorizados: ${r.ctesAutorizados} — fretes ${moedaBr(r.valorFretes)} — ICMS ${moedaBr(r.valorIcms ?? 0)}',
    'CT-e cancelados: ${r.ctesCancelados}',
    'MDF-e: ${r.mdfes}',
    'Compras recebidas: ${r.comprasNotas} — ${moedaBr(r.comprasValor)}',
    'Recebido no mês: ${moedaBr(r.recebido)}',
    'Pago no mês: ${moedaBr(r.pago)}',
    'Saldo de caixa do mês: ${moedaBr(r.saldoCaixa)}',
    '',
    'ARQUIVOS',
    'cte/                        XML autorizados dos CT-e (produção)',
    'mdfe/                       XML autorizados dos MDF-e (produção)',
    'planilhas/ctes.csv          CT-e com CFOP, UFs, tomador, valores e ICMS',
    'planilhas/mdfes.csv         MDF-e do mês',
    'planilhas/compras.csv       notas de compra recebidas (entradas)',
    'planilhas/pagamentos.csv    contas pagas no mês (regime de caixa)',
    'planilhas/recebimentos.csv  contas recebidas no mês (regime de caixa)',
    'planilhas/lancamentos.csv   lançamentos contábeis (débito e crédito) pelo plano de contas',
    'As planilhas usam ";" como separador e vírgula decimal: abrem direto no Excel.',
    if (semConta > 0 || semXml > 0 || homologacao > 0) ...[
      '',
      'ATENÇÃO',
      if (semConta > 0) '- $semConta lançamento(s) sem conta contábil definida (ver a coluna Observação).',
      if (semXml > 0) '- $semXml documento(s) autorizado(s) sem XML guardado no sistema.',
      if (homologacao > 0) '- $homologacao documento(s) de homologação (teste) ficaram fora do pacote.',
    ],
  ];
  return '${linhas.join('\r\n')}\r\n';
}

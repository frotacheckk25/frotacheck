import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frotacheck/home/contabil/contabil_comum.dart';

const _chave = '31261012345678000199570010000001231000001234';

// CT-e 4.00 autorizado, ICMS normal (grupo 00), tomador = remetente
const _cteNormal = '''<?xml version="1.0" encoding="UTF-8"?>
<cteProc xmlns="http://www.portalfiscal.inf.br/cte" versao="4.00">
  <CTe xmlns="http://www.portalfiscal.inf.br/cte">
    <infCte Id="CTe$_chave" versao="4.00">
      <ide>
        <cUF>31</cUF><CFOP>6353</CFOP><natOp>PRESTACAO DE SERVICO DE TRANSPORTE</natOp>
        <mod>57</mod><serie>1</serie><nCT>123</nCT><dhEmi>2026-10-15T10:20:00-03:00</dhEmi>
        <xMunIni>SAO GONCALO DO SAPUCAI</xMunIni><UFIni>MG</UFIni><xMunFim>SAO PAULO</xMunFim><UFFim>SP</UFFim>
        <toma3><toma>0</toma></toma3>
      </ide>
      <emit><CNPJ>12345678000199</CNPJ><xNome>Transportes Horizonte</xNome></emit>
      <rem><CNPJ>11222333000144</CNPJ><xNome>Laticinios Serra Ltda</xNome></rem>
      <dest><CNPJ>55666777000188</CNPJ><xNome>Mercado Paulista SA</xNome></dest>
      <vPrest><vTPrest>1500.00</vTPrest><vRec>1500.00</vRec><Comp><xNome>FRETE PESO</xNome><vComp>1500.00</vComp></Comp></vPrest>
      <imp><ICMS><ICMS00><CST>00</CST><vBC>1500.00</vBC><pICMS>12.00</pICMS><vICMS>180.00</vICMS></ICMS00></ICMS></imp>
    </infCte>
  </CTe>
  <protCTe versao="4.00"><infProt><chCTe>$_chave</chCTe><nProt>131260000012345</nProt><cStat>100</cStat></infProt></protCTe>
</cteProc>''';

// Simples Nacional, tomador "outros" (toma4), remetente pessoa física
const _cteSimples = '''<CTe xmlns="http://www.portalfiscal.inf.br/cte"><infCte Id="CTe31261012345678000199570010000000071000000070" versao="4.00">
<ide><CFOP>5353</CFOP><natOp>FRETE</natOp><serie>1</serie><nCT>7</nCT><dhEmi>2026-10-02T08:00:00-03:00</dhEmi>
<xMunIni>POUSO ALEGRE</xMunIni><UFIni>MG</UFIni><xMunFim>VARGINHA</xMunFim><UFFim>MG</UFFim>
<toma4><toma>4</toma><CNPJ>99888777000166</CNPJ><xNome>Agro Comercio Ltda</xNome></toma4></ide>
<rem><CPF>12345678901</CPF><xNome>Joao da Silva</xNome></rem><dest><CNPJ>55666777000188</CNPJ><xNome>Cooperativa Sul</xNome></dest>
<vPrest><vTPrest>800.00</vTPrest><vRec>800.00</vRec></vPrest>
<imp><ICMS><ICMSSN><CST>90</CST><indSN>1</indSN></ICMSSN></ICMS></imp></infCte></CTe>''';

const _cteOutraUf = '''<CTe xmlns="http://www.portalfiscal.inf.br/cte"><infCte Id="CTe1" versao="4.00"><ide><CFOP>6932</CFOP><toma3><toma>3</toma></toma3></ide>
<dest><CNPJ>55666777000188</CNPJ><xNome>Cooperativa Sul</xNome></dest><vPrest><vTPrest>1000.00</vTPrest></vPrest>
<imp><ICMS><ICMSOutraUF><CST>90</CST><vBCOutraUF>1000.00</vBCOutraUF><pICMSOutraUF>7.00</pICMSOutraUF><vICMSOutraUF>70.00</vICMSOutraUF></ICMSOutraUF></ICMS></imp>
</infCte></CTe>''';

final _config = {
  'conta_caixa': '1.1.1',
  'conta_receita_frete': '3.1.1',
  'contas_categoria': {'combustivel': '4.1.1'},
};
final _pagamentos = [
  {'data_pagamento': '2026-10-10', 'categoria': 'combustivel', 'valor': 500, 'valor_pago': 500, 'descricao': 'Diesel', 'documento': 'NF 9',
   'fornecedores': {'nome': 'Posto X', 'documento': '12345678000100'}},
  {'data_pagamento': '2026-10-05', 'categoria': 'pedagio', 'valor': 80, 'descricao': 'Pedágio'},
];
final _recebimentos = [
  {'data_recebimento': '2026-10-20', 'categoria': 'frete', 'valor': 1500, 'valor_recebido': 1500, 'descricao': 'Frete coleta 3',
   'clientes': {'nome': 'Cliente Y', 'documento': '99999999000199'}},
  {'data_recebimento': '2026-10-21', 'categoria': 'outros', 'valor': 50, 'descricao': 'Venda de sucata'},
];

void main() {
  test('lê CT-e com ICMS normal: CFOP, UFs, tomador, valores e imposto', () {
    final c = lerXmlCte(_cteNormal)!;
    expect(c.chave, _chave);
    expect(c.numero, '123');
    expect(c.serie, '1');
    expect(c.cfop, '6353');
    expect((c.ufInicio, c.municipioInicio, c.ufFim, c.municipioFim), ('MG', 'SAO GONCALO DO SAPUCAI', 'SP', 'SAO PAULO'));
    expect((c.tomador, c.tomadorDoc), ('Laticinios Serra Ltda', '11222333000144'));
    expect((c.destinatario, c.destinatarioDoc), ('Mercado Paulista SA', '55666777000188'));
    expect((c.valorPrestacao, c.valorReceber), (1500.0, 1500.0));
    expect((c.cst, c.baseIcms, c.aliquotaIcms, c.valorIcms), ('00', 1500.0, 12.0, 180.0));
    expect(c.protocolo, '131260000012345');
    expect(dataCsv(c.emissao), '15/10/2026');
  });

  test('lê CT-e do Simples Nacional com tomador "outros" e remetente pessoa física', () {
    final c = lerXmlCte(_cteSimples)!;
    expect(c.cst, '90');
    expect(c.baseIcms, isNull);
    expect(c.valorIcms, isNull);
    expect((c.tomador, c.tomadorDoc), ('Agro Comercio Ltda', '99888777000166'));
    expect(c.remetenteDoc, '12345678901');
    expect(c.valorPrestacao, 800.0);
  });

  test('lê ICMS de outra UF e tomador destinatário', () {
    final c = lerXmlCte(_cteOutraUf)!;
    expect((c.baseIcms, c.aliquotaIcms, c.valorIcms), (1000.0, 7.0, 70.0));
    expect(c.tomador, 'Cooperativa Sul');
  });

  test('XML inválido ou que não é CT-e não quebra', () {
    expect(lerXmlCte('<abc'), isNull);
    expect(lerXmlCte('<NFe><infNFe/></NFe>'), isNull);
  });

  test('lê o MDF-e', () {
    final m = lerXmlMdfe('<mdfeProc xmlns="http://www.portalfiscal.inf.br/mdfe"><MDFe><infMDFe Id="MDFe31"><ide><UFIni>MG</UFIni>'
        '<UFFim>SP</UFFim></ide><tot><qCTe>3</qCTe><vCarga>45000.00</vCarga></tot></infMDFe></MDFe></mdfeProc>')!;
    expect((m.ufInicio, m.ufFim, m.quantidadeCte, m.valorCarga), ('MG', 'SP', 3, 45000.0));
  });

  test('planilha no padrão do Excel brasileiro', () {
    expect(campoCsv('a;b'), '"a;b"');
    expect(campoCsv('diz "oi"'), '"diz ""oi"""');
    expect(campoCsv(null), '');
    expect(valorCsv(1234.5), '1234,50');
    expect(valorCsv(null), '');
    expect(dataCsv('2026-10-05'), '05/10/2026');
    final bytes = arquivoCsv(['A', 'B'], [[1, 'x;y']]);
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]); // BOM: o Excel reconhece UTF-8 e mostra os acentos
    expect(utf8.decode(bytes.skip(3).toList()), 'A;B\r\n1;"x;y"\r\n');
  });

  test('lançamentos contábeis pelo plano de contas (regime de caixa)', () {
    final l = montarLancamentos(pagamentos: _pagamentos, recebimentos: _recebimentos, config: _config);
    expect(l.map((x) => x.data), ['2026-10-05', '2026-10-10', '2026-10-20', '2026-10-21']);
    expect((l[0].debito, l[0].credito, l[0].semConta), ('', '1.1.1', true)); // pedágio sem conta
    expect((l[1].debito, l[1].credito, l[1].valor), ('4.1.1', '1.1.1', 500.0));
    expect(l[1].historico, 'Pagamento: Diesel - Posto X');
    expect(l[1].participante, '12345678000100');
    expect((l[2].debito, l[2].credito, l[2].categoria), ('1.1.1', '3.1.1', 'Receita de fretes'));
    expect((l[3].debito, l[3].credito, l[3].semConta), ('1.1.1', '', true)); // outras receitas sem conta
    expect(contasFaltando(_config, _pagamentos, _recebimentos), ['Outras receitas', 'Pedágio']);
  });

  test('pacote do contador: XML de produção, planilhas e LEIA-ME', () {
    final dados = DadosMes(
      competencia: DateTime(2026, 10),
      empresaNome: 'Transportes Horizonte',
      empresaCnpj: '12345678000199',
      ctes: [
        {'chave_acesso': _chave, 'ambiente': 'producao', 'status': 'autorizado', 'valor_frete': 1500, 'autorizado_em': '2026-10-15T13:20:05Z'},
        {'chave_acesso': '3126TESTE', 'ambiente': 'homologacao', 'status': 'autorizado', 'valor_frete': 99},
      ],
      mdfes: [
        {'chave_acesso': '3126MDFE', 'ambiente': 'producao', 'status': 'encerrado', 'numero_mdfe': 4, 'serie': 1},
      ],
      compras: [
        {'data': '2026-10-08', 'nota_fiscal': '5678', 'valor': 4480, 'parcelas': 1, 'pago': false,
         'itens': [{'quantidade': 160, 'unidade': 'L', 'descricao': 'Óleo 15W40'}],
         'pedidos_compra': {'numero': 1, 'fornecedores': {'nome': 'Distribuidora Sul', 'documento': '11111111000111'}}},
      ],
      pagamentos: _pagamentos,
      recebimentos: _recebimentos,
      config: _config,
      xmlCte: {_chave: utf8.encode(_cteNormal)},
      fechado: true,
      geradoPor: 'Carlos Mendes',
      geradoEm: DateTime(2026, 11, 3, 9, 30),
    );
    final zip = ZipDecoder().decodeBytes(montarPacote(dados));
    String arquivo(String nome) => utf8.decode(zip.files.firstWhere((f) => f.name == nome).content);
    expect(zip.files.map((f) => f.name).toSet(), {
      'cte/$_chave.xml', 'planilhas/ctes.csv', 'planilhas/mdfes.csv', 'planilhas/compras.csv',
      'planilhas/pagamentos.csv', 'planilhas/recebimentos.csv', 'planilhas/lancamentos.csv', 'LEIA-ME.txt',
    });
    final ctes = arquivo('planilhas/ctes.csv');
    expect(ctes, contains('6353'));
    expect(ctes, contains(';1500,00;1500,00;00;1500,00;12,00;180,00;131260000012345;sim'));
    expect(ctes, isNot(contains('3126TESTE'))); // homologação fica fora
    expect(arquivo('planilhas/compras.csv'), contains('160 L Óleo 15W40'));
    expect(arquivo('planilhas/lancamentos.csv'), contains('10/10/2026;4.1.1;1.1.1;500,00;Pagamento: Diesel - Posto X'));
    expect(arquivo('planilhas/mdfes.csv'), contains('3126MDFE;Encerrado'));
    final leia = arquivo('LEIA-ME.txt');
    expect(leia, contains('PACOTE CONTÁBIL — OUTUBRO DE 2026'));
    expect(leia, contains('Situação do mês: FECHADO'));
    expect(leia, contains('CT-e autorizados: 1 — fretes R\$ 1.500,00 — ICMS R\$ 180,00'));
    expect(leia, contains('Saldo de caixa do mês: R\$ 970,00')); // 1.550 recebidos − 580 pagos
    expect(leia, contains('2 lançamento(s) sem conta contábil'));
    expect(leia, contains('1 documento(s) autorizado(s) sem XML'));
    expect(leia, contains('1 documento(s) de homologação'));
  });

  test('competência e faixa do mês', () {
    expect(competenciaRotulo(DateTime(2026, 10)), 'outubro de 2026');
    expect(competenciaChave(DateTime(2026, 3)), '2026-03');
    expect(nomePacote(DateTime(2026, 10)), 'pacote-contabil-2026-10.zip');
    final (ini, fim) = faixaUtcDoMes(DateTime(2026, 12));
    expect(DateTime.parse(ini).toLocal(), DateTime(2026, 12));
    expect(DateTime.parse(fim).toLocal(), DateTime(2027, 1));
  });
}

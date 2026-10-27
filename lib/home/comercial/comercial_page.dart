import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/app_auth_provider.dart';
import '../../core/enums/app_permission.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fetch_all.dart';
import '../../core/utils/formato_br.dart';
import '../../core/utils/snackbar_utils.dart';
import '../fiscal/novo_cte_page.dart';

/// Comercial + Coleta: clientes, cotações de frete e ordens de coleta.
/// Fluxo: cliente → cotação → (aprovada) coleta programada → coletada → viagem.
/// Tabelas: clientes, cotacoes, coletas (docs/MIGRATION_COMERCIAL_COLETA.sql).

const ufs = [
  'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS', 'MT', 'PA',
  'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO',
];

double? numeroDe(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  // aceita "1.234,56", "1234,56" e "1234.56"
  final normal = t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t;
  return double.tryParse(normal);
}

String dataBr(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String isoData(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String horaCurta(String? h) => (h == null || h.length < 5) ? '' : h.substring(0, 5);

String soDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

const statusCotacao = {
  'aberta': ('Aberta', AppColors.info),
  'aprovada': ('Aprovada', AppColors.success),
  'recusada': ('Recusada', AppColors.danger),
  'cancelada': ('Cancelada', AppColors.muted),
};

const statusColeta = {
  'programada': ('Programada', AppColors.info),
  'em_rota': ('Saiu para coletar', AppColors.warning),
  'coletada': ('Coletada', AppColors.success),
  'cancelada': ('Cancelada', AppColors.muted),
};

class ComercialPage extends StatefulWidget {
  const ComercialPage({super.key, this.abaInicial = 0});

  final int abaInicial;

  @override
  State<ComercialPage> createState() => _ComercialPageState();
}

class _ComercialPageState extends State<ComercialPage> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.abaInicial);

  bool carregando = true;
  String? erro;
  List<Map<String, dynamic>> clientes = [];
  List<Map<String, dynamic>> cotacoes = [];
  List<Map<String, dynamic>> coletas = [];
  Map<String, Map<String, dynamic>> veiculos = {};
  Map<String, Map<String, dynamic>> motoristas = {};

  String buscaCliente = '';
  String filtroCotacao = 'aberta';
  String filtroColeta = 'proximas';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      final eid = context.read<AppAuthProvider>().effectiveEmpresaId;
      PostgrestFilterBuilder<List<Map<String, dynamic>>> porEmpresa(String tabela, String colunas) {
        final q = supabase.from(tabela).select(colunas);
        return eid != null ? q.eq('empresa_id', eid) : q;
      }

      final resultados = await Future.wait([
        fetchAllRows((a, b) => porEmpresa('clientes', '*').order('nome').order('id').range(a, b)),
        fetchAllRows((a, b) => porEmpresa('cotacoes', '*, clientes(nome, telefone)')
            .order('created_at', ascending: false).order('id').range(a, b)),
        fetchAllRows((a, b) => porEmpresa('coletas', '*, clientes(nome, documento, endereco, cidade, uf)')
            .order('data_programada').order('id').range(a, b)),
        fetchAllRows((a, b) => porEmpresa('vehicles', 'id, plate, brand, model, odometer').order('plate').order('id').range(a, b)),
        fetchAllRows((a, b) => porEmpresa('drivers', 'id, name').order('name').order('id').range(a, b)),
      ]);
      if (!mounted) return;
      setState(() {
        clientes = resultados[0];
        cotacoes = resultados[1];
        coletas = resultados[2];
        veiculos = {for (final v in resultados[3]) v['id'].toString(): v};
        motoristas = {for (final m in resultados[4]) m['id'].toString(): m};
        carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar comercial: $e');
      if (!mounted) return;
      setState(() {
        carregando = false;
        erro = 'Não foi possível carregar os dados. Verifique a conexão e tente de novo.';
      });
    }
  }

  // ── Indicadores ──────────────────────────────────────────────────────────
  Widget _indicadores() {
    final hoje = DateTime.now();
    final inicioMes = DateTime(hoje.year, hoje.month);
    bool doMes(Map<String, dynamic> c) {
      final d = DateTime.tryParse(c['updated_at']?.toString() ?? '');
      return d != null && !d.toLocal().isBefore(inicioMes);
    }

    final abertas = cotacoes.where((c) => c['status'] == 'aberta').toList();
    final aprovadasMes = cotacoes.where((c) => c['status'] == 'aprovada' && doMes(c)).toList();
    final recusadasMes = cotacoes.where((c) => c['status'] == 'recusada' && doMes(c)).length;
    final valorAprovado = aprovadasMes.fold<double>(0, (s, c) => s + ((c['valor_frete'] as num?)?.toDouble() ?? 0));
    final valorAberto = abertas.fold<double>(0, (s, c) => s + ((c['valor_frete'] as num?)?.toDouble() ?? 0));
    final decididas = aprovadasMes.length + recusadasMes;
    final conversao = decididas == 0 ? '-' : '${(aprovadasMes.length * 100 / decididas).round()}%';
    final coletasHoje = coletas.where((c) => c['data_programada'] == isoData(hoje) && c['status'] != 'cancelada').length;

    Widget card(String titulo, String valor, String sub, Color cor) => Container(
          width: 170,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 12.5)),
            const SizedBox(height: 8),
            Text(valor, style: TextStyle(color: cor, fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          ]),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(children: [
        card('Cotações abertas', '${abertas.length}', moedaBr(valorAberto), AppColors.info),
        const SizedBox(width: 10),
        card('Fechado no mês', moedaBr(valorAprovado), aprovadasMes.length == 1 ? '1 cotação aprovada' : '${aprovadasMes.length} cotações aprovadas', AppColors.success),
        const SizedBox(width: 10),
        card('Conversão no mês', conversao, 'aprovadas ÷ decididas', AppColors.secondary),
        const SizedBox(width: 10),
        card('Coletas hoje', '$coletasHoje', 'programadas para hoje', AppColors.warning),
      ]),
    );
  }

  // ── Clientes ─────────────────────────────────────────────────────────────
  Widget _abaClientes(bool podeEditar) {
    final termo = buscaCliente.toLowerCase();
    final lista = clientes.where((c) {
      if (termo.isEmpty) return true;
      return '${c['nome']} ${c['documento'] ?? ''} ${c['cidade'] ?? ''}'.toLowerCase().contains(termo);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nome, CNPJ/CPF ou cidade'),
          onChanged: (v) => setState(() => buscaCliente = v),
        ),
      ),
      Expanded(
        child: lista.isEmpty
            ? _vazio(Icons.business_rounded, clientes.isEmpty ? 'Nenhum cliente cadastrado ainda.' : 'Nenhum cliente encontrado.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final c = lista[i];
                  final ativo = c['ativo'] != false;
                  final qtdCot = cotacoes.where((q) => q['cliente_id'] == c['id']).length;
                  return _cartao(
                    onTap: podeEditar ? () => _abrirCliente(c) : null,
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                        child: Icon(c['tipo'] == 'PF' ? Icons.person : Icons.business, color: AppColors.secondary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['nome']?.toString() ?? '-',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ativo ? Colors.white : AppColors.muted)),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if ((c['documento'] ?? '').toString().isNotEmpty) _formatarDoc(c['documento'].toString()),
                              if ((c['cidade'] ?? '').toString().isNotEmpty) '${c['cidade']}/${c['uf'] ?? ''}',
                              '$qtdCot cotaç${qtdCot == 1 ? 'ão' : 'ões'}',
                              if (!ativo) 'INATIVO',
                            ].join(' · '),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ]),
                      ),
                      if ((c['telefone'] ?? '').toString().isNotEmpty)
                        IconButton(
                          tooltip: 'WhatsApp',
                          icon: const Icon(Icons.chat_rounded, color: AppColors.success),
                          onPressed: () => _whatsapp(c['telefone'].toString(), 'Olá, ${c['contato'] ?? c['nome']}!'),
                        ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ── Cotações ─────────────────────────────────────────────────────────────
  Widget _abaCotacoes(bool podeEditar) {
    final lista = filtroCotacao == 'todas' ? cotacoes : cotacoes.where((c) => c['status'] == filtroCotacao).toList();
    return Column(children: [
      _filtros(
        {'aberta': 'Abertas', 'aprovada': 'Aprovadas', 'recusada': 'Recusadas', 'todas': 'Todas'},
        filtroCotacao,
        (v) => setState(() => filtroCotacao = v),
      ),
      Expanded(
        child: lista.isEmpty
            ? _vazio(Icons.request_quote_outlined, 'Nenhuma cotação aqui.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final q = lista[i];
                  final st = statusCotacao[q['status']] ?? ('${q['status']}', AppColors.muted);
                  final vencida = q['status'] == 'aberta' &&
                      q['validade'] != null &&
                      DateTime.tryParse(q['validade'].toString())?.isBefore(DateTime.now().subtract(const Duration(days: 1))) == true;
                  return _cartao(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Cotação nº ${q['numero'] ?? '-'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                        const Spacer(),
                        if (vencida) _chip('Vencida', AppColors.danger),
                        if (vencida) const SizedBox(width: 6),
                        _chip(st.$1, st.$2),
                      ]),
                      const SizedBox(height: 6),
                      Text(q['clientes']?['nome']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('${q['origem_cidade']}/${q['origem_uf']}  →  ${q['destino_cidade']}/${q['destino_uf']}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 14, runSpacing: 4, children: [
                        Text(moedaBr((q['valor_frete'] as num?) ?? 0),
                            style: const TextStyle(color: AppColors.neon, fontWeight: FontWeight.bold, fontSize: 16)),
                        if (q['peso_kg'] != null) _info(Icons.scale, '${numeroBr(q['peso_kg'] as num, casas: 0)} kg'),
                        if ((q['natureza_carga'] ?? '').toString().isNotEmpty) _info(Icons.inventory_2_outlined, q['natureza_carga'].toString()),
                        if (q['validade'] != null) _info(Icons.event, 'válida até ${dataBr(q['validade'].toString())}'),
                      ]),
                      if (q['status'] == 'recusada' && (q['motivo_recusa'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Motivo: ${q['motivo_recusa']}', style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                      ],
                      if (podeEditar) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (q['status'] == 'aberta') ...[
                            _botao('Aprovar e programar coleta', Icons.check_circle, AppColors.success, () => _aprovarCotacao(q)),
                            _botao('Recusar', Icons.cancel_outlined, AppColors.danger, () => _recusarCotacao(q)),
                            _botao('Editar', Icons.edit, AppColors.info, () => _abrirCotacao(q)),
                          ],
                          _botao('Enviar ao cliente', Icons.send_rounded, AppColors.secondary, () => _enviarCotacao(q)),
                          if (q['status'] == 'aprovada' && q['coleta_id'] != null)
                            _botao('Ver coleta', Icons.local_shipping, AppColors.warning, () => _tabs.animateTo(2)),
                        ]),
                      ],
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ── Coletas ──────────────────────────────────────────────────────────────
  Widget _abaColetas(bool podeEditar) {
    final hoje = isoData(DateTime.now());
    final podeFiscal = context.read<AppAuthProvider>().can(AppPermission.manageFiscalDocs);
    final lista = coletas.where((c) {
      final d = c['data_programada']?.toString() ?? '';
      switch (filtroColeta) {
        case 'hoje':
          return d == hoje && c['status'] != 'cancelada';
        case 'proximas':
          return d.compareTo(hoje) >= 0 && (c['status'] == 'programada' || c['status'] == 'em_rota') ||
              (d.compareTo(hoje) < 0 && (c['status'] == 'programada' || c['status'] == 'em_rota')); // atrasadas também
        case 'coletadas':
          return c['status'] == 'coletada';
        default:
          return true;
      }
    }).toList();

    return Column(children: [
      _filtros(
        {'proximas': 'Pendentes', 'hoje': 'Hoje', 'coletadas': 'Coletadas', 'todas': 'Todas'},
        filtroColeta,
        (v) => setState(() => filtroColeta = v),
      ),
      Expanded(
        child: lista.isEmpty
            ? _vazio(Icons.local_shipping_outlined, 'Nenhuma coleta aqui.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final c = lista[i];
                  final st = statusColeta[c['status']] ?? ('${c['status']}', AppColors.muted);
                  final atrasada = (c['status'] == 'programada' || c['status'] == 'em_rota') &&
                      (c['data_programada']?.toString() ?? '').compareTo(hoje) < 0;
                  final v = veiculos[c['veiculo_id']?.toString()];
                  final m = motoristas[c['motorista_id']?.toString()];
                  final janela = [horaCurta(c['hora_inicio']?.toString()), horaCurta(c['hora_fim']?.toString())]
                      .where((h) => h.isNotEmpty)
                      .join(' às ');
                  return _cartao(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Coleta nº ${c['numero'] ?? '-'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                        const Spacer(),
                        if (atrasada) _chip('Atrasada', AppColors.danger),
                        if (atrasada) const SizedBox(width: 6),
                        _chip(st.$1, st.$2),
                      ]),
                      const SizedBox(height: 6),
                      Text(c['clientes']?['nome']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      _info(Icons.event, '${dataBr(c['data_programada']?.toString())}${janela.isNotEmpty ? ' · $janela' : ''}'),
                      const SizedBox(height: 2),
                      _info(Icons.place, '${c['endereco_coleta']} — ${c['cidade']}/${c['uf']}'),
                      if ((c['destino_cidade'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        _info(Icons.flag, 'Destino: ${c['destino_cidade']}/${c['destino_uf'] ?? ''}'),
                      ],
                      const SizedBox(height: 2),
                      _info(Icons.local_shipping,
                          v == null ? 'Sem veículo definido' : '${v['plate']} · ${m?['name'] ?? 'sem motorista'}'),
                      if (c['viagem_id'] != null) ...[
                        const SizedBox(height: 2),
                        _info(Icons.directions, 'Viagem criada'),
                      ],
                      if (podeEditar && c['status'] != 'cancelada') ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (c['status'] == 'programada')
                            _botao('Saiu para coletar', Icons.local_shipping, AppColors.warning, () => _mudarStatusColeta(c, 'em_rota')),
                          if (c['status'] == 'programada' || c['status'] == 'em_rota')
                            _botao('Marcar coletada', Icons.inventory, AppColors.success, () => _mudarStatusColeta(c, 'coletada')),
                          if (c['status'] != 'programada' && c['viagem_id'] == null)
                            _botao('Iniciar viagem', Icons.directions, AppColors.secondary, () => _gerarViagem(c)),
                          if (podeFiscal) _botao('Gerar CT-e', Icons.request_quote, AppColors.neon, () => _gerarCte(c)),
                          if (c['status'] != 'coletada') _botao('Editar', Icons.edit, AppColors.info, () => _abrirColeta(c)),
                          if (c['status'] != 'coletada')
                            _botao('Cancelar', Icons.close, AppColors.danger, () => _mudarStatusColeta(c, 'cancelada')),
                          if ((c['telefone'] ?? '').toString().isNotEmpty)
                            _botao('Contato', Icons.chat_rounded, AppColors.success,
                                () => _whatsapp(c['telefone'].toString(), 'Olá! Aqui é da transportadora, sobre a coleta nº ${c['numero']}.')),
                        ]),
                      ],
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ── Ações ────────────────────────────────────────────────────────────────
  Future<void> _abrirCliente([Map<String, dynamic>? c]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: c)));
    if (ok == true) _carregar();
  }

  Future<void> _abrirCotacao([Map<String, dynamic>? q]) async {
    if (clientes.where((c) => c['ativo'] != false).isEmpty) {
      showError(context, 'Cadastre um cliente antes de criar a cotação.');
      _tabs.animateTo(0);
      return;
    }
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CotacaoFormPage(cotacao: q, clientes: clientes)));
    if (ok == true) _carregar();
  }

  Future<void> _abrirColeta([Map<String, dynamic>? c, Map<String, dynamic>? daCotacao]) async {
    if (clientes.where((x) => x['ativo'] != false).isEmpty) {
      showError(context, 'Cadastre um cliente antes de programar a coleta.');
      _tabs.animateTo(0);
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ColetaFormPage(
          coleta: c,
          cotacao: daCotacao,
          clientes: clientes,
          veiculos: veiculos.values.toList(),
          motoristas: motoristas.values.toList(),
        ),
      ),
    );
    if (ok == true) {
      _carregar();
      if (daCotacao != null) _tabs.animateTo(2);
    }
  }

  Future<void> _aprovarCotacao(Map<String, dynamic> q) => _abrirColeta(null, q);

  Future<void> _recusarCotacao(Map<String, dynamic> q) async {
    final motivo = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Recusar cotação'),
        content: TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (opcional)'), maxLength: 200),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Recusar')),
        ],
      ),
    );
    if (confirmou != true) return;
    try {
      await supabase.from('cotacoes').update({'status': 'recusada', 'motivo_recusa': motivo.text.trim()}).eq('id', q['id']);
      if (!mounted) return;
      showSuccess(context, 'Cotação marcada como recusada.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Erro ao recusar');
    }
  }

  void _enviarCotacao(Map<String, dynamic> q) {
    final empresa = context.read<AppAuthProvider>().empresaNome ?? 'Transportadora';
    final texto = StringBuffer()
      ..writeln('*$empresa — Cotação de frete nº ${q['numero']}*')
      ..writeln()
      ..writeln('Cliente: ${q['clientes']?['nome'] ?? '-'}')
      ..writeln('Origem: ${q['origem_cidade']}/${q['origem_uf']}')
      ..writeln('Destino: ${q['destino_cidade']}/${q['destino_uf']}');
    if ((q['natureza_carga'] ?? '').toString().isNotEmpty) texto.writeln('Carga: ${q['natureza_carga']}');
    if (q['peso_kg'] != null) texto.writeln('Peso: ${numeroBr(q['peso_kg'] as num, casas: 0)} kg');
    texto.writeln('*Valor do frete: ${moedaBr((q['valor_frete'] as num?) ?? 0)}*');
    if (q['validade'] != null) texto.writeln('Válida até: ${dataBr(q['validade'].toString())}');
    if ((q['observacoes'] ?? '').toString().isNotEmpty) texto.writeln('Obs.: ${q['observacoes']}');

    final tel = q['clientes']?['telefone']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy, color: AppColors.secondary),
            title: const Text('Copiar texto da cotação'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: texto.toString()));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) showSuccess(context, 'Texto copiado. É só colar no WhatsApp ou e-mail.');
            },
          ),
          if (tel.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: AppColors.success),
              title: const Text('Enviar pelo WhatsApp do cliente'),
              onTap: () {
                Navigator.pop(ctx);
                _whatsapp(tel, texto.toString());
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _mudarStatusColeta(Map<String, dynamic> c, String status) async {
    if (status == 'cancelada') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Cancelar coleta?'),
          content: Text('A coleta nº ${c['numero']} será cancelada.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancelar coleta')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await supabase.from('coletas').update({'status': status}).eq('id', c['id']);
      if (!mounted) return;
      showSuccess(context, 'Coleta nº ${c['numero']}: ${statusColeta[status]!.$1.toLowerCase()}.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Erro ao atualizar a coleta');
    }
  }

  Future<void> _gerarViagem(Map<String, dynamic> c) async {
    final v = veiculos[c['veiculo_id']?.toString()];
    if (v == null || c['motorista_id'] == null) {
      showError(context, 'Defina o veículo e o motorista da coleta antes de iniciar a viagem.');
      _abrirColeta(c);
      return;
    }
    final destino = (c['destino_cidade'] ?? '').toString().isEmpty ? '' : '${c['destino_cidade']}/${c['destino_uf'] ?? ''}';
    if (destino.isEmpty) {
      showError(context, 'Informe o destino da coleta antes de iniciar a viagem.');
      _abrirColeta(c);
      return;
    }
    final km = (v['odometer'] as num?)?.toDouble() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Iniciar viagem?'),
        content: Text('Veículo ${v['plate']} · ${motoristas[c['motorista_id'].toString()]?['name'] ?? ''}\n'
            '${c['cidade']}/${c['uf']} → $destino\nKM inicial: ${numeroBr(km, casas: 0)} (odômetro atual do veículo)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Iniciar viagem')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final injetar = context.read<AppAuthProvider>().inject;
    try {
      final viagem = await supabase
          .from('viagens')
          .insert(injetar({
            'veiculo_id': c['veiculo_id'],
            'motorista_id': c['motorista_id'],
            'data_inicio': DateTime.now().toIso8601String(),
            'origem': '${c['cidade']}/${c['uf']}',
            'destino': destino,
            'quilometragem_inicio': km,
            'status': 'em_progresso',
            'fotos_rota': [],
          }))
          .select('id')
          .single();
      await supabase.from('coletas').update({
        'viagem_id': viagem['id'],
        if (c['status'] != 'coletada') 'status': 'coletada',
      }).eq('id', c['id']);
      if (!mounted) return;
      showSuccess(context, 'Viagem iniciada. Acompanhe em Viagens.');
      _carregar();
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Erro ao iniciar a viagem');
    }
  }

  /// Cria (ou reaproveita) o rascunho de CT-e da coleta e abre a emissão já preenchida.
  /// Remetente = cliente da coleta; o destinatário é completado na tela do CT-e.
  Future<void> _gerarCte(Map<String, dynamic> c) async {
    final eid = c['empresa_id']?.toString();
    if (eid == null) return;
    final cli = Map<String, dynamic>.from((c['clientes'] as Map?) ?? {});
    final v = veiculos[c['veiculo_id']?.toString()];
    try {
      final existente = await supabase
          .from('cte_documentos')
          .select('*')
          .eq('coleta_id', c['id'])
          .eq('status', 'rascunho')
          .limit(1)
          .maybeSingle();
      Map<String, dynamic> rascunho;
      if (existente != null) {
        rascunho = Map<String, dynamic>.from(existente);
      } else {
        final cfg = await supabase.from('company_settings').select('ambiente_fiscal').eq('empresa_id', eid).maybeSingle();
        if (!mounted) return;
        final novo = await supabase
            .from('cte_documentos')
            .insert(context.read<AppAuthProvider>().inject({
              'empresa_id': eid,
              'coleta_id': c['id'],
              'viagem_id': c['viagem_id'],
              'veiculo_id': c['veiculo_id'],
              'motorista_id': c['motorista_id'],
              'ambiente': cfg?['ambiente_fiscal']?.toString() ?? 'homologacao',
              'status': 'rascunho',
              'remetente_nome': cli['nome'],
              'remetente_doc': cli['documento'],
              'natureza_carga': c['natureza_carga'],
              'valor_carga': c['valor_carga'],
              'valor_frete': c['valor_frete'],
              'peso_bruto': c['peso_kg'],
            }))
            .select('*')
            .single();
        rascunho = Map<String, dynamic>.from(novo);
      }
      if (!mounted) return;
      final emitido = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NovoCtePage(
            empresaId: eid,
            viagemId: c['viagem_id']?.toString(),
            cteDocumentoId: rascunho['id'].toString(),
            inicial: {
              ...rascunho,
              'remetente_logradouro': c['endereco_coleta'],
              'remetente_municipio': c['cidade'],
              'remetente_uf': c['uf'],
              'destinatario_municipio': c['destino_cidade'],
              'destinatario_uf': c['destino_uf'],
              'placa': v?['plate'],
            },
          ),
        ),
      );
      if (emitido == true && mounted) showSuccess(context, 'CT-e da coleta nº ${c['numero']} emitido.');
      if (emitido != true && mounted) {
        showSuccess(context, 'Rascunho do CT-e salvo. Continue depois em Documentos Fiscais.');
      }
    } catch (e) {
      if (mounted) showErrorFrom(context, e, prefix: 'Erro ao gerar o CT-e');
    }
  }

  Future<void> _whatsapp(String telefone, String texto) async {
    var n = soDigitos(telefone);
    if (n.length == 10 || n.length == 11) n = '55$n';
    final uri = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(texto)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showError(context, 'Não foi possível abrir o WhatsApp.');
    }
  }

  // ── Componentes ──────────────────────────────────────────────────────────
  Widget _cartao({required Widget child, VoidCallback? onTap}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _info(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: AppColors.muted),
        const SizedBox(width: 5),
        Flexible(child: Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
      ]);

  Widget _botao(String t, IconData i, Color c, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(i, size: 17, color: c),
        label: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.withValues(alpha: 0.5)),
          // o tema do app deixa botões com largura total; aqui eles ficam lado a lado
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _filtros(Map<String, String> opcoes, String atual, ValueChanged<String> onSel) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: opcoes.entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(e.value), selected: atual == e.key, onSelected: (_) => onSel(e.key)),
                  ))
              .toList(),
        ),
      );

  Widget _vazio(IconData i, String t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 54, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
      );

  String _formatarDoc(String d) {
    if (d.length == 14) {
      return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
    }
    if (d.length == 11) return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!auth.can(AppPermission.viewCommercial)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comercial e Coleta')),
        body: _vazio(Icons.lock_outline, 'Você não tem acesso ao módulo Comercial.'),
      );
    }
    final podeEditar = auth.can(AppPermission.manageCommercial);
    final rotulosNovo = ['Novo cliente', 'Nova cotação', 'Nova coleta'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Comercial e Coleta'),
        backgroundColor: AppColors.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Atualizar', onPressed: _carregar)],
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}),
          tabs: [
            Tab(text: 'Clientes (${clientes.length})'),
            Tab(text: 'Cotações (${cotacoes.where((c) => c['status'] == 'aberta').length})'),
            Tab(text: 'Coletas (${coletas.where((c) => c['status'] == 'programada' || c['status'] == 'em_rota').length})'),
          ],
        ),
      ),
      floatingActionButton: podeEditar && !carregando && erro == null
          ? AnimatedBuilder(
              animation: _tabs,
              builder: (_, _) => FloatingActionButton.extended(
                onPressed: () => [_abrirCliente, _abrirCotacao, _abrirColeta][_tabs.index](),
                icon: const Icon(Icons.add),
                label: Text(rotulosNovo[_tabs.index]),
              ),
            )
          : null,
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(erro!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                  ]),
                )
              : Column(children: [
                  _indicadores(),
                  Expanded(
                    child: TabBarView(controller: _tabs, children: [
                      _abaClientes(podeEditar),
                      _abaCotacoes(podeEditar),
                      _abaColetas(podeEditar),
                    ]),
                  ),
                ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Formulários
// ═════════════════════════════════════════════════════════════════════════

abstract class _FormBase<T extends StatefulWidget> extends State<T> {
  final supabase = Supabase.instance.client;
  final formKey = GlobalKey<FormState>();
  bool salvando = false;

  Widget campo(TextEditingController c, String label,
      {bool obrigatorio = false, TextInputType? teclado, int linhas = 1, String? Function(String)? validar, String? dica}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        maxLines: linhas,
        decoration: InputDecoration(labelText: obrigatorio ? '$label *' : label, hintText: dica),
        validator: (v) {
          final t = (v ?? '').trim();
          if (obrigatorio && t.isEmpty) return 'Obrigatório';
          return validar?.call(t);
        },
      ),
    );
  }

  Widget seletorUf(String? valor, ValueChanged<String?> onChanged, {String label = 'UF', bool obrigatorio = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: valor,
        isExpanded: true,
        decoration: InputDecoration(labelText: obrigatorio ? '$label *' : label),
        items: [for (final u in ufs) DropdownMenuItem(value: u, child: Text(u))],
        onChanged: onChanged,
        validator: (v) => obrigatorio && v == null ? 'Obrigatório' : null,
      ),
    );
  }

  String? validarValor(String t) {
    if (t.isEmpty) return null;
    final n = numeroDe(t);
    if (n == null || n < 0) return 'Valor inválido';
    if (n > 999999999) return 'Valor muito alto';
    return null;
  }

  Future<void> salvarCom(Future<void> Function() acao, String sucesso) async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => salvando = true);
    try {
      await acao();
      if (!mounted) return;
      showSuccess(context, sucesso);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('clientes_empresa_documento_uq')) {
        showError(context, 'Já existe um cliente com este CNPJ/CPF.');
      } else {
        showErrorFrom(context, e, prefix: 'Não foi possível salvar');
      }
      setState(() => salvando = false);
    }
  }

  Widget botaoSalvar(String texto, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton.icon(
          onPressed: salvando ? null : onPressed,
          icon: salvando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );

  Widget secao(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(t, style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget layout(String titulo, List<Widget> filhos) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text(titulo), backgroundColor: AppColors.surface),
        body: Form(
          key: formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(20), children: filhos),
            ),
          ),
        ),
      );
}

// ── Cliente ─────────────────────────────────────────────────────────────────
class ClienteFormPage extends StatefulWidget {
  const ClienteFormPage({super.key, this.cliente});
  final Map<String, dynamic>? cliente;

  @override
  State<ClienteFormPage> createState() => _ClienteFormPageState();
}

class _ClienteFormPageState extends _FormBase<ClienteFormPage> {
  late final c = widget.cliente ?? {};
  late String tipo = c['tipo']?.toString() ?? 'PJ';
  late String? uf = c['uf']?.toString();
  late bool ativo = c['ativo'] != false;
  late final nome = TextEditingController(text: c['nome']?.toString() ?? '');
  late final documento = TextEditingController(text: c['documento']?.toString() ?? '');
  late final ie = TextEditingController(text: c['ie']?.toString() ?? '');
  late final contato = TextEditingController(text: c['contato']?.toString() ?? '');
  late final telefone = TextEditingController(text: c['telefone']?.toString() ?? '');
  late final email = TextEditingController(text: c['email']?.toString() ?? '');
  late final endereco = TextEditingController(text: c['endereco']?.toString() ?? '');
  late final cidade = TextEditingController(text: c['cidade']?.toString() ?? '');
  late final obs = TextEditingController(text: c['observacoes']?.toString() ?? '');

  String? _validarDoc(String t) {
    if (t.isEmpty) return null;
    final d = soDigitos(t);
    if (tipo == 'PJ' && d.length != 14) return 'CNPJ deve ter 14 números';
    if (tipo == 'PF' && d.length != 11) return 'CPF deve ter 11 números';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.cliente != null;
    return layout(editando ? 'Editar cliente' : 'Novo cliente', [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'PJ', label: Text('Empresa (CNPJ)'), icon: Icon(Icons.business)),
          ButtonSegment(value: 'PF', label: Text('Pessoa (CPF)'), icon: Icon(Icons.person)),
        ],
        selected: {tipo},
        onSelectionChanged: (s) => setState(() => tipo = s.first),
      ),
      const SizedBox(height: 16),
      campo(nome, tipo == 'PJ' ? 'Razão social / nome' : 'Nome completo', obrigatorio: true,
          validar: (t) => t.length < 2 ? 'Nome muito curto' : null),
      campo(documento, tipo == 'PJ' ? 'CNPJ' : 'CPF', teclado: TextInputType.number, validar: _validarDoc),
      if (tipo == 'PJ') campo(ie, 'Inscrição estadual'),
      secao('Contato'),
      campo(contato, 'Pessoa de contato'),
      campo(telefone, 'Telefone / WhatsApp', teclado: TextInputType.phone, dica: '(35) 99999-9999',
          validar: (t) => t.isEmpty || soDigitos(t).length >= 10 ? null : 'Telefone com DDD'),
      campo(email, 'E-mail', teclado: TextInputType.emailAddress,
          validar: (t) => t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'E-mail inválido'),
      secao('Endereço'),
      campo(endereco, 'Endereço'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: campo(cidade, 'Cidade')),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: seletorUf(uf, (v) => setState(() => uf = v), obrigatorio: false)),
      ]),
      campo(obs, 'Observações', linhas: 3),
      if (editando)
        SwitchListTile(
          value: ativo,
          onChanged: (v) => setState(() => ativo = v),
          title: const Text('Cliente ativo'),
          subtitle: const Text('Clientes inativos não aparecem em novas cotações e coletas.'),
        ),
      const SizedBox(height: 10),
      botaoSalvar(editando ? 'Salvar alterações' : 'Cadastrar cliente', () {
        final dados = {
          'tipo': tipo,
          'nome': nome.text.trim(),
          'documento': documento.text.trim().isEmpty ? null : soDigitos(documento.text),
          'ie': tipo == 'PJ' ? ie.text.trim() : null,
          'contato': contato.text.trim(),
          'telefone': telefone.text.trim(),
          'email': email.text.trim(),
          'endereco': endereco.text.trim(),
          'cidade': cidade.text.trim(),
          'uf': uf,
          'observacoes': obs.text.trim(),
          'ativo': ativo,
        };
        salvarCom(() async {
          if (editando) {
            await supabase.from('clientes').update(dados).eq('id', widget.cliente!['id']);
          } else {
            await supabase.from('clientes').insert(context.read<AppAuthProvider>().inject(dados));
          }
        }, editando ? 'Cliente atualizado.' : 'Cliente cadastrado.');
      }),
    ]);
  }
}

// ── Cotação ─────────────────────────────────────────────────────────────────
class CotacaoFormPage extends StatefulWidget {
  const CotacaoFormPage({super.key, this.cotacao, required this.clientes});
  final Map<String, dynamic>? cotacao;
  final List<Map<String, dynamic>> clientes;

  @override
  State<CotacaoFormPage> createState() => _CotacaoFormPageState();
}

class _CotacaoFormPageState extends _FormBase<CotacaoFormPage> {
  late final q = widget.cotacao ?? {};
  late String? clienteId = q['cliente_id']?.toString();
  late String? origemUf = q['origem_uf']?.toString();
  late String? destinoUf = q['destino_uf']?.toString();
  late DateTime? validade = q['validade'] != null
      ? DateTime.tryParse(q['validade'].toString())
      : DateTime.now().add(const Duration(days: 7));
  late final origem = TextEditingController(text: q['origem_cidade']?.toString() ?? '');
  late final destino = TextEditingController(text: q['destino_cidade']?.toString() ?? '');
  late final natureza = TextEditingController(text: q['natureza_carga']?.toString() ?? '');
  late final peso = TextEditingController(text: q['peso_kg'] != null ? numeroBr(q['peso_kg'] as num, casas: 0) : '');
  late final valorCarga = TextEditingController(text: q['valor_carga'] != null ? numeroBr(q['valor_carga'] as num) : '');
  late final frete = TextEditingController(text: q['valor_frete'] != null ? numeroBr(q['valor_frete'] as num) : '');
  late final obs = TextEditingController(text: q['observacoes']?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final editando = widget.cotacao != null;
    final opcoes = widget.clientes.where((c) => c['ativo'] != false || c['id'].toString() == clienteId).toList();
    return layout(editando ? 'Editar cotação nº ${q['numero']}' : 'Nova cotação', [
      DropdownButtonFormField<String>(
        initialValue: clienteId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Cliente *'),
        items: [for (final c in opcoes) DropdownMenuItem(value: c['id'].toString(), child: Text(c['nome'].toString(), overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => clienteId = v),
        validator: (v) => v == null ? 'Escolha o cliente' : null,
      ),
      const SizedBox(height: 14),
      secao('Rota'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: campo(origem, 'Cidade de origem', obrigatorio: true)),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: seletorUf(origemUf, (v) => setState(() => origemUf = v))),
      ]),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: campo(destino, 'Cidade de destino', obrigatorio: true)),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: seletorUf(destinoUf, (v) => setState(() => destinoUf = v))),
      ]),
      secao('Carga'),
      campo(natureza, 'Natureza da carga', dica: 'Ex.: grãos, móveis, peças'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: campo(peso, 'Peso (kg)', teclado: const TextInputType.numberWithOptions(decimal: true), validar: validarValor)),
        const SizedBox(width: 12),
        Expanded(child: campo(valorCarga, 'Valor da carga (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true), validar: validarValor)),
      ]),
      secao('Proposta'),
      campo(frete, 'Valor do frete (R\$)', obrigatorio: true, teclado: const TextInputType.numberWithOptions(decimal: true),
          validar: validarValor),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event, color: AppColors.secondary),
        title: Text(validade == null ? 'Sem data de validade' : 'Válida até ${dataBr(isoData(validade!))}'),
        trailing: TextButton(
          child: const Text('Alterar'),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: validade ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null) setState(() => validade = d);
          },
        ),
      ),
      campo(obs, 'Observações', linhas: 3, dica: 'Condições, prazo de entrega, forma de pagamento...'),
      const SizedBox(height: 10),
      botaoSalvar(editando ? 'Salvar alterações' : 'Criar cotação', () {
        final dados = {
          'cliente_id': clienteId,
          'origem_cidade': origem.text.trim(),
          'origem_uf': origemUf,
          'destino_cidade': destino.text.trim(),
          'destino_uf': destinoUf,
          'natureza_carga': natureza.text.trim(),
          'peso_kg': numeroDe(peso.text),
          'valor_carga': numeroDe(valorCarga.text),
          'valor_frete': numeroDe(frete.text),
          'validade': validade == null ? null : isoData(validade!),
          'observacoes': obs.text.trim(),
        };
        salvarCom(() async {
          if (editando) {
            await supabase.from('cotacoes').update(dados).eq('id', widget.cotacao!['id']);
          } else {
            await supabase.from('cotacoes').insert(context.read<AppAuthProvider>().inject(dados));
          }
        }, editando ? 'Cotação atualizada.' : 'Cotação criada.');
      }),
    ]);
  }
}

// ── Coleta ──────────────────────────────────────────────────────────────────
class ColetaFormPage extends StatefulWidget {
  const ColetaFormPage({
    super.key,
    this.coleta,
    this.cotacao,
    required this.clientes,
    required this.veiculos,
    required this.motoristas,
  });

  final Map<String, dynamic>? coleta;
  final Map<String, dynamic>? cotacao; // ao aprovar uma cotação, pré-preenche a coleta
  final List<Map<String, dynamic>> clientes;
  final List<Map<String, dynamic>> veiculos;
  final List<Map<String, dynamic>> motoristas;

  @override
  State<ColetaFormPage> createState() => _ColetaFormPageState();
}

class _ColetaFormPageState extends _FormBase<ColetaFormPage> {
  late final Map<String, dynamic> c = widget.coleta ?? {};
  late final Map<String, dynamic> q = widget.cotacao ?? {};
  late final Map<String, dynamic> clienteDaCotacao =
      widget.clientes.firstWhere((x) => x['id'].toString() == q['cliente_id']?.toString(), orElse: () => {});

  late String? clienteId = (c['cliente_id'] ?? q['cliente_id'])?.toString();
  late String? uf = (c['uf'] ?? q['origem_uf'])?.toString();
  late String? destinoUf = (c['destino_uf'] ?? q['destino_uf'])?.toString();
  late String? veiculoId = c['veiculo_id']?.toString();
  late String? motoristaId = c['motorista_id']?.toString();
  late DateTime data = DateTime.tryParse(c['data_programada']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 1));
  late TimeOfDay? horaIni = _hora(c['hora_inicio']);
  late TimeOfDay? horaFim = _hora(c['hora_fim']);

  late final endereco = TextEditingController(text: c['endereco_coleta']?.toString() ?? clienteDaCotacao['endereco']?.toString() ?? '');
  late final cidade = TextEditingController(text: (c['cidade'] ?? q['origem_cidade'])?.toString() ?? '');
  late final destino = TextEditingController(text: (c['destino_cidade'] ?? q['destino_cidade'])?.toString() ?? '');
  late final contato = TextEditingController(text: c['contato']?.toString() ?? clienteDaCotacao['contato']?.toString() ?? '');
  late final telefone = TextEditingController(text: c['telefone']?.toString() ?? clienteDaCotacao['telefone']?.toString() ?? '');
  late final natureza = TextEditingController(text: (c['natureza_carga'] ?? q['natureza_carga'])?.toString() ?? '');
  late final peso = TextEditingController(text: _num(c['peso_kg'] ?? q['peso_kg'], 0));
  late final volumes = TextEditingController(text: c['volumes']?.toString() ?? '');
  late final valorCarga = TextEditingController(text: _num(c['valor_carga'] ?? q['valor_carga'], 2));
  late final frete = TextEditingController(text: _num(c['valor_frete'] ?? q['valor_frete'], 2));
  late final obs = TextEditingController(text: c['observacoes']?.toString() ?? '');

  static String _num(dynamic v, int casas) => v is num ? numeroBr(v, casas: casas) : '';

  static TimeOfDay? _hora(dynamic h) {
    final s = h?.toString() ?? '';
    if (s.length < 5) return null;
    return TimeOfDay(hour: int.tryParse(s.substring(0, 2)) ?? 0, minute: int.tryParse(s.substring(3, 5)) ?? 0);
  }

  static String? _horaSql(TimeOfDay? t) =>
      t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Widget _seletorHora(String label, TimeOfDay? valor, ValueChanged<TimeOfDay?> onSel) => Expanded(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(valor == null ? label : '$label ${valor.format(context)}'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: valor ?? const TimeOfDay(hour: 8, minute: 0));
            onSel(t ?? valor);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editando = widget.coleta != null;
    final daCotacao = widget.cotacao != null;
    final opcoes = widget.clientes.where((x) => x['ativo'] != false || x['id'].toString() == clienteId).toList();

    return layout(
      editando ? 'Editar coleta nº ${c['numero']}' : daCotacao ? 'Aprovar cotação nº ${q['numero']}' : 'Nova coleta',
      [
        if (daCotacao)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Ao salvar, a cotação nº ${q['numero']} fica APROVADA e esta coleta é programada. '
              'Confira o endereço e a data da coleta.',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: clienteId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Cliente *'),
          items: [for (final x in opcoes) DropdownMenuItem(value: x['id'].toString(), child: Text(x['nome'].toString(), overflow: TextOverflow.ellipsis))],
          onChanged: daCotacao ? null : (v) => setState(() => clienteId = v),
          validator: (v) => v == null ? 'Escolha o cliente' : null,
        ),
        const SizedBox(height: 14),
        secao('Quando'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, color: AppColors.secondary),
          title: Text('Data da coleta: ${dataBr(isoData(data))}'),
          trailing: TextButton(
            child: const Text('Alterar'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: data,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => data = d);
            },
          ),
        ),
        Row(children: [
          _seletorHora('Das', horaIni, (t) => setState(() => horaIni = t)),
          const SizedBox(width: 10),
          _seletorHora('Até', horaFim, (t) => setState(() => horaFim = t)),
        ]),
        const SizedBox(height: 16),
        secao('Onde coletar'),
        campo(endereco, 'Endereço da coleta', obrigatorio: true),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: campo(cidade, 'Cidade', obrigatorio: true)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: seletorUf(uf, (v) => setState(() => uf = v))),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: campo(destino, 'Cidade de destino')),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: seletorUf(destinoUf, (v) => setState(() => destinoUf = v), label: 'UF destino', obrigatorio: false)),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: campo(contato, 'Contato no local')),
          const SizedBox(width: 12),
          Expanded(child: campo(telefone, 'Telefone', teclado: TextInputType.phone)),
        ]),
        secao('Carga'),
        campo(natureza, 'Natureza da carga'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: campo(peso, 'Peso (kg)', teclado: const TextInputType.numberWithOptions(decimal: true), validar: validarValor)),
          const SizedBox(width: 12),
          Expanded(child: campo(volumes, 'Volumes', teclado: TextInputType.number,
              validar: (t) => t.isEmpty || (int.tryParse(t) ?? -1) >= 0 ? null : 'Número inteiro')),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: campo(valorCarga, 'Valor da carga (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true), validar: validarValor)),
          const SizedBox(width: 12),
          Expanded(child: campo(frete, 'Valor do frete (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true), validar: validarValor)),
        ]),
        secao('Veículo e motorista'),
        DropdownButtonFormField<String?>(
          initialValue: veiculoId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Veículo'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Definir depois')),
            for (final v in widget.veiculos)
              DropdownMenuItem<String?>(value: v['id'].toString(), child: Text('${v['plate']} · ${v['brand'] ?? ''} ${v['model'] ?? ''}')),
          ],
          onChanged: (v) => setState(() => veiculoId = v),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String?>(
          initialValue: motoristaId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Motorista'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Definir depois')),
            for (final m in widget.motoristas) DropdownMenuItem<String?>(value: m['id'].toString(), child: Text(m['name'].toString())),
          ],
          onChanged: (v) => setState(() => motoristaId = v),
        ),
        const SizedBox(height: 14),
        campo(obs, 'Observações', linhas: 3),
        const SizedBox(height: 10),
        botaoSalvar(
          editando ? 'Salvar alterações' : daCotacao ? 'Aprovar e programar coleta' : 'Programar coleta',
          () {
            if (horaIni != null && horaFim != null && (horaFim!.hour * 60 + horaFim!.minute) < (horaIni!.hour * 60 + horaIni!.minute)) {
              showError(context, 'O horário final deve ser depois do inicial.');
              return;
            }
            final dados = {
              'cliente_id': clienteId,
              'endereco_coleta': endereco.text.trim(),
              'cidade': cidade.text.trim(),
              'uf': uf,
              'destino_cidade': destino.text.trim(),
              'destino_uf': destinoUf,
              'data_programada': isoData(data),
              'hora_inicio': _horaSql(horaIni),
              'hora_fim': _horaSql(horaFim),
              'contato': contato.text.trim(),
              'telefone': telefone.text.trim(),
              'natureza_carga': natureza.text.trim(),
              'peso_kg': numeroDe(peso.text),
              'volumes': int.tryParse(volumes.text.trim()),
              'valor_carga': numeroDe(valorCarga.text),
              'valor_frete': numeroDe(frete.text),
              'veiculo_id': veiculoId,
              'motorista_id': motoristaId,
              'observacoes': obs.text.trim(),
            };
            salvarCom(() async {
              if (editando) {
                await supabase.from('coletas').update(dados).eq('id', widget.coleta!['id']);
                return;
              }
              final nova = await supabase
                  .from('coletas')
                  .insert(context.read<AppAuthProvider>().inject({...dados, if (daCotacao) 'cotacao_id': q['id']}))
                  .select('id')
                  .single();
              if (daCotacao) {
                await supabase.from('cotacoes').update({'status': 'aprovada', 'coleta_id': nova['id']}).eq('id', q['id']);
              }
            }, editando ? 'Coleta atualizada.' : daCotacao ? 'Cotação aprovada e coleta programada.' : 'Coleta programada.');
          },
        ),
      ],
    );
  }
}

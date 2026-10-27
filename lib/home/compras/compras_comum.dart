import 'dart:math' as math;

import '../../core/theme/app_theme.dart';
import '../../core/utils/formato_br.dart';
import '../estoque/estoque_page.dart' show qtdBr;
import '../manutencoes/manutencao_comum.dart' show dataBrManut;

/// Peças comuns do módulo Compras (pedido de compra, aprovação e recebimento).

const statusCompra = {
  'rascunho': ('Rascunho', AppColors.muted),
  'aguardando': ('Aguardando aprovação', AppColors.warning),
  'aprovado': ('Aprovado', AppColors.info),
  'reprovado': ('Reprovado', AppColors.danger),
  'parcial': ('Recebido em parte', AppColors.secondary),
  'recebido': ('Recebido', AppColors.success),
  'cancelado': ('Cancelado', AppColors.muted),
};

/// Categorias que fazem sentido numa compra (mesmas chaves do contas a pagar).
const categoriasCompra = ['pecas', 'pneus', 'combustivel', 'manutencao', 'administrativo', 'outros'];

/// Quanto pedir de um material abaixo do mínimo: o bastante para o estoque
/// chegar ao dobro do mínimo, arredondado para cima (pelo menos 1).
double quantidadeSugerida(num atual, num minimo) {
  final falta = (minimo * 2 - atual).toDouble();
  return math.max(1, falta.ceilToDouble());
}

/// "27/10/2026 14:05" no horário local (os carimbos do banco vêm em UTC).
String dataHoraBr(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '-';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
}

/// Quanto ainda falta receber de um item do pedido.
double pendenteItem(Map<String, dynamic> item) {
  final q = ((item['quantidade'] as num?) ?? 0).toDouble();
  final r = ((item['quantidade_recebida'] as num?) ?? 0).toDouble();
  return math.max(0, q - r);
}

/// Texto do pedido para o fornecedor (WhatsApp).
String textoPedidoFornecedor({
  required Map<String, dynamic> pedido,
  required List<Map<String, dynamic>> itens,
  String? empresa,
  String? contato,
}) {
  final b = StringBuffer();
  b.writeln('Olá${(contato ?? '').trim().isEmpty ? '' : ', ${contato!.trim()}'}!');
  b.writeln('Segue o pedido de compra nº ${pedido['numero']}${(empresa ?? '').trim().isEmpty ? '' : ' da ${empresa!.trim()}'}:');
  b.writeln();
  for (final i in itens) {
    b.writeln('• ${qtdBr(i['quantidade'] as num?)} ${i['unidade'] ?? 'un'} — ${i['descricao']} (${moedaBr((i['valor_unitario'] as num?) ?? 0)} cada)');
  }
  b.writeln();
  b.writeln('Total: ${moedaBr((pedido['valor_total'] as num?) ?? 0)}');
  final parcelas = (pedido['parcelas'] as num?)?.toInt() ?? 1;
  final prazo = (pedido['prazo_dias'] as num?)?.toInt() ?? 30;
  b.writeln('Pagamento: ${parcelas > 1 ? '${parcelas}x, ' : ''}${prazo == 0 ? 'à vista' : '1º vencimento em $prazo dias'}');
  if (pedido['previsao_entrega'] != null) b.writeln('Entrega até: ${dataBrManut(pedido['previsao_entrega'].toString())}');
  b.writeln();
  b.write('Por favor, confirme o recebimento do pedido. Obrigado!');
  return b.toString();
}

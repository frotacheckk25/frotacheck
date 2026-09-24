/// Busca TODAS as linhas de uma consulta, página por página.
///
/// O Supabase (PostgREST) devolve no máximo 1000 linhas por requisição e
/// corta o resto sem avisar — dashboards, relatórios e listas ficavam com
/// totais errados em frotas maiores. Uso:
///
/// ```dart
/// final rows = await fetchAllRows(
///   (from, to) => supabase.from('fuelings').select('id, total_value')
///       .eq('empresa_id', eid).order('id').range(from, to),
/// );
/// ```
///
/// Sempre inclua um `.order(...)` estável (ex.: 'id') antes do `.range`,
/// senão a paginação pode repetir/pular linhas.
Future<List<Map<String, dynamic>>> fetchAllRows(
  Future<List<dynamic>> Function(int from, int to) fetchPage, {
  int pageSize = 1000,
  int maxRows = 100000,
}) async {
  final all = <Map<String, dynamic>>[];
  var from = 0;
  while (from < maxRows) {
    final page = await fetchPage(from, from + pageSize - 1);
    all.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return all;
}

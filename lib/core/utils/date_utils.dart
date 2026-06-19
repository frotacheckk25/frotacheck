class DateUtils {
  /// Tenta parsear várias representações de data retornando null se falhar.
  static DateTime? parseDate(String rawDate) {
    if (rawDate.isEmpty) return null;

    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) return parsed;

    final cleaned = rawDate.replaceAll('/', '-').replaceAll('.', '-');
    final parts = cleaned.split('-').map((part) => part.trim()).toList();
    if (parts.length != 3) return null;

    try {
      if (parts[0].length == 4) {
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }
}

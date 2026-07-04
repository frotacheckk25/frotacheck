import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte uma URL pública de Storage (`.../storage/v1/object/public/<bucket>/<path>`)
/// em uma URL assinada temporária, para uso depois que os buckets do
/// FrotaCheck deixarem de ser de leitura pública. Se a URL não for do padrão
/// esperado (ou já for outra coisa, ex. null/vazia), devolve o valor original.
///
/// Chame isso logo após buscar os dados do Supabase, antes de guardar no
/// estado da tela — os widgets que exibem a imagem (Image.network) não
/// precisam saber que a URL agora é assinada.
Future<String?> toSignedStorageUrl(String? storedUrl, {int expiresInSeconds = 86400}) async {
  if (storedUrl == null || storedUrl.isEmpty) return storedUrl;
  final marker = '/storage/v1/object/public/';
  final idx = storedUrl.indexOf(marker);
  if (idx == -1) return storedUrl;

  final afterMarker = storedUrl.substring(idx + marker.length);
  final slashIdx = afterMarker.indexOf('/');
  if (slashIdx == -1) return storedUrl;

  final bucket = afterMarker.substring(0, slashIdx);
  final path = afterMarker.substring(slashIdx + 1);
  if (bucket.isEmpty || path.isEmpty) return storedUrl;

  try {
    return await Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(path, expiresInSeconds);
  } catch (_) {
    return storedUrl;
  }
}

/// Mesma conversão, mas para uma lista de URLs em paralelo.
Future<List<String>> toSignedStorageUrls(List<String?> storedUrls, {int expiresInSeconds = 86400}) async {
  final resolved = await Future.wait(
    storedUrls.map((u) => toSignedStorageUrl(u, expiresInSeconds: expiresInSeconds)),
  );
  return resolved.whereType<String>().toList();
}

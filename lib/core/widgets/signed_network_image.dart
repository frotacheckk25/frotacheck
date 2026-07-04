import 'package:flutter/material.dart';
import '../utils/signed_storage_url.dart';

/// Substituto de Image.network para fotos guardadas no Storage do Supabase.
/// Resolve a URL pública salva no banco em uma URL assinada temporária antes
/// de carregar a imagem — necessário porque os buckets de Storage deixaram de
/// ter leitura pública (só usuários autenticados podem baixar arquivos).
class SignedNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  const SignedNetworkImage({
    super.key,
    required this.url,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return errorBuilder?.call(context, 'URL vazia', null) ?? const SizedBox.shrink();
    }
    return FutureBuilder<String?>(
      future: toSignedStorageUrl(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final resolved = snapshot.data;
        if (resolved == null || resolved.isEmpty) {
          return errorBuilder?.call(context, 'Falha ao gerar URL assinada', null) ?? const SizedBox.shrink();
        }
        return Image.network(
          resolved,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        );
      },
    );
  }
}

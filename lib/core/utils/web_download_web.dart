import 'dart:js_interop';
import 'dart:typed_data';

// window.__fcDownloadDataUrl é definido em web/index.html — um download
// direto via <a download> não depende do Web Share API (que share_plus usa
// e que boa parte dos navegadores desktop não suporta de forma confiável).
@JS('window.__fcDownloadDataUrl')
external void _downloadDataUrl(String dataUrl, String filename);

void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final dataUrl = Uri.dataFromBytes(bytes, mimeType: mimeType).toString();
  _downloadDataUrl(dataUrl, filename);
}

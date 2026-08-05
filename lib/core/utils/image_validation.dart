import 'dart:typed_data';

/// Confere os magic bytes reais do arquivo (não a extensão do nome, que é
/// facilmente forjável) contra as assinaturas conhecidas de JPEG/PNG/WebP.
/// Usado como última barreira no client antes do upload — o servidor
/// (allowed_mime_types do bucket) só valida o Content-Type declarado, então
/// isso é o que realmente impede um arquivo disfarçado (ex.: um .html ou
/// binário renomeado para .jpg) de ser aceito como foto.
bool isValidImageBytes(Uint8List bytes) {
  if (bytes.length < 12) return false;

  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return true;
  }

  // WebP: "RIFF" .... "WEBP"
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }

  return false;
}

/// Mesma ideia de [isValidImageBytes], mas para os tipos aceitos em
/// documentos_page.dart (pdf/jpg/jpeg/png/doc/docx). Usa [ext] (a extensão
/// que o próprio usuário escolheu no FilePicker) pra saber qual assinatura
/// conferir — arquivo com extensão trocada de propósito (ex.: um .exe
/// renomeado pra .pdf) não bate com a assinatura esperada e é rejeitado.
bool isValidDocumentBytes(String ext, Uint8List bytes) {
  final e = ext.toLowerCase();
  if (e == 'jpg' || e == 'jpeg' || e == 'png') return isValidImageBytes(bytes);

  if (e == 'pdf') {
    // "%PDF-"
    return bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  if (e == 'doc') {
    // OLE Compound File Binary Format: D0 CF 11 E0 A1 B1 1A E1
    return bytes.length >= 8 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0 &&
        bytes[4] == 0xA1 &&
        bytes[5] == 0xB1 &&
        bytes[6] == 0x1A &&
        bytes[7] == 0xE1;
  }

  if (e == 'docx') {
    // .docx é um .zip (OOXML): assinatura "PK"
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  return false;
}

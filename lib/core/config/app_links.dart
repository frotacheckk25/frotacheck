/// URL oficial de produção do PWA — usada em QR Codes, links de
/// compartilhamento e mensagens prontas em toda a "Distribuição do App".
const String kFrotaCheckPwaUrl = 'https://frotacheckoficial.vercel.app';

/// Endereço com que o app foi aberto, guardado antes do Supabase iniciar
/// (ele limpa o "#..." do endereço ao processar links de login/recuperação).
/// A tela de login usa para avisar quando o link de troca de senha venceu.
Uri? uriDeAbertura;

String frotaCheckShareMessage(String? empresaNome) {
  final nome = (empresaNome ?? '').trim();
  final destino = nome.isEmpty ? 'sua equipe' : nome;
  return 'Olá! A $destino usa o FrotaCheck para gerenciar a frota. '
      'Acesse pelo link abaixo, faça login e toque em "Instalar" para '
      'ter o app direto na tela inicial do celular — sem precisar de loja de aplicativos:\n\n'
      '$kFrotaCheckPwaUrl';
}

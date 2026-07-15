/// URL oficial de produção do PWA — usada em QR Codes, links de
/// compartilhamento e mensagens prontas em toda a "Distribuição do App".
const String kFrotaCheckPwaUrl = 'https://frotacheckoficial.vercel.app';

String frotaCheckShareMessage(String? empresaNome) {
  final nome = (empresaNome ?? '').trim();
  final destino = nome.isEmpty ? 'sua equipe' : nome;
  return 'Olá! A $destino usa o FrotaCheck para gerenciar a frota. '
      'Acesse pelo link abaixo, faça login e toque em "Instalar" para '
      'ter o app direto na tela inicial do celular — sem precisar de loja de aplicativos:\n\n'
      '$kFrotaCheckPwaUrl';
}

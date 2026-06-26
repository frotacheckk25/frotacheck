class Checklist {
  final String id;
  final String veiculoId;
  final String motoristaId;
  final String tipo; // 'saida' ou 'retorno'
  final DateTime data;
  final Map<String, bool> itens; // nome -> aprovado
  final List<String> fotoUrls;
  final String assinaturaUrl;
  final bool aprovado;
  final String? observacoes;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  Checklist({
    required this.id,
    required this.veiculoId,
    required this.motoristaId,
    required this.tipo,
    required this.data,
    required this.itens,
    required this.fotoUrls,
    required this.assinaturaUrl,
    required this.aprovado,
    this.observacoes,
    this.criadoEm,
    this.atualizadoEm,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    return Checklist(
      id: json['id'] as String,
      veiculoId: json['veiculo_id'] as String,
      motoristaId: json['motorista_id'] as String,
      tipo: json['tipo'] as String,
      data: DateTime.parse(json['data'] as String),
      itens: Map<String, bool>.from(json['itens'] as Map),
      fotoUrls: List<String>.from(json['foto_urls'] as List),
      assinaturaUrl: json['assinatura_url'] as String,
      aprovado: json['aprovado'] as bool,
      observacoes: json['observacoes'] as String?,
      criadoEm: json['criado_em'] != null
          ? DateTime.parse(json['criado_em'] as String)
          : null,
      atualizadoEm: json['atualizado_em'] != null
          ? DateTime.parse(json['atualizado_em'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'veiculo_id': veiculoId,
    'motorista_id': motoristaId,
    'tipo': tipo,
    'data': data.toIso8601String(),
    'itens': itens,
    'foto_urls': fotoUrls,
    'assinatura_url': assinaturaUrl,
    'aprovado': aprovado,
    'observacoes': observacoes,
    'criado_em': criadoEm?.toIso8601String(),
    'atualizado_em': atualizadoEm?.toIso8601String(),
  };

  static final List<String> itensChecklist = [
    'Pneus',
    'Luzes',
    'Setas',
    'Freios',
    'Retrovisores',
    'Extintor',
    'Macaco',
    'Chave de roda',
    'Triângulo',
    'Documentação',
  ];

  static final List<String> fotosObrigatorias = [
    'Frente',
    'Traseira',
    'Lateral Esquerda',
    'Lateral Direita',
    'Painel Interno',
  ];
}

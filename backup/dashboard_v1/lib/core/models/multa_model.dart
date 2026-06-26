class Multa {
  final String id;
  final String veiculoId;
  final String? motoristaId;
  final DateTime data;
  final double valor;
  final String tipo; // 'infraçao' ou 'juizado'
  final String descricao;
  final String? fotoUrl;
  final String status; // 'aberta', 'paga', 'contestada'
  final DateTime? dataPagamento;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  Multa({
    required this.id,
    required this.veiculoId,
    this.motoristaId,
    required this.data,
    required this.valor,
    required this.tipo,
    required this.descricao,
    this.fotoUrl,
    required this.status,
    this.dataPagamento,
    this.criadoEm,
    this.atualizadoEm,
  });

  factory Multa.fromJson(Map<String, dynamic> json) {
    return Multa(
      id: json['id'] as String,
      veiculoId: json['veiculo_id'] as String,
      motoristaId: json['motorista_id'] as String?,
      data: DateTime.parse(json['data'] as String),
      valor: (json['valor'] as num).toDouble(),
      tipo: json['tipo'] as String,
      descricao: json['descricao'] as String,
      fotoUrl: json['foto_url'] as String?,
      status: json['status'] as String,
      dataPagamento: json['data_pagamento'] != null
          ? DateTime.parse(json['data_pagamento'] as String)
          : null,
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
    'data': data.toIso8601String(),
    'valor': valor,
    'tipo': tipo,
    'descricao': descricao,
    'foto_url': fotoUrl,
    'status': status,
    'data_pagamento': dataPagamento?.toIso8601String(),
    'criado_em': criadoEm?.toIso8601String(),
    'atualizado_em': atualizadoEm?.toIso8601String(),
  };
}

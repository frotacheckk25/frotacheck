class Documento {
  final String id;
  final String? veiculoId;
  final String? motoristaId;
  final String
  tipo; // 'CRLV', 'Licenciamento', 'Seguro', 'CNH_Frente', 'CNH_Verso', 'Certificado'
  final String descricao;
  final String fileUrl;
  final DateTime dataVencimento;
  final DateTime dataPagamento;
  final bool ativo;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  Documento({
    required this.id,
    this.veiculoId,
    this.motoristaId,
    required this.tipo,
    required this.descricao,
    required this.fileUrl,
    required this.dataVencimento,
    required this.dataPagamento,
    required this.ativo,
    this.criadoEm,
    this.atualizadoEm,
  });

  bool get vencidoEm30Dias {
    final agora = DateTime.now();
    final diferenca = dataVencimento.difference(agora).inDays;
    return diferenca <= 30 && diferenca >= 0;
  }

  bool get vencido {
    return DateTime.now().isAfter(dataVencimento);
  }

  factory Documento.fromJson(Map<String, dynamic> json) {
    return Documento(
      id: json['id'] as String,
      veiculoId: json['veiculo_id'] as String?,
      motoristaId: json['motorista_id'] as String?,
      tipo: json['tipo'] as String,
      descricao: json['descricao'] as String,
      fileUrl: json['file_url'] as String,
      dataVencimento: DateTime.parse(json['data_vencimento'] as String),
      dataPagamento: DateTime.parse(json['data_pagamento'] as String),
      ativo: json['ativo'] as bool,
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
    'descricao': descricao,
    'file_url': fileUrl,
    'data_vencimento': dataVencimento.toIso8601String(),
    'data_pagamento': dataPagamento.toIso8601String(),
    'ativo': ativo,
    'criado_em': criadoEm?.toIso8601String(),
    'atualizado_em': atualizadoEm?.toIso8601String(),
  };
}

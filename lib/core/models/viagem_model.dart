class Viagem {
  final String id;
  final String veiculoId;
  final String motoristaId;
  final DateTime dataInicio;
  final DateTime? dataFim;
  final String origem;
  final String destino;
  final double quilometragemInicio;
  final double? quilometragemFim;
  final String status; // 'em_progresso', 'concluida', 'cancelada'
  final List<String> fotosRota;
  final double? consumoLitros;
  final double? custoTotal;
  final String? observacoes;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  Viagem({
    required this.id,
    required this.veiculoId,
    required this.motoristaId,
    required this.dataInicio,
    this.dataFim,
    required this.origem,
    required this.destino,
    required this.quilometragemInicio,
    this.quilometragemFim,
    required this.status,
    required this.fotosRota,
    this.consumoLitros,
    this.custoTotal,
    this.observacoes,
    this.criadoEm,
    this.atualizadoEm,
  });

  double? get quilometragemPercorrida {
    if (quilometragemFim != null) {
      return quilometragemFim! - quilometragemInicio;
    }
    return null;
  }

  factory Viagem.fromJson(Map<String, dynamic> json) {
    return Viagem(
      id: json['id']?.toString() ?? '',
      veiculoId: json['veiculo_id']?.toString() ?? '',
      motoristaId: json['motorista_id']?.toString() ?? '',
      dataInicio: DateTime.parse(json['data_inicio']?.toString() ?? DateTime.now().toIso8601String()),
      dataFim: json['data_fim'] != null
          ? DateTime.parse(json['data_fim']?.toString() ?? '')
          : null,
      origem: json['origem']?.toString() ?? '',
      destino: json['destino']?.toString() ?? '',
      quilometragemInicio: (json['quilometragem_inicio'] as num?)?.toDouble() ?? 0.0,
      quilometragemFim: json['quilometragem_fim'] != null
          ? (json['quilometragem_fim'] as num?)?.toDouble()
          : null,
      status: json['status']?.toString() ?? '',
      fotosRota: List<String>.from(json['fotos_rota'] as List? ?? []),
      consumoLitros: json['consumo_litros'] != null
          ? (json['consumo_litros'] as num?)?.toDouble()
          : null,
      custoTotal: json['custo_total'] != null
          ? (json['custo_total'] as num?)?.toDouble()
          : null,
      observacoes: json['observacoes'] as String?,
      criadoEm: json['criado_em'] != null
          ? DateTime.parse(json['criado_em']?.toString() ?? '')
          : null,
      atualizadoEm: json['atualizado_em'] != null
          ? DateTime.parse(json['atualizado_em']?.toString() ?? '')
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'veiculo_id': veiculoId,
    'motorista_id': motoristaId,
    'data_inicio': dataInicio.toIso8601String(),
    'data_fim': dataFim?.toIso8601String(),
    'origem': origem,
    'destino': destino,
    'quilometragem_inicio': quilometragemInicio,
    'quilometragem_fim': quilometragemFim,
    'status': status,
    'fotos_rota': fotosRota,
    'consumo_litros': consumoLitros,
    'custo_total': custoTotal,
    'observacoes': observacoes,
    'criado_em': criadoEm?.toIso8601String(),
    'atualizado_em': atualizadoEm?.toIso8601String(),
  };
}

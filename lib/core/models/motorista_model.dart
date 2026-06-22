class Motorista {
  final String? id;
  final String? nome;

  Motorista({this.id, this.nome});

  factory Motorista.fromMap(Map<String, dynamic> map) =>
      Motorista(id: map['id']?.toString(), nome: map['nome']?.toString());

  factory Motorista.fromJson(Map<String, dynamic> json) =>
      Motorista.fromMap(json);

  Map<String, dynamic> toMap() => {'id': id, 'nome': nome};
}

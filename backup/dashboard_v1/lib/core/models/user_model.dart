enum UserRole {
  admin, // Acesso total
  gestor, // Gerente de frota
  motorista, // Motorista
}

class AppUser {
  final String id;
  final String email;
  final String nome;
  final UserRole role;
  final bool ativo;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  AppUser({
    required this.id,
    required this.email,
    required this.nome,
    required this.role,
    required this.ativo,
    this.criadoEm,
    this.atualizadoEm,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      nome: json['nome'] as String,
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == (json['role'] as String),
        orElse: () => UserRole.motorista,
      ),
      ativo: json['ativo'] as bool? ?? true,
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
    'email': email,
    'nome': nome,
    'role': role.toString().split('.').last,
    'ativo': ativo,
    'criado_em': criadoEm?.toIso8601String(),
    'atualizado_em': atualizadoEm?.toIso8601String(),
  };

  // Verificadores de permissão
  bool get isAdmin => role == UserRole.admin;
  bool get isGestor => role == UserRole.gestor;
  bool get isMotorista => role == UserRole.motorista;

  bool canView(String resource) {
    if (isAdmin) return true;

    switch (resource) {
      case 'checklists':
        return isGestor || isMotorista;
      case 'multas':
        return isGestor;
      case 'documentos':
        return isGestor;
      case 'viagens':
        return isGestor || isMotorista;
      case 'relatorios':
        return isGestor;
      default:
        return true;
    }
  }

  bool canEdit(String resource) {
    if (isAdmin) return true;

    switch (resource) {
      case 'checklists':
        return isMotorista;
      case 'viagens':
        return isMotorista;
      default:
        return false;
    }
  }

  bool canDelete(String resource) {
    if (isAdmin) return true;
    return false;
  }
}

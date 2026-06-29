import '../enums/app_role.dart';
import '../enums/app_permission.dart';

class UserProfile {
  final String userId;
  final String? empresaId;
  final String? empresaNome;
  final AppRole role;
  final Map<String, bool> customPermissions;
  final String status;
  final DateTime? lastAccess;
  final String? nome;
  final String? email;
  final DateTime? createdAt;

  const UserProfile({
    required this.userId,
    this.empresaId,
    this.empresaNome,
    required this.role,
    this.customPermissions = const {},
    this.status = 'ativo',
    this.lastAccess,
    this.nome,
    this.email,
    this.createdAt,
  });

  /// Verifica se o usuário tem uma permissão específica.
  /// MASTER sempre retorna true. Overrides individuais têm precedência sobre defaults do role.
  bool can(AppPermission permission) {
    if (role == AppRole.master) return true;
    final override = customPermissions[permission.name];
    if (override != null) return override;
    return role.defaultPermissions.contains(permission);
  }

  bool hasRole(AppRole r) => role == r;
  bool hasAnyRole(List<AppRole> roles) => roles.contains(role);

  bool get isActive  => status == 'ativo';
  bool get isBlocked => status == 'bloqueado';
  bool get isPending => status == 'pendente';

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final permMap = <String, bool>{};
    final perms = map['permissions'];
    if (perms is Map) {
      perms.forEach((k, v) {
        if (v is bool) permMap[k.toString()] = v;
      });
    }

    String? empNome;
    final empresa = map['empresas'];
    if (empresa is Map) {
      empNome = empresa['nome']?.toString();
    }

    return UserProfile(
      userId: map['user_id']?.toString() ?? '',
      empresaId: map['empresa_id']?.toString(),
      empresaNome: empNome,
      role: AppRole.fromString(map['role']?.toString()),
      customPermissions: permMap,
      status: map['status']?.toString() ?? 'ativo',
      lastAccess: map['last_access'] != null
          ? DateTime.tryParse(map['last_access'].toString())
          : null,
      nome: map['nome']?.toString(),
      email: map['email']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  /// Perfil temporário para usuário recém-cadastrado, aguardando vinculação de empresa.
  factory UserProfile.pending({required String userId, String? email}) {
    return UserProfile(
      userId: userId,
      email: email,
      role: AppRole.motorista,
      status: 'pendente',
    );
  }

  UserProfile copyWith({
    String? empresaId,
    String? empresaNome,
    AppRole? role,
    Map<String, bool>? customPermissions,
    String? status,
    DateTime? lastAccess,
    String? nome,
    String? email,
  }) {
    return UserProfile(
      userId: userId,
      empresaId: empresaId ?? this.empresaId,
      empresaNome: empresaNome ?? this.empresaNome,
      role: role ?? this.role,
      customPermissions: customPermissions ?? this.customPermissions,
      status: status ?? this.status,
      lastAccess: lastAccess ?? this.lastAccess,
      nome: nome ?? this.nome,
      email: email ?? this.email,
      createdAt: createdAt,
    );
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  final supabase = Supabase.instance.client;
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isGestor => _currentUser?.isGestor ?? false;
  bool get isMotorista => _currentUser?.isMotorista ?? false;

  Future<bool> login(String email, String password) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        await _carregarPerfil(response.user!.id);
        return true;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _carregarPerfil(String userId) async {
    try {
      final response = await supabase
          .from('usuarios')
          .select()
          .eq('id', userId)
          .single();

      _currentUser = AppUser.fromJson(response);
    } catch (e) {
      // Se não encontrar na tabela usuarios, criar um novo
      _currentUser = AppUser(
        id: userId,
        email: supabase.auth.currentUser?.email ?? '',
        nome: supabase.auth.currentUser?.userMetadata?['nome'] ?? 'Usuário',
        role: UserRole.motorista,
        ativo: true,
      );
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    _currentUser = null;
  }

  Future<bool> hasPermission(String resource, String action) async {
    if (_currentUser == null) return false;

    switch (action.toLowerCase()) {
      case 'view':
        return _currentUser!.canView(resource);
      case 'edit':
        return _currentUser!.canEdit(resource);
      case 'delete':
        return _currentUser!.canDelete(resource);
      default:
        return false;
    }
  }

  void reloadUser() {
    if (_currentUser != null) {
      _carregarPerfil(_currentUser!.id);
    }
  }
}

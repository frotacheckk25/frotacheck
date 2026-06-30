import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../enums/app_permission.dart';
import '../enums/app_role.dart';

class AppAuthProvider extends ChangeNotifier {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  StreamSubscription<AuthState>? _authSub;

  // Monotonically increasing counter — each _loadProfile() call captures its
  // own generation. If a newer call starts before the older one finishes, the
  // older call's results are silently discarded, preventing stale writes.
  int _loadGen = 0;

  UserProfile? get profile  => _profile;
  bool get loading           => _loading;
  String? get error          => _error;

  /// True quando autenticado E status == 'ativo'
  bool get isAuthenticated   => _profile != null && _profile!.isActive;
  bool get isPending         => _profile?.isPending ?? false;
  bool get isBlocked         => _profile?.isBlocked ?? false;

  String? get empresaId      => _profile?.empresaId;
  String? get empresaNome    => _profile?.empresaNome;
  AppRole? get role          => _profile?.role;
  bool   get isMaster        => _profile?.role == AppRole.master;

  // ── Impersonation (MASTER visualizando como empresa) ─────────────────────
  String? _impersonatedEmpresaId;
  String? _impersonatedEmpresaNome;

  bool    get isImpersonating        => _impersonatedEmpresaId != null;
  String? get impersonatedEmpresaId  => _impersonatedEmpresaId;
  String? get impersonatedEmpresaNome => _impersonatedEmpresaNome;

  void enterAsEmpresa(String empresaId, String empresaNome) {
    _impersonatedEmpresaId = empresaId;
    _impersonatedEmpresaNome = empresaNome;
    notifyListeners();
  }

  void exitEmpresa() {
    _impersonatedEmpresaId = null;
    _impersonatedEmpresaNome = null;
    notifyListeners();
  }

  // ── Verificações de permissão centralizadas ──────────────────────────────

  bool can(AppPermission permission)       => _profile?.can(permission) ?? false;
  bool hasRole(AppRole r)                  => _profile?.hasRole(r) ?? false;
  bool hasAnyRole(List<AppRole> roles)     => _profile?.hasAnyRole(roles) ?? false;

  /// Injeta empresa_id em um payload antes de um insert/update.
  /// MASTER impersonando injeta a empresa impersonada; caso contrário não injeta.
  Map<String, dynamic> inject(Map<String, dynamic> data) {
    if (isImpersonating) return {...data, 'empresa_id': _impersonatedEmpresaId!};
    if (isMaster || empresaId == null) return data;
    return {...data, 'empresa_id': empresaId};
  }

  // ── Ciclo de vida ────────────────────────────────────────────────────────

  final _supabase = Supabase.instance.client;

  Future<void> initialize() async {
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
          _profile = null;
          _loading = false;
          notifyListeners();
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          _loadProfile();
        default:
          break;
      }
    });

    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _loadProfile();
    } else {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProfile() async {
    final gen = ++_loadGen;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        if (gen != _loadGen) return;
        _profile = null;
        return;
      }

      final res = await _supabase
          .from('user_profiles')
          .select('*, empresas(nome)')
          .eq('user_id', userId)
          .maybeSingle();

      // Discard results from a superseded call (e.g. tokenRefreshed fired
      // while signedIn was still in-flight).
      if (gen != _loadGen) return;

      if (res == null) {
        // Usuário no auth mas sem perfil — aguarda vinculação pelo admin
        _profile = UserProfile.pending(
          userId: userId,
          email: _supabase.auth.currentUser?.email,
        );
      } else {
        _profile = UserProfile.fromMap(res);
        // Atualiza last_access em background, sem bloquear a UI
        _supabase
            .from('user_profiles')
            .update({'last_access': DateTime.now().toIso8601String()})
            .eq('user_id', userId)
            .then((_) {})
            .catchError((_) {});
      }
    } catch (e) {
      debugPrint('AppAuthProvider._loadProfile error: $e');
      if (gen != _loadGen) return;
      _error = e.toString();
      _profile = null;
    } finally {
      if (gen == _loadGen) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> reload() => _loadProfile();

  Future<void> signOut() async {
    // Limpa impersonation antes de sair para não vazar estado entre sessões
    _impersonatedEmpresaId = null;
    _impersonatedEmpresaNome = null;
    await _supabase.auth.signOut();
    _profile = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

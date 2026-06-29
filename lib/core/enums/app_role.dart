import 'package:flutter/material.dart';
import 'app_permission.dart';

enum AppRole {
  master,        // FrotaCheck superadmin — acessa todas as empresas
  adminEmpresa,  // Dono da empresa — controle total dentro da empresa
  gestor,        // Operacional — sem gestão de usuários ou configurações
  motorista;     // Acesso restrito ao próprio trabalho

  String get label {
    switch (this) {
      case AppRole.master:       return 'MASTER';
      case AppRole.adminEmpresa: return 'ADMIN_EMPRESA';
      case AppRole.gestor:       return 'GESTOR';
      case AppRole.motorista:    return 'MOTORISTA';
    }
  }

  String get displayName {
    switch (this) {
      case AppRole.master:       return 'Master';
      case AppRole.adminEmpresa: return 'Admin da Empresa';
      case AppRole.gestor:       return 'Gestor';
      case AppRole.motorista:    return 'Motorista';
    }
  }

  Color get color {
    switch (this) {
      case AppRole.master:       return const Color(0xFFEF4444);
      case AppRole.adminEmpresa: return const Color(0xFF7C3AED);
      case AppRole.gestor:       return const Color(0xFF0D47A1);
      case AppRole.motorista:    return const Color(0xFF1AA251);
    }
  }

  static AppRole fromString(String? s) {
    switch (s?.toUpperCase()) {
      case 'MASTER':        return AppRole.master;
      case 'ADMIN_EMPRESA': return AppRole.adminEmpresa;
      case 'GESTOR':        return AppRole.gestor;
      default:              return AppRole.motorista;
    }
  }

  List<AppPermission> get defaultPermissions {
    switch (this) {
      case AppRole.master:
        return AppPermission.values;

      // ── ADMIN_EMPRESA: controle total da empresa, sem acesso multi-tenant ──
      case AppRole.adminEmpresa:
        return const [
          AppPermission.viewDashboard,
          AppPermission.viewVehicles,    AppPermission.manageVehicles,
          AppPermission.viewDrivers,     AppPermission.manageDrivers,
          AppPermission.viewMaintenance, AppPermission.manageMaintenance,
          AppPermission.viewFuelings,    AppPermission.manageFuelings,
          AppPermission.viewOccurrences, AppPermission.manageOccurrences,
          AppPermission.viewMultas,      AppPermission.manageMultas,
          AppPermission.viewDocuments,   AppPermission.manageDocuments,
          AppPermission.viewChecklists,  AppPermission.manageChecklists,
          AppPermission.viewTires,       AppPermission.manageTires,
          AppPermission.viewAlerts,      AppPermission.manageAlerts,
          AppPermission.viewReports,     AppPermission.exportReports,
          AppPermission.manageSettings,
          AppPermission.viewUsers,       AppPermission.manageUsers,
        ];

      // ── GESTOR: operacional — leitura ampla, sem config ou usuários ─────────
      case AppRole.gestor:
        return const [
          AppPermission.viewDashboard,
          AppPermission.viewVehicles,
          AppPermission.viewDrivers,
          AppPermission.viewMaintenance, AppPermission.manageMaintenance,
          AppPermission.viewFuelings,    AppPermission.manageFuelings,
          AppPermission.viewOccurrences, AppPermission.manageOccurrences,
          AppPermission.viewMultas,
          AppPermission.viewDocuments,
          AppPermission.viewChecklists,  AppPermission.manageChecklists,
          AppPermission.viewTires,
          AppPermission.viewAlerts,
          AppPermission.viewReports,
        ];

      // ── MOTORISTA: restrito ao próprio trabalho diário ────────────────────
      case AppRole.motorista:
        return const [
          AppPermission.viewDashboard,
          AppPermission.viewVehicles,
          AppPermission.viewFuelings,    AppPermission.manageFuelings,
          AppPermission.viewOccurrences, AppPermission.manageOccurrences,
          AppPermission.viewChecklists,  AppPermission.manageChecklists,
        ];
    }
  }
}

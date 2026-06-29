enum AppPermission {
  // Dashboard
  viewDashboard,

  // Veículos
  viewVehicles,
  manageVehicles,

  // Motoristas
  viewDrivers,
  manageDrivers,

  // Manutenções (troca de óleo, revisões, etc.)
  viewMaintenance,
  manageMaintenance,

  // Abastecimentos
  viewFuelings,
  manageFuelings,

  // Ocorrências
  viewOccurrences,
  manageOccurrences,

  // Multas
  viewMultas,
  manageMultas,

  // Documentos
  viewDocuments,
  manageDocuments,

  // Checklists
  viewChecklists,
  manageChecklists,

  // Pneus
  viewTires,
  manageTires,

  // Alertas
  viewAlerts,
  manageAlerts,

  // Relatórios
  viewReports,
  exportReports,

  // Configurações da empresa
  manageSettings,

  // Usuários e empresa (ADMIN_EMPRESA+)
  viewUsers,
  manageUsers,

  // Exclusivo MASTER
  viewAllCompanies,
  manageCompanies,
  manageSystem,
}

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

  // Distribuição do App (QR Code / link de instalação) — MASTER, ADMIN_EMPRESA,
  // DONO e GESTOR; MOTORISTA não tem.
  viewAppDistribution,

  // Documentos Fiscais (CT-e/MDF-e/CIOT) — MASTER, ADMIN_EMPRESA e GESTOR;
  // MOTORISTA não tem.
  viewFiscalDocs,
  manageFiscalDocs, // emitir/cancelar CT-e, MDF-e, CIOT
  manageFiscalSettings, // certificado/CNPJ/IE/ambiente — não vai para GESTOR

  // Segurança da própria conta (MFA/TOTP) — MASTER e ADMIN_EMPRESA apenas
  // (F-06 da auditoria de segurança de 2026-07-29): são os papéis com maior
  // raio de impacto se a conta for comprometida, então só eles têm a tela
  // de habilitar/desabilitar MFA. GESTOR e MOTORISTA não têm.
  manageMfa,
}

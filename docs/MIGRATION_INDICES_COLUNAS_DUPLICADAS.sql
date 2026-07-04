-- =============================================================================
-- Índices para as colunas duplicadas PT/EN em multas e documentos
-- (vehicle_id/veiculo_id) — o app já tem fallback defensivo lendo as duas
-- (vehicle_id ?? veiculo_id), mas sem índice em ambas as consultas por
-- qualquer uma delas fazem full scan.
--
-- Não consolida as colunas (isso exigiria migrar dados + revisar todo o
-- código que lê as duas) — só melhora a performance das consultas atuais.
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_multas_vehicle_id ON public.multas (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_multas_veiculo_id ON public.multas (veiculo_id);
CREATE INDEX IF NOT EXISTS idx_multas_empresa_id ON public.multas (empresa_id);
CREATE INDEX IF NOT EXISTS idx_multas_driver_id  ON public.multas (driver_id);

CREATE INDEX IF NOT EXISTS idx_documentos_vehicle_id ON public.documentos (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_documentos_empresa_id ON public.documentos (empresa_id);
CREATE INDEX IF NOT EXISTS idx_documentos_driver_id  ON public.documentos (driver_id);

-- Colunas usadas constantemente pelas policies de RLS em todas as tabelas
-- de dados — sem índice, toda consulta filtrada por empresa faz full scan.
CREATE INDEX IF NOT EXISTS idx_vehicles_empresa_id     ON public.vehicles (empresa_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_driver_id      ON public.vehicles (driver_id);
CREATE INDEX IF NOT EXISTS idx_drivers_empresa_id      ON public.drivers (empresa_id);
CREATE INDEX IF NOT EXISTS idx_fuelings_empresa_id     ON public.fuelings (empresa_id);
CREATE INDEX IF NOT EXISTS idx_fuelings_driver_id      ON public.fuelings (driver_id);
CREATE INDEX IF NOT EXISTS idx_fuelings_vehicle_id     ON public.fuelings (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_occurrences_empresa_id  ON public.occurrences (empresa_id);
CREATE INDEX IF NOT EXISTS idx_occurrences_driver_id   ON public.occurrences (driver_id);
CREATE INDEX IF NOT EXISTS idx_oil_changes_vehicle_id  ON public.oil_changes (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_manutencoes_vehicle_id  ON public.manutencoes (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_pneus_vehicle_id        ON public.pneus (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_checklists_empresa_id   ON public.checklists (empresa_id);
CREATE INDEX IF NOT EXISTS idx_checklists_motorista_id ON public.checklists (motorista_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_empresa_id ON public.user_profiles (empresa_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_driver_id  ON public.user_profiles (driver_id);

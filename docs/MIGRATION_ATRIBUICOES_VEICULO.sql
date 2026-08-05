-- =============================================================================
-- FrotaCheck — Histórico de atribuição motorista ↔ veículo
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Contexto: vehicles.driver_id só guarda o motorista ATUAL responsável pelo
-- veículo — trocar o motorista sobrescreve o valor antigo, sem deixar
-- rastro de quem pegou o veículo e quando. Esta tabela registra cada
-- período de atribuição (data_inicio/data_fim), alimentando tanto o
-- Histórico do Veículo quanto o novo Histórico do Motorista.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.atribuicoes_veiculo (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    uuid REFERENCES public.empresas(id) ON DELETE CASCADE,
  veiculo_id    uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  motorista_id  uuid REFERENCES public.drivers(id) ON DELETE SET NULL,
  data_inicio   timestamptz NOT NULL DEFAULT now(),
  data_fim      timestamptz,
  criado_em     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_atribuicoes_veiculo_veiculo_id   ON public.atribuicoes_veiculo(veiculo_id);
CREATE INDEX IF NOT EXISTS idx_atribuicoes_veiculo_motorista_id ON public.atribuicoes_veiculo(motorista_id);
-- Garante no máximo UMA atribuição "aberta" (data_fim IS NULL) por veículo de cada vez.
CREATE UNIQUE INDEX IF NOT EXISTS idx_atribuicoes_veiculo_aberta
  ON public.atribuicoes_veiculo(veiculo_id) WHERE (data_fim IS NULL);

ALTER TABLE public.atribuicoes_veiculo ENABLE ROW LEVEL SECURITY;

-- Mesmo padrão de RLS já usado em vehicles/drivers/checklists/viagens neste projeto.
DROP POLICY IF EXISTS "empresa_isolation" ON public.atribuicoes_veiculo;
CREATE POLICY "empresa_isolation" ON public.atribuicoes_veiculo
  FOR ALL
  USING (
    get_my_role() = 'MASTER'
    OR (
      empresa_id = get_my_empresa_id()
      AND (
        get_my_role() = ANY (ARRAY['ADMIN_EMPRESA', 'GESTOR'])
        OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())
      )
    )
  );

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

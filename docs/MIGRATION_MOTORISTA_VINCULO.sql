-- =============================================================================
-- FrotaCheck — Vínculo do motorista (CLT / Agregado)
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Contexto: cliente pediu para diferenciar motoristas empregados (CLT) de
-- motoristas agregados (donos do próprio caminhão, prestando serviço pra
-- transportadora). Essa distinção também importa para o CIOT: motorista
-- agregado é justamente o tipo de operação que exige CIOT (diferente de
-- frota própria + CLT, que desde a Resolução ANTT 6.078/2026 é obrigatória
-- só para a ETC, não para o vínculo do motorista em si).
-- =============================================================================

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS tipo_vinculo text NOT NULL DEFAULT 'clt'
  CHECK (tipo_vinculo IN ('clt', 'agregado'));

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

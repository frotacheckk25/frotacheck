-- =============================================================================
-- FrotaCheck — Regime tributário da empresa para CT-e (complemento de
-- MIGRATION_FISCAL_ENDERECO_EMITENTE.sql, que já tinha sido executado quando
-- este campo foi identificado como necessário).
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_regime_tributario text
  DEFAULT 'simples_nacional' CHECK (fiscal_regime_tributario IN ('simples_nacional','normal'));

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

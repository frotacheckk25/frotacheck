-- =============================================================================
-- FrotaCheck — Endereço estruturado do emitente para CT-e (complemento de
-- MIGRATION_FISCAL_CTE_MDFE_CIOT.sql)
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Motivo: public.empresas.endereco é um texto livre (usado só para exibição).
-- O XML do CT-e exige endereço estruturado do emitente, incluindo o código
-- IBGE do município — que não existe em nenhuma coluna hoje. Guardamos isso
-- em company_settings (ao lado das outras configurações fiscais) em vez de
-- empresas, para não misturar "dados de exibição" com "dados fiscais".
-- =============================================================================

ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_logradouro           text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_numero               text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_complemento          text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_bairro               text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_municipio_codigo_ibge text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_municipio_nome        text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_cep                  text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS fiscal_fone                 text;

-- NOTA: fiscal_regime_tributario foi movido para MIGRATION_FISCAL_REGIME_TRIBUTARIO.sql
-- porque este arquivo já tinha sido executado quando o campo foi adicionado.

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

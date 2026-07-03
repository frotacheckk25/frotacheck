-- =============================================================================
-- FrotaCheck — Adiciona coluna 'phone' em user_profiles
-- Erro original: "Could not find the 'phone' column of 'user_profiles' in
-- the schema cache" ao salvar telefone pessoal em Configurações > Aparência.
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS phone text;

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

-- =============================================================================
-- FrotaCheck — Vínculo direto Driver ↔ Usuário Auth
-- Execute no SQL Editor do Supabase após MIGRATION_DRIVER_ISOLATION.sql
--
-- Problema resolvido:
--   user_profiles.driver_id é a única ponte usuário→motorista.
--   Quando só vehicles.driver_id está definido (via veiculos_page),
--   mas user_profiles.driver_id é NULL, o motorista não vê seu veículo.
--
-- Solução:
--   1. Adiciona drivers.user_id — ponte direta motorista→auth user
--   2. Atualiza get_my_driver_id() para usar COALESCE com o novo campo
--   3. Sincroniza registros existentes via user_profiles.driver_id
-- =============================================================================

-- ── 1. Coluna user_id na tabela drivers ──────────────────────────────────────
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_drivers_user_id
  ON public.drivers(user_id) WHERE user_id IS NOT NULL;

-- ── 2. Sincroniza registros existentes ────────────────────────────────────────
-- Para cada user_profile com driver_id definido, atualiza drivers.user_id.
UPDATE public.drivers d
SET user_id = up.user_id
FROM public.user_profiles up
WHERE up.driver_id = d.id
  AND up.user_id IS NOT NULL
  AND d.user_id IS NULL;

-- ── 3. Atualiza get_my_driver_id() com fallback ───────────────────────────────
-- Primeiro tenta user_profiles.driver_id (fast path).
-- Se NULL, tenta drivers.user_id (fallback para vínculos feitos via veiculos_page).
CREATE OR REPLACE FUNCTION public.get_my_driver_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    -- fast path: user_profiles.driver_id
    (SELECT driver_id
       FROM public.user_profiles
      WHERE user_id = auth.uid()
        AND driver_id IS NOT NULL
      LIMIT 1),
    -- fallback: drivers.user_id
    (SELECT id
       FROM public.drivers
      WHERE user_id = auth.uid()
      LIMIT 1)
  );
$$;

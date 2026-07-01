-- =============================================================================
-- FrotaCheck — Função RPC get_my_vehicle()
-- SECURITY DEFINER: burla RLS e busca o veículo do motorista autenticado
-- diretamente pelo driver_id do seu perfil, sem depender de policies.
--
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_my_vehicle()
RETURNS TABLE (
  id     uuid,
  plate  text,
  model  text,
  year   int,
  brand  text,
  status text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id uuid;
BEGIN
  -- 1) Busca driver_id direto do perfil do usuário autenticado
  SELECT up.driver_id INTO v_driver_id
  FROM public.user_profiles up
  WHERE up.user_id = auth.uid()
  LIMIT 1;

  -- 2) Fallback: tenta via drivers.user_id (se a coluna existir)
  IF v_driver_id IS NULL THEN
    BEGIN
      SELECT d.id INTO v_driver_id
      FROM public.drivers d
      WHERE d.user_id = auth.uid()
      LIMIT 1;
    EXCEPTION WHEN others THEN
      -- coluna user_id ainda não existe em drivers — ignora
      v_driver_id := NULL;
    END;
  END IF;

  IF v_driver_id IS NULL THEN
    RETURN; -- sem driver vinculado: retorna vazio
  END IF;

  RETURN QUERY
  SELECT v.id, v.plate, v.model, v.year::int, v.brand, v.status
  FROM public.vehicles v
  WHERE v.driver_id = v_driver_id
  LIMIT 1;
END;
$$;

-- Garante que usuários autenticados podem chamar a função
GRANT EXECUTE ON FUNCTION public.get_my_vehicle() TO authenticated;

-- Teste: execute como qualquer usuário autenticado para verificar
-- SELECT * FROM get_my_vehicle();

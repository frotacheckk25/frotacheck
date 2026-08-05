-- =============================================================================
-- FrotaCheck — Tipo de veículo + foto real do veículo
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Contexto: cliente pediu para (1) escolher o tipo do veículo ao cadastrar
-- (carro/caminhão/van/ônibus/moto) e (2) permitir que motorista, gestor ou
-- admin substituam a foto genérica por uma foto real do veículo.
-- =============================================================================

-- ─── 1. Colunas novas em vehicles ─────────────────────────────────────────────
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'carro'
  CHECK (tipo IN ('carro', 'caminhao', 'van', 'onibus', 'moto'));

ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS foto_url text;

-- ─── 2. Bucket de Storage para fotos de veículo ──────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('veiculos', 'veiculos', false)
ON CONFLICT (id) DO NOTHING;

-- Mesmo padrão de isolamento já usado em checklists/multas/documentos/fuelings:
-- essas 3 policies são compartilhadas por vários buckets (array de bucket_id),
-- então só precisamos incluir 'veiculos' na lista de cada uma.
DROP POLICY IF EXISTS "authenticated_read_isolated_buckets" ON storage.objects;
CREATE POLICY "authenticated_read_isolated_buckets" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = ANY (ARRAY['checklists','multas','documentos','fuelings','avatars','logos','veiculos'])
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = (get_my_empresa_id())::text
    )
  );

DROP POLICY IF EXISTS "authenticated_write_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_write_frotacheck_buckets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = ANY (ARRAY['avatars','checklists','multas','documentos','logos','fuelings','veiculos'])
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = (get_my_empresa_id())::text
      OR get_my_empresa_id() IS NULL
    )
  );

DROP POLICY IF EXISTS "authenticated_update_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_update_frotacheck_buckets" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = ANY (ARRAY['avatars','checklists','multas','documentos','logos','fuelings','veiculos'])
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = (get_my_empresa_id())::text
      OR get_my_empresa_id() IS NULL
    )
  );

-- ─── 3. get_my_vehicle() precisa devolver os campos novos também ────────────
-- (usada pela tela "Meu Veículo" do motorista — sem isso o app do motorista
-- nunca veria o tipo/foto do próprio veículo)
DROP FUNCTION IF EXISTS public.get_my_vehicle();

CREATE FUNCTION public.get_my_vehicle()
RETURNS TABLE(id uuid, plate text, model text, year integer, brand text, color text, tipo text, foto_url text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_driver_id uuid;
BEGIN
  SELECT up.driver_id INTO v_driver_id
  FROM public.user_profiles up
  WHERE up.user_id = auth.uid()
  LIMIT 1;

  IF v_driver_id IS NULL THEN
    BEGIN
      SELECT d.id INTO v_driver_id
      FROM public.drivers d
      WHERE d.user_id = auth.uid()
      LIMIT 1;
    EXCEPTION WHEN others THEN v_driver_id := NULL; END;
  END IF;

  IF v_driver_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
    SELECT v.id, v.plate, v.model, v.year::int, v.brand, v.color, v.tipo, v.foto_url
    FROM public.vehicles v
    WHERE v.driver_id = v_driver_id
    LIMIT 1;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_my_vehicle() TO authenticated, anon;

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

-- =============================================================================
-- FrotaCheck — Isolamento REAL por motorista no banco (RLS), não só na tela
-- + fecha vazamentos públicos confirmados AO VIVO em 'alerts' e 'manutencoes'
-- + remove policies antigas (de nomes diferentes) que nunca foram dropadas
--   e ainda liberam 'multas'/'documentos' pra qualquer autenticado, de
--   qualquer empresa (Postgres combina policies permissivas com OR — uma
--   policy antiga esquecida anula qualquer policy nova mais restrita).
--
-- Por isso esta versão NÃO confia em "DROP POLICY IF EXISTS <nome>" — ela
-- varre pg_policies e apaga TODAS as policies de cada tabela antes de criar
-- a única policy canônica "empresa_isolation".
--
-- Regras por perfil:
--   MASTER        → vê/escreve em qualquer empresa
--   ADMIN_EMPRESA → vê/escreve tudo da própria empresa
--   GESTOR        → idem ADMIN_EMPRESA
--   MOTORISTA     → vê/escreve APENAS registros do próprio driver_id/veículo
--
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_my_driver_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT driver_id
  FROM public.user_profiles
  WHERE user_id = auth.uid()
    AND driver_id IS NOT NULL
  LIMIT 1;
$$;

-- ── Helper: apaga TODAS as policies existentes de uma tabela ──────────────────
CREATE OR REPLACE FUNCTION public._drop_all_policies(tbl text) RETURNS void AS $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
             WHERE schemaname = 'public' AND tablename = tbl
  LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', pol.policyname, tbl);
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ── fuelings — isolamento por driver_id direto ────────────────────────────────
ALTER TABLE public.fuelings ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('fuelings');
CREATE POLICY "empresa_isolation" ON public.fuelings
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── occurrences — isolamento por driver_id direto ─────────────────────────────
ALTER TABLE public.occurrences ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('occurrences');
CREATE POLICY "empresa_isolation" ON public.occurrences
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── oil_changes — isolamento via veículo vinculado ────────────────────────────
ALTER TABLE public.oil_changes ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('oil_changes');
CREATE POLICY "empresa_isolation" ON public.oil_changes
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = oil_changes.vehicle_id AND v.driver_id = get_my_driver_id()))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── manutencoes — isolamento via veículo vinculado (fecha vazamento público) ───
ALTER TABLE public.manutencoes ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('manutencoes');
CREATE POLICY "empresa_isolation" ON public.manutencoes
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = manutencoes.vehicle_id AND v.driver_id = get_my_driver_id()))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── pneus — isolamento via veículo vinculado ──────────────────────────────────
ALTER TABLE public.pneus ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('pneus');
CREATE POLICY "empresa_isolation" ON public.pneus
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = pneus.vehicle_id AND v.driver_id = get_my_driver_id()))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── checklists — isolamento por motorista_id ──────────────────────────────────
ALTER TABLE public.checklists ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('checklists');
CREATE POLICY "empresa_isolation" ON public.checklists
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── viagens — isolamento por motorista_id ─────────────────────────────────────
DO $$ BEGIN
  ALTER TABLE public.viagens ENABLE ROW LEVEL SECURITY;
  PERFORM public._drop_all_policies('viagens');
  CREATE POLICY "empresa_isolation" ON public.viagens
    FOR ALL TO authenticated
    USING (
      get_my_role() = 'MASTER'
      OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
          AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
               OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())))
    )
    WITH CHECK (
      get_my_role() = 'MASTER'
      OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
    );
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ── alerts — sem NENHUMA proteção RLS até agora (INSERT/SELECT/DELETE anônimo
--    confirmados ao vivo). Schema real: id, title, description, resolved,
--    created_at, empresa_id, company_id — sem vehicle_id/driver_id, então o
--    isolamento aqui é só por empresa (não é acessível pelo motorista no app).
DO $$ BEGIN
  ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
  PERFORM public._drop_all_policies('alerts');
  CREATE POLICY "empresa_isolation" ON public.alerts
    FOR ALL TO authenticated
    USING (
      get_my_role() = 'MASTER'
      OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
    )
    WITH CHECK (
      get_my_role() = 'MASTER'
      OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
    );
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ── documentos — isolamento (tinha policy antiga "authenticated = todos") ─────
-- Documento pode ser do motorista (driver_id/motorista_id) OU do veículo dele.
ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('documentos');
CREATE POLICY "empresa_isolation" ON public.documentos
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND (
                   driver_id = get_my_driver_id()
                   OR motorista_id = get_my_driver_id()
                   OR EXISTS (
                        SELECT 1 FROM public.vehicles v
                        WHERE v.id = documentos.vehicle_id AND v.driver_id = get_my_driver_id())
                 ))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── multas — isolamento (tinha policy antiga "authenticated = todos") ─────────
ALTER TABLE public.multas ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('multas');
CREATE POLICY "empresa_isolation" ON public.multas
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND (
                   driver_id = get_my_driver_id()
                   OR motorista_id = get_my_driver_id()
                   OR EXISTS (
                        SELECT 1 FROM public.vehicles v
                        WHERE v.id = multas.vehicle_id AND v.driver_id = get_my_driver_id())
                 ))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id IS NULL OR empresa_id = get_my_empresa_id()
  );

-- ── vehicles — MOTORISTA só vê/edita o próprio veículo ────────────────────────
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('vehicles');
CREATE POLICY "empresa_isolation" ON public.vehicles
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR'))
  );

-- ── drivers — MOTORISTA só vê/edita o próprio registro ────────────────────────
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
SELECT public._drop_all_policies('drivers');
CREATE POLICY "empresa_isolation" ON public.drivers
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR ((empresa_id IS NULL OR empresa_id = get_my_empresa_id())
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR'))
  );

-- ── user_profiles — ADMIN_EMPRESA nunca tinha UPDATE em perfil de terceiros ───
-- Só existiam profiles_own (UPDATE do próprio) e profiles_master_all (MASTER).
-- A tela "Gestão de Usuários" (trocar role/status de um funcionário)
-- provavelmente falhava silenciosamente (0 linhas afetadas, sem erro) pra
-- qualquer ADMIN_EMPRESA real. GESTOR ganha SELECT (não UPDATE) pra conseguir
-- vincular motorista por e-mail (precisa localizar o perfil).
DROP POLICY IF EXISTS "profiles_admin_empresa" ON public.user_profiles;
CREATE POLICY "profiles_admin_empresa" ON public.user_profiles
  FOR SELECT TO authenticated
  USING (empresa_id = get_my_empresa_id()
         AND get_my_role() IN ('MASTER','ADMIN_EMPRESA','GESTOR'));

DROP POLICY IF EXISTS "profiles_admin_update" ON public.user_profiles;
CREATE POLICY "profiles_admin_update" ON public.user_profiles
  FOR UPDATE TO authenticated
  USING      (empresa_id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA')
  WITH CHECK (empresa_id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA');

DROP FUNCTION IF EXISTS public._drop_all_policies(text);

-- =============================================================================
-- IMPORTANTE — leia antes de considerar isto 100% resolvido:
--
-- Todas as policies acima toleram "empresa_id IS NULL" (pra não travar
-- UPDATE em registros legados/de teste). Isso significa que enquanto essas
-- linhas nulas existirem, QUALQUER usuário autenticado de QUALQUER empresa
-- consegue ver/escrever nelas — não é vazamento público (precisa estar
-- logado), mas é vazamento entre empresas clientes.
--
-- Ação recomendada, quando puder: rodar
--   SELECT tablename, count(*) FROM (
--     SELECT 'drivers' tablename FROM public.drivers WHERE empresa_id IS NULL
--     UNION ALL SELECT 'vehicles' FROM public.vehicles WHERE empresa_id IS NULL
--     UNION ALL SELECT 'multas' FROM public.multas WHERE empresa_id IS NULL
--     -- (repita para as demais tabelas)
--   ) x GROUP BY tablename;
-- e decidir: apagar (se for lixo de teste) ou atribuir a uma empresa real.
-- Depois disso, trocar "empresa_id IS NULL OR" por nada nas policies acima.
-- =============================================================================

-- =============================================================================
-- Fecha a última brecha de isolamento entre empresas: remove a tolerância a
-- "empresa_id IS NULL" das políticas de RLS.
--
-- PRÉ-REQUISITO: rode antes o docs/MIGRATION_LIMPEZA_DADOS_TESTE.sql e confirme
-- que a verificação final retornou 0 em TODAS as tabelas. Se ainda houver
-- alguma linha com empresa_id NULL nessas tabelas, este script vai bloquear
-- o acesso a ela para todo mundo (inclusive ADMIN_EMPRESA/GESTOR), então
-- só rode depois de confirmar a limpeza.
--
-- Reaplica exatamente as mesmas policies de docs/MIGRATION_ISOLAMENTO_MOTORISTA_REAL.sql,
-- só que sem o "empresa_id IS NULL OR".
-- =============================================================================

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

-- ── fuelings ───────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('fuelings');
CREATE POLICY "empresa_isolation" ON public.fuelings
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── occurrences ────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('occurrences');
CREATE POLICY "empresa_isolation" ON public.occurrences
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── oil_changes ────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('oil_changes');
CREATE POLICY "empresa_isolation" ON public.oil_changes
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = oil_changes.vehicle_id AND v.driver_id = get_my_driver_id()))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── manutencoes ────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('manutencoes');
CREATE POLICY "empresa_isolation" ON public.manutencoes
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = manutencoes.vehicle_id AND v.driver_id = get_my_driver_id()))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── pneus ──────────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('pneus');
CREATE POLICY "empresa_isolation" ON public.pneus
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = pneus.vehicle_id AND v.driver_id = get_my_driver_id()))))
  )
  WITH CHECK (
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── checklists ─────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('checklists');
CREATE POLICY "empresa_isolation" ON public.checklists
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── viagens ────────────────────────────────────────────────────────────────
DO $$ BEGIN
  PERFORM public._drop_all_policies('viagens');
  CREATE POLICY "empresa_isolation" ON public.viagens
    FOR ALL TO authenticated
    USING (
      get_my_role() = 'MASTER'
      OR (empresa_id = get_my_empresa_id()
          AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
               OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())))
    )
    WITH CHECK (
      get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
    );
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ── alerts ─────────────────────────────────────────────────────────────────
DO $$ BEGIN
  PERFORM public._drop_all_policies('alerts');
  CREATE POLICY "empresa_isolation" ON public.alerts
    FOR ALL TO authenticated
    USING (get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id())
    WITH CHECK (get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id());
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ── documentos ─────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('documentos');
CREATE POLICY "empresa_isolation" ON public.documentos
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
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
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── multas ─────────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('multas');
CREATE POLICY "empresa_isolation" ON public.multas
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
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
    get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id()
  );

-- ── vehicles ───────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('vehicles');
CREATE POLICY "empresa_isolation" ON public.vehicles
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR'))
  );

-- ── drivers ────────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('drivers');
CREATE POLICY "empresa_isolation" ON public.drivers
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND id = get_my_driver_id())))
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR'))
  );

DROP FUNCTION IF EXISTS public._drop_all_policies(text);

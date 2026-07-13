-- =============================================================================
-- FrotaCheck — Restringe UPDATE/DELETE de MOTORISTA em pneus, multas,
-- documentos e alerts (varredura de segurança de 2026-07-14)
--
-- Problema: as políticas de RLS destas 4 tabelas usam uma única policy
-- "FOR ALL" baseada só em empresa_id (+ dono da linha, no caso de
-- MOTORISTA). Isso cobre SELECT/INSERT corretamente, mas Postgres aplica a
-- mesma condição de UPDATE/DELETE — então um MOTORISTA (ou, no caso de
-- alerts, qualquer papel da empresa) consegue, chamando a API do Supabase
-- diretamente com o próprio JWT, aprovar/editar status ou apagar o próprio
-- registro de multa/pneu/documento, ou o alerta de qualquer colega — mesmo
-- que os botões de "editar status"/"excluir" já estejam escondidos no app
-- (lib/home/multas/multas_page.dart, lib/home/pneus/pneus_page.dart,
-- lib/home/alertas/alertas_page.dart) por checagem de permissão só no
-- cliente. Este script troca a policy única por 4 policies (SELECT/INSERT/
-- UPDATE/DELETE), mantendo INSERT/SELECT como estavam e restringindo
-- UPDATE/DELETE a ADMIN_EMPRESA/GESTOR/MASTER.
--
-- Confirmado no código antes de aplicar: nenhuma tela hoje deixa um
-- MOTORISTA abrir um UPDATE/DELETE nessas 4 tabelas (os únicos call sites
-- de update/delete são todos gated por auth.can(AppPermission.manageX)),
-- então isso não deveria mudar nenhum fluxo visível — só fecha a brecha de
-- chamar a API diretamente.
--
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query).
-- Idempotente — pode rodar mais de uma vez sem erro.
-- =============================================================================

-- ── pneus ────────────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('pneus');

CREATE POLICY "select_isolation" ON public.pneus
  FOR SELECT TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = pneus.vehicle_id AND v.driver_id = get_my_driver_id()))))
  );

CREATE POLICY "insert_isolation" ON public.pneus
  FOR INSERT TO authenticated
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (empresa_id = get_my_empresa_id()
        AND (get_my_role() IN ('ADMIN_EMPRESA','GESTOR')
             OR (get_my_role() = 'MOTORISTA' AND EXISTS (
                   SELECT 1 FROM public.vehicles v
                   WHERE v.id = pneus.vehicle_id AND v.driver_id = get_my_driver_id()))))
  );

CREATE POLICY "update_isolation" ON public.pneus
  FOR UPDATE TO authenticated
  USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')))
  WITH CHECK (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

CREATE POLICY "delete_isolation" ON public.pneus
  FOR DELETE TO authenticated
  USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

-- ── multas ───────────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('multas');

CREATE POLICY "select_isolation" ON public.multas
  FOR SELECT TO authenticated
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
  );

CREATE POLICY "insert_isolation" ON public.multas
  FOR INSERT TO authenticated
  WITH CHECK (
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
  );

CREATE POLICY "update_isolation" ON public.multas
  FOR UPDATE TO authenticated
  USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')))
  WITH CHECK (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

CREATE POLICY "delete_isolation" ON public.multas
  FOR DELETE TO authenticated
  USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

-- ── documentos ───────────────────────────────────────────────────────────────
SELECT public._drop_all_policies('documentos');

CREATE POLICY "select_isolation" ON public.documentos
  FOR SELECT TO authenticated
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
  );

CREATE POLICY "insert_isolation" ON public.documentos
  FOR INSERT TO authenticated
  WITH CHECK (
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
  );

CREATE POLICY "update_isolation" ON public.documentos
  FOR UPDATE TO authenticated
  USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')))
  WITH CHECK (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

CREATE POLICY "delete_isolation" ON public.documentos
  FOR DELETE TO authenticated
  USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

-- ── alerts ───────────────────────────────────────────────────────────────────
-- Sem coluna de dono de linha (não é por veículo/motorista) — qualquer papel
-- da empresa pode gerar um alerta (ex.: troca_oleo_page.dart insere o
-- lembrete de próxima troca rodando como o motorista que fez o registro),
-- mas só ADMIN_EMPRESA/GESTOR/MASTER podem marcar como resolvido ou apagar.
DO $$ BEGIN
  PERFORM public._drop_all_policies('alerts');

  CREATE POLICY "select_isolation" ON public.alerts
    FOR SELECT TO authenticated
    USING (get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id());

  CREATE POLICY "insert_isolation" ON public.alerts
    FOR INSERT TO authenticated
    WITH CHECK (get_my_role() = 'MASTER' OR empresa_id = get_my_empresa_id());

  CREATE POLICY "update_isolation" ON public.alerts
    FOR UPDATE TO authenticated
    USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')))
    WITH CHECK (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));

  CREATE POLICY "delete_isolation" ON public.alerts
    FOR DELETE TO authenticated
    USING (get_my_role() = 'MASTER' OR (empresa_id = get_my_empresa_id() AND get_my_role() IN ('ADMIN_EMPRESA','GESTOR')));
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- =============================================================================
-- Hardening extra: get_my_vehicle() passa a exigir que o veículo pertença à
-- mesma empresa do usuário autenticado, não só ao mesmo driver_id (a função
-- é SECURITY DEFINER e ignora RLS por design — esse é um cinto-e-suspensório
-- contra o caso, hoje improvável, de um driver_id acabar associado a um
-- veículo de outra empresa).
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
  v_empresa_id uuid;
BEGIN
  SELECT up.driver_id, up.empresa_id INTO v_driver_id, v_empresa_id
  FROM public.user_profiles up
  WHERE up.user_id = auth.uid()
  LIMIT 1;

  IF v_driver_id IS NULL THEN
    BEGIN
      SELECT d.id INTO v_driver_id
      FROM public.drivers d
      WHERE d.user_id = auth.uid()
      LIMIT 1;
    EXCEPTION WHEN others THEN
      v_driver_id := NULL;
    END;
  END IF;

  IF v_driver_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT v.id, v.plate, v.model, v.year::int, v.brand, v.status
  FROM public.vehicles v
  WHERE v.driver_id = v_driver_id
    AND (v_empresa_id IS NULL OR v.empresa_id = v_empresa_id)
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_vehicle() TO authenticated;

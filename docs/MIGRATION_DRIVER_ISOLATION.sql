-- =============================================================================
-- FrotaCheck — Isolamento de dados por motorista (Phase 3 RBAC)
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Pré-requisito: supabase_rbac_migration.sql já deve ter sido executado
-- (cria public.empresas, user_profiles, get_my_empresa_id(), get_my_role()).
--
-- Este script:
--   1. Cria a função auxiliar get_my_driver_id()
--   2. Substitui as políticas empresa_isolation de todas as tabelas relevantes
--      por políticas role-aware que restringem o acesso do MOTORISTA apenas
--      aos próprios registros — nunca a registros de outros motoristas.
--
-- Regras por perfil:
--   MASTER        → vê e escreve em qualquer empresa/registro
--   ADMIN_EMPRESA → vê/escreve todos os registros da sua empresa
--   GESTOR        → idem ADMIN_EMPRESA
--   MOTORISTA     → vê APENAS registros vinculados ao próprio driver_id/veículo
-- =============================================================================

-- ── 1. Função auxiliar: get_my_driver_id() ───────────────────────────────────
-- Retorna o drivers.id vinculado ao usuário autenticado (via user_profiles).
-- Retorna NULL para MASTER/ADMIN/GESTOR (sem driver_id vinculado).
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

-- ── 2. fuelings — isolamento por driver_id ────────────────────────────────────
-- MOTORISTA vê apenas abastecimentos onde driver_id = seu próprio driver_id.
DROP POLICY IF EXISTS "empresa_isolation" ON public.fuelings;
CREATE POLICY "empresa_isolation" ON public.fuelings
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

-- ── 3. occurrences — isolamento por driver_id ────────────────────────────────
DROP POLICY IF EXISTS "empresa_isolation" ON public.occurrences;
CREATE POLICY "empresa_isolation" ON public.occurrences
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

-- ── 4. oil_changes — isolamento via veículo vinculado ────────────────────────
-- oil_changes não tem driver_id direto; filtramos via vehicles.driver_id.
DROP POLICY IF EXISTS "empresa_isolation" ON public.oil_changes;
CREATE POLICY "empresa_isolation" ON public.oil_changes
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (
          get_my_role() = 'MOTORISTA'
          AND EXISTS (
            SELECT 1 FROM public.vehicles v
            WHERE v.id = oil_changes.vehicle_id
              AND v.driver_id = get_my_driver_id()
          )
        )
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

-- ── 5. manutencoes — isolamento via veículo vinculado ────────────────────────
DROP POLICY IF EXISTS "empresa_isolation" ON public.manutencoes;
CREATE POLICY "empresa_isolation" ON public.manutencoes
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (
          get_my_role() = 'MOTORISTA'
          AND EXISTS (
            SELECT 1 FROM public.vehicles v
            WHERE v.id = manutencoes.vehicle_id
              AND v.driver_id = get_my_driver_id()
          )
        )
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

-- ── 6. pneus — isolamento via veículo vinculado ──────────────────────────────
DROP POLICY IF EXISTS "empresa_isolation" ON public.pneus;
CREATE POLICY "empresa_isolation" ON public.pneus
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (
          get_my_role() = 'MOTORISTA'
          AND EXISTS (
            SELECT 1 FROM public.vehicles v
            WHERE v.id = pneus.vehicle_id
              AND v.driver_id = get_my_driver_id()
          )
        )
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

-- ── 7. checklists — isolamento por motorista_id ──────────────────────────────
-- Remove políticas antigas (criadas antes do RBAC migration) se ainda existirem.
DROP POLICY IF EXISTS "empresa_isolation" ON public.checklists;
DROP POLICY IF EXISTS "Checklists são visíveis para todos os usuários autenticados" ON public.checklists;
DROP POLICY IF EXISTS "Checklists podem ser criados por usuários autenticados" ON public.checklists;
DROP POLICY IF EXISTS "Checklists podem ser atualizados por criadores" ON public.checklists;
CREATE POLICY "empresa_isolation" ON public.checklists
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

-- ── 8. viagens — isolamento por motorista_id ─────────────────────────────────
DROP POLICY IF EXISTS "empresa_isolation" ON public.viagens;
CREATE POLICY "empresa_isolation" ON public.viagens
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      (empresa_id IS NULL OR empresa_id = get_my_empresa_id())
      AND (
        get_my_role() IN ('ADMIN_EMPRESA', 'GESTOR')
        OR (get_my_role() = 'MOTORISTA' AND motorista_id = get_my_driver_id())
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR empresa_id = get_my_empresa_id()
  );

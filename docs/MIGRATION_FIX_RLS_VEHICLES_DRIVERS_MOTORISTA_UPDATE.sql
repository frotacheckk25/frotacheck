-- =============================================================================
-- FrotaCheck — Corrige RLS de vehicles/drivers para permitir que o próprio
-- motorista salve a foto do seu veículo (e o espelho em drivers.foto_url)
--
-- Bug: a policy "empresa_isolation" de vehicles/drivers tinha o motorista
-- liberado no USING (pode mirar a própria linha: driver_id/id = get_my_driver_id())
-- mas NÃO no WITH CHECK (só ADMIN_EMPRESA/GESTOR/MASTER) — então o UPDATE do
-- motorista passava na checagem de visibilidade e falhava na checagem de
-- escrita, gerando "Erro ao enviar foto do veículo." em Meu Veículo, e
-- falhando silenciosamente (try/catch não-bloqueante) no espelho
-- drivers.foto_url disparado por Meu Perfil.
--
-- Fix: alinhar WITH CHECK ao USING (mesmo padrão já usado em checklists/
-- viagens/multas/etc. neste projeto — RLS só isola por tenant, permissão fina
-- é responsabilidade do Dart).
-- =============================================================================

DROP POLICY IF EXISTS "empresa_isolation" ON public.vehicles;
CREATE POLICY "empresa_isolation" ON public.vehicles
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      empresa_id = get_my_empresa_id()
      AND (
        get_my_role() = ANY (ARRAY['ADMIN_EMPRESA', 'GESTOR'])
        OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (
      empresa_id = get_my_empresa_id()
      AND (
        get_my_role() = ANY (ARRAY['ADMIN_EMPRESA', 'GESTOR'])
        OR (get_my_role() = 'MOTORISTA' AND driver_id = get_my_driver_id())
      )
    )
  );

DROP POLICY IF EXISTS "empresa_isolation" ON public.drivers;
CREATE POLICY "empresa_isolation" ON public.drivers
  FOR ALL TO authenticated
  USING (
    get_my_role() = 'MASTER'
    OR (
      empresa_id = get_my_empresa_id()
      AND (
        get_my_role() = ANY (ARRAY['ADMIN_EMPRESA', 'GESTOR'])
        OR (get_my_role() = 'MOTORISTA' AND id = get_my_driver_id())
      )
    )
  )
  WITH CHECK (
    get_my_role() = 'MASTER'
    OR (
      empresa_id = get_my_empresa_id()
      AND (
        get_my_role() = ANY (ARRAY['ADMIN_EMPRESA', 'GESTOR'])
        OR (get_my_role() = 'MOTORISTA' AND id = get_my_driver_id())
      )
    )
  );

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

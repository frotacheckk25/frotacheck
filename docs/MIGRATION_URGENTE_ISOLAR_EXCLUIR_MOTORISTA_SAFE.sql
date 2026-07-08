-- =============================================================================
-- CRÍTICO — a função excluir_motorista_safe (SECURITY DEFINER, portanto ignora
-- RLS por completo) não validava NADA antes de excluir. Qualquer usuário
-- autenticado — inclusive um MOTORISTA — podia chamar
-- supabase.rpc('excluir_motorista_safe', {driver_id_param: '<qualquer-uuid>'})
-- e apagar um motorista de OUTRA empresa, desvinculando veículo, conta de
-- usuário, abastecimentos, ocorrências, viagens e checklists dele.
--
-- Esta função não existia em nenhum arquivo do repositório — foi criada
-- direto no painel do Supabase, fora de qualquer script versionado (2º caso
-- encontrado nesta auditoria, depois da policy órfã de company_settings).
--
-- Correção: adiciona verificação de permissão idêntica à regra já usada no
-- resto do app (AppPermission.manageDrivers = ADMIN_EMPRESA e GESTOR, restrito
-- à própria empresa; MASTER sem restrição) ANTES de tocar em qualquer tabela.
--
-- Execute no SQL Editor do Supabase.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.excluir_motorista_safe(driver_id_param uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_empresa_id uuid;
  v_caller_role text := get_my_role();
BEGIN
  SELECT empresa_id INTO v_empresa_id FROM public.drivers WHERE id = driver_id_param;

  IF v_empresa_id IS NULL THEN
    RAISE EXCEPTION 'Motorista não encontrado';
  END IF;

  IF v_caller_role <> 'MASTER'
     AND (v_caller_role NOT IN ('ADMIN_EMPRESA', 'GESTOR') OR v_empresa_id IS DISTINCT FROM get_my_empresa_id()) THEN
    RAISE EXCEPTION 'Sem permissão para excluir este motorista';
  END IF;

  UPDATE public.fuelings      SET driver_id = NULL WHERE driver_id = driver_id_param;
  UPDATE public.vehicles      SET driver_id = NULL WHERE driver_id = driver_id_param;
  UPDATE public.user_profiles SET driver_id = NULL WHERE driver_id = driver_id_param;

  BEGIN UPDATE public.occurrences SET driver_id = NULL WHERE driver_id = driver_id_param; EXCEPTION WHEN others THEN NULL; END;
  BEGIN UPDATE public.viagens     SET driver_id = NULL WHERE driver_id = driver_id_param; EXCEPTION WHEN others THEN NULL; END;
  BEGIN UPDATE public.checklists  SET driver_id = NULL WHERE driver_id = driver_id_param; EXCEPTION WHEN others THEN NULL; END;

  DELETE FROM public.drivers WHERE id = driver_id_param;
END;
$function$;

-- Confirma que a nova definição contém a checagem de permissão.
SELECT pg_get_functiondef(oid) AS definicao
FROM pg_proc
WHERE proname = 'excluir_motorista_safe';

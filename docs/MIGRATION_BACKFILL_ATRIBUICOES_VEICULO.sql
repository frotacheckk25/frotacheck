-- =============================================================================
-- FrotaCheck — Backfill único: cria a atribuição "atual" para veículos que já
-- tinham motorista responsável (vehicles.driver_id) ANTES de
-- atribuicoes_veiculo existir. Sem isso, esses veículos nunca mostram nada em
-- "Atribuições" até o motorista ser trocado manualmente pela primeira vez.
--
-- Não recupera a data real em que a atribuição começou (isso nunca foi
-- registrado) — usa a data de execução deste script como data_inicio.
-- Execute no SQL Editor do Supabase. Seguro rodar mais de uma vez (idempotente
-- via NOT EXISTS).
-- =============================================================================

INSERT INTO public.atribuicoes_veiculo (empresa_id, veiculo_id, motorista_id, data_inicio)
SELECT v.empresa_id, v.id, v.driver_id, now()
FROM public.vehicles v
WHERE v.driver_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.atribuicoes_veiculo av
    WHERE av.veiculo_id = v.id AND av.data_fim IS NULL
  );

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

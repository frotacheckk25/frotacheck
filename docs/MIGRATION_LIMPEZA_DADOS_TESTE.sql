-- =============================================================================
-- Limpeza dos dados de teste (empresa_id IS NULL), confirmados pelo usuário
-- como dados criados por um agent para testes, sem vínculo com empresa real.
--
-- NÃO apaga user_profiles: a única linha com empresa_id NULL lá é a própria
-- conta MASTER (macielsoares53@hotmail.com), que legitimamente não tem empresa.
--
-- Ordem: apaga primeiro os registros "filhos" (abastecimentos, ocorrências,
-- trocas de óleo, manutenções, pneus, checklists, viagens, alertas, documentos,
-- multas) e só depois vehicles e drivers, para não esbarrar em chaves
-- estrangeiras que apontem para veículos/motoristas de teste.
--
-- Está tudo dentro de uma transação: se qualquer passo falhar, nada é apagado.
-- =============================================================================

BEGIN;

DELETE FROM public.fuelings     WHERE empresa_id IS NULL;
DELETE FROM public.occurrences  WHERE empresa_id IS NULL;
DELETE FROM public.oil_changes  WHERE empresa_id IS NULL;
DELETE FROM public.manutencoes  WHERE empresa_id IS NULL;
DELETE FROM public.pneus        WHERE empresa_id IS NULL;
DELETE FROM public.checklists   WHERE empresa_id IS NULL;
DELETE FROM public.viagens      WHERE empresa_id IS NULL;
DELETE FROM public.alerts       WHERE empresa_id IS NULL;
DELETE FROM public.documentos   WHERE empresa_id IS NULL;
DELETE FROM public.multas       WHERE empresa_id IS NULL;

DELETE FROM public.vehicles     WHERE empresa_id IS NULL;
DELETE FROM public.drivers      WHERE empresa_id IS NULL;

COMMIT;

-- =============================================================================
-- Verificação: deve retornar 0 em todas as linhas abaixo (exceto se algo
-- inesperado escapou do filtro). user_profiles não é verificado aqui de
-- propósito, pois a conta MASTER deve continuar com empresa_id NULL.
-- =============================================================================
SELECT 'drivers' AS tabela, COUNT(*) FROM public.drivers WHERE empresa_id IS NULL
UNION ALL SELECT 'vehicles', COUNT(*) FROM public.vehicles WHERE empresa_id IS NULL
UNION ALL SELECT 'fuelings', COUNT(*) FROM public.fuelings WHERE empresa_id IS NULL
UNION ALL SELECT 'occurrences', COUNT(*) FROM public.occurrences WHERE empresa_id IS NULL
UNION ALL SELECT 'oil_changes', COUNT(*) FROM public.oil_changes WHERE empresa_id IS NULL
UNION ALL SELECT 'manutencoes', COUNT(*) FROM public.manutencoes WHERE empresa_id IS NULL
UNION ALL SELECT 'pneus', COUNT(*) FROM public.pneus WHERE empresa_id IS NULL
UNION ALL SELECT 'checklists', COUNT(*) FROM public.checklists WHERE empresa_id IS NULL
UNION ALL SELECT 'viagens', COUNT(*) FROM public.viagens WHERE empresa_id IS NULL
UNION ALL SELECT 'alerts', COUNT(*) FROM public.alerts WHERE empresa_id IS NULL
UNION ALL SELECT 'documentos', COUNT(*) FROM public.documentos WHERE empresa_id IS NULL
UNION ALL SELECT 'multas', COUNT(*) FROM public.multas WHERE empresa_id IS NULL;

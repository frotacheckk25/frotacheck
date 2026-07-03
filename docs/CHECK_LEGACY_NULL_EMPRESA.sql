-- Lista quantos registros de cada tabela ainda estão sem empresa_id (dados legados/de teste)
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
UNION ALL SELECT 'multas', COUNT(*) FROM public.multas WHERE empresa_id IS NULL
UNION ALL SELECT 'user_profiles', COUNT(*) FROM public.user_profiles WHERE empresa_id IS NULL;

-- Depois de rodar, me diga os números. Se forem registros de teste que podem ser
-- apagados, eu preparo o DELETE + a migração que remove a tolerância a
-- "empresa_id IS NULL" das políticas de RLS, fechando de vez esse ponto.

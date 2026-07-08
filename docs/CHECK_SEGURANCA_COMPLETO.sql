-- =============================================================================
-- Verificação de segurança completa — roda em cima do banco AO VIVO, não dos
-- arquivos de migração (arquivos antigos podem nunca ter sido executados, ou
-- podem ter sido substituídos por versões mais novas — só o banco real diz
-- a verdade).
--
-- Contexto: encontramos no histórico de docs/*.sql pelo menos 2 arquivos
-- antigos (MIGRATION_CHECKLISTS_MULTAS_DOCS.sql e MIGRATION_EMPRESA_LOGO_
-- CONFIG.sql / MIGRATION_BUCKET_FUELINGS.sql) que, SE tivessem sido
-- executados sobre o schema atual, teriam criado policies permissivas demais
-- (liberando checklists/multas/documentos para qualquer usuário autenticado
-- de qualquer empresa, e reabrindo buckets de Storage como públicos). Este
-- script mostra o que REALMENTE existe hoje no banco.
--
-- Rode cada bloco e me mande o resultado.
-- =============================================================================

-- 1) Todas as policies das 3 tabelas suspeitas — se aparecer mais de uma
--    policy por tabela/comando com nomes tipo "... são visíveis para todos
--    os usuários autenticados" ou "USING (auth.role() = 'authenticated')"
--    SEM checar empresa_id, é uma falha crítica de isolamento multi-tenant.
SELECT tablename, policyname, cmd, roles,
       pg_get_expr(polqual, polrelid)      AS using_clause,
       pg_get_expr(polwithcheck, polrelid) AS with_check_clause
FROM pg_policies
JOIN pg_policy ON pg_policy.polname = pg_policies.policyname
WHERE schemaname = 'public'
  AND tablename IN ('checklists', 'multas', 'documentos')
ORDER BY tablename, cmd;

-- 2) Todas as policies de TODAS as tabelas públicas com RLS, para varredura
--    geral (procure qualquer "USING (true)" ou "auth.role() = 'authenticated'"
--    sem empresa_id em tabela que deveria ser isolada).
SELECT schemaname, tablename, policyname, cmd, roles,
       pg_get_expr(polqual, polrelid) AS using_clause
FROM pg_policies
JOIN pg_policy ON pg_policy.polname = pg_policies.policyname
WHERE schemaname = 'public'
ORDER BY tablename, cmd;

-- 3) Confere se as 3 tabelas realmente têm RLS habilitado (não só policies).
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname IN ('checklists', 'multas', 'documentos', 'planos', 'assinaturas')
  AND relnamespace = 'public'::regnamespace;

-- 4) Todas as policies de storage.objects (leitura/escrita de arquivos) —
--    procure qualquer policy com role "public" (não "authenticated") ou sem
--    filtro de pasta/empresa nos buckets sensíveis.
SELECT policyname, cmd, roles,
       pg_get_expr(polqual, polrelid)      AS using_clause,
       pg_get_expr(polwithcheck, polrelid) AS with_check_clause
FROM pg_policies
JOIN pg_policy ON pg_policy.polname = pg_policies.policyname
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY cmd, policyname;

-- 5) Flag público dos buckets — todos devem estar com public = false.
SELECT id, name, public FROM storage.buckets ORDER BY id;

-- 6) Colunas reais das 3 tabelas suspeitas — confirma se são as mesmas
--    tabelas usadas pelo app hoje (empresa_id, vehicle_id/driver_id em
--    inglês) ou uma estrutura antiga/abandonada (veiculo_id/motorista_id).
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('checklists', 'multas', 'documentos')
ORDER BY table_name, ordinal_position;

-- 7) Confirma se MIGRATION_ADICIONA_VALOR_MENSALIDADE.sql já foi executada
--    (coluna valor_mensalidade em empresas). Se não retornar nenhuma linha,
--    essa migração ainda está pendente.
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'empresas' AND column_name = 'valor_mensalidade';

-- 8) Confirma se MIGRATION_MODULO_PLANOS.sql rodou por completo: deve haver
--    4 planos no catálogo e 1 assinatura por empresa (mesma contagem das
--    duas tabelas).
SELECT
  (SELECT count(*) FROM public.planos) AS total_planos,
  (SELECT count(*) FROM public.empresas) AS total_empresas,
  (SELECT count(*) FROM public.assinaturas) AS total_assinaturas;

-- =============================================================================
-- CRÍTICO — remove policy órfã super-permissiva em company_settings.
--
-- Encontrada via auditoria de segurança ao vivo (não existe em NENHUM
-- arquivo de migração do repositório — foi criada direto no painel do
-- Supabase, fora de qualquer script versionado):
--
--   policy "authenticated can manage company_settings"
--   ON public.company_settings FOR ALL USING (true)
--
-- Como o Postgres combina múltiplas policies permissivas com OR, essa
-- policy sozinha anula o isolamento das policies corretas
-- (company_settings_read / company_settings_write / company_settings_update
-- de docs/MIGRATION_EMPRESA_LOGO_CONFIG.sql) — qualquer usuário autenticado,
-- de qualquer empresa, consegue ler E alterar as configurações
-- (notificações/integrações) de QUALQUER outra empresa.
--
-- Execute no SQL Editor do Supabase.
-- =============================================================================

DROP POLICY IF EXISTS "authenticated can manage company_settings" ON public.company_settings;

-- Confirma que sobraram só as 3 policies corretas e isoladas por empresa.
SELECT policyname, cmd, roles, qual AS using_clause, with_check AS with_check_clause
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'company_settings'
ORDER BY cmd, policyname;

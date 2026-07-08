-- =============================================================================
-- CORREÇÃO URGENTE — CRÍTICA — vazamento residual no bucket "avatars"
--
-- Depois de corrigir a flag "public" do bucket, a listagem anônima
-- (POST /storage/v1/object/list/avatars) continuava funcionando. Causa raiz
-- encontrada: existem 3 policies antigas em storage.objects que nunca foram
-- criadas por nenhuma migração nossa (provavelmente geradas automaticamente
-- pelo próprio Supabase quando o bucket foi marcado como público pela
-- primeira vez, num passo anterior a qualquer migração deste projeto):
--
--   avatars_select  (SELECT, TO public,        USING bucket_id = 'avatars')
--   avatars_insert  (INSERT, TO public,         WITH CHECK bucket_id = 'avatars' AND auth.role() = 'authenticated')
--   avatars_update  (UPDATE, TO public,         USING bucket_id = 'avatars' AND auth.role() = 'authenticated')
--
-- "TO public" no Postgres significa QUALQUER UM, autenticado ou não. Como o
-- Postgres combina policies permissivas com OR, essa "avatars_select" antiga
-- sozinha já garante leitura irrestrita do bucket inteiro pra qualquer
-- pessoa da internet — anulando a policy mais nova e restrita
-- "authenticated_read_public_buckets" só para esse bucket específico.
--
-- Mesmo padrão do bug "profiles_own": uma policy antiga, com nome diferente
-- do que qualquer migração nossa varria, nunca foi removida.
-- =============================================================================

DROP POLICY IF EXISTS "avatars_select" ON storage.objects;
DROP POLICY IF EXISTS "avatars_insert" ON storage.objects;
DROP POLICY IF EXISTS "avatars_update" ON storage.objects;

-- Verificação: NÃO deve retornar nenhuma linha
SELECT policyname, cmd, roles FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
  AND policyname IN ('avatars_select', 'avatars_insert', 'avatars_update');

-- Verificação 2: deve retornar exatamente as mesmas 4 policies restritas de
-- sempre (2 de leitura + 2 de escrita), todas "TO authenticated"
SELECT policyname, cmd, roles FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY cmd, policyname;

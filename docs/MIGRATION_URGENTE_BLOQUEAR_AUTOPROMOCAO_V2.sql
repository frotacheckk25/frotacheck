-- =============================================================================
-- CORREÇÃO URGENTE — CRÍTICA (parte 2 da correção anterior)
--
-- A correção anterior (MIGRATION_URGENTE_BLOQUEAR_AUTOPROMOCAO.sql) criou um
-- trigger BEFORE UPDATE que bloqueia autopromoção via UPDATE. Só que a policy
-- "profiles_own" continua sendo "FOR ALL" (cobre SELECT, INSERT, UPDATE e
-- DELETE) — e o trigger só dispara em UPDATE. Ou seja, o mesmo ataque
-- continua possível por outro caminho:
--
--   1. DELETE /rest/v1/user_profiles?user_id=eq.<próprio_uid>
--      → permitido por profiles_own (FOR ALL, USING user_id = auth.uid()),
--        sem nenhum trigger BEFORE DELETE bloqueando.
--   2. POST /rest/v1/user_profiles { user_id: <próprio_uid>, role: "MASTER" }
--      → permitido pelo WITH CHECK de profiles_own (só valida user_id), e o
--        trigger de proteção não dispara em INSERT.
--
-- Resultado: a mesma autopromoção a MASTER que a correção anterior fechou
-- continua possível, só que via "apagar e recriar a própria linha" em vez de
-- "atualizar".
--
-- CORREÇÃO: divide "profiles_own" em duas policies de propósito único
-- (SELECT e UPDATE), removendo por completo a capacidade de qualquer usuário
-- comum inserir ou apagar a própria linha via essa policy. Isso não quebra
-- nada:
--   - A criação da linha em user_profiles no cadastro é feita pelo trigger
--     SECURITY DEFINER "handle_new_user" (MIGRATION_FIX_SIGNUP_TRIGGER.sql),
--     que roda com privilégio elevado e ignora RLS — não depende de
--     profiles_own ter INSERT.
--   - Não existe nenhuma funcionalidade no app de "usuário apaga a própria
--     conta" que dependa de profiles_own ter DELETE.
--   - MASTER continua com controle total via "profiles_master_all" (FOR ALL),
--     que não é afetada por esta migração.
-- =============================================================================

DROP POLICY IF EXISTS "profiles_own" ON public.user_profiles;

CREATE POLICY "profiles_own_select" ON public.user_profiles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "profiles_own_update" ON public.user_profiles
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- =============================================================================
-- Verificação: deve retornar 2 linhas (profiles_own_select, profiles_own_update)
-- e NENHUMA linha chamada "profiles_own".
-- =============================================================================
SELECT policyname, cmd FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'user_profiles'
ORDER BY policyname;

-- Mostra a definição completa das policies que apareceram na verificação
-- anterior e que não vieram de nenhuma migração desta sessão, para confirmar
-- que não reabrem a mesma brecha de autopromoção por outro caminho.
SELECT policyname, cmd, qual AS using_clause, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'user_profiles'
  AND policyname IN ('profiles_update_own', 'profiles_update_empresa_admin');

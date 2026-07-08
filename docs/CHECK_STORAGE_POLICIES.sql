-- Mostra TODAS as policies atuais em storage.objects, para entender por que
-- a listagem anônima (POST /storage/v1/object/list/<bucket>) ainda funciona
-- mesmo com o bucket marcado como não-público e a policy de SELECT
-- restrita a "authenticated".
SELECT policyname, cmd, roles, qual AS using_clause, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY cmd, policyname;

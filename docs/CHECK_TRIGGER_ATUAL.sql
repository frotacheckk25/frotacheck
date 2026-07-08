-- Mostra a definição atual da função do gatilho de proteção de user_profiles.
-- Precisa conter a linha "IN ('MASTER', 'ADMIN_EMPRESA')" (não só 'MASTER'
-- sozinho) para confirmar que o bloqueio de escalonamento para ADMIN_EMPRESA
-- já foi aplicado.
SELECT pg_get_functiondef(oid) AS definicao
FROM pg_proc
WHERE proname = '_protect_profile_privileged_columns';

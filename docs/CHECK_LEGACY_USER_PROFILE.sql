-- Identifica o usuário sem empresa_id, para confirmar se é a conta MASTER
-- (legítima, não deve ser tocada) ou uma conta de teste esquecida.
SELECT user_id, email, nome, role, status, driver_id, created_at
FROM public.user_profiles
WHERE empresa_id IS NULL;

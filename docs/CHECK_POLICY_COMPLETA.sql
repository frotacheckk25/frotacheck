-- Mostra o texto completo (sem truncar) da policy profiles_update_empresa_admin
SELECT pg_get_expr(polqual, polrelid) AS using_completo,
       pg_get_expr(polwithcheck, polrelid) AS with_check_completo
FROM pg_policy
WHERE polname = 'profiles_update_empresa_admin';

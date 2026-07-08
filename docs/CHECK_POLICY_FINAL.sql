SELECT substring(pg_get_expr(polqual, polrelid), 340, 200) AS trecho_final
FROM pg_policy
WHERE polname = 'profiles_update_empresa_admin';

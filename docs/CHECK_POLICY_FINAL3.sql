SELECT substring(pg_get_expr(polqual, polrelid), 100, 48) AS trecho_final
FROM pg_policy
WHERE polname = 'profiles_update_empresa_admin';

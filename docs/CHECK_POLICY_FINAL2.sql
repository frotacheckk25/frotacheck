SELECT
  length(pg_get_expr(polqual, polrelid)) AS tamanho_total,
  substring(pg_get_expr(polqual, polrelid), 225, 100) AS trecho_final
FROM pg_policy
WHERE polname = 'profiles_update_empresa_admin';

SELECT
  substring(pg_get_expr(polqual, polrelid), 1, 120)   AS parte_1,
  substring(pg_get_expr(polqual, polrelid), 121, 120) AS parte_2,
  substring(pg_get_expr(polqual, polrelid), 241, 120) AS parte_3,
  substring(pg_get_expr(polqual, polrelid), 361, 120) AS parte_4
FROM pg_policy
WHERE polname = 'profiles_update_empresa_admin';

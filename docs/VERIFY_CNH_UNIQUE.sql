-- Confirma se a constraint foi criada com sucesso
SELECT conname, contype, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.drivers'::regclass
  AND conname = 'drivers_empresa_cnh_unique';

-- Se não retornar nenhuma linha, a constraint NÃO foi criada
-- (provavelmente porque a query de diagnóstico encontrou duplicatas e o ALTER TABLE falhou).

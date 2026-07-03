-- Migração: garante unicidade de CNH por empresa (evita corrida de checagem no app - TOCTOU)
-- Antes de aplicar a constraint, rode o SELECT abaixo para achar duplicatas existentes.
-- Se houver duplicatas, resolva manualmente (mesclar/corrigir cadastros) antes de aplicar o UNIQUE.

-- 1) Diagnóstico: duplicatas de CNH dentro da mesma empresa
SELECT empresa_id, cnh_number, COUNT(*) AS qtd, array_agg(id) AS driver_ids
FROM public.drivers
WHERE cnh_number IS NOT NULL AND cnh_number <> ''
GROUP BY empresa_id, cnh_number
HAVING COUNT(*) > 1;

-- 2) Se a consulta acima não retornar linhas, aplique a constraint:
ALTER TABLE public.drivers
  ADD CONSTRAINT drivers_empresa_cnh_unique UNIQUE (empresa_id, cnh_number);

-- Observação: a constraint só impede duplicidade da MESMA CNH dentro da MESMA empresa.
-- Um motorista pode legitimamente ter cadastro em empresas diferentes com a mesma CNH.

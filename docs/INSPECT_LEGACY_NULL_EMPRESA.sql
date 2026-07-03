-- Amostra dos veículos e motoristas sem empresa_id, para confirmar visualmente
-- se são dados de teste (nomes genéricos tipo "Teste", placas aleatórias) ou
-- dados reais que perderam o vínculo com a empresa por engano.

SELECT 'vehicles' AS origem, id, plate, model, brand, created_at
FROM public.vehicles
WHERE empresa_id IS NULL
ORDER BY created_at DESC;

SELECT 'drivers' AS origem, id, name, cnh_number, email, created_at
FROM public.drivers
WHERE empresa_id IS NULL
ORDER BY created_at DESC;

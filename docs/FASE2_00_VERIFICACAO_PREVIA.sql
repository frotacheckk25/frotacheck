-- =============================================================================
-- FrotaCheck — Fase 2 (2026-09-24) — PASSO 0: VERIFICAÇÃO PRÉVIA (só leitura)
--
-- Rode ANTES do FASE2_01. Nada aqui altera o banco. Serve para garantir que
-- as regras novas não vão travar nenhum cliente real no momento da aplicação.
-- =============================================================================

-- 0.1 — Status de empresas. A partir do FASE2_01, SÓ empresas com
-- status = 'ativo' conseguem acessar dados. Se um cliente pagante aparecer
-- aqui com outro status, corrija o status dele ANTES de rodar o FASE2_01.
select id, nome, status from public.empresas where status is distinct from 'ativo' order by nome;

-- 0.2 — Usuários que perderão acesso (status diferente de 'ativo').
-- O app já mostra tela de bloqueio para eles; a diferença é que a API também
-- passa a bloquear. Confira se não há ninguém que deveria estar 'ativo'.
select up.email, up.role, up.status, e.nome as empresa
from public.user_profiles up
left join public.empresas e on e.id = up.empresa_id
where up.status is distinct from 'ativo'
order by up.status, up.email;

-- 0.3 — Contas com MFA ativo (passam a precisar do 2º fator também na API).
select up.email, up.role
from auth.mfa_factors f
join public.user_profiles up on up.user_id = f.user_id
where f.status = 'verified';

-- 0.4 — Placas duplicadas na mesma empresa (impedem a regra de placa única;
-- se houver linhas, o FASE2_01 pula essa regra e avisa — corrija e rode de novo).
select empresa_id, upper(regexp_replace(plate, '[^A-Za-z0-9]', '', 'g')) as placa, count(*) as qtd
from public.vehicles
group by 1, 2
having count(*) > 1;

-- 0.5 — Abastecimentos que violariam as novas regras de sanidade
-- (as regras valem só para registros NOVOS; isto é só para você revisar).
select id, empresa_id, fuel_date, liters, total_value, odometer
from public.fuelings
where liters is null or liters <= 0
   or total_value is null or total_value <= 0
   or odometer < 0
   or (liters > 0 and (total_value / liters < 0.5 or total_value / liters > 100))
order by fuel_date desc
limit 100;

-- 0.6 — Empresas acima do limite do plano (não serão bloqueadas nos veículos
-- já existentes; só não poderão cadastrar novos até ficarem abaixo do limite).
select e.nome, p.codigo as plano, p.limite_veiculos,
       (select count(*) from public.vehicles v where v.empresa_id = e.id) as veiculos
from public.empresas e
join public.assinaturas a on a.empresa_id = e.id
join public.planos p on p.id = a.plano_id
where p.limite_veiculos is not null
  and (select count(*) from public.vehicles v where v.empresa_id = e.id) > p.limite_veiculos;

-- 0.7 — Empresas sem assinatura (sem assinatura = sem limite aplicado).
select e.nome from public.empresas e
where not exists (select 1 from public.assinaturas a where a.empresa_id = e.id);

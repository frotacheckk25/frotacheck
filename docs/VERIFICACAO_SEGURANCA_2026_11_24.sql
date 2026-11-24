-- =============================================================================
-- FrotaCheck — Verificação de segurança (auditoria 2026-11-24)
--
-- SÓ LEITURA. Não altera nada. Rode no Supabase → SQL Editor → New query.
-- Cada linha devolve PASS ou ⚠ FALHA. Qualquer FALHA = rodar a migração
-- correspondente (indicada na coluna "corrigir_com").
--
-- Objetivo: confirmar que TODAS as proteções que existem nos arquivos de
-- migração estão de fato aplicadas no banco de PRODUÇÃO (o risco é uma
-- migração de segurança ter ficado sem rodar).
-- =============================================================================
with
-- 1) RLS ligada em todas as tabelas sensíveis -------------------------------
rls as (
  select 'RLS ligada: ' || t as verificacao,
         case when bool_and(c.relrowsecurity) then 'PASS' else '⚠ FALHA' end as resultado,
         'migração da tabela (RBAC / módulo)' as corrigir_com
  from (values ('vehicles'),('drivers'),('fuelings'),('oil_changes'),('multas'),
               ('occurrences'),('manutencoes'),('documentos'),('pneus'),('checklists'),
               ('viagens'),('alerts'),('user_profiles'),('empresas'),('company_settings'),
               ('clientes'),('cotacoes'),('coletas'),('contas_pagar'),('contas_receber'),
               ('pedidos_compra'),('materiais'),('estoque_movimentos'),('ordens_servico'),
               ('cte_documentos'),('mdfe_documentos'),('ciot_registros'),
               ('rastreamento_posicoes'),('rastreamento_integracoes'),('device_tokens')) v(t)
  join pg_class c on c.relname = v.t and c.relnamespace = 'public'::regnamespace
  group by t
),
-- 2) Nenhuma linha órfã (empresa_id NULL) nas tabelas isoladas ---------------
--    (contagens explícitas: com o leak IS NULL já removido, uma linha órfã só
--     fica visível para MASTER — mas se o leak voltar, ela vaza para todos.)
orfas as (
  select v as verificacao,
         case when n = 0 then 'PASS' else '⚠ FALHA (' || n || ' linhas órfãs)' end as resultado,
         'MIGRATION_FECHAR_ISOLAMENTO_FINAL.sql' as corrigir_com
  from (
    select 'Sem linhas órfãs: vehicles'    v, (select count(*) from public.vehicles    where empresa_id is null) n
    union all select 'Sem linhas órfãs: drivers',     (select count(*) from public.drivers     where empresa_id is null)
    union all select 'Sem linhas órfãs: fuelings',    (select count(*) from public.fuelings    where empresa_id is null)
    union all select 'Sem linhas órfãs: multas',      (select count(*) from public.multas      where empresa_id is null)
    union all select 'Sem linhas órfãs: documentos',  (select count(*) from public.documentos  where empresa_id is null)
    union all select 'Sem linhas órfãs: manutencoes', (select count(*) from public.manutencoes where empresa_id is null)
    union all select 'Sem linhas órfãs: pneus',       (select count(*) from public.pneus       where empresa_id is null)
    union all select 'Sem linhas órfãs: checklists',  (select count(*) from public.checklists  where empresa_id is null)
  ) q
),
-- 3) Gatilho que bloqueia auto-promoção de papel ----------------------------
trg as (
  select * from (values
    ('Trigger anti-escalonamento em user_profiles',
     case when exists (
       select 1 from pg_proc where proname = '_protect_profile_privileged_columns')
       and exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                   where c.relname='user_profiles' and not t.tgisinternal)
       then 'PASS' else '⚠ FALHA' end,
     'MIGRATION_URGENTE_BLOQUEAR_AUTOPROMOCAO_V2.sql'),
    ('Trigger restringe MOTORISTA em vehicles/drivers',
     case when (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
                where c.relname in ('vehicles','drivers')
                  and t.tgname like 'trg_protect_%' and not t.tgisinternal) >= 2
       then 'PASS' else '⚠ FALHA' end,
     'MIGRATION_AUDITORIA_SEGURANCA_2026_07_29.sql')
  ) x(verificacao, resultado, corrigir_com)
),
-- 4) Buckets de storage todos PRIVADOS --------------------------------------
buckets as (
  select 'Bucket privado: ' || id as verificacao,
         case when public = false then 'PASS' else '⚠ FALHA (bucket PÚBLICO)' end as resultado,
         'MIGRATION_URGENTE_STORAGE_PUBLIC_FLAG.sql' as corrigir_com
  from storage.buckets
  where id in ('avatars','checklists','multas','documentos','fuelings','logos','veiculos','documentos-fiscais')
),
-- 5) Não existe a política de leitura pública de storage --------------------
pubpol as (
  select 'Sem política public_read em storage.objects' as verificacao,
         case when not exists (
           select 1 from pg_policies
           where schemaname='storage' and tablename='objects'
             and policyname = 'public_read_frotacheck_buckets')
           then 'PASS' else '⚠ FALHA (leitura pública ligada)' end as resultado,
         'remover a policy public_read_frotacheck_buckets' as corrigir_com
),
-- 6) UPDATE/DELETE do MOTORISTA fechado em multas/pneus/documentos/alerts ----
ud as (
  select 'UPDATE/DELETE separado (não FOR ALL) em ' || t as verificacao,
         case when exists (
           select 1 from pg_policies
           where schemaname='public' and tablename=t and cmd in ('UPDATE','DELETE'))
           then 'PASS' else '⚠ FALHA (ainda é FOR ALL)' end as resultado,
         'MIGRATION_RESTRINGIR_UPDATE_DELETE_MOTORISTA.sql' as corrigir_com
  from (values ('multas'),('pneus'),('documentos'),('alerts')) v(t)
)
select * from rls
union all select * from orfas
union all select * from trg
union all select * from buckets
union all select * from pubpol
union all select * from ud
order by resultado desc, verificacao;
-- =============================================================================
-- Leia a coluna "resultado": se TODAS forem PASS, a produção está com todas
-- as proteções ativas. Qualquer "⚠ FALHA" → rode a migração da coluna ao lado.
-- =============================================================================

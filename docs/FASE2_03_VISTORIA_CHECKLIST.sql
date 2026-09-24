-- =============================================================================
-- FrotaCheck — Fase 2 (2026-09-24) — PASSO 3: VISTORIA NO CHECKLIST
--
-- Campos da ficha de vistoria dos clientes, gravados pelo checklist de
-- saída/retorno do app:
--   km_inicial        KM na saída (o retorno já tinha km_final)
--   nivel_combustivel Reserva | 1/4 | 1/2 | 3/4 | Cheio
--   avarias           por posição de foto:
--                     {"Frente": {"tipos": ["R","A"], "obs": "..."}, ...}
--                     R=Risco A=Amassado T=Trinca F=Falta/Quebra E=Outros
--   destino           texto livre (opcional)
--   finalidade        texto livre (opcional)
--
-- Só ADICIONA colunas (nada é removido ou alterado). Idempotente.
-- ⚠️ Rode ANTES de publicar o app com a vistoria nova — o app novo grava
-- nessas colunas e o checklist falharia sem elas.
-- =============================================================================

begin;

alter table public.checklists add column if not exists km_inicial        integer;
alter table public.checklists add column if not exists nivel_combustivel text;
alter table public.checklists add column if not exists avarias           jsonb not null default '{}'::jsonb;
alter table public.checklists add column if not exists destino           text;
alter table public.checklists add column if not exists finalidade        text;
-- observacoes já é usada pelo checklist de retorno; garante que existe.
alter table public.checklists add column if not exists observacoes       text;

alter table public.checklists drop constraint if exists checklists_nivel_combustivel_ck;
alter table public.checklists add constraint checklists_nivel_combustivel_ck
  check (nivel_combustivel is null or nivel_combustivel in ('Reserva','1/4','1/2','3/4','Cheio'));

alter table public.checklists drop constraint if exists checklists_km_inicial_ck;
alter table public.checklists add constraint checklists_km_inicial_ck
  check (km_inicial is null or km_inicial >= 0);

commit;

-- Verificação: deve listar as 6 colunas.
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'checklists'
  and column_name in ('km_inicial','nivel_combustivel','avarias','destino','finalidade','observacoes')
order by column_name;

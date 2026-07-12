-- =============================================================================
-- FrotaCheck — Feed de notificações (sino) + fix da coluna data_pagamento
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- O que este arquivo faz:
--   1. Corrige o bug de "Marcar como Paga" em multas (coluna ausente).
--   2. Cria a tabela public.notificacoes — feed interno de tudo que os
--      motoristas registram (abastecimento, manutenção, viagem, checklist,
--      ocorrência, multa), consumido pelo sino de Notificações no dashboard.
--   3. Reescreve notify_new_event() para: (a) gravar em notificacoes,
--      (b) continuar disparando o push existente — ambos protegidos contra
--      exceção, para nunca bloquear o INSERT original do motorista.
--   4. Move o gatilho de manutenção de oil_changes (satélite, sem custo)
--      para manutencoes (fonte real), e adiciona gatilhos em viagens/checklists.
-- =============================================================================

-- ── 1. Fix multas: coluna data_pagamento ausente ─────────────────────────────
alter table public.multas add column if not exists data_pagamento date;

-- ── 2. Tabela notificacoes ────────────────────────────────────────────────────
create table if not exists public.notificacoes (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid references public.empresas(id) on delete cascade,
  tipo        text not null,            -- nome da tabela de origem (TG_TABLE_NAME)
  titulo      text not null,
  corpo       text not null,
  vehicle_id  uuid references public.vehicles(id) on delete set null,
  driver_id   uuid references public.drivers(id) on delete set null,
  ref_id      uuid,                     -- id da linha de origem
  created_at  timestamptz not null default now()
);

create index if not exists idx_notificacoes_empresa_created
  on public.notificacoes(empresa_id, created_at desc);

alter table public.notificacoes enable row level security;

drop policy if exists "notificacoes_select" on public.notificacoes;
create policy "notificacoes_select" on public.notificacoes
  for select to authenticated
  using (
    get_my_role() = 'MASTER'
    or (empresa_id = get_my_empresa_id() and get_my_role() in ('ADMIN_EMPRESA','GESTOR'))
  );
-- Sem policy de INSERT/UPDATE/DELETE para authenticated de propósito —
-- só a função SECURITY DEFINER abaixo escreve nesta tabela.

-- Habilita Realtime nesta tabela (sem isso o sino só atualiza pelo polling).
do $$ begin
  alter publication supabase_realtime add table public.notificacoes;
exception when duplicate_object then null;
end $$;

-- Marcador de "última vez que o usuário viu as notificações" (por usuário).
alter table public.user_profiles
  add column if not exists notificacoes_lidas_em timestamptz;

-- ── 3. notify_new_event() reescrita ───────────────────────────────────────────
create or replace function public.notify_new_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  service_key  text;
  project_url  text := 'https://rseefinwtlrjhzosvmgt.supabase.co';
  row_data     jsonb := to_jsonb(NEW);
  v_empresa_id uuid;
  v_vehicle_id uuid;
  v_driver_id  uuid;
  v_titulo     text;
  v_corpo      text;
begin
  v_empresa_id := (row_data->>'empresa_id')::uuid;
  v_vehicle_id := coalesce((row_data->>'vehicle_id')::uuid, (row_data->>'veiculo_id')::uuid);
  v_driver_id  := coalesce((row_data->>'driver_id')::uuid, (row_data->>'motorista_id')::uuid);

  case TG_TABLE_NAME
    when 'fuelings' then
      v_titulo := 'Novo abastecimento registrado';
      v_corpo  := 'Abastecimento de R$ ' ||
                  to_char(coalesce((row_data->>'total_value')::numeric, 0), 'FM999999990.00') ||
                  ' registrado.';
    when 'manutencoes' then
      v_titulo := 'Manutenção registrada';
      v_corpo  := coalesce(row_data->>'tipo', 'Manutenção') || ' registrada.';
    when 'occurrences' then
      v_titulo := 'Nova ocorrência registrada';
      v_corpo  := 'Ocorrência: ' || coalesce(row_data->>'problem_type', 'novo problema') ||
                  ' — prioridade ' || coalesce(row_data->>'priority', 'não informada') || '.';
    when 'multas' then
      v_titulo := 'Nova multa registrada';
      v_corpo  := 'Multa: ' || coalesce(row_data->>'tipo', 'infração') || ' registrada.';
    when 'viagens' then
      v_titulo := 'Viagem iniciada';
      v_corpo  := 'De ' || coalesce(row_data->>'origem', '?') || ' para ' || coalesce(row_data->>'destino', '?') || '.';
    when 'checklists' then
      v_titulo := case when row_data->>'tipo' = 'retorno'
                    then 'Checklist de retorno registrado' else 'Checklist de saída registrado' end;
      v_corpo  := 'Checklist registrado.';
    else
      v_titulo := 'FrotaCheck';
      v_corpo  := 'Nova atividade registrada na sua frota.';
  end case;

  -- 1) Feed interno — nunca deixa uma falha aqui derrubar o INSERT original.
  begin
    insert into public.notificacoes (empresa_id, tipo, titulo, corpo, vehicle_id, driver_id, ref_id)
    values (v_empresa_id, TG_TABLE_NAME, v_titulo, v_corpo, v_vehicle_id, v_driver_id, (row_data->>'id')::uuid);
  exception when others then
    raise warning 'notify_new_event: falha ao gravar notificacoes (%): %', TG_TABLE_NAME, SQLERRM;
  end;

  -- 2) Push via pg_net — idem, nunca derruba o INSERT original.
  begin
    select decrypted_secret into service_key from vault.decrypted_secrets
      where name = 'service_role_key' limit 1;
    if service_key is not null then
      perform net.http_post(
        url := project_url || '/functions/v1/send-push-notification',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
        body := jsonb_build_object('table', TG_TABLE_NAME, 'record', row_data)
      );
    end if;
  exception when others then
    raise warning 'notify_new_event: falha ao chamar pg_net (%): %', TG_TABLE_NAME, SQLERRM;
  end;

  return NEW;
end;
$$;

-- ── 4. Gatilhos ────────────────────────────────────────────────────────────
drop trigger if exists trg_notify_new_fueling on public.fuelings;
create trigger trg_notify_new_fueling after insert on public.fuelings
  for each row execute function public.notify_new_event();

drop trigger if exists trg_notify_new_occurrence on public.occurrences;
create trigger trg_notify_new_occurrence after insert on public.occurrences
  for each row execute function public.notify_new_event();

drop trigger if exists trg_notify_new_multa on public.multas;
create trigger trg_notify_new_multa after insert on public.multas
  for each row execute function public.notify_new_event();

-- MOVE: sai da satélite oil_changes (sem custo), entra na fonte real manutencoes.
drop trigger if exists trg_notify_new_manutencao on public.oil_changes;
drop trigger if exists trg_notify_new_manutencao on public.manutencoes;
create trigger trg_notify_new_manutencao after insert on public.manutencoes
  for each row execute function public.notify_new_event();

drop trigger if exists trg_notify_new_viagem on public.viagens;
create trigger trg_notify_new_viagem after insert on public.viagens
  for each row execute function public.notify_new_event();

drop trigger if exists trg_notify_new_checklist on public.checklists;
create trigger trg_notify_new_checklist after insert on public.checklists
  for each row execute function public.notify_new_event();

do $$ begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'alerts') then
    execute 'drop trigger if exists trg_notify_new_alert on public.alerts';
    execute 'create trigger trg_notify_new_alert after insert on public.alerts for each row execute function public.notify_new_event()';
  end if;
end $$;

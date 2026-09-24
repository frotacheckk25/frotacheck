-- =============================================================================
-- FrotaCheck — Fase 2 (2026-09-24) — PASSO 2: ALERTAS AUTOMÁTICOS DE VENCIMENTO
--
-- Rode DEPOIS do FASE2_01. Resolve o achado A12 da auditoria: CNH vencendo,
-- documento vencendo e troca de óleo por km nunca geravam alerta sozinhos —
-- só eram calculados quando alguém abria a tela.
--
-- O que faz:
--   * Função gerar_alertas_vencimento(), que roda todo dia às 06:00 (Brasília)
--     via pg_cron e cria alertas em public.alerts:
--       - CNH vencendo (≤ 30 dias) e CNH vencida
--       - Documento vencendo (≤ 30 dias) e documento vencido
--       - Troca de óleo próxima (faltando ≤ 500 km) e troca de óleo vencida
--   * Cada alerta tem uma "chave" única: nunca é criado em duplicidade e, se
--     o gestor marcar como resolvido, não volta no dia seguinte.
--   * Alertas que deixaram de valer (CNH renovada, nova troca de óleo
--     registrada, documento atualizado) são resolvidos automaticamente.
--   * Cada alerta novo gera notificação no sino + push para admin/gestor
--     (gatilho já existente em public.alerts).
-- =============================================================================

begin;

alter table public.alerts add column if not exists chave text;

create unique index if not exists alerts_empresa_chave_uk
  on public.alerts (empresa_id, chave)
  where chave is not null;

create or replace function public.gerar_alertas_vencimento()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v_inseridos integer := 0;
  v_n integer;
begin
  create temporary table if not exists _alertas_atuais (
    empresa_id uuid, chave text, titulo text, descricao text, tipo text, vehicle_id uuid
  ) on commit drop;
  truncate _alertas_atuais;

  -- CNH ───────────────────────────────────────────────────────────────────────
  insert into _alertas_atuais
  select d.empresa_id,
         case when d.cnh_expiration < current_date then 'cnh-vencida:' else 'cnh-vencendo:' end
           || d.id || ':' || d.cnh_expiration,
         case when d.cnh_expiration < current_date then 'CNH vencida: ' else 'CNH vencendo: ' end
           || coalesce(d.name, 'Motorista'),
         'Validade: ' || to_char(d.cnh_expiration, 'DD/MM/YYYY'),
         case when d.cnh_expiration < current_date then 'error' else 'warning' end,
         (select v.id from public.vehicles v where v.driver_id = d.id limit 1)
  from public.drivers d
  where d.cnh_expiration is not null
    and d.cnh_expiration <= current_date + 30;

  -- Documentos ────────────────────────────────────────────────────────────────
  insert into _alertas_atuais
  select doc.empresa_id,
         case when doc.data_vencimento < current_date then 'doc-vencido:' else 'doc-vencendo:' end
           || doc.id || ':' || doc.data_vencimento,
         case when doc.data_vencimento < current_date then 'Documento vencido: ' else 'Documento vencendo: ' end
           || coalesce(doc.tipo, 'Documento'),
         coalesce(nullif(doc.descricao, '') || ' — ', '') || 'Vencimento: ' || to_char(doc.data_vencimento, 'DD/MM/YYYY'),
         case when doc.data_vencimento < current_date then 'error' else 'warning' end,
         doc.vehicle_id
  from public.documentos doc
  where doc.data_vencimento is not null
    and coalesce(doc.ativo, true)
    and doc.data_vencimento <= current_date + 30;

  -- Troca de óleo (última troca registrada de cada veículo) ─────────────────
  insert into _alertas_atuais
  select v.empresa_id,
         case when v.odometer >= o.next_change_km then 'oleo-vencida:' else 'oleo-proxima:' end
           || v.id || ':' || o.next_change_km,
         case when v.odometer >= o.next_change_km then 'Troca de óleo vencida: ' else 'Troca de óleo próxima: ' end
           || coalesce(v.plate, 'veículo'),
         'Próxima troca em ' || o.next_change_km || ' km — hodômetro atual ' || coalesce(v.odometer, 0) || ' km',
         case when v.odometer >= o.next_change_km then 'error' else 'warning' end,
         v.id
  from public.vehicles v
  join lateral (
    select oc.next_change_km
    from public.oil_changes oc
    where oc.vehicle_id = v.id and oc.next_change_km is not null
    order by oc.oil_change_date desc nulls last, oc.created_at desc
    limit 1
  ) o on true
  where v.odometer is not null
    and v.odometer >= o.next_change_km - 500;

  -- Cria os que ainda não existem (a chave impede duplicidade) ─────────────
  insert into public.alerts (empresa_id, chave, title, description, tipo, status, vehicle_id)
  select a.empresa_id, a.chave, a.titulo, a.descricao, a.tipo, 'ativo', a.vehicle_id
  from _alertas_atuais a
  where a.empresa_id is not null
  on conflict (empresa_id, chave) where chave is not null do nothing;
  get diagnostics v_inseridos = row_count;

  -- Resolve automaticamente os que deixaram de valer ───────────────────────
  update public.alerts al
     set status = 'resolvido'
   where al.status = 'ativo'
     and al.chave is not null
     and split_part(al.chave, ':', 1) in ('cnh-vencendo','cnh-vencida','doc-vencendo',
                                          'doc-vencido','oleo-proxima','oleo-vencida')
     and not exists (select 1 from _alertas_atuais a
                     where a.empresa_id = al.empresa_id and a.chave = al.chave);
  get diagnostics v_n = row_count;

  raise notice 'gerar_alertas_vencimento: % novos, % resolvidos automaticamente', v_inseridos, v_n;
  return v_inseridos;
end;
$$;

revoke execute on function public.gerar_alertas_vencimento() from public, anon, authenticated;

-- Texto do sino de notificações para alertas (antes caía no genérico
-- "Nova atividade registrada na sua frota").
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

  if v_driver_id is null and v_vehicle_id is not null then
    select driver_id into v_driver_id from public.vehicles where id = v_vehicle_id;
  end if;

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
    when 'alerts' then
      v_titulo := coalesce(row_data->>'title', row_data->>'titulo', 'Novo alerta');
      v_corpo  := coalesce(row_data->>'description', row_data->>'descricao', 'Um novo alerta foi gerado para sua frota.');
    else
      v_titulo := 'FrotaCheck';
      v_corpo  := 'Nova atividade registrada na sua frota.';
  end case;

  begin
    insert into public.notificacoes (empresa_id, tipo, titulo, corpo, vehicle_id, driver_id, ref_id)
    values (v_empresa_id, TG_TABLE_NAME, v_titulo, v_corpo, v_vehicle_id, v_driver_id, (row_data->>'id')::uuid);
  exception when others then
    raise warning 'notify_new_event: falha ao gravar notificacoes (%): %', TG_TABLE_NAME, SQLERRM;
  end;

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

revoke execute on function public.notify_new_event() from public, anon;

commit;

-- ── Agendamento diário (pg_cron) ───────────────────────────────────────────
-- Se der erro "extension pg_cron is not available", habilite em
-- Dashboard → Database → Extensions → pg_cron e rode este bloco de novo.
create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job where jobname = 'frotacheck-alertas-vencimento';
select cron.schedule('frotacheck-alertas-vencimento', '0 9 * * *',  -- 09:00 UTC = 06:00 Brasília
                     'select public.gerar_alertas_vencimento()');

-- Primeira execução agora. O push fica desligado SÓ nesta carga inicial, para
-- os gestores não receberem dezenas de notificações de vencimentos antigos de
-- uma vez — os alertas aparecem normalmente na tela de Alertas e no dashboard.
alter table public.alerts disable trigger trg_notify_new_alert;
select public.gerar_alertas_vencimento() as alertas_criados;
alter table public.alerts enable trigger trg_notify_new_alert;

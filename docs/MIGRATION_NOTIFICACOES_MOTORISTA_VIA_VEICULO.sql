-- =============================================================================
-- FrotaCheck — Notificações sempre com veículo (placa/modelo) e motorista
--
-- Contexto: manutencoes e alerts não têm coluna de motorista própria (só
-- vehicle_id) — então notificacoes.driver_id sempre ficava NULL para esses
-- dois tipos, e o gestor/admin não via QUEM estava associado ao veículo.
-- Fix: se a linha de origem não trouxe driver_id/motorista_id direto, resolve
-- via vehicles.driver_id (o motorista atualmente atribuído ao veículo).
-- Não afeta as tabelas que já trazem driver_id/motorista_id direto
-- (fuelings/occurrences/multas/viagens/checklists) — o fallback só roda
-- quando v_driver_id ainda está NULL.
-- =============================================================================

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

  -- Fallback: tabelas sem coluna de motorista própria (manutencoes, alerts)
  -- usam o motorista atualmente atribuído ao veículo.
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

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

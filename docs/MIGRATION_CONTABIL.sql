-- =============================================================================
-- CONTABILIDADE — fechamento do mês e pacote do contador (2026-10-27)
--
-- contabil_config    : dados do contador e plano de contas (códigos da conta
--                      de caixa/bancos, das receitas e de cada categoria de
--                      despesa) usados para montar os lançamentos contábeis
-- periodos_fechados  : meses fechados. Mês fechado não aceita baixa, estorno
--                      ou alteração de conta paga/recebida com data nele, nem
--                      movimento de estoque ou recebimento de compra datado
--                      nele — o que foi entregue ao contador não muda depois.
-- contabil_eventos   : quem fechou, reabriu (com motivo) ou gerou o pacote
-- bucket pacotes-contabeis : ZIP do mês, com link temporário para o contador
--
-- Fechar, reabrir e configurar: MASTER e ADMIN_EMPRESA (ou quem tiver
-- manageAccounting liberada no perfil — a mesma regra do app). Leitura e
-- geração do pacote: MASTER, ADMIN_EMPRESA e GESTOR. Idempotente.
-- =============================================================================

create table if not exists public.contabil_config (
  empresa_id             uuid primary key references public.empresas(id) on delete cascade,
  contador_nome          text,
  contador_escritorio    text,
  contador_crc           text,
  contador_email         text,
  contador_whatsapp      text,
  conta_caixa            text,
  conta_receita_frete    text,
  conta_outras_receitas  text,
  contas_categoria       jsonb not null default '{}'::jsonb check (jsonb_typeof(contas_categoria) = 'object'),
  updated_at             timestamptz not null default now(),
  updated_by             uuid default auth.uid()
);

create table if not exists public.periodos_fechados (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas(id) on delete cascade,
  competencia       date not null check (extract(day from competencia) = 1),
  fechado_em        timestamptz not null default now(),
  fechado_por       uuid default auth.uid(),
  fechado_por_nome  text,
  observacoes       text,
  unique (empresa_id, competencia)
);

create table if not exists public.contabil_eventos (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id) on delete cascade,
  competencia   date not null,
  acao          text not null check (acao in ('fechado', 'reaberto', 'pacote')),
  detalhe       text,
  usuario_id    uuid default auth.uid(),
  usuario_nome  text,
  created_at    timestamptz not null default now()
);
create index if not exists contabil_eventos_empresa_idx on public.contabil_eventos (empresa_id, competencia, created_at desc);

-- ── Apoio ───────────────────────────────────────────────────────────────────
create or replace function public.mes_fechado(p_empresa uuid, p_data date)
returns boolean language sql stable security definer set search_path = public as $$
  select p_data is not null and exists (
    select 1 from public.periodos_fechados
     where empresa_id = p_empresa and competencia = date_trunc('month', p_data)::date);
$$;
revoke execute on function public.mes_fechado(uuid, date) from public, anon;
grant execute on function public.mes_fechado(uuid, date) to authenticated;

-- Mesma regra do app (UserProfile.can): MASTER sempre; senão vale o que
-- estiver marcado no perfil; senão o padrão do papel (só ADMIN_EMPRESA).
create or replace function public.pode_gerir_contabil()
returns boolean language sql stable security definer set search_path = public as $$
  select public.comercial_pode_escrever() and coalesce((
    select case
      when up.role = 'MASTER' then true
      when jsonb_typeof(up.permissions -> 'manageAccounting') = 'boolean' then (up.permissions ->> 'manageAccounting')::boolean
      else up.role = 'ADMIN_EMPRESA'
    end
    from public.user_profiles up
    where up.user_id = auth.uid() and up.status = 'ativo'
    limit 1
  ), false);
$$;
revoke execute on function public.pode_gerir_contabil() from public, anon;
grant execute on function public.pode_gerir_contabil() to authenticated;

create or replace function public.contabil_config_antes_gravar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' then new.empresa_id := old.empresa_id; end if;
  return new;
end;
$$;
drop trigger if exists contabil_config_antes_gravar on public.contabil_config;
create trigger contabil_config_antes_gravar before insert or update on public.contabil_config
  for each row execute function public.contabil_config_antes_gravar();

-- ── Fechar, reabrir e registrar o pacote ────────────────────────────────────
create or replace function public.fechar_mes_contabil(p_empresa uuid, p_competencia date, p_observacoes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_obs  text := nullif(trim(coalesce(p_observacoes, '')), '');
  v_nome text := public.compras_nome_usuario();
begin
  if not public.pode_gerir_contabil() then raise exception 'Só o administrador da empresa pode fechar o mês'; end if;
  if p_empresa is null or (p_empresa is distinct from public.get_my_empresa_id() and coalesce(public.get_my_role(), '') <> 'MASTER') then
    raise exception 'Empresa inválida';
  end if;
  if v_comp is null or v_comp >= date_trunc('month', (now() at time zone 'America/Sao_Paulo'))::date then
    raise exception 'Só dá para fechar um mês que já terminou';
  end if;
  if exists (select 1 from public.periodos_fechados where empresa_id = p_empresa and competencia = v_comp) then
    raise exception 'O mês % já está fechado', to_char(v_comp, 'MM/YYYY');
  end if;
  insert into public.periodos_fechados (empresa_id, competencia, fechado_por_nome, observacoes)
  values (p_empresa, v_comp, v_nome, v_obs);
  insert into public.contabil_eventos (empresa_id, competencia, acao, detalhe, usuario_nome)
  values (p_empresa, v_comp, 'fechado', v_obs, v_nome);
end;
$$;

create or replace function public.reabrir_mes_contabil(p_empresa uuid, p_competencia date, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare v_comp date := date_trunc('month', p_competencia)::date;
begin
  if not public.pode_gerir_contabil() then raise exception 'Só o administrador da empresa pode reabrir o mês'; end if;
  if p_empresa is null or (p_empresa is distinct from public.get_my_empresa_id() and coalesce(public.get_my_role(), '') <> 'MASTER') then
    raise exception 'Empresa inválida';
  end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo da reabertura'; end if;
  delete from public.periodos_fechados where empresa_id = p_empresa and competencia = v_comp;
  if not found then raise exception 'O mês % não está fechado', to_char(v_comp, 'MM/YYYY'); end if;
  insert into public.contabil_eventos (empresa_id, competencia, acao, detalhe, usuario_nome)
  values (p_empresa, v_comp, 'reaberto', trim(p_motivo), public.compras_nome_usuario());
end;
$$;

create or replace function public.registrar_pacote_contabil(p_empresa uuid, p_competencia date, p_detalhe text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.comercial_pode_escrever() then raise exception 'Sem permissão'; end if;
  if p_empresa is null or (p_empresa is distinct from public.get_my_empresa_id() and coalesce(public.get_my_role(), '') <> 'MASTER') then
    raise exception 'Empresa inválida';
  end if;
  insert into public.contabil_eventos (empresa_id, competencia, acao, detalhe, usuario_nome)
  values (p_empresa, date_trunc('month', p_competencia)::date, 'pacote', left(nullif(trim(coalesce(p_detalhe, '')), ''), 500), public.compras_nome_usuario());
end;
$$;

revoke execute on function public.fechar_mes_contabil(uuid, date, text) from public, anon;
revoke execute on function public.reabrir_mes_contabil(uuid, date, text) from public, anon;
revoke execute on function public.registrar_pacote_contabil(uuid, date, text) from public, anon;
grant execute on function public.fechar_mes_contabil(uuid, date, text) to authenticated;
grant execute on function public.reabrir_mes_contabil(uuid, date, text) to authenticated;
grant execute on function public.registrar_pacote_contabil(uuid, date, text) to authenticated;

-- ── Trava do mês fechado ────────────────────────────────────────────────────
-- Contas a pagar/receber: a baixa (data do pagamento/recebimento) de um mês
-- fechado não muda, não é estornada nem apagada; e não entra baixa nova com
-- data num mês fechado.
create or replace function public.contabil_trava_baixas()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_baixa    text := case when tg_table_name = 'contas_pagar' then 'paga' else 'recebida' end;
  v_campo    text := case when tg_table_name = 'contas_pagar' then 'data_pagamento' else 'data_recebimento' end;
  v_old      jsonb;
  v_new      jsonb;
  v_empresa  uuid;
  v_data_old date;
  v_data_new date;
begin
  -- cascatas internas ("set null" de fornecedor, cliente ou OS apagados)
  if pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  v_empresa := coalesce((v_new ->> 'empresa_id')::uuid, (v_old ->> 'empresa_id')::uuid);
  v_data_old := (v_old ->> v_campo)::date;
  v_data_new := (v_new ->> v_campo)::date;

  if v_old ->> 'status' = v_baixa and public.mes_fechado(v_empresa, v_data_old)
     and (v_new is null or (v_new - 'updated_at') is distinct from (v_old - 'updated_at')) then
    raise exception 'O mês % está fechado na contabilidade: esta baixa não pode mudar. Peça ao administrador para reabrir o mês.',
      to_char(v_data_old, 'MM/YYYY');
  end if;
  if v_new ->> 'status' = v_baixa and public.mes_fechado(v_empresa, v_data_new)
     and (v_old is null or v_old ->> 'status' is distinct from v_baixa or v_data_old is distinct from v_data_new) then
    raise exception 'O mês % está fechado na contabilidade: não dá para lançar baixa com essa data.',
      to_char(v_data_new, 'MM/YYYY');
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists contas_pagar_trava_contabil on public.contas_pagar;
create trigger contas_pagar_trava_contabil before insert or update or delete on public.contas_pagar
  for each row execute function public.contabil_trava_baixas();
drop trigger if exists contas_receber_trava_contabil on public.contas_receber;
create trigger contas_receber_trava_contabil before insert or update or delete on public.contas_receber
  for each row execute function public.contabil_trava_baixas();

-- Estoque e recebimento de compras: nada novo com data num mês fechado
create or replace function public.contabil_trava_data()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.mes_fechado(new.empresa_id, new.data) then
    raise exception 'O mês % está fechado na contabilidade: não dá para lançar com essa data. Peça ao administrador para reabrir o mês.',
      to_char(new.data, 'MM/YYYY');
  end if;
  return new;
end;
$$;
drop trigger if exists estoque_movimentos_trava_contabil on public.estoque_movimentos;
create trigger estoque_movimentos_trava_contabil before insert on public.estoque_movimentos
  for each row execute function public.contabil_trava_data();
drop trigger if exists compra_recebimentos_trava_contabil on public.compra_recebimentos;
create trigger compra_recebimentos_trava_contabil before insert on public.compra_recebimentos
  for each row execute function public.contabil_trava_data();

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.contabil_config   enable row level security;
alter table public.periodos_fechados enable row level security;
alter table public.contabil_eventos  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['contabil_config', 'periodos_fechados', 'contabil_eventos'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($p$create policy %I on public.%I for select to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_select', t);
  end loop;
end $$;
-- configuração: só quem gere a contabilidade grava; meses e eventos só pelas funções
create policy "contabil_config_insert" on public.contabil_config for insert to authenticated
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.pode_gerir_contabil());
create policy "contabil_config_update" on public.contabil_config for update to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.pode_gerir_contabil())
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.pode_gerir_contabil());

grant select, insert, update on public.contabil_config to authenticated;
grant select on public.periodos_fechados, public.contabil_eventos to authenticated;
revoke all on public.contabil_config, public.periodos_fechados, public.contabil_eventos from anon;

-- ── Bucket do pacote do contador (pasta = empresa) ──────────────────────────
insert into storage.buckets (id, name, public)
values ('pacotes-contabeis', 'pacotes-contabeis', false)
on conflict (id) do nothing;

drop policy if exists "pacotes_contabeis_ler" on storage.objects;
drop policy if exists "pacotes_contabeis_gravar" on storage.objects;
drop policy if exists "pacotes_contabeis_atualizar" on storage.objects;
create policy "pacotes_contabeis_ler" on storage.objects for select to authenticated
  using (bucket_id = 'pacotes-contabeis' and (
    (select public.get_my_role()) = 'MASTER'
    or ((storage.foldername(name))[1] = (select public.get_my_empresa_id())::text
        and (select public.get_my_role()) in ('ADMIN_EMPRESA', 'GESTOR'))));
create policy "pacotes_contabeis_gravar" on storage.objects for insert to authenticated
  with check (bucket_id = 'pacotes-contabeis' and (
    (select public.get_my_role()) = 'MASTER'
    or ((storage.foldername(name))[1] = (select public.get_my_empresa_id())::text
        and (select public.get_my_role()) in ('ADMIN_EMPRESA', 'GESTOR'))));
create policy "pacotes_contabeis_atualizar" on storage.objects for update to authenticated
  using (bucket_id = 'pacotes-contabeis' and (
    (select public.get_my_role()) = 'MASTER'
    or ((storage.foldername(name))[1] = (select public.get_my_empresa_id())::text
        and (select public.get_my_role()) in ('ADMIN_EMPRESA', 'GESTOR'))))
  with check (bucket_id = 'pacotes-contabeis' and (
    (select public.get_my_role()) = 'MASTER'
    or ((storage.foldername(name))[1] = (select public.get_my_empresa_id())::text
        and (select public.get_my_role()) in ('ADMIN_EMPRESA', 'GESTOR'))));

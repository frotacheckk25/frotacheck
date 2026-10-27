-- =============================================================================
-- MANUTENÇÃO COMPLETA — ordens de serviço e plano preventivo (2026-10-27)
--
-- ordens_servico        : OS preventiva/corretiva com número por empresa,
--                         veículo, km, oficina e etapas (aberta → em execução
--                         → concluída / cancelada)
-- ordem_servico_itens   : peças e serviços da OS (quantidade × valor); o
--                         total da OS é recalculado no banco
-- plano_preventivo      : itens de manutenção preventiva por veículo, com
--                         intervalo em km e/ou dias e a última realização
--
-- Ao CONCLUIR uma OS o banco:
--   * grava o custo em public.manutencoes (os relatórios e históricos que já
--     existem passam a contar a OS sem mudar nada neles);
--   * atualiza a última realização do item do plano ligado à OS.
-- OS concluída ou cancelada não muda mais (nem os itens).
--
-- Acesso: MASTER, ADMIN_EMPRESA e GESTOR (motorista continua registrando
-- problemas em Ocorrências). Idempotente.
-- =============================================================================

-- ── Plano preventivo ────────────────────────────────────────────────────────
create table if not exists public.plano_preventivo (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  vehicle_id      uuid not null references public.vehicles(id) on delete cascade,
  nome            text not null check (length(trim(nome)) between 2 and 80),
  intervalo_km    integer check (intervalo_km is null or intervalo_km between 100 and 1000000),
  intervalo_dias  integer check (intervalo_dias is null or intervalo_dias between 1 and 3650),
  ultima_km       integer check (ultima_km is null or ultima_km between 0 and 3000000),
  ultima_data     date,
  ativo           boolean not null default true,
  observacoes     text,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (intervalo_km is not null or intervalo_dias is not null)
);
create index if not exists plano_preventivo_veiculo_idx on public.plano_preventivo (empresa_id, vehicle_id);

-- ── Ordens de serviço ───────────────────────────────────────────────────────
create table if not exists public.ordens_servico (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  numero           integer,
  vehicle_id       uuid references public.vehicles(id) on delete set null,
  tipo             text not null default 'corretiva' check (tipo in ('preventiva', 'corretiva')),
  descricao        text not null check (length(trim(descricao)) >= 3),
  km               integer check (km is null or km between 0 and 3000000),
  oficina          text,
  oficina_tipo     text not null default 'externa' check (oficina_tipo in ('interna', 'externa')),
  status           text not null default 'aberta' check (status in ('aberta', 'em_execucao', 'concluida', 'cancelada')),
  data_abertura    date not null default current_date,
  data_conclusao   date,
  valor_total      numeric(14,2) not null default 0,
  plano_item_id    uuid references public.plano_preventivo(id) on delete set null,
  manutencao_id    uuid references public.manutencoes(id) on delete set null,
  observacoes      text,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (empresa_id, numero),
  check (data_conclusao is null or data_conclusao >= data_abertura)
);
create index if not exists ordens_servico_empresa_idx on public.ordens_servico (empresa_id, status, data_abertura desc);
create index if not exists ordens_servico_veiculo_idx on public.ordens_servico (vehicle_id);

create table if not exists public.ordem_servico_itens (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  os_id            uuid not null references public.ordens_servico(id) on delete cascade,
  tipo             text not null default 'peca' check (tipo in ('peca', 'servico')),
  descricao        text not null check (length(trim(descricao)) >= 2),
  quantidade       numeric(10,2) not null default 1 check (quantidade > 0 and quantidade <= 100000),
  valor_unitario   numeric(14,2) not null default 0 check (valor_unitario >= 0 and valor_unitario <= 10000000),
  created_at       timestamptz not null default now()
);
create index if not exists ordem_servico_itens_os_idx on public.ordem_servico_itens (os_id);

-- ── Gatilhos ────────────────────────────────────────────────────────────────
create or replace function public.plano_preventivo_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then new.empresa_id := old.empresa_id; end if;
  if not public.mesma_empresa('vehicles', new.vehicle_id, new.empresa_id) then
    raise exception 'Veículo não pertence a esta empresa';
  end if;
  return new;
end;
$$;
drop trigger if exists plano_preventivo_antes_gravar on public.plano_preventivo;
create trigger plano_preventivo_antes_gravar before insert or update on public.plano_preventivo
  for each row execute function public.plano_preventivo_antes_gravar();

create or replace function public.os_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.numero := public.comercial_proximo_numero('ordens_servico', new.empresa_id);
    new.valor_total := 0;
    new.manutencao_id := null;
    if new.status in ('concluida', 'cancelada') then
      raise exception 'A OS começa aberta';
    end if;
  else
    -- Atualizações internas do banco (total vindo dos itens, ligação com
    -- manutencoes ao concluir, "set null" quando um veículo/item do plano é
    -- apagado) chegam em profundidade > 1 e passam direto.
    if pg_trigger_depth() > 1 then return new; end if;
    -- Edição feita pelo app:
    new.numero := old.numero;
    new.empresa_id := old.empresa_id;
    new.manutencao_id := old.manutencao_id;
    new.valor_total := old.valor_total;  -- o total vem só da soma dos itens
    if old.status in ('concluida', 'cancelada') then
      raise exception 'OS % já está %', old.numero, case old.status when 'concluida' then 'concluída' else 'cancelada' end;
    end if;
  end if;
  if not public.mesma_empresa('vehicles', new.vehicle_id, new.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
  if not public.mesma_empresa('plano_preventivo', new.plano_item_id, new.empresa_id) then raise exception 'Item do plano não pertence a esta empresa'; end if;
  if new.status = 'concluida' then
    if new.vehicle_id is null then raise exception 'Informe o veículo antes de concluir a OS'; end if;
    new.data_conclusao := coalesce(new.data_conclusao, current_date);
  end if;
  return new;
end;
$$;
drop trigger if exists os_antes_gravar on public.ordens_servico;
create trigger os_antes_gravar before insert or update on public.ordens_servico
  for each row execute function public.os_antes_gravar();

-- Conclusão: lança o custo em manutencoes e atualiza o plano preventivo
create or replace function public.os_depois_concluir()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_manut uuid;
begin
  if new.status = 'concluida' and old.status is distinct from 'concluida' then
    insert into public.manutencoes (vehicle_id, tipo, descricao, data, cost, valor, status, oficina, empresa_id, peca_trocada)
    values (
      new.vehicle_id,
      'OS nº ' || new.numero || case new.tipo when 'preventiva' then ' (preventiva)' else ' (corretiva)' end,
      new.descricao,
      new.data_conclusao,
      new.valor_total,
      new.valor_total,
      'Resolvido',
      new.oficina,
      new.empresa_id,
      (select string_agg(i.descricao, ', ' order by i.created_at) from public.ordem_servico_itens i where i.os_id = new.id and i.tipo = 'peca')
    )
    returning id into v_manut;
    update public.ordens_servico set manutencao_id = v_manut where id = new.id;
    if new.plano_item_id is not null then
      update public.plano_preventivo
         set ultima_km = coalesce(new.km, ultima_km), ultima_data = new.data_conclusao
       where id = new.plano_item_id;
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists os_depois_concluir on public.ordens_servico;
create trigger os_depois_concluir after update of status on public.ordens_servico
  for each row execute function public.os_depois_concluir();

-- Itens: mesma empresa da OS, só em OS aberta/em execução, total recalculado
create or replace function public.os_itens_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_os record;
begin
  select id, empresa_id, status into v_os from public.ordens_servico
   where id = case when tg_op = 'DELETE' then old.os_id else new.os_id end;
  -- exclusão em cascata (OS/empresa apagada pelo banco) não é bloqueada
  if tg_op = 'DELETE' and (pg_trigger_depth() > 1 or v_os.id is null) then return old; end if;
  if v_os.id is null then raise exception 'OS não encontrada'; end if;
  if v_os.status not in ('aberta', 'em_execucao') then raise exception 'OS concluída ou cancelada não pode mudar'; end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_op = 'UPDATE' and new.os_id <> old.os_id then raise exception 'Item não pode mudar de OS'; end if;
  new.empresa_id := v_os.empresa_id;
  return new;
end;
$$;
drop trigger if exists os_itens_antes_gravar on public.ordem_servico_itens;
create trigger os_itens_antes_gravar before insert or update or delete on public.ordem_servico_itens
  for each row execute function public.os_itens_antes_gravar();

create or replace function public.os_itens_recalcular()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_os uuid := case when tg_op = 'DELETE' then old.os_id else new.os_id end;
begin
  update public.ordens_servico
     set valor_total = coalesce((select sum(round(quantidade * valor_unitario, 2)) from public.ordem_servico_itens where os_id = v_os), 0)
   where id = v_os;
  return null;
end;
$$;
drop trigger if exists os_itens_recalcular on public.ordem_servico_itens;
create trigger os_itens_recalcular after insert or update or delete on public.ordem_servico_itens
  for each row execute function public.os_itens_recalcular();

-- ── RLS (MASTER, ADMIN_EMPRESA, GESTOR) ─────────────────────────────────────
alter table public.plano_preventivo    enable row level security;
alter table public.ordens_servico      enable row level security;
alter table public.ordem_servico_itens enable row level security;

do $$
declare t text;
begin
  foreach t in array array['plano_preventivo', 'ordens_servico', 'ordem_servico_itens'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($p$create policy %I on public.%I for select to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_select', t);
    execute format($p$create policy %I on public.%I for insert to authenticated
      with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_insert', t);
    execute format($p$create policy %I on public.%I for update to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())
      with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_update', t);
  end loop;
end $$;

-- Exclusão: itens da OS (enquanto aberta) e itens do plano; OS não se apaga (cancela)
drop policy if exists "ordem_servico_itens_delete" on public.ordem_servico_itens;
drop policy if exists "plano_preventivo_delete" on public.plano_preventivo;
create policy "ordem_servico_itens_delete" on public.ordem_servico_itens for delete to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
create policy "plano_preventivo_delete" on public.plano_preventivo for delete to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());

grant select, insert, update on public.plano_preventivo, public.ordens_servico, public.ordem_servico_itens to authenticated;
grant delete on public.plano_preventivo, public.ordem_servico_itens to authenticated;
revoke all on public.plano_preventivo, public.ordens_servico, public.ordem_servico_itens from anon;

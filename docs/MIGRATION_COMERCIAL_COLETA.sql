-- =============================================================================
-- MÓDULO COMERCIAL + COLETA (2026-10-27)
-- Clientes, cotações de frete e ordens de coleta.
-- Fluxo: cliente → cotação (aberta/aprovada/recusada) → coleta programada →
-- coletada → viagem (tabela viagens já existente).
--
-- Segurança no mesmo padrão das demais tabelas:
--   * RLS por empresa (get_my_empresa_id) ou MASTER;
--   * escrita só para MASTER, ADMIN_EMPRESA e GESTOR (motorista não acessa);
--   * gatilho impede apontar para cliente/veículo/motorista/viagem de outra
--     empresa (FK sozinha não garante isso);
--   * número sequencial por empresa, gerado no banco.
-- Idempotente: pode rodar mais de uma vez.
-- =============================================================================

create or replace function public.comercial_pode_escrever()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.get_my_role() in ('MASTER', 'ADMIN_EMPRESA', 'GESTOR'), false);
$$;

-- ── Clientes ────────────────────────────────────────────────────────────────
create table if not exists public.clientes (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id) on delete cascade,
  tipo         text not null default 'PJ' check (tipo in ('PJ', 'PF')),
  nome         text not null check (length(trim(nome)) between 2 and 160),
  documento    text check (documento is null or documento ~ '^[0-9]{11}$|^[0-9]{14}$'),
  ie           text,
  contato      text,
  telefone     text,
  email        text,
  endereco     text,
  cidade       text,
  uf           text check (uf is null or uf ~ '^[A-Z]{2}$'),
  observacoes  text,
  ativo        boolean not null default true,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists clientes_empresa_documento_uq
  on public.clientes (empresa_id, documento) where documento is not null;
create index if not exists clientes_empresa_nome_idx on public.clientes (empresa_id, nome);

-- ── Cotações ────────────────────────────────────────────────────────────────
create table if not exists public.cotacoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  numero          integer,
  cliente_id      uuid not null references public.clientes(id) on delete restrict,
  origem_cidade   text not null,
  origem_uf       text not null check (origem_uf ~ '^[A-Z]{2}$'),
  destino_cidade  text not null,
  destino_uf      text not null check (destino_uf ~ '^[A-Z]{2}$'),
  natureza_carga  text,
  peso_kg         numeric(12,2) check (peso_kg is null or peso_kg >= 0),
  valor_carga     numeric(14,2) check (valor_carga is null or valor_carga >= 0),
  valor_frete     numeric(14,2) not null check (valor_frete >= 0),
  validade        date,
  status          text not null default 'aberta' check (status in ('aberta', 'aprovada', 'recusada', 'cancelada')),
  motivo_recusa   text,
  observacoes     text,
  coleta_id       uuid,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (empresa_id, numero)
);
create index if not exists cotacoes_empresa_status_idx on public.cotacoes (empresa_id, status, created_at desc);

-- ── Coletas ─────────────────────────────────────────────────────────────────
create table if not exists public.coletas (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  numero           integer,
  cliente_id       uuid not null references public.clientes(id) on delete restrict,
  cotacao_id       uuid references public.cotacoes(id) on delete set null,
  endereco_coleta  text not null,
  cidade           text not null,
  uf               text not null check (uf ~ '^[A-Z]{2}$'),
  destino_cidade   text,
  destino_uf       text check (destino_uf is null or destino_uf ~ '^[A-Z]{2}$'),
  data_programada  date not null,
  hora_inicio      time,
  hora_fim         time,
  contato          text,
  telefone         text,
  natureza_carga   text,
  peso_kg          numeric(12,2) check (peso_kg is null or peso_kg >= 0),
  volumes          integer check (volumes is null or volumes >= 0),
  valor_carga      numeric(14,2) check (valor_carga is null or valor_carga >= 0),
  valor_frete      numeric(14,2) check (valor_frete is null or valor_frete >= 0),
  veiculo_id       uuid references public.vehicles(id) on delete set null,
  motorista_id     uuid references public.drivers(id) on delete set null,
  viagem_id        uuid references public.viagens(id) on delete set null,
  status           text not null default 'programada' check (status in ('programada', 'em_rota', 'coletada', 'cancelada')),
  coletada_em      timestamptz,
  observacoes      text,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (empresa_id, numero),
  check (hora_fim is null or hora_inicio is null or hora_fim >= hora_inicio)
);
create index if not exists coletas_empresa_data_idx on public.coletas (empresa_id, data_programada, status);

do $$ begin
  alter table public.cotacoes
    add constraint cotacoes_coleta_fk foreign key (coleta_id) references public.coletas(id) on delete set null;
exception when duplicate_object then null; end $$;

-- ── Gatilhos: número sequencial por empresa, updated_at e mesma empresa ─────
create or replace function public.comercial_proximo_numero(p_tabela text, p_empresa uuid)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtext(p_tabela || p_empresa::text));
  execute format('select coalesce(max(numero), 0) + 1 from public.%I where empresa_id = $1', p_tabela)
    into n using p_empresa;
  return n;
end;
$$;

create or replace function public.mesma_empresa(p_tabela text, p_id uuid, p_empresa uuid)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
declare ok boolean;
begin
  if p_id is null then return true; end if;
  execute format('select exists (select 1 from public.%I where id = $1 and empresa_id = $2)', p_tabela)
    into ok using p_id, p_empresa;
  return ok;
end;
$$;

create or replace function public.clientes_antes_gravar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then new.empresa_id := old.empresa_id; end if;
  return new;
end;
$$;

create or replace function public.cotacoes_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.numero := public.comercial_proximo_numero('cotacoes', new.empresa_id);
  else
    new.numero := old.numero; new.empresa_id := old.empresa_id;
  end if;
  if not public.mesma_empresa('clientes', new.cliente_id, new.empresa_id) then raise exception 'Cliente não pertence a esta empresa'; end if;
  if not public.mesma_empresa('coletas', new.coleta_id, new.empresa_id) then raise exception 'Coleta não pertence a esta empresa'; end if;
  return new;
end;
$$;

create or replace function public.coletas_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.numero := public.comercial_proximo_numero('coletas', new.empresa_id);
  else
    new.numero := old.numero; new.empresa_id := old.empresa_id;
  end if;
  if not public.mesma_empresa('clientes', new.cliente_id, new.empresa_id) then raise exception 'Cliente não pertence a esta empresa'; end if;
  if not public.mesma_empresa('cotacoes', new.cotacao_id, new.empresa_id) then raise exception 'Cotação não pertence a esta empresa'; end if;
  if not public.mesma_empresa('vehicles', new.veiculo_id, new.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
  if not public.mesma_empresa('drivers', new.motorista_id, new.empresa_id) then raise exception 'Motorista não pertence a esta empresa'; end if;
  if not public.mesma_empresa('viagens', new.viagem_id, new.empresa_id) then raise exception 'Viagem não pertence a esta empresa'; end if;
  if new.status = 'coletada' and new.coletada_em is null then new.coletada_em := now(); end if;
  return new;
end;
$$;

drop function if exists public.comercial_antes_gravar() cascade;
drop trigger if exists clientes_antes_gravar on public.clientes;
create trigger clientes_antes_gravar before insert or update on public.clientes
  for each row execute function public.clientes_antes_gravar();
drop trigger if exists cotacoes_antes_gravar on public.cotacoes;
create trigger cotacoes_antes_gravar before insert or update on public.cotacoes
  for each row execute function public.cotacoes_antes_gravar();
drop trigger if exists coletas_antes_gravar on public.coletas;
create trigger coletas_antes_gravar before insert or update on public.coletas
  for each row execute function public.coletas_antes_gravar();

revoke execute on function public.comercial_proximo_numero(text, uuid) from public, anon, authenticated;
revoke execute on function public.mesma_empresa(text, uuid, uuid) from public, anon, authenticated;

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.clientes enable row level security;
alter table public.cotacoes enable row level security;
alter table public.coletas  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['clientes', 'cotacoes', 'coletas'] loop
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
    execute format($p$create policy %I on public.%I for delete to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_delete', t);
  end loop;
end $$;

grant select, insert, update, delete on public.clientes, public.cotacoes, public.coletas to authenticated;
revoke all on public.clientes, public.cotacoes, public.coletas from anon;

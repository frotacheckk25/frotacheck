-- =============================================================================
-- FINANCEIRO — fornecedores, contas a pagar e contas a receber (2026-10-27)
--
-- fornecedores    : cadastro (CNPJ/CPF único na empresa)
-- contas_pagar    : títulos a pagar com categoria, fornecedor, veículo (custo
--                   por veículo), OS de origem, parcelamento e baixa
-- contas_receber  : títulos a receber (fretes) com cliente, coleta/cotação de
--                   origem, parcelamento e baixa
--
-- Regras no banco: referências da mesma empresa, baixa preenche data e valor
-- pagos, título pago/recebido ou cancelado só volta para "aberto" (estorno).
-- Acesso: MASTER, ADMIN_EMPRESA e GESTOR. Idempotente.
-- =============================================================================

create table if not exists public.fornecedores (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id) on delete cascade,
  tipo         text not null default 'PJ' check (tipo in ('PJ', 'PF')),
  nome         text not null check (length(trim(nome)) between 2 and 160),
  documento    text check (documento is null or documento ~ '^[0-9]{11}$|^[0-9]{14}$'),
  categoria    text,
  contato      text,
  telefone     text,
  email        text,
  cidade       text,
  uf           text check (uf is null or uf ~ '^[A-Z]{2}$'),
  observacoes  text,
  ativo        boolean not null default true,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists fornecedores_empresa_documento_uq on public.fornecedores (empresa_id, documento) where documento is not null;
create index if not exists fornecedores_empresa_nome_idx on public.fornecedores (empresa_id, nome);

create table if not exists public.contas_pagar (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  descricao        text not null check (length(trim(descricao)) >= 2),
  categoria        text not null default 'outros' check (categoria in (
                     'combustivel', 'manutencao', 'pneus', 'pecas', 'salarios', 'impostos',
                     'seguros', 'pedagio', 'financiamento', 'aluguel', 'administrativo', 'outros')),
  fornecedor_id    uuid references public.fornecedores(id) on delete set null,
  vehicle_id       uuid references public.vehicles(id) on delete set null,
  os_id            uuid references public.ordens_servico(id) on delete set null,
  documento        text,
  valor            numeric(14,2) not null check (valor > 0 and valor <= 100000000),
  vencimento       date not null,
  status           text not null default 'aberta' check (status in ('aberta', 'paga', 'cancelada')),
  data_pagamento   date,
  valor_pago       numeric(14,2) check (valor_pago is null or valor_pago >= 0),
  forma_pagamento  text,
  parcela          integer not null default 1 check (parcela >= 1),
  parcelas         integer not null default 1 check (parcelas between 1 and 120),
  grupo            uuid,
  observacoes      text,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (parcela <= parcelas)
);
create index if not exists contas_pagar_empresa_idx on public.contas_pagar (empresa_id, status, vencimento);
create index if not exists contas_pagar_os_idx on public.contas_pagar (os_id);

create table if not exists public.contas_receber (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id) on delete cascade,
  descricao          text not null check (length(trim(descricao)) >= 2),
  categoria          text not null default 'frete' check (categoria in ('frete', 'outros')),
  cliente_id         uuid references public.clientes(id) on delete set null,
  coleta_id          uuid references public.coletas(id) on delete set null,
  cotacao_id         uuid references public.cotacoes(id) on delete set null,
  documento          text,
  valor              numeric(14,2) not null check (valor > 0 and valor <= 100000000),
  vencimento         date not null,
  status             text not null default 'aberta' check (status in ('aberta', 'recebida', 'cancelada')),
  data_recebimento   date,
  valor_recebido     numeric(14,2) check (valor_recebido is null or valor_recebido >= 0),
  forma_recebimento  text,
  parcela            integer not null default 1 check (parcela >= 1),
  parcelas           integer not null default 1 check (parcelas between 1 and 120),
  grupo              uuid,
  observacoes        text,
  created_by         uuid default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (parcela <= parcelas)
);
create index if not exists contas_receber_empresa_idx on public.contas_receber (empresa_id, status, vencimento);
create index if not exists contas_receber_coleta_idx on public.contas_receber (coleta_id);

-- ── Gatilhos ────────────────────────────────────────────────────────────────
create or replace function public.fornecedores_antes_gravar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then new.empresa_id := old.empresa_id; end if;
  return new;
end;
$$;
drop trigger if exists fornecedores_antes_gravar on public.fornecedores;
create trigger fornecedores_antes_gravar before insert or update on public.fornecedores
  for each row execute function public.fornecedores_antes_gravar();

create or replace function public.contas_pagar_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    -- título pago ou cancelado só pode voltar para "aberta" (estorno); não muda valores
    if old.status <> 'aberta' and new.status <> 'aberta' and (
         new.valor is distinct from old.valor or new.vencimento is distinct from old.vencimento
      or new.status is distinct from old.status) then
      raise exception 'Conta já % — estorne (volte para aberta) antes de alterar', case old.status when 'paga' then 'paga' else 'cancelada' end;
    end if;
  end if;
  if new.status = 'paga' then
    new.data_pagamento := coalesce(new.data_pagamento, current_date);
    new.valor_pago := coalesce(new.valor_pago, new.valor);
  elsif new.status = 'aberta' then
    new.data_pagamento := null; new.valor_pago := null; new.forma_pagamento := null;
  end if;
  if not public.mesma_empresa('fornecedores', new.fornecedor_id, new.empresa_id) then raise exception 'Fornecedor não pertence a esta empresa'; end if;
  if not public.mesma_empresa('vehicles', new.vehicle_id, new.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
  if not public.mesma_empresa('ordens_servico', new.os_id, new.empresa_id) then raise exception 'OS não pertence a esta empresa'; end if;
  return new;
end;
$$;
drop trigger if exists contas_pagar_antes_gravar on public.contas_pagar;
create trigger contas_pagar_antes_gravar before insert or update on public.contas_pagar
  for each row execute function public.contas_pagar_antes_gravar();

create or replace function public.contas_receber_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    if old.status <> 'aberta' and new.status <> 'aberta' and (
         new.valor is distinct from old.valor or new.vencimento is distinct from old.vencimento
      or new.status is distinct from old.status) then
      raise exception 'Conta já % — estorne (volte para aberta) antes de alterar', case old.status when 'recebida' then 'recebida' else 'cancelada' end;
    end if;
  end if;
  if new.status = 'recebida' then
    new.data_recebimento := coalesce(new.data_recebimento, current_date);
    new.valor_recebido := coalesce(new.valor_recebido, new.valor);
  elsif new.status = 'aberta' then
    new.data_recebimento := null; new.valor_recebido := null; new.forma_recebimento := null;
  end if;
  if not public.mesma_empresa('clientes', new.cliente_id, new.empresa_id) then raise exception 'Cliente não pertence a esta empresa'; end if;
  if not public.mesma_empresa('coletas', new.coleta_id, new.empresa_id) then raise exception 'Coleta não pertence a esta empresa'; end if;
  if not public.mesma_empresa('cotacoes', new.cotacao_id, new.empresa_id) then raise exception 'Cotação não pertence a esta empresa'; end if;
  return new;
end;
$$;
drop trigger if exists contas_receber_antes_gravar on public.contas_receber;
create trigger contas_receber_antes_gravar before insert or update on public.contas_receber
  for each row execute function public.contas_receber_antes_gravar();

-- ── RLS (MASTER, ADMIN_EMPRESA, GESTOR) ─────────────────────────────────────
alter table public.fornecedores   enable row level security;
alter table public.contas_pagar   enable row level security;
alter table public.contas_receber enable row level security;

do $$
declare t text;
begin
  foreach t in array array['fornecedores', 'contas_pagar', 'contas_receber'] loop
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
    -- exclusão só de título ainda em aberto (pago/recebido fica no histórico; cancele em vez de apagar)
    execute format($p$create policy %I on public.%I for delete to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever()
             and %s)$p$, t || '_delete', t, case when t = 'fornecedores' then 'true' else 'status = ''aberta''' end);
  end loop;
end $$;

grant select, insert, update, delete on public.fornecedores, public.contas_pagar, public.contas_receber to authenticated;
revoke all on public.fornecedores, public.contas_pagar, public.contas_receber from anon;

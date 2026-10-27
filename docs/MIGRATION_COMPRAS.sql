-- =============================================================================
-- COMPRAS — pedido de compra com aprovação e recebimento (2026-10-27)
--
-- pedidos_compra          : pedido por fornecedor com número por empresa,
--                           categoria (a mesma do contas a pagar), veículo
--                           (opcional, custo por veículo), previsão de entrega
--                           e condição de pagamento (parcelas e prazo)
-- pedido_compra_itens     : material do estoque ou item avulso (serviço,
--                           frete...); o total do pedido é recalculado no banco
-- compra_recebimentos     : cada recebimento (nota fiscal, valor, itens)
-- pedido_compra_historico : quem fez o quê e quando
--
-- Etapas: rascunho → aguardando → aprovado → parcial → recebido.
--         Reprovado e aprovado voltam para rascunho (a aprovação é desfeita);
--         cancelado em qualquer etapa antes de receber; parcial pode ser
--         encerrado com o que chegou. Só o rascunho aceita mudar itens e dados.
-- Aprovar/reprovar: MASTER e ADMIN_EMPRESA (ou quem tiver approvePurchases
--         liberada no perfil — a mesma regra do app).
-- receber_pedido_compra(): numa transação só, dá entrada no estoque pelo preço
--         do pedido (o custo médio é recalculado), lança o contas a pagar em
--         parcelas e registra o recebimento.
-- Acesso: MASTER, ADMIN_EMPRESA e GESTOR. Idempotente.
-- =============================================================================

create table if not exists public.pedidos_compra (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id) on delete cascade,
  numero             integer,
  fornecedor_id      uuid references public.fornecedores(id) on delete set null,
  categoria          text not null default 'pecas' check (categoria in ('pecas', 'pneus', 'combustivel', 'manutencao', 'administrativo', 'outros')),
  vehicle_id         uuid references public.vehicles(id) on delete set null,
  descricao          text,
  status             text not null default 'rascunho' check (status in ('rascunho', 'aguardando', 'aprovado', 'reprovado', 'parcial', 'recebido', 'cancelado')),
  data_pedido        date not null default current_date,
  previsao_entrega   date,
  parcelas           integer not null default 1 check (parcelas between 1 and 120),
  prazo_dias         integer not null default 30 check (prazo_dias between 0 and 365),
  valor_total        numeric(14,2) not null default 0,
  aprovado_por       uuid,
  aprovado_por_nome  text,
  aprovado_em        timestamptz,
  motivo_reprovacao  text,
  data_recebimento   date,
  observacoes        text,
  created_by         uuid default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (empresa_id, numero)
);
create index if not exists pedidos_compra_empresa_idx on public.pedidos_compra (empresa_id, status, data_pedido desc);

create table if not exists public.pedido_compra_itens (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas(id) on delete cascade,
  pedido_id            uuid not null references public.pedidos_compra(id) on delete cascade,
  material_id          uuid references public.materiais(id) on delete set null,
  descricao            text not null check (length(trim(descricao)) >= 2),
  unidade              text not null default 'un',
  quantidade           numeric(14,3) not null check (quantidade > 0 and quantidade <= 1000000),
  valor_unitario       numeric(14,4) not null default 0 check (valor_unitario >= 0 and valor_unitario <= 10000000),
  quantidade_recebida  numeric(14,3) not null default 0 check (quantidade_recebida >= 0),
  created_at           timestamptz not null default now(),
  check (quantidade_recebida <= quantidade)
);
create index if not exists pedido_compra_itens_pedido_idx on public.pedido_compra_itens (pedido_id);

create table if not exists public.compra_recebimentos (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas(id) on delete cascade,
  pedido_id            uuid not null references public.pedidos_compra(id) on delete cascade,
  data                 date not null default current_date,
  nota_fiscal          text,
  valor                numeric(14,2) not null default 0,
  parcelas             integer not null default 1,
  primeiro_vencimento  date,
  forma_pagamento      text,
  pago                 boolean not null default false,
  itens                jsonb not null default '[]'::jsonb,
  usuario_nome         text,
  created_by           uuid default auth.uid(),
  created_at           timestamptz not null default now()
);
create index if not exists compra_recebimentos_pedido_idx on public.compra_recebimentos (pedido_id);

create table if not exists public.pedido_compra_historico (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id) on delete cascade,
  pedido_id     uuid not null references public.pedidos_compra(id) on delete cascade,
  status_de     text,
  status_para   text,
  descricao     text not null,
  usuario_id    uuid default auth.uid(),
  usuario_nome  text,
  created_at    timestamptz not null default now()
);
create index if not exists pedido_compra_historico_pedido_idx on public.pedido_compra_historico (pedido_id, created_at);

-- Origem da conta a pagar e da entrada no estoque (preenchida só pelo recebimento)
alter table public.contas_pagar add column if not exists pedido_compra_id uuid references public.pedidos_compra(id) on delete set null;
create index if not exists contas_pagar_pedido_idx on public.contas_pagar (pedido_compra_id);
alter table public.estoque_movimentos add column if not exists pedido_compra_id uuid references public.pedidos_compra(id) on delete set null;
create index if not exists estoque_movimentos_pedido_idx on public.estoque_movimentos (pedido_compra_id);

-- ── Apoio ───────────────────────────────────────────────────────────────────
create or replace function public.compras_nome_usuario()
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(up.nome), ''), up.email, 'usuário')
  from public.user_profiles up where up.user_id = auth.uid() limit 1;
$$;
revoke execute on function public.compras_nome_usuario() from public, anon, authenticated;

-- Mesma regra do app (UserProfile.can): MASTER sempre; senão vale o que estiver
-- marcado no perfil; senão o padrão do papel (só ADMIN_EMPRESA aprova).
create or replace function public.pode_aprovar_compras()
returns boolean language sql stable security definer set search_path = public as $$
  select public.comercial_pode_escrever() and coalesce((
    select case
      when up.role = 'MASTER' then true
      when jsonb_typeof(up.permissions -> 'approvePurchases') = 'boolean' then (up.permissions ->> 'approvePurchases')::boolean
      else up.role = 'ADMIN_EMPRESA'
    end
    from public.user_profiles up
    where up.user_id = auth.uid() and up.status = 'ativo'
    limit 1
  ), false);
$$;
revoke execute on function public.pode_aprovar_compras() from public, anon;
grant execute on function public.pode_aprovar_compras() to authenticated;

-- ── Pedido: número, etapas, aprovação e trava depois de enviado ─────────────
create or replace function public.pedidos_compra_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_recebendo boolean := coalesce(current_setting('frotacheck.recebendo_compra', true), '') = 'on';
  v_itens integer;
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.numero := public.comercial_proximo_numero('pedidos_compra', new.empresa_id);
    new.status := 'rascunho';
    new.valor_total := 0;
    new.aprovado_por := null; new.aprovado_por_nome := null; new.aprovado_em := null;
    new.motivo_reprovacao := null; new.data_recebimento := null;
  else
    -- Atualizações internas (total vindo dos itens, "set null" de fornecedor
    -- ou veículo apagado) chegam em profundidade > 1 e passam direto.
    if pg_trigger_depth() > 1 then return new; end if;
    new.numero := old.numero;
    new.empresa_id := old.empresa_id;
    new.valor_total := old.valor_total;
    new.created_by := old.created_by;
    new.aprovado_por := old.aprovado_por; new.aprovado_por_nome := old.aprovado_por_nome; new.aprovado_em := old.aprovado_em;
    if not v_recebendo then new.data_recebimento := old.data_recebimento; end if;
    if not (old.status = 'aguardando' and new.status = 'reprovado') then new.motivo_reprovacao := old.motivo_reprovacao; end if;

    if old.status in ('recebido', 'cancelado') then
      raise exception 'Pedido nº % já está %', old.numero, old.status;
    end if;
    if old.status <> 'rascunho'
       and (new.fornecedor_id, new.categoria, new.vehicle_id, new.descricao, new.parcelas, new.prazo_dias, new.data_pedido)
           is distinct from (old.fornecedor_id, old.categoria, old.vehicle_id, old.descricao, old.parcelas, old.prazo_dias, old.data_pedido) then
      raise exception 'Pedido nº % já foi enviado: volte para rascunho para alterar', old.numero;
    end if;

    if new.status is distinct from old.status then
      if v_recebendo then
        if not (old.status in ('aprovado', 'parcial') and new.status in ('parcial', 'recebido')) then
          raise exception 'Mudança de situação inválida (% → %)', old.status, new.status;
        end if;
      elsif old.status = 'rascunho' and new.status in ('aguardando', 'aprovado') then
        if new.fornecedor_id is null then raise exception 'Escolha o fornecedor antes de enviar o pedido'; end if;
        select count(*) into v_itens from public.pedido_compra_itens where pedido_id = new.id;
        if v_itens = 0 then raise exception 'Inclua pelo menos um item no pedido'; end if;
        if old.valor_total <= 0 then raise exception 'O pedido está com valor zero'; end if;
        new.motivo_reprovacao := null;
      elsif old.status = 'aguardando' and new.status in ('aprovado', 'reprovado') then
        if new.status = 'reprovado' and coalesce(trim(new.motivo_reprovacao), '') = '' then
          raise exception 'Informe o motivo da reprovação';
        end if;
      elsif new.status = 'rascunho' and old.status in ('aguardando', 'reprovado', 'aprovado') then
        new.aprovado_por := null; new.aprovado_por_nome := null; new.aprovado_em := null;
      elsif new.status = 'cancelado' and old.status in ('rascunho', 'aguardando', 'reprovado', 'aprovado') then
        null;
      elsif old.status = 'parcial' and new.status = 'recebido' then
        null; -- encerrado com o que chegou
      else
        raise exception 'Mudança de situação inválida (% → %)', old.status, new.status;
      end if;

      if new.status in ('aprovado', 'reprovado') and not v_recebendo then
        if not public.pode_aprovar_compras() then
          raise exception 'Só o administrador da empresa pode aprovar ou reprovar pedidos de compra';
        end if;
        if new.status = 'aprovado' then
          new.aprovado_por := auth.uid();
          new.aprovado_por_nome := public.compras_nome_usuario();
          new.aprovado_em := now();
        end if;
      end if;
    end if;
  end if;
  if not public.mesma_empresa('fornecedores', new.fornecedor_id, new.empresa_id) then raise exception 'Fornecedor não pertence a esta empresa'; end if;
  if not public.mesma_empresa('vehicles', new.vehicle_id, new.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
  return new;
end;
$$;
drop trigger if exists pedidos_compra_antes_gravar on public.pedidos_compra;
create trigger pedidos_compra_antes_gravar before insert or update on public.pedidos_compra
  for each row execute function public.pedidos_compra_antes_gravar();

-- Histórico das etapas (o recebimento grava o próprio registro, com a NF)
create or replace function public.pedidos_compra_historico_registrar()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_desc text;
begin
  if coalesce(current_setting('frotacheck.recebendo_compra', true), '') = 'on' then return null; end if;
  if tg_op = 'INSERT' then
    v_desc := 'Pedido criado';
  elsif new.status is distinct from old.status then
    v_desc := case
      when new.status = 'aguardando' then 'Enviado para aprovação'
      when new.status = 'aprovado' then 'Aprovado'
      when new.status = 'reprovado' then 'Reprovado: ' || coalesce(new.motivo_reprovacao, '')
      when new.status = 'rascunho' and old.status = 'aprovado' then 'Reaberto para alteração (a aprovação foi desfeita)'
      when new.status = 'rascunho' then 'Voltou para rascunho'
      when new.status = 'cancelado' then 'Cancelado'
      when new.status = 'recebido' then 'Encerrado com o que já foi recebido'
      else 'Situação: ' || new.status
    end;
  else
    return null;
  end if;
  insert into public.pedido_compra_historico (empresa_id, pedido_id, status_de, status_para, descricao, usuario_id, usuario_nome)
  values (new.empresa_id, new.id, case when tg_op = 'UPDATE' then old.status end, new.status, v_desc, auth.uid(), public.compras_nome_usuario());
  return null;
end;
$$;
drop trigger if exists pedidos_compra_historico on public.pedidos_compra;
create trigger pedidos_compra_historico after insert or update of status on public.pedidos_compra
  for each row execute function public.pedidos_compra_historico_registrar();

-- ── Itens: só no rascunho; material da mesma empresa; total recalculado ─────
create or replace function public.pedido_compra_itens_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_ped record;
  v_mat record;
begin
  -- exclusão em cascata (pedido/empresa apagados) e "set null" de material apagado
  if pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  select id, empresa_id, status, numero into v_ped from public.pedidos_compra
   where id = case when tg_op = 'DELETE' then old.pedido_id else new.pedido_id end;
  if v_ped.id is null then
    if tg_op = 'DELETE' then return old; end if;
    raise exception 'Pedido não encontrado';
  end if;
  if coalesce(current_setting('frotacheck.recebendo_compra', true), '') = 'on' then
    if tg_op <> 'UPDATE' then raise exception 'Operação inválida durante o recebimento'; end if;
    return new;
  end if;
  if v_ped.status <> 'rascunho' then
    raise exception 'Pedido nº % já foi enviado: volte para rascunho para mudar os itens', v_ped.numero;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_op = 'UPDATE' and new.pedido_id <> old.pedido_id then raise exception 'Item não pode mudar de pedido'; end if;
  new.empresa_id := v_ped.empresa_id;
  new.quantidade_recebida := 0;
  if new.material_id is not null then
    select id, nome, codigo, unidade into v_mat from public.materiais where id = new.material_id and empresa_id = v_ped.empresa_id;
    if v_mat.id is null then raise exception 'Material não pertence a esta empresa'; end if;
    new.unidade := v_mat.unidade;
    if coalesce(trim(new.descricao), '') = '' then
      new.descricao := v_mat.nome || coalesce(' (' || v_mat.codigo || ')', '');
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists pedido_compra_itens_antes_gravar on public.pedido_compra_itens;
create trigger pedido_compra_itens_antes_gravar before insert or update or delete on public.pedido_compra_itens
  for each row execute function public.pedido_compra_itens_antes_gravar();

create or replace function public.pedido_compra_itens_recalcular()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ped uuid := case when tg_op = 'DELETE' then old.pedido_id else new.pedido_id end;
begin
  update public.pedidos_compra
     set valor_total = coalesce((select sum(round(quantidade * valor_unitario, 2)) from public.pedido_compra_itens where pedido_id = v_ped), 0)
   where id = v_ped;
  return null;
end;
$$;
drop trigger if exists pedido_compra_itens_recalcular on public.pedido_compra_itens;
create trigger pedido_compra_itens_recalcular after insert or update of quantidade, valor_unitario or delete on public.pedido_compra_itens
  for each row execute function public.pedido_compra_itens_recalcular();

-- Ninguém liga uma conta ou entrada de estoque a um pedido "na mão"
create or replace function public.compras_vinculo_protegido()
returns trigger language plpgsql as $$
begin
  if pg_trigger_depth() > 1 or coalesce(current_setting('frotacheck.recebendo_compra', true), '') = 'on' then
    return new;
  end if;
  new.pedido_compra_id := case when tg_op = 'UPDATE' then old.pedido_compra_id end;
  return new;
end;
$$;
drop trigger if exists contas_pagar_vinculo_compra on public.contas_pagar;
create trigger contas_pagar_vinculo_compra before insert or update on public.contas_pagar
  for each row execute function public.compras_vinculo_protegido();
drop trigger if exists estoque_movimentos_vinculo_compra on public.estoque_movimentos;
create trigger estoque_movimentos_vinculo_compra before insert on public.estoque_movimentos
  for each row execute function public.compras_vinculo_protegido();

-- ── Recebimento: estoque + contas a pagar + registro, tudo ou nada ──────────
-- p_itens: [{"item_id": "...", "quantidade": 10}, ...] (quantidade 0 = não veio)
create or replace function public.receber_pedido_compra(
  p_pedido     uuid,
  p_itens      jsonb,
  p_nota       text    default null,
  p_data       date    default null,
  p_vencimento date    default null,
  p_parcelas   integer default 1,
  p_forma      text    default null,
  p_pago       boolean default false
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_ped        record;
  v_item       record;
  v_el         jsonb;
  v_qtd        numeric;
  v_data       date := coalesce(p_data, current_date);
  v_parcelas   integer := case when coalesce(p_pago, false) then 1 else coalesce(p_parcelas, 1) end;
  v_nota       text := nullif(trim(coalesce(p_nota, '')), '');
  v_forma      text := nullif(trim(coalesce(p_forma, '')), '');
  v_venc       date;
  v_valor      numeric := 0;
  v_valor_item numeric;
  v_itens      jsonb := '[]'::jsonb;
  v_forn       text;
  v_grupo      uuid := gen_random_uuid();
  v_cent       bigint;
  v_base       bigint;
  v_status     text;
  v_receb      uuid;
  v_valor_txt  text;
begin
  if not public.comercial_pode_escrever() then raise exception 'Sem permissão'; end if;
  select * into v_ped from public.pedidos_compra where id = p_pedido for update;
  if v_ped.id is null or (v_ped.empresa_id is distinct from public.get_my_empresa_id() and public.get_my_role() <> 'MASTER') then
    raise exception 'Pedido não encontrado';
  end if;
  if v_ped.status not in ('aprovado', 'parcial') then
    raise exception 'Só pedido aprovado pode ser recebido (o nº % está %)', v_ped.numero, v_ped.status;
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe os itens recebidos';
  end if;
  if v_data > current_date + 1 then raise exception 'A data do recebimento não pode ser no futuro'; end if;
  if v_parcelas < 1 or v_parcelas > 120 then raise exception 'Parcelas: de 1 a 120'; end if;
  v_venc := coalesce(p_vencimento, v_data + v_ped.prazo_dias);

  perform set_config('frotacheck.recebendo_compra', 'on', true);

  for v_el in select * from jsonb_array_elements(p_itens) loop
    v_qtd := nullif(v_el ->> 'quantidade', '')::numeric;
    if v_qtd is null or v_qtd = 0 then continue; end if;
    if v_qtd < 0 then raise exception 'Quantidade recebida inválida'; end if;
    select * into v_item from public.pedido_compra_itens
     where id = (v_el ->> 'item_id')::uuid and pedido_id = v_ped.id for update;
    if v_item.id is null then raise exception 'Item não pertence a este pedido'; end if;
    if v_qtd > v_item.quantidade - v_item.quantidade_recebida then
      raise exception 'Recebendo mais do que falta de "%": faltam %', v_item.descricao,
        trim(to_char(v_item.quantidade - v_item.quantidade_recebida, 'FM999999990.###'));
    end if;
    update public.pedido_compra_itens set quantidade_recebida = quantidade_recebida + v_qtd where id = v_item.id;
    v_valor_item := round(v_qtd * v_item.valor_unitario, 2);
    v_valor := v_valor + v_valor_item;
    if v_item.material_id is not null then
      insert into public.estoque_movimentos (empresa_id, material_id, tipo, quantidade, custo_unitario, fornecedor_id, documento, data, pedido_compra_id, observacoes)
      values (v_ped.empresa_id, v_item.material_id, 'entrada', v_qtd, v_item.valor_unitario, v_ped.fornecedor_id, v_nota, v_data, v_ped.id,
              'Recebido do pedido de compra nº ' || v_ped.numero);
    end if;
    v_itens := v_itens || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'descricao', v_item.descricao, 'unidade', v_item.unidade, 'quantidade', v_qtd,
      'valor_unitario', v_item.valor_unitario, 'valor', v_valor_item, 'estoque', v_item.material_id is not null));
  end loop;
  if jsonb_array_length(v_itens) = 0 then raise exception 'Informe a quantidade recebida de pelo menos um item'; end if;

  -- contas a pagar: centavos que sobram da divisão vão para a última parcela
  if v_valor > 0 then
    select nome into v_forn from public.fornecedores where id = v_ped.fornecedor_id;
    v_cent := round(v_valor * 100);
    if v_cent < v_parcelas then raise exception 'Valor pequeno demais para % parcelas', v_parcelas; end if;
    v_base := v_cent / v_parcelas;
    for i in 1..v_parcelas loop
      insert into public.contas_pagar (empresa_id, descricao, categoria, fornecedor_id, vehicle_id, documento, valor, vencimento,
                                       status, data_pagamento, valor_pago, forma_pagamento, parcela, parcelas, grupo, pedido_compra_id, observacoes)
      values (v_ped.empresa_id,
              'Compra nº ' || v_ped.numero || coalesce(' · ' || v_forn, '') || case when v_parcelas > 1 then ' (' || i || '/' || v_parcelas || ')' else '' end,
              v_ped.categoria, v_ped.fornecedor_id, v_ped.vehicle_id, v_nota,
              (case when i = v_parcelas then v_cent - v_base * (v_parcelas - 1) else v_base end) / 100.0,
              case when p_pago then v_data else (v_venc + make_interval(months => i - 1))::date end,
              case when p_pago then 'paga' else 'aberta' end,
              case when p_pago then v_data end,
              case when p_pago then v_valor end,
              v_forma,
              i, v_parcelas, v_grupo, v_ped.id,
              'Recebimento do pedido de compra nº ' || v_ped.numero || coalesce(' · forma prevista: ' || v_forma, ''));
    end loop;
  end if;

  insert into public.compra_recebimentos (empresa_id, pedido_id, data, nota_fiscal, valor, parcelas, primeiro_vencimento, forma_pagamento, pago, itens, usuario_nome)
  values (v_ped.empresa_id, v_ped.id, v_data, v_nota, v_valor, case when v_valor > 0 then v_parcelas else 0 end,
          case when v_valor > 0 then (case when p_pago then v_data else v_venc end) end, v_forma, coalesce(p_pago, false), v_itens,
          public.compras_nome_usuario())
  returning id into v_receb;

  v_status := case when exists (select 1 from public.pedido_compra_itens where pedido_id = v_ped.id and quantidade_recebida < quantidade)
                   then 'parcial' else 'recebido' end;
  update public.pedidos_compra set status = v_status, data_recebimento = v_data where id = v_ped.id;

  v_valor_txt := 'R$ ' || translate(to_char(v_valor, 'FM999,999,990.00'), ',.', '.,');
  insert into public.pedido_compra_historico (empresa_id, pedido_id, status_de, status_para, descricao, usuario_id, usuario_nome)
  values (v_ped.empresa_id, v_ped.id, v_ped.status, v_status,
          case when v_status = 'recebido' then 'Recebido' else 'Recebido em parte' end
            || coalesce(' · NF ' || v_nota, '') || ' · ' || v_valor_txt
            || case when v_valor > 0 then case when p_pago then ' (pago)' else ' em ' || v_parcelas || 'x no contas a pagar' end else '' end,
          auth.uid(), public.compras_nome_usuario());

  perform set_config('frotacheck.recebendo_compra', '', true);
  return jsonb_build_object('recebimento_id', v_receb, 'valor', v_valor, 'status', v_status,
                            'parcelas', case when v_valor > 0 then v_parcelas else 0 end);
end;
$$;
revoke execute on function public.receber_pedido_compra(uuid, jsonb, text, date, date, integer, text, boolean) from public, anon;
grant execute on function public.receber_pedido_compra(uuid, jsonb, text, date, date, integer, text, boolean) to authenticated;

-- ── RLS (MASTER, ADMIN_EMPRESA, GESTOR) ─────────────────────────────────────
alter table public.pedidos_compra          enable row level security;
alter table public.pedido_compra_itens     enable row level security;
alter table public.compra_recebimentos     enable row level security;
alter table public.pedido_compra_historico enable row level security;

do $$
declare t text;
begin
  foreach t in array array['pedidos_compra', 'pedido_compra_itens', 'compra_recebimentos', 'pedido_compra_historico'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($p$create policy %I on public.%I for select to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_select', t);
  end loop;
  -- recebimentos e histórico são só leitura: quem grava é o banco
  foreach t in array array['pedidos_compra', 'pedido_compra_itens'] loop
    execute format($p$create policy %I on public.%I for insert to authenticated
      with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_insert', t);
    execute format($p$create policy %I on public.%I for update to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())
      with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())$p$, t || '_update', t);
    -- pedido só se apaga como rascunho (depois disso, cancele); itens o gatilho controla
    execute format($p$create policy %I on public.%I for delete to authenticated
      using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever()
             and %s)$p$, t || '_delete', t, case when t = 'pedidos_compra' then 'status = ''rascunho''' else 'true' end);
  end loop;
end $$;

grant select, insert, update, delete on public.pedidos_compra, public.pedido_compra_itens to authenticated;
grant select on public.compra_recebimentos, public.pedido_compra_historico to authenticated;
revoke all on public.pedidos_compra, public.pedido_compra_itens, public.compra_recebimentos, public.pedido_compra_historico from anon;

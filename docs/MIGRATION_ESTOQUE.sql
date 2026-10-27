-- =============================================================================
-- ESTOQUE DE MATERIAIS (almoxarifado) — 2026-10-27
--
-- materiais           : cadastro com código (único na empresa), categoria,
--                       unidade, estoque mínimo e local. estoque_atual e
--                       custo_medio são mantidos SÓ pelo banco.
-- estoque_movimentos  : entrada (com custo → recalcula o custo médio),
--                       saída (pelo custo médio, nunca deixa o estoque
--                       negativo) e ajuste de inventário (com motivo).
--                       Movimento não se altera nem se apaga (histórico).
-- baixar_estoque_para_os(): tira a peça do estoque E inclui na OS pelo custo
--                       médio, na mesma transação.
-- Acesso: MASTER, ADMIN_EMPRESA e GESTOR. Idempotente.
-- =============================================================================

create table if not exists public.materiais (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  codigo          text,
  nome            text not null check (length(trim(nome)) between 2 and 120),
  categoria       text not null default 'peca' check (categoria in ('peca', 'filtro', 'lubrificante', 'pneu', 'ferramenta', 'limpeza', 'escritorio', 'outros')),
  unidade         text not null default 'un' check (unidade in ('un', 'L', 'kg', 'm', 'cx', 'par', 'jogo', 'galão', 'balde')),
  estoque_atual   numeric(14,3) not null default 0 check (estoque_atual >= 0),
  estoque_minimo  numeric(14,3) not null default 0 check (estoque_minimo >= 0),
  custo_medio     numeric(14,4) not null default 0 check (custo_medio >= 0),
  localizacao     text,
  observacoes     text,
  ativo           boolean not null default true,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index if not exists materiais_empresa_codigo_uq
  on public.materiais (empresa_id, upper(trim(codigo))) where codigo is not null and trim(codigo) <> '';
create index if not exists materiais_empresa_nome_idx on public.materiais (empresa_id, nome);

create table if not exists public.estoque_movimentos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  material_id      uuid not null references public.materiais(id) on delete cascade,
  tipo             text not null check (tipo in ('entrada', 'saida', 'ajuste')),
  quantidade       numeric(14,3) not null check (quantidade <> 0),
  custo_unitario   numeric(14,4) check (custo_unitario is null or custo_unitario >= 0),
  valor_total      numeric(14,2),
  saldo_apos       numeric(14,3),
  vehicle_id       uuid references public.vehicles(id) on delete set null,
  os_id            uuid references public.ordens_servico(id) on delete set null,
  fornecedor_id    uuid references public.fornecedores(id) on delete set null,
  documento        text,
  observacoes      text,
  data             date not null default current_date,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now()
);
create index if not exists estoque_movimentos_material_idx on public.estoque_movimentos (material_id, created_at);
create index if not exists estoque_movimentos_empresa_idx on public.estoque_movimentos (empresa_id, data);

-- ── Material: estoque e custo só mudam pelos movimentos ─────────────────────
create or replace function public.materiais_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  new.codigo := nullif(upper(trim(coalesce(new.codigo, ''))), '');
  if tg_op = 'INSERT' then
    new.estoque_atual := 0;
    new.custo_medio := 0;
  else
    new.empresa_id := old.empresa_id;
    if coalesce(current_setting('frotacheck.movimentando_estoque', true), '') <> 'on' then
      new.estoque_atual := old.estoque_atual;
      new.custo_medio := old.custo_medio;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists materiais_antes_gravar on public.materiais;
create trigger materiais_antes_gravar before insert or update on public.materiais
  for each row execute function public.materiais_antes_gravar();

-- ── Movimento: valida, calcula e atualiza o saldo e o custo médio ───────────
create or replace function public.estoque_movimento_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m record;
  v_novo numeric;
  v_custo numeric;
begin
  select * into m from public.materiais where id = new.material_id for update;
  -- material de outra empresa é tratado como inexistente
  if m.id is null or (m.empresa_id is distinct from public.get_my_empresa_id() and coalesce(public.get_my_role(), '') <> 'MASTER') then
    raise exception 'Material não encontrado';
  end if;
  new.empresa_id := m.empresa_id;
  if not public.mesma_empresa('vehicles', new.vehicle_id, new.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
  if not public.mesma_empresa('ordens_servico', new.os_id, new.empresa_id) then raise exception 'OS não pertence a esta empresa'; end if;
  if not public.mesma_empresa('fornecedores', new.fornecedor_id, new.empresa_id) then raise exception 'Fornecedor não pertence a esta empresa'; end if;

  v_custo := m.custo_medio;
  if new.tipo = 'entrada' then
    if new.quantidade <= 0 then raise exception 'Quantidade da entrada deve ser maior que zero'; end if;
    if new.custo_unitario is null then raise exception 'Informe o custo unitário da entrada'; end if;
    v_novo := m.estoque_atual + new.quantidade;
    -- custo médio ponderado
    v_custo := round((m.estoque_atual * m.custo_medio + new.quantidade * new.custo_unitario) / v_novo, 4);
  elsif new.tipo = 'saida' then
    if new.quantidade <= 0 then raise exception 'Quantidade da saída deve ser maior que zero'; end if;
    if new.quantidade > m.estoque_atual then
      raise exception 'Estoque insuficiente de "%": há % %', m.nome, trim(to_char(m.estoque_atual, 'FM999999990.###')), m.unidade;
    end if;
    new.custo_unitario := m.custo_medio;
    v_novo := m.estoque_atual - new.quantidade;
  else -- ajuste de inventário: quantidade com sinal (+ sobrou, − faltou)
    if coalesce(trim(new.observacoes), '') = '' then raise exception 'Informe o motivo do ajuste'; end if;
    v_novo := m.estoque_atual + new.quantidade;
    if v_novo < 0 then raise exception 'O ajuste deixaria o estoque negativo'; end if;
    new.custo_unitario := m.custo_medio;
  end if;
  new.valor_total := round(abs(new.quantidade) * new.custo_unitario, 2);
  new.saldo_apos := v_novo;

  perform set_config('frotacheck.movimentando_estoque', 'on', true);
  update public.materiais set estoque_atual = v_novo, custo_medio = v_custo where id = m.id;
  perform set_config('frotacheck.movimentando_estoque', '', true);
  return new;
end;
$$;
drop trigger if exists estoque_movimento_antes_gravar on public.estoque_movimentos;
create trigger estoque_movimento_antes_gravar before insert on public.estoque_movimentos
  for each row execute function public.estoque_movimento_antes_gravar();

-- ── Peça do estoque para a OS (baixa + item da OS na mesma transação) ───────
create or replace function public.baixar_estoque_para_os(p_os uuid, p_material uuid, p_quantidade numeric)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_os record;
  v_mat record;
begin
  if not public.comercial_pode_escrever() then raise exception 'Sem permissão'; end if;
  select * into v_os from public.ordens_servico where id = p_os;
  if v_os.id is null or (v_os.empresa_id is distinct from public.get_my_empresa_id() and public.get_my_role() <> 'MASTER') then
    raise exception 'OS não encontrada';
  end if;
  if v_os.status not in ('aberta', 'em_execucao') then raise exception 'OS concluída ou cancelada não pode receber peças'; end if;
  select * into v_mat from public.materiais where id = p_material and empresa_id = v_os.empresa_id;
  if v_mat.id is null then raise exception 'Material não encontrado'; end if;
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida'; end if;

  insert into public.estoque_movimentos (empresa_id, material_id, tipo, quantidade, vehicle_id, os_id, observacoes)
  values (v_os.empresa_id, v_mat.id, 'saida', p_quantidade, v_os.vehicle_id, v_os.id, 'Usado na OS nº ' || v_os.numero);

  insert into public.ordem_servico_itens (empresa_id, os_id, tipo, descricao, quantidade, valor_unitario)
  values (v_os.empresa_id, v_os.id, 'peca',
          v_mat.nome || coalesce(' (' || v_mat.codigo || ')', '') || ' — do estoque',
          p_quantidade, round(v_mat.custo_medio, 2));
end;
$$;
revoke execute on function public.baixar_estoque_para_os(uuid, uuid, numeric) from public, anon;
grant execute on function public.baixar_estoque_para_os(uuid, uuid, numeric) to authenticated;

-- ── RLS (MASTER, ADMIN_EMPRESA, GESTOR) ─────────────────────────────────────
alter table public.materiais          enable row level security;
alter table public.estoque_movimentos enable row level security;

drop policy if exists "materiais_select" on public.materiais;
drop policy if exists "materiais_insert" on public.materiais;
drop policy if exists "materiais_update" on public.materiais;
drop policy if exists "materiais_delete" on public.materiais;
create policy "materiais_select" on public.materiais for select to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
create policy "materiais_insert" on public.materiais for insert to authenticated
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
create policy "materiais_update" on public.materiais for update to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
-- material só se apaga sem movimento (o histórico protege; desative em vez de apagar)
create policy "materiais_delete" on public.materiais for delete to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever()
         and not exists (select 1 from public.estoque_movimentos em where em.material_id = materiais.id));

drop policy if exists "estoque_movimentos_select" on public.estoque_movimentos;
drop policy if exists "estoque_movimentos_insert" on public.estoque_movimentos;
create policy "estoque_movimentos_select" on public.estoque_movimentos for select to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
create policy "estoque_movimentos_insert" on public.estoque_movimentos for insert to authenticated
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());

grant select, insert, update, delete on public.materiais to authenticated;
grant select, insert on public.estoque_movimentos to authenticated;
revoke all on public.materiais, public.estoque_movimentos from anon;

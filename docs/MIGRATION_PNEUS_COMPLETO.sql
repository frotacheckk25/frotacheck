-- =============================================================================
-- PNEUS COMPLETO — número de fogo, sulco, recapagem, movimentação e custo/km
-- (2026-10-27)
--
-- pneus (tabela existente, só ganha colunas):
--   numero_fogo, medida, sulco_mm, sulco_inicial_mm, recapagens,
--   situacao (em_uso / estoque / recapagem / descartado) e km_acumulado
--   (km rodados nas montagens anteriores). km_instalacao continua sendo o
--   odômetro do veículo na montagem atual.
-- pneu_movimentacoes (nova): histórico de cadastro, montagem, desmontagem,
--   rodízio, medição de sulco, recapagem, conserto e descarte.
-- movimentar_pneu(): única forma de movimentar — valida e grava tudo junto.
--
-- Os pneus que já existem ficam "em uso" se têm veículo, senão "estoque".
-- Idempotente.
-- =============================================================================

alter table public.pneus
  add column if not exists numero_fogo      text,
  add column if not exists medida           text,
  add column if not exists sulco_mm         numeric(4,1),
  add column if not exists sulco_inicial_mm numeric(4,1),
  add column if not exists recapagens       integer not null default 0,
  add column if not exists situacao         text not null default 'em_uso',
  add column if not exists km_acumulado     numeric not null default 0;

update public.pneus set situacao = 'estoque' where vehicle_id is null and situacao = 'em_uso';

do $$ begin
  alter table public.pneus add constraint pneus_situacao_check check (situacao in ('em_uso', 'estoque', 'recapagem', 'descartado'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.pneus add constraint pneus_sulco_check check (sulco_mm is null or sulco_mm between 0 and 40);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.pneus add constraint pneus_recapagens_check check (recapagens between 0 and 10);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.pneus add constraint pneus_km_acumulado_check check (km_acumulado >= 0);
exception when duplicate_object then null; end $$;

create unique index if not exists pneus_empresa_numero_fogo_uq
  on public.pneus (empresa_id, upper(trim(numero_fogo))) where numero_fogo is not null and trim(numero_fogo) <> '';

-- ── Histórico de movimentação ───────────────────────────────────────────────
create table if not exists public.pneu_movimentacoes (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id) on delete cascade,
  pneu_id      uuid not null references public.pneus(id) on delete cascade,
  tipo         text not null check (tipo in ('cadastro', 'montagem', 'desmontagem', 'rodizio', 'medicao',
                                              'recapagem_envio', 'recapagem', 'conserto', 'descarte')),
  vehicle_id   uuid references public.vehicles(id) on delete set null,
  posicao      text,
  km_veiculo   numeric,
  km_rodado    numeric,
  sulco_mm     numeric(4,1),
  custo        numeric(14,2) check (custo is null or custo >= 0),
  observacoes  text,
  data         date not null default current_date,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now()
);
create index if not exists pneu_movimentacoes_pneu_idx on public.pneu_movimentacoes (pneu_id, created_at);

alter table public.pneu_movimentacoes enable row level security;
drop policy if exists "pneu_movimentacoes_select" on public.pneu_movimentacoes;
create policy "pneu_movimentacoes_select" on public.pneu_movimentacoes for select to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
grant select on public.pneu_movimentacoes to authenticated;
revoke all on public.pneu_movimentacoes from anon;

-- ── Regras do pneu (cadastro e edição pelo app) ─────────────────────────────
create or replace function public.pneus_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    -- movimentar (montar, desmontar, rodízio...) só pela função movimentar_pneu,
    -- que liga esta chave só durante a própria transação (o app não consegue
    -- ligá-la: set_config não é exposto pela API)
    if coalesce(current_setting('frotacheck.movimentando_pneu', true), '') <> 'on' and (
         new.vehicle_id is distinct from old.vehicle_id or new.posicao is distinct from old.posicao
      or new.situacao is distinct from old.situacao or new.km_acumulado is distinct from old.km_acumulado
      or new.recapagens is distinct from old.recapagens) then
      raise exception 'Use as ações de movimentação do pneu (montar, desmontar, rodízio...)';
    end if;
  else
    if new.vehicle_id is null then new.situacao := 'estoque'; new.posicao := null;
    else new.situacao := 'em_uso'; end if;
    new.recapagens := coalesce(new.recapagens, 0);
    new.km_acumulado := 0;
    if new.sulco_mm is null then new.sulco_mm := new.sulco_inicial_mm; end if;
    if new.sulco_inicial_mm is null then new.sulco_inicial_mm := new.sulco_mm; end if;
  end if;
  new.numero_fogo := nullif(upper(trim(coalesce(new.numero_fogo, ''))), '');
  if not public.mesma_empresa('vehicles', new.vehicle_id, new.empresa_id) then
    raise exception 'Veículo não pertence a esta empresa';
  end if;
  if new.situacao = 'em_uso' and new.posicao is not null and exists (
       select 1 from public.pneus p
        where p.vehicle_id = new.vehicle_id and p.posicao = new.posicao and p.situacao = 'em_uso' and p.id <> new.id) then
    raise exception 'A posição "%" deste veículo já tem um pneu montado', new.posicao;
  end if;
  return new;
end;
$$;
drop trigger if exists pneus_antes_gravar on public.pneus;
create trigger pneus_antes_gravar before insert or update on public.pneus
  for each row execute function public.pneus_antes_gravar();

-- histórico: registro do cadastro
create or replace function public.pneus_depois_cadastrar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, sulco_mm, custo, data, observacoes)
  values (new.empresa_id, new.id, 'cadastro', new.vehicle_id, new.posicao, new.km_instalacao, new.sulco_mm,
          coalesce(new.valor, new.cost), coalesce(new.data_instalacao, current_date),
          case when new.vehicle_id is null then 'Cadastrado no estoque' else 'Cadastrado já montado' end);
  return null;
end;
$$;
drop trigger if exists pneus_depois_cadastrar on public.pneus;
create trigger pneus_depois_cadastrar after insert on public.pneus
  for each row execute function public.pneus_depois_cadastrar();

-- ── Movimentar pneu ─────────────────────────────────────────────────────────
create or replace function public.movimentar_pneu(
  p_pneu uuid, p_tipo text,
  p_vehicle uuid default null, p_posicao text default null, p_km numeric default null,
  p_sulco numeric default null, p_custo numeric default null, p_obs text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  pn record;
  outro record;
  v_km_rodado numeric;
  v_obs text := nullif(trim(coalesce(p_obs, '')), '');
begin
  if not public.comercial_pode_escrever() then raise exception 'Sem permissão para movimentar pneus'; end if;
  perform set_config('frotacheck.movimentando_pneu', 'on', true);
  select * into pn from public.pneus where id = p_pneu for update;
  if pn.id is null or (pn.empresa_id is distinct from public.get_my_empresa_id() and public.get_my_role() <> 'MASTER') then
    raise exception 'Pneu não encontrado';
  end if;
  if p_custo is not null and p_custo < 0 then raise exception 'Custo inválido'; end if;
  if p_sulco is not null and (p_sulco < 0 or p_sulco > 40) then raise exception 'Sulco inválido (0 a 40 mm)'; end if;
  if p_km is not null and (p_km < 0 or p_km > 3000000) then raise exception 'Km inválido'; end if;
  if pn.situacao = 'descartado' then raise exception 'Pneu descartado não pode ser movimentado'; end if;

  case p_tipo
  when 'montagem' then
    if pn.situacao <> 'estoque' then raise exception 'Só dá para montar um pneu que está no estoque'; end if;
    if p_vehicle is null or nullif(trim(coalesce(p_posicao, '')), '') is null or p_km is null then
      raise exception 'Informe o veículo, a posição e o km do veículo';
    end if;
    if not public.mesma_empresa('vehicles', p_vehicle, pn.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
    update public.pneus set vehicle_id = p_vehicle, posicao = trim(p_posicao), km_instalacao = p_km,
           data_instalacao = current_date, situacao = 'em_uso', sulco_mm = coalesce(p_sulco, sulco_mm)
     where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, sulco_mm, observacoes)
    values (pn.empresa_id, pn.id, 'montagem', p_vehicle, trim(p_posicao), p_km, p_sulco, v_obs);

  when 'desmontagem' then
    if pn.situacao <> 'em_uso' then raise exception 'O pneu não está montado'; end if;
    if p_km is null then raise exception 'Informe o km do veículo na desmontagem'; end if;
    if pn.km_instalacao is not null and p_km < pn.km_instalacao then
      raise exception 'Km menor que o da montagem (% km)', pn.km_instalacao;
    end if;
    v_km_rodado := case when pn.km_instalacao is null then 0 else p_km - pn.km_instalacao end;
    update public.pneus set km_acumulado = km_acumulado + v_km_rodado, vehicle_id = null, posicao = null,
           situacao = 'estoque', sulco_mm = coalesce(p_sulco, sulco_mm)
     where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, km_rodado, sulco_mm, observacoes)
    values (pn.empresa_id, pn.id, 'desmontagem', pn.vehicle_id, pn.posicao, p_km, v_km_rodado, p_sulco, v_obs);

  when 'rodizio' then
    if pn.situacao <> 'em_uso' then raise exception 'O pneu não está montado'; end if;
    if nullif(trim(coalesce(p_posicao, '')), '') is null or trim(p_posicao) = pn.posicao then
      raise exception 'Escolha uma posição diferente da atual';
    end if;
    select * into outro from public.pneus
     where vehicle_id = pn.vehicle_id and posicao = trim(p_posicao) and situacao = 'em_uso' and id <> pn.id for update;
    if outro.id is not null then
      -- troca as posições: libera a posição atual antes de mover
      update public.pneus set posicao = null where id = pn.id;
      update public.pneus set posicao = pn.posicao where id = outro.id;
      insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, observacoes)
      values (pn.empresa_id, outro.id, 'rodizio', pn.vehicle_id, pn.posicao, p_km,
              'De ' || coalesce(outro.posicao, '?') || ' para ' || coalesce(pn.posicao, '?') || ' (troca de posição)');
    end if;
    update public.pneus set posicao = trim(p_posicao) where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, sulco_mm, observacoes)
    values (pn.empresa_id, pn.id, 'rodizio', pn.vehicle_id, trim(p_posicao), p_km, p_sulco,
            coalesce(v_obs, 'De ' || coalesce(pn.posicao, '?') || ' para ' || trim(p_posicao)));
    if p_sulco is not null then update public.pneus set sulco_mm = p_sulco where id = pn.id; end if;

  when 'medicao' then
    if p_sulco is null then raise exception 'Informe o sulco medido (mm)'; end if;
    update public.pneus set sulco_mm = p_sulco,
           status = case when p_sulco <= 3 then 'troca' when p_sulco <= 5 then 'revisar' else 'bom' end
     where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, sulco_mm, observacoes)
    values (pn.empresa_id, pn.id, 'medicao', pn.vehicle_id, pn.posicao, p_km, p_sulco, v_obs);

  when 'recapagem_envio' then
    if pn.situacao <> 'estoque' then raise exception 'Desmonte o pneu antes de enviar para a recapagem'; end if;
    update public.pneus set situacao = 'recapagem' where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, observacoes)
    values (pn.empresa_id, pn.id, 'recapagem_envio', v_obs);

  when 'recapagem' then
    if pn.situacao not in ('recapagem', 'estoque') then raise exception 'Desmonte o pneu antes de registrar a recapagem'; end if;
    if p_sulco is null then raise exception 'Informe o sulco do pneu recapado (mm)'; end if;
    if pn.recapagens >= 10 then raise exception 'Limite de recapagens atingido'; end if;
    update public.pneus set situacao = 'estoque', recapagens = recapagens + 1, sulco_mm = p_sulco, status = 'bom' where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, sulco_mm, custo, observacoes)
    values (pn.empresa_id, pn.id, 'recapagem', p_sulco, p_custo, coalesce(v_obs, 'Recapagem nº ' || (pn.recapagens + 1)));

  when 'conserto' then
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, vehicle_id, posicao, km_veiculo, custo, observacoes)
    values (pn.empresa_id, pn.id, 'conserto', pn.vehicle_id, pn.posicao, p_km, p_custo, v_obs);

  when 'descarte' then
    if pn.situacao = 'em_uso' then raise exception 'Desmonte o pneu antes de descartar'; end if;
    if v_obs is null then raise exception 'Informe o motivo do descarte'; end if;
    update public.pneus set situacao = 'descartado', status = 'troca' where id = pn.id;
    insert into public.pneu_movimentacoes (empresa_id, pneu_id, tipo, observacoes)
    values (pn.empresa_id, pn.id, 'descarte', v_obs);

  else
    raise exception 'Movimentação inválida';
  end case;
end;
$$;
revoke execute on function public.movimentar_pneu(uuid, text, uuid, text, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.movimentar_pneu(uuid, text, uuid, text, numeric, numeric, numeric, text) to authenticated;

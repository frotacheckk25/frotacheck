-- =============================================================================
-- TORRE DE CONTROLE — rastreamento dos veículos (2026-10-27)
--
-- rastreamento_posicoes    : posições recebidas (lat/lng, velocidade, horário)
--                            do celular do motorista durante a viagem ("app")
--                            ou do rastreador do caminhão ("rastreador")
-- rastreamento_ultima      : última posição de cada veículo (mapa rápido),
--                            com "parado desde" calculado no banco
-- rastreamento_integracoes : tokens para o sistema do rastreador enviar as
--                            posições (Edge Function rastreamento-receber);
--                            o banco guarda só o hash do token
--
-- Regras: o motorista só envia posição da SUA viagem em andamento (e do
-- veículo dela); posição vira da viagem em andamento do veículo; posição
-- antiga chegando atrasada não "volta" o mapa. Leitura: MASTER,
-- ADMIN_EMPRESA e GESTOR. Posições com mais de 180 dias são apagadas toda
-- madrugada (pg_cron). Idempotente.
-- =============================================================================

create table if not exists public.rastreamento_posicoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  vehicle_id      uuid not null references public.vehicles(id) on delete cascade,
  driver_id       uuid references public.drivers(id) on delete set null,
  viagem_id       uuid references public.viagens(id) on delete set null,
  latitude        double precision not null check (latitude between -90 and 90),
  longitude       double precision not null check (longitude between -180 and 180),
  velocidade_kmh  numeric(6,1) check (velocidade_kmh is null or velocidade_kmh between 0 and 300),
  precisao_m      numeric(9,1) check (precisao_m is null or precisao_m >= 0),
  rumo            numeric(5,1) check (rumo is null or rumo between 0 and 360),
  ignicao         boolean,
  origem          text not null default 'app' check (origem in ('app', 'rastreador')),
  registrado_em   timestamptz not null default now(),
  recebido_em     timestamptz not null default now(),
  enviado_por     uuid default auth.uid()
);
create index if not exists rastreamento_posicoes_veiculo_idx on public.rastreamento_posicoes (vehicle_id, registrado_em desc);
create index if not exists rastreamento_posicoes_viagem_idx on public.rastreamento_posicoes (viagem_id, registrado_em);
create index if not exists rastreamento_posicoes_empresa_idx on public.rastreamento_posicoes (empresa_id, registrado_em desc);

create table if not exists public.rastreamento_ultima (
  vehicle_id      uuid primary key references public.vehicles(id) on delete cascade,
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  driver_id       uuid,
  viagem_id       uuid,
  latitude        double precision not null,
  longitude       double precision not null,
  velocidade_kmh  numeric(6,1),
  precisao_m      numeric(9,1),
  rumo            numeric(5,1),
  ignicao         boolean,
  origem          text not null,
  registrado_em   timestamptz not null,
  parado_desde    timestamptz,
  atualizado_em   timestamptz not null default now()
);
create index if not exists rastreamento_ultima_empresa_idx on public.rastreamento_ultima (empresa_id);

create table if not exists public.rastreamento_integracoes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  nome             text not null default 'Rastreador' check (length(trim(nome)) between 2 and 60),
  token_hash       text not null unique,
  token_final      text not null,
  ativo            boolean not null default true,
  criado_em        timestamptz not null default now(),
  criado_por_nome  text,
  ultimo_uso       timestamptz,
  revogado_em      timestamptz
);
create index if not exists rastreamento_integracoes_empresa_idx on public.rastreamento_integracoes (empresa_id);

-- ── Apoio ───────────────────────────────────────────────────────────────────
create or replace function public.distancia_metros(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))));
$$;

-- ── Posição: valida quem envia e liga à viagem em andamento ─────────────────
create or replace function public.rastreamento_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_veic     record;
  v_viagem   record;
  v_servico  boolean := coalesce(auth.role(), '') = 'service_role';
  v_motorista uuid;
begin
  select id, empresa_id into v_veic from public.vehicles where id = new.vehicle_id;
  if v_veic.id is null then raise exception 'Veículo não encontrado'; end if;
  new.empresa_id := v_veic.empresa_id;
  new.recebido_em := now();
  new.registrado_em := coalesce(new.registrado_em, now());
  if new.registrado_em > now() + interval '10 minutes' or new.registrado_em < now() - interval '7 days' then
    raise exception 'Horário da posição fora do intervalo aceito';
  end if;

  if v_servico then
    -- integração do rastreador (Edge Function): a empresa já veio do token
    new.origem := 'rastreador';
    new.enviado_por := null;
  else
    new.origem := 'app';
    new.enviado_por := auth.uid();
    if v_veic.empresa_id is distinct from public.get_my_empresa_id() and coalesce(public.get_my_role(), '') <> 'MASTER' then
      raise exception 'Veículo não encontrado';
    end if;
    if public.get_my_role() = 'MOTORISTA' then
      select driver_id into v_motorista from public.user_profiles where user_id = auth.uid() limit 1;
      select id, motorista_id into v_viagem from public.viagens
       where id = new.viagem_id and status = 'em_progresso' and veiculo_id = new.vehicle_id;
      if v_viagem.id is null or v_viagem.motorista_id is distinct from v_motorista then
        raise exception 'Só dá para enviar a posição durante a sua viagem em andamento';
      end if;
      new.driver_id := v_motorista;
    end if;
  end if;

  -- sem viagem informada: usa a viagem em andamento do veículo
  if new.viagem_id is null then
    select id, motorista_id into v_viagem from public.viagens
     where veiculo_id = new.vehicle_id and status = 'em_progresso'
     order by data_inicio desc nulls last limit 1;
    new.viagem_id := v_viagem.id;
    new.driver_id := coalesce(new.driver_id, v_viagem.motorista_id);
  end if;
  if not public.mesma_empresa('viagens', new.viagem_id, new.empresa_id) then raise exception 'Viagem não pertence a esta empresa'; end if;
  if not public.mesma_empresa('drivers', new.driver_id, new.empresa_id) then raise exception 'Motorista não pertence a esta empresa'; end if;
  return new;
end;
$$;
drop trigger if exists rastreamento_antes_gravar on public.rastreamento_posicoes;
create trigger rastreamento_antes_gravar before insert on public.rastreamento_posicoes
  for each row execute function public.rastreamento_antes_gravar();

-- Última posição do veículo (+ "parado desde": andou menos de 150 m e < 5 km/h)
create or replace function public.rastreamento_depois_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  u        record;
  v_parado timestamptz;
begin
  select * into u from public.rastreamento_ultima where vehicle_id = new.vehicle_id for update;
  if u.vehicle_id is not null and u.registrado_em > new.registrado_em then
    return null; -- posição antiga chegando atrasada não volta o mapa
  end if;
  if u.vehicle_id is not null
     and public.distancia_metros(u.latitude, u.longitude, new.latitude, new.longitude) < 150
     and coalesce(new.velocidade_kmh, 0) < 5 then
    v_parado := coalesce(u.parado_desde, u.registrado_em);
  end if;
  insert into public.rastreamento_ultima as r (vehicle_id, empresa_id, driver_id, viagem_id, latitude, longitude, velocidade_kmh,
                                               precisao_m, rumo, ignicao, origem, registrado_em, parado_desde, atualizado_em)
  values (new.vehicle_id, new.empresa_id, new.driver_id, new.viagem_id, new.latitude, new.longitude, new.velocidade_kmh,
          new.precisao_m, new.rumo, new.ignicao, new.origem, new.registrado_em, v_parado, now())
  on conflict (vehicle_id) do update set
    empresa_id = excluded.empresa_id, driver_id = excluded.driver_id, viagem_id = excluded.viagem_id,
    latitude = excluded.latitude, longitude = excluded.longitude, velocidade_kmh = excluded.velocidade_kmh,
    precisao_m = excluded.precisao_m, rumo = excluded.rumo, ignicao = excluded.ignicao, origem = excluded.origem,
    registrado_em = excluded.registrado_em, parado_desde = excluded.parado_desde, atualizado_em = now();
  return null;
end;
$$;
drop trigger if exists rastreamento_depois_gravar on public.rastreamento_posicoes;
create trigger rastreamento_depois_gravar after insert on public.rastreamento_posicoes
  for each row execute function public.rastreamento_depois_gravar();

-- ── Integração com o rastreador (token mostrado uma vez; banco guarda o hash)
create or replace function public.criar_integracao_rastreamento(p_empresa uuid, p_nome text default null)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  if coalesce(public.get_my_role(), '') not in ('MASTER', 'ADMIN_EMPRESA') then
    raise exception 'Só o administrador da empresa cria integrações';
  end if;
  if p_empresa is null or (p_empresa is distinct from public.get_my_empresa_id() and public.get_my_role() <> 'MASTER') then
    raise exception 'Empresa inválida';
  end if;
  v_token := 'fc_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.rastreamento_integracoes (empresa_id, nome, token_hash, token_final, criado_por_nome)
  values (p_empresa, coalesce(nullif(trim(coalesce(p_nome, '')), ''), 'Rastreador'),
          encode(extensions.digest(v_token, 'sha256'), 'hex'), right(v_token, 4), public.compras_nome_usuario());
  return v_token;
end;
$$;

create or replace function public.revogar_integracao_rastreamento(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.get_my_role(), '') not in ('MASTER', 'ADMIN_EMPRESA') then
    raise exception 'Só o administrador da empresa revoga integrações';
  end if;
  update public.rastreamento_integracoes set ativo = false, revogado_em = now()
   where id = p_id and ativo and (empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER');
  if not found then raise exception 'Integração não encontrada'; end if;
end;
$$;

revoke execute on function public.criar_integracao_rastreamento(uuid, text) from public, anon;
revoke execute on function public.revogar_integracao_rastreamento(uuid) from public, anon;
grant execute on function public.criar_integracao_rastreamento(uuid, text) to authenticated;
grant execute on function public.revogar_integracao_rastreamento(uuid) to authenticated;

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.rastreamento_posicoes    enable row level security;
alter table public.rastreamento_ultima      enable row level security;
alter table public.rastreamento_integracoes enable row level security;

drop policy if exists "rastreamento_posicoes_select" on public.rastreamento_posicoes;
drop policy if exists "rastreamento_posicoes_insert" on public.rastreamento_posicoes;
drop policy if exists "rastreamento_ultima_select" on public.rastreamento_ultima;
drop policy if exists "rastreamento_integracoes_select" on public.rastreamento_integracoes;
-- gestores veem a empresa; quem enviou vê as próprias posições
create policy "rastreamento_posicoes_select" on public.rastreamento_posicoes for select to authenticated
  using (((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())
         or enviado_por = auth.uid());
-- motorista também insere (o gatilho só aceita a viagem em andamento dele)
create policy "rastreamento_posicoes_insert" on public.rastreamento_posicoes for insert to authenticated
  with check (empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER');
create policy "rastreamento_ultima_select" on public.rastreamento_ultima for select to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
create policy "rastreamento_integracoes_select" on public.rastreamento_integracoes for select to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER')
         and coalesce(public.get_my_role(), '') in ('MASTER', 'ADMIN_EMPRESA'));

grant select, insert on public.rastreamento_posicoes to authenticated;
grant select on public.rastreamento_ultima, public.rastreamento_integracoes to authenticated;
revoke all on public.rastreamento_posicoes, public.rastreamento_ultima, public.rastreamento_integracoes from anon;

-- ── Limpeza: posições com mais de 180 dias saem toda madrugada ──────────────
select cron.unschedule(jobid) from cron.job where jobname = 'limpar-rastreamento-antigo';
select cron.schedule('limpar-rastreamento-antigo', '30 6 * * *',
  $$delete from public.rastreamento_posicoes where registrado_em < now() - interval '180 days'$$);

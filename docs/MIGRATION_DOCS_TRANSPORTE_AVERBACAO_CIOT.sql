-- =============================================================================
-- DOCUMENTOS DE TRANSPORTE — averbação do seguro, CT-e da coleta e CIOT (2026-10-27)
--
-- 1. company_settings: dados do seguro da carga (seguradora, CNPJ, apólice, averbadora)
-- 2. cte_documentos: coleta de origem + averbação (número, protocolo, data, quem)
-- 3. registrar_averbacao(): única forma de gravar a averbação num CT-e já
--    autorizado (a RLS do CT-e só deixa o app alterar RASCUNHO)
-- 4. ciot_registros: cadastro do CIOT (operadora, contratado, valor, viagem...)
--    com escrita para MASTER/ADMIN_EMPRESA/GESTOR — emissão automática pela
--    operadora entra depois do contrato
-- Idempotente.
-- =============================================================================

-- ── 1. Seguro da carga ──────────────────────────────────────────────────────
alter table public.company_settings
  add column if not exists seguradora_nome text,
  add column if not exists seguradora_cnpj text,
  add column if not exists seguro_apolice  text,
  add column if not exists averbadora      text;

-- ── 2. CT-e: coleta + averbação ─────────────────────────────────────────────
alter table public.cte_documentos
  add column if not exists coleta_id           uuid references public.coletas(id) on delete set null,
  add column if not exists averbacao_numero    text,
  add column if not exists averbacao_protocolo text,
  add column if not exists averbado_em         timestamptz,
  add column if not exists averbado_por        uuid;
create index if not exists idx_cte_documentos_coleta_id on public.cte_documentos(coleta_id);

create or replace function public.cte_coleta_mesma_empresa()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.coleta_id is not null and not public.mesma_empresa('coletas', new.coleta_id, new.empresa_id) then
    raise exception 'Coleta não pertence a esta empresa';
  end if;
  return new;
end;
$$;
drop trigger if exists cte_coleta_mesma_empresa on public.cte_documentos;
create trigger cte_coleta_mesma_empresa before insert or update of coleta_id on public.cte_documentos
  for each row execute function public.cte_coleta_mesma_empresa();

-- ── 3. Averbação do seguro (CT-e autorizado) ────────────────────────────────
create or replace function public.registrar_averbacao(p_cte_id uuid, p_numero text, p_protocolo text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare doc record;
begin
  if coalesce(public.get_my_role(), '') not in ('MASTER', 'ADMIN_EMPRESA', 'GESTOR') then
    raise exception 'Sem permissão para registrar averbação';
  end if;
  select id, empresa_id, status into doc from public.cte_documentos where id = p_cte_id;
  if doc.id is null or (doc.empresa_id is distinct from public.get_my_empresa_id() and public.get_my_role() <> 'MASTER') then
    raise exception 'CT-e não encontrado';
  end if;
  if doc.status <> 'autorizado' then
    raise exception 'Só é possível averbar um CT-e autorizado';
  end if;
  if length(trim(coalesce(p_numero, ''))) < 3 then
    raise exception 'Informe o número da averbação';
  end if;
  update public.cte_documentos
     set averbacao_numero = trim(p_numero),
         averbacao_protocolo = nullif(trim(coalesce(p_protocolo, '')), ''),
         averbado_em = now(),
         averbado_por = auth.uid()
   where id = p_cte_id;
end;
$$;
revoke execute on function public.registrar_averbacao(uuid, text, text) from public, anon;
grant execute on function public.registrar_averbacao(uuid, text, text) to authenticated;

-- ── 4. CIOT ─────────────────────────────────────────────────────────────────
alter table public.ciot_registros
  add column if not exists operadora        text,
  add column if not exists contratado_nome  text,
  add column if not exists contratado_doc   text,
  add column if not exists rntrc            text,
  add column if not exists valor_frete      numeric(14,2),
  add column if not exists viagem_id        uuid references public.viagens(id) on delete set null,
  add column if not exists veiculo_id       uuid references public.vehicles(id) on delete set null,
  add column if not exists motorista_id     uuid references public.drivers(id) on delete set null,
  add column if not exists coleta_id        uuid references public.coletas(id) on delete set null,
  add column if not exists data_inicio      date,
  add column if not exists data_fim         date,
  add column if not exists observacoes      text,
  add column if not exists criado_por       uuid default auth.uid(),
  add column if not exists atualizado_em    timestamptz not null default now();

alter table public.ciot_registros drop constraint if exists ciot_registros_status_check;
alter table public.ciot_registros add constraint ciot_registros_status_check
  check (status in ('pendente', 'registrado', 'encerrado', 'erro', 'cancelado'));
do $$ begin
  alter table public.ciot_registros add constraint ciot_numero_formato
    check (numero_ciot is null or numero_ciot ~ '^[0-9]{12,16}$');
  alter table public.ciot_registros add constraint ciot_contratado_doc_formato
    check (contratado_doc is null or contratado_doc ~ '^[0-9]{11}$|^[0-9]{14}$');
  alter table public.ciot_registros add constraint ciot_valor_positivo
    check (valor_frete is null or valor_frete >= 0);
  alter table public.ciot_registros add constraint ciot_registrado_tem_numero
    check (status not in ('registrado', 'encerrado') or numero_ciot is not null);
exception when duplicate_object then null; end $$;

create or replace function public.ciot_antes_gravar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.atualizado_em := now();
  if tg_op = 'UPDATE' then new.empresa_id := old.empresa_id; end if;
  if not public.mesma_empresa('viagens', new.viagem_id, new.empresa_id) then raise exception 'Viagem não pertence a esta empresa'; end if;
  if not public.mesma_empresa('vehicles', new.veiculo_id, new.empresa_id) then raise exception 'Veículo não pertence a esta empresa'; end if;
  if not public.mesma_empresa('drivers', new.motorista_id, new.empresa_id) then raise exception 'Motorista não pertence a esta empresa'; end if;
  if not public.mesma_empresa('coletas', new.coleta_id, new.empresa_id) then raise exception 'Coleta não pertence a esta empresa'; end if;
  if not public.mesma_empresa('mdfe_documentos', new.mdfe_id, new.empresa_id) then raise exception 'MDF-e não pertence a esta empresa'; end if;
  return new;
end;
$$;
drop trigger if exists ciot_antes_gravar on public.ciot_registros;
create trigger ciot_antes_gravar before insert or update on public.ciot_registros
  for each row execute function public.ciot_antes_gravar();

drop policy if exists "ciot_registros_insert" on public.ciot_registros;
create policy "ciot_registros_insert" on public.ciot_registros for insert to authenticated
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
drop policy if exists "ciot_registros_update" on public.ciot_registros;
create policy "ciot_registros_update" on public.ciot_registros for update to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever())
  with check ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());
grant select, insert, update on public.ciot_registros to authenticated;

-- Leitura do CIOT só para quem gerencia (CPF do contratado e valor do frete não
-- ficam visíveis para motorista). Antes qualquer usuário da empresa lia.
drop policy if exists "ciot_registros_select" on public.ciot_registros;
create policy "ciot_registros_select" on public.ciot_registros for select to authenticated
  using ((empresa_id = public.get_my_empresa_id() or public.get_my_role() = 'MASTER') and public.comercial_pode_escrever());

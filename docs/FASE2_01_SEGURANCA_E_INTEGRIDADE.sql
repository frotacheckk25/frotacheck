-- =============================================================================
-- FrotaCheck — Fase 2 (2026-09-24) — PASSO 1: SEGURANÇA E INTEGRIDADE
--
-- Pré-requisito: rodar docs/FASE2_00_VERIFICACAO_PREVIA.sql e revisar.
-- Rode este arquivo INTEIRO de uma vez no SQL Editor. Está dentro de uma
-- transação: se qualquer passo falhar, NADA é aplicado.
-- Idempotente: pode rodar de novo sem efeito colateral.
--
-- Corrige (ids do relatório de auditoria):
--   C1  excluir_motorista_safe executável sem login
--   C2  usuário bloqueado / empresa suspensa mantinham acesso pela API
--   C4  fiscal_proximo_numero executável sem login
--   A1  MFA exigido só no app (agora também no banco)
--   A2  conta pendente gravava arquivos na pasta de qualquer empresa
--   A5  admin alterava plano/status/valor da própria empresa
--   A6  limite de veículos do plano não existia
--   A7  excluir motorista apagava viagens (CASCADE) / falhava com multa ou CNH
--   A13 ADMIN_EMPRESA não conseguia criar/vincular usuários
--   GESTOR promovendo/bloqueando usuários (policy criada no painel)
--   Motorista editando/apagando multas, pneus, documentos, alertas,
--   manutenções, abastecimentos; registrando em nome de outro motorista;
--   cadastrando veículos
--   M1  hodômetro do veículo não subia quando o motorista registrava
--   M2  get_my_driver_id sem fallback por drivers.user_id
--   M5  arquivos do Storage nunca eram apagados (sem policy de DELETE)
--   M11 download do XML fiscal sem policy de leitura
--   M13 usuário editava as próprias permissões
--   B9  placa duplicada; sanidade de valores de abastecimento; empresa_id NOT NULL
-- =============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. FUNÇÕES DE CONTEXTO (C2, A1, M2)
--    Toda policy do sistema usa estas 3 funções. Elas passam a devolver NULL
--    (= sem acesso a nada) quando: o usuário não está 'ativo', a empresa não
--    está 'ativo', ou a conta tem MFA e a sessão ainda não passou pelo 2º fator.
-- ─────────────────────────────────────────────────────────────────────────────

-- Tolerante a falha: se por algum motivo a tabela de MFA não puder ser lida,
-- NÃO derruba o acesso de todo mundo (só deixa de exigir o 2º fator).
create or replace function public._mfa_ok()
returns boolean
language plpgsql stable security definer
set search_path = public, auth
as $$
begin
  if coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then
    return true;
  end if;
  return not exists (
    select 1 from auth.mfa_factors f
    where f.user_id = auth.uid() and f.status = 'verified'
  );
exception when others then
  return true;
end;
$$;

create or replace function public.get_my_role()
returns text
language sql stable security definer
set search_path = public
as $$
  select up.role
  from public.user_profiles up
  left join public.empresas e on e.id = up.empresa_id
  where up.user_id = auth.uid()
    and up.status = 'ativo'
    and (up.empresa_id is null or e.status = 'ativo')
    and public._mfa_ok()
  limit 1;
$$;

create or replace function public.get_my_empresa_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select up.empresa_id
  from public.user_profiles up
  left join public.empresas e on e.id = up.empresa_id
  where up.user_id = auth.uid()
    and up.status = 'ativo'
    and (up.empresa_id is null or e.status = 'ativo')
    and public._mfa_ok()
  limit 1;
$$;

-- Fallback por drivers.user_id restaurado (M2), sempre restrito à mesma empresa.
create or replace function public.get_my_driver_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  with me as (
    select up.driver_id, up.empresa_id
    from public.user_profiles up
    left join public.empresas e on e.id = up.empresa_id
    where up.user_id = auth.uid()
      and up.status = 'ativo'
      and (up.empresa_id is null or e.status = 'ativo')
      and public._mfa_ok()
    limit 1
  )
  select coalesce(
    (select driver_id from me),
    (select d.id from public.drivers d, me
      where d.user_id = auth.uid() and d.empresa_id = me.empresa_id
      limit 1)
  );
$$;

-- Usado pelo app para mostrar a tela certa (empresa suspensa, etc.) — lê o
-- status mesmo quando as funções acima já bloqueiam o acesso.
create or replace function public.get_my_access()
returns table (user_status text, empresa_status text, mfa_ok boolean)
language sql stable security definer
set search_path = public
as $$
  select up.status, e.status, public._mfa_ok()
  from public.user_profiles up
  left join public.empresas e on e.id = up.empresa_id
  where up.user_id = auth.uid()
  limit 1;
$$;

-- Veículo do motorista: agora respeita status/MFA e exige a mesma empresa.
create or replace function public.get_my_vehicle()
returns table(id uuid, plate text, model text, year integer, brand text, color text, tipo text, foto_url text)
language sql stable security definer
set search_path = public
as $$
  select v.id, v.plate, v.model, v.year::int, v.brand, v.color, v.tipo, v.foto_url
  from public.vehicles v
  where v.driver_id = public.get_my_driver_id()
    and v.empresa_id = public.get_my_empresa_id()
  limit 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. EXCLUSÃO DE MOTORISTA (C1, A7)
--    Nunca mais apaga histórico: as FKs passam a SET NULL (o registro fica,
--    só perde o vínculo com o motorista excluído).
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.viagens alter column motorista_id drop not null;

alter table public.viagens      drop constraint if exists viagens_motorista_id_fkey;
alter table public.viagens      add  constraint viagens_motorista_id_fkey
  foreign key (motorista_id) references public.drivers(id) on delete set null;

-- Veículo com viagens não pode mais ser apagado em cascata (histórico protegido).
alter table public.viagens      drop constraint if exists viagens_veiculo_id_fkey;
alter table public.viagens      add  constraint viagens_veiculo_id_fkey
  foreign key (veiculo_id) references public.vehicles(id);

alter table public.fuelings     drop constraint if exists fuelings_driver_id_fkey;
alter table public.fuelings     add  constraint fuelings_driver_id_fkey
  foreign key (driver_id) references public.drivers(id) on delete set null;

alter table public.vehicles     drop constraint if exists vehicles_driver_fk;
alter table public.vehicles     add  constraint vehicles_driver_fk
  foreign key (driver_id) references public.drivers(id) on delete set null;

alter table public.checklists   drop constraint if exists checklists_driver_id_fkey;
alter table public.checklists   add  constraint checklists_driver_id_fkey
  foreign key (driver_id) references public.drivers(id) on delete set null;

alter table public.multas       drop constraint if exists multas_motorista_id_fkey;
alter table public.multas       add  constraint multas_motorista_id_fkey
  foreign key (motorista_id) references public.drivers(id) on delete set null;

alter table public.documentos   drop constraint if exists documentos_motorista_id_fkey;
alter table public.documentos   add  constraint documentos_motorista_id_fkey
  foreign key (motorista_id) references public.drivers(id) on delete set null;

create or replace function public.excluir_motorista_safe(driver_id_param uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_empresa_id uuid;
  v_role text := coalesce(public.get_my_role(), '');
begin
  if auth.uid() is null then
    raise exception 'Não autenticado';
  end if;

  select empresa_id into v_empresa_id from public.drivers where id = driver_id_param;
  if not found then
    raise exception 'Motorista não encontrado';
  end if;

  if not (
    v_role = 'MASTER'
    or (v_role in ('ADMIN_EMPRESA', 'GESTOR') and v_empresa_id = public.get_my_empresa_id())
  ) then
    raise exception 'Sem permissão para excluir este motorista';
  end if;

  -- multas.driver_id não tem FK (coluna legada) — limpa manualmente.
  update public.multas set driver_id = null where driver_id = driver_id_param;
  -- Fecha atribuição aberta, para o histórico ficar com data de fim.
  update public.atribuicoes_veiculo set data_fim = now()
   where motorista_id = driver_id_param and data_fim is null;

  -- Demais vínculos (abastecimentos, veículo, perfil, checklists, viagens,
  -- ocorrências, multas, documentos, notificações) viram NULL pelas FKs.
  delete from public.drivers where id = driver_id_param;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. PRIVILÉGIOS DE FUNÇÕES (C1, C4)
--    Ninguém sem login executa função nenhuma. Numeração fiscal só pelo
--    servidor (Edge Function com service_role).
-- ─────────────────────────────────────────────────────────────────────────────

revoke execute on all functions in schema public from public, anon;

grant execute on function public._mfa_ok()                    to authenticated;
grant execute on function public.get_my_role()                to authenticated;
grant execute on function public.get_my_empresa_id()          to authenticated;
grant execute on function public.get_my_driver_id()           to authenticated;
grant execute on function public.get_my_access()              to authenticated;
grant execute on function public.get_my_vehicle()             to authenticated;
grant execute on function public.excluir_motorista_safe(uuid) to authenticated;

revoke execute on function public.fiscal_proximo_numero(uuid, text, integer) from authenticated;
grant  execute on function public.fiscal_proximo_numero(uuid, text, integer) to service_role;

-- Funções criadas no futuro também nascem sem acesso anônimo.
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. PERFIS DE USUÁRIO (A13, GESTOR, M13)
-- ─────────────────────────────────────────────────────────────────────────────

-- Policy criada direto no painel: dava UPDATE a GESTOR em qualquer perfil
-- da empresa (promover, bloquear, editar permissões) e era "TO public".
drop policy if exists "profiles_update_empresa_admin" on public.user_profiles;

-- GESTOR só pode mexer em perfil de MOTORISTA (vincular motorista ↔ conta);
-- o trigger abaixo limita QUAIS colunas ele pode alterar.
drop policy if exists "profiles_gestor_update_motorista" on public.user_profiles;
create policy "profiles_gestor_update_motorista" on public.user_profiles
  for update to authenticated
  using      ((select public.get_my_role()) = 'GESTOR' and empresa_id = (select public.get_my_empresa_id()) and role = 'MOTORISTA')
  with check ((select public.get_my_role()) = 'GESTOR' and empresa_id = (select public.get_my_empresa_id()) and role = 'MOTORISTA');

create or replace function public._protect_profile_privileged_columns()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_role text;
  v_old  jsonb := to_jsonb(old);
  v_keep jsonb;
begin
  -- service_role (Edge Functions) e SQL Editor: sem restrição.
  if auth.uid() is null then
    return new;
  end if;

  -- Liberação local usada só pela função vincular_usuario_empresa (definida
  -- abaixo, que já valida tudo). set_config não é exposto pela API REST.
  if current_setting('frotacheck.vinculo_autorizado', true) = 'on' then
    return new;
  end if;

  v_role := public.get_my_role();
  if v_role = 'MASTER' then
    return new;
  end if;

  -- Ninguém altera os próprios campos privilegiados (inclui permissions — M13).
  if new.user_id = auth.uid() then
    v_keep := jsonb_build_object(
      'role', v_old->'role', 'empresa_id', v_old->'empresa_id',
      'driver_id', v_old->'driver_id', 'status', v_old->'status',
      'permissions', v_old->'permissions');
    return jsonb_populate_record(new, v_keep);
  end if;

  if v_role = 'ADMIN_EMPRESA' then
    -- Só MASTER concede MASTER/ADMIN_EMPRESA.
    if new.role in ('MASTER', 'ADMIN_EMPRESA') and new.role is distinct from old.role then
      new.role := old.role;
    end if;
    -- Outro ADMIN_EMPRESA da mesma empresa só pode ser alterado pelo MASTER.
    if old.role = 'ADMIN_EMPRESA' then
      new.role := old.role;
      new.status := old.status;
      new.permissions := old.permissions;
    end if;
    new.empresa_id := old.empresa_id;
  else
    -- GESTOR (e qualquer outro papel): só nome/telefone/driver_id.
    new.role        := old.role;
    new.status      := old.status;
    new.permissions := old.permissions;
    new.empresa_id  := old.empresa_id;
  end if;

  -- driver_id só pode apontar para motorista da mesma empresa do perfil.
  if new.driver_id is distinct from old.driver_id and new.driver_id is not null then
    if not exists (select 1 from public.drivers d
                   where d.id = new.driver_id and d.empresa_id = new.empresa_id) then
      raise exception 'Motorista inválido para esta empresa';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_profile_privileged_columns on public.user_profiles;
create trigger trg_protect_profile_privileged_columns
  before update on public.user_profiles
  for each row execute function public._protect_profile_privileged_columns();

-- A13: ADMIN_EMPRESA/GESTOR não enxergam contas "pendentes" (sem empresa) e
-- não têm INSERT em user_profiles — por isso criar/vincular usuário falhava.
-- Esta função faz isso com as regras certas:
--   * ADMIN_EMPRESA pode atribuir GESTOR ou MOTORISTA; GESTOR só MOTORISTA.
--   * Só "pega" conta que está pendente e sem empresa (nunca de outra empresa).
--   * Conta que já é da mesma empresa: apenas devolve o user_id.
create or replace function public.vincular_usuario_empresa(p_email text, p_role text, p_nome text default null)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_role    text := public.get_my_role();
  v_empresa uuid := public.get_my_empresa_id();
  v_perfil  public.user_profiles%rowtype;
begin
  if v_role not in ('ADMIN_EMPRESA', 'GESTOR') or v_empresa is null then
    raise exception 'Sem permissão para vincular usuários';
  end if;
  if p_role not in ('GESTOR', 'MOTORISTA') or (v_role = 'GESTOR' and p_role <> 'MOTORISTA') then
    raise exception 'Papel não permitido';
  end if;

  select * into v_perfil from public.user_profiles
   where lower(email) = lower(trim(p_email))
   limit 1;
  if not found then
    raise exception 'CONTA_NAO_ENCONTRADA';
  end if;

  if v_perfil.empresa_id = v_empresa then
    return v_perfil.user_id;
  end if;

  if v_perfil.empresa_id is not null or v_perfil.role = 'MASTER' then
    raise exception 'CONTA_OUTRA_EMPRESA';
  end if;

  perform set_config('frotacheck.vinculo_autorizado', 'on', true);
  update public.user_profiles
     set empresa_id = v_empresa,
         role       = p_role,
         status     = 'ativo',
         nome       = coalesce(nullif(trim(p_nome), ''), nome)
   where user_id = v_perfil.user_id;
  perform set_config('frotacheck.vinculo_autorizado', 'off', true);

  return v_perfil.user_id;
end;
$$;

grant execute on function public.vincular_usuario_empresa(text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. EMPRESA E CONFIGURAÇÕES (A5)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public._protect_empresa_columns()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_old  jsonb := to_jsonb(old);
  v_keep jsonb;
begin
  if auth.uid() is null or public.get_my_role() = 'MASTER' then
    return new;
  end if;
  -- Admin edita dados cadastrais; plano/status/limites/valor só o MASTER.
  select coalesce(jsonb_object_agg(k, v_old -> k), '{}'::jsonb) into v_keep
    from unnest(array['plano','status','max_usuarios','max_veiculos',
                      'valor_mensalidade','created_at']) as k
   where v_old ? k;
  return jsonb_populate_record(new, v_keep);
end;
$$;

drop trigger if exists trg_protect_empresa_columns on public.empresas;
create trigger trg_protect_empresa_columns
  before update on public.empresas
  for each row execute function public._protect_empresa_columns();

-- Status do certificado digital só é escrito pela Edge Function (servidor).
create or replace function public._protect_certificado_columns()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_keep jsonb;
begin
  if auth.uid() is null or public.get_my_role() = 'MASTER' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    v_keep := jsonb_build_object('certificado_status', 'nao_configurado',
                                 'certificado_cn', null,
                                 'certificado_validade', null,
                                 'certificado_atualizado_em', null);
  else
    v_keep := jsonb_build_object('certificado_status', to_jsonb(old)->'certificado_status',
                                 'certificado_cn', to_jsonb(old)->'certificado_cn',
                                 'certificado_validade', to_jsonb(old)->'certificado_validade',
                                 'certificado_atualizado_em', to_jsonb(old)->'certificado_atualizado_em');
  end if;
  return jsonb_populate_record(new, v_keep);
end;
$$;

drop trigger if exists trg_protect_certificado_columns on public.company_settings;
create trigger trg_protect_certificado_columns
  before insert or update on public.company_settings
  for each row execute function public._protect_certificado_columns();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RLS DAS TABELAS OPERACIONAIS
--    Padrão: SELECT/INSERT/UPDATE/DELETE separados.
--      * ADMIN_EMPRESA/GESTOR: tudo da própria empresa.
--      * MOTORISTA: vê e registra só o que é dele (driver_id / veículo dele);
--        não edita nem apaga (exceções: concluir a própria viagem, andar o
--        status da própria ocorrência, resolver manutenção do próprio veículo).
--    Todas as policies antigas destas tabelas são removidas antes.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare
  t text;
  pol record;
begin
  foreach t in array array['fuelings','occurrences','checklists','viagens','oil_changes',
                           'manutencoes','pneus','multas','documentos','alerts',
                           'atribuicoes_veiculo','vehicles','drivers']
  loop
    for pol in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', pol.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Abreviações usadas abaixo (comentário, não código):
--   R = (select public.get_my_role())   E = (select public.get_my_empresa_id())
--   D = (select public.get_my_driver_id())

-- fuelings ────────────────────────────────────────────────────────────────────
create policy "sel" on public.fuelings for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "ins" on public.fuelings for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "upd" on public.fuelings for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.fuelings for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- occurrences (motorista pode andar o status da própria ocorrência) ──────────
create policy "sel" on public.occurrences for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "ins" on public.occurrences for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "upd" on public.occurrences for update to authenticated
  using (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))))
  with check (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "del" on public.occurrences for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- checklists ──────────────────────────────────────────────────────────────────
create policy "sel" on public.checklists for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))));
create policy "ins" on public.checklists for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))));
create policy "upd" on public.checklists for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.checklists for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- viagens (motorista conclui a própria viagem) ───────────────────────────────
create policy "sel" on public.viagens for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))));
create policy "ins" on public.viagens for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))));
create policy "upd" on public.viagens for update to authenticated
  using (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))))
  with check (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))));
create policy "del" on public.viagens for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- oil_changes (motorista só do próprio veículo) ──────────────────────────────
create policy "sel" on public.oil_changes for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = oil_changes.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "ins" on public.oil_changes for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = oil_changes.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "upd" on public.oil_changes for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.oil_changes for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- manutencoes (motorista resolve manutenção do próprio veículo) ───────────────
create policy "sel" on public.manutencoes for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = manutencoes.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "ins" on public.manutencoes for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = manutencoes.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "upd" on public.manutencoes for update to authenticated
  using (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                   select 1 from public.vehicles v
                   where v.id = manutencoes.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))))
  with check (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                   select 1 from public.vehicles v
                   where v.id = manutencoes.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "del" on public.manutencoes for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- pneus ───────────────────────────────────────────────────────────────────────
create policy "sel" on public.pneus for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = pneus.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "ins" on public.pneus for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = pneus.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "upd" on public.pneus for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.pneus for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- multas ──────────────────────────────────────────────────────────────────────
create policy "sel" on public.multas for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and (
                 driver_id = (select public.get_my_driver_id())
                 or motorista_id = (select public.get_my_driver_id())
                 or exists (select 1 from public.vehicles v
                            where v.id = multas.vehicle_id and v.driver_id = (select public.get_my_driver_id())))))));
create policy "ins" on public.multas for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and (
                 driver_id = (select public.get_my_driver_id())
                 or motorista_id = (select public.get_my_driver_id()))))));
create policy "upd" on public.multas for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.multas for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- documentos ──────────────────────────────────────────────────────────────────
create policy "sel" on public.documentos for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and (
                 driver_id = (select public.get_my_driver_id())
                 or motorista_id = (select public.get_my_driver_id())
                 or exists (select 1 from public.vehicles v
                            where v.id = documentos.vehicle_id and v.driver_id = (select public.get_my_driver_id())))))));
create policy "ins" on public.documentos for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and (
                 driver_id = (select public.get_my_driver_id())
                 or motorista_id = (select public.get_my_driver_id()))))));
create policy "upd" on public.documentos for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.documentos for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- alerts (motorista só vê alerta do próprio veículo; só gestão resolve) ──────
create policy "sel" on public.alerts for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and exists (
                 select 1 from public.vehicles v
                 where v.id = alerts.vehicle_id and v.driver_id = (select public.get_my_driver_id()))))));
create policy "ins" on public.alerts for insert to authenticated with check (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) is not null));
create policy "upd" on public.alerts for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.alerts for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- atribuicoes_veiculo (histórico; só gestão escreve) ─────────────────────────
create policy "sel" on public.atribuicoes_veiculo for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and motorista_id = (select public.get_my_driver_id())))));
create policy "ins" on public.atribuicoes_veiculo for insert to authenticated
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "upd" on public.atribuicoes_veiculo for update to authenticated
  using      ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "del" on public.atribuicoes_veiculo for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- vehicles (motorista não cadastra nem apaga; só foto e km do próprio) ───────
create policy "sel" on public.vehicles for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "ins" on public.vehicles for insert to authenticated
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "upd" on public.vehicles for update to authenticated
  using (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))))
  with check (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and driver_id = (select public.get_my_driver_id())))));
create policy "del" on public.vehicles for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- drivers (motorista só a própria foto) ──────────────────────────────────────
create policy "sel" on public.drivers for select to authenticated using (
  (select public.get_my_role()) = 'MASTER'
  or (empresa_id = (select public.get_my_empresa_id())
      and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
           or ((select public.get_my_role()) = 'MOTORISTA' and id = (select public.get_my_driver_id())))));
create policy "ins" on public.drivers for insert to authenticated
  with check ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));
create policy "upd" on public.drivers for update to authenticated
  using (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and id = (select public.get_my_driver_id())))))
  with check (
    (select public.get_my_role()) = 'MASTER'
    or (empresa_id = (select public.get_my_empresa_id())
        and ((select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')
             or ((select public.get_my_role()) = 'MOTORISTA' and id = (select public.get_my_driver_id())))));
create policy "del" on public.drivers for delete to authenticated
  using ((select public.get_my_role()) = 'MASTER' or (empresa_id = (select public.get_my_empresa_id()) and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')));

-- Motorista: em vehicles só altera foto_url e odometer (só para cima — M1);
-- em drivers só foto_url. Qualquer outra coluna volta ao valor antigo.
create or replace function public._protect_vehicle_driver_columns()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_km  numeric;
begin
  if auth.uid() is null or coalesce(public.get_my_role(), '') <> 'MOTORISTA' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    raise exception 'Motorista não pode excluir %', tg_table_name;
  end if;

  v_old := to_jsonb(old);
  v_new := to_jsonb(new);

  if tg_table_name = 'vehicles' then
    v_km := greatest(coalesce((v_old->>'odometer')::numeric, 0),
                     coalesce((v_new->>'odometer')::numeric, 0));
    v_old := v_old || jsonb_build_object('foto_url', v_new->'foto_url', 'odometer', v_km);
  else
    v_old := v_old || jsonb_build_object('foto_url', v_new->'foto_url');
  end if;

  return jsonb_populate_record(new, v_old);
end;
$$;

drop trigger if exists trg_protect_vehicle_columns on public.vehicles;
create trigger trg_protect_vehicle_columns
  before update or delete on public.vehicles
  for each row execute function public._protect_vehicle_driver_columns();

drop trigger if exists trg_protect_driver_columns on public.drivers;
create trigger trg_protect_driver_columns
  before update or delete on public.drivers
  for each row execute function public._protect_vehicle_driver_columns();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. LIMITE DE VEÍCULOS DO PLANO (A6)
--    Bloqueia o cadastro quando a empresa atinge o limite do plano da
--    assinatura. Plano sem limite (Enterprise) ou empresa sem assinatura:
--    sem bloqueio. MASTER pode cadastrar acima do limite (negociação especial).
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public._check_limite_plano_veiculos()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_limite int;
  v_plano  text;
  v_qtd    int;
begin
  if auth.uid() is null or public.get_my_role() = 'MASTER' then
    return new;
  end if;

  select p.limite_veiculos, p.nome into v_limite, v_plano
    from public.assinaturas a
    join public.planos p on p.id = a.plano_id
   where a.empresa_id = new.empresa_id;

  if v_limite is null then
    return new;
  end if;

  -- Serializa cadastros simultâneos da mesma empresa (evita passar do limite).
  perform pg_advisory_xact_lock(hashtextextended(new.empresa_id::text, 0));

  select count(*) into v_qtd from public.vehicles where empresa_id = new.empresa_id;
  if v_qtd >= v_limite then
    raise exception 'LIMITE_PLANO: seu plano % permite até % veículos. Fale com o suporte para fazer upgrade.', v_plano, v_limite
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_check_limite_plano_veiculos on public.vehicles;
create trigger trg_check_limite_plano_veiculos
  before insert on public.vehicles
  for each row execute function public._check_limite_plano_veiculos();

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. STORAGE (A2, M5, M11)
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists "authenticated_read_isolated_buckets"     on storage.objects;
drop policy if exists "authenticated_write_frotacheck_buckets"  on storage.objects;
drop policy if exists "authenticated_update_frotacheck_buckets" on storage.objects;
drop policy if exists "authenticated_delete_frotacheck_buckets" on storage.objects;
drop policy if exists "fiscal_read_own_empresa"                 on storage.objects;

create policy "authenticated_read_isolated_buckets" on storage.objects
  for select to authenticated
  using (
    bucket_id = any (array['checklists','multas','documentos','fuelings','avatars','logos','veiculos'])
    and ((select public.get_my_role()) = 'MASTER'
         or (storage.foldername(name))[1] = (select public.get_my_empresa_id())::text)
  );

-- A2: removida a brecha "get_my_empresa_id() IS NULL" (conta pendente).
create policy "authenticated_write_frotacheck_buckets" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = any (array['avatars','checklists','multas','documentos','logos','fuelings','veiculos'])
    and ((select public.get_my_role()) = 'MASTER'
         or (storage.foldername(name))[1] = (select public.get_my_empresa_id())::text)
  );

create policy "authenticated_update_frotacheck_buckets" on storage.objects
  for update to authenticated
  using (
    bucket_id = any (array['avatars','checklists','multas','documentos','logos','fuelings','veiculos'])
    and ((select public.get_my_role()) = 'MASTER'
         or (storage.foldername(name))[1] = (select public.get_my_empresa_id())::text)
  );

-- M5: gestão da empresa pode apagar arquivos da própria pasta.
create policy "authenticated_delete_frotacheck_buckets" on storage.objects
  for delete to authenticated
  using (
    bucket_id = any (array['avatars','checklists','multas','documentos','logos','fuelings','veiculos'])
    and ((select public.get_my_role()) = 'MASTER'
         or ((storage.foldername(name))[1] = (select public.get_my_empresa_id())::text
             and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  );

-- M11: XML/DANFE — leitura só pela gestão da própria empresa (escrita
-- continua exclusiva da Edge Function).
create policy "fiscal_read_own_empresa" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos-fiscais'
    and ((select public.get_my_role()) = 'MASTER'
         or ((storage.foldername(name))[1] = (select public.get_my_empresa_id())::text
             and (select public.get_my_role()) in ('ADMIN_EMPRESA','GESTOR')))
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. INTEGRIDADE DE DADOS (B9, sanidade, NOT NULL)
-- ─────────────────────────────────────────────────────────────────────────────

-- empresa_id obrigatório (resultado 4 da auditoria: 0 linhas nulas).
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array['vehicles','drivers','fuelings','occurrences','oil_changes',
                           'manutencoes','checklists','viagens','pneus','multas',
                           'documentos','alerts']
  loop
    execute format('select count(*) from public.%I where empresa_id is null', t) into n;
    if n = 0 then
      execute format('alter table public.%I alter column empresa_id set not null', t);
    else
      raise notice 'empresa_id NOT NULL NÃO aplicado em % (% linhas nulas)', t, n;
    end if;
  end loop;
end $$;

-- Sanidade dos abastecimentos (vale para registros novos/alterados; os
-- antigos não são reprocessados — NOT VALID).
alter table public.fuelings drop constraint if exists fuelings_valores_validos_ck;
alter table public.fuelings add constraint fuelings_valores_validos_ck check (
  liters > 0
  and total_value > 0
  and (odometer is null or odometer >= 0)
  and case when liters > 0 then (total_value / liters) between 0.5 and 100 else false end
) not valid;

-- Placa única por empresa (ignora hífen/espaço/maiúsculas).
do $$
begin
  if exists (
    select 1 from public.vehicles
    group by empresa_id, upper(regexp_replace(plate, '[^A-Za-z0-9]', '', 'g'))
    having count(*) > 1
  ) then
    raise notice 'Placa única NÃO aplicada: existem placas duplicadas (ver FASE2_00, consulta 0.4).';
  else
    create unique index if not exists vehicles_empresa_placa_unique
      on public.vehicles (empresa_id, upper(regexp_replace(plate, '[^A-Za-z0-9]', '', 'g')));
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. OCORRÊNCIA RESOLVIDA → ALERTA RESOLVIDO (automático, no banco)
--     Antes o app tentava sincronizar e falhava calado para o motorista.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public._sync_alerta_ocorrencia()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.status, '')) in ('resolvido','resolved','concluido','concluído','fechado','closed')
     and lower(coalesce(old.status, '')) is distinct from lower(new.status) then
    update public.alerts set status = 'resolvido'
     where occurrence_id = new.id and status is distinct from 'resolvido';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_alerta_ocorrencia on public.occurrences;
create trigger trg_sync_alerta_ocorrencia
  after update of status on public.occurrences
  for each row execute function public._sync_alerta_ocorrencia();

-- As funções de trigger criadas acima também não precisam de acesso anônimo.
revoke execute on all functions in schema public from public, anon;
grant execute on function public._mfa_ok()                    to authenticated;
grant execute on function public.get_my_role()                to authenticated;
grant execute on function public.get_my_empresa_id()          to authenticated;
grant execute on function public.get_my_driver_id()           to authenticated;
grant execute on function public.get_my_access()              to authenticated;
grant execute on function public.get_my_vehicle()             to authenticated;
grant execute on function public.excluir_motorista_safe(uuid) to authenticated;
grant execute on function public.vincular_usuario_empresa(text, text, text) to authenticated;

-- Funções de trigger: não podem ser chamadas pela API (retornam "trigger"),
-- mas mantêm permissão explícita para os papéis que disparam os gatilhos.
grant execute on function public.handle_new_user()                    to supabase_auth_admin;
grant execute on function public.notify_new_event()                   to authenticated;
grant execute on function public._protect_profile_privileged_columns() to authenticated;
grant execute on function public._protect_vehicle_driver_columns()    to authenticated;
grant execute on function public._protect_empresa_columns()           to authenticated;
grant execute on function public._protect_certificado_columns()       to authenticated;
grant execute on function public._check_limite_plano_veiculos()       to authenticated;
grant execute on function public._sync_alerta_ocorrencia()            to authenticated;

commit;

-- =============================================================================
-- VERIFICAÇÃO (rode depois do COMMIT)
-- =============================================================================

-- a) Nenhuma função executável sem login (deve retornar 0 linhas):
select p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');

-- b) Numeração fiscal fora do alcance de usuários (deve retornar false):
select has_function_privilege('authenticated', 'public.fiscal_proximo_numero(uuid,text,integer)', 'execute');

-- c) Policies por tabela (cada tabela operacional deve ter sel/ins/upd/del):
select tablename, string_agg(policyname, ', ' order by policyname) as policies
from pg_policies where schemaname = 'public'
group by tablename order by tablename;

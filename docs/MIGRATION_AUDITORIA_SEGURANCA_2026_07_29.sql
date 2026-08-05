-- =============================================================================
-- FrotaCheck — Correções da auditoria de segurança de 2026-07-29
--
-- Este arquivo aplica as correções de banco de dados dos achados F-01, F-03,
-- F-04 e F-10 (ver AUDITORIA_SEGURANCA_FROTACHECK_2026_07_29.md para o
-- detalhe completo de cada achado, PoC e justificativa).
-- =============================================================================

-- ── F-01: company_settings_read expunha linhas orfas (empresa_id IS NULL)
-- para QUALQUER usuario autenticado, de qualquer empresa/papel. Confirmado
-- explorável com um PoC real (motorista de teste lendo config de "outra
-- empresa" via API direta). Fix: remove a clausula IS NULL; só MASTER ou a
-- própria empresa podem ler.
drop policy if exists "company_settings_read" on public.company_settings;
create policy "company_settings_read" on public.company_settings
  for select to authenticated
  using (
    empresa_id = get_my_empresa_id()
    or get_my_role() = 'MASTER'
  );

-- Remove a linha orfa de teste que tornava o achado explorável na prática
-- hoje (dado de teste, sem CNPJ/empresa real associada).
delete from public.company_settings where empresa_id is null;

-- ── F-04: o trigger de user_profiles já bloqueava CONCEDER papel MASTER/
-- ADMIN_EMPRESA por quem não é MASTER, mas não bloqueava REVOGAR — um GESTOR
-- podia rebaixar/desativar o ADMIN_EMPRESA da própria empresa via API direta.
-- Fix: estende a mesma função de proteção para reverter tentativas de um
-- GESTOR alterar role/status de uma linha que hoje é ADMIN_EMPRESA.
create or replace function public._protect_profile_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
  -- MASTER pode fazer qualquer alteração, inclusive na própria linha.
  IF get_my_role() = 'MASTER' THEN
    RETURN NEW;
  END IF;

  -- Ninguém além de MASTER pode conceder o papel MASTER ou ADMIN_EMPRESA
  -- a qualquer linha (evita escalonamento de privilégio dentro da empresa).
  IF NEW.role IN ('MASTER', 'ADMIN_EMPRESA') AND (OLD.role IS DISTINCT FROM NEW.role) THEN
    NEW.role := OLD.role;
  END IF;

  -- F-04: GESTOR não pode rebaixar nem desativar o ADMIN_EMPRESA da própria
  -- empresa (só o próprio ADMIN_EMPRESA ou MASTER podem mexer nessa linha).
  IF get_my_role() = 'GESTOR' AND OLD.role = 'ADMIN_EMPRESA' THEN
    NEW.role   := OLD.role;
    NEW.status := OLD.status;
  END IF;

  -- Ninguém pode alterar os próprios campos privilegiados — nem mesmo quem
  -- tem permissão de editar terceiros (ex.: ADMIN_EMPRESA não pode se
  -- autopromover usando a mesma tela que edita subordinados).
  IF NEW.user_id = auth.uid() THEN
    NEW.role       := OLD.role;
    NEW.empresa_id := OLD.empresa_id;
    NEW.driver_id  := OLD.driver_id;
    NEW.status     := OLD.status;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── F-10: remove só a policy duplicada exata (mesmo USING de
-- profiles_own_update, mas sem WITH CHECK) — profiles_update_empresa_admin
-- é MANTIDA de propósito: admin_usuarios_page.dart usa esse caminho para
-- ADMIN_EMPRESA/GESTOR editarem nome de outros usuários da empresa, e a
-- proteção real contra abuso (F-04) agora é o trigger acima, não a policy.
drop policy if exists "profiles_update_own" on public.user_profiles;

-- ── F-03: RLS de vehicles/drivers liberava a linha inteira (qualquer coluna,
-- inclusive DELETE) para o MOTORISTA dono, mesmo a UI só usando isso para
-- trocar a própria foto. Fix: trigger BEFORE UPDATE/DELETE restringindo
-- MOTORISTA a alterar só foto_url, e bloqueando DELETE.
create or replace function public._protect_vehicle_driver_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
  IF get_my_role() = 'MOTORISTA' THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Motorista não pode excluir % ', TG_TABLE_NAME;
    END IF;

    IF TG_TABLE_NAME = 'vehicles' THEN
      NEW.plate      := OLD.plate;
      NEW.brand      := OLD.brand;
      NEW.model      := OLD.model;
      NEW.year       := OLD.year;
      NEW.color      := OLD.color;
      NEW.tipo       := OLD.tipo;
      NEW.odometer   := OLD.odometer;
      NEW.driver_id  := OLD.driver_id;
      NEW.empresa_id := OLD.empresa_id;
      NEW.company_id := OLD.company_id;
    ELSIF TG_TABLE_NAME = 'drivers' THEN
      NEW.name          := OLD.name;
      NEW.cnh_number     := OLD.cnh_number;
      NEW.cnh_category   := OLD.cnh_category;
      NEW.cnh_expiration := OLD.cnh_expiration;
      NEW.phone          := OLD.phone;
      NEW.email          := OLD.email;
      NEW.empresa_id     := OLD.empresa_id;
      NEW.company_id     := OLD.company_id;
      NEW.user_id        := OLD.user_id;
      NEW.tipo_vinculo   := OLD.tipo_vinculo;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

drop trigger if exists trg_protect_vehicle_columns on public.vehicles;
create trigger trg_protect_vehicle_columns
  before update or delete on public.vehicles
  for each row execute function public._protect_vehicle_driver_columns();

drop trigger if exists trg_protect_driver_columns on public.drivers;
create trigger trg_protect_driver_columns
  before update or delete on public.drivers
  for each row execute function public._protect_vehicle_driver_columns();

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

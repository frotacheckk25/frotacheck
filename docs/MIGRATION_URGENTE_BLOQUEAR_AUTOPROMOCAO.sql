-- =============================================================================
-- CORREÇÃO URGENTE — CRÍTICA
--
-- A policy "profiles_own" (criada em supabase_rbac_migration.sql, nunca
-- removida por nenhuma migração posterior) permite que QUALQUER usuário
-- autenticado atualize a própria linha em user_profiles por inteiro, incluindo
-- as colunas "role", "empresa_id" e "driver_id". Como get_my_role(),
-- get_my_empresa_id() e get_my_driver_id() leem exatamente essas colunas,
-- qualquer pessoa que se cadastra no app (mesmo com status "pendente") pode:
--
--   PATCH /rest/v1/user_profiles?user_id=eq.<o_proprio_uid>
--   { "role": "MASTER" }
--
-- ...e virar MASTER, ou trocar "empresa_id"/"driver_id" para assumir a
-- identidade de outra empresa/motorista. Isso derruba TODO o isolamento
-- multiempresa feito nas migrações anteriores, porque todas elas dependem
-- dessas mesmas três colunas para decidir o que cada usuário pode ver/editar.
--
-- CORREÇÃO: trigger BEFORE UPDATE que reverte qualquer tentativa de:
--   (a) qualquer pessoa (menos MASTER) conceder role = 'MASTER' a alguém, e
--   (b) qualquer pessoa (menos MASTER) alterar role/empresa_id/driver_id/status
--       na PRÓPRIA linha (auto-edição), mesmo que a policy RLS permita o UPDATE.
--
-- Isso NÃO quebra os fluxos legítimos existentes:
--   - Admin/Master editando role/status/driver_id de OUTRO usuário continua
--     funcionando normalmente (RLS de profiles_admin_update já escopa isso
--     corretamente por empresa).
--   - Usuário editando o próprio nome/telefone/avatar continua funcionando
--     (essas colunas não são protegidas por este trigger).
--
-- EXECUTE ISSO O QUANTO ANTES no SQL Editor do Supabase.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._protect_profile_privileged_columns()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- MASTER pode fazer qualquer alteração, inclusive na própria linha.
  IF get_my_role() = 'MASTER' THEN
    RETURN NEW;
  END IF;

  -- Ninguém além de MASTER pode conceder o papel MASTER a qualquer linha.
  IF NEW.role = 'MASTER' THEN
    NEW.role := OLD.role;
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
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_privileged_columns ON public.user_profiles;
CREATE TRIGGER trg_protect_profile_privileged_columns
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public._protect_profile_privileged_columns();

-- =============================================================================
-- Verificação recomendada (rode com sua própria conta, autenticado no app):
-- tente, pela própria tela de configurações, nada deve mudar de role/empresa.
-- Não é possível testar via SQL Editor porque ele usa a role "postgres", que
-- ignora RLS e triggers de auth.uid() — o teste real precisa ser feito pelo
-- app ou por uma chamada REST autenticada com o token de um usuário comum.
-- =============================================================================

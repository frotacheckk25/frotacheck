-- =============================================================================
-- ALTO — bloqueia escalonamento de privilégio: ADMIN_EMPRESA promovendo
-- outro usuário a ADMIN_EMPRESA dentro da própria empresa
--
-- A tela "Gestão de Usuários" permitia que um ADMIN_EMPRESA, usando o
-- dropdown normal de "Papel" no menu de ações de outro usuário, selecionasse
-- "Admin da Empresa" e chamasse _alterarRole(userId, AppRole.adminEmpresa).
-- A policy profiles_admin_update só valida a empresa e o papel de QUEM EDITA,
-- não o valor do papel sendo atribuído — e o trigger de proteção anterior só
-- bloqueava role = 'MASTER', deixando role = 'ADMIN_EMPRESA' passar livre.
--
-- Já corrigido no app (lib/home/admin/admin_usuarios_page.dart:
-- _rolesDisponiveis só oferece ADMIN_EMPRESA para quem já é MASTER). Esta
-- migração fecha o mesmo caminho no banco, para quem tentar via API direta.
--
-- PRÉ-REQUISITO: rode isso DEPOIS de
-- docs/MIGRATION_URGENTE_BLOQUEAR_AUTOPROMOCAO_V2.sql (que já recria a
-- função _protect_profile_privileged_columns) — esta migração só faz
-- CREATE OR REPLACE da mesma função, adicionando mais uma regra.
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

  -- Ninguém além de MASTER pode conceder o papel MASTER ou ADMIN_EMPRESA
  -- a qualquer linha (evita escalonamento de privilégio dentro da empresa).
  IF NEW.role IN ('MASTER', 'ADMIN_EMPRESA') AND (OLD.role IS DISTINCT FROM NEW.role) THEN
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

-- O trigger já existe (criado por MIGRATION_URGENTE_BLOQUEAR_AUTOPROMOCAO.sql)
-- e continua apontando para esta mesma função — não precisa recriar.

-- =============================================================================
-- FrotaCheck — Corrigir trigger de signup que cria empresa automaticamente
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Problema: ao registrar um novo usuário, o trigger handle_new_user criava
-- automaticamente uma empresa com nome/CNPJ padrão. Isso é errado para
-- motoristas — apenas admins devem ter empresa vinculada.
--
-- Solução: o trigger agora cria apenas o user_profile sem empresa.
-- O MASTER ou ADMIN_EMPRESA atribui o usuário à empresa depois.
-- =============================================================================

-- ── 1. Recriar handle_new_user SEM criar empresa ─────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_profiles (user_id, empresa_id, role, status, nome, email)
  VALUES (
    NEW.id,
    NULL,                                          -- sem empresa: admin atribui depois
    'MOTORISTA',                                   -- papel padrão
    'pendente',                                    -- aguarda ativação pelo admin
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)),
    NEW.email
  )
  ON CONFLICT (user_id) DO NOTHING;               -- não sobrescreve se já existir

  RETURN NEW;
END;
$$;

-- Garante que o trigger existe e está ativo
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── 2. Limpar empresa de teste criada pelo trigger antigo ─────────────────────
-- ATENÇÃO: este bloco desvincula usuários da empresa "Nome da Sua Empresa LTDA"
-- e depois a deleta. Execute apenas se quiser remover essa empresa.
-- Verifique o ID antes de executar — copie do output da linha SELECT abaixo.

-- Passo 2a: ver o ID da empresa de teste
SELECT id, nome, cnpj, created_at
FROM public.empresas
WHERE nome = 'Nome da Sua Empresa LTDA'
   OR cnpj = '00.000.000/0001-00';

-- Passo 2b: desvincular usuários que estão nessa empresa (substitua o UUID)
-- UPDATE public.user_profiles
--   SET empresa_id = NULL, status = 'pendente'
--   WHERE empresa_id = '<cole-aqui-o-uuid-da-empresa-de-teste>';

-- Passo 2c: deletar a empresa de teste (substitua o UUID)
-- DELETE FROM public.empresas
--   WHERE id = '<cole-aqui-o-uuid-da-empresa-de-teste>';

-- ── 3. (Opcional) Alterar o usuário master para não ter empresa ───────────────
-- O usuário MASTER não precisa de empresa_id.
-- Já está correto se empresa_id IS NULL no user_profiles do master.

-- ── 4. Verificar estado atual dos user_profiles ───────────────────────────────
SELECT
  up.email,
  up.role,
  up.status,
  up.empresa_id,
  e.nome AS empresa_nome
FROM public.user_profiles up
LEFT JOIN public.empresas e ON e.id = up.empresa_id
ORDER BY up.created_at;

-- =============================================================================
-- COMO FUNCIONA AGORA:
--   1. Novo usuário se cadastra → fica como MOTORISTA/pendente sem empresa
--   2. MASTER abre "Gestão de Usuários" → vê o novo usuário
--   3. MASTER muda o papel (ADMIN/GESTOR/MOTORISTA) e atribui a empresa
--   4. MASTER ou ADMIN vincula o motorista a um driver e veículo
-- =============================================================================

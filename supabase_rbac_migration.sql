-- =============================================================================
-- FrotaCheck — Migração SaaS Multi-tenant + RBAC
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

-- ─── 1. TABELA DE EMPRESAS ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.empresas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome        text NOT NULL,
  cnpj        text,
  plano       text NOT NULL DEFAULT 'basico',   -- basico | profissional | enterprise
  status      text NOT NULL DEFAULT 'ativo',    -- ativo | suspenso | cancelado
  max_usuarios  int NOT NULL DEFAULT 10,
  max_veiculos  int NOT NULL DEFAULT 20,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ─── 2. TABELA DE PERFIS DE USUÁRIO ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_profiles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id  uuid REFERENCES public.empresas(id) ON DELETE SET NULL,
  role        text NOT NULL DEFAULT 'MOTORISTA'
                   CHECK (role IN ('MASTER','ADMIN_EMPRESA','GESTOR','MOTORISTA')),
  permissions jsonb NOT NULL DEFAULT '{}',  -- overrides por permissão individual
  status      text NOT NULL DEFAULT 'ativo'
                   CHECK (status IN ('ativo','pendente','bloqueado','inativo')),
  last_access timestamptz,
  nome        text,
  email       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id)
);

-- ─── 3. FUNÇÕES AUXILIARES (SECURITY DEFINER = bypass RLS) ───────────────────

CREATE OR REPLACE FUNCTION public.get_my_empresa_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT empresa_id
  FROM   public.user_profiles
  WHERE  user_id = auth.uid()
  LIMIT  1;
$$;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM   public.user_profiles
  WHERE  user_id = auth.uid()
  LIMIT  1;
$$;

-- ─── 4. RLS NAS NOVAS TABELAS ────────────────────────────────────────────────

-- empresas: MASTER vê tudo; ADMIN_EMPRESA vê só a própria
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "empresas_master_all" ON public.empresas;
CREATE POLICY "empresas_master_all" ON public.empresas
  FOR ALL TO authenticated
  USING  (get_my_role() = 'MASTER')
  WITH CHECK (get_my_role() = 'MASTER');

DROP POLICY IF EXISTS "empresas_admin_own" ON public.empresas;
CREATE POLICY "empresas_admin_own" ON public.empresas
  FOR SELECT TO authenticated
  USING (id = get_my_empresa_id());

-- user_profiles: usuário vê/edita o próprio; ADMIN_EMPRESA vê da empresa
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_own" ON public.user_profiles;
CREATE POLICY "profiles_own" ON public.user_profiles
  FOR ALL TO authenticated
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "profiles_admin_empresa" ON public.user_profiles;
CREATE POLICY "profiles_admin_empresa" ON public.user_profiles
  FOR SELECT TO authenticated
  USING (empresa_id = get_my_empresa_id()
         AND get_my_role() IN ('MASTER','ADMIN_EMPRESA'));

DROP POLICY IF EXISTS "profiles_master_all" ON public.user_profiles;
CREATE POLICY "profiles_master_all" ON public.user_profiles
  FOR ALL TO authenticated
  USING  (get_my_role() = 'MASTER')
  WITH CHECK (get_my_role() = 'MASTER');

-- ─── 5. ADICIONAR empresa_id EM TODAS AS TABELAS DE DADOS ────────────────────

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.fuelings
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.oil_changes
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.multas
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.occurrences
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.manutencoes
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.documentos
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.pneus
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

ALTER TABLE public.checklists
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

-- tabelas que podem existir (ignorar erro se não existir)
DO $$ BEGIN
  ALTER TABLE public.alerts     ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
EXCEPTION WHEN undefined_table THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.viagens    ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ─── 6. RLS DE ISOLAMENTO POR EMPRESA EM TABELAS DE DADOS ────────────────────
-- Padrão: usuário vê dados da própria empresa; MASTER vê tudo.

-- Macro para aplicar a mesma política em todas as tabelas:
-- USING  (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
-- WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')

-- vehicles
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.vehicles;
CREATE POLICY "empresa_isolation" ON public.vehicles
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- drivers
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.drivers;
CREATE POLICY "empresa_isolation" ON public.drivers
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- fuelings
ALTER TABLE public.fuelings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.fuelings;
CREATE POLICY "empresa_isolation" ON public.fuelings
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- oil_changes
ALTER TABLE public.oil_changes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.oil_changes;
CREATE POLICY "empresa_isolation" ON public.oil_changes
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- multas
ALTER TABLE public.multas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.multas;
CREATE POLICY "empresa_isolation" ON public.multas
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- occurrences
ALTER TABLE public.occurrences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.occurrences;
CREATE POLICY "empresa_isolation" ON public.occurrences
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- manutencoes
ALTER TABLE public.manutencoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.manutencoes;
CREATE POLICY "empresa_isolation" ON public.manutencoes
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- documentos
ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.documentos;
CREATE POLICY "empresa_isolation" ON public.documentos
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- pneus
ALTER TABLE public.pneus ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.pneus;
CREATE POLICY "empresa_isolation" ON public.pneus
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- checklists
ALTER TABLE public.checklists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "empresa_isolation" ON public.checklists;
CREATE POLICY "empresa_isolation" ON public.checklists
  FOR ALL TO authenticated
  USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
  WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- viagens (RLS opcional — tabela pode não existir)
DO $$ BEGIN
  ALTER TABLE public.viagens ENABLE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS "empresa_isolation" ON public.viagens;
  CREATE POLICY "empresa_isolation" ON public.viagens
    FOR ALL TO authenticated
    USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
    WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- alerts
DO $$ BEGIN
  ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS "empresa_isolation" ON public.alerts;
  CREATE POLICY "empresa_isolation" ON public.alerts
    FOR ALL TO authenticated
    USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
    WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ─── 8. ÍNDICES DE DESEMPENHO (isolamento por empresa) ───────────────────────
-- Aceleram queries WHERE empresa_id = ...
CREATE INDEX IF NOT EXISTS idx_vehicles_empresa    ON public.vehicles(empresa_id);
CREATE INDEX IF NOT EXISTS idx_drivers_empresa     ON public.drivers(empresa_id);
CREATE INDEX IF NOT EXISTS idx_fuelings_empresa    ON public.fuelings(empresa_id);
CREATE INDEX IF NOT EXISTS idx_oil_changes_empresa ON public.oil_changes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_multas_empresa      ON public.multas(empresa_id);
CREATE INDEX IF NOT EXISTS idx_occurrences_empresa ON public.occurrences(empresa_id);
CREATE INDEX IF NOT EXISTS idx_documentos_empresa  ON public.documentos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_pneus_empresa       ON public.pneus(empresa_id);
CREATE INDEX IF NOT EXISTS idx_checklists_empresa  ON public.checklists(empresa_id);

-- ─── 9. CRIAR EMPRESA INICIAL E VINCULAR USUÁRIO ADMIN ───────────────────────
-- ATENÇÃO: Substitua o email abaixo pelo email do usuário administrador.
-- Execute esta seção separadamente após criar a empresa.

/*
-- Passo 7a: criar a empresa
INSERT INTO public.empresas (nome, cnpj, plano)
VALUES ('Nome da Sua Empresa', '00.000.000/0001-00', 'profissional')
RETURNING id;  -- copie o UUID retornado

-- Passo 7b: criar perfil do admin (substitua os valores abaixo)
INSERT INTO public.user_profiles (user_id, empresa_id, role, status, nome, email)
SELECT
  id,                                         -- user_id do auth.users
  '<cole-aqui-o-uuid-da-empresa>',            -- empresa_id retornado acima
  'ADMIN_EMPRESA',
  'ativo',
  'Nome do Admin',
  email
FROM auth.users
WHERE email = 'admin@suaempresa.com';         -- email do usuário admin

-- Passo 7c (opcional): migrar dados existentes para a empresa
-- UPDATE public.vehicles   SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.drivers    SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.fuelings   SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.oil_changes SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.multas     SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.occurrences SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.manutencoes SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.documentos  SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.pneus       SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
-- UPDATE public.checklists  SET empresa_id = '<uuid-empresa>' WHERE empresa_id IS NULL;
*/

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

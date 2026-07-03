-- =============================================================================
-- FrotaCheck — Corrige colunas faltantes em empresas/company_settings,
-- adiciona RLS de UPDATE para admin_empresa e cria os buckets de Storage
-- que o app já espera (avatars, checklists, multas, documentos, logos).
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

-- ─── 1. COLUNAS FALTANTES EM public.empresas ─────────────────────────────────
-- Erro original: "Could not find the 'email' column of 'empresas' in the
-- schema cache" — o código em configuracoes_page.dart tentava salvar campos
-- que nunca existiram na tabela.

ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS email         text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS telefone      text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS endereco      text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS report_email  text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS logo_url      text;

-- ─── 2. COLUNA FALTANTE EM public.company_settings ───────────────────────────
-- Erro original: tabela não tinha empresa_id, então os toggles de
-- Notificações/Integrações nunca persistiam por empresa (falha silenciosa
-- já capturada por try/catch no código).

ALTER TABLE public.company_settings
  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

CREATE INDEX IF NOT EXISTS idx_company_settings_empresa
  ON public.company_settings(empresa_id);

-- ─── 3. RLS: permitir que ADMIN_EMPRESA atualize a própria empresa ───────────
-- Antes só existia "empresas_admin_own" com FOR SELECT — ninguém além do
-- MASTER conseguia de fato salvar os dados da empresa (UPDATE bloqueado).
-- Restrito a ADMIN_EMPRESA (não GESTOR) para bater com a permissão
-- 'manageSettings' do app (só ADMIN_EMPRESA tem essa permissão hoje).

ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "empresas_admin_update" ON public.empresas;
CREATE POLICY "empresas_admin_update" ON public.empresas
  FOR UPDATE TO authenticated
  USING      (id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA')
  WITH CHECK (id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA');

-- ─── 4. RLS em company_settings (isolamento por empresa) ─────────────────────
-- Leitura liberada pra qualquer membro autenticado da empresa; escrita
-- restrita a ADMIN_EMPRESA (mesma regra de 'manageSettings' do app).

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "empresa_isolation" ON public.company_settings;
DROP POLICY IF EXISTS "company_settings_read" ON public.company_settings;
CREATE POLICY "company_settings_read" ON public.company_settings
  FOR SELECT TO authenticated
  USING (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

DROP POLICY IF EXISTS "company_settings_write" ON public.company_settings;
CREATE POLICY "company_settings_write" ON public.company_settings
  FOR INSERT TO authenticated
  WITH CHECK (empresa_id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA');

DROP POLICY IF EXISTS "company_settings_update" ON public.company_settings;
CREATE POLICY "company_settings_update" ON public.company_settings
  FOR UPDATE TO authenticated
  USING      (empresa_id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA')
  WITH CHECK (empresa_id = get_my_empresa_id() AND get_my_role() = 'ADMIN_EMPRESA');

-- ─── 5. BUCKETS DE STORAGE ────────────────────────────────────────────────────
-- O app já chama supabase.storage.from('avatars'|'checklists'|'multas'|
-- 'documentos') e agora também 'logos'. Nenhum bucket existia — todo upload
-- de foto falhava silenciosamente. Cria todos como públicos para leitura
-- (o app usa getPublicUrl, não signed URLs).

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('avatars',    'avatars',    true),
  ('checklists', 'checklists', true),
  ('multas',     'multas',     true),
  ('documentos', 'documentos', true),
  ('logos',      'logos',      true)
ON CONFLICT (id) DO NOTHING;

-- Leitura pública (necessário pra getPublicUrl funcionar no app)
DROP POLICY IF EXISTS "public_read_frotacheck_buckets" ON storage.objects;
CREATE POLICY "public_read_frotacheck_buckets" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id IN ('avatars','checklists','multas','documentos','logos'));

-- Upload/atualização só para usuários autenticados
DROP POLICY IF EXISTS "authenticated_write_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_write_frotacheck_buckets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id IN ('avatars','checklists','multas','documentos','logos'));

DROP POLICY IF EXISTS "authenticated_update_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_update_frotacheck_buckets" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id IN ('avatars','checklists','multas','documentos','logos'));

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

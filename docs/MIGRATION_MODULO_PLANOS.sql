-- =============================================================================
-- Módulo de Planos / Assinaturas — painel MASTER
--
-- Cria o catálogo de planos vendidos (START/PRO/BUSINESS/ENTERPRISE) e a
-- assinatura vigente de cada empresa (1 assinatura ativa por empresa).
--
-- Não altera nenhuma tabela existente: "empresas.plano" e
-- "empresas.valor_mensalidade" (criados na migração anterior) continuam no
-- banco intactos, mas a partir de agora a fonte de verdade da receita passa
-- a ser a tabela "assinaturas" — muito mais completa (status de cobrança,
-- vencimento, histórico, e campos prontos para gateway de pagamento).
--
-- Execute no SQL Editor do Supabase.
-- =============================================================================

-- ─── 1. Catálogo de planos ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.planos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           text UNIQUE NOT NULL,        -- START | PRO | BUSINESS | ENTERPRISE
  nome             text NOT NULL,
  valor_mensal     numeric(10,2),               -- null = "sob consulta" (Enterprise)
  limite_veiculos  int,                         -- null = ilimitado/personalizado
  descricao        text,
  ordem            int NOT NULL DEFAULT 0,
  ativo            boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.planos (codigo, nome, valor_mensal, limite_veiculos, descricao, ordem)
VALUES
  ('START',      'Start',      149.00, 10,   'Ideal para frotas pequenas começando a se organizar.', 1),
  ('PRO',        'Pro',        299.00, 30,   'Para frotas em crescimento com operação diária intensa.', 2),
  ('BUSINESS',   'Business',   499.00, 80,   'Times maiores, múltiplos gestores e alto volume.', 3),
  ('ENTERPRISE', 'Enterprise', NULL,   NULL, 'Volume e necessidades personalizadas — valor sob consulta.', 4)
ON CONFLICT (codigo) DO NOTHING;

ALTER TABLE public.planos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "planos_select_all" ON public.planos;
CREATE POLICY "planos_select_all" ON public.planos
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "planos_master_write" ON public.planos;
CREATE POLICY "planos_master_write" ON public.planos
  FOR ALL TO authenticated
  USING (get_my_role() = 'MASTER')
  WITH CHECK (get_my_role() = 'MASTER');


-- ─── 2. Assinatura vigente de cada empresa (1:1) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.assinaturas (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              uuid NOT NULL UNIQUE REFERENCES public.empresas(id) ON DELETE CASCADE,
  plano_id                uuid NOT NULL REFERENCES public.planos(id),
  valor_mensal            numeric(10,2) NOT NULL,  -- snapshot do valor pago (pode divergir do catálogo)
  status                  text NOT NULL DEFAULT 'ativo'
                               CHECK (status IN ('ativo','inadimplente','cancelado')),
  data_inicio             date NOT NULL DEFAULT current_date,
  proxima_cobranca        date,
  vencimento_dia          int,                     -- dia do mês do vencimento (1-28)
  gateway                 text,                    -- 'asaas' | 'mercadopago' | 'stripe' (futuro)
  gateway_customer_id     text,
  gateway_subscription_id text,
  observacoes             text,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assinaturas_plano  ON public.assinaturas(plano_id);
CREATE INDEX IF NOT EXISTS idx_assinaturas_status ON public.assinaturas(status);

-- Backfill: cria a assinatura de toda empresa já existente com base no que
-- foi cadastrado manualmente em empresas.plano / empresas.valor_mensalidade.
-- Empresas sem plano reconhecido caem em START por padrão (ajuste depois
-- pela tela "Planos" do painel Master).
-- data_inicio usa a data real de criação da empresa (não a data da migração)
-- para não "zerar" o histórico de crescimento de MRR já reconstruído no
-- painel a partir da data de cadastro de cada empresa.
INSERT INTO public.assinaturas (empresa_id, plano_id, valor_mensal, status, data_inicio, proxima_cobranca, vencimento_dia)
SELECT
  e.id,
  COALESCE(
    (SELECT p.id FROM public.planos p WHERE p.codigo = UPPER(e.plano) LIMIT 1),
    (SELECT p.id FROM public.planos p WHERE p.codigo = 'START' LIMIT 1)
  ),
  COALESCE(NULLIF(e.valor_mensalidade, 0), 149.00),
  CASE e.status WHEN 'ativo' THEN 'ativo' WHEN 'suspenso' THEN 'inadimplente' ELSE 'cancelado' END,
  e.created_at::date,
  (date_trunc('month', now()) + interval '1 month' + interval '4 days')::date,
  5
FROM public.empresas e
WHERE NOT EXISTS (SELECT 1 FROM public.assinaturas a WHERE a.empresa_id = e.id);

-- updated_at automático a cada alteração da assinatura
CREATE OR REPLACE FUNCTION public._touch_assinatura_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_assinaturas_updated_at ON public.assinaturas;
CREATE TRIGGER trg_assinaturas_updated_at
  BEFORE UPDATE ON public.assinaturas
  FOR EACH ROW EXECUTE FUNCTION public._touch_assinatura_updated_at();

ALTER TABLE public.assinaturas ENABLE ROW LEVEL SECURITY;

-- MASTER: controle total (criar, mudar plano, mudar status, cancelar)
DROP POLICY IF EXISTS "assinaturas_master_all" ON public.assinaturas;
CREATE POLICY "assinaturas_master_all" ON public.assinaturas
  FOR ALL TO authenticated
  USING (get_my_role() = 'MASTER')
  WITH CHECK (get_my_role() = 'MASTER');

-- Empresa: só enxerga a própria assinatura (isolamento entre empresas)
DROP POLICY IF EXISTS "assinaturas_admin_own_select" ON public.assinaturas;
CREATE POLICY "assinaturas_admin_own_select" ON public.assinaturas
  FOR SELECT TO authenticated
  USING (empresa_id = get_my_empresa_id());

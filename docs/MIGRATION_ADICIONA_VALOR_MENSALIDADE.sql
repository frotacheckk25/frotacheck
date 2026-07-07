-- =============================================================================
-- Adiciona o valor real da mensalidade (plano vendido) em cada empresa.
-- Sem essa coluna, o painel Master não tem como saber quanto cada empresa
-- paga — hoje o card "Receita mensal" somava o VALOR GASTO pelas empresas em
-- abastecimento, o que é custo delas, não faturamento do FrotaCheck.
-- Execute no SQL Editor do Supabase.
-- =============================================================================

ALTER TABLE public.empresas
  ADD COLUMN IF NOT EXISTS valor_mensalidade numeric(10,2) NOT NULL DEFAULT 0;

-- Preenche um valor inicial coerente com o plano já atribuído a cada empresa
-- existente (ajuste manualmente depois pela tela "Empresas cadastradas" do
-- painel Master, caso o valor real seja diferente do padrão do plano).
UPDATE public.empresas
SET valor_mensalidade = CASE plano
  WHEN 'profissional' THEN 259.90
  WHEN 'enterprise'   THEN 359.90
  ELSE 139.90 -- basico e qualquer outro valor
END
WHERE valor_mensalidade = 0;

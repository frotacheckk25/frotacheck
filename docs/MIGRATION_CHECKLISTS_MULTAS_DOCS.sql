-- =============================================================================
-- ⚠️ SUPERADO — NÃO EXECUTE ESTE ARQUIVO.
--
-- Rascunho antigo de uma versão anterior do schema (referencia
-- public.veiculos/public.motoristas em português, que não existem mais — o
-- schema atual usa public.vehicles/public.drivers). As policies de RLS aqui
-- ("... FOR SELECT USING (auth.role() = 'authenticated')") NÃO isolam por
-- empresa_id — se executadas sobre o banco atual, reabririam checklists/
-- multas/documentos de TODAS as empresas para qualquer usuário autenticado
-- (confirmado ao vivo em auditoria de segurança que essas policies NÃO
-- existem hoje — só a "empresa_isolation" de supabase_rbac_migration.sql).
--
-- Mantido apenas como histórico. Se precisar recriar as tabelas do zero, use
-- supabase_rbac_migration.sql como referência de schema atual.
-- =============================================================================

-- Tabela de Checklists (Saída e Retorno)
CREATE TABLE IF NOT EXISTS public.checklists (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    veiculo_id UUID NOT NULL REFERENCES public.veiculos(id) ON DELETE CASCADE,
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE CASCADE,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('saida', 'retorno')),
    data TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    itens JSONB NOT NULL DEFAULT '{}',
    foto_urls TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    assinatura_url TEXT,
    km_final INTEGER,
    aprovado BOOLEAN DEFAULT true,
    observacoes TEXT,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices para Checklists
CREATE INDEX idx_checklists_veiculo_id ON public.checklists(veiculo_id);
CREATE INDEX idx_checklists_motorista_id ON public.checklists(motorista_id);
CREATE INDEX idx_checklists_tipo ON public.checklists(tipo);
CREATE INDEX idx_checklists_data ON public.checklists(data DESC);

-- Tabela de Multas
CREATE TABLE IF NOT EXISTS public.multas (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    veiculo_id UUID NOT NULL REFERENCES public.veiculos(id) ON DELETE CASCADE,
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    data DATE NOT NULL DEFAULT CURRENT_DATE,
    valor DECIMAL(10, 2) NOT NULL,
    tipo VARCHAR(50) NOT NULL,
    descricao TEXT NOT NULL,
    foto_url TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'aberta' CHECK (status IN ('aberta', 'paga', 'contestada')),
    data_pagamento DATE,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices para Multas
CREATE INDEX idx_multas_veiculo_id ON public.multas(veiculo_id);
CREATE INDEX idx_multas_motorista_id ON public.multas(motorista_id);
CREATE INDEX idx_multas_status ON public.multas(status);
CREATE INDEX idx_multas_data ON public.multas(data DESC);

-- Tabela de Documentos
CREATE TABLE IF NOT EXISTS public.documentos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    veiculo_id UUID REFERENCES public.veiculos(id) ON DELETE CASCADE,
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE CASCADE,
    tipo VARCHAR(50) NOT NULL,
    descricao TEXT NOT NULL,
    file_url TEXT NOT NULL,
    data_vencimento DATE NOT NULL,
    data_pagamento DATE NOT NULL DEFAULT CURRENT_DATE,
    ativo BOOLEAN DEFAULT true,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices para Documentos
CREATE INDEX idx_documentos_veiculo_id ON public.documentos(veiculo_id);
CREATE INDEX idx_documentos_motorista_id ON public.documentos(motorista_id);
CREATE INDEX idx_documentos_tipo ON public.documentos(tipo);
CREATE INDEX idx_documentos_data_vencimento ON public.documentos(data_vencimento);

-- Criar buckets no Storage (se não existirem)
-- Execute via Supabase Dashboard em SQL Editor:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('checklists', 'checklists', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('multas', 'multas', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('documentos', 'documentos', true);

-- Políticas de RLS para Checklists
ALTER TABLE public.checklists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Checklists são visíveis para todos os usuários autenticados"
    ON public.checklists FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Checklists podem ser criados por usuários autenticados"
    ON public.checklists FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Checklists podem ser atualizados por criadores"
    ON public.checklists FOR UPDATE
    USING (auth.role() = 'authenticated');

-- Políticas de RLS para Multas
ALTER TABLE public.multas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Multas são visíveis para todos os usuários autenticados"
    ON public.multas FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Multas podem ser criadas por usuários autenticados"
    ON public.multas FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Multas podem ser atualizadas por usuários autenticados"
    ON public.multas FOR UPDATE
    USING (auth.role() = 'authenticated');

-- Políticas de RLS para Documentos
ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Documentos são visíveis para todos os usuários autenticados"
    ON public.documentos FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Documentos podem ser criados por usuários autenticados"
    ON public.documentos FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Documentos podem ser atualizados por usuários autenticados"
    ON public.documentos FOR UPDATE
    USING (auth.role() = 'authenticated');

CREATE POLICY "Documentos podem ser deletados por usuários autenticados"
    ON public.documentos FOR DELETE
    USING (auth.role() = 'authenticated');

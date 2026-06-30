-- =============================================================================
-- FrotaCheck — Tabela de Viagens (módulo "Minha Viagem" / "Controle de Viagens")
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Pré-requisito: supabase_rbac_migration.sql já deve ter sido executado
-- (cria public.empresas, get_my_empresa_id(), get_my_role()).
--
-- Correção: a versão anterior deste arquivo referenciava public.veiculos e
-- public.motoristas (nomes que nunca existiram no schema atual — as tabelas
-- reais são public.vehicles e public.drivers). Isso fazia o CREATE TABLE
-- falhar na validação da FK e a tabela public.viagens nunca era criada,
-- causando o erro "Could not find table public.viagens" em tempo de execução.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.viagens (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id                uuid REFERENCES public.empresas(id) ON DELETE CASCADE,
    veiculo_id                uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
    motorista_id              uuid NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
    data_inicio               timestamptz NOT NULL DEFAULT now(),
    data_fim                  timestamptz,
    origem                    text NOT NULL,
    destino                   text NOT NULL,
    quilometragem_inicio      numeric(10, 1) NOT NULL,
    quilometragem_fim         numeric(10, 1),
    quilometragem_percorrida  numeric(10, 1),
    duracao_minutos           integer,
    localizacao_inicio        text,
    localizacao_fim           text,
    status                    text NOT NULL DEFAULT 'em_progresso'
                                  CHECK (status IN ('em_progresso', 'concluida', 'cancelada')),
    fotos_rota                text[] NOT NULL DEFAULT ARRAY[]::text[],
    consumo_litros            numeric(10, 2),
    custo_total                numeric(10, 2),
    observacoes               text,
    criado_em                 timestamptz NOT NULL DEFAULT now(),
    atualizado_em             timestamptz NOT NULL DEFAULT now()
);

-- Índices para Viagens
CREATE INDEX IF NOT EXISTS idx_viagens_empresa_id   ON public.viagens(empresa_id);
CREATE INDEX IF NOT EXISTS idx_viagens_veiculo_id   ON public.viagens(veiculo_id);
CREATE INDEX IF NOT EXISTS idx_viagens_motorista_id ON public.viagens(motorista_id);
CREATE INDEX IF NOT EXISTS idx_viagens_status       ON public.viagens(status);
CREATE INDEX IF NOT EXISTS idx_viagens_data_inicio  ON public.viagens(data_inicio DESC);

-- RLS de Viagens — segue o mesmo padrão de isolamento por empresa do restante
-- do sistema (supabase_rbac_migration.sql), em vez de liberar para qualquer
-- usuário autenticado de qualquer empresa.
ALTER TABLE public.viagens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Viagens são visíveis para todos os usuários autenticados" ON public.viagens;
DROP POLICY IF EXISTS "Viagens podem ser criadas por usuários autenticados" ON public.viagens;
DROP POLICY IF EXISTS "Viagens podem ser atualizadas por usuários autenticados" ON public.viagens;
DROP POLICY IF EXISTS "empresa_isolation" ON public.viagens;

CREATE POLICY "empresa_isolation" ON public.viagens
    FOR ALL TO authenticated
    USING  (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
    WITH CHECK (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

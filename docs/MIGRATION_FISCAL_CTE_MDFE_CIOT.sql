-- =============================================================================
-- FrotaCheck — Documentos Fiscais (CT-e / MDF-e / CIOT)
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Pré-requisito: supabase_rbac_migration.sql já deve ter sido executado
-- (cria public.empresas, get_my_empresa_id(), get_my_role()).
--
-- Fase 1 desta feature: CT-e. As tabelas de MDF-e/CIOT já são criadas aqui
-- (schema deliberadamente simples, evita retrabalho de migração depois) mas
-- não têm Edge Function/UI ainda — ficam "em breve" na tela.
-- =============================================================================

-- ─── 1. COLUNAS FISCAIS EM public.empresas ───────────────────────────────────
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS razao_social       text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS inscricao_estadual text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS rntrc              text;
ALTER TABLE public.empresas ADD COLUMN IF NOT EXISTS uf                 text;

-- ─── 2. COLUNAS FISCAIS EM public.company_settings ───────────────────────────
-- Metadados do certificado apenas (nunca o arquivo .pfx nem a senha — esses
-- ficam só no servidor próprio do wrapper ACBr, fora do Supabase).
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS cte_habilitado            boolean DEFAULT false;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS mdfe_habilitado           boolean DEFAULT false;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS ciot_habilitado           boolean DEFAULT false;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS ambiente_fiscal           text DEFAULT 'homologacao' CHECK (ambiente_fiscal IN ('homologacao','producao'));
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS certificado_status        text DEFAULT 'nao_configurado' CHECK (certificado_status IN ('nao_configurado','ativo','vencido','erro'));
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS certificado_cn            text;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS certificado_validade      date;
ALTER TABLE public.company_settings ADD COLUMN IF NOT EXISTS certificado_atualizado_em timestamptz;

-- ─── 3. NUMERAÇÃO FISCAL (contador com lock real, não "select max+1") ────────
CREATE TABLE IF NOT EXISTS public.fiscal_numeracao (
    empresa_id      uuid NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    tipo            text NOT NULL CHECK (tipo IN ('cte','mdfe')),
    serie           integer NOT NULL DEFAULT 1,
    proximo_numero  integer NOT NULL DEFAULT 1,
    PRIMARY KEY (empresa_id, tipo, serie)
);

ALTER TABLE public.fiscal_numeracao ENABLE ROW LEVEL SECURITY;

-- Só a Edge Function (service-role) mexe nessa tabela — nenhuma policy para
-- 'authenticated'. RLS habilitado sem nenhuma policy = ninguém além do
-- service-role (que ignora RLS) consegue ler/escrever.

-- Incrementa e devolve o próximo número atomicamente (evita a corrida de
-- "select max+1" quando duas emissões da mesma empresa acontecem juntas).
CREATE OR REPLACE FUNCTION public.fiscal_proximo_numero(p_empresa_id uuid, p_tipo text, p_serie integer DEFAULT 1)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_numero integer;
BEGIN
  INSERT INTO public.fiscal_numeracao (empresa_id, tipo, serie, proximo_numero)
  VALUES (p_empresa_id, p_tipo, p_serie, 2)
  ON CONFLICT (empresa_id, tipo, serie)
  DO UPDATE SET proximo_numero = public.fiscal_numeracao.proximo_numero + 1
  RETURNING proximo_numero - 1 INTO v_numero;
  RETURN v_numero;
END;
$$;

-- Só a Edge Function (via client service-role) deve poder chamar isso.
REVOKE EXECUTE ON FUNCTION public.fiscal_proximo_numero(uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fiscal_proximo_numero(uuid, text, integer) TO service_role;

-- ─── 4. public.cte_documentos ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cte_documentos (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id            uuid NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    viagem_id             uuid REFERENCES public.viagens(id) ON DELETE SET NULL,
    veiculo_id            uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
    motorista_id          uuid REFERENCES public.drivers(id) ON DELETE SET NULL,
    numero_cte            integer,
    serie                 integer,
    chave_acesso          text UNIQUE,
    ambiente              text NOT NULL CHECK (ambiente IN ('homologacao','producao')),
    remetente_nome        text,
    remetente_doc         text,
    destinatario_nome     text,
    destinatario_doc      text,
    natureza_carga        text,
    valor_carga           numeric(12,2),
    valor_frete           numeric(12,2),
    peso_bruto            numeric(10,2),
    status                text NOT NULL DEFAULT 'rascunho'
                              CHECK (status IN ('rascunho','enviando','autorizado','rejeitado','denegado','cancelado','erro')),
    protocolo_autorizacao text,
    motivo_rejeicao       text,
    xml_autorizado_url    text,
    danfe_pdf_url         text,
    criado_por            uuid,
    criado_em             timestamptz NOT NULL DEFAULT now(),
    enviado_em            timestamptz,
    autorizado_em         timestamptz
);

CREATE INDEX IF NOT EXISTS idx_cte_documentos_empresa_id ON public.cte_documentos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_cte_documentos_viagem_id  ON public.cte_documentos(viagem_id);
CREATE INDEX IF NOT EXISTS idx_cte_documentos_status     ON public.cte_documentos(status);

-- RLS de cte_documentos — desvio deliberado do padrão usual do projeto: aqui
-- RLS não é só isolamento de tenant, também é controle fino de estado, porque
-- chave_acesso/protocolo_autorizacao/status='autorizado' são fatos legais
-- vindos da SEFAZ e um bug no cliente Flutter não pode fabricar isso.
ALTER TABLE public.cte_documentos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cte_documentos_select" ON public.cte_documentos;
CREATE POLICY "cte_documentos_select" ON public.cte_documentos
    FOR SELECT TO authenticated
    USING (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- INSERT/UPDATE direto do Flutter só é permitido para rascunhos (a seção de
-- carga da Nova Viagem grava aqui). Toda transição real de estado (autorizado/
-- rejeitado, chave_acesso, XML/PDF) é escrita só pela Edge Function via
-- service-role, que ignora RLS.
DROP POLICY IF EXISTS "cte_documentos_insert_rascunho" ON public.cte_documentos;
CREATE POLICY "cte_documentos_insert_rascunho" ON public.cte_documentos
    FOR INSERT TO authenticated
    WITH CHECK (
        (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
        AND status = 'rascunho'
    );

DROP POLICY IF EXISTS "cte_documentos_update_rascunho" ON public.cte_documentos;
CREATE POLICY "cte_documentos_update_rascunho" ON public.cte_documentos
    FOR UPDATE TO authenticated
    USING      ((empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER') AND status = 'rascunho')
    WITH CHECK ((empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER') AND status = 'rascunho');

-- ─── 5. public.mdfe_documentos + public.mdfe_cte (Fase 2 — schema já criado) ─
CREATE TABLE IF NOT EXISTS public.mdfe_documentos (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id            uuid NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    numero_mdfe           integer,
    serie                 integer,
    chave_acesso          text UNIQUE,
    ambiente              text NOT NULL CHECK (ambiente IN ('homologacao','producao')),
    status                text NOT NULL DEFAULT 'rascunho'
                              CHECK (status IN ('rascunho','enviando','autorizado','rejeitado','denegado','cancelado','encerrado','erro')),
    protocolo_autorizacao text,
    motivo_rejeicao       text,
    xml_autorizado_url    text,
    criado_por            uuid,
    criado_em             timestamptz NOT NULL DEFAULT now(),
    enviado_em            timestamptz,
    autorizado_em         timestamptz,
    encerrado_em          timestamptz
);

CREATE TABLE IF NOT EXISTS public.mdfe_cte (
    mdfe_id uuid NOT NULL REFERENCES public.mdfe_documentos(id) ON DELETE CASCADE,
    cte_id  uuid NOT NULL REFERENCES public.cte_documentos(id) ON DELETE CASCADE,
    PRIMARY KEY (mdfe_id, cte_id)
);

CREATE INDEX IF NOT EXISTS idx_mdfe_documentos_empresa_id ON public.mdfe_documentos(empresa_id);

ALTER TABLE public.mdfe_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdfe_cte        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mdfe_documentos_select" ON public.mdfe_documentos;
CREATE POLICY "mdfe_documentos_select" ON public.mdfe_documentos
    FOR SELECT TO authenticated
    USING (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

DROP POLICY IF EXISTS "mdfe_cte_select" ON public.mdfe_cte;
CREATE POLICY "mdfe_cte_select" ON public.mdfe_cte
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.mdfe_documentos m
            WHERE m.id = mdfe_cte.mdfe_id
              AND (m.empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
        )
    );

-- Sem policy de INSERT/UPDATE para 'authenticated' em nenhuma das duas —
-- Fase 2 (emissão de MDF-e) ainda não existe, escrita fica só para
-- service-role até a Edge Function correspondente ser construída.

-- ─── 6. public.ciot_registros (Fase 3 — schema solto de propósito) ───────────
CREATE TABLE IF NOT EXISTS public.ciot_registros (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id        uuid NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    mdfe_id           uuid REFERENCES public.mdfe_documentos(id) ON DELETE SET NULL,
    numero_ciot       text,
    status            text NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','registrado','erro','cancelado')),
    ambiente          text,
    payload_enviado   jsonb,
    resposta_recebida jsonb,
    criado_em         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ciot_registros_empresa_id ON public.ciot_registros(empresa_id);

ALTER TABLE public.ciot_registros ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ciot_registros_select" ON public.ciot_registros;
CREATE POLICY "ciot_registros_select" ON public.ciot_registros
    FOR SELECT TO authenticated
    USING (empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');

-- ─── 7. Bucket de Storage privado para XML/DANFE ─────────────────────────────
-- Diferente de avatars/logos/documentos (públicos) — XML assinado e DANFE são
-- mais sensíveis que uma foto de CNH. Leitura só via signed URL. Escrita só
-- pelo service-role (a Edge Function gera o arquivo no servidor fiscal e faz
-- upload ela mesma — nunca upload direto do cliente Flutter).
INSERT INTO storage.buckets (id, name, public)
VALUES ('documentos-fiscais', 'documentos-fiscais', false)
ON CONFLICT (id) DO NOTHING;

-- Sem nenhuma policy de storage.objects para 'authenticated' neste bucket —
-- toda leitura passa por signed URL (gerada via service-role na Edge
-- Function), toda escrita é feita pela Edge Function (service-role, ignora
-- RLS). Isso é intencional: nem SELECT direto do bucket é permitido para
-- usuários comuns.

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

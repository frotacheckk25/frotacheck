-- =============================================================================
-- Módulo de Notificações Push — avisa ADMIN_EMPRESA/GESTOR quando um motorista
-- registra abastecimento, ocorrência, multa, manutenção ou um novo alerta é
-- gerado, mesmo com o app fechado no celular deles.
--
-- Como funciona:
--   1) O app grava o token FCM do dispositivo em public.device_tokens quando
--      o usuário faz login e concede permissão de notificação.
--   2) Um gatilho (AFTER INSERT) nas tabelas fuelings/occurrences/multas/
--      oil_changes/alerts chama a Edge Function "send-push-notification" via
--      pg_net, passando a linha nova.
--   3) A Edge Function busca quem é ADMIN_EMPRESA/GESTOR daquela empresa,
--      pega os tokens deles em device_tokens, e manda o push via Firebase.
--
-- PRÉ-REQUISITOS antes de rodar este script:
--   - Extensão pg_net habilitada (Dashboard → Database → Extensions → pg_net).
--   - A Edge Function "send-push-notification" já publicada (ver
--     supabase/functions/send-push-notification/index.ts).
--   - A service_role key guardada no Vault (rode substituindo o valor real):
--       select vault.create_secret('<SUA_SERVICE_ROLE_KEY>', 'service_role_key');
--     (pegue a service_role key em Project Settings → API — NUNCA a publishable/anon key)
--
-- Execute no SQL Editor do Supabase.
-- =============================================================================

-- ─── 1. Tabela de tokens de notificação por dispositivo ──────────────────────
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token   text NOT NULL,
  platform    text NOT NULL DEFAULT 'android',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON public.device_tokens(user_id);

CREATE OR REPLACE FUNCTION public._touch_device_token_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_device_tokens_updated_at ON public.device_tokens;
CREATE TRIGGER trg_device_tokens_updated_at
  BEFORE UPDATE ON public.device_tokens
  FOR EACH ROW EXECUTE FUNCTION public._touch_device_token_updated_at();

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Cada usuário só gerencia o próprio token (o app grava/atualiza o token do
-- próprio aparelho, nunca de outra pessoa).
DROP POLICY IF EXISTS "device_tokens_own" ON public.device_tokens;
CREATE POLICY "device_tokens_own" ON public.device_tokens
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- MASTER pode ver todos os tokens (suporte/depuração).
DROP POLICY IF EXISTS "device_tokens_master_select" ON public.device_tokens;
CREATE POLICY "device_tokens_master_select" ON public.device_tokens
  FOR SELECT TO authenticated
  USING (get_my_role() = 'MASTER');

-- ─── 2. Função que dispara a Edge Function via pg_net ────────────────────────
-- Lê a service_role key do Vault (nunca fica em texto puro no código da
-- função — pg_get_functiondef é legível por qualquer authenticated, então
-- jamais hardcode segredos aqui).
CREATE OR REPLACE FUNCTION public.notify_new_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  service_key text;
  project_url text := 'https://rseefinwtlrjhzosvmgt.supabase.co';
BEGIN
  SELECT decrypted_secret INTO service_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  -- Se o Vault ainda não foi configurado, não bloqueia o insert original —
  -- só não manda a notificação (evita quebrar o registro do motorista).
  IF service_key IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := project_url || '/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := jsonb_build_object('table', TG_TABLE_NAME, 'record', row_to_json(NEW))
  );

  RETURN NEW;
END;
$$;

-- ─── 3. Gatilhos nas tabelas de eventos do motorista ──────────────────────────
DROP TRIGGER IF EXISTS trg_notify_new_fueling ON public.fuelings;
CREATE TRIGGER trg_notify_new_fueling
  AFTER INSERT ON public.fuelings
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_event();

DROP TRIGGER IF EXISTS trg_notify_new_occurrence ON public.occurrences;
CREATE TRIGGER trg_notify_new_occurrence
  AFTER INSERT ON public.occurrences
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_event();

DROP TRIGGER IF EXISTS trg_notify_new_multa ON public.multas;
CREATE TRIGGER trg_notify_new_multa
  AFTER INSERT ON public.multas
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_event();

DROP TRIGGER IF EXISTS trg_notify_new_manutencao ON public.oil_changes;
CREATE TRIGGER trg_notify_new_manutencao
  AFTER INSERT ON public.oil_changes
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_event();

-- "alerts" é opcional — só cria o gatilho se a tabela existir neste projeto.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'alerts') THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_notify_new_alert ON public.alerts';
    EXECUTE 'CREATE TRIGGER trg_notify_new_alert AFTER INSERT ON public.alerts FOR EACH ROW EXECUTE FUNCTION public.notify_new_event()';
  END IF;
END $$;

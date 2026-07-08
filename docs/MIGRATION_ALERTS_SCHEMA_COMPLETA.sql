-- =============================================================================
-- Corrige o schema da tabela public.alerts, que estava desatualizado em
-- relação ao que o app Flutter espera em vários pontos (Dashboard, tela de
-- Alertas, resolução de ocorrências, alertas do motorista).
--
-- Schema real encontrado (antes desta migração):
--   id, company_id, title, description, resolved, created_at, empresa_id
--
-- O código do app lê/grava também: status, tipo, subtitle, occurrence_id,
-- vehicle_id, priority, problem_type, titulo, descricao. Sem essas colunas,
-- qualquer consulta que as referencie falha com "column ... does not exist"
-- (42703) — o app tem fallbacks silenciosos para não quebrar a tela, mas a
-- tabela alerts nunca é lida/gravada corretamente de verdade.
--
-- Todas as colunas são adicionadas de forma aditiva (ADD COLUMN IF NOT
-- EXISTS) — nada é removido ou renomeado, então não quebra o que já usa
-- 'resolved'/'company_id'/'title'/'description'.
--
-- Execute no SQL Editor do Supabase.
-- =============================================================================

alter table public.alerts
  add column if not exists status       text not null default 'ativo',
  add column if not exists tipo         text not null default 'info',
  add column if not exists subtitle     text,
  add column if not exists titulo       text,
  add column if not exists descricao    text,
  add column if not exists priority     text,
  add column if not exists problem_type text,
  add column if not exists occurrence_id uuid references public.occurrences(id) on delete set null,
  add column if not exists vehicle_id    uuid references public.vehicles(id) on delete set null;

-- Mantém 'status' e 'resolved' consistentes entre si para linhas já existentes.
update public.alerts
  set status = 'resolvido'
  where resolved = true and status = 'ativo';

create index if not exists idx_alerts_empresa_status on public.alerts(empresa_id, status);
create index if not exists idx_alerts_occurrence on public.alerts(occurrence_id) where occurrence_id is not null;

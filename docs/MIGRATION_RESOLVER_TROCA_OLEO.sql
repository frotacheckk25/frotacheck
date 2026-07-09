-- =============================================================================
-- Permite marcar um registro de "Troca de Óleo" (oil_changes) como Resolvido,
-- exigindo peça/serviço realizado + valor gasto — tanto o motorista quanto
-- gestor/admin/dono podem fazer isso, mas ninguém marca "Resolvido" sem
-- preencher os dois campos (validado no app).
--
-- oil_changes.manutencao_id liga o registro de troca de óleo à linha
-- correspondente em manutencoes (onde já vivem os campos status/cost/valor
-- usados pelo card "Em Manutenção" do dashboard) — sem isso, resolver por
-- aqui nunca refletiria no dashboard.
--
-- Execute no SQL Editor do Supabase.
-- =============================================================================

alter table public.oil_changes
  add column if not exists manutencao_id uuid references public.manutencoes(id) on delete set null;

alter table public.manutencoes
  add column if not exists peca_trocada text;

create index if not exists idx_oil_changes_manutencao on public.oil_changes(manutencao_id) where manutencao_id is not null;

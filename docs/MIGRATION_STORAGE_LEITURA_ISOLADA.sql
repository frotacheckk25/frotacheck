-- =============================================================================
-- ALTO — isola a LEITURA do Storage por empresa nos buckets sensíveis
-- (checklists, multas, documentos, fuelings). Até agora só a ESCRITA tinha
-- sido isolada por pasta de empresa (MIGRATION_STORAGE_ISOLAMENTO_ESCRITA.sql);
-- a leitura permitia que qualquer usuário autenticado, de qualquer empresa,
-- lesse arquivos de outra empresa cliente (fotos de checklist, multa,
-- documentos como CNH).
--
-- Os buckets "avatars" e "logos" ficam de fora deste isolamento de propósito:
-- já têm arquivos reais com nome antigo (sem pasta de empresa), e são menos
-- sensíveis (foto de perfil / logo da empresa) — continuam com leitura
-- autenticada ampla, como já estava.
--
-- PRÉ-REQUISITO: os uploads para checklists/multas/documentos/fuelings já
-- gravam dentro de uma pasta "<empresa_id>/arquivo.ext" desde a migração de
-- escrita isolada — sem isso, esta policy bloquearia a leitura de qualquer
-- arquivo desses 4 buckets.
-- =============================================================================

DROP POLICY IF EXISTS "authenticated_read_frotacheck_buckets" ON storage.objects;

CREATE POLICY "authenticated_read_public_buckets" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id IN ('avatars', 'logos'));

CREATE POLICY "authenticated_read_isolated_buckets" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id IN ('checklists', 'multas', 'documentos', 'fuelings')
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = get_my_empresa_id()::text
    )
  );

-- =============================================================================
-- Isolamento por empresa na ESCRITA dos buckets de Storage.
--
-- Hoje qualquer usuário autenticado, de qualquer empresa, pode gravar em
-- qualquer caminho de qualquer um dos buckets (avatars/checklists/multas/
-- documentos/logos/fuelings) — os nomes de arquivo usam só timestamp, sem
-- isolamento nenhum. O app já foi ajustado para gravar sempre dentro de uma
-- pasta com o empresa_id de quem faz upload (ex.: "abc-123/multa_167....jpg").
--
-- PRÉ-REQUISITO: o deploy que prefixa os uploads por empresa_id já precisa
-- estar no ar (senão os próprios uploads passam a ser rejeitados).
--
-- Isso NÃO muda a leitura (que já é "authenticated" desde
-- MIGRATION_STORAGE_AUTENTICADO.sql) — arquivos antigos (sem pasta) continuam
-- legíveis por qualquer autenticado; só a escrita fica restrita à própria
-- pasta a partir de agora.
-- =============================================================================

DROP POLICY IF EXISTS "authenticated_write_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_write_frotacheck_buckets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id IN ('avatars','checklists','multas','documentos','logos','fuelings')
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = get_my_empresa_id()::text
      OR get_my_empresa_id() IS NULL  -- usuário sem empresa (ex.: cadastro pendente) grava em "sem-empresa"
    )
  );

DROP POLICY IF EXISTS "authenticated_update_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_update_frotacheck_buckets" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id IN ('avatars','checklists','multas','documentos','logos','fuelings')
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = get_my_empresa_id()::text
      OR get_my_empresa_id() IS NULL
    )
  );

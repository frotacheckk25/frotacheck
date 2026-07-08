-- =============================================================================
-- ⚠️ SUPERADO — NÃO EXECUTE ESTE ARQUIVO.
-- Foi útil na época (tirou a leitura pública), mas a policy que ele cria
-- ("authenticated_read_frotacheck_buckets") não isola por empresa — qualquer
-- autenticado lê arquivo de qualquer empresa. Isso já foi substituído por
-- docs/MIGRATION_STORAGE_LEITURA_ISOLADA.sql (isola checklists/multas/
-- documentos/fuelings por pasta de empresa). Rodar este arquivo de novo
-- desfaria esse isolamento. Mantido só como histórico.
-- =============================================================================
-- Fecha o vazamento público dos buckets de Storage (avatars/checklists/
-- multas/documentos/logos/fuelings): hoje qualquer pessoa sem login consegue
-- listar e baixar fotos reais de qualquer empresa cliente.
--
-- PRÉ-REQUISITO: o deploy que troca Image.network por SignedNetworkImage
-- (URLs assinadas via createSignedUrl) já precisa estar no ar e testado -
-- confirme abrindo o app e vendo se fotos de checklist, avatar e logo
-- continuam aparecendo normalmente ANTES de rodar este script. Depois que
-- a leitura virar "authenticated", qualquer foto que ainda dependa de link
-- público direto vai parar de carregar.
--
-- Depois de rodar este script, todo download de arquivo desses buckets
-- exige um usuário autenticado (RLS de storage.objects). Não muda mais nada
-- no app — SignedNetworkImage já resolve isso.
-- =============================================================================

DROP POLICY IF EXISTS "public_read_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_read_frotacheck_buckets" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id IN ('avatars','checklists','multas','documentos','logos','fuelings'));

-- As policies de escrita (INSERT/UPDATE) já eram "TO authenticated" e não mudam.

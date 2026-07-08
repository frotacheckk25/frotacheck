-- =============================================================================
-- ⚠️ SUPERADO — NÃO EXECUTE ESTE ARQUIVO.
-- Cria o bucket 'fuelings' como public=true e uma policy de leitura pública
-- (role "public") para TODOS os buckets — mesma vulnerabilidade crítica já
-- corrigida por docs/MIGRATION_URGENTE_STORAGE_PUBLIC_FLAG.sql +
-- docs/MIGRATION_STORAGE_AUTENTICADO.sql + MIGRATION_STORAGE_LEITURA_ISOLADA.sql.
-- Se o bucket 'fuelings' precisar ser recriado, use public=false e as
-- migrações de Storage mais recentes. Mantido só como histórico.
-- =============================================================================
-- Corrige upload de fotos de abastecimento (hodômetro/bomba/cupom) quebrado
-- em produção: lib/home/abastecimentos/abastecimentos_page.dart faz upload
-- para o bucket 'fuelings', mas ele nunca foi criado em
-- docs/MIGRATION_EMPRESA_LOGO_CONFIG.sql (só avatars/checklists/multas/
-- documentos/logos). O upload falha (após 3 tentativas com backoff) e o
-- abastecimento é salvo sem nenhuma foto, silenciosamente.
-- =============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('fuelings', 'fuelings', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "public_read_frotacheck_buckets" ON storage.objects;
CREATE POLICY "public_read_frotacheck_buckets" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id IN ('avatars','checklists','multas','documentos','logos','fuelings'));

DROP POLICY IF EXISTS "authenticated_write_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_write_frotacheck_buckets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id IN ('avatars','checklists','multas','documentos','logos','fuelings'));

DROP POLICY IF EXISTS "authenticated_update_frotacheck_buckets" ON storage.objects;
CREATE POLICY "authenticated_update_frotacheck_buckets" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id IN ('avatars','checklists','multas','documentos','logos','fuelings'));

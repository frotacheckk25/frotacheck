-- =============================================================================
-- Estende o isolamento de LEITURA por empresa para os buckets "avatars" e
-- "logos" — MIGRATION_STORAGE_LEITURA_ISOLADA.sql já tinha isolado
-- checklists/multas/documentos/fuelings, mas deixou avatars/logos de fora
-- de propósito (comentário na própria migração: "menos sensível" + risco de
-- arquivo legado sem pasta). João pediu para isolar esses dois também.
--
-- PRÉ-REQUISITO já cumprido: a ESCRITA de avatars/logos já é isolada por
-- pasta "<empresa_id>/arquivo.ext" desde MIGRATION_STORAGE_ISOLAMENTO_ESCRITA.sql
-- (motorista_home_page.dart e configuracoes_page.dart já fazem upload nesse
-- formato). Então todo avatar/logo enviado pelo app a partir daquela
-- migração já está na pasta certa.
--
-- ATENÇÃO — mesmo efeito colateral que ocorreu ao isolar os outros 4
-- buckets: qualquer avatar/logo enviado ANTES da escrita ser isolada (nome
-- de arquivo achatado, sem pasta de empresa) fica ilegível para todo mundo,
-- inclusive o próprio dono, depois deste script (a pasta requerida não
-- existe no nome do arquivo). Se isso acontecer, o usuário só precisa
-- reenviar a foto/logo — o upload já grava no lugar certo.
--
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query).
-- Idempotente — pode rodar mais de uma vez sem erro.
-- =============================================================================

DROP POLICY IF EXISTS "authenticated_read_public_buckets" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_read_isolated_buckets" ON storage.objects;

CREATE POLICY "authenticated_read_isolated_buckets" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id IN ('checklists', 'multas', 'documentos', 'fuelings', 'avatars', 'logos')
    AND (
      get_my_role() = 'MASTER'
      OR (storage.foldername(name))[1] = get_my_empresa_id()::text
    )
  );

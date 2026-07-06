-- =============================================================================
-- CORREÇÃO URGENTE — CRÍTICA — VAZAMENTO DE DADOS PESSOAIS REAIS, CONFIRMADO AO VIVO
--
-- A migração MIGRATION_STORAGE_AUTENTICADO.sql trocou a POLICY de RLS de leitura
-- de "public" para "authenticated", mas NUNCA trocou a flag public=true da
-- própria tabela storage.buckets. O Supabase Storage tem um endpoint
-- /storage/v1/object/public/<bucket>/<path> que IGNORA COMPLETAMENTE as
-- policies de RLS quando o bucket está marcado como público — é um bypass
-- estrutural, documentado, não um bug do Supabase.
--
-- CONFIRMADO AO VIVO agora mesmo: uma foto de perfil real foi baixada do
-- bucket "avatars" com um curl SEM NENHUM header de autenticação (nem apikey).
-- A listagem pública também funciona (POST /object/list/avatars retorna
-- nomes de arquivo reais).
--
-- Esta é a causa raiz do vazamento — a policy de RLS estava certa, a
-- configuração do bucket é que nunca foi corrigida.
-- =============================================================================

UPDATE storage.buckets
SET public = false
WHERE id IN ('avatars', 'checklists', 'multas', 'documentos', 'logos', 'fuelings');

-- Verificação: deve retornar 6 linhas, todas com public = false
SELECT id, public FROM storage.buckets
WHERE id IN ('avatars', 'checklists', 'multas', 'documentos', 'logos', 'fuelings');

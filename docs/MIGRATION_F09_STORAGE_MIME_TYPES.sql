-- =============================================================================
-- FrotaCheck — F-09 da auditoria de segurança: os buckets de Storage não
-- tinham NENHUMA restrição de tipo/tamanho de arquivo no servidor — o
-- Content-Type era decidido só pelo client (Flutter), contornável. Aqui
-- fixamos uma defesa em profundidade real no lado do banco, independente
-- do que o app envie.
-- =============================================================================

-- Fotos (veículo, motorista/avatar, logo, checklist, multa, abastecimento):
-- só imagens, até 8MB (o client já comprime via image_picker antes de
-- enviar, então isso é generoso, não deve afetar uso legítimo).
update storage.buckets
set allowed_mime_types = array['image/jpeg','image/png','image/webp'],
    file_size_limit = 8388608 -- 8 MB
where id in ('veiculos','avatars','logos','checklists','multas','fuelings');

-- Documentos gerais (CNH, comprovantes etc.) — aceita o mesmo conjunto que
-- o FilePicker do app já oferece (documentos_page.dart): pdf/jpg/png/doc/docx.
update storage.buckets
set allowed_mime_types = array[
      'application/pdf','image/jpeg','image/png',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ],
    file_size_limit = 15728640 -- 15 MB
where id = 'documentos';

-- Documentos fiscais (XML/DANFE) — só a Edge Function escreve aqui
-- (service-role, ignora RLS/allowed_mime_types de qualquer forma), mas
-- vale deixar explícito o que esse bucket deveria conter.
update storage.buckets
set allowed_mime_types = array['application/xml','text/xml','application/pdf'],
    file_size_limit = 10485760 -- 10 MB
where id = 'documentos-fiscais';

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

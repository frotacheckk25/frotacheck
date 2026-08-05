-- =============================================================================
-- FrotaCheck — Foto do motorista
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
--
-- Contexto: cliente pediu para o motorista OU o admin/gestor poderem colocar
-- uma foto real do motorista (câmera ou galeria), igual já fizemos para
-- veículos. Campo novo e independente de user_profiles.avatar_url (que é a
-- foto de conta genérica, usada em qualquer papel, não só motorista) —
-- drivers.foto_url é a foto do CADASTRO do motorista na frota, editável
-- tanto pelo admin/gestor (tela de Motoristas) quanto pelo próprio motorista
-- (tela "Meu Perfil"), convergindo no mesmo campo.
-- =============================================================================

ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS foto_url text;

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

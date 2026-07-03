-- =============================================================================
-- FrotaCheck — Permite UPDATE em registros legados com empresa_id nulo
-- Erro original: "new row violates row-level security policy for table
-- viagens" ao concluir uma viagem antiga (criada antes do empresa_id ser
-- preenchido de forma consistente).
--
-- As policies "empresa_isolation" já tinham USING (permite SELECT/leitura)
-- com "empresa_id IS NULL OR ...", mas o WITH CHECK (que valida a LINHA
-- RESULTANTE de um UPDATE/INSERT) exigia empresa_id = sua_empresa sem
-- aceitar nulo. Como o UPDATE de concluir viagem não altera empresa_id,
-- se a linha já tinha empresa_id nulo, a linha resultante continua nula
-- e o WITH CHECK reprovava — mesmo o usuário tendo permissão de editar.
--
-- Esta migration alinha o WITH CHECK com o USING em todas as tabelas
-- operacionais, permitindo editar registros legados (empresa_id nulo)
-- sem abrir brecha entre empresas diferentes.
-- Execute no SQL Editor do Supabase (Dashboard → SQL Editor → New query)
-- =============================================================================

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'vehicles','drivers','fuelings','oil_changes','multas','occurrences',
    'manutencoes','documentos','pneus','checklists'
  ]
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "empresa_isolation" ON public.%I;
       CREATE POLICY "empresa_isolation" ON public.%I
         FOR ALL TO authenticated
         USING      (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = ''MASTER'')
         WITH CHECK (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = ''MASTER'');',
      t, t
    );
  END LOOP;
END $$;

-- viagens e alerts podem não existir em todo ambiente — trata separado
DO $$ BEGIN
  DROP POLICY IF EXISTS "empresa_isolation" ON public.viagens;
  CREATE POLICY "empresa_isolation" ON public.viagens
    FOR ALL TO authenticated
    USING      (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
    WITH CHECK (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');
EXCEPTION WHEN undefined_table THEN NULL; END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "empresa_isolation" ON public.alerts;
  CREATE POLICY "empresa_isolation" ON public.alerts
    FOR ALL TO authenticated
    USING      (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER')
    WITH CHECK (empresa_id IS NULL OR empresa_id = get_my_empresa_id() OR get_my_role() = 'MASTER');
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- =============================================================================
-- FIM DA MIGRAÇÃO
-- =============================================================================

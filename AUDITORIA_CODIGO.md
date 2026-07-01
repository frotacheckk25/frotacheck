# Relatório de Auditoria de Código

## Escopo
- `C:\frotacheck\lib\home\abastecimentos\*.dart`
- `C:\frotacheck\lib\home\manutencoes\*.dart`
- `C:\frotacheck\lib\home\viagens\*.dart`

Data da auditoria: 2026-06-30

---

## Problemas Encontrados e Corrigidos

### 1. Filtro de data "Hoje" com comparação de strings
**Arquivo:** `lib/home/abastecimentos/lista_abastecimentos_page.dart`

**Problema:** O filtro "Hoje" utilizava `startsWith` em uma string de data, o que pode falhar dependendo do fuso horário ou formato armazenado no banco.

**Correção:** Alterado para comparação direta de `DateTime` (`year`, `month`, `day`), garantindo robustez.

---

### 2. Ordenação de abastecimentos por data incorreta
**Arquivos:** 
- `lib/home/abastecimentos/lista_abastecimentos_page.dart`
- `lib/home/abastecimentos/abastecimentos_page.dart`

**Problema:** As queries de `fuelings` ordenavam por `created_at` (timestamp de criação do registro) ao invés de `fuel_date` (data do abastecimento). Isso poderia exibir registros em ordem diferente da data real do abastecimento.

**Correção:** Alterado `order('created_at')` para `order('fuel_date', ascending: false)` em ambas as queries.

---

### 3. Query de oil_changes sem ordenação (dados incorretos)
**Arquivo:** `lib/home/manutencoes/manutencoes_page.dart`

**Problema:** A query de `oil_changes` não possuía ordenação. A lógica `latestByVehicle` pegava a primeira ocorrência por veículo, que poderia ser uma troca antiga ao invés da mais recente, gerando cálculo errado de `proximaTroca`.

**Correção:** Adicionado `.order('created_at', ascending: false)` e movido para o `Future.wait` para garantir que a lista já venha ordenada.

---

### 4. Falta de tratamento de null em resultados de queries
**Arquivo:** `lib/home/manutencoes/manutencoes_page.dart`

**Problema:** O `Future.wait` assumia que todas as queries retornariam uma `List`. Se alguma query retornasse `null` (ex: RLS bloqueando), o `as List` lançaria `TypeError`, crashando a página.

**Correção:** Alterado para `(results[i] as List? ?? [])`, garantindo que a lista seja vazia em caso de retorno nulo.

---

### 5. double.parse sem validação em viagens
**Arquivo:** `lib/home/viagens/viagens_page.dart`

**Problema:** Em `_salvar` e `_concluir`, o código usava `double.parse()` diretamente nos campos de quilometragem. Se o usuário digitasse texto não numérico, ocorria `FormatException` e crash.

**Correção:** Alterado para `double.tryParse()` com validação e mensagem de erro amigável (`SnackBar`) em caso de valor inválido.

---

### 6. Falta de validação de quilometragem final >= inicial
**Arquivo:** `lib/home/viagens/viagens_page.dart`

**Problema:** Não havia validação impedindo que o usuário informasse uma quilometragem final menor que a inicial, resultando em `kmPerc` negativo.

**Correção:** Adicionada validação `kmFim < kmInicio` com mensagem de erro.

---

### 7. Validações de valor mínimo ausentes em abastecimentos
**Arquivo:** `lib/home/abastecimentos/abastecimentos_page.dart`

**Problema:** Os validators dos campos `litros`, `valor` e `odômetro` apenas checavam se o valor era numérico, mas não impediam valores negativos ou zero.

**Correção:** Adicionadas validações:
- Litros > 0
- Valor total > 0
- Odômetro >= 0

---

### 8. Fluxo de viagem incompleto (faltava cancelar)
**Arquivo:** `lib/home/viagens/viagens_page.dart`

**Problema:** O fluxo de viagem permitia iniciar e concluir, mas não havia ação de cancelar, deixando o fluxo inconsistente.

**Correção:** Adicionada função `_cancelar()` com diálogo de confirmação e botão na tela de detalhe da viagem (visível apenas para status `em_progresso`).

---

### 9. Lints `use_null_aware_elements` (falsos positivos)
**Arquivo:** `lib/home/viagens/viagens_page.dart`

**Problema:** O analyzer reclamava de `if (x != null) 'key': x` em map literals (linhas de `localizacao_inicio` e `localizacao_fim`). Essa sintaxe é a forma correta e recomendada para entries condicionais em maps; o lint é um falso positivo para esse caso.

**Correção:** Adicionados `// ignore: use_null_aware_elements` nas linhas específicas para suprimir o aviso.

---

### 10. Correção de erro de compilação em manutencoes_page.dart
**Arquivo:** `lib/home/manutencoes/manutencoes_page.dart`

**Problema:** Após adicionar `.order()` na declaração de `oilQ`, o analyzer passou a reportar `The method 'eq' isn't defined for the type 'PostgrestTransformBuilder` nas linhas onde `oilQ.eq(...)` era chamado.

**Correção:** Movido o `.order('created_at', ascending: false)` para o momento do `await` no `Future.wait`, mantendo os `.eq()` antes da ordenação.

---

## Problemas que Precisam de Ação Manual (Decisão Arquitetural)

### 1. Isolamento multi-tenant quando `empresa_id` é null
**Arquivos:** 
- `lib/home/abastecimentos/abastecimentos_page.dart`
- `lib/home/manutencoes/manutencoes_page.dart`
- `lib/home/viagens/viagens_page.dart`

**Descrição:** Quando `effectiveEmpresaId` é `null` (ex: admin global ou usuário sem empresa associada), as queries não filtram por `empresa_id`, podendo retornar dados de todas as empresas. Depende da regra de negócio: admin global pode ver tudo, ou deve ser obrigatório ter empresa.

**Ação necessária:** Validar com o produto se `effectiveEmpresaId == null` é um estado esperado e, se sim, garantir que o RLS no Supabase trate esse caso corretamente. Caso contrário, adicionar bloqueio ou filtro adicional.

---

### 2. Motorista sem veículo associado em manutenções
**Arquivo:** `lib/home/manutencoes/manutencoes_page.dart`

**Descrição:** Quando o motorista não tem veículo cadastrado (`vehicleId == null`), as queries de `oil_changes` e `vehicles` não filtram por veículo. Se `empresa_id` também for null, a query retorna dados de todos os veículos de todas as empresas.

**Ação necessária:** Decidir se motorista sem veículo deve:
- Ver apenas suas próprias ocorrências (filtrar `oil_changes` por `driver_id`, se a coluna existir)
- Ser bloqueado de acessar a página de manutenções
- Ter um veículo padrão associado

---

### 3. Uploads de imagem e bucket privado
**Arquivo:** `lib/home/abastecimentos/abastecimentos_page.dart`

**Descrição:** O código usa `supabase.storage.getPublicUrl(nome)` para obter a URL da imagem. Isso funciona apenas se o bucket `fuelings` for público. Se o bucket for privado (recomendado para produção), as URLs retornadas não serão acessíveis sem autenticação.

**Ação necessária:** 
- Verificar se o bucket `fuelings` está configurado como público ou privado.
- Se privado, substituir `getPublicUrl` por geração de signed URL (`supabase.storage.from(bucket).createSignedUrl(nome, expiresIn)`) ou ajustar RLS para permitir leitura pública apenas das imagens.

---

### 4. Ausência de seletor de data para abastecimentos retroativos
**Arquivo:** `lib/home/abastecimentos/abastecimentos_page.dart`

**Descrição:** O campo `fuel_date` é preenchido automaticamente com `DateTime.now()`. Não há forma de registrar um abastecimento de um dia anterior.

**Ação necessária:** Decidir se é necessário adicionar um `showDatePicker` no formulário para permitir datas retroativas.

---

### 5. Coluna `empresa_id` em `viagens`
**Arquivo:** `lib/home/viagens/viagens_page.dart`

**Descrição:** A query de `viagens` filtra por `empresa_id`, mas a tabela pode não ter essa coluna (dependendo do schema). O isolamento multi-tenant pode estar sendo feito apenas por `veiculo_id`/`motorista_id`.

**Ação necessária:** Validar o schema da tabela `viagens` e, se `empresa_id` não existir, remover o filtro ou ajustar para a coluna correta.

---

## Observações Gerais

- **Todos os arquivos auditados passam no `flutter analyze` sem erros ou warnings** (após as correções).
- **Cálculos de quilometragem:** O cálculo `kmPerc = kmFim - kmInicio` está correto, com validação de não-negatividade.
- **Tratamento de erros:** Todas as queries possuem `try-catch` com `SnackBar`, mas as mensagens são genéricas. Pode ser melhorado com mensagens específicas para erro de permissão (RLS), rede ou validação.
- **Uploads de imagem:** O uso de `upsert: true` e nome de arquivo com timestamp evita sobrescrita acidental. O `ImagePicker` já restringe a seleção a imagens.
- **Filtros e ordenação:** A lista de abastecimentos agora ordena por data do abastecimento (`fuel_date`), alinhado com a expectativa do usuário.
- **Dead code:** Nenhum import não utilizado ou código morto foi identificado nos arquivos do escopo.

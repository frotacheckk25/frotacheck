# Auditoria de prontidão — 19/10/2026

Preparação para o 1º cliente (11 veículos no início; meta de suportar 500).

## Veredito

Pronto para começar com 11 carros. Contratar o plano Pro do Supabase em até
2 meses (espaço de fotos do plano grátis acaba e não há backup).

## Testado (produção, empresa demo "Transportes Horizonte")

- Isolamento entre empresas (RLS nas 26 tabelas, storage, tentativa de
  autopromoção a MASTER — revertida pelo gatilho), isolamento do motorista.
- Fluxos de ponta a ponta como gestor (desktop) e motorista (celular):
  checklist saída/retorno com 6 fotos, abastecimento com 3 fotos, veículo e
  motorista (criar/editar/excluir/vincular conta), troca de óleo, ocorrência,
  multa, documento, pneu, viagem (iniciar/concluir), relatórios e PDF,
  cabeçalho do dashboard, configurações.
- Números do dashboard e relatórios conferidos contra o banco.
- Estresse somente leitura: 50 usuários simultâneos, 0 erros, p95 1,5 s.

## Corrigido (commits 227f12a → f7c5c15)

- Histórico de checklists paginado e filtrado no banco (antes: só 500).
- Documentos, multas, ocorrências e trocas de óleo sem limite fixo.
- Fotos de abastecimento limitadas a 1280 px.
- App em pt-BR (`flutter_localizations`): calendários estavam em inglês.
- Formatação BR de moeda/litros (`lib/core/utils/formato_br.dart`).
- Gasto do mês e minigráficos pela data do serviço/infração.
- PDF do relatório: caracteres fora da fonte e fundo sob degradês.
- Viagens: lista todos os motoristas (antes só os com conta no app).
- Teto de KM (3.000.000) em troca de óleo, veículo e viagens.
- Acesso sem e-mail: senha inicial definida por quem cadastra e função
  `admin-redefinir-senha` (botão "Redefinir senha" em Usuários).
- Push: `send-push-notification` com `verify_jwt = false` e `trim()` na senha.

## Configuração feita no painel do Supabase

- **Authentication → Sign In / Providers**
  - Provedor **Email: ENABLED** (se desligar, ninguém faz login).
  - **Confirm email: desligado** — contas entram na hora, sem e-mail.
  - "Secure email change": desligado (e-mails internos não recebem link).
- **Push**: senha aleatória no Vault (`service_role_key`, lida pelo gatilho
  `notify_new_event`) igual ao secret `PUSH_TRIGGER_SECRET` da função.
  Publicar a função sempre com `--no-verify-jwt` (já está no `config.toml`).

## Capacidade do plano gratuito

Cada carro gera ~40 MB/mês de fotos (2 checklists/dia × 6 fotos + abastecimentos).
Espaço grátis: 1 GB → 11 carros ≈ 2 meses; 20 carros ≈ 1 mês. Banco, acessos
simultâneos e notificações não são o gargalo. Pro: 100 GB (~200 carros por 1 ano).

## Pendências

1. Plano Pro do Supabase (US$ 25/mês) em até 2 meses.
2. Trocar a chave `service_role` legada (foi exposta durante a configuração)
   e desativar as chaves antigas — nada do sistema depende mais dela.
3. Gerar APK novo e testar o push no celular do gestor.
4. CT-e/MDF-e não testados (cliente ainda não usará).
5. Opcional: no checklist do motorista, pré-selecionar o único veículo dele.

## Contas de teste (empresa demo)

- Admin: `frotafrtotacheck+demo@gmail.com`
- Motoristas: `frotafrtotacheck+motorista@gmail.com` (Paulo, SDF3C19) e
  `frotafrtotacheck+ricardo@gmail.com` (Ricardo, SBC2F56)

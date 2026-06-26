# Dashboard V1 — Backup

Data: 2026-06-26
Branch git: `dashboard-v1-backup`
Commit: master no momento do backup

## O que está aqui

Cópia completa de toda a pasta `lib/` do projeto FrotaCheck antes do upgrade do Dashboard.
Inclui: todas as telas, widgets compartilhados, modelos, tema, utilitários e páginas de suporte.

## Arquivos principais do Dashboard

| Arquivo | Descrição |
|---------|-----------|
| `lib/features/home_page.dart` | Página principal do Dashboard (3200+ linhas) |
| `lib/core/theme/app_theme.dart` | Cores e tema global |
| `lib/shared/widgets/` | Widgets compartilhados (logo, menu card) |
| `lib/home/` | Todas as sub-páginas do menu |
| `lib/pages/` | Páginas de ação rápida |
| `lib/core/models/` | Modelos de dados |

## Como restaurar

### Opção 1 — Via branch git (recomendado)
```bash
git checkout dashboard-v1-backup
```
Isso restaura o estado completo do projeto no ponto do backup.

### Opção 2 — Restaurar só o Dashboard
Copiar `backup/dashboard_v1/lib/features/home_page.dart`
de volta para `lib/features/home_page.dart`.

### Opção 3 — Restaurar lib/ inteira
```powershell
Copy-Item -Path "backup\dashboard_v1\lib" -Destination "lib" -Recurse -Force
```

# Diagnóstico de Tela Branca - Guia Passo a Passo

## 1. Como Abrir o Console do Navegador

### No Chrome/Edge:
- **Console**: `F12` ou `Ctrl+Shift+J` (Windows) / `Cmd+Option+J` (Mac)
- **Network**: `F12` ou `Ctrl+Shift+E` (Windows) / `Cmd+Option+E` (Mac)

### No Firefox:
- **Console**: `F12` ou `Ctrl+Shift+K`
- **Network**: `F12` → aba "Rede"

## 2. Passos para Identificar o Erro

### Na Aba Console:
1. Abra o console **antes** de acessar a URL da Vercel
2. Recarregue a página com `F5` ou `Ctrl+R`
3. Observe **todos os erros em vermelho** aparecem:
   - Erros de JavaScript (ex: `TypeError`, `ReferenceError`)
   - Erros de inicialização do Supabase
   - Falhas ao carregar assets (imagens, fontes)

### Na Aba Network:
1. Clique em Network e recarregue a página
2. Filtre por "XHR/Fetch" ou "JS"
3. Procure por requisições **falhadas** (status 4xx, 5xx):
   - Requisições para `supabase.co` retornando 401, 403, 404, 500
   - Arquivos `.js` com erro ao carregar
   - Falhas em chamadas de API

## 3. Possíveis Erros Comuns

### Erro de Inicialização Supabase:
```
Supabase initialization error
```
Indica que as credenciais não estão configuradas corretamente.

### Erro de Asset (imagem):
```
Unable to load asset: assets/images/login_bg.jpg
```
A imagem pode não ter sido incluída no build.

### Erro de CORS:
```
Access to fetch at 'https://...' has been blocked by CORS policy
```
Problema de configuração no Supabase ou Vercel.

## 4. Verificação de Variáveis de Ambiente na Vercel

Na Vercel, vá em **Settings → Environment Variables** e adicione:

| Name | Value | Environment |
|------|-------|-------------|
| SUPABASE_URL | `https://rseefinwtlrjhzosvmgt.supabase.co` | Production |
| SUPABASE_ANON_KEY | (sua chave anon/public) | Production |

**Nota**: O projeto atual tem as credenciais hard-coded em `lib/core/config/supabase_config.dart`. Para produção segura, use `--dart-define`:

```bash
flutter build web --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_KEY=xxx
```

## 5. Correções Aplicadas

1. **main.dart**: Adicionado try/catch na inicialização do Supabase
2. **vercel.json**: Configurações otimizadas para Flutter Web

## 6. Debug Adicional

Adicione este código temporário em `main.dart` para diagnóstico:

```dart
import 'dart:html' as html;
void main() async {
  html.window.console.log('DEBUG: Iniciando app...');
  // ... resto do código
}
```
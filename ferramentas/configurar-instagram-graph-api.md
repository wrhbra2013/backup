# Configuracao do Instagram Graph API - Guia Completo

## Resumo dos Problemas Comuns

Se voce esta vendo erros como:
- `This endpoint requires the 'pages_read_engagement' permission`
- `Invalid Scopes`
- `Nenhuma pagina com IG Business encontrada`

Siga os passos abaixo para corrigir.

---

## Passo 1: Criar App no Facebook Developer

1. Acesse: https://developers.facebook.com/
2. Clique em **"Meus Apps"** → **"Criar App"**
3. Escolha o tipo **"Business"**
4. De um nome ao app (ex: "Instagram Feed")
5. Clique em **"Criar App"**

---

## Passo 2: Adicionar Instagram Graph API

1. No painel do app, menu lateral: **"Instagram"**
2. Clique em **"Configurar"**
3. Conecte uma conta Instagram Business/Creator

---

## Passo 3: Configurar Permissoes (OBRIGATORIO)

1. Menu lateral: **"App Review"** → **"Permissions and Features"**
2. Busque e ative as permissoes:

| Permissao | Descricao |
|-----------|-----------|
| `instagram_basic` | Dados basicos do Instagram |
| `pages_show_list` | Listar paginas Facebook |
| `pages_read_engagement` | Ler engajamento dos posts |

3. Clique em **"Start a test"** ou **"Request"** para cada uma

**IMPORTANTE:** Para apps em modo desenvolvimento (sem revisao), as permissoes so funcionam para usuarios **Administradores** do app.

---

## Passo 4: Adicionar Usuario como Administrador

1. Menu lateral: **"Settings"** → **"Roles"**
2. Clique em **"Admins"** → **"Add"**
3. Digite o email ou nome da conta Facebook
4. Confirme

Isso permite que voce teste o app sem precisar enviar para revisao.

---

## Passo 5: Configurar Facebook Login

1. Menu lateral: **"Facebook Login"** → **"Settings"**
2. Em **"Valid OAuth redirect URIs"**, adicione:
   ```
   http://localhost:18923/callback
   ```
3. Clique em **"Save"**

---

## Passo 6: Copiar App ID e App Secret

1. Menu lateral: **"Settings"** → **"Basic"**
2. Copie o **App ID**
3. Clique em **"Show"** ao lado do **App Secret** e copie

---

## Passo 7: Converter Conta Instagram para Business

Se sua conta Instagram nao for Business/Creator:

1. Abra o app Instagram
2. Va em **Configuracoes** → **Conta**
3. Toque em **"Mudar para Conta Profissional"**
4. Escolha **"Negocio"** ou **"Criador"**
5. Siga as instrucoes

---

## Passo 8: Vincular Instagram a Pagina Facebook

1. No Facebook, acesse sua Pagina
2. Va em **Configuracoes da Pagina**
3. Clique em **"Contas Profissionais"**
4. Clique em **"Conectar conta"**
5. Selecione sua conta Instagram
6. Autorize o vinculo

---

## Passo 9: Testar o Script

```bash
node instagram-feed.js
```

O script deve:
1. Detectar as credenciais salvas em `.env`
2. Autenticar via navegador
3. Verificar permissoes
4. Encontrar paginas com Instagram Business
5. Permitir buscar perfis

---

## Troubleshooting (Solucao de Problemas)

### Erro: "pages_read_engagement permission"
- Verifique se a permissao esta ativa em **App Review → Permissions and Features**
- Adicione seu usuario como Administrador em **Settings → Roles**

### Erro: "Nenhuma pagina com IG Business"
- Verifique se sua conta Instagram e Business/Creator
- Verifique se esta vinculada a uma Pagina Facebook
- A vinculacao e feita em: Configuracoes da Pagina → Contas Profissionais

### Erro: "Invalid Scopes"
- Remova permissoes que nao existem da URL OAuth
- Use apenas: `instagram_basic`, `pages_show_list`, `pages_read_engagement`

### Busca nao encontra perfis
- A busca usa a API do Facebook para encontrar **Paginas** com Instagram vinculado
- Nao busca perfis pessoais do Instagram
- Use o nome da **Pagina Facebook** (nao o @ do Instagram)

---

## URLs Uteis

- **Facebook Developer:** https://developers.facebook.com/
- **Seus Apps:** https://developers.facebook.com/apps/
- **Graph API Explorer:** https://developers.facebook.com/tools/explorer/
- **Documentacao Instagram:** https://developers.facebook.com/docs/instagram-api/

---

## Configuracao Automatica

O script `instagram-feed.js` salva as credenciais automaticamente no arquivo `.env`:

```
FB_APP_ID=seu_app_id
FB_APP_SECRET=seu_app_secret
FB_ACCESS_TOKEN=seu_token
```

Na proxima execucao, as credenciais sao reaproveitadas automaticamente.

---

*Guia atualizado em: Janeiro 2026*

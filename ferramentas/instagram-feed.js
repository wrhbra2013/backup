#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const http = require('http');
const { URL } = require('url');
const { exec } = require('child_process');

const API_BASE = 'https://graph.facebook.com/v18.0';
const REDIRECT_PORT = 18923;
const REDIRECT_URI = `http://localhost:${REDIRECT_PORT}/callback`;
const ENV_FILE = path.join(__dirname, '.env');

function loadEnv() {
  const vars = {};
  if (fs.existsSync(ENV_FILE)) {
    const content = fs.readFileSync(ENV_FILE, 'utf-8');
    content.split('\n').forEach(line => {
      const match = line.match(/^([A-Z_]+)=(.+)$/);
      if (match) vars[match[1]] = match[2].trim();
    });
  }
  return vars;
}

function saveEnv(vars) {
  const content = Object.entries(vars).map(([k, v]) => `${k}=${v}`).join('\n') + '\n';
  fs.writeFileSync(ENV_FILE, content, 'utf-8');
}

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
rl.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });
const ask = q => new Promise(resolve => rl.question(q, resolve));

const sleep = ms => new Promise(r => setTimeout(r, ms));

function openBrowser(url) {
  const platform = process.platform;
  const cmd = platform === 'darwin' ? 'open' : platform === 'win32' ? 'start' : 'xdg-open';
  exec(`${cmd} "${url}"`, err => {
    if (err) console.log(`  [aviso] Nao foi possivel abrir o navegador automaticamente.`);
  });
}

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const url = `${API_BASE}/${endpoint}${sep}access_token=${token}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function getAppAccessToken(appId, appSecret) {
  const url = `${API_BASE}/oauth/access_token?client_id=${appId}&client_secret=${appSecret}&grant_type=client_credentials`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.access_token;
}

async function exchangeCodeForToken(appId, appSecret, code) {
  const url = `${API_BASE}/oauth/access_token?client_id=${appId}&client_secret=${appSecret}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&code=${code}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.access_token;
}

async function exchangeForLongLivedToken(appId, appSecret, shortToken) {
  const url = `${API_BASE}/oauth/access_token?grant_type=fb_exchange_token&client_id=${appId}&client_secret=${appSecret}&fb_exchange_token=${shortToken}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.access_token;
}

async function verifyApp(appId, appSecret) {
  console.log('\n--- Verificando App ---\n');
  const appToken = await getAppAccessToken(appId, appSecret);
  console.log('  [ok] App access token obtido');

  const appData = await apiGet(`${appId}?fields=name,category`, appToken);
  console.log(`  [ok] App encontrado: "${appData.name}"`);
  console.log(`      Categoria: ${appData.category || 'N/D'}`);

  return { appToken, appData };
}

function startLocalServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const parsed = new URL(req.url, `http://localhost:${REDIRECT_PORT}`);

      if (parsed.pathname === '/callback') {
        const code = parsed.searchParams.get('code');
        const error = parsed.searchParams.get('error');

        if (error) {
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<html><body style="font-family:sans-serif;text-align:center;padding:60px;">
            <h2>Erro na autenticacao</h2><p>${error}</p>
            <p>Pode fechar esta janela.</p></body></html>`);
          reject(new Error(`Erro OAuth: ${error}`));
          server.close();
          return;
        }

        if (code) {
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<html><body style="font-family:sans-serif;text-align:center;padding:60px;">
            <h2 style="color:#4caf50;">Autenticado com sucesso!</h2>
            <p>Pode fechar esta janela e voltar ao terminal.</p></body></html>`);
          resolve(code);
          server.close();
          return;
        }

        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
      } else {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(`<html><body style="font-family:sans-serif;text-align:center;padding:60px;">
          <h2>Aguardando autenticacao do Facebook...</h2>
          <p>Esta pagina sera redirecionada automaticamente.</p></body></html>`);
      }
    });

    server.listen(REDIRECT_PORT, () => {
      console.log(`  [ok] Servidor local rodando na porta ${REDIRECT_PORT}`);
    });

    server.on('error', err => {
      if (err.code === 'EADDRINUSE') {
        console.error(`  [erro] Porta ${REDIRECT_PORT} ja esta em uso. Feche outros processos e tente novamente.`);
        process.exit(1);
      }
      reject(err);
    });

    setTimeout(() => {
      reject(new Error('Tempo esgotado aguardando autenticacao (5 min)'));
      server.close();
    }, 5 * 60 * 1000);
  });
}

async function setupApp() {
  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║         CONFIGURACAO DO APP FACEBOOK                     ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  console.log('  Fluxo de configuracao:\n');
  console.log('    1. Autenticar no Facebook via navegador');
  console.log('    2. Verificar se o App existe');
  console.log('    3. Checar Instagram Graph API');
  console.log('    4. Checar permissoes');
  console.log('    5. Pronto para usar\n');

  const env = loadEnv();
  let appId = env.FB_APP_ID || '';
  let appSecret = env.FB_APP_SECRET || '';

  if (appId && appSecret) {
    console.log(`  App ID:    ${appId}`);
    console.log(`  App Secret: ${appSecret.substring(0, 8)}...${appSecret.substring(appSecret.length - 4)}\n`);
    const useSaved = (await ask('Usar credenciais salvas? (S/n): ')).trim().toLowerCase();
    if (useSaved === 'n' || useSaved === 'nao') {
      appId = '';
      appSecret = '';
    }
  }

  if (!appId || !appSecret) {
    console.log('  IMPORTANTE: O Facebook NAO fornece API para listar apps.');
    console.log('  Voce precisa saber o App ID e App Secret do seu app.\n');

    console.log('  Para ver seus apps acesse:');
    console.log('    https://developers.facebook.com/apps/\n');

    console.log('  Caso nao tenha um app, crie um agora:\n');
    console.log('  Passo 1: Criar app');
    console.log('    https://developers.facebook.com/');
    console.log('    → Meus Apps → Criar App (tipo Business)\n');
    console.log('  Passo 2: Adicionar Instagram Graph API');
    console.log('    Menu lateral: Instagram → Configurar\n');
    console.log('  Passo 3: Configurar permissoes');
    console.log('    Menu lateral: App Review → Permissions and Features');
    console.log('    Busque e ative:');
    console.log('      ✓ instagram_basic');
    console.log('      ✓ pages_show_list');
    console.log('      ✓ pages_read_engagement\n');
    console.log('  Passo 4: Adicionar usuarios Administradores (para dev)');
    console.log('    Menu lateral: Settings → Roles → Admins');
    console.log('    → Adicione sua conta Facebook\n');
    console.log(`  Passo 5: Adicionar Redirect URI (OBRIGATORIO!)`);
    console.log(`    Menu lateral: "Facebook Login" → Settings`);
    console.log(`    → "Valid OAuth redirect URIs" → adicione:`);
    console.log(`    ${REDIRECT_URI}`);
    console.log(`    → Clique em "Save"\n`);
    console.log('  Passo 6: Copiar App ID e App Secret');
    console.log('    Menu lateral: Settings → Basic → App ID e App Secret\n');

    appId = (await ask('App ID: ')).trim();
    if (!appId) { console.error('App ID vazio.'); process.exit(1); }

    appSecret = (await ask('App Secret: ')).trim();
    if (!appSecret) { console.error('App Secret vazio.'); process.exit(1); }

    saveEnv({ ...env, FB_APP_ID: appId, FB_APP_SECRET: appSecret });
    console.log('\n  [ok] Credenciais salvas em .env');
  }

  console.log('\n--- [1/5] Configurando Redirect URI ---\n');
  console.log('  ANTES de autenticar, adicione este Redirect URI no seu app:\n');
  console.log(`    ${REDIRECT_URI}\n`);
  console.log('  Onde (nova dashboard):');
  console.log('    https://developers.facebook.com/apps/ → seu app');
  console.log('    → Menu lateral: "Facebook Login" (ou "Facebook Login for Business")');
  console.log('    → Settings');
  console.log(`    → "Valid OAuth redirect URIs" → adicione: ${REDIRECT_URI}\n`);
  console.log('  Clique em "Save" apos adicionar.\n');

  const hasRedirect = (await ask('Voce ja adicionou o Redirect URI no app? (s/N): ')).trim().toLowerCase();
  if (hasRedirect !== 's' && hasRedirect !== 'sim') {
    console.log('\n  Adicione o Redirect URI e rode o script novamente.\n');
    process.exit(0);
  }

  console.log('\n--- [1/5] Autenticacao via Navegador ---\n');

  const scopes = [
    'instagram_basic',
    'pages_show_list',
    'pages_read_engagement',
  ].join(',');

  const authUrl = `https://www.facebook.com/v18.0/dialog/oauth?client_id=${appId}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&scope=${scopes}&response_type=code`;

  console.log('  O navegador sera aberto para voce fazer login.\n');
  console.log('  Passo a passo:');
  console.log('    1. Faca login com sua conta Facebook');
  console.log('    2. Clique em "Continuar" para autorizar o app');
  console.log('    3. O navegador redirecionara para localhost (pode mostrar erro, e normal!)');
  console.log('    4. Volte ao terminal - o codigo sera capturado automaticamente\n');
  console.log('  Se nao abrir, copie e cole esta URL no navegador:\n');
  console.log(`  ${authUrl}\n`);

  openBrowser(authUrl);

  console.log('  Aguardando autenticacao... (max 5 minutos)\n');

  let code;
  try {
    code = await startLocalServer();
    console.log('  [ok] Codigo de autorizacao recebido!');
  } catch (err) {
    console.error(`  [erro] ${err.message}`);
    process.exit(1);
  }

  console.log('\n  Gerando Access Token...');
  let token;
  try {
    token = await exchangeCodeForToken(appId, appSecret, code);
    console.log('  [ok] Token de curto prazo obtido!');
  } catch (err) {
    console.error(`  [erro] Nao foi obter o token: ${err.message}`);
    process.exit(1);
  }

  try {
    console.log('  Convertendo para token de longo prazo...');
    token = await exchangeForLongLivedToken(appId, appSecret, token);
    console.log('  [ok] Token de longo prazo obtido! (nao expira por ~60 dias)');
  } catch (err) {
    console.log(`  [aviso] Nao foi possivel converter: ${err.message}`);
    console.log('  Usando o token curto (expira em ~1h).');
  }

  try {
    const me = await apiGet('me?fields=id,name', token);
    console.log(`  [ok] Autenticado como: "${me.name}" (ID: ${me.id})`);
  } catch (err) {
    console.log(`  [aviso] Nao foi validar o token: ${err.message}`);
  }

  saveEnv({ ...env, FB_APP_ID: appId, FB_APP_SECRET: appSecret, FB_ACCESS_TOKEN: token });
  console.log('\n  [ok] Access Token salvo em .env');

  console.log('\n--- [2/5] Verificando App ---\n');

  let appToken;
  try {
    const appInfo = await verifyApp(appId, appSecret);
    appToken = appInfo.appToken;
  } catch (err) {
    console.error(`  [erro] App invalido: ${err.message}`);
    console.log('  Verifique se App ID e App Secret estao corretos.\n');
    const retry = (await ask('Tentar novamente? (s/N): ')).trim().toLowerCase();
    if (retry === 's' || retry === 'sim') return setupApp();
    process.exit(1);
  }

  console.log('\n--- [3/5] Verificando Instagram Graph API ---\n');

  try {
    const appData = await apiGet(`${appId}?fields=name`, appToken);
    console.log(`  App: "${appData.name}"`);
    console.log('  [info] Instagram Graph API: verifique se esta configurada no painel.');
    console.log('    → Menu lateral: Instagram → Configurar\n');
  } catch (err) {
    console.log(`  [aviso] Nao foi verificar app: ${err.message}`);
  }

  console.log('\n--- [4/5] Verificando Permissoes ---\n');

  try {
    const appPerms = await apiGet(`${appId}/permissions?fields=permission,status`, appToken);
    const perms = appPerms.data || [];
    const granted = perms.filter(p => p.status === 'granted').map(p => p.permission);
    const denied = perms.filter(p => p.status === 'denied').map(p => p.permission);

    console.log('  Permissoes do App:');
    const required = ['instagram_basic', 'pages_show_list', 'pages_read_engagement'];
    required.forEach(p => {
      const status = granted.includes(p) ? '✓ concedida' : denied.includes(p) ? '✗ negada' : '? nao configurada';
      console.log(`    ${p}: ${status}`);
    });

    const missing = required.filter(p => !granted.includes(p));
    if (missing.length > 0) {
      console.log(`\n  [erro] Permissoes faltando: ${missing.join(', ')}`);
      console.log('\n  Como configurar no nova dashboard:');
      console.log('  1. https://developers.facebook.com/apps/ → seu app');
      console.log('  2. Menu lateral: "App Review" → "Permissions and Features"');
      console.log('  3. Busque e ative:');
      console.log('     - instagram_basic');
      console.log('     - pages_show_list');
      console.log('     - pages_read_engagement');
      console.log('  4. Pode ser necessario enviar app para revisao\n');
      console.log('  Para apps em modo de desenvolvimento (sem revisao):');
      console.log('  - As permissoes so funcionam para usuarios Administradores do app');
      console.log('  - Adicione seu usuario em: Settings → Roles → Admins\n');
    } else {
      console.log('\n  [ok] Todas as permissoes obrigatorias concedidas.');
    }
  } catch (err) {
    console.log(`  [aviso] Nao foi verificar permissoes: ${err.message}`);
  }

  console.log('\n--- [5/5] Verificando Paginas e Instagram Business ---\n');

  try {
    const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    const pages = pagesData.data || [];

    if (pages.length === 0) {
      console.log('  [aviso] Nenhuma Pagina Facebook encontrada.');
      console.log('  Certifique-se de que sua conta Instagram Business esta vinculada a uma Pagina.');
    } else {
      console.log(`  [ok] ${pages.length} pagina(s) encontrada(s):\n`);
      pages.forEach((p, i) => {
        const igId = p.instagram_business_account?.id || 'Nao vinculada';
        const status = p.instagram_business_account?.id ? '✓ IG Business vinculada' : '✗ Sem IG Business';
        console.log(`    ${i + 1}. ${p.name} (ID: ${p.id})`);
        console.log(`       Instagram: ${igId} - ${status}`);
      });

      const withIG = pages.filter(p => p.instagram_business_account?.id);
      if (withIG.length === 0) {
        console.log('\n  [aviso] Nenhuma pagina tem Instagram Business vinculado.');
        console.log('  Vincule sua conta Instagram Business em:');
        console.log('    Facebook → Configuracoes da Pagina → Contas Profissionais → Conectar conta');
      } else {
        console.log(`\n  [ok] ${withIG.length} pagina(s) com Instagram Business pronta(s).`);
      }
    }
  } catch (err) {
    if (err.message.includes('pages_show_list')) {
      console.log('  [erro] Falta a permissao "pages_show_list".');
      console.log('  Adicione nas configuracoes do app → Permissoes da API.');
    } else if (err.message.includes('pages_read_engagement')) {
      console.log('  [erro] Falta a permissao "pages_read_engagement".');
      console.log('  Adicione nas configuracoes do app → Permissoes da API.');
    } else {
      console.log(`  [aviso] Nao foi verificar paginas: ${err.message}`);
    }
  }

  console.log('\n  NOTA: O Facebook NAO disponibiliza API para listar todos os apps.');
  console.log('  Para ver seus apps, acesse: https://developers.facebook.com/apps/\n');

  return token;
}

async function searchPages(query, token) {
  const data = await apiGet(`pages/search?q=${encodeURIComponent(query)}&fields=id,name,instagram_business_account`, token);
  return (data.data || []).filter(p => p.instagram_business_account?.id);
}

async function resolveIgUserId(input, token) {
  const clean = input.replace(/^@/, '').trim();

  if (/^\d+$/.test(clean)) return clean;

  const pages = await searchPages(clean, token);
  if (pages.length === 0) throw new Error(`Nenhuma pagina com IG Business encontrada para "${clean}".`);
  if (pages.length === 1) {
    console.log(`  Encontrado: ${pages[0].name} (IG ID: ${pages[0].instagram_business_account.id})`);
    return pages[0].instagram_business_account.id;
  }

  console.log(`\n  ${pages.length} resultados encontrados:\n`);
  pages.forEach((p, i) => {
    console.log(`  [${i + 1}] ${p.name}  |  IG ID: ${p.instagram_business_account.id}  |  Page ID: ${p.id}`);
  });

  const choice = await ask(`\n  Escolha o numero (1-${pages.length}): `);
  const idx = parseInt(choice, 10) - 1;
  if (idx < 0 || idx >= pages.length) throw new Error('Escolha invalida.');
  return pages[idx].instagram_business_account.id;
}

async function downloadProfileSummary(token, query, limit) {
  const igUserId = await resolveIgUserId(query, token);

  console.log('  Buscando dados do perfil...');
  const profileData = await apiGet(`${igUserId}?fields=username,name,biography,followers_count,follows_count,media_count,profile_picture_url`, token);

  console.log(`  Buscando ${limit} posts recentes...`);
  const postsData = await apiGet(`${igUserId}/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,like_count,comments_count,permalink&limit=${limit}`, token);

  const posts = postsData.data || [];
  let totalLikes = 0, totalComments = 0;
  posts.forEach(p => { totalLikes += (p.like_count ?? 0); totalComments += (p.comments_count ?? 0); });

  return {
    perfil: {
      username: profileData.username || null,
      nome: profileData.name || null,
      bio: profileData.biography || null,
      seguidores: profileData.followers_count ?? null,
      seguindo: profileData.follows_count ?? null,
      total_posts: profileData.media_count ?? null,
      foto_perfil: profileData.profile_picture_url || null,
      id_ig_business: igUserId,
    },
    estatisticas: {
      posts_baixados: posts.length,
      total_likes: totalLikes,
      total_comentarios: totalComments,
      media_likes_por_post: posts.length ? +(totalLikes / posts.length).toFixed(1) : 0,
      media_comentarios_por_post: posts.length ? +(totalComments / posts.length).toFixed(1) : 0,
    },
    posts: posts.map(p => ({
      id: p.id,
      tipo: (p.media_type || 'IMAGE').toUpperCase(),
      data: p.timestamp || null,
      legenda: p.caption || null,
      likes: p.like_count ?? 0,
      comentarios: p.comments_count ?? 0,
      url_midia: p.media_url || null,
      url_thumbnail: p.thumbnail_url || null,
      permalink: p.permalink || null,
    })),
  };
}

async function main() {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log(`
Uso interativo: node instagram-feed.js
  Configura automaticamente o app e autentica via navegador.
  Credenciais (App ID/Secret/Token) salvas automaticamente em .env.

Uso direto: node instagram-feed.js --token TOKEN --user "NOME OU ID" [--limit NUM]

Fluxo interativo:
  1. Verifica se tem credenciais salvas em .env
  2. Se nao, pede App ID + App Secret e salva
  3. Abre o navegador para autenticacao OAuth automatica
  4. Recebe o codigo, converte para token de longo prazo
  5. Verifica permissoes e Instagram Graph API
  6. Pronto para usar

Configuracao obrigatoria no Facebook Developer:
  1. Criar app (tipo Business)
  2. Adicionar produto: Instagram Graph API
  3. App Review → Permissions and Features → ative:
     - instagram_basic
     - pages_show_list
     - pages_read_engagement
  4. Settings → Roles → adicione seu usuario como Admin
  5. Facebook Login → Settings → adicione Redirect URI:
     http://localhost:18923/callback

Nota: Para apps em modo desenvolvimento, so Administradores podem usar.
`);
    process.exit(0);
  }

  console.log('=== Instagram Feed Resumo (CLI) ===\n');

  let token, user, limit;

  if (process.argv.includes('--token')) {
    token = process.argv[process.argv.indexOf('--token') + 1];
    user = process.argv[process.argv.indexOf('--user') + 1];
    const limIdx = process.argv.indexOf('--limit');
    limit = limIdx >= 0 ? parseInt(process.argv[limIdx + 1], 10) || 25 : 25;
  } else {
    const env = loadEnv();
    const savedToken = env.FB_ACCESS_TOKEN || '';

    if (savedToken) {
      console.log('  Access Token salvo encontrado em .env\n');
      const useSaved = (await ask('Usar token salvo? (S/n): ')).trim().toLowerCase();
      if (useSaved === 'n' || useSaved === 'nao') {
        const hasToken = (await ask('Cole seu Access Token: ')).trim();
        if (!hasToken) { console.error('Token vazio.'); process.exit(1); }
        token = hasToken;
      } else {
        token = savedToken;
      }
    } else {
      const hasToken = (await ask('Voce ja tem um Access Token? (s/N): ')).trim().toLowerCase();

      if (hasToken === 's' || hasToken === 'sim') {
        token = (await ask('Cole seu Access Token: ')).trim();
        if (!token) { console.error('Token vazio.'); process.exit(1); }
      } else {
        token = await setupApp();
      }
    }

    console.log('\nFormats de busca:');
    console.log('  - Nome da pagina:  "nike" ou "Nike Brasil"');
    console.log('  - Com @:           @nike');
    console.log('  - ID numerico:     17841400123456789');
    user = (await ask('\nBuscar perfil: ')).trim();
    if (!user) { console.error('Perfil vazio. Abortando.'); process.exit(1); }

    const limitStr = (await ask('Quantidade de posts (padrao 25): ')).trim();
    limit = parseInt(limitStr, 10) || 25;
  }

  console.log('\n--- Iniciando ---\n');

  try {
    const summary = await downloadProfileSummary(token, user, limit);

    const filename = `instagram-${summary.perfil.username || user.replace(/[^a-zA-Z0-9]/g, '_')}-resumo.json`;
    fs.writeFileSync(filename, JSON.stringify(summary, null, 2), 'utf-8');

    console.log(`\n=== PERFIL ===`);
    console.log(`  Username:    @${summary.perfil.username}`);
    console.log(`  Nome:        ${summary.perfil.nome || 'N/A'}`);
    console.log(`  Bio:         ${summary.perfil.bio || 'N/A'}`);
    console.log(`  Seguidores:  ${summary.perfil.seguidores}`);
    console.log(`  Seguindo:    ${summary.perfil.seguindo}`);
    console.log(`  Total posts: ${summary.perfil.total_posts}`);
    console.log(`  IG Business: ${summary.perfil.id_ig_business}`);

    console.log(`\n=== ESTATISTICAS (ultimos ${summary.estatisticas.posts_baixados} posts) ===`);
    console.log(`  Likes:      ${summary.estatisticas.total_likes} total | ${summary.estatisticas.media_likes_por_post} media/post`);
    console.log(`  Comentarios: ${summary.estatisticas.total_comentarios} total | ${summary.estatisticas.media_comentarios_por_post} media/post`);

    console.log(`\n=== POSTS ===`);
    summary.posts.forEach((p, i) => {
      const date = p.data ? new Date(p.data).toLocaleDateString('pt-BR') : 'N/D';
      console.log(`  ${i + 1}. [${p.tipo}] ${date} | ❤${p.likes} 💬${p.comentarios}`);
      console.log(`     ${(p.legenda || 'Sem legenda').substring(0, 100)}`);
    });

    console.log(`\nSalvo em: ${filename}`);

  } catch (err) {
    console.error(`\nErro: ${err.message}`);
    process.exit(1);
  } finally {
    rl.close();
  }
}

main();

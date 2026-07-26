#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const { URL } = require('url');
const { exec } = require('child_process');
const readline = require('readline');

// ─── Configuração ────────────────────────────────────────────────────────────

const FB_API_VERSION = process.env.FB_API_VERSION || 'v18.0';
const API_BASE = `https://graph.facebook.com/${FB_API_VERSION}`;
const REDIRECT_PORT = parseInt(process.env.FB_REDIRECT_PORT, 10) || 18923;
const REDIRECT_URI = `http://localhost:${REDIRECT_PORT}/callback`;
const ENV_FILE = path.join(__dirname, '.env');

const RETRY_MAX = 3;
const RETRY_BASE_MS = 1000;
const OAUTH_TIMEOUT_MS = 5 * 60 * 1000;
const REQUIRED_PERMISSIONS = ['instagram_basic', 'pages_show_list', 'pages_read_engagement'];

const IG_HEADERS = {
  'User-Agent': 'Instagram 219.0.0.12.117 Android (30/11; 420dpi; 1080x2400; samsung; SM-A515F; a51; exynos9611; en_US; 346143258)',
  'Accept': '*/*',
  'Accept-Language': 'en-US',
  'X-IG-App-ID': '936619743392459',
  'X-Requested-With': 'XMLHttpRequest',
};

const DEBUG = !!process.env.DEBUG;

function logDebug(...args) {
  if (DEBUG) console.log('  [debug]', ...args);
}

// ─── Utilitários ─────────────────────────────────────────────────────────────

function loadEnv() {
  const vars = {};
  if (!fs.existsSync(ENV_FILE)) return vars;
  const lines = fs.readFileSync(ENV_FILE, 'utf-8').split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx < 1) continue;
    vars[trimmed.slice(0, idx)] = trimmed.slice(idx + 1).trim();
  }
  return vars;
}

function saveEnv(vars) {
  const content = Object.entries(vars).map(([k, v]) => `${k}=${v}`).join('\n') + '\n';
  fs.writeFileSync(ENV_FILE, content, 'utf-8');
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

function openBrowser(url) {
  const cmd = process.platform === 'darwin' ? 'open'
            : process.platform === 'win32' ? 'start'
            : 'xdg-open';
  try {
    const { spawnSync } = require('child_process');
    spawnSync(cmd, [url], { stdio: 'ignore' });
  } catch {
    console.log('  [aviso] Nao foi possivel abrir o navegador automaticamente.');
  }
}

function sanitizeFilename(str) {
  return str.replace(/[^a-zA-Z0-9]/g, '_');
}

// ─── CLI helpers ─────────────────────────────────────────────────────────────

function getArg(name) {
  const idx = process.argv.indexOf(name);
  if (idx < 0 || idx + 1 >= process.argv.length) return null;
  return process.argv[idx + 1];
}

function hasFlag(name) {
  return process.argv.includes(name);
}

// ─── API Facebook ────────────────────────────────────────────────────────────

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const url = `${API_BASE}/${endpoint}${sep}access_token=${token}`;
  logDebug('GET', url.replace(token, '***'));
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function apiGetWithRetry(endpoint, token, retries = RETRY_MAX) {
  for (let i = 0; i < retries; i++) {
    try {
      return await apiGet(endpoint, token);
    } catch (err) {
      if (i === retries - 1) throw err;
      const msg = err.message || '';
      const isRetryable = /429|500|502|503/.test(msg);
      if (!isRetryable) throw err;
      const delay = RETRY_BASE_MS * Math.pow(2, i);
      console.log(`  [retry] Tentativa ${i + 2}/${retries} em ${delay}ms...`);
      await sleep(delay);
    }
  }
}

async function apiGetAllPages(endpoint, token, limit = 100) {
  const sep = endpoint.includes('?') ? '&' : '?';
  let url = `${API_BASE}/${endpoint}${sep}limit=${limit}`;
  const allData = [];
  let safety = 0;
  while (url && safety < 50) {
    const sep2 = url.includes('?') ? '&' : '?';
    const fullUrl = `${url}${sep2}access_token=${token}`;
    logDebug('GET (page)', fullUrl.replace(token, '***'));
    const res = await fetch(fullUrl);
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
    const data = await res.json();
    if (data.error) throw new Error(data.error.message);
    allData.push(...(data.data || []));
    url = data.paging?.next || null;
    safety++;
  }
  return allData;
}

async function getAppAccessToken(appId, appSecret) {
  const url = `${API_BASE}/oauth/access_token?client_id=${appId}&client_secret=${appSecret}&grant_type=client_credentials`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.access_token;
}

async function exchangeCodeForToken(appId, appSecret, code) {
  const url = `${API_BASE}/oauth/access_token?client_id=${appId}&client_secret=${appSecret}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&code=${code}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.access_token;
}

async function exchangeForLongLivedToken(appId, appSecret, shortToken) {
  const url = `${API_BASE}/oauth/access_token?grant_type=fb_exchange_token&client_id=${appId}&client_secret=${appSecret}&fb_exchange_token=${shortToken}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.access_token;
}

async function isTokenValid(token) {
  try {
    await apiGet('me?fields=id', token);
    return true;
  } catch {
    return false;
  }
}

// ─── OAuth / Auth local server ───────────────────────────────────────────────

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
    }, OAUTH_TIMEOUT_MS);
  });
}

// ─── Verificação do App ──────────────────────────────────────────────────────

async function verifyApp(appId, appSecret) {
  console.log('\n--- Verificando App ---\n');
  const appToken = await getAppAccessToken(appId, appSecret);
  console.log('  [ok] App access token obtido');

  const appData = await apiGet(`${appId}?fields=name,category`, appToken);
  console.log(`  [ok] App encontrado: "${appData.name}"`);
  console.log(`      Categoria: ${appData.category || 'N/D'}`);

  return { appToken, appData };
}

// ─── Setup App ───────────────────────────────────────────────────────────────

async function setupApp(rl, askFn) {
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
    const useSaved = (await askFn('Usar credenciais salvas? (S/n): ')).trim().toLowerCase();
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

    appId = (await askFn('App ID: ')).trim();
    if (!appId) throw new Error('App ID vazio.');

    appSecret = (await askFn('App Secret: ')).trim();
    if (!appSecret) throw new Error('App Secret vazio.');

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

  const hasRedirect = (await askFn('Voce ja adicionou o Redirect URI no app? (s/N): ')).trim().toLowerCase();
  if (hasRedirect !== 's' && hasRedirect !== 'sim') {
    throw new Error('Adicione o Redirect URI e rode o script novamente.');
  }

  console.log('\n--- [1/5] Autenticacao via Navegador ---\n');

  const scopes = REQUIRED_PERMISSIONS.join(',');

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
    throw new Error(`Falha na autenticacao: ${err.message}`);
  }

  console.log('\n  Gerando Access Token...');
  let token;
  try {
    token = await exchangeCodeForToken(appId, appSecret, code);
    console.log('  [ok] Token de curto prazo obtido!');
  } catch (err) {
    throw new Error(`Nao foi obter o token: ${err.message}`);
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

  try {
    await verifyApp(appId, appSecret);
  } catch (err) {
    console.error(`  [erro] App invalido: ${err.message}`);
    console.log('  Verifique se App ID e App Secret estao corretos.\n');
    const retry = (await askFn('Tentar novamente? (s/N): ')).trim().toLowerCase();
    if (retry === 's' || retry === 'sim') return setupApp(rl, askFn);
    throw new Error('App invalido.');
  }

  console.log('\n--- [3/5] Verificando Instagram Graph API ---\n');

  try {
    const appData = await apiGet(`${appId}?fields=name`, (await getAppAccessToken(appId, appSecret)));
    console.log(`  App: "${appData.name}"`);
    console.log('  [info] Instagram Graph API: verifique se esta configurada no painel.');
    console.log('    → Menu lateral: Instagram → Configurar\n');
  } catch (err) {
    console.log(`  [aviso] Nao foi verificar app: ${err.message}`);
  }

  console.log('\n--- [4/5] Verificando Permissoes ---\n');

  try {
    const appPerms = await apiGet(`${appId}/permissions?fields=permission,status`, (await getAppAccessToken(appId, appSecret)));
    const perms = appPerms.data || [];
    const granted = perms.filter(p => p.status === 'granted').map(p => p.permission);
    const denied = perms.filter(p => p.status === 'denied').map(p => p.permission);

    console.log('  Permissoes do App:');
    REQUIRED_PERMISSIONS.forEach(p => {
      const status = granted.includes(p) ? '✓ concedida' : denied.includes(p) ? '✗ negada' : '? nao configurada';
      console.log(`    ${p}: ${status}`);
    });

    const missing = REQUIRED_PERMISSIONS.filter(p => !granted.includes(p));
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
      console.log('  NOTA: Buscar paginas publicas (pages/search) requer adicional:');
      console.log('  - App Review → Permissions and Features');
      console.log('  - Ative "Page Public Content Access" ou "Page Public Metadata Access"');
      console.log('  - Sem isso, use o Instagram User ID diretamente (via URL do perfil)\n');
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
    const msg = err.message || '';
    if (msg.includes('pages_show_list')) {
      console.log('  [erro] Falta a permissao "pages_show_list".');
      console.log('  Adicione nas configuracoes do app → Permissoes da API.');
    } else if (msg.includes('pages_read_engagement')) {
      console.log('  [erro] Falta a permissao "pages_read_engagement".');
      console.log('  Adicione nas configuracoes do app → Permissoes da API.');
    } else {
      console.log(`  [aviso] Nao foi verificar paginas: ${msg}`);
    }
  }

  console.log('\n  NOTA: O Facebook NAO disponibiliza API para listar todos os apps.');
  console.log('  Para ver seus apps, acesse: https://developers.facebook.com/apps/\n');

  return token;
}

// ─── Instagram — Busca e resolução de IDs ────────────────────────────────────

async function getManagedPages(token) {
  const data = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
  return (data.data || []).filter(p => p.instagram_business_account?.id);
}

async function tryPagesSearch(query, token) {
  try {
    const data = await apiGet(`pages/search?q=${encodeURIComponent(query)}&fields=id,name,instagram_business_account`, token);
    return (data.data || []).filter(p => p.instagram_business_account?.id);
  } catch (err) {
    const msg = err.message || '';
    if (msg.includes('pages_read_engagement') || msg.includes('Page Public Content Access')) {
      return null;
    }
    throw err;
  }
}

async function searchHashtag(query, token) {
  const managed = await getManagedPages(token);
  if (managed.length === 0) return { error: 'no_pages' };

  const igUserId = managed[0].instagram_business_account.id;

  let hashtagId;
  try {
    const searchResult = await apiGet(`ig_hashtag_search?user_id=${igUserId}&q=${encodeURIComponent(query)}`, token);
    const hashtags = searchResult.data || [];
    if (hashtags.length === 0) return { error: 'not_found' };
    hashtagId = hashtags[0].id;
  } catch (err) {
    const msg = err.message || '';
    if (msg.includes('instagram_basic') || msg.includes('pages_read_engagement')) {
      return { error: 'no_permission' };
    }
    throw err;
  }

  const postsData = await apiGet(`${hashtagId}/recent_media?user_id=${igUserId}&fields=id,caption,media_type,timestamp,like_count,comments_count,permalink,username&limit=50`, token);
  const posts = postsData.data || [];

  const profilesMap = {};
  posts.forEach(p => {
    const u = p.username;
    if (u && !profilesMap[u]) {
      profilesMap[u] = {
        username: u,
        post_count: 0,
        total_likes: 0,
        total_comments: 0,
        latest_post: p.timestamp,
      };
    }
    if (u) {
      profilesMap[u].post_count++;
      profilesMap[u].total_likes += p.like_count ?? 0;
      profilesMap[u].total_comments += p.comments_count ?? 0;
    }
  });

  const profiles = Object.values(profilesMap)
    .sort((a, b) => b.post_count - a.post_count);

  return { hashtag: query, hashtagId, profiles, posts };
}

// ─── Instagram — Scraping de ID do perfil ────────────────────────────────────

const ID_PATTERN = /^\d{10,}$/;

async function fetchViaWebProfileInfo(username) {
  try {
    const res = await fetch(`https://i.instagram.com/api/v1/users/web_profile_info/?username=${encodeURIComponent(username)}`, {
      headers: { ...IG_HEADERS, 'X-IG-App-ID': '936619743392459' },
      redirect: 'follow',
    });
    if (res.ok) {
      const data = await res.json();
      const id = data?.data?.user?.id;
      if (id && ID_PATTERN.test(String(id))) return String(id);
    }
  } catch (err) {
    logDebug('fetchViaWebProfileInfo falhou:', err.message);
  }
  return null;
}

async function fetchViaUsernameInfo(username) {
  try {
    const res = await fetch(`https://i.instagram.com/api/v1/users/${encodeURIComponent(username)}/usernameinfo/`, {
      headers: IG_HEADERS,
      redirect: 'follow',
    });
    if (res.ok) {
      const data = await res.json();
      const id = data?.user?.pk_id || data?.user?.pk || data?.user?.id;
      if (id && ID_PATTERN.test(String(id))) return String(id);
    }
  } catch (err) {
    logDebug('fetchViaUsernameInfo falhou:', err.message);
  }
  return null;
}

async function fetchViaA1Endpoint(username) {
  try {
    const res = await fetch(`https://www.instagram.com/${username}/?__a=1&__d=dis`, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'X-IG-App-ID': '936619743392459',
      },
      redirect: 'follow',
    });
    if (res.ok) {
      const data = await res.json();
      const id = data?.graphql?.user?.id || data?.data?.user?.id || data?.user?.pk_id || data?.user?.pk;
      if (id && ID_PATTERN.test(String(id))) return String(id);
    }
  } catch (err) {
    logDebug('fetchViaA1Endpoint falhou:', err.message);
  }
  return null;
}

async function fetchViaHTMLParsing(username) {
  try {
    const res = await fetch(`https://www.instagram.com/${username}/`, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      },
      redirect: 'follow',
    });
    const html = await res.text();

    const patterns = [
      /"profilePage_(\d+)"/,
      /"user_id"\s*:\s*"?(\d{10,})/,
      /"pk"\s*:\s*"?(\d{10,})/,
      /"id"\s*:\s*"(\d{10,})"/,
      /content="user:\/\/(\d{10,})"/,
      /"profile_id"\s*:\s*"?(\d{10,})/,
      /"user_id"\s*:\s*(\d{10,})/,
      /"profilePage_\d+"\s*,\s*"id"\s*:\s*"?(\d{10,})/,
      /"logging_page_id"\s*:\s*"profilePage_(\d+)"/,
      /"id"\s*:\s*(\d{15,17})/,
    ];
    for (const re of patterns) {
      const m = html.match(re);
      if (m && ID_PATTERN.test(m[1])) return m[1];
    }

    const sharedDataMatch = html.match(/window\._sharedData\s*=\s*({[\s\S]+?});\s*<\/script>/);
    if (sharedDataMatch) {
      try {
        const sd = JSON.parse(sharedDataMatch[1]);
        const id = sd?.entry_data?.ProfilePage?.[0]?.graphql?.user?.id
                || sd?.require?.[0]?.[3]?.[0]?.[1]?.__bbox?.require?.[0]?.[3]?.[1]?.__bbox?.require?.[0]?.[3]?.[1]?.__bbox?.result?.data?.user?.id;
        if (id && ID_PATTERN.test(String(id))) return String(id);
      } catch { /* JSON parse falhou */ }
    }

    const additionalDataMatch = html.match(/window\.__additionalDataLoaded\s*\(\s*['"][^'"]+['"]\s*,\s*({[\s\S]+?})\s*\)\s*;/);
    if (additionalDataMatch) {
      try {
        const ad = JSON.parse(additionalDataMatch[1]);
        const id = ad?.graphql?.user?.id || ad?.data?.user?.id || ad?.user?.pk;
        if (id && ID_PATTERN.test(String(id))) return String(id);
      } catch { /* JSON parse falhou */ }
    }

    const scriptBlocks = html.match(/<script type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g);
    if (scriptBlocks) {
      for (const block of scriptBlocks) {
        try {
          const json = JSON.parse(block.replace(/<script[^>]*>/, '').replace(/<\/script>/, ''));
          const id = json?.mainEntityofPage?.identifier?.value || json?.identifier?.value;
          if (id && ID_PATTERN.test(String(id))) return String(id);
        } catch { /* JSON parse falhou */ }
      }
    }

    if (html.includes('/accounts/login') || html.includes('"challenge"') || html.includes('loginRequired')) {
      console.log('  [aviso] Instagram exige login para acessar este perfil (challenge wall).');
    }
  } catch (err) {
    logDebug('fetchViaHTMLParsing falhou:', err.message);
  }
  return null;
}

const FETCH_STRATEGIES = [
  fetchViaWebProfileInfo,
  fetchViaUsernameInfo,
  fetchViaA1Endpoint,
  fetchViaHTMLParsing,
];

async function fetchIgUserIdFromProfile(username) {
  for (const strategy of FETCH_STRATEGIES) {
    const id = await strategy(username);
    if (id) return id;
  }
  return null;
}

// ─── Instagram — Resolução de ID ─────────────────────────────────────────────

async function resolveIgUserId(input, token) {
  const clean = input.replace(/^@/, '').trim();

  if (/^\d+$/.test(clean)) {
    if (clean.length < 10) {
      console.log(`  [aviso] ID "${clean}" parece curto. Instagram User IDs normalmente tem 15-17 digitos.`);
      console.log('  Continuando mesmo assim...\n');
    }
    return clean;
  }

  console.log('  Buscando entre suas paginas gerenciadas...');
  const managed = await getManagedPages(token);

  if (managed.length > 0) {
    const match = managed.find(p =>
      p.name.toLowerCase().includes(clean.toLowerCase()) ||
      p.instagram_business_account.username?.toLowerCase() === clean.toLowerCase()
    );
    if (match) {
      console.log(`  Encontrado: ${match.name} (IG ID: ${match.instagram_business_account.id})`);
      return match.instagram_business_account.id;
    }
  }

  console.log('  Buscando via pages/search...');
  const searched = await tryPagesSearch(clean, token);

  if (searched === null || searched.length === 0) {
    if (searched === null) {
      console.log('\n  [aviso] pages/search indisponivel (requer "Page Public Content Access" no app).');
    } else {
      console.log(`\n  Nenhuma pagina com IG Business encontrada para "${clean}".`);
    }

    console.log('  Tentando extrair ID do perfil no Instagram...\n');
    const fetchedId = await fetchIgUserIdFromProfile(clean);
    if (fetchedId && fetchedId.length >= 10) {
      console.log(`  [ok] ID encontrado: ${fetchedId}`);
      return fetchedId;
    }
    if (fetchedId) {
      console.log(`  [aviso] ID "${fetchedId}" parece curto demais para um Instagram User ID.`);
    }

    console.log('  Nao foi possivel obter o ID automaticamente.\n');
    console.log('  O Instagram Graph API so funciona com Instagram Business/Creator Accounts');
    console.log('  vinculados a uma Pagina Facebook que voce gerencia.\n');
    console.log('  Como obter o Instagram User ID:');
    console.log('    1. Abra instagram.com/<usuario> no navegador');
    console.log('    2. Pressione F12 → Console');
    console.log('    3. Cole e execute:');
    console.log('       fetch("/api/v1/users/web_profile_info/?username=" + location.pathname.split("/")[1])');
    console.log('       .then(r => r.json()).then(d => console.log(d.data.user.id))');
    console.log('    4. O ID sera um numero de ~17 digitos\n');
    console.log('  Alternativa - via Graph API (se a conta for Business):');
    console.log(`    https://graph.facebook.com/${FB_API_VERSION}/{PAGE_ID}?fields=instagram_business_account&access_token=SEU_TOKEN\n`);
    console.log('  Ou use o ID de uma de suas paginas gerenciadas (veja acima).\n');

    throw new Error('Instagram User ID nao foi possivel obter automaticamente. Veja as instrucoes acima.');
  }

  if (searched.length === 1) {
    console.log(`  Encontrado: ${searched[0].name} (IG ID: ${searched[0].instagram_business_account.id})`);
    return searched[0].instagram_business_account.id;
  }

  console.log(`\n  ${searched.length} resultados encontrados:\n`);
  searched.forEach((p, i) => {
    console.log(`  [${i + 1}] ${p.name}  |  IG ID: ${p.instagram_business_account.id}  |  Page ID: ${p.id}`);
  });

  return { multiple: searched };
}

// ─── Instagram — Validação e diagnóstico ─────────────────────────────────────

async function validateIgBusinessId(igUserId, token) {
  try {
    const data = await apiGet(`${igUserId}?fields=id,username,name,account_type`, token);
    return { valid: true, data };
  } catch (err) {
    return { valid: false, error: err.message };
  }
}

async function diagnoseIgIssue(igUserId, token) {
  console.log('\n  --- Diagnostico ---\n');
  console.log(`  ID informado: ${igUserId}`);

  const isNumeric = /^\d+$/.test(String(igUserId));
  if (isNumeric && String(igUserId).length < 18) {
    console.log('  [problema] O ID parece ser de um usuario comum, nao de uma conta Business.');
    console.log('  O Graph API so aceita Instagram Business/Creator Accounts.\n');
  }

  try {
    const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    const pages = pagesData.data || [];
    const withIG = pages.filter(p => p.instagram_business_account?.id);

    if (withIG.length > 0) {
      console.log('  Suas contas Instagram Business vinculadas:\n');
      withIG.forEach(p => {
        const ig = p.instagram_business_account;
        const match = String(ig.id) === String(igUserId) || (ig.username && ig.username.toLowerCase() === String(igUserId).toLowerCase());
        const marker = match ? ' ← ESTE' : '';
        console.log(`    - ${p.name} → @${ig.username || '?'} (ID: ${ig.id})${marker}`);
      });
      console.log('');
    } else {
      console.log('  [problema] Nenhuma conta Instagram Business vinculada a suas paginas.\n');
    }

    if (withIG.length > 0) {
      const suggested = withIG[0];
      console.log('  [sugestao] Use o ID da sua conta Business vinculada:');
      console.log(`    node instagram-feed.js`);
      console.log(`    E ao pedir o perfil, cole: ${suggested.instagram_business_account.id}`);
      if (suggested.instagram_business_account.username) {
        console.log(`    Ou: @${suggested.instagram_business_account.username}\n`);
      }
    } else {
      console.log('  [sugestao] Para usar o Graph API, voce precisa:');
      console.log('    1. Converter sua conta Instagram para Business/Creator');
      console.log('    2. Vincular a uma Pagina Facebook que voce gerencia');
      console.log('    3. Rodar: node instagram-feed.js --connect\n');
    }
  } catch (err) {
    logDebug('diagnoseIgIssue falhou:', err.message);
  }

  console.log('  [alternativa] Busca por hashtag (sem permissao extra):');
  console.log('    node instagram-feed.js --discover "tag-do-seu-nicho"\n');
}

// ─── Instagram — Download do perfil ──────────────────────────────────────────

async function downloadProfileSummary(token, query, limit) {
  const igUserId = await resolveIgUserId(query, token);

  if (typeof igUserId === 'object' && igUserId.multiple) {
    return { multiple: igUserId.multiple };
  }

  console.log('  Validando ID no Graph API...');
  const validation = await validateIgBusinessId(igUserId, token);

  if (!validation.valid) {
    console.log(`\n  [erro] ID "${igUserId}" nao e uma conta Instagram Business valida.`);
    console.log(`  Motivo: ${validation.error}\n`);
    await diagnoseIgIssue(igUserId, token);
    throw new Error(`ID "${igUserId}" nao acessivel via Graph API. Veja o diagnostico acima.`);
  }

  if (validation.data?.account_type && validation.data.account_type !== 'BUSINESS' && validation.data.account_type !== 'CREATOR') {
    console.log(`  [aviso] Tipo de conta: ${validation.data.account_type} (precisa ser BUSINESS ou CREATOR)`);
  }

  console.log('  Buscando dados do perfil...');
  const profileData = await apiGet(`${igUserId}?fields=username,name,biography,followers_count,follows_count,media_count,profile_picture_url`, token);

  console.log(`  Buscando ${limit} posts recentes (com paginacao)...`);
  const posts = await apiGetAllPages(`${igUserId}/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,like_count,comments_count,permalink`, token, limit);

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

// ─── CLI — Handlers ──────────────────────────────────────────────────────────

async function showAccounts(token) {
  console.log('\n--- Identificando sua conta ---\n');

  try {
    const me = await apiGet('me?fields=id,name', token);
    console.log('  [ok] Conta Facebook:');
    console.log(`      Nome: ${me.name}`);
    console.log(`      ID:   ${me.id}\n`);
  } catch (err) {
    console.log(`  [erro] Nao foi possivel identificar a conta: ${err.message}\n`);
  }

  console.log('--- Suas paginas gerenciadas ---\n');

  try {
    const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    const pages = pagesData.data || [];

    if (pages.length === 0) {
      console.log('  Nenhuma pagina encontrada.');
      console.log('  Crie ou gerencie uma Pagina Facebook em: https://www.facebook.com/pages/\n');
      return;
    }

    console.log(`  ${pages.length} pagina(s) encontrada(s):\n`);
    pages.forEach((p, i) => {
      const ig = p.instagram_business_account;
      console.log(`  ${i + 1}. ${p.name}`);
      console.log(`     Page ID: ${p.id}`);
      if (ig) {
        console.log(`     Instagram Business User ID: ${ig.id}`);
        console.log(`     Username: @${ig.username || '(nao informado)'}`);
        console.log(`     Use este ID para buscar posts: node instagram-feed.js --token <TOKEN> --user ${ig.id}`);
      } else {
        console.log('     Instagram: nao vinculada');
        console.log('     Vincule em: Facebook → Configuracoes da Pagina → Contas Profissionais');
      }
      console.log('');
    });

    const withIG = pages.filter(p => p.instagram_business_account?.id);
    const withoutIG = pages.filter(p => !p.instagram_business_account?.id);

    if (withoutIG.length > 0 && withIG.length > 0) {
      console.log('  NOTA: Paginas sem Instagram vinculado nao podem ser consultadas.');
      console.log('  Para vincular: Facebook → Configuracoes da Pagina → Contas Profissionais → Conectar conta\n');
    }

    if (withIG.length > 0) {
      console.log('  IDs disponiveis para uso direto:');
      withIG.forEach(p => {
        console.log(`    ${p.instagram_business_account.id}  (${p.name})`);
      });
      console.log('');
    }

    console.log('  Para buscar outros perfis (que nao sao suas paginas):');
    console.log('    1. Ative "Page Public Content Access" no App Review');
    console.log('    2. Use: node instagram-feed.js --search "nome do perfil"');
    console.log('    3. Ou use --accounts para ver seus IDs novamente\n');

  } catch (err) {
    const msg = err.message || '';
    if (msg.includes('pages_show_list')) {
      console.log('  [erro] Falta a permissao "pages_show_list".');
      console.log('  Ative em: App Review → Permissions and Features\n');
    } else {
      console.log(`  [erro] ${msg}\n`);
    }
  }
}

async function connectInstagram(token, rl, askFn) {
  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║    CONECTAR INSTAGRAM BUSINESS AO META BUSINESS         ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  try {
    const me = await apiGet('me?fields=id,name', token);
    console.log(`  [ok] Conectado como: "${me.name}" (ID: ${me.id})\n`);
  } catch (err) {
    console.log(`  [erro] Token invalido: ${err.message}\n`);
    return;
  }

  let pages = [];
  try {
    const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    pages = pagesData.data || [];
  } catch (err) {
    console.log(`  [erro] Nao foi possivel listar paginas: ${err.message}\n`);
    return;
  }

  const withoutIG = pages.filter(p => !p.instagram_business_account?.id);
  const withIG = pages.filter(p => p.instagram_business_account?.id);

  if (withIG.length > 0) {
    console.log('  [ok] Paginas ja com Instagram Business vinculado:\n');
    withIG.forEach(p => {
      console.log(`    ✓ ${p.name} → @${p.instagram_business_account.username || '?'} (ID: ${p.instagram_business_account.id})`);
    });
    console.log('');
  }

  if (withoutIG.length === 0 && withIG.length > 0) {
    console.log('  Todas suas paginas ja tem Instagram vinculado.');
    console.log('  Se quiser vincular outra pagina, crie uma nova Pagina Facebook primeiro.\n');
  } else if (withoutIG.length === 0 && pages.length === 0) {
    console.log('  [aviso] Nenhuma Pagina Facebook encontrada.');
    console.log('  Voce precisa criar uma Pagina Facebook antes de conectar o Instagram.\n');
    console.log('  Criar pagina: https://www.facebook.com/pages/create/\n');
  }

  if (withoutIG.length > 0) {
    console.log(`  Paginas SEM Instagram vinculado (${withoutIG.length}):\n`);
    withoutIG.forEach((p, i) => {
      console.log(`    ${i + 1}. ${p.name} (ID: ${p.id})`);
    });
    console.log('');

    console.log('  ────────────────────────────────────────────────────────\n');
    console.log('  PASSO A PASSO para conectar:\n');
    console.log('  O navegador sera aberto no Meta Business Suite.\n');
    console.log('  1. Faca login com sua conta Facebook (se pedir)');
    console.log('  2. No menu lateral, va em "Configuracoes" (engrenagem)');
    console.log('  3. Clique em "Contas" → "Contas de Instagram"');
    console.log('  4. Clique em "Conectar conta"');
    console.log('  5. Escolha a Pagina Facebook que quer vincular');
    console.log('  6. Faca login na sua conta Instagram');
    console.log('  7. Autorize o acesso');
    console.log('  8. Pronto! Volte ao terminal e confirme\n');
    console.log('  ────────────────────────────────────────────────────────\n');
  }

  const bizUrl = 'https://business.facebook.com/settings/instagram';
  console.log('  Abrindo Meta Business Suite no navegador...\n');
  console.log('  Se nao abrir, copie e cole:');
  console.log(`  ${bizUrl}\n`);

  openBrowser(bizUrl);

  const confirmou = (await askFn('  Voce conectou o Instagram? (s/N): ')).trim().toLowerCase();
  if (confirmou !== 's' && confirmou !== 'sim') {
    console.log('\n  Connecte primeiro e rode novamente: node instagram-feed.js --connect\n');
    return;
  }

  console.log('\n  Verificando conexao...\n');
  await sleep(2000);

  try {
    const pagesData2 = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    const pages2 = pagesData2.data || [];
    const withIG2 = pages2.filter(p => p.instagram_business_account?.id);
    const withoutIG2 = pages2.filter(p => !p.instagram_business_account?.id);

    if (withIG2.length === 0) {
      console.log('  [aviso] Nenhuma pagina com Instagram detectada ainda.');
      console.log('  Algumas causas possiveis:');
      console.log('    - A conta Instagram nao e Business/Creator');
      console.log('    - A conexao ainda nao foi finalizada');
      console.log('    - O token nao tem acesso a pagina correta\n');
      console.log('  Para converter sua conta Instagram em Business:');
      console.log('    1. Abra o app Instagram');
      console.log('    2. Configuracoes → Conta → Mudar para conta profissional');
      console.log('    3. Escolha a categoria');
      console.log('    4. Conecte a uma Pagina Facebook existente\n');
    } else {
      console.log(`  [ok] ${withIG2.length} pagina(s) com Instagram Business:\n`);
      withIG2.forEach(p => {
        console.log(`    ✓ ${p.name}`);
        console.log(`      Instagram: @${p.instagram_business_account.username || '?'}`);
        console.log(`      User ID:   ${p.instagram_business_account.id}`);
        console.log(`      Comando:   node instagram-feed.js --user ${p.instagram_business_account.id}\n`);
      });

      if (withoutIG2.length > 0) {
        console.log(`  ${withoutIG2.length} pagina(s) ainda sem Instagram vinculado.`);
      }

      console.log('  [ok] Conexao verificada! Agora voce pode:');
      console.log('    - Buscar posts: node instagram-feed.js --user <IG_USER_ID>');
      console.log('    - Descobrir perfis: node instagram-feed.js --discover "hashtag"');
      console.log('    - Ver contas: node instagram-feed.js --accounts\n');
    }
  } catch (err) {
    console.log(`  [aviso] Nao foi verificar: ${err.message}`);
    console.log('  Tente: node instagram-feed.js --accounts\n');
  }
}

async function handleSearch(token) {
  const query = getArg('--search');
  if (!query) throw new Error('Informe o nome para busca.');

  console.log(`\nBuscando por: ${query}`);
  const results = await tryPagesSearch(query, token);

  if (results === null) {
    console.log('\n  [erro] pages/search requer "Page Public Content Access".');
    console.log('  Ative em: App Review → Permissions and Features');
    console.log('  Ou use --accounts para ver suas paginas.\n');
  } else if (results.length === 0) {
    console.log(`\n  Nenhum resultado para "${query}".`);
  } else {
    console.log(`\n  ${results.length} resultado(s):\n`);
    results.forEach((p, i) => {
      console.log(`  [${i + 1}] ${p.name}`);
      console.log(`      Page ID:    ${p.id}`);
      console.log(`      IG User ID: ${p.instagram_business_account.id}`);
      console.log(`      Username:   @${p.instagram_business_account.username || '?'}\n`);
    });
  }
}

async function handleDiscover(token, rl, askFn) {
  const hashtag = getArg('--discover');
  if (!hashtag) throw new Error('Informe a hashtag.');

  console.log(`\n--- Descobrindo perfis via hashtag #${hashtag} ---\n`);
  console.log('  Buscando posts recentes...\n');

  const result = await searchHashtag(hashtag, token);

  if (result.error === 'no_pages') {
    console.log('  [erro] Nenhuma pagina gerenciada com IG Business.');
    console.log('  Crie uma Pagina Facebook e vincule sua conta Instagram Business.\n');
    return;
  }
  if (result.error === 'not_found') {
    console.log(`  Hashtag #${hashtag} nao encontrada no Instagram.`);
    console.log('  Tente outra tag.\n');
    return;
  }
  if (result.error === 'no_permission') {
    console.log('  [erro] Falta a permissao "instagram_basic" ou "pages_read_engagement".');
    console.log('  Ative em: App Review → Permissions and Features\n');
    return;
  }

  const { profiles, posts } = result;

  if (profiles.length === 0) {
    console.log('  Nenhum post encontrado para esta hashtag.\n');
    return;
  }

  console.log(`  Hashtag: #${hashtag}`);
  console.log(`  Posts encontrados: ${posts.length}`);
  console.log(`  Perfis unicos: ${profiles.length}\n`);
  console.log('  Perfis mais ativos nesta hashtag:\n');

  const top = profiles.slice(0, 20);
  top.forEach((p, i) => {
    const avgLikes = p.post_count ? (p.total_likes / p.post_count).toFixed(0) : 0;
    const avgComments = p.post_count ? (p.total_comments / p.post_count).toFixed(0) : 0;
    console.log(`  ${String(i + 1).padStart(2)}. @${p.username}`);
    console.log(`      Posts: ${p.post_count} | Likes medio: ${avgLikes} | Comentarios medio: ${avgComments}`);
  });

  console.log('\n  Para analisar um perfil, use:');
  console.log(`    node instagram-feed.js --token <TOKEN> --user <USERNAME> --limit 25\n`);

  const discoverAll = (await askFn('  Exportar todos os perfis para JSON? (s/N): ')).trim().toLowerCase();
  if (discoverAll === 's' || discoverAll === 'sim') {
    const filename = `instagram-discover-${hashtag}.json`;
    fs.writeFileSync(filename, JSON.stringify({ hashtag, profiles, posts }, null, 2), 'utf-8');
    console.log(`\n  Salvo em: ${filename}`);
  }
}

async function handleInteractiveFeed(token, rl, askFn) {
  console.log('\nFormats de busca:');
  console.log('  - Nome da pagina:  "nike" ou "Nike Brasil"');
  console.log('  - Com @:           @nike');
  console.log('  - ID numerico:     17841400123456789');
  console.log('  (ou use --accounts / --search / --discover)\n');

  const user = (await askFn('Buscar perfil: ')).trim();
  if (!user) throw new Error('Perfil vazio.');

  const limitStr = (await askFn('Quantidade de posts (padrao 25): ')).trim();
  const limit = parseInt(limitStr, 10) || 25;

  console.log('\n--- Iniciando ---\n');

  const summary = await downloadProfileSummary(token, user, limit);

  if (summary.multiple) {
    console.log(`\n  ${summary.multiple.length} resultados encontrados:\n`);
    summary.multiple.forEach((p, i) => {
      console.log(`  [${i + 1}] ${p.name}  |  IG ID: ${p.instagram_business_account.id}  |  Page ID: ${p.id}`);
    });
    const choice = (await askFn(`\n  Escolha o numero (1-${summary.multiple.length}): `)).trim();
    const idx = parseInt(choice, 10) - 1;
    if (idx < 0 || idx >= summary.multiple.length) throw new Error('Escolha invalida.');
    const selected = summary.multiple[idx].instagram_business_account.id;
    console.log(`\n  Buscando dados de ${selected}...\n`);
    const summary2 = await downloadProfileSummary(token, selected, limit);
    return printAndSave(summary2, selected, askFn);
  }

  await printAndSave(summary, user, askFn);
}

async function printAndSave(summary, user, askFn) {
  const filename = `instagram-${summary.perfil.username || sanitizeFilename(user)}-resumo.json`;
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
}

// ─── Resolução de Token ──────────────────────────────────────────────────────

async function resolveToken(rl, askFn) {
  const env = loadEnv();
  const savedToken = env.FB_ACCESS_TOKEN || '';

  if (savedToken) {
    console.log('  Access Token salvo encontrado em .env\n');

    console.log('  Vervalido validade do token...');
    const valid = await isTokenValid(savedToken);
    if (!valid) {
      console.log('  [aviso] O token salvo parece estar expirado ou invalido.\n');
    }

    const useSaved = (await askFn('Usar token salvo? (S/n): ')).trim().toLowerCase();
    if (useSaved === 'n' || useSaved === 'nao') {
      const hasToken = (await askFn('Cole seu Access Token: ')).trim();
      if (!hasToken) throw new Error('Token vazio.');
      return hasToken;
    }

    if (!valid) {
      console.log('  [aviso] Continuando com token potencialmente expirado...');
    }
    return savedToken;
  }

  const hasToken = (await askFn('Voce ja tem um Access Token? (s/N): ')).trim().toLowerCase();
  if (hasToken === 's' || hasToken === 'sim') {
    const token = (await askFn('Cole seu Access Token: ')).trim();
    if (!token) throw new Error('Token vazio.');
    return token;
  }
  return setupApp(rl, askFn);
}

// ─── Help ────────────────────────────────────────────────────────────────────

function showHelp() {
  console.log(`
Uso interativo: node instagram-feed.js
  Configura automaticamente o app e autentica via navegador.
  Credenciais (App ID/Secret/Token) salvas automaticamente em .env.

Uso direto: node instagram-feed.js --token TOKEN --user "NOME OU ID" [--limit NUM]

Comandos:
  --accounts          Mostra sua conta e paginas gerenciadas com IDs
  --connect           Conecta Instagram Business ao Meta Business (abre browser)
  --search "nome"     Busca perfil por nome (requer Page Public Content Access)
  --discover "tag"    Descobre perfis via hashtag (sem permissao extra!)

Fluxo interativo:
  1. Verifica se tem credenciais salvas em .env
  2. Se nao, pede App ID + App Secret e salva
  3. Abre o navegador para autenticacao OAuth automatica
  4. Recebe o codigo, converte para token de longo prazo
  5. Verifica permissoes e Instagram Graph API
  6. Pronto para usar

Conexao com Instagram (recomendado rodar primeiro):
  node instagram-feed.js --connect
  → Abre o Meta Business Suite e guia voce passo a passo
  → Conecta sua conta Instagram Business a uma Pagina Facebook

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

Para buscar QUALQUER perfil publico, ative tambem:
  6. App Review → Permissions and Features → ative:
     - Page Public Content Access (ou Page Public Metadata Access)
     - Envie o app para revisao

Descoberta por hashtag (SEM permissao extra):
  node instagram-feed.js --discover "fitness"
  node instagram-feed.js --discover "streetwear"
  node instagram-feed.js --discover "skateboarding"
  → Busca posts recentes da hashtag e lista perfis mais ativos
  → Requer apenas instagram_basic + pagina gerenciada

Variaveis de ambiente:
  FB_API_VERSION      Versao da Graph API (default: v18.0)
  FB_REDIRECT_PORT    Porta do servidor OAuth (default: 18923)
  DEBUG               Ativa logs de debug (qualquer valor)

Nota: Para apps em modo desenvolvimento, so Administradores podem usar.
`);
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  if (hasFlag('--help') || hasFlag('-h')) {
    showHelp();
    process.exit(0);
  }

  console.log('=== Instagram Feed Resumo (CLI) ===\n');

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });
  const askFn = q => new Promise(resolve => rl.question(q, resolve));

  try {
    if (hasFlag('--token')) {
      const token = getArg('--token');
      const user = getArg('--user');
      const limIdx = process.argv.indexOf('--limit');
      const limit = limIdx >= 0 ? parseInt(process.argv[limIdx + 1], 10) || 25 : 25;

      if (!token || !user) throw new Error('Uso: --token TOKEN --user "USUARIO"');

      console.log('\n--- Iniciando ---\n');
      const summary = await downloadProfileSummary(token, user, limit);

      if (summary.multiple) {
        console.log(`\n  ${summary.multiple.length} resultados encontrados:\n`);
        summary.multiple.forEach((p, i) => {
          console.log(`  [${i + 1}] ${p.name}  |  IG ID: ${p.instagram_business_account.id}  |  Page ID: ${p.id}`);
        });
        const choice = (await askFn(`\n  Escolha o numero (1-${summary.multiple.length}): `)).trim();
        const idx = parseInt(choice, 10) - 1;
        if (idx < 0 || idx >= summary.multiple.length) throw new Error('Escolha invalida.');
        const selected = summary.multiple[idx].instagram_business_account.id;
        const summary2 = await downloadProfileSummary(token, selected, limit);
        await printAndSave(summary2, selected, askFn);
      } else {
        await printAndSave(summary, user, askFn);
      }
      rl.close();
      return;
    }

    const token = await resolveToken(rl, askFn);

    const commands = [
      ['--connect',  () => connectInstagram(token, rl, askFn)],
      ['--accounts', () => showAccounts(token)],
      ['--search',   () => handleSearch(token)],
      ['--discover', () => handleDiscover(token, rl, askFn)],
    ];

    for (const [flag, handler] of commands) {
      if (hasFlag(flag)) {
        await handler();
        rl.close();
        return;
      }
    }

    await handleInteractiveFeed(token, rl, askFn);
  } catch (err) {
    console.error(`\nErro: ${err.message}`);
    if (DEBUG) console.error(err.stack);
    process.exit(1);
  } finally {
    rl.close();
  }
}

// Só exporta se for importado como módulo (permite testes)
if (require.main === module) {
  main();
}

module.exports = {
  loadEnv,
  saveEnv,
  sleep,
  openBrowser,
  sanitizeFilename,
  getArg,
  hasFlag,
  apiGet,
  apiGetWithRetry,
  apiGetAllPages,
  getAppAccessToken,
  exchangeCodeForToken,
  exchangeForLongLivedToken,
  isTokenValid,
  getManagedPages,
  tryPagesSearch,
  searchHashtag,
  fetchIgUserIdFromProfile,
  resolveIgUserId,
  validateIgBusinessId,
  diagnoseIgIssue,
  downloadProfileSummary,
  startLocalServer,
  verifyApp,
  setupApp,
  showAccounts,
  connectInstagram,
  handleSearch,
  handleDiscover,
  handleInteractiveFeed,
  printAndSave,
  resolveToken,
  showHelp,
  main,
  API_BASE,
  REDIRECT_PORT,
  REDIRECT_URI,
  ENV_FILE,
  REQUIRED_PERMISSIONS,
  IG_HEADERS,
  ID_PATTERN,
  FETCH_STRATEGIES,
};

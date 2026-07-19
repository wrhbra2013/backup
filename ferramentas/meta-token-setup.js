#!/usr/bin/env node

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { exec } = require('child_process');
const crypto = require('crypto');

const REDIRECT_PORT = 9876;
const REDIRECT_URI = `http://localhost:${REDIRECT_PORT}/callback`;
const GRAPH_API = 'https://graph.facebook.com/v18.0';
const CONFIG_PATH = path.join(__dirname, '.meta-config.json');
const ENV_PATH = path.join(__dirname, '.env');
const SCOPES = [
  'pages_show_list',
  'pages_read_engagement',
  'instagram_basic',
  'instagram_manage_insights',
  'business_management',
].join(',');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = q => new Promise(resolve => rl.question(q, resolve));

process.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });

// ── Config ──────────────────────────────────────────────

function loadConfig() {
  if (fs.existsSync(CONFIG_PATH)) {
    try { return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8')); }
    catch { return null; }
  }
  return null;
}

function saveConfig(config) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), 'utf-8');
  console.log(`  Config salva em: ${CONFIG_PATH}`);
}

function resetConfig() {
  if (fs.existsSync(CONFIG_PATH)) fs.unlinkSync(CONFIG_PATH);
  console.log('  Config resetada.');
}

// ── Env ─────────────────────────────────────────────────

function loadEnv() {
  if (!fs.existsSync(ENV_PATH)) return {};
  const env = {};
  fs.readFileSync(ENV_PATH, 'utf-8').split('\n').forEach(l => {
    const m = l.match(/^([A-Z_]+)=(.*)$/);
    if (m) env[m[1]] = m[2].trim();
  });
  return env;
}

function saveEnv(updates) {
  let lines = [];
  if (fs.existsSync(ENV_PATH)) {
    lines = fs.readFileSync(ENV_PATH, 'utf-8').split('\n').filter(l => {
      const key = l.match(/^([A-Z_]+)=/);
      return key && !(key[1] in updates);
    });
  }
  for (const [k, v] of Object.entries(updates)) {
    if (v !== undefined && v !== null && v !== '') lines.push(`${k}=${v}`);
  }
  fs.writeFileSync(ENV_PATH, lines.join('\n') + '\n', 'utf-8');
}

// ── HTTP ────────────────────────────────────────────────

function openBrowser(url) {
  const platform = process.platform;
  const cmd = platform === 'darwin' ? 'open' : platform === 'win32' ? 'start' : 'xdg-open';
  exec(`${cmd} "${url}"`, err => {
    if (err) console.log(`\n  Abra manualmente no navegador:\n  ${url}\n`);
  });
}

function httpGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); }
        catch { reject(new Error(`Resposta invalida: ${body.substring(0, 200)}`)); }
      });
    }).on('error', reject);
  });
}

function httpPost(url, data) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const postData = new URLSearchParams(data).toString();
    const req = https.request({
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(postData) },
    }, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); }
        catch { reject(new Error(`Resposta invalida: ${body.substring(0, 200)}`)); }
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

function startCallbackServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const url = new URL(req.url, `http://localhost:${REDIRECT_PORT}`);
      const code = url.searchParams.get('code');
      const error = url.searchParams.get('error');

      if (error) {
        res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(`<h2>Erro: ${error}</h2><p>${url.searchParams.get('error_description') || ''}</p>`);
        server.close();
        reject(new Error(`OAuth erro: ${error}`));
        return;
      }

      if (code) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(`<h2>Autorizado!</h2><p>Pode fechar esta janela.</p>`);
        server.close();
        resolve(code);
        return;
      }

      res.writeHead(404); res.end('Not found');
    });

    server.listen(REDIRECT_PORT, () => {
      console.log(`  Callback em http://localhost:${REDIRECT_PORT}`);
    });

    server.on('error', err => {
      if (err.code === 'EADDRINUSE') {
        console.error(`\n  Porta ${REDIRECT_PORT} em uso. Feche o programa e tente novamente.`);
        process.exit(1);
      }
      reject(err);
    });
  });
}

// ── API ─────────────────────────────────────────────────

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const data = await httpGet(`${GRAPH_API}/${endpoint}${sep}access_token=${token}`);
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function exchangeCodeForToken(code, appId, appSecret) {
  const data = await httpGet(`${GRAPH_API}/oauth/access_token?` +
    `client_id=${appId}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&client_secret=${appSecret}&code=${code}`);
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function exchangeForLongLived(shortToken, appId, appSecret) {
  const data = await httpGet(`${GRAPH_API}/oauth/access_token?` +
    `grant_type=fb_exchange_token&client_id=${appId}&client_secret=${appSecret}&fb_exchange_token=${shortToken}`);
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function getApps(token) {
  const data = await apiGet('me/apps?fields=id,name,app_domains,category,status', token);
  return data.data || [];
}

async function getPages(token) {
  const data = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
  return data.data || [];
}

async function createApp(token) {
  const data = await httpPost(`${GRAPH_API}/me/apps`, {
    name: `instagram-feed-${Date.now()}`,
    category: 'BUSINESS',
    access_token: token,
  });
  if (data.error) throw new Error(data.error.message);
  return data;
}

// ── Main ────────────────────────────────────────────────

async function main() {
  console.log('=== Meta Token Setup ===\n');

  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log(`
Uso: node meta-token-setup.js [opcoes]

Opcoes:
  --reset     Apaga config salva e pede App ID/Secret novamente
  --help      Mostra esta ajuda

Fluxo:
  1. Abre navegador para login no Facebook
  2. Busca apps existentes na sua conta
  3. Permite criar app novo se nao existir
  4. Gera token longo (60 dias) e salva em .env

Config (.meta-config.json) e salva na primeira vez.
Nas proximas execucoes, usa os dados automaticamente.
`);
    process.exit(0);
  }

  if (process.argv.includes('--reset')) {
    resetConfig();
    process.exit(0);
  }

  let config = loadConfig();
  let appId, appSecret;

  if (config && config.appId && config.appSecret) {
    console.log(`  Config encontrada:`);
    console.log(`    App ID:     ${config.appId}`);
    console.log(`    App Secret: ${'*'.repeat(8)}${config.appSecret.slice(-4)}`);
    const use = await ask('\n  Usar esta config? (S/n/r=reset): ');

    if (use.toLowerCase() === 'r') {
      resetConfig();
      config = null;
    } else if (use.toLowerCase() === 'n') {
      config = null;
    } else {
      appId = config.appId;
      appSecret = config.appSecret;
    }
  }

  if (!appId) {
    console.log('\n  Informe os dados do seu app Facebook:');
    console.log('  (Crie em: https://developers.facebook.com/apps/)\n');
    appId = (await ask('  App ID: ')).trim();
    if (!appId) { console.error('  App ID obrigatorio.'); process.exit(1); }

    appSecret = (await ask('  App Secret: ')).trim();
    if (!appSecret) { console.error('  App Secret obrigatorio.'); process.exit(1); }

    saveConfig({ appId, appSecret });
  }

  console.log('\n  Iniciando OAuth...');
  console.log(`  Permissoes: ${SCOPES}\n`);

  const authUrl = `https://www.facebook.com/v18.0/dialog/oauth?` +
    `client_id=${appId}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&` +
    `response_type=code&scope=${SCOPES}&state=${crypto.randomBytes(16).toString('hex')}`;

  console.log('  Abrindo navegador...');
  openBrowser(authUrl);

  const code = await startCallbackServer();

  console.log('\n  Trocando codigo por token...');
  const shortToken = await exchangeCodeForToken(code, appId, appSecret);
  console.log(`  Token curto: expira em ${shortToken.expires_in || '?'}s`);

  const user = await apiGet('me?fields=id,name', shortToken.access_token);
  console.log(`  Logado como: ${user.name} (${user.id})`);

  console.log('\n  Buscando seus apps...');
  const apps = await getApps(shortToken.access_token);

  if (apps.length > 0) {
    console.log(`\n  ${apps.length} app(s) encontrado(s):\n`);
    apps.forEach((app, i) => {
      const st = app.status === 1 ? 'ativo' : app.status === 2 ? 'inativo' : `#${app.status}`;
      console.log(`  [${i + 1}] ${app.name}  |  ${app.id}  |  ${st}`);
    });

    const choice = (await ask(`\n  Escolha (1-${apps.length}) ou Enter p/ usar o informado: `)).trim();
    if (choice) {
      const idx = parseInt(choice, 10) - 1;
      if (idx >= 0 && idx < apps.length) {
        appId = apps[idx].id;
        saveConfig({ appId, appSecret });
      }
    }
  } else {
    console.log('\n  Nenhum app encontrado.');
    const create = await ask('  Criar app novo? (S/n): ');
    if (create.toLowerCase() !== 'n') {
      const newApp = await createApp(shortToken.access_token);
      appId = newApp.id;
      console.log(`  App criado: ${appId}`);
      console.log(`  Va em https://developers.facebook.com/apps/${appId}/basic/ para ver o App Secret.`);
      appSecret = (await ask('  App Secret: ')).trim();
      saveConfig({ appId, appSecret });
    }
  }

  console.log('\n  Gerando token longo (60 dias)...');
  try {
    const longToken = await exchangeForLongLived(shortToken.access_token, appId, appSecret);
    console.log('  Token longo gerado!');

    saveEnv({
      META_ACCESS_TOKEN: longToken.access_token,
      META_TOKEN_EXPIRES: new Date(Date.now() + (longToken.expires_in || 0) * 1000).toISOString(),
      META_USER_ID: user.id,
      META_USER_NAME: user.name,
      META_APP_ID: appId,
      META_APP_SECRET: appSecret,
    });

    const pages = await getPages(longToken.access_token);
    const withIg = pages.filter(p => p.instagram_business_account);
    const withoutIg = pages.filter(p => !p.instagram_business_account);

    if (withIg.length > 0) {
      console.log(`\n  Paginas com Instagram Business:\n`);
      withIg.forEach((p, i) => {
        console.log(`  [${i + 1}] ${p.name}  |  IG: ${p.instagram_business_account.id}  |  Page: ${p.id}`);
      });
      console.log(`\n  Uso:`);
      console.log(`    source .env`);
      console.log(`    node instagram-feed.js --token "$META_ACCESS_TOKEN" --user "${withIg[0].name}"`);
    } else {
      console.log('\n  Nenhuma pagina com Instagram Business encontrada.');
    }

    if (withoutIg.length > 0) {
      console.log(`\n  Paginas SEM Instagram Business:`);
      withoutIg.forEach(p => console.log(`    - ${p.name} (${p.id})`));
    }

  } catch (err) {
    console.error(`\n  Erro token longo: ${err.message}`);
    console.log('  Salvando token curto...');
    saveEnv({
      META_ACCESS_TOKEN: shortToken.access_token,
      META_USER_ID: user.id,
      META_USER_NAME: user.name,
      META_APP_ID: appId,
      META_APP_SECRET: appSecret,
    });
  }

  console.log('');
  rl.close();
}

main().catch(err => {
  console.error(`\nErro: ${err.message}`);
  process.exit(1);
});

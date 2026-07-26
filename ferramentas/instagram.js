#!/usr/bin/env node
/**
 * Instagram Tool - Script unificado
 * Resumo de perfis + gerenciamento de tokens + limpeza de arquivos
 *
 * Uso:
 *   node instagram.js perfil <username> [--posts N]    Busca perfil publico (sem API)
 *   node instagram.js feed <usuario> [--limit N]       Busca via Graph API (precisa token)
 *   node instagram.js token                            Configura token OAuth (Meta)
 *   node instagram.js accounts                         Lista paginas gerenciadas
 *   node instagram.js cleanup [--dry-run]              Remove arquivos desnecessarios
 *   node instagram.js --help                           Mostra ajuda
 */

'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const { URL } = require('url');
const readline = require('readline');
const { execSync } = require('child_process');

// ─── Constantes ──────────────────────────────────────────────────────────────

const DIR = __dirname;
const ENV_FILE = path.join(DIR, '.env');
const CONFIG_FILE = path.join(DIR, '.meta-config.json');
const FB_API_VERSION = process.env.FB_API_VERSION || 'v18.0';
const API_BASE = `https://graph.facebook.com/${FB_API_VERSION}`;
const REDIRECT_PORT = parseInt(process.env.FB_REDIRECT_PORT, 10) || 18923;
const REDIRECT_URI = `http://localhost:${REDIRECT_PORT}/callback`;
const REQUIRED_PERMISSIONS = ['instagram_basic', 'pages_show_list', 'pages_read_engagement'];
const RETRY_MAX = 3;
const RETRY_BASE_MS = 1000;
const OAUTH_TIMEOUT_MS = 5 * 60 * 1000;
const SERVER_PORT = parseInt(process.env.INSTAGRAM_PORT || '18925', 10);
const DEBUG = !!process.env.DEBUG;

const IG_HEADERS = {
  'User-Agent': 'Instagram 275.0.0.27.98 Android (30/11; 420dpi; 1080x2400; samsung; SM-A515F; a51; exynos9611; en_US; 458229258)',
  'Accept': '*/*',
  'Accept-Language': 'en-US',
  'X-IG-App-ID': '936619743392459',
  'X-Requested-With': 'XMLHttpRequest',
};

const DESKTOP_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
};

// ─── Arquivos que NAO sao apagados na limpeza (protegidos) ───────────────────

const PROTECTED_FILES = new Set([
  'instagram.js',
  'instagram-feed.js',
  'instagram-perfil.js',
  'instagram-perfil.py',
  'instagram-feed.html',
  'server.js',
  'meta-token-setup.js',
  'build.js',
  'package.json',
  'package-lock.json',
  'node_modules',
  '.env',
  '.meta-config.json',
  'configurar-instagram-graph-api.md',
  'configurar-instagram-graph-api.html',
  'configurar-instagram-graph-api.pdf',
  'instagram-passo-a-passo.pdf',
]);

// ─── Utilitarios ─────────────────────────────────────────────────────────────

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

function saveEnv(updates) {
  let lines = [];
  if (fs.existsSync(ENV_FILE)) {
    lines = fs.readFileSync(ENV_FILE, 'utf-8').split('\n').filter(l => {
      const idx = l.indexOf('=');
      if (idx < 1) return false;
      const key = l.slice(0, idx).trim();
      return !(key in updates);
    });
  }
  for (const [k, v] of Object.entries(updates)) {
    if (v !== undefined && v !== null) lines.push(`${k}=${v}`);
  }
  fs.writeFileSync(ENV_FILE, lines.join('\n') + '\n', 'utf-8');
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function sanitizeFilename(str) { return str.replace(/[^a-zA-Z0-9]/g, '_'); }

function openBrowser(url) {
  const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
  try { execSync(`${cmd} "${url}" 2>/dev/null`); } catch {}
}

function logDebug(...args) { if (DEBUG) console.log('  [debug]', ...args); }

// ─── CLI ─────────────────────────────────────────────────────────────────────

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
rl.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });
const ask = q => new Promise(resolve => rl.question(q, resolve));

function getArg(name) {
  const idx = process.argv.indexOf(name);
  if (idx < 0 || idx + 1 >= process.argv.length) return null;
  return process.argv[idx + 1];
}

function hasFlag(name) { return process.argv.includes(name); }

function getPositionalArgs() {
  return process.argv.slice(2).filter(a => !a.startsWith('--'));
}

// ─── Graph API ───────────────────────────────────────────────────────────────

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const url = `${API_BASE}/${endpoint}${sep}access_token=${token}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function apiGetWithRetry(endpoint, token, retries = RETRY_MAX) {
  for (let i = 0; i < retries; i++) {
    try { return await apiGet(endpoint, token); }
    catch (err) {
      if (i === retries - 1) throw err;
      if (!/429|500|502|503/.test(err.message)) throw err;
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

async function isTokenValid(token) {
  try { await apiGet('me?fields=id', token); return true; }
  catch { return false; }
}

// ─── OAuth ───────────────────────────────────────────────────────────────────

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

function startLocalServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const parsed = new URL(req.url, `http://localhost:${REDIRECT_PORT}`);
      if (parsed.pathname === '/callback') {
        const code = parsed.searchParams.get('code');
        const error = parsed.searchParams.get('error');
        if (error) {
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<html><body style="font-family:sans-serif;text-align:center;padding:60px;"><h2>Erro na autenticacao</h2><p>${error}</p></body></html>`);
          reject(new Error(`Erro OAuth: ${error}`));
          server.close(); return;
        }
        if (code) {
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<html><body style="font-family:sans-serif;text-align:center;padding:60px;"><h2 style="color:#4caf50;">Autenticado com sucesso!</h2><p>Pode fechar esta janela.</p></body></html>`);
          resolve(code); server.close(); return;
        }
        res.writeHead(404); res.end('Not found');
      } else {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(`<html><body style="font-family:sans-serif;text-align:center;padding:60px;"><h2>Aguardando autenticacao...</h2></body></html>`);
      }
    });
    server.listen(REDIRECT_PORT, () => console.log(`  Servidor OAuth na porta ${REDIRECT_PORT}`));
    server.on('error', err => {
      if (err.code === 'EADDRINUSE') { console.error(`  [erro] Porta ${REDIRECT_PORT} em uso.`); process.exit(1); }
      reject(err);
    });
    setTimeout(() => { reject(new Error('Timeout OAuth (5 min)')); server.close(); }, OAUTH_TIMEOUT_MS);
  });
}

// ─── Instagram Scraping (sem API) ────────────────────────────────────────────

async function tryFetch(url, headers) {
  try {
    const res = await fetch(url, { headers, redirect: 'follow' });
    if (!res.ok) return null;
    const text = await res.text();
    try { return JSON.parse(text); } catch { return text; }
  } catch { return null; }
}

async function scrapeProfile(username) {
  const clean = username.replace(/^@/, '');

  logDebug('Tentativa 1: API mobile...');
  let data = await tryFetch(
    `https://i.instagram.com/api/v1/users/web_profile_info/?username=${clean}`,
    IG_HEADERS
  );
  if (data?.data?.user) return data.data.user;

  logDebug('Tentativa 2: Pagina web...');
  const htmlRes = await tryFetch(`https://www.instagram.com/${clean}/`, DESKTOP_HEADERS);
  if (typeof htmlRes === 'string') {
    const idMatch = htmlRes.match(/"user_id"\s*:\s*"?(\d{10,})/);
    if (idMatch) {
      logDebug('Tentativa 3: full_detail...');
      const apiRes = await tryFetch(
        `https://i.instagram.com/api/v1/users/${idMatch[1]}/full_detail/`,
        IG_HEADERS
      );
      if (apiRes?.user) return apiRes.user;
    }
  }

  return null;
}

// ─── Resumo de Perfil ────────────────────────────────────────────────────────

function buildSummary(user, maxPosts = 25) {
  const edgePosts = user.edge_owner_to_timeline_media || user.edge_felix_timeline || { edges: [] };
  const posts = (edgePosts.edges || []).slice(0, maxPosts).map(e => {
    const node = e.node || e;
    const caption = node.edge_media_to_caption?.edges?.[0]?.node?.text || null;
    return {
      id: node.id || null,
      shortcode: node.shortcode || null,
      data: node.taken_at_timestamp ? new Date(node.taken_at_timestamp * 1000).toISOString() : null,
      legenda: caption,
      tipo: node.is_video ? 'VIDEO' : (node.__typename || 'IMAGE'),
      likes: node.edge_liked_by?.count ?? node.edge_media_preview_like?.count ?? 0,
      comentarios: node.edge_media_to_comment?.count ?? 0,
      views: node.video_view_count || null,
      url: node.shortcode ? `https://www.instagram.com/p/${node.shortcode}/` : null,
      thumbnail: node.thumbnail_src || node.display_url || null,
      hashtags: (caption?.match(/#[\w\u00C0-\u024F]+/g) || []),
      mencoes: (caption?.match(/@[\w.]+/g) || []),
    };
  });

  const totalLikes = posts.reduce((s, p) => s + p.likes, 0);
  const totalComments = posts.reduce((s, p) => s + p.comentarios, 0);

  const allHashtags = {};
  posts.forEach(p => p.hashtags.forEach(t => { allHashtags[t] = (allHashtags[t] || 0) + 1; }));
  const topHashtags = Object.entries(allHashtags)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 20)
    .map(([tag, count]) => ({ tag, vezes: count }));

  return {
    perfil: {
      username: user.username,
      nome: user.full_name || null,
      bio: user.biography || null,
      seguidores: user.edge_followed_by?.count ?? user.follower_count ?? null,
      seguindo: user.edge_follow?.count ?? user.following_count ?? null,
      total_posts: user.edge_owner_to_timeline_media?.count ?? user.media_count ?? null,
      eh_business: user.is_business ?? user.is_business_account ?? null,
      categoria: user.business_category_name || user.category_name || null,
      url_perfil: user.profile_pic_url_hd || user.profile_pic_url || null,
      url: `https://www.instagram.com/${user.username}/`,
      verificado: user.is_verified ?? null,
    },
    estatisticas: {
      posts_baixados: posts.length,
      total_likes: totalLikes,
      total_comentarios: totalComments,
      media_likes_por_post: posts.length ? +(totalLikes / posts.length).toFixed(1) : 0,
      media_comentarios_por_post: posts.length ? +(totalComments / posts.length).toFixed(1) : 0,
    },
    hashtags_mais_usadas: topHashtags,
    posts,
    buscado_em: new Date().toISOString(),
  };
}

function buildApiSummary(profileData, posts) {
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
      id_ig_business: profileData.id || null,
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
    buscado_em: new Date().toISOString(),
  };
}

// ─── HTML Generator ──────────────────────────────────────────────────────────

function generateHtml(summary) {
  const dataJson = JSON.stringify(summary, null, 2);
  const p = summary.perfil;
  const e = summary.estatisticas;

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>@${p.username || 'instagram'} - Feed Resumo</title>
<style>
:root{--bg:linear-gradient(135deg,#f5f7fa,#e8ecf1);--surface:rgba(255,255,255,0.9);--border:rgba(0,0,0,0.07);--text:#1a1a2e;--muted:#555;--dim:#999;--accent:#E1306C;--accent2:#833AB4;--accent3:#F77737;--grad:linear-gradient(45deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888);--shadow:0 4px 16px rgba(0,0,0,0.08)}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,sans-serif;background:var(--bg);min-height:100vh;color:var(--text)}
header{background:rgba(255,255,255,0.85);backdrop-filter:blur(12px);padding:16px 30px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:14px;box-shadow:0 1px 3px rgba(0,0,0,0.06)}
.ig-icon{width:36px;height:36px;border-radius:10px;background:var(--grad);display:flex;align-items:center;justify-content:center;font-size:1.2rem}
header h1{font-size:1.4rem;font-weight:700;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.container{max-width:1200px;margin:0 auto;padding:24px}
.profile{background:var(--surface);border-radius:16px;padding:30px;margin-bottom:24px;box-shadow:var(--shadow);display:flex;gap:24px;align-items:center;flex-wrap:wrap}
.profile img{width:96px;height:96px;border-radius:50%;border:3px solid var(--accent)}
.profile-info h2{font-size:1.3rem;margin-bottom:4px}
.profile-info .bio{color:var(--muted);font-size:0.88rem;margin-bottom:8px}
.stats{display:flex;gap:24px;flex-wrap:wrap}
.stat{text-align:center}
.stat .num{font-size:1.4rem;font-weight:700;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.stat .label{font-size:0.72rem;color:var(--dim);text-transform:uppercase;letter-spacing:0.5px}
.summary{background:var(--surface);border-radius:16px;padding:24px;margin-bottom:24px;box-shadow:var(--shadow)}
.summary h3{font-size:0.85rem;text-transform:uppercase;letter-spacing:1px;color:var(--muted);margin-bottom:16px}
.summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:16px}
.summary-card{background:rgba(225,48,108,0.04);border:1px solid rgba(225,48,108,0.1);border-radius:10px;padding:14px;text-align:center}
.summary-card .val{font-size:1.6rem;font-weight:700;color:var(--accent)}
.summary-card .lbl{font-size:0.72rem;color:var(--dim);margin-top:4px}
.feed{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}
.post{background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:hidden;transition:transform 0.2s,box-shadow 0.2s;box-shadow:0 1px 3px rgba(0,0,0,0.06)}
.post:hover{transform:translateY(-2px);box-shadow:var(--shadow)}
.post img{width:100%;aspect-ratio:1;object-fit:cover;display:block;background:#f0f0f0}
.post-placeholder{width:100%;aspect-ratio:1;background:#f0f0f0;display:flex;align-items:center;justify-content:center;color:var(--dim);font-size:2rem}
.post-body{padding:14px}
.post-meta{display:flex;justify-content:space-between;margin-bottom:8px}
.post-type{font-size:0.68rem;text-transform:uppercase;letter-spacing:0.5px;padding:2px 8px;border-radius:4px;font-weight:600}
.type-image{background:rgba(225,48,108,0.1);color:#d62862}
.type-video{background:rgba(131,58,180,0.1);color:#7b2fa8}
.type-carousel{background:rgba(247,119,55,0.1);color:#e06820}
.post-date{font-size:0.72rem;color:var(--dim)}
.post-caption{font-size:0.82rem;line-height:1.5;max-height:4.5em;overflow:hidden;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;word-break:break-word}
.post-stats{display:flex;gap:16px;margin-top:10px;padding-top:10px;border-top:1px solid rgba(0,0,0,0.05);font-size:0.78rem;color:var(--muted)}
.post-link{display:inline-block;margin-top:8px;font-size:0.75rem;color:var(--accent);text-decoration:none;font-weight:600}
.post-link:hover{text-decoration:underline}
.toolbar{position:fixed;bottom:20px;right:20px;display:flex;gap:8px;z-index:10}
.toolbar button{padding:10px 16px;border-radius:8px;border:none;cursor:pointer;font-size:0.82rem;font-weight:600;box-shadow:var(--shadow);font-family:inherit}
.btn-dl{background:var(--grad);color:#fff}
.btn-dl:hover{transform:translateY(-1px);box-shadow:0 4px 20px rgba(225,48,108,0.3)}
.btn-top{background:#fff;color:var(--text);border:1px solid var(--border)!important}
footer{text-align:center;padding:30px;color:var(--dim);font-size:0.75rem}
@media(max-width:600px){.profile{flex-direction:column;text-align:center}.stats{justify-content:center}.feed{grid-template-columns:1fr}}
</style>
</head>
<body>
<header>
<div class="ig-icon">&#128247;</div>
<h1>@${p.username || 'instagram'} - Feed Resumo</h1>
</header>
<div class="container">
<div class="profile">
${p.foto_perfil || p.url_perfil ? `<img src="${p.foto_perfil || p.url_perfil}" alt="avatar" onerror="this.style.display='none'">` : ''}
<div class="profile-info">
<h2>${p.nome || '@' + (p.username || '?')}</h2>
<div class="bio">${p.bio || 'Sem bio'}</div>
<div class="stats">
<div class="stat"><div class="num">${(p.seguidores || 0).toLocaleString()}</div><div class="label">Seguidores</div></div>
<div class="stat"><div class="num">${(p.seguindo || 0).toLocaleString()}</div><div class="label">Seguindo</div></div>
<div class="stat"><div class="num">${(p.total_posts || 0).toLocaleString()}</div><div class="label">Posts</div></div>
</div>
</div>
</div>
<div class="summary">
<h3>Estatisticas dos ultimos ${e.posts_baixados} posts</h3>
<div class="summary-grid">
<div class="summary-card"><div class="val">${e.total_likes.toLocaleString()}</div><div class="lbl">Likes totais</div></div>
<div class="summary-card"><div class="val">${e.media_likes_por_post}</div><div class="lbl">Media likes/post</div></div>
<div class="summary-card"><div class="val">${e.total_comentarios.toLocaleString()}</div><div class="lbl">Comentarios totais</div></div>
<div class="summary-card"><div class="val">${e.media_comentarios_por_post}</div><div class="lbl">Media comentarios/post</div></div>
</div>
</div>
<div class="feed">
${(summary.posts || []).map(post => {
  const tc = post.tipo === 'VIDEO' ? 'type-video' : post.tipo === 'CAROUSEL' || post.tipo === 'CAROUSEL_ALBUM' ? 'type-carousel' : 'type-image';
  const date = post.data ? new Date(post.data).toLocaleDateString('pt-BR', {day:'2-digit',month:'short',year:'numeric'}) : '';
  const thumb = post.url_thumbnail || post.url_midia;
  const thumbHtml = post.tipo === 'VIDEO'
    ? `<div class="post-placeholder">&#127916;</div>`
    : thumb
      ? `<img src="${thumb}" alt="post" loading="lazy" onerror="this.outerHTML='<div class=post-placeholder>&#128247;</div>'">`
      : `<div class="post-placeholder">&#128247;</div>`;
  return `<div class="post">
${thumbHtml}
<div class="post-body">
<div class="post-meta"><span class="post-type ${tc}">${post.tipo}</span><span class="post-date">${date}</span></div>
<div class="post-caption">${(post.legenda || 'Sem legenda').replace(/</g,'&lt;')}</div>
<div class="post-stats"><span>&#10084;&#65039; ${post.likes}</span><span>&#128172; ${post.comentarios}</span></div>
${post.permalink ? `<a class="post-link" href="${post.permalink}" target="_blank">Ver no Instagram &rarr;</a>` : ''}
</div></div>`;
}).join('\n')}
</div>
</div>
<footer>Gerado automaticamente por instagram.js</footer>
<div class="toolbar">
<button class="btn-dl" onclick="downloadJSON()">JSON</button>
<button class="btn-top" onclick="window.scrollTo({top:0,behavior:'smooth'})">Topo</button>
</div>
<script>
const DATA = ${dataJson};
function downloadJSON(){
  const b=new Blob([JSON.stringify(DATA,null,2)],{type:'application/json'});
  const a=document.createElement('a');
  a.href=URL.createObjectURL(b);
  a.download='instagram-${p.username || 'feed'}-resumo.json';
  a.click();
}
</script>
</body>
</html>`;
}

// ─── Instagram ID Resolution ─────────────────────────────────────────────────

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
  } catch (err) { logDebug('fetchViaWebProfileInfo:', err.message); }
  return null;
}

async function fetchViaHTMLParsing(username) {
  try {
    const res = await fetch(`https://www.instagram.com/${username}/`, {
      headers: DESKTOP_HEADERS,
      redirect: 'follow',
    });
    const html = await res.text();
    const patterns = [
      /"user_id"\s*:\s*"?(\d{10,})/,
      /"pk"\s*:\s*"?(\d{10,})/,
      /"id"\s*:\s*"(\d{10,})"/,
      /content="user:\/\/(\d{10,})"/,
      /"logging_page_id"\s*:\s*"profilePage_(\d+)"/,
      /"id"\s*:\s*(\d{15,17})/,
    ];
    for (const re of patterns) {
      const m = html.match(re);
      if (m && ID_PATTERN.test(m[1])) return m[1];
    }
  } catch (err) { logDebug('fetchViaHTMLParsing:', err.message); }
  return null;
}

async function fetchIgUserIdFromProfile(username) {
  const strategies = [fetchViaWebProfileInfo, fetchViaHTMLParsing];
  for (const strategy of strategies) {
    const id = await strategy(username);
    if (id) return id;
  }
  return null;
}

async function getManagedPages(token) {
  const data = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
  return (data.data || []).filter(p => p.instagram_business_account?.id);
}

async function tryPagesSearch(query, token) {
  try {
    const data = await apiGet(`pages/search?q=${encodeURIComponent(query)}&fields=id,name,instagram_business_account`, token);
    return (data.data || []).filter(p => p.instagram_business_account?.id);
  } catch { return null; }
}

async function resolveIgUserId(input, token) {
  const clean = input.replace(/^@/, '').trim();
  if (/^\d+$/.test(clean)) return clean;

  logDebug('Buscando entre paginas gerenciadas...');
  const managed = await getManagedPages(token);
  const match = managed.find(p =>
    p.name.toLowerCase().includes(clean.toLowerCase()) ||
    p.instagram_business_account.username?.toLowerCase() === clean.toLowerCase()
  );
  if (match) return match.instagram_business_account.id;

  logDebug('Tentando pages/search...');
  const searched = await tryPagesSearch(clean, token);
  if (searched && searched.length > 0) return searched[0].instagram_business_account.id;

  logDebug('Extraindo ID do Instagram...');
  const fetchedId = await fetchIgUserIdFromProfile(clean);
  if (fetchedId) return fetchedId;

  return null;
}

// ─── Comandos ────────────────────────────────────────────────────────────────

async function cmdPerfil() {
  const fromFileIdx = process.argv.indexOf('--from-file');
  if (fromFileIdx >= 0) {
    const fromFile = process.argv[fromFileIdx + 1];
    if (!fromFile) { console.error('[erro] Use: --from-file <arquivo.json>'); return; }
    console.log(`\n--- Lendo de: ${fromFile} ---\n`);
    try {
      const content = fs.readFileSync(fromFile, 'utf-8');
      const data = JSON.parse(content);
      const userData = data.data?.user || data.user || data;
      if (!userData.username) { console.error('[erro] Formato invalido: campo username nao encontrado.'); return; }
      const maxPosts = getArg('--posts') ? parseInt(getArg('--posts'), 10) || 25 : 25;
      return processUser(userData, maxPosts);
    } catch (err) {
      console.error(`[erro] ${err.message}`);
      return;
    }
  }

  const args = getPositionalArgs();
  const usernameIdx = args.indexOf('perfil') >= 0 ? args.indexOf('perfil') + 1 : 1;
  const username = args[usernameIdx] || getArg('perfil');

  if (!username) {
    console.log('Uso: node instagram.js perfil <username> [--posts N]\n');
    console.log('Exemplo: node instagram.js perfil grupoamoranimal --posts 50');
    console.log('         node instagram.js perfil --from-file instagram-waroha-browser.json');
    return;
  }

  const postsFlag = process.argv.indexOf('--posts');
  const maxPosts = postsFlag >= 0 ? parseInt(process.argv[postsFlag + 1], 10) || 25 : 25;
  const clean = username.replace(/^@/, '');

  console.log(`\n--- Buscando perfil @${clean} ---\n`);

  console.log('  Tentando API mobile...');
  const user = await scrapeProfile(clean);

  if (!user) {
    const jsonFile = 'instagram-' + clean + '-browser.json';
    console.log('  [aviso] Acesso automatico bloqueado.\n');
    console.log('  === Extraindo manualmente ===\n');
    console.log('  1. Abra no navegador: https://www.instagram.com/' + clean + '/');
    console.log('  2. Abra o Console (F12 → Console) e cole:\n');
    console.log('     fetch("/api/v1/users/web_profile_info/?username=' + clean + '", {headers:{"X-IG-App-ID":"936619743392459"}}).then(r=>r.json()).then(d=>{const u=d.data.user;const o={username:u.username,full_name:u.full_name,followed_by_viewer_count:u.edge_followed_by.count,follows_viewer_count:u.edge_follow.count,profile_pic_url_hd:u.profile_pic_url_hd,is_private:u.is_private,is_verified:u.is_verified,edge_owner_to_timeline_media:{count:u.edge_owner_to_timeline_media.count,edges:u.edge_owner_to_timeline_media.edges.map(e=>({node:{shortcode:e.node.shortcode,display_url:e.node.display_url,edge_media_to_caption:{edges:e.node.edge_media_to_caption.edges},edge_media_preview_like:{count:e.node.edge_media_preview_like.count},taken_at_timestamp:e.node.taken_at_timestamp,typename:e.node.__typename}}))}};console.log(JSON.stringify(o,null,2))})\n');
    console.log('  3. Copie TODO o resultado (select all → copy)\n');
    console.log('  4. Salve como: ' + DIR + '/' + jsonFile);
    console.log('     Exemplo no terminal:\n');
    console.log('     xclip -selection clipboard > ' + jsonFile);
    console.log('     ou cole no nano/vim:\n');
    console.log('     nano ' + jsonFile + '\n');
    console.log('  5. Rode:\n');
    console.log('     node instagram.js perfil --from-file ' + jsonFile);
    console.log('\n  --- OU cole o JSON direto no terminal ---\n');
    console.log('     node instagram.js perfil --paste ' + clean);
    return;
  }

  return processUser(user, maxPosts);
}

function processUser(user, maxPosts) {
  console.log(`  [ok] Perfil: @${user.username}`);
  console.log('  Processando posts...\n');

  const summary = buildSummary(user, maxPosts);
  const filename = `instagram-${summary.perfil.username}-resumo.json`;
  fs.writeFileSync(path.join(DIR, filename), JSON.stringify(summary, null, 2), 'utf-8');

  const htmlFilename = `instagram-${summary.perfil.username}-feed.html`;
  fs.writeFileSync(path.join(DIR, htmlFilename), generateHtml(summary), 'utf-8');

  printSummary(summary);
  console.log(`\n  JSON: ${filename}`);
  console.log(`  HTML: ${htmlFilename}`);
}

async function cmdFeed() {
  const env = loadEnv();
  let token = env.FB_ACCESS_TOKEN || '';
  if (!token) {
    console.log('[erro] Nenhum token encontrado. Execute: node instagram.js token');
    return;
  }

  const valid = await isTokenValid(token);
  if (!valid) {
    console.log('[aviso] Token pode estar expirado. Execute: node instagram.js token');
    const use = (await ask('Continuar mesmo assim? (s/N): ')).trim().toLowerCase();
    if (use !== 's' && use !== 'sim') return;
  }

  const user = getArg('--user') || getPositionalArgs()[1];
  if (!user) {
    console.log('Uso: node instagram.js feed <usuario> [--limit N]');
    return;
  }

  const limitFlag = process.argv.indexOf('--limit');
  const limit = limitFlag >= 0 ? parseInt(process.argv[limitFlag + 1], 10) || 25 : 25;

  console.log(`\n--- Buscando via Graph API ---\n`);
  console.log('  Resolvendo ID...');
  const igUserId = await resolveIgUserId(user, token);
  if (!igUserId) {
    console.log('  [erro] Nao foi possivel encontrar o ID.');
    console.log('  Use o ID numerico do Instagram ou verifique o token.');
    return;
  }
  console.log(`  ID: ${igUserId}`);

  console.log('  Buscando dados do perfil...');
  const profileData = await apiGet(`${igUserId}?fields=username,name,biography,followers_count,follows_count,media_count,profile_picture_url`, token);

  console.log(`  Buscando ${limit} posts recentes...`);
  const posts = await apiGetAllPages(`${igUserId}/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,like_count,comments_count,permalink`, token, limit);

  const summary = buildApiSummary(profileData, posts);
  const filename = `instagram-${summary.perfil.username || sanitizeFilename(user)}-resumo.json`;
  fs.writeFileSync(path.join(DIR, filename), JSON.stringify(summary, null, 2), 'utf-8');

  const htmlFilename = `instagram-${summary.perfil.username || sanitizeFilename(user)}-feed.html`;
  fs.writeFileSync(path.join(DIR, htmlFilename), generateHtml(summary), 'utf-8');

  printSummary(summary);
  console.log(`\n  JSON: ${filename}`);
  console.log(`  HTML: ${htmlFilename}`);
}

async function cmdToken() {
  const env = loadEnv();
  let appId = env.FB_APP_ID || '';
  let appSecret = env.FB_APP_SECRET || '';

  if (appId && appSecret) {
    console.log(`  App ID: ${appId}`);
    const use = (await ask('Usar credenciais salvas? (S/n): ')).trim().toLowerCase();
    if (use === 'n' || use === 'nao') { appId = ''; appSecret = ''; }
  }

  if (!appId || !appSecret) {
    console.log('\n  Crie um app em: https://developers.facebook.com/apps/\n');
    console.log('  Configuracao necessaria:');
    console.log('  1. Criar app (tipo Business)');
    console.log('  2. Adicionar: Instagram Graph API');
    console.log('  3. Ativar permissoes: instagram_basic, pages_show_list, pages_read_engagement');
    console.log('  4. Facebook Login → Settings → Redirect URI: ' + REDIRECT_URI);
    console.log('  5. Settings → Roles → adicione seu usuario como Admin\n');

    appId = (await ask('App ID: ')).trim();
    if (!appId) { console.error('App ID obrigatorio.'); return; }

    appSecret = (await ask('App Secret: ')).trim();
    if (!appSecret) { console.error('App Secret obrigatorio.'); return; }

    loadEnv()[appId] = appId;
    saveEnv({ FB_APP_ID: appId, FB_APP_SECRET: appSecret });
  }

  const scopes = REQUIRED_PERMISSIONS.join(',');
  const authUrl = `https://www.facebook.com/v18.0/dialog/oauth?client_id=${appId}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&scope=${scopes}&response_type=code`;

  console.log('\n  Abrindo navegador...');
  openBrowser(authUrl);

  console.log('  Aguardando autenticacao... (max 5 min)\n');
  let code;
  try { code = await startLocalServer(); }
  catch (err) { console.error(`  [erro] ${err.message}`); return; }

  console.log('  Gerando token...');
  let token = await exchangeCodeForToken(appId, appSecret, code);
  console.log('  [ok] Token de curto prazo obtido');

  try {
    token = await exchangeForLongLivedToken(appId, appSecret, token);
    console.log('  [ok] Token de longo prazo obtido (~60 dias)');
  } catch (err) {
    console.log(`  [aviso] Nao foi converter: ${err.message}`);
  }

  const user = await apiGet('me?fields=id,name', token);
  console.log(`  [ok] Logado como: "${user.name}" (ID: ${user.id})`);

  saveEnv({ FB_APP_ID: appId, FB_APP_SECRET: appSecret, FB_ACCESS_TOKEN: token });
  console.log('\n  [ok] Token salvo em .env');

  try {
    const pages = await getManagedPages(token);
    if (pages.length > 0) {
      console.log(`\n  ${pages.length} pagina(s) com Instagram Business:\n`);
      pages.forEach((p, i) => {
        console.log(`  [${i + 1}] ${p.name} → @${p.instagram_business_account.username || '?'} (ID: ${p.instagram_business_account.id})`);
      });
    }
  } catch {}
}

async function cmdAccounts() {
  const env = loadEnv();
  const token = env.FB_ACCESS_TOKEN || '';
  if (!token) {
    console.log('[erro] Nenhum token. Execute: node instagram.js token');
    return;
  }

  console.log('\n--- Suas paginas gerenciadas ---\n');

  try {
    const me = await apiGet('me?fields=id,name', token);
    console.log(`  Conta: ${me.name} (ID: ${me.id})\n`);
  } catch (err) {
    console.log(`  [erro] Token invalido: ${err.message}`);
    return;
  }

  try {
    const pages = await getManagedPages(token);
    if (pages.length === 0) {
      console.log('  Nenhuma pagina com Instagram Business vinculada.');
      return;
    }
    console.log(`  ${pages.length} pagina(s):\n`);
    pages.forEach((p, i) => {
      const ig = p.instagram_business_account;
      console.log(`  ${i + 1}. ${p.name}`);
      console.log(`     Page ID: ${p.id}`);
      console.log(`     IG ID: ${ig.id} | @${ig.username || '?'}\n`);
    });
  } catch (err) {
    console.log(`  [erro] ${err.message}`);
  }
}

async function cmdCleanup() {
  const dryRun = hasFlag('--dry-run');
  console.log(`\n--- Limpeza de arquivos ${dryRun ? '(simulacao)' : ''} ---\n`);

  const allFiles = fs.readdirSync(DIR);
  const stats = { removed: 0, kept: 0, protected: 0, totalSize: 0 };

  const deletablePatterns = [
    /^instagram-.*-resumo\.json$/,
    /^instagram-.*-feed\.html$/,
    /^instagram-.*-browser\.json$/,
    /^instagram-.*-discover-/,
    /-resumo\.json$/,
    /-feed\.html$/,
    /^instagram-feed-\d+\.json$/,
  ];

  console.log('  Arquivos encontrados:\n');

  for (const file of allFiles) {
    if (file === '.' || file === '..' || file === 'node_modules') continue;

    const isProtected = PROTECTED_FILES.has(file);
    const isDeletable = !isProtected && deletablePatterns.some(p => p.test(file));

    if (isDeletable) {
      const filePath = path.join(DIR, file);
      const stat = fs.statSync(filePath);
      const sizeKB = (stat.size / 1024).toFixed(1);

      if (dryRun) {
        console.log(`  [remover] ${file} (${sizeKB} KB)`);
      } else {
        try {
          fs.unlinkSync(filePath);
          console.log(`  [removido] ${file} (${sizeKB} KB)`);
        } catch (err) {
          console.log(`  [erro] ${file}: ${err.message}`);
        }
      }
      stats.removed++;
      stats.totalSize += stat.size;
    } else {
      stats.kept++;
    }
  }

  // Also check for data/ directory files that aren't needed
  const dataDir = path.join(DIR, 'data');
  if (fs.existsSync(dataDir)) {
    const dataFiles = fs.readdirSync(dataDir);
    for (const file of dataFiles) {
      if (file === 'trends.json') continue; // Keep trends.json
      const filePath = path.join(dataDir, file);
      if (dryRun) {
        console.log(`  [remover] data/${file}`);
      } else {
        try { fs.unlinkSync(filePath); console.log(`  [removido] data/${file}`); }
        catch {}
      }
      stats.removed++;
    }
  }

  const sizeMB = (stats.totalSize / (1024 * 1024)).toFixed(2);
  console.log(`\n  Resultado: ${stats.removed} arquivo(s) ${dryRun ? 'a remover' : 'removido(s)'} (${sizeMB} MB)`);
  if (dryRun) console.log('  Execute sem --dry-run para confirmar.');
}

// ─── Print Summary ───────────────────────────────────────────────────────────

function printSummary(summary) {
  const p = summary.perfil;
  const e = summary.estatisticas;
  console.log(`\n=== PERFIL ===`);
  console.log(`  Username:    @${p.username}`);
  console.log(`  Nome:        ${p.nome || 'N/A'}`);
  console.log(`  Bio:         ${p.bio || 'N/A'}`);
  console.log(`  Seguidores:  ${p.seguidores}`);
  console.log(`  Seguindo:    ${p.seguindo}`);
  console.log(`  Posts:       ${p.total_posts}`);
  console.log(`\n=== ESTATISTICAS (ultimos ${e.posts_baixados} posts) ===`);
  console.log(`  Likes:       ${e.total_likes} total | ${e.media_likes_por_post} media/post`);
  console.log(`  Comentarios: ${e.total_comentarios} total | ${e.media_comentarios_por_post} media/post`);
}

// ─── Help ────────────────────────────────────────────────────────────────────

function showHelp() {
  console.log(`
instagram.js - Ferramenta unificada do Instagram

Uso:
  node instagram.js perfil <username> [--posts N]   Busca perfil publico (sem API)
  node instagram.js feed <usuario> [--limit N]      Busca via Graph API (precisa token)
  node instagram.js token                           Configura token OAuth
  node instagram.js accounts                        Lista paginas gerenciadas
  node instagram.js cleanup [--dry-run]             Remove arquivos desnecessarios
  node instagram.js server                          Inicia servidor web com UI

Comandos detalhados:

  perfil <username>
    Busca dados de um perfil publico do Instagram.
    Usa API mobile + scraping (nao precisa de token).
    Gera JSON + HTML.
    Exemplo: node instagram.js perfil grupoamoranimal --posts 50

  feed <usuario>
    Busca dados via Instagram Graph API (precisa token configurado).
    Aceita username, @usuario ou ID numerico.
    Gera JSON + HTML.
    Exemplo: node instagram.js feed nike --limit 50

  token
    Configura o OAuth com Meta/Facebook.
    Abre navegador para autenticacao.
    Salva token de longo prazo em .env.

  accounts
    Lista paginas Facebook com Instagram Business vinculado.

  cleanup
    Remove arquivos JSON/HTML gerados em execucoes anteriores.
    Use --dry-run para ver o que seria removido sem apagar.

  server
    Inicia servidor web com interface grafica (UI).
    Porta padrao: 18925 (altere via INSTAGRAM_PORT).
    Acesse: http://localhost:18925

Arquivos protegidos (nunca sao removidos):
  *.js, *.html, *.md, *.pdf, *.py, .env, package.json, node_modules/
`);
}

// ─── Server / Web UI ────────────────────────────────────────────────────────

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function jsonResponse(res, data, status = 200) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(JSON.stringify(data));
}

function sendSSE(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

function startSSE(res) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });
}

async function handleApiPerfil(req, res) {
  const url = new URL(req.url, `http://localhost:${SERVER_PORT}`);
  const username = url.searchParams.get('username');
  const posts = parseInt(url.searchParams.get('posts') || '25', 10);

  if (!username) return jsonResponse(res, { error: 'username obrigatorio' }, 400);

  const clean = username.replace(/^@/, '');
  console.log(`  [api] Perfil @${clean} (${posts} posts)...`);

  const user = await scrapeProfile(clean);
  if (!user) return jsonResponse(res, { error: 'Perfil nao encontrado ou bloqueado', username: clean }, 404);

  const summary = buildSummary(user, posts);

  const filename = `instagram-${summary.perfil.username}-resumo.json`;
  const htmlFilename = `instagram-${summary.perfil.username}-feed.html`;
  fs.writeFileSync(path.join(DIR, filename), JSON.stringify(summary, null, 2), 'utf-8');
  fs.writeFileSync(path.join(DIR, htmlFilename), generateHtml(summary), 'utf-8');

  console.log(`  [api] OK: @${summary.perfil.username}`);
  jsonResponse(res, { ok: true, summary, files: { json: filename, html: htmlFilename } });
}

async function handleApiFeed(req, res) {
  startSSE(res);

  try {
    const url = new URL(req.url, `http://localhost:${SERVER_PORT}`);
    const token = url.searchParams.get('token');
    const user = url.searchParams.get('user');
    const limit = parseInt(url.searchParams.get('limit') || '25', 10);

    if (!token) { sendSSE(res, 'error', { message: 'token obrigatorio' }); res.end(); return; }
    if (!user) { sendSSE(res, 'error', { message: 'user obrigatorio' }); res.end(); return; }

    sendSSE(res, 'log', { message: 'Resolvendo ID...' });
    const igUserId = await resolveIgUserId(user, token);
    if (!igUserId) { sendSSE(res, 'error', { message: 'Nao foi possivel encontrar o ID para "' + user + '"' }); res.end(); return; }

    sendSSE(res, 'log', { message: `ID: ${igUserId}` });
    sendSSE(res, 'log', { message: 'Buscando dados do perfil...' });
    const profileData = await apiGet(`${igUserId}?fields=username,name,biography,followers_count,follows_count,media_count,profile_picture_url`, token);

    sendSSE(res, 'log', { message: `Buscando ${limit} posts recentes...` });
    const posts = await apiGetAllPages(`${igUserId}/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,like_count,comments_count,permalink`, token, limit);

    const summary = buildApiSummary(profileData, posts);
    const filename = `instagram-${summary.perfil.username || sanitizeFilename(user)}-resumo.json`;
    const htmlFilename = `instagram-${summary.perfil.username || sanitizeFilename(user)}-feed.html`;
    fs.writeFileSync(path.join(DIR, filename), JSON.stringify(summary, null, 2), 'utf-8');
    fs.writeFileSync(path.join(DIR, htmlFilename), generateHtml(summary), 'utf-8');

    sendSSE(res, 'log', { message: `OK: @${summary.perfil.username} (${posts.length} posts)` });
    sendSSE(res, 'done', { summary, files: { json: filename, html: htmlFilename } });
  } catch (err) {
    sendSSE(res, 'error', { message: err.message });
  } finally {
    res.end();
  }
}

async function handleApiAccounts(req, res) {
  const url = new URL(req.url, `http://localhost:${SERVER_PORT}`);
  const token = url.searchParams.get('token');
  if (!token) return jsonResponse(res, { error: 'token obrigatorio' }, 400);

  try {
    const me = await apiGet('me?fields=id,name', token);
    const pages = await getManagedPages(token);
    jsonResponse(res, {
      ok: true,
      conta: { nome: me.name, id: me.id },
      paginas: pages.map(p => ({
        nome: p.name,
        pageId: p.id,
        igId: p.instagram_business_account.id,
        igUsername: p.instagram_business_account.username || null,
      })),
    });
  } catch (err) {
    jsonResponse(res, { error: err.message }, 400);
  }
}

async function handleApiEnv(req, res) {
  const env = loadEnv();

  if (req.method === 'GET') {
    return jsonResponse(res, {
      FB_APP_ID: env.FB_APP_ID || '',
      FB_APP_SECRET: env.FB_APP_SECRET || '',
      FB_ACCESS_TOKEN: env.FB_ACCESS_TOKEN || '',
      INSTAGRAM_PORT: env.INSTAGRAM_PORT || '18925',
    });
  }

  if (req.method === 'POST') {
    let body = '';
    for await (const chunk of req) body += chunk;
    try {
      const data = JSON.parse(body);
      const updates = {};
      for (const key of ['FB_APP_ID', 'FB_APP_SECRET', 'FB_ACCESS_TOKEN', 'INSTAGRAM_PORT']) {
        if (data[key] !== undefined) updates[key] = data[key];
      }
      saveEnv(updates);
      return jsonResponse(res, { ok: true, message: 'Configuracao salva em .env' });
    } catch (err) {
      return jsonResponse(res, { error: err.message }, 400);
    }
  }

  jsonResponse(res, { error: 'Method not allowed' }, 405);
}

async function handleApiTokenStatus(req, res) {
  const env = loadEnv();
  const hasToken = !!env.FB_ACCESS_TOKEN;
  let valid = false;
  if (hasToken) valid = await isTokenValid(env.FB_ACCESS_TOKEN);

  jsonResponse(res, {
    hasAppId: !!env.FB_APP_ID,
    hasAppSecret: !!env.FB_APP_SECRET,
    hasToken,
    tokenValid: valid,
    appId: env.FB_APP_ID || null,
  });
}

async function handleApiCleanup(req, res) {
  const url = new URL(req.url, `http://localhost:${SERVER_PORT}`);
  const dryRun = url.searchParams.get('dry-run') === 'true';

  const allFiles = fs.readdirSync(DIR);
  const removed = [];

  const deletablePatterns = [
    /^instagram-.*-resumo\.json$/,
    /^instagram-.*-feed\.html$/,
    /^instagram-.*-browser\.json$/,
    /^instagram-.*-discover-/,
  ];

  for (const file of allFiles) {
    if (PROTECTED_FILES.has(file)) continue;
    const isDeletable = deletablePatterns.some(p => p.test(file));
    if (isDeletable) {
      const filePath = path.join(DIR, file);
      const stat = fs.statSync(filePath);
      if (!dryRun) {
        try { fs.unlinkSync(filePath); } catch {}
      }
      removed.push({ file, size: stat.size });
    }
  }

  jsonResponse(res, { ok: true, removed, dryRun });
}

function startServer() {
  const PORT = parseInt(process.env.INSTAGRAM_PORT || '18925', 10);

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const pathname = url.pathname;

    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      });
      return res.end();
    }

    if (pathname === '/api/perfil') return handleApiPerfil(req, res);
    if (pathname === '/api/feed') return handleApiFeed(req, res);
    if (pathname === '/api/accounts') return handleApiAccounts(req, res);
    if (pathname === '/api/token-status') return handleApiTokenStatus(req, res);
    if (pathname === '/api/cleanup') return handleApiCleanup(req, res);
    if (pathname === '/api/env') return handleApiEnv(req, res);

    let filePath = pathname === '/' ? '/instagram-ui.html' : pathname;
    const fullPath = path.join(DIR, filePath);

    if (!fs.existsSync(fullPath) || fs.statSync(fullPath).isDirectory()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      return res.end('Not found');
    }

    const ext = path.extname(fullPath);
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    fs.createReadStream(fullPath).pipe(res);
  });

  server.listen(PORT, () => {
    console.log(`\n  Instagram Tool - Web UI`);
    console.log(`  http://localhost:${PORT}\n`);
    console.log('  Pressione Ctrl+C para parar.\n');
  });
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  if (hasFlag('--help') || hasFlag('-h')) { showHelp(); return; }

  const command = getPositionalArgs()[0];

  switch (command) {
    case 'perfil':
      await cmdPerfil();
      break;
    case 'feed':
      await cmdFeed();
      break;
    case 'token':
      await cmdToken();
      break;
    case 'accounts':
      await cmdAccounts();
      break;
    case 'cleanup':
      await cmdCleanup();
      break;
    case 'server':
      startServer();
      return;
    default:
      console.log('\n  Instagram Tool - Ferramenta unificada\n');
      console.log('  Comandos:');
      console.log('    perfil <username>   Busca perfil publico (sem API)');
      console.log('    feed <usuario>     Busca via Graph API');
      console.log('    token              Configura token OAuth');
      console.log('    accounts           Lista paginas gerenciadas');
      console.log('    cleanup            Remove arquivos desnecessarios');
      console.log('    server             Inicia servidor web com UI');
      console.log('\n  Execute com --help para mais detalhes.\n');
      break;
  }

  rl.close();
}

main().catch(err => {
  console.error(`\nErro: ${err.message}`);
  if (DEBUG) console.error(err.stack);
  process.exit(1);
});

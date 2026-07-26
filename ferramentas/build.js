#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const API_BASE = 'https://graph.facebook.com/v18.0';
const ENV_FILE = path.join(__dirname, '.env');
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
rl.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });
const ask = q => new Promise(resolve => rl.question(q, resolve));

function loadEnv() {
  const vars = {};
  if (fs.existsSync(ENV_FILE)) {
    fs.readFileSync(ENV_FILE, 'utf-8').split('\n').forEach(line => {
      const m = line.match(/^([A-Z_]+)=(.+)$/);
      if (m) vars[m[1]] = m[2].trim();
    });
  }
  return vars;
}

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const url = `${API_BASE}/${endpoint}${sep}access_token=${token}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data;
}

async function fetchIgUserId(username) {
  try {
    const res = await fetch(`https://www.instagram.com/${username}/`, {
      headers: { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' }
    });
    const html = await res.text();
    for (const re of [/profilePage_(\d+)/, /"profile_id"\s*:\s*(\d+)/, /"user_id"\s*:\s*(\d+)/, /content="user:\/\/(\d+)"/, /"id"\s*:\s*"(\d{10,})"/]) {
      const m = html.match(re);
      if (m) return m[1];
    }
  } catch (_) {}
  return null;
}

async function resolveUserId(input, token) {
  const clean = input.replace(/^@/, '').trim();
  if (/^\d+$/.test(clean)) return clean;

  console.log('  Buscando entre paginas gerenciadas...');
  try {
    const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    const pages = (pagesData.data || []).filter(p => p.instagram_business_account && p.instagram_business_account.id);
    const match = pages.find(p => p.name.toLowerCase().includes(clean.toLowerCase()));
    if (match) { console.log(`  Encontrado: ${match.name}`); return match.instagram_business_account.id; }
  } catch (_) {}

  console.log('  Tentando pages/search...');
  try {
    const sd = await apiGet(`pages/search?q=${encodeURIComponent(clean)}&fields=id,name,instagram_business_account`, token);
    const sp = (sd.data || []).filter(p => p.instagram_business_account && p.instagram_business_account.id);
    if (sp.length > 0) { console.log(`  Encontrado: ${sp[0].name}`); return sp[0].instagram_business_account.id; }
  } catch (e) { console.log(`  pages/search: ${e.message}`); }

  console.log('  Extraindo ID do Instagram...');
  const id = await fetchIgUserId(clean);
  if (id) { console.log(`  ID encontrado: ${id}`); return id; }

  console.log('  Nao foi possivel encontrar automaticamente.');
  const manual = (await ask('  Instagram User ID: ')).trim();
  if (!manual || !/^\d+$/.test(manual)) throw new Error('ID invalido.');
  return manual;
}

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
${p.foto_perfil ? `<img src="${p.foto_perfil}" alt="avatar" onerror="this.style.display='none'">` : ''}
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
${summary.posts.map(post => {
  const tc = post.tipo === 'VIDEO' ? 'type-video' : post.tipo === 'CAROUSEL' ? 'type-carousel' : 'type-image';
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
<footer>Gerado automaticamente por instagram-feed-build</footer>
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

async function main() {
  console.log('=== Instagram Feed Builder ===\n');

  const env = loadEnv();
  let token = env.FB_ACCESS_TOKEN || '';

  if (token) {
    console.log('  Access Token salvo encontrado em .env');
    const use = (await ask('  Usar token salvo? (S/n): ')).trim().toLowerCase();
    if (use === 'n') token = (await ask('  Cole seu Access Token: ')).trim();
  } else {
    token = (await ask('  Access Token: ')).trim();
  }
  if (!token) { console.error('Token vazio.'); process.exit(1); }

  const query = (await ask('  Buscar perfil: ')).trim();
  if (!query) { console.error('Perfil vazio.'); process.exit(1); }

  const limitStr = (await ask('  Quantidade de posts (padrao 25): ')).trim();
  const limit = parseInt(limitStr, 10) || 25;

  console.log('\n--- Iniciando ---\n');

  const userId = await resolveUserId(query, token);
  console.log(`\n  Buscando dados do perfil (${userId})...`);
  const profileData = await apiGet(`${userId}?fields=username,name,biography,followers_count,follows_count,media_count,profile_picture_url`, token);

  console.log(`  Buscando ${limit} posts recentes...`);
  const postsData = await apiGet(`${userId}/media?fields=id,caption,media_type,media_url,thumbnail_url,timestamp,like_count,comments_count,permalink&limit=${limit}`, token);

  const posts = postsData.data || [];
  let totalLikes = 0, totalComments = 0;
  posts.forEach(p => { totalLikes += (p.like_count || 0); totalComments += (p.comments_count || 0); });

  const summary = {
    perfil: {
      username: profileData.username || null,
      nome: profileData.name || null,
      bio: profileData.biography || null,
      seguidores: profileData.followers_count || null,
      seguindo: profileData.follows_count || null,
      total_posts: profileData.media_count || null,
      foto_perfil: profileData.profile_picture_url || null,
      id_ig_business: userId,
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
      likes: p.like_count || 0,
      comentarios: p.comments_count || 0,
      url_midia: p.media_url || null,
      url_thumbnail: p.thumbnail_url || null,
      permalink: p.permalink || null,
    })),
  };

  console.log(`\n  Perfil: @${summary.perfil.username}`);
  console.log(`  Seguidores: ${summary.perfil.seguidores}`);
  console.log(`  Posts: ${posts.length}`);
  console.log(`  Likes: ${totalLikes} | Comentarios: ${totalComments}`);

  const html = generateHtml(summary);
  const filename = `instagram-${summary.perfil.username || query.replace(/[^a-zA-Z0-9]/g, '_')}-feed.html`;
  const outPath = path.join(__dirname, filename);
  fs.writeFileSync(outPath, html, 'utf-8');

  const jsonFile = `instagram-${summary.perfil.username || query.replace(/[^a-zA-Z0-9]/g, '_')}-resumo.json`;
  fs.writeFileSync(path.join(__dirname, jsonFile), JSON.stringify(summary, null, 2), 'utf-8');

  console.log(`\n  [ok] HTML gerado: ${filename}`);
  console.log(`  [ok] JSON gerado: ${jsonFile}`);

  try {
    execSync(`xdg-open "${outPath}" 2>/dev/null`);
    console.log('  Abrindo no navegador...');
  } catch (_) {
    console.log(`  Abra manualmente: file://${outPath}`);
  }

  rl.close();
}

main().catch(err => { console.error(`\nErro: ${err.message}`); process.exit(1); });

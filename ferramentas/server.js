#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 18924;
const API_BASE = 'https://graph.facebook.com/v18.0';
const DIR = __dirname;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
};

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
}

function sendSSE(res, event, data) {
  res.write('event: ' + event + '\ndata: ' + JSON.stringify(data) + '\n\n');
}

function sendLog(res, msg) {
  const ts = new Date().toLocaleTimeString('pt-BR');
  sendSSE(res, 'log', { message: '[' + ts + '] ' + msg });
}

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const url = API_BASE + '/' + endpoint + sep + 'access_token=' + token;
  const r = await fetch(url);
  const d = await r.json();
  if (d.error) throw new Error(d.error.message);
  return d;
}

async function handleFeed(res, params) {
  cors(res);
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  const token = params.get('token');
  const query = params.get('user') || '';
  const limit = parseInt(params.get('limit') || '12', 10);
  const fields = params.get('fields') || 'id,caption,media_type,media_url,thumbnail_url,timestamp,like_count,comments_count,permalink';

  if (!token) { sendSSE(res, 'error', { message: 'Token obrigatorio' }); res.end(); return; }

  try {
    sendLog(res, '--- Iniciando busca de feed ---');

    let userId = params.get('userId') || '';

    if (userId && /^\d+$/.test(userId)) {
      sendLog(res, 'Usando ID informado: ' + userId);
    } else if (query && /^\d+$/.test(query)) {
      userId = query;
      sendLog(res, 'Usando ID numerico: ' + userId);
    } else if (query) {
      const clean = query.replace(/^@/, '').trim();
      sendLog(res, 'Buscando Instagram ID para "' + clean + '"...');

      sendLog(res, 'Buscando entre paginas gerenciadas...');
      const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
      const pages = (pagesData.data || []).filter(p => p.instagram_business_account && p.instagram_business_account.id);

      const match = pages.find(p =>
        p.name.toLowerCase().includes(clean.toLowerCase()) ||
        (p.instagram_business_account.username && p.instagram_business_account.username.toLowerCase() === clean.toLowerCase())
      );

      if (match) {
        userId = match.instagram_business_account.id;
        sendLog(res, 'Encontrado: ' + match.name + ' (IG ID: ' + userId + ')');
      } else {
        sendLog(res, 'Nao encontrado em paginas gerenciadas. Tentando pages/search...');
        try {
          const searchUrl = 'pages/search?q=' + encodeURIComponent(clean) + '&fields=id,name,instagram_business_account';
          const searchData = await apiGet(searchUrl, token);
          const searchPages = (searchData.data || []).filter(p => p.instagram_business_account && p.instagram_business_account.id);
          if (searchPages.length > 0) {
            userId = searchPages[0].instagram_business_account.id;
            sendLog(res, 'Encontrado via search: ' + searchPages[0].name + ' (IG ID: ' + userId + ')');
          }
        } catch (e) {
          sendLog(res, 'pages/search indisponivel: ' + e.message);
        }

        if (!userId) {
          sendLog(res, 'Tentando extrair ID do perfil no Instagram...');
          const fetchedId = await fetchIgUserId(clean);
          if (fetchedId) {
            userId = fetchedId;
            sendLog(res, 'ID extraido do Instagram: ' + userId);
          }
        }

        if (!userId) {
          sendSSE(res, 'error', { message: 'Nao foi possivel encontrar o Instagram ID para "' + query + '". Forneça o ID numericamente.' });
          res.end();
          return;
        }
      }
    } else {
      sendLog(res, 'Detectando User ID via paginas...');
      const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
      const pages = pagesData.data || [];
      const withIG = pages.find(p => p.instagram_business_account && p.instagram_business_account.id);
      if (!withIG) {
        sendSSE(res, 'error', { message: 'Nenhuma conta Instagram Business vinculada encontrada.' });
        res.end();
        return;
      }
      userId = withIG.instagram_business_account.id;
      sendLog(res, 'ID detectado: ' + userId + ' (via ' + withIG.name + ')');
    }

    sendLog(res, 'Buscando dados do perfil...');
    const profileData = await apiGet(userId + '?fields=username,name,biography,followers_count,follows_count,media_count,profile_picture_url', token);
    sendLog(res, 'Perfil: @' + (profileData.username || '?') + ' | ' + (profileData.followers_count || 0) + ' seguidores | ' + (profileData.media_count || 0) + ' posts');

    sendLog(res, 'Buscando ' + limit + ' posts recentes...');
    const postsData = await apiGet(userId + '/media?fields=' + fields + '&limit=' + limit, token);
    const posts = postsData.data || [];

    let totalLikes = 0, totalComments = 0;
    posts.forEach(p => { totalLikes += (p.like_count || 0); totalComments += (p.comments_count || 0); });

    sendLog(res, 'Posts baixados: ' + posts.length);
    sendLog(res, 'Likes total: ' + totalLikes + ' | Comentarios total: ' + totalComments);

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

    sendLog(res, '--- Feed completo! ---');
    sendSSE(res, 'done', summary);

  } catch (err) {
    sendSSE(res, 'error', { message: err.message });
  } finally {
    res.end();
  }
}

async function handleSearch(res, params) {
  cors(res);
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  const token = params.get('token');
  const query = params.get('q') || '';

  if (!token) { sendSSE(res, 'error', { message: 'Token obrigatorio' }); res.end(); return; }

  try {
    sendLog(res, 'Buscando paginas para "' + query + '"...');

    let results = [];

    const pagesData = await apiGet('me/accounts?fields=id,name,instagram_business_account', token);
    const pages = (pagesData.data || []).filter(p => p.instagram_business_account && p.instagram_business_account.id);
    const managedMatch = pages.filter(p =>
      p.name.toLowerCase().includes(query.toLowerCase()) ||
      (p.instagram_business_account.username && p.instagram_business_account.username.toLowerCase().includes(query.toLowerCase()))
    );

    if (managedMatch.length > 0) {
      sendLog(res, managedMatch.length + ' resultado(s) em paginas gerenciadas');
      results = managedMatch.map(p => ({
        id: p.instagram_business_account.id,
        name: p.name,
        pageId: p.id,
        source: 'managed',
      }));
    }

    if (results.length === 0) {
      sendLog(res, 'Tentando pages/search...');
      try {
        const searchUrl = 'pages/search?q=' + encodeURIComponent(query) + '&fields=id,name,instagram_business_account';
        const searchData = await apiGet(searchUrl, token);
        const searchPages = (searchData.data || []).filter(p => p.instagram_business_account && p.instagram_business_account.id);
        if (searchPages.length > 0) {
          sendLog(res, searchPages.length + ' resultado(s) via pages/search');
          results = searchPages.map(p => ({
            id: p.instagram_business_account.id,
            name: p.name,
            pageId: p.id,
            source: 'search',
          }));
        }
      } catch (e) {
        sendLog(res, 'pages/search: ' + e.message);
      }
    }

    if (results.length === 0) {
      sendLog(res, 'Tentando extrair ID do Instagram...');
      const fetchedId = await fetchIgUserId(query.replace(/^@/, '').trim());
      if (fetchedId) {
        sendLog(res, 'ID encontrado: ' + fetchedId);
        results = [{ id: fetchedId, name: query, pageId: null, source: 'instagram' }];
      }
    }

    sendLog(res, results.length + ' resultado(s) encontrado(s)');
    sendSSE(res, 'done', { results });

  } catch (err) {
    sendSSE(res, 'error', { message: err.message });
  } finally {
    res.end();
  }
}

async function fetchIgUserId(username) {
  try {
    const res = await fetch('https://www.instagram.com/' + username + '/', {
      headers: { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' }
    });
    const html = await res.text();
    const patterns = [
      /profilePage_(\d+)/,
      /"profile_id"\s*:\s*(\d+)/,
      /"user_id"\s*:\s*(\d+)/,
      /content="user:\/\/(\d+)"/,
      /"id"\s*:\s*"(\d{10,})"/,
    ];
    for (const re of patterns) {
      const m = html.match(re);
      if (m) return m[1];
    }
  } catch (_) {}
  return null;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost:' + PORT);
  const pathname = url.pathname;

  if (pathname === '/api/feed') {
    return handleFeed(res, url.searchParams);
  }

  if (pathname === '/api/search') {
    return handleSearch(res, url.searchParams);
  }

  let filePath = path.join(DIR, pathname === '/' ? 'instagram-feed.html' : pathname);
  const ext = path.extname(filePath);

  if (!fs.existsSync(filePath)) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    return res.end('Not found');
  }

  res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
  fs.createReadStream(filePath).pipe(res);
});

server.listen(PORT, () => {
  console.log('Instagram Feed Server rodando em http://localhost:' + PORT);
  console.log('Abra o navegador e acesse a URL acima.');
});

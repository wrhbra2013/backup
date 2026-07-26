#!/usr/bin/env node
/**
 * Busca dados de um perfil publico do Instagram (sem API key).
 * Uso: node instagram-perfil.js <username> [--posts N] [--from-file JSON_FILE]
 * Exemplo: node instagram-perfil.js grupoamoranimal --posts 50
 * Exemplo: node instagram-perfil.js --from-file dados.json
 */
const fs = require('fs');
const readline = require('readline');
const path = require('path');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
rl.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });
const ask = q => new Promise(resolve => rl.question(q, resolve));

const usernameArg = process.argv.find((a, i) => !a.startsWith('--') && i > 1);
const username = usernameArg || null;
const postsFlag = process.argv.indexOf('--posts');
const maxPosts = postsFlag >= 0 ? parseInt(process.argv[postsFlag + 1], 10) || 25 : 25;
const fromFileIdx = process.argv.indexOf('--from-file');
const fromFile = fromFileIdx >= 0 ? process.argv[fromFileIdx + 1] : null;

if (!username && !fromFile) {
  console.log('Uso: node instagram-perfil.js <username> [--posts N]');
  console.log('     node instagram-perfil.js --from-file dados.json\n');
  console.log('Exemplo: node instagram-perfil.js grupoamoranimal --posts 50');
  process.exit(1);
}

const cleanUsername = username ? username.replace(/^@/, '') : null;

const MOBILE_HEADERS = {
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

async function tryFetch(url, headers) {
  try {
    const res = await fetch(url, { headers, redirect: 'follow' });
    if (!res.ok) return null;
    const text = await res.text();
    try { return JSON.parse(text); } catch { return text; }
  } catch { return null; }
}

async function fetchProfile() {
  console.log(`--- Buscando perfil @${cleanUsername} ---\n`);

  console.log('  Tentativa 1: API mobile...');
  let data = await tryFetch(
    `https://i.instagram.com/api/v1/users/web_profile_info/?username=${cleanUsername}`,
    MOBILE_HEADERS
  );
  if (data?.data?.user) {
    console.log('  [ok] Sucesso via API mobile\n');
    return data.data.user;
  }

  console.log('  Tentativa 2: Pagina web...');
  const htmlRes = await tryFetch(
    `https://www.instagram.com/${cleanUsername}/`,
    DESKTOP_HEADERS
  );
  if (typeof htmlRes === 'string') {
    const html = htmlRes;
    const idMatch = html.match(/"user_id"\s*:\s*"?(\d{10,})/);
    if (idMatch) {
      console.log('  [info] Encontrou ID, tentando full_detail...');
      const apiRes = await tryFetch(
        `https://i.instagram.com/api/v1/users/${idMatch[1]}/full_detail/`,
        MOBILE_HEADERS
      );
      if (apiRes?.user) {
        console.log('  [ok] Sucesso via full_detail\n');
        return apiRes.user;
      }
    }
    if (html.includes('/accounts/login')) {
      console.log('  [aviso] Instagram exige login.\n');
    }
  }

  return null;
}

function buildSummary(user) {
  const profile = user.profile_pic_url_hd || user.profile_pic_url || null;
  const isBusiness = user.is_business ?? user.is_business_account ?? null;
  const category = user.business_category_name || user.category_name || null;

  const edgePosts = user.edge_owner_to_timeline_media || user.edge_felix_timeline || { edges: [] };
  const posts = (edgePosts.edges || []).slice(0, maxPosts).map(e => {
    const node = e.node || e;
    const isVideo = node.is_video || false;
    return {
      id: node.id || null,
      shortcode: node.shortcode || null,
      data: node.taken_at_timestamp ? new Date(node.taken_at_timestamp * 1000).toISOString() : null,
      legenda: node.edge_media_to_caption?.edges?.[0]?.node?.text || null,
      tipo: isVideo ? 'VIDEO' : (node.__typename || 'IMAGE'),
      likes: node.edge_liked_by?.count ?? node.edge_media_preview_like?.count ?? 0,
      comentarios: node.edge_media_to_comment?.count ?? 0,
      views: node.video_view_count || null,
      url: node.shortcode ? `https://www.instagram.com/p/${node.shortcode}/` : null,
      thumbnail: node.thumbnail_src || node.display_url || null,
      hashtags: (node.edge_media_to_caption?.edges?.[0]?.node?.text?.match(/#[\w\u00C0-\u024F]+/g) || []),
      mencoes: (node.edge_media_to_caption?.edges?.[0]?.node?.text?.match(/@[\w.]+/g) || []),
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
      username: user.username || cleanUsername,
      nome: user.full_name || null,
      bio: user.biography || null,
      seguidores: user.edge_followed_by?.count ?? user.follower_count ?? null,
      seguindo: user.edge_follow?.count ?? user.following_count ?? null,
      total_posts: user.edge_owner_to_timeline_media?.count ?? user.media_count ?? null,
      eh_business: isBusiness,
      categoria: category,
      url_perfil: profile,
      url: `https://www.instagram.com/${user.username || cleanUsername}/`,
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

function printSummary(summary) {
  console.log(`=== RESUMO ===`);
  console.log(`  Username:     @${summary.perfil.username}`);
  console.log(`  Nome:         ${summary.perfil.nome || 'N/A'}`);
  console.log(`  Bio:          ${summary.perfil.bio || 'N/A'}`);
  console.log(`  Seguidores:   ${summary.perfil.seguidores}`);
  console.log(`  Seguindo:     ${summary.perfil.seguindo}`);
  console.log(`  Posts:        ${summary.perfil.total_posts}`);
  console.log(`  Business:     ${summary.perfil.eh_business}`);
  console.log(`  Verificado:   ${summary.perfil.verificado}`);
  console.log(`\n  === ESTATISTICAS (ultimos ${summary.estatisticas.posts_baixados} posts) ===`);
  console.log(`  Likes:        ${summary.estatisticas.total_likes} total | ${summary.estatisticas.media_likes_por_post} media/post`);
  console.log(`  Comentarios:  ${summary.estatisticas.total_comentarios} total | ${summary.estatisticas.media_comentarios_por_post} media/post`);
  if (summary.hashtags_mais_usadas.length > 0) {
    console.log(`  Top hashtags: ${summary.hashtags_mais_usadas.slice(0, 10).map(h => h.tag).join(', ')}`);
  }
}

async function main() {
  let user;

  if (fromFile) {
    console.log(`--- Lendo dados de ${fromFile} ---\n`);
    const content = fs.readFileSync(fromFile, 'utf-8');
    const data = JSON.parse(content);
    user = data.data?.user || data.user || data.graphql?.user || data;
    if (!user.username && !user.edge_owner_to_timeline_media) {
      console.log('[erro] Formato nao reconhecido no arquivo.');
      process.exit(1);
    }
  } else {
    user = await fetchProfile();
  }

  if (!user) {
    console.log('--- EXTRAÇÃO MANUAL ---\n');
    console.log('O Instagram bloqueou o acesso automatico.\n');
    console.log('  1. Abra no navegador:');
    console.log(`     https://www.instagram.com/${cleanUsername}/\n`);
    console.log('  2. Pressione F12 → aba "Console"');
    console.log('  3. Cole este codigo e pressione Enter:\n');

    const code = `fetch("/api/v1/users/web_profile_info/?username=${cleanUsername}",{headers:{"X-IG-App-ID":"936619743392459"}}).then(r=>r.json()).then(d=>{window._igData=d.data.user;console.log(JSON.stringify(d.data.user,null,2))})`;
    console.log(`     ${code}\n`);
    console.log('  4. Copie todo o JSON impresso (clique direito → Copy object)');
    console.log('  5. Cole aqui quando pedido\n');

    const savedFile = `instagram-${cleanUsername}-browser.json`;
    console.log(`  Alternativa: salve o JSON em ${savedFile} e use:`);
    console.log(`  node instagram-perfil.js --from-file ${savedFile}\n`);

    let pasted = '';
    try { pasted = (await ask('Cole o JSON do navegador (vazio para abortar): ')).trim(); } catch { }
    if (!pasted) {
      console.log('\nAbortado.');
      process.exit(0);
    }

    try {
      user = JSON.parse(pasted);
      user = user.data?.user || user.user || user.graphql?.user || user;
    } catch {
      console.log('[erro] JSON invalido.');
      process.exit(1);
    }

    fs.writeFileSync(savedFile, JSON.stringify(user, null, 2), 'utf-8');
    console.log(`  [ok] Dados salvos em ${savedFile}\n`);
  }

  console.log(`  [ok] Perfil: @${user.username || cleanUsername}`);
  console.log(`  Buscando posts...\n`);

  const summary = buildSummary(user);
  const filename = `instagram-${summary.perfil.username}-resumo.json`;
  fs.writeFileSync(filename, JSON.stringify(summary, null, 2), 'utf-8');

  printSummary(summary);
  console.log(`\n  Salvo em: ${filename}`);
  rl.close();
}

main();

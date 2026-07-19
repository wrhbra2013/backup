#!/usr/bin/env node
const fs = require('fs');
const readline = require('readline');

const API_BASE = 'https://graph.facebook.com/v18.0';

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
rl.on('SIGINT', () => { console.log('\nCancelado.'); process.exit(0); });
const ask = q => new Promise(resolve => rl.question(q, resolve));

async function apiGet(endpoint, token) {
  const sep = endpoint.includes('?') ? '&' : '?';
  const url = `${API_BASE}/${endpoint}${sep}access_token=${token}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data;
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
  O script vai pedir: token, perfil (nome, @username ou ID) e quantidade de posts.

Uso direto: node instagram-feed.js --token TOKEN --user "NOME OU ID" [--limit NUM]
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
    token = (await ask('Access Token (cole seu token do Graph API): ')).trim();
    if (!token) { console.error('Token vazio. Abortando.'); process.exit(1); }

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

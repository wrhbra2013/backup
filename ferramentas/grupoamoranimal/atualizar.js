#!/usr/bin/env node
/**
 * atualizar.js — Atualiza automaticamente os dados de postagens do @grupoamoranimal
 *
 * Pipeline:
 *   1. Coleta todas as postagens publicas do perfil (via imginn.com)
 *   2. Classifica cada postagem em: adocao | castracao | procura-se | doacao | outros
 *   3. Regrava instagram-grupoamoranimal-dataset.json
 *   4. Regenera instagram-grupoamoranimal-abas.html (pagina com abas)
 *
 * Uso:
 *   node atualizar.js                 Atualiza tudo (coleta do zero)
 *   node atualizar.js --save-only     Nao coleta; apenas regenera JSON/HTML com os dados ja salvos
 *   node atualizar.js --max-pages N   Limite de paginas coletadas (padrao: 250)
 *   node atualizar.js --delay MS      Pausa entre paginas em ms (padrao: 450)
 *
 * Requisitos: Node.js 18+ (fetch nativo).
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const USERNAME = 'grupoamoranimal';
const FILE_JSON = path.join(DIR, 'instagram-grupoamoranimal-dataset.json');
const FILE_HTML = path.join(DIR, 'instagram-grupoamoranimal-abas.html');
const FILE_TPL = path.join(DIR, 'template-abas.html');

const UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';
const REFERER = 'https://imginn.com/' + USERNAME + '/';
const API_HEADERS = { 'User-Agent': UA, Accept: 'application/json', Referer: REFERER };
const PAGE_HEADERS = { 'User-Agent': UA, 'Accept-Language': 'pt-BR,pt;q=0.9' };

let MAX_PAGES = 250;
let DELAY_MS = 450;
let SAVE_ONLY = process.argv.includes('--save-only');

for (let i = 0; i < process.argv.length; i++) {
  if (process.argv[i] === '--max-pages') MAX_PAGES = parseInt(process.argv[i + 1], 10) || MAX_PAGES;
  if (process.argv[i] === '--delay') DELAY_MS = parseInt(process.argv[i + 1], 10) || DELAY_MS;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log('[atualizar]', ...a);

// ─── Classificacao ───────────────────────────────────────────────────────────

const norm = (s = '') => (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const tem = (c, ...p) => p.some((w) => c.includes(w));

function classificar(cap) {
  const c = norm(cap);
  if (!c) return { categoria: 'outros', tags: [] };
  const tags = [];

  const ehProcuraSe =
    (tem(c, 'procura-se') && !tem(c, 'lar')) ||
    tem(c, 'desaparec') ||
    tem(c, 'sumiu') ||
    tem(c, 'desapareceu') ||
    (tem(c, 'encontrad') && tem(c, 'dono')) ||
    tem(c, 'nao vimos') ||
    tem(c, 'nao achamos');

  const ehCastracao =
    tem(c, 'castra') &&
    tem(c, 'mutirao', 'gratuit', 'castrar', 'castramovel', 'controle populacional', 'cirurgia',
      'projeto de castracao', 'edital', 'castrar e', '1.o mutirao', '2.o mutirao', '3.o mutirao',
      'realizamos', 'realizou', 'realizado', 'veterinaria', 'clinica veterinaria',
      'emenda parlamentar', 'recursos para castracao');

  const ehAdocao = tem(c, 'adocao', 'adot', 'feirinha de adocao', 'feira de adocao',
    'doacao responsavel', 'procura de um lar', 'novo lar', 'lar cheio de amor', 'lar amoroso',
    'em busca de um lar', 'busca de um lar', 'para adocao', 'adote', 'adotantes', 'lares temporarios');

  const ehDoacao = tem(c, 'pix', 'doe', 'doacao de racao', 'arrecadacao', 'vaquinha', 'rifa',
    'apadrinhe', 'apadrinhar', 'contribuicao', 'doador', 'nota fiscal', 'precisamos de',
    'doacoes de', 'cobertores', 'racao') && !ehAdocao;

  if (ehProcuraSe) tags.push('procura-se');
  if (ehCastracao) tags.push('castracao');
  if (ehAdocao) tags.push('adocao');
  if (ehDoacao) tags.push('doacao');

  let categoria;
  if (ehProcuraSe) categoria = 'procura-se';
  else if (ehCastracao) categoria = 'castracao';
  else if (ehAdocao) categoria = 'adocao';
  else if (ehDoacao) categoria = 'doacao';
  else categoria = 'outros';
  return { categoria, tags };
}

function titulo(cap) {
  const linhas = (cap || '').split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
  let t = '';
  for (const l of linhas) {
    const limpa = l.replace(/#[\w\u00C0-\u024F]+/g, ' ').replace(/@[\w.]+/g, ' ').replace(/\s+/g, ' ').trim();
    const semEmoji = limpa.replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2B50}\u{2764}\u{2705}\u{274C}\u{2728}\u{2714}\u{27A1}\u{2197}\u{2B05}\u{27A4}\u{1F000}-\u{1F9FF}\u{231B}\u{23F0}\u{1F4F1}]/gu, ' ').replace(/\s+/g, ' ').trim();
    if (semEmoji.length > 5) { t = semEmoji; break; }
  }
  if (!t) t = (cap || '').replace(/#[\w\u00C0-\u024F]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (t.length > 90) t = t.slice(0, 90).trimEnd() + '…';
  return t || 'Postagem sem título';
}

// ─── Coleta via imginn ───────────────────────────────────────────────────────

async function getProfilePage() {
  const res = await fetch('https://imginn.com/' + USERNAME + '/', { headers: PAGE_HEADERS });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' ao abrir a pagina do perfil');
  return await res.text();
}

function parseProfile(html) {
  const m = html.match(/class="load-more"[^>]*data-cursor="([^"]+)"[^>]*data-id="(\d+)"[^>]*data-username="([^"]+)"[^>]*data-verified="([^"]+)"/);
  if (!m) throw new Error('Nao encontrou o cursor inicial (imginn bloqueou?)');
  const postsM = html.match(/([\d.,]+)\s*posts/i);
  return {
    id: m[2],
    cursor: m[1],
    username: m[3],
    verified: m[4],
    totalPosts: postsM ? parseInt(postsM[1].replace(/\./g, '').replace(',', '.'), 10) : null,
  };
}

async function fetchPage(prof, cursor) {
  const url = 'https://imginn.com/api/posts/?id=' + prof.id + '&cursor=' + encodeURIComponent(cursor) +
    '&username=' + prof.username + '&verified=' + prof.verified + '&hl=';
  const res = await fetch(url, { headers: API_HEADERS });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return await res.json();
}

async function collect(prof) {
  const all = [];
  let cursor = prof.cursor;
  let pages = 0;
  let falhas = 0;
  let completo = false;
  log('Coletando postagens de @' + USERNAME + ' (id ' + prof.id + ')...');

  while (cursor && pages < MAX_PAGES) {
    try {
      const d = await fetchPage(prof, cursor);
      if (d.items && d.items.length) {
        all.push(...d.items);
        pages++;
        falhas = 0;
        cursor = d.cursor && d.hasNext ? d.cursor : null;
        if (pages % 10 === 0) log(all.length + ' posts (' + pages + ' paginas)...');
        await sleep(DELAY_MS);
        continue;
      }
      cursor = null;
    } catch (e) {
      log('erro na pagina ' + pages + ': ' + e.message);
      falhas++;
      const base = e.message.includes('429') ? 15000 : 2000;
      const espera = Math.min(60000, base * Math.pow(2, falhas - 1)) + Math.floor(Math.random() * 1000);
      log('  -> esperando ' + Math.round(espera / 1000) + 's antes de tentar de novo (' + falhas + 'a falha)');
      await sleep(espera);
      if (falhas >= 5) { log('desistindo apos 5 falhas consecutivas.'); break; }
      continue;
    }
  }
  if (!cursor && pages >= MAX_PAGES) completo = false;
  else if (!cursor) completo = true;
  else completo = false;

  const unicos = new Map();
  for (const i of all) if (!unicos.has(i.code)) unicos.set(i.code, i);
  const lista = [...unicos.values()];
  log('coleta concluida: ' + lista.length + ' posts unicos em ' + pages + ' paginas' +
    (completo ? ' (fim do feed).' : ' (parcial).'));
  return { lista, completo };
}

function rawItemsDoDataset(dataset) {
  return dataset.posts.map((p) => ({
    id: p.id, code: p.code, alt: p.legenda, date: p.timestamp_unix,
    likeCount: p.likes, commentCount: p.comentarios, isVideo: p.tipo === 'VIDEO',
    isSidecar: p.tipo === 'CAROUSEL', thumb: p.thumbnail, src: p.midia, srcs: (p.midias || []).map((m) => m.src),
  }));
}

// ─── Montagem dos arquivos ───────────────────────────────────────────────────

function buildDataset(lista, totalPosts) {
  const vistos = new Set();
  const posts = [];
  for (const i of lista) {
    if (vistos.has(i.code)) continue;
    vistos.add(i.code);
    const cap = (i.alt || '').trim();
    const { categoria, tags } = classificar(cap);
    posts.push({
      id: i.id,
      code: i.code,
      url: 'https://www.instagram.com/p/' + i.code + '/',
      data_iso: i.date ? new Date(i.date * 1000).toISOString() : null,
      timestamp_unix: i.date,
      titulo: titulo(cap),
      legenda: cap,
      categoria,
      tags,
      likes: i.likeCount || 0,
      comentarios: i.commentCount || 0,
      tipo: i.isVideo ? 'VIDEO' : i.isSidecar ? 'CAROUSEL' : 'IMAGE',
      thumbnail: i.thumb || null,
      midia: i.src || null,
      midias: (i.srcs || []).map((s) => ({ src: s })),
    });
  }
  posts.sort((a, b) => (b.data_iso || '').localeCompare(a.data_iso || ''));

  const datas = posts.map((p) => p.data_iso).filter(Boolean).sort();
  const cobertura = datas.length ? datas[0].slice(0, 10) + ' a ' + datas[datas.length - 1].slice(0, 10) : null;

  const porCategoria = {};
  for (const p of posts) porCategoria[p.categoria] = (porCategoria[p.categoria] || 0) + 1;

  const totalLikes = posts.reduce((s, p) => s + p.likes, 0);
  const totalCom = posts.reduce((s, p) => s + p.comentarios, 0);

  return {
    metadados: {
      fonte: 'imginn.com (visualizador publico do Instagram)',
      perfil_url: 'https://www.instagram.com/' + USERNAME + '/',
      perfil_nome: 'ONG- Grupo Amor Animal - Jaque',
      perfil_username: USERNAME,
      cobertura,
      posts_coletados: posts.length,
      posts_totais_do_perfil: totalPosts,
      cobertura_percentual: totalPosts ? Math.round((posts.length / totalPosts) * 1000) / 10 : null,
      gerado_em: new Date().toISOString(),
      observacao: 'Conjunto de postagens publicas coletadas automaticamente pelo script atualizar.js.',
    },
    estatisticas: {
      por_categoria: porCategoria,
      total_likes: totalLikes,
      total_comentarios: totalCom,
      media_likes_por_post: posts.length ? Math.round((totalLikes / posts.length) * 10) / 10 : 0,
      media_comentarios_por_post: posts.length ? Math.round((totalCom / posts.length) * 10) / 10 : 0,
      posts_com_legenda: posts.filter((p) => p.legenda).length,
    },
    posts,
  };
}

function gerarHtml(dataset) {
  if (!fs.existsSync(FILE_TPL)) {
    throw new Error('Template nao encontrado: ' + FILE_TPL + '\nCopie o template-abas.html para a mesma pasta do script.');
  }
  const compact = dataset.posts.map((p) => ({
    code: p.code, url: p.url, data: p.data_iso, titulo: p.titulo,
    legenda: p.legenda, categoria: p.categoria, likes: p.likes, com: p.comentarios, tipo: p.tipo,
  }));
  const dataJson = JSON.stringify(compact).replace(/</g, '\\u003c');
  const tpl = fs.readFileSync(FILE_TPL, 'utf8');
  return tpl
    .replace('/*__DATA__*/[]', dataJson)
    .replace('__COBERTURA__', dataset.metadados.cobertura || 'n/d')
    .replace('__TOTAL__', String(dataset.posts.length))
    .replace('__GERADO_EM__', new Date(dataset.metadados.gerado_em).toLocaleString('pt-BR'));
}

// ─── Principal ───────────────────────────────────────────────────────────────

async function main() {
  let lista = null;
  let totalPosts = null;
  let origem = '';
  let datasetAntigo = null;
  if (fs.existsSync(FILE_JSON)) {
    try { datasetAntigo = JSON.parse(fs.readFileSync(FILE_JSON, 'utf8')); } catch (_) {}
  }
  const countAnterior = datasetAntigo && datasetAntigo.posts ? datasetAntigo.posts.length : 0;

  if (!SAVE_ONLY) {
    try {
      const html = await getProfilePage();
      const prof = parseProfile(html);
      totalPosts = prof.totalPosts;
      const res = await collect(prof);
      origem = 'imginn.com (coleta ao vivo)';
      if (res.lista.length === 0) {
        log('AVISO: coleta ao vivo nao retornou posts. Mantendo dados anteriores.');
      } else if (countAnterior > 0 && (!res.completo || res.lista.length < countAnterior)) {
        const mapa = new Map(rawItemsDoDataset(datasetAntigo).map((i) => [i.code, i]));
        for (const i of res.lista) mapa.set(i.code, i);
        lista = [...mapa.values()];
        log('coleta parcial: mesclado com dados anteriores -> ' + lista.length + ' posts (sem perda).');
      } else {
        lista = res.lista;
      }
    } catch (e) {
      log('AVISO: falha na coleta ao vivo (' + e.message + ').');
    }
  }

  if (!lista) {
    if (!fs.existsSync(FILE_JSON)) {
      log('ERRO: sem dados novos e sem dataset anterior para regenerar.');
      process.exit(1);
    }
    const antigo = JSON.parse(fs.readFileSync(FILE_JSON, 'utf8'));
    lista = rawItemsDoDataset(antigo);
    totalPosts = antigo.metadados.posts_totais_do_perfil;
    origem = 'dataset existente (--save-only ou coleta indisponivel)';
    log('Usando dados ja salvos (' + lista.length + ' posts).');
  }

  const dataset = buildDataset(lista, totalPosts);
  fs.writeFileSync(FILE_JSON, JSON.stringify(dataset, null, 2));

  let html;
  try {
    html = gerarHtml(dataset);
    fs.writeFileSync(FILE_HTML, html);
  } catch (e) {
    log('AVISO: nao foi possivel gerar o HTML (' + e.message + ')');
  }

  log('===== RESUMO =====');
  log('origem      : ' + origem);
  log('posts       : ' + dataset.posts.length + (dataset.metadados.posts_totais_do_perfil ? ' de ' + dataset.metadados.posts_totais_do_perfil + ' no perfil' : ''));
  log('cobertura   : ' + (dataset.metadados.cobertura || 'n/d'));
  log('categorias  : ' + JSON.stringify(dataset.estatisticas.por_categoria));
  log('dataset     : ' + FILE_JSON);
  log('pagina html : ' + FILE_HTML);
  log('concluido em ' + new Date().toLocaleString('pt-BR'));
}

main().catch((e) => {
  console.error('[atualizar] ERRO fatal:', e.message);
  process.exit(1);
});

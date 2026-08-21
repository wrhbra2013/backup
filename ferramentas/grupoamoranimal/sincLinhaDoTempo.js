#!/usr/bin/env node
/**
 * sincLinhaDoTempo.js — Envia posts do Instagram + eventos para endpoint
 * /linha_do_tempo da API, criando um historico unificado.
 *
 * Fluxo:
 *   1. Le instagram-grupoamoranimal-dataset.json (posts IG)
 *   2. Busca /eventos da API (eventos ja cadastrados)
 *   3. Normaliza ambos para um formato unico de "item da linha do tempo"
 *   4. Envia novos items para POST /linha_do_tempo (dedupe por ref+tipo)
 *
 * Uso:
 *   node sincLinhaDoTempo.js                       Sincroniza tudo
 *   node sincLinhaDoTempo.js --dry-run             Apenas mostra o que seria enviado
 *   node sincLinhaDoTempo.js --force               Reenvia todos
 *   node sincLinhaDoTempo.js --user X --pass Y     Credenciais
 *   node sincLinhaDoTempo.js --limite 50           Limita a 50 posts do IG
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_DATASET = path.join(DIR, 'instagram-grupoamoranimal-dataset.json');
const FILE_STATE   = path.join(DIR, 'linha_do_tempo_sinc.json');
const IMG_DIR      = path.join(DIR, 'img-resumo-mensal');

const API_PADRAO = 'https://api.projetosdinamicos.com.br/amoranimal';

let API   = process.env.API_BASE  || API_PADRAO;
let USER  = process.env.API_USER  || '';
let PASS  = process.env.API_PASS  || '';
let DRY   = process.argv.includes('--dry-run');
let FORCE = process.argv.includes('--force');
let LIMITE = null;

process.argv.forEach((a, i) => {
  if (a === '--user')  USER  = process.argv[i + 1] || USER;
  if (a === '--pass')  PASS  = process.argv[i + 1] || PASS;
  if (a === '--api')   API   = process.argv[i + 1] || API;
  if (a === '--limite') LIMITE = parseInt(process.argv[i + 1], 10) || null;
});

// ─── Helpers ────────────────────────────────────────────────────────────

function log(msg) { console.log(`[lt] ${msg}`); }
function warn(msg) { console.log(`[lt] ⚠ ${msg}`); }
function ok(msg) { console.log(`[lt] ✓ ${msg}`); }

function lerJson(arq) {
  if (!fs.existsSync(arq)) return null;
  return JSON.parse(fs.readFileSync(arq, 'utf-8'));
}

function salvarJson(arq, dados) {
  fs.writeFileSync(arq, JSON.stringify(dados, null, 2), 'utf-8');
}

function loadState() {
  const s = lerJson(FILE_STATE);
  return s || { sincronizados: [] };
}

function saveState(state) {
  salvarJson(FILE_STATE, state);
}

async function apiFetch(endpoint, opts = {}) {
  const url = API + endpoint;
  const r = await fetch(url, {
    ...opts,
    headers: { 'Content-Type': 'application/json', ...opts.headers }
  });
  return r;
}

async function login() {
  if (!USER || !PASS) {
    warn('Credenciais nao informadas (--user/--pass ou API_USER/API_PASS)');
    warn('Continuando sem token (apenas leitura publica)');
    return null;
  }
  log('Fazendo login...');
  const r = await apiFetch('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ usuario: USER, senha: PASS })
  });
  if (!r.ok) {
    warn('Login falhou: ' + r.status);
    return null;
  }
  const data = await r.json();
  ok('Login OK');
  return data.token;
}

function normalizarData(d) {
  if (!d) return null;
  if (d.match(/^\d{4}-\d{2}-\d{2}/)) return d.split('T')[0];
  if (d.match(/^\d{2}\/\d{2}\/\d{4}/)) {
    const [dd, mm, yyyy] = d.split('/');
    return `${yyyy}-${mm}-${dd}`;
  }
  return null;
}

function extrairFotoBase64(code) {
  const jpg = path.join(IMG_DIR, code + '.jpg');
  if (fs.existsSync(jpg)) {
    const buf = fs.readFileSync(jpg);
    return 'data:image/jpeg;base64,' + buf.toString('base64');
  }
  return null;
}

// ─── Converter posts IG para items da linha do tempo ────────────────────

function postsParaItems(posts) {
  const items = [];
  for (const p of posts) {
    const data = normalizarData(p.data_iso || p.data);
    if (!data) continue;

    const fotoBase64 = extrairFotoBase64(p.code);
    const fotoUrl = fotoBase64 || (p.thumbnail_src || p.display_url || '');

    let link = '';
    if (p.code) {
      link = `https://www.instagram.com/p/${p.code}/`;
    }

    items.push({
      ref: p.code || '',
      tipo: 'instagram',
      titulo: (p.legenda || '').substring(0, 80) || 'Post Instagram',
      descricao: p.legenda || '',
      foto_url: fotoUrl,
      data: data,
      likes: p.likes || 0,
      categoria: p.categoria || 'outros',
      link: link,
      origem: 'instagram'
    });
  }
  return items;
}

// ─── Converter eventos da API para items da linha do tempo ──────────────

function eventosParaItems(eventos) {
  const items = [];
  for (const e of eventos) {
    const data = normalizarData(e.data_evento || e.created_at);
    if (!data) continue;

    let foto = '';
    if (e.fotos || e.arquivo) {
      const f = e.fotos || e.arquivo;
      if (f.startsWith('http') || f.startsWith('data:')) foto = f;
      else foto = API + '/uploads/eventos/' + f;
    }

    items.push({
      ref: 'ev_' + e.id,
      tipo: 'evento',
      titulo: e.titulo || 'Evento',
      descricao: e.descricao || '',
      foto_url: foto,
      data: data,
      local: e.local || e.endereco || '',
      link: '',
      origem: 'api'
    });
  }
  return items;
}

// ─── Main ───────────────────────────────────────────────────────────────

async function main() {
  log('=== Linha do Tempo — Sincronizacao ===');
  log('API: ' + API);
  log('Modo: ' + (DRY ? 'DRY-RUN' : 'ENVIO'));

  // 1. Ler dataset do Instagram
  const dataset = lerJson(FILE_DATASET);
  if (!dataset || !dataset.posts) {
    warn('Dataset do Instagram nao encontrado: ' + FILE_DATASET);
    return;
  }
  let posts = dataset.posts;
  if (LIMITE) posts = posts.slice(0, LIMITE);
  log(`Posts IG: ${posts.length}`);

  // 2. Converter IG para items
  const itemsIG = postsParaItems(posts);
  log(`Items IG normalizados: ${itemsIG.length}`);

  // 3. Buscar eventos da API (leitura publica)
  let itemsEventos = [];
  try {
    const rEv = await apiFetch('/eventos');
    if (rEv.ok) {
      const eventos = await rEv.json();
      itemsEventos = eventosParaItems(Array.isArray(eventos) ? eventos : []);
      log(`Eventos da API: ${itemsEventos.length}`);
    }
  } catch (e) {
    warn('Nao foi possivel buscar eventos: ' + e.message);
  }

  // 4. Juntar tudo
  const todos = [...itemsIG, ...itemsEventos];
  todos.sort((a, b) => (b.data || '').localeCompare(a.data || ''));
  log(`Total de items: ${todos.length}`);

  // 5. Dedupe
  const state = loadState();
  const jaEnv = new Set(state.sincronizados.map(s => s.ref + '|' + s.tipo));
  const novos = FORCE ? todos : todos.filter(t => !jaEnv.has(t.ref + '|' + t.tipo));
  log(`Novos para enviar: ${novos.length}`);

  if (novos.length === 0) {
    ok('Nada novo para enviar.');
    return;
  }

  // 6. Enviar
  if (DRY) {
    log('--- DRY RUN: items que seriam enviados ---');
    for (const item of novos.slice(0, 20)) {
      log(`  [${item.tipo}] ${item.data} — ${item.titulo.substring(0, 50)}`);
    }
    if (novos.length > 20) log(`  ... e mais ${novos.length - 20} items`);
    return;
  }

  // Login
  const token = await login();
  const headers = {};
  if (token) headers['Authorization'] = 'Bearer ' + token;

  let enviados = 0;
  let erros = 0;

  for (const item of novos) {
    try {
      const r = await apiFetch('/linha_do_tempo', {
        method: 'POST',
        headers,
        body: JSON.stringify(item)
      });

      if (r.ok) {
        enviados++;
        state.sincronizados.push({ ref: item.ref, tipo: item.tipo, data: item.data });
        if (enviados % 10 === 0) ok(`Enviados: ${enviados}/${novos.length}`);
      } else {
        const txt = await r.text().catch(() => '');
        warn(`Erro ${r.status} para ${item.ref}: ${txt.substring(0, 80)}`);
        erros++;
      }
    } catch (e) {
      warn(`Falha de rede para ${item.ref}: ${e.message}`);
      erros++;
    }
  }

  // 7. Salvar estado
  saveState(state);

  log('=== Resultado ===');
  ok(`Enviados: ${enviados}`);
  if (erros > 0) warn(`Erros: ${erros}`);
  ok('Estado salvo em linha_do_tempo_sinc.json');
}

main().catch(e => {
  console.error('[lt] ERRO FATAL:', e.message);
  process.exit(1);
});

#!/usr/bin/env node
/**
 * filtrar.js — Gera dataset-filtrado.json organizando os posts por CATEGORIA e
 * ordenados por TIMESTAMP (mais recente primeiro). Para cada post que tem
 * correspondencia com a API (adocao, procura-se, castracao), inclui tambem o
 * campo "api" com as colunas que seriam enviadas na sincronizacao, facilitando
 * a revisao antes de postar.
 *
 * Uso:
 *   node filtrar.js                Gera dataset-filtrado.json
 *   node filtrar.js --castracao    Inclui payload de castracao (eventos)
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_JSON = path.join(DIR, '..', 'json', 'instagram-grupoamoranimal-dataset.json');
const FILE_OUT = path.join(DIR, '..', 'json', 'dataset-filtrado.json');
const INCLUI_CASTRACAO = process.argv.includes('--castracao');

// ─── Mesmos helpers do sincronizar.js ────────────────────────────────────────

const norm = (s = '') => (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const tem = (c, ...p) => p.some((w) => c.includes(w));

const IGNORAR_NOME = new Set([
  'pequena', 'pequeno', 'grande', 'medio', 'media', 'média', 'adotavel', 'adotável', 'adocao', 'adoção',
  'linda', 'lindo', 'lindinha', 'femea', 'fêmea', 'macho', 'gata', 'gato', 'gatinho', 'gatinha',
  'cadelinha', 'cachorro', 'cachorra', 'filhote', 'fofa', 'fofo', 'docil', 'dócil', 'castrada',
  'castrado', 'vacinada', 'vacinado', 'resgatada', 'resgatado', 'carinhosa', 'carinhoso',
]);

function nomePet(cap) {
  let m = (cap || '').match(/atende pelo nome\s+([A-Z][\wçãáéíóúâêô]{1,30})/i);
  if (m) return m[1];
  m = (cap || '').match(/([A-Z][a-zçãáéíóúâêô]+),?\s+(est[áa]|procura|busca|precisa|encontra-se|aguarda|esta) /i);
  if (m && !IGNORAR_NOME.has(norm(m[1]))) return m[1];
  m = (cap || '').match(/^([A-Z][a-zçãáéíóúâêô]+)(?:\s|[.,])/m);
  if (m && !IGNORAR_NOME.has(norm(m[1]))) return m[1];
  return null;
}

function especie(cap) {
  const c = norm(cap);
  if (tem(c, 'gata', 'gato', 'gat ', 'felina', 'felino')) return 'felino';
  if (tem(c, 'cachorr', 'cao ', 'cÃ£o', 'canina', 'canino', 'dog')) return 'canino';
  return null;
}

function porte(cap) {
  const c = norm(cap);
  if (tem(c, 'porte pequeno', 'pequeno porte', 'pequena')) return 'pequeno';
  if (tem(c, 'porte medio', 'medio porte', 'porte médio')) return 'medio';
  if (tem(c, 'porte grande', 'grande porte')) return 'grande';
  return null;
}

function idade(cap) {
  const m = (cap || '').match(/(\d{1,2})\s*(ano|anos|mes|meses|mês|mêses)/i);
  if (m) return tem(norm(m[2]), 'mes') ? m[1] + (parseInt(m[1], 10) > 1 ? ' meses' : ' mês') : m[1] + (parseInt(m[1], 10) > 1 ? ' anos' : ' ano');
  if (tem(norm(cap), 'filhot')) return 'filhote';
  return null;
}

function telefone(cap) {
  const m = (cap || '').match(/\(?\d{2}\)?[\s.-]?\d{4,5}[\s.-]?\d{4}/);
  return m ? m[0] : null;
}

const MESES = { janeiro: 1, fevereiro: 2, marco: 3, março: 3, abril: 4, maio: 5, junho: 6, julho: 7, agosto: 8, setembro: 9, outubro: 10, novembro: 11, dezembro: 12 };

function dataEvento(cap, fallback) {
  const c = norm(cap);
  let m = c.match(/(\d{1,2})\s+de\s+([a-zç]+)/i);
  if (m && MESES[m[2]]) {
    const y = new Date(fallback || Date.now()).getUTCFullYear();
    const dt = new Date(Date.UTC(y, MESES[m[2]] - 1, parseInt(m[1], 10)));
    if (!isNaN(dt)) return dt.toISOString();
  }
  m = c.match(/(\d{1,2})\/\s?(\d{1,2})(?:\/(\d{4}))?/);
  if (m) {
    const y = m[3] ? parseInt(m[3], 10) : new Date(fallback || Date.now()).getUTCFullYear();
    const dt = new Date(Date.UTC(y, parseInt(m[2], 10) - 1, parseInt(m[1], 10)));
    if (!isNaN(dt)) return dt.toISOString();
  }
  return fallback || null;
}

function limparTexto(s, max) {
  if (!s) return '';
  let t = s.replace(/#[\w\u00C0-\u024F]+/g, ' ').replace(/@[\w.]+/g, ' ')
    .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2B50}\u{2764}\u{2705}\u{274C}\u{2728}\u{2714}\u{27A1}\u{2197}\u{2B05}\u{27A4}\u{1F000}-\u{1F9FF}\u{231B}\u{23F0}\u{1F4F1}]/gu, ' ')
    .replace(/\s+/g, ' ').trim();
  if (max && t.length > max) t = t.slice(0, max).trimEnd() + '…';
  return t;
}

// ─── Payloads da API ─────────────────────────────────────────────────────────

function payloadAdocao(p) {
  const cap = p.legenda || '';
  return {
    nome: nomePet(cap) || limparTexto(p.titulo, 45) || 'Pet para adoção',
    idade: idade(cap),
    especie: especie(cap),
    porte: porte(cap),
    caracteristicas: limparTexto(cap, 300) || null,
    foto_url: p.midia || p.thumbnail || null,
    status: 'disponivel',
  };
}

function payloadProcuraSe(p) {
  const cap = p.legenda || '';
  return {
    tutor_nome: 'ONG Amor Animal',
    tutor_contato: telefone(cap) || '(14) 98101-1234',
    tutor_whatsapp: telefone(cap) || '(14) 98101-1234',
    pet_nome: nomePet(cap) || limparTexto(p.titulo, 45) || 'Pet desaparecido',
    pet_especie: { felino: 'Gato', canino: 'Cachorro' }[especie(cap)] || 'Outro',
    pet_idade: idade(cap),
    pet_porte: porte(cap) || null,
    pet_caracteristicas: limparTexto(cap, 300) || null,
    local_desaparecimento: 'Marília/SP',
    data_desaparecimento: p.data_iso ? p.data_iso.slice(0, 10) : null,
    foto_url: p.midia || p.thumbnail || null,
  };
}

function payloadEvento(p) {
  const cap = p.legenda || '';
  return {
    titulo: limparTexto(p.titulo, 90) || 'Mutirão de Castração',
    data_evento: dataEvento(cap, p.data_iso),
    descricao: cap || null,
    arquivo: p.thumbnail || p.midia || null,
  };
}

// ─── Montagem ────────────────────────────────────────────────────────────────

const TABELA = { adocao: '/adocao', 'procura-se': '/procura_se' };
if (INCLUI_CASTRACAO) TABELA.castracao = '/eventos';

function main() {
  if (!fs.existsSync(FILE_JSON)) {
    console.error('[filtrar] dataset nao encontrado: ' + FILE_JSON);
    process.exit(1);
  }
  const dataset = JSON.parse(fs.readFileSync(FILE_JSON, 'utf8'));

  const grupos = {};
  dataset.posts.forEach((p) => {
    const cat = p.categoria;
    if (!grupos[cat]) grupos[cat] = [];
    const base = {
      code: p.code,
      url: p.url,
      data_iso: p.data_iso,
      timestamp_unix: p.timestamp_unix,
      titulo: p.titulo,
      legenda: p.legenda,
      midia: p.midia,
      thumbnail: p.thumbnail,
    };
    if (TABELA[cat]) {
      base.api = {
        tabela: TABELA[cat],
        payload: cat === 'adocao' ? payloadAdocao(p)
          : cat === 'procura-se' ? payloadProcuraSe(p)
          : payloadEvento(p),
      };
    }
    grupos[cat].push(base);
  });

  const categorias = {};
  Object.keys(grupos).forEach((cat) => {
    const lista = grupos[cat].slice().sort((a, b) => (b.timestamp_unix || 0) - (a.timestamp_unix || 0));
    categorias[cat] = {
      total: lista.length,
      tabela_api: TABELA[cat] || null,
      posts: lista,
    };
  });

  const ordem = ['adocao', 'castracao', 'procura-se', 'doacao', 'outros'];
  const porCategoria = {};
  ordem.forEach((c) => { if (categorias[c]) porCategoria[c] = categorias[c]; });
  Object.keys(categorias).forEach((c) => { if (!porCategoria[c]) porCategoria[c] = categorias[c]; });

  const out = {
    metadados: {
      fonte: dataset.metadados.fonte,
      perfil_username: dataset.metadados.perfil_username,
      cobertura: dataset.metadados.cobertura,
      total_posts: dataset.posts.length,
      gerado_em: new Date().toISOString(),
      observacao: 'Dataset filtrado por categoria e ordenado por timestamp (mais recente primeiro). ' +
        'Campo "api" contem as colunas que seriam enviadas na sincronizacao.',
    },
    por_categoria: {},
  };
  Object.keys(porCategoria).forEach((c) => {
    out.por_categoria[c] = {
      total: porCategoria[c].total,
      tabela_api: porCategoria[c].tabela_api,
      posts: porCategoria[c].posts,
    };
  });

  fs.writeFileSync(FILE_OUT, JSON.stringify(out, null, 2));
  console.log('[filtrar] gerado: ' + FILE_OUT);
  console.log('[filtrar] total posts: ' + dataset.posts.length);
  Object.keys(out.por_categoria).forEach((c) => {
    const p = out.por_categoria[c];
    console.log('  ' + c + ': ' + p.total + (p.tabela_api ? ' -> ' + p.tabela_api : ' (sem tabela)'));
  });
}

main();

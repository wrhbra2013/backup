#!/usr/bin/env node
/**
 * preview.js — Gera preview-sincronizacao.html com TODOS os posts do dataset
 * em tabelas, mostrando as colunas que seriam enviadas para a API, para
 * revisao manual antes da sincronizacao.
 *
 * Uso:
 *   node preview.js            Gera o HTML com todos os posts
 *   node preview.js --castracao  Inclui posts de castracao (eventos)
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_JSON = path.join(DIR, '..', 'json', 'instagram-grupoamoranimal-dataset.json');
const FILE_HTML = path.join(DIR, '..', 'html', 'preview-sincronizacao.html');
const INCLUI_CASTRACAO = process.argv.includes('--castracao');

const API = process.env.API_BASE || 'https://api.projetosdinamicos.com.br/amoranimal';
const ENDPOINTS_API = ['adocao', 'procura_se', 'castracao', 'eventos', 'voluntario', 'transparencia', 'parceria', 'settings'];

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

// ─── Payloads (mesmos do sincronizar.js) ─────────────────────────────────────

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

// ─── Montagem do HTML ────────────────────────────────────────────────────────

const TABELA = { adocao: '/adocao', 'procura-se': '/procura_se' };
if (INCLUI_CASTRACAO) TABELA.castracao = '/eventos';

const OBRIGATORIOS = {
  '/adocao': ['nome'],
  '/procura_se': ['pet_nome', 'local_desaparecimento', 'tutor_contato'],
  '/eventos': ['titulo'],
};

function esc(s) {
  return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function celula(valor, obrigatorio) {
  const v = valor == null ? '' : String(valor);
  let cls = v ? '' : obrigatorio ? 'falta-obrigatorio' : 'vazio';
  return '<td class="' + cls + '" title="' + esc(v) + '">' + esc(v.length > 400 ? v.slice(0, 400) + '…' : v) + '</td>';
}

async function buscarApi() {
  const resultados = [];
  for (const ep of ENDPOINTS_API) {
    try {
      const res = await fetch(API + '/' + ep, { headers: { Accept: 'application/json' } });
      if (!res.ok) { resultados.push({ ep, status: res.status, erro: 'HTTP ' + res.status }); continue; }
      const data = await res.json();
      if (!Array.isArray(data)) { resultados.push({ ep, status: res.status, erro: 'resposta nao e lista' }); continue; }
      const colunas = [];
      data.forEach((r) => Object.keys(r).forEach((k) => { if (!colunas.includes(k)) colunas.push(k); }));
      resultados.push({ ep, status: res.status, colunas, linhas: data.length, exemplo: data[0] || null });
    } catch (e) {
      resultados.push({ ep, status: 0, erro: e.message });
    }
  }
  return resultados;
}

function tabelaApiHtml(t, payloadKeys) {
  if (t.erro) {
    return '<div class="post-wrapper"><h3 style="margin:0 0 4px">/<code>' + esc(t.ep) + '</code></h3>' +
      '<span class="badge falta">ERRO: ' + esc(t.erro) + '</span></div>';
  }
  const cols = t.colunas.map((c) => {
    const preenchido = payloadKeys.includes(c);
    return '<td class="' + (preenchido ? 'col-sync' : '') + '" title="' + (preenchido ? 'campo preenchido pelo sincronizar.js' : '') + '">' +
      '<code>' + esc(c) + '</code>' + (preenchido ? ' <span class="seta">← sync</span>' : '') + '</td>';
  }).join('');
  const exemplo = t.exemplo ? Object.keys(t.exemplo).map((k) =>
    '<tr><th class="col">' + esc(k) + '</th><td class="ex-valor" title="' + esc(String(t.exemplo[k])) + '">' + esc(String(t.exemplo[k]).slice(0, 90) || '(vazio)') + '</td></tr>').join('') : '';
  return '<div class="post-wrapper">' +
    '<h3 style="margin:0 0 4px">/<code>' + esc(t.ep) + '</code> — <b>' + t.linhas + '</b> linha(s), <b>' + t.colunas.length + '</b> coluna(s)</h3>' +
    '<details>' +
    '<summary>Ver exemplo de registro</summary>' +
    '<table>' + exemplo + '</table>' +
    '</details>' +
    '<table><tr>' + cols + '</tr></table>' +
    '</div>';
}

async function main() {
  if (!fs.existsSync(FILE_JSON)) {
    console.error('[preview] dataset nao encontrado: ' + FILE_JSON);
    process.exit(1);
  }
  const dataset = JSON.parse(fs.readFileSync(FILE_JSON, 'utf8'));
  const posts = dataset.posts;

  const linhas = [];
  let totalValidos = 0;
  let totalComFalta = 0;

  posts.forEach((p, idx) => {
    const rota = TABELA[p.categoria];
    if (!rota) return;
    let payload;
    if (p.categoria === 'adocao') payload = payloadAdocao(p);
    else if (p.categoria === 'procura-se') payload = payloadProcuraSe(p);
    else if (p.categoria === 'castracao') payload = payloadEvento(p);

    const cols = Object.keys(payload);
    const reqs = OBRIGATORIOS[rota] || [];
    const faltando = reqs.filter((k) => !payload[k]);
    if (faltando.length) totalComFalta++; else totalValidos++;

    const tituloLinha = '<td rowspan="' + (cols.length + 1) + '">' +
      '<strong>' + esc(p.categoria) + '</strong><br>' +
      '<a href="' + esc(p.url) + '" target="_blank">' + esc(p.code) + '</a><br>' +
      '<small>' + esc((p.data_iso || '').slice(0, 10)) + '</small><br>' +
      (p.midia || p.thumbnail
        ? '<img src="' + esc(p.midia || p.thumbnail) + '" width="80" height="80" style="object-fit:cover;border-radius:6px;">'
        : '<span class="vazio">sem foto</span>') +
      '<br><br><details><summary><small>Titulo original</small></summary><div class="titulo-orig">' + esc(p.titulo) + '</div></details>' +
      '</td>';

    const badge = faltando.length
      ? '<span class="badge falta">FALTAM ' + faltando.length + ' campo(s): ' + faltando.join(', ') + '</span>'
      : '<span class="badge ok">OK</span>';

    linhas.push('<tr>' + tituloLinha + '<th>POST /<code>' + rota.slice(1) + '</code></th><td colspan="2">' + badge + '</td></tr>');

    cols.forEach((k) => {
      const req = reqs.includes(k);
      linhas.push('<tr><th class="col" title="' + (req ? 'obrigatorio' : '') + '">' + esc(k) + (req ? ' *' : '') + '</th>' + celula(payload[k], req) + '<td class="origem-valor">' + esc(JSON.stringify(payload[k])) + '</td></tr>');
    });
  });

  const contagem = {};
  posts.forEach((p) => { if (TABELA[p.categoria]) contagem[p.categoria] = (contagem[p.categoria] || 0) + 1; });

  const resumoCategorias = Object.keys(contagem).map((c) =>
    '<span class="cat-pill">' + esc(c) + ': <b>' + contagem[c] + '</b></span>').join('');

  console.log('[preview] consultando API em ' + API + ' ...');
  const apiTabelas = await buscarApi();
  const payloadKeys = {
    adocao: Object.keys(payloadAdocao(posts.find((p) => p.categoria === 'adocao') || {})),
    procura_se: Object.keys(payloadProcuraSe(posts.find((p) => p.categoria === 'procura-se') || {})),
    castracao: Object.keys(payloadEvento(posts.find((p) => p.categoria === 'castracao') || {})),
  };
  const chavePorEndpoint = { adocao: 'adocao', procura_se: 'procura_se', castracao: 'castracao' };
  const apiTabelasHtml = apiTabelas.map((t) =>
    tabelaApiHtml(t, (chavePorEndpoint[t.ep] && payloadKeys[chavePorEndpoint[t.ep]]) || [])).join('\n');

  const html = `<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>Preview de Sincronizacao - Grupo Amor Animal</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; padding: 1.5rem; background: #0f172a; color: #e2e8f0; }
  h1 { margin-top: 0; }
  .toolbar { display: flex; gap: 1rem; flex-wrap: wrap; align-items: center; margin-bottom: 1rem; }
  .cat-pill { background: #1e293b; border: 1px solid #334155; padding: 4px 10px; border-radius: 20px; font-size: 0.85rem; }
  .badge { padding: 3px 10px; border-radius: 20px; font-size: 0.8rem; font-weight: 600; }
  .badge.ok { background: #14532d; color: #4ade80; }
  .badge.falta { background: #7f1d1d; color: #fca5a5; }
  .stats { display: flex; gap: 1.5rem; margin-bottom: 1rem; }
  .stats div { background: #1e293b; border: 1px solid #334155; padding: 8px 16px; border-radius: 8px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 0.5rem; background: #1e293b; border: 1px solid #334155; }
  th, td { border: 1px solid #334155; padding: 6px 10px; font-size: 0.85rem; vertical-align: top; text-align: left; }
  th.col { width: 160px; background: #0f172a; color: #94a3b8; font-weight: 600; }
  td { word-break: break-word; }
  td.vazio { color: #64748b; font-style: italic; }
  td.falta-obrigatorio { background: #450a0a; color: #fecaca; font-weight: 700; }
  .origem-valor { color: #64748b; font-size: 0.72rem; }
  .titulo-orig { font-size: 0.72rem; color: #94a3b8; }
  details summary { cursor: pointer; color: #7dd3fc; }
  .post-wrapper { margin-bottom: 1.25rem; }
  a { color: #7dd3fc; }
  .nav { position: sticky; top: 0; background: #0f172a; padding: 8px 0; border-bottom: 1px solid #334155; z-index: 10; }
  .col-sync { background: #052e16; }
  .seta { color: #4ade80; font-size: 0.7rem; }
  .ex-valor { color: #94a3b8; font-size: 0.78rem; }
  .api-section { margin: 2rem 0; padding: 1rem; background: #172033; border: 1px solid #334155; border-radius: 10px; }
  h2.sec { color: #7dd3fc; border-bottom: 1px solid #334155; padding-bottom: 6px; }
</style>
</head>
<body>
<h1>Preview de Sincronizacao — Grupo Amor Animal</h1>
<div class="toolbar">
  <span class="cat-pill">posts no dataset: <b>${posts.length}</b></span>
  ${resumoCategorias}
  <span class="cat-pill">a enviar: <b>${posts.filter((p) => TABELA[p.categoria]).length}</b></span>
</div>
<div class="stats">
  <div>✅ Campos OK: <b>${totalValidos}</b></div>
  <div>⚠️ Faltam campos: <b>${totalComFalta}</b></div>
</div>
<p><small>Gerado em ${new Date().toLocaleString('pt-BR')}. Legenda: <b style="color:#4ade80">OK</b> = campos preenchidos; <b style="color:#fca5a5">FALTAM</b> = obrigatorios vazios; <b style="color:#64748b">vazio</b> = opcional. Clique no post (instagram) para abrir o original.</small></p>

<div class="api-section">
  <h2 class="sec">Tabelas da API (consultadas ao vivo)</h2>
  <p><small>Colunas encontradas em cada endpoint. <span style="color:#4ade80">← sync</span> marca a coluna preenchida pelo sincronizar.js.</small></p>
  ${apiTabelasHtml}
</div>

${linhas.map((l) => '<div class="post-wrapper">' + '<table>' + l + '</table></div>').join('\n')}
</body>
</html>`;

  fs.writeFileSync(FILE_HTML, html);
  console.log('[preview] gerado: ' + FILE_HTML);
  console.log('[preview] posts a enviar: ' + posts.filter((p) => TABELA[p.categoria]).length + ' | OK: ' + totalValidos + ' | com falta: ' + totalComFalta);
}

main().catch((e) => {
  console.error('[preview] ERRO fatal: ' + e.message);
  process.exit(1);
});

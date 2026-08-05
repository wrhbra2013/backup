#!/usr/bin/env node
/**
 * cruzar-api.js — Cruza os posts do resumo-mensal com as tabelas da API Amor Animal
 * e gera os "inputs" corretos para postagem (mesma lógica do sincronizar.js).
 *
 * Para cada post do resumo (instagram-grupoamoranimal-resumo-mensal.json) calcula:
 *   * Rota da API (tabela) para a qual ele seria enviado
 *   * Payload (JSON de input) com os campos corretos, extraídos da legenda
 *   * Observações (campos faltantes, foto, telefone etc.)
 *
 * Gera: instagram-grupoamoranimal-postagem.html
 *
 * Uso:
 *   node cruzar-api.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_RESUMO = path.join(DIR, '..', 'json', 'instagram-grupoamoranimal-resumo-mensal.json');
const FILE_DATASET = path.join(DIR, '..', 'json', 'instagram-grupoamoranimal-dataset.json');
const OUT_HTML = path.join(DIR, '..', 'html', 'instagram-grupoamoranimal-postagem.html');
const API_BASE = 'https://api.projetosdinamicos.com.br/amoranimal';
const ENDPOINTS = ['adocao', 'procura_se', 'eventos', 'castracao', 'adotado', 'home'];

// ─── Helpers de parsing (espelho do sincronizar.js) ──────────────────────────

const norm = (s = '') => (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const tem = (c, ...p) => p.some((w) => c.includes(w));

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
  if (m) {
    if (tem(norm(m[2]), 'mes')) return m[1] + (parseInt(m[1], 10) > 1 ? ' meses' : ' mês');
    return m[1] + (parseInt(m[1], 10) > 1 ? ' anos' : ' ano');
  }
  if (tem(norm(cap), 'filhot')) return 'filhote';
  return null;
}

function telefone(cap) {
  const m = (cap || '').match(/\(?\d{2}\)?[\s.-]?\d{4,5}[\s.-]?\d{4}/);
  return m ? m[0] : null;
}

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
    const dd = parseInt(m[1], 10), mm = parseInt(m[2], 10);
    const y = m[3] ? parseInt(m[3], 10) : new Date(fallback || Date.now()).getUTCFullYear();
    const dt = new Date(Date.UTC(y, mm - 1, dd));
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

// ─── Payloads (espelho do sincronizar.js) ────────────────────────────────────

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

const ROTAS = {
  adocao: { rota: '/adocao', label: 'Adoção (animais disponíveis)', fn: payloadAdocao },
  'procura-se': { rota: '/procura_se', label: 'Procura-se (desaparecidos)', fn: payloadProcuraSe },
  castracao: { rota: '/eventos', label: 'Eventos / Mutições de Castração', fn: payloadEvento },
  doacao: null,
  outros: null,
};

// ─── Coleta de dados ─────────────────────────────────────────────────────────

function carregarResumo() {
  const resumo = JSON.parse(fs.readFileSync(FILE_RESUMO, 'utf8'));
  // mescla legenda/foto do dataset (imginn) por code
  let legenda = {}, thumb = {}, midia = {};
  if (fs.existsSync(FILE_DATASET)) {
    const ds = JSON.parse(fs.readFileSync(FILE_DATASET, 'utf8'));
    ds.posts.forEach((p) => {
      if (p.legenda) legenda[p.code] = p.legenda;
      if (p.thumbnail) thumb[p.code] = p.thumbnail;
      if (p.midia) midia[p.code] = p.midia;
    });
  }
  const posts = [];
  Object.keys(resumo.por_ano).forEach((ano) =>
    Object.keys(resumo.por_ano[ano].meses).forEach((mes) =>
      resumo.por_ano[ano].meses[mes].posts.forEach((p) => {
        posts.push({
          code: p.code,
          url: p.url,
          data: p.data,
          timestamp_unix: p.timestamp_unix,
          titulo: p.titulo,
          tipo: p.tipo,
          likes: p.likes,
          comentarios: p.comentarios,
          categoria: p.categoria,
          legenda: p.legenda || legenda[p.code] || '',
          thumbnail: p.thumbnail || thumb[p.code] || null,
          midia: midia[p.code] || null,
          data_iso: p.timestamp_unix ? new Date(p.timestamp_unix * 1000).toISOString() : null,
        });
      })));
  return { resumo, posts };
}

async function buscarApi() {
  const cacheDir = path.join(DIR, '..', '.api-cache');
  const out = {};
  for (const ep of ENDPOINTS) {
    const cache = path.join(cacheDir, ep + '.json');
    try {
      const res = await fetch(API_BASE + '/' + ep);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      out[ep] = Array.isArray(data) ? data.length : 0;
      if (fs.existsSync(cacheDir)) fs.writeFileSync(cache, JSON.stringify(Array.isArray(data) ? data : []));
    } catch (e) {
      console.log('[cruzar] AVISO: /' + ep + ' indisponivel (' + e.message + '); usando cache.');
      out[ep] = fs.existsSync(cache) ? JSON.parse(fs.readFileSync(cache, 'utf8')).length : 0;
    }
  }
  return out;
}

// ─── Montagem ────────────────────────────────────────────────────────────────

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function dadosPost(p) {
  const map = ROTAS[p.categoria];
  let payload = null, observacoes = [];
  if (map) {
    payload = map.fn(p);
    if (!payload.foto_url) observacoes.push('sem foto (foto_url vazio)');
    if (p.categoria === 'adocao' && !idade(p.legenda)) observacoes.push('idade não identificada');
    if (p.categoria === 'procura-se' && !telefone(p.legenda)) observacoes.push('telefone não identificado (usa padrão)');
    if (p.categoria === 'castracao' && payload.data_evento === p.data_iso) observacoes.push('data do evento não identificada (usa data do post)');
  } else if (p.categoria === 'doacao') {
    observacoes.push('não mapeado: categoria "doacao" não tem tabela própria (apenas avisos/home)');
  } else {
    observacoes.push('não mapeado: categoria "outros"');
  }
  return {
    code: p.code,
    url: p.url,
    data: p.data,
    data_iso: p.data_iso,
    titulo: p.titulo,
    tipo: p.tipo,
    likes: p.likes,
    comentarios: p.comentarios,
    categoria: p.categoria,
    legenda: p.legenda,
    rota: map ? map.rota : null,
    label: map ? map.label : null,
    payload,
    observacoes,
  };
}

// ─── HTML ────────────────────────────────────────────────────────────────────

const CSS = `
:root{--bg:linear-gradient(135deg,#f5f7fa,#e8ecf1);--surface:rgba(255,255,255,0.92);--border:rgba(0,0,0,0.07);--text:#1a1a2e;--muted:#555;--dim:#999;--grad:linear-gradient(45deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888);--c-adocao:#0a7d4f;--bg-adocao:rgba(10,125,79,0.12);--c-castracao:#1d4ed8;--bg-castracao:rgba(29,78,216,0.12);--c-procura:#c2410c;--bg-procura:rgba(194,65,12,0.12);--c-doacao:#a21caf;--bg-doacao:rgba(162,28,175,0.12);--c-outros:#6b7280;--bg-outros:rgba(107,114,128,0.14);--shadow:0 4px 16px rgba(0,0,0,0.08)}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,sans-serif;background:var(--bg);min-height:100vh;color:var(--text)}
header{background:rgba(255,255,255,0.85);backdrop-filter:blur(12px);padding:14px 30px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:14px;box-shadow:0 1px 3px rgba(0,0,0,0.06);position:sticky;top:0;z-index:50;flex-wrap:wrap}
.ig-icon{width:36px;height:36px;border-radius:10px;background:var(--grad);display:flex;align-items:center;justify-content:center;font-size:1.2rem}
header h1{font-size:1.25rem;font-weight:700;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
header .sub{font-size:0.72rem;color:var(--dim);width:100%}
.container{max-width:1280px;margin:0 auto;padding:20px 24px}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:18px}
.tab{padding:8px 16px;border-radius:20px;border:1px solid var(--border);background:var(--surface);cursor:pointer;font-size:0.85rem;font-weight:600;font-family:inherit;color:var(--muted);transition:all .15s;display:flex;align-items:center;gap:6px}
.tab .n{font-size:0.7rem;background:rgba(0,0,0,0.06);padding:1px 7px;border-radius:10px;color:var(--dim)}
.tab:hover{transform:translateY(-1px);box-shadow:var(--shadow)}
.tab.active{background:var(--grad);color:#fff;border-color:transparent}
.tab.active .n{background:rgba(255,255,255,0.25);color:#fff}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.card .v{font-size:1.4rem;font-weight:800;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.card .l{font-size:0.7rem;color:var(--muted);text-transform:uppercase;letter-spacing:0.6px;margin-top:2px}
.section-title{font-size:1.05rem;font-weight:700;margin:24px 0 12px;display:flex;align-items:center;gap:8px}
.section-title .bar{width:4px;height:18px;border-radius:2px;background:var(--grad)}
table{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);font-size:0.82rem}
thead th{text-align:left;font-size:0.68rem;text-transform:uppercase;letter-spacing:0.6px;color:var(--dim);padding:10px 12px;background:rgba(0,0,0,0.03);border-bottom:1px solid var(--border);white-space:nowrap}
tbody td{padding:9px 12px;border-bottom:1px solid rgba(0,0,0,0.04);vertical-align:top}
tbody tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(204,35,102,0.04)}
td.num,th.num{text-align:right}
.badge{font-size:0.62rem;text-transform:uppercase;letter-spacing:0.5px;padding:2px 8px;border-radius:20px;font-weight:700;white-space:nowrap}
.badge-adocao{background:var(--bg-adocao);color:var(--c-adocao)}
.badge-castracao{background:var(--bg-castracao);color:var(--c-castracao)}
.badge-procura-se{background:var(--bg-procura);color:var(--c-procura)}
.badge-doacao{background:var(--bg-doacao);color:var(--c-doacao)}
.badge-outros{background:var(--bg-outros);color:var(--c-outros)}
.link-ig{color:#cc2366;text-decoration:none;font-weight:700;white-space:nowrap}
.link-ig:hover{text-decoration:underline}
.info{font-size:0.78rem;color:var(--dim);margin-bottom:12px}
.obs{font-size:0.72rem;color:#b45309;margin-top:4px}
.foto-cell{font-size:0.72rem}
details{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:4px 8px}
summary{cursor:pointer;font-size:0.72rem;color:var(--muted);font-weight:600;padding:4px}
pre{margin-top:6px;padding:10px;background:#1a1a2e;color:#d1fae5;border-radius:8px;font-size:0.72rem;overflow:auto;white-space:pre-wrap;word-break:break-all;max-height:320px}
.btn-copy{padding:4px 10px;border-radius:6px;border:1px solid var(--border);background:#fff;color:var(--text);font-size:0.7rem;font-weight:600;cursor:pointer;font-family:inherit;margin-top:6px}
.btn-copy:hover{border-color:#cc2366}
.controls{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px}
.controls input{padding:9px 14px;border-radius:10px;border:1px solid var(--border);background:var(--surface);font-family:inherit;font-size:0.85rem;color:var(--text);outline:none;flex:1;min-width:200px}
.controls input:focus{border-color:#cc2366;box-shadow:0 0 0 3px rgba(204,35,102,0.1)}
.destaque{background:rgba(204,35,102,0.05);border:1px solid rgba(204,35,102,0.15);border-radius:12px;padding:14px 16px;margin-bottom:16px;font-size:0.85rem;color:var(--muted)}
.destaque b{color:var(--text)}
footer{text-align:center;padding:30px;color:var(--dim);font-size:0.75rem}
.toolbar{position:fixed;bottom:20px;right:20px;display:flex;gap:8px;z-index:10}
.toolbar button{padding:10px 16px;border-radius:8px;border:none;cursor:pointer;font-size:0.82rem;font-weight:600;box-shadow:var(--shadow);font-family:inherit}
.btn-top{background:#fff;color:var(--text);border:1px solid var(--border)!important}
.row-hide{display:none!important}
@media(max-width:700px){header{padding:12px 16px}}
`;

const JS = `
document.getElementById('busca').addEventListener('input', e => {
  const q = e.target.value.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,'');
  document.querySelectorAll('tbody tr').forEach(tr => {
    const txt = tr.getAttribute('data-busca') || '';
    tr.classList.toggle('row-hide', !!q && !txt.includes(q));
  });
});
document.querySelectorAll('.btn-copy').forEach(b => b.addEventListener('click', () => {
  const pre = b.parentElement.querySelector('pre');
  navigator.clipboard.writeText(pre.textContent).then(() => {
    const old = b.textContent; b.textContent = 'Copiado ✓';
    setTimeout(() => b.textContent = old, 1200);
  });
}));
`;

function fmtData(iso) {
  if (!iso) return '—';
  const d = iso.length > 10 ? new Date(iso) : new Date(iso + 'T00:00:00');
  const p = (n) => String(n).padStart(2, '0');
  if (isNaN(d)) return iso;
  return p(d.getDate()) + '/' + p(d.getMonth() + 1) + '/' + d.getFullYear();
}

const CAT_BADGE = (c) => '<span class="badge badge-' + c + '">' + ({
  adocao: 'Adoção', castracao: 'Castração', 'procura-se': 'Procura-se', doacao: 'Doações', outros: 'Outros',
}[c] || c) + '</span>';

function rowPost(d, showRota) {
  const payload = d.payload;
  const pre = payload
    ? '<details><summary>Ver payload (JSON de input)</summary>' +
      '<pre>' + esc(JSON.stringify(payload, null, 2)) + '</pre>' +
      '<button class="btn-copy" type="button">Copiar JSON</button></details>'
    : '<span style="color:var(--dim)">—</span>';
  const obs = d.observacoes.length ? '<div class="obs">⚠ ' + d.observacoes.join(' · ') + '</div>' : '';
  const foto = d.thumbnail ? '<span style="color:var(--c-adocao)">&#9989; foto</span>' : '<span style="color:var(--c-doacao)">&#10060; sem foto</span>';
  return '<tr data-busca="' + esc((d.titulo + ' ' + d.legenda + ' ' + (d.rota || '')).toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')) + '">' +
    '<td class="num" style="white-space:nowrap">' + fmtData(d.data) + '</td>' +
    (showRota ? '<td>' + (d.rota || '—') + '</td>' : '') +
    '<td>' + (d.rota ? esc(d.payload && (d.payload.nome || d.payload.pet_nome || d.payload.titulo) || d.titulo) : '') + '</td>' +
    '<td>' + esc(d.titulo) + '<br><a class="link-ig" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver no Instagram &#8599;</a>' + obs + '</td>' +
    '<td class="foto-cell">' + foto + '</td>' +
    '<td>' + pre + '</td>' +
    '</tr>';
}

function buildHtml({ resumo, posts, apiCount }) {
  const dados = posts.map(dadosPost);
  const porRota = {};
  const ignorados = [];
  dados.forEach((d) => {
    if (d.rota) (porRota[d.rota] = porRota[d.rota] || []).push(d);
    else ignorados.push(d);
  });
  const totalMap = dados.filter((d) => d.rota).length;
  const badge = (c) => CAT_BADGE(c);
  const legend = 'Cada post do resumo-mensal foi cruzado com a tabela da API correspondente à sua categoria. ' +
    'Os payloads abaixo usam exatamente a mesma lógica de extração do sincronizar.js.';

  let sec = '';
  Object.keys(ROTAS).forEach((cat) => {
    const map = ROTAS[cat];
    if (!map) return;
    const lista = porRota[map.rota] || [];
    sec += '<div class="section-title"><span class="bar"></span>' + esc(map.label) +
      ' <span style="font-size:0.72rem;color:var(--dim)">' + map.rota + '</span>' +
      ' <span class="badge badge-' + cat + '" style="margin-left:6px">' + lista.length + ' post(s)</span>' +
      '</div>';
    sec += '<div class="info">Já existem ' + (apiCount[cat === 'adocao' ? 'adocao' : cat === 'procura-se' ? 'procura_se' : 'eventos'] || 0) +
      ' registros nesta tabela na API.</div>';
    sec += '<div style="overflow-x:auto"><table><thead><tr>' +
      '<th>Data</th><th>Nome/Input</th><th>Post de origem</th><th>Foto</th><th>Input (payload)</th></tr></thead><tbody>' +
      lista.map((d) => rowPost(d, false)).join('') + '</tbody></table></div>';
  });

  sec += '<div class="section-title"><span class="bar"></span>Não mapeados (sem tabela na API)</div>';
  sec += '<div class="info">' + ignorados.length + ' posts das categorias "doação" e "outros" não possuem tabela correspondente na API (o sincronizar.js os ignora).</div>';
  sec += '<div style="overflow-x:auto"><table><thead><tr>' +
    '<th>Data</th><th>Categoria</th><th>Post de origem</th><th>Motivo</th></tr></thead><tbody>' +
    ignorados.map((d) => '<tr data-busca="' + esc((d.titulo + ' ' + d.legenda + ' ' + d.categoria).toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')) + '">' +
      '<td class="num" style="white-space:nowrap">' + fmtData(d.data) + '</td>' +
      '<td>' + badge(d.categoria) + '</td>' +
      '<td>' + esc(d.titulo) + '<br><a class="link-ig" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver no Instagram &#8599;</a></td>' +
      '<td class="obs">' + esc(d.observacoes.join(' · ')) + '</td></tr>').join('') +
    '</tbody></table></div>';

  const now = new Date().toLocaleString('pt-BR');
  return '<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n<meta charset="UTF-8">\n' +
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
    '<title>@grupoamoranimal - Cruzamento com a API (inputs de postagem)</title>\n<style>' + CSS + '</style>\n</head>\n<body>\n' +
    '<header><div class="ig-icon">&#128062;</div><h1>@grupoamoranimal - Cruzamento com a API Amor Animal</h1>' +
    '<div class="sub">Posts do resumo-mensal prontos para postagem nas tabelas da API · inputs extraídos automaticamente da legenda · gerado em ' + esc(now) + '</div></header>\n' +
    '<div class="container">\n' +
    '<div class="destaque"><b>' + esc(legend) + '</b></div>\n' +
    '<div class="cards">' +
    '<div class="card"><div class="v">' + posts.length + '</div><div class="l">Posts no resumo</div></div>' +
    '<div class="card"><div class="v">' + totalMap + '</div><div class="l">Posts mapeáveis (API)</div></div>' +
    '<div class="card"><div class="v">' + ignorados.length + '</div><div class="l">Não mapeados</div></div>' +
    '<div class="card"><div class="v">' + Object.keys(porRota).length + '</div><div class="l">Tabelas-alvo</div></div>' +
    '</div>\n' +
    '<div class="controls"><input type="text" id="busca" placeholder="Filtrar por título, nome do pet ou texto da legenda..."></div>\n' +
    sec + '\n</div>\n' +
    '<footer>Gerado automaticamente · Dados: instagram-grupoamoranimal-resumo-mensal.json + lógica de payload do sincronizar.js · API: ' + esc(API_BASE) + '</footer>\n' +
    '<div class="toolbar"><button class="btn-top" onclick="window.scrollTo({top:0,behavior:\'smooth\'})">Topo</button></div>\n' +
    '<script>' + JS + '</script>\n</body>\n</html>';
}

async function main() {
  if (!fs.existsSync(FILE_RESUMO)) {
    console.error('[cruzar] ERRO: resumo-mensal nao encontrado. Rode resumo-mensal.py antes.');
    process.exit(1);
  }
  const { resumo, posts } = carregarResumo();
  const apiCount = await buscarApi();
  const html = buildHtml({ resumo, posts, apiCount });
  fs.writeFileSync(OUT_HTML, html);
  console.log('[cruzar] posts: ' + posts.length);
  const porCat = {};
  posts.forEach((p) => { porCat[p.categoria] = (porCat[p.categoria] || 0) + 1; });
  console.log('[cruzar] por categoria: ' + JSON.stringify(porCat));
  console.log('[cruzar] registros atuais na API: ' + JSON.stringify(apiCount));
  console.log('[cruzar] pagina gerada: ' + OUT_HTML + ' (' + (html.length / 1024).toFixed(1) + ' KB)');
}

main().catch((e) => { console.error('[cruzar] ERRO fatal:', e); process.exit(1); });

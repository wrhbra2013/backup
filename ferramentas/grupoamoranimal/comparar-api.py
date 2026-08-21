#!/usr/bin/env python3
"""comparar-api.py — Compara os dados do resumo-mensal com a API do site Amor Animal.

Busca os dados da API (api.projetosdinamicos.com.br/amoranimal), compara com o
resumo de postagens do Instagram (instagram-grupoamoranimal-resumo-mensal.json) e
gera instagram-grupoamoranimal-comparacao.html contendo:
  * Visão de comparação (Instagram x API por categoria)
  * Detalhes de cada tabela da API com correspondências no Instagram
  * Abas por ano com o resumo mensal de postagens (dados do resumo-mensal)

Uso:
  python3 comparar-api.py
"""
import json
import os
import sys
import urllib.request
from datetime import datetime

DIR = os.path.dirname(os.path.abspath(__file__))
API_BASE = 'https://api.projetosdinamicos.com.br/amoranimal'
RESUMO_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.json')
DATASET_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-dataset.json')
OUT_HTML = os.path.join(DIR, 'instagram-grupoamoranimal-comparacao.html')
CACHE_DIR = os.path.join(DIR, '.api-cache')

ENDPOINTS = ['adocao', 'procura_se', 'eventos', 'castracao', 'adotado', 'home']

MESES_PT = {1: 'Janeiro', 2: 'Fevereiro', 3: 'Março', 4: 'Abril', 5: 'Maio', 6: 'Junho',
            7: 'Julho', 8: 'Agosto', 9: 'Setembro', 10: 'Outubro', 11: 'Novembro', 12: 'Dezembro'}

CATEGORIAS_API = {
    'adocao': ['adocao', 'adotado'],
    'castracao': ['eventos', 'castracao'],
    'procura-se': ['procura_se'],
    'doacao': ['home'],
    'outros': [],
}

CSS = """
:root{
  --bg:linear-gradient(135deg,#f5f7fa,#e8ecf1);
  --surface:rgba(255,255,255,0.92);
  --border:rgba(0,0,0,0.07);
  --text:#1a1a2e;--muted:#555;--dim:#999;
  --grad:linear-gradient(45deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888);
  --c-adocao:#0a7d4f;--bg-adocao:rgba(10,125,79,0.12);
  --c-castracao:#1d4ed8;--bg-castracao:rgba(29,78,216,0.12);
  --c-procura:#c2410c;--bg-procura:rgba(194,65,12,0.12);
  --c-doacao:#a21caf;--bg-doacao:rgba(162,28,175,0.12);
  --c-outros:#6b7280;--bg-outros:rgba(107,114,128,0.14);
  --shadow:0 4px 16px rgba(0,0,0,0.08);
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,sans-serif;background:var(--bg);min-height:100vh;color:var(--text)}
header{background:rgba(255,255,255,0.85);backdrop-filter:blur(12px);padding:14px 30px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:14px;box-shadow:0 1px 3px rgba(0,0,0,0.06);position:sticky;top:0;z-index:50;flex-wrap:wrap}
.ig-icon{width:36px;height:36px;border-radius:10px;background:var(--grad);display:flex;align-items:center;justify-content:center;font-size:1.2rem}
header h1{font-size:1.25rem;font-weight:700;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
header .sub{font-size:0.72rem;color:var(--dim);width:100%}
.container{max-width:1250px;margin:0 auto;padding:20px 24px}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:18px}
.tab{padding:8px 16px;border-radius:20px;border:1px solid var(--border);background:var(--surface);cursor:pointer;font-size:0.85rem;font-weight:600;font-family:inherit;color:var(--muted);transition:all .15s;display:flex;align-items:center;gap:6px}
.tab .n{font-size:0.7rem;background:rgba(0,0,0,0.06);padding:1px 7px;border-radius:10px;color:var(--dim)}
.tab:hover{transform:translateY(-1px);box-shadow:var(--shadow)}
.tab.active{background:var(--grad);color:#fff;border-color:transparent}
.tab.active .n{background:rgba(255,255,255,0.25);color:#fff}
.hidden{display:none!important}
.section-title{font-size:1.05rem;font-weight:700;margin:22px 0 12px;display:flex;align-items:center;gap:8px}
.section-title .bar{width:4px;height:18px;border-radius:2px;background:var(--grad)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.card .v{font-size:1.45rem;font-weight:800;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.card .l{font-size:0.72rem;color:var(--muted);text-transform:uppercase;letter-spacing:0.6px;margin-top:2px}
table{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);font-size:0.82rem}
thead th{text-align:left;font-size:0.68rem;text-transform:uppercase;letter-spacing:0.6px;color:var(--dim);padding:10px 12px;background:rgba(0,0,0,0.03);border-bottom:1px solid var(--border);white-space:nowrap}
tbody td{padding:9px 12px;border-bottom:1px solid rgba(0,0,0,0.04);vertical-align:middle}
tbody tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(204,35,102,0.04)}
td.num,th.num{text-align:right}
.badge{font-size:0.62rem;text-transform:uppercase;letter-spacing:0.5px;padding:2px 8px;border-radius:20px;font-weight:700;white-space:nowrap}
.badge-adocao{background:var(--bg-adocao);color:var(--c-adocao)}
.badge-castracao{background:var(--bg-castracao);color:var(--c-castracao)}
.badge-procura-se{background:var(--bg-procura);color:var(--c-procura)}
.badge-doacao{background:var(--bg-doacao);color:var(--c-doacao)}
.badge-outros{background:var(--bg-outros);color:var(--c-outros)}
.type-pill{font-size:0.66rem;padding:2px 7px;border-radius:6px;background:rgba(0,0,0,0.05);color:var(--muted);font-weight:700;white-space:nowrap}
.status-pill{font-size:0.66rem;padding:2px 8px;border-radius:6px;font-weight:700;white-space:nowrap}
.status-ok{background:rgba(16,185,129,0.14);color:#047857}
.status-warn{background:rgba(234,179,8,0.16);color:#a16207}
.status-empty{background:rgba(107,114,128,0.14);color:var(--muted)}
.month-block{margin-bottom:26px}
.month-head{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:10px}
.month-head h3{font-size:1rem;color:#cc2366}
.month-chips{display:flex;gap:8px;flex-wrap:wrap;margin-left:auto}
.chip{font-size:0.7rem;padding:3px 10px;border-radius:20px;background:var(--surface);border:1px solid var(--border);color:var(--muted)}
.chip b{color:var(--text)}
.controls{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px}
.controls input{padding:9px 14px;border-radius:10px;border:1px solid var(--border);background:var(--surface);font-family:inherit;font-size:0.85rem;color:var(--text);outline:none;flex:1;min-width:200px}
.controls input:focus{border-color:#cc2366;box-shadow:0 0 0 3px rgba(204,35,102,0.1)}
.info{font-size:0.78rem;color:var(--dim);margin-bottom:12px}
.link-ig{color:#cc2366;text-decoration:none;font-weight:700;white-space:nowrap}
.link-ig:hover{text-decoration:underline}
.est-bar{height:6px;border-radius:3px;background:rgba(0,0,0,0.05);overflow:hidden;min-width:90px}
.est-bar>i{display:block;height:100%;border-radius:3px;background:var(--grad)}
.destaque{background:rgba(204,35,102,0.05);border:1px solid rgba(204,35,102,0.15);border-radius:12px;padding:14px 16px;margin-bottom:16px;font-size:0.85rem;color:var(--muted)}
.destaque b{color:var(--text)}
.cmp-tile{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.cmp-bar{flex:1;min-width:120px;height:8px;border-radius:4px;background:rgba(0,0,0,0.06);overflow:hidden;position:relative}
.cmp-bar>i{position:absolute;top:0;left:0;height:100%;border-radius:4px}
.cmp-bar .ig{background:linear-gradient(90deg,#f09433,#dc2743)}
.cmp-bar .api{background:#3897f0}
.cmp-legend{font-size:0.7rem;color:var(--dim);display:flex;gap:14px;align-items:center;margin-bottom:12px}
.cmp-legend span{display:flex;align-items:center;gap:5px}
.cmp-legend i{width:10px;height:10px;border-radius:3px;display:inline-block}
footer{text-align:center;padding:30px;color:var(--dim);font-size:0.75rem}
.toolbar{position:fixed;bottom:20px;right:20px;display:flex;gap:8px;z-index:10}
.toolbar button{padding:10px 16px;border-radius:8px;border:none;cursor:pointer;font-size:0.82rem;font-weight:600;box-shadow:var(--shadow);font-family:inherit}
.btn-top{background:#fff;color:var(--text);border:1px solid var(--border)!important}
.obs{font-size:0.72rem;color:var(--dim);margin-top:6px}
@media(max-width:700px){header{padding:12px 16px}.month-head h3{width:100%}.month-chips{margin-left:0}}
"""

JS = """
const RESUMO = JSON.parse(document.getElementById('resumo-data').textContent);
const API = JSON.parse(document.getElementById('api-data').textContent);
const API_BASE = API.base;
const LABEL = {adocao:'Adoção',castracao:'Castração','procura-se':'Procura-se',doacao:'Doações',outros:'Outros'};
const MESES = {1:'Janeiro',2:'Fevereiro',3:'Março',4:'Abril',5:'Maio',6:'Junho',7:'Julho',8:'Agosto',9:'Setembro',10:'Outubro',11:'Novembro',12:'Dezembro'};
const TABELAS = ['adocao','procura_se','eventos','castracao','adotado','home'];
const TAB_LABEL = {adocao:'Adoção (animais disponíveis)',procura_se:'Procura-se (desaparecidos)',eventos:'Eventos / Mutições',castracao:'Castração (agendamentos)',adotado:'Adotados',home:'Avisos (home)'};
const TAB_CAT = {adocao:'adocao',procura_se:'procura-se',eventos:'castracao',castracao:'castracao',adotado:'adocao',home:'doacao'};
const CATS = Object.keys(LABEL);
let view = 'comparacao';
let q = '';

const $ = id => document.getElementById(id);
const num = n => (n == null ? '—' : Number(n).toLocaleString('pt-BR'));
const esc = s => String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,'');
const badge = c => '<span class="badge badge-' + c + '">' + (LABEL[c] || c) + '</span>';
const tipo = t => '<span class="type-pill">' + (t === 'VIDEO' ? 'Vídeo' : t === 'CAROUSEL' ? 'Carrossel' : 'Imagem') + '</span>';
const fmtData = iso => {
  if(!iso) return '—';
  const d = new Date(iso.indexOf('T') >= 0 ? iso : iso + 'T00:00:00');
  const p = n => String(n).padStart(2,'0');
  return p(d.getDate()) + '/' + p(d.getMonth()+1) + '/' + d.getFullYear();
};
const statusPill = (ok, txt) => '<span class="status-pill status-' + (ok ? 'ok' : 'warn') + '">' + txt + '</span>';

// Lista plana de posts (com legenda quando disponivel)
const FLAT = [];
Object.keys(RESUMO.por_ano).forEach(a => Object.values(RESUMO.por_ano[a].meses).forEach(m => m.posts.forEach(p => FLAT.push(p))));

function renderTabs(){
  const el = $('tabs');
  el.innerHTML = '';
  const mk = (key, label, n) => {
    const b = document.createElement('button');
    b.className = 'tab' + (view === key ? ' active' : '');
    b.innerHTML = label + (n != null ? ' <span class="n">' + n + '</span>' : '');
    b.onclick = () => { view = key; renderTabs(); render(); window.scrollTo({top:0,behavior:'smooth'}); };
    el.appendChild(b);
  };
  mk('comparacao', 'Comparação', API.total_registros);
  Object.keys(RESUMO.por_ano).forEach(a => mk(a, a, RESUMO.por_ano[a].quantidade_posts));
}

function card(v, l){ return '<div class="card"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

function contagemCategorias(){
  const c = {};
  FLAT.forEach(p => c[p.categoria] = (c[p.categoria]||0)+1);
  return c;
}

function correspondencias(registros, cat){
  const palavras = new Set();
  registros.forEach(r => {
    let k = (r.nome || r.pet_nome || '').split(/[\\s,;.]+/).map(norm).filter(w => w && w.length > 2);
    if(!k.length && r.titulo){
      k = r.titulo.split(/[\\s,;:.!?()]+/).map(norm).filter(w => w && w.length > 3).slice(0, 3);
    }
    k.forEach(w => palavras.add(w));
  });
  return FLAT.filter(p => p.categoria === cat && Array.from(palavras).some(w => norm(p.legenda||p.titulo||'').includes(w)));
}

function renderComparacao(){
  const cats = contagemCategorias();
  const totalPosts = FLAT.length;
  const totalApi = API.total_registros;
  const anos = RESUMO.por_ano;
  let html = '';

  html += '<div class="destaque"><b>Comparação @grupoamoranimal</b> — ' + totalPosts +
    ' posts do Instagram (resumo-mensal, ' + Object.keys(anos).join(', ') +
    ') x ' + totalApi + ' registros na API do site Amor Animal (api.projetosdinamicos.com.br/amoranimal).<br>' +
    'Coleta da API: ' + API.buscado_em + '. Correspondências são aproximadas, por nome/título.</div>';

  html += '<div class="cards">' +
    card(num(totalPosts), 'Posts no Instagram') +
    card(num(totalApi), 'Registros na API') +
    card(num(Object.keys(anos).length), 'Anos cobertos') +
    card(API.cobertura || '—', 'Período dos registros') +
    '</div>';

  // Tabela de comparação por categoria
  html += '<div class="section-title"><span class="bar"></span>Comparação por categoria</div>';
  html += '<div class="cmp-legend"><span><i class="ig"></i>Posts no Instagram</span><span><i class="api"></i>Registros na API</span></div>';
  html += '<div style="overflow-x:auto"><table><thead><tr>' +
    '<th>Categoria</th><th class="num">Posts IG</th><th class="num">Registros API</th><th>Tabelas da API</th><th>Proporção</th></tr></thead><tbody>';
  const maxVal = Math.max(1, ...Object.values(cats), totalApi);
  CATS.forEach(c => {
    const apiN = TABELAS.filter(t => TAB_CAT[t] === c).reduce((s,t) => s + (API.data[t] ? API.data[t].length : 0), 0);
    const igN = cats[c] || 0;
    const largIg = Math.round(igN/maxVal*100);
    const largApi = Math.round(apiN/maxVal*100);
    const tabelas = TABELAS.filter(t => TAB_CAT[t] === c).map(t => '<span class="type-pill" style="margin-right:4px">' + TAB_LABEL[t] + '</span>').join('');
    html += '<tr><td>' + badge(c) + '</td><td class="num">' + num(igN) + '</td><td class="num">' + num(apiN) + '</td><td>' + (tabelas || '—') + '</td>' +
      '<td><div class="cmp-tile"><div class="cmp-bar"><i class="ig" style="width:' + largIg + '%"></i><i class="api" style="width:' + largApi + '%;left:' + largIg + '%;max-width:' + (100-largIg) + '%"></i></div>' +
      '<span style="font-size:0.7rem;color:var(--dim)">' + igN + ' vs ' + apiN + '</span></div></td></tr>';
  });
  html += '</tbody></table></div>';

  // Comparação por ano (posts IG por categoria x registros API)
  html += '<div class="section-title"><span class="bar"></span>Posts do Instagram por ano (resumo-mensal)</div>';
  html += '<div style="overflow-x:auto"><table><thead><tr><th>Ano</th>' +
    CATS.map(c => '<th class="num">' + LABEL[c] + '</th>').join('') +
    '<th class="num">Total</th></tr></thead><tbody>' +
    Object.keys(anos).map(a => {
      const A = anos[a];
      return '<tr><td><b>' + a + '</b></td>' +
        CATS.map(c => '<td class="num">' + num(A.por_categoria[c]||0) + '</td>').join('') +
        '<td class="num"><b>' + num(A.quantidade_posts) + '</b></td></tr>';
    }).join('') + '</tbody></table></div>';

  // Detalhe por tabela da API
  html += '<div class="section-title"><span class="bar"></span>Detalhes das tabelas da API</div>';
  TABELAS.forEach(t => {
    const recs = API.data[t] || [];
    const cat = TAB_CAT[t];
    const postsCat = FLAT.filter(p => p.categoria === cat).length;
    const correspondem = correspondencias(recs, cat);
    const ok = recs.length > 0;
    html += '<div class="month-block"><div class="month-head"><h3>' + TAB_LABEL[t] + ' <span style="font-size:0.72rem;color:var(--dim)">/' + t + '</span></h3>' +
      '<div class="month-chips">' +
      '<span class="chip"><b>' + recs.length + '</b> registros</span>' +
      '<span class="chip">IG: <b>' + postsCat + '</b> posts</span>' +
      (correspondem.length ? '<span class="chip">' + statusPill(true, correspondem.length + ' correspondência(s)') + '</span>' : '<span class="chip">' + statusPill(false, 'sem correspondência') + '</span>') +
      '</div></div>' +
      (recs.length ? tabelaDetalhe(t, recs, correspondem) : '<div class="info">Sem registros nesta tabela.</div>') +
      '</div>';
  });

  $('view-comparacao').innerHTML = html;
}

function tabelaDetalhe(t, recs, correspondem){
  if(t === 'castracao'){
    const cols = ['Ticket','Tutor','Pet','Espécie','Clínica','Agenda','Status','Origem'];
    let rows = recs.map(r =>
      '<tr><td>' + esc(r.ticket || '—') + '</td><td>' + esc(r.nome || '—') + '</td><td>' + esc(r.nome_pet || r.pet_nome || '—') + '</td>' +
      '<td>' + esc(r.especie || '—') + '</td><td>' + esc(r.clinica || '—') + '</td><td>' + esc(r.agenda || '—') + '</td>' +
      '<td>' + statusPill(r.status === 'ATENDIDO', esc(r.status || '—')) + '</td><td>' + fmtData(r.origem) + '</td></tr>').join('');
    const atendidos = recs.filter(r => r.status === 'ATENDIDO').length;
    return '<div class="info">' + recs.length + ' agendamentos · ' + atendidos + ' atendidos · ' + (recs.length-atendidos) + ' pendentes</div>' +
      '<div style="overflow-x:auto"><table><thead><tr>' + cols.map(c => '<th' + (c==='Ticket'?' class="num"':'') + '>' + c + '</th>').join('') + '</tr></thead><tbody>' + rows + '</tbody></table></div>';
  }
  if(t === 'adocao'){
    const cols = ['Nome','Espécie','Porte','Idade','Contato','Origem','No Instagram'];
    let rows = recs.map(r => {
      const corr = correspondem.filter(p => norm(r.nome||'').length > 2 && norm(p.legenda||p.titulo||'').includes(norm(r.nome)));
      return '<tr><td><b>' + esc(r.nome || '—') + '</b></td><td>' + esc(r.especie || '—') + '</td><td>' + esc(r.porte || '—') + '</td>' +
        '<td>' + esc(r.idade || '—') + '</td><td>' + esc(r.contato || '—') + '</td><td>' + fmtData(r.origem) + '</td>' +
        '<td>' + (corr.length ? corr.map(p => '<a class="link-ig" target="_blank" rel="noopener" href="' + esc(p.url) + '">' + fmtData(p.data) + '</a>').join(' ') : '<span style="color:var(--dim)">—</span>') + '</td></tr>';
    }).join('');
    return '<div style="overflow-x:auto"><table><thead><tr>' + cols.map(c => '<th>' + c + '</th>').join('') + '</tr></thead><tbody>' + rows + '</tbody></table></div>';
  }
  if(t === 'eventos'){
    const cols = ['Título','Data do evento','Origem','No Instagram'];
    let rows = recs.map(r => {
      const kws = (r.titulo||'').split(/[\s,;:.!?()]+/).map(norm).filter(w => w && w.length > 3).slice(0, 2);
      const corr = correspondem.filter(p => kws.some(w => norm(p.legenda||p.titulo||'').includes(w)));
      return '<tr><td>' + esc(r.titulo || '—') + '</td><td>' + fmtData(r.data_evento) + '</td><td>' + fmtData(r.origem) + '</td>' +
        '<td>' + (corr.length ? corr.map(p => '<a class="link-ig" target="_blank" rel="noopener" href="' + esc(p.url) + '">' + fmtData(p.data) + '</a>').join(' ') : '<span style="color:var(--dim)">—</span>') + '</td></tr>';
    }).join('');
    return '<div style="overflow-x:auto"><table><thead><tr>' + cols.map(c => '<th>' + c + '</th>').join('') + '</tr></thead><tbody>' + rows + '</tbody></table></div>';
  }
  if(t === 'home'){
    const cols = ['Título','Mensagem','Origem'];
    let rows = recs.map(r => '<tr><td><b>' + esc(r.titulo || '—') + '</b></td><td>' + esc(r.mensagem || '—') + '</td><td>' + fmtData(r.origem) + '</td></tr>').join('');
    return '<div style="overflow-x:auto"><table><thead><tr>' + cols.map(c => '<th>' + c + '</th>').join('') + '</tr></thead><tbody>' + rows + '</tbody></table></div>';
  }
  // procura_se / adotado (generico)
  const cols = Object.keys(recs[0] || {}).slice(0, 8);
  let rows = recs.map(r => '<tr>' + cols.map(c => '<td>' + esc(typeof r[c] === 'object' ? JSON.stringify(r[c]) : r[c]) + '</td>').join('') + '</tr>').join('');
  return '<div style="overflow-x:auto"><table><thead><tr>' + cols.map(c => '<th>' + esc(c) + '</th>').join('') + '</tr></thead><tbody>' + rows + '</tbody></table></div>';
}

function renderAno(ano){
  const A = RESUMO.por_ano[ano];
  const meses = Object.keys(A.meses);
  let html = '<div class="cards">' +
    card(num(A.quantidade_posts), 'Posts em ' + ano) +
    card(num(A.total_likes), 'Curtidas') +
    card(num(A.total_comentarios), 'Comentários') +
    card(num(A.imagens), 'Imagens') +
    card(num(A.videos), 'Vídeos') +
    card(num(A.carrosseis), 'Carrosséis') +
    '</div>';

  html += '<div class="section-title"><span class="bar"></span>Meses (' + meses.length + ')</div>';

  meses.forEach(m => {
    const M = A.meses[m];
    const [, mm] = m.split('-');
    const nomeMes = MESES[Number(mm)] || m;
    const cats = Object.entries(M.por_categoria).map(([c,n]) => badge(c) + ' ' + n).join(' ');

    let rows = M.posts.map(p => {
      const ok = !q ||
        norm(p.titulo).includes(q) ||
        norm(p.categoria).includes(q) ||
        norm(LABEL[p.categoria]).includes(q);
      if(!ok) return '';
      return '<tr>' +
        '<td class="num">' + num(p.likes) + '</td>' +
        '<td class="num">' + num(p.comentarios) + '</td>' +
        '<td>' + fmtData(p.data) + '</td>' +
        '<td>' + tipo(p.tipo) + '</td>' +
        '<td>' + badge(p.categoria) + '</td>' +
        '<td>' + esc(p.titulo) + '</td>' +
        '<td><a class="link-ig" target="_blank" rel="noopener" href="' + esc(p.url) + '">Ver &#8599;</a></td>' +
        '</tr>';
    }).join('');

    if(q && rows === '') return;

    html += '<div class="month-block"><div class="month-head"><h3>' + nomeMes + ' ' + ano + '</h3>' +
      '<div class="month-chips">' +
      '<span class="chip"><b>' + M.quantidade_posts + '</b> posts</span>' +
      '<span class="chip">&#10084;&#65039; <b>' + num(M.total_likes) + '</b></span>' +
      '<span class="chip">&#128172; <b>' + num(M.total_comentarios) + '</b></span>' +
      (cats ? '<span class="chip">' + cats + '</span>' : '') +
      '</div></div>' +
      '<div style="overflow-x:auto"><table><thead><tr>' +
      '<th class="num">Curtidas</th><th class="num">Com.</th><th>Data</th><th>Tipo</th><th>Categoria</th><th>Título</th><th>Link</th>' +
      '</tr></thead><tbody>' + (rows || '<tr><td colspan="7" style="text-align:center;color:var(--dim)">Nenhuma postagem corresponde ao filtro.</td></tr>') +
      '</tbody></table></div></div>';
  });

  if(q && !meses.some(m => A.meses[m].posts.some(p => norm(p.titulo).includes(q) || norm(p.categoria).includes(q) || norm(LABEL[p.categoria]).includes(q)))){
    html = '<div class="info">Nenhuma postagem em ' + ano + ' corresponde a "' + q + '".</div>';
  }

  $('view-ano').innerHTML = html;
}

function render(){
  renderComparacao();
  const isCmp = view === 'comparacao';
  if(!isCmp) renderAno(view);
  $('view-comparacao').classList.toggle('hidden', !isCmp);
  $('view-ano').classList.toggle('hidden', isCmp);
  $('info').textContent = isCmp
    ? 'Comparação entre ' + FLAT.length + ' posts do Instagram (resumo-mensal) e ' + API.total_registros + ' registros da API.'
    : view + ': ' + (q ? 'linhas correspondentes a "' + q + '".' : '');
}

$('busca').addEventListener('input', e => { q = norm(e.target.value.trim()); render(); });
renderTabs();
render();
"""


def esc(s):
    return str(s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


def fetch_api():
    """Busca dados de todos os endpoints da API, com fallback para cache local."""
    dados = {}
    ok = 0
    for ep in ENDPOINTS:
        cache = os.path.join(CACHE_DIR, ep + '.json')
        try:
            with urllib.request.urlopen(API_BASE + '/' + ep, timeout=25) as r:
                raw = r.read().decode('utf-8')
            dados[ep] = json.loads(raw)
            ok += 1
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(cache, 'w', encoding='utf-8') as f:
                f.write(raw)
        except Exception as e:
            print('AVISO: falha ao buscar /%s (%s); usando cache.' % (ep, e), file=sys.stderr)
            if os.path.exists(cache):
                dados[ep] = json.load(open(cache, encoding='utf-8'))
            else:
                dados[ep] = []
    print('API: %d/%d endpoints buscados com sucesso.' % (ok, len(ENDPOINTS)))
    return dados


def build_html(resumo, api):
    data_json = json.dumps(resumo, ensure_ascii=False).replace('</', '<\\/')
    total_registros = sum(len(api.get(ep, []) or []) for ep in ENDPOINTS)
    datas = [r.get('origem') for ep in ENDPOINTS for r in (api.get(ep) or []) if r.get('origem')]
    datas = [d for d in datas if d]
    cobertura = None
    if datas:
        cobertura = '%s a %s' % (min(datas)[:10], max(datas)[:10])
    api_payload = {'base': API_BASE, 'buscado_em': datetime.now().strftime('%d/%m/%Y %H:%M'),
                   'cobertura': cobertura, 'total_registros': total_registros, 'data': api}
    api_json = json.dumps(api_payload, ensure_ascii=False).replace('</', '<\\/')

    perf = resumo['perfil']
    anos = resumo['por_ano']
    todas_datas = [p['data'][:10] for a in anos.values() for m in a['meses'].values() for p in m['posts']]
    primeiro = min(todas_datas) if todas_datas else '—'
    ultimo = max(todas_datas) if todas_datas else '—'
    buscado = resumo.get('buscado_em', '')
    try:
        buscado_fmt = datetime.fromisoformat(buscado).strftime('%d/%m/%Y %H:%M')
    except Exception:
        buscado_fmt = buscado

    sub = ('@%s &middot; %s &middot; Instagram %s a %s (%s posts de %s) &middot; '
           'API Amor Animal: %s registros (%s) &middot; gerado em %s') % (
        esc(perf['username']), esc(perf['nome']), esc(primeiro), esc(ultimo),
        resumo['estatisticas']['posts_coletados'], perf['total_posts'],
        total_registros, cobertura or 'n/d', buscado_fmt)

    return ('<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n<meta charset="UTF-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
            '<title>@grupoamoranimal - Comparação Instagram x API</title>\n<style>' + CSS +
            '</style>\n</head>\n<body>\n<header>\n<div class="ig-icon">&#128062;</div>\n'
            '<h1>@grupoamoranimal - Comparação Instagram x API Amor Animal</h1>\n'
            '<div class="sub">' + sub + '</div>\n</header>\n<div class="container">\n'
            '<div class="tabs" id="tabs"></div>\n'
            '<div class="controls"><input type="text" id="busca" placeholder="Filtrar postagens na aba do ano (título ou categoria)..."></div>\n'
            '<div class="info" id="info"></div>\n'
            '<div id="view-comparacao"></div>\n'
            '<div id="view-ano" class="hidden"></div>\n</div>\n'
            '<footer>Gerado automaticamente a partir do resumo-mensal (Instagram) e da API ' + esc(API_BASE) + '</footer>\n'
            '<div class="toolbar"><button class="btn-top" onclick="window.scrollTo({top:0,behavior:\'smooth\'})">Topo</button></div>\n'
            '<script type="application/json" id="resumo-data">' + data_json + '</script>\n'
            '<script type="application/json" id="api-data">' + api_json + '</script>\n'
            '<script>' + JS + '</script>\n</body>\n</html>')


def merge_legendas(resumo):
    """Acrescenta a legenda completa aos posts do resumo (do dataset imginn), quando houver."""
    if not os.path.exists(DATASET_JSON):
        return resumo
    try:
        ds = json.load(open(DATASET_JSON, encoding='utf-8'))
    except Exception:
        return resumo
    legenda = {p['code']: p.get('legenda') for p in ds.get('posts', []) if p.get('legenda')}
    count = 0
    for a in resumo['por_ano'].values():
        for m in a['meses'].values():
            for p in m['posts']:
                if p.get('code') in legenda and not p.get('legenda'):
                    p['legenda'] = legenda[p['code']]
                    count += 1
    print('Legendas mescladas: %d posts.' % count)
    return resumo


def main():
    if not os.path.exists(RESUMO_JSON):
        print('ERRO: %s nao encontrado. Rode resumo-mensal.py antes.' % RESUMO_JSON)
        raise SystemExit(1)
    resumo = json.load(open(RESUMO_JSON, encoding='utf-8'))
    resumo = merge_legendas(resumo)
    api = fetch_api()
    html = build_html(resumo, api)
    with open(OUT_HTML, 'w', encoding='utf-8') as f:
        f.write(html)
    print('Pagina gerada: %s' % OUT_HTML)
    print('Tamanho: %.1f KB' % (len(html.encode('utf-8')) / 1024))


if __name__ == '__main__':
    main()

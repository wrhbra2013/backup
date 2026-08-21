#!/usr/bin/env python3
"""pagina-dashboard.py — Gera pagina HTML (dashboard) de simulacao offline
para o site amoranimal.ong.br, unindo o resumo-mensal as fotos locais.

Le instagram-grupoamoranimal-resumo-mensal.json (mais recente) e gera
instagram-grupoamoranimal-dashboard.html com:
  * Header replicando o site oficial (amoranimal.ong.br)
  * KPIs (posts, curtidas, comentarios, categorias, por ano)
  * Posts em grade/cards com as fotos locais de img-resumo-mensal
  * Busca e filtro por categoria, visao por ano/mes

Uso:
  python3 pagina-dashboard.py
"""
import json
import os
from datetime import datetime

DIR = os.path.dirname(os.path.abspath(__file__))
IN_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.json')
IMG_DIR = os.path.join(DIR, 'img-resumo-mensal')
OUT_HTML = os.path.join(DIR, 'instagram-grupoamoranimal-dashboard.html')

MESES_PT = {1: 'Janeiro', 2: 'Fevereiro', 3: 'Março', 4: 'Abril', 5: 'Maio', 6: 'Junho',
            7: 'Julho', 8: 'Agosto', 9: 'Setembro', 10: 'Outubro', 11: 'Novembro', 12: 'Dezembro'}
MESES_CURTO = {1: 'Jan', 2: 'Fev', 3: 'Mar', 4: 'Abr', 5: 'Mai', 6: 'Jun',
               7: 'Jul', 8: 'Ago', 9: 'Set', 10: 'Out', 11: 'Nov', 12: 'Dez'}

CSS = """
:root{
  --brand-teal:#0d9488;--brand-teal-dark:#0f766e;--brand-teal-light:#14b8a6;
  --brand-coral:#f97316;--brand-coral-2:#ea580c;--brand-purple:#8b5cf6;
  --brand-pink:#ec4899;--brand-blue:#0ea5e9;--brand-blue-dark:#0284c7;
  --bg-color:#f8fafc;--bg-alt:#e2e8f0;--text-color:#1e293b;--muted-color:#64748b;
  --container-bg:#ffffff;--container-shadow:0 4px 20px rgba(0,0,0,0.08);--container-border:#e2e8f0;
  --border-color:#e2e8f0;--heading-color:var(--brand-coral);
  --nav-bg:#0d9488;--nav-text:#fff;--nav-gradient:linear-gradient(135deg,#0d9488,#0f766e);
  --button-bg:linear-gradient(135deg,#0d9488,#0f766e);--button-text:#fff;
  --c-adocao:#0a7d4f;--bg-adocao:rgba(10,125,79,0.12);
  --c-castracao:#1d4ed8;--bg-castracao:rgba(29,78,216,0.12);
  --c-procura:#c2410c;--bg-procura:rgba(194,65,12,0.12);
  --c-doacao:#a21caf;--bg-doacao:rgba(162,28,175,0.12);
  --c-outros:#6b7280;--bg-outros:rgba(107,114,128,0.14);
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',system-ui,-apple-system,Tahoma,Arial,sans-serif;background:var(--bg-color);color:var(--text-color);line-height:1.6}
img{max-width:100%;display:block}

/* Header do site */
.site-header{background:var(--nav-gradient);color:var(--nav-text);position:sticky;top:0;z-index:100;box-shadow:0 2px 12px rgba(0,0,0,0.15)}
.header-inner{max-width:1250px;margin:0 auto;padding:0 1.5rem;display:flex;align-items:center;gap:1.5rem;height:64px}
.header-logo{display:flex;align-items:center;gap:10px;color:#fff;text-decoration:none}
.header-logo-icon{width:38px;height:38px;border-radius:50%;background:linear-gradient(135deg,#f97316,#ec4899);display:flex;align-items:center;justify-content:center;font-size:1.2rem}
.header-logo-text{font-weight:700;font-size:1.05rem}
.header-nav{display:flex;gap:1.1rem;margin-left:auto;align-items:center;flex-wrap:wrap}
.header-nav a{color:rgba(255,255,255,0.92);text-decoration:none;font-size:0.9rem;font-weight:600;transition:opacity .2s}
.header-nav a:hover{opacity:.8}
.header-badge{background:#fff;color:var(--brand-teal);font-size:0.68rem;font-weight:800;padding:4px 10px;border-radius:20px;letter-spacing:0.5px}

/* Banner de simulacao */
.sim-banner{background:linear-gradient(135deg,#fffbeb,#fef3c7);border-bottom:1px solid #fde68a;color:#92400e}
.sim-banner-inner{max-width:1250px;margin:0 auto;padding:10px 1.5rem;font-size:0.85rem;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.sim-banner b{color:#78350f}

.container{max-width:1250px;margin:0 auto;padding:20px 1.5rem 60px}
.page-title{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:4px}
.page-title h1{font-size:1.7rem;color:var(--text-color)}
.page-title h1 span{background:var(--grad,linear-gradient(45deg,#f97316,#ec4899));-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.sub{font-size:0.8rem;color:var(--muted-color);margin-bottom:18px}

/* KPIs */
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:14px;margin-bottom:24px}
.kpi{background:var(--container-bg);border:1px solid var(--border-color);border-radius:14px;padding:16px 18px;box-shadow:var(--container-shadow);transition:transform .2s}
.kpi:hover{transform:translateY(-3px)}
.kpi .k-ico{font-size:1.4rem}
.kpi .k-val{font-size:1.6rem;font-weight:800;line-height:1.2;margin-top:6px}
.kpi .k-lbl{font-size:0.72rem;color:var(--muted-color);text-transform:uppercase;letter-spacing:0.5px;margin-top:2px}
.kpi.grad .k-val{background:linear-gradient(45deg,#0d9488,#0ea5e9);-webkit-background-clip:text;-webkit-text-fill-color:transparent}

/* Tabs */
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0}
.tab{padding:8px 16px;border-radius:20px;border:1px solid var(--border-color);background:var(--container-bg);cursor:pointer;font-size:0.85rem;font-weight:600;font-family:inherit;color:var(--muted-color);transition:all .15s;display:flex;align-items:center;gap:6px}
.tab .n{font-size:0.7rem;background:rgba(0,0,0,0.06);padding:1px 7px;border-radius:10px}
.tab:hover{transform:translateY(-1px);box-shadow:var(--container-shadow)}
.tab.active{background:var(--button-bg);color:#fff;border-color:transparent}
.tab.active .n{background:rgba(255,255,255,0.25)}

/* Busca */
.controls{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:18px}
.controls input{flex:1;min-width:220px;padding:11px 16px;border-radius:12px;border:2px solid var(--border-color);font-family:inherit;font-size:0.92rem;outline:none;background:var(--container-bg);color:var(--text-color)}
.controls input:focus{border-color:var(--brand-teal)}
.info{font-size:0.8rem;color:var(--muted-color);margin-bottom:14px}

/* Grade de posts */
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:16px}
.card-hide{display:none!important}
.post-card{background:var(--container-bg);border:1px solid var(--border-color);border-radius:14px;overflow:hidden;box-shadow:var(--container-shadow);transition:transform .2s,box-shadow .2s;display:flex;flex-direction:column}
.post-card:hover{transform:translateY(-4px);box-shadow:0 8px 26px rgba(0,0,0,0.14)}
.post-img{position:relative;height:220px;overflow:hidden;background:linear-gradient(135deg,#cffafe,#ffe4e6);display:flex;align-items:center;justify-content:center;font-size:3.4rem}
.post-img img{width:100%;height:100%;object-fit:cover;transition:transform .4s}
.post-card:hover .post-img img{transform:scale(1.07)}
.post-date{position:absolute;top:10px;left:10px;background:var(--brand-teal);color:#fff;font-size:0.7rem;font-weight:700;padding:4px 10px;border-radius:20px}
.post-type{position:absolute;top:10px;right:10px;background:rgba(255,255,255,0.92);color:var(--text-color);font-size:0.68rem;font-weight:800;padding:3px 8px;border-radius:12px;text-transform:uppercase;letter-spacing:0.4px}
.post-body{padding:14px 16px;display:flex;flex-direction:column;flex:1}
.post-title{font-size:0.92rem;font-weight:600;line-height:1.45;margin-bottom:10px;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.post-foot{display:flex;align-items:center;gap:8px;margin-top:auto;padding-top:10px;border-top:1px solid rgba(0,0,0,0.05);font-size:0.76rem;color:var(--muted-color);flex-wrap:wrap}
.post-foot .stat{display:inline-flex;align-items:center;gap:4px}
.link-post{margin-left:auto;color:var(--brand-teal);font-weight:700;text-decoration:none;font-size:0.8rem;white-space:nowrap}
.link-post:hover{text-decoration:underline}

/* Badges */
.badge{font-size:0.62rem;text-transform:uppercase;letter-spacing:0.5px;padding:2px 8px;border-radius:20px;font-weight:700;white-space:nowrap;text-decoration:none}
.badge-adocao{background:var(--bg-adocao);color:var(--c-adocao)}
.badge-castracao{background:var(--bg-castracao);color:var(--c-castracao)}
.badge-procura-se{background:var(--bg-procura);color:var(--c-procura)}
.badge-doacao{background:var(--bg-doacao);color:var(--c-doacao)}
.badge-outros{background:var(--bg-outros);color:var(--c-outros)}

/* Categorias */
.cat-row{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:8px}
.est-bar{flex:1;min-width:120px;height:10px;border-radius:5px;background:rgba(0,0,0,0.06);overflow:hidden}
.est-bar>i{display:block;height:100%;border-radius:5px}

/* Tabela anos/meses */
table{width:100%;border-collapse:collapse;background:var(--container-bg);border:1px solid var(--border-color);border-radius:12px;overflow:hidden;box-shadow:var(--container-shadow);font-size:0.82rem}
thead th{text-align:left;font-size:0.68rem;text-transform:uppercase;letter-spacing:0.6px;color:var(--muted-color);padding:10px 12px;background:rgba(0,0,0,0.03);border-bottom:1px solid var(--border-color);white-space:nowrap}
tbody td{padding:9px 12px;border-bottom:1px solid rgba(0,0,0,0.04);vertical-align:middle}
tbody tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(13,148,136,0.05)}
td.num,th.num{text-align:right}
.overflow{overflow-x:auto}
.section-title{font-size:1.05rem;font-weight:700;margin:24px 0 12px;display:flex;align-items:center;gap:8px}
.section-title .bar{width:4px;height:18px;border-radius:2px;background:var(--button-bg)}

/* Footer */
.site-footer{background:linear-gradient(135deg,#1e293b,#334155);color:#e2e8f0;padding:2.5rem 0}
.footer-inner{max-width:1250px;margin:0 auto;padding:0 1.5rem;text-align:center;font-size:0.85rem}
.site-footer a{color:var(--brand-teal-light);text-decoration:none}

@media(max-width:768px){.header-nav{display:none}.kpis{grid-template-columns:repeat(2,1fr)}.page-title h1{font-size:1.3rem}}
"""

JS = """
const RESUMO = JSON.parse(document.getElementById('resumo-data').textContent);
const FOTOS = RESUMO._fotos || [];
const FOTO_SET = new Set(FOTOS);
const LABEL = {adocao:'Adoção',castracao:'Castração','procura-se':'Procura-se',doacao:'Doações',outros:'Outros'};
const MESES = {1:'Janeiro',2:'Fevereiro',3:'Março',4:'Abril',5:'Maio',6:'Junho',7:'Julho',8:'Agosto',9:'Setembro',10:'Outubro',11:'Novembro',12:'Dezembro'};
const MESES_C = {1:'Jan',2:'Fev',3:'Mar',4:'Abr',5:'Mai',6:'Jun',7:'Jul',8:'Ago',9:'Set',10:'Out',11:'Nov',12:'Dez'};
const CATS = Object.keys(LABEL);
let view = 'dashboard';
let catFiltro = 'todas';
let q = '';

const $ = id => document.getElementById(id);
const num = n => (n == null ? '—' : Number(n).toLocaleString('pt-BR'));
const esc = s => String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,'');
const badge = c => '<a class="badge badge-' + c + '" data-cat="' + c + '" href="#">' + (LABEL[c] || c) + '</a>';
const tipo = t => t === 'VIDEO' ? 'Vídeo' : t === 'CAROUSEL' ? 'Carrossel' : 'Imagem';
const fmtData = iso => {
  if(!iso) return '—';
  const d = new Date(iso.indexOf('T') >= 0 ? iso : iso + 'T00:00:00');
  const p = n => String(n).padStart(2,'0');
  return p(d.getDate()) + '/' + p(d.getMonth()+1) + '/' + d.getFullYear();
};
const imgSrc = code => FOTO_SET.has(code) ? 'img-resumo-mensal/' + code + '.jpg' : null;

function todosPosts(){
  const out = [];
  Object.values(RESUMO.por_ano).forEach(a => Object.values(a.meses).forEach(m => m.posts.forEach(p => out.push(p))));
  return out;
}

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
  mk('dashboard', 'Dashboard', RESUMO.estatisticas.posts_coletados);
  Object.keys(RESUMO.por_ano).forEach(a => mk(a, a, RESUMO.por_ano[a].quantidade_posts));
}

function kpi(ico, val, lbl, grad){
  return '<div class="kpi' + (grad ? ' grad' : '') + '"><div class="k-ico">' + ico + '</div>' +
    '<div class="k-val">' + val + '</div><div class="k-lbl">' + lbl + '</div></div>';
}

function renderDashboard(){
  const e = RESUMO.estatisticas, p = RESUMO.perfil;
  const anos = RESUMO.por_ano;
  const totalCats = {};
  Object.values(anos).forEach(a => Object.entries(a.por_categoria).forEach(([c,n]) => totalCats[c]=(totalCats[c]||0)+n));
  const maxCat = Math.max(1, ...Object.values(totalCats));
  let html = '';

  html += '<div class="kpis">' +
    kpi('📸', num(e.posts_coletados), 'Posts analisados', true) +
    kpi('❤️', num(e.total_likes), 'Curtidas', true) +
    kpi('💬', num(e.total_comentarios), 'Comentários', true) +
    kpi('📈', num(e.media_likes_por_post), 'Média curtidas') +
    kpi('📊', num(e.media_comentarios_por_post), 'Média comentários') +
    kpi('👥', num(p.seguidores), 'Seguidores') +
    kpi('🐾', num(p.total_posts), 'Posts no perfil') +
    '</div>';

  html += '<div class="section-title"><span class="bar"></span>Categorias (' + Object.values(totalCats).reduce((a,b)=>a+b,0) + ' posts)</div>';
  html += CATS.filter(c => totalCats[c]).sort((a,b)=>totalCats[b]-totalCats[a]).map(c =>
    '<div class="cat-row"><span>' + badge(c) + '</span>' +
    '<span style="font-size:0.85rem;color:var(--muted-color);min-width:44px">' + num(totalCats[c]) + ' (' + Math.round(totalCats[c]/e.posts_coletados*100) + '%)</span>' +
    '<div class="est-bar"><i style="width:' + Math.round(totalCats[c]/maxCat*100) + '%;background:var(--button-bg)"></i></div></div>'
  ).join('');

  html += '<div class="section-title"><span class="bar"></span>Visão por ano</div>';
  html += '<div class="overflow"><table><thead><tr>' +
    '<th>Ano</th><th class="num">Posts</th><th class="num">Curtidas</th><th class="num">Comentários</th>' +
    '<th class="num">Imagens</th><th class="num">Vídeos</th><th class="num">Carrosséis</th>' +
    '<th class="num">Média curt.</th><th class="num">Média com.</th><th>Categorias</th></tr></thead><tbody>' +
    Object.keys(anos).map(a => {
      const A = anos[a];
      const top = Object.entries(A.por_categoria).slice(0,3).map(([c,n]) => badge(c) + ' ' + n).join(' ');
      return '<tr><td><b>' + a + '</b></td><td class="num">' + num(A.quantidade_posts) + '</td>' +
        '<td class="num">' + num(A.total_likes) + '</td><td class="num">' + num(A.total_comentarios) + '</td>' +
        '<td class="num">' + num(A.imagens) + '</td><td class="num">' + num(A.videos) + '</td>' +
        '<td class="num">' + num(A.carrosseis) + '</td><td class="num">' + num(A.media_likes_por_post) + '</td>' +
        '<td class="num">' + num(A.media_comentarios_por_post) + '</td><td>' + top + '</td></tr>';
    }).join('') + '</tbody></table></div>';

  $('view-dashboard').innerHTML = html;
}

function postCard(p){
  const src = imgSrc(p.code);
  const img = src ? '<img loading="lazy" src="' + esc(src) + '" alt="' + esc(p.titulo) + '">' : '<span>🐾</span>';
  return '<div class="post-card" data-busca="' + esc(norm((p.titulo||'') + ' ' + (p.categoria||'') + ' ' + (LABEL[p.categoria]||''))) + '" data-cat="' + esc(p.categoria) + '">' +
    '<div class="post-img">' + img +
    '<span class="post-date">' + fmtData(p.data) + '</span>' +
    '<span class="post-type">' + tipo(p.tipo) + '</span></div>' +
    '<div class="post-body">' +
    '<div class="post-title">' + esc(p.titulo) + '</div>' +
    '<div class="post-foot"><span class="badge badge-' + p.categoria + '">' + (LABEL[p.categoria] || p.categoria) + '</span>' +
    '<span class="stat">❤️ ' + num(p.likes) + '</span>' +
    '<span class="stat">💬 ' + num(p.comentarios) + '</span>' +
    '<a class="link-post" target="_blank" rel="noopener" href="' + esc(p.url) + '">Ver ↗</a></div></div></div>';
}

function renderAno(ano){
  const A = RESUMO.por_ano[ano];
  const meses = Object.keys(A.meses);
  const todos = [];
  meses.forEach(m => A.meses[m].posts.forEach(p => todos.push(Object.assign({mes:m}, p))));
  const filtrados = todos.filter(p => {
    if(catFiltro !== 'todas' && p.categoria !== catFiltro) return false;
    if(q && !norm((p.titulo||'') + ' ' + (p.categoria||'') + ' ' + (LABEL[p.categoria]||'')).includes(q)) return false;
    return true;
  });
  let html = '<div class="kpis">' +
    kpi('📸', num(A.quantidade_posts), 'Posts em ' + ano, true) +
    kpi('❤️', num(A.total_likes), 'Curtidas') +
    kpi('💬', num(A.total_comentarios), 'Comentários') +
    kpi('🖼️', num(A.imagens), 'Imagens') +
    kpi('🎬', num(A.videos), 'Vídeos') +
    kpi('🎠', num(A.carrosseis), 'Carrosséis') +
    '</div>';

  html += '<div class="section-title"><span class="bar"></span>Meses (' + meses.length + ')</div>';
  html += '<div class="overflow"><table><thead><tr>' +
    '<th>Mês</th><th class="num">Posts</th><th class="num">Curtidas</th><th class="num">Coment.</th>' +
    '<th class="num">Imagens</th><th class="num">Vídeos</th><th class="num">Carrosséis</th><th>Categorias</th></tr></thead><tbody>' +
    meses.map(m => {
      const M = A.meses[m];
      const [, mm] = m.split('-');
      const cats = Object.entries(M.por_categoria).map(([c,n]) => badge(c) + ' ' + n).join(' ');
      return '<tr><td><b>' + (MESES[Number(mm)] || m) + ' ' + ano + '</b></td><td class="num">' + num(M.quantidade_posts) + '</td>' +
        '<td class="num">' + num(M.total_likes) + '</td><td class="num">' + num(M.total_comentarios) + '</td>' +
        '<td class="num">' + num(M.imagens) + '</td><td class="num">' + num(M.videos) + '</td>' +
        '<td class="num">' + num(M.carrosseis) + '</td><td>' + cats + '</td></tr>';
    }).join('') + '</tbody></table></div>';

  html += '<div class="section-title"><span class="bar"></span>Posts (' + filtrados.length + (q ? ' de ' + todos.length : '') + ')</div>';
  html += '<div class="grid">' + (filtrados.map(postCard).join('') ||
    '<div class="info" style="grid-column:1/-1">Nenhuma postagem corresponde ao filtro.</div>') + '</div>';
  $('view-ano').innerHTML = html;
}

function render(){
  renderDashboard();
  renderAno(view);
  const isDash = view === 'dashboard';
  $('view-dashboard').classList.toggle('hidden', !isDash);
  $('view-ano').classList.toggle('hidden', isDash);
  const dados = isDash ? RESUMO.estatisticas.posts_coletados : document.querySelectorAll('#view-ano .post-card').length;
  $('info').textContent = isDash
    ? 'Visão geral dos ' + RESUMO.estatisticas.posts_coletados + ' posts coletados (unidos às ' + FOTOS.length + ' fotos locais de img-resumo-mensal).'
    : view + ': ' + dados + ' postagens' + (catFiltro !== 'todas' ? ' em ' + LABEL[catFiltro] : '') + (q ? ' para "' + q + '"' : '') + '.';
}

$('busca').addEventListener('input', e => { q = norm(e.target.value.trim()); render(); });
document.addEventListener('click', e => {
  const b = e.target.closest('[data-cat]');
  if(!b) return;
  e.preventDefault();
  const c = b.getAttribute('data-cat');
  if(b.classList.contains('badge')){
    catFiltro = (catFiltro === c && view !== 'dashboard') ? 'todas' : c;
    if(view === 'dashboard') view = Object.keys(RESUMO.por_ano)[0];
    renderTabs();
    render();
    document.querySelector('#view-ano .grid').scrollIntoView({behavior:'smooth'});
  }
});
renderTabs();
render();
"""


def build_html(resumo, fotos):
    esc_py = lambda s: str(s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    data = dict(resumo)
    data['_fotos'] = sorted(fotos)
    data_json = json.dumps(data, ensure_ascii=False).replace('</', '<\\/')
    buscado = resumo.get('buscado_em', '')
    try:
        buscado_fmt = datetime.fromisoformat(buscado).strftime('%d/%m/%Y %H:%M')
    except Exception:
        buscado_fmt = buscado
    perf = resumo['perfil']
    est = resumo['estatisticas']
    sub = ('Dashboard simulado de <a href="https://amoranimal.ong.br" target="_blank" rel="noopener">amoranimal.ong.br</a> &middot; '
           'dados de @%s &middot; %s posts &middot; %s fotos locais &middot; gerado em %s') % (
        esc_py(perf['username']), est['posts_coletados'], len(fotos), buscado_fmt)
    return ('<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n<meta charset="UTF-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
            '<title>Amor Animal Marília — Dashboard simulado (offline)</title>\n<style>' + CSS +
            '</style>\n</head>\n<body>\n'
            '<header class="site-header"><div class="header-inner">'
            '<a class="header-logo" href="#"><span class="header-logo-icon">🐶</span><span class="header-logo-text">ONG Amor Animal Marília</span></a>'
            '<nav class="header-nav"><a href="#dashboard">Dashboard</a><a href="#anos">Por Ano</a>'
            '<a href="https://www.instagram.com/grupoamoranimal/" target="_blank" rel="noopener">Instagram</a>'
            '<span class="header-badge">SIMULAÇÃO OFFLINE</span></nav></div></header>\n'
            '<div class="sim-banner"><div class="sim-banner-inner">🔬 <b>Página offline de simulação.</b> '
            'Dashboard do site populado com o resumo-mensal do Instagram @grupoamoranimal — '
            'as fotos são locais (img-resumo-mensal) e nenhum dado sai da sua máquina.</div></div>\n'
            '<div class="container" id="dashboard">\n'
            '<div class="page-title"><h1><span>Dashboard</span> Amor Animal Marília</h1></div>\n'
            '<div class="sub">' + sub + '</div>\n'
            '<div class="tabs" id="tabs"></div>\n'
            '<div class="controls"><input type="text" id="busca" placeholder="Buscar por título ou categoria..."></div>\n'
            '<div class="info" id="info"></div>\n'
            '<div id="view-dashboard"></div>\n'
            '<div id="view-ano" class="hidden"></div>\n'
            '</div>\n'
            '<footer class="site-footer"><div class="footer-inner">'
            '<p><b>ONG Amor Animal Marília</b> — página OFFLINE de simulação do dashboard</p>'
            '<p style="margin-top:8px;opacity:.8">Dados públicos do Instagram @grupoamoranimal &middot; '
            'Fonte: instagram-grupoamoranimal-resumo-mensal.json + img-resumo-mensal &middot; '
            'Réplica visual de <a href="https://amoranimal.ong.br" target="_blank" rel="noopener">amoranimal.ong.br</a> &middot; '
            'Nenhum dado foi enviado à API real.</p></div></footer>\n'
            '<script type="application/json" id="resumo-data">' + data_json + '</script>\n'
            '<script>' + JS + '</script>\n</body>\n</html>')


def main():
    if not os.path.exists(IN_JSON):
        print('ERRO: %s nao encontrado. Rode resumo-mensal.py antes.' % IN_JSON)
        raise SystemExit(1)
    resumo = json.load(open(IN_JSON, encoding='utf-8'))
    fotos = [f[:-4] for f in os.listdir(IMG_DIR) if f.endswith('.jpg')] if os.path.isdir(IMG_DIR) else []
    html = build_html(resumo, fotos)
    with open(OUT_HTML, 'w', encoding='utf-8') as f:
        f.write(html)
    print('Pagina gerada: %s' % OUT_HTML)
    print('Posts: %d | Fotos locais: %d | Tamanho: %.1f KB' % (
        resumo['estatisticas']['posts_coletados'], len(fotos), len(html.encode('utf-8')) / 1024))


if __name__ == '__main__':
    main()

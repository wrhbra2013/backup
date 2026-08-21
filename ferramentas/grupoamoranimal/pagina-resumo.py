#!/usr/bin/env python3
"""pagina-resumo.py — Gera pagina HTML com dashboard e tabelas por ano/mês.

Le instagram-grupoamoranimal-resumo-mensal.json (gerado por resumo-mensal.py)
e gera instagram-grupoamoranimal-resumo-mensal.html com:
  * Dashboard (estatísticas gerais, perfil, tabela por ano, categorias)
  * Menu por ano, com cada ano dividido em meses (tabelas de posts)

Uso:
  python3 pagina-resumo.py
"""
import json
import os
from datetime import datetime

DIR = os.path.dirname(os.path.abspath(__file__))
IN_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.json')
OUT_HTML = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.html')

MESES_PT = {1: 'Janeiro', 2: 'Fevereiro', 3: 'Março', 4: 'Abril', 5: 'Maio', 6: 'Junho',
            7: 'Julho', 8: 'Agosto', 9: 'Setembro', 10: 'Outubro', 11: 'Novembro', 12: 'Dezembro'}

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
.profile-card{display:grid;grid-template-columns:auto 1fr;gap:14px;background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:16px;box-shadow:0 1px 3px rgba(0,0,0,0.05);align-items:center}
.avatar{width:64px;height:64px;border-radius:50%;background:var(--grad);display:flex;align-items:center;justify-content:center;font-size:1.8rem;color:#fff}
.profile-card h3{font-size:1.05rem}
.profile-card .usr{color:var(--dim);font-size:0.8rem;font-weight:600}
.profile-card .bio{color:var(--muted);font-size:0.8rem;margin-top:4px;white-space:pre-wrap}
.profile-stats{display:flex;gap:18px;margin-top:10px;flex-wrap:wrap}
.profile-stats span{font-size:0.78rem;color:var(--muted)}
.profile-stats b{color:var(--text)}
.verified{display:inline-block;background:#3897f0;color:#fff;font-size:0.62rem;padding:1px 7px;border-radius:10px;margin-left:6px;vertical-align:2px}
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
footer{text-align:center;padding:30px;color:var(--dim);font-size:0.75rem}
.est-bar{height:6px;border-radius:3px;background:rgba(0,0,0,0.05);overflow:hidden;min-width:90px}
.est-bar>i{display:block;height:100%;border-radius:3px;background:var(--grad)}
.toolbar{position:fixed;bottom:20px;right:20px;display:flex;gap:8px;z-index:10}
.toolbar button{padding:10px 16px;border-radius:8px;border:none;cursor:pointer;font-size:0.82rem;font-weight:600;box-shadow:var(--shadow);font-family:inherit}
.btn-top{background:#fff;color:var(--text);border:1px solid var(--border)!important}
@media(max-width:700px){header{padding:12px 16px}.month-head h3{width:100%}.month-chips{margin-left:0}}
"""

JS = """
const RESUMO = JSON.parse(document.getElementById('resumo-data').textContent);
const LABEL = {adocao:'Adoção',castracao:'Castração','procura-se':'Procura-se',doacao:'Doações',outros:'Outros'};
const MESES = {1:'Janeiro',2:'Fevereiro',3:'Março',4:'Abril',5:'Maio',6:'Junho',7:'Julho',8:'Agosto',9:'Setembro',10:'Outubro',11:'Novembro',12:'Dezembro'};
const CATS = Object.keys(LABEL);
let view = 'dashboard';
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

function card(v, l){
  return '<div class="card"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>';
}

function renderDashboard(){
  const e = RESUMO.estatisticas, p = RESUMO.perfil, anos = RESUMO.por_ano;
  let html = '';

  // Perfil
  const y = Object.values(anos).reduce((s,a)=>s+a.quantidade_posts,0);
  const totalCats = {};
  Object.values(anos).forEach(a => Object.entries(a.por_categoria).forEach(([c,n]) => totalCats[c]=(totalCats[c]||0)+n));
  html += '<div class="profile-card"><div class="avatar">&#128062;</div><div><h3>' + esc(p.nome) +
    (p.eh_verificado ? '<span class="verified">&#10003; Verificado</span>' : '') + '</h3>' +
    '<div class="usr">@' + esc(p.username) + '</div>' +
    (p.bio ? '<div class="bio">' + esc(p.bio) + '</div>' : '') +
    '<div class="profile-stats"><span><b>' + num(p.seguidores) + '</b> seguidores</span>' +
    '<span><b>' + num(p.seguindo) + '</b> seguindo</span>' +
    '<span><b>' + num(p.total_posts) + '</b> posts no perfil</span>' +
    '<span><b>' + num(y) + '</b> posts analisados (' + (p.total_posts ? Math.round(y/p.total_posts*100) : 0) + '%)</span></div></div></div>';

  html += '<div class="section-title"><span class="bar"></span>Estatísticas gerais</div>';
  html += '<div class="cards">' +
    card(num(e.posts_coletados), 'Posts coletados') +
    card(num(e.total_likes), 'Total de curtidas') +
    card(num(e.total_comentarios), 'Total de comentários') +
    card(num(e.media_likes_por_post), 'Média de curtidas') +
    card(num(e.media_comentarios_por_post), 'Média de comentários') +
    '</div>';

  // Tabela por ano
  html += '<div class="section-title"><span class="bar"></span>Visão por ano</div>';
  html += '<div style="overflow-x:auto"><table><thead><tr>' +
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

  // Categorias
  html += '<div class="section-title"><span class="bar"></span>Categorias</div>';
  html += '<div style="overflow-x:auto"><table><thead><tr><th>Categoria</th><th class="num">Posts</th><th class="num">%</th><th>Distribuição</th></tr></thead><tbody>';
  const total = e.posts_coletados || 1;
  CATS.filter(c => totalCats[c]).sort((a,b)=>totalCats[b]-totalCats[a]).forEach(c => {
    const n = totalCats[c];
    html += '<tr><td>' + badge(c) + '</td><td class="num">' + num(n) + '</td><td class="num">' + Math.round(n/total*100) + '%</td>' +
      '<td><div class="est-bar"><i style="width:' + Math.round(n/total*100) + '%"></i></div></td></tr>';
  });
  html += '</tbody></table></div>';

  html += '<div class="section-title"><span class="bar"></span>Categorias por ano</div>';
  html += '<div style="overflow-x:auto"><table><thead><tr><th>Ano</th>' +
    CATS.map(c => '<th class="num">' + LABEL[c] + '</th>').join('') + '</tr></thead><tbody>' +
    Object.keys(anos).map(a => {
      const A = anos[a];
      return '<tr><td><b>' + a + '</b></td>' + CATS.map(c => '<td class="num">' + num(A.por_categoria[c]||0) + '</td>').join('') + '</tr>';
    }).join('') + '</tbody></table></div>';

  $('view-dashboard').innerHTML = html;
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

    if(q && rows === '') return; // mes sem correspondencia escondido

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
  renderDashboard();
  renderAno(view);
  const isDash = view === 'dashboard';
  $('view-dashboard').classList.toggle('hidden', !isDash);
  $('view-ano').classList.toggle('hidden', isDash);
  const encontrados = isDash ? 0 : Array.from(document.querySelectorAll('#view-ano tbody tr')).length;
  $('info').textContent = isDash
    ? 'Visão geral dos ' + RESUMO.estatisticas.posts_coletados + ' posts coletados.'
    : view + ': ' + (q ? encontrados + ' linhas correspondentes a "' + q + '".' : '');
}

$('busca').addEventListener('input', e => { q = norm(e.target.value.trim()); render(); });
renderTabs();
render();
"""


def build_html(resumo):
    esc_py = lambda s: str(s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    data_json = json.dumps(resumo, ensure_ascii=False).replace('</', '<\\/')
    buscado = resumo.get('buscado_em', '')
    try:
        buscado_fmt = datetime.fromisoformat(buscado).strftime('%d/%m/%Y %H:%M')
    except Exception:
        buscado_fmt = buscado
    perf = resumo['perfil']
    anos = resumo['por_ano']
    todas_datas = [p['data'][:10] for a in anos.values() for m in a['meses'].values() for p in m['posts']]
    primeiro = min(todas_datas) if todas_datas else '—'
    ultimo = max(todas_datas) if todas_datas else '—'
    sub = ('@%s &middot; %s &middot; cobertura: %s a %s &middot; '
           '%s posts de %s no perfil &middot; gerado em %s') % (
        esc_py(perf['username']), esc_py(perf['nome']), esc_py(primeiro), esc_py(ultimo),
        resumo['estatisticas']['posts_coletados'], perf['total_posts'], buscado_fmt)
    return ('<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n<meta charset="UTF-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
            '<title>@grupoamoranimal - Resumo por Ano/Mês</title>\n<style>' + CSS +
            '</style>\n</head>\n<body>\n<header>\n<div class="ig-icon">&#128062;</div>\n'
            '<h1>@grupoamoranimal - Resumo por Ano/Mês</h1>\n'
            '<div class="sub">' + sub + '</div>\n</header>\n<div class="container">\n'
            '<div class="tabs" id="tabs"></div>\n'
            '<div class="controls"><input type="text" id="busca" placeholder="Filtrar postagens nesta página (título ou categoria)..."></div>\n'
            '<div class="info" id="info"></div>\n'
            '<div id="view-dashboard"></div>\n'
            '<div id="view-ano" class="hidden"></div>\n</div>\n'
            '<footer>Gerado automaticamente a partir de dados publicos do perfil @grupoamoranimal &middot; '
            'Fonte: instagram-grupoamoranimal-resumo-mensal.json</footer>\n'
            '<div class="toolbar"><button class="btn-top" onclick="window.scrollTo({top:0,behavior:\'smooth\'})">Topo</button></div>\n'
            '<script type="application/json" id="resumo-data">' + data_json + '</script>\n'
            '<script>' + JS + '</script>\n</body>\n</html>')


def main():
    if not os.path.exists(IN_JSON):
        print('ERRO: %s nao encontrado. Rode resumo-mensal.py antes.' % IN_JSON)
        raise SystemExit(1)
    resumo = json.load(open(IN_JSON, encoding='utf-8'))
    html = build_html(resumo)
    with open(OUT_HTML, 'w', encoding='utf-8') as f:
        f.write(html)
    print('Pagina gerada: %s' % OUT_HTML)
    print('Tamanho: %.1f KB' % (len(html.encode('utf-8')) / 1024))


if __name__ == '__main__':
    main()

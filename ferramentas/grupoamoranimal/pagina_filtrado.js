#!/usr/bin/env node
/**
 * pagina_filtrado.js — Gera dataset-filtrado.html com os dados do
 * dataset-filtrado.json em tabelas por categoria, para revisao visual.
 *
 * Uso:
 *   node pagina_filtrado.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_JSON = path.join(DIR, 'dataset-filtrado.json');
const FILE_HTML = path.join(DIR, 'dataset-filtrado.html');

function esc(s) {
  return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function main() {
  if (!fs.existsSync(FILE_JSON)) {
    console.error('[pagina_filtrado] arquivo nao encontrado: ' + FILE_JSON + '\nRode antes: node filtrar.js');
    process.exit(1);
  }
  const d = JSON.parse(fs.readFileSync(FILE_JSON, 'utf8'));
  const cats = d.por_categoria;

  const ordem = ['adocao', 'castracao', 'procura-se', 'doacao', 'outros'];
  const secoes = [];

  ordem.forEach((cat) => {
    if (!cats[cat]) return;
    const grupo = cats[cat];
    const posts = grupo.posts;
    const temApi = grupo.tabela_api && posts[0] && posts[0].api;
    const chavesApi = temApi ? Object.keys(posts[0].api.payload) : [];

    const thBasicos = '<th>#</th><th>C\u00f3digo</th><th>Data</th><th>T\u00edtulo</th>';
    const thApi = chavesApi.map((k) => '<th title="coluna da API">' + esc(k) + '</th>').join('');

    const linhas = posts.map((p, i) => {
      const foto = p.midia || p.thumbnail;
      const celulasApi = chavesApi.map((k) => {
        const v = p.api ? p.api.payload[k] : null;
        const s = v == null ? '' : String(v);
        let html = s.length > 200 ? '<details><summary>ver</summary>' + esc(s) + '</details>' : esc(s);
        if (k === 'foto_url' && v) html = '<a href="' + esc(v) + '" target="_blank">\ud83d\uddbc\ufe0f foto</a>';
        return '<td class="' + (v == null ? 'vazio' : '') + '">' + (html || '<i>vazio</i>') + '</td>';
      }).join('');

      const tituloTd = p.titulo && p.titulo.length > 90
        ? '<details><summary>' + esc(p.titulo.slice(0, 90)) + '…</summary>' + esc(p.titulo) + '</details>'
        : esc(p.titulo || '-');

      return '<tr>' +
        '<td>' + (i + 1) + '</td>' +
        '<td><a href="' + esc(p.url) + '" target="_blank">' + esc(p.code) + '</a></td>' +
        '<td class="data">' + esc((p.data_iso || '').slice(0, 10)) + '</td>' +
        '<td>' + tituloTd + '</td>' +
        (temApi ? celulasApi : '') +
        '</tr>';
    }).join('\n');

    const badge = grupo.tabela_api
      ? '<span class="badge" style="background:#14532d;color:#4ade80;">→ ' + esc(grupo.tabela_api) + '</span>'
      : '<span class="badge" style="background:#3b0764;color:#c4b5fd;">sem tabela na API</span>';

    secoes.push(
      '<section>' +
      '<h2>' + esc(cat) + ' <span class="count">' + grupo.total + '</span> ' + badge + '</h2>' +
      '<div class="table-wrap"><table><thead><tr>' + thBasicos + thApi + '</tr></thead>' +
      '<tbody>' + linhas + '</tbody></table></div>' +
      '</section>'
    );
  });

  const stats = Object.keys(cats).map((c) =>
    '<div class="stat"><span class="stat-cat">' + esc(c) + '</span><b>' + cats[c].total + '</b></div>').join('');

  const html = `<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>Dataset Filtrado - Grupo Amor Animal</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; padding: 1.5rem; background: #0f172a; color: #e2e8f0; }
  h1 { margin-top: 0; font-size: 1.4rem; }
  .meta { color: #94a3b8; font-size: 0.85rem; margin-bottom: 1rem; }
  .stats { display: flex; gap: 0.75rem; flex-wrap: wrap; margin-bottom: 1.5rem; }
  .stat { background: #1e293b; border: 1px solid #334155; border-radius: 10px; padding: 10px 16px; min-width: 110px; }
  .stat b { display: block; font-size: 1.4rem; }
  .stat-cat { color: #7dd3fc; font-size: 0.8rem; text-transform: uppercase; }
  section { margin-bottom: 2rem; }
  h2 { font-size: 1.1rem; border-bottom: 1px solid #334155; padding-bottom: 6px; }
  .count { background: #1e293b; color: #7dd3fc; border-radius: 20px; padding: 2px 10px; font-size: 0.85rem; }
  .badge { margin-left: 8px; padding: 2px 10px; border-radius: 20px; font-size: 0.8rem; }
  .table-wrap { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; background: #1e293b; border: 1px solid #334155; font-size: 0.82rem; }
  th, td { border: 1px solid #334155; padding: 5px 8px; text-align: left; vertical-align: top; }
  th { background: #172033; color: #94a3b8; position: sticky; top: 0; }
  td.vazio { color: #64748b; font-style: italic; }
  td.data { white-space: nowrap; color: #94a3b8; }
  a { color: #7dd3fc; }
  details summary { cursor: pointer; color: #cbd5e1; }
</style>
</head>
<body>
<h1>Dataset Filtrado — Grupo Amor Animal</h1>
<div class="meta">${esc(d.metadados.fonte)} | ${esc(d.metadados.cobertura || '')} | total: <b>${d.metadados.total_posts}</b> | gerado: ${esc((d.metadados.gerado_em || '').slice(0, 16).replace('T', ' '))}</div>
<div class="stats">${stats}</div>
${secoes.join('\n')}
</body>
</html>`;

  fs.writeFileSync(FILE_HTML, html);
  console.log('[pagina_filtrado] gerado: ' + FILE_HTML);
}

main();

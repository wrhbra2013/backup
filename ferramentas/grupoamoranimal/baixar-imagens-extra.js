#!/usr/bin/env node
/**
 * baixar-imagens-extra.js — Baixa imagens dos posts via greatfon.com/dumpor.com
 * (fallback quando imginn expira e o Instagram bloqueia o instaloader).
 *
 * Uso: node baixar-imagens-extra.js <codes.json> <dir_destino> <resultado.json>
 *
 * Para cada code: busca a página do post no greatfon, extrai TODAS as URLs
 * cdn2.dumpor.io, e baixa a primeira que retornar imagem válida (>2KB).
 * URLs compartilhadas entre vários posts (imagens padrão) são descartadas.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

const RE_URL = /https:\/\/cdn2\.dumpor\.io\/[^\s"'<>()\\]+\.(?:jpg|jpeg|webp)/g;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function baixar(url, dest) {
  const res = await fetch(url, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(25000) });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 2000) throw new Error('conteudo pequeno');
  fs.writeFileSync(dest, buf);
}

async function main() {
  const [codesFile, destDir, resultFile] = process.argv.slice(2);
  const codes = JSON.parse(fs.readFileSync(codesFile, 'utf8'));
  fs.mkdirSync(destDir, { recursive: true });

  const cacheUrl = {};   // url -> true/false (download ok/nao)
  const urlPorCode = {}; // code -> urls candidatas

  const result = {};
  let ok = 0, semUrl = 0;

  for (const code of codes) {
    const dest = path.join(destDir, code + '.jpg');
    if (fs.existsSync(dest)) { result[code] = true; ok++; continue; }
    let urls = [];
    try {
      const r = await fetch('https://www.greatfon.com/p/' + code + '/', {
        headers: { 'User-Agent': UA },
        redirect: 'follow',
        signal: AbortSignal.timeout(25000),
      });
      const t = await r.text();
      urls = [...new Set((t.match(RE_URL) || []).map((u) => u.trim()))];
    } catch (e) {
      console.log('[erro-pagina] ' + code + ' (' + e.message.slice(0, 40) + ')');
    }
    urlPorCode[code] = urls;
    if (!urls.length) { semUrl++; result[code] = false; console.log('[sem-url] ' + code); }
    await sleep(800);
  }

  for (const code of codes) {
    const dest = path.join(destDir, code + '.jpg');
    if (fs.existsSync(dest)) continue;
    const candidatas = urlPorCode[code] || [];
    let baixou = false;
    for (const u of candidatas) {
      if (cacheUrl[u] === false) continue;
      try {
        await baixar(u, dest);
        cacheUrl[u] = true;
        result[code] = true;
        ok++;
        baixou = true;
        console.log('[ok] ' + code);
        break;
      } catch (e) {
        cacheUrl[u] = false;
      }
    }
    if (!baixou) { result[code] = false; console.log('[falha] ' + code); }
    await sleep(400);
  }

  fs.writeFileSync(resultFile, JSON.stringify(result));
  console.log('concluido: ' + ok + '/' + codes.length + ' baixadas' + (semUrl ? ' | sem url: ' + semUrl : ''));
}

main().catch((e) => { console.error('ERRO fatal:', e); process.exit(1); });

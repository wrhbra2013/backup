#!/usr/bin/env node
/**
 * simular-site.js — Simula a população das tabelas da API Amor Animal na página
 * oficial (amoranimal.ong.br) usando os dados e IMAGENS dos posts do Instagram
 * @grupoamoranimal.
 *
 * Gera uma página HTML OFFLINE que replica o visual do site oficial (header,
 * hero, "Nosso Impacto", eventos, carrossel de adoção, desaparecidos e CTA),
 * populada com os posts convertidos para as tabelas da API. As imagens dos posts
 * são baixadas para uma pasta local, para que a página funcione sem internet.
 *
 * Uso:
 *   node simular-site.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const DIR = __dirname;
const FILE_RESUMO = path.join(DIR, '..', 'json', 'instagram-grupoamoranimal-resumo-mensal.json');
const FILE_DATASET = path.join(DIR, '..', 'json', 'instagram-grupoamoranimal-dataset.json');
const OUT_HTML = path.join(DIR, '..', 'html', 'instagram-grupoamoranimal-site-simulacao.html');
const IMG_DIR = path.join(DIR, '..', 'html', 'img-simulacao-site');

// ─── Helpers de parsing (espelho do sincronizar.js / simular-api.js) ──────────

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
  adocao: { rota: '/adocao', fn: payloadAdocao },
  'procura-se': { rota: '/procura_se', fn: payloadProcuraSe },
  castracao: { rota: '/eventos', fn: payloadEvento },
};

// ─── Filtro de qualidade (espelho do simular-api.js) ─────────────────────────

const STOP_NOME = new Set([
  'agradecemos', 'agradecimento', 'obrigado', 'obrigada', 'votem', 'voto', 'vote', 'ajude', 'ajudar',
  'precisamos', 'precisa', 'conheca', 'participe', 'compareca', 'doacao', 'doacoes', 'doe', 'doar',
  'arrecadacao', 'vaquinha', 'rifa', 'campanha', 'mutirao', 'feirinha', 'feira', 'evento', 'eventos',
  'castracao', 'castrar', 'castra', 'vacina', 'vacinacao', 'adocao', 'adote', 'quero', 'venha', 'temos',
  'ajuda', 'curta', 'compartilhe', 'salve', 'resgate', 'vamos', 'juntos', 'aniversario', 'natal',
  'feliz', 'parabens', 'hoje', 'amanha', 'sabado', 'domingo', 'sexta', 'link', 'bio', 'instagram',
  'whatsapp', 'gratidao', 'gratidão', 'dia', 'dias', 'sos', 'urgente', 'divulg', 'divulgue', 'noticia',
  'noticias', 'recursos', 'projeto', 'edital', 'emenda', 'parlamentar', 'conseguir', 'semana', 'mes',
  'anos', 'animal', 'animais', 'pets', 'peludinhos', 'mensagem', 'sobre', 'nossa', 'nosso', 'nossa',
  'obrigado', 'todos', 'tudo', 'estamos', 'ja', 'ate', 'vem', 'compartilha', 'pedimos', 'preciso',
]);

const CTX_ADOCAO = ['adot', 'lar', 'castrad', 'resgat', 'filhot', 'femea', 'macho', 'doci', 'amorosa', 'amoroso', 'vacinad', 'pet', 'dona', 'tutor'];
const CTX_EVENTO = ['feira', 'mutirao', 'castra', 'evento', 'dia', 'sabado', 'domingo', 'sexta', 'local', 'onde', 'horario', 'compareca', 'particip', 'realiz', 'acontec', 'vagas'];

function validarAdocao(p, pl) {
  const nome = norm(pl.nome || '');
  const c = norm(p.legenda || '');
  if (!nome || nome.length < 2) return { ok: false, motivo: 'sem nome de pet' };
  if (STOP_NOME.has(nome)) return { ok: false, motivo: 'nome genérico ("' + pl.nome + '")' };
  if (!CTX_ADOCAO.some((w) => c.includes(w))) return { ok: false, motivo: 'legenda sem contexto de adoção' };
  return { ok: true, motivo: null };
}
function validarProcura(p, pl) {
  const nome = norm(pl.pet_nome || '');
  const c = norm(p.legenda || '');
  if (!telefone(c)) return { ok: false, motivo: 'sem telefone de contato na legenda' };
  if (!nome || nome.length < 2) return { ok: false, motivo: 'sem nome do pet' };
  if (STOP_NOME.has(nome)) return { ok: false, motivo: 'nome genérico ("' + pl.pet_nome + '")' };
  if (!tem(c, 'sumiu', 'desaparec', 'procura', 'fugiu', 'perdeu', 'nao ach', 'nao vim')) return { ok: false, motivo: 'legenda sem contexto de desaparecimento' };
  return { ok: true, motivo: null };
}
function validarEvento(p, pl) {
  const c = norm(p.legenda || '');
  if (!pl.data_evento || pl.data_evento === p.data_iso) return { ok: false, motivo: 'data do evento não identificada no texto' };
  if (!CTX_EVENTO.some((w) => c.includes(w))) return { ok: false, motivo: 'legenda sem contexto de evento' };
  return { ok: true, motivo: null };
}

const VALIDADORES = {
  '/adocao': validarAdocao,
  '/procura_se': validarProcura,
  '/eventos': validarEvento,
};

// ─── Coleta de dados ─────────────────────────────────────────────────────────

function carregarResumo() {
  const resumo = JSON.parse(fs.readFileSync(FILE_RESUMO, 'utf8'));
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

function processar(posts) {
  const dados = [];
  const rejeitados = [];
  posts.forEach((p) => {
    const map = ROTAS[p.categoria];
    if (!map) return;
    const payload = map.fn(p);
    const valid = VALIDADORES[map.rota](p, payload);
    const item = {
      code: p.code, url: p.url, data: p.data, data_iso: p.data_iso,
      titulo: p.titulo, legenda: p.legenda, thumbnail: p.thumbnail,
      likes: p.likes, comentarios: p.comentarios,
      categoria: p.categoria, rota: map.rota, payload,
    };
    if (valid.ok) dados.push(item);
    else rejeitados.push(Object.assign(item, { motivo: valid.motivo }));
  });
  return { dados, rejeitados };
}

// ─── Imagens (offline) ───────────────────────────────────────────────────────

async function baixar(url, dest) {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(45000) });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    fs.writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
    return true;
  } catch (_) {
    return false;
  }
}

async function prepararImagens(posts) {
  fs.mkdirSync(IMG_DIR, { recursive: true });
  let baixadas = 0, falhas = 0;
  const fila = [];
  for (const d of posts) {
    const url = d.thumbnail;
    const dest = path.join(IMG_DIR, d.code + '.jpg');
    const jaExiste = fs.existsSync(dest);
    if (!url) { d.img = null; continue; }
    d.img = jaExiste ? 'img-simulacao-site/' + d.code + '.jpg' : null;
    if (!jaExiste) fila.push({ d, url, dest });
  }
  console.log('[simular-site] ' + fila.length + ' imagens a baixar...');
  const CONC = 6;
  for (let i = 0; i < fila.length; i += CONC) {
    await Promise.all(fila.slice(i, i + CONC).map(async (f) => {
      const ok = await baixar(f.url, f.dest);
      if (ok) { f.d.img = 'img-simulacao-site/' + f.d.code + '.jpg'; baixadas++; }
      else { f.d.img = f.url; falhas++; }
    }));
    process.stdout.write('\r  ' + Math.min(i + CONC, fila.length) + '/' + fila.length + ' ...');
  }
  console.log('\n[simular-site] imagens baixadas: ' + baixadas + ' | falhas (usando URL remota): ' + falhas);

  const faltando = fila.filter((f) => !fs.existsSync(f.dest));
  if (faltando.length > 0) {
    const codesFile = path.join(DIR, '_imagens-faltantes.json');
    const resFile = path.join(DIR, '_imagens-resultado.json');
    fs.writeFileSync(codesFile, JSON.stringify(faltando.map((f) => f.d.code)));

    console.log('[simular-site] tentando ' + faltando.length + ' imagens via greatfon/dumpor...');
    try {
      execFileSync(process.execPath,
        [path.join(DIR, 'baixar-imagens-extra.js'), codesFile, IMG_DIR, resFile],
        { stdio: 'inherit', timeout: 1800000 });
    } catch (e) {
      console.error('[simular-site] downloader greatfon encerrou com erro: ' + (e.message || e));
    }
    let res = fs.existsSync(resFile) ? JSON.parse(fs.readFileSync(resFile, 'utf8')) : {};
    let recuperadas = 0;
    for (const f of faltando) {
      if (res[f.d.code] && fs.existsSync(f.dest)) {
        f.d.img = 'img-simulacao-site/' + f.d.code + '.jpg';
        recuperadas++;
      }
    }
    if (recuperadas) console.log('[simular-site] recuperadas via greatfon/dumpor: ' + recuperadas);

    const aindaFaltam = faltando.filter((f) => !fs.existsSync(f.dest));
    if (aindaFaltam.length > 0) {
      console.log('[simular-site] tentando ' + aindaFaltam.length + ' via instaloader (sessao IG)...');
      fs.writeFileSync(codesFile, JSON.stringify(aindaFaltam.map((f) => f.d.code)));
      try {
        execFileSync('python3',
          [path.join(DIR, '..', 'py', 'baixar-imagens.py'), codesFile, IMG_DIR, resFile],
          { stdio: 'inherit', timeout: 900000 });
      } catch (e) {
        console.error('[simular-site] helper instaloader encerrou com erro: ' + (e.message || e));
      }
      res = fs.existsSync(resFile) ? JSON.parse(fs.readFileSync(resFile, 'utf8')) : {};
      recuperadas = 0;
      for (const f of aindaFaltam) {
        if (res[f.d.code] && fs.existsSync(f.dest)) {
          f.d.img = 'img-simulacao-site/' + f.d.code + '.jpg';
          recuperadas++;
        }
      }
      if (recuperadas) console.log('[simular-site] recuperadas via instaloader: ' + recuperadas);
    }

    try { fs.unlinkSync(codesFile); } catch (_) {}
    try { fs.unlinkSync(resFile); } catch (_) {}
  }
}

// ─── HTML (réplica do site oficial) ──────────────────────────────────────────

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const fmtData = (iso) => {
  if (!iso) return '—';
  const d = iso.length > 10 ? new Date(iso) : new Date(iso + 'T00:00:00');
  if (isNaN(d)) return iso;
  const p = (n) => String(n).padStart(2, '0');
  return p(d.getDate()) + '/' + p(d.getMonth() + 1) + '/' + d.getFullYear();
};

const CSS = `
:root{
  --brand-teal:#0d9488;--brand-teal-dark:#0f766e;--brand-teal-light:#14b8a6;
  --brand-coral:#f97316;--brand-coral-2:#ea580c;--brand-purple:#8b5cf6;
  --brand-pink:#ec4899;--brand-blue:#0ea5e9;--brand-blue-dark:#0284c7;
  --bg-color:#f8fafc;--bg-alt:#e2e8f0;--text-color:#1e293b;--muted-color:#64748b;
  --container-bg:#ffffff;--container-shadow:0 4px 20px rgba(0,0,0,0.08);--container-border:#e2e8f0;
  --border-color:#e2e8f0;--heading-color:var(--brand-coral);
  --nav-bg:#0d9488;--nav-text:#fff;--nav-gradient:linear-gradient(135deg,#0d9488,#0f766e);
  --button-bg:linear-gradient(135deg,#0d9488,#0f766e);--button-text:#fff;
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',system-ui,-apple-system,Tahoma,Arial,sans-serif;background:var(--bg-color);color:var(--text-color);line-height:1.6}
img{max-width:100%;display:block}

/* Header */
.site-header{background:var(--nav-gradient);color:var(--nav-text);position:sticky;top:0;z-index:100;box-shadow:0 2px 12px rgba(0,0,0,0.15)}
.header-inner{max-width:1200px;margin:0 auto;padding:0 1.5rem;display:flex;align-items:center;gap:1.5rem;height:64px}
.header-logo{display:flex;align-items:center;gap:10px;color:#fff;text-decoration:none}
.header-logo-icon{width:38px;height:38px;border-radius:50%;background:linear-gradient(135deg,#f97316,#ec4899);display:flex;align-items:center;justify-content:center;font-size:1.2rem}
.header-logo-text{font-weight:700;font-size:1.05rem}
.header-nav{display:flex;gap:1.1rem;margin-left:auto;align-items:center}
.header-nav a{color:rgba(255,255,255,0.92);text-decoration:none;font-size:0.9rem;font-weight:600;transition:opacity .2s}
.header-nav a:hover{opacity:.8}
.header-badge{background:#fff;color:var(--brand-teal);font-size:0.68rem;font-weight:800;padding:4px 10px;border-radius:20px;letter-spacing:0.5px}

/* Banner de simulação */
.sim-banner{background:linear-gradient(135deg,#fffbeb,#fef3c7);border-bottom:1px solid #fde68a;color:#92400e}
.sim-banner-inner{max-width:1200px;margin:0 auto;padding:10px 1.5rem;font-size:0.85rem;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.sim-banner b{color:#78350f}

/* Hero */
.hero-landing{background:linear-gradient(135deg,rgba(13,148,136,0.9),rgba(14,165,233,0.85)),url('img-simulacao-site/hero-bg.jpg') center/cover;padding:6rem 0;color:#fff;text-align:center}
.hero-landing h1{font-size:3rem;font-weight:700;margin-bottom:1rem;text-shadow:2px 2px 4px rgba(0,0,0,0.3)}
.hero-landing p{font-size:1.25rem;margin-bottom:2rem;opacity:.95;max-width:720px;margin-left:auto;margin-right:auto}
.hero-landing .btn{display:inline-block;padding:1rem 2rem;font-size:1.1rem;border-radius:50px;font-weight:600;text-decoration:none;transition:all .3s;cursor:pointer;border:none}
.hero-landing .btn-primary{background:#fff;color:var(--brand-teal)}
.hero-landing .btn-primary:hover{transform:translateY(-3px);box-shadow:0 10px 20px rgba(0,0,0,0.2)}
.hero-landing .btn-outline{background:transparent;border:2px solid #fff;color:#fff;margin-left:1rem}
.hero-landing .btn-outline:hover{background:#fff;color:var(--brand-teal)}
.hero-tag{display:inline-block;background:rgba(255,255,255,0.2);border:1px solid rgba(255,255,255,0.4);padding:4px 14px;border-radius:20px;font-size:0.8rem;margin-bottom:1.2rem;letter-spacing:0.5px}

/* Seções */
.landing-section{padding:4rem 0}
.landing-section-alt{background:linear-gradient(180deg,var(--bg-color) 0%,var(--bg-alt) 100%)}
.landing-section-white{background:var(--container-bg)}
.landing-container{max-width:1200px;margin:0 auto;padding:0 1.5rem}
.landing-section h2{color:var(--heading-color);font-size:1.9rem;border-bottom:3px solid var(--brand-teal);display:inline-block;padding-bottom:0.4em;margin-bottom:1.5em}
.text-center{text-align:center}

/* Stats */
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:28px;margin:2rem 0}
.stat-card{background:var(--container-bg);border:2px solid var(--border-color);border-radius:16px;padding:26px 18px;text-align:center;transition:all .3s}
.stat-card:hover{transform:translateY(-5px);box-shadow:var(--container-shadow);border-color:var(--brand-teal)}
.stat-card-icon{font-size:2.2rem;margin-bottom:0.8rem}
.stat-card-number{font-size:2.3rem;font-weight:700;color:var(--text-color);line-height:1}
.stat-card-label{color:var(--muted-color);margin-top:0.5rem;font-size:0.9rem}

/* Grid missão */
.landing-grid{display:grid;grid-template-columns:1fr 1fr;gap:2rem;align-items:center}
.landing-grid h2{margin-bottom:0.6em}
.landing-grid p{line-height:1.8;color:var(--text-color)}
.fieldset{max-width:320px;margin:0 auto;border:2px solid var(--brand-teal);border-radius:12px;padding:1.5rem;text-align:center}
.fieldset legend{font-weight:700;color:var(--heading-color);padding:0 10px;font-size:0.95rem}

/* Busca */
.controls{max-width:1200px;margin:0 auto;padding:0 1.5rem}
.controls input{width:100%;padding:12px 16px;border-radius:12px;border:2px solid var(--border-color);font-family:inherit;font-size:0.95rem;outline:none;background:var(--container-bg);color:var(--text-color)}
.controls input:focus{border-color:var(--brand-teal)}
.card-hide{display:none!important}

/* Eventos */
.events-grid{display:flex;flex-direction:row;gap:1.5rem;overflow-x:auto;padding-bottom:8px;scroll-behavior:smooth;-webkit-overflow-scrolling:touch}
.events-grid::-webkit-scrollbar{height:8px}
.events-grid::-webkit-scrollbar-track{background:#f1f1f1;border-radius:4px}
.events-grid::-webkit-scrollbar-thumb{background:var(--brand-teal);border-radius:4px}
.evt-card{background:var(--container-bg);border-radius:12px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.15);transition:transform .3s,box-shadow .3s;flex:0 0 320px}
.evt-card:hover{transform:translateY(-5px);box-shadow:0 8px 30px rgba(0,0,0,0.25)}
.evt-card-img{position:relative;width:100%;height:250px;overflow:hidden;background:var(--bg-alt)}
.evt-card-img img{width:100%;height:100%;object-fit:cover;transition:transform .4s}
.evt-card:hover .evt-card-img img{transform:scale(1.1)}
.evt-card-date{position:absolute;top:10px;left:10px;background:var(--brand-teal);color:#fff;font-size:0.72rem;font-weight:700;padding:4px 10px;border-radius:20px}
.evt-card-body{padding:15px;color:var(--text-color)}
.evt-card-title{margin:0 0 8px;font-size:1.1rem;font-weight:600;color:var(--heading-color)}
.evt-card-desc{font-size:0.82rem;color:var(--muted-color);line-height:1.6;max-height:78px;overflow:hidden}
.link-post{display:inline-flex;align-items:center;gap:6px;margin-top:10px;color:var(--brand-teal);font-size:0.82rem;font-weight:700;text-decoration:none}
.link-post:hover{text-decoration:underline}

/* Carrossel de adoção */
.pet-carousel-wrapper{width:100%;overflow:hidden;padding:10px 0}
.pet-carousel{display:flex;gap:1.5rem;width:max-content;animation:scrollPets 60s linear infinite}
.pet-carousel:hover{animation-play-state:paused}
@keyframes scrollPets{0%{transform:translateX(0)}100%{transform:translateX(-50%)}}
.pet-carousel-item{flex:0 0 280px;background:var(--container-bg);border-radius:12px;overflow:hidden;box-shadow:var(--container-shadow);transition:transform .3s,box-shadow .3s;border:1px solid var(--container-border)}
.pet-carousel-item:hover{transform:translateY(-4px);box-shadow:0 8px 25px rgba(0,0,0,0.15)}
.pet-ph{height:230px;background:linear-gradient(135deg,#cffafe,#ffe4e6);display:flex;align-items:center;justify-content:center;font-size:3rem}
.pet-ph img{width:100%;height:100%;object-fit:cover}
.pet-body{padding:12px 14px}
.pet-name{font-weight:700;font-size:1.02rem;color:var(--text-color)}
.pet-meta{display:flex;gap:6px;flex-wrap:wrap;margin:6px 0}
.pill{font-size:0.64rem;font-weight:700;padding:2px 8px;border-radius:12px;background:rgba(0,0,0,0.06);color:var(--muted-color);text-transform:uppercase;letter-spacing:0.4px}
.pill-especie{background:rgba(14,165,233,0.12);color:#0284c7}
.pill-porte{background:rgba(139,92,246,0.12);color:#7c3aed}
.pill-idade{background:rgba(16,185,129,0.12);color:#047857}
.pill-procura{background:rgba(249,115,22,0.14);color:#c2410c}
.pet-desc{font-size:0.76rem;color:var(--muted-color);line-height:1.5;max-height:66px;overflow:hidden}
.pet-foot{display:flex;align-items:center;gap:8px;margin-top:10px;padding-top:10px;border-top:1px solid rgba(0,0,0,0.05);font-size:0.72rem;color:var(--muted-color);flex-wrap:wrap}
.pet-foot .link-post{margin-top:0;margin-left:auto}
.status{font-size:0.62rem;font-weight:800;padding:3px 9px;border-radius:20px;text-transform:uppercase;letter-spacing:0.5px}
.status-disponivel{background:rgba(16,185,129,0.14);color:#047857}
.status-procura{background:rgba(194,65,12,0.14);color:#c2410c}
.status-evento{background:rgba(29,78,216,0.12);color:#1d4ed8}

/* CTA */
.cta{text-align:center}
.cta p{font-size:1.1rem;color:var(--text-color);margin:0 auto 2rem;max-width:600px}
.cta .btn{display:inline-block;padding:0.9rem 1.8rem;border-radius:10px;font-weight:600;text-decoration:none;border:none;cursor:pointer;transition:all .3s;font-size:1rem;margin:0 0.4rem}
.btn-teal{background:var(--button-bg);color:var(--button-text)}
.btn-teal:hover{transform:translateY(-2px);box-shadow:0 4px 20px rgba(13,148,136,0.4)}
.btn-coral{background:var(--brand-coral);color:#fff}
.btn-purple{background:var(--brand-purple);color:#fff}

/* Footer */
.site-footer{background:linear-gradient(135deg,#1e293b,#334155);color:#e2e8f0;padding:2.5rem 0;margin-top:3rem}
.footer-inner{max-width:1200px;margin:0 auto;padding:0 1.5rem;text-align:center;font-size:0.85rem}
.site-footer a{color:var(--brand-teal-light);text-decoration:none}

@media(max-width:768px){
  .hero-landing h1{font-size:2rem}
  .landing-grid{grid-template-columns:1fr}
  .header-nav{display:none}
  .stats-grid{grid-template-columns:repeat(2,1fr)}
  .pet-carousel-item{flex-basis:240px}
}
`;

const JS = `
document.getElementById('busca').addEventListener('input', e => {
  const q = e.target.value.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,'');
  document.querySelectorAll('[data-busca]').forEach(el => {
    const txt = el.getAttribute('data-busca') || '';
    el.classList.toggle('card-hide', !!q && !txt.includes(q));
  });
});
`;

function buildHtml({ resumo, posts, dados, rejeitados, resumoPg }) {
  const porRota = {};
  dados.forEach((d) => { (porRota[d.rota] = porRota[d.rota] || []).push(d); });

  const grupos = {};
  (porRota['/adocao'] || []).forEach((d) => {
    const k = norm(d.payload.nome);
    (grupos[k] = grupos[k] || []).push(d);
  });
  const adocao = Object.keys(grupos).map((k) => grupos[k][0]);
  const procura = porRota['/procura_se'] || [];
  const eventos = porRota['/eventos'] || [];

  const nomeMes = { 1: 'Jan', 2: 'Fev', 3: 'Mar', 4: 'Abr', 5: 'Mai', 6: 'Jun', 7: 'Jul', 8: 'Ago', 9: 'Set', 10: 'Out', 11: 'Nov', 12: 'Dez' };

  const buscaAttr = (s) => esc(norm(s));
  const img = (d, alt) => {
    const src = d.img || d.thumbnail || null;
    return src
      ? '<img loading="lazy" src="' + esc(src) + '" alt="' + esc(alt) + '">'
      : '<span>🐾</span>';
  };

  const totLikes = posts.reduce((s, p) => s + (p.likes || 0), 0);
  const totCom = posts.reduce((s, p) => s + (p.comentarios || 0), 0);

  const statCards = [
    ['🐾', adocao.length, 'Pets para Adoção'],
    ['🔎', procura.length, 'Desaparecidos'],
    ['📅', eventos.length, 'Eventos / Mutições'],
    ['📊', posts.length, 'Posts analisados'],
    ['❤️', totLikes, 'Curtidas nos posts'],
    ['💬', totCom, 'Comentários'],
  ].map(([i, v, l]) =>
    '<div class="stat-card"><div class="stat-card-icon">' + i + '</div>' +
    '<div class="stat-card-number">' + v + '</div><div class="stat-card-label">' + l + '</div></div>').join('');

  const eventoCards = eventos.map((d) => {
    const pl = d.payload;
    const dt = pl.data_evento ? new Date(pl.data_evento) : null;
    const dtTxt = dt && !isNaN(dt)
      ? dt.getDate() + ' ' + (nomeMes[dt.getMonth() + 1] || '') + ' ' + dt.getFullYear()
      : 'Data não informada';
    const desc = limparTexto(pl.descricao || '', 160);
    return '<div class="evt-card" data-busca="' + buscaAttr((pl.titulo || '') + ' ' + desc) + '">' +
      '<div class="evt-card-img">' + img(d, pl.titulo) +
      '<span class="evt-card-date">' + esc(dtTxt) + '</span></div>' +
      '<div class="evt-card-body"><div class="evt-card-title">' + esc(pl.titulo) + '</div>' +
      '<div class="evt-card-desc">' + esc(desc) + '</div>' +
      '<a class="link-post" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver post no Instagram ↗</a></div></div>';
  }).join('');

  const chipEsp = (especie) => especie ? '<span class="pill pill-especie">' + esc({ felino: 'Gato', canino: 'Cachorro' }[especie] || especie) + '</span>' : '';
  const chipPorte = (porte) => porte ? '<span class="pill pill-porte">' + esc(porte) + '</span>' : '';
  const chipIdade = (idade) => idade ? '<span class="pill pill-idade">' + esc(idade) + '</span>' : '';

  const petCards = adocao.map((d) => {
    const pl = d.payload;
    const outros = (grupos[norm(pl.nome)] || []).length;
    return '<div class="pet-carousel-item" data-busca="' + buscaAttr((pl.nome || '') + ' ' + (pl.caracteristicas || '')) + '">' +
      '<div class="pet-ph">' + img(d, pl.nome) + '</div>' +
      '<div class="pet-body"><div class="pet-name">' + esc(pl.nome) + (outros > 1 ? ' <span class="pill">' + outros + ' posts</span>' : '') + '</div>' +
      '<div class="pet-meta">' + chipEsp(pl.especie) + chipPorte(pl.porte) + chipIdade(pl.idade) + '</div>' +
      '<div class="pet-desc">' + esc(pl.caracteristicas || '') + '</div>' +
      '<div class="pet-foot"><span class="status status-disponivel">Disponível</span>' +
      '<a class="link-post" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver post ↗</a></div></div></div>';
  }).join('');

  const procuraCards = procura.map((d) => {
    const pl = d.payload;
    return '<div class="pet-carousel-item" data-busca="' + buscaAttr((pl.pet_nome || '') + ' ' + (pl.pet_caracteristicas || '')) + '">' +
      '<div class="pet-ph">' + img(d, pl.pet_nome) + '</div>' +
      '<div class="pet-body"><div class="pet-name">🔎 ' + esc(pl.pet_nome) + '</div>' +
      '<div class="pet-meta">' + chipEsp({ Gato: 'felino', Cachorro: 'canino' }[pl.pet_especie] || pl.pet_especie) + chipPorte(pl.pet_porte) + chipIdade(pl.pet_idade) + '</div>' +
      '<div class="pet-desc">' + esc(pl.pet_caracteristicas || '') + '</div>' +
      '<div class="pet-foot"><span class="status status-procura">Procura-se</span>' +
      '<span>📞 ' + esc(pl.tutor_contato || '') + '</span>' +
      '<a class="link-post" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver post ↗</a></div></div></div>';
  }).join('');

  const now = new Date().toLocaleString('pt-BR');
  const sub = '@grupoamoranimal · ' + resumo.perfil.nome + ' · ' + resumo.estatisticas.posts_coletados +
    ' posts analisados · simulação das tabelas da API (adocao, procura_se, eventos) · gerado em ' + now;

  return '<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n<meta charset="UTF-8">\n' +
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
    '<title>ONG Amor Animal Marília — Simulação offline com posts do Instagram</title>\n' +
    '<style>' + CSS + '</style>\n</head>\n<body>\n' +

    '<header class="site-header"><div class="header-inner">' +
    '<a class="header-logo" href="#"><span class="header-logo-icon">🐶</span><span class="header-logo-text">ONG Amor Animal Marília</span></a>' +
    '<nav class="header-nav">' +
    '<a href="#impacto">Nosso Impacto</a>' +
    '<a href="#eventos">Eventos</a>' +
    '<a href="#adocao">Pets para Adoção</a>' +
    '<a href="#procura">Desaparecidos</a>' +
    '<a href="https://www.instagram.com/grupoamoranimal/" target="_blank" rel="noopener">Instagram</a>' +
    '<span class="header-badge">SIMULAÇÃO OFFLINE</span>' +
    '</nav></div></header>\n' +

    '<div class="sim-banner"><div class="sim-banner-inner">' +
    '🔬 <b>Página offline de simulação.</b> Réplica visual de amornimal.ong.br populada com os dados dos posts do Instagram @grupoamoranimal — ' +
    'as imagens são dos próprios posts e nada é enviado à API real.</div></div>\n' +

    '<section class="hero-landing"><div class="landing-container">' +
    '<span class="hero-tag">' + esc(sub) + '</span>' +
    '<h1>Amor que Transforma Vidas</h1>' +
    '<p>Junte-se a nós na missão de resgatar, cuidar e encontrar lares amorosos para animais abandonados. Esta é uma prévia de como o site ficaria populado com as postagens do Instagram.</p>' +
    '<a href="#adocao" class="btn btn-primary">Quero Adotar</a>' +
    '<a href="#impacto" class="btn btn-outline">Ver a Simulação</a>' +
    '</div></section>\n' +

    '<section class="landing-section landing-section-alt" id="impacto"><div class="landing-container">' +
    '<h2 class="text-center">Nosso Impacto</h2>' +
    '<div class="stats-grid">' + statCards + '</div>' +
    '</div></section>\n' +

    '<div class="controls"><input type="text" id="busca" placeholder="Filtrar pets, eventos e desaparecidos por nome ou texto..."></div>\n' +

    '<section class="landing-section landing-section-white" id="eventos"><div class="landing-container">' +
    '<h2>Eventos</h2>' +
    (eventoCards
      ? '<div class="events-grid">' + eventoCards + '</div>'
      : '<div class="info">Nenhum evento aprovado pelo filtro de qualidade.</div>') +
    '</div></section>\n' +

    '<section class="landing-section landing-section-alt" id="adocao"><div class="landing-container">' +
    '<h2>Pets para Adoção</h2>' +
    '<div class="pet-carousel-wrapper"><div class="pet-carousel">' +
    (petCards + petCards || '<div class="info">Nenhum pet aprovado pelo filtro.</div>') +
    '</div></div></section>\n' +

    '<section class="landing-section landing-section-white" id="procura"><div class="landing-container">' +
    '<h2>Desaparecidos</h2>' +
    (procuraCards
      ? '<div class="pet-carousel-wrapper"><div class="pet-carousel">' + procuraCards + procuraCards + '</div></div>'
      : '<div class="info">Nenhum caso de procura-se aprovado pelo filtro.</div>') +
    '</div></section>\n' +

    '<section class="landing-section landing-section-alt"><div class="landing-container">' +
    '<div class="landing-grid"><div><h2>Nossa Missão</h2>' +
    '<p>A ONG Amor Animal é dedicada ao resgate, reabilitação e realocação de animais em situação de vulnerabilidade. ' +
    'Movidos pela compaixão, trabalhamos incansavelmente para oferecer uma segunda chance a cada um deles, ' +
    'promovendo a posse responsável e o bem-estar animal em nossa comunidade.</p></div>' +
    '<div><div class="fieldset"><legend>Origem dos dados</legend>' +
    '<div style="font-size:2.4rem">📸</div>' +
    '<p style="margin-top:0.8rem;color:var(--text-color);font-size:0.9rem">Esta página foi gerada a partir dos posts públicos do perfil <b>@grupoamoranimal</b> ' +
    '(' + resumo.estatisticas.posts_coletados + ' posts analisados), simulando a população das tabelas da API do site.</p></div></div></div>' +
    '</div></section>\n' +

    '<section class="landing-section landing-section-white"><div class="landing-container cta">' +
    '<h2 class="text-center">Faça Parte da Mudança</h2>' +
    '<p>Sua ajuda, seja como voluntário, parceiro ou doador, é fundamental para continuarmos nosso trabalho.</p>' +
    '<a class="btn btn-teal" href="https://www.instagram.com/grupoamoranimal/" target="_blank" rel="noopener">Siga no Instagram</a>' +
    '<a class="btn btn-coral" href="#adocao">Adote um Pet</a>' +
    '<a class="btn btn-purple" href="#impacto">Veja os Números</a>' +
    '</div></section>\n' +

    '<footer class="site-footer"><div class="footer-inner">' +
    '<p><b>ONG Amor Animal Marília</b> — página OFFLINE de simulação gerada em ' + esc(now) + '</p>' +
    '<p style="margin-top:8px;opacity:.8">Dados públicos do Instagram @grupoamoranimal · Fonte: instagram-grupoamoranimal-resumo-mensal.json + instagram-grupoamoranimal-dataset.json · ' +
    'Réplica visual de <a href="https://amoranimal.ong.br" target="_blank" rel="noopener">amoranimal.ong.br</a> · Nenhum dado foi enviado à API real.</p>' +
    '</div></footer>\n' +

    '<script>' + JS + '</script>\n</body>\n</html>';
}

async function main() {
  if (!fs.existsSync(FILE_RESUMO)) {
    console.error('[simular-site] ERRO: resumo-mensal nao encontrado. Rode resumo-mensal.py antes.');
    process.exit(1);
  }
  const { resumo, posts } = carregarResumo();
  const { dados, rejeitados } = processar(posts);
  console.log('[simular-site] posts no resumo: ' + posts.length);
  console.log('[simular-site] validos (simulados): ' + dados.length);
  console.log('[simular-site] filtrados (input incorreto): ' + rejeitados.length);
  const porCat = {};
  dados.forEach((d) => { porCat[d.rota] = (porCat[d.rota] || 0) + 1; });
  console.log('[simular-site] por tabela: ' + JSON.stringify(porCat));

  await prepararImagens(dados);

  const html = buildHtml({ resumo, posts, dados, rejeitados });
  fs.writeFileSync(OUT_HTML, html);
  console.log('[simular-site] pagina gerada: ' + OUT_HTML + ' (' + (html.length / 1024).toFixed(1) + ' KB)');
}

main().catch((e) => { console.error('[simular-site] ERRO fatal:', e); process.exit(1); });

#!/usr/bin/env node
/**
 * simular-api.js — Filtra os inputs corretos e simula as tabelas da API Amor Animal
 * com os dados do resumo-mensal.
 *
 * Fluxo:
 *   1. Lê instagram-grupoamoranimal-resumo-mensal.json (+ legenda/foto do dataset)
 *   2. Para cada post calcula o payload (mesma lógica do sincronizar.js)
 *   3. Aplica FILTRO DE QUALIDADE (inputs corretos por tabela)
 *   4. Gera instagram-grupoamoranimal-simulacao.html simulando a visualização
 *      das tabelas da API (adocao, procura_se, eventos) populadas
 *
 * Uso:
 *   node simular-api.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_RESUMO = path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.json');
const FILE_DATASET = path.join(DIR, 'instagram-grupoamoranimal-dataset.json');
const OUT_HTML = path.join(DIR, 'instagram-grupoamoranimal-simulacao.html');
const API_BASE = 'https://api.projetosdinamicos.com.br/amoranimal';
const ENDPOINTS = ['adocao', 'procura_se', 'eventos', 'castracao', 'adotado', 'home'];

// ─── Helpers (espelho do sincronizar.js) ─────────────────────────────────────

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
};

// ─── FILTRO DE QUALIDADE (inputs corretos) ───────────────────────────────────

const STOP_NOME = new Set([
  // palavras de parada: frases iniciais, conectivos, dias/meses, numerais e adjetivos comuns (nao sao nome de pet)
  'agradecemos', 'agradecimento', 'agradeco', 'obrigado', 'obrigada', 'votem', 'voto', 'vote', 'apoiem',
  'ajude', 'ajudar', 'ajuda', 'precisamos', 'precisa', 'preciso', 'precisando', 'conheca', 'participe',
  'participacao', 'participação', 'compareca', 'convidamos', 'convida', 'doacao', 'doacoes', 'doe', 'doar',
  'arrecadacao', 'arrecadando', 'vaquinha', 'rifa', 'campanha', 'mutirao', 'feirinha', 'feira', 'evento',
  'eventos', 'castracao', 'castrar', 'castra', 'vacina', 'vacinacao', 'adocao', 'adote', 'adotar', 'adota',
  'adotou', 'adotada', 'adotado', 'adotados', 'quero', 'quer', 'venha', 'temos', 'vamos', 'ter', 'curta',
  'compartilhe', 'compartilha', 'divulgue', 'divulg', 'salve', 'salvem', 'resgate', 'juntos', 'aniversario',
  'natal', 'feliz', 'parabens', 'hoje', 'amanha', 'sabado', 'domingo', 'sexta', 'link', 'bio', 'instagram',
  'whatsapp', 'gratidao', 'gratidão', 'dia', 'dias', 'sos', 'urgente', 'noticia', 'noticias', 'recursos',
  'projeto', 'edital', 'emenda', 'parlamentar', 'conseguir', 'conseguiu', 'conseguimos', 'consegue', 'semana',
  'mes', 'anos', 'ano', 'animal', 'animais', 'pets', 'peludinhos', 'peludinho', 'mensagem', 'sobre', 'nossa',
  'nosso', 'todos', 'tudo', 'estamos', 'ja', 'ate', 'vem', 'pedimos', 'gostaria', 'disponiveis', 'disponíveis',
  // iniciadores de frase e conectivos
  'mais', 'mas', 'neste', 'nesta', 'nesse', 'nessa', 'nesses', 'nessas', 'estes', 'estas', 'esses', 'essas',
  'esse', 'essa', 'uma', 'um', 'uns', 'umas', 'voce', 'ela', 'ele', 'elas', 'eles', 'por', 'para', 'pra',
  'em', 'no', 'na', 'nao', 'nos', 'de', 'do', 'da', 'das', 'dos', 'a', 'o', 'os', 'as', 'agora', 'ontem', 'quando',
  'onde', 'como', 'porque', 'se', 'ainda', 'depois', 'antes', 'so', 'muito', 'muita', 'muitos', 'muitas',
  'faca', 'fazer', 'troque', 'troca', 'contribua', 'mude', 'transforme',
  // meses
  'janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
  'novembro', 'dezembro',
  // adjetivos/descritores comuns que nao sao nome
  'pequena', 'pequeno', 'pequenos', 'pequenas', 'grande', 'grandes', 'media', 'medio', 'medios', 'filhote',
  'filhotes', 'femea', 'macho', 'machos', 'gata', 'gato', 'gatos', 'gatas', 'gatinho', 'gatinha', 'gatinhos',
  'gatinhas', 'cachorro', 'cachorra', 'cachorrinhos', 'cachorrinha', 'cadelinha', 'cadelinhas', 'canino',
  'felino', 'adoravel', 'linda', 'lindo', 'lindinha', 'bonita', 'bonito', 'fofa', 'fofo', 'docil', 'castrado',
  'castrada', 'vacinado', 'vacinada', 'resgatado', 'resgatada', 'adotavel', 'pet', 'companheiro', 'companheira',
  'novinho', 'novinha', 'idoso', 'idosa', 'amigao', 'carinhosa', 'carinhoso',
  // entidades / nomes locais (nao sao pets disponiveis)
  'marilia', 'ong', 'cedvet', 'aasu', 'bild', 'univem',
]);

const CTX_ADOCAO = ['adot', 'lar', 'castrad', 'resgat', 'filhot', 'femea', 'macho', 'doci', 'amorosa', 'amoroso', 'vacinad', 'pet', 'dona', 'tutor'];
const CTX_EVENTO = ['feira', 'mutirao', 'castra', 'evento', 'dia', 'sabado', 'domingo', 'sexta', 'local', 'onde', 'horario', 'compareca', 'particip', 'realiz', 'acontec', 'vagas'];

// marcadores de post de campanha/anuncio/agradecimento (nao e um pet individual disponivel)
function ehCampanha(c) {
  return tem(c,
    'feirinha', 'feira de ado', 'feira solidaria', 'mutirao', 'campanha', 'vaquinha', 'rifa', 'arrecadac',
    'doacao responsavel', 'dia mundial', 'aniversario', '7 motivos', 'motivos para', 'aviso importante',
    'nos ajude', 'dependemos', 'um dia pode mudar', 'uma boa racao', 'puppy', 'expo da univem',
    'preconceito ainda', 'abril pet', 'quatro patas', 'historia de', 'convidam', 'convidamos', 'convida voce',
    'parceria com', 'transformar uma vida', 'mudar a vida', 'e possivel', 'estamos precisando', 'suas doacoes',
    'sua doacao', 'sua ajuda', 'sua colaboracao', 'quem quiser', 'vai rolar', 'rolar uma', 'super especial',
    'mes de conscientizacao', 'dia do cachorro', 'dia do gato', 'agradecemos', 'obrigada a todos',
    'ja tem lar', 'tem lar', 'encontrou um lar', 'encontrou uma familia', 'novo lar em', 'ganhou um lar',
    'ganharam um lar', 'agora tem um lar', 'agora segui', 'seguiu feliz', 'seguindo feliz', 'semana passada',
    'uma voluntaria da ong', 'cuida de mais de', 'mais de 300', 'heroidequatropatas', 'quadrinhos',
    'carrega a bandeira', 'faca o mesmo', 'transforme vidas',
  );
}

function validarAdocao(p, pl) {
  const cap = p.legenda || '';
  const c = norm(cap);
  const tit = norm(p.titulo || '');
  const proprio = nomePet(cap);
  if (!proprio) return { ok: false, motivo: 'sem nome próprio de pet na legenda' };
  const nome = norm(proprio);
  if (nome.length < 2) return { ok: false, motivo: 'sem nome de pet' };
  if (/\s/.test(nome) || nome.length > 12) return { ok: false, motivo: 'nome não é nome próprio ("' + proprio + '")' };
  if (STOP_NOME.has(nome)) return { ok: false, motivo: 'nome genérico ("' + proprio + '")' };
  if (ehCampanha(c + ' ' + tit)) return { ok: false, motivo: 'post de campanha/anúncio' };
  if (tem(c, 'foi adotad', 'foram adotad', 'ja adotad') && !tem(c, 'devolvid', 'voltou', 'retornou', 'de volta'))
    return { ok: false, motivo: 'pet já adotado' };
  if (!CTX_ADOCAO.some((w) => c.includes(w))) return { ok: false, motivo: 'legenda sem contexto de adoção' };
  return { ok: true, motivo: null };
}
function validarProcura(p, pl) {
  const cap = p.legenda || '';
  const c = norm(cap);
  const proprio = nomePet(cap);
  if (!proprio) return { ok: false, motivo: 'sem nome próprio do pet na legenda' };
  const nome = norm(proprio);
  if (STOP_NOME.has(nome)) return { ok: false, motivo: 'nome genérico ("' + proprio + '")' };
  if (!telefone(c)) return { ok: false, motivo: 'sem telefone de contato na legenda' };
  if (!tem(c, 'sumiu', 'desaparec', 'procura', 'fugiu', 'perdeu', 'nao ach', 'nao vim')) return { ok: false, motivo: 'legenda sem contexto de desaparecimento' };
  return { ok: true, motivo: null };
}
function validarEvento(p, pl) {
  const c = norm(p.legenda || '');
  if (!pl.data_evento || pl.data_evento === p.data_iso) return { ok: false, motivo: 'data do evento não identificada no texto' };
  if (!CTX_EVENTO.some((w) => c.includes(w))) return { ok: false, motivo: 'legenda sem contexto de evento' };
  const d = new Date(pl.data_evento);
  const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  if (!isNaN(d) && d < hoje) return { ok: false, motivo: 'data no passado (relato, não evento futuro)' };
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
  return posts;
}

async function buscarApi() {
  const cacheDir = path.join(DIR, '.api-cache');
  const out = {};
  for (const ep of ENDPOINTS) {
    const cache = path.join(cacheDir, ep + '.json');
    try {
      const res = await fetch(API_BASE + '/' + ep);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      out[ep] = Array.isArray(data) ? data.length : 0;
    } catch (e) {
      out[ep] = fs.existsSync(cache) ? JSON.parse(fs.readFileSync(cache, 'utf8')).length : 0;
    }
  }
  return out;
}

// ─── Montagem ────────────────────────────────────────────────────────────────

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const fmtData = (iso) => {
  if (!iso) return '—';
  const d = iso.length > 10 ? new Date(iso) : new Date(iso + 'T00:00:00');
  if (isNaN(d)) return iso;
  const p = (n) => String(n).padStart(2, '0');
  return p(d.getDate()) + '/' + p(d.getMonth() + 1) + '/' + d.getFullYear();
};

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
      categoria: p.categoria, rota: map.rota, label: map.label,
      payload,
    };
    if (valid.ok) dados.push(item);
    else rejeitados.push(Object.assign(item, { motivo: valid.motivo }));
  });
  return { dados, rejeitados };
}

const CSS = `
:root{--bg:linear-gradient(135deg,#f5f7fa,#e8ecf1);--surface:rgba(255,255,255,0.92);--border:rgba(0,0,0,0.07);--text:#1a1a2e;--muted:#555;--dim:#999;--grad:linear-gradient(45deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888);--c-adocao:#0a7d4f;--bg-adocao:rgba(10,125,79,0.12);--c-castracao:#1d4ed8;--bg-castracao:rgba(29,78,216,0.12);--c-procura:#c2410c;--bg-procura:rgba(194,65,12,0.12);--c-doacao:#a21caf;--bg-doacao:rgba(162,28,175,0.12);--c-outros:#6b7280;--bg-outros:rgba(107,114,128,0.14);--shadow:0 4px 16px rgba(0,0,0,0.08)}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,sans-serif;background:var(--bg);min-height:100vh;color:var(--text)}
header{background:rgba(255,255,255,0.85);backdrop-filter:blur(12px);padding:14px 30px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:14px;box-shadow:0 1px 3px rgba(0,0,0,0.06);position:sticky;top:0;z-index:50;flex-wrap:wrap}
.ig-icon{width:36px;height:36px;border-radius:10px;background:var(--grad);display:flex;align-items:center;justify-content:center;font-size:1.2rem}
header h1{font-size:1.25rem;font-weight:700;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
header .sub{font-size:0.72rem;color:var(--dim);width:100%}
.container{max-width:1280px;margin:0 auto;padding:20px 24px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.card .v{font-size:1.4rem;font-weight:800;background:var(--grad);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.card .l{font-size:0.7rem;color:var(--muted);text-transform:uppercase;letter-spacing:0.6px;margin-top:2px}
.section-title{font-size:1.05rem;font-weight:700;margin:26px 0 12px;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.section-title .bar{width:4px;height:18px;border-radius:2px;background:var(--grad)}
.info{font-size:0.78rem;color:var(--dim);margin-bottom:14px}
.destaque{background:rgba(204,35,102,0.05);border:1px solid rgba(204,35,102,0.15);border-radius:12px;padding:14px 16px;margin-bottom:16px;font-size:0.85rem;color:var(--muted)}
.destaque b{color:var(--text)}
.pet-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px}
.pet-card{background:var(--surface);border:1px solid var(--border);border-radius:14px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06);transition:transform .18s,box-shadow .18s;display:flex;flex-direction:column}
.pet-card:hover{transform:translateY(-2px);box-shadow:var(--shadow)}
.pet-ph{height:150px;background:linear-gradient(135deg,#fce4ec,#f3e5f5);display:flex;align-items:center;justify-content:center;font-size:2.6rem;color:#c2185b}
.pet-ph img{width:100%;height:100%;object-fit:cover}
.pet-body{padding:12px 14px;flex:1;display:flex;flex-direction:column}
.pet-name{font-size:1.02rem;font-weight:800}
.pet-meta{display:flex;gap:6px;flex-wrap:wrap;margin:6px 0}
.pill{font-size:0.64rem;font-weight:700;padding:2px 8px;border-radius:12px;background:rgba(0,0,0,0.05);color:var(--muted);text-transform:uppercase;letter-spacing:0.4px}
.pill-especie{background:rgba(29,78,216,0.1);color:#1d4ed8}
.pill-porte{background:rgba(162,28,175,0.1);color:#a21caf}
.pill-idade{background:rgba(10,125,79,0.1);color:#0a7d4f}
.pet-desc{font-size:0.76rem;color:var(--muted);line-height:1.5;flex:1}
.pet-foot{display:flex;align-items:center;gap:8px;margin-top:10px;padding-top:10px;border-top:1px solid rgba(0,0,0,0.05);font-size:0.72rem;color:var(--dim);flex-wrap:wrap}
.status{font-size:0.66rem;font-weight:800;padding:3px 9px;border-radius:20px;text-transform:uppercase;letter-spacing:0.5px}
.status-disponivel{background:rgba(16,185,129,0.14);color:#047857}
.status-procura{background:rgba(194,65,12,0.14);color:#c2410c}
.status-evento{background:rgba(29,78,216,0.12);color:#1d4ed8}
.link-ig{color:#cc2366;text-decoration:none;font-weight:700;margin-left:auto}
.link-ig:hover{text-decoration:underline}
.event-date{background:var(--grad);color:#fff;padding:8px 12px;font-weight:800;font-size:0.78rem;text-align:center}
table{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);font-size:0.8rem}
thead th{text-align:left;font-size:0.68rem;text-transform:uppercase;letter-spacing:0.6px;color:var(--dim);padding:10px 12px;background:rgba(0,0,0,0.03);border-bottom:1px solid var(--border);white-space:nowrap}
tbody td{padding:9px 12px;border-bottom:1px solid rgba(0,0,0,0.04);vertical-align:top}
tbody tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(204,35,102,0.04)}
.badge{font-size:0.62rem;text-transform:uppercase;letter-spacing:0.5px;padding:2px 8px;border-radius:20px;font-weight:700;white-space:nowrap}
.badge-adocao{background:var(--bg-adocao);color:var(--c-adocao)}
.badge-castracao{background:var(--bg-castracao);color:var(--c-castracao)}
.badge-procura-se{background:var(--bg-procura);color:var(--c-procura)}
.motivo{color:#b45309;font-size:0.74rem}
.controls{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px}
.controls input{padding:9px 14px;border-radius:10px;border:1px solid var(--border);background:var(--surface);font-family:inherit;font-size:0.85rem;color:var(--text);outline:none;flex:1;min-width:200px}
.controls input:focus{border-color:#cc2366;box-shadow:0 0 0 3px rgba(204,35,102,0.1)}
.card-hide{display:none!important}
.row-hide{display:none!important}
.empty{grid-column:1/-1;text-align:center;color:var(--dim);padding:40px 0}
footer{text-align:center;padding:30px;color:var(--dim);font-size:0.75rem}
.toolbar{position:fixed;bottom:20px;right:20px;display:flex;gap:8px;z-index:10}
.toolbar button{padding:10px 16px;border-radius:8px;border:none;cursor:pointer;font-size:0.82rem;font-weight:600;box-shadow:var(--shadow);font-family:inherit}
.btn-top{background:#fff;color:var(--text);border:1px solid var(--border)!important}
@media(max-width:700px){header{padding:12px 16px}}
`;

const JS = `
document.getElementById('busca').addEventListener('input', e => {
  const q = e.target.value.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g,'');
  document.querySelectorAll('.pet-card, .card-filtro').forEach(el => {
    const txt = el.getAttribute('data-busca') || '';
    el.classList.toggle('card-hide', !!q && !txt.includes(q));
  });
  document.querySelectorAll('#rejeitados tbody tr').forEach(tr => {
    const txt = tr.getAttribute('data-busca') || '';
    tr.classList.toggle('row-hide', !!q && !txt.includes(q));
  });
});
`;

function buildHtml(posts, apiCount) {
  const { dados, rejeitados } = processar(posts);
  const porRota = {};
  dados.forEach((d) => { (porRota[d.rota] = porRota[d.rota] || []).push(d); });
  const nomeMes = { 1: 'Janeiro', 2: 'Fevereiro', 3: 'Março', 4: 'Abril', 5: 'Maio', 6: 'Junho', 7: 'Julho', 8: 'Agosto', 9: 'Setembro', 10: 'Outubro', 11: 'Novembro', 12: 'Dezembro' };

  const buscaAttr = (s) => esc(norm(s));

  function fotoHtml(d, alt) {
    return d.thumbnail
      ? '<div class="pet-ph"><img loading="lazy" src="' + esc(d.thumbnail) + '" alt="' + esc(alt) + '"></div>'
      : '<div class="pet-ph">🐾</div>';
  }

  // ── /adocao (agrupado por pet) ──
  const grupos = {};
  (porRota['/adocao'] || []).forEach((d) => {
    const k = norm(d.payload.nome);
    (grupos[k] = grupos[k] || []).push(d);
  });
  const adocaoCards = Object.keys(grupos).map((k) => {
    const g = grupos[k], d = g[g.length - 1], pl = d.payload;
    const nomes = g.map((x) => x.titulo).join(' ');
    const chips = [];
    if (pl.especie) chips.push('<span class="pill pill-especie">' + esc({ felino: 'Gato', canino: 'Cachorro' }[pl.especie] || pl.especie) + '</span>');
    if (pl.porte) chips.push('<span class="pill pill-porte">' + esc(pl.porte) + '</span>');
    if (pl.idade) chips.push('<span class="pill pill-idade">' + esc(pl.idade) + '</span>');
    return '<div class="pet-card" data-busca="' + buscaAttr((pl.nome || '') + ' ' + (pl.caracteristicas || '') + ' ' + nomes) + '">' +
      fotoHtml(d, pl.nome) +
      '<div class="pet-body">' +
      '<div class="pet-name">' + esc(pl.nome) + (g.length > 1 ? ' <span class="pill">' + g.length + ' posts</span>' : '') + '</div>' +
      '<div class="pet-meta">' + chips.join('') + '</div>' +
      '<div class="pet-desc">' + esc(pl.caracteristicas || '') + '</div>' +
      '<div class="pet-foot"><span class="status status-disponivel">Disponível</span>' +
      '<span>' + fmtData(d.data) + '</span>' +
      '<a class="link-ig" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver post &#8599;</a></div>' +
      '</div></div>';
  }).join('');

  // ── /procura_se ──
  const procuraCards = (porRota['/procura_se'] || []).map((d) => {
    const pl = d.payload;
    return '<div class="pet-card" data-busca="' + buscaAttr((pl.pet_nome || '') + ' ' + (pl.pet_caracteristicas || '') + ' ' + d.titulo) + '">' +
      fotoHtml(d, pl.pet_nome) +
      '<div class="pet-body">' +
      '<div class="pet-name">🔎 ' + esc(pl.pet_nome) + '</div>' +
      '<div class="pet-meta">' +
      '<span class="pill pill-especie">' + esc(pl.pet_especie || 'Outro') + '</span>' +
      (pl.pet_porte ? '<span class="pill pill-porte">' + esc(pl.pet_porte) + '</span>' : '') +
      (pl.pet_idade ? '<span class="pill pill-idade">' + esc(pl.pet_idade) + '</span>' : '') +
      '</div>' +
      '<div class="pet-desc">' + esc(pl.pet_caracteristicas || '') + '</div>' +
      '<div class="pet-foot"><span class="status status-procura">Procura-se</span>' +
      '<span>' + esc(pl.local_desaparecimento || '') + (pl.data_desaparecimento ? ' · ' + fmtData(pl.data_desaparecimento) : '') + '</span>' +
      '<span style="margin-left:auto;color:var(--c-castracao)">📞 ' + esc(pl.tutor_contato || '') + '</span></div>' +
      '<div class="pet-foot" style="border:none;padding-top:2px"><a class="link-ig" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver post &#8599;</a></div>' +
      '</div></div>';
  }).join('');

  // ── /eventos ──
  const eventoCards = (porRota['/eventos'] || []).map((d) => {
    const pl = d.payload;
    const dt = pl.data_evento ? new Date(pl.data_evento) : null;
    const dtHtml = dt && !isNaN(dt)
      ? '<div class="event-date">' + String(dt.getDate()).padStart(2, '0') + '/' + String(dt.getMonth() + 1).padStart(2, '0') + '/' + dt.getFullYear() + '</div>'
      : '<div class="event-date">Data não informada</div>';
    return '<div class="pet-card" data-busca="' + buscaAttr((pl.titulo || '') + ' ' + (pl.descricao || '')) + '">' +
      dtHtml + fotoHtml(d, pl.titulo) +
      '<div class="pet-body">' +
      '<div class="pet-name">📅 ' + esc(pl.titulo) + '</div>' +
      '<div class="pet-meta"><span class="pill pill-especie">Evento</span>' +
      '<span class="pill pill-porte">Castração/Adoção</span></div>' +
      '<div class="pet-desc">' + esc((pl.descricao || '').slice(0, 220)) + (pl.descricao && pl.descricao.length > 220 ? '…' : '') + '</div>' +
      '<div class="pet-foot"><span class="status status-evento">Evento</span>' +
      '<span>' + fmtData(d.data) + '</span>' +
      '<a class="link-ig" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver post &#8599;</a></div>' +
      '</div></div>';
  }).join('');

  // ── rejeitados ──
  const rejRows = rejeitados.map((d) =>
    '<tr data-busca="' + buscaAttr((d.titulo + ' ' + (d.legenda || '') + ' ' + (d.motivo || ''))) + '">' +
    '<td style="white-space:nowrap">' + fmtData(d.data) + '</td>' +
    '<td>' + badge(d.categoria) + '</td>' +
    '<td><b>' + esc(d.rota) + '</b></td>' +
    '<td>' + esc(d.titulo) + '<br><a class="link-ig" target="_blank" rel="noopener" href="' + esc(d.url) + '">ver &#8599;</a></td>' +
    '<td class="motivo">' + esc(d.motivo) + '</td></tr>').join('');

  function badge(c) {
    return '<span class="badge badge-' + c + '">' + ({ adocao: 'Adoção', castracao: 'Castração', 'procura-se': 'Procura-se' }[c] || c) + '</span>';
  }

  const now = new Date().toLocaleString('pt-BR');
  const totalValidos = dados.length;
  const totalRejeitados = rejeitados.length;
  const naoMapeados = posts.length - totalValidos - totalRejeitados;

  return '<!DOCTYPE html>\n<html lang="pt-BR">\n<head>\n<meta charset="UTF-8">\n' +
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
    '<title>@grupoamoranimal - Simulação das tabelas da API</title>\n<style>' + CSS + '</style>\n</head>\n<body>\n' +
    '<header><div class="ig-icon">&#128062;</div><h1>@grupoamoranimal - Simulação das tabelas da API Amor Animal</h1>' +
    '<div class="sub">Posts do resumo-mensal filtrados pelos inputs corretos e simulados dentro das tabelas da API · ' +
    Object.keys(ROTAS).map((c) => { const r = ROTAS[c]; return r.label + ': ' + (porRota[r.rota] ? porRota[r.rota].length : 0) + ''; }).join(' · ') +
    ' · gerado em ' + esc(now) + '</div></header>\n' +
    '<div class="container">\n' +
    '<div class="destaque"><b>Filtro de qualidade aplicado.</b> Cada post do resumo foi convertido no payload da tabela correspondente ' +
    '(mesma lógica do sincronizar.js) e passou pela validação de inputs (nome próprio, contexto, data e contato). ' +
    'Somente os aprovados entram na simulação; os reprovados aparecem na tabela de filtrados no fim.</div>\n' +
    '<div class="cards">' +
    '<div class="card"><div class="v">' + totalValidos + '</div><div class="l">Posts válidos (simulados)</div></div>' +
    '<div class="card"><div class="v">' + totalRejeitados + '</div><div class="l">Filtrados (input incorreto)</div></div>' +
    '<div class="card"><div class="v">' + naoMapeados + '</div><div class="l">Sem tabela (doação/outros)</div></div>' +
    '<div class="card"><div class="v">' + posts.length + '</div><div class="l">Total no resumo</div></div>' +
    '</div>\n' +
    '<div class="controls"><input type="text" id="busca" placeholder="Filtrar por nome do pet, título ou texto..."></div>\n' +

    '<div class="section-title"><span class="bar"></span>/adocao — Animais disponíveis para adoção' +
    ' <span class="badge badge-adocao">' + Object.keys(grupos).length + ' pets</span>' +
    ' <span style="font-size:0.72rem;color:var(--dim)">(na API hoje: ' + apiCount.adocao + ')</span></div>' +
    '<div class="info">' + (porRota['/adocao'] || []).length + ' posts de adoção válidos, agrupados em ' + Object.keys(grupos).length + ' pets distintos.</div>' +
    '<div class="pet-grid">' + (adocaoCards || '<div class="empty">Nenhum pet de adoção aprovado pelo filtro.</div>') + '</div>\n' +

    '<div class="section-title"><span class="bar"></span>/procura_se — Pets desaparecidos' +
    ' <span class="badge badge-procura-se">' + (porRota['/procura_se'] || []).length + '</span>' +
    ' <span style="font-size:0.72rem;color:var(--dim)">(na API hoje: ' + apiCount.procura_se + ')</span></div>' +
    '<div class="pet-grid">' + (procuraCards || '<div class="empty">Nenhum caso de procura-se aprovado pelo filtro.</div>') + '</div>\n' +

    '<div class="section-title"><span class="bar"></span>/eventos — Eventos e mutirões' +
    ' <span class="badge badge-castracao">' + (porRota['/eventos'] || []).length + '</span>' +
    ' <span style="font-size:0.72rem;color:var(--dim)">(na API hoje: ' + apiCount.eventos + ')</span></div>' +
    '<div class="pet-grid">' + (eventoCards || '<div class="empty">Nenhum evento aprovado pelo filtro.</div>') + '</div>\n' +

    '<div class="section-title"><span class="bar"></span>Filtrados pelo controle de qualidade (' + totalRejeitados + ')</div>' +
    '<div class="info">Posts com inputs incorretos, descartados da simulação. Verifique o motivo para corrigir manualmente antes de postar.</div>' +
    '<div style="overflow-x:auto"><table id="rejeitados"><thead><tr>' +
    '<th>Data</th><th>Categoria</th><th>Tabela</th><th>Post de origem</th><th>Motivo do filtro</th></tr></thead><tbody>' +
    (rejRows || '<tr><td colspan="5" style="text-align:center;color:var(--dim)">Nenhum post foi filtrado.</td></tr>') +
    '</tbody></table></div>\n' +
    '</div>\n' +
    '<footer>Gerado automaticamente · Filtro de qualidade: nome próprio + contexto + data + contato · API: ' + esc(API_BASE) + '</footer>\n' +
    '<div class="toolbar"><button class="btn-top" onclick="window.scrollTo({top:0,behavior:\'smooth\'})">Topo</button></div>\n' +
    '<script>' + JS + '</script>\n</body>\n</html>';
}

async function main() {
  if (!fs.existsSync(FILE_RESUMO)) {
    console.error('[simular] ERRO: resumo-mensal nao encontrado. Rode resumo-mensal.py antes.');
    process.exit(1);
  }
  const posts = carregarResumo();
  const apiCount = await buscarApi();
  const html = buildHtml(posts, apiCount);
  fs.writeFileSync(OUT_HTML, html);
  const { dados, rejeitados } = processar(posts);
  console.log('[simular] posts no resumo: ' + posts.length);
  console.log('[simular] validos (simulados): ' + dados.length);
  console.log('[simular] filtrados (input incorreto): ' + rejeitados.length);
  const porMotivo = {};
  rejeitados.forEach((d) => { porMotivo[d.motivo] = (porMotivo[d.motivo] || 0) + 1; });
  console.log('[simular] motivos: ' + JSON.stringify(porMotivo, null, 2));
  console.log('[simular] pagina gerada: ' + OUT_HTML + ' (' + (html.length / 1024).toFixed(1) + ' KB)');
}

main().catch((e) => { console.error('[simular] ERRO fatal:', e); process.exit(1); });

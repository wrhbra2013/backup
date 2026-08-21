#!/usr/bin/env node
/**
 * sincronizar.js — Sincroniza o dataset do @grupoamoranimal com a API do site
 * (https://api.projetosdinamicos.com.br/amoranimal).
 *
 * Fluxo:
 *   1. Le instagram-grupoamoranimal-dataset.json
 *   2. Faz login na API (obtem token JWT)
 *   3. Aplica o filtro de qualidade (espelho do simular-api.js) e envia apenas
 *      os posts NOVOS aprovados (dedupe pelo code do Instagram via sincronizados.json)
 *
 * Imagens: envia a foto local de img-resumo-mensal/<code>.jpg em base64
 * (data:image/jpeg;base64,...), igual aos formularios do site. Se nao existir
 * a imagem local, cai para a URL do CDN (p.midia/p.thumbnail) como fallback.
 *
 * Mapeamento de categorias -> tabela da API:
 *   adocao     -> POST /adocao     (campo da foto: foto_url)
 *   procura-se -> POST /procura_se (campo da foto: foto_url)
 *   castracao  -> POST /eventos    (campo da foto: fotos)  [somente com --castracao]
 *   doacao/outros -> ignorados
 *
 * Uso:
 *   node sincronizar.js                       Sincroniza (adocao + procura-se)
 *   node sincronizar.js --castracao           Inclui posts de castracao como eventos
 *   node sincronizar.js --dry-run             Apenas mostra o que seria enviado
 *   node sincronizar.js --force               Reenvia todos os posts (ignora dedupe)
 *   node sincronizar.js --user X --pass Y     Credenciais (ou env API_USER/API_PASS)
 *   node sincronizar.js --api URL             URL base da API (padrao: producao)
 *
 * Requisitos: Node.js 18+ (fetch nativo).
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FILE_JSON = path.join(DIR, 'instagram-grupoamoranimal-dataset.json');
const FILE_STATE = path.join(DIR, 'sincronizados.json');
const IMG_DIR = path.join(DIR, 'img-resumo-mensal');

const API_PADRAO = 'https://api.projetosdinamicos.com.br/amoranimal';

let API = process.env.API_BASE || API_PADRAO;
let USER = process.env.API_USER || '';
let PASS = process.env.API_PASS || '';
let DRY_RUN = process.argv.includes('--dry-run');
let FORCE = process.argv.includes('--force');
let INCLUI_CASTRACAO = process.argv.includes('--castracao');
let LIMITE = null;

const arg = (name) => {
  const i = process.argv.indexOf(name);
  return i !== -1 ? process.argv[i + 1] : null;
};
API = arg('--api') || API;
USER = arg('--user') || USER;
PASS = arg('--pass') || PASS;
const lim = arg('--max');
if (lim) LIMITE = parseInt(lim, 10) || null;

const log = (...a) => console.log('[sincronizar]', ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ─── Autenticacao ────────────────────────────────────────────────────────────

async function login() {
  if (!USER || !PASS) {
    log('ERRO: informe usuario/senha (--user/--pass ou env API_USER/API_PASS).');
    process.exit(1);
  }
  log('Fazendo login como "' + USER + '"...');
  const res = await fetch(API + '/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ usuario: USER, senha: PASS }),
  });
  if (!res.ok) throw new Error('login HTTP ' + res.status);
  const data = await res.json();
  if (!data.token) throw new Error('login sem token na resposta');
  return data.token;
}

async function apipost(token, rota, payload) {
  const res = await fetch(API + rota, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + token,
    },
    body: JSON.stringify(payload),
  });
  const txt = await res.text();
  let body = null;
  try { body = JSON.parse(txt); } catch (_) {}
  if (!res.ok) {
    const msg = (body && (body.error || body.message)) || txt || ('HTTP ' + res.status);
    throw new Error(rota + ' -> ' + res.status + ' ' + msg);
  }
  return body;
}

// ─── Helpers de parsing ──────────────────────────────────────────────────────

const norm = (s = '') => (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');

function especie(cap) {
  const c = norm(cap);
  if (tem(c, 'gata', 'gato', 'gat ', 'felina', 'felino')) return 'felino';
  if (tem(c, 'cachorr', 'cao ', 'cÃ£o', 'canina', 'canino', 'dog')) return 'canino';
  return null;
}

function tem(c, ...p) { return p.some((w) => c.includes(w)); }

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

// ─── Imagens (base64 local, igual aos formularios do site) ───────────────────

function fotoBase64(code) {
  try {
    const file = path.join(IMG_DIR, code + '.jpg');
    if (fs.existsSync(file)) {
      return 'data:image/jpeg;base64,' + fs.readFileSync(file).toString('base64');
    }
  } catch (_) {}
  return null;
}

// ─── Mapeamento por categoria ────────────────────────────────────────────────

function payloadAdocao(p) {
  const cap = p.legenda || '';
  return {
    nome: nomePet(cap) || limparTexto(p.titulo, 45) || 'Pet para adoção',
    idade: idade(cap),
    especie: especie(cap),
    porte: porte(cap),
    caracteristicas: limparTexto(cap, 300) || null,
    foto_url: fotoBase64(p.code) || p.midia || p.thumbnail || null,
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
    foto_url: fotoBase64(p.code) || p.midia || p.thumbnail || null,
  };
}

function payloadEvento(p) {
  const cap = p.legenda || '';
  return {
    titulo: limparTexto(p.titulo, 90) || 'Mutirão de Castração',
    data_evento: (dataEvento(cap, p.data_iso) || '').slice(0, 10) || null,
    local: 'Marília/SP',
    descricao: cap || null,
    fotos: fotoBase64(p.code) || p.thumbnail || p.midia || null,
  };
}

// ─── Filtro de qualidade (espelho do simular-api.js) ─────────────────────────

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
  if (!pl.data_evento || pl.data_evento === p.data_iso.slice(0, 10)) return { ok: false, motivo: 'data do evento não identificada no texto' };
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

// ─── Principal ───────────────────────────────────────────────────────────────

function main() {
  if (!fs.existsSync(FILE_JSON)) {
    log('ERRO: dataset nao encontrado: ' + FILE_JSON);
    log('Rode primeiro: node atualizar.js');
    process.exit(1);
  }
  const dataset = JSON.parse(fs.readFileSync(FILE_JSON, 'utf8'));

  let estado = {};
  if (fs.existsSync(FILE_STATE)) {
    try { estado = JSON.parse(fs.readFileSync(FILE_STATE, 'utf8')); } catch (_) {}
  }

  const mapRotas = { adocao: '/adocao', 'procura-se': '/procura_se' };
  if (INCLUI_CASTRACAO) mapRotas.castracao = '/eventos';

  let pendentes = dataset.posts.filter((p) => mapRotas[p.categoria]);
  if (!FORCE) pendentes = pendentes.filter((p) => !estado[p.code]);
  if (LIMITE) pendentes = pendentes.slice(0, LIMITE);

  log('posts no dataset : ' + dataset.posts.length);
  log('ja sincronizados  : ' + Object.keys(estado).length);
  log('a sincronizar     : ' + pendentes.length + (LIMITE ? ' (limite ' + LIMITE + ')' : ''));
  const comImgLocal = pendentes.filter((p) => fotoBase64(p.code)).length;
  log('com imagem local  : ' + comImgLocal + '/' + pendentes.length + ' (img-resumo-mensal)');
  for (const r in mapRotas) {
    const n = dataset.posts.filter((p) => p.categoria === r).length;
    log('  categoria "' + r + '" -> ' + mapRotas[r] + ' (' + n + ' no dataset)');
  }
  if (!pendentes.length) { log('nada novo para enviar.'); return; }
  if (DRY_RUN) { log('=== DRY RUN: nada sera enviado ==='); }

  let token = null;
  if (!DRY_RUN) token = login();

  Promise.resolve(token).then(async (tok) => {
    let ok = 0, falha = 0, pulado = 0, filtrado = 0;
    for (const p of pendentes) {
      let payload;
      const rota = mapRotas[p.categoria];
      try {
        if (p.categoria === 'adocao') payload = payloadAdocao(p);
        else if (p.categoria === 'procura-se') payload = payloadProcuraSe(p);
        else if (p.categoria === 'castracao') payload = payloadEvento(p);
        else throw new Error('categoria sem mapeamento: ' + p.categoria);
      } catch (e) {
        log('pulando ' + p.code + ': ' + e.message);
        pulado++;
        continue;
      }

      const val = VALIDADORES[rota](p, payload);
      if (!val.ok) {
        log('FILTRADO ' + p.categoria + ' ' + p.code + ' -> ' + rota + ' | ' + val.motivo + ' | ' + (payload.nome || payload.pet_nome || payload.titulo || ''));
        filtrado++;
        continue;
      }

      if (DRY_RUN) {
        const img = payload.foto_url || payload.fotos;
        const imgInfo = img ? (img.startsWith('data:') ? 'foto base64 (' + Math.round(img.length / 1024) + ' KB)' : 'foto url') : 'sem foto';
        log('[dry] ' + p.categoria + ' ' + p.code + ' -> ' + rota + ' | ' + (payload.nome || payload.pet_nome || payload.titulo || '') + ' | ' + imgInfo);
        ok++;
        continue;
      }

      try {
        const resp = await apipost(tok, rota, payload);
        const novoId = resp && (resp.id != null ? resp.id : resp.pet && resp.pet.id);
        estado[p.code] = { code: p.code, tabela: rota, api_id: novoId != null ? novoId : null, data_iso: p.data_iso, sincronizado_em: new Date().toISOString() };
        ok++;
        log('OK ' + p.code + ' -> ' + rota + (novoId != null ? ' (id ' + novoId + ')' : ''));
      } catch (e) {
        falha++;
        log('FALHA ' + p.code + ' -> ' + e.message);
        if (falha >= 10) { log('desistindo apos 10 falhas.'); break; }
      }
      await sleep(250);
    }

    if (!DRY_RUN && ok > 0) {
      fs.writeFileSync(FILE_STATE, JSON.stringify(estado, null, 2));
      log('estado salvo em ' + FILE_STATE);
    }
    log('===== RESUMO =====');
    log('enviados : ' + ok);
    log('filtrados: ' + filtrado + ' (controle de qualidade)');
    log('falhas   : ' + falha);
    log('pulados  : ' + pulado);
    if (DRY_RUN) log('(dry-run — nada foi enviado)');
  }).catch((e) => {
    log('ERRO fatal: ' + e.message);
    process.exit(1);
  });
}

main();

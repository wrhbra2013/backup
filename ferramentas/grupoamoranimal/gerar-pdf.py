#!/usr/bin/env python3
"""gerar-pdf.py — Gera PDF com auditoria do projeto Grupo Amor Animal."""

import json, os, sys, re, urllib.request
from datetime import datetime
from fpdf import FPDF

DIR = os.path.dirname(os.path.abspath(__file__))
API_BASE = 'https://api.projetosdinamicos.com.br/amoranimal'
ENDPOINTS = ['adocao', 'procura_se', 'eventos', 'castracao', 'adotado', 'home']

def limpar(txt):
    """Remove emojis e caracteres nao-latin1 para o Helvetica."""
    s = str(txt)
    s = re.sub(r'[\U0001F000-\U0001FFFF]', '', s)
    s = s.encode('latin-1', 'replace').decode('latin-1')
    return s

def carregar_json(nome):
    path = os.path.join(DIR, nome)
    if not os.path.exists(path): return None
    with open(path, encoding='utf-8') as f: return json.load(f)

def buscar_api():
    dados = {}
    for ep in ENDPOINTS:
        try:
            with urllib.request.urlopen(API_BASE + '/' + ep, timeout=15) as r:
                dados[ep] = json.loads(r.read().decode('utf-8'))
        except Exception:
            dados[ep] = []
    return dados

def contar_categorias(dataset):
    cats = {}
    for p in dataset.get('posts', []):
        c = p.get('categoria', 'outros')
        cats[c] = cats.get(c, 0) + 1
    return cats

print('[pdf] coletando dados...')
api = buscar_api()
dataset = carregar_json('instagram-grupoamoranimal-dataset.json')
filtrado = carregar_json('dataset-filtrado.json')
resumo = carregar_json('instagram-grupoamoranimal-resumo-mensal.json')

api_total = sum(len(v) for v in api.values())
cat_dataset = contar_categorias(dataset) if dataset else {}
total_posts = dataset.get('metadados', {}).get('posts_coletados', 0) if dataset else 0
cobertura = dataset.get('metadados', {}).get('cobertura', 'n/d') if dataset else 'n/d'

payloads_prontos = 0
if filtrado:
    for cat, info in filtrado.get('por_categoria', {}).items():
        for p in info.get('posts', []):
            if p.get('api'): payloads_prontos += 1

por_ano = {}
if resumo:
    for ano, dados in resumo.get('por_ano', {}).items():
        por_ano[ano] = dados.get('quantidade_posts', 0)

class PDF(FPDF):
    def header(self):
        self.set_font('Helvetica', 'B', 9)
        self.set_text_color(150, 150, 150)
        self.cell(0, 6, limpar('Auditoria - Grupo Amor Animal - ' + datetime.now().strftime('%d/%m/%Y')), align='R')
        self.ln(8)

    def footer(self):
        self.set_y(-15)
        self.set_font('Helvetica', '', 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, 'Pagina %d/{nb}' % self.page_no(), align='C')

    def tit(self, txt):
        self.set_x(10)
        self.set_font('Helvetica', 'B', 16)
        self.set_text_color(30, 30, 60)
        self.cell(0, 12, limpar(txt))
        self.ln(10)
        self.set_draw_color(204, 35, 102)
        self.set_line_width(0.8)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(6)

    def sub(self, txt):
        self.set_x(10)
        self.set_font('Helvetica', 'B', 12)
        self.set_text_color(204, 35, 102)
        self.cell(0, 9, limpar(txt))
        self.ln(8)

    def s2(self, txt):
        self.set_x(10)
        self.set_font('Helvetica', 'B', 10)
        self.set_text_color(50, 50, 80)
        self.cell(0, 7, limpar(txt))
        self.ln(6)

    def txt(self, txt):
        self.set_x(10)
        self.set_font('Helvetica', '', 9.5)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 5.2, limpar(txt))
        self.ln(2)

    def neg(self, txt):
        self.set_x(10)
        self.set_font('Helvetica', 'B', 9.5)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 5.2, limpar(txt))
        self.ln(1)

    def lst(self, itens):
        self.set_font('Helvetica', '', 9.5)
        self.set_text_color(40, 40, 40)
        for item in itens:
            self.set_x(10)
            self.multi_cell(0, 5.2, limpar('  - ' + item))
        self.ln(2)

    def tbl(self, cab, linhas, largs=None):
        if not largs: largs = [190 / len(cab)] * len(cab)
        self.set_font('Helvetica', 'B', 8.5)
        self.set_fill_color(240, 240, 245)
        self.set_text_color(50, 50, 80)
        for i, h in enumerate(cab):
            self.cell(largs[i], 7, limpar(h), border=1, fill=True)
        self.ln()
        self.set_font('Helvetica', '', 8.5)
        self.set_text_color(40, 40, 40)
        for linha in linhas:
            if self.get_y() > 268: self.add_page()
            for i, val in enumerate(linha):
                self.cell(largs[i], 6.5, limpar(str(val)[:55]), border=1)
            self.ln()
        self.ln(3)
        self.set_x(10)

    def code(self, txt):
        self.set_fill_color(26, 26, 46)
        self.set_font('Courier', '', 7.5)
        self.set_text_color(209, 250, 229)
        x, y = self.get_x(), self.get_y()
        linhas = txt.split('\n')
        h = len(linhas) * 4.2 + 6
        if y + h > 272:
            self.add_page()
            y = self.get_y()
        self.rect(x, y, 190, h, 'F')
        self.set_xy(x + 4, y + 3)
        for l in linhas:
            self.cell(0, 4.2, limpar(l))
            self.ln(4.2)
        self.set_y(y + h + 3)
        self.set_x(10)

    def dest(self, txt):
        self.set_fill_color(255, 245, 248)
        self.set_draw_color(204, 35, 102)
        self.set_font('Helvetica', '', 9.5)
        self.set_text_color(80, 40, 60)
        x, y = self.get_x(), self.get_y()
        self.rect(x, y, 190, 14, 'D')
        self.set_xy(x + 3, y + 2)
        self.multi_cell(184, 5, limpar(txt))
        self.set_y(y + 16)
        self.set_x(10)


pdf = PDF()
pdf.alias_nb_pages()
pdf.set_auto_page_break(auto=True, margin=20)

# CAPA
pdf.add_page()
pdf.ln(35)
pdf.set_font('Helvetica', 'B', 26)
pdf.set_text_color(204, 35, 102)
pdf.cell(0, 14, 'Auditoria Completa', align='C')
pdf.ln(14)
pdf.set_font('Helvetica', 'B', 18)
pdf.set_text_color(30, 30, 60)
pdf.cell(0, 11, 'Grupo Amor Animal', align='C')
pdf.ln(12)
pdf.set_font('Helvetica', '', 11)
pdf.set_text_color(100, 100, 100)
pdf.cell(0, 7, '@grupoamoranimal - Instagram para API', align='C')
pdf.ln(18)
pdf.set_font('Helvetica', '', 9.5)
pdf.cell(0, 6, 'Gerado em: %s' % datetime.now().strftime('%d/%m/%Y %H:%M'), align='C')
pdf.ln(5)
pdf.cell(0, 6, 'API: %s' % API_BASE, align='C')
pdf.ln(5)
pdf.cell(0, 6, 'Posts analisados: %d | Registros API: %d' % (total_posts, api_total), align='C')
pdf.ln(5)
pdf.cell(0, 6, 'Periodo: %s' % cobertura, align='C')
pdf.ln(20)
pdf.set_draw_color(204, 35, 102)
pdf.set_line_width(0.5)
pdf.line(60, pdf.get_y(), 150, pdf.get_y())
pdf.ln(8)
pdf.set_font('Helvetica', 'I', 8.5)
pdf.set_text_color(130, 130, 130)
pdf.cell(0, 6, 'Documento gerado automaticamente por gerar-pdf.py', align='C')

# 1. RESUMO EXECUTIVO
pdf.add_page()
pdf.tit('1. Resumo Executivo')
pdf.txt(
    'Este documento apresenta a auditoria completa do projeto Grupo Amor Animal, '
    'que sincroniza postagens do perfil Instagram @grupoamoranimal com a API do site '
    'api.projetosdinamicos.com.br/amoranimal. '
    'O foco e explicar os processos, alternativas e complexidades de postar dados '
    'no site sem quebrar a integridade das tabelas.'
)
pdf.s2('Numeros Gerais')
pdf.tbl(
    ['Metrica', 'Valor'],
    [
        ['Posts no Instagram', str(total_posts)],
        ['Periodo coberto', cobertura],
        ['Registros na API', str(api_total)],
        ['Payloads JSON prontos', str(payloads_prontos)],
        ['Categorias mapeaveis', '3 (adocao, procura-se, eventos)'],
        ['Categorias sem tabela', '2 (doacao, outros) - 63%% dos posts'],
    ],
    [95, 95]
)

# 2. ESTADO ATUAL
pdf.tit('2. Estado Atual da API')
pdf.txt('A API possui 6 tabelas. Estado atual:')
for ep in ENDPOINTS:
    registros = api.get(ep, [])
    n = len(registros)
    if n > 0:
        nomes = [str(r.get('nome', r.get('titulo', r.get('ticket', '?'))))[:40] for r in registros[:3]]
        pdf.neg('/%s: %d registro(s)' % (ep, n))
        pdf.lst(nomes)
    else:
        pdf.neg('/%s: vazio' % ep)

pdf.s2('Arquivos locais vs API')
pdf.txt(
    'Os arquivos JSON da pasta (adocao.json, eventos.json, castracao.json, etc.) '
    'espelham exatamente o estado da API. Sao backups locais.'
)

# 3. PIPELINE
pdf.add_page()
pdf.tit('3. Pipeline de Dados (Instagram -> API)')
pdf.s2('3.1 Fluxo completo')
pdf.code(
    'atualizar.js          Coleta posts do Instagram via imginn.com\n'
    '    |\n'
    'dataset.json          Classifica por categoria\n'
    '    |\n'
    'filtrar.js            Gera dataset-filtrado.json com payloads\n'
    '    |\n'
    'sincronizar.js        Envia payloads aprovados para a API\n'
    '    |\n'
    'sincronizados.json    Registra o que ja foi enviado (dedupe)\n'
    '    |\n'
    'API /adocao           Animais disponiveis\n'
    'API /procura_se       Animais desaparecidos\n'
    'API /eventos          Eventos e mutiroes\n'
)
pdf.s2('3.2 Scripts auxiliares')
pdf.tbl(
    ['Script', 'Funcao'],
    [
        ['atualizar.js', 'Coleta posts do Instagram, classifica, gera dataset.json'],
        ['filtrar.js', 'Organiza por categoria, gera payloads JSON por post'],
        ['sincronizar.js', 'Envia payloads aprovados para a API (auth JWT)'],
        ['simular-api.js', 'Simula tabelas da API sem enviar (preview)'],
        ['cruzar-api.js', 'Cruza posts com tabelas, gera HTML de revisao'],
        ['comparar-api.py', 'Compara dados Instagram x API'],
        ['pagina-tabelas-api.py', 'Mostra tabelas da API com posts relacionados'],
    ],
    [50, 140]
)

# 4. CADEIA DE FILTROS
pdf.add_page()
pdf.tit('4. Cadeia de Filtros (como posts sao pulados)')
pdf.txt('O sincronizar.js possui 4 camadas de filtro:')

pdf.s2('Camada 1 - Mapeamento de categorias')
pdf.txt(
    'Apenas 3 categorias do Instagram tem tabela na API:\n'
    '  adocao -> /adocao (105 posts)\n'
    '  procura-se -> /procura_se (4 posts)\n'
    '  castracao -> /eventos (23 posts, so com --castracao)\n\n'
    'doacao (178) e outros (50) = IGNORADOS (228 posts, 63%%).'
)

pdf.s2('Camada 2 - Dedupe (sincronizados.json)')
pdf.txt(
    'Arquivo sincronizados.json registra cada post ja enviado. '
    'Na proxima execucao, posts com code duplicado sao pulados. '
    'NAO EXISTE ainda (nenhum post sincronizado). Use --force para reenviar.'
)

pdf.s2('Camada 3 - Montagem do payload')
pdf.txt(
    'O script extrai dados da legenda (nome, especie, porte, idade, foto). '
    'Se a extracao falhar, o post e pulado.'
)

pdf.s2('Camada 4 - Filtro de qualidade')
pdf.txt('Cada tabela tem um validador proprio:')

pdf.s2('  /adocao - validarAdocao():')
pdf.lst([
    'Exige nome proprio real (nao \"Voce\", \"Em\", \"Para\")',
    'Nome: 2-12 caracteres, sem espacos',
    'Nao pode ser generico (STOP_NOME: 200+ palavras)',
    'Nao pode ser campanha/anuncio',
    'Nao pode ser pet ja adotado',
    'Legenda deve ter contexto de adocao',
])

pdf.s2('  /procura_se - validarProcura():')
pdf.lst([
    'Exige nome proprio do pet',
    'Exige telefone de contato na legenda',
    'Legenda deve ter contexto de desaparecimento',
])

pdf.s2('  /eventos - validarEvento():')
pdf.lst([
    'Data do evento identificada no texto',
    'Data deve ser FUTURA (passado = rejeitado)',
    'Legenda deve ter contexto de evento',
])

# 5. PROBLEMAS
pdf.add_page()
pdf.tit('5. Problemas Detectados')

pdf.s2('5.1 Payloads de adocao com qualidade ruim')
pdf.txt(
    'Dos 105 posts de "adocao", a maioria NAO sao pets individuais - '
    'sao campanhas, feirinhas e avisos. O payload fica com nome = trecho da legenda.'
)
pdf.code(
    'POST: "Um dia pode mudar uma vida..."\n'
    'Payload gerado:\n'
    '  nome: "Um dia pode mudar uma vida..."  <- NOME ERRADO\n'
    '  especie: "felino" (detectado errado)\n'
    '  porte: null\n'
    '  foto_url: "https://scontent-..." (CDN expira!)'
)

pdf.s2('5.2 /castracao != posts do Instagram')
pdf.txt(
    'A tabela /castracao (89 registros) e de FORMULARIOS de agendamento '
    '(ticket, clinica, agenda, cpf...). '
    'Os 23 posts de "castracao" do Instagram sao anuncios de mutiroes, '
    'nao formularios. O sincronizar.js nem inclui castracao por padrao.'
)

pdf.s2('5.3 Fotos com CDN temporal')
pdf.txt(
    'URLs do CDN do Instagram expiram em horas. '
    'Sem imagem local em img-resumo-mensal/, o payload fica com URL quebrada.'
)

pdf.s2('5.4 /eventos so aceita eventos futuros')
pdf.txt('O filtro rejeita posts com data passada. Dos 3 eventos na API, 2 ja aconteceram.')

pdf.s2('5.5 63%% dos posts sem tabela')
pdf.txt('178 doacao + 50 outros = 228 posts sem correspondencia na API.')

# 6. ALTERNATIVAS
pdf.add_page()
pdf.tit('6. Alternativas para Filtrar Postagens')
pdf.txt(
    'Para controlar quais posts sao enviados ao site sem quebrar os dados, '
    'existem 7 alternativas praticas:'
)

pdf.s2('Alternativa 1 - Blacklist (lista de exclusao)')
pdf.neg('Complexidade: BAIXA | Escala: BOA | Risco: BAIXO')
pdf.txt('Criar ignorar.json com codes que NUNCA devem ser enviados:')
pdf.code(
    '// ignorar.json\n'
    '{\n'
    '  "codes": ["DbGwiaUO4n8", "Da6UtXiuEpS"],\n'
    '  "obs": "posts de campanha"\n'
    '}\n\n'
    '// No sincronizar.js, apos linha 358:\n'
    'const bl = JSON.parse(fs.readFileSync("ignorar.json")).codes;\n'
    'pendentes = pendentes.filter(p => !bl.includes(p.code));'
)
pdf.txt('Pro: Controle total. Contra: manual.')

pdf.s2('Alternativa 2 - Whitelist (enviar so estes)')
pdf.neg('Complexidade: BAIXA | Escala: RUIM | Risco: MINIMO')
pdf.txt('Listar apenas codes que DEVEM ser enviados. Zero risco:')
pdf.code(
    '// enviar.json\n'
    '{ "codes": ["DajSyzBFfMo", "DW62dppO8Yh"] }'
)
pdf.txt('Pro: Seguro. Contra: lista um por um.')

pdf.add_page()
pdf.s2('Alternativa 3 - Qualidade mais rigorosa (auto)')
pdf.neg('Complexidade: MEDIA | Escala: ALTA | Risco: MEDIO')
pdf.txt('Reforcar validadores com regras extras:')
pdf.code(
    '// Exigir foto local (base64)\n'
    'if (!fotoBase64(p.code))\n'
    '  return {ok:false, motivo:"sem foto local"};\n\n'
    '// Rejeitar posts virais (>300 likes)\n'
    'if (p.likes > 300)\n'
    '  return {ok:false, motivo:"post viral"};\n\n'
    '// Exigir indicador de pet disponivel\n'
    'const IND = ["disponivel","procura","lar","adotar"];\n'
    'if (!IND.some(w => c.includes(w)))\n'
    '  return {ok:false, motivo:"sem indicador"};'
)
pdf.txt('Pro: Automatico. Contra: pode rejeitar bons posts.')

pdf.s2('Alternativa 4 - Sincronizacao bidirecional')
pdf.neg('Complexidade: ALTA | Escala: ALTA | Risco: BAIXO')
pdf.txt(
    'Antes de enviar, consultar a API para ver se o pet ja existe. '
    'Se ja existe (mesmo nome), pular. Evita duplicatas sem depender de sincronizados.json.'
)
pdf.code(
    '// Buscar nomes ja na API\n'
    'const apiAdocao = await fetch(API + "/adocao");\n'
    'const listaApi = await apiAdocao.json();\n'
    'const nomesApi = new Set(listaApi.map(r => norm(r.nome)));\n\n'
    '// No loop: se ja existe, pular\n'
    'if (nomesApi.has(norm(payload.nome))) {\n'
    '  log("PULADO (ja existe) " + payload.nome);\n'
    '  continue;\n'
    '}'
)
pdf.txt('Pro: Evita duplicatas. Contra: matching por nome e impreciso.')

pdf.s2('Alternativa 5 - So posts recentes')
pdf.neg('Complexidade: BAIXA | Escala: BOA | Risco: MEDIO')
pdf.txt('Sincronizar apenas posts dos ultimos N dias:')
pdf.code(
    '// No sincronizar.js:\n'
    'const DIAS = 30;\n'
    'const corte = new Date(Date.now() - DIAS*86400000).toISOString();\n'
    'pendentes = pendentes.filter(p => p.data_iso > corte);'
)
pdf.txt('Pro: Simples. Contra: pula posts antigos uteis.')

pdf.add_page()
pdf.s2('Alternativa 6 - Modo interativo')
pdf.neg('Complexidade: BAIXA | Escala: RUIM | Risco: MINIMO')
pdf.txt('Perguntar post por post antes de enviar:')
pdf.code(
    'for (const p of pendentes) {\n'
    '  console.log(p.code + " - " + p.titulo);\n'
    '  const r = pergunta("Enviar? (s/n/q) ");\n'
    '  if (r === "q") break;\n'
    '  if (r !== "s") { pulado++; continue; }\n'
    '  // enviar...\n'
    '}'
)
pdf.txt('Pro: Controle humano total. Contra: lento.')

pdf.s2('Alternativa 7 - Status no dataset')
pdf.neg('Complexidade: MEDIA | Escala: ALTA | Risco: BAIXO')
pdf.txt('Adicionar campo sync_status no dataset (pendente/aprovado/rejeitado):')
pdf.code(
    '// No atualizar.js:\n'
    'function classificarPost(cap) {\n'
    '  const {categoria, tags} = classificar(cap);\n'
    '  let sync_status = "pendente";\n'
    '  if (["doacao","outros"].includes(categoria))\n'
    '    sync_status = "nao_mapeado";\n'
    '  return {categoria, tags, sync_status};\n'
    '}\n\n'
    '// No sincronizar.js:\n'
    'pendentes = dataset.posts.filter(p =>\n'
    '  mapRotas[p.categoria] &&\n'
    '  p.sync_status !== "rejeitado" &&\n'
    '  p.sync_status !== "nao_mapeado"\n'
    ');'
)
pdf.txt('Pro: Integra com pipeline. Contra: altera estrutura do dataset.')

# 7. TABELA COMPARATIVA
pdf.add_page()
pdf.tit('7. Tabela Comparativa das Alternativas')
pdf.tbl(
    ['Alt', 'Nome', 'Complexidade', 'Escala', 'Risco', 'Esforco'],
    [
        ['1', 'Blacklist', 'Baixa', 'Boa', 'Baixo', 'Baixo'],
        ['2', 'Whitelist', 'Baixa', 'Ruim', 'Minimo', 'Medio'],
        ['3', 'Qualidade rigorosa', 'Media', 'Alta', 'Medio', 'Medio'],
        ['4', 'Bidirecional', 'Alta', 'Alta', 'Baixo', 'Alto'],
        ['5', 'So recentes', 'Baixa', 'Boa', 'Medio', 'Baixo'],
        ['6', 'Interativo', 'Baixa', 'Ruim', 'Minimo', 'Alto'],
        ['7', 'Status dataset', 'Media', 'Alta', 'Baixo', 'Medio'],
    ],
    [10, 35, 30, 30, 30, 25]
)

pdf.s2('Recomendacao')
pdf.dest(
    'Combinar Alternativa 1 (blacklist) + Alternativa 3 (qualidade rigorosa). '
    'Controle manual para posts problematicos E filtro automatico para o resto.'
)

# 8. COMO POSTAR CORRETAMENTE
pdf.add_page()
pdf.tit('8. Como Postar Corretamente')
pdf.txt('Metodo 1: Via sincronizar.js (automatico)')
pdf.code(
    '# 1. Atualizar dataset\n'
    'node atualizar.js\n\n'
    '# 2. Testar o que seria enviado\n'
    'API_USER="user" API_PASS="pass" node sincronizar.js --dry-run\n\n'
    '# 3. Enviar de verdade\n'
    'API_USER="user" API_PASS="pass" node sincronizar.js'
)
pdf.txt('Metodo 2: Via curl (controle total)')
pdf.code(
    '# Autenticar\n'
    'TOKEN=$(curl -s -X POST API_BASE/auth/login \\\n'
    '  -H "Content-Type: application/json" \\\n'
    '  -d \'{"usuario":"USER","senha":"PASS"}\' | \\\n'
    '  python3 -c "import sys,json; print(json.load(sys.stdin)[\'token\'])")\n\n'
    '# POST /adocao (pet individual)\n'
    'curl -X POST API_BASE/adocao \\\n'
    '  -H "Content-Type: application/json" \\\n'
    '  -H "Authorization: Bearer $TOKEN" \\\n'
    '  -d \'{"nome":"Nami","especie":"canino",\n'
    '         "porte":"medio","status":"disponivel"}\''
)
pdf.s2('Regras de ouro')
pdf.lst([
    'So postar pets INDIVIDUAIS com nome proprio real',
    'Nome: "Nami", "Thor" — NAO trecho de legenda',
    'Foto: base64 local ou URL permanente (nao CDN do Instagram)',
    'Eventos: so com data FUTURA',
    'Castracao: NAO postar do Instagram (tabela e para formularios)',
    'Doacao/outros: nao tem tabela, ficam so no Instagram',
    'Sempre usar --dry-run antes de enviar',
])

# 9. CONCLUSAO
pdf.add_page()
pdf.tit('9. Conclusao')
pdf.txt(
    'O pipeline de sincronizacao Instagram -> API esta bem estruturado com '
    'atualizar.js, filtrar.js e sincronizar.js. Os filtros de qualidade '
    'rejeitam corretamente a maioria dos posts incorretos.'
)
pdf.txt(
    'O principal desafio e que 63%% dos posts do Instagram nao tem '
    'correspondencia na API (doacao e outros). Dos posts mapeaveis, '
    'muitos sao campanhas/feiras disfarçados de adocao.'
)
pdf.txt(
    'A recomendacao e usar blacklist + qualidade rigorosa, sempre '
    'validando com --dry-run antes de enviar. O arquivo '
    'sincronizados.json (dedupe) deve ser preservado apos cada '
    'execucao bem-sucedida para evitar duplicatas.'
)
pdf.s2('Proximos passos sugeridos')
pdf.lst([
    'Criar ignorar.json com os codes problematicos',
    'Rodar simular-api.js para ver simulacao antes de enviar',
    'Usar --dry-run sempre antes do envio real',
    'Baixar imagens locais via baixar-imagens.py para evitar CDN quebrado',
    'Considerar criar tabela /doacao na API para os 178 posts de doacao',
])

OUT = os.path.join(DIR, 'auditoria-grupoamoranimal.pdf')
pdf.output(OUT)
sz = os.path.getsize(OUT) / 1024
print('[pdf] gerado: %s (%.1f KB)' % (OUT, sz))

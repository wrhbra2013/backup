#!/usr/bin/env python3
"""resumo-mensal.py — Resumo do perfil @grupoamoranimal dividido por ano/mês.

Coleta todas as postagens públicas do perfil via instaloader (sessão do Firefox)
e gera instagram-grupoamoranimal-resumo-mensal.json agrupado por timestamp
(ano → mês) com estatísticas, categorias e lista compacta de posts.

Uso:
  python3 resumo-mensal.py                  Coleta tudo e gera o JSON
  python3 resumo-mensal.py --max-posts N    Limita a coleta (teste)
  python3 resumo-mensal.py --save-only      Regenera o JSON a partir do último parcial salvo

Requisitos: python3 + instaloader; cookies do Instagram no Firefox.
"""
import argparse
import json
import os
import re
import sqlite3
import sys
import time
from collections import defaultdict
from datetime import datetime

import instaloader

DIR = os.path.dirname(os.path.abspath(__file__))
USERNAME = 'grupoamoranimal'
COOKIES_DB = '/tmp/opencode/fx-cookies/cookies.sqlite'
OUT_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.json')
PARTIAL_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.partial.json')

# ─── Classificação (espelho do atualizar.js) ─────────────────────────────────

def norm(s):
    s = (s or '').lower()
    s = re.sub(r'[\u0300-\u036f]', '', s)
    return s

def tem(c, *palavras):
    return any(w in c for w in palavras)

def classificar(cap):
    c = norm(cap)
    tags = []
    if not c:
        return 'outros', tags

    eh_procura_se = (
        (tem(c, 'procura-se') and not tem(c, 'lar')) or
        tem(c, 'desaparec') or tem(c, 'sumiu') or tem(c, 'desapareceu') or
        (tem(c, 'encontrad') and tem(c, 'dono')) or
        tem(c, 'nao vimos') or tem(c, 'nao achamos')
    )
    eh_castracao = (
        tem(c, 'castra') and
        tem(c, 'mutirao', 'gratuit', 'castrar', 'castramovel', 'controle populacional',
            'cirurgia', 'projeto de castracao', 'edital', 'castrar e', '1.o mutirao',
            '2.o mutirao', '3.o mutirao', 'realizamos', 'realizou', 'realizado',
            'veterinaria', 'clinica veterinaria', 'emenda parlamentar',
            'recursos para castracao')
    )
    eh_adocao = tem(c, 'adocao', 'adot', 'feirinha de adocao', 'feira de adocao',
                    'doacao responsavel', 'procura de um lar', 'novo lar',
                    'lar cheio de amor', 'lar amoroso', 'em busca de um lar',
                    'busca de um lar', 'para adocao', 'adote', 'adotantes',
                    'lares temporarios')
    eh_doacao = (tem(c, 'pix', 'doe', 'doacao de racao', 'arrecadacao', 'vaquinha',
                     'rifa', 'apadrinhe', 'apadrinhar', 'contribuicao', 'doador',
                     'nota fiscal', 'precisamos de', 'doacoes de', 'cobertores',
                     'racao') and not eh_adocao)

    if eh_procura_se:
        tags.append('procura-se')
    if eh_castracao:
        tags.append('castracao')
    if eh_adocao:
        tags.append('adocao')
    if eh_doacao:
        tags.append('doacao')

    if eh_procura_se:
        cat = 'procura-se'
    elif eh_castracao:
        cat = 'castracao'
    elif eh_adocao:
        cat = 'adocao'
    elif eh_doacao:
        cat = 'doacao'
    else:
        cat = 'outros'
    return cat, tags

EMOJI_RE = re.compile(
    '[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0000FE0F\U00002B50'
    '\U00002764\U00002705\U0000274C\U00002728\U00002714\U000027A1'
    '\U00002197\U00002B05\U000027A4\U0001F000-\U0001F9FF\U0000231B'
    '\U000023F0\U0001F4F1]'
)
TAG_RE = re.compile(r'#[A-Za-z\u00C0-\u024F]+')
USER_RE = re.compile(r'@[\w.]+')
SPACE_RE = re.compile(r'\s+')


def titulo(cap):
    cap = cap or ''
    for linha in cap.split('\n'):
        limpa = SPACE_RE.sub(' ', TAG_RE.sub(' ', USER_RE.sub(' ', linha))).strip()
        sem_emoji = SPACE_RE.sub(' ', EMOJI_RE.sub(' ', limpa)).strip()
        if len(sem_emoji) > 5:
            t = sem_emoji
            break
    else:
        t = SPACE_RE.sub(' ', TAG_RE.sub(' ', cap)).strip()
    if len(t) > 90:
        t = t[:90].rstrip() + '…'
    return t or 'Postagem sem título'


# ─── Sessão instaloader ──────────────────────────────────────────────────────

def load_session(L):
    """Carrega cookies do Firefox e registra a sessão como logada no instaloader."""
    con = sqlite3.connect(COOKIES_DB)
    cur = con.cursor()
    cur.execute(
        "SELECT name, value FROM moz_cookies WHERE host LIKE '%instagram.com' "
        "AND name IN ('sessionid','csrftoken','ig_did','ds_user_id','rur')"
    )
    cookies = cur.fetchall()
    con.close()
    if not cookies:
        return False
    sess = L.context._session
    for name, value in cookies:
        sess.cookies.set(name, value, domain='.instagram.com', path='/')
    # Sem login() o instaloader não marca a sessão como logada; registra manualmente.
    map_cookies = dict(cookies)
    user_id = map_cookies.get('ds_user_id')
    if user_id:
        try:
            dono = instaloader.Profile.from_id(L.context, user_id)
            L.context.username = dono.username
            L.context.user_id = dono.userid
        except Exception as e:
            print('AVISO: nao resolveu usuario da sessao (%s); usando modo anonimo.' % e,
                  file=sys.stderr)
    return True


# ─── Montagem do resumo ──────────────────────────────────────────────────────

def tipo_post(node):
    if node.get('is_video'):
        return 'VIDEO'
    if node.get('__typename') == 'GraphSidecar':
        return 'CAROUSEL'
    return 'IMAGE'


def novo_post(post, dt, legenda):
    node = post._node
    cat, tags = classificar(legenda)
    return {
        'code': post.shortcode,
        'url': f'https://www.instagram.com/p/{post.shortcode}/',
        'data': dt.isoformat(),
        'timestamp_unix': int(dt.timestamp()),
        'titulo': titulo(legenda),
        'tipo': tipo_post(node),
        'likes': (node.get('edge_media_preview_like') or {}).get('count', 0),
        'comentarios': node.get('comments', 0) or 0,
        'categoria': cat,
        'tags': tags,
        'views': node.get('video_view_count'),
    }


def build_summary(perfil, posts, buscado_em):
    total_likes = sum(p['likes'] for p in posts)
    total_com = sum(p['comentarios'] for p in posts)
    n = len(posts)

    por_ano = {}
    for p in posts:
        ano = p['data'][:4]
        mes = p['data'][:7]
        ano_info = por_ano.setdefault(ano, {'quantidade_posts': 0, 'total_likes': 0,
                                            'total_comentarios': 0, 'imagens': 0,
                                            'videos': 0, 'carrosseis': 0,
                                            'por_categoria': defaultdict(int),
                                            'meses': {}})
        ano_info['quantidade_posts'] += 1
        ano_info['total_likes'] += p['likes']
        ano_info['total_comentarios'] += p['comentarios']
        if p['tipo'] == 'VIDEO':
            ano_info['videos'] += 1
        elif p['tipo'] == 'CAROUSEL':
            ano_info['carrosseis'] += 1
        else:
            ano_info['imagens'] += 1
        ano_info['por_categoria'][p['categoria']] += 1
        mes_info = ano_info['meses'].setdefault(mes, {
            'quantidade_posts': 0, 'total_likes': 0, 'total_comentarios': 0,
            'imagens': 0, 'videos': 0, 'carrosseis': 0,
            'por_categoria': defaultdict(int), 'posts': []})
        mes_info['quantidade_posts'] += 1
        mes_info['total_likes'] += p['likes']
        mes_info['total_comentarios'] += p['comentarios']
        if p['tipo'] == 'VIDEO':
            mes_info['videos'] += 1
        elif p['tipo'] == 'CAROUSEL':
            mes_info['carrosseis'] += 1
        else:
            mes_info['imagens'] += 1
        mes_info['por_categoria'][p['categoria']] += 1
        mes_info['posts'].append(p)

    # Converte defaultdicts e ordena decrescente (mais recente primeiro)
    def fix(info):
        info['por_categoria'] = dict(sorted(info['por_categoria'].items(),
                                            key=lambda kv: kv[1], reverse=True))
        q = info['quantidade_posts']
        if q:
            info['media_likes_por_post'] = round(info['total_likes'] / q, 1)
            info['media_comentarios_por_post'] = round(info['total_comentarios'] / q, 1)
        else:
            info['media_likes_por_post'] = 0
            info['media_comentarios_por_post'] = 0
        return info

    for ano, info in por_ano.items():
        info['meses'] = {m: fix(mi) for m, mi in sorted(info['meses'].items(), reverse=True)}
        fix(info)
    por_ano = {a: por_ano[a] for a in sorted(por_ano, reverse=True)}

    summary = {
        'perfil': {
            'username': perfil.username,
            'nome': perfil.full_name,
            'bio': perfil.biography,
            'seguidores': perfil.followers,
            'seguindo': perfil.followees,
            'total_posts': perfil.mediacount,
            'eh_verificado': perfil.is_verified,
            'url_perfil': perfil.profile_pic_url,
            'url': f'https://www.instagram.com/{perfil.username}/',
        },
        'estatisticas': {
            'posts_coletados': n,
            'total_likes': total_likes,
            'total_comentarios': total_com,
            'media_likes_por_post': round(total_likes / n, 1) if n else 0,
            'media_comentarios_por_post': round(total_com / n, 1) if n else 0,
        },
        'por_ano': por_ano,
        'buscado_em': buscado_em,
    }
    return summary


def save(summary):
    with open(OUT_JSON, 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)


def print_resumo(summary):
    print('\n=== RESUMO POR ANO/MÊS (@%s) ===' % summary['perfil']['username'])
    for ano, info in summary['por_ano'].items():
        print(f'\n[ {ano} ]  posts={info["quantidade_posts"]}  '
              f'likes={info["total_likes"]}  com={info["total_comentarios"]}')
        for mes, m in info['meses'].items():
            print('  {:<7} posts={:>4}  likes={:>7}  com={:>4}  '
                  'img={:>3} vid={:>3} car={:>3}  cat={}'.format(
                      mes[2:], m['quantidade_posts'], m['total_likes'],
                      m['total_comentarios'], m['imagens'], m['videos'],
                      m['carrosseis'], m['por_categoria']))
    print(f'\nTotal: {summary["estatisticas"]["posts_coletados"]} posts coletados')
    print(f'Salvo em: {OUT_JSON}')


# ─── Principal ───────────────────────────────────────────────────────────────

def build_perfil(dados):
    """Cria um objeto simples no formato esperado por build_summary."""
    return argparse.Namespace(**dados)


def dataset_post(p):
    """Converte um post do instagram-grupoamoranimal-dataset.json para o formato do resumo."""
    return {
        'code': p.get('code'),
        'url': p.get('url'),
        'data': datetime.fromtimestamp(p.get('timestamp_unix') or 0).isoformat(),
        'timestamp_unix': p.get('timestamp_unix') or 0,
        'titulo': p.get('titulo') or titulo(p.get('legenda')),
        'tipo': p.get('tipo') or 'IMAGE',
        'likes': p.get('likes') or 0,
        'comentarios': p.get('comentarios') or 0,
        'categoria': p.get('categoria') or 'outros',
        'tags': p.get('tags') or [],
        'views': None,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--max-posts', type=int, default=0)
    ap.add_argument('--save-only', action='store_true')
    ap.add_argument('--from-local', action='store_true',
                    help='Gera o resumo apenas com dados locais (parcial + dataset).')
    args = ap.parse_args()

    if args.from_local:
        posts = {}
        perfil_data = None
        buscado_em = datetime.now().isoformat()
        if os.path.exists(PARTIAL_JSON):
            data = json.load(open(PARTIAL_JSON, encoding='utf-8'))
            perfil_data = data.get('perfil')
            for p in data.get('posts', []):
                posts[p['code']] = p
            print(f'Parcial: {len(data.get("posts", []))} posts.')
        ds_file = os.path.join(DIR, 'instagram-grupoamoranimal-dataset.json')
        if os.path.exists(ds_file):
            ds = json.load(open(ds_file, encoding='utf-8'))
            if perfil_data is None:
                perfil_data = {
                    'username': ds['metadados'].get('perfil_username', USERNAME),
                    'full_name': ds['metadados'].get('perfil_nome', ''),
                    'biography': '',
                    'followers': 0, 'followees': 0,
                    'mediacount': ds['metadados'].get('posts_totais_do_perfil', 0),
                    'is_verified': False,
                    'profile_pic_url': '',
                }
            for p in ds.get('posts', []):
                posts.setdefault(p.get('code'), dataset_post(p))
            print(f'Dataset: {len(ds.get("posts", []))} posts.')
        if not posts:
            print('ERRO: sem dados locais. Rode primeiro a coleta ao vivo.', file=sys.stderr)
            sys.exit(1)
        lista = sorted(posts.values(), key=lambda p: p.get('timestamp_unix') or 0, reverse=True)
        perfil = build_perfil(perfil_data or {})
        print(f'Usando {len(lista)} posts locais (unicos).')
        summary = build_summary(perfil, lista, buscado_em)
        save(summary)
        print_resumo(summary)
        return

    if args.save_only:
        if not os.path.exists(PARTIAL_JSON):
            print('ERRO: nenhum parcial salvo para --save-only.', file=sys.stderr)
            sys.exit(1)
        data = json.load(open(PARTIAL_JSON, encoding='utf-8'))
        posts = data['posts']
        perfil = data.get('perfil')
        buscado_em = data.get('buscado_em')
        print(f'Usando {len(posts)} posts do parcial salvo.')
    else:
        L = instaloader.Instaloader(quiet=True, max_connection_attempts=8)
        if not load_session(L):
            print('AVISO: nenhum cookie encontrado. Tentando sem sessão...', file=sys.stderr)
        print(f'Carregando perfil @{USERNAME}...')
        perfil = instaloader.Profile.from_username(L.context, USERNAME)

        # Semeia com o parcial salvo (retomável) e segue coletando os mais antigos.
        posts = []
        seen = set()
        if os.path.exists(PARTIAL_JSON):
            try:
                antigo = json.load(open(PARTIAL_JSON, encoding='utf-8'))
                posts = antigo.get('posts', [])
                seen = {p['code'] for p in posts}
                print(f'Retomando de {len(posts)} posts ja coletados.')
            except Exception as e:
                print(f'AVISO: parcial ilegivel ({e}). Coletando do zero.', file=sys.stderr)

        def salvar_parcial():
            json.dump({'perfil': {
                          'username': perfil.username,
                          'full_name': perfil.full_name,
                          'biography': perfil.biography,
                          'followers': perfil.followers,
                          'followees': perfil.followees,
                          'mediacount': perfil.mediacount,
                          'is_verified': perfil.is_verified,
                          'profile_pic_url': perfil.profile_pic_url,
                      },
                      'posts': posts,
                      'buscado_em': datetime.now().isoformat()},
                     open(PARTIAL_JSON, 'w', encoding='utf-8'),
                     ensure_ascii=False, indent=2)

        concluido = False
        falhas = 0
        while not concluido:
            try:
                for post in perfil.get_posts():
                    code = post.shortcode
                    novo = code not in seen
                    seen.add(code)
                    if novo:
                        dt = datetime.fromtimestamp(post.date_utc.timestamp())
                        posts.append(novo_post(post, dt, post.caption))
                        time.sleep(0.6)
                    else:
                        time.sleep(0.05)
                    if len(posts) % 100 == 0:
                        salvar_parcial()
                        print(f'  {len(posts)} posts...', flush=True)
                    if args.max_posts and len(posts) >= args.max_posts:
                        concluido = True
                        break
                else:
                    concluido = True
            except instaloader.InstaloaderException as e:
                falhas += 1
                print(f'  erro na coleta: {e} — tentativa {falhas}/6',
                      file=sys.stderr, flush=True)
                if falhas >= 6:
                    print('  desistindo apos 6 tentativas; salvando o que tem.',
                          file=sys.stderr)
                    break
                time.sleep(15 * falhas)
        salvar_parcial()
        buscado_em = datetime.now().isoformat()
        print(f'Coleta concluída: {len(posts)} posts.')

    summary = build_summary(perfil, posts, buscado_em)
    save(summary)
    print_resumo(summary)


if __name__ == '__main__':
    main()

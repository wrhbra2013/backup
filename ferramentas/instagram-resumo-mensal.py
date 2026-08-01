#!/usr/bin/env python3
"""Gera resumo de postagens por mês de um perfil Instagram usando instaloader."""
import sqlite3
import json
import sys
from collections import defaultdict
from datetime import datetime

import instaloader

COOKIES_DB = '/tmp/opencode/fx-cookies/cookies.sqlite'
USERNAME = 'grupoamoranimal'


def load_session_from_firefox(L, db=COOKIES_DB):
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.execute(
        "SELECT name, value FROM moz_cookies WHERE host LIKE '%instagram.com' "
        "AND name IN ('sessionid','csrftoken','ig_did','ds_user_id','rur')"
    )
    cookies = cur.fetchall()
    con.close()
    sess = L.context._session
    for name, value in cookies:
        sess.cookies.set(name, value, domain='.instagram.com', path='/')


def main():
    L = instaloader.Instaloader(quiet=True)
    load_session_from_firefox(L)

    print(f'Carregando perfil @{USERNAME}...')
    profile = instaloader.Profile.from_username(L.context, USERNAME)

    posts_by_month = defaultdict(list)
    total_likes = 0
    total_comments = 0
    n = 0

    print('Baixando metadados dos posts...')
    for post in profile.get_posts():
        d = datetime.fromtimestamp(post.date_utc.timestamp())
        month = d.strftime('%Y-%m')
        posts_by_month[month].append({
            'shortcode': post.shortcode,
            'data': post.date_utc.isoformat(),
            'tipo': 'VIDEO' if post.is_video else ('CAROUSEL' if post.typename == 'GraphSidecar' else 'IMAGE'),
            'likes': post.likes,
            'comentarios': post.comments,
            'views': getattr(post, 'video_view_count', None),
            'legenda': post.caption,
            'url': f'https://www.instagram.com/p/{post.shortcode}/',
        })
        total_likes += post.likes
        total_comments += post.comments
        n += 1
        if n % 100 == 0:
            print(f'  {n} posts...')

    months = sorted(posts_by_month.keys(), reverse=True)
    summary = {
        'perfil': {
            'username': profile.username,
            'nome': profile.full_name,
            'bio': profile.biography,
            'seguidores': profile.followers,
            'seguindo': profile.followees,
            'total_posts': profile.mediacount,
            'eh_verificado': profile.is_verified,
            'url': f'https://www.instagram.com/{profile.username}/',
        },
        'estatisticas': {
            'posts_baixados': n,
            'total_likes': total_likes,
            'total_comentarios': total_comments,
            'media_likes_por_post': round(total_likes / n, 1) if n else 0,
            'media_comentarios_por_post': round(total_comments / n, 1) if n else 0,
        },
        'resumo_por_mes': [],
        'buscado_em': datetime.now().isoformat(),
    }

    for month in months:
        month_posts = posts_by_month[month]
        m_likes = sum(p['likes'] for p in month_posts)
        m_comments = sum(p['comentarios'] for p in month_posts)
        videos = sum(1 for p in month_posts if p['tipo'] == 'VIDEO')
        carousels = sum(1 for p in month_posts if p['tipo'] == 'CAROUSEL')
        summary['resumo_por_mes'].append({
            'mes': month,
            'quantidade_posts': len(month_posts),
            'total_likes': m_likes,
            'total_comentarios': m_comments,
            'media_likes_por_post': round(m_likes / len(month_posts), 1),
            'media_comentarios_por_post': round(m_comments / len(month_posts), 1),
            'imagens': len(month_posts) - videos - carousels,
            'videos': videos,
            'carrosséis': carousels,
        })

    out = f'instagram-{USERNAME}-resumo-mensal.json'
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print('\n=== RESUMO POR MÊS ===')
    print('{:<10}{:>7}{:>10}{:>7}'.format('MÊS', 'POSTS', 'LIKES', 'COM.'))
    for m in summary['resumo_por_mes']:
        print('{:<10}{:>7}{:>10}{:>7}'.format(m['mes'], m['quantidade_posts'], m['total_likes'], m['total_comentarios']))
    print('\nSalvo em: {}'.format(out))


if __name__ == '__main__':
    main()

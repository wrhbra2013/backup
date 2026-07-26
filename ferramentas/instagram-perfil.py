#!/usr/bin/env python3
"""
Busca dados de um perfil publico do Instagram e salva em JSON.
Uso: python3 instagram-perfil.py <username> [--posts N]
Exemplo: python3 instagram-perfil.py grupoamoranimal --posts 50
"""
import sys
import json
import argparse
from datetime import datetime

def main():
    parser = argparse.ArgumentParser(description='Buscar perfil Instagram publico')
    parser.add_argument('username', help='Nome do usuario (sem @)')
    parser.add_argument('--posts', type=int, default=25, help='Quantidade de posts (padrao: 25)')
    args = parser.parse_args()

    username = args.username.lstrip('@')

    try:
        import instaloader
    except ImportError:
        print('[erro] instaloader nao instalado. Execute: pip3 install instaloader')
        sys.exit(1)

    L = instaloader.Instaloader(
        download_videos=False,
        download_video_thumbnails=False,
        download_geotags=False,
        download_comments=False,
        save_metadata=False,
        compress_json=False,
        quiet=True,
    )

    print(f'--- Buscando perfil @{username} ---\n')

    try:
        profile = instaloader.Profile.from_username(L.context, username)
    except instaloader.exceptions.ProfileNotExistsException:
        print(f'[erro] Perfil @{username} nao encontrado.')
        sys.exit(1)
    except instaloader.exceptions.ConnectionException as e:
        print(f'[erro] Falha na conexao: {e}')
        print('O Instagram pode estar bloqueando. Tente novamente em alguns minutos.')
        sys.exit(1)

    print(f'  [ok] Perfil encontrado: @{profile.username}')
    print(f'  Buscando {args.posts} posts recentes...\n')

    posts_data = []
    count = 0
    for post in profile.get_posts():
        if count >= args.posts:
            break

        posts_data.append({
            'id': str(post.shortcode),
            'shortcode': post.shortcode,
            'data': post.date_utc.isoformat() if post.date_utc else None,
            'legenda': post.caption if post.caption else None,
            'tipo': post.typename,
            'likes': post.likes if hasattr(post, 'likes') else 0,
            'comentarios': post.comments if hasattr(post, 'comments') else 0,
            'views': post.video_view_count if post.is_video and hasattr(post, 'video_view_count') else None,
            'url': f'https://www.instagram.com/p/{post.shortcode}/',
            'thumbnail': post.url if post.url else None,
            'hashtags': list(post.caption_hashtags) if post.caption_hashtags else [],
            'mencoes': list(post.caption_mentions) if post.caption_mentions else [],
            'localizacao': {
                'nome': post.location.name if post.location else None,
                'lat': post.location.lat if post.location and hasattr(post.location, 'lat') else None,
                'lng': post.location.lng if post.location and hasattr(post.location, 'lng') else None,
            } if post.location else None,
        })

        print(f'  [{count+1}/{args.posts}] {post.shortcode} - {post.date_utc.strftime("%d/%m/%Y") if post.date_utc else "N/D"}')

        count += 1

    total_likes = sum(p['likes'] for p in posts_data)
    total_comments = sum(p['comentarios'] for p in posts_data)
    total_views = sum(p['views'] or 0 for p in posts_data if p['views'])

    all_hashtags = {}
    for p in posts_data:
        for tag in p['hashtags']:
            all_hashtags[tag] = all_hashtags.get(tag, 0) + 1
    top_hashtags = sorted(all_hashtags.items(), key=lambda x: x[1], reverse=True)[:20]

    result = {
        'perfil': {
            'username': profile.username,
            'nome': profile.full_name or None,
            'bio': profile.biography or None,
            'seguidores': profile.followers,
            'seguindo': profile.followees,
            'total_posts': profile.mediacount,
            'eh_business': profile.is_business_account if hasattr(profile, 'is_business_account') else None,
            'categoria': profile.business_category_name if hasattr(profile, 'business_category_name') else None,
            'url_perfil': profile.profile_pic_url if hasattr(profile, 'profile_pic_url') else None,
            'url': f'https://www.instagram.com/{profile.username}/',
            'verificado': profile.is_verified if hasattr(profile, 'is_verified') else None,
        },
        'estatisticas': {
            'posts_baixados': len(posts_data),
            'total_likes': total_likes,
            'total_comentarios': total_comments,
            'total_views': total_views,
            'media_likes_por_post': round(total_likes / len(posts_data), 1) if posts_data else 0,
            'media_comentarios_por_post': round(total_comments / len(posts_data), 1) if posts_data else 0,
            'media_views_por_post': round(total_views / len(posts_data), 1) if posts_data and total_views else None,
        },
        'hashtags_mais_usadas': [{'tag': f'#{tag}', 'vezes': count} for tag, count in top_hashtags],
        'posts': posts_data,
        'buscado_em': datetime.utcnow().isoformat(),
    }

    filename = f'instagram-{username}-resumo.json'
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f'\n=== RESUMO ===')
    print(f'  Username:     @{result["perfil"]["username"]}')
    print(f'  Nome:         {result["perfil"]["nome"] or "N/A"}')
    print(f'  Bio:          {result["perfil"]["bio"] or "N/A"}')
    print(f'  Seguidores:   {result["perfil"]["seguidores"]}')
    print(f'  Seguindo:     {result["perfil"]["seguindo"]}')
    print(f'  Posts:        {result["perfil"]["total_posts"]}')
    print(f'  Business:     {result["perfil"]["eh_business"]}')
    print(f'  Verificado:   {result["perfil"]["verificado"]}')
    print(f'\n  === ESTATISTICAS (ultimos {len(posts_data)} posts) ===')
    print(f'  Likes:        {result["estatisticas"]["total_likes"]} total | {result["estatisticas"]["media_likes_por_post"]} media/post')
    print(f'  Comentarios:  {result["estatisticas"]["total_comentarios"]} total | {result["estatisticas"]["media_comentarios_por_post"]} media/post')
    if result['estatisticas']['total_views']:
        print(f'  Views:        {result["estatisticas"]["total_views"]} total | {result["estatisticas"]["media_views_por_post"]} media/post')
    if result['hashtags_mais_usadas']:
        print(f'\n  Top hashtags: {", ".join(h["tag"] for h in result["hashtags_mais_usadas"][:10])}')
    print(f'\n  Salvo em: {filename}')

if __name__ == '__main__':
    main()

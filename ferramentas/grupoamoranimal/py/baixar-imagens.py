#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
baixar-imagens.py — Baixa a imagem (capa) de posts do Instagram via instaloader
usando a sessão salva do Firefox, para alimentar a página offline de simulação.

Uso:
  python3 baixar-imagens.py <codes.json> <dir_destino> <resultado.json>

  codes.json      — lista de shortcodes de posts
  dir_destino     — pasta onde salvar <code>.jpg
  resultado.json  — saída: { code: true/false, ... }

Se o Instagram estiver bloqueando (403 no graphql), detecta 3 falhas
consecutivas e para cedo, para não queimar tentativas inúteis.
"""
import sys
import os
import json
import time
import sqlite3

import instaloader

COOKIES_DB = '/tmp/opencode/fx-cookies/cookies.sqlite'


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
    map_cookies = dict(cookies)
    user_id = map_cookies.get('ds_user_id')
    if user_id:
        try:
            dono = instaloader.Profile.from_id(L.context, user_id)
            L.context.username = dono.username
            L.context.user_id = dono.userid
        except Exception:
            pass
    return True


def main():
    codes_file, dest_dir, result_file = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(codes_file, 'r', encoding='utf-8') as f:
        codes = json.load(f)
    os.makedirs(dest_dir, exist_ok=True)

    L = instaloader.Instaloader(quiet=True, max_connection_attempts=4)
    if not load_session(L):
        print('AVISO: cookies de sessao do Instagram nao encontrados', file=sys.stderr)

    result = {}
    consec = 0
    total_ok = 0
    for code in codes:
        dest = os.path.join(dest_dir, code)
        try:
            post = instaloader.Post.from_shortcode(L.context, code)
            L.download_pic(dest, post.url, post.date_utc)
            ok = os.path.exists(dest + '.jpg')
            result[code] = ok
            if ok:
                total_ok += 1
                consec = 0
            else:
                consec += 1
            print('[ok]    ' + code, flush=True)
        except instaloader.BadResponseException:
            result[code] = False
            consec += 1
            print('[403]   ' + code, flush=True)
            if consec >= 3:
                print('Instagram bloqueando (3 falhas consecutivas); parando cedo.',
                      file=sys.stderr)
                break
            time.sleep(20)
        except instaloader.InstaloaderException as e:
            result[code] = False
            consec = 0
            print('[falha] ' + code + ' (%s)' % str(e)[:70], flush=True)
            time.sleep(2)

    with open(result_file, 'w', encoding='utf-8') as f:
        json.dump(result, f)
    print('concluido: %d/%d imagens baixadas' % (total_ok, len(codes)))


if __name__ == '__main__':
    main()

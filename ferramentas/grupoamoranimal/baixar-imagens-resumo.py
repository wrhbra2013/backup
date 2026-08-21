#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
baixar-imagens-resumo.py — Baixa a imagem (capa) dos posts do resumo-mensal
diretamente do site do Instagram (acesso externo anônimo, UA de celular).

Lê instagram-grupoamoranimal-resumo-mensal.json, pega o code de cada post e
faz download da imagem via página pública do post (og:image).

Uso:
  python3 baixar-imagens-resumo.py [--dir DIR] [--limit N] [--skip]

  --dir DIR    pasta de destino (padrão: ./img-resumo-mensal)
  --limit N    baixa no máximo N imagens (teste)
  --skip       pula posts que já têm imagem salva
"""
import argparse
import json
import os
import re
import sys
import time

import requests

DIR = os.path.dirname(os.path.abspath(__file__))
IN_JSON = os.path.join(DIR, 'instagram-grupoamoranimal-resumo-mensal.json')
OUT_DIR = os.path.join(DIR, 'img-resumo-mensal')
RESULT_JSON = os.path.join(DIR, 'baixar-imagens-resumo-resultado.json')

UA = ('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1')
OG_RE = re.compile(r'property="og:image" content="([^"]+)"')


def codigos_do_resumo():
    with open(IN_JSON, encoding='utf-8') as f:
        data = json.load(f)
    codes = []
    for ano in data['por_ano'].values():
        for mes in ano['meses'].values():
            for p in mes['posts']:
                codes.append(p['code'])
    return codes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default=OUT_DIR)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--skip', action='store_true')
    args = ap.parse_args()

    os.makedirs(args.dir, exist_ok=True)
    codes = codigos_do_resumo()
    if args.limit:
        codes = codes[:args.limit]
    print('Posts a processar: %d' % len(codes))

    sess = requests.Session()
    sess.headers['User-Agent'] = UA

    result = {}
    ok = 0
    for i, code in enumerate(codes, 1):
        dest = os.path.join(args.dir, code + '.jpg')
        if args.skip and os.path.exists(dest):
            result[code] = True
            ok += 1
            continue
        try:
            r = sess.get('https://www.instagram.com/p/%s/' % code, timeout=40)
            if r.status_code != 200:
                raise RuntimeError('pagina HTTP %d' % r.status_code)
            m = OG_RE.search(r.text)
            if not m:
                raise RuntimeError('og:image nao encontrado')
            url = m.group(1).replace('&amp;', '&')
            ri = sess.get(url, timeout=40)
            if ri.status_code != 200 or not (ri.headers.get('content-type') or '').startswith('image'):
                raise RuntimeError('imagem HTTP %d (%s)' % (ri.status_code, ri.headers.get('content-type')))
            with open(dest, 'wb') as f:
                f.write(ri.content)
            result[code] = True
            ok += 1
            status = 'ok'
        except Exception as e:
            result[code] = False
            status = 'FALHA %s' % str(e)[:60]
        print('[%d/%d] %-11s %s' % (i, len(codes), code, status), flush=True)
        time.sleep(0.8)

    with open(RESULT_JSON, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print('Concluido: %d/%d imagens em %s' % (ok, len(codes), args.dir))


if __name__ == '__main__':
    main()

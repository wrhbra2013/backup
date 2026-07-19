#!/usr/bin/env python3
"""Fetch trending news from Google News RSS and save as JSON."""
import json
import re
import urllib.request
from datetime import datetime

RSS_FEEDS = {
    "BR": "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=pt-BR&gl=BR&ceid=BR:pt-419",
    "US": "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
}

CATEGORIES = {
    "mundo": "Mundo",
    "política": "Política",
    "economia": "Economia",
    "tecnologia": "Tecnologia",
    "entretenimento": "Entretenimento",
    "esportes": "Esportes",
    "ciência": "Ciência",
    "saúde": "Saúde",
}


def fetch_rss(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        "Accept": "application/rss+xml, application/xml, text/xml",
    })
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8")


def parse_rss(xml_text):
    items = []
    for match in re.finditer(r"<item>(.*?)</item>", xml_text, re.DOTALL):
        block = match.group(1)
        title = re.search(r"<title>(.*?)</title>", block)
        source = re.search(r"<source[^>]*>(.*?)</source>", block)
        link = re.search(r"<link>(.*?)</link>", block)
        pubdate = re.search(r"<pubDate>(.*?)</pubDate>", block)
        if title:
            raw_title = title.group(1).strip()
            source_name = source.group(1).strip() if source else ""
            if source_name and source_name in raw_title:
                clean_title = raw_title.replace(f" - {source_name}", "").strip()
            else:
                clean_title = raw_title
            category = guess_category(clean_title)
            items.append({
                "titulo": clean_title,
                "fonte": source_name,
                "categoria": category,
                "link": link.group(1).strip() if link else "",
                "publicado": pubdate.group(1).strip() if pubdate else "",
            })
    return items


def guess_category(title):
    t = title.lower()
    if any(w in t for w in ["guerra", "eua", "trump", "irã", "ucrânia", "israel", "otan", "nato", "diplomacia", "netanyahu", "hamas", "hezbollah", "drone", "ataque", "militar", "nuclear", "sanç"]):
        return "Mundo"
    if any(w in t for w in ["lula", "bolsonaro", "senado", "deputado", "governo", "stf", "eleiç", "congresso", "base", "emenda", "partido", "candidat", "impeach", "ministro"]):
        return "Política"
    if any(w in t for w in ["dólar", "ibov", "bolsa", "economia", "banco", "inflação", "juros", "piib", "pib", "mercado", "ações", "petrobras", "investiment", "tarifa", "comércio"]):
        return "Economia"
    if any(w in t for w in ["apple", "google", "ia ", "inteligência artificial", "tech", "celular", "app", "software", "dados", "ciber", "hack", "robô", "algoritm"]):
        return "Tecnologia"
    if any(w in t for w in ["filme", "série", "netflix", "música", "oscar", "grammy", "show", "ator", "atriz", "première", "celebridade"]):
        return "Entretenimento"
    if any(w in t for w in ["copa", "futebol", "olimpíad", "campeonato", "nba", "f1", "jogador", "time", "gol", "título", "liga"]):
        return "Esportes"
    if any(w in t for w in ["ciência", "pesquis", "descoberta", "estudo", "laboratório", "vacina", "vírus", "câncer", "saúde", "médic", "hospital"]):
        return "Ciência"
    return "Geral"


def main():
    result = {"updated": datetime.utcnow().isoformat() + "Z", "source": "google_news_rss", "terms": []}

    for geo, url in RSS_FEEDS.items():
        try:
            xml = fetch_rss(url)
            items = parse_rss(xml)
            for it in items:
                it["geo"] = geo
                it["volume"] = "Trending"
            result["terms"].extend(items)
        except Exception as e:
            print(f"Erro ao buscar {geo}: {e}")

    if not result["terms"]:
        result["updated"] = datetime.utcnow().isoformat() + "Z"
        result["source"] = "unavailable"

    out_path = "ferramentas/data/trends.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"Salvos {len(result['terms'])} termos de {result['source']} em {out_path}")


if __name__ == "__main__":
    main()

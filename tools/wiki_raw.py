"""Fetches raw wikitext from the RuneScape wikis for lore research.

Usage: python wiki_raw.py <host> <Page_Name> [<Page_Name> ...]
       host: rs | osrs | dw
Pages are saved to tools/out/wiki/<host>-<page>.txt and printed.
"""
import os
import sys
import urllib.parse
import urllib.request

HOSTS = {
    "rs": "https://runescape.wiki",
    "osrs": "https://oldschool.runescape.wiki",
    "dw": "https://dragonwilds.runescape.wiki",
}


def fetch(host, page):
    url = HOSTS[host] + "/w/" + urllib.parse.quote(page) + "?action=raw"
    req = urllib.request.Request(url, headers={"User-Agent": "ExtraSpecialStudio-LoreResearch/1.0 (fan mod research)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def main():
    host = sys.argv[1]
    out = os.path.join(os.path.dirname(__file__), "out", "wiki")
    os.makedirs(out, exist_ok=True)
    for page in sys.argv[2:]:
        try:
            text = fetch(host, page)
        except Exception as e:
            print(f"##### {host}:{page} FAILED {e}")
            continue
        safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in page)
        with open(os.path.join(out, f"{host}-{safe}.txt"), "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"##### {host}:{page} ({len(text)} chars)")
        print(text)


if __name__ == "__main__":
    main()

"""Lists printable names from the game's IoStore table of contents.

The .utoc of build 25632050 is not encrypted, so its directory index (folder
and file names) can be read as plain strings. Read-only: the file is opened
for reading and nothing is written next to the game.

Usage: python utoc_names.py <regex> [<regex> ...]
"""
import re
import sys

UTOC = r"C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds\Content\Paks\RSDragonwilds-Windows.utoc"


def main():
    pats = [re.compile(p, re.I) for p in sys.argv[1:]] or [re.compile(".")]
    data = open(UTOC, "rb").read()
    seen = set()
    for m in re.finditer(rb"[ -~]{4,}", data):
        s = m.group().decode("ascii", "replace")
        if s in seen:
            continue
        seen.add(s)
        if any(p.search(s) for p in pats):
            print(s)


if __name__ == "__main__":
    main()

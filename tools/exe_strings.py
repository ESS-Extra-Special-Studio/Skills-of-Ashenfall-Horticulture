"""Lists ASCII and UTF-16 strings from the game executable that match a regex.

Reflection names (classes, functions, properties) are stored as plain strings
in the shipping exe. A hit proves the name is in this build, not how it is
called. Read-only.

Usage: python exe_strings.py <out.txt>          (dump everything once)
       python exe_strings.py --grep <regex> <dump.txt>
"""
import re
import sys

EXE = r"C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\RSDragonwilds-Win64-Shipping.exe"


def dump(out):
    data = open(EXE, "rb").read()
    seen = set()
    with open(out, "w", encoding="utf-8") as fh:
        for m in re.finditer(rb"[A-Za-z_][ -~]{3,200}", data):
            s = m.group().decode("ascii")
            if s not in seen:
                seen.add(s)
                fh.write(s + "\n")
        for m in re.finditer(rb"(?:[A-Za-z_]\x00)(?:[ -~]\x00){3,200}", data):
            s = m.group().decode("utf-16-le")
            if s not in seen:
                seen.add(s)
                fh.write(s + "\n")
    print(len(seen), "strings")


if __name__ == "__main__":
    if sys.argv[1] == "--grep":
        pat = re.compile(sys.argv[2], re.I)
        for line in open(sys.argv[3], encoding="utf-8"):
            if pat.search(line):
                print(line.rstrip())
    else:
        dump(sys.argv[1])

"""Where the sibling checkouts the tools read live on this machine.

Each path comes from an environment variable, else a git-ignored
tools/local_paths.txt (NAME=path lines), else the folder beside this repo.
  ESL_DRAGONWILDS     the ESL-DragonWilds checkout
  DRAGONWILDS_ASSETS  the DragonwildsAssets checkout
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARENT = os.path.dirname(ROOT)


def _local_file():
    out = {}
    path = os.path.join(ROOT, "tools", "local_paths.txt")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            name, sep, value = line.strip().partition("=")
            if sep and not name.startswith("#"):
                out[name.strip()] = value.strip()
    return out


def _path(name, sibling):
    return os.environ.get(name) or _local_file().get(name) or os.path.join(PARENT, sibling)


ESL_REPO = _path("ESL_DRAGONWILDS", "ESL-DragonWilds")
ESL_MOD = os.path.join(ESL_REPO, "ESLDragonWilds")
ESL_CURVE = os.path.join(ESL_MOD, "Scripts", "curve.lua")
ASSETS_REPO = _path("DRAGONWILDS_ASSETS", "DragonwildsAssets")
ASSETS_VANILLA = os.path.join(ASSETS_REPO, "scripts", "vanilla")

"""Horticulture 1-25 XP budget: splicing as the main source, ordinary farming
at about a third of the 1.0 rates.

Reads the XP numbers and level bands from the mod's Lua (rules and training)
and the shared curve from ESL, then plays out in-game days for a few player
styles using expected values (a graft that takes with chance p pays p of the
"takes" XP and 1-p of the "rejected" XP; discoveries count when the expected
number of takes for that pairing reaches 1).

usage: python tools/budget_sim.py
"""
import itertools
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

SCRIPTS = os.path.join(ROOT, "SkillsOfAshenfallHorticulture", "Scripts")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from local_paths import ESL_CURVE as CURVE  # noqa: E402
CAP = 3152

lua = lua54.LuaRuntime()
_t = lua.execute(open(CURVE, encoding="utf-8").read()).TOTAL
TOTAL = [int(_t[i]) for i in range(1, 26)]
lua.execute('package.path = [[' + SCRIPTS + r'\?.lua;]] .. package.path')
R = lua.eval('(require("horticulture_splice_rules"))')
SXP = {k: int(v) for k, v in R.XP.items()}
lua.execute("""
Key = {} ModifierKey = {} function LoopAsync() end function RegisterKeyBindAsync() end
package.preload["UEHelpers"] = function() return {} end
""")
FXP = {k: int(v) for k, v in lua.eval('(require("horticulture_training"))').XP.items()}

CROPS = {k: (int(v.band), float(v.tier)) for k, v in R.CROPS.items()}
TREES = {k: int(v.band) for k, v in R.TREES.items() if v.band}
FLAG = {k: (v.id, int(v.level) if v.level else 0) for k, v in R.FLAGSHIPS.items()}


def level(x):
    lv = 1
    for i, t in enumerate(TOTAL, 1):
        if x >= t:
            lv = i
    return min(lv, 25)


def chance(scion, host, lv, first):
    if first:
        return 1.0
    band = CROPS.get(scion, (TREES.get(scion, 1), 0))[0]
    c = 60 + max(0, lv - band)
    if scion in CROPS:
        host_tier = {"Ash": 1, "Oak": 2, "Willow": 3}.get(host, 1)
        tier = CROPS[scion][1]
        if tier > host_tier:
            c -= -(-(tier - host_tier) // 1) * 10
    return max(25, min(95, c)) / 100


def legal(scion, host, lv, host_kind):
    if scion == host:
        return False
    if host_kind == "plot" and scion in TREES:
        return False
    sb = CROPS.get(scion, (TREES.get(scion), 0))[0]
    hb = CROPS.get(host, (TREES.get(host), 0))[0]
    if sb is None or hb is None or lv < sb or lv < hb:
        return False
    f = FLAG.get(scion + ">" + host)
    return not (f and lv < f[1])


def run(plots, grafts_per_day, trees_per_day, farming=True, days=12):
    xp = 33
    rows = [("unlock", xp, level(xp), 0, 0)]
    found = {}
    expected_takes = {}
    hybrid_trees = 0.0
    free_trees = 2.0
    first = True
    src = {"splice": 0.0, "farm": 0.0}
    pending = []
    for day in range(1, days + 1):
        lv = level(xp)
        # Dawn: yesterday's grafts resolve.
        for scion, host, kind, p in pending:
            gain = p * SXP["takes"] + (1 - p) * SXP["rejected"]
            key = scion + ">" + host
            # Discovery pays on the first take: in expectation, the share of
            # "not found yet" that this attempt turns into "found".
            missing = 1 - expected_takes.get(key, 0)
            expected_takes[key] = 1 - missing * (1 - p)
            gain += missing * p * (SXP["flagship"] if key in FLAG else SXP["discovery"])
            if key not in found and expected_takes[key] >= 0.5:
                found[key] = day
            if kind == "tree":
                hybrid_trees += p
                free_trees += 1 - p
            else:
                gain += p * SXP["pick"]
            xp += gain
            src["splice"] += gain
        pending = []
        first = first and not expected_takes
        # Picks from hybrid trees, once a day each.
        gain = hybrid_trees * SXP["pick"]
        xp += gain
        src["splice"] += gain
        free_trees += trees_per_day
        # Today's grafts: new pairings first (flagships first), else repeats.
        lv = level(xp)
        scions = [s for s in list(CROPS) + list(TREES) if lv >= CROPS.get(s, (TREES.get(s), 0))[0]]
        hosts_plot = [c for c in CROPS if lv >= CROPS[c][0]]
        hosts_tree = [t for t in TREES if lv >= TREES[t]]
        options = []
        for s, h in itertools.product(scions, hosts_plot):
            if legal(s, h, lv, "plot"):
                options.append((s, h, "plot"))
        for s, h in itertools.product(scions, hosts_tree):
            if legal(s, h, lv, "tree"):
                options.append((s, h, "tree"))
        options.sort(key=lambda o: (o[0] + ">" + o[1] in found, o[0] + ">" + o[1] not in FLAG))
        plot_slots, tree_slots = plots // 2, int(free_trees)
        made = 0
        for s, h, kind in options * grafts_per_day:
            if made >= grafts_per_day or (plot_slots <= 0 and tree_slots <= 0):
                break
            if kind == "plot" and plot_slots <= 0 or kind == "tree" and tree_slots <= 0:
                continue
            p = chance(s, h, lv, first and made == 0)
            pending.append((s, h, kind, p))
            gain = SXP["cutting"] + SXP["graft"]
            xp += gain
            src["splice"] += gain
            made += 1
            if kind == "plot":
                plot_slots -= 1
            else:
                tree_slots -= 1
                free_trees -= 1
        # Ordinary farming: half the plots go round each day.
        if farming:
            per_plot = FXP["plant"] + 2 * FXP["water"] + FXP["compost"] + FXP["harvest"]
            gain = plots / 2 * per_plot + (FXP["firstPlant"] + FXP["firstHarvest"] if day <= 4 else 0)
            xp += gain
            src["farm"] += gain
        rows.append((f"day {day}", int(min(xp, CAP)), level(xp), made, len(found)))
        if xp >= CAP:
            break
    return rows, found, src


STYLES = [
    ("steady: 8 plots, 6 grafts/day, plants 2 trees/day", (8, 6, 2)),
    ("keen: 12 plots, 10 grafts/day, plants 3 trees/day", (12, 10, 3)),
    ("light: 4 plots, 3 grafts/day, plants 1 tree/day", (4, 3, 1)),
]

if __name__ == "__main__":
    print("Splicing XP:", SXP)
    print("Farming XP (about a third of 1.0):", FXP)
    print("Level 25 =", TOTAL[24], "XP (cap", CAP, ")")
    for name, args in STYLES:
        rows, found, src = run(*args)
        print("\n" + name)
        for label, x, lv, made, n in rows:
            print("   %-8s %5d XP  L%-2d  grafts %2d  hybrids found %2d" % (label, x, lv, made, n))
        total = src["splice"] + src["farm"]
        print("   share: splicing %d%%, farming %d%%" % (100 * src["splice"] / total, 100 * src["farm"] / total))
        flags = sorted((d, k) for k, d in found.items() if k in FLAG)
        print("   flagships:", ", ".join("%s day %d" % (FLAG[k][0], d) for d, k in flags))

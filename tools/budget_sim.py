import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pylib"))
from lupa import lua54  # noqa: E402

CURVE = r"<user>\IdeaProjects\ESL-DragonWilds\ESLDragonWilds\Scripts\curve.lua"
_t = lua54.LuaRuntime().execute(open(CURVE, encoding="utf-8").read()).TOTAL
TOTAL = [int(_t[i]) for i in range(1, 26)]
XP = dict(plant=30, water=15, compost=30, harvest=70, firstPlant=50, firstHarvest=100)


def level(x):
    lv = 1
    for i, t in enumerate(TOTAL, 1):
        if x >= t:
            lv = i
    return lv


def run(plots, species, compost=True, waters=2):
    xp = 33
    rows = [("Unlock: read the Observances", xp, level(xp))]
    seen_p, seen_h = set(), set()
    for cycle in range(1, 9):
        steps = [("sow", "plant")] + [("water", "water")] + ([("compost", "compost")] if compost else [])
        steps += [("water", "water")] * (waters - 1) + [("harvest", "harvest")]
        for label, kind in steps:
            for p in range(plots):
                sp = p % species
                xp += XP[kind]
                if kind == "plant" and sp not in seen_p:
                    seen_p.add(sp)
                    xp += XP["firstPlant"]
                if kind == "harvest" and sp not in seen_h:
                    seen_h.add(sp)
                    xp += XP["firstHarvest"]
                if xp >= 3152:
                    rows.append((f"Cycle {cycle} {label}, plot {p + 1} of {plots}", xp, 25))
                    return rows
            rows.append((f"Cycle {cycle} {label} ({plots} plots)", xp, level(xp)))
    return rows


for args in [(8, 4, True), (8, 1, True), (8, 4, False), (12, 4, True), (4, 2, True)]:
    print(args)
    for r in run(*args):
        print("   %-40s %5d  L%d" % r)

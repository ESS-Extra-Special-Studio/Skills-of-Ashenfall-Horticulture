"""Estimates the play needed to take vanilla Farming from 1 to 25.

Every XP number below was read from the shipped game (build 25632050):
  DT_XPEvents_Farming (IoStore, parsed by hand; rows -> float XP):
    Tilling 3, Watering_Stage_1 2, Watering_Stage_2 15, Watering_Stage_3 2,
    CuringPlant_Stage_1..3 2, Planting 5, Composting_Tier_1 10,
    Composting_Tier_2 50, Composting_Tier_3 30, Harvesting 8,
    TreePlanting 2, CreatingCurePotion 2
  [/Script/Dominion.FarmingSettings] in RSDragonwilds-Windows.pak:
    YieldXpFactor=1.0, BerryBushXpReductionFactor=0.05, CyclePeriod=720 s,
    GrowthStageToPerTierWateringXPMultiplier=((1, 1.0))
  FPD_Cabbage / FPD_Potato / FPD_Wheat: BaseYield 5, HarvestXpFactor default
  FPD_Onion / FPD_Tomato: Tier 2, BaseYield 5, HarvestXpFactor set (wiki: 2)
  DT_XPEvents_Tomes: Tome_Tier1_Farming 100, Tome_Tier2_Farming 400
  CT_XPByLevel: read from ESL's curve.lua at run time (L10 463, L15 969,
  L20 1,798, L25 3,152), never copied here
Formulae and the 2-day crop cycle are from the DW wiki Farming page:
  Yield = ceil(ceil(ceil(Base*secateurs)*compost)*water), compost 1.5, water 1.15
  HarvestXP = ceil(8 * (1 + Yield * HarvestXpFactor) * boosts)
Level unlocks (wiki): compost bin at Farming 10, Uproot 15, trees 20.
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

sys.path.insert(0, os.path.join(ROOT, "tools"))
from local_paths import ESL_CURVE as CURVE  # noqa: E402


def load_curve():
    lua = lua54.LuaRuntime()
    curve = lua.execute(open(CURVE, encoding="utf-8").read())
    t = curve.TOTAL
    return {lvl: int(t[lvl]) for lvl in range(1, len(t) + 1)}


TOTAL = load_curve()
assert TOTAL[25] == 3152 and TOTAL[15] == 969, "ESL curve.lua changed"
PLANT, WATER_SEEDED, WATER_GROWING, COMPOST, HARVEST_BASE = 5, 2, 15, 10, 8


def harvest_xp(factor, compost, watered, boost=1.0):
    y = 5
    if compost:
        y = math.ceil(y * 1.5)
    if watered:
        y = math.ceil(y * 1.15)
    return math.ceil(HARVEST_BASE * (1 + y * factor) * boost), y


def cycle_xp(factor=1, compost=False, hand_water=True, boost=1.0):
    """One plot, plant to harvest: plant, water day 1 (seeded) and day 2 (growing)."""
    h, _ = harvest_xp(factor, compost, True, boost)
    xp = PLANT + h
    if hand_water:
        xp += WATER_SEEDED + WATER_GROWING
    if compost:
        xp += COMPOST
    return math.ceil(xp * boost) if boost != 1.0 else xp


def run(name, plots, start_xp, factor=1, hand_water=True, boost=1.0, compost_from=10):
    xp, cycles, plot_cycles = start_xp, 0, 0
    while xp < TOTAL[25]:
        compost = xp >= TOTAL[compost_from]
        per = cycle_xp(factor, compost, hand_water, boost)
        xp += per * plots
        cycles += 1
        plot_cycles += plots
    print(f"{name:52} {plots:>3} plots  {cycles:>2} crop cycles  {plot_cycles:>3} plot-cycles"
          f"  ~{cycles * 2:>2} in-game days")
    return cycles


def main():
    print("Per plot-cycle XP (tier-1 crop, ash plot):")
    print(f"  no compost, hand-watered : {cycle_xp(1, False, True)}  (harvest {harvest_xp(1, False, True)})")
    print(f"  compost, hand-watered    : {cycle_xp(1, True, True)}  (harvest {harvest_xp(1, True, True)})")
    print(f"  compost, rain-watered    : {cycle_xp(1, True, False)}")
    print(f"  tier-2 crop, compost     : {cycle_xp(2, True, True)}")
    print()
    quest = 9 + 5 + 2 + 15 + harvest_xp(1, False, True)[0]
    print(f"Growing Pains (3 weed layers, 1 wheat plot) ~{quest} XP, plus a Tome of Farming (100 or 400 base)")
    print()
    start_low = quest + 100
    start_high = quest + 400
    print(f"{'scenario':52} {'':>9}  {'':>15}")
    run("fresh, tome 100, hand-watered", 4, start_low)
    run("fresh, tome 100, hand-watered", 8, start_low)
    run("fresh, tome 400, hand-watered", 8, start_high)
    run("fresh, tome 100, rain does the watering", 8, start_low, hand_water=False)
    run("fresh, tome 100, 15% boost (ring + food)", 8, start_low, boost=1.155)
    run("Ghornfell player, tier-2 seeds", 8, start_low, factor=2)
    run("fresh, tome 100, hand-watered", 12, start_low)
    print()
    print("Milestones on the 8-plot, hand-watered path (cumulative XP after each cycle):")
    xp, cycle = start_low, 0
    while xp < TOTAL[25]:
        xp += cycle_xp(1, xp >= TOTAL[10], True) * 8
        cycle += 1
        lvl = max(level for level, total in TOTAL.items() if xp >= total)
        print(f"  cycle {cycle}: {xp:>5} XP, Farming {lvl}")


if __name__ == "__main__":
    main()

"""Offline tests for splicing: rules, the satchel save, the cut/graft/dawn
loop, the world helpers, hybrid layouts, and horticulture_splicing.lua
driven with a fake world and ESL.

usage: python tools/splice_test.py
"""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

SCRIPTS = os.path.join(ROOT, "SkillsOfAshenfallHorticulture", "Scripts")
TMP = tempfile.mkdtemp(prefix="hort_splice_")

BASE = r"""
local scripts = ...
package.path = scripts .. "\\?.lua;" .. package.path
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = { CONTROL = "CTRL", SHIFT = "SHIFT", ALT = "ALT" }
print = function() end
loops, binds = {}, {}
function LoopAsync(ms, fn) loops[#loops + 1] = fn end
function ExecuteInGameThread(fn) fn() end
function RegisterKeyBindAsync(key, mods, fn)
    local m = table.concat(mods or {}, "+")
    binds[(m ~= "" and (m .. "+") or "") .. key] = fn
end
function FText(s) return s end
function FName(s) return s end
function FindAllOf() return nil end
function FindFirstOf() return nil end
local invalid = { IsValid = function() return false end }
function StaticFindObject() return invalid end
package.preload["UEHelpers"] = function()
    return {
        GetPlayerController = function() return nil end,
        GetWorld = function() return nil end,
        GetKismetSystemLibrary = function() return nil end,
    }
end
"""

failures = 0


def check(name, ok, detail=""):
    global failures
    failures += 0 if ok else 1
    print(("ok   " if ok else "FAIL ") + name + ((" -> " + str(detail)) if detail != "" else ""))


def fresh():
    lua = lua54.LuaRuntime()
    lua.execute(BASE, SCRIPTS)
    return lua


# Rules -------------------------------------------------------------------
L = fresh()
R = L.eval('(require("horticulture_splice_rules"))')
cancut = L.eval("function(t) local ok, why = require('horticulture_splice_rules').CanCut(t) return tostring(ok) .. '|' .. tostring(why) end")
cangraft = L.eval("function(s, h, lv) local ok, why = require('horticulture_splice_rules').CanGraft(s, h, lv) return tostring(ok) .. '|' .. tostring(why) end")
T = L.table_from


def t(**kw):
    return L.table_from(kw)


r = cancut(t(species="Ash", level=1))
check("ash cutting needs an axe in hand", r.startswith("false") and "axe" in r, r)
r = cancut(t(species="Ash", level=1, axePower=1))
check("ash cutting with a stone axe", r.startswith("true"), r)
r = cancut(t(species="Oak", level=8, axePower=1))
check("oak cutting with a stone axe is refused", r.startswith("false") and "too weak" in r, r)
r = cancut(t(species="Oak", level=7, axePower=3))
check("oak cutting needs Horticulture 8", r.startswith("false") and "8" in r, r)
r = cancut(t(species="Oak", level=8, axePower=3))
check("oak cutting at 8 with a bronze axe", r.startswith("true"), r)
r = cancut(t(species="FPD_Potato", level=4, alive=True))
check("potato cutting needs 5", r.startswith("false") and "5" in r, r)
r = cancut(t(species="FPD_Potato", level=5, alive=True))
check("potato cutting at 5 from a living plant", r.startswith("true"), r)
r = cancut(t(species="FPD_Potato", level=5, alive=False))
check("no cutting from a dead plant", r.startswith("false") and "living" in r, r)
r = cancut(t(species="Maple", level=25, axePower=8))
check("maple is beyond v1", r.startswith("false") and "beyond" in r, r)
r = cancut(t(species="Willow", level=20, axePower=4))
check("willow cutting at 20 with an iron axe", r.startswith("true"), r)

r = cangraft("Oak", t(species="FPD_Cabbage", kind="plot", stage=1), 25)
check("tree cutting never onto a crop", r.startswith("false") and "cannot take on a crop" in r, r)
r = cangraft("FPD_Potato", t(species="Ash", kind="tree", planted=True), 5)
check("potato onto a planted ash", r.startswith("true"), r)
r = cangraft("FPD_Potato", t(species="Ash", kind="tree", planted=False), 5)
check("wild tree refused", r.startswith("false") and "planted" in r, r)
r = cangraft("FPD_Cabbage", t(species="FPD_Potato", kind="plot", stage=1), 5)
check("cabbage onto a growing potato plot", r.startswith("true"), r)
r = cangraft("FPD_Cabbage", t(species="FPD_Potato", kind="plot", stage=2), 5)
check("not onto a harvestable crop", r.startswith("false"), r)
r = cangraft("FPD_Potato", t(species="FPD_Potato", kind="plot", stage=1), 5)
check("same species is not a hybrid", r.startswith("false") and "just more" in r, r)
r = cangraft("FPD_Cabbage", t(species="FPD_Cabbage", kind="plot", stage=1), 1)
check("cabbage onto cabbage is allowed (the Primelet graft)", r.startswith("true"), r)
check("cabbage onto cabbage is a Doubled Cabbage", R.HybridName("FPD_Cabbage", "FPD_Cabbage") == "Doubled Cabbage")

plants = L.eval(r"""function()
    local R = require("horticulture_splice_rules")
    local out = {}
    out[#out + 1] = R.PlantsKey({ "Ash", "FPD_Potato" })
    out[#out + 1] = R.PlantsKey({ "Ash", "FPD_Potato", "FPD_Cabbage" })
    out[#out + 1] = R.PlantsName({ "Ash", "FPD_Potato" })
    out[#out + 1] = R.PlantsName({ "Ash", "FPD_Potato", "FPD_Cabbage" })
    local tree = { kind = "tree", planted = true }
    local plot = { kind = "plot", stage = 1 }
    local function can(p, s, h, lv) local ok, why = R.CanAddTo(p, s, h, lv) return tostring(ok) .. "|" .. tostring(why) end
    out[#out + 1] = can({ "Ash", "FPD_Potato" }, "FPD_Cabbage", tree, 25)
    R.MAX_LEVEL = 99
    out[#out + 1] = tostring(R.MaxPlants(49)) .. tostring(R.MaxPlants(50))
    out[#out + 1] = can({ "Ash", "FPD_Potato" }, "FPD_Cabbage", tree, 50)
    out[#out + 1] = can({ "FPD_Potato", "FPD_Cabbage" }, "Oak", plot, 50)
    out[#out + 1] = can({ "Ash", "FPD_Potato" }, "FPD_Potato", tree, 50)
    out[#out + 1] = can({ "Ash", "FPD_Potato", "FPD_Cabbage" }, "FPD_Wheat", tree, 60)
    R.MAX_LEVEL = 25
    return table.concat(out, "\n")
end""")().split("\n")
check("plant list key: newest cutting first, host last", plants[0] == "FPD_Potato>Ash" and plants[1] == "FPD_Cabbage>FPD_Potato>Ash", plants[:2])
check("plant list names", plants[2] == "Tuberwood Ash" and plants[3] == "Cabbage-Potato-Ash", plants[2:4])
check("v1: a third graft is beyond 25", plants[4].startswith("false") and "beyond" in plants[4], plants[4])
check("Triple Graft opens at 50 in the 1-99 plan", plants[5] == "23", plants[5])
check("triple: cabbage onto Tuberwood Ash", plants[6].startswith("true"), plants[6])
check("triple: a tree cutting still never goes onto a crop", "cannot take on a crop" in plants[7], plants[7])
check("triple: no plant twice", "already carries" in plants[8], plants[8])
check("triple: three at most", plants[9].startswith("false"), plants[9])
r = cangraft("FPD_Cabbage", t(species="Oak", kind="sapling", planted=True), 7)
check("oak host needs 8", r.startswith("false") and "8" in r, r)
r = cangraft("Ash", t(species="Oak", kind="tree", planted=True), 8)
check("ash onto oak (tree on tree)", r.startswith("true"), r)
r = cangraft("Willow", t(species="Oak", kind="tree", planted=True), 19)
check("Weeping Oak needs 20", r.startswith("false") and "20" in r, r)

chance = L.eval("function(s, h, lv, b) return require('horticulture_splice_rules').Chance(s, h, lv, b) end")
check("chance at band is 60", chance("FPD_Cabbage", t(species="Ash"), 1, 0) == 60)
check("chance +1 per level above band", chance("FPD_Cabbage", t(species="Ash"), 11, 0) == 70)
check("chance -10 per tier above host", chance("FPD_Onion", t(species="FPD_Cabbage", tier=1), 18, 0) == 50,
      chance("FPD_Onion", t(species="FPD_Cabbage", tier=1), 18, 0))
check("chance clamps at 95", chance("FPD_Cabbage", t(species="Ash"), 25, 30) == 95)
check("names", R.HybridName("FPD_Potato", "Ash") == "Tuberwood Ash" and R.HybridName("FPD_Flax", "Oak") == "Flax-Oak")
prods = L.eval("function() local p = require('horticulture_splice_rules').Products('FPD_Potato', 'Ash') return #p .. ' ' .. p[1].count .. ' ' .. p[1].item end")()
check("Tuberwood Ash gives 3 potatoes", prods.startswith("1 3 ") and prods.endswith("ITEM_Resources_Potato"), prods)
n = L.eval("function() local n, r = 0, 0 for _, f in pairs(require('horticulture_splice_rules').FLAGSHIPS) do n = n + 1 if f.required then r = r + 1 end end return n .. '/' .. r end")()
check("8 flagships, 5 required", n == "8/5", n)

# Store -------------------------------------------------------------------
roundtrip = L.eval(r"""function(path)
    local Store = require("horticulture_splice_store")
    local st = Store.New()
    st.dawn = 4; st.firstTaken = true; st.nextId = 3
    st.cuttings = { { species = "FPD_Potato", taken = 4 }, { species = "Ash", taken = 3 } }
    st.selected = 2
    st.grafts = { { id = "g2", kind = "tree", host = "Ash", scion = "FPD_Potato", state = "hybrid", made = 3, lastPick = 4, x = 100.4, y = -50, z = 7 } ,
                  { id = "g1", kind = "plot", host = "FPD_Potato", scion = "FPD_Cabbage", state = "pending", made = 4, key = "plot:77", tier = 1, x = 1, y = 2, z = 3 } }
    st.sources = { ["plot:77"] = 4, old = 2 }
    assert(Store.Save(path, st))
    local b = Store.Load(path)
    return string.format("%d %s %d %d %s %s %d %s %s %s %s %s %s", b.dawn, tostring(b.firstTaken), b.nextId, #b.cuttings,
        b.cuttings[1].species, b.selected, #b.grafts, b.grafts[1].host, tostring(b.grafts[1].lastPick), tostring(b.grafts[1].x),
        b.grafts[2].key, tostring(b.sources["plot:77"]), tostring(b.sources.old))
end""")
got = roundtrip(os.path.join(TMP, "store.txt"))
check("store round trip", got == "4 true 3 2 FPD_Potato 2 2 Ash 4 100 plot:77 4 nil", got)
missing = L.eval("function(p) local s = require('horticulture_splice_store').Load(p) return s.dawn .. #s.cuttings end")(os.path.join(TMP, "none.txt"))
check("missing file is a fresh satchel", missing == "00", missing)

V1 = """# old
version=1
dawn=3
selected=1
nextid=4
firsttaken=1
cut=FPD_Potato|3
graft=g2|tree|Ash|FPD_Potato|hybrid|2|3|100|200|0||||
graft=g3|plot|FPD_Potato|FPD_Cabbage|pending|3||5|6|0|plot:7|1||
"""
with open(os.path.join(TMP, "v1.txt"), "w") as f:
    f.write(V1)
mig = L.eval(r"""function(path, out)
    local Store = require("horticulture_splice_store")
    local st = Store.Load(path)
    local g1, g2 = st.grafts[1], st.grafts[2]
    local a = string.format("%d %s %s %s %s %s %s %s", #st.grafts, table.concat(g1.plants, ">"), g1.host, g1.scion,
        tostring(g1.lastPick), table.concat(g2.plants, ">"), g2.key, tostring(g2.tier))
    Store.Save(out, st)
    local text = io.open(out):read("*a")
    local b = Store.Load(out)
    return a .. "\n" .. (text:find("version=2", 1, true) and "v2" or "v?") .. " " .. table.concat(b.grafts[1].plants, ">")
        .. " " .. b.grafts[2].host .. " " .. b.grafts[2].scion
end""")(os.path.join(TMP, "v1.txt"), os.path.join(TMP, "v2.txt")).split("\n")
check("version 1 save migrates to plant lists", mig[0] == "2 Ash>FPD_Potato Ash FPD_Potato 3 FPD_Potato>FPD_Cabbage plot:7 1", mig[0])
check("migrated save is written as version 2 and reads back", mig[1] == "v2 Ash>FPD_Potato FPD_Potato FPD_Cabbage", mig[1])

trip = L.eval(r"""function(path)
    local Store = require("horticulture_splice_store")
    local st = Store.New()
    st.grafts = { Store.SetPlants({ id = "g9", kind = "tree", state = "hybrid", x = 1, y = 2, z = 3, world = "Aseroth" },
        { "Ash", "FPD_Potato", "FPD_Cabbage" }) }
    st.primelets = { { id = "p4", stage = 2, growth = 3, tended = 5, born = 1, world = "Aseroth", x = 10.4, y = 20, z = 30, yaw = 90, carried = false },
                     { id = "p5", stage = 1, growth = 0, tended = -1, born = 2, world = "?", x = 0, y = 0, z = 0, yaw = 0, carried = true } }
    st.cuttings = { { species = "Primelet", taken = 2, primelet = "p5" }, { species = "FPD_Cabbage", taken = 5 } }
    Store.Save(path, st)
    local b = Store.Load(path)
    local g, p, q = b.grafts[1], b.primelets[1], b.primelets[2]
    return string.format("%s %s %s %s|%s %d %d %d %s %s %s|%s %s|%s %s", table.concat(g.plants, ">"), g.host, g.scion, g.world,
        p.id, p.stage, p.growth, p.tended, p.world, tostring(p.x), tostring(p.carried), q.id, tostring(q.carried),
        tostring(b.cuttings[1].primelet), tostring(b.cuttings[2].primelet))
end""")(os.path.join(TMP, "trip.txt"))
check("three-plant hybrid, primelets and a carried primelet round-trip",
      trip == "Ash>FPD_Potato>FPD_Cabbage Ash FPD_Cabbage Aseroth|p4 2 3 5 Aseroth 10 false|p5 true|p5 nil", trip)

# Core: the Tuberwood Ash loop ---------------------------------------------
flow = L.eval(r"""function()
    local Core = require("horticulture_splice_core")
    local st = require("horticulture_splice_store").New()
    local out = {}
    local function say(...) out[#out + 1] = table.concat({ ... }, " ") end
    local potato = { species = "FPD_Potato", kind = "crop", key = "plot:1", level = 5, alive = true }
    local c, why = Core.TakeCutting(st, potato)
    say("cut", c and c.species or why)
    c, why = Core.TakeCutting(st, potato)
    say("again", c and "yes" or why)
    local ash = { species = "Ash", kind = "sapling", planted = true, x = 1000, y = 2000, z = 0 }
    local g
    g, why = Core.Graft(st, ash, 5)
    say("graft", g and (g.scion .. ">" .. g.host .. " " .. g.state) or why)
    g, why = Core.Graft(st, ash, 5)
    say("regraft", g and "yes" or why)
    local outs, wilted = Core.Dawn(st, 5, function() return 100 end)
    say("dawn", #outs, outs[1] and outs[1].result or "-", outs[1] and outs[1].chance or "-")
    -- the sapling has grown into a tree a few cm away
    local tree = { species = "Ash", kind = "tree", planted = true, x = 1040, y = 1990, z = 0 }
    local h = Core.GraftOn(st, tree)
    say("same host", h and h.state or "none")
    local p
    p, why = Core.Pick(st, h)
    say("pick", p and (#p .. " " .. p[1].count .. " " .. p[1].name) or why)
    p, why = Core.Pick(st, h)
    say("pick again", p and "yes" or why)
    Core.Dawn(st, 5, function() return 100 end)
    p = Core.Pick(st, h)
    say("next day", p and "yes" or "no")
    return table.concat(out, "\n")
end""")
lines = flow().split("\n")
check("take a potato cutting", lines[0] == "cut FPD_Potato", lines[0])
check("one cutting per plant per day", "already took" in lines[1], lines[1])
check("graft potato onto planted ash", lines[2] == "graft FPD_Potato>Ash pending", lines[2])
check("no second graft on a pending host", "after dawn" in lines[3], lines[3])
check("first graft always takes at dawn", lines[4] == "dawn 1 takes 100", lines[4])
check("sapling grown into a tree keeps the graft", lines[5] == "same host hybrid", lines[5])
check("pick 3 potatoes", lines[6] == "pick 1 3 Potato", lines[6])
check("once a day", "Already picked today" in lines[7], lines[7])
check("pick again after dawn", lines[8] == "next day yes", lines[8])

misc = L.eval(r"""function()
    local Core = require("horticulture_splice_core")
    local st = require("horticulture_splice_store").New()
    local out = {}
    for i = 1, 7 do
        local c, why = Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "p" .. i, level = 1, alive = true })
        if not c then out[#out + 1] = why end
    end
    out[#out + 1] = "#" .. #st.cuttings
    Core.Dawn(st, 1, function() return 1 end)
    out[#out + 1] = "after1 " .. #st.cuttings
    Core.Dawn(st, 1, function() return 1 end)
    out[#out + 1] = "after2 " .. #st.cuttings
    -- rejection: second graft can fail
    st.firstTaken = true
    Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "z", level = 1, alive = true })
    Core.Graft(st, { species = "Ash", kind = "tree", planted = true, x = 0, y = 0 }, 1)
    local outs = Core.Dawn(st, 1, function() return 100 end)
    out[#out + 1] = outs[1].result .. " " .. outs[1].chance .. " grafts " .. #st.grafts
    -- crop host harvest returns products
    Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "y", level = 5, alive = true })
    local g = Core.Graft(st, { species = "FPD_Potato", kind = "plot", key = "plot:9", stage = 1, tier = 1, x = 5, y = 5 }, 5)
    Core.Dawn(st, 5, function() return 1 end)
    local p = Core.Harvested(st, g)
    out[#out + 1] = "harvest " .. #p .. " " .. p[1].count .. " " .. p[1].name .. " grafts " .. #st.grafts
    -- lost host
    Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "x", level = 5, alive = true })
    Core.Graft(st, { species = "FPD_Potato", kind = "plot", key = "plot:10", stage = 1, x = 9, y = 9 }, 5)
    outs = Core.Dawn(st, 5, function() return 1 end, function() return false end)
    out[#out + 1] = outs[1].result
    return table.concat(out, "\n")
end""")
lines = misc().split("\n")
check("satchel holds 6", "full (6)" in lines[0] and lines[1] == "#6", lines[:2])
check("cuttings survive one dawn", lines[2] == "after1 6", lines[2])
check("cuttings wilt after two dawns", lines[3] == "after2 0", lines[3])
check("a later graft can be rejected", lines[4] == "rejected 60 grafts 0", lines[4])
check("Brassitato harvest adds 2 cabbages", lines[5] == "harvest 1 2 Cabbage grafts 0", lines[5])
check("host gone by dawn: graft lost", lines[6] == "lost", lines[6])

# Brassica Primelet ---------------------------------------------------------
prime = L.eval(r"""function()
    local Core = require("horticulture_splice_core")
    local P = require("horticulture_primelet")
    local st = require("horticulture_splice_store").New()
    local out = {}
    local function say(...) out[#out + 1] = table.concat({ ... }, " ") end
    say("roll", tostring(P.Roll(function() return 15 end, 1.5)), tostring(P.Roll(function() return 16 end, 1.5)),
        tostring(P.Roll(function() return 1 end, 0)))
    -- An ordinary take: a Doubled Cabbage.
    st.firstTaken = true
    Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "a", level = 1, alive = true })
    Core.Graft(st, { species = "FPD_Cabbage", kind = "plot", key = "plot:1", stage = 1, tier = 1, x = 0, y = 0, z = 0, world = "W" }, 1)
    local outs = Core.Dawn(st, 1, function(n) return n == 1000 and 500 or 1 end)
    say("plain", outs[1].result, #st.grafts, #st.primelets)
    -- Forced: the graft becomes a primelet beside the plot.
    Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "b", level = 1, alive = true })
    Core.Graft(st, { species = "FPD_Cabbage", kind = "plot", key = "plot:2", stage = 1, tier = 1, x = 500, y = 0, z = 7, world = "W" }, 1)
    outs = Core.Dawn(st, 1, function() return 1 end, nil, { forcePrimelet = true })
    local p = outs[1].primelet
    say("forced", outs[1].result, #st.grafts, #st.primelets, p.x, p.y, p.z, p.world, P.Name(p))
    -- Cabbage onto potato never becomes one.
    Core.TakeCutting(st, { species = "FPD_Cabbage", kind = "crop", key = "c", level = 5, alive = true })
    Core.Graft(st, { species = "FPD_Potato", kind = "plot", key = "plot:3", stage = 1, tier = 1, x = 900, y = 0 }, 5)
    outs = Core.Dawn(st, 5, function() return 1 end, nil, { forcePrimelet = true })
    say("brassitato", outs[1].result)
    -- Tending and growth.
    local rng = function(n) return 1 end
    local line, counted = P.Tend(st, p, rng)
    say("tend", tostring(counted))
    line, counted = P.Tend(st, p, rng)
    say("again", tostring(counted), line:find("after dawn") and "after dawn" or line)
    local _, _, grown = Core.Dawn(st, 1, rng)
    say("day1", p.growth, p.stage, #grown)
    Core.Dawn(st, 1, rng)
    say("untended", p.growth, p.stage)
    P.Tend(st, p, rng)
    _, _, grown = Core.Dawn(st, 1, rng)
    say("day2", p.growth, p.stage, #grown, P.Name(p))
    for i = 1, 3 do P.Tend(st, p, rng) Core.Dawn(st, 1, rng) end
    say("grown", p.growth, p.stage, P.Name(p))
    P.Tend(st, p, rng) Core.Dawn(st, 1, rng)
    say("cap", p.stage)
    -- Near, pick up, keep through dawns, set down in another world.
    local me = { X = 350, Y = 0 }
    say("near", tostring(P.Near(st, me, 0, "W") == p), tostring(P.Near(st, me, 180, "W") == p), tostring(P.Near(st, me, 0, "Other") == nil))
    local cutting = Core.TakeCutting(st, { species = "Primelet", kind = "crop", level = 25, alive = true })
    say("cut", tostring(cutting))
    local entry = P.PickUp(st, p, 6)
    say("carried", tostring(p.carried), #P.Visible(st, "W"), Core.Selected(st).primelet)
    Core.Dawn(st, 1, rng) Core.Dawn(st, 1, rng) Core.Dawn(st, 1, rng)
    say("kept", #st.cuttings, Core.Selected(st).primelet)
    local g, why = Core.Graft(st, { species = "Ash", kind = "tree", planted = true, x = 0, y = 0 }, 1)
    say("nograft", why)
    P.Place(st, entry, 1, 2, 3, 45, "Other")
    say("placed", #st.cuttings, tostring(p.carried), p.world, #P.Visible(st, "W"), #P.Visible(st, "Other"))
    say("status", P.StatusLine(st, "Other"))
    return table.concat(out, "\n")
end""")().split("\n")
check("primelet roll: 1.5% is 15 in 1000; 0 never", prime[0] == "roll true false false", prime[0])
check("cabbage on cabbage usually makes a Doubled Cabbage", prime[1] == "plain takes 1 0", prime[1])
check("a primelet climbs out beside the plot; the graft ends", prime[2] == "forced primelet 1 1 590 0 7 W Primelet Sprout", prime[2])
check("only cabbage on cabbage can become a primelet", prime[3] == "brassitato takes", prime[3])
check("tend once a day", prime[4] == "tend true" and prime[5] == "again false after dawn", prime[4:6])
check("a tended day grows it", prime[6] == "day1 1 1 0", prime[6])
check("an untended day does not", prime[7] == "untended 1 1", prime[7])
check("two tended days: Brassica Primelet", prime[8] == "day2 2 2 1 Brassica Primelet", prime[8])
check("five tended days: Prime-ling", prime[9] == "grown 5 3 Prime-ling", prime[9])
check("Prime-ling is the last stage", prime[10] == "cap 3", prime[10])
check("near: facing it, not turned away, not in another world", prime[11] == "near true false true", prime[11])
check("no cutting from a primelet", prime[12] == "cut nil", prime[12])
check("picked up into the satchel", prime[13].startswith("carried true 0 p"), prime[13])
check("a carried primelet never wilts", prime[14].startswith("kept 1 p"), prime[14])
check("a carried primelet is not grafted", "Set the Primelet down" in prime[15], prime[15])
check("set down in another world", prime[16] == "placed 0 false Other 0 1", prime[16])
check("status line", prime[17].startswith("status Prime-ling (fully grown, at home"), prime[17])

# World helpers -------------------------------------------------------------
W = L.eval('(require("horticulture_world"))')
names = [("BP_FellableTree_Oak_C", "Oak"), ("SM_FH_Ash_Tree_01", "Ash"), ("BP_Sapling_Ash_01_C", "Ash"),
         ("BP_FellableTree_MagicTree_C", "Magic"), ("SM_Willow_01", "Willow"), ("BP_FellableTree_Base_C", None),
         ("SM_Splash_01", None), ("BP_Sapling_Yew_Small1_C", "Yew")]
for n_, want in names:
    got = W.SpeciesFromName(n_)
    check("species from " + n_, got == want, got)
crops = [("BP_Gatherable_Potato_C", "FPD_Potato"), ("Potato", "FPD_Potato"), ("Cabbage Plant", "FPD_Cabbage"),
         ("SM_Redberry_Bush_01", "FPD_Redberry"), ("Potato Seeds", None), ("ITEM_Farming_Seed_Potato", None),
         ("BP_Spawner_Onion_C", "FPD_Onion"), ("Wheat", "FPD_Wheat"), ("Ash Logs", None), ("Potatoes", "FPD_Potato")]
for n_, want in crops:
    got = W.CropFromName(n_)
    check("crop from " + n_, got == want, got)
check("dawn passed 5:50 -> 6:10", W.PassedDawn(5.8, 6.2) is True)
check("dawn not passed 6:10 -> 9:00", W.PassedDawn(6.2, 9.0) is False)
check("sleep 22:00 -> 7:00 passes dawn", W.PassedDawn(22.0, 7.0) is True)
check("22:00 -> 2:00 does not", W.PassedDawn(22.0, 2.0) is False)
check("3:00 -> 23:00 (slept a whole day) passes", W.PassedDawn(3.0, 23.0) is True)

pick = L.eval(r"""function()
    local W = require("horticulture_world")
    local me = { X = 0, Y = 0, Z = 0 }
    local eye = { X = 0, Y = 0, Z = 160 }
    local list = {
        { kind = "plot", loc = { X = 200, Y = 0, Z = 0 }, name = "plot" },
        { kind = "tree", loc = { X = 400, Y = 300, Z = 0 }, name = "tree" },
        { kind = "tree", loc = { X = 3000, Y = 0, Z = 0 }, name = "far" },
    }
    local function aim(x, y, z) local l = math.sqrt(x*x+y*y+z*z) return { X = x/l, Y = y/l, Z = z/l } end
    local a = W.Pick(list, eye, aim(200, 0, -150), me)
    local b = W.Pick(list, eye, aim(400, 300, 0), me)
    local c = W.Pick(list, eye, aim(-1, 0, 0), me)
    local d = W.Pick(list, eye, aim(1, 0, 0), me)
    return (a and a.name or "-") .. " " .. (b and b.name or "-") .. " " .. (c and c.name or "-") .. " " .. (d and d.name or "-")
end""")()
check("aim picks plot, tree trunk, nothing behind, not out of reach", pick == "plot tree - -", pick)

tall = L.eval(r"""function()
    local W = require("horticulture_world")
    local me = { X = 0, Y = 0, Z = 0 }
    local eye = { X = -400, Y = 0, Z = 160 }
    local list = { { kind = "sapling", planted = true, loc = { X = 200, Y = 0, Z = 0 }, name = "sapling" } }
    local a = W.Pick(list, eye, { X = 1, Y = 0, Z = 0 }, me)
    local b = W.Pick(list, eye, { X = 0, Y = 1, Z = 0 }, me)
    return (a and a.name or "-") .. " " .. (b and b.name or "-")
end""")()
check("a level camera ray hits a grown sapling's trunk", tall == "sapling -", tall)

feet = L.eval(r"""function()
    local W = require("horticulture_world")
    local me = { X = 0, Y = 0, Z = 0 }
    local list = {
        { kind = "wild", loc = { X = 50, Y = 0, Z = 0 }, name = "wild" },
        { kind = "sapling", planted = false, loc = { X = 80, Y = 0, Z = 0 }, name = "wildsap" },
        { kind = "sapling", planted = true, loc = { X = 150, Y = 0, Z = 0 }, name = "shoot" },
        { kind = "sapling", planted = true, loc = { X = 200, Y = 0, Z = 0 }, name = "far" },
    }
    local a = W.NearestPlanted(list, me, 220)
    local b = W.NearestPlanted(list, me, 100)
    return (a and a.name or "-") .. " " .. (b and b.name or "-")
end""")()
check("a planted shoot at the feet counts as aimed; wild ones do not", feet == "shoot -", feet)

# Looks layouts ------------------------------------------------------------
lay = L.eval(r"""function()
    local Looks = require("horticulture_looks")
    local out = {}
    for _, id in ipairs({ "TuberwoodAsh", "BrassicaOak", "SheafAsh", "WeepingOak", "BambleNone" }) do
        local p = Looks.Layout(id, "FPD_Cabbage", "tree", { height = 900, radius = 300 })
        local bad = 0
        for _, piece in ipairs(p) do if not Looks.MESH[piece.mesh] then bad = bad + 1 end end
        out[#out + 1] = id .. "=" .. #p .. (bad > 0 and "!" or "")
    end
    local b = Looks.Layout("Brassitato", "FPD_Cabbage", "plot", { height = 40, radius = 40 })
    out[#out + 1] = "Brassitato=" .. #b .. ":" .. b[1].mesh
    local tub = Looks.Layout("TuberwoodAsh", "FPD_Potato", "tree", { height = 900, radius = 300 })
    local low = true
    for _, piece in ipairs(tub) do if piece.z < 300 then low = false end end
    out[#out + 1] = "tuberhigh=" .. tostring(low)
    local o = Looks.ParseOverrides("# c\nTuberwoodAsh = /Game/Mods/X/SM_T\nBrassicaOak=/Game/A/B.B\n")
    out[#out + 1] = o.TuberwoodAsh .. " " .. o.BrassicaOak
    out[#out + 1] = Looks.PACKAGED.TuberwoodAsh
    return table.concat(out, " ")
end""")()
check("layouts for the flagships", all(s in lay for s in ["TuberwoodAsh=12", "BrassicaOak=10", "SheafAsh=12", "WeepingOak=2", "BambleNone=4"]) and "!" not in lay, lay)
check("Brassitato crowns the potato with a cabbage", "Brassitato=1:cabbage" in lay, lay)
check("built-in Tuberwood potatoes hang in the canopy", "tuberhigh=true" in lay, lay)
check("meshes.txt overrides", "/Game/Mods/X/SM_T.SM_T /Game/A/B.B" in lay, lay)
att = L.eval(r"""function()
    local Looks = require("horticulture_looks")
    local out = {}
    local list = Looks.ParseAttachments([[
# Tuberwood Ash: potatoes hanging in the branches
/Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01 | 120 -40 610 | 0 35 90 | 1.8
/Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01.SM_Potato_Fruit_01 | 1 2 3 | | 1 2 3
/Game/Art/X/SM_Bare
]])
    out[#out + 1] = #list .. " " .. list[1].path .. " " .. list[1].z .. " " .. list[1].yaw .. " " .. list[1].roll .. " " .. list[1].scale
    out[#out + 1] = list[2].path .. " " .. list[2].scale .. list[2].scaleY .. list[2].scaleZ .. " " .. list[3].x .. list[3].scale
    local pieces = Looks.AttachmentPieces(list, 2)
    out[#out + 1] = pieces[1].x .. " " .. pieces[1].z .. " " .. pieces[1].scale .. " " .. pieces[2].scaleZ
    local Rules = require("horticulture_splice_rules")
    local tri = Looks.LayoutPlants({ "Ash", "FPD_Potato", "FPD_Wheat" }, Rules.HybridId, "tree", { height = 900, radius = 300 })
    out[#out + 1] = "triple=" .. #tri
    local pl = Looks.PrimeletLayout(1.5)
    local bad, ingots = 0, 0
    for _, p in ipairs(pl) do
        if not Looks.MESH[p.mesh] then bad = bad + 1 end
        if p.mesh == "goldIngot" then ingots = ingots + 1 end
    end
    out[#out + 1] = "primelet=" .. #pl .. " " .. pl[1].mesh .. " " .. tostring(pl[1].tint ~= nil) .. " ingots " .. ingots .. " bad " .. bad
    return table.concat(out, "\n")
end""")().split("\n")
check("attachment file: path, location, rotation, scale", att[0] == "3 /Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01.SM_Potato_Fruit_01 610 35 90 1.8", att[0])
check("attachment file: full path, per-axis scale, path only", att[1] == "/Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01.SM_Potato_Fruit_01 123 01", att[1])
check("attachments scale with the host actor", att[2] == "240 1220 3.6 6", att[2])
check("a triple hybrid wears both layouts (Tuberwood 12 + Sheaf 12)", att[3] == "triple=24", att[3])
check("primelet look: tinted cabbage and a crown of 5 gold ingots", att[4] == "primelet=6 cabbage true ingots 5 bad 0", att[4])
check("packaged Tuberwood path", "/Game/Mods/SkillsOfAshenfallHorticulture/Art/Plants/TuberwoodAsh/SM_TuberwoodAsh_Additions_01.SM_TuberwoodAsh_Additions_01" in lay, lay)

# Pipeline placement data ---------------------------------------------------
pl = L.eval(r"""function(scripts)
    local P = require("horticulture_placements")
    local out = {}
    for _, id in ipairs({ "TuberwoodAsh", "BrassicaOak", "SheafAsh", "Brassitato", "WeepingOak" }) do
        local d, why = P.Load(scripts, id)
        if not d then
            out[#out + 1] = id .. "=missing " .. tostring(why)
        else
            local hosts, bad, pieces, nonVanilla = 0, 0, 0, 0
            for host in pairs(d.hosts) do
                hosts = hosts + 1
                local shape = P.Shape(d, host)
                if not shape or #shape.attachments == 0 then bad = bad + 1 else
                    for _, p in ipairs(P.Pieces(shape, { havePak = false })) do
                        pieces = pieces + 1
                        if not p.path:find("^/Game/Art/") then nonVanilla = nonVanilla + 1 end
                    end
                end
            end
            out[#out + 1] = string.format("%s=%d hosts %d bad %d nonvanilla", id, hosts, bad, nonVanilla)
        end
    end
    local d = P.Load(scripts, "TuberwoodAsh")
    local key = P.HostKey("StaticMesh /Game/Art/Env/Landscape/Foliage/Trees/Ash_Tree/SM_FH_Ash_Tree_02.SM_FH_Ash_Tree_02")
    local shape, name = P.Shape(d, key)
    local all = #P.Pieces(shape, { havePak = true })
    local free = P.Pieces(shape, { havePak = false })
    local capped = P.Pieces(shape, { havePak = false, cap = 40 })
    local ground = 0
    for _, p in ipairs(capped) do if p.group == "ground_fruit" then ground = ground + 1 end end
    local high = 0
    for _, p in ipairs(free) do if p.group == "canopy_fruit" and p.z > 600 then high = high + 1 end end
    out[#out + 1] = string.format("tub %s %s all %d free %d capped %d ground %d high %d", key:match("[^/]+$"), name, all, #free, #capped, ground, high)
    out[#out + 1] = "none=" .. tostring(P.Shape(d, "/Game/Art/X/SM_Unknown") == nil) .. " " .. tostring(P.Load(scripts, "TwoBarkAsh") == nil)
    local q = P.Quat(10, 30, -20)
    local r = P.Rotator(q)
    out[#out + 1] = string.format("rot %.2f %.2f %.2f", r.Pitch, r.Yaw, r.Roll)
    local loc, rot, s = P.World({ x = 100, y = 0, z = 50, pitch = 0, yaw = 10, roll = 0, scale = 2, scaleY = 2, scaleZ = 2 },
        { X = 1000, Y = 2000, Z = 0 }, { Pitch = 0, Yaw = 90, Roll = 0 }, { X = 1.5, Y = 1.5, Z = 1.5 })
    out[#out + 1] = string.format("world %.0f %.0f %.0f yaw %.0f scale %.1f", loc.X, loc.Y, loc.Z, rot.Yaw, s.X)
    local t = P.Transform(free[1])
    out[#out + 1] = string.format("xf %.3f %.0f", math.sqrt(t.Rotation.X ^ 2 + t.Rotation.Y ^ 2 + t.Rotation.Z ^ 2 + t.Rotation.W ^ 2), t.Translation.Z)
    return table.concat(out, "\n")
end""")(SCRIPTS).split("\n")
for line, want in zip(pl[:5], ["TuberwoodAsh=9 hosts 0 bad 0", "BrassicaOak=6 hosts 0 bad 0", "SheafAsh=9 hosts 0 bad 0",
                               "Brassitato=3 hosts 0 bad 0", "WeepingOak=6 hosts 0 bad 0"]):
    check("placement data: " + want.split("=")[0] + " covers every host with vanilla meshes only", line.startswith(want) and line.endswith(" 0 nonvanilla"), line)
check("host picked by mesh path; stalks need the pak; cap drops fallen fruit first", pl[5].startswith("tub SM_FH_Ash_Tree_02 shape_1 all 132 free 104 capped 40 ground 0"), pl[5])
check("Tuberwood potatoes hang in the canopy (most above 6 m)", int(pl[5].split("high ")[1]) >= 40, pl[5])
check("unknown host or hybrid: no placement data", pl[6] == "none=true true", pl[6])
check("rotator <-> quaternion round trip", pl[7] == "rot 10.00 30.00 -20.00", pl[7])
check("world transform on a turned, scaled host", pl[8] == "world 1000 2150 75 yaw 100 scale 3.0", pl[8])
check("instance transform: unit quaternion and location", pl[9].startswith("xf 1.000 "), pl[9])

# Newest placement version, material overrides
vdir = os.path.join(TMP, "vers")
os.makedirs(os.path.join(vdir, "placements"), exist_ok=True)
for v, tag in [(1, "old"), (3, "new"), (12, "bad")]:
    with open(os.path.join(vdir, "placements", "hort_plant_sheaf_ash_v%03d.lua" % v), "w") as f:
        f.write('return { schema = "ess.hybrid_placement/1", shapes = {}, hosts = {}, tag = "%s" }' % tag if tag != "bad" else "return {")
mo = L.eval(r"""function(scripts, vdir)
    local P = require("horticulture_placements")
    local out = {}
    P.Reset()
    local files = {}
    for _, id in ipairs({ "TuberwoodAsh", "BrassicaOak", "SheafAsh", "Brassitato", "WeepingOak" }) do
        files[#files + 1] = P.Load(scripts, id).file:match("_(v%d+)$")
    end
    out[#out + 1] = "files " .. table.concat(files, " ")
    P.Reset()
    local d, why = P.Load(vdir, "SheafAsh")
    out[#out + 1] = "pick " .. tostring(d and d.tag) .. " " .. tostring(why)
    P.Reset()
    local tub = P.Load(scripts, "TuberwoodAsh")
    local all = 0
    for _, s in pairs(tub.shapes) do
        local n = #P.Pieces(s, { havePak = false, cap = require("horticulture_looks").CAP.ism })
        local free = #P.Pieces(s, { havePak = false })
        if n == free then all = all + 1 end
    end
    out[#out + 1] = "ismcap " .. all
    local w = P.Load(scripts, "WeepingOak")
    local keys, pieces = {}, 0
    for name, s in pairs(w.shapes) do
        for _, p in ipairs(P.Pieces(s, { havePak = false })) do
            pieces = pieces + 1
            keys[P.OverrideKey(p.overrides)] = true
        end
    end
    local nk = 0
    for _ in pairs(keys) do nk = nk + 1 end
    local p = P.Pieces(w.shapes.shape_1, {})[1]
    local c = P.OverrideCalls(p.overrides[1])
    local v = c.vectors[1]
    out[#out + 1] = string.format("willow %d piece(s) %d key(s) slot %d %s %.2f %.2f %.2f %.0f scalars %s=%.2f %s=%.2f none='%s'",
        pieces, nk, c.slot, v[1], v[2].R, v[2].G, v[2].B, v[2].A, c.scalars[1][1], c.scalars[1][2], c.scalars[2][1], c.scalars[2][2],
        P.OverrideKey(P.Pieces(tub.shapes.shape_1, {})[1].overrides))
    -- applying them to a component: recorded calls; a failing engine call is swallowed
    local Looks = require("horticulture_looks")
    Looks.Init(require("horticulture_util"), vdir)
    local calls = {}
    local mid = { IsValid = function() return true end,
        SetVectorParameterValue = function(_, n, c) calls[#calls + 1] = "v " .. n .. string.format(" %.2f", c.G) end,
        SetScalarParameterValue = function(_, n, x) calls[#calls + 1] = "s " .. n .. string.format(" %.2f", x) end }
    local comp = { GetMaterial = function(_, i) return "MI" .. i end,
        CreateDynamicMaterialInstance = function(_, i, src, name) calls[#calls + 1] = "mid " .. i .. " " .. tostring(src) return mid end }
    Looks.ApplyOverrides(comp, p.overrides)
    out[#out + 1] = table.concat(calls, ", ")
    local broken = { GetMaterial = function() error("gone") end, CreateDynamicMaterialInstance = function() error("no") end }
    local ok = pcall(Looks.ApplyOverrides, broken, p.overrides)
    out[#out + 1] = "broken " .. tostring(ok)
    return table.concat(out, "\n")
end""")(SCRIPTS, vdir).split("\n")
check("newest shipped versions are used (Brassitato stays v001)", mo[0] == "files v007 v002 v002 v001 v002", mo[0])
check("loader takes the newest file that loads (a broken newer one is skipped)", mo[1] == "pick new nil", mo[1])
check("instanced cap keeps every pak-free Tuberwood piece on all three shapes", mo[2] == "ismcap 3", mo[2])
check("Weeping Oak overrides reach the pieces (one instanced component per tree)", mo[3].startswith("willow 2 piece(s) 1 key(s) slot 0 Color_Mult_A 1.15 1.45 0.20 1 scalars Color_Mult_Blend=1.00 Subsurface Amount scale=0.35 none=''"), mo[3])
check("overrides: one dynamic instance of the slot's material, then its parameters",
      mo[4] == "mid 0 MI0, v Color_Mult_A 1.45, v Color_Mult_B 1.45, s Color_Mult_Blend 1.00, s Subsurface Amount scale 0.35", mo[4])
check("overrides: engine failures are swallowed", mo[5] == "broken true", mo[5])

# The game glue, with a fake world -----------------------------------------
GLUE = r"""
local scripts, tmp = ...
logs = {}
print = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
xp, cards, awards, given, applied, cleared = {}, {}, {}, {}, {}, {}
level, unlocked = 5, true
aimed, nearby, axe, hour = nil, {}, nil, 12.0
local pawn = { IsValid = function() return true end, GetFullName = function() return "Pawn /p" end,
    K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end }
local pc = { IsValid = function() return true end, GetFullName = function() return "PC /pc" end, Pawn = pawn }
package.loaded["UEHelpers"] = { GetPlayerController = function() return pc end, GetWorld = function() return nil end,
    GetKismetSystemLibrary = function() return nil end }
local W = require("horticulture_world")
W.Aimed = function() return aimed end
W.Nearby = function() return nearby end
W.HeldAxe = function() return axe end
W.Hour = function() return hour end
W.IsServer = function() return true end
W.Give = function(item, n) given[#given + 1] = item:match("([^/]+)$") .. "x" .. n return true end
local Looks = require("horticulture_looks")
Looks.Init = function() end
Looks.Apply = function(g, h, mode, id) applied[#applied + 1] = g.id .. ":" .. mode .. ":" .. id return 3 end
Looks.Clear = function(id) cleared[#cleared + 1] = id end
Looks.ApplyPrimelet = function(id, loc, yaw, scale) applied[#applied + 1] = id .. ":" .. string.format("%.0f,%.0f,%.2f", loc.X, loc.Y, scale) return 6 end
Looks.ClearAll = function() end
local paid, order = {}, {}
ESL = {
    Character = function() return "Tester" end,
    IsUnlocked = function() return unlocked end,
    GetLevel = function() return level end,
    Gate = function() cards[#cards + 1] = "GATE" end,
    AddXp = function(_, n, label) xp[#xp + 1] = label .. "=" .. n return n end,
    Award = function(_, id, n) if paid[id] then return nil end paid[id] = true order[#order + 1] = id awards[#awards + 1] = id .. "=" .. n return n end,
    HasPaid = function(_, id) return paid[id] == true end,
    Paid = function() return order end,
    ShowCard = function(_, k, t, d) cards[#cards + 1] = k .. "|" .. t .. "|" .. d return true end,
    Store = { ProgressFile = function(char, skill) return tmp .. "\\" .. char .. "." .. skill .. ".txt" end },
}
S = require("horticulture_splicing")
S.Start({ ESL = ESL, SKILL = "Horticulture", dir = tmp, actionKey = "G" })
local t0 = 0
os.clock = function() t0 = t0 + 10 return t0 end
function tick() for _, fn in ipairs(loops) do fn() end end
function press(k) binds[k]() tick() end
function take(list) local s = table.concat(_G[list], " ; ") _G[list] = {} return s end
function plot(species, stage, x) return { kind = "plot", species = species, stage = stage, alive = stage == 1 or stage == 2, tier = 1,
    key = "plot:" .. x, planted = true, loc = { X = x, Y = 0, Z = 0 }, obj = {}, actor = {} } end
function tree(species, planted, x, kind) return { kind = kind or "tree", species = species, planted = planted, alive = true,
    loc = { X = x, Y = 100, Z = 0 }, obj = {}, actor = {} } end
"""

L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
g = L.globals()
potato = g.plot("FPD_Potato", 1, 50)
ash = g.tree("Ash", True, 300, "sapling")
g.nearby = L.table_from([potato, ash])
bound = sorted(str(k) for k in g.binds.keys())
check("splicing keys are G, Alt+G, Shift+G and E (Primelet); none on Ctrl (the game's Evade)",
      bound == ["ALT+G", "E", "G", "SHIFT+G"], bound)

g.aimed = potato
g.press("G")
check("G on a potato plot takes a cutting", "Cutting taken=8" in g.take("xp"), "")
c = g.take("cards")
check("CUTTING TAKEN card (ESL card, own kicker)", "CUTTING TAKEN|Potato|Satchel 1/6" in c, c)
g.aimed = ash
g.press("G")
x = g.take("xp")
check("G on a planted ash with a potato cutting grafts", "Graft made=20" in x, x)
c = g.take("cards")
check("GRAFT MADE card promises the first graft", "GRAFT MADE|Potato onto ash|Your first graft" in c, c)
check("pending look applied", "g1:pending:TuberwoodAsh" in g.take("applied"))
g.hour = 5.5
g.tick()
g.hour = 6.5
g.tick()
for _ in range(4):
    g.tick()
x = g.take("xp")
a = g.take("awards")
c = g.take("cards")
check("dawn: graft took (+45)", "Graft took=45" in x, x)
check("Tuberwood Ash discovered once (+200)", "hybrid:TuberwoodAsh=200" in a, a)
check("TUBERWOOD ASH DISCOVERED reveal card", "DISCOVERY CATALOGUE|TUBERWOOD ASH DISCOVERED|" in c and "1 of 8 flagship" in c, c)
check("never the game's Farming & Fishing card", "Farming" not in c and "Fishing" not in c, "")
check("lore card follows", "FROM THE DISCOVERY CATALOGUE|Tuberwood Ash|An ash that has decided" in c, c)
titles = [card.split("|")[1] for card in c.split(" ; ") if card.count("|") >= 2]
check("hybrid card titles fit on one line", titles and max(len(t) for t in titles) <= 40, titles)
g.tick()
check("hybrid look applied", "g1:hybrid:TuberwoodAsh" in g.take("applied"))
g.aimed = ash
g.press("G")
check("G on Tuberwood Ash picks 3 potatoes", "ITEM_Resources_Potatox3" in g.take("given"))
x = g.take("xp")
check("picking pays 25", "Hybrid picked=25" in x, x)
g.press("G")
c = g.take("cards")
check("second pick the same day refused", "Already picked today" in c, c)
cat = g.S.CatalogueLine()
check("catalogue line", cat == "Hybrids (1/8 flagship): Tuberwood Ash", cat)

# A tree cutting never goes onto a crop; Alt+G cuts; axe gating.
g.aimed = g.tree("Ash", False, 900)
g.axe = None
g.press("ALT+G")
c = g.take("cards")
check("Alt+G on a tree without an axe says why", "NO CUTTING|Hold a logging axe" in c, c)
g.axe = 1
g.press("ALT+G")
check("Alt+G with a stone axe takes an ash cutting", "Cutting taken=8" in g.take("xp"))
g.take("cards")
g.aimed = ash
g.press("G")
c = g.take("cards")
check("picked hybrid with a cutting in hand says when to pick, not that it cannot graft",
      "NOTHING TO PICK|Already picked today" in c and "CANNOT GRAFT" not in c, c)
cab = g.plot("FPD_Cabbage", 1, 1200)
g.nearby = L.table_from([potato, ash, cab])
g.aimed = cab
g.press("G")
c = g.take("cards")
x = g.take("xp")
check("ash cutting onto a cabbage is refused", "CANNOT GRAFT|Tree cuttings cannot take on a crop" in c, c)
check("refusal pays nothing", "Graft made" not in x, x)

# Save survives a restart.
save = os.path.join(TMP, "Tester.Horticulture.splicing.txt")
check("splicing save written beside the ESL file", os.path.exists(save), save)
L2 = fresh()
L2.execute(GLUE, SCRIPTS, TMP)
st = L2.eval('(require("horticulture_splicing")).State()')
check("restart keeps grafts and satchel", st is not None and len(st.grafts) == 1 and len(st.cuttings) == 1 and st.dawn == 1,
      "" if st is None else (len(st.grafts), len(st.cuttings), st.dawn))

# Crop-on-crop: Brassitato through the plot's harvest.
L = fresh()
L.execute(GLUE, SCRIPTS, os.path.join(TMP))
g = L.globals()
os.remove(save)
L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
g = L.globals()
cabbage = g.plot("FPD_Cabbage", 1, 50)
potato = g.plot("FPD_Potato", 1, 400)
g.nearby = L.table_from([cabbage, potato])
g.aimed = cabbage
g.press("G")
g.aimed = potato
g.press("G")
g.S.Dawn("test")
for _ in range(4):
    g.tick()
a = g.take("awards")
check("Brassitato discovered", "hybrid:Brassitato=200" in a, a)
potato.stage = 2
g.tick()
potato.stage = 0
potato.species = None
g.tick()
gv = g.take("given")
check("Brassitato harvest gives 2 cabbages", "ITEM_Resources_Cabbagex2" in gv, gv)
for _ in range(3):
    g.tick()
c = g.take("cards")
check("HYBRID HARVEST card", "HYBRID HARVEST|Brassitato|" in c, c)

# A wild potato is a source, never a host.
os.remove(save)
L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
g = L.globals()
wild = L.eval('function() return { kind = "wild", species = "FPD_Potato", alive = true, planted = false, loc = { X = 40, Y = 0, Z = 0 } } end')()
ash = g.tree("Ash", True, 300, "sapling")
g.nearby = L.table_from([wild, ash])
g.aimed = wild
g.press("G")
check("G on a wild potato takes a cutting", "Cutting taken=8" in g.take("xp"))
g.take("cards")
g.press("G")
c = g.take("cards")
check("a wild potato is not a host", "NO CUTTING|" in c and "GRAFT MADE" not in c, c)
g.aimed = ash
g.press("G")
check("wild potato cutting grafts onto a planted ash", "Graft made=20" in g.take("xp"))

# Brassica Primelet in the world: graft, forced reveal, tend, carry, set down.
os.remove(save)
L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
g = L.globals()
c1 = g.plot("FPD_Cabbage", 1, 2000)
c2 = g.plot("FPD_Cabbage", 1, 50)
g.nearby = L.table_from([c1, c2])
g.aimed = c1
g.press("G")
g.aimed = c2
g.press("G")
x = g.take("xp")
check("cabbage onto cabbage grafts", "Graft made=20" in x, x)
g.take("cards")
g.S.ForcePrimelet()
g.S.Dawn("test")
for _ in range(6):
    g.tick()
a = g.take("awards")
c = g.take("cards")
check("Primelet reveal: secret catalogue entry and XP", "hybrid:BrassicaPrimelet=200" in a, a)
check("Primelet reveal cards in order", c.find("SOMETHING HAS HAPPENED|BRASSICA PRIMELET") >= 0
      and c.find("SOMETHING HAS HAPPENED") < c.find("SECRET ENTRY: BRASSICA PRIMELET") < c.find("Brassica Primelet|The Observances")
      < c.find("KEEPING A PRIMELET|Brassica Primelet|Tend it once a day"), c)
titles = [card.split("|")[1] for card in c.split(" ; ") if card.count("|") >= 2]
check("reveal card titles fit on one line", titles and max(len(t) for t in titles) <= 40, titles)
ap = g.take("applied")
check("Primelet drawn beside the plot", "prime:p" in ap and ":140,0,0.80" in ap, ap)
check("catalogue lists the secret entry once found", "Brassica Primelet (secret)" in g.S.CatalogueLine(), g.S.CatalogueLine())
g.aimed = None
g.press("G")
c = g.take("cards")
check("G beside it tends it", "TENDED|Primelet Sprout|" in c and "Primelet tended=5" in g.take("xp"), c)
g.binds["E"]()
c = g.take("cards")
check("E tends it too, once a day", "PRIMELET|Primelet Sprout|It has had all the attention" in c, c)
g.press("ALT+G")
c = g.take("cards")
check("Alt+G picks it up", "PICKED UP|Primelet Sprout|" in c, c)
check("satchel shows it", "Primelet Sprout*" in g.S.SatchelLine(), g.S.SatchelLine())
check("status line says it is carried", "in your satchel" in g.S.PrimeletLine(), g.S.PrimeletLine())
g.press("G")
c = g.take("cards")
check("G sets it down", "SET DOWN|Primelet Sprout|" in c, c)
ap = g.take("applied")
check("set down in front of the player", ":120,0,0.80" in ap, ap)
L2 = fresh()
L2.execute(GLUE, SCRIPTS, TMP)
pl = L2.eval('(function() local st = require("horticulture_splicing").State() return #st.primelets .. " " .. tostring(st.primelets[1].carried) .. " " .. st.primelets[1].x end)()')
check("restart keeps the Primelet where it was set down", pl == "1 false 120", pl)

# The dev force key seeds a graft ahead of a player with no cabbage plots.
os.remove(save)
L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
g = L.globals()
g.nearby = L.table_from([])
g.S.ForcePrimelet()
g.S.ForcePrimelet()
n = L.eval('(function() return #require("horticulture_splicing").State().grafts end)()')
check("dev force seeds one cabbage graft", n == 1, n)
g.S.Dawn("test")
for _ in range(6):
    g.tick()
check("seeded graft becomes a Primelet ahead of the player", "hybrid:BrassicaPrimelet=200" in g.take("awards"))
ap = g.take("applied")
check("seeded Primelet two metres ahead", "prime:p" in ap and ":200,0," in ap, ap)

# Action Wheel (optional companion) ----------------------------------------
WHEEL = r"""
local tmp = ...
local Wheel = require("horticulture_wheel")
noWheel = Wheel.Start(S, tmp .. "\\nowhere", function() end)
local W = require("horticulture_world")
W.Facing = function() return { X = 0, Y = 0, Z = 0 }, 0 end
W.WorldKey = function() return "w" end
statusRuns = 0
package.loaded["actionwheel"] = { Register = function(def) def_ = def return true end }
withWheel = Wheel.Start(S, tmp, function() statusRuns = statusRuns + 1 end)
function act(id) for _, a in ipairs(def_.actions) do if a.id == id then return a end end end
function view(id)
    local r = act(id).check({ kind = "tree" })
    if r == nil then return "hidden" end
    return (r.enabled and "on" or "off") .. (r.locked and " locked" or "") .. (r.label and (" " .. r.label) or "") .. (r.reason and (" | " .. r.reason) or "")
end
function kids(id)
    local out = {}
    for _, k in ipairs(act(id).children({ kind = "tree" })) do
        out[#out + 1] = k.label .. (k.enabled and " on" or " off") .. (k.reason and (" | " .. k.reason) or "")
    end
    return table.concat(out, " ; ")
end
function run(id, kind) act(id).run({ kind = kind }) tick() end
function choose(id, value) act(id).run({ kind = "tree" }, { value = value }) tick() end
function ids() local out = {} for _, a in ipairs(def_.actions) do out[#out + 1] = a.id end return table.concat(out, ",") end
"""
os.remove(save) if os.path.exists(save) else None
L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
L.execute(WHEEL, TMP)
g = L.globals()
check("wheel: without ActionWheel, Start returns false and the keys stay as they are",
      g.noWheel is False and sorted(str(k) for k in g.binds.keys()) == ["ALT+G", "E", "G", "SHIFT+G"], g.noWheel)
check("wheel: with ActionWheel, Horticulture registers its slices",
      g.withWheel is True and g.ids() == "pick,graft,take_cutting,inspect,tend,pick_up,set_down,next_cutting,status", g.ids())

potato = g.plot("FPD_Potato", 1, 50)
ash = g.tree("Ash", True, 300, "sapling")
oak = g.tree("Oak", True, 600)
g.nearby = L.table_from([potato, ash, oak])
g.aimed = potato
g.level = 1
v = g.view("take_cutting")
check("wheel: Take cutting greyed and locked by level, with the rule's reason", v == "off locked | Potato cuttings need Horticulture 5", v)
check("wheel: Graft hidden with an empty satchel; Pick hidden without a hybrid", g.view("graft") == "hidden" and g.view("pick") == "hidden")
g.level = 5
check("wheel: Take cutting on at Horticulture 5", g.view("take_cutting") == "on", g.view("take_cutting"))
g.run("take_cutting", "crop")
check("wheel: Take cutting runs the same cutting as Alt+G", "Cutting taken=8" in g.take("xp"))
v = g.view("take_cutting")
check("wheel: one cutting per plant per day, greyed with the reason", v == "off | You already took a cutting from this plant today", v)
g.aimed = oak
v = g.view("graft")
check("wheel: Graft greyed when every cutting is refused for the same reason (level gate)", v == "off locked | Oak hosts need Horticulture 8", v)
g.aimed = ash
check("wheel: Graft on a planted ash with a potato cutting", g.view("graft") == "on" and g.kids("graft") == "Potato cutting on", g.kids("graft"))
check("wheel: Check graft hidden before a graft", g.view("inspect") == "hidden")
g.choose("graft", 1)
x = g.take("xp")
check("wheel: choosing the cutting grafts it", "Graft made=20" in x, x)
g.take("cards")
check("wheel: Check graft offered once grafted", g.view("inspect") == "on")
g.run("inspect", "sapling")
c = g.take("cards")
check("wheel: Check graft shows the chance before dawn", "GRAFT|Potato onto ash|Waiting for dawn. About 100% it takes." in c, c)
g.S.Dawn("test")
for _ in range(4):
    g.tick()
g.take("cards"); g.take("xp"); g.take("awards")
v = g.view("pick")
check("wheel: Pick names the hybrid", v == "on Pick Tuberwood Ash", v)
g.run("pick", "sapling")
check("wheel: Pick gives the same produce as G", "ITEM_Resources_Potatox3" in g.take("given"))
v = g.view("pick")
check("wheel: picked today, greyed with the reason", v == "off Pick Tuberwood Ash | Already picked today. More after dawn", v)

# Primelet slices, on the self wheel as well.
L.execute('local P = require("horticulture_primelet") local st = S.State() P.New(st, 60, 0, 0, "w") S.Save()')
v = g.view("tend")
check("wheel: Tend offered beside a Primelet, by its stage name", v.startswith("on Tend "), v)
check("wheel: Primelet slices go on every wheel, including the self wheel", "all" in list(g.act("tend").kinds.values()))
g.run("tend", "self")
c = g.take("cards")
check("wheel: Tend tends (once a day)", "TENDED|" in c, c)
check("wheel: tended today, greyed", g.view("tend").endswith("| Already tended today. Again after dawn"), g.view("tend"))
g.run("pick_up", "self")
c = g.take("cards")
check("wheel: Pick up puts it in the satchel", "PICKED UP|" in c, c)
v = g.view("set_down")
check("wheel: carrying it, Set down appears and Graft hides", v.startswith("on Set down ") and g.view("graft") == "hidden", v)
check("wheel: Next cutting hidden with one thing in the satchel", g.view("next_cutting") == "hidden")
g.axe = 1
g.run("take_cutting", "sapling")
g.take("cards"); g.take("xp")
check("wheel: Next cutting on the self wheel with two things in the satchel", g.view("next_cutting") == "on")
g.run("next_cutting", "self")
c = g.take("cards")
check("wheel: Next cutting runs Shift+G's cycle", "SELECTED|Primelet Sprout|1 of 2" in c, c)
g.run("status", "self")
check("wheel: Horticulture slice runs the status key's function", g.statusRuns == 1, g.statusRuns)

g.unlocked = False
check("wheel: locked skill: Take cutting greyed and locked, the rest hidden",
      g.view("take_cutting").startswith("off locked | Horticulture is locked") and g.view("pick") == "hidden"
      and g.view("graft") == "hidden" and g.view("tend") == "hidden" and g.view("status") == "on", g.view("take_cutting"))

if failures and os.environ.get("SPLICE_DEBUG"):
    for i in range(1, len(g.logs) + 1):
        print("  log:", g.logs[i])

print("RESULT", "FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)

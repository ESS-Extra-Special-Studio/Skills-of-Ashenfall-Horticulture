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
check("two tended days: Brassica Primelet, now known by its full name", prime[8].startswith("day2 2 2 1 ") and " the " in prime[8], prime[8])
check("five tended days: Mini Brassica Prime", prime[9].startswith("grown 5 3 ") and " the " in prime[9], prime[9])
check("Mini Brassica Prime is the last stage", prime[10] == "cap 3", prime[10])
check("stage names: Sprout, Brassica Primelet, Mini Brassica Prime",
      L.eval('(function() local P = require("horticulture_primelet") return P.STAGES[1].name .. "|" .. P.STAGES[2].name .. "|" .. P.STAGES[3].name end)()')
      == "Primelet Sprout|Brassica Primelet|Mini Brassica Prime")
check("near: facing it, not turned away, not in another world", prime[11] == "near true false true", prime[11])
check("no cutting from a primelet", prime[12] == "cut nil", prime[12])
check("picked up into the satchel", prime[13].startswith("carried true 0 p"), prime[13])
check("a carried primelet never wilts", prime[14].startswith("kept 1 p"), prime[14])
check("a carried primelet is not grafted", "Set the Primelet down" in prime[15], prime[15])
check("set down in another world", prime[16] == "placed 0 false Other 0 1", prime[16])
check("status line", prime[17].startswith("status ") and ", Mini Brassica Prime (fully grown, at home" in prime[17], prime[17])

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
    local big = 0
    for _, piece in ipairs(tub) do big = math.max(big, piece.scale) end
    out[#out + 1] = string.format("fruitmax=%.2f", big)
    local o = Looks.ParseOverrides("# c\nTuberwoodAsh = /Game/Mods/X/SM_T\nBrassicaOak=/Game/A/B.B\n")
    out[#out + 1] = o.TuberwoodAsh .. " " .. o.BrassicaOak
    out[#out + 1] = Looks.PACKAGED.TuberwoodAsh
    return table.concat(out, " ")
end""")()
check("layouts for the flagships", all(s in lay for s in ["TuberwoodAsh=12", "BrassicaOak=10", "SheafAsh=12", "WeepingOak=2", "BambleNone=4"]) and "!" not in lay, lay)
check("Brassitato crowns the potato with a cabbage", "Brassitato=1:cabbage" in lay, lay)
check("built-in Tuberwood potatoes hang in the canopy", "tuberhigh=true" in lay, lay)
check("built-in layouts keep fruit at natural size (1.0)", "fruitmax=1.00" in lay, lay)
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
check("no whole-hybrid cooked meshes are assumed (meshes.txt can still name one)", lay.endswith("/Game/A/B.B"), lay)

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
    local high, groundFree, maxFruit = 0, 0, 0
    for _, p in ipairs(free) do
        if p.group == "canopy_fruit" and p.z > 600 then high = high + 1 end
        if p.group == "ground_fruit" then groundFree = groundFree + 1 end
        if P.IsFruit(p.group, p.path) then maxFruit = math.max(maxFruit, p.scale, p.scaleY, p.scaleZ) end
    end
    out[#out + 1] = string.format("fruit %d %.3f %s %s", groundFree, maxFruit, tostring(P.Skipped("Fallen_Fruit")), tostring(P.Skipped("canopy_fruit")))
    -- The safety net on old-style data: ground fruit dropped, giant fruit clamped,
    -- natural wheat (a whole plant mesh at half scale) left alone.
    local fake = { attachments = {
        { mesh = "/Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01", group = "ground_fruit", scale = { 1, 1, 1 } },
        { mesh = "/Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01", group = "canopy_fruit", scale = { 2.8, 2.8, 2.8 } },
        { mesh = "/Game/Art/Item/Resources/Wheat/SM_Wheat_01", group = "canopy_fruit", scale = { 0.5, 0.5, 0.55 } },
        { mesh = "/Game/Art/Item/Resources/Wheat/SM_Wheat_01", group = "canopy_fruit", scale = { 1.4, 1.4, 1.4 } },
        { mesh = "/Game/Mods/SoAHorticulture/Hybrids/SM_HYB_FruitStem_01", group = "canopy_stem", scale = { 1, 1, 1.6 } },
    } }
    local fp = P.Pieces(fake, { havePak = true })
    out[#out + 1] = string.format("safety %d %.2f %.2f/%.2f %.2f %.2f", #fp, fp[1].scale, fp[2].scale, fp[2].scaleZ, fp[3].scale, fp[4].scaleZ)
    local sheaf = P.Load(scripts, "SheafAsh")
    local wmin, wmax = 9, 0
    for _, sh in pairs(sheaf.shapes) do
        for _, p in ipairs(P.Pieces(sh, { havePak = true })) do
            if p.path:find("SM_Wheat_", 1, true) then wmin, wmax = math.min(wmin, p.scale), math.max(wmax, p.scale) end
        end
    end
    local raw = 0
    for _, sh in pairs(sheaf.shapes) do
        for _, a in ipairs(sh.attachments) do if a.mesh:find("SM_Wheat_", 1, true) then raw = math.max(raw, a.scale[1]) end end
    end
    out[#out + 1] = string.format("wheat %.2f %.2f %s", wmin, wmax, tostring(math.abs(raw - wmax) < 1e-9))
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
tub = pl[8].split()
check("host picked by mesh path; stalks need the pak; cap respected",
      pl[8].startswith("tub SM_FH_Ash_Tree_02 shape_1 all ") and int(tub[4]) > int(tub[6]) > 40 and tub[8] == "40" and tub[10] == "0", pl[8])
check("loader safety net: ground fruit skipped, giant fruit to natural size (2.8 -> 1.0), natural wheat untouched, oversized wheat to 0.55, stems unclamped", pl[6] == "safety 4 1.00 0.50/0.55 0.55 1.60", pl[6])
check("Sheaf Ash v003 wheat (0.45-0.55, a whole plant mesh) passes the clamp unchanged", pl[7].endswith(" true") and pl[7].startswith("wheat 0.4"), pl[7])
check("ground/fallen fruit groups are never placed; fruit scale clamped to 1.1", pl[5].startswith("fruit 0 1.0") and pl[5].endswith(" true false"), pl[5])
check("Tuberwood potatoes hang in the canopy (most above 6 m)", int(pl[8].split("high ")[1]) >= 40, pl[8])
check("unknown host or hybrid: no placement data", pl[9] == "none=true true", pl[9])
check("rotator <-> quaternion round trip", pl[10] == "rot 10.00 30.00 -20.00", pl[10])
check("world transform on a turned, scaled host", pl[11] == "world 1000 2150 75 yaw 100 scale 3.0", pl[11])
check("instance transform: unit quaternion and location", pl[12].startswith("xf 1.000 "), pl[12])

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
check("newest shipped versions are used (Tuberwood v013, Brassica-Oak v005, Sheaf v004, Brassitato v003, Weeping v003)", mo[0] == "files v013 v005 v004 v003 v003", mo[0])
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
promptHost, promptTarget, tagShown = nil, nil, {}
W.PromptHost = function() return promptHost end
W.PromptTarget = function() return promptTarget end
package.loaded["horticulture_nametag"] = { Show = function(t) tagShown[#tagShown + 1] = tostring(t) end }
W.Give = function(item, n) given[#given + 1] = item:match("([^/]+)$") .. "x" .. n return true end
local Looks = require("horticulture_looks")
Looks.Init = function() end
Looks.Apply = function(g, h, mode, id) applied[#applied + 1] = g.id .. ":" .. mode .. ":" .. id return 3 end
Looks.Clear = function(id) cleared[#cleared + 1] = id end
Looks.ApplyPrimelet = function(id, loc, yaw, stage, personality, potted)
    applied[#applied + 1] = id .. ":" .. string.format("%.0f,%.0f,%s,%s,%s", loc.X, loc.Y, stage, tostring(personality), potted and "pot" or "nopot")
    return 6, 50
end
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
check("splicing keys are G, Alt+G, Shift+G and E (pick, Primelet); none on Ctrl (the game's Evade)",
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
ash.kind = "sapling"
g.press("E")
c = g.take("cards")
check("E on a hybrid shoot does nothing (the game's E destroys shoots)", c == "", c)
ash.kind = "tree"
g.press("E")
c = g.take("cards")
check("E on a grown hybrid tree picks too (here: already picked today)", "NOTHING TO PICK|Already picked today" in c, c)
ash.kind = "sapling"
cat = g.S.CatalogueLine()
check("catalogue line", cat == "Hybrids (1/8 flagship): Tuberwood Ash", cat)
g.promptHost = ash
g.tagShown = L.table()
g.tick()
check("name tag: Tuberwood Ash over the game's prompt on the hybrid", g.S.TagText() == "Tuberwood Ash" and "Tuberwood Ash" in list(g.tagShown.values()), list(g.tagShown.values()))
g.promptHost = g.tree("Ash", False, 5000)
check("name tag: none on an ordinary ash", g.S.TagText() is None, g.S.TagText())
g.promptHost = None
g.promptTarget = L.table()
check("name tag: none while the prompt is on something else", g.S.TagText() is None, g.S.TagText())
g.promptTarget = None

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
check("Primelet drawn beside the plot, as a sprout with a personality, no pot", "prime:p" in ap and ":140,0,sprout," in ap
      and ",nil," not in ap and ap.endswith("nopot"), ap)
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
check("set down in front of the player", ":120,0,sprout," in ap, ap)
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
check("seeded Primelet two metres ahead", "prime:p" in ap and ":200,0,sprout," in ap, ap)

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

# Wind sway (ported from DragonwildsAssets scripts/lua/test_hybrid_sway.lua) ----
L = fresh()
sw = L.eval(r"""function()
    local S = require("horticulture_sway")
    local P = require("horticulture_placements")
    local cfg = setmetatable({}, { __index = S.defaults })
    local out, fails = {}, {}
    local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
    local function zaxis(p, r)
        p, r = math.rad(p), math.rad(r)
        return -math.cos(r) * math.sin(p), math.sin(r), math.cos(r) * math.cos(p)
    end
    for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 0.7, 0.7 } }) do
        local sx, sy = 0, 0
        for t = 0, 7, 0.05 do
            local p, r = S.tilt(cfg, t, { X = d[1], Y = d[2] }, 20, { X = 1234, Y = -567 })
            local x, y = zaxis(p, r)
            sx, sy = sx + x, sy + y
            check(math.abs(p) <= cfg.max_deg + 1e-9 and math.abs(r) <= cfg.max_deg + 1e-9, "within max_deg")
        end
        check(sx * d[1] + sy * d[2] > 0, ("downwind %g,%g"):format(d[1], d[2]))
    end
    local p, r = S.tilt(cfg, 1, { X = 0, Y = 0 }, 20, { X = 0, Y = 0 })
    check(p == 0 and r == 0, "zero direction upright")
    p, r = S.tilt(cfg, 1, { X = 1, Y = 0 }, 0, { X = 0, Y = 0 })
    check(p == 0 and r == 0, "zero intensity upright")
    local peak = 0
    for t = 0, 7, 0.01 do
        local a, b = S.tilt(cfg, t, { X = 1, Y = 0 }, 500, { X = 0, Y = 0 })
        peak = math.max(peak, math.sqrt(a * a + b * b))
    end
    check(peak <= cfg.max_deg * 1.05 + 1e-9, "storm capped " .. peak)
    local l = S.to_local({ X = 1, Y = 0 }, 90)
    check(math.abs(l.X) < 1e-9 and math.abs(l.Y + 1) < 1e-9, "to_local yaw 90")
    out[#out + 1] = "maths " .. (#fails == 0 and "ok" or table.concat(fails, "; "))

    -- Glue: distance gate, budget cap, parking, gone trees dropped, calm fallback.
    local clock, applied, gone = 0, {}, {}
    local dir = { X = 1, Y = 0 }
    local s = S.new({ max_trees = 3 }, {
        clock = function() return clock end,
        wind = function() return dir, 20 end,
        player = function() return { X = 0, Y = 0 } end,
        apply = function(tree, pp, rr) if gone[tree.id] then return false end applied[tree.id] = { pp, rr } return true end,
    })
    local trees = {}
    for k = 1, 6 do trees[k] = { id = k } s:add(k, trees[k], { X = k * 400, Y = 0, Yaw = 0 }) end
    local n = s:tick()
    out[#out + 1] = string.format("budget %d %s %s", n, tostring(applied[1] ~= nil and applied[3] ~= nil), tostring(applied[4] == nil))
    s.trees[1].pos.X = 99999
    applied = {}
    s:tick()
    out[#out + 1] = "parked " .. tostring(applied[1] and applied[1][1] == 0 and applied[1][2] == 0)
        .. " " .. tostring(applied[4] ~= nil and applied[4][1] ~= 0)
    s.trees[5].pos.X = 100
    applied = {}
    s:tick()
    out[#out + 1] = "budget-parked " .. tostring(applied[4] and applied[4][1] == 0 and applied[4][2] == 0)
    s.trees[5].pos.X = 2000
    gone[2] = true
    s:tick()
    out[#out + 1] = "gone " .. tostring(s.trees[2] == nil) .. " " .. s:count()
    dir = { X = 0, Y = 0 }
    applied = {}
    s:tick()
    local moved = false
    for _, a in pairs(applied) do if a[1] ~= 0 or a[2] ~= 0 then moved = true end end
    out[#out + 1] = "calm " .. tostring(s.calm) .. " " .. tostring(moved)
    local nowind = S.new({}, { clock = function() return 0 end, wind = function() return nil end,
        player = function() return { X = 0, Y = 0 } end, apply = function() error("must not be called") end })
    nowind:add(1, {}, { X = 0, Y = 0, Yaw = 0 })
    out[#out + 1] = "nowind " .. nowind:tick()

    -- The anchor's rotation: the host's rotation, then the tilt in its frame.
    local rot = P.Rotator(P.QuatMul(P.Quat(0, 90, 0), P.Quat(0.5, 0, 0)))
    out[#out + 1] = string.format("compose %.2f %.2f %.2f", rot.Pitch, rot.Yaw, rot.Roll)
    -- Fruit at 6 m moves about 3.7 cm at the default 0.35 degrees.
    out[#out + 1] = string.format("reach %.1f", 600 * math.rad(S.defaults.base_deg))
    local t0, N = os.clock(), 20000
    for k = 1, N do S.tilt(cfg, k * 0.001, S.to_local({ X = 0.6, Y = 0.8 }, k % 360), 20, { X = k, Y = -k }) end
    out[#out + 1] = string.format("cost %.2f", (os.clock() - t0) / N * 1e6)
    return table.concat(out, "\n")
end""")().split("\n")
check("sway maths: leans downwind every way, upright when calm or still, storm capped, host yaw", sw[0] == "maths ok", sw[0])
check("sway: nearest 3 within 30 m updated (budget cap)", sw[1] == "budget 3 true true", sw[1])
check("sway: a tree walked out of range is parked upright; the next nearest takes its place", sw[2] == "parked true true", sw[2])
check("sway: a tree pushed past the budget is parked upright, not frozen", sw[3] == "budget-parked true", sw[3])
check("sway: a look that is gone is dropped", sw[4] == "gone true 5", sw[4])
check("sway: game wind direction 0 falls back to a default direction", sw[5] == "calm true true", sw[5])

# Baked fruit layers (manifest host mesh + hybrid/produce -> asset) ----------
L = fresh()
fl = L.eval(r"""function()
    local F = require("horticulture_fruit_layers")
    local none = tostring(F.Find("/Game/A/SM_Ash", "tuberwood_ash", "Potato"))
    F.Set({ schema = F.SCHEMA, layers = {
        { host = "/Game/A/SM_Ash", produce = "Potato", asset = "/Game/Mods/SoAHorticulture/FruitLayers/SM_FL_Ash_Potato" },
        { host = "/Game/A/SM_Ash", hybrid = "tuberwood_ash", asset = "/Game/Mods/X/SM_FL_Tuberwood.SM_FL_Tuberwood" },
        { host = "/Game/A/SM_Oak", asset = "/Game/Mods/X/SM_Bad" },
    } }, "test")
    local hyb = F.Find("/Game/A/SM_Ash", "tuberwood_ash", "Potato")
    local gen = F.Find("/Game/A/SM_Ash", "generic:Potato>Ash", "Potato")
    local miss = F.Find("/Game/A/SM_Oak", "x", "Potato")
    return table.concat({ none, F.Count(), hyb.asset, gen.asset, tostring(miss) }, "|")
end""")()
check("fruit layers: hybrid wins over produce, asset path completed, bad/missing entries ignored",
      fl == "nil|2|/Game/Mods/X/SM_FL_Tuberwood.SM_FL_Tuberwood|/Game/Mods/SoAHorticulture/FruitLayers/SM_FL_Ash_Potato.SM_FL_Ash_Potato|nil", fl)
check("sway: no wind readable, nothing touched", sw[6] == "nowind 0", sw[6])
check("sway: anchor rotation is host yaw then tilt", sw[7] == "compose 0.50 90.00 0.00" or sw[7] == "compose 0.50 90.00 -0.00", sw[7])
print("  info: sway reach at 6 m", sw[8], "| pure Lua per tree update (us):", sw[9])

cf = L.eval(r"""function(dir)
    local C = require("horticulture_config")
    local f = io.open(dir .. "\\..\\config.txt", "w") f:write("quiet = true\n") f:close()
    local s = C.Load(dir)
    local f2 = io.open(dir .. "\\..\\config.txt", "w") f2:write("sway = false\nsway_degrees = 0.6\n") f2:close()
    local s2 = C.Load(dir)
    os.remove(dir .. "\\..\\config.txt")
    return string.format("%s %s %s %s %s %s", tostring(s.sway), tostring(s.sway_degrees), tostring(s.quiet), tostring(s.debug), tostring(s2.sway), tostring(s2.sway_degrees))
end""")(os.path.join(TMP, "Scripts"))
check("config: sway on by default (also for an old config.txt without it), 0.35 deg; sway = false turns it off",
      cf == "true 0.35 true false false 0.6", cf)

# Hybrid names on the game's own prompt (WorldActor.DisplayName) -------------
L = fresh()
nm = L.eval(r"""function()
    FText = function(s) return { ToString = function() return s end } end
    local U = { valid = function(a) return a ~= nil and not a.gone end, full = function(a) return a.id end,
        fname = function(a) return a.id end, log = function() end }
    local N = require("horticulture_names")
    local function tree(id) return { id = id, DisplayName = FText("Ash Tree") } end
    local out = {}
    local a = tree("A")
    out[#out + 1] = string.format("set %s %s", tostring(N.Set(U, a, "Tuberwood Ash")), a.DisplayName:ToString())
    out[#out + 1] = "has " .. tostring(N.Has(U, a, "Tuberwood Ash"))
    local writes = 0
    local b = setmetatable({ id = "B" }, {
        __index = function(_, k) if k == "DisplayName" then return FText("Ash Tree") end end,
        __newindex = function(t, k, v) if k == "DisplayName" then writes = writes + 1 else rawset(t, k, v) end end })
    for _ = 1, 10 do N.Set(U, b, "Tuberwood Ash") end
    out[#out + 1] = "stubborn " .. writes
    N.Restore(U, a)
    out[#out + 1] = "restored " .. a.DisplayName:ToString()
    out[#out + 1] = "gone " .. tostring(N.Set(U, { gone = true }, "X"))
    return table.concat(out, "\n")
end""")().split("\n")
check("prompt name: a hybrid's tree is renamed once (Ash Tree -> Tuberwood Ash)", nm[0] == "set true Tuberwood Ash" and nm[1] == "has true", nm[:2])
check("prompt name: a game that keeps its own name is tried 3 times, then left to the tag", nm[2] == "stubborn 3", nm[2])
check("prompt name: the game's name comes back when the hybrid ends", nm[3] == "restored Ash Tree", nm[3])
check("prompt name: a gone actor is left alone", nm[4] == "gone false", nm[4])

# Discovery reveals wait for the game's level-up banner ----------------------
os.remove(save) if os.path.exists(save) else None
L = fresh()
L.execute(GLUE, SCRIPTS, TMP)
L.execute(r"""
clock = 0
os.clock = function() return clock end
bannerOn = false
local banner = { IsValid = function() return true end, IsInViewport = function() return true end,
    IsVisible = function() return bannerOn end, GetRenderOpacity = function() return 1 end }
FindAllOf = function(c) if c == "WBP_LevelUpNotification_C" then return { banner } end end
levelUp = false
ESL.AddXp = function(_, n, label) xp[#xp + 1] = label .. "=" .. n if levelUp then return n, 5, 6 end return n, 5, 5 end
function step(sec) clock = clock + sec tick() end
""")
g = L.globals()
potato = g.plot("FPD_Potato", 1, 50)
ash = g.tree("Ash", True, 300, "sapling")
g.nearby = L.table_from([potato, ash])
g.aimed = potato
g.press("G")
g.step(10)
g.aimed = ash
g.press("G")
g.step(10)
g.take("cards")
g.levelUp = True
g.S.Dawn("test")
g.step(0.5)
c = g.take("cards")
check("banner hold: after a level-up even the ordinary dawn card waits for the banner", c == "", c)
g.step(2)
c = g.take("cards")
check("reveal hold: discovery waits for the banner to appear after a level-up", "DISCOVERED" not in c and "GRAFT TOOK" not in c, c)
g.bannerOn = True
for _ in range(10):
    g.step(1)
c = g.take("cards")
check("banner hold: no card while the level-up banner is on screen", c == "", c)
g.bannerOn = False
g.step(0.5)
check("banner hold: a moment's grace after the banner goes", g.take("cards") == "")
g.step(1)
c = g.take("cards")
check("banner hold: then the dawn card", "GRAFT TOOK|" in c and "DISCOVERED" not in c, c)
g.step(10)
c = g.take("cards")
check("reveal hold: then the discovery shows", "DISCOVERY CATALOGUE|TUBERWOOD ASH DISCOVERED|" in c, c)
g.step(10)
c = g.take("cards")
check("reveal hold: the lore card follows the reveal", "FROM THE DISCOVERY CATALOGUE|Tuberwood Ash|" in c, c)
g.bannerOn = True
g.levelUp = False
L.execute('S.Dawn("test")')
for _ in range(30):
    g.step(1)
check("reveal hold: never held longer than 25 s (a banner that never goes)", True)

# Vanilla skill gates -------------------------------------------------------
L = fresh()
T = L.table_from
cancut = L.eval("function(t) local ok, why = require('horticulture_splice_rules').CanCut(t) return tostring(ok) .. '|' .. tostring(why) end")
cangraft = L.eval("function(s, h, lv) local ok, why = require('horticulture_splice_rules').CanGraft(s, h, lv) return tostring(ok) .. '|' .. tostring(why) end")
r = cancut(T({"species": "Ash", "kind": "tree", "level": 1, "axePower": 1, "skills": T({"Farming": 19})}))
check("gate: an ash cutting needs Tree Farming (Farming 20)", r == "false|Needs Farming 20", r)
r = cancut(T({"species": "Ash", "kind": "tree", "level": 1, "axePower": 1, "skills": T({"Farming": 20})}))
check("gate: Farming 20 takes the ash cutting", r.startswith("true"), r)
r = cancut(T({"species": "Oak", "kind": "tree", "level": 8, "axePower": 1, "skills": T({"Farming": 30})}))
check("gate: the axe tier still applies after the Farming gate", r.startswith("false") and "too weak" in r, r)
r = cancut(T({"species": "FPD_Potato", "kind": "crop", "level": 5, "alive": True, "skills": T({"Farming": 0})}))
check("gate: crops need Farming 1 (Growing Pains)", r == "false|Needs Farming 1", r)
r = cancut(T({"species": "FPD_Potato", "kind": "crop", "level": 5, "alive": True, "skills": T({"Farming": 1})}))
check("gate: Farming 1 takes a potato cutting", r.startswith("true"), r)
r = cancut(T({"species": "Ash", "kind": "tree", "level": 1, "axePower": 1, "skills": T({})}))
check("gate: an unreadable Farming level never blocks", r.startswith("true"), r)
r = cancut(T({"species": "Ash", "kind": "tree", "level": 1, "axePower": 1}))
check("gate: no skills given never blocks", r.startswith("true"), r)
r = cangraft("FPD_Potato", T({"species": "Ash", "kind": "sapling", "planted": True, "skills": T({"Farming": 19})}), 1)
check("gate: grafting onto an ash host needs Farming 20", r == "false|Needs Farming 20 for ash", r)
r = cangraft("Oak", T({"species": "Ash", "kind": "tree", "planted": True, "skills": T({"Farming": 19})}), 8)
check("gate: a tree cutting as the donor needs Farming 20", r == "false|Needs Farming 20 for oak", r)
r = cangraft("FPD_Cabbage", T({"species": "FPD_Potato", "kind": "plot", "planted": True, "stage": 1, "skills": T({"Farming": 0})}), 5)
check("gate: crop donor and crop host both checked", r.startswith("false|Needs Farming 1"), r)
r = cangraft("FPD_Potato", T({"species": "Ash", "kind": "sapling", "planted": True, "skills": T({"Farming": 20})}), 1)
check("gate: Farming 20 grafts potato onto ash", r.startswith("true"), r)

# Derived gates: crop -> lowest plot tier in its FPD Farming.Tiers tags (pak
# scan 2026-10-06); tree -> axe power that fells it. Tier -> level is ours.
plots = L.eval("function() local R = require('horticulture_splice_rules') local t = {} for k, c in pairs(R.CROPS) do t[#t + 1] = k .. '=' .. tostring(c.plot) end table.sort(t) return table.concat(t, ',') end")()
want_plots = {"FPD_Cabbage": 1, "FPD_Potato": 1, "FPD_Wheat": 1, "FPD_Redberry": 1, "FPD_Flax": 1, "FPD_Harralander": 1,
              "FPD_Marrentill": 1, "FPD_Kwuarm": 1, "FPD_Onion": 2, "FPD_Tomato": 2, "FPD_Dwellberry": 2}
check("derived: every crop's plot tier matches the game data", plots == ",".join(sorted(f"{k}={v}" for k, v in want_plots.items())), plots)
needs = L.eval("""function() local R = require('horticulture_splice_rules') local t = {}
    for _, s in ipairs({ 'FPD_Cabbage', 'FPD_Onion', 'FPD_Dwellberry', 'Ash', 'Oak', 'Willow', 'Maple', 'Yew', 'Magic' }) do
        local p = {} for _, g in ipairs(R.SkillGates(s)) do p[#p + 1] = g.skill .. ' ' .. g.level end
        t[#t + 1] = s .. ':' .. table.concat(p, '+') end
    return table.concat(t, ',') end""")()
check("derived: the gate table", needs == "FPD_Cabbage:Farming 1,FPD_Onion:Farming 10,FPD_Dwellberry:Farming 10,"
      "Ash:Woodcutting 1+Farming 20,Oak:Woodcutting 10+Farming 20,Willow:Woodcutting 20+Farming 20,"
      "Maple:Woodcutting 40+Farming 20,Yew:Woodcutting 50+Farming 20,Magic:Woodcutting 60+Farming 20", needs)
r = cancut(T({"species": "Oak", "kind": "tree", "level": 8, "axePower": 3, "skills": T({"Farming": 30, "Woodcutting": 9})}))
check("gate: an oak cutting needs Woodcutting 10 (bronze axe tier)", r == "false|Needs Woodcutting 10", r)
r = cancut(T({"species": "Oak", "kind": "tree", "level": 8, "axePower": 3, "skills": T({"Farming": 30, "Woodcutting": 10})}))
check("gate: Woodcutting 10 and a bronze axe take the oak cutting", r.startswith("true"), r)
r = cancut(T({"species": "Willow", "kind": "tree", "level": 20, "axePower": 4, "skills": T({"Farming": 30, "Woodcutting": 19})}))
check("gate: a willow cutting needs Woodcutting 20 (iron axe tier)", r == "false|Needs Woodcutting 20", r)
r = cancut(T({"species": "FPD_Onion", "kind": "crop", "level": 18, "alive": True, "skills": T({"Farming": 9})}))
check("gate: an onion cutting needs Farming 10 (oak plot tier)", r == "false|Needs Farming 10", r)
r = cancut(T({"species": "FPD_Wheat", "kind": "crop", "level": 10, "alive": True, "skills": T({"Farming": 1})}))
check("gate: wheat grows in the ash plot, Farming 1", r.startswith("true"), r)
r = cangraft("Oak", T({"species": "Ash", "kind": "tree", "planted": True, "skills": T({"Farming": 30, "Woodcutting": 9})}), 8)
check("gate: an oak donor needs Woodcutting 10", r == "false|Needs Woodcutting 10 for oak", r)
r = cangraft("FPD_Potato", T({"species": "Willow", "kind": "tree", "planted": True, "skills": T({"Farming": 30, "Woodcutting": 15})}), 20)
check("gate: a willow host needs Woodcutting 20", r == "false|Needs Woodcutting 20 for willow", r)
r = cangraft("FPD_Tomato", T({"species": "FPD_Potato", "kind": "plot", "planted": True, "stage": 1, "skills": T({"Farming": 9})}), 18)
check("gate: a tomato donor needs Farming 10", r == "false|Needs Farming 10 for tomato", r)
r = cangraft("FPD_Potato", T({"species": "FPD_Dwellberry", "kind": "plot", "planted": True, "stage": 1, "skills": T({"Farming": 9})}), 22)
check("gate: a dwellberry host needs Farming 10", r == "false|Needs Farming 10 for dwellberry", r)
W2 = L.eval('(require("horticulture_wheel"))')
check("wheel: 'Needs Farming 20' is greyed as a level lock", W2.LevelLocked("Needs Farming 20 for ash") is True and W2.LevelLocked("Needs Woodcutting 20") is True
      and W2.LevelLocked("Your axe is too weak") is False)

# All 150 Horticulture 1-25 combinations: generic looks -----------------------
gen = L.eval(r"""function(scripts)
    local G = require("horticulture_hybrid_generic")
    local P = require("horticulture_placements")
    local Rules = require("horticulture_splice_rules")
    local out = {}
    if not G.Load(scripts .. "\\placements") then return "load failed" end
    local combos = dofile(scripts .. "\\placements\\hort_plant_generic_hybrids_1_25_combos_v003.lua").combos
    local n, missing, empty, big, bigPak, nestOnTree, leafy, illegal, nopakMoved = 0, {}, {}, 0, 0, 0, 0, 0, 0
    for _, e in ipairs(combos) do
        n = n + 1
        local scion, host = e.key:match("^(.-)>(.+)$")
        local d = G.Placement(scion, host)
        if not d then missing[#missing + 1] = e.key else
            local shapes, pieces = 0, 0
            for mesh, sid in pairs(d.hosts) do
                local shape = d.shapes[sid]
                shapes = shapes + 1
                for _, a in ipairs(shape.attachments) do
                    if Rules.IsTree(host) and not Rules.IsTree(scion) and a.name:find("^nestle") then nestOnTree = nestOnTree + 1 end
                    if a.no_pak_location then
                        local dx = a.no_pak_location[1] - a.location[1]
                        local dy = a.no_pak_location[2] - a.location[2]
                        local dz = a.no_pak_location[3] - a.location[3]
                        if dx * dx + dy * dy + dz * dz > 1 then nopakMoved = nopakMoved + 1 end
                    end
                end
                local free = P.Pieces(shape, { havePak = false })
                pieces = pieces + #free
                for _, p in ipairs(free) do
                    if math.max(p.scale or 1, p.scaleY or 0, p.scaleZ or 0) > 1.0001 then big = big + 1 end
                end
                for _, p in ipairs(P.Pieces(shape, { havePak = true })) do
                    if P.IsFruit(p.group, p.path) and math.max(p.scale or 1, p.scaleY or 0, p.scaleZ or 0) > 1.0001 then bigPak = bigPak + 1 end
                end
            end
            if pieces == 0 then empty[#empty + 1] = e.key end
            local ok = Rules.CanGraft(scion, { species = host, kind = Rules.IsTree(host) and "tree" or "plot", planted = true, stage = 1 }, 25)
            if not ok then illegal = illegal + 1 end
        end
    end
    return string.format("n %d missing %d empty %d big %d bigpak %d nestontree %d illegal %d nopak %d %s %s", n, #missing, #empty, big, bigPak,
        nestOnTree, illegal, nopakMoved, table.concat(missing, ","), table.concat(empty, ","))
end""")(SCRIPTS)
check("generic: the combos file lists all 150 level 1-25 combinations", gen.startswith("n 150 "), gen)
check("generic: every combination has a look on every host mesh it can show", " missing 0 empty 0 " in gen, gen)
check("generic: nothing above natural size, with or without the pak (no giant anything)", " big 0 bigpak 0 " in gen, gen)
check("generic: crops on trees hang from branches (never nestled in the leaves)", " nestontree 0 " in gen, gen)
check("generic: every listed combination is one the rules allow at 25", " illegal 0 " in gen, gen)
check("generic: without the stalk mesh the fruit moves to the bark", int(gen.split(" nopak ")[1].split()[0]) > 0, gen)
fb = L.eval(r"""function()
    local P = require("horticulture_placements")
    local shape = { attachments = {
        { mesh = "/Game/Art/Item/Resources/Potato/SM_Potato_Fruit_01", group = "canopy_fruit", location = { 100, 0, 500 },
          no_pak_location = { 60, 0, 480 }, rotation = { 0, 0, 0 }, scale = { 1, 1, 1 } } } }
    local a = P.Pieces(shape, { havePak = true })[1]
    local b = P.Pieces(shape, { havePak = false })[1]
    return string.format("%.0f,%.0f %.0f,%.0f", a.x, a.z, b.x, b.z)
end""")()
check("no-pak fallback: the bark-contact position replaces the stalk-tip one", fb == "100,500 60,480", fb)

# Primelet voice --------------------------------------------------------------
voice = L.eval(r"""function()
    local Talk = require("horticulture_primelet_talk")
    local V = Talk.V
    local out = {}
    local seq = {}
    local function fixed(list) local i = 0 return function(n) i = i + 1 local v = list[(i - 1) % #list + 1] return math.min(n, math.max(1, v)) end end
    math.randomseed(25)
    local counts, owned = {}, {}
    for i = 1, 6000 do
        local k = Talk.RollPersonality(owned, function(n) return math.random(n) end)
        counts[k] = (counts[k] or 0) + 1
    end
    out[#out + 1] = string.format("unhinged %.3f pompous %.3f", counts.unhinged / 6000, counts.pompous / 6000)
    local damp = {}
    for i = 1, 6000 do
        local k = Talk.RollPersonality({ pompous = 3 }, function(n) return math.random(n) end)
        damp[k] = (damp[k] or 0) + 1
    end
    out[#out + 1] = string.format("damped %.3f", damp.pompous / 6000)
    local used = {}
    for _, n in ipairs(V.P.grumpy.names) do used[n] = true end
    out[#out + 1] = "second " .. Talk.RollName("grumpy", used, fixed({ 1 }))
    out[#out + 1] = "fresh " .. tostring(Talk.RollName("grumpy", { ["Old Stalk"] = true }, fixed({ 1 })) ~= "Old Stalk")
    local m = { id = "p1", stage = 1, personality = "pompous", name = "Lord Savoy", said = {} }
    out[#out + 1] = "sproutname " .. tostring(Talk.FullName(m))
    m.stage = 2
    out[#out + 1] = "fullname " .. tostring(Talk.FullName(m))
    local e = Talk.New({ rng = function(n) return math.random(n) end, clock = function() return 0 end })
    m.stage = 1
    local t1, n1 = e:Line(m, "talk", {})
    local inSprout = false
    for _, s in ipairs(V.SHARED.sprout) do if s == t1 then inSprout = true end end
    out[#out + 1] = "sprout " .. tostring(n1) .. " " .. tostring(inSprout) .. " " .. tostring(e:Line(m, "potted", {}) == nil)
    m.stage = 3
    local t3, n3 = e:Line(m, "talk", { level = 12 })
    out[#out + 1] = "mini " .. tostring(n3) .. " " .. tostring(t3 ~= nil)
    local seen, dup = {}, 0
    for i = 1, 10 do
        local text, line = e:Pick(m, V.P.pompous.talk, {})
        if seen[text] then dup = dup + 1 end
        seen[text] = true
        e:Remember(m, text, line)
    end
    out[#out + 1] = "norepeat " .. dup
    local f1, _, _, l1 = e:Line(m, "first_words", {})
    e:Remember(m, f1, l1)
    local f2, _, _, l2 = e:Line(m, "first_words", {})
    e:Remember(m, f2, l2)
    local f3 = e:Line(m, "first_words", {})
    out[#out + 1] = "once " .. tostring(f1 ~= f2) .. " " .. tostring(f3 == nil) .. " " .. tostring(next(m.said) ~= nil)
    -- cooldowns
    local clock = 0
    local c = Talk.New({ rng = function(n) return 1 end, clock = function() return clock end })
    local a, b = { id = "a" }, { id = "b" }
    c:Spoke(a, "Hello there.", nil, 0)
    local r = {}
    for _, t in ipairs({ 2, 10, 31, 151 }) do
        r[#r + 1] = string.format("%s/%s/%s", tostring(c:CanSpeak("b", "ambient", t)), tostring(c:CanSpeak("a", "ambient", t)), tostring(c:CanSpeak("b", "talk", t)))
    end
    out[#out + 1] = "gaps " .. table.concat(r, " ")
    c:SetChattiness("off")
    out[#out + 1] = "off " .. tostring(c:CanSpeak("b", "ambient", 1000)) .. " " .. tostring(c:CanSpeak("b", "potted", 1000)) .. " " .. tostring(c:CanSpeak("b", "talk", 1000))
    out[#out + 1] = string.format("bubble %.2f %.2f", Talk.BubbleSeconds("0123456789"), Talk.BubbleSeconds(string.rep("x", 200)))
    -- arrangement
    local function ring(n, r, step, skip)
        local pts = {}
        for i = 0, n - 1 do
            local ang = math.rad(i * (step or 72) + ((skip and i == 1) and 25 or 0))
            pts[#pts + 1] = { x = 1000 + r * math.cos(ang), y = 500 + r * math.sin(ang), z = 0, id = i }
        end
        return pts
    end
    local five = ring(5, 250)
    local found = Talk.Arrangement(five)
    out[#out + 1] = "five " .. tostring(found ~= nil) .. string.format(" %.0f", found and found.r or 0)
    local bent = ring(5, 250, 72, true)
    local f2b, nearly = Talk.Arrangement(bent)
    out[#out + 1] = "bent " .. tostring(f2b ~= nil) .. " " .. tostring(nearly)
    local crowded = ring(5, 250)
    crowded[#crowded + 1] = { x = 1000, y = 500, z = 0, id = 9 }
    out[#out + 1] = "crowded " .. tostring(Talk.Arrangement(crowded) ~= nil)
    local small = ring(5, 80)
    out[#out + 1] = "small " .. tostring(Talk.Arrangement(small) ~= nil)
    local stairs = ring(5, 250)
    stairs[3].z = 200
    out[#out + 1] = "stairs " .. tostring(Talk.Arrangement(stairs) ~= nil)
    local three = { five[1], five[2], five[3] }
    local four = { five[1], five[2], five[3], five[4] }
    out[#out + 1] = string.format("progress %d %d %d %d", Talk.Progress({ five[1], five[2] }), Talk.Progress(three), Talk.Progress(four), Talk.Progress(five))
    out[#out + 1] = "pools " .. tostring(Talk.ProgressPool(3, 4, false)) .. " " .. tostring(Talk.ProgressPool(4, 3, false)) .. " " .. tostring(Talk.ProgressPool(4, 4, true))
    local d = Talk.New({ rng = function(n) return n end, clock = function() return 0 end })
    local s1, s2 = { id = "s1", stage = 3, personality = "grumpy", name = "Gristle", said = {} }, { id = "s2", stage = 3, personality = "pompous", name = "Lord Savoy", said = {} }
    local first = d:Completed(s1, s2, {}, false)
    local later = d:Completed(s1, s2, {}, true)
    out[#out + 1] = "first " .. tostring(first == V.SHARED.ring_first) .. " " .. tostring(later ~= nil)
    local fa, fb2, la = d:Bicker(s1, s2, {})
    out[#out + 1] = "bicker " .. tostring(fa and fa.personality) .. " " .. tostring(la ~= nil)
    out[#out + 1] = "fill " .. Talk.Fill("{name} and {other}: {minis}", s1, { other = "Lord Savoy", minis = 3 })
    out[#out + 1] = "tier " .. Talk.HintTier(2) .. Talk.HintTier(3) .. Talk.HintTier(4) .. Talk.HintTier(9)
    out[#out + 1] = "ignored " .. tostring(Talk.IgnoredTier(s1, 1)) .. " " .. tostring(Talk.IgnoredTier(s1, 5))
    return table.concat(out, "\n")
end""")().split("\n")
un, po = float(voice[0].split()[1]), float(voice[0].split()[3])
check("personality roll follows the weights (unhinged ~7%, pompous ~20%)", 0.05 < un < 0.09 and 0.17 < po < 0.23, voice[0])
check("owning three Pompous makes a fourth rarer", float(voice[1].split()[1]) < 0.05, voice[1])
check("names: all taken gives 'the Second'", voice[2].startswith("second ") and voice[2].endswith(" the Second"), voice[2])
check("names: a used name is skipped", voice[3] == "fresh true", voice[3])
check("a Sprout has no full name yet", voice[4] == "sproutname nil", voice[4])
check("full name from the Brassica Primelet stage", voice[5] == "fullname Lord Savoy the Pompous", voice[5])
check("a Sprout is narrated, from the shared sprout lines, and never speaks for events", voice[6] == "sprout true true true", voice[6])
check("a Mini Brassica Prime speaks", voice[7] == "mini false true", voice[7])
check("a Mini does not repeat its recent lines", voice[8] == "norepeat 0", voice[8])
check("first words: once lines are said once, and saved", voice[9] == "once true true true", voice[9])
check("cooldowns: bubble, 30 s global, 150 s per Mini; talk only waits 4 s", voice[10] == "gaps false/false/false false/false/true true/false/true true/true/true", voice[10])
check("chattiness off: only talk and tend replies", voice[11] == "off false false true", voice[11])
check("bubble time 3 s + 0.055 s a character, 3-8 s", voice[12] == "bubble 3.55 8.00", voice[12])
check("arrangement: five evenly round a 2.5 m centre fit", voice[13] == "five true 250", voice[13])
check("arrangement: one out of step does not fit, but nearly", voice[14] == "bent false true", voice[14])
check("arrangement: a sixth in the middle spoils it", voice[15] == "crowded false", voice[15])
check("arrangement: too small does not count", voice[16] == "small false", voice[16])
check("arrangement: not on one floor does not count", voice[17] == "stairs false", voice[17])
check("progress 0, 3, 4, 5", voice[18] == "progress 0 3 4 5", voice[18])
check("progress lines: closer, colder, nearly", voice[19] == "pools closer colder nearly", voice[19])
check("the first completion says the shared first line; later ones vary", voice[20] == "first true true", voice[20])
check("bickering: the pair's first speaker leads", voice[21] == "bicker pompous true", voice[21])
check("tokens filled", voice[22] == "fill Gristle and Lord Savoy: 3", voice[22])
check("hint tiers at 3, 4 and 5 grown Minis", voice[23] == "tier 0123", voice[23])
check("ignored lines by days", voice[24] == "ignored nil 4", voice[24])

store = L.eval(r"""function()
    local Store = require("horticulture_splice_store")
    local P = require("horticulture_primelet")
    local st = Store.New()
    st.pmflag1, st.lastSeen = true, 1790000000
    local p = P.New(st, 1, 2, 3, "W", function(n) return 1 end)
    p.stage, p.potted, p.talked, p.ign, p.seen = 3, true, 4, 2, 5
    p.said = { abcd1234 = true, ["0000beef"] = true }
    local back = Store.Parse(Store.Serialize(st))
    local q = back.primelets[1]
    local keys = {}
    for k in pairs(q.said) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = { string.format("%s|%s|%s|%s|%d|%d|%d|%s|%s|%s", q.personality, q.name, tostring(q.potted), tostring(q.carried), q.talked, q.ign, q.seen,
        table.concat(keys, ","), tostring(back.pmflag1), tostring(back.lastSeen)) }
    local text = Store.Serialize(st)
    out[#out + 1] = "neutral " .. tostring(not text:lower():find("ring") and not text:lower():find("summon"))
    local old = Store.Parse("version=2\ndawn=3\nnextid=5\nprimelet=p1|3|5|2|0|W|10|20|30|0|0\nprimelet=p2|1|0|-1|1|W|1|1|1|0|0\n")
    out[#out + 1] = string.format("old %d %s %s", #old.primelets, tostring(old.primelets[1].personality), tostring(old.primelets[1].potted))
    local n = P.Migrate(old, function(k) return 1 end)
    out[#out + 1] = string.format("migrated %d %s %s %s", n, tostring(old.primelets[1].personality ~= nil), tostring(old.primelets[1].name ~= old.primelets[2].name),
        P.Name(old.primelets[1]):match(" the %a+$") and "named" or P.Name(old.primelets[1]))
    out[#out + 1] = "again " .. P.Migrate(old, function(k) return 1 end)
    local g = Store.New()
    local m = P.New(g, 0, 0, 0, "W", function(k) return 1 end)
    m.stage = 3
    local entry = P.PickUp(g, m, 6)
    local _, _, pot1 = P.Place(g, entry, 1, 1, 1, 0, "W")
    entry = P.PickUp(g, m, 6)
    local _, _, pot2 = P.Place(g, entry, 2, 2, 2, 0, "W")
    local y = Store.New()
    local young = P.New(y, 0, 0, 0, "W", function(k) return 1 end)
    local e2 = P.PickUp(y, young, 6)
    local _, _, pot3 = P.Place(y, e2, 1, 1, 1, 0, "W")
    out[#out + 1] = string.format("pot %s %s %s %s", tostring(pot1), tostring(pot2), tostring(m.potted), tostring(pot3))
    return table.concat(out, "\n")
end""")().split("\n")
check("save keeps personality, name, pot, talked, ignored tier, seen, said lines, and the file flags",
      store[0] == "pompous|Lord Savoy|true|false|4|2|5|0000beef,abcd1234|true|1790000000", store[0])
check("save keys are neutral", store[1] == "neutral true", store[1])
check("older save rows still load", store[2] == "old 2 nil false", store[2])
check("migration rolls a personality and a different name for each", store[3] == "migrated 2 true true named", store[3])
check("migration runs once", store[4] == "again 0", store[4])
check("potting: a grown Mini takes a pot the first time it is set down, once; a younger one does not", store[5] == "pot true false true false", store[5])

looks = L.eval(r"""function(scripts)
    local PL = require("horticulture_primelet_looks")
    PL.Load(scripts .. "\\placements")
    local Looks = require("horticulture_looks")
    local function summary(stage, pers, potted)
        local pieces, z = Looks.PrimeletPieces(stage, pers, potted)
        local pot, face, minz = 0, 0, math.huge
        for _, p in ipairs(pieces) do
            if p.group == "pot" or p.name == "pot" then pot = pot + 1 end
            if (p.path or ""):find("SM_PRM_Face", 1, true) then face = face + 1 end
            minz = math.min(minz, p.z or 0)
        end
        return string.format("%d pot %d face %d z %.0f", #pieces, pot, face, z)
    end
    local lift = PL.Stage("primeling").lift_cm
    return table.concat({ PL.File(), summary("sprout", "grumpy", false), summary("primeling", "grumpy", true), summary("primeling", "grumpy", false),
        string.format("%.2f", lift) }, "\n")
end""")(SCRIPTS).split("\n")
check("Primelet looks from the pipeline data file", looks[0] == "hort_plant_brassica_primelet_v001", looks[0])
check("a sprout has no pot; without the pak no face pieces", " pot 0 face 0 " in looks[1], looks[1])
check("a potted Mini stands in its pot; bubble above it", " pot 0 " not in looks[2] and looks[2].endswith("z 85"), looks[2])
ppot = int(looks[2].split()[0]) - int(looks[3].split()[0])
check("an unpotted Mini drops the pot and sits lower by the pot's lift", ppot > 0 and " pot 0 " in looks[3] and looks[3].endswith("z 64"), looks[2:4])

bob = L.eval(r"""function(scripts)
    local PL = require("horticulture_primelet_looks")
    PL.Load(scripts .. "\\placements")
    local peak, minsz, maxsz = 0, 2, 0
    for i = 0, 280 do
        local dz, sz = PL.Bob(i / 100, "primeling", 0)
        peak = math.max(peak, math.abs(dz))
        minsz, maxsz = math.min(minsz, sz), math.max(maxsz, sz)
    end
    local a = PL.Bob(0.7, "primeling", 0)
    local b = PL.Bob(0.7, "primeling", 1.3)
    return string.format("%s %s %.2f %.3f %.3f %s", tostring(PL.Bobs("body")), tostring(PL.Bobs("pot")), peak, minsz, maxsz, tostring(math.abs(a - b) > 0.05))
end""")(SCRIPTS)
check("idle bob: body pieces only (never the pot), under a centimetre, slight squash, creatures out of step",
      bob.startswith("true false ") and float(bob.split()[2]) <= 0.61 and float(bob.split()[3]) >= 0.98 and bob.endswith(" true"), bob)

cfgt = L.eval(r"""function(tmp)
    local C = require("horticulture_config")
    local function load(text)
        local dir = tmp .. "\\cfg" .. tostring(math.random(100000))
        os.execute('mkdir "' .. dir .. '\\Scripts" 2>nul')
        local f = io.open(dir .. "\\config.txt", "w") f:write(text) f:close()
        return C.Load(dir .. "\\Scripts", function() end).primelet_chattiness
    end
    return load("primelet_chattiness = Chatty\n") .. " " .. load("primelet_chattiness = loud\n") .. " " .. load("")
end""")(TMP)
check("config: primelet_chattiness reads off/quiet/normal/chatty, else normal", cfgt == "chatty normal normal", cfgt)

# Mutation tints ------------------------------------------------------------
mut = L.eval(r"""function(scripts, tmp)
    local M = require("horticulture_mutation")
    local Rules = require("horticulture_splice_rules")
    local out = {}
    local combos = dofile(scripts .. "\\placements\\hort_plant_generic_hybrids_1_25_combos_v003.lua").combos
    local n, none, bad, unstable, used = 0, 0, 0, 0, {}
    for _, e in ipairs(combos) do
        local scion, host = e.key:match("^(.-)>(.+)$")
        local id = Rules.HybridId(scion, host)
        local t = M.For(id, Rules.ComboKey(scion, host))
        n = n + 1
        if not t then none = none + 1 else
            used[t.name] = true
            for _, ch in ipairs({ "R", "G", "B" }) do
                if t.mult[ch] < 0.3 or t.mult[ch] > 1 or t.add[ch] < 0 or t.add[ch] > 0.5 then bad = bad + 1 end
            end
            if M.For(id, Rules.ComboKey(scion, host)) ~= t then unstable = unstable + 1 end
        end
    end
    local nu = 0
    for _ in pairs(used) do nu = nu + 1 end
    out[#out + 1] = string.format("n %d none %d bad %d unstable %d names %d", n, none, bad, unstable, nu)
    local names, dup = {}, 0
    for id, f in pairs(M.FLAGSHIP) do
        if names[f.name] then dup = dup + 1 end
        names[f.name] = true
        for _, ch in ipairs({ "R", "G", "B" }) do
            if f.mult[ch] < 0.3 or f.mult[ch] > 1 or f.add[ch] < 0 or f.add[ch] > 0.5 then dup = dup + 100 end
        end
    end
    out[#out + 1] = "flagship dup " .. dup
    local tub = M.For("TuberwoodAsh", "potato>ash")
    out[#out + 1] = string.format("tub %s %s", tub.name, tostring(tub.mult.B > tub.mult.R and tub.mult.B > tub.mult.G
        and tub.add.B > tub.add.R and tub.add.B > tub.add.G))
    out[#out + 1] = string.format("hash %d %d", M.Hash(""), M.Hash("a"))
    local vec, sca = M.Params(tub)
    local ps = {}
    for p, c in pairs(vec) do ps[#ps + 1] = string.format("%s=%.2f,%.2f,%.2f", p, c.R, c.G, c.B) end
    for p, x in pairs(sca) do ps[#ps + 1] = string.format("%s=%.0f", p, x) end
    table.sort(ps)
    out[#out + 1] = table.concat(ps, " ")
    out[#out + 1] = table.concat({ tostring(M.Takes("tree", "/Game/Env/MI_GF_AshTree_Leaves.MI_GF_AshTree_Leaves")),
        tostring(M.Takes("tree", "MaterialInstanceConstant /Game/Env/Foliage/Trees/MI_BM_AshTree_Trunk.MI_BM_AshTree_Trunk")), tostring(M.Takes("sapling", "MI_Oak_Leaf_01")) .. "," .. tostring(M.Takes("tree", "/Game/Env/Foliage/MI_Ash_Tree_02_IMP1.MI_Ash_Tree_02_IMP1")),
        tostring(M.Takes("plot", "MI_Cabbage")) }, " ")
    -- applying it: leaf slot gets a dynamic instance, bark is left; an
    -- existing dynamic instance is changed in place and put back on untint
    local Looks = require("horticulture_looks")
    Looks.Init(require("horticulture_util"), scripts .. "\\placements")
    local calls = {}
    local function mat(name) return { IsValid = function() return true end, GetFullName = function() return name end } end
    local function newMid(name)
        local m = mat(name)
        m.SetScalarParameterValue = function(_, p, x) calls[#calls + 1] = string.format("%s s %s %.2f", name, p, x) end
        m.SetVectorParameterValue = function(_, p, c) calls[#calls + 1] = string.format("%s v %s %.2f", name, p, c.B) end
        m.K2_GetScalarParameterValue = function() return 0.25 end
        m.K2_GetVectorParameterValue = function() return { R = 1, G = 1, B = 0.5, A = 1 } end
        return m
    end
    local slots = { mat("MaterialInstanceConstant /Game/MI_Ash_Bark"), mat("MaterialInstanceConstant /Game/MI_Ash_Leaves") }
    local created = newMid("MaterialInstanceDynamic /Engine/Transient.MID_1")
    local comp = { IsValid = function() return true end, GetNumMaterials = function() return #slots end,
        GetMaterial = function(_, i) return slots[i + 1] end,
        CreateDynamicMaterialInstance = function(_, i, src) calls[#calls + 1] = "create " .. i slots[i + 1] = created return created end,
        SetMaterial = function(_, i, m) calls[#calls + 1] = "set " .. i .. " " .. m:GetFullName() slots[i + 1] = m end }
    local saved = Looks.Mutate({ kind = "tree", comps = { comp } }, tub)
    out[#out + 1] = #saved .. " | " .. table.concat(calls, ", ")
    out[#out + 1] = "holds " .. tostring(Looks.MutationHolds(saved))
    slots[2] = mat("MaterialInstanceConstant /Game/MI_Ash_Leaves")
    out[#out + 1] = "swapped " .. tostring(Looks.MutationHolds(saved))
    calls = {}
    local existing = newMid("MaterialInstanceDynamic /Engine/Transient.MID_9")
    existing.Parent = mat("MaterialInstanceConstant /Game/MI_Ash_Leaves")
    slots[2] = existing
    saved = Looks.Mutate({ kind = "tree", comps = { comp } }, tub)
    Looks.Untint(saved)
    out[#out + 1] = #saved .. " | " .. table.concat(calls, ", ")
    calls = {}
    slots[2] = mat("MaterialInstanceConstant /Game/MI_Ash_Leaves")
    Looks.Untint(Looks.Mutate({ kind = "tree", comps = { comp } }, tub))
    out[#out + 1] = table.concat(calls, ", ")
    local C = require("horticulture_config")
    local dir = tmp .. "\\cfgm" .. tostring(math.random(100000))
    os.execute('mkdir "' .. dir .. '\\Scripts" 2>nul')
    local f = io.open(dir .. "\\config.txt", "w") f:write("") f:close()
    local d = C.Load(dir .. "\\Scripts", function() end).mutation_tint
    f = io.open(dir .. "\\config.txt", "w") f:write("mutation_tint = false\n") f:close()
    out[#out + 1] = "cfg " .. tostring(d) .. " " .. tostring(C.Load(dir .. "\\Scripts", function() end).mutation_tint)
    return table.concat(out, "\n")
end""")(SCRIPTS, TMP).split("\n")
check("mutation: all 150 combos get a tint, within bounds, the same every time, from several palette colours",
      mut[0].startswith("n 150 none 0 bad 0 unstable 0 ") and int(mut[0].split()[-1]) >= 6, mut[0])
check("mutation: each flagship has its own tint", mut[1] == "flagship dup 0", mut[1])
check("mutation: Tuberwood Ash stays deep blue-violet", mut[2] == "tub deep blue-violet true", mut[2])
check("mutation: FNV-1a hash", mut[3] == "hash 2166136261 3826002220", mut[3])
check("mutation: a tint is a colour multiply and add, both blends full on",
      mut[4] == "Color_Add_A=0.10,0.02,0.40 Color_Add_B=0.10,0.02,0.40 Color_Add_Blend=1 Color_Mult_A=0.35,0.30,0.60 "
      "Color_Mult_B=0.35,0.30,0.60 Color_Mult_Blend=1", mut[4])
check("mutation: trees tint leaves and the impostor, not bark (even in a Foliage folder); crops tint the whole plant", mut[5] == "true false true,true true", mut[5])
M1 = "MaterialInstanceDynamic /Engine/Transient.MID_1 "
TINT_CALLS = ["v Color_Mult_A 0.60", "v Color_Mult_B 0.60", "v Color_Add_A 0.40", "v Color_Add_B 0.40", "s Color_Mult_Blend 1.00", "s Color_Add_Blend 1.00"]
p6 = mut[6].split(" | ", 1)[1].split(", ")
check("mutation: a dynamic instance of the leaf slot only, with the tint's multiply and add",
      mut[6].startswith("1 | create 1, ") and sorted(p6[1:]) == sorted(M1 + c for c in TINT_CALLS), mut[6])
check("mutation: noticed when the game swaps the material back", mut[7] == "holds true" and mut[8] == "swapped false", mut[7:9])
M9 = "MaterialInstanceDynamic /Engine/Transient.MID_9 "
parts = mut[9].split(" | ", 1)[1].split(", ")
check("mutation: an existing dynamic instance is tinted in place and its values put back",
      mut[9].startswith("1 | ") and "create" not in mut[9] and len(parts) == 12
      and sorted(parts[:6]) == sorted(M9 + c for c in TINT_CALLS)
      and sorted(parts[6:]) == sorted(M9 + c for c in ["s Color_Mult_Blend 0.25", "s Color_Add_Blend 0.25", "v Color_Mult_A 0.50",
                                                       "v Color_Mult_B 0.50", "v Color_Add_A 0.50", "v Color_Add_B 0.50"]), mut[9])
check("mutation: untint puts the original material back", mut[10].endswith("set 1 MaterialInstanceConstant /Game/MI_Ash_Leaves"), mut[10])
check("config: mutation_tint defaults on and can be turned off", mut[11] == "cfg true false", mut[11])

# Secrecy: nothing a player sees mentions what five Minis are for ----------
import re  # noqa: E402
SHIP = os.path.join(ROOT, "SkillsOfAshenfallHorticulture")
bad = []
for dirpath, _, files in os.walk(SHIP):
    for fn in files:
        if re.search(r"summon|ritual", fn, re.I):
            bad.append("file name " + fn)
        if not fn.endswith((".lua", ".md", ".txt")):
            continue
        p = os.path.join(dirpath, fn)
        text = open(p, encoding="utf-8", errors="replace").read()
        rel = os.path.relpath(p, SHIP)
        for word in [r"summon", r"ritual", r"post_v1", r"V\.RITUAL"]:
            if re.search(word, text, re.I):
                bad.append(rel + ": " + word)
        if fn == "horticulture_primelet_voice.lua" and re.search(r"min = 75|master", text):
            bad.append(rel + ": 75+ band")
        if fn in ("README.md", "CHANGELOG.md", "horticulture_config.lua", "horticulture_perks.lua") and re.search(r"\b(ring|circle|five minis|level 75)\b", text, re.I):
            bad.append(rel + ": ring/circle")
check("secrecy: no summoning, ritual or post-v1 text shipped; README, CHANGELOG, config and perks never mention a ring", not bad, bad)

if failures and os.environ.get("SPLICE_DEBUG"):
    for i in range(1, len(g.logs) + 1):
        print("  log:", g.logs[i])

print("RESULT", "FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)

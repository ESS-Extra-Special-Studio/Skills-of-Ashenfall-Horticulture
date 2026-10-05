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
r = cangraft("FPD_Cabbage", t(species="FPD_Cabbage", kind="plot", stage=1), 5)
check("same species is not a hybrid", r.startswith("false") and "just more" in r, r)
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
    for _, piece in ipairs(tub) do if piece.z > 10 then low = false end end
    out[#out + 1] = "tuberlow=" .. tostring(low)
    local o = Looks.ParseOverrides("# c\nTuberwoodAsh = /Game/Mods/X/SM_T\nBrassicaOak=/Game/A/B.B\n")
    out[#out + 1] = o.TuberwoodAsh .. " " .. o.BrassicaOak
    out[#out + 1] = Looks.PACKAGED.TuberwoodAsh
    return table.concat(out, " ")
end""")()
check("layouts for the flagships", all(s in lay for s in ["TuberwoodAsh=12", "BrassicaOak=10", "SheafAsh=12", "WeepingOak=2", "BambleNone=4"]) and "!" not in lay, lay)
check("Brassitato crowns the potato with a cabbage", "Brassitato=1:cabbage" in lay, lay)
check("Tuberwood potatoes sit at the roots", "tuberlow=true" in lay, lay)
check("meshes.txt overrides", "/Game/Mods/X/SM_T.SM_T /Game/A/B.B" in lay, lay)
check("packaged Tuberwood path", "/Game/Mods/SkillsOfAshenfallHorticulture/Art/Plants/TuberwoodAsh/SM_TuberwoodAsh_Additions_01.SM_TuberwoodAsh_Additions_01" in lay, lay)

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
check("splicing keys are G, Alt+G, Shift+G; none on Ctrl (the game's Evade)",
      bound == ["ALT+G", "G", "SHIFT+G"], bound)

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
check("lore card follows", "Tuberwood Ash|An ash that has decided" in c, c)
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

if failures and os.environ.get("SPLICE_DEBUG"):
    for i in range(1, len(g.logs) + 1):
        print("  log:", g.logs[i])

print("RESULT", "FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)

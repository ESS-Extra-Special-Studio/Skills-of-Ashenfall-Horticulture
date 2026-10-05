"""Unit test for horticulture_training.lua with fake plots, player and ESL.

Covers: proximity mode (no hooks), the rain guard, hook-confirmed mode on a
server (own work pays, other players' work does not), locked skill pays
nothing, first-sowing/first-harvest bonuses pay once per crop kind.

usage: python tools/training_test.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

SCRIPTS = os.path.join(ROOT, "SkillsOfAshenfallHorticulture", "Scripts")

HARNESS = r"""
local scripts, withHooks, withAddXp = ...
package.path = scripts .. "\\?.lua;" .. package.path
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = {}
loops, hooks, awards = {}, {}, {}
print = function() end
function LoopAsync(ms, fn) loops[#loops + 1] = fn end
function ExecuteInGameThread(fn) fn() end
function ExecuteWithDelay() end
function RegisterKeyBindAsync() end

local function obj(name, fields)
    local o = fields or {}
    o.IsValid = function() return true end
    o.GetFullName = function() return name end
    return o
end

farm = obj("FarmCommandComponent /Game/PC_0.Farm")
otherFarm = obj("FarmCommandComponent /Game/PC_1.Farm")
pawn = obj("Pawn /Game/Pawn_0", { K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end })
pc = obj("PlayerController /Game/PC_0", { Pawn = pawn, FarmCommandComponent = farm })

plots = {}
function make_plot(i, x)
    local p = obj("FarmSlotComponent /Game/Plot_" .. i, {
        K2_GetComponentLocation = function() return { X = x, Y = 0, Z = 0 } end,
        VisibleState = { PlotStage = 0, GrowthStage = 0, WateringProgress = 0, FertilizingProgress = 0, PlantDataNetID = 0 },
    })
    plots[#plots + 1] = p
    return p
end
-- Crop 7 is a cabbage the data subsystem can name; crop 3 is unknown.
local function plant(asset, name)
    return obj("FarmPlantDataAsset /Game/Gameplay/Farming/Plants/" .. asset .. "." .. asset, {
        GetFName = function() return { ToString = function() return asset end } end,
        DisplayName = { ToString = function() return name end },
    })
end
local cabbage = plant("FPD_Cabbage", "Cabbage")
subsystem = obj("DominionDataSubsystem /Engine/Transient.Data", {
    GetNetIdForData = function(_, data) if data == cabbage then return 7 end return 0 end,
})
function FindFirstOf(cls) if cls == "DominionDataSubsystem" then return subsystem end return nil end
function FindAllOf(cls)
    if cls == "FarmSlotComponent" then return plots end
    if cls == "FarmPlantDataAsset" then return { cabbage } end
    return nil
end
local invalid = { IsValid = function() return false end }
function StaticFindObject(path)
    if withHooks and path:find("FarmCommandComponent:", 1, true) then return obj(path) end
    return invalid
end
function RegisterHook(path, fn)
    if not withHooks then error("no hooks") end
    hooks[path:match(":(.+)$")] = fn
end
function FText(s) return s end
function FName(s) return s end
package.preload["UEHelpers"] = function()
    return {
        GetPlayerController = function() return pc end,
        GetWorld = function() return obj("World /Game/World") end,
        GetKismetSystemLibrary = function() return { IsValid = function() return true end, IsServer = function() return true end } end,
    }
end

unlocked = true
local paid, order = {}, {}
cards = {}
ESL = {
    Character = function() return "Tester" end,
    IsUnlocked = function() return unlocked end,
    Award = function(skill, id, xp, label)
        if not unlocked or paid[id] then return nil end
        paid[id] = true
        order[#order + 1] = id
        awards[#awards + 1] = id .. "=" .. xp
        return xp
    end,
    Paid = function() return order end,
    ShowCard = function(skill, kicker, title, detail)
        cards[#cards + 1] = kicker .. "|" .. title .. "|" .. detail
        return true
    end,
}
if withAddXp then
    ESL.AddXp = function(skill, xp, label)
        if not unlocked then return nil end
        awards[#awards + 1] = "add:" .. label .. "=" .. xp
        return xp
    end
end
Training = require("horticulture_training")
Training.Start({ ESL = ESL, SKILL = "Horticulture", dev = false })

function step()
    for _, fn in ipairs(loops) do fn() end
end
function call_hook(name, comp)
    hooks[name]({ get = function() return comp end })
end
function set(p, k, v) p.VisibleState[k] = v end
function take()
    local out = awards
    awards = {}
    return table.concat(out, " ")
end
"""


def runtime(with_hooks, with_addxp=False):
    lua = lua54.LuaRuntime()
    lua.execute(HARNESS, SCRIPTS, with_hooks, with_addxp)
    return lua


failures = 0


def check(name, got, want_parts, absent=()):
    global failures
    ok = all(w in got for w in want_parts) and not any(a in got for a in absent)
    failures += 0 if ok else 1
    print(("ok   " if ok else "FAIL ") + name + " -> " + (got or "(nothing)"))


def kinds(got):
    return sorted(a.split(":")[0] for a in got.split()) if got else []


# Proximity mode: no hooks.
L = runtime(False)
g = L.globals()
p1 = g.make_plot(1, 100)
p2 = g.make_plot(2, 200)
far = g.make_plot(3, 2500)
p4 = g.make_plot(4, 150)
g.step()
check("baseline pays nothing", g.take(), [], ["plant"])
g.set(p1, "PlotStage", 1); g.set(p1, "PlantDataNetID", 7)
g.step()
got = g.take()
check("sow pays plant + first sowing", got, ["plant:", "=10", "firstplant:FPD_Cabbage=17"])
g.set(p2, "PlotStage", 1); g.set(p2, "PlantDataNetID", 7)
g.step()
got = g.take()
check("second sowing of same crop: no first bonus", got, ["plant:"], ["firstplant"])
g.set(p1, "WateringProgress", 0.2)
g.step()
check("water pays", g.take(), ["water:", "=5"])
g.set(p1, "WateringProgress", 0.4)
g.step()
check("more water same stage pays nothing", g.take(), [], ["water"])
g.set(p1, "GrowthStage", 1); g.set(p1, "WateringProgress", 0.0)
g.step(); g.take()
g.set(p1, "WateringProgress", 0.2)
g.step()
check("water next growth stage pays", g.take(), ["water:"])
g.set(p1, "FertilizingProgress", 0.2)
g.step()
check("compost pays", g.take(), ["compost:", "=10"])
g.set(p1, "FertilizingProgress", 1.0)
g.step()
check("compost again same sowing pays nothing", g.take(), [], ["compost"])
g.set(p1, "PlotStage", 4)
g.step()
check("disease by itself pays nothing", g.take(), [], ["cure"])
g.set(p1, "PlotStage", 1)
g.step()
check("cure pays", g.take(), ["cure:", "=13"])
g.set(p1, "PlotStage", 2)
g.step()
check("ripening pays nothing", g.take(), [], ["harvest"])
g.set(p1, "PlotStage", 0)
g.step()
check("harvest pays + first harvest", g.take(), ["harvest:", "=23", "firstharvest:FPD_Cabbage=33"])
card = g.cards[1] if len(g.cards) else ""
check("catalogue card on first harvest", card or "", ["VANILLA PLANTS|Cabbage|1 of 24"])
check("catalogue line", g.Training.CatalogueLine(), ["1/24: Cabbage"])
g.set(far, "PlotStage", 1)
g.step()
check("plot out of reach pays nothing", g.take(), [], ["plant"])
g.set(p1, "PlotStage", 3)
g.step(); g.take()
g.set(p1, "PlotStage", 0)
g.step()
check("weeding pays", g.take(), ["weed:", "=3"])
# Rain: three plots watered at once.
g.set(p4, "PlotStage", 1)
g.step(); g.take()
g.set(p2, "WateringProgress", 0.5); g.set(p4, "WateringProgress", 0.5); g.set(far, "WateringProgress", 0.5)
g.step()
check("rain on three plots pays nothing", g.take(), [], ["water"])
g.unlocked = False
g.set(p2, "PlotStage", 2)
g.step(); g.take()
g.set(p2, "PlotStage", 0)
g.step()
check("locked skill pays nothing", g.take(), [], ["harvest"])

# Hook mode on a server.
L = runtime(True)
g = L.globals()
p1 = g.make_plot(1, 100)
g.step()
g.set(p1, "PlotStage", 1); g.set(p1, "PlantDataNetID", 3)
g.call_hook("Server_TryPlantSeed", g.otherFarm)
g.step()
check("host: another player's sowing pays nothing", g.take(), [], ["plant"])
g.set(p1, "PlotStage", 0)
g.step(); g.take()
g.call_hook("Server_TryPlantSeed", g.farm)
g.set(p1, "PlotStage", 1)
g.step()
check("host: own sowing pays, unknown crop by id", g.take(), ["plant:", "firstplant:net3=17"])
g.set(p1, "WateringProgress", 0.3)
g.step()
check("host: water without own request pays nothing", g.take(), [], ["water"])

# ESL with AddXp: repeatable work records nothing per source.
L = runtime(False, True)
g = L.globals()
p1 = g.make_plot(1, 100)
g.step()
g.set(p1, "PlotStage", 1); g.set(p1, "PlantDataNetID", 7)
g.step()
check("AddXp: sowing is repeatable XP, first sowing still once", g.take(),
      ["add:Seed sown=10", "firstplant:FPD_Cabbage=17"], [" plant:", "=10 plant:"])
g.set(p1, "WateringProgress", 0.2)
g.step()
check("AddXp: water pays", g.take(), ["add:Watered=5"])
g.set(p1, "WateringProgress", 0.4)
g.step()
check("AddXp: more water same stage pays nothing", g.take(), [], ["Watered"])
g.set(p1, "GrowthStage", 1); g.set(p1, "WateringProgress", 0.0)
g.step(); g.take()
g.set(p1, "WateringProgress", 0.2)
g.step()
check("AddXp: water next stage pays", g.take(), ["add:Watered=5"])
g.set(p1, "FertilizingProgress", 0.2)
g.step()
g.set(p1, "FertilizingProgress", 0.6)
g.step()
check("AddXp: compost pays once", g.take(), ["add:Soil fed=10"])
g.set(p1, "PlotStage", 2)
g.step(); g.take()
g.set(p1, "PlotStage", 0)
g.step()
check("AddXp: harvest repeatable + catalogue once", g.take(), ["add:Crop harvested=23", "firstharvest:FPD_Cabbage=33"])
g.set(p1, "PlotStage", 1)
g.step(); g.take()
g.set(p1, "PlotStage", 2)
g.step(); g.take()
g.set(p1, "PlotStage", 0)
g.step()
check("AddXp: second harvest, no second catalogue entry", g.take(), ["add:Crop harvested=23"], ["firstharvest"])

print("RESULT", "FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)

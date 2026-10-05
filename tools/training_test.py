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
local scripts, withHooks = ...
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
function FindAllOf(cls) if cls == "FarmSlotComponent" then return plots end return nil end
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
local paid = {}
ESL = {
    Character = function() return "Tester" end,
    IsUnlocked = function() return unlocked end,
    Award = function(skill, id, xp, label)
        if not unlocked or paid[id] then return nil end
        paid[id] = true
        awards[#awards + 1] = id .. "=" .. xp
        return xp
    end,
}
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


def runtime(with_hooks):
    lua = lua54.LuaRuntime()
    lua.execute(HARNESS, SCRIPTS, with_hooks)
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
check("sow pays plant + first sowing", got, ["plant:", "=30", "firstplant:7=50"])
g.set(p2, "PlotStage", 1); g.set(p2, "PlantDataNetID", 7)
g.step()
got = g.take()
check("second sowing of same crop: no first bonus", got, ["plant:"], ["firstplant"])
g.set(p1, "WateringProgress", 0.2)
g.step()
check("water pays", g.take(), ["water:", "=15"])
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
check("compost pays", g.take(), ["compost:", "=30"])
g.set(p1, "FertilizingProgress", 1.0)
g.step()
check("compost again same sowing pays nothing", g.take(), [], ["compost"])
g.set(p1, "PlotStage", 4)
g.step()
check("disease by itself pays nothing", g.take(), [], ["cure"])
g.set(p1, "PlotStage", 1)
g.step()
check("cure pays", g.take(), ["cure:", "=40"])
g.set(p1, "PlotStage", 2)
g.step()
check("ripening pays nothing", g.take(), [], ["harvest"])
g.set(p1, "PlotStage", 0)
g.step()
check("harvest pays + first harvest", g.take(), ["harvest:", "=70", "firstharvest:7=100"])
g.set(far, "PlotStage", 1)
g.step()
check("plot out of reach pays nothing", g.take(), [], ["plant"])
g.set(p1, "PlotStage", 3)
g.step(); g.take()
g.set(p1, "PlotStage", 0)
g.step()
check("weeding pays", g.take(), ["weed:", "=10"])
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
check("host: own sowing pays", g.take(), ["plant:", "firstplant:3=50"])
g.set(p1, "WateringProgress", 0.3)
g.step()
check("host: water without own request pays nothing", g.take(), [], ["water"])

print("RESULT", "FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)

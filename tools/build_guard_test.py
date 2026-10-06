"""Unit test for the build-mode hold in horticulture_util.lua (U.every).

Picking a piece in the build menu streams its class in, and periodic Lua work
in those frames crashed the game inside UE4SS. Covers: tasks run normally;
held while the BuildModeComponent (on the pawn or the controller) reports
build mode, by bIsBuildMode or by a non-zero CurrentBuildMode; held for the
grace period after; run again once it is over; no component means no hold.

usage: python tools/build_guard_test.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

SCRIPTS = os.path.join(ROOT, "SkillsOfAshenfallHorticulture", "Scripts")

HARNESS = r"""
local scripts = ...
package.path = scripts .. "\\?.lua;" .. package.path
print = function() end
loops = {}
function LoopAsync(ms, fn) loops[#loops + 1] = fn end
function ExecuteInGameThread(fn) fn() end
clock = 0
os.clock = function() return clock end

local function obj(name, fields)
    local o = fields or {}
    o.IsValid = function() return true end
    o.GetFullName = function() return name end
    return o
end
build = obj("BuildModeComponent /Game/Pawn_0.Build", {})
pawn = obj("Pawn /Game/Pawn_0", {})
pc = obj("PlayerController /Game/PC_0", { Pawn = pawn })
package.preload["UEHelpers"] = function()
    return { GetPlayerController = function() return pc end }
end

U = require("horticulture_util")
runs = 0
U.every(100, "Test task", function() runs = runs + 1 end)

function tick(dt)
    clock = clock + (dt or 0.25)
    for _, fn in ipairs(loops) do fn() end
    return runs
end
function take()
    local n = runs
    runs = 0
    return n
end
"""

failures = 0


def check(label, got, want):
    global failures
    ok = got == want
    if not ok:
        failures += 1
    print(("PASS " if ok else "FAIL ") + label + ("" if ok else f": got {got!r}, want {want!r}"))


def runtime():
    lua = lua54.LuaRuntime()
    lua.execute(HARNESS, SCRIPTS)
    return lua.globals()


g = runtime()
g.tick(); g.tick()
check("no build component: tasks run", g.take(), 2)

g.pawn.BuildModeComponent = g.build
g.build.bIsBuildMode = False
g.tick(); g.tick()
check("component, not building: tasks run", g.take(), 2)

g.build.bIsBuildMode = True
g.tick(); g.tick(); g.tick()
check("bIsBuildMode: tasks held", g.take(), 0)

g.build.bIsBuildMode = False
g.tick(1.0)
check("just left build mode: still held (grace)", g.take(), 0)
g.tick(1.0)
check("within grace: still held", g.take(), 0)
g.tick(1.5)
check("after grace: tasks run again", g.take(), 1)

g = runtime()
g.pc.BuildModeComponent = g.build
g.build.CurrentBuildMode = 0
g.tick()
check("controller component, CurrentBuildMode 0: tasks run", g.take(), 1)
g.build.CurrentBuildMode = 2
g.tick(); g.tick()
check("CurrentBuildMode non-zero: tasks held", g.take(), 0)
g.build.CurrentBuildMode = 0
g.tick(4.0)
check("CurrentBuildMode back to 0, after grace: tasks run", g.take(), 1)

g = runtime()
g.pawn.BuildModeComponent = g.build
g.build.bIsBuildMode = g.pawn
g.build.CurrentBuildMode = 0
g.tick()
check("bIsBuildMode an object (as in game), CurrentBuildMode 0: tasks run", g.take(), 1)
g.build.CurrentBuildMode = 1
g.tick(); g.tick()
check("bIsBuildMode an object, build menu open (CurrentBuildMode 1): tasks held", g.take(), 0)
g.build.CurrentBuildMode = 2
g.tick()
check("bIsBuildMode an object, placing (CurrentBuildMode 2): tasks held", g.take(), 0)
g.build.CurrentBuildMode = 0
g.tick(4.0)
check("bIsBuildMode an object, out of build mode after grace: tasks run", g.take(), 1)

print("RESULT", "FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)

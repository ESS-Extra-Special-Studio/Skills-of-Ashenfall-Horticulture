"""Static checks for the Horticulture Lua, without the game.

1. Syntax: every .lua under the mod's Scripts compiles under Lua 5.4 (the
   UE4SS Lua version), using the lupa package in tools/pylib.
2. Boot: main.lua runs against a sandbox copy of ESL:DragonWilds with UE4SS
   stubbed out (no world, no player), then every loop and key callback it
   registered runs once. Nothing is written outside tools/out/sandbox.

usage: python tools/lua_check.py
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pylib"))
from lupa import lua54  # noqa: E402

MOD = os.path.join(ROOT, "SkillsOfAshenfallHorticulture")
ESL = r"<user>\IdeaProjects\ESL-DragonWilds\ESLDragonWilds"
SANDBOX = os.path.join(ROOT, "tools", "out", "sandbox")


def syntax():
    bad = 0
    lua = lua54.LuaRuntime()
    check = lua.eval("function(src, name) local f, err = load(src, '@' .. name) return err end")
    for base, _, files in os.walk(MOD):
        for f in files:
            if f.endswith(".lua"):
                path = os.path.join(base, f)
                err = check(open(path, encoding="utf-8").read(), os.path.relpath(path, ROOT))
                print(("FAIL " + err) if err else ("ok   " + os.path.relpath(path, ROOT)))
                bad += 1 if err else 0
    return bad


STUBS = r"""
local sandbox = ...
-- ESL keeps progress under %LOCALAPPDATA%; point it into the sandbox so a
-- check can never create or move anything in the real Saved folder.
local real_getenv = os.getenv
os.getenv = function(k)
    if k == "LOCALAPPDATA" then return sandbox .. "\\LocalAppData" end
    return real_getenv(k)
end
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = { CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }
loops, keys, prints = {}, {}, {}
local real_print = print
print = function(s) prints[#prints + 1] = s real_print((s:gsub("\n$", ""))) end
function LoopAsync(ms, fn) loops[#loops + 1] = fn end
function ExecuteWithDelay(ms, fn) end
function ExecuteInGameThread(fn) fn() end
function RegisterKeyBindAsync(key, mods, fn) keys[#keys + 1] = { key = key, fn = fn } end
RegisterKeyBind = RegisterKeyBindAsync
function RegisterHook() error("no hooks outside the game") end
local invalid = setmetatable({}, { __index = function(t, k)
    if k == "IsValid" then return function() return false end end
    return nil
end })
function StaticFindObject() return invalid end
function FindAllOf() return nil end
function FindFirstOf() return invalid end
function LoadAsset() return invalid end
function FText(s) return s end
function FName(s) return s end
function CreateInvalidObject() return invalid end
function StaticConstructObject() return invalid end
ModRef = nil
package.preload["UEHelpers"] = function()
    local H = {}
    function H.GetPlayerController() return invalid end
    function H.GetWorld() return invalid end
    function H.GetGameInstance() return invalid end
    function H.GetKismetSystemLibrary() return invalid end
    function H.GetKismetMathLibrary() return invalid end
    return H
end
"""


SWITCHES = ("dev.txt", "dev-unlock.txt", "showcase.txt", "spike.txt", "book-mesh.txt", "placement.txt", "config.txt")


def boot(files=()):
    if os.path.isdir(SANDBOX):
        shutil.rmtree(SANDBOX)
    shutil.copytree(ESL, os.path.join(SANDBOX, "ESLDragonWilds"),
                    ignore=shutil.ignore_patterns("Saves", "Saves.*"))
    runtime = os.path.join(SANDBOX, "ESLDragonWilds", "Runtime")
    if os.path.isdir(runtime):
        for f in os.listdir(runtime):
            p = os.path.join(runtime, f)
            if os.path.isfile(p) and f != ".gitkeep":
                os.remove(p)
    os.makedirs(runtime, exist_ok=True)
    os.makedirs(os.path.join(SANDBOX, "ESLDragonWilds", "Saves"), exist_ok=True)
    os.makedirs(os.path.join(SANDBOX, "LocalAppData", "RSDragonwilds", "Saved"), exist_ok=True)
    shutil.copytree(MOD, os.path.join(SANDBOX, "SkillsOfAshenfallHorticulture"),
                    ignore=shutil.ignore_patterns(*SWITCHES))
    for name in files:
        open(os.path.join(SANDBOX, "SkillsOfAshenfallHorticulture", name), "w").close()
    print("--- boot", ("with " + ", ".join(files)) if files else "release")
    main = os.path.join(SANDBOX, "SkillsOfAshenfallHorticulture", "Scripts", "main.lua")
    lua = lua54.LuaRuntime()
    lua.execute(STUBS, SANDBOX)
    run = lua.eval("""function(path)
        local ok, err = xpcall(function() dofile(path) end, debug.traceback)
        if not ok then return 'main.lua: ' .. tostring(err) end
        for i, fn in ipairs(loops) do
            local okL, errL = pcall(fn)
            if not okL then return 'loop ' .. i .. ': ' .. tostring(errL) end
        end
        for _, k in ipairs(keys) do
            local okK, errK = pcall(k.fn)
            if not okK then return 'key ' .. tostring(k.key) .. ': ' .. tostring(errK) end
        end
        return nil
    end""")
    err = run(main)
    g = lua.globals()
    prints = g["prints"]
    out = [prints[i] for i in range(1, len(prints) + 1)]
    loaded = any("Loaded 1.0.0" in s for s in out)
    print("boot:", "FAIL " + err if err else "ok", "| loops", len(g["loops"]), "| keys", len(g["keys"]),
          "| loaded line", loaded)
    reg = os.path.join(SANDBOX, "ESLDragonWilds", "Runtime", "Horticulture.skill")
    if not os.path.exists(reg):
        reg = os.path.join(SANDBOX, "ESLDragonWilds", "Saves", "Horticulture.skill")
    print("registry:", reg if os.path.exists(reg) else "MISSING")
    if os.path.exists(reg):
        print(open(reg, encoding="utf-8").read())
    return 1 if (err or not loaded) else 0


if __name__ == "__main__":
    failures = syntax()
    failures += boot(("dev.txt", "dev-unlock.txt", "spike.txt"))
    failures += boot(("showcase.txt",))
    failures += boot()
    print("RESULT", "FAIL" if failures else "PASS")
    sys.exit(1 if failures else 0)

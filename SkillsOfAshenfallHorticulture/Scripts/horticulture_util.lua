local UEHelpers = require("UEHelpers")

local U = {}

local PREFIX = "[Skills of Ashenfall: Horticulture] "

function U.log(msg)
    print(PREFIX .. msg .. "\n")
end

local said = {}
function U.log_once(key, msg)
    if said[key] then return end
    said[key] = true
    U.log(msg)
end

function U.valid(obj)
    local ok, yes = pcall(function() return obj ~= nil and obj:IsValid() end)
    return ok and yes
end

function U.full(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    return ok and name or ""
end

function U.fname(obj)
    local ok, name = pcall(function() return obj:GetFName():ToString() end)
    return ok and name or ""
end

function U.exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- Runs fn on the game thread when UE4SS offers it. Spawning, widgets and
-- property writes go through here.
function U.game(fn)
    local wrapped = function()
        local ok, err = pcall(fn)
        if not ok then U.log_once("game" .. tostring(err), "Game-thread task failed: " .. tostring(err)) end
    end
    if ExecuteInGameThread then ExecuteInGameThread(wrapped) else wrapped() end
end

-- True while the local player is placing a building, and for a moment after.
-- The first time a piece is picked in the build menu the game streams its
-- class in; any of our periodic work in those frames crashed the game inside
-- UE4SS (UE4SS.dll+0x2ace27, a null read under UStruct::FindProperty), so
-- U.every holds every task until building is over.
local BUILD_GRACE = 3
local BUILD_POLL = 0.2
local BUILD_SEARCH = 5
local building = { comp = nil, at = -math.huge, on = false, until_ = -math.huge, said = nil, searched = -math.huge }

local function build_component()
    if U.valid(building.comp) then return building.comp end
    building.comp = nil
    local holders = { U.pawn(), U.pc() }
    for _, holder in ipairs(holders) do
        pcall(function()
            local c = holder.BuildModeComponent
            if U.valid(c) then building.comp = c end
        end)
        if building.comp then return building.comp end
    end
    if os.clock() - building.searched < BUILD_SEARCH or not FindAllOf then return nil end
    building.searched = os.clock()
    local mine = {}
    for _, h in ipairs(holders) do mine[U.full(h)] = true end
    for _, c in ipairs(FindAllOf("BuildModeComponent") or {}) do
        local owner = nil
        pcall(function() owner = c:GetOwner() end)
        if U.valid(c) and owner and mine[U.full(owner)] then
            building.comp = c
            U.log_once("buildcomp", "Build mode read from " .. U.full(c))
            return c
        end
    end
    return nil
end

local function build_mode_on(comp)
    local flag, mode = nil, nil
    pcall(function() flag = comp.bIsBuildMode end)
    pcall(function() mode = comp.CurrentBuildMode end)
    mode = tonumber(mode)
    -- bIsBuildMode reads back as a TrivialObject in game, never a boolean;
    -- CurrentBuildMode is 1 with the build menu open and 2 while placing.
    if type(flag) ~= "boolean" then flag = nil end
    local on = flag == true or (mode ~= nil and mode ~= 0)
    local seen = tostring(on) .. "/" .. tostring(flag) .. "/" .. tostring(mode)
    if seen ~= building.said then
        building.said = seen
        U.log("Build mode " .. (on and "on" or "off") .. " (bIsBuildMode " .. tostring(flag)
            .. ", CurrentBuildMode " .. tostring(mode) .. "): periodic work " .. (on and "held" or "resumes"))
    end
    return on
end

function U.Building()
    local t = os.clock()
    if t - building.at >= BUILD_POLL then
        building.at = t
        local comp = build_component()
        building.on = comp ~= nil and build_mode_on(comp)
        if building.on then building.until_ = t + BUILD_GRACE end
    end
    return building.on or t < building.until_
end

-- Runs fn every ms milliseconds, on the game thread when UE4SS can loop there.
-- Queuing game-thread work from LoopAsync's thread many times a second can
-- corrupt UE4SS's callback references, so the fallback skips a beat while the
-- previous one is still queued.
function U.every(ms, name, fn)
    local function run()
        if U.Building() then return end
        local ok, err = pcall(fn)
        if not ok then U.log_once(name .. tostring(err), name .. " failed: " .. tostring(err)) end
    end
    if LoopInGameThreadWithDelay and pcall(LoopInGameThreadWithDelay, ms, function() run() return false end) then
        return
    end
    if not LoopAsync then return end
    local waiting = false
    LoopAsync(ms, function()
        if not waiting then
            waiting = true
            U.game(function() waiting = false run() end)
        end
        return false
    end)
end

function U.pc()
    local ok, pc = pcall(UEHelpers.GetPlayerController)
    if ok and U.valid(pc) then return pc end
    return nil
end

function U.pawn()
    local pc = U.pc()
    if not pc then return nil end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if U.valid(pawn) then return pawn end
    return nil
end

function U.location(actor)
    local ok, v = pcall(function()
        local l = actor:K2_GetActorLocation()
        return { X = l.X, Y = l.Y, Z = l.Z }
    end)
    return ok and v or nil
end

function U.dist(a, b)
    if not (a and b) then return math.huge end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, (a.Z or 0) - (b.Z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function U.dist2d(a, b)
    if not (a and b) then return math.huge end
    local dx, dy = a.X - b.X, a.Y - b.Y
    return math.sqrt(dx * dx + dy * dy)
end

-- Short stable id for an object name, for source ids in the save.
function U.hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- Instances of a class, without class default objects.
function U.live_of(className)
    local out = {}
    for _, o in ipairs(FindAllOf(className) or {}) do
        if U.valid(o) and not U.full(o):find("Default__", 1, true) then out[#out + 1] = o end
    end
    return out
end

-- Name of the property's type, such as "ObjectProperty" or "TextProperty".
function U.prop_type(prop)
    local ok, t = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return ok and t or "?"
end

function U.prop_name(prop)
    local ok, n = pcall(function() return prop:GetFName():ToString() end)
    return ok and n or "?"
end

-- Every property of a class and its parents: { name, type, owner, prop }.
function U.properties(cls)
    local out = {}
    local depth = 0
    while U.valid(cls) and depth < 12 do
        local owner = U.fname(cls)
        pcall(function()
            cls:ForEachProperty(function(prop)
                out[#out + 1] = { name = U.prop_name(prop), type = U.prop_type(prop), owner = owner, prop = prop }
            end)
        end)
        local okS, super = pcall(function() return cls:GetSuperStruct() end)
        cls = okS and super or nil
        depth = depth + 1
    end
    return out
end

-- The UFunction for a function name on an object's class or its parents.
function U.find_function(obj, name)
    local okC, cls = pcall(function() return obj:GetClass() end)
    local depth = 0
    while okC and U.valid(cls) and depth < 12 do
        local path = U.full(cls):match("^%S+%s+(.+)$")
        if path then
            local fn = StaticFindObject(path .. ":" .. name)
            if U.valid(fn) then return fn, path end
        end
        local okS, super = pcall(function() return cls:GetSuperStruct() end)
        cls = okS and super or nil
        depth = depth + 1
    end
    return nil
end

function U.text(widget)
    local ok, t = pcall(function() return widget:GetText():ToString() end)
    return ok and t or nil
end

function U.set_text(widget, s)
    if not U.valid(widget) then return false end
    local ok = pcall(function() widget:SetText(FText(s)) end)
    return ok
end

function U.visible(widget)
    local ok, v = pcall(function() return widget:IsVisible() end)
    return ok and v == true
end

return U

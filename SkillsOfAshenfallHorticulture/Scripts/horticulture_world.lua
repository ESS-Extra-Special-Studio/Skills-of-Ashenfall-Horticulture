-- The game side of splicing: what the player is aiming at, the axe in their
-- hand, the in-game clock and giving items.
--
-- Verified in build 25632050 (exe reflection names, /Script/Dominion):
--   FarmSlotComponent: GetPlotID, PlotTier, PlantMeshComponent, VisibleState
--   FellableTree: TreeData, bIsFarmingTree, bIsStump
--   SaplingBase: FarmingGrowingTree_Id_ServerOnly
--   Blueprints BP_FellableTree_{Ash,Oak,Willow,Yew,Maple,MagicTree},
--   BP_Sapling_{Ash,Oak,Yew}_*, BP_Sapling_Base
--   Equipment:BP_GetEquipmentData, ItemData:GetBasePowerLevel,
--   DominionRuntimeBlueprintLibrary:TryGiveItemToPlayer(PlayerController,
--   ItemData, Count), InventoryComponent:AddItemByData,
--   InGameTimeFunctionLibrary:GetInGameTime(WorldContextObject)
-- Not verified: which of these read or work from Lua. Each has a fallback
-- and logs the way that worked once.
local UEHelpers = require("UEHelpers")
local U = require("horticulture_util")
local Crops = require("horticulture_crops")
local Rules = require("horticulture_splice_rules")

local World = {}

local REACH = { plot = 450, sapling = 500, tree = 750, wild = 400 }
local RADIUS = { plot = 90, sapling = 70, tree = 160, wild = 60 }
local WILD_CLASSES = { "GatherableResource", "HarvestableResource" }
local PROMPT = "WBP_HUD_InteractionPrompt_C"
local SCAN = 2000
local TIME_LIB = "/Script/Dominion.Default__InGameTimeFunctionLibrary"
local RUNTIME_LIB = "/Script/Dominion.Default__DominionRuntimeBlueprintLibrary"
local TICKS_PER_HOUR = 36000000000

local SPECIES_WORDS = {
    { "magictree", "Magic" }, { "magic", "Magic" }, { "willow", "Willow" }, { "maple", "Maple" },
    { "yew", "Yew" }, { "oak", "Oak" }, { "ash", "Ash" },
}

local CROP_WORDS = {
    { "cabbage", "FPD_Cabbage" }, { "potato", "FPD_Potato" }, { "wheat", "FPD_Wheat" },
    { "redberry", "FPD_Redberry" }, { "redberries", "FPD_Redberry" }, { "berry_bush", "FPD_Redberry" },
    { "flax", "FPD_Flax" }, { "onion", "FPD_Onion" }, { "tomato", "FPD_Tomato" },
    { "harralander", "FPD_Harralander" }, { "marrentill", "FPD_Marrentill" }, { "marentill", "FPD_Marrentill" },
    { "kwuarm", "FPD_Kwuarm" }, { "dwellberry", "FPD_Dwellberry" }, { "dwellberries", "FPD_Dwellberry" },
}

local function words(name)
    return "_" .. tostring(name or ""):lower():gsub("[^%a%d]", "_") .. "_"
end

local function has_word(s, w)
    return s:find("_" .. w .. "_", 1, true) or s:find("_" .. w .. "%d") or s:find("_" .. w .. "e?s_")
end

-- Tree species from names such as BP_FellableTree_Oak_C or
-- SM_FH_Ash_Tree_01, matched as whole words.
function World.SpeciesFromName(name)
    local s = words(name)
    for _, w in ipairs(SPECIES_WORDS) do
        if s:find("_" .. w[1] .. "_", 1, true) or s:find("_" .. w[1] .. "%d") then return w[2] end
    end
    return nil
end

-- Crop key from names such as BP_Gatherable_Potato_C or a prompt's
-- "Potato Plant". Seeds are not plants.
function World.CropFromName(name)
    local s = words(name)
    if s:find("_seed", 1, true) then return nil end
    for _, w in ipairs(CROP_WORDS) do
        if has_word(s, w[1]) then return w[2] end
    end
    return nil
end

local function class_names(obj)
    local out = {}
    local okC, cls = pcall(function() return obj:GetClass() end)
    local depth = 0
    while okC and U.valid(cls) and depth < 8 do
        out[#out + 1] = U.fname(cls)
        local okS, super = pcall(function() return cls:GetSuperStruct() end)
        cls = okS and super or nil
        depth = depth + 1
    end
    return out
end

local function mesh_names(actor)
    local out = {}
    local cls = StaticFindObject("/Script/Engine.StaticMeshComponent")
    pcall(function()
        actor:K2_GetComponentsByClass(cls):ForEach(function(_, c)
            local comp = c:get()
            local mesh = nil
            pcall(function() mesh = comp.StaticMesh end)
            if U.valid(mesh) then out[#out + 1] = U.fname(mesh) end
        end)
    end)
    return out
end

function World.TreeSpecies(actor)
    for _, n in ipairs(class_names(actor)) do
        local s = World.SpeciesFromName(n)
        if s then return s end
    end
    for _, n in ipairs(mesh_names(actor)) do
        local s = World.SpeciesFromName(n)
        if s then return s end
    end
    return nil
end

local function prop(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v end
    return nil
end

local function slot_location(slot)
    local ok, v = pcall(function()
        local l = slot:K2_GetComponentLocation()
        return { X = l.X, Y = l.Y, Z = l.Z }
    end)
    if ok and v then return v end
    local owner = nil
    pcall(function() owner = slot:GetOwner() end)
    return U.location(owner)
end

local function plot_key(slot, loc)
    local ok, id = pcall(function() return slot:GetPlotID() end)
    if ok and id ~= nil then
        local s = tostring(id)
        if s ~= "" and s ~= "0" and s ~= "nil" then return "plot:" .. s end
    end
    if loc then return string.format("plot@%.0f,%.0f", loc.X, loc.Y) end
    return nil
end

local function plot_info(slot)
    local loc = slot_location(slot)
    if not loc then return nil end
    local st = nil
    pcall(function()
        local v = slot.VisibleState
        st = { stage = tonumber(v.PlotStage), net = tonumber(v.PlantDataNetID) }
    end)
    if not st then return nil end
    local species = nil
    if st.net and st.net > 0 and st.stage ~= 0 and st.stage ~= 3 then
        species = Crops.Key(st.net)
    end
    local tier = tonumber(prop(slot, "PlotTier")) or 1
    if tier < 1 then tier = tier + 1 end
    local owner = nil
    pcall(function() owner = slot:GetOwner() end)
    local plant = prop(slot, "PlantMeshComponent")
    return {
        kind = "plot", obj = slot, actor = owner, loc = loc, species = species, stage = st.stage,
        alive = st.stage == 1 or st.stage == 2, tier = tier, key = plot_key(slot, loc),
        planted = true, plant = U.valid(plant) and plant or nil,
    }
end

local function sapling_planted(actor)
    local id = prop(actor, "FarmingGrowingTree_Id_ServerOnly")
    if id == nil then
        U.log_once("saplingid", "Sapling farming id not readable; every sapling counts as planted")
        return true
    end
    local n = tonumber(type(id) == "table" and id.Value or id)
    if n == nil then return tostring(id) ~= "0" end
    return n ~= 0
end

local function sapling_info(actor)
    local loc = U.location(actor)
    if not loc then return nil end
    local species = World.TreeSpecies(actor)
    return { kind = "sapling", obj = actor, actor = actor, loc = loc, species = species, alive = true, planted = sapling_planted(actor) }
end

local function tree_info(actor)
    local loc = U.location(actor)
    if not loc then return nil end
    if prop(actor, "bIsStump") == true then return { kind = "stump", obj = actor, actor = actor, loc = loc } end
    local species = World.TreeSpecies(actor)
    return { kind = "tree", obj = actor, actor = actor, loc = loc, species = species, alive = true, planted = prop(actor, "bIsFarmingTree") == true }
end

-- A wild crop plant (a gatherable potato, the cabbages of Bramblemead): a
-- source of cuttings, never a host.
local function wild_info(actor)
    local loc = U.location(actor)
    if not loc then return nil end
    local species = nil
    for _, n in ipairs(class_names(actor)) do
        species = species or World.CropFromName(n)
    end
    if not species then
        for _, n in ipairs(mesh_names(actor)) do species = species or World.CropFromName(n) end
    end
    if not species then return nil end
    return { kind = "wild", obj = actor, actor = actor, loc = loc, species = species, alive = true, planted = false }
end

-- Every plot, sapling, tree and wild crop plant within range of a point.
function World.Nearby(center, range)
    local out = {}
    range = range or SCAN
    for _, slot in ipairs(U.live_of("FarmSlotComponent")) do
        local p = plot_info(slot)
        if p and U.dist(p.loc, center) <= range then out[#out + 1] = p end
    end
    for _, a in ipairs(U.live_of("SaplingBase")) do
        local loc = U.location(a)
        if loc and U.dist(loc, center) <= range then
            local s = sapling_info(a)
            if s then out[#out + 1] = s end
        end
    end
    for _, a in ipairs(U.live_of("FellableTree")) do
        local loc = U.location(a)
        if loc and U.dist(loc, center) <= range then
            local t = tree_info(a)
            if t then out[#out + 1] = t end
        end
    end
    if range <= 1500 then
        for _, cls in ipairs(WILD_CLASSES) do
            for _, a in ipairs(U.live_of(cls)) do
                local loc = U.location(a)
                if loc and U.dist(loc, center) <= range then
                    local w = wild_info(a)
                    if w then out[#out + 1] = w end
                end
            end
        end
    end
    return out
end

-- The interaction prompt the game shows for what the player looks at, when
-- it names a crop ("Potato", "Cabbage"): wild plants drawn as foliage have
-- no actor of their own until the game makes one for the prompt.
function World.PromptCrop(me)
    for _, prompt in ipairs(U.live_of(PROMPT)) do
        if U.visible(prompt) then
            local block = prop(prompt, "ItemNameTextBlock")
            local text = U.valid(block) and U.text(block) or nil
            local species = text and World.CropFromName(text)
            if species then
                local actor = prop(prompt, "CurrentWorldActor")
                local loc = U.valid(actor) and U.location(actor) or nil
                if loc and U.dist2d(loc, me) > REACH.wild then loc = nil end
                U.log_once("prompt" .. species, "Wild " .. species .. " seen through the prompt \"" .. text .. "\" (" .. U.full(actor) .. ")")
                return { kind = "wild", obj = actor, actor = actor, loc = loc or me, species = species, alive = true, planted = false, prompt = text }
            end
        end
    end
    return nil
end

-- Camera position and look direction.
function World.Camera()
    local pc = U.pc()
    if not pc then return nil end
    local cam = prop(pc, "PlayerCameraManager")
    local loc, rot = nil, nil
    if U.valid(cam) then
        pcall(function()
            local l = cam:GetCameraLocation()
            loc = { X = l.X, Y = l.Y, Z = l.Z }
            local r = cam:GetCameraRotation()
            rot = { Pitch = r.Pitch, Yaw = r.Yaw }
        end)
    end
    if not (loc and rot) then
        local pawn = U.pawn()
        loc = U.location(pawn)
        pcall(function()
            local r = pc:GetControlRotation()
            rot = { Pitch = r.Pitch, Yaw = r.Yaw }
        end)
        if loc then loc.Z = loc.Z + 60 end
    end
    if not (loc and rot) then return nil end
    local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
    return loc, { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end

-- Picks the candidate the camera ray passes closest to, within reach of the
-- player. Pure: candidates carry loc and kind.
function World.Pick(candidates, eye, dir, me)
    local best, bestScore = nil, math.huge
    for _, c in ipairs(candidates) do
        local kind = c.kind == "stump" and "tree" or c.kind
        if U.dist2d(c.loc, me) <= (REACH[kind] or 500) then
            local lift = kind == "tree" and 150 or ((kind == "sapling" or kind == "wild") and 30 or 10)
            local tx, ty, tz = c.loc.X - eye.X, c.loc.Y - eye.Y, c.loc.Z + lift - eye.Z
            local along = tx * dir.X + ty * dir.Y + tz * dir.Z
            if along > 0 then
                -- Trees are tall: measure to the trunk line, not one point.
                local px, py, pz = eye.X + dir.X * along, eye.Y + dir.Y * along, eye.Z + dir.Z * along
                local dz = 0
                if kind == "tree" then
                    local rel = pz - c.loc.Z
                    if rel > 0 and rel < 1200 then dz = 0 else dz = pz - (c.loc.Z + lift) end
                else
                    dz = pz - (c.loc.Z + lift)
                end
                local perp = math.sqrt((px - c.loc.X) ^ 2 + (py - c.loc.Y) ^ 2 + dz * dz)
                local score = perp - (RADIUS[kind] or 80)
                if score <= 40 then
                    score = score + along * 0.05
                    if score < bestScore then best, bestScore = c, score end
                end
            end
        end
    end
    return best
end

function World.Aimed()
    local me = U.location(U.pawn())
    if not me then return nil end
    local eye, dir = World.Camera()
    if not eye then return nil end
    local best = World.Pick(World.Nearby(me, 1000), eye, dir, me)
    -- Something the player grew wins; otherwise a crop the game's own
    -- prompt names, then whatever the camera points at.
    if best and (best.kind == "plot" or best.planted) then return best end
    return World.PromptCrop(me) or best
end

-- The axe in the player's hand: its power, item name and how it was read.
local equipLogged = false
function World.HeldAxe()
    local pawn = U.pawn()
    if not pawn then return nil end
    local pawnName = U.full(pawn)
    for _, eq in ipairs(U.live_of("Equipment")) do
        local owner = nil
        pcall(function() owner = eq:GetOwner() end)
        local parent = nil
        pcall(function() parent = eq:GetAttachParentActor() end)
        if U.full(owner) == pawnName or U.full(parent) == pawnName then
            local data = nil
            pcall(function() data = eq:BP_GetEquipmentData() end)
            local name = U.valid(data) and U.fname(data) or U.fname(eq)
            local byName = Rules.AxePower(name)
            if byName then
                local power, how = byName, "item name"
                local okP, base = pcall(function() return data:GetBasePowerLevel() end)
                if okP and tonumber(base) and tonumber(base) > 0 then power, how = tonumber(base), "GetBasePowerLevel" end
                if not equipLogged then
                    equipLogged = true
                    U.log(string.format("Held axe read: %s, power %d (%s; by name %d)", name, power, how, byName))
                end
                return power, name
            end
        end
    end
    return nil
end

-- Hour of the in-game clock (0-24, fractional), or nil.
local clockWay = nil
function World.Hour()
    local lib = StaticFindObject(TIME_LIB)
    local world = UEHelpers.GetWorld()
    if not (U.valid(lib) and U.valid(world)) then return nil end
    local ok, t = pcall(function() return lib:GetInGameTime(world) end)
    if not ok or t == nil then return nil end
    local h, m = nil, nil
    pcall(function() h, m = t.Hours, t.Minutes end)
    if type(h) == "number" then
        if clockWay ~= "fields" then clockWay = "fields" U.log("In-game clock read (Hours/Minutes)") end
        return (h % 24) + (tonumber(m) or 0) / 60
    end
    local ticks = nil
    pcall(function() ticks = t.Ticks end)
    if type(ticks) == "number" then
        if clockWay ~= "ticks" then clockWay = "ticks" U.log("In-game clock read (Ticks)") end
        return (ticks / TICKS_PER_HOUR) % 24
    end
    return nil
end

-- Did the clock pass dawn between two readings? Sleeping jumps the clock.
World.DAWN_HOUR = 6
function World.PassedDawn(last, now)
    if not (last and now) then return false end
    local d = World.DAWN_HOUR
    if now >= last then return last < d and now >= d end
    return now >= d or last < d
end

local function load_item(path)
    local full = path .. "." .. path:match("([^/]+)$")
    local obj = StaticFindObject(full)
    if not U.valid(obj) and LoadAsset then
        local ok, loaded = pcall(LoadAsset, full)
        if ok and U.valid(loaded) then obj = loaded end
    end
    return U.valid(obj) and obj or nil
end

-- Gives count of an item to the local player. Returns true when given.
local giveWay = nil
function World.Give(path, count)
    local pc = U.pc()
    local data = load_item(path)
    if not (pc and data) then
        U.log_once("noitem" .. path, "Item " .. path .. " could not be loaded")
        return false
    end
    local lib = StaticFindObject(RUNTIME_LIB)
    if U.valid(lib) then
        local ok, given = pcall(function() return lib:TryGiveItemToPlayer(pc, data, count) end)
        if ok and given ~= false then
            if giveWay ~= "try" then giveWay = "try" U.log("Items given through TryGiveItemToPlayer") end
            return true
        end
    end
    local pawn = U.pawn()
    local inv = pawn and prop(pawn, "InventoryComponent")
    if U.valid(inv) then
        local ok, given = pcall(function() return inv:AddItemByData(data, count, 100, {}) end)
        if ok and given ~= false then
            if giveWay ~= "add" then giveWay = "add" U.log("Items given through InventoryComponent:AddItemByData") end
            return true
        end
    end
    U.log_once("give" .. path, "Could not give " .. path)
    return false
end

-- A server or single player: the only machines where v1 splicing runs.
function World.IsServer()
    local ok, yes = pcall(function()
        return UEHelpers.GetKismetSystemLibrary():IsServer(UEHelpers.GetWorld())
    end)
    if ok and yes ~= nil then return yes == true end
    return true
end

return World

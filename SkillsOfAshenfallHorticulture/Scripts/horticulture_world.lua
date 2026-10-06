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
local TRUNK = { tree = 1200, sapling = 400 }
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
    local st = Crops.PlotState(slot)
    if not st then return nil end
    local species = nil
    local named = type(st.net) == "string" or (tonumber(st.net) or 0) > 0
    if named and st.stage ~= 0 and st.stage ~= 3 then
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
        water = (tonumber(st.water) or 0) >= 1 and 1 or 0, fert = (tonumber(st.fert) or 0) >= 1 and 1 or 0, growth = st.growth,
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

-- Developer aid: the game's wild crop spawners (BP_Spawner_Potato_C and the
-- like) within range, for finding a plant to take a cutting from.
local SPAWNERS = { "BP_Spawner_Potato_C", "BP_Spawner_Cabbage_C", "BP_Spawner_Onion_C", "BP_Spawner_Wheat_C" }
function World.WildSpawners(center, range)
    local out = {}
    for _, cls in ipairs(SPAWNERS) do
        for _, a in ipairs(U.live_of(cls)) do
            local loc = U.location(a)
            local species = World.CropFromName(cls)
            if loc and species and U.dist2d(loc, center) <= range then
                out[#out + 1] = { species = species, loc = loc, actor = a }
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
                -- Trees and grown saplings are tall: measure to the trunk
                -- line, not one point.
                local px, py, pz = eye.X + dir.X * along, eye.Y + dir.Y * along, eye.Z + dir.Z * along
                local dz = 0
                if TRUNK[kind] then
                    local rel = pz - c.loc.Z
                    if rel > 0 and rel < TRUNK[kind] then dz = 0 else dz = pz - (c.loc.Z + lift) end
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

-- The sapling or tree the game's own prompt is on ("Ash Shoot - Destroy").
-- The camera ray of the over-the-shoulder view passes well beyond a shoot
-- at the player's feet; the prompt does not.
function World.PromptHost(me)
    for _, prompt in ipairs(U.live_of(PROMPT)) do
        if U.visible(prompt) then
            local actor = prop(prompt, "CurrentWorldActor")
            local loc = U.valid(actor) and U.location(actor) or nil
            if loc and U.dist2d(loc, me) <= REACH.tree then
                for _, n in ipairs(class_names(actor)) do
                    if n == "SaplingBase" then return sapling_info(actor) end
                    if n == "FellableTree" then return tree_info(actor) end
                end
            end
        end
    end
    return nil
end

-- The closest plant the player grew within a short reach. Pure.
function World.NearestPlanted(candidates, me, range)
    local best, bestD = nil, range
    for _, c in ipairs(candidates) do
        if c.kind == "plot" or c.planted then
            local d = U.dist2d(c.loc, me)
            if d <= bestD then best, bestD = c, d end
        end
    end
    return best
end

local AT_FEET = 300

function World.Aimed()
    local me = U.location(U.pawn())
    if not me then return nil end
    local eye, dir = World.Camera()
    if not eye then return nil end
    local near = World.Nearby(me, 1000)
    local best = World.Pick(near, eye, dir, me)
    -- Something the player grew wins: under the camera ray, under the game's
    -- prompt, or at their feet. Otherwise a crop the prompt names, then
    -- whatever the camera points at.
    if best and (best.kind == "plot" or best.planted) then return best end
    local host = World.PromptHost(me)
    if host and host.planted then return host end
    return World.PromptCrop(me) or best or World.NearestPlanted(near, me, AT_FEET)
end

-- The player's LoadoutComponent (on the controller or the pawn).
local function loadout()
    local names = { [U.full(U.pc())] = true, [U.full(U.pawn())] = true }
    for _, comp in ipairs(U.live_of("LoadoutComponent")) do
        local owner = nil
        pcall(function() owner = comp:GetOwner() end)
        if names[U.full(owner)] then return comp end
    end
    return nil
end

-- What the loadout holds in each slot. ELoadoutSlot runs Head .. FishingBait
-- (HeldRight 7, HeldLeft 8 in build 25632050); every slot is read so an
-- order change cannot hide the hands.
local LOADOUT_SLOTS = 10
local function loadout_items(comp)
    local out = {}
    for slot = 0, LOADOUT_SLOTS do
        local eq = nil
        pcall(function() eq = comp:GetEquipmentFromSlot(slot) end)
        if U.valid(eq) then
            local data = nil
            pcall(function() data = eq:BP_GetEquipmentData() end)
            out[#out + 1] = { slot = slot, eq = eq, data = U.valid(data) and data or nil,
                name = U.valid(data) and U.fname(data) or U.fname(eq) }
        end
    end
    return out
end

local function axe_from(item)
    local byName = Rules.AxePower(item.name)
    if not byName then return nil end
    local power, src = byName, "item name"
    local okP, base = pcall(function() return item.data:GetBasePowerLevel() end)
    if okP and tonumber(base) and tonumber(base) > 0 then power, src = tonumber(base), "GetBasePowerLevel" end
    return power, src
end

-- The axe in the player's hand: its power and item name.
local equipLogged = false
function World.HeldAxe()
    local pawn = U.pawn()
    if not pawn then return nil end
    local items, how = {}, nil
    local comp = loadout()
    if comp then
        items, how = loadout_items(comp), "LoadoutComponent"
    else
        local pawnName = U.full(pawn)
        for _, eq in ipairs(U.live_of("Equipment")) do
            local owner, parent = nil, nil
            pcall(function() owner = eq:GetOwner() end)
            pcall(function() parent = eq:GetAttachParentActor() end)
            if U.full(owner) == pawnName or U.full(parent) == pawnName then
                local data = nil
                pcall(function() data = eq:BP_GetEquipmentData() end)
                items[#items + 1] = { eq = eq, data = U.valid(data) and data or nil,
                    name = U.valid(data) and U.fname(data) or U.fname(eq) }
            end
        end
        how = "attached Equipment"
    end
    for _, item in ipairs(items) do
        local power, src = axe_from(item)
        if power then
            if not equipLogged then
                equipLogged = true
                U.log(string.format("Held axe read: %s, power %d (%s, %s slot %s)", item.name, power, src, how, tostring(item.slot)))
            end
            return power, item.name
        end
    end
    return nil
end

-- Developer dump: the player's loadout, slot by slot.
function World.DumpEquipment()
    local comp = loadout()
    if not comp then
        U.log(string.format("[splice] no LoadoutComponent owned by the player (%d live)", #U.live_of("LoadoutComponent")))
        return
    end
    U.log("[splice] loadout " .. U.full(comp))
    for _, item in ipairs(loadout_items(comp)) do
        U.log(string.format("[splice]   slot %d: %s", item.slot, item.name))
    end
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

-- A crop's vanilla BaseYield and HarvestXpFactor, read from its loaded
-- FarmPlantDataAsset ({ yield, factor }); nil fields fall back to Rules.
local cropValues = {}
function World.CropValues(species)
    if cropValues[species] then return cropValues[species] end
    local data = StaticFindObject("/Game/Gameplay/Farming/Plants/" .. species .. "." .. species)
    if not U.valid(data) then return nil end
    local v = { yield = tonumber(prop(data, "BaseYield")), factor = tonumber(prop(data, "HarvestXpFactor")) }
    U.log(string.format("%s vanilla BaseYield %s, HarvestXpFactor %s", species, tostring(v.yield), tostring(v.factor)))
    cropValues[species] = v
    return v
end

-- Vanilla Farming XP through the game's own
-- SkillComponent:AddXpFromEvent(XPEventRowHandle, ContextString, Multiplier,
-- bIgnoreModifier) with DT_XPEvents_Farming's Harvesting row (8 XP), so the
-- game's level-up runs as for any harvest. The skill's CurrentXp only shows
-- the grant a frame later (seen in game: 3272 stays 3272 straight after the
-- call, 3280 by the next pick). Returns the amount asked once the call went
-- through, nil when it could not be made.
local FARMING_ID = "PyUi-0LU_riFY46AnnFiWg"
local XP_TABLE = "/Game/Gameplay/Progress/XPEventTables/DT_XPEvents_Farming.DT_XPEvents_Farming"
local function farming_xp(sc)
    local xp = nil
    pcall(function()
        local arr = sc.Skills
        for i = 1, arr:GetArrayNum() do
            local e = arr[i]
            if e.SkillData.PersistenceID:ToString() == FARMING_ID then xp = e.CurrentXp break end
        end
    end)
    return tonumber(xp)
end

function World.AddFarmingXp(amount, context)
    if not amount or amount <= 0 then return 0 end
    local sc = prop(U.pc(), "SkillComponent")
    if not U.valid(sc) then return nil end
    local dt = StaticFindObject(XP_TABLE)
    if not U.valid(dt) and LoadAsset then
        local ok, loaded = pcall(LoadAsset, XP_TABLE)
        if ok then dt = loaded end
    end
    if not U.valid(dt) then
        U.log_once("noxptable", "DT_XPEvents_Farming not found; no Farming XP for picks")
        return nil
    end
    local before = farming_xp(sc)
    local ok, err = pcall(function()
        sc:AddXpFromEvent({ DataTable = dt, RowName = FName("Harvesting") }, context or "Horticulture", amount / Rules.HARVEST_XP_BASE, true)
    end)
    if not ok then
        U.log_once("addxp", "AddXpFromEvent failed: " .. tostring(err))
        return nil
    end
    U.log(string.format("Farming XP via AddXpFromEvent: +%d (Farming XP was %s)", amount, tostring(before)))
    return amount
end

-- True while the player is in plain gameplay: no build menu, inventory or
-- other menu (those show the mouse cursor).
function World.InGameplay()
    local pc = U.pc()
    if not pc then return false end
    return prop(pc, "bShowMouseCursor") ~= true
end

-- The actor the game's interaction prompt is on, or nil.
function World.PromptTarget()
    for _, prompt in ipairs(U.live_of(PROMPT)) do
        if U.visible(prompt) then
            local actor = prop(prompt, "CurrentWorldActor")
            if U.valid(actor) then return actor end
        end
    end
    return nil
end

-- Where the player stands (feet) and which way the camera faces (yaw).
function World.Facing()
    local pawn = U.pawn()
    local loc = U.location(pawn)
    if not loc then return nil end
    local half = 90
    pcall(function() half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    local yaw = 0
    pcall(function() yaw = U.pc():GetControlRotation().Yaw end)
    return { X = loc.X, Y = loc.Y, Z = loc.Z - half }, yaw
end

-- Ground height at x, y near nearZ (a short trace, so tree canopies above
-- are not hit); nearZ when nothing is hit.
function World.GroundAt(x, y, nearZ)
    local z = nil
    pcall(function()
        local ksl = UEHelpers.GetKismetSystemLibrary()
        local pawn = U.pawn()
        if not (U.valid(ksl) and pawn) then return end
        local hit, color = {}, { R = 0, G = 0, B = 0, A = 0 }
        if ksl:LineTraceSingle(pawn, { X = x, Y = y, Z = nearZ + 250 }, { X = x, Y = y, Z = nearZ - 400 },
            0, false, {}, 0, hit, true, color, color, 0.0) then
            pcall(function() z = hit.ImpactPoint.Z end)
            if not z then pcall(function() z = hit.Location.Z end) end
        end
    end)
    return z or nearZ
end

-- Which world save is loaded, so a Primelet set down in one world does not
-- appear in another. Read from the game state's WorldInfo (the world's id,
-- else its name), then world-save settings; "?" when none can be read (then
-- Primelets show in every world).
local WORLD_HOLDERS = { "GameStateBase", "GameInstance", "GameModeBase", "SpudSubsystem" }
local WORLD_FIELDS = { "WorldId", "WorldName", "SaveSlotName", "SlotName", "WorldSaveGuid" }
local worldKey, worldKeyFrom = nil, nil

local function text_of(v)
    local s = nil
    pcall(function() s = v:ToString() end)
    if s == nil and type(v) == "string" then s = v end
    if s == nil and type(v) == "number" then s = tostring(v) end
    if s == nil then
        pcall(function()
            if v.A ~= nil then s = string.format("%08x%08x%08x%08x", v.A % 2^32, v.B % 2^32, v.C % 2^32, v.D % 2^32) end
        end)
        if s == "00000000000000000000000000000000" then s = nil end
    end
    if s and s ~= "" and s ~= "None" then return s end
    return nil
end

local function world_from(obj, label)
    if not U.valid(obj) then return nil end
    local settings = prop(obj, "WorldSaveSettings")
    local info = prop(obj, "WorldInfo")
    for _, holder in ipairs({ info, settings, obj }) do
        if holder ~= nil then
            for _, f in ipairs(WORLD_FIELDS) do
                local v = nil
                pcall(function() v = holder[f] end)
                local s = v ~= nil and text_of(v) or nil
                if s then
                    local via = holder == info and ".WorldInfo." or holder == settings and ".WorldSaveSettings." or "."
                    return s, label .. via .. f
                end
            end
        end
    end
    return nil
end

function World.WorldKey()
    if worldKey then return worldKey end
    local key, from = nil, nil
    pcall(function()
        local gi = UEHelpers.GetGameInstance and UEHelpers.GetGameInstance()
        key, from = world_from(gi, "GameInstance")
    end)
    if not key then
        for _, cls in ipairs(WORLD_HOLDERS) do
            for _, obj in ipairs(U.live_of(cls)) do
                key, from = world_from(obj, U.fname(obj:GetClass()))
                if key then break end
            end
            if key then break end
        end
    end
    if key then
        worldKey, worldKeyFrom = (key:gsub("[|\r\n=]", "_")), from
        U.log("World key " .. worldKey .. " (" .. from .. ")")
        return worldKey
    end
    U.log_once("noworldkey", "World save name not readable; Primelets show in every world")
    return "?"
end

-- A new world is loading: read the key again.
function World.ResetWorldKey() worldKey, worldKeyFrom = nil, nil end

-- A server or single player: the only machines where v1 splicing runs.
function World.IsServer()
    local ok, yes = pcall(function()
        return UEHelpers.GetKismetSystemLibrary():IsServer(UEHelpers.GetWorld())
    end)
    if ok and yes ~= nil then return yes == true end
    return true
end

return World

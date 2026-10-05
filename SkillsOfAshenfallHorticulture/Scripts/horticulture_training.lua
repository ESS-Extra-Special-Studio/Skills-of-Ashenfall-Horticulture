-- Horticulture XP from real farming work.
--
-- Verified in build 25632050 (exe reflection names, /Script/Dominion):
--   PlayerController.FarmCommandComponent, with Server_TryPlantSeed(PlotID,
--   NetID, bIsPreferredPlotTier), Server_TryApplyWateringCharges(PlotID,
--   WaterIndex, Charges), Server_TryFertilizePlot, Server_TryHealDisease
--   (bUseCurePotion), Server_TryHarvestPlot(YieldMultiplier, bIsManual, Tool,
--   bCondenseYieldToOneItem), Server_TryTillPlot, Server_TryGrowWeedsToNextStage
--   FarmSlotComponent: GetPlotID, VisibleState (FarmPlotVisibleState:
--   PlantDataNetID, WateredIndex, PlotStage, GrowthStage, WateringProgress,
--   FertilizingProgress, TillingProgress)
--   EFarmPlotStage: Idle, Planted, Harvestable, Weeds, Diseased, Dead
--
-- XP is paid when a plot near the player actually changes state, so a failed
-- attempt pays nothing. VisibleState is the replicated state, so every
-- machine sees it. Where the farming RPC runs locally (single player and the
-- host), a change pays only if the local player's own FarmCommandComponent
-- asked for it in the last few seconds; another player's work pays them, not
-- the host. On a co-op guest the RPC runs on the host, so a guest is paid for
-- changes on plots within reach of their character.
local UEHelpers = require("UEHelpers")
local U = require("horticulture_util")

local Training = {}

-- Budget: docs/HORTICULTURE_1-25.md (Dragonwilds docs folder).
Training.XP = {
    plant = 30,
    water = 15,
    compost = 30,
    weed = 10,
    cure = 40,
    harvest = 70,
    firstPlant = 50,
    firstHarvest = 100,
}

local LABEL = {
    plant = "Seed sown",
    water = "Watered",
    compost = "Soil fed",
    weed = "Weeds cleared",
    cure = "Blight cured",
    harvest = "Crop harvested",
    firstPlant = "New crop sown",
    firstHarvest = "New crop catalogued",
}

local IDLE, PLANTED, HARVESTABLE, WEEDS, DISEASED = 0, 1, 2, 3, 4

local FUNCTIONS = {
    Server_TryPlantSeed = "plant",
    Server_TryApplyWateringCharges = "water",
    Server_TryFertilizePlot = "compost",
    Server_TryHealDisease = "cure",
    Server_TryHarvestPlot = "harvest",
    Server_TryTillPlot = "weed",
    Server_TryGrowWeedsToNextStage = "weed",
}
local COMPONENT = "/Script/Dominion.FarmCommandComponent"

local REACH = 800
local SCAN_RANGE = 3000
local ASK_WINDOW = 4.0

local cfg = nil
local slots = {}
local lastScan = -100
local snap = {}
local planting = {}
local asked = {}
local hooksOk = false
local hookFired = false
local unconfirmed = 0
local forceProximity = false
local serverCache = nil

local function now() return os.clock() end

local function is_server()
    if serverCache ~= nil then return serverCache end
    local ok, yes = pcall(function()
        return UEHelpers.GetKismetSystemLibrary():IsServer(UEHelpers.GetWorld())
    end)
    if ok and yes ~= nil then serverCache = yes == true end
    return serverCache ~= false
end

local function local_farm_component()
    local pc = U.pc()
    if not pc then return nil end
    local comp = nil
    pcall(function() comp = pc.FarmCommandComponent end)
    return U.valid(comp) and comp or nil
end

local hookTries = 0
local function register_hooks()
    if hooksOk or not RegisterHook then return end
    hookTries = hookTries + 1
    if hookTries == 10 then
        U.log("Farming functions not found at " .. COMPONENT .. "; paying for plot changes within reach instead")
    end
    local n = 0
    for fn, kind in pairs(FUNCTIONS) do
        local path = COMPONENT .. ":" .. fn
        if U.valid(StaticFindObject(path)) then
            local ok = pcall(RegisterHook, path, function(ctx)
                local mine = false
                pcall(function() mine = U.full(ctx:get()) == U.full(local_farm_component()) end)
                if mine then
                    asked[kind] = now()
                    if not hookFired then
                        hookFired = true
                        U.log("Farming hooks confirmed (" .. fn .. ")")
                    end
                end
            end)
            if ok then n = n + 1 end
        end
    end
    if n > 0 then
        hooksOk = true
        U.log("Farming hooks registered: " .. n .. " of 7")
    end
end

local function slot_location(slot)
    local ok, v = pcall(function()
        local l = slot:K2_GetComponentLocation()
        return { X = l.X, Y = l.Y, Z = l.Z }
    end)
    if ok and v then return v end
    local okO, owner = pcall(function() return slot:GetOwner() end)
    if okO then return U.location(owner) end
    return nil
end

local function read_state(slot)
    local ok, st = pcall(function()
        local v = slot.VisibleState
        return {
            stage = tonumber(v.PlotStage),
            growth = tonumber(v.GrowthStage),
            water = tonumber(v.WateringProgress) or 0,
            fert = tonumber(v.FertilizingProgress) or 0,
            net = tonumber(v.PlantDataNetID),
        }
    end)
    if ok and st and st.stage then return st end
    U.log_once("nostate", "Farm plot state could not be read (" .. tostring(st) .. "); Horticulture XP from farming is off")
    return nil
end

local function rescan(me)
    local list = {}
    for _, slot in ipairs(U.live_of("FarmSlotComponent")) do
        local loc = slot_location(slot)
        if loc and U.dist(loc, me) <= SCAN_RANGE then
            list[#list + 1] = { obj = slot, key = U.full(slot), loc = loc }
        end
    end
    slots = list
    lastScan = now()
end

local function credited(kind, loc, me)
    if U.dist(loc, me) > REACH then return false end
    if hooksOk and is_server() and not forceProximity then
        local t = asked[kind]
        if t and now() - t <= ASK_WINDOW then
            asked[kind] = nil
            return true
        end
        if not hookFired then
            unconfirmed = unconfirmed + 1
            if unconfirmed >= 3 then
                forceProximity = true
                U.log("Farming hooks never fired; paying for plot changes within reach instead")
                return true
            end
        end
        return false
    end
    return true
end

local function award(kind, id, extra)
    local ESL, SKILL = cfg.ESL, cfg.SKILL
    local gain = ESL.Award(SKILL, id, Training.XP[kind], LABEL[kind])
    if gain and cfg.dev then U.log("XP " .. kind .. " +" .. gain .. " (" .. id .. ")") end
    if extra then
        local g2 = ESL.Award(SKILL, extra.id, Training.XP[extra.kind], LABEL[extra.kind])
        if g2 and cfg.dev then U.log("XP " .. extra.kind .. " +" .. g2 .. " (" .. extra.id .. ")") end
    end
end

-- Compares a plot's state with the last reading and pays for what the
-- player did to it.
local function compare(slot, old, cur, me, rain)
    local key = U.hash(slot.key)
    local stamp = tostring(os.time())
    local function pay(kind, id, extra)
        if credited(kind, slot.loc, me) then award(kind, id, extra) end
    end

    if cur.stage == PLANTED and (old.stage == IDLE or old.stage == WEEDS) then
        planting[slot.key] = stamp
        pay("plant", "plant:" .. key .. ":" .. stamp,
            cur.net and { kind = "firstPlant", id = "firstplant:" .. cur.net } or nil)
    elseif old.stage == WEEDS and cur.stage == IDLE then
        pay("weed", "weed:" .. key .. ":" .. stamp)
    elseif old.stage == DISEASED and cur.stage == PLANTED then
        pay("cure", "cure:" .. key .. ":" .. stamp)
    elseif old.stage == HARVESTABLE and cur.stage ~= HARVESTABLE and cur.stage ~= 5 then
        pay("harvest", "harvest:" .. key .. ":" .. stamp,
            old.net and { kind = "firstHarvest", id = "firstharvest:" .. old.net } or nil)
        planting[slot.key] = nil
    end

    local serial = planting[slot.key] or "s"
    if cur.water > old.water + 0.001 and cur.stage ~= IDLE and not rain then
        pay("water", "water:" .. key .. ":" .. serial .. ":" .. tostring(cur.growth or 0))
    end
    if cur.fert > old.fert + 0.001 then
        pay("compost", "compost:" .. key .. ":" .. serial)
    end
end

local function tick()
    if not (cfg.ESL.Character() and U.pc()) then
        snap, slots, serverCache = {}, {}, nil
        return
    end
    local me = U.location(U.pawn())
    if not me then return end
    if now() - lastScan > 5 then rescan(me) end
    local unlocked = cfg.ESL.IsUnlocked(cfg.SKILL)
    local seen, changes, watered = {}, {}, 0
    for _, slot in ipairs(slots) do
        if U.valid(slot.obj) then
            seen[slot.key] = true
            local cur = read_state(slot.obj)
            if not cur then return end
            local old = snap[slot.key]
            snap[slot.key] = cur
            if old then
                changes[#changes + 1] = { slot = slot, old = old, cur = cur }
                if cur.water > old.water + 0.001 then watered = watered + 1 end
            end
        end
    end
    -- Rain waters every plot at once and pays no Farming XP. Only matters
    -- when paying by reach; the hooks never fire for rain.
    local rain = watered >= 3 and not (hooksOk and is_server() and not forceProximity)
    if unlocked then
        for _, c in ipairs(changes) do compare(c.slot, c.old, c.cur, me, rain) end
    end
    for k in pairs(snap) do
        if not seen[k] then snap[k] = nil end
    end
end

function Training.Start(config)
    cfg = config
    U.every(3000, "Farming hooks", function()
        if not hooksOk then U.game(register_hooks) end
    end)
    U.every(500, "Farming check", function() U.game(tick) end)
end

-- For the dev dump.
function Training.Status()
    return string.format("hooks %s, fired %s, server %s, proximity %s, plots in range %d",
        tostring(hooksOk), tostring(hookFired), tostring(is_server()), tostring(forceProximity), #slots)
end

function Training.Slots() return slots end

return Training

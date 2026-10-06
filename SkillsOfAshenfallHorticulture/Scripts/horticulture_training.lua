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
local Crops = require("horticulture_crops")
local Prize = require("horticulture_prize")

local Training = {}

-- Splicing is the main source of Horticulture XP; ordinary farming pays
-- about a third of the 1.0 farming-only rates so a plot round still trains a
-- little. Budget: tools\budget_sim.py and
-- docs/HORTICULTURE_SPLICING_REDESIGN.md (Dragonwilds docs folder).
Training.XP = {
    plant = 10,
    water = 5,
    compost = 10,
    weed = 3,
    cure = 13,
    harvest = 23,
    firstPlant = 17,
    firstHarvest = 33,
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
    local ok, st = pcall(Crops.PlotState, slot)
    if ok and st and st.stage then return st end
    U.log_once("nostate", "A farm plot's state could not be read (" .. tostring(st) .. "); that plot pays no Horticulture XP")
    return nil
end

local function rescan(me)
    local list = {}
    for _, slot in ipairs(U.live_of("FarmSlotComponent")) do
        local loc = Crops.Placed(slot) and slot_location(slot)
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

-- Repeatable work goes through ESL.AddXp, so nothing piles up in the save.
-- ESL builds without it fall back to one-off awards under a unique id.
local function repeatable(kind, id)
    local ESL, SKILL = cfg.ESL, cfg.SKILL
    if ESL.AddXp then return ESL.AddXp(SKILL, Training.XP[kind], LABEL[kind]) end
    return ESL.Award(SKILL, id, Training.XP[kind], LABEL[kind])
end

-- The Vanilla Plants section of the Discovery Catalogue: the first harvest
-- of each kind of crop.
local function catalogue(net)
    local ESL, SKILL = cfg.ESL, cfg.SKILL
    local key, name = Crops.Key(net)
    local gain = ESL.Award(SKILL, "firstharvest:" .. key, Training.XP.firstHarvest, LABEL.firstHarvest .. ": " .. name)
    if not gain then return end
    if ESL.ShowCard and not cfg.quiet then
        ESL.ShowCard(SKILL, "VANILLA PLANTS", name,
            string.format("%d of %d crops catalogued", Training.CatalogueCount(), Crops.TOTAL))
    end
end

local function first_sowing(net)
    local key, name = Crops.Key(net)
    return cfg.ESL.Award(cfg.SKILL, "firstplant:" .. key, Training.XP.firstPlant, LABEL.firstPlant .. ": " .. name)
end

local function award(kind, id, net)
    local gain = repeatable(kind, id)
    if gain and (cfg.dev or cfg.debug) then U.log("XP " .. kind .. " +" .. gain) end
    if net and kind == "plant" then first_sowing(net) end
    if net and kind == "harvest" then catalogue(net) end
end

-- Compares a plot's state with the last reading and pays for what the
-- player did to it.
local function compare(slot, old, cur, me, rain)
    local key = U.hash(slot.key)
    local stamp = tostring(os.time())
    local function pay(kind, id, net)
        if credited(kind, slot.loc, me) then
            award(kind, id, net)
            return true
        end
        return false
    end

    if cur.stage == PLANTED and (old.stage == IDLE or old.stage == WEEDS) then
        planting[slot.key] = { serial = stamp, tended = {} }
        pay("plant", "plant:" .. key .. ":" .. stamp, cur.net)
    elseif old.stage == WEEDS and cur.stage == IDLE then
        pay("weed", "weed:" .. key .. ":" .. stamp)
    elseif old.stage == DISEASED and cur.stage == PLANTED then
        pay("cure", "cure:" .. key .. ":" .. stamp)
    elseif old.stage == HARVESTABLE and cur.stage ~= HARVESTABLE and cur.stage ~= 5 then
        pay("harvest", "harvest:" .. key .. ":" .. stamp, old.net)
        planting[slot.key] = nil
        Prize.Clear(slot)
    end

    -- Watering pays once per growth stage of a planting, composting once
    -- per planting; the unique ids matter only to the Award fallback.
    if not planting[slot.key] and cur.stage ~= IDLE and cur.stage ~= WEEDS then
        planting[slot.key] = { serial = "s" .. stamp, tended = {} }
    end
    local p = planting[slot.key]
    local serial = p and p.serial or "s"
    local stage = "w" .. tostring(cur.growth or 0)
    if cur.water > old.water + 0.001 and cur.stage ~= IDLE and not rain and not (p and p.tended[stage]) then
        if pay("water", "water:" .. key .. ":" .. serial .. ":" .. stage) and p then p.tended[stage] = true end
    end
    if cur.fert > old.fert + 0.001 and not (p and p.tended.fed) then
        if pay("compost", "compost:" .. key .. ":" .. serial) and p then p.tended.fed = true end
    end

    if cur.stage == HARVESTABLE and p and p.tended.fed then
        local days = 0
        for k in pairs(p.tended) do
            if k:sub(1, 1) == "w" then days = days + 1 end
        end
        if days >= 2 then Prize.Apply(slot) end
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
            if cur then
                local old = snap[slot.key]
                snap[slot.key] = cur
                if old then
                    changes[#changes + 1] = { slot = slot, old = old, cur = cur }
                    if cur.water > old.water + 0.001 then watered = watered + 1 end
                end
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

-- Catalogue keys of the crops this character has harvested, in order.
function Training.Catalogue()
    local list = {}
    for _, id in ipairs(cfg.ESL.Paid(cfg.SKILL) or {}) do
        local key = tostring(id):match("^firstharvest:(.+)$")
        if key then list[#list + 1] = key end
    end
    return list
end

function Training.CatalogueCount() return #Training.Catalogue() end

-- One line for the status display.
function Training.CatalogueLine()
    local names = {}
    for _, key in ipairs(Training.Catalogue()) do names[#names + 1] = Crops.NameOf(key) end
    if #names == 0 then return "Vanilla Plants: no crops yet" end
    return string.format("Vanilla Plants %d/%d: %s", #names, Crops.TOTAL, table.concat(names, ", "))
end

-- For the dev dump.
function Training.Status()
    return string.format("hooks %s, fired %s, server %s, proximity %s, plots in range %d",
        tostring(hooksOk), tostring(hookFired), tostring(is_server()), tostring(forceProximity), #slots)
end

function Training.Slots() return slots end

return Training

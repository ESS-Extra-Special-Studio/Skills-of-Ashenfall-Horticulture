-- Names the crop on a plot from its PlantDataNetID.
--
-- Verified in build 25632050: FarmPlotVisibleState.PlantDataNetID; the
-- native DominionDataSubsystem (Core\DominionDataSubsystem.h) holds
-- NetIdToData and DataToNetIdMap and has GetNetIdForData, GetNetIdsForDatas
-- and GetDatasForNetIds; FarmPlantDataAsset.DisplayName (Text). Shipped crop
-- assets: 24 FPD_* under /Game/Gameplay/Farming/Plants (FPD_Weeds excluded).
-- Not verified: whether those functions and the map can be called or read
-- from Lua. Each way is tried in turn; the log names the one that works.
local U = require("horticulture_util")

local Crops = {}

Crops.TOTAL = 24

local cache = {}
local method = nil

local function subsystem()
    local s = nil
    pcall(function() s = FindFirstOf("DominionDataSubsystem") end)
    return U.valid(s) and s or nil
end

local function describe(data)
    if not U.valid(data) then return nil end
    local key = U.fname(data)
    local name = nil
    pcall(function() name = data.DisplayName:ToString() end)
    if not name or name == "" then name = (key:gsub("^FPD_", ""):gsub("_", " ")) end
    return { key = key, name = name }
end

local function is_plant(data)
    local ok, yes = pcall(function()
        return data:GetClass():GetFName():ToString():find("FarmPlantData", 1, true) ~= nil
    end)
    return ok and yes
end

-- The map, if UE4SS can walk it.
local function from_map(sub, net)
    local found = nil
    pcall(function()
        sub.NetIdToData:ForEach(function(k, v)
            local id = tonumber(k:get())
            local data = v:get()
            if id and U.valid(data) and is_plant(data) then
                cache[id] = cache[id] or describe(data)
                if id == net then found = cache[id] end
            end
        end)
    end)
    return found
end

-- Every loaded plant asset, asking the subsystem for its id.
local function from_reverse(sub, net)
    local found = nil
    for _, data in ipairs(U.live_of("FarmPlantDataAsset")) do
        local ok, id = pcall(function() return sub:GetNetIdForData(data) end)
        id = ok and tonumber(type(id) == "table" and id.Value or id) or nil
        if id then
            cache[id] = cache[id] or describe(data)
            if id == net then found = cache[id] end
        end
    end
    return found
end

function Crops.Resolve(net)
    net = tonumber(net)
    if not net or net <= 0 then return nil end
    if cache[net] then return cache[net] end
    local sub = subsystem()
    if not sub then return nil end
    local ways = { map = from_map, reverse = from_reverse }
    if method then
        local hit = ways[method](sub, net)
        if hit then return hit end
    end
    for name, fn in pairs(ways) do
        if name ~= method then
            local hit = fn(sub, net)
            if hit then
                if method ~= name then U.log("Crop names read through the data subsystem (" .. name .. ")") end
                method = name
                return hit
            end
        end
    end
    U.log_once("crop" .. net, "No crop name for plant id " .. net .. "; it is catalogued by id")
    return nil
end

-- Build 25632050 and later keep the plot state natively: FarmSlotComponent
-- has no VisibleState property. What Lua can still read is the slot's
-- PlantMeshComponent.StaticMesh, GetSoilState, CanHarvest, CanHealDisease,
-- IsFullyWatered and IsFullyFertilized, and each FarmPlantDataAsset's
-- Stages[i].Healthy/Diseased/Dead.Mesh. The mesh names the crop and stage.
local byMesh, byKey = {}, {}
local meshBuilt, meshAssets = -100, -1

local function index_meshes()
    local t = os.clock()
    local assets = U.live_of("FarmPlantDataAsset")
    if #assets == meshAssets and t - meshBuilt < 30 then return end
    meshBuilt, meshAssets = t, #assets
    for _, data in ipairs(assets) do
        local info = describe(data)
        if info then
            byKey[info.key] = info
            pcall(function()
                local list = {}
                data.Stages:ForEach(function(_, elem) list[#list + 1] = elem:get() end)
                for i, st in ipairs(list) do
                    for _, cond in ipairs({ "Healthy", "Diseased", "Dead" }) do
                        pcall(function()
                            local mesh = st[cond].Mesh
                            if U.valid(mesh) then
                                local name = U.fname(mesh)
                                byMesh[name] = byMesh[name] or { key = info.key, stage = i, cond = cond }
                            end
                        end)
                    end
                end
            end)
        end
    end
end

local function call(obj, fn)
    local ok, v = pcall(function() return obj[fn](obj) end)
    if ok then return v end
    return nil
end

local IDLE, PLANTED, HARVESTABLE, WEEDS, DISEASED, DEAD = 0, 1, 2, 3, 4, 5

local function from_mesh(slot)
    local plant = nil
    pcall(function() plant = slot.PlantMeshComponent end)
    if not U.valid(plant) then return nil end
    local visible = call(plant, "IsVisible") == true
    local name = nil
    pcall(function() name = U.fname(plant.StaticMesh) end)
    local st = {
        water = call(slot, "IsFullyWatered") == true and 1 or 0,
        fert = call(slot, "IsFullyFertilized") == true and 1 or 0,
    }
    if not visible or not name or name == "" then
        st.stage = IDLE
        return st
    end
    local hit = byMesh[name]
    if not hit then
        index_meshes()
        hit = byMesh[name]
    end
    if not hit and name:lower():find("weed", 1, true) then hit = { key = "FPD_Weeds", stage = 1 } end
    if not hit then
        U.log_once("mesh" .. name, "Plot mesh " .. name .. " matches no crop; that plot is skipped")
        return nil
    end
    if hit.key == "FPD_Weeds" then
        st.stage = WEEDS
        return st
    end
    st.net, st.growth = hit.key, hit.stage - 1
    if hit.cond == "Dead" then
        st.stage = DEAD
    elseif call(slot, "CanHealDisease") == true or hit.cond == "Diseased" then
        st.stage = DISEASED
    elseif call(slot, "CanHarvest") == true then
        st.stage = HARVESTABLE
    else
        st.stage = PLANTED
    end
    return st
end

local stateWay = nil

-- False for a plot still on the build cursor (BuildingPiece bIsPreview or
-- bIsGhosted), and for a slot whose owner is gone: leaving build mode
-- leaves the preview's slot behind for a moment, and reading its plant mesh
-- crashed the game (UE4SS.dll+0x2ace27). Neither is a host or a source.
function Crops.Placed(slot)
    if not U.valid(slot) then return false end
    local owner = nil
    local asked = pcall(function() owner = slot:GetOwner() end)
    if asked and not U.valid(owner) then return false end
    if not asked then return true end
    local preview, ghost = false, false
    pcall(function() preview = owner.bIsPreview == true end)
    pcall(function() ghost = owner.bIsGhosted == true end)
    return not (preview or ghost)
end

-- { stage (EFarmPlotStage), growth, water, fert, net } or nil. net is the
-- network id when VisibleState is readable, else the FPD_ asset name.
function Crops.PlotState(slot)
    if not Crops.Placed(slot) then return nil end
    if stateWay ~= "mesh" then
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
        if ok and st and st.stage then
            if stateWay ~= "visible" then U.log("Plot state read from VisibleState") end
            stateWay = "visible"
            return st
        end
    end
    local st = from_mesh(slot)
    if st and stateWay ~= "mesh" then
        U.log("Plot state read from the plant mesh and slot functions")
        stateWay = "mesh"
    end
    return st
end

-- A stable catalogue key: the asset name when known, else the network id.
function Crops.Key(net)
    if type(net) == "string" and net:find("^FPD_") then return net, Crops.NameOf(net) end
    local c = Crops.Resolve(net)
    if c then return c.key, c.name end
    return "net" .. tostring(net), "an unnamed crop"
end

function Crops.Method() return method end

-- Display names for catalogue keys when the asset is not loaded.
local NAMES = {
    FPD_SnapDragon = "Snapdragon", FPD_CorpseCotton = "Corpse cotton", FPD_SwampWeed = "Swamp weed",
    FPD_Weed_Desert = "Desert weed", FPD_Cactus_Barrel = "Barrel cactus", FPD_Cactus_Bunny = "Bunny cactus",
    FPD_Cactus_Pipe = "Fibrous pipe cactus",
}

function Crops.NameOf(key)
    if byKey[key] then return byKey[key].name end
    for _, c in pairs(cache) do
        if c.key == key then return c.name end
    end
    if NAMES[key] then return NAMES[key] end
    if key:find("^net") then return "Unnamed crop" end
    return (key:gsub("^FPD_", ""):gsub("_", " "))
end

return Crops

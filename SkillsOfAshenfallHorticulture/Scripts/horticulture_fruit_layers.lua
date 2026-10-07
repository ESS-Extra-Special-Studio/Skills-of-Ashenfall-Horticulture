-- Baked fruit layers: one mesh per host tree shape and produce, made by the
-- DragonwildsAssets pipeline with the host's own foliage material wind, so
-- the fruit sways exactly with the branches. Shipped in SoAHorticulture_P;
-- listed in Scripts\placements\hort_fruit_layers_vNNN.lua:
--
--   return {
--     schema = "ess.fruit_layers/1",
--     layers = {
--       { host = "/Game/.../SM_Ash_Tree_01",          -- host mesh key
--         produce = "FPD_Redberry",                    -- scion id (generic combos)
--         -- or hybrid = "TuberwoodAsh",              -- one hybrid (wins over produce)
--         asset = "/Game/Mods/SoAHorticulture/FruitLayers/SM_FL_Ash01_Redberry.SM_FL_Ash01_Redberry",
--         cull_distance_cm = 9000,                     -- optional
--         material_overrides = { ... },                -- optional, as in placement data
--       },
--     },
--   }
--
-- The layer is placed at the host mesh component's exact transform. Pure
-- Lua: no engine objects are held here.
local F = {}

F.ID = "hort_fruit_layers"
F.SCHEMA = "ess.fruit_layers/1"
F.MAX_VERSION = 99

local data = nil

local function asset(path)
    if path:find(".", 1, true) then return path end
    return path .. "." .. path:match("([^/]+)$")
end

-- Reads the newest manifest in folder. True when one loads.
function F.Load(folder)
    data = false
    for v = F.MAX_VERSION, 1, -1 do
        local file = string.format("%s_v%03d", F.ID, v)
        local chunk = loadfile(folder .. "\\" .. file .. ".lua") or loadfile(folder .. "/" .. file .. ".lua")
        if chunk then
            local ok, t = pcall(chunk)
            if ok and type(t) == "table" and t.schema == F.SCHEMA and type(t.layers) == "table" then
                F.Set(t, file)
                return true
            end
        end
    end
    return false
end

-- Installs a manifest table directly (tests).
function F.Set(t, file)
    data = { byHybrid = {}, byProduce = {}, file = file, count = 0 }
    for _, e in ipairs(t and t.layers or {}) do
        if type(e) == "table" and type(e.host) == "string" and type(e.asset) == "string" and (e.hybrid or e.produce) then
            local layer = { host = e.host, asset = asset(e.asset), cull = e.cull_distance_cm, overrides = e.material_overrides }
            if e.hybrid then data.byHybrid[e.host .. "|" .. tostring(e.hybrid)] = layer
            else data.byProduce[e.host .. "|" .. tostring(e.produce)] = layer end
            data.count = data.count + 1
        end
    end
end

function F.Loaded() return data and data.count > 0 or false end
function F.File() return data and data.file or nil end
function F.Count() return data and data.count or 0 end

-- The layer for this host mesh and hybrid (or scion's produce), or nil.
function F.Find(hostKey, hybridId, scion)
    if not (data and hostKey) then return nil end
    return (hybridId and data.byHybrid[hostKey .. "|" .. tostring(hybridId)])
        or (scion and data.byProduce[hostKey .. "|" .. tostring(scion)])
        or nil
end

return F

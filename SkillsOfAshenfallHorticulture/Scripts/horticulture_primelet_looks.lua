-- Brassica Primelet / Mini Brassica Prime looks from placement data
-- (placements/hort_plant_brassica_primelet/hort_plant_brassica_primelet_vNNN.lua).
-- Pure Lua 5.4, no game calls; the game side is Looks.place / spawn.
--
--   local P = require("primelet_looks")
--   P.Load(folder)                                   -- newest version in folder
--   local pieces = P.Pieces("primeling", "grumpy", havePak)
--   -- { {path, x, y, z, pitch, yaw, roll, scale, scaleY, scaleZ, group}, ... } relative to the pivot,
--   -- exactly what horticulture_looks.lua's place(world, b, loc, yaw, pieces) takes.
--   local yaw = P.FaceYaw(pivot, target)             -- turn-to-face (degrees)
--   local dz, sz = P.Bob(t, "primeling", phase)       -- optional idle: body z offset (cm), Z scale factor
local P = {}

P.ID = "hort_plant_brassica_primelet"
P.MAX_VERSION = 50

local data, file = nil, nil
local atan2 = math.atan2 or math.atan

local function try(folder, f)
    local chunk = loadfile(folder .. "\\" .. f .. ".lua") or loadfile(folder .. "/" .. f .. ".lua")
    if not chunk then return nil end
    local ok, t = pcall(chunk)
    if ok and type(t) == "table" and t.schema == "ess.primelet_looks/1" then return t end
    return nil
end

function P.Load(folder)
    data, file = nil, nil
    for v = P.MAX_VERSION, 1, -1 do
        local f = string.format("%s_v%03d", P.ID, v)
        local t = try(folder, f)
        if t then data, file = t, f return true end
    end
    return false
end

function P.Loaded() return data ~= nil end
function P.File() return file end
function P.Data() return data end

-- "/Game/X/SM_Y" -> "/Game/X/SM_Y.SM_Y" (Looks' load() and GetAsset want object paths).
function P.ObjectPath(pkg)
    if pkg:find("%.") then return pkg end
    return pkg .. "." .. pkg:match("([^/]+)$")
end

-- Stage keys follow horticulture_primelet.lua (sprout, primelet, primeling).
function P.Stage(stageKey) return data and data.stages[stageKey] or nil end

-- Pieces for one stage and personality. Without the pak, the face, crown and
-- Mini body (requires_pak) are left out: the vanilla cabbage and pot still show.
-- With the pak, no_pak_only pieces (the Mini's vanilla cabbage) are left out.
function P.Pieces(stageKey, personality, havePak)
    if not data then return nil end
    local byStage = data.looks[stageKey]
    if not byStage then return nil end
    local list = byStage[personality] or byStage[data.personalities[1]]
    local out = {}
    for _, a in ipairs(list) do
        if (havePak and not a.no_pak_only) or (not havePak and not a.requires_pak) then
            out[#out + 1] = {
                path = P.ObjectPath(a.mesh), group = a.group, name = a.name,
                x = a.location[1], y = a.location[2], z = a.location[3],
                pitch = a.rotation[1], yaw = a.rotation[2], roll = a.rotation[3],
                scale = a.scale[1], scaleY = a.scale[2], scaleZ = a.scale[3],
            }
        end
    end
    return out
end

-- Yaw (degrees) that turns the face (+X) from pivot towards target; both {X, Y}.
function P.FaceYaw(pivot, target)
    return math.deg(atan2(target.Y - pivot.Y, target.X - pivot.X))
end

-- Optional idle bob at time t (seconds): z offset in cm for "body" pieces and a
-- Z scale factor; phase (seconds) keeps a group out of sync. The pot never moves.
function P.Bob(t, stageKey, phase)
    if not data or not data.idle then return 0, 1 end
    local st = data.stages[stageKey]
    local s = st and st.cabbage_scale or 1
    local w = math.sin(2 * math.pi * ((t + (phase or 0)) / data.idle.period_s))
    return data.idle.bob_cm * s * w, 1 + data.idle.squash * w
end

function P.Bobs(group)
    if not data or not data.idle then return false end
    for _, g in ipairs(data.idle.groups) do if g == group then return true end end
    return false
end

return P

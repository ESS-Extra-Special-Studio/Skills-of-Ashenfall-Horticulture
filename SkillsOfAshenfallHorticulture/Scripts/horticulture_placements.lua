-- Flagship hybrid looks from the asset pipeline's placement data
-- (ess.hybrid_placement/1, DragonwildsAssets/placements/<id>/<id>_vNNN.lua,
-- copied into Scripts\placements unchanged). Each file maps every vanilla
-- host mesh to a shape, and each shape lists vanilla meshes with a transform
-- relative to the host mesh's pivot: an ash tree bearing potatoes, an oak
-- hung with cabbages. Pure Lua: no game calls, so it is tested offline.
local Placements = {}

-- Hybrid id -> versioned placement file. A new pipeline version is a new
-- file here; the old one can stay until the new one is checked in game.
Placements.FILES = {
    TuberwoodAsh = "hort_plant_tuberwood_ash_v006",
    BrassicaOak = "hort_plant_brassica_oak_v001",
    SheafAsh = "hort_plant_sheaf_ash_v001",
    Brassitato = "hort_plant_brassitato_v001",
    WeepingOak = "hort_plant_weeping_oak_v001",
}

-- Groups dropped first when a shape has more pieces than the cap.
Placements.THIN_FIRST = { "ground_fruit", "canopy_stem" }

-- Groups recoloured with a Looks tint name, per hybrid. Empty: the tint
-- parameters had no visible effect on the willow canopy in game.
Placements.GROUP_TINT = {}

local cache = {}

-- data for a hybrid, read once from dir\placements\<file>.lua; nil (and a
-- reason) when the hybrid has no data or the file is missing or bad.
function Placements.Load(dir, hybridId)
    local file = Placements.FILES[hybridId]
    if not file then return nil, "no placement data" end
    if cache[file] ~= nil then return cache[file] or nil, cache[file] and nil or "unreadable" end
    local chunk = loadfile(dir .. "\\placements\\" .. file .. ".lua") or loadfile(dir .. "/placements/" .. file .. ".lua")
    local ok, data = false, nil
    if chunk then ok, data = pcall(chunk) end
    if not ok or type(data) ~= "table" or data.schema ~= "ess.hybrid_placement/1" or type(data.shapes) ~= "table" then
        cache[file] = false
        return nil, "unreadable"
    end
    cache[file] = data
    return data
end

function Placements.Reset() cache = {} end

-- "/Game/.../SM_Ash_Tree_01" from a full or path name
-- ("StaticMesh /Game/.../SM_Ash_Tree_01.SM_Ash_Tree_01").
function Placements.HostKey(name)
    if type(name) ~= "string" then return nil end
    local path = name:match("(/[%w_/%-]+)") 
    return path
end

-- The shape for a host mesh, or nil when the data does not cover it.
function Placements.Shape(data, hostKey)
    local name = hostKey and data.hosts and data.hosts[hostKey]
    local shape = name and data.shapes[name]
    return shape, name
end

local function asset(path)
    if path:find(".", 1, true) then return path end
    return path .. "." .. path:match("([^/]+)$")
end

-- The pieces to place: { path, x, y, z, pitch, yaw, roll, scale, scaleY,
-- scaleZ, group } relative to the host pivot. requires_pak pieces are
-- skipped without the pak; above cap, THIN_FIRST groups go first, then an
-- even stride through the rest (whole clusters stay mostly whole).
function Placements.Pieces(shape, opts)
    opts = opts or {}
    local list = {}
    for _, a in ipairs(shape.attachments or {}) do
        if opts.havePak or not a.requires_pak then list[#list + 1] = a end
    end
    local cap = opts.cap
    if cap and #list > cap then
        for _, group in ipairs(Placements.THIN_FIRST) do
            if #list <= cap then break end
            local kept = {}
            for _, a in ipairs(list) do if a.group ~= group then kept[#kept + 1] = a end end
            list = kept
        end
        if #list > cap then
            local kept, step = {}, #list / cap
            for i = 1, cap do kept[i] = list[math.floor((i - 1) * step) + 1] end
            list = kept
        end
    end
    local out = {}
    for _, a in ipairs(list) do
        local l, r, s = a.location or {}, a.rotation or {}, a.scale or {}
        out[#out + 1] = {
            path = asset(a.mesh), x = l[1] or 0, y = l[2] or 0, z = l[3] or 0,
            pitch = r[1] or 0, yaw = r[2] or 0, roll = r[3] or 0,
            scale = s[1] or 1, scaleY = s[2] or s[1] or 1, scaleZ = s[3] or s[1] or 1,
            group = a.group,
        }
    end
    return out
end

-- Rotation maths in Unreal's conventions (FRotator degrees, FQuat).
function Placements.Quat(pitch, yaw, roll)
    local d = math.pi / 360
    local sp, cp = math.sin(pitch * d), math.cos(pitch * d)
    local sy, cy = math.sin(yaw * d), math.cos(yaw * d)
    local sr, cr = math.sin(roll * d), math.cos(roll * d)
    return {
        X = cr * sp * sy - sr * cp * cy,
        Y = -cr * sp * cy - sr * cp * sy,
        Z = cr * cp * sy - sr * sp * cy,
        W = cr * cp * cy + sr * sp * sy,
    }
end

function Placements.QuatMul(a, b)
    return {
        X = a.W * b.X + a.X * b.W + a.Y * b.Z - a.Z * b.Y,
        Y = a.W * b.Y - a.X * b.Z + a.Y * b.W + a.Z * b.X,
        Z = a.W * b.Z + a.X * b.Y - a.Y * b.X + a.Z * b.W,
        W = a.W * b.W - a.X * b.X - a.Y * b.Y - a.Z * b.Z,
    }
end

function Placements.Rotate(q, v)
    local ux, uy, uz = q.X, q.Y, q.Z
    local tx = 2 * (uy * v.Z - uz * v.Y)
    local ty = 2 * (uz * v.X - ux * v.Z)
    local tz = 2 * (ux * v.Y - uy * v.X)
    return {
        X = v.X + q.W * tx + (uy * tz - uz * ty),
        Y = v.Y + q.W * ty + (uz * tx - ux * tz),
        Z = v.Z + q.W * tz + (ux * ty - uy * tx),
    }
end

function Placements.Rotator(q)
    local singularity = q.Z * q.X - q.W * q.Y
    local yawY = 2 * (q.W * q.Z + q.X * q.Y)
    local yawX = 1 - 2 * (q.Y * q.Y + q.Z * q.Z)
    local r2d = 180 / math.pi
    local yaw = math.atan(yawY, yawX) * r2d
    if singularity < -0.4999995 then
        return { Pitch = -90, Yaw = yaw, Roll = -yaw - 2 * math.atan(q.X, q.W) * r2d }
    elseif singularity > 0.4999995 then
        return { Pitch = 90, Yaw = yaw, Roll = yaw - 2 * math.atan(q.X, q.W) * r2d }
    end
    return {
        Pitch = math.asin(2 * singularity) * r2d,
        Yaw = yaw,
        Roll = math.atan(-2 * (q.W * q.X + q.Y * q.Z), 1 - 2 * (q.X * q.X + q.Y * q.Y)) * r2d,
    }
end

-- A piece's world transform on a host component at loc/rot/scale.
function Placements.World(piece, loc, rot, scale)
    local hq = Placements.Quat(rot.Pitch or 0, rot.Yaw or 0, rot.Roll or 0)
    local v = Placements.Rotate(hq, { X = piece.x * scale.X, Y = piece.y * scale.Y, Z = piece.z * scale.Z })
    local q = Placements.QuatMul(hq, Placements.Quat(piece.pitch, piece.yaw, piece.roll))
    return { X = loc.X + v.X, Y = loc.Y + v.Y, Z = loc.Z + v.Z }, Placements.Rotator(q),
        { X = piece.scale * scale.X, Y = piece.scaleY * scale.Y, Z = piece.scaleZ * scale.Z }
end

-- The FTransform for an instance relative to its component.
function Placements.Transform(piece)
    return {
        Rotation = Placements.Quat(piece.pitch, piece.yaw, piece.roll),
        Translation = { X = piece.x, Y = piece.y, Z = piece.z },
        Scale3D = { X = piece.scale, Y = piece.scaleY, Z = piece.scaleZ },
    }
end

return Placements

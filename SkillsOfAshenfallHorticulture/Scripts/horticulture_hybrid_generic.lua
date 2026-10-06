-- Generic hybrid looks: socket set (per host mesh) x produce (per donor), the
-- Lua twin of scripts/blender/compose/generic_math.py. Pure Lua 5.4, no game
-- calls. Data: placements/generic/<id>_{sockets,produce,combos}_vNNN.lua.
--
--   local G = require("hybrid_generic")
--   G.Load(folder)                         -- folder holding the three files (newest version of each)
--   local data = G.Placement("FPD_Onion", "Oak")
--   -- data is ess.hybrid_placement/1 shaped: data.hosts[mesh] -> shape id,
--   -- data.shapes[id].attachments = { {mesh, location, rotation, scale, group, requires_pak}, ... }
--   -- so Placements.Shape / Placements.Pieces use it unchanged.
local G = {}

G.ID = "hort_plant_generic_hybrids_1_25"
G.MAX_VERSION = 50

local rad, deg, sin, cos, sqrt = math.rad, math.deg, math.sin, math.cos, math.sqrt
local atan2 = math.atan2 or math.atan

-- UE FRotationMatrix rows (X, Y, Z axes) of a rotator.
function G.RotAxes(p, y, r)
    p, y, r = rad(p), rad(y), rad(r)
    local sp, cp, sy, cy, sr, cr = sin(p), cos(p), sin(y), cos(y), sin(r), cos(r)
    return {
        { cp * cy, cp * sy, sp },
        { sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp },
        { -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp },
    }
end

-- Rotate a local vector into the parent frame.
function G.Apply(rows, v)
    local out = {}
    for k = 1, 3 do out[k] = rows[1][k] * v[1] + rows[2][k] * v[2] + rows[3][k] * v[3] end
    return out
end

-- Rows of "b then a" (child b expressed in parent a).
function G.Mul(a, b)
    return { G.Apply(a, b[1]), G.Apply(a, b[2]), G.Apply(a, b[3]) }
end

-- UE FMatrix::Rotator() for rows (X, Y, Z).
function G.ToRotator(m)
    local x, y, z = m[1], m[2], m[3]
    local pitch = deg(atan2(x[3], sqrt(x[1] * x[1] + x[2] * x[2])))
    local yaw = deg(atan2(x[2], x[1]))
    local sy = G.RotAxes(pitch, yaw, 0)[2]
    local roll = deg(atan2(z[1] * sy[1] + z[2] * sy[2] + z[3] * sy[3], y[1] * sy[1] + y[2] * sy[2] + y[3] * sy[3]))
    return { pitch, yaw, roll }
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

-- Piece transform (socket-local) -> host-relative. scale_cap only shrinks.
function G.Compose(socket, piece)
    local rs = G.RotAxes(socket.rotation[1], socket.rotation[2], socket.rotation[3])
    local d = G.Apply(rs, piece.location)
    local rot = G.ToRotator(G.Mul(rs, G.RotAxes(piece.rotation[1], piece.rotation[2], piece.rotation[3])))
    local loc, r, scale = {}, {}, {}
    for k = 1, 3 do
        loc[k] = round2(socket.location[k] + d[k])
        r[k] = round2(rot[k])
        local s = piece.scale[k]
        if socket.scale_cap and s > socket.scale_cap then s = socket.scale_cap end
        scale[k] = s
    end
    return loc, r, scale
end

function G.UseFor(hostKind, scionIsTree)
    if hostKind == "crop" then
        if scionIsTree then return nil end
        return "nestle"
    end
    if scionIsTree then return "limb" end
    return "hang"
end

-- { {index (0-based), socket, pieces}, ... } by the documented rule.
function G.Select(shape, entry, use)
    local sockets = shape.sockets[use]
    local u = entry.uses[use]
    if not u or not sockets or #sockets == 0 then return {} end
    local out = {}
    for i = 1, math.min(#sockets, u.clusters) do
        local s = sockets[i]
        local variants = u.variants
        if variants[1] == nil then variants = variants[s.mode or "default"] end
        out[#out + 1] = { i - 1, s, variants[((i - 1) % #variants) + 1] }
    end
    return out
end

-- Host-relative attachments for one host mesh and scion (empty when not covered).
function G.ComboAttachments(sockets, produce, hostMesh, scion)
    local sid = sockets.hosts[hostMesh]
    if not sid then return {} end
    local shape = sockets.shapes[sid]
    local entry = produce.produce[scion]
    if not entry then return {} end
    local use = G.UseFor(shape.kind, entry.kind == "tree")
    local atts = {}
    if not use then return atts end
    for _, sel in ipairs(G.Select(shape, entry, use)) do
        local i, s, pieces = sel[1], sel[2], sel[3]
        for k, p in ipairs(pieces) do
            local loc, rot, scale = G.Compose(s, p)
            local noPak = nil
            if p.no_pak_location then
                noPak = G.Compose(s, { location = p.no_pak_location, rotation = p.rotation, scale = p.scale })
            end
            atts[#atts + 1] = {
                name = string.format("%s_%02d_%d", use, i, k - 1), mesh = p.mesh,
                location = loc, rotation = rot, scale = scale, group = p.group,
                requires_pak = p.requires_pak and true or false, cluster = i,
                no_pak_location = noPak, material_overrides = p.material_overrides,
            }
        end
    end
    return atts
end

-- Loading ------------------------------------------------------------------

local data = nil

local function newest(folder, kind)
    for v = G.MAX_VERSION, 1, -1 do
        local file = string.format("%s_%s_v%03d", G.ID, kind, v)
        local chunk = loadfile(folder .. "\\" .. file .. ".lua") or loadfile(folder .. "/" .. file .. ".lua")
        if chunk then
            local ok, t = pcall(chunk)
            if ok and type(t) == "table" then return t, file end
        end
    end
    return nil, nil
end

-- Reads the newest sockets, produce and combos files. True when all three load.
function G.Load(folder)
    local s, sf = newest(folder, "sockets")
    local p, pf = newest(folder, "produce")
    local c, cf = newest(folder, "combos")
    if not (s and p and c) or s.schema ~= "ess.hybrid_socket/1" or p.schema ~= "ess.hybrid_produce/1" then
        data = false
        return false
    end
    data = { sockets = s, produce = p, combos = c, files = { sf, pf, cf }, cache = {}, byKey = {} }
    for _, e in ipairs(c.combos or {}) do data.byKey[e.key] = e end
    return true
end

function G.Loaded() return data and true or false end
function G.Files() return data and data.files or nil end

-- The combo entry for scion>host (Rules.ComboKey order), or nil when not legal at 1-25.
function G.Combo(scion, host)
    return data and data.byKey[tostring(scion) .. ">" .. tostring(host)] or nil
end

-- ess.hybrid_placement/1-shaped data for a combo, covering every mesh the host
-- species can show (plot stages, or grown trees and saplings). Cached per combo.
function G.Placement(scion, host)
    if not data then return nil end
    local key = tostring(scion) .. ">" .. tostring(host)
    if data.cache[key] ~= nil then return data.cache[key] or nil end
    local combo = data.byKey[key]
    local meshes = combo and data.combos.host_meshes[host]
    if not meshes then
        data.cache[key] = false
        return nil
    end
    local out = {
        schema = "ess.hybrid_placement/1", hybrid_id = "generic:" .. key, generic = true,
        version = data.sockets.version, file = data.files[1],
        component_defaults = data.produce.component_defaults, hosts = {}, shapes = {},
    }
    for _, list in pairs(meshes) do
        for _, mesh in ipairs(list) do
            local sid = data.sockets.hosts[mesh]
            if sid then
                out.hosts[mesh] = sid
                if not out.shapes[sid] then
                    out.shapes[sid] = { attachments = G.ComboAttachments(data.sockets, data.produce, mesh, scion) }
                end
            end
        end
    end
    data.cache[key] = out
    return out
end

return G

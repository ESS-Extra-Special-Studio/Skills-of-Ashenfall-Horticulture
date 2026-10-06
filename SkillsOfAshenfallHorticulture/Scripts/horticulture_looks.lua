-- What a hybrid looks like: the game's own meshes placed on and around the
-- host (potatoes at an ash's roots, cabbages in an oak's canopy), and a tint
-- and scale on the host itself. Nothing is cooked; every mesh ships with the
-- game. When a cooked hybrid mesh is installed (a ~mods pak with
-- /Game/Mods/SkillsOfAshenfallHorticulture/...), it is loaded by path and
-- used instead of the kitbash. meshes.txt beside the Scripts folder can point
-- a hybrid at another path ("TuberwoodAsh = /Game/Mods/.../SM_Name").
--
-- The five flagships wear the asset pipeline's placement data
-- (horticulture_placements.lua): the shape is picked by the host's actual
-- tree or crop mesh, and the vanilla pieces are added as one instanced mesh
-- component per mesh type on a single actor (per-piece actors, a few per
-- refresh, if instancing fails).
--
-- Per-hybrid placement data replaces the built-in layout: a list of
-- { asset path, transform relative to the host's base and facing } given to
-- Looks.SetAttachments, or read from looks\<HybridId>.txt beside the Scripts
-- folder (format at Looks.ParseAttachments).
--
-- Everything spawned here is local to this machine and never saved by the
-- game: the looks are rebuilt from the splicing save whenever the host is
-- near.
local Looks = {}

local ITEM = "/Game/Art/Item/Resources/"
local TREES = "/Game/Art/Env/Landscape/Foliage/Trees/"

local function asset(path)
    local name = path:match("([^/]+)$")
    return path .. "." .. name
end

Looks.MESH = {
    cabbage = asset(ITEM .. "Cabbage/SM_Cabbage_01"),
    cabbage2 = asset(ITEM .. "Cabbage/SM_Cabbage_01v2"),
    cabbage3 = asset(ITEM .. "Cabbage/SM_Cabbage_01v3"),
    potato = asset(ITEM .. "Potato/SM_Potato_Fruit_01"),
    potatoPlant = asset(ITEM .. "Potato/SM_Potato_Plant_01"),
    wheat = asset(ITEM .. "Wheat/SM_Wheat_01"),
    onionPlant = asset(ITEM .. "Onion_Plant/SM_Onion_Plant_01"),
    onion = asset(ITEM .. "Onion_Plant/SM_Onion_Fruit_01"),
    berryBush = asset(ITEM .. "Berry_Bush/SM_Berry_Bush_01"),
    flax = asset(ITEM .. "Flax/SM_Flax_01"),
    willowCanopy = asset(TREES .. "Willow/Willow_01_Components/SM_Willow_01_Canopy"),
    oakCanopy = asset(TREES .. "Oak_Tree/FH_OakTree_01_Components/SM_FH_Oak_Tree_01_Canopy"),
    ashSapling = asset(TREES .. "Ash_Tree/SM_Ash_Sapling_01"),
    goldIngot = asset(ITEM .. "Ingots/SM_Ingot_Gold_01"),
}

-- Whole cooked hybrid meshes by hybrid id. None ship: every hybrid is the
-- host bearing the donor's produce (placement data). meshes.txt can still
-- point a hybrid at a cooked mesh.
Looks.PACKAGED = {}

-- Scion meshes for ordinary combinations: a few small pieces of the scion.
local SCION_MESH = {
    FPD_Cabbage = "cabbage", FPD_Potato = "potato", FPD_Wheat = "wheat", FPD_Onion = "onion",
    FPD_Redberry = "berryBush", FPD_Flax = "flax",
    Oak = "oakCanopy", Willow = "willowCanopy", Ash = "ashSapling",
}

-- Tints: hue shift and a colour pushed into whichever of the vanilla leaf
-- and crop parameters the material has.
local TINT = {
    FPD_Cabbage = { hue = 0.08, color = { R = 0.55, G = 0.8, B = 0.6 } },
    FPD_Potato = { hue = -0.04, color = { R = 0.6, G = 0.5, B = 0.35 } },
    FPD_Wheat = { hue = -0.1, color = { R = 0.95, G = 0.78, B = 0.35 } },
    FPD_Redberry = { hue = -0.25, color = { R = 0.85, G = 0.3, B = 0.25 } },
    FPD_Onion = { hue = 0.05, color = { R = 0.8, G = 0.75, B = 0.55 } },
    FPD_Flax = { hue = 0.12, color = { R = 0.55, G = 0.65, B = 0.85 } },
    Willow = { hue = 0.04, color = { R = 0.6, G = 0.75, B = 0.45 } },
    Oak = { hue = -0.03, color = { R = 0.5, G = 0.6, B = 0.3 } },
    Ash = { hue = 0.02, color = { R = 0.55, G = 0.7, B = 0.4 } },
}
local DEFAULT_TINT = { hue = 0.06, color = { R = 0.6, G = 0.7, B = 0.5 } }

-- Hybrids whose host keeps its own colours (the change is all in the parts).
Looks.NO_TINT = { TuberwoodAsh = true, Brassitato = true, WeepingCabbage = true }

local SCALAR_PARAMS = { "RandomColor_HueShift" }
local VECTOR_PARAMS = { "Color Top", "Color Bottom", "Subsurface Color", "Color_Mult_A", "Color_Mult_B" }

-- Pure layout ------------------------------------------------------------

-- size: { height, radius } of the host in cm (radius: half its width).
-- Returns the pieces { mesh, x, y, z (relative to the host's base),
-- scale, yaw, pitch, roll } and the host scale multiplier.
local function ring(out, mesh, n, r, z, scale, opts)
    opts = opts or {}
    for i = 1, n do
        local a = (i - 1) / n * 2 * math.pi + (opts.phase or 0)
        local rr = r * (1 + ((i % 3) - 1) * (opts.jitter or 0))
        out[#out + 1] = {
            mesh = mesh, x = math.cos(a) * rr, y = math.sin(a) * rr,
            z = z + ((i % 2 == 0) and (opts.dz or 0) or 0),
            scale = scale * (1 + ((i % 4) - 1.5) * 0.08),
            yaw = math.deg(a) + (opts.yaw or 0), pitch = opts.pitch or 0, roll = opts.roll or 0,
        }
    end
end

local function canopy(size)
    local h = size.height
    return h * 0.62, h * 0.82, math.max(size.radius * 0.55, 60)
end

local layout
Looks.FRUIT = { cabbage = true, cabbage2 = true, cabbage3 = true, potato = true, wheat = true, onion = true }

-- The built-in layout, only for combinations the placement data does not
-- cover. Nothing is ever larger than the game draws it: no piece above
-- natural size (fruit above Placements.FRUIT_MAX), and the host keeps its
-- own scale (the second value is always 1.0).
function Looks.Layout(hybridId, scion, hostKind, size)
    local out = layout(hybridId, scion, hostKind, size)
    local P = require("horticulture_placements")
    for _, p in ipairs(out) do
        local max = Looks.FRUIT[p.mesh] and P.FruitMax(Looks.MESH[p.mesh]) or 1.0
        p.scale = math.min(p.scale, max)
    end
    return out, 1.0
end

layout = function(hybridId, scion, hostKind, size)
    local out = {}
    local small = hostKind == "sapling" or hostKind == "plot"
    local s = small and math.max(size.height / 600, 0.25) or 1
    if hybridId == "TuberwoodAsh" then
        local lo, hi, r = canopy(size)
        ring(out, "potato", 7, r, lo, 2.2 * s, { phase = 0.3, jitter = 0.2, pitch = 20 })
        ring(out, "potato", 5, r * 0.75, (lo + hi) / 2, 2.0 * s, { phase = 1.0, jitter = 0.2, pitch = -15 })
        return out, 1.0
    elseif hybridId == "BrassicaOak" then
        local lo, hi, r = canopy(size)
        ring(out, "cabbage", 4, r, lo, 1.6 * s, { phase = 0.2, jitter = 0.2 })
        ring(out, "cabbage2", 3, r * 0.8, (lo + hi) / 2, 1.5 * s, { phase = 1.1 })
        ring(out, "cabbage3", 3, r * 0.6, hi, 1.4 * s, { phase = 2.0 })
        return out, 1.0
    elseif hybridId == "SheafAsh" then
        local lo, hi, r = canopy(size)
        ring(out, "wheat", 6, r * 1.05, lo, 1.4 * s, { phase = 0.3, pitch = -15, jitter = 0.15 })
        ring(out, "wheat", 6, r * 0.85, hi, 1.3 * s, { phase = 0.8, pitch = 15, jitter = 0.15 })
        return out, 1.0
    elseif hybridId == "WeepingOak" then
        local lo = size.height * 0.45
        out[#out + 1] = { mesh = "willowCanopy", x = 0, y = 0, z = lo, scale = 0.55 * s, yaw = 35, pitch = 0, roll = 0 }
        out[#out + 1] = { mesh = "willowCanopy", x = 0, y = 0, z = lo * 0.95, scale = 0.45 * s, yaw = 200, pitch = 0, roll = 0 }
        return out, 1.0
    elseif hybridId == "BrambleOak" then
        local lo, hi, r = canopy(size)
        ring(out, "berryBush", 6, r * 0.9, (lo + hi) / 2, 0.6 * s, { jitter = 0.2, dz = 60 })
        return out, 1.0
    elseif hybridId == "TwoBarkAsh" then
        local lo = size.height * 0.55
        out[#out + 1] = { mesh = "oakCanopy", x = size.radius * 0.3, y = 0, z = lo, scale = 0.45 * s, yaw = 0, pitch = 0, roll = 0 }
        return out, 1.0
    elseif hybridId == "Brassitato" then
        out[#out + 1] = { mesh = "cabbage", x = 0, y = 0, z = math.max(size.height * 0.7, 18), scale = 0.9, yaw = 20, pitch = 0, roll = 0 }
        return out, 1.1
    elseif hybridId == "WeepingCabbage" then
        out[#out + 1] = { mesh = "onionPlant", x = 0, y = 0, z = 0, scale = 1.1, yaw = 0, pitch = 0, roll = 0 }
        return out, 1.0
    end
    -- Ordinary combinations: a few small pieces of the scion and a scale.
    local mesh = SCION_MESH[scion]
    if mesh then
        if hostKind == "plot" then
            out[#out + 1] = { mesh = mesh, x = 0, y = 0, z = math.max(size.height * 0.6, 15), scale = 0.6, yaw = 0, pitch = 0, roll = 0 }
        elseif mesh == "oakCanopy" or mesh == "willowCanopy" or mesh == "ashSapling" then
            local lo = size.height * 0.6
            out[#out + 1] = { mesh = mesh, x = size.radius * 0.25, y = 0, z = lo, scale = (mesh == "ashSapling" and 1.5 or 0.3) * s, yaw = 0, pitch = 0, roll = 0 }
        else
            local lo, hi, r = canopy(size)
            ring(out, mesh, 4, r * 0.8, (lo + hi) / 2, 1.0 * s, { dz = 50 })
        end
    end
    return out, 1.08
end

-- A hybrid of more than two plants wears every cutting's layout at once.
-- plants: { host, scion1, scion2, ... }; idFor(scion, host) names each pair.
function Looks.LayoutPlants(plants, idFor, hostKind, size)
    local out, hostScale = {}, 1.0
    for i = 2, #plants do
        local pieces, s = Looks.Layout(idFor(plants[i], plants[1]), plants[i], hostKind, size)
        for _, p in ipairs(pieces) do out[#out + 1] = p end
        if s > hostScale then hostScale = s end
    end
    return out, hostScale
end

-- Placement data: one attachment per line,
--   <asset path> | x y z | pitch yaw roll | scale   (or sx sy sz)
-- x y z in cm from the host's base, turned with the host; rotation in
-- degrees on top of the host's facing. Only the path is required.
function Looks.ParseAttachments(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%S") then
            local fields = {}
            for f in (line .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = f end
            local path = (fields[1] or ""):match("^%s*(.-)%s*$")
            local function nums(s)
                local t = {}
                for n in (s or ""):gmatch("[-%d%.eE+]+") do t[#t + 1] = tonumber(n) end
                return t
            end
            local loc, rot, sc = nums(fields[2]), nums(fields[3]), nums(fields[4])
            if path ~= "" then
                if not path:find(".", 1, true) then path = asset(path) end
                out[#out + 1] = {
                    path = path, x = loc[1] or 0, y = loc[2] or 0, z = loc[3] or 0,
                    pitch = rot[1] or 0, yaw = rot[2] or 0, roll = rot[3] or 0,
                    scale = sc[1] or 1, scaleY = sc[2], scaleZ = sc[3],
                }
            end
        end
    end
    return out
end

-- Attachments as pieces, scaled with the host actor (placed trees vary).
function Looks.AttachmentPieces(list, hostScale)
    local s = hostScale or 1
    local out = {}
    for _, a in ipairs(list) do
        out[#out + 1] = {
            path = a.path, x = a.x * s, y = a.y * s, z = a.z * s,
            pitch = a.pitch, yaw = a.yaw, roll = a.roll,
            scale = a.scale * s, scaleY = a.scaleY and a.scaleY * s, scaleZ = a.scaleZ and a.scaleZ * s,
        }
    end
    return out
end

-- The Brassica Primelet without its placement data file: a vanilla cabbage,
-- tinted, with a crown of gold ingots stood on end.
Looks.PRIMELET_TINT = { hue = 0.12, color = { R = 0.75, G = 0.85, B = 0.35 } }

function Looks.PrimeletLayout(scale)
    local s = scale or 1
    local out = { { mesh = "cabbage", x = 0, y = 0, z = 0, scale = 2.2 * s, yaw = 0, pitch = 0, roll = 0, tint = Looks.PRIMELET_TINT } }
    ring(out, "goldIngot", 5, 9 * s, 26 * s, 0.35 * s, { pitch = 90 })
    return out
end

-- Pending grafts show a binding of flax twine at the graft point.
function Looks.PendingLayout(hostKind, size)
    local z = hostKind == "tree" and math.min(size.height * 0.12, 120) or math.max(size.height * 0.3, 10)
    return { { mesh = "flax", x = 0, y = 0, z = z, scale = hostKind == "tree" and 0.5 or 0.3, yaw = 0, pitch = 0, roll = 0 } }
end

function Looks.Tint(scion)
    return TINT[scion] or DEFAULT_TINT
end

-- meshes.txt: "<HybridId> = <asset path>" lines override PACKAGED.
function Looks.ParseOverrides(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(%S+)%s*$")
        if k and not line:match("^%s*#") then
            if not v:find(".", 1, true) then v = asset(v) end
            out[k] = v
        end
    end
    return out
end

-- Game side ---------------------------------------------------------------

local U = nil
local UEHelpers = nil
local meshCache = {}
local packagedSeen = {}
local overrides = {}
local built = {}
local attachments = {}
local looksDir = nil
local scriptsDir = nil
local Placements = require("horticulture_placements")
local Generic = require("horticulture_hybrid_generic")
local Primelets = require("horticulture_primelet_looks")
local Mutation = require("horticulture_mutation")

-- Placement looks: at most CAP pieces per host (instanced, or as actors),
-- BATCH actors added per refresh. mode "ism" or "actors" (dev toggle).
Looks.CAP = { ism = 128, actors = 40 }
Looks.BATCH = 24
Looks.mode = "ism"
-- The Horticulture pak (our stalk mesh), beside the Scripts folder. v1
-- ships without it; requires_pak pieces are skipped.
Looks.PAK_FILE = "SoAHorticulture_P.utoc"
local havePak = nil

-- Placement data for a hybrid: a list of { path, x, y, z, pitch, yaw, roll,
-- scale [, scaleY, scaleZ] }, or nil to go back to the built-in layout.
function Looks.SetAttachments(hybridId, list)
    attachments[hybridId] = list or false
    for id, b in pairs(built) do
        if b.hybridId == hybridId then Looks.Clear(id) end
    end
end

function Looks.Attachments(hybridId)
    if attachments[hybridId] == nil then
        attachments[hybridId] = false
        local f = looksDir and io.open(looksDir .. "\\" .. hybridId .. ".txt", "r")
        if f then
            local list = Looks.ParseAttachments(f:read("*a"))
            f:close()
            if #list > 0 then
                attachments[hybridId] = list
                if U then U.log(string.format("%s: %d attachment(s) from looks\\%s.txt", hybridId, #list, hybridId)) end
            end
        end
    end
    return attachments[hybridId] or nil
end

-- Mod packages load through the asset registry (LoadAsset returns nothing
-- for /Game/Mods/...); only tried when the pak is installed.
local function load_mod_asset(path)
    if not havePak then return nil end
    local obj = nil
    pcall(function()
        local helpers = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
        local pkg, name = path:match("^([^%.]+)%.(.+)$")
        obj = helpers:GetAsset({ PackageName = FName(pkg), AssetName = FName(name) })
    end)
    return U.valid(obj) and obj or nil
end

-- Only misses are cached: a loaded mesh nothing uses any more is garbage
-- collected, and a kept reference to it crashes the game when reused.
local function load(path)
    if meshCache[path] == false then return nil end
    local obj = StaticFindObject(path)
    if not U.valid(obj) and path:find("^/Game/Mods/") then
        obj = load_mod_asset(path)
    elseif not U.valid(obj) and LoadAsset then
        local ok, loaded = pcall(LoadAsset, path)
        if ok and U.valid(loaded) then obj = loaded end
    end
    if U.valid(obj) then return obj end
    meshCache[path] = false
    return nil
end

function Looks.Init(util, dir)
    U = util
    UEHelpers = require("UEHelpers")
    looksDir = dir .. "\\..\\looks"
    scriptsDir = dir
    local pak = io.open(dir .. "\\..\\" .. Looks.PAK_FILE, "rb")
    havePak = pak ~= nil
    if pak then pak:close() end
    U.log("Horticulture pak " .. (havePak and "installed: hybrid stalks and Primelet faces shown" or "not installed: hybrid looks use the game's meshes only"))
    if Generic.Load(dir .. "\\placements") then
        U.log("Generic hybrid looks: " .. table.concat(Generic.Files(), ", "))
    else
        U.log("Generic hybrid look data missing from Scripts\\placements; ordinary combinations use the built-in layout")
    end
    if Primelets.Load(dir .. "\\placements") then U.log("Primelet looks: " .. Primelets.File()) end
    local f = io.open(dir .. "\\..\\meshes.txt", "r")
    if f then
        overrides = Looks.ParseOverrides(f:read("*a"))
        f:close()
        local n = 0
        for _ in pairs(overrides) do n = n + 1 end
        U.log("meshes.txt: " .. n .. " hybrid mesh path(s)")
    end
end

-- The cooked mesh for a hybrid, or nil (the kitbash is used).
function Looks.Packaged(hybridId)
    local path = overrides[hybridId] or Looks.PACKAGED[hybridId]
    if not path then return nil end
    local mesh = load(path)
    if packagedSeen[hybridId] == nil then
        packagedSeen[hybridId] = mesh ~= nil
        U.log(string.format("%s: cooked mesh %s %s", hybridId, path, mesh and "loaded" or "not installed; using the game's own meshes"))
    end
    return mesh, path
end

local function rotate(x, y, yawDeg)
    local a = math.rad(yawDeg or 0)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
end

local function spawn(world, mesh, loc, rot, scale)
    local cls = load("/Script/Engine.StaticMeshActor")
    if not cls then return nil end
    local ok, actor = pcall(function() return world:SpawnActor(cls, loc, rot) end)
    if not ok or not U.valid(actor) then return nil end
    pcall(function()
        local comp = actor.StaticMeshComponent
        comp:SetMobility(2)
        comp:SetStaticMesh(mesh)
        comp:SetCollisionEnabled(0)
    end)
    pcall(function() actor:SetActorEnableCollision(false) end)
    local s = type(scale) == "table" and scale or { X = scale, Y = scale, Z = scale }
    pcall(function() actor:SetActorScale3D(s) end)
    return actor
end

-- Dev showcase: a vanilla mesh as a stand-in host.
function Looks.SpawnMesh(path, loc, rot, scale)
    local mesh = load(path)
    local world = UEHelpers.GetWorld()
    if not mesh or not U.valid(world) then return nil end
    return spawn(world, mesh, loc, rot or { Pitch = 0, Yaw = 0, Roll = 0 }, scale or 1)
end

-- Host size from its bounds; defaults when they cannot be read.
function Looks.Size(actor, kind)
    local base = U.location(actor)
    local size = nil
    pcall(function()
        local origin, extent = {}, {}
        actor:GetActorBounds(true, origin, extent, false)
        if extent.Z and extent.Z > 1 and base then
            local top = origin.Z + extent.Z
            size = { height = math.max(top - base.Z, 20), radius = math.max(extent.X, extent.Y) }
        end
    end)
    if size and kind == "tree" and size.height > 4000 then size = nil end
    if not size then
        if kind == "tree" then size = { height = 900, radius = 350 }
        elseif kind == "sapling" then size = { height = 150, radius = 60 }
        else size = { height = 40, radius = 40 } end
    end
    return size
end

local function mesh_components(actor)
    local out = {}
    local cls = StaticFindObject("/Script/Engine.StaticMeshComponent")
    pcall(function()
        actor:K2_GetComponentsByClass(cls):ForEach(function(_, c)
            local comp = c:get()
            if U.valid(comp) then out[#out + 1] = comp end
        end)
    end)
    return out
end

-- Tints every material on the host's meshes (parameters the material lacks
-- are ignored by the engine) and keeps the originals to put back.
local function tint(comps, scion)
    local t = type(scion) == "table" and scion or Looks.Tint(scion)
    local saved = {}
    for _, comp in ipairs(comps) do
        local n = 0
        pcall(function() n = comp:GetNumMaterials() end)
        for i = 0, math.min(n, 8) - 1 do
            local original = nil
            pcall(function() original = comp:GetMaterial(i) end)
            local okM, mid = pcall(function() return comp:CreateDynamicMaterialInstance(i, original, FName("None")) end)
            if okM and U.valid(mid) then
                saved[#saved + 1] = { comp = comp, index = i, material = original }
                for _, p in ipairs(SCALAR_PARAMS) do pcall(function() mid:SetScalarParameterValue(FName(p), t.hue) end) end
                local c = { R = t.color.R, G = t.color.G, B = t.color.B, A = 1 }
                for _, p in ipairs(VECTOR_PARAMS) do pcall(function() mid:SetVectorParameterValue(FName(p), c) end) end
            end
        end
    end
    return saved
end

local function untint(saved)
    for _, s in ipairs(saved or {}) do
        if U.valid(s.comp) and s.restore then
            pcall(function() s.mid:SetScalarParameterValue(FName("RandomColor_HueShift"), s.restore.hue) end)
            for p, c in pairs(s.restore.colors) do pcall(function() s.mid:SetVectorParameterValue(FName(p), c) end) end
        elseif U.valid(s.comp) and s.material then
            pcall(function() s.comp:SetMaterial(s.index, s.material) end)
        end
    end
end

-- Mutation tint (horticulture_mutation): the host's own leaf (tree) or
-- plant (crop) materials as dynamic instances with the hybrid's hue shift
-- and colour multiply. A material that is already a dynamic instance is
-- changed in place and its values kept to put back.
Looks.MUTATION = true
local MUTATION_COLORS = { "Color_Mult_A", "Color_Mult_B" }

local function is_mid(m)
    return tostring(U.full(m) or ""):find("MaterialInstanceDynamic", 1, true) ~= nil
end

local function material_path(m)
    if is_mid(m) then
        local parent = nil
        pcall(function() parent = m.Parent end)
        if U.valid(parent) then return U.full(parent) end
    end
    return U.full(m)
end

local function mutate(h, t)
    local comps = {}
    for _, c in ipairs(h.comps or {}) do if U.valid(c) then comps[#comps + 1] = c end end
    if #comps == 0 and U.valid(h.actor) then comps = mesh_components(h.actor) end
    local saved = {}
    for _, comp in ipairs(comps) do
        local n = 0
        pcall(function() n = comp:GetNumMaterials() end)
        for i = 0, math.min(n, 8) - 1 do
            local original = nil
            pcall(function() original = comp:GetMaterial(i) end)
            if U.valid(original) and Mutation.Takes(h.kind, material_path(original)) then
                local s = { comp = comp, index = i }
                if is_mid(original) then
                    s.mid = original
                    s.restore = { hue = 0, colors = {} }
                    pcall(function() s.restore.hue = original:K2_GetScalarParameterValue(FName("RandomColor_HueShift")) end)
                    for _, p in ipairs(MUTATION_COLORS) do
                        pcall(function() s.restore.colors[p] = original:K2_GetVectorParameterValue(FName(p)) end)
                    end
                else
                    s.material = original
                    pcall(function() s.mid = comp:CreateDynamicMaterialInstance(i, original, FName("None")) end)
                end
                if U.valid(s.mid) then
                    pcall(function() s.mid:SetScalarParameterValue(FName("RandomColor_HueShift"), t.hue) end)
                    local c = { R = t.mult.R, G = t.mult.G, B = t.mult.B, A = 1 }
                    for _, p in ipairs(MUTATION_COLORS) do pcall(function() s.mid:SetVectorParameterValue(FName(p), c) end) end
                    s.midName = U.full(s.mid)
                    saved[#saved + 1] = s
                end
            end
        end
    end
    return saved
end

-- True while every tinted slot still shows our instance (the game can
-- swap a tree's materials, for example when it streams back in).
local function mutation_holds(saved)
    for _, s in ipairs(saved or {}) do
        local now = nil
        pcall(function() now = s.comp:GetMaterial(s.index) end)
        if not U.valid(s.comp) or not U.valid(now) or U.full(now) ~= s.midName then return false end
    end
    return true
end

local function apply_mutation(b, g, h, hybridId)
    if not Looks.MUTATION or not U.valid(h.actor) then return end
    local Rules = require("horticulture_splice_rules")
    local key = (g.plants and #g.plants > 2) and Rules.PlantsKey(g.plants) or Rules.ComboKey(g.scion, g.host)
    local t = Mutation.For(hybridId, key)
    if not t then return end
    b.tinted = mutate(h, t)
    b.mutation = t
end
Looks.Mutate, Looks.MutationHolds, Looks.Untint = mutate, mutation_holds, untint

local function scale_comps(comps, factor)
    local saved = {}
    for _, comp in ipairs(comps) do
        local okS, cur = pcall(function() return comp.RelativeScale3D end)
        if okS and cur then
            local was = { X = cur.X, Y = cur.Y, Z = cur.Z }
            saved[#saved + 1] = { comp = comp, scale = was }
            pcall(function() comp:SetRelativeScale3D({ X = was.X * factor, Y = was.Y * factor, Z = was.Z * factor }) end)
        end
    end
    return saved
end

local function unscale(saved)
    for _, s in ipairs(saved or {}) do
        if U.valid(s.comp) then pcall(function() s.comp:SetRelativeScale3D(s.scale) end) end
    end
end

-- Wind sway (horticulture_sway): instanced looks tilt their anchor, which
-- sits at the host mesh's pivot, so the whole look bends about the trunk.
local swayer = nil
local swayCost = { ticks = 0, seconds = 0, since = nil, reports = 0 }

local function sway_apply(b, pitch, roll)
    local a = b.actors[b.anchor or 1]
    if not U.valid(a) then return false end
    local r = b.t.rot
    local rot = Placements.Rotator(Placements.QuatMul(Placements.Quat(r.Pitch, r.Yaw, r.Roll), Placements.Quat(pitch, 0, roll)))
    pcall(function() a:K2_SetActorRotation(rot, false) end)
    return true
end

-- opts: { enabled, deg, debug }. Off: nothing ticks and looks stay still.
function Looks.StartSway(opts)
    opts = opts or {}
    U = U or require("horticulture_util")
    if opts.enabled == false then U.log("Wind sway is off (sway = false)") return end
    local Sway = require("horticulture_sway")
    local cfg = { base_deg = opts.deg or Sway.defaults.base_deg }
    -- Wind and the player's place change slowly; looking them up is most of
    -- an update's cost, so they are read a few times a second, as numbers.
    local seen = { windAt = -math.huge, playerAt = -math.huge }
    swayer = Sway.new(cfg, {
        clock = os.clock,
        wind = function()
            local t = os.clock()
            if t - seen.windAt >= 1.0 then
                seen.dir, seen.intensity = Sway.GameWind(swayer.cfg, UEHelpers.GetWorld())
                seen.windAt = t
            end
            return seen.dir, seen.intensity
        end,
        player = function()
            local t = os.clock()
            if t - seen.playerAt >= 0.5 then
                local p = U.location(U.pawn())
                seen.player = p and { X = p.X, Y = p.Y } or nil
                seen.playerAt = t
            end
            return seen.player
        end,
        apply = function(b, pitch, roll)
            local t0 = os.clock()
            local ok = sway_apply(b, pitch, roll)
            swayCost.applying = (swayCost.applying or 0) + (os.clock() - t0)
            return ok
        end,
    })
    U.every(math.floor(1000 / cfg.rate_hz + 0.5), "Hybrid sway", function()
        if swayer:count() == 0 then return end
        local t0 = os.clock()
        local n = swayer:tick()
        local c = swayCost
        c.ticks, c.seconds = c.ticks + 1, c.seconds + (os.clock() - t0)
        c.since = c.since or t0
        if os.clock() - c.since >= 30 then
            c.reports = (c.reports or 0) + 1
            if c.reports <= 3 or opts.debug then
                U.log(string.format("Wind sway: %d tree(s) tilted, %.3f ms per update (%.3f ms tilting), %.2f ms per second%s",
                    n, c.seconds / c.ticks * 1000, (c.applying or 0) / c.ticks * 1000, c.seconds / (os.clock() - c.since) * 1000,
                    swayer.calm and " (game wind direction is 0; default direction used)" or ""))
            end
            c.ticks, c.seconds, c.since, c.applying = 0, 0, nil, 0
        end
    end)
    U.log(string.format("Wind sway on: %.2f deg at the game's default wind, nearest %d within %d m at %d Hz",
        cfg.base_deg, swayer.cfg.max_trees, swayer.cfg.radius_cm / 100, swayer.cfg.rate_hz))
end

function Looks.SwayCount() return swayer and swayer:count() or 0 end

function Looks.SetSwayDegrees(d)
    if swayer then swayer.cfg.base_deg = d end
    return swayer ~= nil
end

function Looks.Clear(graftId)
    if swayer then swayer:remove(graftId) end
    local b = built[graftId]
    if not b then return end
    for _, a in ipairs(b.actors) do
        if U.valid(a) then pcall(function() a:K2_DestroyActor() end) end
    end
    untint(b.tinted)
    unscale(b.scaled)
    built[graftId] = nil
end

function Looks.ClearAll()
    for id in pairs(built) do Looks.Clear(id) end
end

function Looks.Built(graftId) return built[graftId] end
function Looks.ScriptsDir() return scriptsDir end

-- Builds the look for graft g on host h = { actor, kind, loc, comps }
-- (comps: the meshes to tint and scale; plots pass the plant mesh).
-- mode: "pending" or "hybrid". Returns the number of pieces placed.
-- Spawns pieces around base, turned by yaw, into b.actors. A piece names a
-- Looks.MESH entry (mesh) or an asset path (path); tint recolours it.
local function place(world, b, base, yaw, pieces)
    for _, p in ipairs(pieces) do
        local path = p.path or Looks.MESH[p.mesh]
        local mesh = path and load(path)
        if mesh then
            local x, y = rotate(p.x or 0, p.y or 0, yaw)
            local scale = p.scale or 1
            if p.scaleY or p.scaleZ then scale = { X = scale, Y = p.scaleY or scale, Z = p.scaleZ or scale } end
            local a = spawn(world, mesh, { X = base.X + x, Y = base.Y + y, Z = base.Z + (p.z or 0) },
                { Pitch = p.pitch or 0, Yaw = (p.yaw or 0) + yaw, Roll = p.roll or 0 }, scale)
            if a then
                b.actors[#b.actors + 1] = a
                if p.tint then tint(mesh_components(a), p.tint) end
            end
        else
            U.log_once("mesh" .. tostring(path), "Hybrid look: mesh " .. tostring(path) .. " could not be loaded")
        end
    end
end

-- Placement looks ------------------------------------------------------------

local function mesh_key(comp)
    local m = nil
    pcall(function() m = comp.StaticMesh end)
    if not U.valid(m) then pcall(function() m = comp:GetStaticMesh() end) end
    if not U.valid(m) then return nil end
    local name = nil
    pcall(function() name = m:GetFullName() end)
    return Placements.HostKey(name)
end

-- The host's mesh component whose mesh the data covers (a plot passes its
-- plant mesh; a tree its root mesh), with the shape; else nil and the mesh
-- paths seen.
local function host_component(h, data)
    local cands = {}
    for _, c in ipairs(h.comps or {}) do cands[#cands + 1] = c end
    local root = nil
    pcall(function() root = h.actor.RootStaticMeshComponent end)
    if U.valid(root) then cands[#cands + 1] = root end
    if not h.comps or #h.comps == 0 then
        for _, c in ipairs(mesh_components(h.actor)) do cands[#cands + 1] = c end
    end
    local seen = {}
    for _, c in ipairs(cands) do
        local key = mesh_key(c)
        if key then
            local shape, name = Placements.Shape(data, key)
            if shape then return c, shape, key, name end
            seen[#seen + 1] = key
        end
    end
    return nil, nil, table.concat(seen, ", ")
end

local function comp_transform(c)
    local loc, rot, scl = nil, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = 1, Y = 1, Z = 1 }
    pcall(function() local l = c:K2_GetComponentLocation() loc = { X = l.X, Y = l.Y, Z = l.Z } end)
    pcall(function() local r = c:K2_GetComponentRotation() rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
    pcall(function() local s = c:K2_GetComponentScale() scl = { X = s.X, Y = s.Y, Z = s.Z } end)
    return loc, rot, scl
end

-- The data's material overrides on one component: a dynamic instance of
-- the slot's material with the listed parameters. Best effort; a failure
-- leaves the mesh's own material. The instance belongs to the component,
-- so nothing is kept here.
local function apply_overrides(comp, overrides)
    for _, mo in ipairs(overrides or {}) do
        pcall(function()
            local c = Placements.OverrideCalls(mo)
            local current = nil
            pcall(function() current = comp:GetMaterial(c.slot) end)
            local mid = comp:CreateDynamicMaterialInstance(c.slot, current, FName("None"))
            if not U.valid(mid) then return end
            for _, v in ipairs(c.vectors) do pcall(function() mid:SetVectorParameterValue(FName(v[1]), v[2]) end) end
            for _, s in ipairs(c.scalars) do pcall(function() mid:SetScalarParameterValue(FName(s[1]), s[2]) end) end
        end)
    end
end

Looks.ApplyOverrides = apply_overrides

local IDENTITY = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }

-- One actor at the host mesh's transform; one instanced mesh component per
-- mesh type on it. Returns the instances added (0: instancing unavailable).
local function build_ism(world, b, t, pieces, tints, cull)
    local anchor = spawn(world, nil, t.loc, t.rot, t.scl)
    if not anchor then return 0 end
    b.actors[#b.actors + 1] = anchor
    b.anchor = #b.actors
    local cls = load("/Script/Engine.InstancedStaticMeshComponent")
    if not cls then return 0 end
    local byKey, order = {}, {}
    for _, p in ipairs(pieces) do
        local key = p.path .. "#" .. Placements.OverrideKey(p.overrides)
        if not byKey[key] then byKey[key] = {} order[#order + 1] = key end
        table.insert(byKey[key], p)
    end
    local n = 0
    for _, key in ipairs(order) do
        local group = byKey[key]
        local path = group[1].path
        local mesh = load(path)
        if mesh then
            local ok, ism = pcall(function() return anchor:AddComponentByClass(cls, false, IDENTITY, false) end)
            if not ok or not U.valid(ism) then return n end
            pcall(function() ism:SetMobility(2) end)
            pcall(function() ism:SetStaticMesh(mesh) end)
            pcall(function() ism:SetCollisionEnabled(0) end)
            if cull then pcall(function() ism:SetCullDistances(0, cull) end) end
            for _, p in ipairs(group) do
                pcall(function() ism:AddInstance(Placements.Transform(p), false) end)
            end
            local count = 0
            pcall(function() count = ism:GetInstanceCount() end)
            n = n + count
            apply_overrides(ism, group[1].overrides)
            local tintName = nil
            for _, p in ipairs(group) do tintName = tintName or (tints and tints[p.group]) end
            if tintName then tint({ ism }, tintName) end
        else
            U.log_once("mesh" .. path, "Hybrid look: mesh " .. path .. " could not be loaded")
        end
    end
    return n
end

-- Per-piece actors, BATCH per call; true when the queue is done.
local function continue_actors(b)
    local world = UEHelpers.GetWorld()
    if not U.valid(world) then return false end
    local last = math.min(b.qi + Looks.BATCH - 1, #b.queue)
    for i = b.qi, last do
        local p = b.queue[i]
        local mesh = load(p.path)
        if mesh then
            local loc, rot, scl = Placements.World(p, b.t.loc, b.t.rot, b.t.scl)
            local a = spawn(world, mesh, loc, rot, scl)
            if a then
                b.actors[#b.actors + 1] = a
                if b.cull then pcall(function() a.StaticMeshComponent:SetCullDistance(b.cull) end) end
                if p.overrides then
                    local comp = nil
                    pcall(function() comp = a.StaticMeshComponent end)
                    if U.valid(comp) then apply_overrides(comp, p.overrides) end
                end
                local tintName = b.tints and b.tints[p.group]
                if tintName then tint(mesh_components(a), tintName) end
            end
        end
    end
    b.qi = last + 1
    if b.qi > #b.queue then
        b.queue = nil
        U.log(string.format("%s look: %d actor(s) placed", b.hybridId, #b.actors))
        return true
    end
    return false
end

-- The placement data for graft g: the flagship's own file when it covers
-- this host's mesh, else the generic look for the combination (socket set
-- of the host mesh x produce of the scion). nil for combinations beyond
-- Horticulture 25.
local function placement_for(h, hybridId, g)
    local data = scriptsDir and Placements.Load(scriptsDir, hybridId)
    local comp, shape, key, name
    if data then comp, shape, key, name = host_component(h, data) end
    if not shape and g and Generic.Loaded() then
        local gd = Generic.Placement(g.scion, g.host)
        if gd then
            data = gd
            comp, shape, key, name = host_component(h, data)
        end
    end
    return data, comp, shape, key, name
end

-- Builds a hybrid's look from placement data. False when no data covers
-- this host (the built-in layout is used instead).
local function apply_placement(world, b, h, hybridId, g)
    local data, comp, shape, key, name = placement_for(h, hybridId, g)
    if not data then return false end
    if not shape then
        U.log_once("noshape" .. hybridId .. tostring(key), string.format("%s: no placement shape for host mesh(es) %s; built-in look used",
            hybridId, key ~= "" and key or "(none readable)"))
        return false
    end
    local loc, rot, scl = comp_transform(comp)
    if not loc then return false end
    local cull = data.component_defaults and data.component_defaults.cull_distance_cm
    local tints = Placements.GROUP_TINT[hybridId]
    local tintTables = nil
    if tints then
        tintTables = {}
        for g, n in pairs(tints) do tintTables[g] = Looks.Tint(n) end
    end
    local t0 = os.clock()
    local pieces = Placements.Pieces(shape, { havePak = havePak, cap = Looks.CAP.ism })
    local short = key:match("([^/]+)$")
    b.t = { loc = loc, rot = rot, scl = scl }
    if Looks.mode == "ism" then
        local n = build_ism(world, b, b.t, pieces, tintTables, cull)
        if n > 0 then
            b.instances = n
            U.log(string.format("%s look: %d of %d piece(s) instanced on %s (%s, %s) in %.1f ms",
                hybridId, n, #shape.attachments, short, name, tostring(data.file), (os.clock() - t0) * 1000))
            return true
        end
        for _, a in ipairs(b.actors) do if U.valid(a) then pcall(function() a:K2_DestroyActor() end) end end
        b.actors = {}
        U.log_once("noism", "Instanced meshes unavailable; hybrid looks use one actor per piece")
        Looks.mode = "actors"
    end
    b.queue = Placements.Pieces(shape, { havePak = havePak, cap = Looks.CAP.actors })
    b.qi, b.cull, b.tints = 1, cull, tintTables
    U.log(string.format("%s look: %d of %d piece(s) as actors on %s (%s), %d per refresh",
        hybridId, #b.queue, #shape.attachments, short, name, Looks.BATCH))
    continue_actors(b)
    return true
end

-- The host's identity for redraws: the actor and its current mesh, so a
-- plot's growth stage or a sapling growing up rebuilds the look.
local function host_sig(h)
    local c = h.comps and h.comps[1]
    if not U.valid(c) then pcall(function() c = h.actor.RootStaticMeshComponent end) end
    return U.full(h.actor) .. "|" .. tostring(U.valid(c) and mesh_key(c) or "")
end

function Looks.Apply(g, h, mode, hybridId)
    local b = built[g.id]
    local hostName = host_sig(h)
    if b and b.host == hostName and b.mode == mode and U.valid(h.actor) then
        if b.queue then continue_actors(b) end
        if mode == "hybrid" then
            if not Looks.MUTATION then
                if b.tinted then untint(b.tinted) b.tinted, b.mutation = nil, nil end
            elseif not b.mutation or not mutation_holds(b.tinted) then
                apply_mutation(b, g, h, hybridId)
            end
        end
        b.count = math.max(#b.actors, b.instances or 0)
        return b.count
    end
    Looks.Clear(g.id)
    local world = UEHelpers.GetWorld()
    if not U.valid(world) then return 0 end
    local base = h.loc or U.location(h.actor)
    if not base then return 0 end
    local yaw = 0
    pcall(function() yaw = h.actor:K2_GetActorRotation().Yaw end)
    local size = h.size or Looks.Size(h.actor, h.kind)
    b = { host = hostName, mode = mode, actors = {}, count = 0, hybridId = hybridId }
    built[g.id] = b
    local pieces, hostScale = nil, 1.0
    local packaged = mode == "hybrid" and Looks.Packaged(hybridId) or nil
    if mode == "hybrid" then apply_mutation(b, g, h, hybridId) end
    if mode == "hybrid" and not packaged and apply_placement(world, b, h, hybridId, g) then
        b.count = math.max(#b.actors, b.instances or 0)
        if swayer and b.instances and b.t and b.anchor and h.kind ~= "plot" then
            swayer:add(g.id, b, { X = b.t.loc.X, Y = b.t.loc.Y, Yaw = b.t.rot.Yaw })
        end
        return b.count
    end
    local attached = mode == "hybrid" and not packaged and Looks.Attachments(hybridId) or nil
    if packaged then
        local a = spawn(world, packaged, base, { Pitch = 0, Yaw = yaw, Roll = 0 }, 1.0)
        if a then b.actors[#b.actors + 1] = a end
        pieces = {}
    elseif attached then
        local actorScale = 1
        pcall(function() actorScale = h.actor:GetActorScale3D().Z end)
        pieces = Looks.AttachmentPieces(attached, actorScale)
    elseif mode == "pending" then
        pieces = Looks.PendingLayout(h.kind, size)
    elseif g.plants and #g.plants > 2 then
        local Rules = require("horticulture_splice_rules")
        pieces, hostScale = Looks.LayoutPlants(g.plants, Rules.HybridId, h.kind, size)
    else
        pieces, hostScale = Looks.Layout(hybridId, g.scion, h.kind, size)
    end
    place(world, b, base, yaw, pieces)
    b.count = #b.actors
    return b.count
end

-- The pieces of a Primelet at stageKey ("sprout", "primelet", "primeling")
-- and the height of its speech bubble above loc. A grown Mini not yet potted
-- sits on the ground without the pot.
function Looks.PrimeletPieces(stageKey, personality, potted)
    local pieces = Primelets.Pieces(stageKey, personality or "curious", havePak)
    if not pieces then
        local s = ({ sprout = 0.8, primelet = 1.15, primeling = 1.5 })[stageKey] or 1
        return Looks.PrimeletLayout(s), 60 * s
    end
    local stage = Primelets.Stage(stageKey) or {}
    local bubble = stage.speech_bubble_z_cm or 60
    if stage.potted and not potted then
        local out, lift = {}, stage.lift_cm or 0
        for _, p in ipairs(pieces) do
            if p.group ~= "pot" and p.name ~= "pot" then
                p.z = (p.z or 0) - lift
                out[#out + 1] = p
            end
        end
        return out, bubble - lift
    end
    return pieces, bubble
end

-- A Primelet at loc, facing yaw. Rebuilt only when it moves, grows or is
-- potted. Returns the number of pieces and the bubble height.
function Looks.ApplyPrimelet(id, loc, yaw, stageKey, personality, potted)
    local sig = string.format("%.0f,%.0f,%.0f,%.0f,%s,%s,%s", loc.X, loc.Y, loc.Z, yaw or 0,
        tostring(stageKey), tostring(personality), potted and "pot" or "")
    local b = built[id]
    if b and b.host == sig and b.count > 0 and U.valid(b.actors[1]) then return b.count, b.bubbleZ end
    Looks.Clear(id)
    local world = UEHelpers.GetWorld()
    if not U.valid(world) then return 0 end
    local pieces, bubbleZ = Looks.PrimeletPieces(stageKey, personality, potted)
    b = { host = sig, mode = "primelet", actors = {}, count = 0, bubbleZ = bubbleZ }
    built[id] = b
    place(world, b, loc, yaw or 0, pieces)
    b.count = #b.actors
    return b.count, bubbleZ
end

return Looks

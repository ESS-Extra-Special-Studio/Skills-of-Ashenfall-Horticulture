-- What a hybrid looks like: the game's own meshes placed on and around the
-- host (potatoes at an ash's roots, cabbages in an oak's canopy), and a tint
-- and scale on the host itself. Nothing is cooked; every mesh ships with the
-- game. When a cooked hybrid mesh is installed (a ~mods pak with
-- /Game/Mods/SkillsOfAshenfallHorticulture/...), it is loaded by path and
-- used instead of the kitbash. meshes.txt beside the Scripts folder can point
-- a hybrid at another path ("TuberwoodAsh = /Game/Mods/.../SM_Name").
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
}

-- Cooked hybrid meshes, when the asset pak is installed. "Additions" meshes
-- hold only the new parts, modelled on the vanilla host's pivot.
local MOD_ART = "/Game/Mods/SkillsOfAshenfallHorticulture/Art/Plants/"
Looks.PACKAGED = {
    TuberwoodAsh = asset(MOD_ART .. "TuberwoodAsh/SM_TuberwoodAsh_Additions_01"),
    BrassicaOak = asset(MOD_ART .. "BrassicaOak/SM_BrassicaOak_Additions_01"),
    Brassitato = asset(MOD_ART .. "Brassitato/SM_Brassitato_Additions_01"),
    SheafAsh = asset(MOD_ART .. "SheafAsh/SM_SheafAsh_Additions_01"),
    WeepingOak = asset(MOD_ART .. "WeepingOak/SM_WeepingOak_Additions_01"),
}

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

function Looks.Layout(hybridId, scion, hostKind, size)
    local out = {}
    local small = hostKind == "sapling" or hostKind == "plot"
    local s = small and math.max(size.height / 600, 0.25) or 1
    if hybridId == "TuberwoodAsh" then
        local r = math.max(math.min(size.radius * 0.12, 70), 18)
        ring(out, "potato", 9, r, -3, 2.4 * s, { jitter = 0.25, dz = 4, pitch = 20 })
        ring(out, "potatoPlant", 3, r * 1.6, 0, 1.0 * s, { phase = 0.5 })
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

local function load(path)
    if meshCache[path] ~= nil then return meshCache[path] or nil end
    local obj = StaticFindObject(path)
    if not U.valid(obj) and LoadAsset then
        local ok, loaded = pcall(LoadAsset, path)
        if ok and U.valid(loaded) then obj = loaded end
    end
    if U.valid(obj) then
        meshCache[path] = obj
        return obj
    end
    meshCache[path] = false
    return nil
end

function Looks.Init(util, dir)
    U = util
    UEHelpers = require("UEHelpers")
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
    pcall(function() actor:SetActorScale3D({ X = scale, Y = scale, Z = scale }) end)
    return actor
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
    local t = Looks.Tint(scion)
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
        if U.valid(s.comp) and s.material then pcall(function() s.comp:SetMaterial(s.index, s.material) end) end
    end
end

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

function Looks.Clear(graftId)
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

-- Builds the look for graft g on host h = { actor, kind, loc, comps }
-- (comps: the meshes to tint and scale; plots pass the plant mesh).
-- mode: "pending" or "hybrid". Returns the number of pieces placed.
function Looks.Apply(g, h, mode, hybridId)
    local b = built[g.id]
    local hostName = U.full(h.actor)
    if b and b.host == hostName and b.mode == mode and U.valid(h.actor) then return b.count end
    Looks.Clear(g.id)
    local world = UEHelpers.GetWorld()
    if not U.valid(world) then return 0 end
    local base = h.loc or U.location(h.actor)
    if not base then return 0 end
    local yaw = 0
    pcall(function() yaw = h.actor:K2_GetActorRotation().Yaw end)
    local size = h.size or Looks.Size(h.actor, h.kind)
    b = { host = hostName, mode = mode, actors = {}, count = 0 }
    built[g.id] = b
    local pieces, hostScale = nil, 1.0
    local packaged = mode == "hybrid" and Looks.Packaged(hybridId) or nil
    if packaged then
        local a = spawn(world, packaged, base, { Pitch = 0, Yaw = yaw, Roll = 0 }, 1.0)
        if a then b.actors[#b.actors + 1] = a end
        pieces = {}
    elseif mode == "pending" then
        pieces = Looks.PendingLayout(h.kind, size)
    else
        pieces, hostScale = Looks.Layout(hybridId, g.scion, h.kind, size)
    end
    for _, p in ipairs(pieces) do
        local mesh = load(Looks.MESH[p.mesh])
        if mesh then
            local x, y = rotate(p.x, p.y, yaw)
            local a = spawn(world, mesh, { X = base.X + x, Y = base.Y + y, Z = base.Z + p.z },
                { Pitch = p.pitch or 0, Yaw = (p.yaw or 0) + yaw, Roll = p.roll or 0 }, p.scale)
            if a then b.actors[#b.actors + 1] = a end
        else
            U.log_once("mesh" .. p.mesh, "Hybrid look: mesh " .. tostring(Looks.MESH[p.mesh]) .. " could not be loaded")
        end
    end
    if mode == "hybrid" then
        local comps = h.comps or mesh_components(h.actor)
        if not Looks.NO_TINT[hybridId] then b.tinted = tint(comps, g.scion) end
        if hostScale ~= 1.0 then b.scaled = scale_comps(comps, hostScale) end
    end
    b.count = #b.actors
    return b.count
end

return Looks

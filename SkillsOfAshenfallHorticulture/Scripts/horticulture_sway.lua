-- Wind sway for hybrid looks, ported from DragonwildsAssets
-- scripts/lua/hybrid_sway.lua (docs/PLANT_HYBRID_WORKFLOW.md "Wind sway").
-- Canopy wind is a material offset on the leaves, so fruit placed in a tree
-- hangs still unless it is moved. Every piece of a look hangs from one
-- anchor at the host's pivot (the trunk base); tilting the anchor a fraction
-- of a degree moves each fruit by its height times the angle, the same
-- height-proportional bend as the canopy, so fruit and stalks move with the
-- branches. Wind comes from the game's MPC_Global, which the foliage reads.
--
-- The maths is pure Lua. The game side comes in through env, and nothing
-- here holds an engine object: each tick looks the world and the parameter
-- collection up again, and trees are the caller's plain tables.
local Sway = {}

Sway.defaults = {
    rate_hz = 15,              -- sway updates per second
    radius_cm = 3000,          -- only trees within 30 m of the player sway
    max_trees = 12,            -- nearest N per update (budget cap)
    base_deg = 0.35,           -- tilt at Wind_Intensity == ref_intensity
    max_deg = 1.0,
    ref_intensity = 20,        -- MPC_Global Wind_Intensity default
    gust_wavelength_cm = 8626, -- the foliage materials' "Gust Pattern Size"
    period_s = 3.5,            -- main sway period
    cross_frac = 0.25,         -- side-to-side share across the wind
    calm_dir = { X = 0.8, Y = 0.6 }, -- used when the game leaves Wind_Direction at 0
    mpc = "/Game/Materials/ParamCollection/MPC_Global.MPC_Global",
}

-- Tilt (degrees, FRotator pitch and roll in the host's frame) for one tree.
-- wind_dir = {X, Y} (any length; zero means calm), pos = tree {X, Y}.
function Sway.tilt(cfg, t, wind_dir, intensity, pos)
    local dx, dy = wind_dir.X or 0, wind_dir.Y or 0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-4 or intensity <= 0 then return 0, 0 end
    dx, dy = dx / len, dy / len
    local amp = math.min(cfg.max_deg, cfg.base_deg * intensity / cfg.ref_intensity)
    -- A wave travelling along the wind: neighbouring trees sway a little out
    -- of phase, like the foliage.
    local phase = 2 * math.pi * ((pos.X * dx + pos.Y * dy) / cfg.gust_wavelength_cm - t / cfg.period_s)
    local along = amp * (0.55 + 0.45 * math.sin(phase)) -- leans downwind, never back past upright
    local across = amp * cfg.cross_frac * math.sin(phase * 1.7 + 1.3)
    -- FRotator maps local +Z to (-cosR*sinP, sinR, cosR*cosP).
    local lx, ly = along * dx - across * dy, along * dy + across * dx
    return -lx, ly
end

-- World wind direction into a host's frame (planted trees carry a yaw).
function Sway.to_local(dir, yaw_deg)
    local a = -math.rad(yaw_deg or 0)
    local c, s = math.cos(a), math.sin(a)
    return { X = dir.X * c - dir.Y * s, Y = dir.X * s + dir.Y * c }
end

-- The game's wind: direction {X, Y} and intensity from MPC_Global, read
-- fresh each call. nil when the collection cannot be read.
function Sway.GameWind(cfg, world)
    local dir, intensity = nil, nil
    pcall(function()
        local lib = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local mpc = StaticFindObject(cfg.mpc)
        if not (lib and lib:IsValid() and mpc and mpc:IsValid() and world and world:IsValid()) then return end
        local d = lib:GetVectorParameterValue(world, mpc, FName("Wind_Direction"))
        intensity = lib:GetScalarParameterValue(world, mpc, FName("Wind_Intensity"))
        dir = { X = d.R or 0, Y = d.G or 0 }
    end)
    if not (dir and type(intensity) == "number") then return nil end
    return dir, intensity
end

-- env: { clock(), wind() -> dir, intensity, player() -> {X, Y},
-- apply(tree, pitch, roll) -> false when the tree is gone }.
function Sway.new(cfg, env)
    cfg = setmetatable(cfg or {}, { __index = Sway.defaults })
    local self = { cfg = cfg, trees = {}, calm = false }

    -- tree: the caller's table for one look; pos = {X, Y, Yaw}.
    function self:add(key, tree, pos) self.trees[key] = { tree = tree, pos = pos } end
    function self:remove(key) self.trees[key] = nil end
    function self:count() local n = 0 for _ in pairs(self.trees) do n = n + 1 end return n end

    -- Returns how many trees were tilted.
    function self:tick()
        local t = env.clock()
        local dir, intensity = env.wind()
        local player = env.player()
        if not (dir and player) then return 0 end
        self.calm = math.abs(dir.X) + math.abs(dir.Y) < 1e-4
        if self.calm then dir = cfg.calm_dir end
        local near = {}
        local r2 = cfg.radius_cm * cfg.radius_cm
        for key, tr in pairs(self.trees) do
            local dx, dy = tr.pos.X - player.X, tr.pos.Y - player.Y
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then near[#near + 1] = { key = key, tr = tr, d2 = d2 }
            elseif tr.tilted then
                -- Out of range: parked upright.
                env.apply(tr.tree, 0, 0)
                tr.tilted = false
            end
        end
        table.sort(near, function(a, b) return a.d2 < b.d2 end)
        local n = 0
        for k = 1, math.min(#near, cfg.max_trees) do
            local tr = near[k].tr
            local pitch, roll = Sway.tilt(cfg, t, Sway.to_local(dir, tr.pos.Yaw), intensity, tr.pos)
            if env.apply(tr.tree, pitch, roll) == false then
                self.trees[near[k].key] = nil
            else
                tr.tilted = true
                n = n + 1
            end
        end
        -- Beyond the budget: parked upright rather than frozen mid-lean.
        for k = cfg.max_trees + 1, #near do
            local tr = near[k].tr
            if tr.tilted then
                env.apply(tr.tree, 0, 0)
                tr.tilted = false
            end
        end
        return n
    end
    return self
end

return Sway

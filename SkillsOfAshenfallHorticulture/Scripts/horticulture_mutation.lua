-- Mutation tints: each hybrid's host leaves (tree) or plant (crop) take on
-- their own colour, so a hybrid reads as a mutated plant of its species.
-- Pure Lua, no game calls; horticulture_looks applies the result.
--
-- The vanilla leaf material (M_Foliage_Tree and its instances) has
-- RandomColor_HueShift (scalar, fraction of a full turn) and Color_Mult_A /
-- Color_Mult_B (colour multiplies). A tree Blueprint normally feeds the
-- material its per-tree data; a copy of the tree's mesh without it renders
-- the canopy deep blue-violet, which is where Tuberwood Ash's colour came
-- from. Setting the same parameters on a dynamic instance of the host's own
-- leaf material gives that look on purpose, at any time of day.
local M = {}

-- Hand-picked for the flagships. hue: RandomColor_HueShift; mult: the
-- Color_Mult colour (1, 1, 1 leaves the texture's colour).
M.FLAGSHIP = {
    TuberwoodAsh = { name = "deep blue-violet", hue = 0.42, mult = { R = 0.55, G = 0.5, B = 1.0 } },
    BrassicaOak = { name = "cabbage blue-green", hue = 0.1, mult = { R = 0.75, G = 0.95, B = 0.9 } },
    Brassitato = { name = "purple-veined", hue = 0.72, mult = { R = 0.9, G = 0.75, B = 0.95 } },
    SheafAsh = { name = "harvest gold", hue = -0.08, mult = { R = 1.0, G = 0.9, B = 0.55 } },
    WeepingOak = { name = "silver-green", hue = 0.05, mult = { R = 0.85, G = 0.95, B = 0.85 } },
    BrambleOak = { name = "bramble red", hue = -0.2, mult = { R = 1.0, G = 0.7, B = 0.65 } },
    TwoBarkAsh = { name = "copper", hue = -0.12, mult = { R = 1.0, G = 0.8, B = 0.6 } },
    WeepingCabbage = { name = "onion-skin pink", hue = 0.85, mult = { R = 1.0, G = 0.8, B = 0.85 } },
}

-- Ordinary combinations: one of these, chosen by the combination itself, so
-- the same pair always looks the same. Subtle to moderate; each still reads
-- as its species.
M.PALETTE = {
    { name = "teal", hue = 0.15, mult = { R = 0.8, G = 1.0, B = 0.95 } },
    { name = "amber", hue = -0.06, mult = { R = 1.0, G = 0.9, B = 0.7 } },
    { name = "plum", hue = 0.7, mult = { R = 0.9, G = 0.8, B = 0.95 } },
    { name = "rust", hue = -0.14, mult = { R = 1.0, G = 0.8, B = 0.7 } },
    { name = "frost", hue = 0.3, mult = { R = 0.85, G = 0.92, B = 1.0 } },
    { name = "lime", hue = 0.04, mult = { R = 0.95, G = 1.0, B = 0.75 } },
    { name = "rose", hue = 0.88, mult = { R = 1.0, G = 0.85, B = 0.9 } },
    { name = "indigo", hue = 0.5, mult = { R = 0.8, G = 0.8, B = 1.0 } },
}

-- FNV-1a over the key's bytes, 32 bits.
function M.Hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h ~ s:byte(i)) * 16777619 % 4294967296
    end
    return h
end

-- The tint for a hybrid: its flagship entry, else a palette entry picked by
-- the combination key (Rules.ComboKey or Rules.PlantsKey).
function M.For(hybridId, comboKey)
    local f = M.FLAGSHIP[hybridId]
    if f then return f end
    local key = comboKey or hybridId
    if not key then return nil end
    return M.PALETTE[M.Hash(key) % #M.PALETTE + 1]
end

-- Which of a host's materials take the tint. Trees: leaves only (their bark
-- shares the parameter names). Crops: the whole plant mesh.
local LEAF = { "leaves", "leaf", "canopy", "foliage", "needles", "frond" }

function M.Takes(kind, materialPath)
    if kind == "plot" then return true end
    local p = tostring(materialPath or ""):lower()
    for _, w in ipairs(LEAF) do
        if p:find(w, 1, true) then return true end
    end
    return false
end

return M

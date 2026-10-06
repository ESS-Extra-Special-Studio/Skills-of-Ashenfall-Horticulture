-- Mutation tints: each hybrid's host leaves (tree) or plant (crop) take on
-- their own colour, so a hybrid reads as a mutated plant of its species.
-- Pure Lua, no game calls; horticulture_looks applies the result.
--
-- The vanilla leaf material (M_Foliage_Tree and its instances) multiplies
-- its colour by Color_Mult_A/B and adds Color_Add_A/B, each weighted by
-- Color_Mult_Blend / Color_Add_Blend (0 on vanilla trees). Tested in game on
-- a Blueprint ash: only these two change the canopy; RandomColor_HueShift,
-- Color Top/Bottom and Subsurface Color do not. The add is what turns a
-- canopy deep blue-violet.
local M = {}

-- Hand-picked for the flagships. mult: Color_Mult (1, 1, 1 keeps the leaf's
-- colour); add: Color_Add (0, 0, 0 adds nothing).
M.FLAGSHIP = {
    TuberwoodAsh = { name = "deep blue-violet", mult = { R = 0.35, G = 0.3, B = 0.6 }, add = { R = 0.1, G = 0.02, B = 0.4 } },
    BrassicaOak = { name = "cabbage blue-green", mult = { R = 0.7, G = 0.9, B = 1.0 }, add = { R = 0.0, G = 0.04, B = 0.1 } },
    Brassitato = { name = "purple-veined", mult = { R = 0.85, G = 0.7, B = 0.9 }, add = { R = 0.08, G = 0.0, B = 0.1 } },
    SheafAsh = { name = "harvest gold", mult = { R = 1.0, G = 0.85, B = 0.4 }, add = { R = 0.18, G = 0.1, B = 0.0 } },
    WeepingOak = { name = "silver-green", mult = { R = 0.85, G = 0.95, B = 0.85 }, add = { R = 0.06, G = 0.08, B = 0.06 } },
    BrambleOak = { name = "bramble red", mult = { R = 0.9, G = 0.55, B = 0.5 }, add = { R = 0.18, G = 0.0, B = 0.02 } },
    TwoBarkAsh = { name = "copper", mult = { R = 0.95, G = 0.65, B = 0.4 }, add = { R = 0.14, G = 0.05, B = 0.0 } },
    WeepingCabbage = { name = "onion-skin pink", mult = { R = 1.0, G = 0.75, B = 0.85 }, add = { R = 0.12, G = 0.02, B = 0.08 } },
}

-- Ordinary combinations: one of these, chosen by the combination itself, so
-- the same pair always looks the same. Subtle to moderate; each still reads
-- as its species.
M.PALETTE = {
    { name = "teal", mult = { R = 0.7, G = 1.0, B = 0.95 }, add = { R = 0.0, G = 0.04, B = 0.08 } },
    { name = "amber", mult = { R = 1.0, G = 0.85, B = 0.55 }, add = { R = 0.1, G = 0.05, B = 0.0 } },
    { name = "plum", mult = { R = 0.8, G = 0.65, B = 0.85 }, add = { R = 0.08, G = 0.0, B = 0.1 } },
    { name = "rust", mult = { R = 0.95, G = 0.65, B = 0.5 }, add = { R = 0.12, G = 0.02, B = 0.0 } },
    { name = "frost", mult = { R = 0.85, G = 0.95, B = 1.0 }, add = { R = 0.05, G = 0.07, B = 0.1 } },
    { name = "lime", mult = { R = 0.95, G = 1.0, B = 0.6 }, add = { R = 0.05, G = 0.08, B = 0.0 } },
    { name = "rose", mult = { R = 1.0, G = 0.75, B = 0.8 }, add = { R = 0.1, G = 0.02, B = 0.05 } },
    { name = "indigo", mult = { R = 0.6, G = 0.6, B = 0.95 }, add = { R = 0.03, G = 0.02, B = 0.15 } },
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

-- The material parameters for a tint: vectors and scalars by name.
function M.Params(t)
    local m = { R = t.mult.R, G = t.mult.G, B = t.mult.B, A = 1 }
    local a = { R = t.add.R, G = t.add.G, B = t.add.B, A = 1 }
    return { Color_Mult_A = m, Color_Mult_B = m, Color_Add_A = a, Color_Add_B = a },
        { Color_Mult_Blend = 1, Color_Add_Blend = 1 }
end

-- Which of a host's materials take the tint. Trees: leaves, and the distant
-- impostor so the colour holds far away; not bark (it shares the parameter
-- names). Only the material's own name counts: tree folders are named
-- Foliage. Crops: the whole plant mesh.
local LEAF = { "leaves", "leaf", "canopy", "needles", "frond", "_imp" }

function M.Takes(kind, materialPath)
    if kind == "plot" then return true end
    local p = tostring(materialPath or ""):lower():match("([^/]+)$") or ""
    for _, w in ipairs(LEAF) do
        if p:find(w, 1, true) then return true end
    end
    return false
end

return M

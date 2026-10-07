-- Horticulture perks. None is active in 1.0.0: the skills menu shows no perk
-- rows, and Perks.Has always answers false.
local Perks = {}

Perks.ACTIVE = {}

-- Rows for ESL.RegisterSkill (perks = ...).
function Perks.Rows()
    return {}
end

function Perks.Has(id, level)
    local p = Perks.ACTIVE[id]
    return p ~= nil and (level or 0) >= p.level
end

return Perks

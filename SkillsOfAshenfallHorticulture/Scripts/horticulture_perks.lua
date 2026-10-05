-- Proposed Horticulture perks. None is active: the rows show in the skills
-- menu only with dev.txt, marked as proposals, and Perks.Has always answers
-- false until a perk is approved and its effect written.
local Perks = {}

Perks.PROPOSED = {
    { id = "steady_hands", level = 5, name = "Steady hands", description = "Cuttings keep for three dawns instead of two." },
    { id = "twine_wise", level = 10, name = "Twine-wise", description = "Grafts are 5% more likely to take." },
    { id = "deep_satchel", level = 15, name = "Deep satchel", description = "Your cutting satchel holds eight." },
    { id = "bountiful", level = 20, name = "Bountiful", description = "Hybrid trees give one more of each product." },
    { id = "brassicas_heir", level = 25, name = "Brassica's heir", description = "A rejected graft gives its cutting back." },
}

Perks.ACTIVE = {}

-- Rows for ESL.RegisterSkill (perks = ...).
function Perks.Rows(dev)
    local out = {}
    if not dev then return out end
    for _, p in ipairs(Perks.PROPOSED) do
        out[#out + 1] = { level = p.level, name = "[Proposal] " .. p.name, description = p.description }
    end
    return out
end

function Perks.Has(id, level)
    local p = Perks.ACTIVE[id]
    return p ~= nil and (level or 0) >= p.level
end

return Perks

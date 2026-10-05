-- The splicing loop on a state table from horticulture_splice_store: take a
-- cutting, graft it, resolve grafts at dawn, pick from hybrids. Pure Lua; the
-- game side (horticulture_splicing) supplies what the player is aiming at
-- and pays the XP.
local Rules = require("horticulture_splice_rules")

local Core = {}

-- Within this distance (2D, cm) a host is the same host: a sapling grows
-- into its tree a few centimetres away.
Core.TREE_MATCH = 150
Core.PLOT_MATCH = 60

local function dist2d(a, b)
    if not (a and b and a.x and b.x) then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function Core.Selected(st)
    return st.cuttings[st.selected]
end

function Core.Cycle(st)
    if #st.cuttings == 0 then return nil end
    st.selected = st.selected % #st.cuttings + 1
    return st.cuttings[st.selected]
end

-- The graft on a host, matched by plot id or by position.
function Core.GraftOn(st, host)
    for _, g in ipairs(st.grafts) do
        if host.kind == "plot" and g.kind == "plot" then
            if (host.key and g.key == host.key) or (not host.key and dist2d(g, host) <= Core.PLOT_MATCH) then return g end
        elseif host.kind ~= "plot" and g.kind ~= "plot" then
            if dist2d(g, host) <= Core.TREE_MATCH then return g end
        end
    end
    return nil
end

function Core.Remove(st, g)
    for i, other in ipairs(st.grafts) do
        if other == g then
            table.remove(st.grafts, i)
            return true
        end
    end
    return false
end

-- src: { species, kind, key, level, axePower, alive }. Returns the cutting,
-- or nil and the reason.
function Core.TakeCutting(st, src)
    local ok, why = Rules.CanCut(src)
    if not ok then return nil, why end
    if #st.cuttings >= Rules.SATCHEL_SIZE then
        return nil, string.format("Your cutting satchel is full (%d). Graft one first", Rules.SATCHEL_SIZE)
    end
    if src.key and st.sources[src.key] == st.dawn then
        return nil, "You already took a cutting from this plant today"
    end
    local c = { species = src.species, taken = st.dawn }
    st.cuttings[#st.cuttings + 1] = c
    st.selected = #st.cuttings
    if src.key then st.sources[src.key] = st.dawn end
    return c
end

-- host: { species, kind, key, planted, stage, tier, x, y, z, bonus }.
-- Returns the graft, or nil and the reason.
function Core.Graft(st, host, level)
    local existing = Core.GraftOn(st, host)
    if existing then
        if existing.state == "pending" then return nil, "Already grafted. Come back after dawn" end
        return nil, "This is already a " .. Rules.HybridName(existing.scion, existing.host)
    end
    local c = Core.Selected(st)
    if not c then return nil, "Your satchel is empty. Take a cutting first" end
    local ok, why = Rules.CanGraft(c.species, host, level)
    if not ok then return nil, why end
    table.remove(st.cuttings, st.selected)
    if st.selected > #st.cuttings then st.selected = math.max(1, #st.cuttings) end
    local g = {
        id = "g" .. st.nextId, kind = host.kind, host = host.species, scion = c.species,
        state = "pending", made = st.dawn, x = host.x, y = host.y, z = host.z,
        key = host.key, tier = host.tier, bonus = host.bonus,
    }
    st.nextId = st.nextId + 1
    st.grafts[#st.grafts + 1] = g
    return g
end

-- Chance for a pending graft. The very first graft a character makes
-- always takes, so the loop is learned before it can disappoint.
function Core.ChanceFor(st, g, level)
    if not st.firstTaken then return 100 end
    return Rules.Chance(g.scion, { species = g.host, tier = g.tier }, level, g.bonus)
end

-- One dawn. rng(n) returns 1..n. alive(g) returns false when the host is
-- known to be gone (harvested, felled, dug up), nil when unknown.
-- Returns outcomes { graft, result = "takes"|"rejected"|"lost", chance }
-- and the cuttings that wilted.
function Core.Dawn(st, level, rng, alive)
    st.dawn = st.dawn + 1
    local outcomes = {}
    local keep = {}
    for _, g in ipairs(st.grafts) do
        if g.state == "pending" and (g.made or 0) < st.dawn then
            if alive and alive(g) == false then
                outcomes[#outcomes + 1] = { graft = g, result = "lost" }
            else
                local chance = Core.ChanceFor(st, g, level)
                if rng(100) <= chance then
                    g.state = "hybrid"
                    st.firstTaken = true
                    keep[#keep + 1] = g
                    outcomes[#outcomes + 1] = { graft = g, result = "takes", chance = chance }
                else
                    outcomes[#outcomes + 1] = { graft = g, result = "rejected", chance = chance }
                end
            end
        else
            keep[#keep + 1] = g
        end
    end
    st.grafts = keep
    local wilted, fresh = {}, {}
    for _, c in ipairs(st.cuttings) do
        if st.dawn - (c.taken or 0) >= Rules.WILT_DAWNS then wilted[#wilted + 1] = c else fresh[#fresh + 1] = c end
    end
    st.cuttings = fresh
    if st.selected > #fresh then st.selected = math.max(1, #fresh) end
    for k, d in pairs(st.sources) do
        if d ~= st.dawn then st.sources[k] = nil end
    end
    return outcomes, wilted
end

-- Tree and sapling hybrids give once per in-game day.
function Core.CanPick(st, g)
    if not g or g.state ~= "hybrid" then return false, "Nothing to pick yet" end
    if g.kind == "plot" then return false, "Harvest the crop as usual; the graft adds to it" end
    if g.lastPick == st.dawn then return false, "Already picked today. More after dawn" end
    return true
end

function Core.Pick(st, g)
    local ok, why = Core.CanPick(st, g)
    if not ok then return nil, why end
    g.lastPick = st.dawn
    return Rules.Products(g.scion, g.host)
end

-- A crop host was harvested: its graft ends. Products only for a hybrid.
function Core.Harvested(st, g)
    Core.Remove(st, g)
    if g.state ~= "hybrid" then return {} end
    return Rules.Products(g.scion, g.host)
end

return Core

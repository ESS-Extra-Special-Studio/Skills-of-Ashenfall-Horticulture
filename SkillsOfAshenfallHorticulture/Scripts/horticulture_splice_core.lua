-- The splicing loop on a state table from horticulture_splice_store: take a
-- cutting, graft it, resolve grafts at dawn, pick from hybrids. Pure Lua; the
-- game side (horticulture_splicing) supplies what the player is aiming at
-- and pays the XP.
local Rules = require("horticulture_splice_rules")
local Store = require("horticulture_splice_store")
local Primelet = require("horticulture_primelet")

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
function Core.CanTakeCutting(st, src)
    if src.species == Primelet.SPECIES then return false, "You will not take a cutting from a minor miracle. Alt+G picks it up" end
    local ok, why = Rules.CanCut(src)
    if not ok then return false, why end
    if #st.cuttings >= Rules.SATCHEL_SIZE then
        return false, string.format("Your cutting satchel is full (%d). Graft one first", Rules.SATCHEL_SIZE)
    end
    if src.key and st.sources[src.key] == st.dawn then
        return false, "You already took a cutting from this plant today"
    end
    return true
end

-- A plot gives one prime cutting per crop cycle (ROOTSTOCK.primeCooldown
-- dawns); otherwise the cutting is common.
function Core.TakeCutting(st, src)
    local ok, why = Core.CanTakeCutting(st, src)
    if not ok then return nil, why end
    local quality = Rules.CuttingQuality(src)
    st.primeSources = st.primeSources or {}
    if quality >= 2 and src.key then
        local last = st.primeSources[src.key]
        if last and st.dawn - last < Rules.ROOTSTOCK.primeCooldown then quality = 1 else st.primeSources[src.key] = st.dawn end
    end
    local c = { species = src.species, taken = st.dawn, quality = quality }
    st.cuttings[#st.cuttings + 1] = c
    st.selected = #st.cuttings
    if src.key then st.sources[src.key] = st.dawn end
    return c
end

-- A dormant hybrid tree that this cutting can wake: the same crop (prime),
-- or for a wood hybrid a fresh cutting of the same wood. Tree cuttings only
-- come from living trees and wilt in WILT_DAWNS, so any in the satchel is fresh.
local function refreshable(existing, c)
    return existing.state == "hybrid" and Rules.UsesVigour(existing) and (existing.vigour or 0) <= 0
        and c and not c.primelet and c.species == existing.scion
end

local function wakes(existing, c)
    return Rules.IsWoodHybrid(existing) or (c.quality or 1) >= 2
end

-- host: { species, kind, key, planted, stage, tier, x, y, z, bonus, world }.
-- Returns the graft, or nil and the reason.
-- Whether cutting c (default: the selected one) can be grafted onto host.
function Core.CanGraft(st, host, level, c)
    c = c or Core.Selected(st)
    local existing = Core.GraftOn(st, host)
    if existing then
        if existing.state == "pending" then return false, "Already grafted. Come back after dawn" end
        if refreshable(existing, c) then
            if wakes(existing, c) then return true, "refresh" end
            return false, Rules.DormantText(existing.scion) .. ". " .. Rules.PRIME_HOWTO
        end
        local why = "This is already a " .. Rules.PlantsName(existing.plants)
        if c and not c.primelet and Rules.MaxPlants(level) > #existing.plants then
            local ok, refuse = Rules.CanAddTo(existing.plants, c.species, host, level, c.quality)
            if not ok then why = refuse end
        end
        return false, why
    end
    if not c then return false, "Your satchel is empty. Take a cutting first" end
    if c.primelet then return false, "Set the Primelet down first (G on open ground)" end
    return Rules.CanGraft(c.species, host, level, c.quality)
end

local function use_selected(st)
    local c = Core.Selected(st)
    table.remove(st.cuttings, st.selected)
    if st.selected > #st.cuttings then st.selected = math.max(1, #st.cuttings) end
    return c
end

-- Returns the graft and "refresh" when a prime cutting woke a dormant tree
-- (no dawn roll), or nil and the reason.
function Core.Graft(st, host, level)
    local ok, why = Core.CanGraft(st, host, level)
    if not ok then return nil, why end
    if why == "refresh" then
        local g = Core.GraftOn(st, host)
        local c = use_selected(st)
        g.vigour = Rules.VigourFor(g)
        g.quality = c.quality or 1
        return g, "refresh"
    end
    local c = use_selected(st)
    local g = Store.SetPlants({
        id = "g" .. st.nextId, kind = host.kind,
        state = "pending", made = st.dawn, x = host.x, y = host.y, z = host.z,
        key = host.key, tier = host.tier, bonus = host.bonus, world = host.world, quality = c.quality or 1,
    }, { host.species, c.species })
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

-- Cabbage onto cabbage: the graft that can become a Brassica Primelet.
function Core.IsPrimeletGraft(g)
    return #g.plants == 2 and g.host == "FPD_Cabbage" and g.scion == "FPD_Cabbage"
end

-- Where a primelet climbs out to: beside its plot.
Core.PRIMELET_OFFSET = 90

-- One dawn. rng(n) returns 1..n. alive(g) returns false when the host is
-- known to be gone (harvested, felled, dug up), nil when unknown.
-- opts: { primeletChance (percent) }.
-- Returns outcomes { graft, result = "takes"|"rejected"|"lost"|"primelet",
-- chance, primelet }, the cuttings that wilted and the primelets that grew
-- a stage.
function Core.Dawn(st, level, rng, alive, opts)
    opts = opts or {}
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
                    st.firstTaken = true
                    local primeChance = opts.primeletChance or Rules.PRIMELET.chance
                    if Core.IsPrimeletGraft(g) and Primelet.Roll(rng, primeChance) then
                        local p = Primelet.New(st, (g.x or 0) + Core.PRIMELET_OFFSET, g.y or 0, g.z or 0, g.world, rng)
                        outcomes[#outcomes + 1] = { graft = g, result = "primelet", chance = chance, primelet = p }
                    else
                        g.state = "hybrid"
                        if Rules.UsesVigour(g) then g.vigour = Rules.VigourFor(g) end
                        keep[#keep + 1] = g
                        outcomes[#outcomes + 1] = { graft = g, result = "takes", chance = chance }
                    end
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
        if not c.primelet and st.dawn - (c.taken or 0) >= Rules.WILT_DAWNS then wilted[#wilted + 1] = c else fresh[#fresh + 1] = c end
    end
    st.cuttings = fresh
    if st.selected > #fresh then st.selected = math.max(1, #fresh) end
    for k, d in pairs(st.sources) do
        if d ~= st.dawn then st.sources[k] = nil end
    end
    return outcomes, wilted, Primelet.Dawn(st)
end

-- Tree and sapling hybrids give once per in-game day and use one vigour, going
-- dormant at none. A crop scion is picked; a wood hybrid only gives to a
-- chop (how = "chop"), never to a pick. The third return names the reason:
-- "dormant", "chop" (a wood hybrid wants a swing) or nil.
function Core.CanPick(st, g, how)
    if not g or g.state ~= "hybrid" then return false, "Nothing to pick yet" end
    if g.kind == "plot" then return false, "Harvest the crop as usual; the graft adds to it" end
    if Rules.UsesVigour(g) and (g.vigour or 0) <= 0 then return false, Rules.DormantText(g.scion), "dormant" end
    local wood = Rules.IsWoodHybrid(g)
    if g.lastPick == st.dawn then
        return false, wood and "Already chopped for bonus wood today. More after dawn" or "Already picked today. More after dawn"
    end
    if wood and how ~= "chop" then return false, Rules.ChopHowTo(g), "chop" end
    return true
end

local function give(g, opts)
    local o = { tree = true }
    for k, v in pairs(opts or {}) do o[k] = v end
    return Rules.Products(g.scion, g.host, o)
end

-- opts: Rules.Products tree options (farming, live).
function Core.Pick(st, g, opts)
    local ok, why = Core.CanPick(st, g)
    if not ok then return nil, why end
    g.lastPick = st.dawn
    if Rules.UsesVigour(g) then g.vigour = (g.vigour or 0) - 1 end
    return give(g, opts)
end

-- A swing at a wood hybrid with an axe of axePower. The first chop each day
-- with an axe that could fell every wood in it gives the bonus wood.
-- Returns the products, or nil, the reason and its kind ("weak", "dormant",
-- "chop" when it was already chopped today).
function Core.Chop(st, g, axePower, opts)
    if not Rules.IsWoodHybrid(g) then return nil, "Only wood hybrids give to a chop" end
    local ok, why, reason = Core.CanPick(st, g, "chop")
    if not ok then return nil, why, reason or "chop" end
    local need = Rules.WoodAxePower(g)
    if (axePower or 0) < need then
        return nil, "The bonus wood needs " .. Rules.AnAxe(need) .. " or better", "weak"
    end
    g.lastPick = st.dawn
    g.vigour = (g.vigour or 0) - 1
    return give(g, opts)
end

-- A crop host was harvested: its graft ends. Products only for a hybrid.
-- opts: Rules.Products plot options; the graft's own fed, wet and quality
-- fill compost, water and prime.
function Core.Harvested(st, g, opts)
    Core.Remove(st, g)
    if g.state ~= "hybrid" then return {} end
    local o = { plot = true, compost = g.fed == true, water = g.wet == true, prime = (g.quality or 1) >= 2, tier = g.tier }
    for k, v in pairs(opts or {}) do o[k] = v end
    return Rules.Products(g.scion, g.host, o)
end

-- A hybrid tree was felled: its graft ends. At most one pick's worth falls
-- with the logs, and only when a pick was left (not picked today, vigour
-- remaining). A wood hybrid's share also needs the axe its chops need
-- (opts.axePower).
function Core.Felled(st, g, opts)
    Core.Remove(st, g)
    if g.state ~= "hybrid" or g.lastPick == st.dawn then return {} end
    if Rules.UsesVigour(g) and (g.vigour or 0) <= 0 then return {} end
    if Rules.IsWoodHybrid(g) and ((opts and opts.axePower) or 0) < Rules.WoodAxePower(g) then return {} end
    return give(g, opts)
end

return Core

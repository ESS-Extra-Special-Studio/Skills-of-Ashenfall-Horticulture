-- The Brassica Primelet: a cabbage grafted onto a cabbage that, very rarely,
-- climbs out of the plot. The player raises it by tending it once a day,
-- carries it in the satchel and sets it down at home. Pure Lua on the
-- splicing state (st.primelets); the game side spawns its look and pays XP.
--
-- Text here is MOD LORE (fan-written, not Jagex canon); see the Dragonwilds
-- docs, LORE_VERIFICATION.md.
local Talk = require("horticulture_primelet_talk")

local Primelet = {}

Primelet.SPECIES = "Primelet"
Primelet.REACH = 260
Primelet.CLOSE = 130

-- need: tended days to reach the stage. The look of each stage (size, face,
-- pot) is in placements\hort_plant_brassica_primelet_*.lua. Saves keep the
-- stage number, so a renamed stage needs no migration.
Primelet.STAGES = {
    { id = "sprout", name = "Primelet Sprout", need = 0 },
    { id = "primelet", name = "Brassica Primelet", need = 2 },
    { id = "primeling", name = "Mini Brassica Prime", need = 5 },
}
Primelet.GROWN_STAGE = 3

Primelet.TEND_LINES = {
    {
        "You water the sprout. It leans towards you, then away, then towards you again, as if checking.",
        "You tell the sprout about your day. It listens with every leaf.",
        "The sprout has edged a little further from the onions.",
    },
    {
        "You water the Primelet. It accepts this as tribute.",
        "You talk to the Primelet about the weather. It disagrees, politely.",
        "The Primelet has folded its outer leaves into something like a crown. You compliment it. It knew.",
    },
    {
        "The Mini Brassica Prime allows itself to be watered.",
        "You ask the Mini Brassica Prime how it is. It rustles in a way that suggests fried, eventually, but not yet.",
        "The Mini Brassica Prime regards your cooking pot for a long moment. You move the pot.",
    },
}

Primelet.TENDED_TODAY = "It has had all the attention it can stand today. Come back after dawn."

Primelet.GROWN = {
    [2] = "Overnight it has grown a second layer of leaves and an air of authority. It has opinions now, and a name to match.",
    [3] = "It is a Mini Brassica Prime now. Small birds land near it, think better of it, and leave. Set it down at home and it will want a pot.",
}

Primelet.REVEAL = {
    kicker = "SOMETHING HAS HAPPENED",
    title = "BRASSICA PRIMELET",
    detail = "Cabbage onto cabbage should have made more cabbage. Instead a small cabbage has climbed out of the plot and is looking at you expectantly.",
    catalogue = "Not one of the flagships. Not, strictly, one of anything.",
    lore = "The Observances say their lord delights in difference. Kalestix never wrote down what happens when a cabbage is introduced to itself. Now you know.",
    howto = "Tend it once a day (E or G beside it). Alt+G picks it up; select it in the satchel and press G to set it down at home.",
}

function Primelet.Stage(p)
    return Primelet.STAGES[p.stage] or Primelet.STAGES[1]
end

-- "Lord Savoy the Pompous" once its personality shows, else the stage name.
function Primelet.Name(p)
    return Talk.FullName(p) or Primelet.Stage(p).name
end

-- Rolls a personality and name for a primelet that has none: at birth, and
-- for primelets from saves made before they had one.
function Primelet.RollTraits(st, p, rng)
    if p.personality and Talk.V.P[p.personality] and p.name then return false end
    local owned, used = {}, {}
    for _, q in ipairs(st.primelets or {}) do
        if q ~= p and q.personality then owned[q.personality] = (owned[q.personality] or 0) + 1 end
        if q ~= p and q.name then used[q.name] = true end
    end
    if not (p.personality and Talk.V.P[p.personality]) then p.personality = Talk.RollPersonality(owned, rng) end
    if not p.name then p.name = Talk.RollName(p.personality, used, rng) end
    p.said = p.said or {}
    return true
end

-- Rolls every primelet missing a personality; returns how many it rolled.
function Primelet.Migrate(st, rng)
    local n = 0
    for _, p in ipairs(st.primelets or {}) do
        if Primelet.RollTraits(st, p, rng) then n = n + 1 end
    end
    return n
end

-- A new primelet beside the plot it came from.
function Primelet.New(st, x, y, z, world, rng)
    st.primelets = st.primelets or {}
    local p = {
        id = "p" .. st.nextId, stage = 1, growth = 0, tended = -1, born = st.dawn,
        world = world or "?", x = x, y = y, z = z, yaw = 0, carried = false, said = {},
    }
    st.nextId = st.nextId + 1
    st.primelets[#st.primelets + 1] = p
    Primelet.RollTraits(st, p, rng or function(n) return math.random(n) end)
    return p
end

function Primelet.Grown(p) return (p.stage or 1) >= Primelet.GROWN_STAGE end

-- Grown Minis this character owns (every world).
function Primelet.GrownCount(st)
    local n = 0
    for _, p in ipairs(st and st.primelets or {}) do if Primelet.Grown(p) then n = n + 1 end end
    return n
end

function Primelet.Find(st, id)
    for _, p in ipairs(st.primelets or {}) do
        if p.id == id then return p end
    end
    return nil
end

-- rng(n) returns 1..n. chance in percent, to a tenth.
function Primelet.Roll(rng, chance)
    return rng(1000) <= math.floor((chance or 0) * 10 + 0.5)
end

-- Once a day. Returns the line to show and whether it counted.
function Primelet.Tend(st, p, rng)
    if p.tended == st.dawn then return Primelet.TENDED_TODAY, false end
    p.tended = st.dawn
    local lines = Primelet.TEND_LINES[p.stage] or Primelet.TEND_LINES[1]
    return lines[rng and rng(#lines) or 1], true
end

-- At dawn (after st.dawn has moved on): a primelet tended the day before
-- grows one day. Returns the primelets that reached a new stage.
function Primelet.Dawn(st)
    local grown = {}
    for _, p in ipairs(st.primelets or {}) do
        if p.tended == st.dawn - 1 then
            p.growth = p.growth + 1
            local nextStage = Primelet.STAGES[p.stage + 1]
            if nextStage and p.growth >= nextStage.need then
                p.stage = p.stage + 1
                grown[#grown + 1] = p
            end
        end
    end
    return grown
end

local function in_world(p, world)
    return p.world == "?" or world == nil or world == "?" or p.world == world
end

-- Primelets set down in this world.
function Primelet.Visible(st, world)
    local out = {}
    for _, p in ipairs(st.primelets or {}) do
        if not p.carried and in_world(p, world) then out[#out + 1] = p end
    end
    return out
end

-- The primelet the player is facing within reach (or standing on), or nil.
-- me: { X, Y }, yaw: facing in degrees.
function Primelet.Near(st, me, yaw, world)
    local fx, fy = math.cos(math.rad(yaw or 0)), math.sin(math.rad(yaw or 0))
    local best, bestD = nil, math.huge
    for _, p in ipairs(Primelet.Visible(st, world)) do
        local dx, dy = (p.x or 0) - me.X, (p.y or 0) - me.Y
        local d = math.sqrt(dx * dx + dy * dy)
        local facing = d < 1 or (dx * fx + dy * fy) / d > 0.4
        if d <= Primelet.CLOSE or (d <= Primelet.REACH and facing) then
            if d < bestD then best, bestD = p, d end
        end
    end
    return best
end

-- Into the satchel, as an entry that never wilts.
function Primelet.PickUp(st, p, satchelSize)
    if #st.cuttings >= satchelSize then
        return nil, string.format("Your satchel is full (%d). Graft a cutting first", satchelSize)
    end
    p.carried = true
    local entry = { species = Primelet.SPECIES, taken = st.dawn, primelet = p.id }
    st.cuttings[#st.cuttings + 1] = entry
    st.selected = #st.cuttings
    return entry
end

-- Out of the satchel at x, y, z facing yaw.
function Primelet.Place(st, entry, x, y, z, yaw, world)
    local p = Primelet.Find(st, entry.primelet)
    for i, c in ipairs(st.cuttings) do
        if c == entry then
            table.remove(st.cuttings, i)
            break
        end
    end
    if st.selected > #st.cuttings then st.selected = math.max(1, #st.cuttings) end
    if not p then return nil, "It is not in your satchel" end
    p.carried, p.x, p.y, p.z, p.yaw, p.world = false, x, y, z, yaw or 0, world or p.world
    -- A grown Mini goes into a pot the first time it is set down.
    local firstPot = Primelet.Grown(p) and not p.potted
    if firstPot then p.potted = true end
    return p, nil, firstPot
end

function Primelet.StatusLine(st, world)
    local parts = {}
    for _, p in ipairs(st and st.primelets or {}) do
        local nextStage = Primelet.STAGES[p.stage + 1]
        local grow = nextStage and string.format("%d/%d days tended", p.growth, nextStage.need) or "fully grown"
        local where = p.carried and "in your satchel" or (in_world(p, world) and "at home" or "in another world")
        local name = Talk.FullName(p)
        local what = name and (name .. ", " .. Primelet.Stage(p).name) or Primelet.Stage(p).name
        parts[#parts + 1] = string.format("%s (%s, %s%s)", what, grow, where,
            p.tended == st.dawn and ", tended today" or "")
    end
    return table.concat(parts, "; ")
end

return Primelet

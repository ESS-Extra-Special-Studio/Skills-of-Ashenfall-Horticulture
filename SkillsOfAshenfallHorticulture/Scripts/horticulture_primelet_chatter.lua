-- The game side of the Primelets' voice: horticulture_splicing reports what
-- happened (talked to, tended, potted, set down, picked up, grown), this
-- picks the line through horticulture_primelet_talk and shows it in a bubble
-- above the Mini, or in the name tag when no bubble can be drawn. It also
-- polls for unprompted lines and checks where the potted Minis stand.
--
-- Cooking is seen as a rise in the player's Cooking XP. Triggers the game
-- cannot report yet are left out: cabbage food in the satchel, rain, low
-- health and death.
local Talk = require("horticulture_primelet_talk")
local Primelet = require("horticulture_primelet")
local Bubble = require("horticulture_bubble")
local Looks = require("horticulture_looks")
local World = require("horticulture_world")

local V = Talk.V
local Chatter = {}

local U, cfg, hooks, eng = nil, nil, nil, nil
local fallback = nil
local later = {}
local seen = {}
local returnedArmed = false
local firstWords = {}
local lastK = 0
local standing = nil

local function now() return os.clock() end
local function rng(n) return math.random(n) end

-- The vanilla Cooking level, read at most every 5 s; nil when unknown.
local cookingCache = { at = -100 }
local function cooking_level()
    if now() - cookingCache.at < 5 then return cookingCache.level end
    local ok, n = pcall(function() return cfg.ESL.GetVanillaLevel and cfg.ESL.GetVanillaLevel("Cooking") end)
    cookingCache = { at = now(), level = ok and type(n) == "number" and n or nil }
    return cookingCache.level
end

function Chatter.Init(util, config, h)
    U, cfg, hooks = util, config, h
    eng = Talk.New({ chattiness = config.primeletChattiness, rng = rng, clock = now })
end

-- A new character or session: who has been seen, and whether it has been
-- long enough since the last session for the returned lines.
function Chatter.Reset(st)
    seen, firstWords, later, lastK, standing, fallback = {}, {}, {}, 0, nil, nil
    returnedArmed = st and st.lastSeen ~= nil and os.time() - st.lastSeen >= V.TIMING.returned_real_days * 86400 or false
    if Bubble then Bubble.HideAll() end
end

local function me() return U.location(U.pawn()) end

local function dist(p, loc)
    if not loc then return math.huge end
    return math.sqrt(((p.x or 0) - loc.X) ^ 2 + ((p.y or 0) - loc.Y) ^ 2)
end

local function catalogue_count()
    local ok, n = pcall(hooks.catalogue)
    return ok and n or 0
end

local function time_of_day()
    local h = World.Hour()
    if not h then return nil end
    if h >= 5 and h < 8 then return "dawn" end
    if h >= 21 or h < 5 then return "night" end
    return nil
end

local function ctx_for(p, extra)
    local st = hooks.state()
    local minis = Primelet.GrownCount(st)
    local last = p.talked or p.tended
    local c = {
        level = hooks.level(), minis = minis, catalogue = catalogue_count(), flagships = hooks.flagships(),
        hintTier = Talk.HintTier(minis), time = time_of_day(), cooking = cooking_level(),
        ignoredDays = last and last >= 0 and (st.dawn - last) or 0,
    }
    if not eng:TopicReady("hint", V.TIMING.hint_gap_s) then c.hintTier = 0 end
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function head(p)
    return function()
        local b = Looks.Built("prime:" .. p.id)
        return { X = p.x or 0, Y = p.y or 0, Z = (p.z or 0) + (b and b.bubbleZ or 60) + 8 }
    end
end

local function show(p, text, line, pool)
    local t = now()
    local secs = eng:Spoke(p, text, line, t)
    if pool == "hint" then eng:TopicUsed("hint", t) end
    local name = Primelet.Name(p)
    if not (cfg.bubbles ~= false and Bubble.Show(name, text, head(p), secs, t)) then
        fallback = { text = name .. ": " .. text, untilT = t + secs }
    end
    U.log(string.format("Primelet %s (%s) says: %s", p.id, name, text))
    hooks.save()
    return text
end

-- A line from a grown Mini for trigger, when it may speak. Returns the text,
-- or nil (nothing to say, too soon, or the player is out of earshot).
function Chatter.Event(p, trigger, extra)
    if not (p and eng and Primelet.Grown(p)) then return nil end
    if trigger ~= "talk" and trigger ~= "tended" and trigger ~= "picked_up" and dist(p, me()) > V.TIMING.hearing_radius_cm then return nil end
    if not eng:CanSpeak(p.id, trigger, now()) then return nil end
    local text, _, pool, line = eng:Line(p, trigger, ctx_for(p, extra))
    if not text then return nil end
    return show(p, text, line, pool)
end

-- Narration for a Sprout or Primelet being tended or talked to, or nil.
function Chatter.Narration(p, trigger)
    if not (p and eng) or Primelet.Grown(p) then return nil end
    local text, _, _, line = eng:Line(p, trigger, ctx_for(p))
    if text then eng:Remember(p, text, line) end
    return text
end

-- The player tended or talked to p: resets its ignored count.
function Chatter.Attended(p)
    local st = hooks.state()
    p.talked, p.ign = st.dawn, nil
end

-- At dawn p reached the last stage. Returns its first words for the card;
-- the Mini says them aloud when the player is next nearby.
function Chatter.FirstWords(p)
    if not eng then return nil end
    local text, _, _, line = eng:Line(p, "first_words", ctx_for(p))
    if not text then return nil end
    eng:Remember(p, text, line)
    firstWords[p.id] = text
    return text
end

local function say_later(delay, p, text)
    later[#later + 1] = { at = now() + delay, p = p, text = text }
end

-- Grown, potted Minis set down in this world.
local function potted_here()
    local out = {}
    for _, p in ipairs(Primelet.Visible(hooks.state(), World.WorldKey())) do
        if Primelet.Grown(p) and p.potted then
            out[#out + 1] = { x = p.x or 0, y = p.y or 0, z = p.z or 0, p = p }
        end
    end
    return out
end

local function nearest(list, loc)
    local best, bestD = nil, math.huge
    for _, m in ipairs(list) do
        local d = dist(m.p or m, loc)
        if d < bestD then best, bestD = m, d end
    end
    return best, bestD
end

local function members_key(set)
    local ids = {}
    for _, m in ipairs(set) do ids[#ids + 1] = m.p.id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- After a Mini is set down, picked up or grows: where the potted Minis
-- stand, and what (if anything) they make of it.
function Chatter.CheckArrangement(reason)
    if not (eng and hooks.state()) then return end
    local all = potted_here()
    local found, nearly = Talk.Arrangement(all)
    local k = found and V.ARRANGE.size or Talk.Progress(all)
    U.log(string.format("Primelet arrangement check (%s): %d potted, %d", reason or "?", #all, k))
    local loc = me()
    if found then
        local key = members_key(found.members)
        local t = now()
        if standing and standing.key == key and t - standing.at < V.TIMING.ring_roast_gap_s then
            lastK = k
            return
        end
        standing = { key = key, at = t, idleAt = t, cx = found.cx, cy = found.cy, r = found.r, members = found.members }
        local byAngle = {}
        for _, m in ipairs(found.members) do
            byAngle[#byAngle + 1] = { m = m, a = math.atan(m.y - found.cy, m.x - found.cx) }
        end
        table.sort(byAngle, function(a, b) return a.a < b.a end)
        for i, e in ipairs(byAngle) do
            later[#later + 1] = { at = t + i * V.ARRANGE.turn_stagger_s, turn = e.m.p,
                yaw = math.deg(math.atan(found.cy - e.m.y, found.cx - e.m.x)) }
        end
        local speaker = nearest(found.members, loc) or found.members[1]
        local others = {}
        for _, m in ipairs(found.members) do if m ~= speaker then others[#others + 1] = m end end
        local other = others[rng(#others)]
        local inMiddle = loc and math.sqrt((loc.X - found.cx) ^ 2 + (loc.Y - found.cy) ^ 2) < V.ARRANGE.player_centre_frac * found.r
        local st = hooks.state()
        local first, second = eng:Completed(speaker.p, other and other.p, ctx_for(speaker.p, { playerInCentre = inMiddle }), st.pmflag1)
        st.pmflag1 = true
        local delay = #byAngle * V.ARRANGE.turn_stagger_s
        if first then later[#later + 1] = { at = t + delay, p = speaker.p, text = first, force = true } end
        if second and other then later[#later + 1] = { at = t + delay + V.TIMING.exchange_pause_s, p = other.p, text = second, force = true } end
        hooks.save()
    else
        standing = nil
        local pool = Talk.ProgressPool(lastK, k, nearly)
        local speaker = pool and nearest(all, loc)
        if speaker then Chatter.Event(speaker.p, pool) end
    end
    lastK = k
end

local function plant_near(p)
    local list = hooks.hybridsNear and hooks.hybridsNear(p, V.NEIGHBOUR_RADIUS_CM) or {}
    if #list == 0 then return nil end
    return list[rng(#list)]
end

-- Every ambient_poll_s: lines nobody asked for.
function Chatter.Poll()
    if not (eng and hooks.state()) then return end
    local st = hooks.state()
    local loc = me()
    if not loc then return end
    local near = {}
    for _, p in ipairs(Primelet.Visible(st, World.WorldKey())) do
        if Primelet.Grown(p) and dist(p, loc) <= V.TIMING.ambient_radius_cm then near[#near + 1] = p end
    end
    for _, p in ipairs(near) do
        if not seen[p.id] then
            seen[p.id] = true
            local away = p.seen and st.dawn - p.seen >= V.TIMING.returned_game_days
            p.seen = st.dawn
            if (returnedArmed or away) and Chatter.Event(p, "returned") then return end
        end
        p.seen = st.dawn
        if firstWords[p.id] then
            local text = firstWords[p.id]
            firstWords[p.id] = nil
            if eng:CanSpeak(p.id, "first_words", now()) then show(p, text) return end
        end
    end
    if #near == 0 then return end
    local t = now()
    if standing and t - standing.idleAt >= V.TIMING.ring_idle_gap_s then
        standing.idleAt = t
        local m = standing.members[rng(#standing.members)]
        local text = m and eng:Idle(m.p, ctx_for(m.p))
        if text and dist(m.p, loc) <= V.TIMING.ambient_radius_cm then show(m.p, text) return end
    end
    for _, p in ipairs(near) do
        local c = ctx_for(p)
        local tier = Talk.IgnoredTier(p, c.ignoredDays)
        if tier and tier > (p.ign or 0) and eng:CanSpeak(p.id, "ignored", t) then
            if Chatter.Event(p, "ignored") then p.ign = tier hooks.save() return end
        end
    end
    local chance = eng:AmbientChance(time_of_day() == "night")
    if chance <= 0 then return end
    if #near >= 2 and eng:TopicReady("bicker", V.TIMING.bicker_gap_s, t) and rng(1000) <= chance * 1000 then
        local a, b = near[rng(#near)], nil
        for _, q in ipairs(near) do
            if q ~= a and math.sqrt((q.x - a.x) ^ 2 + (q.y - a.y) ^ 2) <= V.TIMING.bicker_pair_cm then b = q break end
        end
        if b and eng:CanSpeak(a.id, "bicker", t) then
            local first, second, l1, l2 = eng:Bicker(a, b, ctx_for(a))
            if first then
                eng:TopicUsed("bicker", t)
                show(first, l1)
                say_later(V.TIMING.exchange_pause_s, second, l2)
                return
            end
        end
    end
    for _, p in ipairs(near) do
        if rng(1000) <= chance * 1000 and eng:CanSpeak(p.id, "ambient", t) then
            local plant = plant_near(p)
            if plant and eng:TopicReady("plant:" .. plant, V.TIMING.plant_gap_s, t) and rng(2) == 1 then
                if Chatter.Event(p, "plants", { plant = plant }) then eng:TopicUsed("plant:" .. plant, t) return end
            end
            if Chatter.Event(p, "ambient") then return end
        end
    end
end

-- The player cooked something (Cooking XP rose): the nearest grown Mini
-- within COOKING_RADIUS_CM remarks on it, at most once per cooking_gap_s.
function Chatter.Cooked()
    if not (eng and hooks.state()) then return nil end
    local t = now()
    if not eng:TopicReady("cooking", V.TIMING.cooking_gap_s, t) then return nil end
    local loc = me()
    if not loc then return nil end
    local best, bestD = nil, V.COOKING_RADIUS_CM
    for _, p in ipairs(Primelet.Visible(hooks.state(), World.WorldKey())) do
        local d = dist(p, loc)
        if Primelet.Grown(p) and d <= bestD then best, bestD = p, d end
    end
    local text = best and Chatter.Event(best, "cooking")
    if text then eng:TopicUsed("cooking", t) end
    return text
end

-- Every 100 ms: bubbles follow their Minis; delayed lines and turns.
function Chatter.Tick()
    local t = now()
    if #later > 0 then
        local keep = {}
        for _, e in ipairs(later) do
            if e.at <= t then
                if e.turn then
                    e.turn.yaw = e.yaw
                    if hooks.refresh then hooks.refresh() end
                elseif e.force or eng:CanSpeak(e.p.id, "talk", t) then
                    show(e.p, e.text)
                end
            else
                keep[#keep + 1] = e
            end
        end
        later = keep
    end
    Bubble.Tick(t)
end

-- Whether Tick has anything to do (a bubble up, or a line waiting).
function Chatter.Busy()
    return #later > 0 or Bubble.Active()
end

-- The name tag's text while a line is shown there instead of a bubble.
function Chatter.TagLine()
    if fallback and fallback.untilT > now() then return fallback.text end
    fallback = nil
    return nil
end

function Chatter.PollSeconds() return V.TIMING.ambient_poll_s end
function Chatter.SetChattiness(name) if eng then eng:SetChattiness(name) end end
function Chatter.Engine() return eng end

-- Developer only: the Mini nearest the player says something now, gaps
-- ignored (trigger defaults to "talk").
function Chatter.DevSay(trigger)
    local st = hooks.state()
    if not st then return nil end
    local list = {}
    for _, p in ipairs(Primelet.Visible(st, World.WorldKey())) do list[#list + 1] = p end
    local p = nearest(list, me())
    if not p then U.log("[DEV] No Primelet here") return nil end
    if not Primelet.Grown(p) then
        local text = Chatter.Narration(p, "talk")
        U.log("[DEV] " .. Primelet.Name(p) .. " is not grown: " .. tostring(text))
        return text
    end
    eng.bubbleUntil, eng.lastAny = -math.huge, -math.huge
    eng.lastSpoke[p.id] = nil
    local text, _, pool, line = eng:Line(p, trigger or "talk", ctx_for(p))
    if not text then U.log("[DEV] " .. Primelet.Name(p) .. " has nothing to say for " .. tostring(trigger)) return nil end
    return show(p, text, line, pool)
end

return Chatter

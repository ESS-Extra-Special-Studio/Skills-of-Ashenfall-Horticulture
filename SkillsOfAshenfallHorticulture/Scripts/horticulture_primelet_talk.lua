-- What the Primelets say and when: personality and name rolls, picking a
-- line for a trigger, the cooldowns, and how potted Minis stand relative to
-- each other. Pure Lua on horticulture_primelet_voice.lua; the game side
-- (horticulture_splicing) detects the triggers and shows the bubble.
--
-- A "mini" here is a primelet record from the splicing save: { id, stage,
-- personality, name, potted, said = { [hash] = true }, x, y, z }.
local V = require("horticulture_primelet_voice")

local Talk = {}
Talk.V = V

local STAGE_KEYS = { "sprout", "primelet", "primeling" }

function Talk.StageKey(p) return STAGE_KEYS[p and p.stage or 1] or "sprout" end

-- A short stable key for a line, for the saved "said once" list.
function Talk.Hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- Personality and name ----------------------------------------------------

-- owned: personality -> count already owned. rng(n) returns 1..n.
function Talk.RollPersonality(owned, rng)
    owned = owned or {}
    local total, w = 0, {}
    for _, key in ipairs(V.ORDER) do
        w[key] = V.P[key].weight * (V.ROLL.owned_damping ^ (owned[key] or 0))
        total = total + w[key]
    end
    local r = rng(1000) / 1000 * total
    for _, key in ipairs(V.ORDER) do
        r = r - w[key]
        if r <= 0 then return key end
    end
    return V.ORDER[#V.ORDER]
end

local ORDINALS = { "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth" }

-- A name from the personality's list that this character does not use yet;
-- when all are taken, "<name> the Second", "the Third", ...
function Talk.RollName(key, used, rng)
    used = used or {}
    local names = V.P[key] and V.P[key].names or { "Primelet" }
    local free = {}
    for _, n in ipairs(names) do if not used[n] then free[#free + 1] = n end end
    if #free > 0 then return free[rng(#free)] end
    for _, ord in ipairs(ORDINALS) do
        for _, n in ipairs(names) do
            local candidate = n .. " the " .. ord
            if not used[candidate] then return candidate end
        end
    end
    return names[rng(#names)]
end

function Talk.Label(p)
    local P = p and p.personality and V.P[p.personality]
    return P and P.label or nil
end

-- "Lord Savoy the Pompous" once the personality shows (from the Brassica
-- Primelet stage), else nil.
function Talk.FullName(p)
    local stage = V.STAGES[Talk.StageKey(p)]
    local label = Talk.Label(p)
    if not (stage and stage.shows_personality and label and p.name) then return nil end
    return p.name .. " the " .. label
end

function Talk.Trait(p)
    local stage = V.STAGES[Talk.StageKey(p)]
    if not (stage and stage.shows_personality) then return V.SPROUT_TRAIT end
    local P = p.personality and V.P[p.personality]
    return P and P.trait or V.SPROUT_TRAIT
end

function Talk.Speaks(p)
    local stage = V.STAGES[Talk.StageKey(p)]
    return stage ~= nil and stage.speaks == true
end

-- Hint tier from grown Minis owned (all worlds).
function Talk.HintTier(minis)
    local tier = 0
    for _, h in ipairs(V.HINT_TIERS) do if (minis or 0) >= h.minis then tier = h.tier end end
    return tier
end

-- Lines -------------------------------------------------------------------

local function as_line(line) return type(line) == "table" and line or { line } end

-- ctx: { level, minis, catalogue, flagships, hintTier, ignoredDays, time,
-- playerInCentre, item, plant, other, cooking }. cooking is the vanilla
-- Cooking level, nil when unknown (then no min_cooking/max_cooking line plays).
function Talk.Eligible(t, ctx)
    ctx = ctx or {}
    local level = ctx.level or 1
    if t.min_level and level < t.min_level then return false end
    if t.max_level and level > t.max_level then return false end
    if t.minis and (ctx.minis or 0) < t.minis then return false end
    if t.max_minis and (ctx.minis or 0) > t.max_minis then return false end
    if t.catalogue and (ctx.catalogue or 0) < t.catalogue then return false end
    if t.flagships and (ctx.flagships or 0) < t.flagships then return false end
    if t.hint_tier and (ctx.hintTier or 0) < t.hint_tier then return false end
    if (t.min_cooking or t.max_cooking) and type(ctx.cooking) ~= "number" then return false end
    if t.min_cooking and ctx.cooking < t.min_cooking then return false end
    if t.max_cooking and ctx.cooking > t.max_cooking then return false end
    if t.player_in_centre and not ctx.playerInCentre then return false end
    if type(t.when) == "number" and (ctx.ignoredDays or 0) < t.when then return false end
    if type(t.when) == "string" and ctx.time ~= t.when then return false end
    if t.src == "rs3" and not V.ALLOW_MAINLAND then return false end
    local text = t[1] or ""
    if text:find("{item}", 1, true) and not ctx.item then return false end
    if text:find("{plant}", 1, true) and not ctx.plant then return false end
    if text:find("{other}", 1, true) and not ctx.other then return false end
    return true
end

function Talk.Fill(text, mini, ctx)
    ctx = ctx or {}
    local map = {
        name = mini and mini.name or "", other = ctx.other or "", item = ctx.item or "",
        plant = ctx.plant or "", catalogue = tostring(ctx.catalogue or 0), minis = tostring(ctx.minis or 0),
    }
    return (text:gsub("{(%a+)}", function(k) return map[k] or ("{" .. k .. "}") end))
end

local function weighted(list, rng)
    local total = 0
    for _, t in ipairs(list) do total = total + (t.w or 1) end
    if total <= 0 then return nil end
    local r = rng(1000) / 1000 * total
    for _, t in ipairs(list) do
        r = r - (t.w or 1)
        if r <= 0 then return t end
    end
    return list[#list]
end

-- The engine: remembers recent lines and when each Mini last spoke.
-- opts: { chattiness = "normal", rng = function(n) 1..n end, clock = os.clock }
function Talk.New(opts)
    opts = opts or {}
    local e = {
        rng = opts.rng or function(n) return math.random(n) end,
        clock = opts.clock or os.clock,
        recentMini = {}, recentGlobal = {}, lastSpoke = {}, lastAny = -math.huge, bubbleUntil = -math.huge,
        topicAt = {},
    }
    e.chat = V.CHATTINESS[opts.chattiness or V.CHATTINESS_DEFAULT] or V.CHATTINESS.normal
    return setmetatable(e, { __index = Talk })
end

function Talk:SetChattiness(name)
    self.chat = V.CHATTINESS[name] or V.CHATTINESS.normal
end

local function recent_has(list, text)
    for _, s in ipairs(list or {}) do if s == text then return true end end
    return false
end

-- A line from pool for mini, or nil. Recent lines are avoided; with nothing
-- else left the global, then the per-Mini, no-repeat rule is relaxed. Once
-- lines already said are never repeated.
function Talk:Pick(mini, pool, ctx)
    local mine = self.recentMini[mini.id] or {}
    for pass = 1, 3 do
        local ok = {}
        for _, line in ipairs(pool or {}) do
            local t = as_line(line)
            if t[1] and Talk.Eligible(t, ctx)
                and not (t.once and mini.said and mini.said[Talk.Hash(t[1])])
                and (pass >= 3 or not recent_has(mine, t[1]))
                and (pass >= 2 or not recent_has(self.recentGlobal, t[1])) then
                ok[#ok + 1] = t
            end
        end
        if #ok > 0 then
            local t = weighted(ok, self.rng)
            return Talk.Fill(t[1], mini, ctx), t
        end
    end
    return nil
end

-- Pools for a speaking Mini (personality pool, or a shared one by name).
function Talk.Pool(mini, name)
    local P = mini.personality and V.P[mini.personality]
    if name == "sprout" then return V.SHARED.sprout end
    return P and P[name] or nil
end

local function pool_has_line(self, mini, pool, ctx)
    for _, line in ipairs(pool or {}) do
        local t = as_line(line)
        if t[1] and Talk.Eligible(t, ctx) and not (t.once and mini.said and mini.said[Talk.Hash(t[1])]) then return true end
    end
    return false
end

-- Picks a pool from a mix (name -> weight), skipping pools with nothing
-- eligible.
function Talk:Mix(mini, mix, ctx)
    local cands, total = {}, 0
    for _, name in ipairs({ "talk", "level", "accomplishment", "gods", "hint", "time", "cooking_level" }) do
        local w = mix[name]
        if w and w > 0 and pool_has_line(self, mini, Talk.Pool(mini, name), ctx) then
            cands[#cands + 1] = { name = name, w = w }
            total = total + w
        end
    end
    if total == 0 then return nil end
    local r = self.rng(1000) / 1000 * total
    for _, c in ipairs(cands) do
        r = r - c.w
        if r <= 0 then return c.name end
    end
    return cands[#cands].name
end

-- The line for a trigger, or nil. Sprouts and Primelets do not speak: the
-- Sprout's tend and talk lines are the shared narration, a Primelet's its
-- personality's narration. Returns text, whether it is narrated, the pool
-- name and the line (for Spoke / Remember).
function Talk:Line(mini, trigger, ctx)
    ctx = ctx or {}
    local key = Talk.StageKey(mini)
    if key ~= "primeling" then
        if trigger ~= "tended" and trigger ~= "talk" then return nil end
        local pool = key == "sprout" and V.SHARED.sprout or (Talk.Pool(mini, "primelet") or V.SHARED.sprout)
        local text, line = self:Pick(mini, pool, ctx)
        return text, true, key, line
    end
    local poolName = trigger
    if trigger == "talk" then poolName = self:Mix(mini, V.TALK_MIX, ctx) or "talk"
    elseif trigger == "ambient" then poolName = self:Mix(mini, V.AMBIENT_MIX, ctx)
        if not poolName then return nil end
    end
    if trigger == "ignored" then
        local best = nil
        for _, line in ipairs(Talk.Pool(mini, "ignored") or {}) do
            local t = as_line(line)
            if type(t.when) == "number" and t.when <= (ctx.ignoredDays or 0) and (not best or t.when > best.when) then best = t end
        end
        if not best then return nil end
        return Talk.Fill(best[1], mini, ctx), false, "ignored", best
    end
    if trigger == "cabbage_food" and ctx.item and V.SHARED.items[ctx.item] and self.rng(100) <= V.SHARED.item_specific_chance * 100 then
        local text, line = self:Pick(mini, V.SHARED.items[ctx.item], ctx)
        if text then return text, false, "items", line end
    end
    if trigger == "plants" and ctx.plant and V.SHARED.plants[ctx.plant] and self.rng(100) <= V.SHARED.plant_specific_chance * 100 then
        local text, line = self:Pick(mini, V.SHARED.plants[ctx.plant], ctx)
        if text then return text, false, "plants", line end
    end
    local text, line = self:Pick(mini, Talk.Pool(mini, poolName), ctx)
    return text, false, poolName, line
end

-- The highest ignored tier (days) this Mini has a line for, up to days.
function Talk.IgnoredTier(mini, days)
    local best = nil
    for _, line in ipairs(Talk.Pool(mini, "ignored") or {}) do
        local t = as_line(line)
        if type(t.when) == "number" and t.when <= (days or 0) and (not best or t.when > best) then best = t.when end
    end
    return best
end

-- Cooldowns ---------------------------------------------------------------

function Talk:IsEvent(trigger) return V.EVENT_TRIGGERS[trigger] == true end

-- Whether mini may speak now for trigger. Events (talk, tend, set down...)
-- ignore the gaps but let a bubble on screen stay up event_overlap_s first;
-- anything else waits for the bubble to go and for the global and per-Mini
-- gaps, scaled by chattiness ("off": never).
function Talk:CanSpeak(miniId, trigger, t)
    t = t or self.clock()
    local mult = self.chat.gap_mult
    if mult == math.huge and trigger ~= "talk" and trigger ~= "tended" then return false end
    if self:IsEvent(trigger) then
        return t >= self.bubbleUntil or t - self.lastAny >= V.TIMING.event_overlap_s
    end
    if mult == math.huge then return false end
    if t < self.bubbleUntil then return false end
    if t - self.lastAny < V.TIMING.global_gap_s * mult then return false end
    if t - (self.lastSpoke[miniId] or -math.huge) < V.TIMING.per_mini_gap_s * mult then return false end
    return true
end

-- Per-topic gap (cooking, a food, a plant, bickering, hints).
function Talk:TopicReady(topic, gap, t)
    t = t or self.clock()
    local mult = self.chat.gap_mult
    if mult == math.huge then return false end
    return t - (self.topicAt[topic] or -math.huge) >= gap * mult
end

function Talk:TopicUsed(topic, t) self.topicAt[topic] = t or self.clock() end

-- Chance an eligible Mini speaks unprompted in one poll.
function Talk:AmbientChance(night)
    local c = V.TIMING.ambient_chance * self.chat.ambient_mult
    if night and V.TIMING.quiet_at_night then c = c * V.TIMING.night_ambient_mult end
    return c
end

function Talk.BubbleSeconds(text)
    local b = V.BUBBLE
    local s = b.base_s + b.per_char_s * #(text or "")
    if s < b.min_s then s = b.min_s end
    if s > b.max_s then s = b.max_s end
    return s
end

-- Records a spoken line; returns how long to show it.
function Talk:Spoke(mini, text, line, t)
    t = t or self.clock()
    local secs = Talk.BubbleSeconds(text)
    self.lastSpoke[mini.id] = t
    self.lastAny = t
    self.bubbleUntil = math.max(self.bubbleUntil, t + secs)
    self:Remember(mini, text, line)
    return secs
end

-- Records a line as used (no repeats, once lines) without the cooldowns:
-- narration, and lines kept to say later.
function Talk:Remember(mini, text, line)
    local mine = self.recentMini[mini.id] or {}
    table.insert(mine, 1, line and line[1] or text)
    while #mine > V.TIMING.no_repeat_mini do table.remove(mine) end
    self.recentMini[mini.id] = mine
    table.insert(self.recentGlobal, 1, line and line[1] or text)
    while #self.recentGlobal > V.TIMING.no_repeat_global do table.remove(self.recentGlobal) end
    if line and line.once then
        mini.said = mini.said or {}
        mini.said[Talk.Hash(line[1])] = true
    end
end

-- Two Minis bickering: the pair entry for their personalities (either way
-- round; "any" matches anyone). Returns first, second, line1, line2.
function Talk:Bicker(a, b, ctx)
    local fits = {}
    for _, e in ipairs(V.BICKER) do
        if not e.hint_tier or (ctx and ctx.hintTier or 0) >= e.hint_tier then
            local function m(want, p) return want == "any" or want == p.personality end
            if m(e.a, a) and m(e.b, b) then fits[#fits + 1] = { a, b, e[1], e[2] }
            elseif m(e.a, b) and m(e.b, a) then fits[#fits + 1] = { b, a, e[1], e[2] } end
        end
    end
    if #fits == 0 then return nil end
    local f = fits[self.rng(#fits)]
    return f[1], f[2], f[3], f[4]
end

-- Arrangement -------------------------------------------------------------
-- pts: { {x, y, z, id}, ... } of grown, potted Minis set down in one world.

local function fit(pts, angTol, radTol)
    local R = V.ARRANGE
    local n = #pts
    local zmin, zmax, cx, cy = math.huge, -math.huge, 0, 0
    for _, p in ipairs(pts) do
        zmin, zmax = math.min(zmin, p.z or 0), math.max(zmax, p.z or 0)
        cx, cy = cx + p.x / n, cy + p.y / n
    end
    if zmax - zmin > R.floor_z_spread_cm then return false end
    local rs, angs, mean = {}, {}, 0
    for i, p in ipairs(pts) do
        rs[i] = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
        angs[i] = math.deg(math.atan(p.y - cy, p.x - cx)) % 360
        mean = mean + rs[i] / n
    end
    if mean < R.radius_min_cm or mean > R.radius_max_cm then return false end
    local tol = math.max(mean * radTol, R.radius_floor_cm)
    for _, r in ipairs(rs) do if math.abs(r - mean) > tol then return false end end
    table.sort(angs)
    for i = 1, #angs do
        local gap = (angs[i % #angs + 1] - angs[i]) % 360
        if math.abs(gap - R.angle_step_deg) > angTol then return false end
    end
    for i = 1, n do
        for j = i + 1, n do
            local d = math.sqrt((pts[i].x - pts[j].x) ^ 2 + (pts[i].y - pts[j].y) ^ 2)
            if d > R.max_pair_distance_cm then return false end
        end
    end
    return true, cx, cy, mean
end

function Talk.Fit(pts) return fit(pts, V.ARRANGE.angle_tolerance_deg, V.ARRANGE.radius_tolerance) end
function Talk.Nearly(pts) return fit(pts, V.ARRANGE.near_angle_deg, V.ARRANGE.near_radius_tol) end

local function combos(list, k, start, acc, out)
    if #acc == k then
        local c = {}
        for i, v in ipairs(acc) do c[i] = v end
        out[#out + 1] = c
        return
    end
    for i = start, #list do
        acc[#acc + 1] = list[i]
        combos(list, k, i + 1, acc, out)
        acc[#acc] = nil
    end
end

-- The best five: a full fit with a clear middle, else nil and whether some
-- five nearly fit. all: every eligible Mini (the middle must be clear of the
-- others too).
function Talk.Arrangement(all)
    local R = V.ARRANGE
    if #all < R.size then return nil, false end
    local sets = {}
    combos(all, R.size, 1, {}, sets)
    local nearly = false
    for _, set in ipairs(sets) do
        local ok, cx, cy, mean = Talk.Fit(set)
        if ok then
            local clear = true
            for _, p in ipairs(all) do
                local member = false
                for _, m in ipairs(set) do if m == p then member = true end end
                if not member and math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2) < R.centre_clear_frac * mean then clear = false end
            end
            if clear then return { members = set, cx = cx, cy = cy, r = mean } end
        elseif Talk.Nearly(set) then
            nearly = true
        end
    end
    return nil, nearly
end

-- Progress k: 0, or 3 to 5. The most Minis that sit round one centre, through
-- three of them, within the radius tolerance, with gaps that are whole
-- steps of the angle within its tolerance.
function Talk.Progress(all)
    local R = V.ARRANGE
    if #all < R.progress_min_members then return 0 end
    if Talk.Arrangement(all) then return R.size end
    local best = 0
    local triples = {}
    combos(all, 3, 1, {}, triples)
    for _, t in ipairs(triples) do
        local a, b, c = t[1], t[2], t[3]
        local d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        if math.abs(d) > 1e-6 then
            local a2, b2, c2 = a.x ^ 2 + a.y ^ 2, b.x ^ 2 + b.y ^ 2, c.x ^ 2 + c.y ^ 2
            local ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
            local uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
            local r = math.sqrt((a.x - ux) ^ 2 + (a.y - uy) ^ 2)
            if r >= R.radius_min_cm and r <= R.radius_max_cm then
                local tol = math.max(r * R.radius_tolerance, R.radius_floor_cm)
                local on = {}
                for _, p in ipairs(all) do
                    local pr = math.sqrt((p.x - ux) ^ 2 + (p.y - uy) ^ 2)
                    if math.abs(pr - r) <= tol and math.abs((p.z or 0) - (a.z or 0)) <= R.floor_z_spread_cm then
                        on[#on + 1] = math.deg(math.atan(p.y - uy, p.x - ux)) % 360
                    end
                end
                table.sort(on)
                local okSteps = #on >= 3
                for i = 1, #on - 1 do
                    local gap = on[i + 1] - on[i]
                    local steps = math.floor(gap / R.angle_step_deg + 0.5)
                    if steps < 1 or math.abs(gap - steps * R.angle_step_deg) > R.angle_tolerance_deg then okSteps = false end
                end
                if okSteps then best = math.max(best, math.min(#on, R.size - 1)) end
            end
        end
    end
    return best >= R.progress_min_members and best or 0
end

-- The line for a change in progress (old k -> new k), or nil.
function Talk.ProgressPool(oldK, newK, nearly)
    if newK > oldK and newK >= 3 and newK < V.ARRANGE.size then return "closer" end
    if newK < oldK then return "colder" end
    if nearly and newK < V.ARRANGE.size then return "nearly" end
    return nil
end

-- The lines when five stand together (v1 always takes this branch):
-- first, the speaker's line; then optionally a second member's follow-up.
-- heardFirst: the character has heard the first line before.
function Talk:Completed(speaker, other, ctx, heardFirst)
    local first
    if not heardFirst then
        first = V.SHARED.ring_first
    elseif self.rng(100) <= 60 then
        first = self:Pick(speaker, Talk.Pool(speaker, "complete"), ctx)
    end
    first = first or self:Pick(speaker, V.SHARED.ring_complete, ctx)
    local second = nil
    if other and self.rng(100) <= V.SHARED.ring_pile_on_chance * 100 then
        second = self:Pick(other, V.SHARED.ring_pile_on, ctx)
    end
    return first, second
end

function Talk:Idle(mini, ctx) return self:Pick(mini, V.SHARED.ring_idle, ctx) end

return Talk

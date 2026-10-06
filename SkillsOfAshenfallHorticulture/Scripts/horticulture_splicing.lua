-- Splicing in the world: the action keys, the cards, dawn, hybrid looks,
-- picking and the Discovery Catalogue.
--
-- G (action_key): pick from a hybrid if it is ready, else graft the
-- selected cutting onto the plant you aim at if it can take it, else take a
-- cutting from it. Alt+G always takes a cutting (Ctrl is the game's Evade).
-- Shift+G picks the next cutting in the satchel.
--
-- Brassica Primelet: E or G beside it tends it, Alt+G picks it up into the
-- satchel, and G with it selected sets it down in front of the player.
--
-- v1 runs in single player and for the host of a co-op world; the looks are
-- local to the host's screen.
local U = require("horticulture_util")
local Rules = require("horticulture_splice_rules")
local Store = require("horticulture_splice_store")
local Core = require("horticulture_splice_core")
local World = require("horticulture_world")
local Looks = require("horticulture_looks")
local Primelet = require("horticulture_primelet")

local Splicing = {}

local LOOK_RANGE = 6000
local CARD_GAP = 4.5
local FALLBACK_DAY_SECONDS = 20 * 60
local HEAL_VFX = "/Game/Art/VFX/Library/Env/Farming/NS_Farm_Plant_Healed.NS_Farm_Plant_Healed"

local cfg = nil
local st = nil
local stFor = nil
local path = nil
local lastHour = nil
local noClockSince = nil
local cards = {}
local nextCardAt = 0
local plotStage = {}
local hostsCache = { at = -100, list = {} }
local forcePrimelet = false
local shownPrimelets = {}

local function now() return os.clock() end

-- State -------------------------------------------------------------------

local function file_for(charKey)
    local ESL = cfg.ESL
    local base = nil
    if ESL.Store and ESL.Store.ProgressFile then
        pcall(function() base = ESL.Store.ProgressFile(charKey, cfg.SKILL) end)
    end
    if base then return (base:gsub("%.txt$", "") .. ".splicing.txt") end
    return cfg.dir .. "\\..\\splicing-" .. tostring(charKey):gsub("[^%w_%-]", "_") .. ".txt"
end

local function save()
    if st and path and not Store.Save(path, st) then
        U.log_once("savefail" .. path, "Could not write " .. path)
    end
end

local function ensure_state()
    local charKey = cfg.ESL.Character()
    if not charKey then
        if st then Looks.ClearAll() end
        st, stFor, path, lastHour = nil, nil, nil, nil
        shownPrimelets = {}
        World.ResetWorldKey()
        return nil
    end
    if st and stFor == charKey then return st end
    Looks.ClearAll()
    shownPrimelets = {}
    path = file_for(charKey)
    st = Store.Load(path)
    stFor = charKey
    lastHour = nil
    plotStage = {}
    U.log(string.format("Splicing for %s: %d cutting(s), %d graft(s), dawn %d (%s)",
        tostring(charKey), #st.cuttings, #st.grafts, st.dawn, path))
    return st
end

local function level()
    return cfg.ESL.GetLevel(cfg.SKILL) or 1
end

-- Cards -------------------------------------------------------------------

local function card(kicker, title, detail, seconds)
    if cfg.quiet then return end
    cards[#cards + 1] = { kicker, title, detail or "", seconds or 4 }
end

local function pump_cards()
    if #cards == 0 or now() < nextCardAt then return end
    local c = table.remove(cards, 1)
    cfg.ESL.ShowCard(cfg.SKILL, c[1], c[2], c[3], c[4])
    nextCardAt = now() + math.max(CARD_GAP, c[4] + 0.5)
end

-- Says why something could not be done. Not queued: it answers a key press.
local function refuse(kicker, why)
    U.log(kicker .. ": " .. tostring(why))
    if not cfg.quiet then cfg.ESL.ShowCard(cfg.SKILL, kicker, why, "", 3.5) end
end

local function xp(amount, label)
    local ESL = cfg.ESL
    local gain = ESL.AddXp and ESL.AddXp(cfg.SKILL, amount, label) or ESL.Award(cfg.SKILL, "splice:" .. label .. ":" .. os.time() .. ":" .. math.random(1e6), amount, label)
    if cfg.dev or cfg.debug then U.log("XP " .. label .. " +" .. tostring(gain)) end
    return gain
end

-- Catalogue ---------------------------------------------------------------

function Splicing.Discovered()
    local out = {}
    for _, id in ipairs(cfg.ESL.Paid(cfg.SKILL) or {}) do
        local h = tostring(id):match("^hybrid:(.+)$")
        if h then out[#out + 1] = h end
    end
    return out
end

local function flagship_count()
    local n, req = 0, 0
    for _, id in ipairs(Splicing.Discovered()) do
        local f = Rules.FlagshipById(id)
        if f then
            n = n + 1
            if f.required then req = req + 1 end
        end
    end
    return n, req
end

local function hybrid_label(id)
    if id == Rules.PRIMELET.id then return Rules.PRIMELET.name .. " (secret)" end
    local f = Rules.FlagshipById(id)
    if f then return f.name end
    local scion, host = id:match("^(.-)>(.+)$")
    if scion then return Rules.HybridName(scion, host) end
    return id
end

local function vfx_at(loc)
    local sys = StaticFindObject(HEAL_VFX)
    if not U.valid(sys) and LoadAsset then pcall(function() sys = LoadAsset(HEAL_VFX) end) end
    local lib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    if not (U.valid(sys) and U.valid(lib) and loc) then return end
    pcall(function()
        lib:SpawnSystemAtLocation(require("UEHelpers").GetWorld(), sys, loc, { Pitch = 0, Yaw = 0, Roll = 0 },
            { X = 2, Y = 2, Z = 2 }, true, true, 0, true)
    end)
end

local function discover(g)
    local id = Rules.HybridId(g.scion, g.host)
    local f = Rules.Flagship(g.scion, g.host)
    local name = Rules.HybridName(g.scion, g.host)
    local amount = f and Rules.XP.flagship or Rules.XP.discovery
    local gain = cfg.ESL.Award(cfg.SKILL, "hybrid:" .. id, amount, name .. " discovered")
    if not gain then return false end
    if f then
        local n = flagship_count()
        card("DISCOVERY CATALOGUE", string.upper(name) .. " DISCOVERED",
            string.format("%s %d of %d flagship hybrids.", f.detail, n, Rules.FLAGSHIP_TOTAL), 7)
        card(name, f.lore, "From the Discovery Catalogue (End).", 6)
    else
        card("HYBRID RECORDED", name,
            string.format("%s onto %s. Gives %s.", Rules.Name(g.scion), Rules.Name(g.host):lower(), Rules.Name(g.scion):lower()), 5)
    end
    U.log("Discovered " .. name .. " (+" .. tostring(gain) .. " XP)")
    return true
end

-- Hosts in the world ------------------------------------------------------

local function nearby_hosts(me)
    if now() - hostsCache.at < 4 and U.dist(hostsCache.me, me) < 1500 then return hostsCache.list end
    hostsCache = { at = now(), me = me, list = World.Nearby(me, LOOK_RANGE) }
    return hostsCache.list
end

local function as_point(c)
    return { kind = c.kind == "stump" and "tree" or c.kind, key = c.key, x = c.loc.X, y = c.loc.Y }
end

-- The live host of a graft among the candidates, or nil.
local function host_of(g, list)
    for _, c in ipairs(list) do
        if g.kind == "plot" and c.kind == "plot" then
            if (g.key and c.key == g.key) or (not g.key and Core.GraftOn({ grafts = { g } }, as_point(c))) then return c end
        elseif g.kind ~= "plot" and c.kind ~= "plot" and c.kind ~= "wild" then
            if Core.GraftOn({ grafts = { g } }, as_point(c)) then return c end
        end
    end
    return nil
end

local function look_host(c)
    if c.kind == "plot" then
        local loc = c.loc
        local plantLoc = nil
        if c.plant then
            pcall(function()
                local l = c.plant:K2_GetComponentLocation()
                plantLoc = { X = l.X, Y = l.Y, Z = l.Z }
            end)
        end
        return { actor = c.actor or c.obj, kind = "plot", loc = plantLoc or loc, comps = c.plant and { c.plant } or {},
            size = { height = 45, radius = 45 } }
    end
    return { actor = c.actor, kind = c.kind, loc = c.loc }
end

local function give_products(list)
    local parts = {}
    for _, p in ipairs(list) do
        if World.Give(p.item, p.count) then parts[#parts + 1] = p.count .. " " .. p.name:lower() end
    end
    return parts
end

local function end_graft(g, reason)
    Core.Remove(st, g)
    Looks.Clear(g.id)
    plotStage[g.id] = nil
    save()
    U.log("Graft " .. g.id .. " ended: " .. reason)
end

-- Crop grafts follow their plot: harvest ends a hybrid with a bonus, a
-- plot that empties or dies ends a pending graft.
local function watch_plot(g, c)
    local was = plotStage[g.id]
    plotStage[g.id] = c.stage
    if was == nil or was == c.stage then
        if c.species and c.species ~= g.host and c.stage ~= 0 then end_graft(g, "plot replanted") end
        return
    end
    if was == 2 and (c.stage == 0 or c.stage == 3 or c.stage == 1) then
        if g.state == "hybrid" then
            local products = Core.Harvested(st, g)
            Looks.Clear(g.id)
            plotStage[g.id] = nil
            save()
            local parts = give_products(products)
            xp(Rules.XP.pick, "Hybrid harvested")
            card("HYBRID HARVEST", Rules.HybridName(g.scion, g.host),
                #parts > 0 and ("The graft gave " .. table.concat(parts, ", ") .. " as well.") or "The graft gave nothing extra this time.")
        else
            end_graft(g, "harvested before dawn")
            card("GRAFT LOST", Rules.Name(g.scion) .. " onto " .. Rules.Name(g.host):lower(), "The crop was harvested before the graft could take.")
        end
    elseif c.stage == 5 or c.stage == 0 then
        end_graft(g, "plot " .. (c.stage == 5 and "died" or "emptied"))
    end
end

local function refresh_looks()
    if not ensure_state() or #st.grafts == 0 then return end
    local me = U.location(U.pawn())
    if not me then return end
    local list = nearby_hosts(me)
    for i = #st.grafts, 1, -1 do
        local g = st.grafts[i]
        local far = U.dist2d({ X = g.x or 0, Y = g.y or 0 }, me) > LOOK_RANGE
        local c = (not far) and host_of(g, list) or nil
        if not c then
            Looks.Clear(g.id)
        elseif c.kind == "stump" then
            local products = g.state == "hybrid" and Rules.Products(g.scion, g.host) or {}
            end_graft(g, "felled")
            if #products > 0 then
                local parts = give_products(products)
                card("FELLED", Rules.HybridName(g.scion, g.host),
                    #parts > 0 and ("It gave " .. table.concat(parts, ", ") .. " as it fell.") or "")
            end
        else
            if g.kind == "plot" then watch_plot(g, c) end
            if Core.GraftOn(st, as_point(c)) == g then
                local id = Rules.HybridId(g.scion, g.host)
                local placed = Looks.Apply(g, look_host(c), g.state == "hybrid" and "hybrid" or "pending", id)
                U.log_once("look" .. g.id .. g.state, string.format("%s look on %s: %d piece(s)",
                    g.state == "hybrid" and Rules.HybridName(g.scion, g.host) or "Pending graft", U.fname(c.actor or c.obj), placed))
            end
        end
    end
end

-- Primelets set down in this world are drawn when near; carried ones and
-- those in other worlds are not.
local function refresh_primelets()
    if not ensure_state() then return end
    local me = U.location(U.pawn())
    local want = {}
    if me and st.primelets and #st.primelets > 0 then
        for _, p in ipairs(Primelet.Visible(st, World.WorldKey())) do
            if U.dist2d({ X = p.x or 0, Y = p.y or 0 }, me) <= LOOK_RANGE then
                local id = "prime:" .. p.id
                want[id] = true
                local n = Looks.ApplyPrimelet(id, { X = p.x, Y = p.y, Z = p.z }, p.yaw, Primelet.Stage(p).scale)
                U.log_once("look" .. id .. p.stage, string.format("%s %s at %.0f, %.0f: %d piece(s)", Primelet.Name(p), p.id, p.x, p.y, n))
            end
        end
    end
    for id in pairs(shownPrimelets) do
        if not want[id] then Looks.Clear(id) end
    end
    shownPrimelets = want
end

-- Dawn --------------------------------------------------------------------

local function alive_check(g)
    local me = U.location(U.pawn())
    if not me then return nil end
    if U.dist2d({ X = g.x or 0, Y = g.y or 0 }, me) > LOOK_RANGE then return nil end
    local c = host_of(g, World.Nearby(me, LOOK_RANGE))
    if not c then return nil end
    if c.kind == "stump" then return false end
    if g.kind == "plot" and (c.stage == 0 or c.stage == 5 or (c.species and c.species ~= g.host)) then return false end
    return true
end

local function primelet_born(o)
    local g, p = o.graft, o.primelet
    forcePrimelet = false
    Looks.Clear(g.id)
    xp(Rules.XP.takes, "Graft took")
    local R = Primelet.REVEAL
    local howto = R.howto:gsub("%f[%w]G%f[%W]", cfg.actionKey)
    card(R.kicker, R.title, R.detail, 9)
    local gain = cfg.ESL.Award(cfg.SKILL, "hybrid:" .. Rules.PRIMELET.id, Rules.XP.primelet, Rules.PRIMELET.name .. " discovered")
    if gain then
        card("DISCOVERY CATALOGUE", "SECRET ENTRY: " .. string.upper(Rules.PRIMELET.name), R.catalogue, 7)
        card(Rules.PRIMELET.name, R.lore, howto, 10)
    else
        card(Rules.PRIMELET.name, "Another one. The cabbages are, it seems, talking.", howto, 8)
    end
    vfx_at({ X = p.x, Y = p.y, Z = (p.z or 0) + 40 })
    U.log(string.format("Brassica Primelet %s from graft %s at %.0f, %.0f (world %s)", p.id, g.id, p.x, p.y, tostring(p.world)))
end

function Splicing.Dawn(reason)
    if not ensure_state() then return end
    local outcomes, wilted, grown = Core.Dawn(st, level(), function(n) return math.random(n) end, alive_check,
        { primeletChance = cfg.primeletChance, forcePrimelet = forcePrimelet })
    save()
    U.log(string.format("Dawn %d (%s): %d graft(s) resolved, %d cutting(s) wilted", st.dawn, reason or "clock", #outcomes, #wilted))
    for _, p in ipairs(grown or {}) do
        xp(Rules.XP.primeletStage, "Primelet grew")
        card("THE PRIMELET HAS GROWN", Primelet.Name(p), Primelet.GROWN[p.stage] or "", 6)
    end
    for _, o in ipairs(outcomes) do
        local g = o.graft
        local pair = Rules.Name(g.scion) .. " onto " .. Rules.Name(g.host):lower()
        if o.result == "primelet" then
            primelet_born(o)
        elseif o.result == "takes" then
            xp(Rules.XP.takes, "Graft took")
            Looks.Clear(g.id)
            card("GRAFT TOOK", pair, "It has become a " .. Rules.HybridName(g.scion, g.host) .. ".")
            discover(g)
            vfx_at({ X = g.x, Y = g.y, Z = (g.z or 0) + 50 })
        elseif o.result == "rejected" then
            xp(Rules.XP.rejected, "Graft rejected")
            Looks.Clear(g.id)
            card("GRAFT REJECTED", pair, string.format("The %s would not have it (%d%% chance). Try again with a fresh cutting.", Rules.Name(g.host):lower(), o.chance or 0))
        else
            Looks.Clear(g.id)
            card("GRAFT LOST", pair, "The host was gone by dawn.")
        end
    end
    if #wilted > 0 then
        local names = {}
        for _, c in ipairs(wilted) do names[#names + 1] = Rules.Name(c.species) end
        card("CUTTINGS WILTED", table.concat(names, ", "), "Cuttings keep for two dawns. Graft them sooner.")
    end
    hostsCache.at = -100
end

local function watch_clock()
    if not ensure_state() then return end
    local h = World.Hour()
    if not h then
        noClockSince = noClockSince or now()
        U.log_once("noclock", "In-game clock not readable; a graft resolves every " .. FALLBACK_DAY_SECONDS // 60 .. " minutes of play instead")
        if now() - noClockSince >= FALLBACK_DAY_SECONDS then
            noClockSince = now()
            Splicing.Dawn("timer")
        end
        return
    end
    noClockSince = nil
    if lastHour and World.PassedDawn(lastHour, h) then Splicing.Dawn(string.format("clock %.2f -> %.2f", lastHour, h)) end
    lastHour = h
end

-- Keys --------------------------------------------------------------------

local function ready()
    if not (U.pc() and cfg.ESL.Character()) then return false end
    if not cfg.ESL.IsUnlocked(cfg.SKILL) then
        cfg.ESL.Gate(cfg.SKILL, { notify = true, title = "Horticulture", skill = cfg.SKILL })
        return false
    end
    if not World.IsServer() then
        refuse("SPLICING", "Splicing works in single player or as the host in this version")
        return false
    end
    return ensure_state() ~= nil
end

local function source_of(c)
    local crop = c.kind == "plot" or c.kind == "wild"
    local src = { species = c.species, kind = crop and "crop" or "tree", level = level(), alive = c.alive }
    if c.kind == "plot" then
        src.key = c.key
    elseif c.kind == "wild" then
        src.key = string.format("wild:%s@%d,%d", tostring(c.species), math.floor(c.loc.X / 300), math.floor(c.loc.Y / 300))
    else
        src.key = string.format("%s@%.0f,%.0f", tostring(c.species), c.loc.X, c.loc.Y)
        if Rules.IsTree(c.species) then src.axePower = World.HeldAxe() end
    end
    return src
end

local function host_from(c)
    local tier = c.tier
    return {
        species = c.species, kind = c.kind, key = c.kind == "plot" and c.key or nil, planted = c.planted,
        stage = c.stage, tier = tier, x = c.loc.X, y = c.loc.Y, z = c.loc.Z, world = World.WorldKey(),
    }
end

local function take_cutting(c)
    if not c or c.kind == "stump" then
        refuse("NO CUTTING", "Aim at a crop, sapling or tree within reach")
        return
    end
    local cut, why = Core.TakeCutting(st, source_of(c))
    if not cut then refuse("NO CUTTING", why) return end
    save()
    xp(Rules.XP.cutting, "Cutting taken")
    card("CUTTING TAKEN", Rules.Name(cut.species),
        string.format("Satchel %d/%d. Graft it within %d dawns.", #st.cuttings, Rules.SATCHEL_SIZE, Rules.WILT_DAWNS))
    U.log("Cutting taken: " .. cut.species)
end

local function graft(c)
    local g, why = Core.Graft(st, host_from(c), level())
    if not g then return false, why end
    save()
    xp(Rules.XP.graft, "Graft made")
    local chance = Core.ChanceFor(st, g, level())
    local pair = Rules.Name(g.scion) .. " onto " .. Rules.Name(g.host):lower()
    local f = Rules.Flagship(g.scion, g.host)
    local hint = chance >= 100 and "Your first graft. It will take at dawn." or string.format("Check it after dawn. About %d%% it takes.", chance)
    if f and not cfg.ESL.HasPaid(cfg.SKILL, "hybrid:" .. f.id) then hint = hint .. " Something new may grow." end
    card("GRAFT MADE", pair, hint)
    U.log(string.format("Graft %s: %s (chance %d)", g.id, pair, chance))
    hostsCache.at = -100
    refresh_looks()
    return true
end

local function pick(g)
    local products, why = Core.Pick(st, g)
    if not products then return false, why end
    save()
    local parts = give_products(products)
    xp(Rules.XP.pick, "Hybrid picked")
    card("PICKED", Rules.HybridName(g.scion, g.host),
        (#parts > 0 and table.concat(parts, ", ") or "Nothing could be added to your pack") .. ". More after dawn.")
    return true
end

-- Primelets ---------------------------------------------------------------

local function near_primelet()
    if not (st and st.primelets and #st.primelets > 0) then return nil end
    local feet, yaw = World.Facing()
    if not feet then return nil end
    return Primelet.Near(st, feet, yaw, World.WorldKey())
end

local function tend(p)
    local line, counted = Primelet.Tend(st, p, function(n) return math.random(n) end)
    if counted then
        save()
        local nextStage = Primelet.STAGES[p.stage + 1]
        if nextStage then xp(Rules.XP.tend, "Primelet tended") end
        vfx_at({ X = p.x, Y = p.y, Z = (p.z or 0) + 30 })
    end
    if not cfg.quiet then
        cfg.ESL.ShowCard(cfg.SKILL, counted and "TENDED" or "PRIMELET", Primelet.Name(p), line, 5)
    end
    U.log("Primelet " .. p.id .. (counted and " tended" or " already tended today"))
end

local function pick_up(p)
    local entry, why = Primelet.PickUp(st, p, Rules.SATCHEL_SIZE)
    if not entry then refuse("SATCHEL", why) return end
    save()
    refresh_primelets()
    if not cfg.quiet then
        cfg.ESL.ShowCard(cfg.SKILL, "PICKED UP", Primelet.Name(p),
            "It settles into your satchel without complaint. Press " .. cfg.actionKey .. " to set it down.", 5)
    end
    U.log("Primelet " .. p.id .. " picked up")
end

local function set_down(entry)
    local feet, yaw = World.Facing()
    if not feet then return end
    local d = 120
    local x, y = feet.X + math.cos(math.rad(yaw)) * d, feet.Y + math.sin(math.rad(yaw)) * d
    local z = World.GroundAt(x, y, feet.Z)
    local p, why = Primelet.Place(st, entry, x, y, z, yaw + 180, World.WorldKey())
    if not p then refuse("PRIMELET", why) return end
    save()
    refresh_primelets()
    if not cfg.quiet then
        cfg.ESL.ShowCard(cfg.SKILL, "SET DOWN", Primelet.Name(p), "It surveys its new surroundings and finds them adequate.", 4)
    end
    U.log(string.format("Primelet %s set down at %.0f, %.0f, %.0f (world %s)", p.id, x, y, z, tostring(p.world)))
end

-- The game's interact key: tends a Primelet the player faces, unless the
-- game's own prompt is on something else.
function Splicing.Interact()
    if not (U.pc() and cfg.ESL.Character() and cfg.ESL.IsUnlocked(cfg.SKILL)) then return end
    if not ensure_state() then return end
    local p = near_primelet()
    if not p or World.PromptTarget() then return end
    tend(p)
end

function Splicing.Action()
    if not ready() then return end
    local sel = Core.Selected(st)
    if sel and sel.primelet then set_down(sel) return end
    local p = near_primelet()
    if p then tend(p) return end
    local c = World.Aimed()
    if not c then
        refuse("HORTICULTURE", "Aim at a crop, sapling or tree within reach")
        return
    end
    local g = c.kind ~= "stump" and c.kind ~= "wild" and Core.GraftOn(st, as_point(c)) or nil
    local pickWhy = nil
    if g and g.state == "hybrid" and g.kind ~= "plot" then
        local ok, why = Core.CanPick(st, g)
        if ok then pick(g) return end
        if not Core.Selected(st) then refuse("NOTHING TO PICK", why) return end
        pickWhy = why
    end
    if c.kind == "stump" then refuse("HORTICULTURE", "Nothing grows from a stump") return end
    -- With a cutting in hand, a plant you grew is a host: say why a graft
    -- fails rather than quietly taking a cutting from it.
    local isHost = c.kind == "plot" or c.planted
    if Core.Selected(st) and isHost then
        local ok, why = graft(c)
        if ok then return end
        -- A hybrid picked today: its harvest is the news, not the graft.
        if pickWhy then refuse("NOTHING TO PICK", pickWhy) return end
        U.log("CANNOT GRAFT: " .. tostring(why))
        if not cfg.quiet then
            cfg.ESL.ShowCard(cfg.SKILL, "CANNOT GRAFT", why, "Alt+" .. cfg.actionKey .. " takes a cutting from it instead.", 4)
        end
        return
    end
    take_cutting(c)
end

function Splicing.TakeCutting()
    if not ready() then return end
    local p = near_primelet()
    if p then pick_up(p) return end
    take_cutting(World.Aimed())
end

function Splicing.Cycle()
    if not ready() then return end
    local c = Core.Cycle(st)
    if not c then refuse("SATCHEL", "Your satchel is empty. Take a cutting first") return end
    save()
    if not cfg.quiet then
        local p = c.primelet and Primelet.Find(st, c.primelet)
        cfg.ESL.ShowCard(cfg.SKILL, p and "SELECTED" or "CUTTING SELECTED", p and Primelet.Name(p) or Rules.Name(c.species),
            string.format("%d of %d in your satchel.%s", st.selected, #st.cuttings,
                p and (" " .. cfg.actionKey .. " sets it down.") or ""), 2.5)
    end
end

-- Status ------------------------------------------------------------------

function Splicing.SatchelLine()
    if not st then return "Satchel: empty" end
    if #st.cuttings == 0 then return "Satchel: empty" end
    local names = {}
    for i, c in ipairs(st.cuttings) do
        local p = c.primelet and Primelet.Find(st, c.primelet)
        names[#names + 1] = (p and Primelet.Name(p) or Rules.Name(c.species)) .. (i == st.selected and "*" or "")
    end
    return string.format("Satchel %d/%d: %s", #st.cuttings, Rules.SATCHEL_SIZE, table.concat(names, ", "))
end

function Splicing.CatalogueLine()
    local found = Splicing.Discovered()
    local names = {}
    for _, id in ipairs(found) do names[#names + 1] = hybrid_label(id) end
    local n = flagship_count()
    if #names == 0 then return string.format("Hybrids: none yet (0/%d flagship)", Rules.FLAGSHIP_TOTAL) end
    return string.format("Hybrids (%d/%d flagship): %s", n, Rules.FLAGSHIP_TOTAL, table.concat(names, ", "))
end

-- For the status line; empty when the character has no Primelet.
function Splicing.PrimeletLine()
    if not st or not st.primelets or #st.primelets == 0 then return "" end
    return Primelet.StatusLine(st, World.WorldKey())
end

function Splicing.PendingCount()
    local p, h = 0, 0
    for _, g in ipairs(st and st.grafts or {}) do
        if g.state == "pending" then p = p + 1 else h = h + 1 end
    end
    return p, h
end

-- Developer helpers -------------------------------------------------------

function Splicing.State() return ensure_state() end
function Splicing.Save() save() end
function Splicing.Refresh() hostsCache.at = -100 refresh_looks() refresh_primelets() end

-- Developer only: the next cabbage-on-cabbage graft that takes becomes a
-- Brassica Primelet.
-- With no cabbage-on-cabbage graft pending, one is seeded two metres ahead
-- of the player (a character with no farm plots can still test it).
function Splicing.ForcePrimelet()
    forcePrimelet = true
    U.log("[DEV] The next cabbage-on-cabbage graft that takes becomes a Brassica Primelet")
    if not ensure_state() then return end
    for _, g in ipairs(st.grafts) do
        if g.state == "pending" and Core.IsPrimeletGraft(g) then return end
    end
    local feet, yaw = World.Facing()
    if not feet then return end
    local x = feet.X + math.cos(math.rad(yaw)) * 200 - Core.PRIMELET_OFFSET
    local y = feet.Y + math.sin(math.rad(yaw)) * 200
    local g = Store.SetPlants({ id = "g" .. st.nextId, kind = "plot", key = "dev:primelet", state = "pending",
        made = st.dawn, x = x, y = y, z = World.GroundAt(x + Core.PRIMELET_OFFSET, y, feet.Z), tier = 1, world = World.WorldKey() }, { "FPD_Cabbage", "FPD_Cabbage" })
    st.nextId = st.nextId + 1
    st.grafts[#st.grafts + 1] = g
    save()
    U.log(string.format("[DEV] Seeded cabbage-on-cabbage graft %s; the Primelet will appear at %.0f, %.0f after dawn", g.id, x + Core.PRIMELET_OFFSET, y))
end

function Splicing.Dump()
    if not ensure_state() then U.log("[splice] no character") return end
    U.log(string.format("[splice] dawn %d, hour %s, level %d, file %s", st.dawn, tostring(World.Hour()), level(), path))
    U.log("[splice] " .. Splicing.SatchelLine() .. " | world " .. World.WorldKey())
    for _, g in ipairs(st.grafts) do
        U.log(string.format("[splice] %s %s %s (%s) at %.0f, %.0f made %s picked %s",
            g.id, g.state, table.concat(g.plants, ">"), g.kind, g.x or 0, g.y or 0, tostring(g.made), tostring(g.lastPick)))
    end
    for _, p in ipairs(st.primelets or {}) do
        U.log(string.format("[splice] primelet %s stage %d growth %d tended %d world %s carried %s at %.0f, %.0f, %.0f",
            p.id, p.stage, p.growth, p.tended, tostring(p.world), tostring(p.carried), p.x or 0, p.y or 0, p.z or 0))
    end
    local c = World.Aimed()
    if c then
        U.log(string.format("[splice] aimed: %s %s species %s planted %s stage %s tier %s key %s",
            c.kind, U.full(c.actor or c.obj), tostring(c.species), tostring(c.planted), tostring(c.stage), tostring(c.tier), tostring(c.key)))
    else
        U.log("[splice] aimed: nothing")
    end
    local me = U.location(U.pawn())
    if me then
        for _, h in ipairs(World.Nearby(me, 6000)) do
            if h.kind == "plot" or h.planted then
                U.log(string.format("[splice] planted %s %s at %.0f, %.0f (%.0f m)", h.kind, tostring(h.species),
                    h.loc.X, h.loc.Y, U.dist2d(h.loc, me) / 100))
            end
        end
        for _, w in ipairs(World.WildSpawners(me, 6000)) do
            U.log(string.format("[splice] wild %s at %.0f, %.0f (%.0f m)", w.species, w.loc.X, w.loc.Y, U.dist2d(w.loc, me) / 100))
        end
    end
    U.log("[splice] held axe power " .. tostring((World.HeldAxe())))
    World.DumpEquipment()
    U.log("[splice] " .. Splicing.CatalogueLine())
end

function Splicing.Start(config)
    cfg = config
    Looks.Init(U, cfg.dir)
    math.randomseed(os.time())
    U.every(2000, "Splicing clock", function() U.game(watch_clock) end)
    U.every(2000, "Hybrid looks", function() U.game(refresh_looks) U.game(refresh_primelets) end)
    U.every(500, "Splicing cards", pump_cards)
    local key = Key[cfg.actionKey]
    RegisterKeyBindAsync(key, {}, function() U.game(Splicing.Action) end)
    RegisterKeyBindAsync(key, { ModifierKey.ALT }, function() U.game(Splicing.TakeCutting) end)
    RegisterKeyBindAsync(key, { ModifierKey.SHIFT }, function() U.game(Splicing.Cycle) end)
    RegisterKeyBindAsync(Key.E, {}, function() U.game(Splicing.Interact) end)
end

return Splicing

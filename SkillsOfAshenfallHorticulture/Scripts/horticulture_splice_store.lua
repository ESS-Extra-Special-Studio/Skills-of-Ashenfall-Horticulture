-- The character's splicing state: the cutting satchel, grafts in the world,
-- Brassica Primelets, the dawn counter and which plants gave a cutting
-- today. One text file per character beside the ESL progress file,
-- Saved\ESLDragonWilds\<character>.Horticulture.splicing.txt. Discoveries
-- live in the ESL save itself (Award ids "hybrid:<id>").
--
-- A graft keeps its plants as an ordered list, host first ("Ash>FPD_Potato"),
-- so a third graft adds to the list. Version 1 files kept a host and a
-- scion field; they are read into the list.
local Store = {}

Store.VERSION = 3

-- Hybrid trees saved before Rootstock (crop scions) or before the wood rule
-- (tree scions) wake with this many picks or chops once.
Store.GRANDFATHER_VIGOUR = 4

function Store.New()
    return {
        dawn = 0,
        selected = 1,
        nextId = 1,
        firstTaken = false,
        cuttings = {},
        grafts = {},
        sources = {},
        primeSources = {},
        primelets = {},
    }
end

-- Sets a graft's plant list and the host and scion it is known by: the
-- first plant, and the newest cutting.
function Store.SetPlants(g, plants)
    g.plants = plants
    g.host = plants[1]
    g.scion = plants[#plants]
    return g
end

local function clean(s)
    return (tostring(s or ""):gsub("[|\r\n=]", "_"))
end

local function num(s)
    return tonumber(s)
end

local V1_FIELDS = { "id", "kind", "host", "scion", "state", "made", "lastPick", "x", "y", "z", "key", "tier", "bonus" }
-- Fields after "world" came with Rootstock (version 3); older rows lack them.
local GRAFT_FIELDS = { "id", "kind", "plants", "state", "made", "lastPick", "x", "y", "z", "key", "tier", "bonus", "world",
    "quality", "vigour", "fed", "wet" }
local NUMERIC = { made = true, lastPick = true, x = true, y = true, z = true, tier = true, bonus = true, quality = true, vigour = true }
-- Fields after "carried" came with the Primelet voice; older rows lack them.
local PRIMELET_FIELDS = { "id", "stage", "growth", "tended", "born", "world", "x", "y", "z", "yaw", "carried",
    "personality", "name", "potted", "talked", "ign", "seen", "said" }
local PRIMELET_NUMERIC = { stage = true, growth = true, tended = true, born = true, x = true, y = true, z = true, yaw = true,
    talked = true, ign = true, seen = true }

local function row(t, fields)
    local parts = {}
    for i, f in ipairs(fields) do
        local v = t[f]
        if f == "plants" then v = table.concat(t.plants or { t.host, t.scion }, ">")
        elseif f == "said" then
            local keys = {}
            for k in pairs(t.said or {}) do keys[#keys + 1] = k end
            table.sort(keys)
            v = table.concat(keys, ",")
        elseif type(v) == "number" and (f == "x" or f == "y" or f == "z" or f == "yaw") then v = string.format("%.0f", v)
        elseif type(v) == "boolean" then v = v and "1" or "0" end
        parts[i] = clean(v == nil and "" or v)
    end
    return table.concat(parts, "|")
end

function Store.Serialize(st)
    local lines = {
        "# Skills of Ashenfall: Horticulture splicing. Edited by the mod; do not edit while the game runs.",
        "version=" .. Store.VERSION,
        "dawn=" .. st.dawn,
        "selected=" .. st.selected,
        "nextid=" .. st.nextId,
        "firsttaken=" .. (st.firstTaken and "1" or "0"),
    }
    if st.pmflag1 then lines[#lines + 1] = "pmflag1=1" end
    if st.lastSeen then lines[#lines + 1] = "lastseen=" .. string.format("%.0f", st.lastSeen) end
    for _, c in ipairs(st.cuttings) do
        lines[#lines + 1] = "cut=" .. clean(c.species) .. "|" .. c.taken .. "|" .. clean(c.primelet or "") .. "|" .. (c.quality or 1)
    end
    for _, g in ipairs(st.grafts) do
        lines[#lines + 1] = "graft=" .. row(g, GRAFT_FIELDS)
    end
    for _, p in ipairs(st.primelets or {}) do
        lines[#lines + 1] = "primelet=" .. row(p, PRIMELET_FIELDS)
    end
    local keys = {}
    for k in pairs(st.sources) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        if st.sources[k] == st.dawn then lines[#lines + 1] = "src=" .. clean(k) .. "|" .. st.sources[k] end
    end
    keys = {}
    for k in pairs(st.primeSources or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do lines[#lines + 1] = "prime=" .. clean(k) .. "|" .. st.primeSources[k] end
    return table.concat(lines, "\n") .. "\n"
end

local function split(s, sep)
    sep = sep or "|"
    local out = {}
    for part in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out + 1] = part end
    return out
end

local function read_row(v, fields, numeric)
    local p = split(v)
    local t = {}
    for i, f in ipairs(fields) do
        local raw = p[i]
        if raw == "" then raw = nil end
        if raw and numeric[f] then raw = num(raw) end
        t[f] = raw
    end
    return t
end

function Store.Parse(text)
    local st = Store.New()
    local version = 1
    for line in (text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k == "version" then version = num(v) or 1
        elseif k == "dawn" then st.dawn = num(v) or 0
        elseif k == "selected" then st.selected = num(v) or 1
        elseif k == "nextid" then st.nextId = num(v) or 1
        elseif k == "firsttaken" then st.firstTaken = v == "1"
        elseif k == "pmflag1" then st.pmflag1 = v == "1"
        elseif k == "lastseen" then st.lastSeen = num(v)
        elseif k == "cut" then
            local p = split(v)
            if p[1] ~= "" then
                st.cuttings[#st.cuttings + 1] = { species = p[1], taken = num(p[2]) or 0, primelet = (p[3] and p[3] ~= "" and p[3]) or nil,
                    quality = num(p[4]) or 1 }
            end
        elseif k == "graft" then
            local g
            if version < 2 then
                g = read_row(v, V1_FIELDS, NUMERIC)
                if g.host and g.scion then Store.SetPlants(g, { g.host, g.scion }) end
            else
                g = read_row(v, GRAFT_FIELDS, NUMERIC)
                if g.plants then Store.SetPlants(g, split(g.plants, ">")) end
            end
            g.fed, g.wet = g.fed == "1", g.wet == "1"
            if g.state == "hybrid" and g.kind ~= "plot" and g.scion and g.vigour == nil then g.vigour = Store.GRANDFATHER_VIGOUR end
            if g.id and g.plants and #g.plants >= 2 then st.grafts[#st.grafts + 1] = g end
        elseif k == "primelet" then
            local p = read_row(v, PRIMELET_FIELDS, PRIMELET_NUMERIC)
            p.carried = p.carried == "1"
            p.potted = p.potted == "1"
            local said = {}
            for _, h in ipairs(p.said and split(p.said, ",") or {}) do if h ~= "" then said[h] = true end end
            p.said = said
            p.stage, p.growth, p.tended = p.stage or 1, p.growth or 0, p.tended or -1
            p.world = p.world or "?"
            if p.id then st.primelets[#st.primelets + 1] = p end
        elseif k == "src" then
            local p = split(v)
            if p[1] ~= "" then st.sources[p[1]] = num(p[2]) end
        elseif k == "prime" then
            local p = split(v)
            if p[1] ~= "" then st.primeSources[p[1]] = num(p[2]) end
        end
    end
    if st.selected > #st.cuttings then st.selected = math.max(1, #st.cuttings) end
    return st
end

function Store.Load(path)
    local f = path and io.open(path, "r")
    if not f then return Store.New() end
    local text = f:read("*a")
    f:close()
    return Store.Parse(text)
end

-- Writes through a temporary file so a crash mid-write keeps the old file.
function Store.Save(path, st)
    if not path then return false end
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(Store.Serialize(st))
    f:close()
    os.remove(path)
    local ok = os.rename(tmp, path)
    return ok == true
end

return Store

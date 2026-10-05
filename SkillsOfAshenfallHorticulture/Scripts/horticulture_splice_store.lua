-- The character's splicing state: the cutting satchel, grafts in the world,
-- the dawn counter and which plants gave a cutting today. One text file per
-- character beside the ESL progress file,
-- Saved\ESLDragonWilds\<character>.Horticulture.splicing.txt. Discoveries
-- live in the ESL save itself (Award ids "hybrid:<id>").
local Store = {}

Store.VERSION = 1

function Store.New()
    return {
        dawn = 0,
        selected = 1,
        nextId = 1,
        firstTaken = false,
        cuttings = {},
        grafts = {},
        sources = {},
    }
end

local function clean(s)
    return (tostring(s or ""):gsub("[|\r\n=]", "_"))
end

local function num(s)
    return tonumber(s)
end

local GRAFT_FIELDS = { "id", "kind", "host", "scion", "state", "made", "lastPick", "x", "y", "z", "key", "tier", "bonus" }

function Store.Serialize(st)
    local lines = {
        "# Skills of Ashenfall: Horticulture splicing. Edited by the mod; do not edit while the game runs.",
        "version=" .. Store.VERSION,
        "dawn=" .. st.dawn,
        "selected=" .. st.selected,
        "nextid=" .. st.nextId,
        "firsttaken=" .. (st.firstTaken and "1" or "0"),
    }
    for _, c in ipairs(st.cuttings) do
        lines[#lines + 1] = "cut=" .. clean(c.species) .. "|" .. c.taken
    end
    for _, g in ipairs(st.grafts) do
        local parts = {}
        for i, f in ipairs(GRAFT_FIELDS) do
            local v = g[f]
            if type(v) == "number" and (f == "x" or f == "y" or f == "z") then v = string.format("%.0f", v) end
            parts[i] = clean(v == nil and "" or v)
        end
        lines[#lines + 1] = "graft=" .. table.concat(parts, "|")
    end
    local keys = {}
    for k in pairs(st.sources) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        if st.sources[k] == st.dawn then lines[#lines + 1] = "src=" .. clean(k) .. "|" .. st.sources[k] end
    end
    return table.concat(lines, "\n") .. "\n"
end

local function split(s)
    local out = {}
    for part in (s .. "|"):gmatch("([^|]*)|") do out[#out + 1] = part end
    return out
end

function Store.Parse(text)
    local st = Store.New()
    for line in (text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k == "dawn" then st.dawn = num(v) or 0
        elseif k == "selected" then st.selected = num(v) or 1
        elseif k == "nextid" then st.nextId = num(v) or 1
        elseif k == "firsttaken" then st.firstTaken = v == "1"
        elseif k == "cut" then
            local p = split(v)
            if p[1] ~= "" then st.cuttings[#st.cuttings + 1] = { species = p[1], taken = num(p[2]) or 0 } end
        elseif k == "graft" then
            local p = split(v)
            local g = {}
            for i, f in ipairs(GRAFT_FIELDS) do
                local raw = p[i]
                if raw == "" then raw = nil end
                if raw and (f == "made" or f == "lastPick" or f == "x" or f == "y" or f == "z" or f == "tier" or f == "bonus") then
                    raw = num(raw)
                end
                g[f] = raw
            end
            if g.id and g.host and g.scion then st.grafts[#st.grafts + 1] = g end
        elseif k == "src" then
            local p = split(v)
            if p[1] ~= "" then st.sources[p[1]] = num(p[2]) end
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

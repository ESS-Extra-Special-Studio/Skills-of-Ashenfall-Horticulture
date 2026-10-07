-- Player settings: config.txt next to the Scripts folder, in the same form as
-- Historian's. It is written with the defaults on first run; a missing or
-- invalid value uses the default.
--
-- Default keys avoid what this install already binds: F10 and Tilde
-- (ConsoleEnabler), Insert (BPModLoader), Ctrl+R hot reload, Ctrl+O UE4SS GUI,
-- Ctrl+J, Ctrl+H and Ctrl+Numpad 5-9 (Keybinds), F3 (LineTrace), HOME
-- (ExampleSkill), F7 and F5/F6/F8/F9/F11 (Historian and its developer keys),
-- F9 (the HUD mod) and F12 (Steam screenshots). Ctrl+Alt+G belongs to the
-- studio's internal dev tool only.
local Config = {}

local FIELDS = {
    { key = "status_key", default = "END", kind = "key",
      help = "Key that shows or hides the Horticulture status line and Discovery Catalogue (a UE4SS key name, such as END or NUM_ONE). Shift and this key rereads the Observances." },
    { key = "action_key", default = "G", kind = "key",
      help = "Splicing key. Aim at a plant: picks from a hybrid when it is ready, grafts your selected cutting onto it when it can take it, otherwise takes a cutting. Alt and this key always takes a cutting; Shift and this key picks the next cutting in your satchel. With the optional Action Wheel mod, holding its key (Z) offers the same actions on a wheel; this key keeps working." },
    { key = "primelet_chance", default = "1.5", kind = "number", min = 0, max = 100,
      help = "Percent chance that a cabbage grafted onto a cabbage, once it takes, becomes something else entirely. 0 turns it off." },
    { key = "quiet", default = "false", kind = "bool",
      help = "true hides Horticulture's own cards (cuttings, grafts, Discovery Catalogue entries, the reminder after reading the book). XP and level-up notifications still show." },
    { key = "sway", default = "true", kind = "bool",
      help = "true lets the fruit on hybrid trees sway with the wind, like the leaves. false keeps it still (a little less work each frame)." },
    { key = "sway_degrees", default = "0.35", kind = "number", min = 0, max = 3,
      help = "How far hybrid trees' fruit leans in the game's normal wind, in degrees about the trunk base. 0 keeps it still." },
    { key = "mutation_tint", default = "true", kind = "bool",
      help = "true gives each hybrid's leaves (or crop) its own mutated colour, such as Tuberwood Ash's deep blue-violet. false keeps the host plant's natural colours." },
    { key = "name_tag", default = "true", kind = "bool",
      help = "true shows a small tag above the game's prompt with the name of the Brassica Primelet you face, or of a hybrid whose name the game's own prompt cannot show. Hybrid trees name themselves in the prompt either way." },
    { key = "primelet_chattiness", default = "normal", kind = "choice", choices = { "off", "quiet", "normal", "chatty" },
      help = "How often a grown Primelet speaks up on its own: off, quiet, normal or chatty. With off it only answers when you talk to it or tend it." },
    { key = "wild_cuttings", default = "false", kind = "bool",
      help = "true lets crop cuttings come from wild plants as well as your farm plots." },
    { key = "vigour_picks", default = "4", kind = "number", min = 1, max = 100,
      help = "Picks a crop grafted onto a tree gives before it goes dormant. A new prime cutting of the same crop wakes it." },
    { key = "wood_chops", default = "4", kind = "number", min = 1, max = 100,
      help = "Bonus chops a tree grafted onto a tree gives before it goes dormant. The bonus wood comes on the first chop each day with an axe that could fell every wood in it. A fresh cutting of the grafted tree wakes it." },
    { key = "prime_cooldown_dawns", default = "2", kind = "number", min = 0, max = 30,
      help = "Dawns before the same farm plot gives another prime cutting (one per crop cycle)." },
    { key = "pick_per_farming_levels", default = "10", kind = "number", min = 1, max = 99,
      help = "A tree pick gives the crop's normal harvest plus one per this many Farming levels, never more than half a tended plot's harvest." },
    { key = "pick_farming_xp", default = "true", kind = "bool",
      help = "true pays a little Farming XP for each crop picked from a hybrid tree." },
    { key = "pick_farming_xp_share", default = "0.25", kind = "number", min = 0, max = 1,
      help = "Share of the Farming XP a plot harvest of the same crop pays, for one tree pick." },
    { key = "pick_farming_xp_cap", default = "8", kind = "number", min = 0, max = 100,
      help = "Most Farming XP one tree pick pays." },
    { key = "compost_multiplier", default = "1.5", kind = "number", min = 1, max = 5,
      help = "How much composting a crop hybrid's plot multiplies its extra harvest (the game's own compost bonus is 1.5)." },
    { key = "water_multiplier", default = "1.15", kind = "number", min = 1, max = 5,
      help = "How much watering a crop hybrid's plot multiplies its extra harvest (the game's own water bonus is 1.15)." },
    { key = "prime_share", default = "1", kind = "number", min = 0, max = 10,
      help = "Extra produce a crop hybrid grown from a prime cutting adds at harvest, before compost and water." },
    { key = "farming_scale_cap", default = "1.25", kind = "number", min = 1, max = 3,
      help = "Most a crop hybrid's extra harvest grows with Farming level (1% a level above 25)." },
    { key = "debug", default = "false", kind = "bool",
      help = "true writes extra detail to UE4SS.log, such as each XP payment and crop name lookup." },
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and not line:match("^%s*#") then out[k:lower()] = trim(v) end
    end
    return out
end

local function default_text()
    local lines = { "# Skills of Ashenfall: Horticulture settings. Restart the game after editing.", "" }
    for _, f in ipairs(FIELDS) do
        lines[#lines + 1] = "# " .. f.help
        lines[#lines + 1] = f.key .. " = " .. f.default
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

-- Returns the settings table. log reports values that were not understood.
function Config.Load(dir, log)
    local path = dir .. "\\..\\config.txt"
    local f = io.open(path, "r")
    local raw = {}
    if f then
        raw = parse(f:read("*a"))
        f:close()
    else
        local w = io.open(path, "w")
        if w then
            w:write(default_text())
            w:close()
        end
    end
    local out = {}
    for _, field in ipairs(FIELDS) do
        local v = raw[field.key]
        local value = nil
        if field.kind == "bool" then
            if v == nil or v == "" then value = field.default == "true"
            elseif v == "true" or v == "1" or v == "yes" then value = true
            elseif v == "false" or v == "0" or v == "no" then value = false end
        elseif field.kind == "key" then
            local name = (v and v ~= "") and v:upper() or field.default
            if Key and Key[name] ~= nil then value = name end
        elseif field.kind == "number" then
            local n = tonumber((v and v ~= "") and v or field.default)
            if n and n >= field.min and n <= field.max then value = n end
        elseif field.kind == "choice" then
            local s = (v and v ~= "") and v:lower() or field.default
            for _, c in ipairs(field.choices) do if c == s then value = s end end
        end
        if value == nil then
            if log then log("config.txt: " .. field.key .. " = " .. tostring(v) .. " is not understood; using " .. field.default) end
            if field.kind == "bool" then value = field.default == "true"
            elseif field.kind == "number" then value = tonumber(field.default)
            else value = field.default end
        end
        out[field.key] = value
    end
    return out
end

return Config

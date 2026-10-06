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
            if v == "true" or v == "1" or v == "yes" then value = true
            elseif v == nil or v == "" or v == "false" or v == "0" or v == "no" then value = false end
        elseif field.kind == "key" then
            local name = (v and v ~= "") and v:upper() or field.default
            if Key and Key[name] ~= nil then value = name end
        elseif field.kind == "number" then
            local n = tonumber((v and v ~= "") and v or field.default)
            if n and n >= field.min and n <= field.max then value = n end
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

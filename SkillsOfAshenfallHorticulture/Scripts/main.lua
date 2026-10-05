-- Skills of Ashenfall: Horticulture, levels 1-25, on ESL:DragonWilds.
-- Unlocks at Historian 25 and Farming 25 once the character has read the
-- Observances of Brassica Prime, hidden in a hymnal by the Bramblemead
-- cabbage patch.
local MOD = "Skills of Ashenfall: Horticulture"
local SKILL = "Horticulture"
local VERSION = "1.0.0"
local BOOK_ID = "BrassicaPrime"

local function log(msg)
    print("[" .. MOD .. "] " .. msg .. "\n")
end

local function script_dir()
    local source = debug.getinfo(1, "S").source
    source = source:match("^@(.*)$") or source
    return source:match("^(.*)[/\\]")
end

local dir = script_dir()
if not dir then
    log("Could not find the script folder")
    return
end

package.path = dir .. "\\?.lua;" .. dir .. "\\..\\..\\ESLDragonWilds\\Scripts\\?.lua;" .. package.path
local okESL, ESL = pcall(require, "esl")
if not okESL then
    log("ESL:DragonWilds is missing or failed to load. Install it in the same ~mods folder as this mod. (" .. tostring(ESL) .. ")")
    return
end
if not (ESL.RequireVersion and ESL.RequireVersion("1.1.0", MOD)) then
    log("ESL:DragonWilds is too old. Install ESL:DragonWilds 1.1.0 or later.")
    return
end

local U = require("horticulture_util")
local Lore = require("horticulture_lore")
local Book = require("horticulture_book")
local Training = require("horticulture_training")

-- dev.txt turns on the developer keys. dev-unlock.txt as well drops the
-- Historian and Farming requirements, for testing on a fresh character; the
-- book is still required. Neither file ships (tools\check_release.ps1).
local DEV = U.exists(dir .. "\\..\\dev.txt")
local DEV_UNLOCK = DEV and U.exists(dir .. "\\..\\dev-unlock.txt")
local FORCE_MESH = U.exists(dir .. "\\..\\book-mesh.txt")

ESL.Depends(ESL.HISTORIAN, "1.0.0", MOD)

local BOOK_REQUIREMENT = { book = BOOK_ID, label = "the Observances of Brassica Prime" }
local requires = {
    { skill = ESL.HISTORIAN, level = 25 },
    { vanilla = "Farming", level = 25 },
    BOOK_REQUIREMENT,
}
if DEV_UNLOCK then
    requires = { BOOK_REQUIREMENT }
    log("[DEV] dev-unlock.txt: Historian 25 and Farming 25 are not required in this session. Never ship this file.")
end

local DEV_PERKS = {
    { level = 5, name = "[Test] Seed saver", description = "Test row, unlocked at level 5." },
    { level = 15, name = "[Test] Grafter", description = "Test row, unlocked at level 15." },
    { level = 25, name = "[Test] Cultivar", description = "Test row, unlocked at level 25." },
}

ESL.RegisterSkill({
    id = SKILL,
    name = "Horticulture",
    version = VERSION,
    mod = MOD,
    iconFile = dir .. "\\..\\Textures\\horticulture-skill-icon.png",
    capXp = 3152,
    maxLevel = 25,
    maxLevelText = "Horticulture 25: all v1.0.0 has to teach",
    flavour = "Coax new things out of old seed: save it, cross it, graft it and feed the soil.",
    levelUpText = "Sow, water, feed, cure and harvest your crops to gain Horticulture XP.",
    panelLabel = "Progress to next level",
    trainingText = "Every crop you sow, water, compost, cure or harvest pays Horticulture XP, and the first sowing and harvest of each kind of crop pays extra.",
    requires = requires,
    perks = DEV and DEV_PERKS or {},
})

-- The world prompt on our own book shows the Historian level it needs.
ESL.RequireSkill(ESL.HISTORIAN, 25, Lore.PROMPT_NAME)

local config = {
    ESL = ESL,
    SKILL = SKILL,
    BOOK_ID = BOOK_ID,
    dir = dir,
    dev = DEV,
    devUnlock = DEV_UNLOCK,
    forceMesh = FORCE_MESH,
}

Book.Start(config)
Training.Start(config)

-- The first level comes from the reading itself, paid once the host's new
-- skill card has had its moment, so the game's own XP popup and level-up
-- banner follow it.
local REDISCOVERY = "rediscovery:" .. BOOK_ID
local REDISCOVERY_XP = 33
local unlockSeenAt = nil
U.every(1000, "Rediscovery", function()
    local character = ESL.Character()
    if not character or not ESL.IsUnlocked(SKILL) or ESL.HasPaid(SKILL, REDISCOVERY) then
        unlockSeenAt = nil
        return
    end
    unlockSeenAt = unlockSeenAt or os.clock()
    if os.clock() - unlockSeenAt >= 5.5 then
        ESL.Award(SKILL, REDISCOVERY, REDISCOVERY_XP, "Brassica Prime's Observances")
        log("Horticulture rediscovered by " .. character)
    end
end)

ESL.OnSkillUnlocked(SKILL, function(_, character)
    log("Horticulture unlocked for " .. tostring(character))
end)

local function in_world()
    return U.pc() ~= nil and ESL.Character() ~= nil
end

RegisterKeyBindAsync(Key.F10, {}, function()
    if not in_world() then log("Load into a world first") return end
    if not ESL.IsUnlocked(SKILL) then
        ESL.Gate(SKILL, { notify = true, title = "Horticulture", skill = SKILL })
        return
    end
    ESL.ToggleStatus(SKILL)
end)

RegisterKeyBindAsync(Key.F10, { ModifierKey.SHIFT }, function()
    Book.Reread()
end)

if DEV then
    require("horticulture_dev").Start(config, Book, Training)
    RegisterKeyBindAsync(Key.F6, { ModifierKey.CONTROL }, function() ESL.TestNotifications(SKILL) end)
    RegisterKeyBindAsync(Key.F7, { ModifierKey.CONTROL }, function() ESL.SelectInSkillsMenu(SKILL) end)
end

log("Loaded " .. VERSION .. ". F10 shows Horticulture, Shift+F10 rereads the Observances."
    .. (DEV and " Developer keys on." or ""))

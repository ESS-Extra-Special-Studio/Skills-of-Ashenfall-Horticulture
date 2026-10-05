-- Skills of Ashenfall: Horticulture, levels 1-25, on ESL:DragonWilds.
-- Unlocks at Historian 25 and Farming 25 once the character has read the
-- Observances of Brassica Prime, hidden in a hymnal by the Bramblemead
-- cabbage patch. Trained by taking cuttings and grafting them onto crops and
-- trees the player planted; the hybrids that take are entered in the
-- Discovery Catalogue.
local MOD = "Skills of Ashenfall: Horticulture"
-- Permanent: names every player's save file. Never change it.
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
if not (ESL.RequireVersion and ESL.RequireVersion("1.0.0", MOD)) then
    log("ESL:DragonWilds is too old. Install ESL:DragonWilds 1.0.0 or later.")
    return
end

local U = require("horticulture_util")
local Lore = require("horticulture_lore")
local Book = require("horticulture_book")
local Training = require("horticulture_training")
local Splicing = require("horticulture_splicing")
local Perks = require("horticulture_perks")

-- dev.txt turns on the developer keys. dev-unlock.txt as well drops the
-- Historian and Farming requirements, for testing on a fresh character; the
-- book is still required. showcase.txt drops them too, with no developer
-- keys, for recording the unlock on a low-level character. spike.txt logs
-- farming hooks and plot state for the in-game spike. None of these files
-- ships (tools\check_release.ps1).
local DEV = U.exists(dir .. "\\..\\dev.txt")
local SHOWCASE = U.exists(dir .. "\\..\\showcase.txt")
local DEV_UNLOCK = (DEV and U.exists(dir .. "\\..\\dev-unlock.txt")) or SHOWCASE
local SPIKE = U.exists(dir .. "\\..\\spike.txt")
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
    log("[DEV] " .. (SHOWCASE and "showcase.txt" or "dev-unlock.txt")
        .. ": Historian 25 and Farming 25 are not required in this session. Never ship this file.")
end

local Settings = require("horticulture_config").Load(dir, log)
local STATUS_KEY = Settings.status_key

ESL.RegisterSkill({
    id = SKILL,
    name = "Horticulture",
    version = VERSION,
    mod = MOD,
    iconFile = dir .. "\\..\\Textures\\horticulture-skill-icon.png",
    capXp = 3152,
    maxLevel = 25,
    maxLevelText = "Horticulture 25: all v1.0.0 has to teach",
    flavour = "Take cuttings, graft them onto the crops and trees you planted, and see what grows by dawn.",
    levelUpText = "Take cuttings and graft them onto your crops and trees to gain Horticulture XP. New hybrids pay the most.",
    panelLabel = "Progress to next level",
    trainingText = "Aim at a plant and press " .. Settings.action_key .. " to take a cutting, then aim at a crop, sapling or tree you planted and press "
        .. Settings.action_key .. " to graft it. At dawn the graft takes or is rejected; a graft that takes becomes a hybrid, "
        .. "and each new hybrid enters your Discovery Catalogue. Pick from hybrid trees once a day. Tree cuttings need an axe that can fell the tree, "
        .. "and never take on a crop. Ordinary farming still pays a little.",
    requires = requires,
    perks = Perks.Rows(DEV),
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
    quiet = Settings.quiet,
    debug = Settings.debug,
    actionKey = Settings.action_key,
    primeletChance = Settings.primelet_chance,
}

Book.Start(config)
Training.Start(config)
Splicing.Start(config)

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

RegisterKeyBindAsync(Key[STATUS_KEY], {}, function()
    if not in_world() then log("Load into a world first") return end
    if not ESL.IsUnlocked(SKILL) then
        ESL.Gate(SKILL, { notify = true, title = "Horticulture", skill = SKILL })
        return
    end
    ESL.ToggleStatus(SKILL, function()
        local prime = Splicing.PrimeletLine()
        return Splicing.SatchelLine() .. (prime ~= "" and ("  |  " .. prime) or "") .. "  |  " .. Splicing.CatalogueLine()
            .. "  |  " .. Training.CatalogueLine()
    end)
end)

RegisterKeyBindAsync(Key[STATUS_KEY], { ModifierKey.SHIFT }, function()
    Book.Reread()
end)

if SPIKE then
    require("horticulture_spike").Start(config)
end

if DEV then
    local Dev = require("horticulture_dev")
    Dev.Start(config, Book, Training, Splicing)
    RegisterKeyBindAsync(Key.F2, Dev.SHIFT_ALT, function() ESL.TestNotifications(SKILL) end)
    RegisterKeyBindAsync(Key.F3, Dev.SHIFT_ALT, function() ESL.SelectInSkillsMenu(SKILL) end)
end

log("Loaded " .. VERSION .. ". " .. STATUS_KEY .. " shows Horticulture, Shift+" .. STATUS_KEY
    .. " rereads the Observances, " .. Settings.action_key .. " takes cuttings and grafts (Alt+" .. Settings.action_key
    .. " cutting only, Shift+" .. Settings.action_key .. " next cutting)." .. (Settings.quiet and " Quiet mode is on." or "")
    .. (DEV and " Developer keys on." or ""))

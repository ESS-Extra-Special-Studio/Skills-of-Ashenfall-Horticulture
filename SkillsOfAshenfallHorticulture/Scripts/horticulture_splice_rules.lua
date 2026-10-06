-- Splicing rules: which cuttings exist, who may take them, what may be
-- grafted onto what, the chance a graft takes, XP, and the named hybrids.
-- Pure Lua, no game calls, so the offline tests can drive it directly.
--
-- Design: docs/HORTICULTURE_SPLICING_REDESIGN.md (Dragonwilds docs folder),
-- sections 3.1-3.4 and 4.
--
-- Vanilla gates mirrored (build 25632050):
--   Trees need an axe that can fell them: power Ash 1 (stone), Oak 3
--   (bronze), Willow 4 (iron), Maple 6 (mithril), Yew 7 (adamant), Magic 8.
--   Crops have a tier and a preferred plot tier (Ash plot 1, Oak plot 2,
--   Willow plot 3, Yew plot 4).
local Rules = {}

Rules.SATCHEL_SIZE = 6
Rules.WILT_DAWNS = 2
Rules.MAX_LEVEL = 25

-- Paced by tools\budget_sim.py: Horticulture 25 (3,152 XP) in four to six
-- in-game days, about three quarters of it from splicing.
Rules.XP = {
    cutting = 8,
    graft = 20,
    takes = 45,
    rejected = 10,
    discovery = 50,
    flagship = 200,
    pick = 25,
    primelet = 200,
    primeletStage = 30,
    tend = 5,
}

-- A hybrid is an ordered list of plants: the host first, then each cutting
-- grafted onto it. v1 stops at two; the 1-99 plan's Triple Graft (level 50)
-- raises it to three, with no change to the save.
Rules.MAX_PLANTS = 2
Rules.TRIPLE_LEVEL = 50

function Rules.MaxPlants(level)
    if Rules.MAX_LEVEL >= Rules.TRIPLE_LEVEL and (level or 1) >= Rules.TRIPLE_LEVEL then return 3 end
    return Rules.MAX_PLANTS
end

-- Same-species grafts that are allowed. Cabbage onto cabbage is how a
-- Brassica Primelet happens.
Rules.SELF_GRAFTS = { FPD_Cabbage = true }

Rules.PRIMELET = {
    id = "BrassicaPrimelet", name = "Brassica Primelet",
    chance = 1.5, -- percent of cabbage-on-cabbage grafts that take
}

-- Trees. band: Horticulture level at which the species may be cut and used
-- as a host; nil means beyond v1. hostTier: the plot tier the species
-- stands in for when a crop is grafted onto it.
Rules.TREES = {
    Ash = { name = "Ash", power = 1, band = 1, hostTier = 1, item = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Wood_Ash" },
    Oak = { name = "Oak", power = 3, band = 8, hostTier = 2, item = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Wood_Oak" },
    Willow = { name = "Willow", power = 4, band = 20, hostTier = 3, item = "/Game/Gameplay/Items/Resources/Wood/ITEM_Resources_Wood_Willow" },
    Maple = { name = "Maple", power = 6, hostTier = 3 },
    Yew = { name = "Yew", power = 7, hostTier = 4 },
    Magic = { name = "Magic", power = 8, hostTier = 4 },
}

local PLANT = "/Game/Gameplay/Items/Resources/Plant/"
local FOOD = "/Game/Gameplay/Items/Consumables/Food/Items/v3/"

-- Crops, keyed by their FarmPlantDataAsset name.
Rules.CROPS = {
    FPD_Cabbage = { name = "Cabbage", band = 1, tier = 1, item = PLANT .. "ITEM_Resources_Cabbage" },
    FPD_Potato = { name = "Potato", band = 5, tier = 1, item = PLANT .. "ITEM_Resources_Potato" },
    FPD_Wheat = { name = "Wheat", band = 10, tier = 1, item = PLANT .. "ITEM_Resources_Wheat" },
    FPD_Redberry = { name = "Redberry", band = 10, tier = 1, item = FOOD .. "ITEM_Consumable_Fruit_Redberry" },
    FPD_Flax = { name = "Flax", band = 13, tier = 1, item = PLANT .. "ITEM_Resources_Flax" },
    FPD_Harralander = { name = "Harralander", band = 15, tier = 1.5 },
    FPD_Marrentill = { name = "Marrentill", band = 15, tier = 1.5 },
    FPD_Onion = { name = "Onion", band = 18, tier = 2, item = PLANT .. "ITEM_Resources_Onion" },
    FPD_Tomato = { name = "Tomato", band = 18, tier = 2, item = PLANT .. "ITEM_Resources_Tomato" },
    FPD_Kwuarm = { name = "Kwuarm", band = 22, tier = 1.5 },
    FPD_Dwellberry = { name = "Dwellberry", band = 22, tier = 2, item = FOOD .. "ITEM_Consumable_Fruit_Dwellberry" },
}

-- Logging axes by item name, for when the item's own power cannot be read.
Rules.AXES = {
    ITEM_Logging_Axe_Stone = 1,
    ITEM_Logging_Axe_Bronze = 3,
    ITEM_Logging_Axe_Iron = 4,
    ITEM_Logging_Axe_Steel = 5,
    ITEM_Logging_Axe_Mithril = 6,
    ITEM_Logging_Axe_Adamant = 7,
    ITEM_Logging_Axe_Rune = 8,
}

function Rules.IsTree(species) return Rules.TREES[species] ~= nil end
function Rules.IsCrop(species) return Rules.CROPS[species] ~= nil end

function Rules.Name(species)
    local d = Rules.TREES[species] or Rules.CROPS[species]
    if d then return d.name end
    return (tostring(species):gsub("^FPD_", ""):gsub("_", " "))
end

function Rules.Band(species)
    local d = Rules.TREES[species] or Rules.CROPS[species]
    return d and d.band or nil
end

-- Power of an axe from its item name, or nil when it is not a logging axe.
function Rules.AxePower(itemName)
    if not itemName then return nil end
    for name, power in pairs(Rules.AXES) do
        if itemName:find(name, 1, true) then return power end
    end
    return nil
end

-- Named hybrids. key = scion .. ">" .. host.
Rules.FLAGSHIPS = {
    ["FPD_Potato>Ash"] = {
        id = "TuberwoodAsh", name = "Tuberwood Ash", required = true, order = 1,
        products = { { species = "FPD_Potato", count = 3 } },
        detail = "Potato grafted onto ash. Pick potatoes from its branches once a day.",
        lore = "An ash that has decided the interesting part of a tree is underground. It may have a point.",
    },
    ["FPD_Cabbage>Oak"] = {
        id = "BrassicaOak", name = "Brassica-Oak", required = true, order = 2,
        products = { { species = "FPD_Cabbage", count = 3 } },
        detail = "Cabbage grafted onto oak. Pick cabbages from the canopy once a day.",
        lore = "Brassicans held that every tree is a cabbage that lost its nerve. This one found it again, about twenty feet up.",
    },
    ["FPD_Cabbage>FPD_Potato"] = {
        id = "Brassitato", name = "Brassitato", required = true, order = 3,
        products = { { species = "FPD_Cabbage", count = 2 } },
        detail = "Cabbage grafted onto potato. Its harvest brings cabbages as well.",
        lore = "Two crops in one plot, which saves on fencing. It cannot decide whether to be boiled or mashed, and neither can the cook.",
    },
    ["FPD_Wheat>Ash"] = {
        id = "SheafAsh", name = "Sheaf Ash", required = true, order = 4,
        products = { { species = "FPD_Wheat", count = 4 } },
        detail = "Wheat grafted onto ash. Pick wheat from its branches once a day.",
        lore = "A loaf on a branch was the dream. A sheaf on a branch is what was achieved.",
    },
    ["Willow>Oak"] = {
        id = "WeepingOak", name = "Weeping Oak", required = true, order = 5, level = 20,
        products = { { species = "Willow", count = 2 }, { species = "Oak", count = 1 } },
        detail = "Willow grafted onto oak. Pick willow and oak wood once a day.",
        lore = "Oak for strength, willow for grief. The result stands very firmly and is sad about it.",
    },
    ["FPD_Redberry>Oak"] = {
        id = "BrambleOak", name = "Bramble Oak", order = 6,
        products = { { species = "FPD_Redberry", count = 3 } },
        detail = "Redberry grafted onto oak. Pick redberries from the canopy once a day.",
        lore = "The birds found it before the gardener did, and have not stopped telling each other.",
    },
    ["Oak>Ash"] = {
        id = "TwoBarkAsh", name = "Two-Bark Ash", order = 7,
        products = { { species = "Oak", count = 2 } },
        detail = "Oak grafted onto ash. Pick oak wood once a day.",
        lore = "Two druids argued over which tree to plant. This is the compromise, and neither of them likes it.",
    },
    ["FPD_Onion>FPD_Cabbage"] = {
        id = "WeepingCabbage", name = "Weeping Cabbage", order = 8,
        products = { { species = "FPD_Onion", count = 2 } },
        detail = "Onion grafted onto cabbage. Its harvest brings onions as well.",
        lore = "The cook cries before she even cuts it.",
    },
}

Rules.FLAGSHIP_TOTAL = 8
Rules.REQUIRED_TOTAL = 5

-- Named hybrids that are not flagships.
Rules.NAMES = {
    ["FPD_Cabbage>FPD_Cabbage"] = "Doubled Cabbage",
}

function Rules.ComboKey(scion, host) return tostring(scion) .. ">" .. tostring(host) end

-- Key for an ordered plant list { host, scion1, scion2, ... }: the newest
-- cutting first, the host last, so a pair gives the same key as ComboKey.
function Rules.PlantsKey(plants)
    local parts = {}
    for i = #plants, 1, -1 do parts[#parts + 1] = tostring(plants[i]) end
    return table.concat(parts, ">")
end

function Rules.Flagship(scion, host)
    return Rules.FLAGSHIPS[Rules.ComboKey(scion, host)]
end

function Rules.FlagshipById(id)
    for key, f in pairs(Rules.FLAGSHIPS) do
        if f.id == id then return f, key end
    end
    return nil
end

-- Display name for any hybrid: the flagship name, else "Scion-Host".
function Rules.HybridName(scion, host)
    local f = Rules.Flagship(scion, host)
    if f then return f.name end
    local named = Rules.NAMES[Rules.ComboKey(scion, host)]
    if named then return named end
    return Rules.Name(scion) .. "-" .. Rules.Name(host)
end

-- Display name for an ordered plant list; pairs use HybridName.
function Rules.PlantsName(plants)
    if #plants == 2 then return Rules.HybridName(plants[2], plants[1]) end
    local names = {}
    for i = #plants, 1, -1 do names[#names + 1] = Rules.Name(plants[i]) end
    return table.concat(names, "-")
end

-- Catalogue id for a combination: flagships by id, others by species.
function Rules.HybridId(scion, host)
    local f = Rules.Flagship(scion, host)
    if f then return f.id end
    return Rules.ComboKey(scion, host)
end

-- What a hybrid gives: the flagship's list, else 2 of the scion's own item.
function Rules.Products(scion, host)
    local f = Rules.Flagship(scion, host)
    local list = f and f.products or { { species = scion, count = 2 } }
    local out = {}
    for _, p in ipairs(list) do
        local d = Rules.CROPS[p.species] or Rules.TREES[p.species]
        if d and d.item then out[#out + 1] = { species = p.species, count = p.count, item = d.item, name = d.name } end
    end
    return out
end

-- Can this source give a cutting? src = { species, kind = "crop"|"tree",
-- level, axePower (tree sources), alive (crop sources) }.
-- Returns true, or false and a reason for the card.
function Rules.CanCut(src)
    local species, level = src.species, src.level or 1
    if not species then return false, "Nothing here to take a cutting from" end
    local band = Rules.Band(species)
    local name = Rules.Name(species)
    if not band then return false, name .. " cuttings are beyond Horticulture " .. Rules.MAX_LEVEL end
    if level < band then return false, string.format("%s cuttings need Horticulture %d", name, band) end
    if Rules.IsTree(species) then
        local need = Rules.TREES[species].power
        if not src.axePower then return false, "Hold a logging axe to take a cutting from " .. name:lower() end
        if src.axePower < need then
            return false, string.format("Your axe is too weak for %s; it takes an axe that can fell it", name:lower())
        end
    elseif not src.alive then
        return false, "Cuttings come from a living plant"
    end
    return true
end

-- Can this cutting go onto this host? host = { species, kind = "plot" |
-- "sapling" | "tree", planted (by a player), stage (plot stage) }.
-- Returns true, or false and a reason.
function Rules.CanGraft(scion, host, level)
    level = level or 1
    if not host or not host.species then return false, "Aim at a crop, sapling or tree you planted" end
    local sName, hName = Rules.Name(scion), Rules.Name(host.species)
    if host.kind == "plot" then
        if Rules.IsTree(scion) then return false, "Tree cuttings cannot take on a crop" end
        if host.stage ~= 1 then return false, "Graft onto a growing crop, before it is ready to harvest" end
    elseif host.kind == "sapling" or host.kind == "tree" then
        if not host.planted then return false, "Only trees you planted will take a graft" end
    else
        return false, "That cannot take a graft"
    end
    if scion == host.species and not Rules.SELF_GRAFTS[scion] then return false, "That is just more " .. sName:lower() end
    local band = Rules.Band(host.species)
    if not band then return false, hName .. " is beyond Horticulture " .. Rules.MAX_LEVEL .. " as a host" end
    if level < band then return false, string.format("%s hosts need Horticulture %d", hName, band) end
    local f = Rules.Flagship(scion, host.species)
    if f and f.level and level < f.level then
        return false, string.format("%s needs Horticulture %d", f.name, f.level)
    end
    return true
end

-- Can one more cutting go onto an existing hybrid? plants: its ordered list.
-- The pair rules still hold against the host (a tree cutting never goes
-- onto a crop), no plant appears twice, and the list stops at MaxPlants.
function Rules.CanAddTo(plants, scion, host, level)
    if #plants >= Rules.MaxPlants(level) then
        if Rules.MaxPlants(level) < 3 then return false, "A third graft is beyond Horticulture " .. Rules.MAX_LEVEL end
        return false, "It cannot take another graft"
    end
    for _, p in ipairs(plants) do
        if p == scion then return false, "It already carries " .. Rules.Name(scion):lower() end
    end
    return Rules.CanGraft(scion, { species = plants[1], kind = host.kind, planted = host.planted, stage = host.stage }, level)
end

-- Chance in percent that a graft takes. host.tier: plot tier (plots) or the
-- tree's hostTier. bonus: extra points (compost, clean water).
function Rules.Chance(scion, host, level, bonus)
    local band = Rules.Band(scion) or 1
    local chance = 60 + math.max(0, (level or 1) - band)
    local crop = Rules.CROPS[scion]
    local hostTier = host.tier
    if not hostTier and Rules.TREES[host.species] then hostTier = Rules.TREES[host.species].hostTier end
    if crop and hostTier and crop.tier > hostTier then
        chance = chance - math.ceil(crop.tier - hostTier) * 10
    end
    chance = chance + (bonus or 0)
    if chance < 25 then chance = 25 end
    if chance > 95 then chance = 95 end
    return chance
end

return Rules

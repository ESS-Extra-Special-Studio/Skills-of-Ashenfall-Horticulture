-- The Brassica Prime book in the world, read through the game's own lore
-- popup.
--
-- Verified in build 25632050 (pak directory index and exe reflection names):
--   /Game/Gameplay/World/Misc/BP_LoreItem              the lore pickup actor
--   /Game/Art/Env/Props/Gameplay_Props/Lore_Book/SM_Lore_Book_01
--   WBP_LorePopupMainPanel_C, with RichTextDescription (ULorePopupMainPanel)
--   LorePopupUIAPI: OpenLorePopup, CloseLorePopup, CurrentEntry
--   JournalEntryData: DisplayName, PageDescriptions; JournalEntryKnowLoreData
--   UnlockJournalEntry ignores entry data it cannot find by persistence id
--   WBP_HUD_InteractionPrompt_C: CurrentWorldActor, ItemNameTextBlock
--   Server_RequestInteraction(bIsSecondaryInteraction, bIsRelease)
--   bSkipSpudStore (keeps a runtime actor out of the world save)
-- Not verified: which property of BP_LoreItem names its journal entry, the
-- parameters of OpenLorePopup, and the popup's title widget. Each is found by
-- reflection at runtime and logged, and every path falls back to the next.
--
-- The book is spawned locally on each machine, never replicated, and never
-- stored in the world save. Reading is recorded per character in the skill's
-- ESL save (read=book:BrassicaPrime). Nothing is written to the journal.
local UEHelpers = require("UEHelpers")
local U = require("horticulture_util")
local Lore = require("horticulture_lore")
local Placement = require("horticulture_placement")
local Page = require("horticulture_page")

local Book = {}

local LORE_ITEM = "/Game/Gameplay/World/Misc/BP_LoreItem.BP_LoreItem_C"
local BOOK_MESH = "/Game/Art/Env/Props/Gameplay_Props/Lore_Book/SM_Lore_Book_01.SM_Lore_Book_01"
local PREFERRED_TEMPLATE = "JOURNAL_Know_LoreScrap_C4"

local SPAWN_RANGE = 15000
local READ_RANGE = 300
local TARGET_GRACE = 0.6
local OPEN_WAIT_MS = 450
local FALLBACK_SECONDS = 3.0

local cfg = nil
local place = nil
local groundZ = nil
local book = nil
local bookMode = nil
local bookFor = nil
local spawnFailures = 0
local lastTargeted = -1
local lastSignal = -1
local promptNamed = {}
local entryProp = nil
local entryPropChecked = false
local clone = nil
local cloneSeq = 0
local session = nil
local hooked = false

local function now() return os.clock() end

-- Book state -------------------------------------------------------------

local function in_world()
    return U.pc() ~= nil and cfg.ESL.Character() ~= nil
end

local function can_decipher()
    if cfg.devUnlock then return true end
    return (cfg.ESL.MeetsRequirements({ { skill = cfg.ESL.HISTORIAN, level = 25 } }))
end

local function texts(ready)
    if ready then return Lore.TITLE, Lore.BODY end
    return Lore.PROMPT_NAME, Lore.LOCKED_BODY
end

-- The local player's JournalComponent, matched the way Historian matches it.
local function local_journal()
    local pc = U.pc()
    if not pc then return nil end
    local name = nil
    pcall(function() name = pc.PlayerState.PlayerNamePrivate:ToString() end)
    if not name or name ~= cfg.ESL.Character() then return nil end
    local prefix = U.full(pc):match("^%S+%s+(.+)$")
    if not prefix then return nil end
    for _, comp in ipairs(FindAllOf("JournalComponent") or {}) do
        if U.full(comp):find(prefix, 1, true) then return comp end
    end
    return nil
end

local function page_count(entry)
    local ok, n = pcall(function() return entry.PageDescriptions:GetArrayNum() end)
    return ok and n or nil
end

-- A lore entry the character already owns, used as the shape of our page.
-- Owned entries only, so nothing new can ever be filed in the journal.
local function template_entry()
    local comp = local_journal()
    if not U.valid(comp) then return nil end
    local best, fallback = nil, nil
    pcall(function()
        comp.UnlockedJournalEntries:ForEach(function(_, e)
            local obj = e:get()
            if not U.valid(obj) then return end
            local name = U.fname(obj)
            local cls = U.fname(obj:GetClass())
            if name == PREFERRED_TEMPLATE then best = obj end
            if not fallback and cls:find("KnowLore", 1, true) and page_count(obj) == 1 then fallback = obj end
        end)
    end)
    return best or fallback
end

-- Name of the text field inside JournalPageDescription, found by reflection.
local pageField = nil
local function page_text_field(entry)
    if pageField then return pageField end
    for _, p in ipairs(U.properties(entry:GetClass())) do
        if p.name == "PageDescriptions" then
            pcall(function()
                local struct = p.prop:GetInner():GetStruct()
                struct:ForEachProperty(function(f)
                    if not pageField and U.prop_type(f) == "TextProperty" then pageField = U.prop_name(f) end
                end)
            end)
            break
        end
    end
    if pageField then U.log("Journal page text field: " .. pageField) end
    return pageField
end

-- A transient copy of an owned entry carrying our title and text. It is not
-- registered with the journal, so the game cannot file or save it.
local function make_entry(template, title, body)
    if not U.valid(template) then return nil end
    local gi = UEHelpers.GetGameInstance()
    if not U.valid(gi) then return nil end
    cloneSeq = cloneSeq + 1
    local ok, e = pcall(StaticConstructObject, template:GetClass(), gi,
        FName("SoAHorticultureBook" .. cloneSeq), 0, 0, false, false, template)
    if not ok or not U.valid(e) then
        U.log_once("clone", "Could not copy a journal entry for the book page (" .. tostring(e) .. "); the popup text is replaced on screen instead")
        return nil
    end
    local okTitle = pcall(function() e.DisplayName = FText(title) end)
    local field = page_text_field(e)
    local okBody = false
    if field then
        okBody = pcall(function()
            e.PageDescriptions:ForEach(function(i, elem)
                elem:get()[field] = FText(i == 1 and body or "")
            end)
        end)
    end
    U.log_once("cloneok", string.format("Book page entry built from %s (title set %s, text set %s)", U.fname(template), tostring(okTitle), tostring(okBody)))
    return e
end

-- Placement and spawning -------------------------------------------------

local function trace_ground(x, y, nearZ)
    local ksl = UEHelpers.GetKismetSystemLibrary()
    local pawn = U.pawn()
    if not (U.valid(ksl) and pawn) then return nil end
    local hit = {}
    local color = { R = 0, G = 0, B = 0, A = 0 }
    local ok, wasHit = pcall(function()
        return ksl:LineTraceSingle(pawn, { X = x, Y = y, Z = nearZ + 5000 }, { X = x, Y = y, Z = nearZ - 5000 },
            0, false, {}, 0, hit, true, color, color, 0.0)
    end)
    if not (ok and wasHit) then return nil end
    local z = nil
    pcall(function() z = hit.ImpactPoint.Z end)
    if not z then pcall(function() z = hit.Location.Z end) end
    return z
end

local function spot()
    local p = place
    local z = p.z or groundZ
    if not z then
        local me = U.location(U.pawn())
        if not me then return nil end
        groundZ = trace_ground(p.x, p.y, me.Z)
        if not groundZ then return nil end
        U.log(string.format("Book ground found at z %.0f by line trace", groundZ))
        z = groundZ
    end
    return { X = p.x, Y = p.y, Z = z + 2 }, { Pitch = 0, Yaw = p.yaw or 0, Roll = 0 }
end

local function load_object(path)
    local obj = StaticFindObject(path)
    if U.valid(obj) then return obj end
    local ok, loaded = pcall(LoadAsset, path)
    if ok and U.valid(loaded) then return loaded end
    return nil
end

local function find_entry_property(actor)
    if entryPropChecked then return entryProp end
    entryPropChecked = true
    for _, p in ipairs(U.properties(actor:GetClass())) do
        if p.type == "ObjectProperty" then
            local inner = ""
            pcall(function() inner = U.fname(p.prop:GetPropertyClass()) end)
            if inner:find("Journal", 1, true) then
                entryProp = p.name
                U.log("BP_LoreItem names its entry in " .. p.name .. " (" .. inner .. ")")
                return entryProp
            end
        end
    end
    U.log("BP_LoreItem has no journal entry object property; the popup is opened by the mod")
    return nil
end

local function configure(actor)
    pcall(function() actor.bSkipSpudStore = true end)
    local skip = nil
    pcall(function() skip = actor.bSkipSpudStore end)
    U.log_once("spud", "Book bSkipSpudStore = " .. tostring(skip))
    pcall(function()
        if actor:HasAuthority() then actor:SetReplicates(false) end
    end)
    if bookMode == "loreitem" then
        local prop = find_entry_property(actor)
        local template = prop and template_entry()
        if prop and template then
            local ok = pcall(function() actor[prop] = template end)
            U.log_once("entryset", "Book entry set to owned " .. U.fname(template) .. ": " .. tostring(ok))
        end
    end
end

local function adopt_existing(loc)
    for _, a in ipairs(U.live_of("BP_LoreItem_C")) do
        if U.dist2d(U.location(a), loc) < 150 then return a end
    end
    return nil
end

local function spawn_mesh(world, loc, rot)
    local cls = load_object("/Script/Engine.StaticMeshActor")
    local mesh = load_object(BOOK_MESH)
    if not (cls and mesh) then return nil end
    local actor = world:SpawnActor(cls, loc, rot)
    if not U.valid(actor) then return nil end
    pcall(function()
        local comp = actor.StaticMeshComponent
        comp:SetMobility(2)
        comp:SetStaticMesh(mesh)
    end)
    return actor
end

local function spawn_book()
    local loc, rot = spot()
    if not loc then return end
    local existing = adopt_existing(loc)
    if existing then
        book, bookMode = existing, "loreitem"
        configure(existing)
        U.log("Book already in the world here; using it")
        return
    end
    local world = UEHelpers.GetWorld()
    if not U.valid(world) then return end
    local actor = nil
    if not cfg.forceMesh then
        local cls = load_object(LORE_ITEM)
        if cls then
            local ok, a = pcall(function() return world:SpawnActor(cls, loc, rot) end)
            if ok and U.valid(a) then actor, bookMode = a, "loreitem" end
        end
        if not actor then U.log_once("noloreitem", "BP_LoreItem did not spawn; using the plain lore book model") end
    end
    if not actor then
        local ok, a = pcall(spawn_mesh, world, loc, rot)
        if ok and U.valid(a) then actor, bookMode = a, "mesh" end
    end
    if not actor then
        spawnFailures = spawnFailures + 1
        U.log_once("spawnfail", "The book could not be spawned")
        return
    end
    book = actor
    bookFor = cfg.ESL.Character()
    configure(actor)
    U.log(string.format("Book placed at %.0f, %.0f, %.0f (%s, %s)", loc.X, loc.Y, loc.Z, bookMode, place.source or "?"))
end

local function ensure_book()
    if not in_world() then
        book, groundZ, session = nil, nil, nil
        return
    end
    if U.valid(book) and bookFor == cfg.ESL.Character() then return end
    if spawnFailures >= 5 then return end
    local me = U.location(U.pawn())
    if not me then return end
    if U.dist2d(me, { X = place.x, Y = place.y }) > SPAWN_RANGE then return end
    book = nil
    spawn_book()
end

-- Prompt and interaction -------------------------------------------------

local function is_book(actor)
    return U.valid(book) and U.valid(actor) and U.full(actor) == U.full(book)
end

local function watch_prompt()
    if not U.valid(book) then return end
    for _, prompt in ipairs(U.live_of("WBP_HUD_InteractionPrompt_C")) do
        local target = nil
        pcall(function() target = prompt.CurrentWorldActor end)
        if is_book(target) then
            lastTargeted = now()
            local nameBlock = nil
            pcall(function() nameBlock = prompt.ItemNameTextBlock end)
            if U.valid(nameBlock) and U.text(nameBlock) ~= Lore.PROMPT_NAME then
                local was = U.text(nameBlock)
                U.set_text(nameBlock, Lore.PROMPT_NAME)
                if not promptNamed[tostring(was)] then
                    promptNamed[tostring(was)] = true
                    U.log("Book prompt renamed from \"" .. tostring(was) .. "\"")
                end
            end
        end
    end
end

local function near_book()
    if not U.valid(book) then return false end
    return U.dist(U.location(U.pawn()), U.location(book)) <= READ_RANGE
end

local function find_popup()
    for _, w in ipairs(U.live_of("WBP_LorePopupMainPanel_C")) do
        if U.visible(w) then return w end
    end
    return nil
end

-- The popup's title widgets: text widgets inside the lore popup showing the
-- entry's title, or named like a title.
local function title_widgets(oldTitle)
    local out = {}
    for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
        for _, t in ipairs(U.live_of(cls)) do
            local f = U.full(t)
            if (f:find("WBP_LorePopupMainPanel_C", 1, true) or f:find("WBP_Panel_LorePopup_C", 1, true))
                and not f:find("RichTextDescription", 1, true) and U.visible(t) then
                local s = U.text(t)
                local n = U.fname(t):lower()
                if s and s ~= "" and ((oldTitle and s == oldTitle) or n:find("title", 1, true) or n:find("header", 1, true)) then
                    out[#out + 1] = t
                    U.log_once("title" .. n, "Popup title widget: " .. U.fname(t) .. " (\"" .. s .. "\")")
                end
            end
        end
    end
    return out
end

-- Keeps our title and text on the popup. The body is the panel's
-- RichTextDescription (ULorePopupMainPanel).
local function overwrite(panel, s)
    local desc = nil
    pcall(function() desc = panel.RichTextDescription end)
    if U.valid(desc) and U.text(desc) ~= s.body then U.set_text(desc, s.body) end
    if not s.titles or (#s.titles == 0 and now() - s.shownAt < 1.0) then
        s.titles = title_widgets(s.oldTitle)
    end
    for _, t in ipairs(s.titles) do
        if U.valid(t) and U.text(t) ~= s.title then U.set_text(t, s.title) end
    end
end

local function lore_api()
    return U.live_of("LorePopupUIAPI")[1]
end

local function arg_for(prop, entry)
    local t = U.prop_type(prop)
    if t == "ObjectProperty" then
        local inner = ""
        pcall(function() inner = U.fname(prop:GetPropertyClass()) end)
        if inner:find("Journal", 1, true) then return entry end
        if inner:find("Character", 1, true) or inner:find("Pawn", 1, true) or inner:find("Actor", 1, true) then return U.pawn() end
        return CreateInvalidObject and CreateInvalidObject() or nil
    elseif t == "BoolProperty" then return false
    elseif t == "TextProperty" then return FText("")
    elseif t == "StrProperty" then return ""
    elseif t == "NameProperty" then return FName("None")
    elseif t:find("Int", 1, true) or t:find("Float", 1, true) or t:find("Double", 1, true) or t == "ByteProperty" or t == "EnumProperty" then return 0
    end
    return {}
end

-- Opens the game's lore popup on a journal entry through LorePopupUIAPI.
local function open_via_api(entry)
    local api = lore_api()
    if not api then return false, "no LorePopupUIAPI instance" end
    local fn = U.find_function(api, "OpenLorePopup")
    if not fn then return false, "OpenLorePopup not found" end
    local args, n, sig = {}, 0, {}
    pcall(function()
        fn:ForEachProperty(function(p)
            local name = U.prop_name(p)
            sig[#sig + 1] = name .. ":" .. U.prop_type(p)
            if name ~= "ReturnValue" then
                n = n + 1
                args[n] = arg_for(p, entry)
            end
        end)
    end)
    U.log_once("opensig", "OpenLorePopup(" .. table.concat(sig, ", ") .. ") on " .. U.full(api))
    local ok, err = pcall(function() api:OpenLorePopup(table.unpack(args, 1, n)) end)
    return ok, err
end

local function finish(ready)
    local ESL, SKILL = cfg.ESL, cfg.SKILL
    if ready then
        if ESL.ReadBook(SKILL, cfg.BOOK_ID) then
            U.log("Observances of Brassica Prime read by " .. tostring(ESL.Character()))
            if ExecuteWithDelay then
                ExecuteWithDelay(6000, function()
                    if not ESL.IsUnlocked(SKILL) then
                        ESL.Gate(SKILL, { notify = true, title = "Horticulture", skill = SKILL })
                    end
                end)
            end
        end
    else
        ESL.Gate({ { skill = ESL.HISTORIAN, level = 25 } }, { notify = true, title = Lore.PROMPT_NAME, skill = ESL.HISTORIAN })
    end
end

-- One reading: wait for the native popup our book may open; otherwise open
-- it ourselves. Then keep our text on it while it stays up.
local function read(fromWorld)
    if session and now() - session.started < 1.0 then return end
    local ready = can_decipher()
    local title, body = texts(ready)
    session = { started = now(), ready = ready, title = title, body = body, panel = nil, finished = false, opened = false }
    local s = session
    local function try_api()
        if s ~= session or s.panel then return end
        local template = template_entry()
        if not U.valid(clone) or s.cloneTitle ~= title then
            clone = make_entry(template, title, body)
            s.cloneTitle = title
        end
        local entry = U.valid(clone) and clone or template
        if not U.valid(entry) then
            U.log("No owned lore entry to shape the popup with; read a journal page first")
            return
        end
        s.oldTitle = nil
        pcall(function() s.oldTitle = entry.DisplayName:ToString() end)
        local ok, err = open_via_api(entry)
        s.opened = ok
        if not ok then U.log("The lore popup could not be opened: " .. tostring(err)) end
    end
    if fromWorld and bookMode == "loreitem" and ExecuteWithDelay then
        ExecuteWithDelay(OPEN_WAIT_MS, function() U.game(try_api) end)
    else
        U.game(try_api)
    end
end

local function pump_session()
    local s = session
    if not s then return end
    local age = now() - s.started
    local panel = find_popup()
    if panel then
        if not s.panel then
            s.panel = U.full(panel)
            s.shownAt = now()
            if not s.oldTitle then
                pcall(function() s.oldTitle = lore_api().CurrentEntry.DisplayName:ToString() end)
            end
        end
        if U.full(panel) == s.panel then
            overwrite(panel, s)
            if not s.finished then
                s.finished = true
                finish(s.ready)
            end
        end
    elseif s.panel then
        session = nil
    elseif age > FALLBACK_SECONDS then
        U.log("No lore popup appeared; showing the Observances on the mod's own page")
        if Page.Show(s.title, s.body) and not s.finished then
            s.finished = true
            finish(s.ready)
        end
        session = nil
    end
end

local function signal(source)
    if not in_world() or not U.valid(book) then return end
    if now() - lastSignal < 0.4 then return end
    local aimed = now() - lastTargeted <= TARGET_GRACE
    if not aimed and not (bookMode == "mesh" and near_book()) then return end
    lastSignal = now()
    U.log_once("signal" .. source, "Book interaction seen through " .. source)
    read(true)
end

local function hook_interaction()
    if hooked or not RegisterHook then return end
    local pc, pawn = U.pc(), U.pawn()
    if not (pc and pawn) then return end
    local owners = { pc, pawn }
    local compClass = StaticFindObject("/Script/Engine.ActorComponent")
    for _, actor in ipairs({ pc, pawn }) do
        pcall(function()
            actor:K2_GetComponentsByClass(compClass):ForEach(function(_, c) owners[#owners + 1] = c:get() end)
        end)
    end
    for _, obj in ipairs(owners) do
        local fn, path = U.find_function(obj, "Server_RequestInteraction")
        if fn then
            hooked = true
            local function mine(ctx)
                local ok, yes = pcall(function()
                    local c = ctx:get()
                    local owner = c.GetOwner and c:GetOwner() or c
                    local me = U.pawn()
                    return U.full(c) == U.full(me) or U.full(owner) == U.full(me) or U.full(owner) == U.full(U.pc())
                end)
                return ok and yes
            end
            local okHook = pcall(RegisterHook, path .. ":Server_RequestInteraction", function(ctx, secondary, release)
                local rel = false
                pcall(function() rel = release:get() end)
                if not rel and mine(ctx) then signal("interaction request") end
            end)
            for _, name in ipairs({ "Multicast_AcknowledgeInteractionRequest", "Client_DeniedInteraction" }) do
                if U.valid(StaticFindObject(path .. ":" .. name)) then
                    pcall(RegisterHook, path .. ":" .. name, function(ctx)
                        if mine(ctx) then signal(name) end
                    end)
                end
            end
            U.log("Interaction hooks on " .. path .. ": " .. tostring(okHook))
            return
        end
    end
end

-- Public -----------------------------------------------------------------

function Book.Start(config)
    cfg = config
    place = Placement.Load(cfg.dir)
    U.log(string.format("Brassica Prime book: %s at %.0f, %.0f%s. It appears within %d m.",
        place.source or "?", place.x, place.y, place.z and string.format(", %.0f", place.z) or "", SPAWN_RANGE // 100))
    U.every(1000, "Book check", function() U.game(ensure_book) end)
    U.every(100, "Book prompt", function() U.game(watch_prompt) end)
    U.every(60, "Book popup", function()
        if session then U.game(pump_session) end
    end)
    U.every(3000, "Interaction hook", function()
        if not hooked and in_world() then U.game(hook_interaction) end
    end)
    RegisterKeyBindAsync(Key.E, {}, function() signal("E key") end)
end

-- Opens the book from anywhere once it has been read.
function Book.Reread()
    if not in_world() then return end
    if not cfg.ESL.HasReadBook(cfg.SKILL, cfg.BOOK_ID) then
        U.log("Find and read the Annotated Hymnal first")
        return
    end
    read(false)
end

-- Developer helpers ------------------------------------------------------

function Book.Actor() return book, bookMode end
function Book.Place() return place end

function Book.SetPlace(p)
    place = p
    groundZ = nil
    if U.valid(book) then pcall(function() book:K2_DestroyActor() end) end
    book = nil
    spawnFailures = 0
end

function Book.OpenNow()
    read(false)
end

function Book.Template()
    return template_entry()
end

return Book

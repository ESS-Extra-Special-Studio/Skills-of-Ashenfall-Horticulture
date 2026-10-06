-- Hybrid names on the game's own prompt. A tree's prompt name is its
-- WorldActor.DisplayName ("Ash Tree"), a per-actor property, so a hybrid's
-- tree is renamed once ("Tuberwood Ash") and checked again only when its
-- look is refreshed. Streaming makes a fresh actor with the game's name,
-- which is renamed the same way. Should the game keep writing its own name
-- back, renaming stops after a few tries and the name tag carries the name.
-- Actors are keyed by full name; no engine object is kept.
local Names = {}

Names.MAX_WRITES = 5

local named = {}

local function read(actor)
    local s = nil
    pcall(function() s = actor.DisplayName:ToString() end)
    return s
end

-- Gives actor the name; true when the game's prompt will show it.
function Names.Set(U, actor, name)
    if not U.valid(actor) then return false end
    local cur = read(actor)
    if cur == nil then return false end
    if cur == name then return true end
    local key = U.full(actor)
    local e = named[key]
    if e and e.writes >= Names.MAX_WRITES then return false end
    if not e then
        e = { original = cur, writes = 0 }
        named[key] = e
    end
    e.writes = e.writes + 1
    pcall(function() actor.DisplayName = FText(name) end)
    local now = read(actor)
    if e.writes == 1 then
        U.log(string.format("Prompt name of %s: \"%s\" -> \"%s\"", U.fname(actor), cur, tostring(now)))
    elseif e.writes >= Names.MAX_WRITES then
        U.log("The game keeps renaming " .. U.fname(actor) .. "; its hybrid name is left to the name tag")
    end
    return now == name
end

-- True when the actor already carries the name.
function Names.Has(U, actor, name)
    return U.valid(actor) and read(actor) == name
end

-- Puts the game's own name back (the hybrid has ended).
function Names.Restore(U, actor)
    if not U.valid(actor) then return end
    local key = U.full(actor)
    local e = named[key]
    if not e then return end
    named[key] = nil
    pcall(function() actor.DisplayName = FText(e.original) end)
end

return Names

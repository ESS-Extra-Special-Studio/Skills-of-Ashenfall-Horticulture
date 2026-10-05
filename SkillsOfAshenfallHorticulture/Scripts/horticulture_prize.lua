-- Prize specimens: a crop the player fed and watered on every growing day
-- stands a size larger on their own screen once it is ready to harvest.
-- Cosmetic and local: only the plant mesh's relative scale changes. Nothing
-- is saved, replicated or given to the player.
--
-- Verified in build 25632050 (exe reflection names): PlantMeshComponent and
-- PlantMeshComponentRef among the farm plot's properties. Not verified: which
-- object holds the component, and whether the game resets its scale; the
-- scale is re-applied on every check. Off until the in-game spike shows it
-- works (docs/HORTICULTURE_TEST_WINDOW.md, step S6).
local U = require("horticulture_util")

local Prize = {}

Prize.ENABLED = false
Prize.SCALE = 1.2

local marked = {}

function Prize.Mesh(slotObj)
    local comp = nil
    pcall(function() comp = slotObj.PlantMeshComponent end)
    if U.valid(comp) then return comp end
    pcall(function() comp = slotObj:GetOwner().PlantMeshComponent end)
    if U.valid(comp) then return comp end
    return nil
end

local function scale_of(comp)
    local ok, s = pcall(function()
        local v = comp.RelativeScale3D
        return { X = v.X, Y = v.Y, Z = v.Z }
    end)
    return ok and s or nil
end

local function set_scale(comp, s)
    return (pcall(function() comp:SetRelativeScale3D(s) end))
end

-- Scales the slot's plant up, or restores it. Returns the mesh component.
function Prize.Set(slot, on)
    local comp = Prize.Mesh(slot.obj)
    if not comp then return nil end
    local m = marked[slot.key]
    if on then
        if not m or m.comp ~= comp then
            local base = scale_of(comp)
            if not base then return nil end
            m = { comp = comp, base = base }
            marked[slot.key] = m
        end
        local b = m.base
        local want = { X = b.X * Prize.SCALE, Y = b.Y * Prize.SCALE, Z = b.Z * Prize.SCALE }
        local cur = scale_of(comp)
        if not cur or math.abs(cur.Z - want.Z) > 0.001 then set_scale(comp, want) end
    elseif m then
        if U.valid(m.comp) then set_scale(m.comp, m.base) end
        marked[slot.key] = nil
    end
    return comp
end

function Prize.Apply(slot)
    if Prize.ENABLED then Prize.Set(slot, true) end
end

function Prize.Clear(slot)
    Prize.Set(slot, false)
end

return Prize

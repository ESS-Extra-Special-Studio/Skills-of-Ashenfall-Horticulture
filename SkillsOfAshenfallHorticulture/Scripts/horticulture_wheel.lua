-- Horticulture on the Action Wheel (optional companion mod). Without
-- ActionWheel installed, Start returns false and nothing changes: G, Alt+G
-- and Shift+G work the same either way.
--
-- Slices are worked out by View from Splicing.WheelContext(), which reads
-- the plant under the crosshair exactly as the keys do (the wheel holds the
-- camera still while it is open), and each slice runs a Splicing entry
-- point that applies the same rules as its key.
local Core = require("horticulture_splice_core")
local Rules = require("horticulture_splice_rules")
local Primelet = require("horticulture_primelet")

local Wheel = {}

local function level_locked(why)
    if type(why) ~= "string" then return false end
    return why:find("Horticulture %d+") ~= nil or why:find("^Needs %a+ %d+") ~= nil
end

Wheel.LevelLocked = level_locked

local function slice(ok, why, label)
    return { enabled = ok == true, reason = not ok and why or nil, locked = not ok and level_locked(why) or nil, label = label }
end

-- ctx: { blocked, locked, inWorld, st, level, primelet, aimed, src, host, graft }.
-- Returns action id -> { enabled, reason, locked, label, children }; an id
-- that is missing is hidden.
function Wheel.View(ctx)
    local v = {}
    if ctx.blocked then
        v.take_cutting = { enabled = false, reason = ctx.blocked, locked = ctx.locked }
        -- Locked, the status key shows what is still needed.
        v.status = slice(ctx.inWorld ~= false, ctx.blocked)
        return v
    end
    local st = ctx.st
    v.status = { enabled = true }
    local sel = Core.Selected(st)
    local carrying = sel and sel.primelet and sel or nil
    if carrying then
        local p = Primelet.Find(st, carrying.primelet)
        v.set_down = { enabled = true, label = "Set down " .. (p and Primelet.Name(p) or "Primelet") }
    end
    local p = ctx.primelet
    if p then
        local name = Primelet.Name(p)
        if p.tended == st.dawn and Primelet.Grown(p) then
            v.tend = { enabled = true, label = "Talk to " .. name }
        else
            v.tend = slice(p.tended ~= st.dawn, "Already tended today. Again after dawn", "Tend " .. name)
        end
        v.pick_up = slice(#st.cuttings < Rules.SATCHEL_SIZE,
            string.format("Your satchel is full (%d). Graft a cutting first", Rules.SATCHEL_SIZE), "Pick up " .. name)
    end
    if #st.cuttings > 1 then v.next_cutting = { enabled = true } end

    local g = ctx.graft
    if g then v.inspect = { enabled = true } end
    if g and g.state == "hybrid" and g.kind ~= "plot" and not carrying then
        local ok, why = Core.CanPick(st, g)
        local label = "Pick " .. Rules.HybridName(g.scion, g.host)
        if Rules.UsesVigour(g) and (g.vigour or 0) > 0 then label = string.format("%s (%d left)", label, g.vigour) end
        v.pick = slice(ok, why, label)
    end

    local host = ctx.host
    if host and not carrying and (host.kind == "plot" or (ctx.aimed and ctx.aimed.planted)) then
        local kids, firstWhy, allSame, any = {}, nil, true, false
        for i, c in ipairs(st.cuttings) do
            if not c.primelet then
                local ok, why = Core.CanGraft(st, host, ctx.level, c)
                local kid = slice(ok, why, Rules.Name(c.species) .. " cutting")
                kid.value = i
                kids[#kids + 1] = kid
                any = any or ok
                if not ok then
                    if firstWhy == nil then firstWhy = why elseif why ~= firstWhy then allSame = false end
                end
            end
        end
        if #kids > 0 then
            if not any and allSame then
                v.graft = slice(false, firstWhy)
            else
                v.graft = { enabled = true, children = kids }
            end
        end
    end

    if ctx.src then
        local ok, why = Core.CanTakeCutting(st, ctx.src)
        v.take_cutting = slice(ok, why)
    elseif ctx.aimed and ctx.aimed.kind == "stump" then
        v.take_cutting = slice(false, "Nothing grows from a stump")
    elseif not ctx.aimed then
        v.take_cutting = slice(false, "Aim at a crop, sapling or tree within reach")
    end
    return v
end

-- The registration, separate from Start so it can be tested offline.
-- view() returns the current View; S is horticulture_splicing.
function Wheel.Definition(S, view, status)
    local function check(id)
        return function()
            local s = view()[id]
            if not s then return nil end
            return { enabled = s.enabled, reason = s.reason, locked = s.locked, label = s.label }
        end
    end
    return {
        id = "Horticulture", name = "Horticulture", mod = "Skills of Ashenfall: Horticulture",
        target_name = function(target) return S.TargetName and S.TargetName(target) or nil end,
        actions = {
            { id = "pick", label = "Pick hybrid", kinds = { "tree", "sapling" }, order = 1, ask = true,
              hint = "Pick from a hybrid you grew (G)", check = check("pick"), run = function() S.WheelPick() end },
            { id = "graft", label = "Graft", kinds = { "plot", "crop", "sapling", "tree" }, order = 2, ask = true,
              hint = "Graft a cutting from your satchel onto a plant you grew (G)", check = check("graft"),
              children = function()
                  local s = view().graft
                  local out = {}
                  for _, k in ipairs(s and s.children or {}) do
                      out[#out + 1] = { label = k.label, value = k.value, enabled = k.enabled, reason = k.reason, locked = k.locked }
                  end
                  return out
              end,
              run = function(_, choice)
                  if choice and choice.value then S.WheelGraft(choice.value) end
              end },
            { id = "take_cutting", label = "Take cutting", kinds = { "plot", "crop", "sapling", "tree" }, order = 3, ask = true,
              hint = "Take a cutting for your satchel (Alt+G)", check = check("take_cutting"), run = function() S.WheelTakeCutting() end },
            { id = "inspect", label = "Check graft", kinds = { "plot", "crop", "sapling", "tree" }, order = 4, ask = true,
              hint = "How the graft on this plant is doing", check = check("inspect"), run = function() S.InspectGraft() end },
            { id = "tend", label = "Tend Primelet", kinds = { "all" }, order = 5, ask = true,
              hint = "Once a day (E or G beside it)", check = check("tend"), run = function() S.TendPrimelet() end },
            { id = "pick_up", label = "Pick up Primelet", kinds = { "all" }, order = 6, ask = true,
              hint = "Into your satchel (Alt+G beside it)", check = check("pick_up"), run = function() S.PickUpPrimelet() end },
            { id = "set_down", label = "Set down Primelet", kinds = { "all" }, order = 7, ask = true,
              hint = "On open ground in front of you (G)", check = check("set_down"), run = function() S.SetDownPrimelet() end },
            { id = "next_cutting", label = "Next cutting", kinds = { "self" }, order = 8, ask = true,
              hint = "Select the next thing in your satchel (Shift+G)", check = check("next_cutting"), run = function() S.Cycle() end },
            { id = "status", label = "Horticulture", kinds = { "self" }, order = 9, ask = true,
              hint = "Satchel, Primelet and Discovery Catalogue", check = check("status"),
              run = function() if status then status() end end },
        },
    }
end

-- Registers with the wheel when it is installed: the client in ESL, or the
-- standalone ActionWheel mod. status: the function the status key runs.
-- Returns true when registered.
function Wheel.Start(S, dir, status)
    package.path = dir .. "\\..\\..\\ESLDragonWilds\\Scripts\\?.lua;" .. dir .. "\\..\\..\\ActionWheel\\Scripts\\?.lua;" .. package.path
    local okAW, AW = pcall(require, "actionwheel")
    if not okAW or type(AW) ~= "table" or type(AW.Register) ~= "function" then return false end
    -- With the wheel naming its targets, our own name tag stands down.
    if type(AW.ShowsTargetName) == "function" then
        S.wheelNames = function()
            local ok, on = pcall(AW.ShowsTargetName)
            return ok and on == true
        end
    end
    -- One context per wheel opening: every check of one query runs together.
    local cached, at = nil, -1
    local function view()
        local now = os.clock()
        if not cached or now - at > 0.25 then
            local ok, ctx = pcall(S.WheelContext)
            cached, at = Wheel.View(ok and ctx or { blocked = "Horticulture is not ready" }), now
        end
        return cached
    end
    return AW.Register(Wheel.Definition(S, view, status)) == true
end

return Wheel

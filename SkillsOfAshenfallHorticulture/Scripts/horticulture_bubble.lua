-- Speech bubbles above the Mini Brassica Primes: our own widget, placed each
-- tick at the Mini's head projected to the screen. Two at most (an exchange
-- between two Minis). Show returns false when a bubble cannot be drawn, and
-- the caller falls back to the name tag.
local UEHelpers = require("UEHelpers")

local Bubble = {}

local INK = { R = 0.97, G = 0.95, B = 0.88, A = 0.94 }
local TEXT = { R = 0.10, G = 0.09, B = 0.07, A = 1.0 }
local NAME = { R = 0.28, G = 0.45, B = 0.16, A = 1.0 }
local HIDDEN, HIT_TEST_INVISIBLE = 2, 3
local SLOTS = 2

Bubble.wrap = 380
Bubble.size = 16

local slots = {}
local broken = false

local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

local function build(i)
    local s = slots[i]
    if s and valid(s.root) and valid(s.text) then return s end
    s = { visible = false }
    local ok = pcall(function()
        local gi = UEHelpers.GetGameInstance()
        local userWidget = StaticFindObject("/Script/UMG.UserWidget")
        local treeClass = StaticFindObject("/Script/UMG.WidgetTree")
        local canvasClass = StaticFindObject("/Script/UMG.CanvasPanel")
        local borderClass = StaticFindObject("/Script/UMG.Border")
        local boxClass = StaticFindObject("/Script/UMG.VerticalBox")
        local textClass = StaticFindObject("/Script/UMG.TextBlock")
        if not (valid(gi) and valid(userWidget) and valid(treeClass) and valid(canvasClass) and valid(borderClass)
            and valid(boxClass) and valid(textClass)) then return end
        local tag = "HorticultureBubble" .. i
        local w = StaticConstructObject(userWidget, gi, FName(tag))
        w.WidgetTree = StaticConstructObject(treeClass, w, FName(tag .. "Tree"))
        local canvas = StaticConstructObject(canvasClass, w.WidgetTree, FName(tag .. "Canvas"))
        w.WidgetTree.RootWidget = canvas
        local border = StaticConstructObject(borderClass, canvas, FName(tag .. "Border"))
        border:SetBrushColor(INK)
        border:SetPadding({ Left = 12, Top = 6, Right = 12, Bottom = 8 })
        local box = StaticConstructObject(boxClass, border, FName(tag .. "Box"))
        local name = StaticConstructObject(textClass, box, FName(tag .. "Name"))
        local text = StaticConstructObject(textClass, box, FName(tag .. "Text"))
        pcall(function()
            name.Font.Size = Bubble.size - 3
            name:SetColorAndOpacity({ SpecifiedColor = NAME, ColorUseRule = 0 })
        end)
        pcall(function()
            text.Font.Size = Bubble.size
            text:SetColorAndOpacity({ SpecifiedColor = TEXT, ColorUseRule = 0 })
        end)
        pcall(function() text:SetAutoWrapText(false) end)
        pcall(function() text.WrapTextAt = Bubble.wrap end)
        pcall(function() text:SetWrapTextAt(Bubble.wrap) end)
        box:AddChildToVerticalBox(name)
        box:AddChildToVerticalBox(text)
        border:SetContent(box)
        local slot = canvas:AddChildToCanvas(border)
        slot:SetAutoSize(true)
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
        slot:SetAlignment({ X = 0.5, Y = 1.0 })
        w:AddToViewport(29)
        w:SetVisibility(HIDDEN)
        s.root, s.name, s.text, s.slot = w, name, text, slot
    end)
    if not (ok and valid(s.root)) then return nil end
    slots[i] = s
    return s
end

-- World location to viewport units, or nil when off screen.
local function project(loc)
    local pc = UEHelpers.GetPlayerController()
    if not valid(pc) then return nil end
    local out, done = {}, false
    pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        if valid(wll) then done = wll:ProjectWorldLocationToWidgetPosition(pc, loc, out, false) end
    end)
    if done and out.X then return out.X, out.Y end
    out, done = {}, false
    pcall(function() done = pc:ProjectWorldLocationToScreen(loc, out, false) end)
    if not (done and out.X) then return nil end
    local scale = 1
    pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        scale = wll:GetViewportScale(UEHelpers.GetWorld())
    end)
    if not scale or scale <= 0 then scale = 1 end
    return out.X / scale, out.Y / scale
end

local function hide(s)
    if s and s.visible and valid(s.root) then pcall(function() s.root:SetVisibility(HIDDEN) end) end
    if s then s.visible = false end
end

-- Shows name and text above loc (a function returning the world location of
-- the Mini's head) for secs. Returns false if no bubble could be drawn.
function Bubble.Show(name, text, loc, secs, now)
    if broken then return false end
    local free, oldest = nil, nil
    for i = 1, SLOTS do
        local s = slots[i]
        if not (s and s.untilT and s.untilT > now) then free = free or i end
        if not oldest or (slots[i] and slots[oldest] and (slots[i].untilT or 0) < (slots[oldest].untilT or 0)) then oldest = i end
    end
    local i = free or oldest or 1
    local s = build(i)
    if not s then broken = true return false end
    pcall(function() s.name:SetText(FText(name or "")) end)
    pcall(function() s.text:SetText(FText(text or "")) end)
    -- Off screen, it appears when the player turns towards the Mini.
    s.loc, s.untilT = loc, now + secs
    Bubble.Tick(now)
    return true
end

-- Places visible bubbles; returns how many are on screen.
function Bubble.Tick(now)
    local n = 0
    for i = 1, SLOTS do
        local s = slots[i]
        if s and s.untilT then
            if s.untilT <= now or not valid(s.root) then
                hide(s)
                s.untilT = nil
            else
                local ok, wl = pcall(s.loc)
                local x, y = nil, nil
                if ok and wl then x, y = project(wl) end
                if x then
                    pcall(function() s.slot:SetPosition({ X = x, Y = y }) end)
                    if not s.visible then
                        local inView = true
                        pcall(function() inView = s.root:IsInViewport() end)
                        if not inView then pcall(function() s.root:AddToViewport(29) end) end
                        pcall(function() s.root:SetVisibility(HIT_TEST_INVISIBLE) end)
                        s.visible = true
                    end
                    n = n + 1
                else
                    hide(s)
                end
            end
        end
    end
    return n
end

-- True while a bubble is up or waits for Tick to hide it.
function Bubble.Active()
    for i = 1, SLOTS do
        if slots[i] and slots[i].untilT then return true end
    end
    return false
end

function Bubble.HideAll()
    for i = 1, SLOTS do
        hide(slots[i])
        if slots[i] then slots[i].untilT = nil end
    end
end

function Bubble.Broken() return broken end

return Bubble

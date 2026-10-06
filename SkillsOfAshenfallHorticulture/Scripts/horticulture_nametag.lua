-- A small name tag just above the game's interaction prompt, for names the
-- game's prompt cannot carry: a hybrid tree's own name over "Ash Tree", and
-- the Brassica Primelet, which has no prompt. Our own widget, so nothing of
-- the game's is rewritten; the text is set only when it changes.
local UEHelpers = require("UEHelpers")

local Tag = {}

local INK = { R = 0.03, G = 0.03, B = 0.035, A = 0.78 }
local LEAF = { R = 0.72, G = 0.90, B = 0.55, A = 1.0 }
local HIDDEN, HIT_TEST_INVISIBLE = 2, 3

-- From the screen centre, in viewport units: the tag's bottom-left corner,
-- just above the game's prompt name, which starts right of the crosshair.
Tag.offset = { X = 54, Y = -16 }
Tag.size = 18

local root, label = nil, nil
local shownText, visible = nil, false

local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

local function build()
    if valid(root) and valid(label) then return true end
    root, label, shownText, visible = nil, nil, nil, false
    local ok = pcall(function()
        local gi = UEHelpers.GetGameInstance()
        local userWidget = StaticFindObject("/Script/UMG.UserWidget")
        local treeClass = StaticFindObject("/Script/UMG.WidgetTree")
        local canvasClass = StaticFindObject("/Script/UMG.CanvasPanel")
        local borderClass = StaticFindObject("/Script/UMG.Border")
        local textClass = StaticFindObject("/Script/UMG.TextBlock")
        if not (valid(gi) and valid(userWidget) and valid(treeClass) and valid(canvasClass) and valid(borderClass) and valid(textClass)) then
            return
        end
        local w = StaticConstructObject(userWidget, gi, FName("HorticultureNameTag"))
        w.WidgetTree = StaticConstructObject(treeClass, w, FName("HorticultureNameTagTree"))
        local canvas = StaticConstructObject(canvasClass, w.WidgetTree, FName("HorticultureNameTagCanvas"))
        w.WidgetTree.RootWidget = canvas
        local border = StaticConstructObject(borderClass, canvas, FName("HorticultureNameTagBorder"))
        border:SetBrushColor(INK)
        border:SetPadding({ Left = 10, Top = 4, Right = 10, Bottom = 4 })
        local t = StaticConstructObject(textClass, border, FName("HorticultureNameTagText"))
        pcall(function()
            t.Font.Size = Tag.size
            t:SetColorAndOpacity({ SpecifiedColor = LEAF, ColorUseRule = 0 })
        end)
        border:SetContent(t)
        local slot = canvas:AddChildToCanvas(border)
        slot:SetAutoSize(true)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        slot:SetAlignment({ X = 0.0, Y = 1.0 })
        slot:SetPosition({ X = Tag.offset.X, Y = Tag.offset.Y })
        w:AddToViewport(30)
        w:SetVisibility(HIDDEN)
        root, label = w, t
    end)
    return ok and valid(root)
end

-- Shows text on the tag; nil hides it.
function Tag.Show(text)
    if text == nil then
        if visible and valid(root) then pcall(function() root:SetVisibility(HIDDEN) end) end
        visible = false
        return
    end
    if not build() then return end
    local inView = true
    pcall(function() inView = root:IsInViewport() end)
    if not inView then pcall(function() root:AddToViewport(30) end) end
    if text ~= shownText then
        pcall(function() label:SetText(FText(text)) end)
        shownText = text
    end
    if not visible then
        pcall(function() root:SetVisibility(HIT_TEST_INVISIBLE) end)
        visible = true
    end
end

function Tag.Text() return visible and shownText or nil end

-- Moves the tag; it is rebuilt at the new place on its next showing.
function Tag.SetOffset(x, y)
    Tag.offset = { X = x, Y = y }
    if valid(root) then pcall(function() root:RemoveFromParent() end) end
    root, label, shownText, visible = nil, nil, nil, false
end

return Tag

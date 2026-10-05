-- Last-resort reading panel, built from plain UMG widgets the way ESL's card
-- is. Used only when the game's lore popup cannot be opened, so the book can
-- always be read. Closes on Escape, after a minute, or when replaced.
local UEHelpers = require("UEHelpers")
local U = require("horticulture_util")

local Page = {}

local PARCHMENT = { R = 0.93, G = 0.89, B = 0.78, A = 1.0 }
local INK = { R = 0.06, G = 0.05, B = 0.04, A = 0.95 }
local GOLD = { R = 0.86, G = 0.72, B = 0.38, A = 1.0 }
local HIDDEN, SELF_HIT = 2, 4

local root, titleBlock, bodyBlock = nil, nil, nil
local gen = 0

local function build()
    if U.valid(root) then return true end
    local gi = UEHelpers.GetGameInstance()
    local cls = {}
    for _, n in ipairs({ "UserWidget", "WidgetTree", "CanvasPanel", "Border", "VerticalBox", "TextBlock", "SizeBox" }) do
        cls[n] = StaticFindObject("/Script/UMG." .. n)
        if not U.valid(cls[n]) then return false end
    end
    if not U.valid(gi) then return false end
    root = StaticConstructObject(cls.UserWidget, gi, FName("SoAHorticulturePage"))
    root.WidgetTree = StaticConstructObject(cls.WidgetTree, root, FName("SoAHorticulturePageTree"))
    local canvas = StaticConstructObject(cls.CanvasPanel, root.WidgetTree, FName("SoAHorticulturePageCanvas"))
    root.WidgetTree.RootWidget = canvas

    local size = StaticConstructObject(cls.SizeBox, canvas, FName("SoAHorticulturePageSize"))
    size:SetWidthOverride(760)
    local border = StaticConstructObject(cls.Border, size, FName("SoAHorticulturePageBorder"))
    border:SetBrushColor(INK)
    border:SetPadding({ Left = 36, Top = 28, Right = 36, Bottom = 28 })
    size:SetContent(border)
    local column = StaticConstructObject(cls.VerticalBox, border, FName("SoAHorticulturePageColumn"))
    border:SetContent(column)

    titleBlock = StaticConstructObject(cls.TextBlock, column, FName("SoAHorticulturePageTitle"))
    pcall(function()
        titleBlock.Font.Size = 28
        titleBlock:SetColorAndOpacity({ SpecifiedColor = GOLD, ColorUseRule = 0 })
    end)
    local titleSlot = column:AddChildToVerticalBox(titleBlock)
    pcall(function() titleSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 16 }) end)

    bodyBlock = StaticConstructObject(cls.TextBlock, column, FName("SoAHorticulturePageBody"))
    pcall(function()
        bodyBlock.Font.Size = 17
        bodyBlock:SetColorAndOpacity({ SpecifiedColor = PARCHMENT, ColorUseRule = 0 })
        bodyBlock:SetAutoWrapText(true)
    end)
    column:AddChildToVerticalBox(bodyBlock)

    local slot = canvas:AddChildToCanvas(size)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    slot:SetAlignment({ X = 0.5, Y = 0.5 })
    root:AddToViewport(90)
    root:SetVisibility(HIDDEN)
    return true
end

function Page.Show(title, body)
    if not build() then
        U.log("The fallback reading panel could not be built either")
        return false
    end
    U.set_text(titleBlock, title)
    U.set_text(bodyBlock, body:gsub("\r\n", "\n"))
    pcall(function() root:SetVisibility(SELF_HIT) end)
    gen = gen + 1
    local mine = gen
    if ExecuteWithDelay then
        ExecuteWithDelay(60000, function()
            if mine == gen then U.game(Page.Hide) end
        end)
    end
    return true
end

function Page.Hide()
    if U.valid(root) then pcall(function() root:SetVisibility(HIDDEN) end) end
    gen = gen + 1
end

function Page.Visible()
    return U.valid(root) and U.visible(root)
end

RegisterKeyBindAsync(Key.ESCAPE, {}, function()
    if Page.Visible() then U.game(Page.Hide) end
end)

return Page

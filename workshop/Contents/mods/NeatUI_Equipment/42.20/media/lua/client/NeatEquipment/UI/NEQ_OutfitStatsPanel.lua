--[[ ============================================================================
    NEQ_OutfitStatsPanel - the protection or the warmth of one saved outfit.

    Opened from the two buttons beside Wear in an open outfit. It is the
    character window's Protection and Temperature tabs, but about the outfit
    instead of the survivor: the same body diagram (vanilla ISBodyPartPanel,
    the one Rocco's panels show too), the same columns with the game's own
    names - bite and scratch, insulation and wind resistance - and the numbers
    worked out by NEQ_OutfitStats from the outfit's own garments.

    One window per wardrobe, following it: open another outfit and the numbers
    are that outfit's. The two buttons switch it between protection and
    temperature, and the button already lit closes it.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/BodyParts/ISBodyPartPanel"

local Style   = require("NeatEquipment/NEQ_Style")
local Symbols = require("NeatEquipment/NEQ_Symbols")
local Stats   = require("NeatEquipment/NEQ_OutfitStats")

local FONT_TITLE = UIFont.Medium
local FONT_ROW   = UIFont.Small

-- ISBodyPartPanel is a fixed-size drawing (123 x 302), so this window is too.
local DIAGRAM_W, DIAGRAM_H = 123, 302
local PAD = 10
local WELL = 6

---@class NEQ_OutfitStatsPanel : ISPanel
local NEQ_OutfitStatsPanel = ISPanel:derive("NEQ_OutfitStatsPanel")

--- The character window's colours. Protection: its bad-to-good pair, over
--- 0..100. Temperature: the insulation view's five stops, over 0..1
--- (ISClothingInsPanel:create).
local function schemes()
    local bad, good = getCore():getBadHighlitedColor(), getCore():getGoodHighlitedColor()
    return {
        protection = {
            { val = 0, color = Color.new(bad:getR(), bad:getG(), bad:getB(), 1) },
            { val = 100, color = Color.new(good:getR(), good:getG(), good:getB(), 1) },
        },
        temperature = {
            { val = 0.00, color = Color.new(29 / 255, 34 / 255, 237 / 255, 1) },
            { val = 0.25, color = Color.new(0 / 255, 255 / 255, 234 / 255, 1) },
            { val = 0.50, color = Color.new(84 / 255, 255 / 255, 55 / 255, 1) },
            { val = 0.75, color = Color.new(255 / 255, 246 / 255, 0 / 255, 1) },
            { val = 1.00, color = Color.new(255 / 255, 0 / 255, 0 / 255, 1) },
        },
    }
end

local MODES = {
    protection = {
        icon = "armor", tab = "protection", max = 100,
        columns = { "IGUI_health_Bite", "IGUI_health_Scratch" },
    },
    temperature = {
        icon = "temperature", tab = "clothingIns", max = 1,
        columns = { "IGUI_Temp_Insulation", "IGUI_Temp_WindResistance" },
    },
}

--- The tab's own name, the one the character window gives it - also the
--- label of the wardrobe button that opens this. xpSystemText is vanilla's
--- (XpSystem_text.lua).
function NEQ_OutfitStatsPanel.title(mode)
    local texts = rawget(_G, "xpSystemText")
    local name = texts and MODES[mode] and texts[MODES[mode].tab]
    if name then return name end
    return getText(mode == "protection" and "IGUI_XP_Protection" or "IGUI_XP_ClothingIns")
end

function NEQ_OutfitStatsPanel:new(wardrobe)
    local o = ISPanel:new(0, 0, 300, 400)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.wardrobe = wardrobe
    o.char = wardrobe.char
    o.playerNum = wardrobe.playerNum
    o.mode = "protection"
    o.schemes = schemes()
    return o
end

function NEQ_OutfitStatsPanel:headerHeight()
    return self.wardrobe:headerHeight()
end

-- ---------------------------------------------------------------------------
-- Construction and layout
-- ---------------------------------------------------------------------------
function NEQ_OutfitStatsPanel:createChildren()
    self.closeButton = Style.newSquareButton(0, 0, 16, Style.tex("close"),
        self, self.close, Style.close)
    self.closeButton.neqTip = getText("UI_NEQ_tip_close")
    self:addChild(self.closeButton)

    -- The vanilla body diagram, set up as the character window sets it up
    -- for protection: no selection, colours only.
    self.diagram = ISBodyPartPanel:new(self.char, 0, 0, self, nil)
    self.diagram.canSelect = false
    self.diagram:initialise()
    self:addChild(self.diagram)

    self:layout()
end

function NEQ_OutfitStatsPanel:layout()
    local tm = getTextManager()
    local header = self:headerHeight()
    local fontH = tm:getFontHeight(FONT_ROW)
    self.lineH = fontH + 3
    self.fontH = fontH

    -- The widest part name and column title, in either mode, so switching
    -- between the two does not resize the window under the pointer.
    local nameW = 0
    for i = 0, Stats.PART_COUNT - 1 do
        nameW = math.max(nameW, tm:MeasureStringX(FONT_ROW, BodyPartType.getDisplayName(BodyPartType.FromIndex(i))))
    end
    nameW = math.max(nameW, tm:MeasureStringX(FONT_ROW, getText("IGUI_health_Part")))
    local columnW = tm:MeasureStringX(FONT_ROW, "100%")
    for _, mode in pairs(MODES) do
        for _, key in ipairs(mode.columns) do
            columnW = math.max(columnW, tm:MeasureStringX(FONT_ROW, getText(key)))
        end
    end
    self.nameW, self.columnW = nameW, columnW

    local buttonSize = Style.headerButtonSize(header)
    self.closeButton:setWidth(buttonSize)
    self.closeButton:setHeight(buttonSize)

    -- The outfit's line under the header, then the diagram in a well and the
    -- table beside it.
    self.outfitY = header + PAD
    self.bodyY = self.outfitY + self.lineH + math.floor(PAD / 2)

    self.well = { x = PAD, y = self.bodyY, w = DIAGRAM_W + WELL * 2, h = DIAGRAM_H + WELL * 2 }
    self.diagram:setX(self.well.x + WELL)
    self.diagram:setY(self.well.y + WELL)

    self.tableX = self.well.x + self.well.w + PAD
    self.columnX = { self.tableX + nameW + PAD }
    self.columnX[2] = self.columnX[1] + columnW + PAD

    local width = self.columnX[2] + columnW + PAD
    local tableH = (Stats.PART_COUNT + 1) * self.lineH + 4
    local height = self.bodyY + math.max(self.well.h, tableH) + PAD

    -- The title needs its room too: icon, name, close button.
    local titleW = tm:MeasureStringX(FONT_TITLE, NEQ_OutfitStatsPanel.title("temperature"))
    titleW = math.max(titleW, tm:MeasureStringX(FONT_TITLE, NEQ_OutfitStatsPanel.title("protection")))
    width = math.max(width, PAD * 4 + Style.headerIconSize(header) + titleW + buttonSize)

    self:setWidth(width)
    self:setHeight(height)
    self.closeButton:setX(width - PAD - buttonSize)
    self.closeButton:setY(math.floor((header - buttonSize) / 2))
end

-- ---------------------------------------------------------------------------
-- Opening, switching, following the wardrobe
-- ---------------------------------------------------------------------------
--- Opens on `mode`, switches to it, or - when it is already the one showing -
--- closes. The behaviour of the character window's own tabs.
---
--- Whether it is up is our own flag, not isVisible: asking a window that was
--- never built builds it (ISUIElement:isVisible -> instantiate), and a window
--- is born visible - the first click would have closed it.
function NEQ_OutfitStatsPanel:toggle(mode)
    if self.shown and self.mode == mode then
        self:close()
        return
    end
    self.mode = mode
    self.measured = nil
    if not self.shown then
        -- Measured afresh on every opening: a garment torn since the last
        -- look counts as torn.
        self.outfit = nil
        self.shown = true
        self:setVisible(true)
        self:addToUIManager()
        self:place()
    end
    self:bringToTop()
end

function NEQ_OutfitStatsPanel:isShown()
    return self.shown == true
end

--- Beside the wardrobe the first time, on the side with room; where the player
--- leaves it after that.
function NEQ_OutfitStatsPanel:place()
    if self.placed then
        self:clampToScreen()
        return
    end
    self.placed = true

    local screenW = getCore():getScreenWidth()
    local wardrobe = self.wardrobe
    local x = wardrobe:getX() + wardrobe:getWidth() + 4
    if x + self.width > screenW then x = wardrobe:getX() - self.width - 4 end
    self:setX(math.max(0, math.min(x, screenW - self.width)))
    self:setY(wardrobe:getY())
    self:clampToScreen()
end

function NEQ_OutfitStatsPanel:clampToScreen()
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setX(math.max(0, math.min(self:getX(), screenW - self:getWidth())))
    self:setY(math.max(0, math.min(self:getY(), screenH - self:getHeight())))
end

function NEQ_OutfitStatsPanel:close()
    self.shown = false
    self:setVisible(false)
    self:removeFromUIManager()
end

--- Is `outfit` still one of the wardrobe's? A deleted outfit closes this.
function NEQ_OutfitStatsPanel:stillSaved(outfit)
    for _, saved in ipairs(self.wardrobe:outfits()) do
        if saved == outfit then return true end
    end
    return false
end

--- The outfit to show: the one open in the wardrobe, or the last one shown
--- while none is open.
function NEQ_OutfitStatsPanel:currentOutfit()
    local open = self.wardrobe.expandedIndex and self.wardrobe:outfits()[self.wardrobe.expandedIndex]
    return open or self.outfit
end

--- Measures again when the outfit or the mode changed. Replacing an outfit
--- makes a new table (NEQ_Outfit.replace), so identity is enough.
function NEQ_OutfitStatsPanel:refresh()
    local outfit = self:currentOutfit()
    if outfit ~= self.outfit then
        self.outfit = outfit
        self.protection, self.warmth = nil, nil
        if outfit then
            local items = Stats.items(outfit, self.char, self.playerNum)
            self.protection = Stats.protection(items)
            self.warmth = Stats.warmth(items)
        end
        self.measured = nil
    end
    if self.measured == self.mode then return end
    self.measured = self.mode

    local mode = MODES[self.mode]
    self.diagram.maxValue = mode.max
    self.diagram:setColorScheme(self.schemes[self.mode])
    for i = 0, Stats.PART_COUNT - 1 do
        local part = BodyPartType.FromIndex(i)
        local value = 0
        if self.mode == "protection" and self.protection then
            value = self.protection.bite[i] + self.protection.scratch[i]
        elseif self.warmth then
            value = self.warmth.insulation[i]
        end
        self.diagram:setValue(part, value, true)
    end
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_OutfitStatsPanel:prerender()
    if self.outfit and not self:stillSaved(self.outfit) then
        self.outfit = nil
        self:close()
        return
    end
    self:refresh()

    local header = self:headerHeight()
    Style.drawWindow(self, 0, 0, self.width, self.height, header)

    -- Header: the tab's icon and name, as in the character window.
    local c, d = Style.text, Style.dim
    local iconSize = Style.headerIconSize(header)
    local icon = Style.tex(MODES[self.mode].icon)
    local x = PAD
    if icon then
        self:drawTextureScaled(icon, x, math.floor((header - iconSize) / 2), iconSize, iconSize, 1, 0.9, 0.9, 0.9)
        x = x + iconSize + PAD
    end
    local titleH = getTextManager():getFontHeight(FONT_TITLE)
    local title = Style.fitText(NEQ_OutfitStatsPanel.title(self.mode), self.closeButton:getX() - x - PAD, FONT_TITLE)
    self:drawText(title, x, math.floor((header - titleH) / 2), c.r, c.g, c.b, 1, FONT_TITLE)

    -- Which outfit: its symbol and its name, like its row in the wardrobe.
    local outfit = self.outfit
    if outfit then
        local ox = PAD
        local tex = outfit.symbol and Symbols.texture(outfit.symbol)
        if tex then
            Style.drawTextureFitted(self, tex, ox, self.outfitY, self.lineH, self.lineH, 1, 0.92, 0.92, 0.92)
            ox = ox + self.lineH + math.floor(PAD / 2)
        end
        local name = Style.fitText(outfit.name or getText("UI_NEQ_outfit_default_name"),
            self.width - ox - PAD, FONT_ROW)
        self:drawText(name, ox, self.outfitY + math.floor((self.lineH - self.fontH) / 2), c.r, c.g, c.b, 1, FONT_ROW)
    end

    -- The stage the diagram stands on, as the wardrobe's 3D previews do.
    local well = self.well
    Style.drawCard(self, well.x, well.y, well.w, well.h, 0.07, 0.55)

    -- The table: part, and the mode's two columns.
    local mode = MODES[self.mode]
    local y = self.bodyY
    self:drawText(getText("IGUI_health_Part"), self.tableX, y, d.r, d.g, d.b, 1, FONT_ROW)
    for k = 1, 2 do
        self:drawText(getText(mode.columns[k]), self.columnX[k], y, d.r, d.g, d.b, 1, FONT_ROW)
    end
    y = y + self.lineH
    local s = Style.separator
    self:drawRect(self.tableX, y, self.width - self.tableX - PAD, 1, 0.6, s.r, s.g, s.b)
    y = y + 3

    for i = 0, Stats.PART_COUNT - 1 do
        local part = BodyPartType.FromIndex(i)
        self:drawText(BodyPartType.getDisplayName(part), self.tableX, y, c.r, c.g, c.b, 1, FONT_ROW)
        local values = { 0, 0 }
        if self.mode == "protection" and self.protection then
            values = { self.protection.bite[i], self.protection.scratch[i] }
        elseif self.warmth then
            values = { self.warmth.insulation[i], self.warmth.wind[i] }
        end
        for k = 1, 2 do
            local v = values[k]
            local r, g, b = self.diagram:getRgbForValue(v)
            local shown = (self.mode == "protection") and v or math.floor(v * 100 + 0.5)
            self:drawText(tostring(shown) .. "%", self.columnX[k], y, r, g, b, 1, FONT_ROW)
        end
        y = y + self.lineH
    end
end

function NEQ_OutfitStatsPanel:render()
    local button = self.closeButton
    if button:isMouseOver() then
        Style.drawButtonTip(self, button.neqTip, button:getX() + button:getWidth() / 2,
            button:getY() + button:getHeight() + 3, true, 2, self.width - 2)
    end
end

-- ---------------------------------------------------------------------------
-- Mouse: dragged by the header, like the wardrobe.
-- ---------------------------------------------------------------------------
function NEQ_OutfitStatsPanel:onMouseDown(x, y)
    self:bringToTop()
    if y < self:headerHeight() then
        self.moving = true
        self:setCapture(true)
    end
    return true
end

function NEQ_OutfitStatsPanel:dragBy(dx, dy)
    if not self.moving then return end
    self:setX(self:getX() + dx)
    self:setY(self:getY() + dy)
end

function NEQ_OutfitStatsPanel:onMouseMove(dx, dy)        self:dragBy(dx, dy) end
function NEQ_OutfitStatsPanel:onMouseMoveOutside(dx, dy) self:dragBy(dx, dy) end

function NEQ_OutfitStatsPanel:stopMoving()
    if not self.moving then return end
    self.moving = false
    self:setCapture(false)
    self:clampToScreen()
end

function NEQ_OutfitStatsPanel:onMouseUp(x, y)        self:stopMoving() return true end
function NEQ_OutfitStatsPanel:onMouseUpOutside(x, y) self:stopMoving() end

return NEQ_OutfitStatsPanel

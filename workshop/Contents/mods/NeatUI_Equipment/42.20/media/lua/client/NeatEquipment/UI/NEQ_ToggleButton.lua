--[[ ============================================================================
    NEQ_ToggleButton - the little Equipment button on the side of the CleanUI
    inventory.

    It is a top-level UI element rather than a child of the inventory window, so
    it does not have to fight CleanUI over the title-bar layout: it simply
    re-positions itself against that window every frame and follows it around.

    It sits on the outer edge of the inventory - the left one, or the right one
    when Mod Options put the panel there - level with the top of the window.
    The docked panel starts at that same top edge, and its header leaves the
    button a place of its own (headerReserve, in the panel), which is why the
    two never overlap and the button stays clickable with the panel open.

    A standing figure - "what you have on" - rather than the bag it used to be,
    which read as one more container next to the real ones. Grey when the
    panel is closed, orange when it is open. Same square-button art as the
    header buttons.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISUIElement"

local Style  = require("NeatEquipment/NEQ_Style")
local State  = require("NeatEquipment/NEQ_State")
local Tetris = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")

local GAP = 3

---@class NEQ_ToggleButton : ISUIElement
local NEQ_ToggleButton = ISUIElement:derive("NEQ_ToggleButton")

function NEQ_ToggleButton:new(panel)
    local o = ISUIElement:new(0, 0, 16, 16)
    setmetatable(o, self)
    self.__index = self

    o.panel = panel
    o.inventoryPage = panel.inventoryPage
    o.playerNum = panel.playerNum

    return o
end

--- Reads the intent, not the animation: the button should light the instant it is
--- clicked, not a tenth of a second later when the panel has finished moving.
function NEQ_ToggleButton:isOpen()
    return self.panel ~= nil and not self.panel.closed
end

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------
--- Big enough to be the obvious way in, small enough that it still belongs to
--- the title bar it sits against.
---
--- Lo stesso lato dei tasti dell'intestazione: agganciato sta in fila con loro,
--- dentro la stessa barra, e un tasto piu' piccolo degli altri sembrerebbe di
--- un'altra finestra.
function NEQ_ToggleButton:preferredSize()
    local band = self.panel and tonumber(self.panel.headerHeight)
    if band then return Style.headerButtonSize(band) end
    local page = self.inventoryPage
    local titleBarHeight = (page and page.titleBarHeight and page:titleBarHeight()) or 16
    return math.max(18, math.floor(titleBarHeight * 1.15))
end

--- Quanti pixel del pannello agganciato occupa, dal suo bordo verso
--- l'inventario: il tasto, lo stacco, e la striscia di Tetris a sinistra. Uno
--- in piu' perche' il pannello sormonta l'inventario di un pixel
--- (snapToInventory). Calcolato e non letto dalla posizione: il pannello lo
--- chiede durante il suo prerender, che puo' venire prima di reposition.
function NEQ_ToggleButton:reserveInPanel()
    local size = self:preferredSize()
    if State.dockRight then return GAP + size + 1 + 2 end
    return size + GAP + Tetris.sideStripWidth(self.inventoryPage) + 1 + 2
end

function NEQ_ToggleButton:reposition()
    local page = self.inventoryPage
    if not page then return end

    local titleBarHeight = page.titleBarHeight and page:titleBarHeight() or 16
    local size = self:preferredSize()

    self:setWidth(size)
    self:setHeight(size)

    -- The side the panel hangs from, chosen in Mod Options, and never flipped
    -- by itself: a button that moves when the window nears a screen edge is a
    -- button you have to look for.
    --
    -- A sinistra l'unico scostamento e' la striscia delle linguette di Notloc,
    -- che sotto Inventory Tetris sta in questo stesso punto. Tolto il loro
    -- pannello di solito e' vuota e non chiede niente; se ci resta dentro la
    -- linguetta di un'altra mod, le si fa posto invece di scriverci sopra. A
    -- destra la striscia non c'e'.
    if State.dockRight then
        self:setX(page:getX() + page:getWidth() + GAP)
    else
        self:setX(page:getX() - size - GAP - Tetris.sideStripWidth(page))
    end

    -- In altezza sta al centro della NOSTRA intestazione, a pannello aperto o
    -- chiuso: agganciato e aperto e' li' dentro, e un tasto che salta di
    -- qualche pixel ogni volta che lo si preme sembra rotto. Da chiuso sporge
    -- un poco sotto la barra di CleanUI, come faceva prima della 1.0.0. Il
    -- pannello agganciato parte dal bordo alto dell'inventario, salvo quando lo
    -- schermo lo spinge piu' su (snapToInventory): allora si segue lui.
    local band = tonumber(self.panel and self.panel.headerHeight) or titleBarHeight
    local top = page:getY()
    if self.panel and self.panel.docked and self:isOpen() then
        top = self.panel:getY()
    end
    self:setY(top + math.floor((band - size) / 2))
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_ToggleButton:prerender()
    -- This element is never hidden, only shrunk to nothing: prerender does not
    -- run on a hidden element, and this is the one piece that has to keep
    -- running to bring the panel back when the inventory reappears.
    if self.panel then self.panel:updateVisibility() end

    local page = self.inventoryPage
    if not page or not page:isVisible() then
        self:setWidth(0)
        return
    end

    -- Chi ha scelto la scorciatoia non vuole vedere il tasto. Larghezza zero,
    -- non invisibile: vedi la nota su State:setHideBagButton.
    if State.hideBagButton or State.disabled then
        self:setWidth(0)
        return
    end

    self:reposition()

    local open = self:isOpen()
    local hover = self:isMouseOver()

    local r, g, b = 0.20, 0.20, 0.20
    if open then
        local a = Style.accent
        r, g, b = a.r, a.g, a.b
    end
    if self.pressed then
        r, g, b = r * 0.8, g * 0.8, b * 0.8
    elseif hover then
        r, g, b = math.min(r * 1.2, 1), math.min(g * 1.2, 1), math.min(b * 1.2, 1)
    end

    local bg, border = Style.tex("btnBg"), Style.tex("btnBorder")
    if bg then
        self:drawTextureScaled(bg, 0, 0, self.width, self.height, 0.85, r, g, b)
    else
        self:drawRect(0, 0, self.width, self.height, 0.85, r, g, b)
    end
    if border then
        self:drawTextureScaled(border, 0, 0, self.width, self.height, 1, 0.4, 0.4, 0.4)
    end

    local icon = Style.tex("figure")
    if icon then
        local size = math.floor(self.width * 0.78)
        local offset = math.floor((self.width - size) / 2)
        self:drawTextureScaled(icon, offset, offset, size, size, 1, 0.95, 0.95, 0.95)
    end
end

function NEQ_ToggleButton:render()
    if self.width <= 0 then return end
    if not self:isMouseOver() then return end

    -- The label hangs off the outer side, away from the inventory it would
    -- otherwise cover.
    local text = getText(self:isOpen() and "UI_NEQ_tip_close" or "UI_NEQ_tip_open")

    local tm = getTextManager()
    local font = UIFont.Small
    local fontH = tm:getFontHeight(font)
    local textW = tm:MeasureStringX(font, text)
    local padX = math.max(4, math.floor(fontH * 0.45))
    local w = textW + padX * 2
    local h = fontH + math.max(2, math.floor(fontH * 0.25))

    local x = State.dockRight and (self.width + 6) or (-6 - w)
    local y = math.floor((self.height - h) / 2)

    Style.drawPill(self, x, y, w, h)
    self:drawText(text, x + padX, y + math.floor((h - fontH) / 2), 1, 1, 1, 1, font)
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_ToggleButton:onMouseDown(x, y)
    self.pressed = true
    return true
end

function NEQ_ToggleButton:onMouseUp(x, y)
    if not self.pressed then return true end
    self.pressed = false

    if self.panel then
        self.panel:togglePanel()
        getSoundManager():playUISound("UIActivateButton")
    end
    return true
end

function NEQ_ToggleButton:onMouseUpOutside(x, y)
    self.pressed = false
end

return NEQ_ToggleButton

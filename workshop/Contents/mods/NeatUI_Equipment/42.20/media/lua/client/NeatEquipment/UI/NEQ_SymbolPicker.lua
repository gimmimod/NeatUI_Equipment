--[[ ============================================================================
    NEQ_SymbolPicker - the sheet of symbols an outfit can carry.

    Project Writing's symbol sheet, rebuilt for the wardrobe: category tabs on
    top, a grid of tiles below, the wheel to scroll. It is a popup - it opens
    under the button that asked for it, closes on a pick or on a click
    anywhere else - so it is its own top-level panel rather than a child of the
    wardrobe, and can hang past the wardrobe's edge.

    Tabs and tiles are not child buttons. There are up to a hundred and
    forty tiles, and every one of them only needs a rectangle to draw and a
    rectangle to hit: both come from the same layout pass below, so what is
    drawn and what is clicked cannot disagree.

    The first tile of every tab is "no symbol": the outfit goes back to the
    hanger.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local Style   = require("NeatEquipment/NEQ_Style")
local Symbols = require("NeatEquipment/NEQ_Symbols")

---@class NEQ_SymbolPicker : ISPanel
local NEQ_SymbolPicker = ISPanel:derive("NEQ_SymbolPicker")

local BASE = { cell = 28, gap = 4, pad = 8, tabGap = 3 }
local COLUMNS = 8
local VISIBLE_ROWS = 5
local NONE = ""

local function r(v) return math.floor(v + 0.5) end

function NEQ_SymbolPicker:new()
    local o = ISPanel:new(0, 0, 200, 200)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.scale = 1
    o.tab = nil
    o.scrollRow = 0
    o.tabRects = {}
    o.cells = {}
    return o
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
function NEQ_SymbolPicker:metrics()
    local s = self.scale
    local m = {
        cell = math.max(18, r(BASE.cell * s)),
        gap = math.max(2, r(BASE.gap * s)),
        pad = math.max(5, r(BASE.pad * s)),
        tabGap = math.max(2, r(BASE.tabGap * s)),
    }
    m.font, m.fontH = Style.pickFont(math.max(10, r(getTextManager():getFontHeight(UIFont.Small) * s)))
    m.tabH = m.fontH + math.max(4, r(7 * s))
    m.width = m.pad * 2 + COLUMNS * m.cell + (COLUMNS - 1) * m.gap
    return m
end

--- The ids shown in the current tab, "no symbol" first.
function NEQ_SymbolPicker:list()
    local out = { NONE }
    for _, id in ipairs(Symbols.groups()[self.tab] or {}) do out[#out + 1] = id end
    return out
end

function NEQ_SymbolPicker:layout()
    local m = self:metrics()
    self:setWidth(m.width)

    -- Tabs wrap: nine names do not fit on one line of a sheet this wide.
    self.tabRects = {}
    local x, y = m.pad, m.pad
    for _, tab in ipairs(Symbols.tabs()) do
        local label = Symbols.tabLabel(tab)
        local w = getTextManager():MeasureStringX(m.font, label) + math.max(8, r(12 * self.scale))
        if x > m.pad and x + w > m.width - m.pad then
            x = m.pad
            y = y + m.tabH + m.tabGap
        end
        self.tabRects[#self.tabRects + 1] = { tab = tab, label = label, x = x, y = y, w = w, h = m.tabH }
        x = x + w + m.tabGap
    end

    self.gridY = y + m.tabH + m.pad
    local list = self:list()
    self.rows = math.max(1, math.ceil(#list / COLUMNS))
    self.visibleRows = math.min(self.rows, VISIBLE_ROWS)
    self.scrollRow = math.max(0, math.min(self.scrollRow, self.rows - self.visibleRows))

    self.cells = {}
    for i, id in ipairs(list) do
        local col = (i - 1) % COLUMNS
        local row = math.floor((i - 1) / COLUMNS)
        self.cells[i] = { id = id, row = row,
            x = m.pad + col * (m.cell + m.gap), size = m.cell }
    end

    self:setHeight(self.gridY + self.visibleRows * (m.cell + m.gap) - m.gap + m.pad)
end

--- Where a cell is drawn now, scroll included.
function NEQ_SymbolPicker:cellY(cell)
    local m = self:metrics()
    return self.gridY + (cell.row - self.scrollRow) * (m.cell + m.gap)
end

function NEQ_SymbolPicker:cellVisible(cell)
    return cell.row >= self.scrollRow and cell.row < self.scrollRow + self.visibleRows
end

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------
--- Opens under `anchor` (a UI element on screen), with `current` marked.
--- `onPick(id)` receives the chosen id, or nil for "no symbol".
function NEQ_SymbolPicker:open(anchor, current, scale, onPick)
    -- The click that closed the sheet lands on its own button a moment later:
    -- the sheet closes on the press, the button fires on the release. Without
    -- this, that button would open it straight back - a toggle that cannot be
    -- switched off.
    if self.closedFor == anchor and self.closedAt
        and getTimestampMs() - self.closedAt < 500 then
        self.closedFor = nil
        return
    end

    self.anchor = anchor
    self.current = current
    self.onPick = onPick
    self.scale = scale or 1
    self.tab = (current and Symbols.tabOf(current)) or self.tab or Symbols.tabs()[1]
    self.scrollRow = 0
    self:layout()

    -- Show the row the current symbol sits in.
    for _, cell in ipairs(self.cells) do
        if cell.id == current and not self:cellVisible(cell) then
            self.scrollRow = math.min(cell.row, self.rows - self.visibleRows)
        end
    end

    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local ax, ay = anchor:getAbsoluteX(), anchor:getAbsoluteY()
    local x = ax + anchor:getWidth() - self.width
    local y = ay + anchor:getHeight() + 2
    if y + self.height > screenH then y = ay - self.height - 2 end
    self:setX(math.max(0, math.min(x, screenW - self.width)))
    self:setY(math.max(0, math.min(y, screenH - self.height)))

    if not self.inManager then
        self:addToUIManager()
        self.inManager = true
    end
    self:setVisible(true)
    self:setAlwaysOnTop(true)
    self:bringToTop()
end

function NEQ_SymbolPicker:close()
    if not self:isVisible() then return end
    self.closedFor = self.anchor
    self.closedAt = getTimestampMs()
    self:setVisible(false)
    self.onPick = nil
end

function NEQ_SymbolPicker:isOpenFor(anchor)
    return self:isVisible() and self.anchor == anchor
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_SymbolPicker:prerender()
    Style.drawCard(self, 0, 0, self.width, self.height, 0.10, 0.98, Style.CARD_LINE_OPEN, 1)
end

function NEQ_SymbolPicker:render()
    local m = self:metrics()
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()

    for _, t in ipairs(self.tabRects) do
        local on = t.tab == self.tab
        local hover = over and mx >= t.x and mx < t.x + t.w and my >= t.y and my < t.y + t.h
        local c = on and Style.accent or (hover and Style.text or Style.dim)
        if on then
            self:drawRect(t.x + 2, t.y + t.h - 2, t.w - 4, 2, 1, c.r, c.g, c.b)
        end
        self:drawTextCentre(t.label, t.x + t.w / 2, t.y + math.floor((t.h - m.fontH) / 2),
            c.r, c.g, c.b, 1, m.font)
    end

    local top = self.gridY
    local height = self.visibleRows * (m.cell + m.gap)
    self:setStencilRect(0, top, self.width, height)

    local tip = nil
    for _, cell in ipairs(self.cells) do
        if self:cellVisible(cell) then
            local x, y, size = cell.x, self:cellY(cell), cell.size
            local hover = over and mx >= x and mx < x + size and my >= y and my < y + size
            local selected = (cell.id == NONE and not self.current) or cell.id == self.current

            local fill = hover and 0.20 or 0.15
            local line, lineAlpha = Style.CARD_LINE, 0.9
            if selected then line, lineAlpha = Style.selection, 1
            elseif hover then line, lineAlpha = Style.accent, 0.9 end
            Style.drawCard(self, x, y, size, size, fill, 0.9, line, lineAlpha)

            local p = math.max(3, math.floor(size * 0.18))
            if cell.id == NONE then
                local hanger = Style.tex("outfitLoad")
                if hanger then
                    self:drawTextureScaled(hanger, x + p, y + p, size - p * 2, size - p * 2,
                        hover and 0.8 or 0.45, 0.9, 0.9, 0.9)
                end
                if hover then tip = { text = getText("UI_NEQ_wardrobe_symbol_none"), x = x + size / 2, y = y + size } end
            else
                local tex = Symbols.texture(cell.id)
                if tex then
                    Style.drawTextureFitted(self, tex, x + p, y + p, size - p * 2, size - p * 2,
                        1, 0.92, 0.92, 0.92)
                end
            end
        end
    end
    self:clearStencilRect()

    if self.rows > self.visibleRows then
        local frac = self.visibleRows / self.rows
        local barH = math.max(14, height * frac)
        local at = self.scrollRow / math.max(1, self.rows - self.visibleRows)
        local bx = self.width - math.max(3, math.floor(m.pad / 2))
        self:drawRect(bx, top, 2, height - m.gap, 0.35, 0.30, 0.30, 0.32)
        local a = Style.accent
        self:drawRect(bx, top + (height - m.gap - barH) * at, 2, barH, 0.9, a.r, a.g, a.b)
    end

    if tip then
        Style.drawButtonTip(self, tip.text, tip.x, tip.y + 2, true, 2, self.width - 2)
    end
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_SymbolPicker:onMouseDown(x, y) return true end

function NEQ_SymbolPicker:onMouseUp(x, y)
    for _, t in ipairs(self.tabRects) do
        if x >= t.x and x < t.x + t.w and y >= t.y and y < t.y + t.h then
            if self.tab ~= t.tab then
                self.tab = t.tab
                self.scrollRow = 0
                self:layout()
                getSoundManager():playUISound("UISelectListItem")
            end
            return true
        end
    end

    for _, cell in ipairs(self.cells) do
        if self:cellVisible(cell) then
            local cy = self:cellY(cell)
            if x >= cell.x and x < cell.x + cell.size and y >= cy and y < cy + cell.size then
                local pick = self.onPick
                local id = cell.id ~= NONE and cell.id or nil
                self:close()
                if pick then pick(id) end
                getSoundManager():playUISound("UIActivateButton")
                return true
            end
        end
    end
    return true
end

function NEQ_SymbolPicker:onMouseWheel(del)
    local maxRow = math.max(0, self.rows - self.visibleRows)
    self.scrollRow = math.max(0, math.min(maxRow, self.scrollRow + del))
    return true
end

function NEQ_SymbolPicker:onMouseDownOutside(x, y)
    self:close()
end

return NEQ_SymbolPicker

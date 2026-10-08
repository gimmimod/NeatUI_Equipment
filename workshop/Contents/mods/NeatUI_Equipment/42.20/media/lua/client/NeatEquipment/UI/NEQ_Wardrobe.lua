--[[ ============================================================================
    NEQ_Wardrobe - save an outfit, put one back on.

    Its own window, not a popup: it is dragged by its header, resized by the
    corner grip, and closes only when you close it. Wearing an outfit leaves it
    open, and so does closing the equipment panel - deciding what to wear is
    usually several tries, and a list that vanishes on the first click makes you
    reopen it every time.

    Two parts, because there are only two things to do here:

        top     the save card: what you have on, in 3D, as it would be saved;
                two ticks for what goes into it (bags; belt and hotbar); the
                name, its symbol, and the tick that saves
        bottom  the saved outfits, one rounded box each. Clicking a box opens
                it downwards: the outfit in 3D, the shirt button that puts it
                on, and three square buttons beside it - the outfit's own
                protection and warmth, part by part (NEQ_OutfitStatsPanel), and
                "replace", which saves what you have on over this outfit,
                keeping its name and symbol. One box is open at a time.

    The header has Rocco's collapse arrow (NEQ_Collapse): armed, the window
    rolls up to its header when the pointer leaves and unrolls when it comes
    back to the header, so the wardrobe can stay on screen as a title bar.

    The list scrolls once it is taller than the screen allows: 24 outfits, one
    of them open, do not fit on a 1080p screen.

    Every box - the card, a row, an open row, the name field - is the same
    rounded nine-patch (NEQ_Style.drawCard), so every corner in the window has
    the same radius whatever the box's height.

    Sizing follows NeatUI XP Drop: the grip drives a single scale factor and
    every metric derives from it. Only the width the grip reports is used - the
    height is however much there is to show.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"

local Config  = require("NeatEquipment/NEQ_Config")
local State   = require("NeatEquipment/NEQ_State")
local Style   = require("NeatEquipment/NEQ_Style")
local Outfit  = require("NeatEquipment/NEQ_Outfit")
local Dresser = require("NeatEquipment/NEQ_Dresser")
local Symbols = require("NeatEquipment/NEQ_Symbols")
local NEQ_Grip = require("NeatEquipment/UI/NEQ_Grip")
local NEQ_OutfitPreview = require("NeatEquipment/UI/NEQ_OutfitPreview")
local NEQ_SymbolPicker  = require("NeatEquipment/UI/NEQ_SymbolPicker")
local Collapse = require("NeatEquipment/UI/NEQ_Collapse")
local NEQ_OutfitStatsPanel = require("NeatEquipment/UI/NEQ_OutfitStatsPanel")

local FONT_TITLE = UIFont.Medium
local FONT_ROW   = UIFont.Small

local BASE_WIDTH = 270
local MIN_SCALE = 0.85
local MAX_SCALE = 2.00
local NAME_LIMIT = 24

-- The symbol a save card shows before one is chosen. One of the game's own,
-- so it is always there.
local PLACEHOLDER_SYMBOL = "FaceHappy"

-- How long the replace button waits for its second click.
local REPLACE_CONFIRM_MS = 4000

---@class NEQ_Wardrobe : ISPanel
local NEQ_Wardrobe = ISPanel:derive("NEQ_Wardrobe")

-- La stessa barra del titolo del pannello equipaggiamento, alla lettera.
NEQ_Wardrobe.headerH = math.floor(getTextManager():getFontHeight(FONT_TITLE) * 1.5)

-- Open wardrobes, for the clothing event. Weak: a closed window is not kept
-- alive by being listed here.
local openWardrobes = setmetatable({}, { __mode = "k" })

function NEQ_Wardrobe:new(playerNum)
    local o = ISPanel:new(0, 0, BASE_WIDTH, 200)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.playerNum = playerNum
    o.char = getSpecificPlayer(playerNum)
    o.rows = {}
    o.renamingIndex = nil
    o.expandedIndex = nil
    o.scrollY = 0
    o.newSymbol = nil

    local config = Config.get()
    o.scale = math.max(MIN_SCALE, math.min(config.wardrobe_scale or 1.0, MAX_SCALE))
    o.saveBags = config.wardrobe_save_bags ~= false
    o.saveHotbar = config.wardrobe_save_hotbar ~= false

    -- After the fields: it wraps the mouse handlers of this very instance.
    Collapse.init(o)
    return o
end

-- ---------------------------------------------------------------------------
-- Metrics
-- ---------------------------------------------------------------------------
local function r(v) return math.floor(v + 0.5) end

--[[ Le misure della finestra, in un posto solo.

    Due cose non scalano con il resto, di proposito:

      * la barra del titolo, alta esattamente quanto quella del pannello
        equipaggiamento: sono due finestre della stessa famiglia;
      * il trascinatore d'angolo, 16 px come in Rocco.

    I tasti su una riga sono piu' piccoli di quelli d'intestazione: una riga e'
    fatta soprattutto di nome, e tasti all'80% dell'altezza la comandavano.
]]
function NEQ_Wardrobe:metrics()
    local s = self.scale
    local fontH = getTextManager():getFontHeight(FONT_ROW)
    local rowH = math.max(26, r((fontH + 12) * s))
    return {
        width = r(BASE_WIDTH * s),
        pad = math.max(6, r(8 * s)),
        gap = math.max(4, r(5 * s)),
        section = math.max(8, r(10 * s)),
        cardPad = math.max(6, r(8 * s)),
        rowH = rowH,
        rowInset = math.max(4, math.floor(rowH * 0.16)),
        rowButton = math.max(13, math.floor(rowH * 0.52)),
        symbol = rowH - 2 * math.max(4, math.floor(rowH * 0.16)),
        savePreview = math.max(130, r(170 * s)),
        slotPreview = math.max(120, r(150 * s)),
        toggleH = math.max(22, r((fontH + 10) * s)),
        fieldH = math.max(24, r((fontH + 12) * s)),
        wearH = math.max(22, r((fontH + 10) * s)),
        header = NEQ_Wardrobe.headerH,
        grip = 16,
        fontH = fontH,
    }
end

function NEQ_Wardrobe:headerHeight()
    return self:metrics().header
end

function NEQ_Wardrobe:outfits()
    return Outfit.all(self.char)
end

--- Is the hotbar left out of every outfit by Mod Options? Then the save
--- card's hotbar tick is off and cannot be turned on.
local function hotbarLockedOff()
    return State.wardrobeNoHotbar == true
end

-- ---------------------------------------------------------------------------
-- Small controls
-- ---------------------------------------------------------------------------
--- An ISButton that draws nothing of vanilla's: `paint(button)` draws it all.
local function newPaintedButton(target, onclick, paint)
    local b = ISButton:new(0, 0, 10, 10, "", target, onclick)
    b:initialise()
    b:instantiate()
    b:setDisplayBackground(false)
    b.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    b.prerender = function(button) end
    b.render = paint
    return b
end

--- A symbol well: a small dark box with the symbol in it, or the hanger when
--- the outfit has none. `placeholder` is for the save card, where the empty
--- state is an invitation - a dim smiley - rather than the hanger.
local function paintSymbolWell(button, symbol, placeholder)
    local hover = button:isMouseOver()
    local line = hover and Style.accent or Style.CARD_LINE
    Style.drawCard(button, 0, 0, button.width, button.height,
        hover and 0.12 or 0.07, 0.95, line, hover and 0.9 or 0.8)

    local tex = symbol and Symbols.texture(symbol)
    local alpha, tint = 1, 0.92
    if not tex then
        tex = placeholder and Symbols.texture(PLACEHOLDER_SYMBOL) or Style.tex("outfitLoad")
        alpha = hover and 0.75 or 0.45
    end
    if tex then
        local p = math.max(3, math.floor(button.width * 0.2))
        Style.drawTextureFitted(button, tex, p, p, button.width - p * 2, button.height - p * 2,
            alpha, tint, tint, tint)
    end
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
function NEQ_Wardrobe:createChildren()
    local wardrobe = self

    self.closeButton = Style.newSquareButton(0, 0, 16, Style.tex("close"),
        self, self.onClose, Style.close)
    self.closeButton.neqTip = getText("UI_NEQ_tip_close")
    self:addChild(self.closeButton)

    -- Rocco's arrow, on the left of the header like in NR_Header: orange and
    -- pointing down while the window stays open.
    self.collapseButton = Style.newSquareButton(0, 0, 16, Style.tex("collapseOpen"),
        self, self.onClickCollapse, Style.accent)
    self:addChild(self.collapseButton)
    self:refreshCollapseButton()

    -- The save card ---------------------------------------------------------
    self.savePreview = NEQ_OutfitPreview:new(0, 0, 60, 120, self.playerNum)
    self.savePreview:initialise()
    self:addChild(self.savePreview)

    self.bagsToggle = newPaintedButton(self, self.onToggleBags, function(button)
        wardrobe:paintToggle(button, Style.tex("bagClosed"), getText("UI_NEQ_wardrobe_bags"),
            wardrobe.saveBags, false)
    end)
    self.bagsToggle.neqTip = getText("UI_NEQ_wardrobe_bags_tip")
    self:addChild(self.bagsToggle)

    self.hotbarToggle = newPaintedButton(self, self.onToggleHotbar, function(button)
        local locked = hotbarLockedOff()
        wardrobe:paintToggle(button, Style.tex("belt"), getText("UI_NEQ_wardrobe_hotbar"),
            wardrobe.saveHotbar and not locked, locked)
    end)
    self:addChild(self.hotbarToggle)

    self.nameEntry = self:newTextField(Outfit.suggestName(self.char))
    self.nameEntry.onCommandEntered = function() wardrobe:onSave() end
    self.lastSuggestion = self.nameEntry:getInternalText()

    self.symbolButton = newPaintedButton(self, self.onPickNewSymbol, function(button)
        paintSymbolWell(button, wardrobe.newSymbol, true)
    end)
    self.symbolButton.neqTip = getText("UI_NEQ_wardrobe_symbol")
    self:addChild(self.symbolButton)

    -- Neat's "+", green, as Rocco's add buttons: this adds an outfit to the
    -- list. The tick stays for confirming a rename.
    self.saveButton = Style.newSquareButton(0, 0, 16, Style.tex("add"),
        self, self.onSave, Style.selection)
    self.saveButton.neqTip = getText("UI_NEQ_wardrobe_save")
    self:addChild(self.saveButton)

    -- The open row --------------------------------------------------------
    self.slotPreview = NEQ_OutfitPreview:new(0, 0, 60, 120, self.playerNum)
    self.slotPreview:initialise()
    self.slotPreview:setVisible(false)
    self:addChild(self.slotPreview)

    self.wearButton = newPaintedButton(self, self.onWearExpanded, function(button)
        wardrobe:paintWearButton(button)
    end)
    self.wearButton:setVisible(false)
    self:addChild(self.wearButton)

    -- Beside the wear button: the outfit's protection and warmth, then the
    -- one that changes the outfit. The first two are labelled with the names
    -- the character window gives the same tabs, already in every language.
    self.protectionButton = self:newOpenRowButton(Style.tex("armor"),
        NEQ_OutfitStatsPanel.title("protection"), function() self:onShowStats("protection") end)
    self.temperatureButton = self:newOpenRowButton(Style.tex("temperature"),
        NEQ_OutfitStatsPanel.title("temperature"), function() self:onShowStats("temperature") end)
    self.replaceButton = self:newOpenRowButton(Style.tex("swap"),
        getText("UI_NEQ_wardrobe_replace"), function() self:onReplaceExpanded() end)
    self.openRowButtons = { self.protectionButton, self.temperatureButton, self.replaceButton }

    local panel = self
    self.grip = NEQ_Grip:new(16, self,   -- NR_ResizeWidget.SIZE
        function(width) panel:onGripResize(width) end,
        function() Config.set("wardrobe_scale", panel.scale) end)
    self.grip:initialise()
    self:addChild(self.grip)
    self.grip:setAlwaysOnTop(true)

    self.picker = NEQ_SymbolPicker:new()
    self.picker:initialise()

    self:refreshSavePreview()
    self:rebuild()
end

--[[ A Neat text field: the vanilla entry box keeps its caret, selection and
    keys, and loses only its flat grey rectangle.

    Where the text sits is the engine's business (UITextBox2), and by default
    it hugs the top-left corner, two pixels in: in a box with rounded corners
    the name ran over the edge. Two things put it back inside:

      * setCentreVertically - the engine's own switch, the one the crafting
        filter uses (ISWidgetRecipeFilterPanel);
      * the box is placed FIELD_INSET further in than the field it draws,
        which starts that much to its left.

    Not the engine's frame, which would give a 5 px inset of its own
    (UITextBox2.getInset): even at alpha 0 part of it showed, as a blue
    square at the start of the field.
]]
local FIELD_INSET = 7

function NEQ_Wardrobe:newTextField(text)
    local entry = ISTextEntryBox:new(text or "", 0, 0, 10, 10)
    entry:initialise()
    entry:instantiate()
    if entry.setMaxTextLength then entry:setMaxTextLength(NAME_LIMIT) end
    pcall(function() entry.javaObject:setCentreVertically(true) end)
    entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.prerender = function(box)
        Style.drawTextField(box, -FIELD_INSET, 0, box.width + FIELD_INSET, box.height, box:isFocused())
    end
    self:addChild(entry)
    return entry
end

--- Places a field made by newTextField over the rectangle it should look like.
function NEQ_Wardrobe:placeTextField(entry, x, y, w, h)
    entry:setX(x + FIELD_INSET)
    entry:setY(y)
    entry:setWidth(math.max(24, w - FIELD_INSET))
    entry:setHeight(h)
end

function NEQ_Wardrobe:onGripResize(width)
    local scale = math.max(MIN_SCALE, math.min(width / BASE_WIDTH, MAX_SCALE))
    if math.abs(scale - self.scale) < 0.005 then return end

    self.scale = scale
    if self.picker then self.picker:close() end
    -- A rebuild throws the rename field away: keep what was typed.
    if self.renamingIndex then
        self:commitRename()
    else
        self:rebuild()
    end
end

--- Rows are rebuilt whenever the list or the scale changes rather than kept in
--- sync: there are at most two dozen, and rebuilding is a few inserts. Always
--- from a click or an event, never from a render pass (METODO/03, lesson 12).
function NEQ_Wardrobe:rebuild()
    for _, row in ipairs(self.rows) do
        self:removeChild(row.symbolButton)
        self:removeChild(row.renameButton)
        self:removeChild(row.deleteButton)
    end
    self.rows = {}

    if self.renameEntry then
        self:removeChild(self.renameEntry)
        self.renameEntry = nil
    end

    local outfits = self:outfits()
    if self.expandedIndex and not outfits[self.expandedIndex] then self.expandedIndex = nil end

    for index in ipairs(outfits) do
        local row = { index = index }

        row.symbolButton = newPaintedButton(self, function() self:onPickRowSymbol(index) end,
            function(button)
                local outfit = self:outfits()[index]
                paintSymbolWell(button, outfit and outfit.symbol, false)
            end)
        row.symbolButton.neqTip = getText("UI_NEQ_wardrobe_symbol")
        self:addChild(row.symbolButton)

        row.renameButton = self:newRowButton(Style.tex("rename"),
            getText("UI_NEQ_wardrobe_rename"), function() self:onRename(index) end)
        -- Red, like the close button: the one control here that destroys
        -- something should not look like the one next to it.
        row.deleteButton = self:newRowButton(Style.tex("remove"),
            getText("UI_NEQ_wardrobe_delete"), function() self:onDelete(index) end, Style.close)

        self.rows[#self.rows + 1] = row
    end

    self:refreshRowIcons()
    self:showExpanded()
    self:layout()
end

function NEQ_Wardrobe:newRowButton(icon, tip, onclick, colour)
    local button = Style.newSquareButton(0, 0, 16, icon, self,
        function() onclick() end, colour)
    button.neqTip = tip
    self:addChild(button)
    return button
end

--- A button of the open row: hidden until a row is open.
function NEQ_Wardrobe:newOpenRowButton(icon, tip, onclick)
    local button = self:newRowButton(icon, tip, onclick)
    button:setVisible(false)
    return button
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
--- How tall the part of a row below its header line is, when open.
function NEQ_Wardrobe:bodyHeight(m)
    return m.gap + m.slotPreview + m.gap + m.wearH + m.cardPad
end

function NEQ_Wardrobe:rowHeight(index, m)
    if self.expandedIndex == index then return m.rowH + self:bodyHeight(m) end
    return m.rowH
end

function NEQ_Wardrobe:layout()
    local m = self:metrics()
    self:setWidth(m.width)
    local inner = m.width - m.pad * 2

    -- Stesse proporzioni dell'intestazione di Equipment: vedi Style.HEADER.
    local buttonSize = Style.headerButtonSize(m.header)
    self.closeButton:setX(m.width - m.pad - buttonSize)
    self.closeButton:setY(math.floor((m.header - buttonSize) / 2))
    self.closeButton:setWidth(buttonSize)
    self.closeButton:setHeight(buttonSize)

    self.collapseButton:setX(m.pad)
    self.collapseButton:setY(math.floor((m.header - buttonSize) / 2))
    self.collapseButton:setWidth(buttonSize)
    self.collapseButton:setHeight(buttonSize)

    -- The save card ---------------------------------------------------------
    local card = { x = m.pad, y = m.header + m.pad, w = inner }
    local cx = card.x + m.cardPad
    local cw = card.w - m.cardPad * 2
    local cy = card.y + m.cardPad

    local previewW = math.floor(m.savePreview * 0.62)
    self.saveWell = { x = cx, y = cy, w = cw, h = m.savePreview }
    self.savePreview:setX(cx + math.floor((cw - previewW) / 2))
    self.savePreview:setY(cy)
    self.savePreview:setWidth(previewW)
    self.savePreview:setHeight(m.savePreview)
    cy = cy + m.savePreview + m.gap

    -- One under the other, full width. Side by side each had about 75 px for
    -- its label, and "Cintura e barra rapida" is not 75 px in any font.
    self.bagsToggle:setX(cx)
    self.bagsToggle:setY(cy)
    self.bagsToggle:setWidth(cw)
    self.bagsToggle:setHeight(m.toggleH)
    cy = cy + m.toggleH + m.gap

    self.hotbarToggle:setX(cx)
    self.hotbarToggle:setY(cy)
    self.hotbarToggle:setWidth(cw)
    self.hotbarToggle:setHeight(m.toggleH)
    self.hotbarToggle.neqTip = getText(hotbarLockedOff()
        and "UI_NEQ_wardrobe_hotbar_locked" or "UI_NEQ_wardrobe_hotbar_tip")
    cy = cy + m.toggleH + m.gap

    -- Name, symbol, save: the two squares are as tall as the field.
    local square = m.fieldH
    self.saveButton:setX(cx + cw - square)
    self.saveButton:setY(cy)
    self.saveButton:setWidth(square)
    self.saveButton:setHeight(square)
    self.symbolButton:setX(cx + cw - square * 2 - m.gap)
    self.symbolButton:setY(cy)
    self.symbolButton:setWidth(square)
    self.symbolButton:setHeight(square)
    self:placeTextField(self.nameEntry, cx, cy, self.symbolButton:getX() - m.gap - cx, m.fieldH)
    cy = cy + m.fieldH + m.cardPad

    card.h = cy - card.y
    self.saveCard = card

    -- The list --------------------------------------------------------------
    self.listHeaderY = card.y + card.h + m.section
    self.listTop = self.listHeaderY + m.fontH + m.gap

    local contentH = 0
    for index in ipairs(self.rows) do
        contentH = contentH + self:rowHeight(index, m) + m.gap
    end
    if #self.rows == 0 then contentH = m.rowH + m.gap end
    contentH = contentH - m.gap
    self.contentH = contentH

    local screenH = getCore():getScreenHeight()
    local maxView = math.max(m.rowH * 2, screenH - 2 * m.pad - self.listTop - m.pad)
    self.viewH = math.min(contentH, maxView)
    self:clampScroll()

    -- Below the list, room for the corner grip: with only the padding it sat on
    -- the last row, right where its delete button is.
    self:setHeight(self.listTop + self.viewH + math.max(m.pad, m.grip - 2))

    if self.grip then
        self.grip:setWidth(m.grip)
        self.grip:setHeight(m.grip)
        self.grip:setX(self.width - m.grip)
        self.grip:setY(self.height - m.grip)
    end

    self:placeRows()
    self:clampToScreen()
end

function NEQ_Wardrobe:clampScroll()
    local maxScroll = math.max(0, (self.contentH or 0) - (self.viewH or 0))
    self.scrollY = math.max(0, math.min(self.scrollY or 0, maxScroll))
end

--- Where row `index` starts inside the list, before scrolling.
function NEQ_Wardrobe:rowOffset(index, m)
    local y = 0
    for i = 1, index - 1 do y = y + self:rowHeight(i, m) + m.gap end
    return y
end

--- Is the band [top, top + h) wholly inside the visible part of the list?
function NEQ_Wardrobe:inView(top, h)
    return top >= self.listTop and top + h <= self.listTop + self.viewH
end

--- Puts every child that lives in the list where the scroll says, and hides
--- the ones that would stick out of it: the list is clipped when drawn, a
--- child is not, and a button hanging over the save card could be clicked.
function NEQ_Wardrobe:placeRows()
    local m = self:metrics()
    local rowButton = m.rowButton
    local rowButtonY = math.floor((m.rowH - rowButton) / 2)
    local y = self.listTop - self.scrollY

    for index, row in ipairs(self.rows) do
        row.y = y
        local renaming = self.renamingIndex == index
        local headerShown = self:inView(y, m.rowH)

        row.symbolButton:setX(m.pad + m.rowInset)
        row.symbolButton:setY(y + math.floor((m.rowH - m.symbol) / 2))
        row.symbolButton:setWidth(m.symbol)
        row.symbolButton:setHeight(m.symbol)
        row.symbolButton:setVisible(headerShown)

        -- **Dentro** la riga, con lo stesso margine del simbolo a sinistra:
        -- a filo del bordo i tasti si appoggiavano sull'angolo stondato.
        local right = m.width - m.pad - m.rowInset - math.floor(rowButtonY / 2)

        -- While a row is being renamed its delete button steps aside: one stray
        -- click next to the field should not throw the outfit away.
        row.deleteButton:setVisible(headerShown and not renaming)
        row.deleteButton:setX(right - rowButton)
        row.deleteButton:setY(y + rowButtonY)
        row.deleteButton:setWidth(rowButton)
        row.deleteButton:setHeight(rowButton)

        -- The rename button becomes the tick that confirms it, in the same
        -- place: one control, two states.
        row.renameButton:setVisible(headerShown)
        row.renameButton:setX(renaming and (right - rowButton) or (right - rowButton * 2 - m.gap))
        row.renameButton:setY(y + rowButtonY)
        row.renameButton:setWidth(rowButton)
        row.renameButton:setHeight(rowButton)

        row.textX = m.pad + m.rowInset + m.symbol + m.gap + math.floor(m.rowInset / 2)
        row.textLimit = row.renameButton:getX() - m.gap

        if self.expandedIndex == index then
            local bodyTop = y + m.rowH + m.gap
            local previewW = math.floor(m.slotPreview * 0.62)
            self.slotWell = { x = m.pad + m.cardPad, y = bodyTop,
                w = m.width - m.pad * 2 - m.cardPad * 2, h = m.slotPreview }
            self.slotPreview:setX(math.floor((m.width - previewW) / 2))
            self.slotPreview:setY(bodyTop)
            self.slotPreview:setWidth(previewW)
            self.slotPreview:setHeight(m.slotPreview)
            self.slotPreview:setVisible(self:inView(bodyTop, m.slotPreview))

            -- The wear button keeps its width; the three squares, as tall as
            -- it, line up on its right, and the group is centred.
            local square = m.wearH
            local squares = #self.openRowButtons * (square + m.gap)
            local wearW = math.min(self.slotWell.w - squares,
                math.max(r(120 * self.scale), previewW + m.rowH))
            local groupX = self.slotWell.x + math.floor((self.slotWell.w - wearW - squares) / 2)
            local wearY = bodyTop + m.slotPreview + m.gap
            local shown = self:inView(wearY, m.wearH)
            self.wearButton:setX(groupX)
            self.wearButton:setY(wearY)
            self.wearButton:setWidth(wearW)
            self.wearButton:setHeight(m.wearH)
            self.wearButton:setVisible(shown)

            for i, button in ipairs(self.openRowButtons) do
                button:setX(groupX + wearW + m.gap + (i - 1) * (square + m.gap))
                button:setY(wearY)
                button:setWidth(square)
                button:setHeight(square)
                button:setVisible(shown)
            end
        end

        y = y + self:rowHeight(index, m) + m.gap
    end

    if self.renameEntry and self.renamingIndex then
        local row = self.rows[self.renamingIndex]
        if row then
            local margin = math.max(3, math.floor(m.rowH * 0.14))
            local left = row.textX - math.floor(m.gap / 2)
            local right = row.renameButton:getX() - m.gap
            self:placeTextField(self.renameEntry, left, row.y + margin, right - left, m.rowH - margin * 2)
            self.renameEntry:setVisible(self:inView(row.y, m.rowH))
        end
    end
end

function NEQ_Wardrobe:clampToScreen()
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setX(math.max(0, math.min(self:getX(), screenW - self:getWidth())))
    self:setY(math.max(0, math.min(self:getY(), screenH - self:getHeight())))
end

--- Scrolls just enough for the open row to be wholly visible, header first.
function NEQ_Wardrobe:revealExpanded()
    if not self.expandedIndex then return end
    local m = self:metrics()
    local top = self:rowOffset(self.expandedIndex, m)
    local bottom = top + self:rowHeight(self.expandedIndex, m)
    if bottom - self.scrollY > self.viewH then self.scrollY = bottom - self.viewH end
    if top < self.scrollY then self.scrollY = top end
    self:clampScroll()
    self:placeRows()
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
--- The header's icon and title, after the collapse arrow.
function NEQ_Wardrobe:drawHeaderTitle(m)
    local pad = m.pad
    local c = Style.text

    -- Stessa regola dell'icona del pannello equipaggiamento.
    local iconSize = Style.headerIconSize(m.header)
    local iconY = math.floor((m.header - iconSize) / 2)
    local icon = Style.tex("wardrobe")
    local x = self.collapseButton:getX() + self.collapseButton:getWidth() + pad
    if icon then
        self:drawTextureScaled(icon, x, iconY, iconSize, iconSize, 1, 0.9, 0.9, 0.9)
        x = x + iconSize + pad
    end
    local titleH = getTextManager():getFontHeight(FONT_TITLE)
    local title = Style.fitText(getText("UI_NEQ_wardrobe_title"),
        self.closeButton:getX() - x - pad, FONT_TITLE)
    self:drawText(title, x, math.floor((m.header - titleH) / 2), c.r, c.g, c.b, 1, FONT_TITLE)
end

function NEQ_Wardrobe:prerender()
    local m = self:metrics()
    self:updateReplaceArm()

    -- Rolled up: the header and nothing else. The engine already skips the
    -- children below it; this is the window's own drawing.
    if not Collapse.isBodyVisible(self) then
        Style.drawWindow(self, 0, 0, self.width, m.header, m.header)
        self:drawHeaderTitle(m)
        return
    end

    Style.drawWindow(self, 0, 0, self.width, self.height, m.header)
    self:drawHeaderTitle(m)
    self:updateTabButtons()

    local pad = m.pad

    -- The save card: the box, then a soft stage for the survivor to stand on.
    local card = self.saveCard
    if card then
        Style.drawCard(self, card.x, card.y, card.w, card.h, 0.11, 0.92, Style.CARD_LINE, 0.9)
        local well = self.saveWell
        Style.drawCard(self, well.x, well.y, well.w, well.h, 0.07, 0.55)
    end

    Style.drawSectionHeader(self, getText("UI_NEQ_wardrobe_load"),
        pad, self.listHeaderY, self.width - pad * 2, FONT_ROW)

    local outfits = self:outfits()
    if #outfits == 0 then
        local d = Style.dim
        local text = getText("UI_NEQ_wardrobe_empty")
        local tw = getTextManager():MeasureStringX(FONT_ROW, text)
        self:drawText(text, math.floor((self.width - tw) / 2),
            self.listTop + math.floor((m.rowH - m.fontH) / 2), d.r, d.g, d.b, 1, FONT_ROW)
        return
    end

    self:setStencilRect(0, self.listTop, self.width, self.viewH)

    local hovered = self:rowAt(self:getMouseX(), self:getMouseY())
    for i, row in ipairs(self.rows) do
        local outfit = outfits[i]
        local h = self:rowHeight(i, m)
        if outfit and row.y + h > self.listTop and row.y < self.listTop + self.viewH then
            self:drawOutfitRow(row, outfit, i, h, hovered == i, m)
        end
    end

    self:clearStencilRect()

    if self.contentH > self.viewH then
        local frac = self.viewH / self.contentH
        local barH = math.max(18, math.floor(self.viewH * frac))
        local at = self.scrollY / math.max(1, self.contentH - self.viewH)
        local bx = self.width - math.max(3, math.floor(pad / 2)) - 1
        self:drawRect(bx, self.listTop, 2, self.viewH, 0.35, 0.30, 0.30, 0.32)
        local a = Style.accent
        self:drawRect(bx, self.listTop + math.floor((self.viewH - barH) * at), 2, barH, 0.9, a.r, a.g, a.b)
    end
end

function NEQ_Wardrobe:drawOutfitRow(row, outfit, index, h, hover, m)
    local open = self.expandedIndex == index
    local x, w = m.pad, self.width - m.pad * 2
    Style.drawRow(self, x, row.y, w, h, hover, open)

    local c = Style.text
    local textY = row.y + math.floor((m.rowH - m.fontH) / 2)

    if self.renamingIndex ~= index then
        -- A saved outfit always has a name; the fallback is for one written by
        -- an older build, and must not be suggestName - that walks the whole
        -- list, and this runs every frame.
        local name = outfit.name or getText("UI_NEQ_outfit_default_name")

        local count = tostring(Outfit.count(outfit, Outfit.skipsHotbar(outfit, State.wardrobeNoHotbar)))
        local cw = getTextManager():MeasureStringX(FONT_ROW, count)
        local label = Style.fitText(name, row.textLimit - row.textX - cw - 12, FONT_ROW)
        self:drawText(label, row.textX, textY, c.r, c.g, c.b, 1, FONT_ROW)

        local d = Style.dim
        self:drawText(count, row.textLimit - cw - 4, textY, d.r, d.g, d.b, 1, FONT_ROW)
    end

    if not open then return end

    -- The open part: a hairline under the header, the stage for the preview,
    -- and what the outfit leaves out, under the wear button's shoulders.
    local s = Style.separator
    self:drawRect(x + m.cardPad, row.y + m.rowH, w - m.cardPad * 2, 1, 0.5, s.r, s.g, s.b)

    local well = self.slotWell
    if well then
        Style.drawCard(self, well.x, well.y, well.w, well.h, 0.07, 0.55)

        local notes = {}
        if outfit.noBags then notes[#notes + 1] = Style.tex("bagClosed") end
        if Outfit.skipsHotbar(outfit, State.wardrobeNoHotbar) then notes[#notes + 1] = Style.tex("belt") end
        -- Small struck-through icons in the stage's corner: "this outfit does
        -- not handle bags / the belt".
        local size = math.max(12, math.floor(m.rowButton * 0.9))
        local nx = well.x + well.w - size - m.gap
        local ny = well.y + m.gap
        for _, tex in ipairs(notes) do
            if tex then
                self:drawTextureScaled(tex, nx, ny, size, size, 0.55, 0.9, 0.9, 0.9)
                local cr = Style.close
                self:drawRect(nx - 1, ny + math.floor(size / 2), size + 2, 2, 0.9, cr.r, cr.g, cr.b)
                ny = ny + size + m.gap
            end
        end
    end
end

function NEQ_Wardrobe:paintToggle(button, icon, label, checked, disabled)
    local hover = button:isMouseOver() and not disabled
    local fill = hover and 0.20 or 0.15
    local line, lineAlpha = Style.CARD_LINE, 0.9
    if hover then line, lineAlpha = Style.accent, 0.85 end
    Style.drawCard(button, 0, 0, button.width, button.height, fill, disabled and 0.5 or 0.9, line, lineAlpha)

    local h = button.height
    local inset = math.max(4, math.floor(h * 0.2))
    local check = h - inset * 2
    Style.drawCheck(button, inset, inset, check, checked, hover, disabled)

    local x = inset + check + math.floor(inset * 0.8)
    local iconSize = math.floor(h * 0.62)
    local alpha = disabled and 0.4 or 1
    if icon then
        button:drawTextureScaled(icon, x, math.floor((h - iconSize) / 2), iconSize, iconSize,
            alpha, 0.9, 0.9, 0.9)
        x = x + iconSize + math.floor(inset * 0.6)
    end

    local fontH = getTextManager():getFontHeight(FONT_ROW)
    local text = Style.fitText(label, button.width - x - inset, FONT_ROW)
    local c = disabled and Style.dim or Style.text
    button:drawText(text, x, math.floor((h - fontH) / 2), c.r, c.g, c.b, alpha, FONT_ROW)
end

--- The shirt button: a wide Neat button, the shirt and "Wear" centred as one
--- group - two separate centres drift apart when the window is resized.
function NEQ_Wardrobe:paintWearButton(button)
    local state = "default"
    if button.pressed then state = "pressed"
    elseif button:isMouseOver() then state = "hover" end
    Style.drawWideButton(button, 0, 0, button.width, button.height, state)

    local tm = getTextManager()
    local iconSize = math.floor(button.height * 0.66)
    local gap = math.floor(iconSize * 0.4)
    local label = Style.fitText(getText("UI_NEQ_wardrobe_wear"),
        button.width - iconSize - gap - 16, FONT_ROW)
    local textW = tm:MeasureStringX(FONT_ROW, label)
    local groupX = math.floor((button.width - (iconSize + gap + textW)) / 2)

    local icon = Style.tex("equipAll")
    if icon then
        button:drawTextureScaled(icon, groupX, math.floor((button.height - iconSize) / 2),
            iconSize, iconSize, 1, 0.95, 0.95, 0.95)
    end
    local c = Style.text
    button:drawText(label, groupX + iconSize + gap,
        math.floor((button.height - tm:getFontHeight(FONT_ROW)) / 2), c.r, c.g, c.b, 1, FONT_ROW)
end

--- Neat labels for the small buttons, drawn after every child so nothing
--- covers them. Same reason the equipment panel does it from its own render.
function NEQ_Wardrobe:render()
    local candidates = { self.collapseButton, self.closeButton }
    if Collapse.isBodyVisible(self) then
        for _, button in ipairs({ self.bagsToggle, self.hotbarToggle, self.symbolButton,
            self.saveButton }) do
            candidates[#candidates + 1] = button
        end
        for _, row in ipairs(self.rows) do
            candidates[#candidates + 1] = row.symbolButton
            candidates[#candidates + 1] = row.renameButton
            candidates[#candidates + 1] = row.deleteButton
        end
        for _, button in ipairs(self.openRowButtons) do candidates[#candidates + 1] = button end
    end

    for _, button in ipairs(candidates) do
        if button and button.neqTip and button:isVisible() and button:isMouseOver() then
            Style.drawButtonTip(self, button.neqTip,
                button:getX() + button:getWidth() / 2,
                button:getY() + button:getHeight() + 3, true, 2, self.width - 2)
            return
        end
    end
end

--- The row under a point of the window, or nil. Only inside the visible list.
function NEQ_Wardrobe:rowAt(x, y)
    if not self.listTop or y < self.listTop or y >= self.listTop + (self.viewH or 0) then return nil end
    if x < 0 or x >= self.width then return nil end
    local m = self:metrics()
    for i, row in ipairs(self.rows) do
        if row.y and y >= row.y and y < row.y + self:rowHeight(i, m) then return i end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The save card
-- ---------------------------------------------------------------------------
--- What would be saved right now, with the two ticks applied.
function NEQ_Wardrobe:captureCurrent(name)
    local noHotbar = hotbarLockedOff() or not self.saveHotbar
    return Outfit.capture(self.char, self.playerNum, name, not self.saveBags, noHotbar)
end

function NEQ_Wardrobe:refreshSavePreview()
    if self.savePreview then
        self.savePreview:setOutfit(self:captureCurrent(nil))
    end
end

function NEQ_Wardrobe:onToggleBags()
    self.saveBags = not self.saveBags
    Config.set("wardrobe_save_bags", self.saveBags)
    self:refreshSavePreview()
    getSoundManager():playUISound("UISelectListItem")
end

function NEQ_Wardrobe:onToggleHotbar()
    if hotbarLockedOff() then return end
    self.saveHotbar = not self.saveHotbar
    Config.set("wardrobe_save_hotbar", self.saveHotbar)
    self:refreshSavePreview()
    getSoundManager():playUISound("UISelectListItem")
end

function NEQ_Wardrobe:onPickNewSymbol(button)
    self.picker:open(self.symbolButton, self.newSymbol, self.scale, function(id)
        self.newSymbol = id
    end)
end

--- The name the save card proposes follows the list - "Outfit 3" after two -
--- until the player types their own.
function NEQ_Wardrobe:refreshSuggestion()
    local current = self.nameEntry:getInternalText()
    if current ~= "" and current ~= self.lastSuggestion then return end
    local suggestion = Outfit.suggestName(self.char)
    self.nameEntry:setText(suggestion)
    self.lastSuggestion = suggestion
end

function NEQ_Wardrobe:onSave()
    if self.renamingIndex then self:commitRename() end

    local name = self.nameEntry:getInternalText() or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = Outfit.suggestName(self.char) end

    local outfit = self:captureCurrent(name)
    outfit.symbol = self.newSymbol

    local saved, reason = Outfit.save(self.char, outfit)
    if not saved then
        local key = (reason == "full") and "UI_NEQ_wardrobe_full" or "UI_NEQ_wardrobe_nothing"
        self.char:setHaloNote(getText(key), 220, 180, 90, 300)
        return
    end

    getSoundManager():playUISound("UIActivateButton")

    -- The new outfit opens at the bottom of the list, in view: that is the
    -- proof it was saved, and what it looks like.
    self.newSymbol = nil
    self.renamingIndex = nil
    self.expandedIndex = #self:outfits()
    self.lastSuggestion = nil
    self.nameEntry:setText("")
    self:refreshSuggestion()
    self.nameEntry:unfocus()
    self:rebuild()
    self:revealExpanded()
end

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------
--- Hands the open row's outfit to the preview, and shows or hides the two
--- children that belong to it.
function NEQ_Wardrobe:showExpanded()
    local outfit = self.expandedIndex and self:outfits()[self.expandedIndex]
    if outfit then
        self.slotPreview:setOutfit(outfit)
    else
        self.expandedIndex = nil
        self.slotPreview:setVisible(false)
        self.wearButton:setVisible(false)
        for _, button in ipairs(self.openRowButtons) do button:setVisible(false) end
        self.slotWell = nil
    end
    -- The confirmation belongs to the row it was asked on.
    if self.replaceArmed and self.replaceArmed.index ~= self.expandedIndex then
        self:disarmReplace()
    end
end

function NEQ_Wardrobe:toggleExpanded(index)
    if self.expandedIndex == index then
        self.expandedIndex = nil
    else
        self.expandedIndex = index
    end
    getSoundManager():playUISound("UISelectListItem")
    self:showExpanded()
    self:layout()
    self:revealExpanded()
end

function NEQ_Wardrobe:onPickRowSymbol(index)
    local row = self.rows[index]
    local outfit = self:outfits()[index]
    if not row or not outfit then return end
    self.picker:open(row.symbolButton, outfit.symbol, self.scale, function(id)
        Outfit.setSymbol(self.char, index, id)
    end)
end

--- Wearing does not close the window: picking an outfit is usually several
--- tries, and a list that disappears on the first click has to be reopened
--- every time.
function NEQ_Wardrobe:onWear(index)
    local outfit = self:outfits()[index]
    if not outfit then return end

    local started, missing = Dresser.wear(self.char, self.playerNum, outfit)

    if #missing > 0 then
        -- Naming the first one is more use than a count: it is usually the
        -- thing you forgot to bring.
        self.char:setHaloNote(
            getText("UI_NEQ_wardrobe_missing", tostring(#missing), missing[1]),
            220, 180, 90, 400)
    elseif not started then
        self.char:setHaloNote(getText("UI_NEQ_wardrobe_already"), 200, 200, 200, 250)
    end

    if started then getSoundManager():playUISound("UIActivateButton") end
end

function NEQ_Wardrobe:onWearExpanded()
    if self.expandedIndex then self:onWear(self.expandedIndex) end
end

--- The outfit's protection or warmth, in a window of its own that follows the
--- open outfit. The button already lit closes it.
function NEQ_Wardrobe:onShowStats(mode)
    if not self.expandedIndex then return end
    if not self.statsPanel then
        self.statsPanel = NEQ_OutfitStatsPanel:new(self)
        self.statsPanel:initialise()
    end
    self.statsPanel:toggle(mode)
    getSoundManager():playUISound("UISelectListItem")
end

--- Which of the two the stats window is showing, or nil.
function NEQ_Wardrobe:shownStats()
    local panel = self.statsPanel
    if panel and panel:isShown() then return panel.mode end
    return nil
end

--- The two buttons light up while their window is up. Compared first: this
--- runs every frame, the retint only when it changes.
function NEQ_Wardrobe:updateTabButtons()
    local shown = self:shownStats()
    if shown == self.lastShownTab then return end
    self.lastShownTab = shown
    Style.setButtonActive(self.protectionButton, shown == "protection" and Style.accent or nil)
    Style.setButtonActive(self.temperatureButton, shown == "temperature" and Style.accent or nil)
end

--[[ Replace: what you have on now becomes this outfit, under its name and
    symbol, in its place in the list. It is captured with the outfit's own
    choices - an outfit saved without bags stays without bags - rather than
    the save card's ticks, which are about the next new outfit.

    It overwrites a saved outfit, so it takes two clicks: the first turns the
    button into a green tick for a few seconds, the second replaces. The same
    shape as rename, whose pencil becomes the tick that confirms.
]]
function NEQ_Wardrobe:onReplaceExpanded()
    local index = self.expandedIndex
    local outfit = index and self:outfits()[index]
    if not outfit then return end

    if not self.replaceArmed or self.replaceArmed.index ~= index then
        self:armReplace(index)
        getSoundManager():playUISound("UISelectListItem")
        return
    end
    self:disarmReplace()

    local noHotbar = hotbarLockedOff() or outfit.noHotbar == true
    local current = Outfit.capture(self.char, self.playerNum, outfit.name,
        outfit.noBags == true, noHotbar)
    if not Outfit.replace(self.char, index, current) then
        self.char:setHaloNote(getText("UI_NEQ_wardrobe_nothing"), 220, 180, 90, 300)
        return
    end

    getSoundManager():playUISound("UIActivateButton")
    self.char:setHaloNote(getText("UI_NEQ_wardrobe_replaced"), 200, 200, 200, 250)
    self:showExpanded()
    self:layout()
end

function NEQ_Wardrobe:armReplace(index)
    self.replaceArmed = { index = index, at = getTimestampMs() }
    Style.setButtonIcon(self.replaceButton, Style.tex("confirm"))
    Style.setButtonActive(self.replaceButton, Style.selection)
    self.replaceButton.neqTip = getText("UI_NEQ_wardrobe_replace_confirm")
end

function NEQ_Wardrobe:disarmReplace()
    self.replaceArmed = nil
    Style.setButtonIcon(self.replaceButton, Style.tex("swap"))
    Style.setButtonActive(self.replaceButton, nil)
    self.replaceButton.neqTip = getText("UI_NEQ_wardrobe_replace")
end

--- The tick goes back to the swap icon when nobody confirms in time.
function NEQ_Wardrobe:updateReplaceArm()
    local armed = self.replaceArmed
    if armed and getTimestampMs() - armed.at > REPLACE_CONFIRM_MS then
        self:disarmReplace()
    end
end

function NEQ_Wardrobe:onDelete(index)
    if not Outfit.delete(self.char, index) then return end

    self.renamingIndex = nil
    if self.expandedIndex == index then
        self.expandedIndex = nil
    elseif self.expandedIndex and self.expandedIndex > index then
        self.expandedIndex = self.expandedIndex - 1
    end
    if self.picker then self.picker:close() end
    self:rebuild()
    self:refreshSuggestion()
end

--- Clicking rename turns that row into an editable one: a Neat field where the
--- name was, and the rename button becomes a tick. Enter confirms too.
function NEQ_Wardrobe:onRename(index)
    if self.renamingIndex == index then
        self:commitRename()
        return
    end
    if self.renamingIndex then self:commitRename() end

    local outfit = self:outfits()[index]
    if not outfit then return end

    self.renamingIndex = index
    self:refreshRowIcons()

    -- Nasce con misure qualsiasi: e' placeRows a metterlo al suo posto, ed e'
    -- l'unico che sa dove sta la riga. Due conti per la stessa cosa erano gia'
    -- finiti con il campo fuori dallo slot.
    self.renameEntry = self:newTextField(outfit.name or "")
    self.renameEntry.onCommandEntered = function() self:commitRename() end
    self:layout()
    self.renameEntry:focus()
end

--- The rename button shows a pencil normally and a tick while that row is being
--- edited, so confirming is where renaming was.
function NEQ_Wardrobe:refreshRowIcons()
    for index, row in ipairs(self.rows) do
        local renaming = self.renamingIndex == index
        Style.setButtonIcon(row.renameButton, Style.tex(renaming and "confirm" or "rename"))
        Style.setButtonActive(row.renameButton, renaming and Style.selection or nil)
        row.renameButton.neqTip = getText(renaming and "UI_NEQ_wardrobe_confirm"
            or "UI_NEQ_wardrobe_rename")
    end
end

function NEQ_Wardrobe:commitRename()
    local index = self.renamingIndex
    if index and self.renameEntry then
        local name = self.renameEntry:getInternalText()
        if name and name ~= "" then Outfit.rename(self.char, index, name) end
    end
    self.renamingIndex = nil
    self:rebuild()
    self:refreshSuggestion()
end

-- ---------------------------------------------------------------------------
-- Collapse
-- ---------------------------------------------------------------------------
function NEQ_Wardrobe:onClickCollapse()
    Collapse.onClickCollapse(self)
    self:refreshCollapseButton()
end

--- The arrow says what a click would do: roll up when the window is pinned
--- open, keep it open when the roll-up is armed.
function NEQ_Wardrobe:refreshCollapseButton()
    Collapse.refreshButton(self)
    self.collapseButton.neqTip = getText(Collapse.isCollapsed(self)
        and "UI_NEQ_wardrobe_pin" or "UI_NEQ_wardrobe_collapse")
end

--- Called by NEQ_Collapse. What lives below the header cannot be reached
--- while it is rolled up: a rename is committed rather than left half-typed,
--- and the symbol sheet - a window of its own - goes away with the rest.
function NEQ_Wardrobe:onCollapseBody(shown)
    if shown then return end
    if self.picker then self.picker:close() end
    if self.renamingIndex then self:commitRename() end
    if self.nameEntry then self.nameEntry:unfocus() end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
function NEQ_Wardrobe:setVisible(visible)
    ISPanel.setVisible(self, visible)
    if visible then
        openWardrobes[self] = true
        -- Whatever changed while the window was shut - clothes, the options -
        -- is read again now.
        if self.nameEntry then
            self:refreshSuggestion()
            self:refreshSavePreview()
        end
    else
        openWardrobes[self] = nil
        if self.picker then self.picker:close() end
        if self.statsPanel and self.statsPanel:isShown() then self.statsPanel:close() end
    end
end

function NEQ_Wardrobe:onClose()
    if self.renamingIndex then self:commitRename() end
    self:setVisible(false)
    self:removeFromUIManager()
end

--- Clothes changed: the save card shows what you have on, so it follows.
local function onClothingUpdated(character)
    for wardrobe in pairs(openWardrobes) do
        if wardrobe.char == character and wardrobe:isVisible() then
            wardrobe:refreshSavePreview()
        end
    end
end
Events.OnClothingUpdated.Add(onClothingUpdated)

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_Wardrobe:onMouseDown(x, y)
    self:bringToTop()

    if y < self:headerHeight() then
        self.moving = true
        self:setCapture(true)
        return true
    end

    -- A click on a row's header line opens or closes it; the buttons on it
    -- are children and get the click first.
    if self.renamingIndex == nil then
        local index = self:rowAt(x, y)
        local row = index and self.rows[index]
        if row and y < row.y + self:metrics().rowH then
            self:toggleExpanded(index)
            return true
        end
    end

    return true
end

function NEQ_Wardrobe:onMouseWheel(del)
    if not self.contentH or self.contentH <= self.viewH then return false end
    local m = self:metrics()
    self.scrollY = self.scrollY + del * (m.rowH + m.gap)
    self:clampScroll()
    self:placeRows()
    return true
end

--- Dragging by the header. Both mouse handlers come here rather than one
--- calling the other: NEQ_Collapse wraps each of them, and the inside one
--- resets the timer the outside one counts.
function NEQ_Wardrobe:dragBy(dx, dy)
    if not self.moving then return end
    self:setX(self:getX() + dx)
    self:setY(self:getY() + dy)
end

function NEQ_Wardrobe:onMouseMove(dx, dy)        self:dragBy(dx, dy) end
function NEQ_Wardrobe:onMouseMoveOutside(dx, dy) self:dragBy(dx, dy) end

function NEQ_Wardrobe:stopMoving()
    if not self.moving then return end
    self.moving = false
    self:setCapture(false)
    self:clampToScreen()
end

function NEQ_Wardrobe:onMouseUp(x, y)        self:stopMoving() return true end
function NEQ_Wardrobe:onMouseUpOutside(x, y) self:stopMoving() end

--- Committing on click-away rather than swallowing the edit: losing a typed
--- name to a stray click is a small betrayal.
function NEQ_Wardrobe:onMouseDownOutside(x, y)
    if self.renamingIndex then self:commitRename() end
end

return NEQ_Wardrobe

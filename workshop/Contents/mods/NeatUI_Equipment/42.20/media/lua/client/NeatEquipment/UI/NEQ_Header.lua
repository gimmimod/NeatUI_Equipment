--[[ ============================================================================
    NEQ_Header - the panel's title bar.

        [bag] Equipment            [hanger] [shirt] [eye] [chain]

    The strip itself is painted by NEQ_Panel as part of the window (header and
    body have to be drawn as one piece or the rounded corners do not line up),
    so this element is transparent: it owns the icon, the title, the four
    buttons and the drag gesture, nothing else.

    There is no close button. The figure on the side of the inventory already opens
    and closes the panel, and a second control doing the same job in a different
    place is one more thing that can disagree with the first.

    Tooltips are reported, not drawn: hoveredTip() hands the panel what to say
    and where, and the panel draws it in its own render pass. A button drawing
    its own would be covered by the body, and ISButton:setTooltip would put a
    vanilla square popup in the middle of a Neat window.

    Two rules keep the bar from ever looking broken:

      * the title is drawn only when it fits whole. At the docked width there is
        no room, and half a word running into a button is worse than no word.
      * requiredWidth() is what the buttons actually need, and NEQ_Panel feeds
        it to the resize grip, so the panel cannot be dragged narrow enough for
        the buttons to reach the title icon.

    Colour follows the Neat rule: orange means "this is currently on" - the eye
    while equipped items are hidden, the chain while the panel is attached, the
    hanger while the wardrobe window is up. The shirt never lights: taking your
    clothes off is a thing you do, not a mode you are in.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local Style  = require("NeatEquipment/NEQ_Style")
local Tetris = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")

local FONT = UIFont.Small

---@class NEQ_Header : ISPanel
local NEQ_Header = ISPanel:derive("NEQ_Header")

function NEQ_Header:new(x, y, width, height, panel)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.panel = panel
    o.moving = false

    return o
end

function NEQ_Header:createChildren()
    local size = self:buttonSize()
    local y = math.floor((self.height - size) / 2)

    self.dockButton = Style.newSquareButton(0, y, size, Style.tex("dock"),
        self, self.onToggleDock)
    self:addChild(self.dockButton)

    -- Niente occhio sotto Inventory Tetris: l'elenco da cui toglierebbe le cose
    -- indossate non esiste piu'. buttonList salta i nil, quindi i tre rimasti si
    -- ridispongono da soli. Un tasto che non fa niente e' peggio di un tasto che
    -- non c'e'.
    if Tetris.hasEquippedList() then
        self.eyeButton = Style.newSquareButton(0, y, size, Style.tex("eyeShow"),
            self, self.onToggleHideEquipped)
        self:addChild(self.eyeButton)
    end

    self.stripButton = Style.newSquareButton(0, y, size, Style.tex("unequipAll"),
        self, self.onToggleStrip)
    self:addChild(self.stripButton)

    self.wardrobeButton = Style.newSquareButton(0, y, size, Style.tex("wardrobe"),
        self, self.onWardrobe)
    self:addChild(self.wardrobeButton)

    self:refreshButtons()
    self:layout()
end

-- ---------------------------------------------------------------------------
-- Metrics
-- ---------------------------------------------------------------------------
function NEQ_Header:buttonSize()
    return Style.headerButtonSize(self.height)
end

function NEQ_Header:padding()
    return Style.headerPadding(self.height)
end

--- Tighter than the outer padding: the four buttons should read as one group
--- pushed into the corner, not as four separate controls.
function NEQ_Header:buttonGap()
    return Style.headerGap(self.height)
end

function NEQ_Header:iconSize()
    return Style.headerIconSize(self.height)
end

--- Buttons in the order they appear, right to left. Anything nil is skipped, so
--- the maths below never has to know how many there are.
function NEQ_Header:buttonList()
    -- Composta a mano e non come tabella letterale: un buco in mezzo -
    -- l'occhio, che sotto Inventory Tetris non viene creato - fermerebbe ipairs
    -- al primo nil, e i tasti dopo di lui resterebbero senza posizione ne'
    -- misura, cioe' invisibili in un angolo.
    local list = {}
    local all = { self.dockButton, self.eyeButton, self.stripButton, self.wardrobeButton }
    for i = 1, 4 do
        if all[i] then list[#list + 1] = all[i] end
    end
    return list
end

--- The narrowest the panel may be: the title icon, then every button. Below this
--- the buttons start climbing over the icon, which is what the smallest resize
--- used to look like.
---
--- Not called minimumWidth: ISUIElement:new writes minimumWidth = 0 onto every
--- element it builds, so a method of that name is shadowed by a number on this
--- very instance and calling it is an error. See the note in NEQ_Grip.
function NEQ_Header:requiredWidth()
    local size = self:buttonSize()
    local pad = self:padding()
    local gap = self:buttonGap()

    local count = 0
    for _, button in ipairs(self:buttonList()) do
        if button then count = count + 1 end
    end
    if count == 0 then count = 4 end

    local _, reserve = self.panel:headerReserve()
    return pad + self:iconSize() + pad + (count * size + (count - 1) * gap) + pad + reserve
end

--- Right to left, so the group always owns the corner however many buttons
--- there are.
function NEQ_Header:layout()
    local size = self:buttonSize()
    local pad = self:padding()
    local gap = self:buttonGap()
    local y = math.floor((self.height - size) / 2)

    -- Il posto del tasto con la figura, quando il pannello e' agganciato: i
    -- tasti si spostano a sinistra se il tasto sta a destra, l'icona del titolo
    -- a destra se sta a sinistra (render).
    local side, reserve = self.panel:headerReserve()
    self.leftReserve = (side == "left") and reserve or 0
    local right = self.width - ((side == "right") and reserve or 0)

    local x = right - pad - size
    local leftmost = right

    for _, button in ipairs(self:buttonList()) do
        if button then
            button:setX(x)
            button:setY(y)
            button:setWidth(size)
            button:setHeight(size)
            leftmost = x
            x = x - size - gap
        end
    end

    self.textLimit = leftmost
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
--- Icons and tints follow the current state; the labels describe the action a
--- click performs rather than the state itself.
function NEQ_Header:refreshButtons()
    local State = self.panel.state

    if self.eyeButton then
        local hidden = State.hideEquipped == true
        Style.setButtonIcon(self.eyeButton, Style.tex(hidden and "eyeHide" or "eyeShow"))
        Style.setButtonActive(self.eyeButton, hidden and Style.accent or nil)
        self.eyeButton.neqTip = getText(hidden and "UI_NEQ_tip_show_equipped"
            or "UI_NEQ_tip_hide_equipped")
    end

    if self.dockButton then
        -- Lit while the link is live, which is what the chain is a picture of.
        local docked = self.panel.docked == true
        Style.setButtonIcon(self.dockButton, Style.tex(docked and "dock" or "undock"))
        Style.setButtonActive(self.dockButton, docked and Style.accent or nil)
        self.dockButton.neqTip = getText(docked and "UI_NEQ_tip_undock" or "UI_NEQ_tip_dock")
    end

    if self.stripButton then
        -- One button, two jobs, and the picture says which: a struck-through
        -- shirt takes everything off, a plain one puts back exactly what came
        -- off. It never lights up - orange is reserved for a setting left
        -- switched on, and this is a thing you do, not a mode you are in.
        local canRestore = self.panel:canRestoreOutfit()
        Style.setButtonIcon(self.stripButton, Style.tex(canRestore and "equipAll" or "unequipAll"))
        Style.setButtonActive(self.stripButton, nil)
        self.stripButton.neqTip = getText(canRestore and "UI_NEQ_equip_all" or "UI_NEQ_unequip_all")
    end

    if self.wardrobeButton then
        -- Lit while the wardrobe window is up: it is a thing that is currently
        -- open, which is exactly what orange means everywhere else here.
        local open = self.panel:isWardrobeOpen()
        Style.setButtonActive(self.wardrobeButton, open and Style.accent or nil)
        self.wardrobeButton.neqTip = getText("UI_NEQ_wardrobe_title")
    end
end

--- What the panel should say, and where. Returned rather than drawn: see the
--- note at the top of the file.
---@return string|nil text, number|nil centreX, number|nil bottomY
function NEQ_Header:hoveredTip()
    for _, button in ipairs(self:buttonList()) do
        if button and button.neqTip and button:isMouseOver() then
            return button.neqTip,
                self.x + button:getX() + button:getWidth() / 2,
                self.y + button:getY() + button:getHeight() + 3
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_Header:render()
    local pad = self:padding()
    local iconSize = self:iconSize()
    local iconY = math.floor((self.height - iconSize) / 2)

    local icon = Style.tex("figure")
    local x = pad + (self.leftReserve or 0)
    if icon then
        self:drawTextureScaled(icon, x, iconY, iconSize, iconSize, 1, 0.9, 0.9, 0.9)
        x = x + iconSize + pad
    end

    -- Whole word or nothing. pad * 2 rather than pad, because a title that only
    -- just clears the first button looks crowded.
    local title = getText("UI_NEQ_title")
    local available = (self.textLimit or self.width) - x - pad * 2
    local tm = getTextManager()
    if available >= tm:MeasureStringX(FONT, title) then
        local c = Style.text
        self:drawText(title, x, math.floor((self.height - tm:getFontHeight(FONT)) / 2),
            c.r, c.g, c.b, 1, FONT)
    end
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
function NEQ_Header:onToggleDock()         self.panel:toggleDocked() end
function NEQ_Header:onToggleHideEquipped() self.panel:toggleHideEquipped() end
function NEQ_Header:onToggleStrip()        self.panel:toggleStrip() end
function NEQ_Header:onWardrobe()           self.panel:openWardrobe() end

-- ---------------------------------------------------------------------------
-- Drag (undocked only - a docked panel follows the inventory instead)
-- ---------------------------------------------------------------------------
function NEQ_Header:canDrag()
    return not self.panel.docked and not self.panel.state.lockPanel
end

function NEQ_Header:onMouseDown(x, y)
    if not self:canDrag() then return false end
    self.moving = true
    self:setCapture(true)
    return true
end

function NEQ_Header:moveBy(dx, dy)
    if not self.moving then return false end
    self.panel:setX(self.panel:getX() + dx)
    self.panel:setY(self.panel:getY() + dy)
    return true
end

function NEQ_Header:onMouseMove(dx, dy)        return self:moveBy(dx, dy) end
function NEQ_Header:onMouseMoveOutside(dx, dy) return self:moveBy(dx, dy) end

function NEQ_Header:stopMoving()
    if not self.moving then return false end
    self.moving = false
    self:setCapture(false)
    self.panel:clampToScreen()
    self.panel:savePosition()
    return true
end

function NEQ_Header:onMouseUp(x, y)        return self:stopMoving() end
function NEQ_Header:onMouseUpOutside(x, y) return self:stopMoving() end

return NEQ_Header

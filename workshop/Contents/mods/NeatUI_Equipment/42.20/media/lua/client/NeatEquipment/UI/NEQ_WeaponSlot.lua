--[[ ============================================================================
    NEQ_WeaponSlot - primary / secondary hand.

    Same Clean HotBar slot shell as everything else, with the vanilla hand
    silhouette showing through when the hand is empty. Dropping a two-handed
    weapon on the primary slot widens it into a second square: releasing on the
    right half equips it with both hands, on the left half with one.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local State          = require("NeatEquipment/NEQ_State")
local Style          = require("NeatEquipment/NEQ_Style")
local Drag           = require("NeatEquipment/NEQ_DragDrop")
local ControllerNode = require("NeatEquipment/NEQ_ControllerNode")
local NEQ_Slot       = require("NeatEquipment/UI/NEQ_Slot")
local Tetris         = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")

---@class NEQ_WeaponSlot : ISPanel
local NEQ_WeaponSlot = ISPanel:derive("NEQ_WeaponSlot")

function NEQ_WeaponSlot:new(body, inventoryPane, playerNum, isSecondary)
    local o = ISPanel:new(0, 0, State.weaponSize, State.weaponSize)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.body = body
    o.inventoryPane = inventoryPane
    o.playerNum = playerNum
    o.player = getSpecificPlayer(playerNum)
    o.isSecondary = isSecondary

    return o
end

function NEQ_WeaponSlot:initialise()
    ISPanel.initialise(self)

    State:addScaleListener(self, NEQ_WeaponSlot.onScaleChanged)
    self:onScaleChanged()

    ControllerNode
        :injectControllerNode(self)
        :setJoypadDownHandler(self.controllerNodeOnJoypadDown)

    self.isController = self.controllerNode:isController(self.player)
end

function NEQ_WeaponSlot:onScaleChanged()
    self:setWidth(State.weaponSize)
    self:setHeight(State.weaponSize)
end

function NEQ_WeaponSlot:getHandItem()
    if self.isSecondary then
        return self.player:getSecondaryHandItem()
    end
    return self.player:getPrimaryHandItem()
end

function NEQ_WeaponSlot:getLabel()
    return getText(self.isSecondary and "UI_NEQ_slot_secondary" or "UI_NEQ_slot_primary")
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
--- The palm that sits inside the circle. Strong enough to name the hand when it
--- is empty, faded back to a watermark once there is an item to read on top.
function NEQ_WeaponSlot:drawHandBackdrop(x, occupied)
    local tex = Style.tex(self.isSecondary and "handSecondary" or "handPrimary")
    if not tex then return end

    local size = State.weaponSize
    local inset = math.max(3, math.floor(size * 0.22))
    Style.drawTextureFitted(self, tex, x + inset, inset,
        size - inset * 2, size - inset * 2,
        occupied and 0.16 or 0.40, 0.85, 0.85, 0.85)
end

function NEQ_WeaponSlot:prerender()
    local size = State.weaponSize
    local item = self:getHandItem()
    local dragged = Drag.getDraggedItem()

    local highlight = nil
    self.draw2hSlot = false

    if dragged then
        if dragged ~= item and self:canAcceptItem(dragged) then
            highlight = item and State.REPLACE_COLOR or State.GOOD_COLOR
        end
        if not self.isSecondary and dragged:isTwoHandWeapon() then
            self.draw2hSlot = true
        end
    end

    -- The two-hand target grows to the right of the primary slot while a
    -- two-handed weapon is in flight, then collapses again.
    self:setWidth(self.draw2hSlot and (size * 2 + State.gapX) or size)
    if self.draw2hSlot then self:bringToTop() end

    local focused = self.controllerNode and self.controllerNode.isFocused
    local hover = (not self.isController) and self:isMouseOver()

    Style.drawSlot(self, 0, 0, size, size, {
        round = true,
        hover = hover or focused,
        hasItem = item ~= nil,
        equipped = item ~= nil,
        highlight = highlight,
        focus = focused and ControllerNode.FOCUS_COLOR or nil,
    })
    self:drawHandBackdrop(0, item ~= nil)

    if self.draw2hSlot then
        local secondX = size + State.gapX
        Style.drawSlot(self, secondX, 0, size, size, {
            round = true,
            hover = true,
            highlight = State.GOOD_COLOR,
        })
        -- The extra circle stands for the other hand, so it wears the other
        -- palm whichever slot it grew out of.
        local tex = Style.tex("handSecondary")
        if tex then
            local inset = math.max(3, math.floor(size * 0.22))
            Style.drawTextureFitted(self, tex, secondX + inset, inset,
                size - inset * 2, size - inset * 2, 0.40, 0.85, 0.85, 0.85)
        end
    end
end

function NEQ_WeaponSlot:render()
    local size = State.weaponSize
    local item = self:getHandItem()

    if item then
        local alpha = (item == Drag.getDraggedItem()) and 0.5 or 1.0
        -- Wider inset than a square slot: a circle has less room in its corners.
        local inset = math.max(3, math.floor(size * 0.2))
        Style.drawItemIcon(self, item, inset, inset,
            size - inset * 2, size - inset * 2, alpha)
    end

    if self:isMouseOver() or (self.controllerNode and self.controllerNode.isFocused) then
        local minX, maxX = nil, nil
        if self.parent then
            minX = -self.x
            maxX = self.parent:getWidth() - self.x
        end
        Style.drawSlotLabel(self, self:getLabel(), size / 2, -2, UIFont.Small, minX, maxX)
        if item then self.body:doTooltipForItem(self, item) end
    end
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------
function NEQ_WeaponSlot:canAcceptItem(item)
    -- Sotto Inventory Tetris i due rifiuti saltano: le mani sono un posto come
    -- un altro dove tenere una cosa. Vedi ModCompatibility/NEQ_InventoryTetris.
    if not Tetris.handsAcceptAnything() then
        if item:getCategory() == "Food" and not item:getScriptItem():isCantEat() then
            return false
        end
        if item:getCategory() == "Clothing" then
            return false
        end
    end
    return self:isHandUsable(item) == true
end

function NEQ_WeaponSlot:isHandUsable(item)
    local playerObj = getSpecificPlayer(self.playerNum)
    local damage = playerObj:getBodyDamage()
    local hand = self.isSecondary and damage:getBodyPart(BodyPartType.Hand_L)
        or damage:getBodyPart(BodyPartType.Hand_R)

    -- Written out rather than folded into `a and b or c`: with that idiom a
    -- false left-hand result silently falls through to the other hand's answer,
    -- which is why the original mod reported the wrong hand for an item held in
    -- the left one.
    local alreadyHere, inOtherHand
    if self.isSecondary then
        alreadyHere = playerObj:isSecondaryHandItem(item)
        inOtherHand = playerObj:isPrimaryHandItem(item)
    else
        alreadyHere = playerObj:isPrimaryHandItem(item)
        inOtherHand = playerObj:isSecondaryHandItem(item)
    end

    if alreadyHere and not inOtherHand then return false end
    if hand:isDeepWounded() then return false end
    if hand:getFractureTime() > 0 and hand:getSplintFactor() <= 0 then return false end

    -- Re-equipping an item that gets replaced on unequip causes a cascade of
    -- problems; the original mod forbids it and so do we.
    if inOtherHand and item:getScriptItem():getReplaceWhenUnequip() then return false end

    return true
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_WeaponSlot:onRightMouseUp(x, y)
    local item = self:getHandItem()
    if item then
        NEQ_Slot.openItemContextMenu(self, x, y, item, self.inventoryPane, self.playerNum)
    end
end

function NEQ_WeaponSlot:onMouseDown(x, y)
    local item = self:getHandItem()
    if item then
        Drag.prepareDrag(self, Drag.itemToStack(item), x, y)
    end
end

function NEQ_WeaponSlot:onMouseMove(dx, dy)        Drag.startDrag(self) end
function NEQ_WeaponSlot:onMouseMoveOutside(dx, dy) Drag.startDrag(self) end

function NEQ_WeaponSlot:onMouseUp(x, y)
    -- Il rilascio e' avvenuto su un'altra finestra, che si e' gia' presa
    -- l'oggetto: rimetterlo in mano adesso sarebbe disfare il trasferimento.
    -- Vedi NEQ_DragDrop.isForeignDrop.
    if Drag.isForeignDrop(self, x, y) then
        Drag.endDrag()
        return
    end

    if Drag.isDragging() then
        self:handleItemDrop(Drag.getDraggedItem(), x)
    end
    Drag.endDrag()
end

function NEQ_WeaponSlot:onMouseUpOutside(x, y)
    Drag.cancelDrag(self, NEQ_WeaponSlot.dropOrUnequip)
end

function NEQ_WeaponSlot:handleItemDrop(item, x)
    if not item then return end

    local bothHands = item:isRequiresEquippedBothHands()
    if self.draw2hSlot and x > State.weaponSize + State.gapX then
        bothHands = true
    end

    if bothHands then
        ISInventoryPaneContextMenu.equipWeapon(item, true, true, self.playerNum)
    elseif self:canAcceptItem(item) then
        ISInventoryPaneContextMenu.equipWeapon(item, not self.isSecondary, false, self.playerNum)
    end
end

function NEQ_WeaponSlot:dropOrUnequip()
    NEQ_Slot.doDropOrUnequip(self, self:getHandItem())
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
function NEQ_WeaponSlot:controllerNodeOnJoypadDown(button)
    local item = self:getHandItem()
    if button == Joypad.AButton then
        if item then
            NEQ_Slot.openItemContextMenu(self, self:getWidth(), self:getHeight() / 2, item,
                self.inventoryPane, self.playerNum)
        end
        return true
    end
    if button == Joypad.XButton then
        if item then ISInventoryPaneContextMenu.unequipItem(item, self.playerNum) end
        return true
    end
    return false
end

return NEQ_WeaponSlot

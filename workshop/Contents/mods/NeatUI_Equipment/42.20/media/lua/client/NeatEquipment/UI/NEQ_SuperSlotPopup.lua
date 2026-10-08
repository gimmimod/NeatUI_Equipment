--[[ ============================================================================
    NEQ_SuperSlotPopup - the little grid that drops out of an expanded slot.

    One instance per panel, reparented to whichever super-slot is currently
    expanded: the sub-slots themselves are owned by that super-slot and simply
    change parent, which is why the popup never has to know anything about body
    locations.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISUIElement"

local State          = require("NeatEquipment/NEQ_State")
local Style          = require("NeatEquipment/NEQ_Style")
local ControllerNode = require("NeatEquipment/NEQ_ControllerNode")

local MAX_COLUMNS = 3

---@class NEQ_SuperSlotPopup : ISUIElement
local NEQ_SuperSlotPopup = ISUIElement:derive("NEQ_SuperSlotPopup")

function NEQ_SuperSlotPopup:createChildren()
    ControllerNode
        :injectControllerNode(self)
        :setChildrenNodeProvider(self.getControllerNodes, self)
end

function NEQ_SuperSlotPopup:getControllerNodes()
    local nodes = {}
    if not self.equipmentSlots or not self:isVisible() then return nodes end

    for _, slot in ipairs(self.equipmentSlots) do
        if slot.item then table.insert(nodes, slot.controllerNode) end
    end
    return nodes
end

function NEQ_SuperSlotPopup:applySlots(equipmentSlots)
    self.equipmentSlots = equipmentSlots
    self:layoutSlots()
end

function NEQ_SuperSlotPopup:layoutSlots()
    self:clearChildren()

    local pad = math.max(3, math.floor(4 * State.scale))
    local gap = math.max(2, math.floor(3 * State.scale))
    local size = State.slotSize

    self.visibleSlots = 0
    local column, row = 0, 0

    for _, slot in ipairs(self.equipmentSlots) do
        if slot.item then
            self:addChild(slot)
            slot:setVisible(true)
            slot:setX(pad + column * (size + gap))
            slot:setY(pad + row * (size + gap))

            self.visibleSlots = self.visibleSlots + 1
            column = column + 1
            if column >= MAX_COLUMNS then
                column = 0
                row = row + 1
            end
        else
            slot:setVisible(false)
        end
    end

    local columns = math.min(self.visibleSlots, MAX_COLUMNS)
    local rows = math.max(1, math.ceil(self.visibleSlots / MAX_COLUMNS))
    self:setWidth(pad * 2 + columns * size + math.max(0, columns - 1) * gap)
    self:setHeight(pad * 2 + rows * size + math.max(0, rows - 1) * gap)
end

--- Puts the popup away and tells the slot that owns it. Hiding it without
--- saying so would leave that slot believing it is still expanded, and the
--- next click on it would only close something that is not on screen.
function NEQ_SuperSlotPopup:close()
    local owner = self.owner
    self.owner = nil
    if owner then owner:setExpanded(false) end
    self:setVisible(false)
end

--- A popup opened by clicking its slot stays open until something else is
--- clicked. This is that "something else": the UI manager sends this to every
--- top-level element the click missed, and this popup is one.
---
--- The owning slot is the exception. A click on it is that slot's own toggle,
--- and closing here first would leave it re-opening what the player just asked
--- to close.
function NEQ_SuperSlotPopup:onMouseDownOutside(x, y)
    local owner = self.owner
    if owner and not owner:isMouseOver() then
        owner:setExpanded(false)
    end
end

--- Presses on the popup stay on the popup, the gaps between its slots
--- included. Passed on, they reach the panel underneath, which comes to the
--- front and covers the popup (see NEQ_Slot:onMouseDown).
function NEQ_SuperSlotPopup:onMouseDown(x, y)      return true end
function NEQ_SuperSlotPopup:onRightMouseDown(x, y) return true end

function NEQ_SuperSlotPopup:prerender()
    Style.drawNP(self, Style.NP.round, 0, 0, self.width, self.height, Style.TINT_BODY, 0.97)
end

return NEQ_SuperSlotPopup

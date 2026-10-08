--[[ ============================================================================
    NEQ_HotbarSlot - one hotbar attachment point (holster, belt loop, sling...).

    These mirror the real hotbar: the slot list comes from ISHotbar.availableSlot
    and attaching goes through ISHotbar:attachItem, so anything done here shows
    up on the hotbar itself immediately.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local State          = require("NeatEquipment/NEQ_State")
local Style          = require("NeatEquipment/NEQ_Style")
local Drag           = require("NeatEquipment/NEQ_DragDrop")
local ControllerNode = require("NeatEquipment/NEQ_ControllerNode")
local NEQ_Slot       = require("NeatEquipment/UI/NEQ_Slot")
local Tetris         = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")
local AttachAction   = require("NeatEquipment/NEQ_AttachAction")

---@class NEQ_HotbarSlot : ISPanel
local NEQ_HotbarSlot = ISPanel:derive("NEQ_HotbarSlot")

function NEQ_HotbarSlot:new(hotbar, body, inventoryPane, playerNum)
    local o = ISPanel:new(0, 0, State.hotbarSize, State.hotbarSize)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.hotbar = hotbar
    o.body = body
    o.inventoryPane = inventoryPane
    o.playerNum = playerNum

    return o
end

function NEQ_HotbarSlot:initialise()
    ISPanel.initialise(self)

    State:addScaleListener(self, NEQ_HotbarSlot.onScaleChanged)

    ControllerNode
        :injectControllerNode(self)
        :setJoypadDownHandler(self.controllerNodeOnJoypadDown)

    self.isController = self.controllerNode:isController(getSpecificPlayer(self.playerNum))
end

function NEQ_HotbarSlot:onScaleChanged()
    self:setWidth(State.hotbarSize)
    self:setHeight(State.hotbarSize)
end

function NEQ_HotbarSlot:getSlot()
    return self.index and self.hotbar.availableSlot[self.index] or nil
end

function NEQ_HotbarSlot:getItem()
    return self.index and self.hotbar.attachedItems[self.index] or nil
end

function NEQ_HotbarSlot:getSlotName()
    local slot = self:getSlot()
    if not slot then return nil end
    return getTextOrNull("IGUI_HotbarAttachment_" .. slot.slotType) or slot.name
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_HotbarSlot:prerender()
    if not self.index then return end

    local item = self:getItem()
    local highlight = nil

    local dragged = Drag.getDraggedItem()
    if dragged and dragged ~= item and self:canAttachItem(dragged) then
        highlight = item and State.REPLACE_COLOR or State.GOOD_COLOR
    end

    local focused = self.controllerNode and self.controllerNode.isFocused
    local hover = (not self.isController) and self:isMouseOver()

    Style.drawSlot(self, 0, 0, self.width, self.height, {
        hover = hover or focused,
        hasItem = item ~= nil,
        equipped = item ~= nil and item:isEquipped(),
        highlight = highlight,
        focus = focused and ControllerNode.FOCUS_COLOR or nil,
    })
end

function NEQ_HotbarSlot:render()
    if not self.index then return end

    local item = self:getItem()

    if item then
        local alpha = (item == Drag.getDraggedItem()) and 0.5 or 1.0
        local inset = math.max(2, math.floor(self.width * 0.12))
        Style.drawItemIcon(self, item, inset, inset,
            self.width - inset * 2, self.height - inset * 2, alpha)
    else
        -- Empty slot: the attachment's own icon, dimmed, so the player can see
        -- what belongs there.
        local slot = self:getSlot()
        if slot and slot.texture then
            local inset = math.max(3, math.floor(self.width * 0.18))
            Style.drawTextureFitted(self, slot.texture, inset, inset,
                self.width - inset * 2, self.height - inset * 2, 0.30, 1, 1, 1)
        end
    end

    if self:isMouseOver() or (self.controllerNode and self.controllerNode.isFocused) then
        local name = self:getSlotName()
        if name then
            local minX, maxX = nil, nil
            if self.parent then
                minX = -self.x
                maxX = self.parent:getWidth() - self.x
            end
            self:bringToTop()
            Style.drawSlotLabel(self, name, self.width / 2, -2, UIFont.Small, minX, maxX)
        end
        if item then self.body:doTooltipForItem(self, item) end
    end
end

-- ---------------------------------------------------------------------------
-- Attachment rules
-- ---------------------------------------------------------------------------
--- The hotbar can be told, per attachment type, that a slot is off limits
--- ("null" replacement). Both the check and the action have to honour that.
function NEQ_HotbarSlot:findAttachment(item)
    local slot = self:getSlot()
    if not slot or not slot.def or not slot.def.attachments then return nil end

    local attachmentType = item:getAttachmentType()
    for slotType, attachment in pairs(slot.def.attachments) do
        if attachmentType == slotType then
            local replacement = self.hotbar.replacements and self.hotbar.replacements[attachmentType]
            if replacement == "null" then return nil end
            return attachment, slot.def
        end
    end
    return nil
end

function NEQ_HotbarSlot:canAttachItem(item)
    return self:findAttachment(item) ~= nil
end

--- What ISHotbar:attachItem does with doAnim, with the gestures chosen when
--- each action starts (NEQ_AttachAction.newAttach).
function NEQ_HotbarSlot:attachItemIfPossible(item)
    local attachment, slotDef = self:findAttachment(item)
    if not attachment then return end

    local character = getSpecificPlayer(self.playerNum)
    if slotDef.name == "Back" and self.hotbar.replacements
        and self.hotbar.replacements[item:getAttachmentType()] then
        attachment = self.hotbar.replacements[item:getAttachmentType()]
    end

    ISInventoryPaneContextMenu.transferIfNeeded(character, item)
    local current = self.hotbar.attachedItems[self.index]
    if current then
        ISTimedActionQueue.add(AttachAction.newDetach(character, current))
    end
    ISTimedActionQueue.add(AttachAction.newAttach(character, item, attachment, self.index, slotDef))
end

function NEQ_HotbarSlot:detachItem(item)
    ISTimedActionQueue.add(AttachAction.newDetach(getSpecificPlayer(self.playerNum), item))
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_HotbarSlot:onRightMouseUp(x, y)
    local item = self:getItem()
    if item then
        NEQ_Slot.openItemContextMenu(self, x, y, item, self.inventoryPane, self.playerNum)
    end
end

function NEQ_HotbarSlot:onMouseDown(x, y)
    local item = self:getItem()
    if item then
        Drag.prepareDrag(self, Drag.itemToStack(item), x, y)
    end
end

function NEQ_HotbarSlot:onMouseMove(dx, dy)        Drag.startDrag(self) end
function NEQ_HotbarSlot:onMouseMoveOutside(dx, dy) Drag.startDrag(self) end

function NEQ_HotbarSlot:onMouseUp(x, y)
    -- Il rilascio e' avvenuto su un'altra finestra, che si e' gia' presa
    -- l'oggetto. Vedi NEQ_DragDrop.isForeignDrop.
    if Drag.isForeignDrop(self, x, y) then
        Drag.endDrag()
        return
    end

    local dragged = Drag.getDraggedItem()
    if dragged and dragged ~= self:getItem() then
        self:attachItemIfPossible(dragged)
    end
    Drag.endDrag()
end

function NEQ_HotbarSlot:onMouseUpOutside(x, y)
    Drag.cancelDrag(self, NEQ_HotbarSlot.dropOrUnequip)
end

--- Dragging an attached item onto the inventory detaches it rather than
--- unequipping it - it was never worn in the first place.
function NEQ_HotbarSlot:dropOrUnequip()
    local item = self:getItem()
    if not item then return end

    -- Sotto Inventory Tetris no: e' la griglia a raccogliere il rilascio, e
    -- staccare l'oggetto qui vorrebbe dire farlo due volte.
    if not Tetris.paneHandlesDrop()
        and self.inventoryPane and self.inventoryPane:isMouseOver() then
        self:detachItem(item)
        return
    end

    local playerObj = getSpecificPlayer(self.playerNum)
    if playerObj:getVehicle() then return end

    if not Drag.isMouseOverAnyUI() then
        ISInventoryPaneContextMenu.dropItem(item, self.playerNum)
    end
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
function NEQ_HotbarSlot:controllerNodeOnJoypadDown(button)
    local item = self:getItem()
    if button == Joypad.XButton then
        if item then self:detachItem(item) end
        return true
    end
    if button == Joypad.AButton then
        if item then
            NEQ_Slot.openItemContextMenu(self, self.width, self.height / 2, item,
                self.inventoryPane, self.playerNum)
        end
        return true
    end
    return false
end

return NEQ_HotbarSlot

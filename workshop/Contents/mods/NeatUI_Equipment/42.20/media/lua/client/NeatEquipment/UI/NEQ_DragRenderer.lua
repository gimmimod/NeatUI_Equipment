--[[ ============================================================================
    NEQ_DragRenderer - draws the item under the cursor while it is being dragged
    out of an equipment slot.

    Vanilla only paints a dragged item while the drag was started inside an
    inventory pane; a drag that begins on one of our slots would otherwise be
    invisible until it reached a pane. This is a zero-size element pinned to the
    top of the UI stack that paints the icon at the mouse position, and stands
    down as soon as a real pane takes over the drag.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISUIElement"

local State = require("NeatEquipment/NEQ_State")
local Style = require("NeatEquipment/NEQ_Style")
local Drag  = require("NeatEquipment/NEQ_DragDrop")

---@class NEQ_DragRenderer : ISUIElement
local NEQ_DragRenderer = ISUIElement:derive("NEQ_DragRenderer")

function NEQ_DragRenderer:new(inventoryPane, playerNum)
    local o = ISUIElement:new(0, 0, 0, 0)
    setmetatable(o, self)
    self.__index = self

    o.inventoryPane = inventoryPane
    o.playerNum = playerNum

    return o
end

function NEQ_DragRenderer:prerender()
    self:bringToTop()
end

function NEQ_DragRenderer:render()
    if self.inventoryPane.dragging then return end

    local item = Drag.getDraggedItem()
    if not item then return end

    local loot = getPlayerLoot(self.playerNum)
    if loot and loot.inventoryPane and loot.inventoryPane.dragging then return end

    local size = math.floor(32 * State.scale)
    local x = self:getMouseX() - math.floor(size / 2)
    local y = self:getMouseY() - math.floor(size / 2)

    -- The element is zero-sized, so its stencil would clip everything away.
    self:suspendStencil()
    Style.drawItemIcon(self, item, x, y, size, size, 1)
    self:resumeStencil()
end

return NEQ_DragRenderer

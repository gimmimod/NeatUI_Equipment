--[[ ============================================================================
    NEQ_Grip - the corner handle that resizes a panel.

    This used to be vanilla's ISResizeWidget. It is not any more, and the reason
    is worth writing down: that widget resizes its target itself, on its own
    terms, and both panels here decide their own size (the equipment panel from
    one scale factor, the wardrobe from its content). Two things setting the
    same width every frame is a fight, and the widget was also moved out from
    under the cursor mid-drag by the very relayout it triggered. Whatever the
    exact internals are - and they are not readable from here - the result was a
    handle that jittered, errored and eventually stopped responding.

    So the grip does nothing but report. It measures against the *absolute mouse
    position at the moment of the press*, never against accumulated deltas or
    its own coordinates, which makes it immune to being repositioned during the
    drag: however the panel rearranges itself, the next report is still
    "mouse has moved N pixels since you grabbed me".

    The panel decides what that means.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISUIElement"

local Style = require("NeatEquipment/NEQ_Style")

---@class NEQ_Grip : ISUIElement
local NEQ_Grip = ISUIElement:derive("NEQ_Grip")

--- The callbacks are stored as onGrip / onGripEnd, and the odd names are the
--- point. ISUIElement already has a method called onResize, and the engine
--- calls it on every element while it updates the UI - so a field of that name
--- is not a field at all, it is us handing the engine our callback to invoke
--- whenever it likes, with its own arguments. That is precisely what happened:
--- the wardrobe was dividing an element by a number, every frame, because the
--- engine had called the resize callback with the element as its argument.
---
--- Rule: never name a field on a UI element after anything vanilla owns.
---
--- onGrip(width, height) is called with the size the panel would have if it
--- followed the cursor. onGripEnd() is called once, when the drag ends.
function NEQ_Grip:new(size, target, onGrip, onGripEnd)
    local o = ISUIElement:new(0, 0, size, size)
    setmetatable(o, self)
    self.__index = self

    o.target = target
    o.onGrip = onGrip
    o.onGripEnd = onGripEnd
    o.dragging = false

    return o
end

function NEQ_Grip:prerender()
    Style.drawResizeGrip(self, 0, 0, self.width, self.dragging or self:isMouseOver())
end

function NEQ_Grip:onMouseDown(x, y)
    self.dragging = true
    self.startMouseX = getMouseX()
    self.startMouseY = getMouseY()
    self.startWidth = self.target:getWidth()
    self.startHeight = self.target:getHeight()
    self:setCapture(true)
    return true
end

function NEQ_Grip:drag()
    if not self.dragging then return end
    if not self.onGrip then return end

    self.onGrip(
        self.startWidth + (getMouseX() - self.startMouseX),
        self.startHeight + (getMouseY() - self.startMouseY))
end

function NEQ_Grip:onMouseMove(dx, dy)        self:drag() end
function NEQ_Grip:onMouseMoveOutside(dx, dy) self:drag() end

function NEQ_Grip:release()
    if not self.dragging then return false end
    self.dragging = false
    self:setCapture(false)
    if self.onGripEnd then self.onGripEnd() end
    return true
end

function NEQ_Grip:onMouseUp(x, y)        self:release() return true end
function NEQ_Grip:onMouseUpOutside(x, y) self:release() return true end

return NEQ_Grip

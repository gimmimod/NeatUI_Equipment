--[[ ============================================================================
    NEQ_Avatar - the 3D character preview in the middle of the panel.

    Framing (the part that is easy to get wrong)
    -------------------------------------------
    ISUI3DModel's zoom is not "bigger number, closer camera" - it is the
    opposite, and the useful range for a whole body is negative. Vanilla frames
    a full-length character with setZoom(-3) on a box roughly half as wide as it
    is tall (CharacterCreationAvatar:setFacePreview); a 151x302 box at -3 frames
    a doll the same way. A positive zoom - 18 for a face, say - fills the box
    with a shoulder, which on a small panel looks
    like a blurry grey rectangle rather than a character.

    NEQ_Body sizes the box to about that ratio, so the numbers below are just
    vanilla's.

    Refresh
    -------
    setCharacter copies the character's item visuals into the model, so calling
    it again after an equipment change is what updates the preview. It is not
    free, so it only runs when NEQ_Body says the worn items actually changed -
    never per frame. It also resets the facing, so the direction is put back
    afterwards: taking a jacket off while looking at your own back should not
    spin you round to the front.

    Drag to turn is vanilla's, re-tuned the way NeatUI Hairstyler does it:
    vanilla needs 40px of travel per 45-degree step, which on a preview this
    size means dragging across the whole thing for one turn.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISUI3DModel"

---@class NEQ_Avatar : ISUI3DModel
local NEQ_Avatar = ISUI3DModel:derive("NEQ_Avatar")

local MODEL_ZOOM = -3
local MODEL_Y_OFFSET = 0

function NEQ_Avatar:new(x, y, width, height, playerNum)
    local o = ISUI3DModel.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.char = getSpecificPlayer(playerNum)
    o.animateWhilePaused = true
    o.dragX = 0
    return o
end

function NEQ_Avatar:instantiate()
    ISUI3DModel.instantiate(self)

    -- Order matters: everything here goes through the java object, which only
    -- exists once ISUI3DModel.instantiate has run.
    self:setState("idle")
    self:setIsometric(false)
    self:setDirection(IsoDirections.S)
    self:setZoom(MODEL_ZOOM)
    self:setXOffset(0)
    self:setYOffset(MODEL_Y_OFFSET)
    self:refresh()
end

--- Re-reads the character, which is what pulls the new clothing into the model.
function NEQ_Avatar:refresh()
    if not self.javaObject or not self.char then return end
    pcall(function()
        local direction = self:getDirection()
        self:setCharacter(self.char)
        self:setDirection(direction)
    end)
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
-- prerender paints under the model, render paints over it.
--
-- Nothing is painted under it on purpose: no well, no frame, no plate. The
-- survivor stands on the panel itself, which is what makes the middle of the
-- window read as one open space with slots around its edge rather than as a
-- third box nested inside the second. Vanilla ISUI3DModel draws no background
-- of its own, so leaving this empty is all it takes.
function NEQ_Avatar:prerender()
    ISUI3DModel.prerender(self)
end

function NEQ_Avatar:render()
    ISUI3DModel.render(self)
end

-- ---------------------------------------------------------------------------
-- Drag to turn
-- ---------------------------------------------------------------------------
function NEQ_Avatar:onMouseDown(x, y)
    self.mouseDown = true
    self.dragX = 0
    self:setCapture(true)
    return true
end

function NEQ_Avatar:rotateStep(dx)
    if not self.mouseDown then return end

    local step = math.max(6, math.floor((self.width or 64) * 0.14))
    self.dragX = (self.dragX or 0) + dx

    -- while, not if: a fast drag can cross several steps in one event.
    while math.abs(self.dragX) >= step do
        local dir = IsoDirectionSet.rotate(self:getDirection(), (self.dragX < 0) and -1 or 1)
        self:setDirection(dir)
        self.dragX = self.dragX + ((self.dragX < 0) and step or -step)
    end
end

function NEQ_Avatar:onMouseMove(dx, dy)        self:rotateStep(dx) end
function NEQ_Avatar:onMouseMoveOutside(dx, dy) self:rotateStep(dx) end

function NEQ_Avatar:endDrag()
    self.mouseDown = false
    self.dragX = 0
    self:setCapture(false)
end

function NEQ_Avatar:onMouseUp(x, y)        self:endDrag() return true end
function NEQ_Avatar:onMouseUpOutside(x, y) self:endDrag() return true end

--- Right-click faces the character front again - a turned-around preview is
--- otherwise fiddly to straighten by hand.
function NEQ_Avatar:onRightMouseUp(x, y)
    self:setDirection(IsoDirections.S)
    return true
end

return NEQ_Avatar

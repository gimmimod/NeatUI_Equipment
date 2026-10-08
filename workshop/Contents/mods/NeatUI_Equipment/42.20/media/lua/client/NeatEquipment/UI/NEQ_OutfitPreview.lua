--[[ ============================================================================
    NEQ_OutfitPreview - an outfit on the survivor's own body, in 3D.

    The wardrobe shows outfits the survivor is not wearing, so the preview
    cannot be setCharacter(player): that always shows what is on right now.
    ISUI3DModel can also draw a SurvivorDesc, and that is the road taken here -
    the one Sims Changing Room takes (SCR_Preview):

      * a throwaway descriptor from SurvivorFactory, never the player's own
        getDescriptor();
      * the player's face, hair, skin and build copied onto it (HumanVisual
        carries no clothes, so nothing real comes along);
      * the outfit put on it as fresh instanceItem() copies, dyed and patterned
        from the descriptor. The copies never enter any inventory.

    Hotbar items are not drawn: a descriptor has worn items, not attachments.

    The model is re-dressed on the next frame after setOutfit, never inside it:
    several changes in a row cost one rebuild.

    If a future build refuses any of this, the preview falls back to the live
    survivor - less useful, never wrong.

    Framing and drag-to-turn are NEQ_Avatar's: see the note there.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISUI3DModel"

local Outfit = require("NeatEquipment/NEQ_Outfit")

---@class NEQ_OutfitPreview : ISUI3DModel
local NEQ_OutfitPreview = ISUI3DModel:derive("NEQ_OutfitPreview")

local MODEL_ZOOM = -3

function NEQ_OutfitPreview:new(x, y, width, height, playerNum)
    local o = ISUI3DModel.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.char = getSpecificPlayer(playerNum)
    o.animateWhilePaused = true
    o.dragX = 0
    o.pendingOutfit = nil
    o.dirty = false
    return o
end

function NEQ_OutfitPreview:instantiate()
    ISUI3DModel.instantiate(self)
    self:setState("idle")
    self:setIsometric(false)
    self:setDirection(IsoDirections.S)
    self:setZoom(MODEL_ZOOM)
    self:setXOffset(0)
    self:setYOffset(0)
    self.dirty = true
end

-- ---------------------------------------------------------------------------
-- Dressing
-- ---------------------------------------------------------------------------
--- A blank survivor with the player's look, or nil if the engine will not make
--- one.
local function blankDescriptor(character)
    local ok, desc = pcall(function() return SurvivorFactory.CreateSurvivor() end)
    if not ok or not desc then return nil end

    pcall(function() desc:setFemale(character:isFemale()) end)
    pcall(function() desc:getHumanVisual():copyFrom(character:getHumanVisual()) end)

    -- A freshly made survivor comes dressed. Strip it.
    local cleared = pcall(function() desc:getWornItems():clear() end)
    if not cleared then return nil end
    return desc
end

--- A copy of the garment a descriptor describes, for the preview only.
local function instantiate(descriptor)
    if not descriptor or not descriptor.type then return nil end
    local ok, item = pcall(function() return instanceItem(descriptor.type) end)
    if not ok or not item then return nil end

    if descriptor.tint then
        pcall(function()
            item:getVisual():setTint(ImmutableColor.new(
                descriptor.tint.r, descriptor.tint.g, descriptor.tint.b, 1))
        end)
    end
    if descriptor.texture then
        pcall(function()
            local clothing = item:getClothingItem()
            if clothing and not clothing:hasModel() then
                item:getVisual():setBaseTexture(descriptor.texture)
            else
                item:getVisual():setTextureChoice(descriptor.texture)
            end
        end)
    end
    pcall(function() item:synchWithVisual() end)
    return item
end

local function dress(desc, outfit)
    for key, descriptor in pairs(outfit and outfit.worn or {}) do
        local location = Outfit.isOutfitLocation(key) and Outfit.location(key)
        local item = location and instantiate(descriptor)
        if item then
            pcall(function() desc:setWornItem(location, item) end)
        end
    end
end

--- Show this outfit. It is read on the next frame, so the table must stay
--- valid until then; the wardrobe passes saved outfits, which do.
function NEQ_OutfitPreview:setOutfit(outfit)
    self.pendingOutfit = outfit
    self.dirty = true
end

function NEQ_OutfitPreview:rebuild()
    if not self.javaObject or not self.char then return end

    local direction = nil
    pcall(function() direction = self:getDirection() end)

    local desc = blankDescriptor(self.char)
    if desc then
        dress(desc, self.pendingOutfit)
        local ok = pcall(function() self:setSurvivorDesc(desc) end)
        if not ok then desc = nil end
    end
    if not desc then
        pcall(function() self:setCharacter(self.char) end)
    end

    if direction then pcall(function() self:setDirection(direction) end) end
end

function NEQ_OutfitPreview:prerender()
    if self.dirty then
        self.dirty = false
        self:rebuild()
    end
    ISUI3DModel.prerender(self)
end

-- ---------------------------------------------------------------------------
-- Drag to turn (NEQ_Avatar)
-- ---------------------------------------------------------------------------
function NEQ_OutfitPreview:onMouseDown(x, y)
    self.mouseDown = true
    self.dragX = 0
    self:setCapture(true)
    return true
end

function NEQ_OutfitPreview:rotateStep(dx)
    if not self.mouseDown then return end

    local step = math.max(6, math.floor((self.width or 64) * 0.14))
    self.dragX = (self.dragX or 0) + dx

    while math.abs(self.dragX) >= step do
        local dir = IsoDirectionSet.rotate(self:getDirection(), (self.dragX < 0) and -1 or 1)
        self:setDirection(dir)
        self.dragX = self.dragX + ((self.dragX < 0) and step or -step)
    end
end

function NEQ_OutfitPreview:onMouseMove(dx, dy)        self:rotateStep(dx) end
function NEQ_OutfitPreview:onMouseMoveOutside(dx, dy) self:rotateStep(dx) end

function NEQ_OutfitPreview:endDrag()
    self.mouseDown = false
    self.dragX = 0
    self:setCapture(false)
end

function NEQ_OutfitPreview:onMouseUp(x, y)        self:endDrag() return true end
function NEQ_OutfitPreview:onMouseUpOutside(x, y) self:endDrag() return true end

--- Right-click faces the survivor front again.
function NEQ_OutfitPreview:onRightMouseUp(x, y)
    self:setDirection(IsoDirections.S)
    return true
end

return NEQ_OutfitPreview

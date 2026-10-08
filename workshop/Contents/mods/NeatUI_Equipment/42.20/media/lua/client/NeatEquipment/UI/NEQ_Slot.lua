--[[ ============================================================================
    NEQ_Slot - one body location.

    Used twice: as the sub-slot inside a layered super-slot popup, and as an
    "extra" slot for body locations that have no dedicated place around the
    avatar. It draws itself with the Clean HotBar slot recipe (NEQ_Style) and
    speaks the vanilla drag protocol through NEQ_DragDrop.

    The static helpers at the bottom (context menu, unequip-all, drop-or-unequip)
    are shared by every other slot type, so they live here rather than being
    copied four times.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local State          = require("NeatEquipment/NEQ_State")
local Style          = require("NeatEquipment/NEQ_Style")
local Drag           = require("NeatEquipment/NEQ_DragDrop")
local ClothingExtra  = require("NeatEquipment/NEQ_ClothingExtra")
local ControllerNode = require("NeatEquipment/NEQ_ControllerNode")
local Tetris         = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")

---@class NEQ_Slot : ISPanel
local NEQ_Slot = ISPanel:derive("NEQ_Slot")

function NEQ_Slot:new(x, y, bodyLocation, body, inventoryPane, playerNum)
    local o = ISPanel:new(x, y, State.slotSize, State.slotSize)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.bodyLocation = bodyLocation
    o.body = body
    o.inventoryPane = inventoryPane
    o.playerNum = playerNum
    o.bodyLocationGroup = getSpecificPlayer(playerNum):getWornItems():getBodyLocationGroup()

    return o
end

function NEQ_Slot:initialise()
    ISPanel.initialise(self)

    State:addScaleListener(self, NEQ_Slot.onScaleChanged)

    ControllerNode
        :injectControllerNode(self)
        :setJoypadDownHandler(self.controllerNodeOnJoypadDown)

    self.isController = self.controllerNode:isController(getSpecificPlayer(self.playerNum))
end

function NEQ_Slot:onScaleChanged()
    self:setWidth(State.slotSize)
    self:setHeight(State.slotSize)
end

function NEQ_Slot:setItem(item) self.item = item end
function NEQ_Slot:clearItem() self.item = nil end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_Slot:prerender()
    local focused = self.controllerNode and self.controllerNode.isFocused
    local hover = (not self.isController) and self:isMouseOver()

    local highlight = nil
    local dragged = Drag.getDraggedItem()
    if dragged and dragged ~= self.item then
        local location = ClothingExtra.getDefaultBodyLocation(dragged)
        -- self.bodyLocation is nil while the slot is sitting unused in the
        -- pool; isExclusive would throw on it.
        if location and self.bodyLocation then
            local conflicts = location == self.bodyLocation
                or self.bodyLocationGroup:isExclusive(location, self.bodyLocation)
            if conflicts then highlight = State.BAD_COLOR end
        end
    end

    Style.drawSlot(self, 0, 0, self.width, self.height, {
        hover = hover or focused,
        hasItem = self.item ~= nil,
        equipped = self.item ~= nil,
        highlight = highlight,
        focus = focused and ControllerNode.FOCUS_COLOR or nil,
    })
end

function NEQ_Slot:render()
    local item = self.item
    if not item then return end

    local alpha = (item == Drag.getDraggedItem()) and 0.5 or 1.0
    local inset = math.max(2, math.floor(self.width * 0.12))
    Style.drawItemIcon(self, item, inset, inset,
        self.width - inset * 2, self.height - inset * 2, alpha)

    if (not self.isController and self:isMouseOver()) or self.controllerNode.isFocused then
        self.body:doTooltipForItem(self, item)
    end
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_Slot:onRightMouseUp(x, y)
    if self.item then
        NEQ_Slot.openItemContextMenu(self, x, y, self.item, self.inventoryPane, self.playerNum)
    end
end

--- A press on a garment is taken here, not passed on.
---
--- In the layer popup the equipment panel lies right underneath, and a press
--- no child claims goes on to the next window below (UIManager.
--- updateMouseButtons). That window gets onFocus first, and ISUIElement:onFocus
--- brings a top-level window to the front: the panel jumped over the popup the
--- moment a drag began, which looked exactly like the popup closing. The super
--- slot has always returned true here, which is why its chips never did it.
function NEQ_Slot:onMouseDown(x, y)
    if not self.item then return false end
    Drag.prepareDrag(self, Drag.itemToStack(self.item), x, y)
    return true
end

--- The right button too: the menu opens on the release, and the release has
--- to find this slot still in front.
function NEQ_Slot:onRightMouseDown(x, y)
    return self.item ~= nil
end

function NEQ_Slot:onMouseMove(dx, dy)        Drag.startDrag(self) end
function NEQ_Slot:onMouseMoveOutside(dx, dy) Drag.startDrag(self) end

--- Rilasciare un capo qui sopra lo fa indossare **in questa posizione**.
---
--- Mancava, e la mancanza si vedeva: `prerender` accende gia' il riquadro
--- rosso quando ci passi sopra un capo che va in conflitto, cioe' lo slot
--- prometteva un rilascio che poi non accettava. E' anche il motivo per cui
--- esiste il ventaglio: trascinando una camicia su un torso con tre strati si
--- apre proprio per poter scegliere **quale** strato sostituire, e finora
--- lasciarla su uno di quegli slot non faceva niente.
function NEQ_Slot:onMouseUp(x, y)
    -- Rilasciato su un'altra finestra, che se l'e' gia' preso.
    if Drag.isForeignDrop(self, x, y) then
        Drag.endDrag()
        return
    end

    local item = Drag.getDraggedItem()
    if item and item ~= self.item then
        NEQ_Slot.wearAtBodyLocation(item, self.bodyLocation, self.playerNum)
    end
    Drag.endDrag()
end

--- Indossare un capo in una posizione precisa del corpo.
---
--- Se e' la sua posizione naturale basta indossarlo; se e' una delle sue
--- alternative serve la voce corrispondente, che e' come vanilla stessa
--- gestisce un capo che puo' stare in piu' posti. Torna falso se quel capo li'
--- non ci puo' andare: chi chiama lascia perdere e il capo resta dov'e'.
---
--- Sta qui e non nei due chiamanti perche' era gia' scritta in NEQ_SuperSlot e
--- ne serviva una seconda copia: due copie della stessa regola sono la strada
--- piu' breve perche' un giorno dicano cose diverse.
function NEQ_Slot.wearAtBodyLocation(item, bodyLocation, playerNum)
    if not item or not bodyLocation then return false end

    local default = ClothingExtra.getDefaultBodyLocation(item)
    if default == bodyLocation then
        ISInventoryPaneContextMenu.onWearItems({ item }, playerNum)
        return true
    end

    local extra = ClothingExtra.findExtraOptionForBodyLocation(item, bodyLocation)
    if not extra then return false end

    ISInventoryPaneContextMenu.onClothingItemExtra(item, extra, getSpecificPlayer(playerNum))
    return true
end

function NEQ_Slot:onMouseUpOutside(x, y)
    Drag.cancelDrag(self, NEQ_Slot.dropOrUnequip)
end

function NEQ_Slot:dropOrUnequip()
    NEQ_Slot.doDropOrUnequip(self, self.item)
end

-- ---------------------------------------------------------------------------
-- Shared behaviour
-- ---------------------------------------------------------------------------

--- Where a dragged item ends up when it is released outside every slot:
--- over the inventory list it is unequipped, over the loot list it is
--- transferred, over the world it is dropped, over anything else nothing
--- happens.
--- Mette in coda lo spogliarsi, ma solo se l'oggetto e' davvero addosso.
--- Chiamarla su qualcosa che il personaggio non indossa non costa niente:
--- unequipItem controlla da se' e non fa nulla.
function NEQ_Slot.unequipIfWorn(item, playerNum)
    if not item then return end

    local character = getSpecificPlayer(playerNum)
    if not character then return end

    local worn = false
    pcall(function() worn = character:isEquipped(item) == true end)
    if worn then
        ISInventoryPaneContextMenu.unequipItem(item, playerNum)
    end
end

function NEQ_Slot.doDropOrUnequip(owner, item)
    if not item then return end

    -- Sotto Inventory Tetris queste due strade non si prendono: l'oggetto lo
    -- sistema la griglia, nella casella su cui e' stato posato. Vedi
    -- ModCompatibility/NEQ_InventoryTetris, T.paneHandlesDrop.
    if not Tetris.paneHandlesDrop() then
        if owner.inventoryPane and owner.inventoryPane:isMouseOver() then
            ISInventoryPaneContextMenu.unequipItem(item, owner.playerNum)
            return
        end

        local loot = getPlayerLoot(owner.playerNum)
        if loot and loot.inventoryPane and loot.inventoryPane:isMouseOver() then
            -- Prima si toglie, poi si sposta, e in quest'ordine: la coda delle
            -- azioni lo mantiene. Un capo trasferito mentre e' ancora indossato
            -- finisce dentro il contenitore **e** resta addosso al modello - e'
            -- per questo che dropItem, in vanilla, comincia proprio con lo
            -- spogliarsi (ISInventoryPaneContextMenu.lua:3851).
            NEQ_Slot.unequipIfWorn(item, owner.playerNum)
            loot.inventoryPane:transferItemsByWeight({ item }, loot.inventoryPane.inventory)
            return
        end
    end

    local playerObj = getSpecificPlayer(owner.playerNum)
    if playerObj:getVehicle() then return end

    if not Drag.isMouseOverAnyUI() then
        ISInventoryPaneContextMenu.dropItem(item, owner.playerNum)
    end
end

--- Vanilla's context menu wants an item "stack" record, not a bare item.
local function stacksFromItem(item, inventoryPane)
    local stack = { items = {}, invPanel = inventoryPane }
    stack.name = item:getName()
    stack.cat = item:getDisplayCategory() or item:getCategory()

    -- The first entry is the representative item, as in vanilla, so the weight
    -- below counts it once even though it appears twice.
    table.insert(stack.items, item)
    table.insert(stack.items, item)
    stack.weight = item:getUnequippedWeight()
    stack.count = 2

    return { stack }
end

--- The plain vanilla item context menu, left exactly as the rest of the game's
--- is: taking everything off is a button in the panel header, not an extra
--- entry bolted onto every item menu.
function NEQ_Slot.openItemContextMenu(uiContext, x, y, item, invPane, playerNum)
    local player = getSpecificPlayer(playerNum)
    local container = item:getContainer()
    local isInInventory = container and container:isInCharacterInventory(player)

    local menu = ISInventoryPaneContextMenu.createMenu(
        playerNum, isInInventory, stacksFromItem(item, invPane),
        uiContext:getAbsoluteX() + x, uiContext:getAbsoluteY() + y)
    if not menu then return end

    if menu.numOptions > 1 and JoypadState.players[playerNum + 1] then
        uiContext.controllerNode:focusContextMenu(playerNum, menu)
    end
end

--- Takes off everything the character is wearing. Driven by the header button.
---@param player IsoPlayer
function NEQ_Slot.unequipAll(player)
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        if item and not item:isHidden() then
            ISInventoryPaneContextMenu.unequipItem(item, player:getPlayerNum())
        end
    end
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
function NEQ_Slot:controllerNodeOnJoypadDown(button)
    local item = self.item
    if button == Joypad.XButton then
        if item then ISInventoryPaneContextMenu.unequipItem(item, self.playerNum) end
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

return NEQ_Slot

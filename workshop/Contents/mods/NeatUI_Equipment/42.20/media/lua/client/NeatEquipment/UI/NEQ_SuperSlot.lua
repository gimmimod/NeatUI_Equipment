--[[ ============================================================================
    NEQ_SuperSlot - one of the slots around the avatar.

    A "super" slot stands for a whole area of the body (head, torso, waist, ...)
    and can therefore hold several layered items at once - a jacket over a shirt
    over a vest. The big square shows the outermost one; the rest are stacked as
    mini icons in a narrow strip beside it, and clicking the slot expands them
    into a popup where each layer gets its own full slot.

    The strip is drawn on the side that faces the avatar, so a slot in the right
    column grows leftwards instead of off the panel edge. That is what lets the
    panel be this narrow.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local State          = require("NeatEquipment/NEQ_State")
local Style          = require("NeatEquipment/NEQ_Style")
local Drag           = require("NeatEquipment/NEQ_DragDrop")
local ClothingExtra  = require("NeatEquipment/NEQ_ClothingExtra")
local ControllerNode = require("NeatEquipment/NEQ_ControllerNode")
local NEQ_Slot       = require("NeatEquipment/UI/NEQ_Slot")

-- Two chips beside the slot, each half its height, so the pair lines up flush
-- with the slot's top and bottom edges. Anything past the third layer is
-- counted in a badge rather than shrunk into an unreadable third chip - the
-- popup is one click away and shows them all.
local VISIBLE_LAYER_CHIPS = 2

---@class NEQ_SuperSlot : ISPanel
local NEQ_SuperSlot = ISPanel:derive("NEQ_SuperSlot")

---@param definition NEQSlotDefinition
function NEQ_SuperSlot:new(definition, body, inventoryPane, playerNum, popup)
    local o = ISPanel:new(0, 0, State.superSize + State.subStrip, State.superSize)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.definition = definition
    o.body = body
    o.inventoryPane = inventoryPane
    o.playerNum = playerNum
    o.popup = popup

    -- Left-column slots grow their layer strip to the right, right-column slots
    -- to the left: either way the strip points at the avatar.
    o.subSide = (definition.column == "right") and "left" or "right"

    o.slots = {}
    o.slotsByBodyLocation = {}
    o.mouseDownX = 0
    o.mouseDownY = 0
    o.moveWithMouse = false

    o.bodyLocationGroup = getSpecificPlayer(playerNum):getWornItems():getBodyLocationGroup()

    return o
end

function NEQ_SuperSlot:initialise()
    ISPanel.initialise(self)

    State:addScaleListener(self, NEQ_SuperSlot.onScaleChanged)
    self:onScaleChanged()

    ControllerNode
        :injectControllerNode(self)
        :setJoypadDownHandler(self.controllerNodeOnJoypadDown)
        :setLoseJoypadFocusHandler(function() self:setExpanded(false) end)
        :setChildrenNodeProvider(self.getVisibleControllerNodes, self)

    self.isController = self.controllerNode:isController(getSpecificPlayer(self.playerNum))
end

--- The sub-slots are created here but deliberately not added as children: they
--- only ever appear inside the popup, which adopts them when this slot is
--- expanded. They are instantiated all the same, because setVisible needs a
--- java object and the popup calls it on the hidden ones too.
function NEQ_SuperSlot:createChildren()
    for _, bodyLocation in ipairs(self.definition.bodyLocations) do
        local slot = NEQ_Slot:new(0, 0, bodyLocation, self.body, self.inventoryPane, self.playerNum)
        slot:initialise()
        slot:instantiate()
        slot:setVisible(false)
        self.slotsByBodyLocation[bodyLocation] = slot
        self.slots[#self.slots + 1] = slot
    end
end

function NEQ_SuperSlot:onScaleChanged()
    self:setWidth(State.superSize + State.subStrip)
    self:setHeight(State.superSize)
end

--- x of the big square inside this element.
function NEQ_SuperSlot:mainX()
    return (self.subSide == "left") and State.subStrip or 0
end

-- L'inizio della striscia non ha piu' una funzione sua: lo decide chipRect
-- insieme allo stacco, o le due misure tornerebbero a divergere.

-- ---------------------------------------------------------------------------
-- Contents
-- ---------------------------------------------------------------------------
function NEQ_SuperSlot:setItem(item, bodyLocation)
    local slot = self.slotsByBodyLocation[bodyLocation]
    if slot then slot:setItem(item) end
end

function NEQ_SuperSlot:clearItem()
    for _, slot in ipairs(self.slots) do slot:clearItem() end
end

function NEQ_SuperSlot:getTopSlot()
    -- Definition order, not table order: the first location that holds anything
    -- is the outermost layer.
    for _, bodyLocation in ipairs(self.definition.bodyLocations) do
        local slot = self.slotsByBodyLocation[bodyLocation]
        if slot and slot.item then return slot end
    end
    return nil
end

function NEQ_SuperSlot:getTopItem()
    local slot = self:getTopSlot()
    return slot and slot.item or nil
end

function NEQ_SuperSlot:hasItem()
    return self:getTopItem() ~= nil
end

function NEQ_SuperSlot:getItemCount()
    local count = 0
    for _, slot in pairs(self.slotsByBodyLocation) do
        if slot.item then count = count + 1 end
    end
    return count
end

function NEQ_SuperSlot:getNthItem(index)
    local count = 0
    for _, bodyLocation in ipairs(self.definition.bodyLocations) do
        local slot = self.slotsByBodyLocation[bodyLocation]
        if slot and slot.item then
            count = count + 1
            if count == index then return slot.item end
        end
    end
    return nil
end

--- Every worn item in this area, outermost first.
function NEQ_SuperSlot:collectItems()
    local items = {}
    for _, bodyLocation in ipairs(self.definition.bodyLocations) do
        local slot = self.slotsByBodyLocation[bodyLocation]
        if slot and slot.item then
            items[#items + 1] = slot.item
        end
    end
    return items
end

--- How many layer chips are actually drawn for `count` items: one slot plus at
--- most two chips.
local function chipCount(count)
    return math.max(0, math.min(count - 1, VISIBLE_LAYER_CHIPS))
end

--[[ Le targhette, con il loro spazio attorno.

    Prima erano esattamente mezzo slot e **si toccavano**: fra la prima e la
    seconda niente, e fra la targhetta e il quadrato grande niente. Tre riquadri
    con il bordo in comune non si leggono come tre riquadri: si leggono come uno
    solo, sbrodolato, e con quattro strati addosso sembrava che i riquadri
    piccoli entrassero dentro quello grande.

    Adesso c'e' uno stacco, e le targhette si stringono di quel tanto invece di
    sfondare: due targhette piu' lo stacco stanno ancora dentro l'altezza dello
    slot, e in orizzontale la targhetta piu' lo stacco stanno dentro la striscia
    - quindi l'elemento resta largo `superSize + subStrip` e il resto del
    posizionamento non cambia.

    Lo stacco sta anche dalla parte del quadrato grande, che e' quello che
    rimette il confine fra i due.
]]
local function chipGeom()
    local gap = math.max(1, math.floor(2 * State.scale))
    return gap, math.max(6, State.subStrip - gap)
end

function NEQ_SuperSlot:chipRect(index, chips)
    local gap, size = chipGeom()
    local slot = State.superSize

    -- Centrate verticalmente qualunque sia il numero: una sola targhetta
    -- veniva gia' centrata, due partivano dall'alto, e la differenza si vedeva.
    local total = chips * size + math.max(0, chips - 1) * gap
    local top = math.floor((slot - total) / 2)

    -- Lo stacco cade sempre dal lato del quadrato grande.
    local x = (self.subSide == "left") and 0 or (slot + gap)

    return x, top + (index - 1) * (size + gap), size, size
end

function NEQ_SuperSlot:doesItemConflict(item, bodyLocation)
    if not bodyLocation then return false end

    for _, slot in pairs(self.slotsByBodyLocation) do
        if slot.item and slot.item ~= item then
            if bodyLocation == slot.bodyLocation
                or self.bodyLocationGroup:isExclusive(bodyLocation, slot.bodyLocation) then
                return true
            end
        end
    end
    return false
end

--- Questo capo e' uno dei nostri strati?
function NEQ_SuperSlot:ownsItem(item)
    if not item then return false end
    for _, slot in pairs(self.slotsByBodyLocation) do
        if slot.item == item then return true end
    end
    return false
end

function NEQ_SuperSlot:isDraggingMyItem()
    return self:ownsItem(Drag.getDraggedItem())
end

--- Quali posizioni del corpo sono occupate, adesso. Serve a capire se il
--- ventaglio aperto sta ancora mostrando quello che hai addosso.
function NEQ_SuperSlot:layerSignature()
    local parts = {}
    for _, bodyLocation in ipairs(self.definition.bodyLocations) do
        local slot = self.slotsByBodyLocation[bodyLocation]
        if slot and slot.item then parts[#parts + 1] = bodyLocation end
    end
    return table.concat(parts, ",")
end

--- Best sub-slot for an incoming item: the one it already occupies, else a free
--- one it fits, else its default location.
function NEQ_SuperSlot:determineTargetSlot(item)
    local valid = ClothingExtra.getBodyLocationsForItem(item)

    local current, empty, default = nil, nil, nil
    for bodyLocation, slot in pairs(self.slotsByBodyLocation) do
        if slot.item == item then
            current = slot
            break
        end
        if valid[bodyLocation] then
            if not slot.item and not empty then empty = slot end
            if not default then default = slot end
        end
    end

    return current or empty or default
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_SuperSlot:prerender()
    local size = State.superSize
    local mainX = self:mainX()
    local items = self:collectItems()
    local count = #items

    local focused = self.controllerNode and self.controllerNode.isFocused
    local hover = (not self.isController) and self:isMouseOver()

    local highlight = nil
    local dragged = Drag.getDraggedItem()
    if dragged then
        local target = self:determineTargetSlot(dragged)
        if target then
            local canAccept = target.item ~= dragged
            local conflicts = self:doesItemConflict(dragged, target.bodyLocation)
            highlight = (canAccept and conflicts and State.REPLACE_COLOR)
                or (canAccept and State.GOOD_COLOR)
                or (conflicts and State.BAD_COLOR)
                or nil
        end
    end

    Style.drawSlot(self, mainX, 0, size, size, {
        hover = hover or focused,
        hasItem = count > 0,
        equipped = count > 0,
        highlight = highlight,
        focus = focused and ControllerNode.FOCUS_COLOR or nil,
    })

    -- The chips only exist while there is something to stack in them.
    local chips = chipCount(count)
    for i = 1, chips do
        local cx, cy, cw, ch = self:chipRect(i, chips)
        Style.drawSlot(self, cx, cy, cw, ch, { hasItem = true, equipped = true })
    end

    -- Uno slot che ha perso gli strati non puo' restare aperto: se ne occupa
    -- `update`, insieme al resto di quello che il ventaglio deve rispecchiare.
    -- Stava anche qui, e due posti che decidono la stessa cosa sono due posti
    -- da tenere allineati.
end

function NEQ_SuperSlot:render()
    local size = State.superSize
    local mainX = self:mainX()
    local items = self:collectItems()
    local count = #items

    if count > 0 then
        -- Sbiadito e' il capo che stai trascinando, qualunque sia. Prima lo era
        -- sempre e solo il piu' esterno, quindi partendo da una targhetta si
        -- vedeva sbiadire il quadrato grande: il riscontro indicava il capo
        -- sbagliato esattamente come faceva il trascinamento.
        local dragged = Drag.getDraggedItem()
        local inset = math.max(2, math.floor(size * 0.12))
        Style.drawItemIcon(self, items[1], mainX + inset, inset,
            size - inset * 2, size - inset * 2,
            (items[1] == dragged) and 0.5 or 1.0)

        local chips = chipCount(count)
        for i = 1, chips do
            local cx, cy, cw, ch = self:chipRect(i, chips)
            local item = items[i + 1]
            local chipInset = math.max(1, math.floor(cw * 0.12))
            Style.drawItemIcon(self, item, cx + chipInset, cy + chipInset,
                cw - chipInset * 2, ch - chipInset * 2,
                (item == dragged) and 0.5 or 1.0)
        end

        -- Everything past the chips is a number on the slot rather than a chip
        -- too small to recognise.
        local hidden = count - 1 - chips
        if hidden > 0 then
            Style.drawCountBadge(self, mainX, 0, size, hidden)
        end
    end

    -- Name label above the big square. The bounds are the body panel's edges
    -- expressed in this slot's coordinates, so a long name near the panel edge
    -- slides inwards rather than being clipped.
    if self:isMouseOver() or (self.controllerNode and self.controllerNode.isFocused) then
        local minX, maxX = nil, nil
        if self.parent then
            minX = -self.x
            maxX = self.parent:getWidth() - self.x
        end
        Style.drawSlotLabel(self, getText(self.definition.name),
            mainX + size / 2, -2, UIFont.Small, minX, maxX)
    end

    self:updateHoverTooltip(items, count)
end

function NEQ_SuperSlot:updateHoverTooltip(items, count)
    if count == 0 then return end

    if not self.isController and not Drag.isDragging() and self:isMouseOver() then
        local index = self:mousePositionToSlotIndex(self:getMouseX(), self:getMouseY())
        if index ~= -1 and index <= count then
            self.body:doTooltipForItem(self, items[index])
        else
            self.body:closeTooltip()
        end
    elseif self.controllerNode.isFocused and not self.controllerNode.selectedChild then
        self.body:doTooltipForItem(self, items[1])
    end
end

--- Quanti capi restano fuori: ne' il quadrato grande ne' una targhetta.
--- Sono quelli che la pastiglia "+N" conta.
function NEQ_SuperSlot:hiddenLayerCount()
    local count = #self:collectItems()
    return math.max(0, count - 1 - chipCount(count))
end

--- Il puntatore e' sulla pastiglia "+N"?
---
--- La pastiglia sta nell'angolo in basso a destra **dentro** il quadrato
--- grande, ed e' arancione come una targhetta: sembra il riquadro del capo che
--- conta, ma non lo e'. Chi ci cliccava sopra apriva il menu del capo piu'
--- esterno - la giacca - e la maglietta sotto restava irraggiungibile finche'
--- non si toglieva qualcos'altro. Segnalato, ed e' giusto: adesso e' un
--- bersaglio suo, e quello che fa e' aprire il ventaglio dove ogni strato ha
--- il suo slot.
function NEQ_SuperSlot:isOverBadge(x, y)
    local hidden = self:hiddenLayerCount()
    if hidden <= 0 then return false end

    local bx, by, bw, bh = Style.countBadgeRect(self:mainX(), 0, State.superSize, hidden)

    -- Il bersaglio e' un filo piu' largo di quello che si vede. Da quando il
    -- conteggio e' una scritta invece di una pastiglia, il rettangolo disegnato
    -- e' esattamente la scritta: due cifre di altezza dodici pixel sono un
    -- bersaglio che si manca. Il margine sta qui e non in countBadgeRect,
    -- perche' li' quel rettangolo e' quello che si disegna.
    local grow = math.max(2, math.floor(State.superSize * 0.08))
    bx, by, bw, bh = bx - grow, by - grow, bw + grow * 2, bh + grow * 2

    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

--- 1 for the big square, 2..n for the layer chips, -1 for nothing. Reads the
--- same geometry the chips are drawn with, so the two cannot drift apart.
function NEQ_SuperSlot:mousePositionToSlotIndex(x, y)
    local size = State.superSize
    local mainX = self:mainX()

    -- Prima della verifica sul quadrato grande: la pastiglia ci sta dentro.
    if self:isOverBadge(x, y) then return -1 end

    if x >= mainX and x < mainX + size and y >= 0 and y < size then
        return 1
    end

    local chips = chipCount(#self:collectItems())
    for i = 1, chips do
        local cx, cy, cw, ch = self:chipRect(i, chips)
        if x >= cx and x < cx + cw and y >= cy and y < cy + ch then
            return i + 1
        end
    end

    return -1
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_SuperSlot:onRightMouseUp(x, y)
    if self:isOverBadge(x, y) then
        self:setExpanded(true, true)
        return true
    end

    local index = self:mousePositionToSlotIndex(x, y)
    if index == -1 then return end

    local item = self:getNthItem(index)
    if item then
        NEQ_Slot.openItemContextMenu(self, x, y, item, self.inventoryPane, self.playerNum)
        return true
    end
end

function NEQ_SuperSlot:onMouseDown(x, y)
    self.mouseDownX = x
    self.mouseDownY = y

    -- Premere sulla pastiglia non deve cominciare a trascinare la giacca:
    -- quel riquadro parla dei capi sotto, non di quello sopra.
    if self:isOverBadge(x, y) then return true end

    -- **Si trascina il capo su cui hai premuto**, non sempre il piu' esterno.
    -- Il clic destro lo faceva gia' - apre il menu del capo giusto, con
    -- getNthItem - ma il trascinamento no: partendo da una targhetta si
    -- staccava la giacca, e la maglietta che avevi preso restava addosso. Le
    -- targhette sembravano decorative proprio per questo.
    local index = self:mousePositionToSlotIndex(x, y)
    local item = (index ~= -1 and self:getNthItem(index)) or self:getTopItem()
    if item then
        Drag.prepareDrag(self, Drag.itemToStack(item), x, y)
        return true
    end

    ISPanel.onMouseDown(self, x, y)
end

function NEQ_SuperSlot:onMouseMove(dx, dy)
    local item = Drag.getDraggedItem()
    if not item then return end

    local target = self:determineTargetSlot(item)
    if target then
        -- Hovering a conflicting item over a layered slot opens it, so the layer
        -- it should replace can be picked directly.
        local location = ClothingExtra.getDefaultBodyLocation(item)
        if self:doesItemConflict(item, location) then
            self:setExpanded(true)
        end
    else
        Drag.startDrag(self)
    end
end

--- Attenzione: qui arrivano **gli spostamenti**, non le coordinate
--- (`ISUIElement.lua:1567` - `onMouseMoveOutside(dx, dy)`).
---
--- La chiusura del ventaglio stava qui e li confrontava con la posizione
--- dell'ultima pressione, che e' un numero di tutt'altra natura: il risultato
--- era che bastava muovere il mouse fuori dallo slot perche' si chiudesse -
--- **compreso muoverlo verso il ventaglio**, che sta due pixel piu' sotto. Il
--- ventaglio scappava proprio mentre si andava a prenderlo. Adesso quel
--- controllo sta in `update`, dove si guarda dov'e' il puntatore invece di
--- quanto si e' mosso.
function NEQ_SuperSlot:onMouseMoveOutside(dx, dy)
    if not Drag.isDragging() then
        Drag.startDrag(self)
    end
end

function NEQ_SuperSlot:onMouseUp(x, y)
    -- Il rilascio e' avvenuto su un'altra finestra, che si e' gia' presa
    -- l'oggetto. Vedi NEQ_DragDrop.isForeignDrop.
    if Drag.isForeignDrop(self, x, y) then
        Drag.endDrag()
        return
    end

    if Drag.isDragging() then
        self:handleDragDrop()
    else
        self:handleSlotClick(x, y)
    end
    Drag.endDrag()
end

function NEQ_SuperSlot:onMouseUpOutside(x, y)
    Drag.cancelDrag(self, NEQ_SuperSlot.dropOrUnequip)
end

function NEQ_SuperSlot:handleDragDrop()
    local item = Drag.getDraggedItem()
    if not item then return end

    local target = self:determineTargetSlot(item)
    if target then
        self:handleClothingDrop(item, target.bodyLocation)
    end
    Drag.endDrag()
end

function NEQ_SuperSlot:handleClothingDrop(item, bodyLocation)
    if not self.slotsByBodyLocation[bodyLocation] then return end
    -- La regola sta in NEQ_Slot, in un posto solo: la usa anche il rilascio su
    -- un sotto-slot del ventaglio, e due copie prima o poi divergono.
    NEQ_Slot.wearAtBodyLocation(item, bodyLocation, self.playerNum)
end

function NEQ_SuperSlot:handleSlotClick(x, y)
    if math.abs(x - self.mouseDownX) < 5 and math.abs(y - self.mouseDownY) < 5 then
        -- La pastiglia apre e basta: e' l'invito a vedere gli strati che non
        -- ci stanno, quindi chiuderli con lo stesso clic non avrebbe senso.
        if self:isOverBadge(x, y) then
            self:setExpanded(true, true)
        else
            self:setExpanded(not self.expanded, true)
        end
    end
    ISPanel.onMouseUp(self, x, y)
end

function NEQ_SuperSlot:dropOrUnequip()
    -- Il capo che stavi trascinando, non il piu' esterno: da quando si puo'
    -- partire da una targhetta i due possono essere diversi, e trascinando la
    -- maglietta nel vuoto veniva tolta la giacca.
    local item = Drag.getDraggedItem()
    if not self:ownsItem(item) then item = self:getTopItem() end
    if item then NEQ_Slot.doDropOrUnequip(self, item) end
end

function NEQ_SuperSlot:unequip()
    local item = self:getTopItem()
    if item then ISInventoryPaneContextMenu.unequipItem(item, self.playerNum) end
end

-- ---------------------------------------------------------------------------
-- Expanded popup
-- ---------------------------------------------------------------------------
--- `pinned` is the difference between the two ways this popup opens.
---
--- Hovering a dragged garment over a layered slot opens it so the layer to
--- replace can be picked: that one belongs to the pointer and closes as soon
--- as the pointer moves away. Clicking the slot is a decision, and the popup
--- then stays put until it is clicked away - the layer strip is small, and a
--- window that vanishes on the first millimetre of mouse movement cannot be
--- read, let alone clicked into.
function NEQ_SuperSlot:setExpanded(expanded, pinned)
    if self.expanded == expanded then
        -- Re-opening an already open popup by hand still pins it: the drag may
        -- have opened it first.
        if self.expanded and pinned then self.pinned = true end
        return
    end

    self.expanded = expanded and self:getItemCount() > 1
    self.pinned = self.expanded and pinned == true

    if self.expanded then
        self:openPopup()
        local top = self:getTopSlot()
        self.controllerNode:setSelectedChild(top and top.controllerNode)
    else
        if self.popup.owner == self then
            self.popup.owner = nil
            self.popup:setVisible(false)
        end
        self.controllerNode:setSelectedChild(nil)
    end
end

function NEQ_SuperSlot:openPopup()
    -- One popup, one owner. A pinned popup left open on another slot would
    -- otherwise keep believing it is expanded while its sub-slots have already
    -- been adopted by this one.
    local previous = self.popup.owner
    if previous and previous ~= self then previous:setExpanded(false) end
    self.popup.owner = self

    -- Prima si riempie, poi lo si mette: il posto dipende da quanto e' grande,
    -- e la misura la decide applySlots. Nell'ordine di prima veniva posizionato
    -- con la misura del ventaglio precedente.
    local slots = {}
    for _, bodyLocation in ipairs(self.definition.bodyLocations) do
        local slot = self.slotsByBodyLocation[bodyLocation]
        if slot then table.insert(slots, slot) end
    end
    self.popup:applySlots(slots)
    self.popupSignature = self:layerSignature()

    self:placePopup()

    self.popup:setVisible(true)
    self.popup:bringToTop()
    self.body:bringTooltipToTop()
end

--- Dove va il ventaglio: **attaccato** allo slot, e dentro lo schermo.
---
--- I due pixel di stacco che c'erano sembravano niente ed erano il buco in cui
--- il puntatore non e' ne' sullo slot ne' sul ventaglio: passandoci sopra, la
--- prova "sono ancora qui?" diceva di no e il ventaglio si chiudeva sotto le
--- dita. Adesso i due si toccano.
---
--- Sotto se ci sta, sopra altrimenti: gli slot dell'ultima fila hanno il bordo
--- basso del pannello subito sotto, e un ventaglio disegnato oltre il bordo
--- dello schermo non si vede e non si clicca.
function NEQ_SuperSlot:placePopup()
    local w, h = self.popup:getWidth(), self.popup:getHeight()
    local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    local y = ay + self:getHeight()
    if y + h > screenH then y = ay - h end
    if y < 0 then y = 0 end

    local x = ax + self:mainX()
    if x + w > screenW then x = screenW - w end
    if x < 0 then x = 0 end

    self.popup:setX(x)
    self.popup:setY(y)
end

--- Il ventaglio deve dire quello che hai addosso **adesso**, e chiudersi quando
--- il puntatore se ne va davvero.
---
--- Sta in `update` e non in `prerender` per due motivi diversi. Il rifacimento
--- perche' `applySlots` aggiunge figli, e aggiungere figli mentre il motore
--- percorre l'albero per disegnarlo e' la lezione 12. La chiusura perche' e'
--- l'unico posto dove si puo' guardare **dov'e'** il puntatore a ogni giro:
--- gli eventi del mouse dicono di quanto si e' mosso, non dove sta.
function NEQ_SuperSlot:update()
    ISPanel.update(self)
    if not self.expanded then return end

    -- Togliendo uno strato con il ventaglio aperto, prima restava disegnato lo
    -- slot di un capo che non era piu' addosso, cliccabile e vuoto.
    local signature = self:layerSignature()
    if signature ~= self.popupSignature then
        if self:getItemCount() > 1 then
            self:openPopup()
        else
            self:setExpanded(false)
            return
        end
    end

    -- Il ventaglio segue il pannello. Prima si posizionava solo all'apertura,
    -- quindi trascinando il pannello restava indietro, staccato dal suo slot.
    self:placePopup()

    -- Aperto a mano resta aperto finche' non si clicca altrove: e' il patto di
    -- `pinned`. Con il controller il puntatore non c'entra.
    if self.pinned or self.isController then return end

    -- Mai mentre si sta portando via uno dei nostri capi: chiudere il ventaglio
    -- sotto un trascinamento partito da li' vuol dire nascondere lo slot da cui
    -- e' partito, a meta' del gesto.
    if self:isDraggingMyItem() then return end

    if not self:isMouseOver() and not self.popup:isMouseOver() then
        self:setExpanded(false)
    end
end

function NEQ_SuperSlot:getVisibleControllerNodes()
    if not self.expanded then return nil end

    local nodes = {}
    for _, slot in pairs(self.slotsByBodyLocation) do
        if slot:isVisible() then table.insert(nodes, slot.controllerNode) end
    end
    return nodes
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
function NEQ_SuperSlot:controllerNodeOnJoypadDown(button)
    if button == Joypad.BButton then
        self:setExpanded(not self.expanded)
        return true
    end
    if button == Joypad.XButton then
        self:unequip()
        return true
    end
    if button == Joypad.AButton then
        local item = self:getTopItem()
        if item then
            NEQ_Slot.openItemContextMenu(self, self.width, self.height / 2, item,
                self.inventoryPane, self.playerNum)
        end
        return true
    end
    return false
end

return NEQ_SuperSlot

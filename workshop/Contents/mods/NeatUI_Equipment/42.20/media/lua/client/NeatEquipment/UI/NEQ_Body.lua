--[[ ============================================================================
    NEQ_Body - the contents of the panel: avatar, slots, hotbar.

    Layout, top to bottom:

        left column   |  3D avatar  |  right column      (NEQ_SlotDefs)
                        primary / secondary hands
        --- other ---   any body location with no slot of its own
        --- hotbar ---  the real hotbar attachment points

    Everything is positioned from NEQ_State's metrics, so a resize is just
    "recompute and re-place" - no second set of numbers anywhere.

    Refreshing is event-driven. OnClothingUpdated marks the display dirty and the
    next prerender rebuilds; a cheap 250 ms snapshot comparison catches the cases
    where the engine does not fire the event (hands, hidden items). Nothing here
    rebuilds per frame.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanelJoypad"

local State          = require("NeatEquipment/NEQ_State")
local Style          = require("NeatEquipment/NEQ_Style")
local Tooltip        = require("NeatEquipment/NEQ_Tooltip")
local SlotDefs       = require("NeatEquipment/Definitions/NEQ_SlotDefs")
local NEQ_Slot       = require("NeatEquipment/UI/NEQ_Slot")
local NEQ_SuperSlot  = require("NeatEquipment/UI/NEQ_SuperSlot")
local NEQ_WeaponSlot = require("NeatEquipment/UI/NEQ_WeaponSlot")
local NEQ_HotbarSlot = require("NeatEquipment/UI/NEQ_HotbarSlot")
local NEQ_Avatar     = require("NeatEquipment/UI/NEQ_Avatar")

local FALLBACK_CHECK_MS = 250

-- Both pools are filled once, when the panel is built, and never grown again.
--
-- The slots used to be created on demand, which meant addChild running from
-- inside prerender - that is, adding a child to the tree while the engine is
-- walking that same tree to draw it. It survives most of the time and then does
-- not, and when it does not the whole panel stops updating: slots freeze on
-- whatever they were showing, which is why a screwdriver could sit in a hand
-- the panel never admitted to.
--
-- These are ceilings, not limits anyone will meet: eleven body locations have a
-- slot of their own already, and a survivor wearing twelve *further* ones, or
-- carrying twenty hotbar attachments, is not a case worth risking the tree for.
-- Alzati dopo una segnalazione: con le mod che aggiungono agganci si arriva
-- davvero a diciotto slot di barra rapida, che col vecchio tetto di venti
-- stava per un pelo. Sono elementi nascosti tenuti da parte, non costano
-- niente finche' non servono.
local EXTRA_SLOT_POOL = 20
local HOTBAR_SLOT_POOL = 36

-- Oltre questo, la sezione della barra rapida si **stringe** invece di
-- allungarsi.
--
-- Senza freno il conto e' questo: diciotto slot a scala 1.8 fanno cinque
-- righe da 76 px e portano il pannello a 1029 px, cioe' piu' alto di uno
-- schermo 1080 - e la barra rapida sta in fondo, quindi e' proprio lei a
-- finire fuori. In piu' il numero di colonne a scala 1 viene esattamente 5.0:
-- sul filo, e un pelo di scala in piu' lo fa cadere a 4, che vuol dire una
-- riga intera in piu' di colpo. Da agganciato quel salto entra nella rincorsa
-- dell'altezza e la fa oscillare.
local MAX_HOTBAR_ROWS = 3

-- OnClothingUpdated is global, so the live displays register themselves here to
-- be found by player number.
local ACTIVE_BY_PLAYER = {}

-- Il personaggio puo' essere uno zombie a cui una mod sta cambiando i vestiti:
-- l'evento e' globale davvero. Vedi State.localPlayerNum.
local function onClothingUpdated(character)
    local playerNum = State.localPlayerNum(character)
    if not playerNum then return end
    local body = ACTIVE_BY_PLAYER[playerNum]
    if body then body.checkRequested = true end
end

Events.OnClothingUpdated.Add(onClothingUpdated)

---@class NEQ_Body : ISPanelJoypad
local NEQ_Body = ISPanelJoypad:derive("NEQ_Body")

function NEQ_Body:new(x, y, width, inventoryPane, playerNum, popup)
    local o = ISPanelJoypad:new(x, y, width, 10)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.inventoryPane = inventoryPane
    o.playerNum = playerNum
    o.char = getSpecificPlayer(playerNum)
    o.popup = popup

    o.superSlots = {}
    o.superSlotsByBodyLocation = {}
    o.extraSlotPool = {}
    o.extraSlotsByBodyLocation = {}
    o.hotbarSlots = {}
    o.hotbarSlotPool = {}

    o.wornSnapshot = {}
    o.hotbarSnapshot = {}
    o.snapshotReady = false
    o.hotbarSnapshotReady = false
    o.checkRequested = true
    o.nextFallbackCheck = 0

    o.sectionOtherY = nil
    o.sectionHotbarY = nil

    o.onHotbarRefresh = function(hotbar) o:refreshHotbarLayout(hotbar, false) end

    return o
end

function NEQ_Body:createChildren()
    ISPanelJoypad.createChildren(self)

    self:createAvatar()
    self:createSuperSlots()
    self:createWeaponSlots()
    self:createSlotPools()

    State:addScaleListener(self, NEQ_Body.onScaleChanged)
    State:addHideHotbarListener(self, NEQ_Body.onHideHotbarChanged)
    ACTIVE_BY_PLAYER[self.playerNum] = self

    self:layout()
    self:refreshIfNeeded(true)
    self:ensureHotbarHook()
end

--- The resize grip is parented here rather than to the panel, and that is the
--- whole fix for "the corner handle does nothing".
---
--- The grip sat where it looks like it should: a child of the panel, drawn last
--- and flagged always-on-top. It rendered in the right place and never received
--- a click, because this body is also a child of the panel and it covers the
--- entire panel below the header - including that corner. Whatever order the
--- engine hit-tests siblings in, a full-size sibling in the way is a coin flip
--- worth not taking. Inside the body it is a child among the slots, and the
--- slots have always received their clicks.
---
--- Added last so it sits above the slot pools; nothing else reaches that corner
--- anyway.
function NEQ_Body:attachGrip(grip)
    self.grip = grip
    self:addChild(grip)
end

--- Bottom-right of the body, which is bottom-right of the panel: the body's
--- height is the panel's height minus the header.
function NEQ_Body:positionGrip(size, visible)
    if not self.grip then return end

    self.grip:setVisible(visible)
    if not visible then return end

    self.grip:setWidth(size)
    self.grip:setHeight(size)
    self.grip:setX(self:getWidth() - size)
    self.grip:setY(self:getHeight() - size)
end

function NEQ_Body:dispose()
    if ACTIVE_BY_PLAYER[self.playerNum] == self then
        ACTIVE_BY_PLAYER[self.playerNum] = nil
    end
    self:releaseHotbarHook()
    State:removeListeners(self)
end

-- ---------------------------------------------------------------------------
-- Children
-- ---------------------------------------------------------------------------
function NEQ_Body:createAvatar()
    self.avatar = NEQ_Avatar:new(0, 0, 10, 10, self.playerNum)
    self.avatar:initialise()
    self.avatar:instantiate()
    self:addChild(self.avatar)
end

function NEQ_Body:createSuperSlots()
    for _, definition in ipairs(SlotDefs) do
        local slot = NEQ_SuperSlot:new(definition, self, self.inventoryPane, self.playerNum, self.popup)
        slot:initialise()
        self:addChild(slot)
        table.insert(self.superSlots, slot)

        for _, bodyLocation in ipairs(definition.bodyLocations) do
            local list = self.superSlotsByBodyLocation[bodyLocation]
            if not list then
                list = {}
                self.superSlotsByBodyLocation[bodyLocation] = list
            end
            table.insert(list, slot)
        end
    end
end

function NEQ_Body:createWeaponSlots()
    self.primarySlot = NEQ_WeaponSlot:new(self, self.inventoryPane, self.playerNum, false)
    self.primarySlot:initialise()
    self:addChild(self.primarySlot)

    self.secondarySlot = NEQ_WeaponSlot:new(self, self.inventoryPane, self.playerNum, true)
    self.secondarySlot:initialise()
    self:addChild(self.secondarySlot)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
-- layout() chains into updateExtraSlots() and from there into the hotbar
-- section, so one call re-places everything.
function NEQ_Body:onScaleChanged()
    self:setWidth(State.contentW)
    self:layout()
end

--- Places the avatar, the two columns and the hands, then hands off to the
--- extra / hotbar sections, which own the rest of the height.
function NEQ_Body:layout()
    local w = self:getWidth()
    local pad, gapY = State.pad, State.gapY
    local super, strip = State.superSize, State.subStrip

    local leftX = pad
    local rightMainX = w - pad - super
    local rightX = rightMainX - strip

    -- Rows per column come straight from the definitions.
    local rows = { left = 0, right = 0 }
    for _, slot in ipairs(self.superSlots) do
        local column = slot.definition.column
        rows[column] = math.max(rows[column] or 0, slot.definition.row)
    end

    -- Slots draw their name in a pill just above themselves. The top row needs
    -- somewhere to put it, or the label lands on the panel header.
    local top = pad + Style.slotLabelHeight(UIFont.Small) + 2

    local tallest = math.max(rows.left, rows.right)
    local columnH = tallest * super + math.max(0, tallest - 1) * gapY

    -- The two columns rarely have the same number of slots. Centring the
    -- shorter one against the taller keeps the avatar flanked evenly instead of
    -- leaving a hole in one bottom corner.
    local columnTop = {}
    for _, side in ipairs({ "left", "right" }) do
        local count = rows[side]
        local height = count * super + math.max(0, count - 1) * gapY
        columnTop[side] = top + math.floor((columnH - height) / 2)
    end

    for _, slot in ipairs(self.superSlots) do
        local def = slot.definition
        slot:setX(def.column == "right" and rightX or leftX)
        slot:setY(columnTop[def.column] + (def.row - 1) * (super + gapY))
    end

    -- Hands go in the bottom corners rather than in a row under the middle.
    -- The corners were empty - the columns are the same height and the space
    -- below them was doing nothing - and moving the hands there hands the whole
    -- middle of the panel back to the character.
    local weapon = State.weaponSize
    local handsY = top + columnH + gapY

    self.primarySlot:setX(pad)
    self.primarySlot:setY(handsY)
    self.secondarySlot:setX(w - pad - weapon)
    self.secondarySlot:setY(handsY)

    self.avatarBlockBottom = handsY + weapon

    -- The model box: as tall as everything above, and exactly half as wide.
    --
    -- The ratio is not decoration. ISUI3DModel frames a full body against the
    -- box it is given, and vanilla's own full-length preview is a box half as
    -- wide as it is tall at zoom -3; a box wider than that wastes the space,
    -- one narrower crops the character. So the height is decided first - the
    -- whole column stack plus the hands row, since the hands are out at the
    -- corners now - and the width follows from it.
    --
    -- With no frame around it the box may overlap the slot columns: what hangs
    -- over the edge is transparent, and an idle survivor stands well inside it.
    local modelH = math.max(40, self.avatarBlockBottom - pad)
    local modelW = math.floor(modelH * 0.5)
    self.avatar:setX(math.floor((w - modelW) / 2))
    self.avatar:setY(pad)
    self.avatar:setWidth(modelW)
    self.avatar:setHeight(modelH)

    self:updateExtraSlots()
end

--- Grid geometry shared by the extra and hotbar sections.
local function gridColumns(width, pad, size, gap)
    return math.max(1, math.floor((width - pad * 2 + gap) / (size + gap)))
end

--- La misura degli slot della barra rapida che tiene la sezione dentro il
--- budget di righe.
---
--- Si stringe un pixel alla volta finche' le righe non ci stanno, e non si
--- scende mai sotto uno slot dell'equipaggiamento: sotto quella misura la
--- sezione smetterebbe di leggersi come la parte importante del pannello, che
--- e' il motivo per cui questi slot nascono piu' grandi degli altri. Con
--- pochi agganci non cambia niente e la misura resta quella piena.
local function fitHotbarSize(width, pad, gap, size, count)
    local floorSize = math.min(size, State.slotSize)
    while size > floorSize do
        if math.ceil(count / gridColumns(width, pad, size, gap)) <= MAX_HOTBAR_ROWS then
            break
        end
        size = size - 1
    end
    return size
end

--- Where row `row` (0-based) of a grid starts. Every row is centred on its own,
--- so a hotbar of eight reads as five over three centred under each other
--- rather than five with three hanging off the left.
local function rowStartX(width, pad, size, gap, columns, count, row)
    local inThisRow = math.min(columns, count - row * columns)
    local used = math.max(0, inThisRow * (size + gap) - gap)
    return pad + math.max(0, math.floor((width - pad * 2 - used) / 2))
end

--- Rebuilds the "other" section: every worn body location that has no slot of
--- its own around the avatar (mod-added locations, mostly).
function NEQ_Body:updateExtraSlots()
    for key, slot in pairs(self.extraSlotsByBodyLocation) do
        slot:setVisible(false)
        table.insert(self.extraSlotPool, slot)
        self.extraSlotsByBodyLocation[key] = nil
    end

    local w = self:getWidth()
    local pad, gapX, gapY = State.pad, State.gapX, State.gapY
    local size = State.slotSize
    local columns = gridColumns(w, pad, size, gapX)

    -- The gap between a section title and its grid is a whole label tall: the
    -- slots below draw their hover name into it.
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local headerH = fontH + Style.slotLabelHeight(UIFont.Small)

    local sectionTop = self.avatarBlockBottom + State.sectionGap
    local gridTop = sectionTop + headerH

    -- Collected first so the grid knows how wide it will be before placing
    -- anything; a short row is centred rather than left-aligned.
    local pending = {}
    local seen = {}
    local worn = self.char:getWornItems()
    for i = 1, worn:size() do
        local wornItem = worn:get(i - 1)
        local item = wornItem:getItem()
        if item and not item:isHidden() then
            local bodyLocation = wornItem:getLocation()
            if not self.superSlotsByBodyLocation[bodyLocation] and not seen[bodyLocation] then
                seen[bodyLocation] = true
                table.insert(pending, { location = bodyLocation, item = item })
            end
        end
    end

    -- Il numero su cui centrare le righe e' quello che si riesce davvero a
    -- posare, non quello che si vorrebbe: il serbatoio ha un tetto.
    local count = math.min(#pending, #self.extraSlotPool)
    local placed = 0

    local column, row = 0, 0
    for _, entry in ipairs(pending) do
        if column >= columns then
            column = 0
            row = row + 1
        end

        local slot = self:acquireExtraSlot(entry.location)
        if not slot then break end

        slot:setX(rowStartX(w, pad, size, gapX, columns, count, row) + column * (size + gapX))
        slot:setY(gridTop + row * (size + gapY))
        slot:setItem(entry.item)
        self.extraSlotsByBodyLocation[entry.location] = slot

        placed = placed + 1
        column = column + 1
    end

    -- What was actually placed, not what was wanted: the pool has a ceiling and
    -- the section has to be measured against what is on screen.
    count = placed
    self.extraCount = count
    if count > 0 then
        self.sectionOtherY = sectionTop
        local usedRows = math.ceil(count / columns)
        self.extraBottom = gridTop + usedRows * size + math.max(0, usedRows - 1) * gapY
    else
        self.sectionOtherY = nil
        self.extraBottom = self.avatarBlockBottom
    end

    self:refreshHotbarLayout(getPlayerHotbar(self.playerNum), true)
end

--- Every slot either pool will ever hand out, built here where adding to the
--- tree is safe. See the note by EXTRA_SLOT_POOL.
function NEQ_Body:createSlotPools()
    for _ = 1, EXTRA_SLOT_POOL do
        local slot = NEQ_Slot:new(0, 0, nil, self, self.inventoryPane, self.playerNum)
        slot:initialise()
        self:addChild(slot)
        slot:setVisible(false)
        table.insert(self.extraSlotPool, slot)
    end

    local hotbar = getPlayerHotbar(self.playerNum)
    for _ = 1, HOTBAR_SLOT_POOL do
        local slot = NEQ_HotbarSlot:new(hotbar, self, self.inventoryPane, self.playerNum)
        slot:initialise()
        self:addChild(slot)
        slot:setVisible(false)
        table.insert(self.hotbarSlotPool, slot)
    end
end

---@return NEQ_Slot|nil nil once the pool is exhausted
function NEQ_Body:acquireExtraSlot(bodyLocation)
    local pooled = table.remove(self.extraSlotPool)
    if not pooled then return nil end

    pooled.bodyLocation = bodyLocation
    pooled:setItem(nil)
    pooled:setVisible(true)
    return pooled
end

-- ---------------------------------------------------------------------------
-- Hotbar section
-- ---------------------------------------------------------------------------
function NEQ_Body:onHideHotbarChanged(hide)
    if hide then
        self:releaseHotbarSlots()
        self:releaseHotbarHook()
        self.hotbarSnapshotReady = false
        table.wipe(self.hotbarSnapshot)
        self:finishHeight()
        return
    end

    -- ensureHotbarHook only rebuilds when the hook itself changes, and it will
    -- not have: force the section back into existence.
    self:ensureHotbarHook()
    self:refreshHotbarLayout(getPlayerHotbar(self.playerNum), true)
end

function NEQ_Body:ensureHotbarHook()
    if State.hideHotbar then
        self:releaseHotbarHook()
        return
    end

    local hotbar = getPlayerHotbar(self.playerNum)
    if not hotbar then return end

    if self.hookedHotbar and self.hookedHotbar ~= hotbar
        and self.hookedHotbar.neq_onRefresh == self.onHotbarRefresh then
        self.hookedHotbar.neq_onRefresh = nil
    end

    if self.hookedHotbar ~= hotbar or hotbar.neq_onRefresh ~= self.onHotbarRefresh then
        hotbar.neq_onRefresh = self.onHotbarRefresh
        self.hookedHotbar = hotbar
        self:refreshHotbarLayout(hotbar, true)
    end
end

function NEQ_Body:releaseHotbarHook()
    if self.hookedHotbar and self.hookedHotbar.neq_onRefresh == self.onHotbarRefresh then
        self.hookedHotbar.neq_onRefresh = nil
    end
    self.hookedHotbar = nil
end

--- The slot list only changes when the player puts on or takes off something
--- that carries attachment points, so compare before rebuilding.
function NEQ_Body:hotbarSlotsChanged(hotbar)
    if not hotbar then return false end
    if not self.hotbarSnapshotReady then return true end

    local slots = hotbar.availableSlot
    if #self.hotbarSnapshot ~= #slots then return true end

    for i, slot in ipairs(slots) do
        local snapshot = self.hotbarSnapshot[i]
        if not snapshot or snapshot.slotType ~= slot.slotType or snapshot.def ~= slot.def then
            return true
        end
    end
    return false
end

function NEQ_Body:captureHotbarSnapshot(hotbar)
    table.wipe(self.hotbarSnapshot)
    if not hotbar then
        self.hotbarSnapshotReady = false
        return
    end
    for i, slot in ipairs(hotbar.availableSlot) do
        self.hotbarSnapshot[i] = { slotType = slot.slotType, def = slot.def }
    end
    self.hotbarSnapshotReady = true
end

function NEQ_Body:refreshHotbarLayout(hotbar, force)
    if State.hideHotbar or not hotbar then
        self:releaseHotbarSlots()
        self:finishHeight()
        return
    end
    if not force and not self:hotbarSlotsChanged(hotbar) then return end

    self:releaseHotbarSlots()

    local w = self:getWidth()
    local pad, gapX, gapY = State.pad, State.gapX, State.gapY

    -- Quanti se ne possono davvero mettere: il serbatoio ha un tetto, e i
    -- conti della griglia devono partire da quel numero. Prima partivano dal
    -- numero voluto, quindi con il serbatoio esaurito l'ultima riga veniva
    -- centrata per slot che non sarebbero mai stati posati.
    local count = math.min(#hotbar.availableSlot, #self.hotbarSlotPool)

    local size = fitHotbarSize(w, pad, gapX, State.hotbarSize, count)
    local columns = gridColumns(w, pad, size, gapX)

    -- The gap between a section title and its grid is a whole label tall: the
    -- slots below draw their hover name into it.
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local headerH = fontH + Style.slotLabelHeight(UIFont.Small)

    local sectionTop = (self.extraBottom or self.avatarBlockBottom) + State.sectionGap
    local gridTop = sectionTop + headerH

    local placed = 0
    local column, row = 0, 0
    for i = 1, count do
        if column >= columns then
            column = 0
            row = row + 1
        end

        local slot = self:acquireHotbarSlot(hotbar)
        if not slot then break end

        slot.index = i
        slot:setWidth(size)
        slot:setHeight(size)
        slot:setX(rowStartX(w, pad, size, gapX, columns, count, row) + column * (size + gapX))
        slot:setY(gridTop + row * (size + gapY))

        placed = placed + 1
        column = column + 1
    end

    count = placed
    if count > 0 then
        self.sectionHotbarY = sectionTop
        local usedRows = math.ceil(count / columns)
        self.hotbarBottom = gridTop + usedRows * size + math.max(0, usedRows - 1) * gapY
    else
        self.sectionHotbarY = nil
        self.hotbarBottom = nil
    end

    self:captureHotbarSnapshot(hotbar)
    self:finishHeight()
end

--- From the front, not the back: the slots are laid out in order and a
--- controller walks them in the order they were created.
---@return NEQ_HotbarSlot|nil nil once the pool is exhausted
function NEQ_Body:acquireHotbarSlot(hotbar)
    local pooled = table.remove(self.hotbarSlotPool, 1)
    if not pooled then return nil end

    -- A pooled slot may predate the current hotbar object (respawn, player
    -- switch); re-point it before it is used again.
    pooled.hotbar = hotbar
    pooled:setVisible(true)
    table.insert(self.hotbarSlots, pooled)
    return pooled
end

function NEQ_Body:releaseHotbarSlots()
    for _, slot in ipairs(self.hotbarSlots) do
        slot:setVisible(false)
        slot.index = nil
        table.insert(self.hotbarSlotPool, slot)
    end
    table.wipe(self.hotbarSlots)
    self.sectionHotbarY = nil
    self.hotbarBottom = nil
end

--- The panel asks for this height; it is the only thing that decides how tall
--- the window is.
function NEQ_Body:finishHeight()
    local bottom = self.hotbarBottom or self.extraBottom or self.avatarBlockBottom or 0
    self:setHeight(bottom + State.pad)
end

--- What this body is currently made of, as a string to compare.
---
--- The docked panel resizes itself to meet the bottom of the inventory, and
--- gives up after a few tries so it cannot chase a target forever. That budget
--- has to be handed back when the *contents* change, not only when the
--- inventory moves: putting on a belt adds hotbar slots, which adds a row,
--- which makes the panel taller than the window it is hanging from - and
--- taking the belt off again used to leave the panel shrunk, with no way back
--- but detaching and re-docking it by hand.
---
--- Counts, deliberately, and never rows or heights: rows depend on the width,
--- the width depends on the scale, and the scale is what this signature is used
--- to decide. A signature that moved with the scale would reset the budget it
--- is supposed to be spending, and the panel would resize forever.
function NEQ_Body:layoutSignature()
    return #self.hotbarSlots .. ":" .. (self.extraCount or 0)
        .. ":" .. (State.hideHotbar and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- Worn item tracking
-- ---------------------------------------------------------------------------
function NEQ_Body:stateChanged()
    if not self.snapshotReady then return true end

    local worn = self.char:getWornItems()
    if #self.wornSnapshot ~= worn:size() then return true end

    for i = 1, worn:size() do
        local wornItem = worn:get(i - 1)
        local item = wornItem:getItem()
        local snapshot = self.wornSnapshot[i]
        if not snapshot
            or snapshot.item ~= item
            or snapshot.location ~= wornItem:getLocation()
            or snapshot.hidden ~= item:isHidden() then
            return true
        end
    end

    if self.primaryHand ~= self.char:getPrimaryHandItem() then return true end
    if self.secondaryHand ~= self.char:getSecondaryHandItem() then return true end

    -- Holstered and slung items are not worn items and are not in a hand, but
    -- they are on the model: a rifle moved to the back changes the preview and
    -- nothing above would have noticed.
    if self:attachedSignature() ~= self.attachedSig then return true end

    return false
end

--- A cheap string standing for "what is attached to the hotbar right now".
--- Compared, never parsed.
function NEQ_Body:attachedSignature()
    local hotbar = getPlayerHotbar(self.playerNum)
    if not hotbar then return "" end

    local parts = {}
    for index, slot in ipairs(hotbar.availableSlot) do
        local item = hotbar.attachedItems[index]
        parts[#parts + 1] = tostring(slot.slotType) .. "="
            .. (item and tostring(item:getID()) or "-")
    end
    return table.concat(parts, ",")
end

function NEQ_Body:captureSnapshot()
    table.wipe(self.wornSnapshot)

    local worn = self.char:getWornItems()
    for i = 1, worn:size() do
        local wornItem = worn:get(i - 1)
        local item = wornItem:getItem()
        self.wornSnapshot[i] = {
            item = item,
            location = wornItem:getLocation(),
            hidden = item:isHidden(),
        }
    end

    self.primaryHand = self.char:getPrimaryHandItem()
    self.secondaryHand = self.char:getSecondaryHandItem()
    self.attachedSig = self:attachedSignature()
    self.snapshotReady = true
end

function NEQ_Body:refreshIfNeeded(force)
    local now = getTimestampMs()
    if not force and not self.checkRequested and now < self.nextFallbackCheck then
        return
    end

    self.checkRequested = false
    self.nextFallbackCheck = now + FALLBACK_CHECK_MS

    if not self:stateChanged() then return end

    self:updateExtraSlots()
    self:updateSlotItems()
    self:captureSnapshot()

    if self.avatar then self.avatar:refresh() end
end

function NEQ_Body:updateSlotItems()
    for _, slot in pairs(self.extraSlotsByBodyLocation) do
        slot:clearItem()
    end
    for _, superSlot in ipairs(self.superSlots) do
        superSlot:clearItem()
    end

    local worn = self.char:getWornItems()
    for i = 1, worn:size() do
        local wornItem = worn:get(i - 1)
        local bodyLocation = wornItem:getLocation()
        local item = wornItem:getItem()

        local list = self.superSlotsByBodyLocation[bodyLocation]
        if list then
            for _, slot in ipairs(list) do
                slot:setItem(item, bodyLocation)
            end
        end

        local extra = self.extraSlotsByBodyLocation[bodyLocation]
        if extra then extra:setItem(item) end
    end
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
function NEQ_Body:prerender()
    self:refreshIfNeeded(false)
    if not State.hideHotbar then self:ensureHotbarHook() end

    local pad = State.pad
    local w = self:getWidth()

    if self.sectionOtherY then
        Style.drawSectionHeader(self, getText("UI_NEQ_section_other"),
            pad, self.sectionOtherY, w - pad * 2, UIFont.Small)
    end
    if self.sectionHotbarY then
        Style.drawSectionHeader(self, getText("UI_NEQ_section_hotbar"),
            pad, self.sectionHotbarY, w - pad * 2, UIFont.Small)
    end
end

--- Slots handle their own mouse presses; swallowing them here would break the
--- panel drag started on empty space.
function NEQ_Body:onMouseDown(x, y)
    return false
end

-- ---------------------------------------------------------------------------
-- Tooltip plumbing (shared with the inventory pane)
-- ---------------------------------------------------------------------------
function NEQ_Body:doTooltipForItem(owner, item)
    self.tooltipOwner = owner

    -- A controller player has no pointer for the tooltip to follow, so it is
    -- anchored instead.
    local followMouse = not (owner and owner.controllerNode and owner.controllerNode.isFocused)
    Tooltip.show(self.inventoryPane, self.playerNum, item, followMouse)
end

function NEQ_Body:bringTooltipToTop()
    Tooltip.bringToTop(self.inventoryPane)
end

function NEQ_Body:closeTooltip()
    Tooltip.hide(self.inventoryPane)
    self.tooltipOwner = nil
end

local function contains(haystack, needle)
    for _, v in pairs(haystack) do
        if v == needle then return true end
    end
    return false
end

--- Called by the patched ISInventoryPane:updateTooltip while the pointer is
--- over this panel: closes the tooltip as soon as its owner stops being hovered.
function NEQ_Body:updateTooltip()
    if not self.inventoryPane.toolRender then return end

    local owner = nil
    for _, child in pairs(self.children) do
        if child:isMouseOver() or (child.controllerNode and child.controllerNode.isFocused) then
            owner = child
        end
    end

    if not owner and self.popup
        and (self.popup:isMouseOver() or self.popup.controllerNode.isFocused) then
        owner = self.popup
    end

    if not owner
        or (self.tooltipOwner ~= owner
            and (not owner.children or not contains(owner.children, self.tooltipOwner))) then
        self:closeTooltip()
    end
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
function NEQ_Body:getControllerNodes()
    local nodes = {}

    for _, slot in ipairs(self.superSlots) do
        table.insert(nodes, slot.controllerNode)
    end
    table.insert(nodes, self.primarySlot.controllerNode)
    table.insert(nodes, self.secondarySlot.controllerNode)
    for _, slot in pairs(self.extraSlotsByBodyLocation) do
        table.insert(nodes, slot.controllerNode)
    end
    if not State.hideHotbar then
        for _, slot in ipairs(self.hotbarSlots) do
            table.insert(nodes, slot.controllerNode)
        end
    end

    return nodes
end

return NEQ_Body

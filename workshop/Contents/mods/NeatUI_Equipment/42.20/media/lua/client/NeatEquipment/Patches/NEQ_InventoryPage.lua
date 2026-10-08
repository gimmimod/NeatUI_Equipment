--[[ ============================================================================
    NEQ_InventoryPage - attaches the panel to the character inventory window.

    Everything is hooked from OnGameBoot rather than at file load. CleanUI
    replaces ISInventoryPage wholesale; hooking at load time would capture
    whichever version happened to be defined first, and mod load order is not
    something to rely on. By OnGameBoot every mod's Lua has been read, so the
    function we wrap is the one that will actually run.

    The pin dance in the mouse handlers is there because the inventory window
    collapses itself when the pointer wanders off it, and it has no idea our
    panel is part of the same thing, so the pin flag is raised for the duration
    of the vanilla call and put back afterwards.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISInventoryPage"

local NEQ_Panel      = require("NeatEquipment/UI/NEQ_Panel")
local NEQ_ToggleButton = require("NeatEquipment/UI/NEQ_ToggleButton")
local NEQ_DragRenderer = require("NeatEquipment/UI/NEQ_DragRenderer")
local Tetris         = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")
local State          = require("NeatEquipment/NEQ_State")

NEQ_InventoryPage = NEQ_InventoryPage or {}
local P = NEQ_InventoryPage

local panelsByPlayer = {}

---@return NEQ_Panel|nil
function P.getPanel(playerNum)
    return panelsByPlayer[playerNum]
end

--- Toggled by the key binding and by the controller button.
function P.togglePanel(playerNum)
    if State.disabled then return end
    local panel = panelsByPlayer[playerNum]
    if not panel then return end
    panel:togglePanel()
end

-- ---------------------------------------------------------------------------
-- Creation
-- ---------------------------------------------------------------------------
local function attachTo(page)
    local playerNum = page.player
    if not page.onCharacter or not playerNum then return end
    if page.neqEquipmentPanel then return end

    -- Inventory Tetris porta con se' Equipment UI e lo attacca a questo stesso
    -- bordo. Prima di posare il nostro si leva il loro: vedi il file.
    Tetris.takeOverFrom(page)

    local panel = NEQ_Panel:new(page.inventoryPane, playerNum)
    panel:initialise()
    panel:addToUIManager()

    local toggle = NEQ_ToggleButton:new(panel)
    toggle:initialise()
    toggle:addToUIManager()
    panel.toggleButton = toggle

    -- addToUIManager shows whatever it adds; the panel may well have been left
    -- closed. The toggle re-derives this every frame, but not before the first
    -- one has been drawn.
    panel:updateVisibility()

    -- Sotto Tetris l'oggetto trascinato lo disegnano loro: il nostro lo
    -- disegnerebbe una seconda volta, sfalsato.
    local dragRenderer = nil
    if Tetris.wantsDragRenderer() then
        dragRenderer = NEQ_DragRenderer:new(page.inventoryPane, playerNum)
        dragRenderer:initialise()
        dragRenderer:addToUIManager()
    end

    page.neqEquipmentPanel = panel
    panelsByPlayer[playerNum] = panel

    -- The panel and its helpers are owned by this window: when it goes, so do
    -- they. Il disegnatore del trascinamento puo' non esserci: sotto Tetris
    -- quel lavoro e' loro.
    local og_removeFromUIManager = page.removeFromUIManager
    page.removeFromUIManager = function(self)
        og_removeFromUIManager(self)
        if dragRenderer then dragRenderer:removeFromUIManager() end
        panel:removeFromUIManager()
        if panelsByPlayer[playerNum] == panel then panelsByPlayer[playerNum] = nil end
        self.neqEquipmentPanel = nil
    end

    local og_bringToTop = page.bringToTop
    page.bringToTop = function(self)
        og_bringToTop(self)
        if panel:isVisible() and panel.docked then panel:bringToTop() end
    end
end

-- ---------------------------------------------------------------------------
-- Keeping the inventory from collapsing over our own panel
-- ---------------------------------------------------------------------------
local function isOver(element)
    if not element or not element:isVisible() then return false end
    local mx, my = getMouseX(), getMouseY()
    local x, y = element:getAbsoluteX(), element:getAbsoluteY()
    return mx >= x and mx <= x + element:getWidth()
        and my >= y and my <= y + element:getHeight()
end

local function isMouseOverEquipment(page)
    local panel = page.neqEquipmentPanel
    if not panel or panel.playerNum ~= 0 then return false end
    if isOver(panel) then return true end
    if isOver(panel.toggleButton) then return true end
    if panel.popup and panel.popup:isVisible() and isOver(panel.popup) then return true end
    return false
end

--- Runs `fn` with the inventory window pinned, so its own "pointer left me"
--- logic does not fire while the pointer is really on our panel.
local function withPin(page, fn, ...)
    local panel = page.neqEquipmentPanel
    if panel and panel.docked and isMouseOverEquipment(page) then
        local wasPinned = page.pin
        page.pin = true
        local result = fn(...)
        page.pin = wasPinned
        return result
    end
    return fn(...)
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------
local hooked = false

local function installHooks()
    if hooked then return end
    hooked = true

    local og_createChildren = ISInventoryPage.createChildren
    function ISInventoryPage:createChildren()
        -- Prima della catena, non dopo: sotto Tetris + CleanUI il pannello si
        -- rompe **dentro** og_createChildren, e porta giu' createPlayerData con
        -- se'. Qui e' il primo momento in cui tutti gli OnGameBoot sono passati
        -- e non esiste ancora nessun pannello. La chiamata e' a vuoto se
        -- Tetris non c'e'.
        Tetris.installPaneShim()

        og_createChildren(self)
        attachTo(self)
    end

    function ISInventoryPage:isMouseOverNeatEquipment()
        return isMouseOverEquipment(self)
    end

    local og_onMouseDownOutside = ISInventoryPage.onMouseDownOutside
    function ISInventoryPage:onMouseDownOutside(x, y)
        return withPin(self, og_onMouseDownOutside, self, x, y)
    end

    local og_onRightMouseDownOutside = ISInventoryPage.onRightMouseDownOutside
    function ISInventoryPage:onRightMouseDownOutside(x, y)
        return withPin(self, og_onRightMouseDownOutside, self, x, y)
    end

    local og_onMouseMoveOutside = ISInventoryPage.onMouseMoveOutside
    function ISInventoryPage:onMouseMoveOutside(dx, dy)
        return withPin(self, og_onMouseMoveOutside, self, dx, dy)
    end
end

Events.OnGameBoot.Add(installHooks)

-- ---------------------------------------------------------------------------
-- Key binding
-- ---------------------------------------------------------------------------
local function onKeyPressed(key)
    if key ~= getCore():getKey("neq_toggle_equipment") then return end
    P.togglePanel(0)
end

Events.OnKeyPressed.Add(onKeyPressed)

return P

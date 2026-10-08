--[[ ============================================================================
    NEQ_Tooltip - shows the vanilla item tooltip for an equipment slot.

    The panel deliberately reuses the inventory pane's own ISToolTipInv rather
    than making a second one: that is what keeps a single tooltip on screen when
    the pointer moves between the inventory list and a slot, and it is also what
    UIManager.setPlayerInventoryTooltip expects to be told about.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISToolTipInv"

NEQ_Tooltip = NEQ_Tooltip or {}
local T = NEQ_Tooltip

--- Keeps the engine's idea of the two inventory tooltips in step with ours.
local function syncEngineTooltips(playerNum)
    -- Il pannello interno va chiesto e non dato per scontato: mentre le
    -- finestre vengono smontate - morte del personaggio, disconnessione da un
    -- server - la pagina c'e' ancora e il suo pannello no.
    local inventoryPage = getPlayerInventory(playerNum)
    local inventoryPane = inventoryPage and inventoryPage.inventoryPane
    local inventoryTooltip = inventoryPane and inventoryPane.toolRender

    local lootPage = getPlayerLoot(playerNum)
    local lootPane = lootPage and lootPage.inventoryPane
    local lootTooltip = lootPane and lootPane.toolRender

    UIManager.setPlayerInventoryTooltip(playerNum,
        inventoryTooltip and inventoryTooltip.javaObject or nil,
        lootTooltip and lootTooltip.javaObject or nil)
end

---@param pane ISInventoryPane
---@param item InventoryItem
function T.show(pane, playerNum, item, followMouse)
    local page = pane.parent
    if not page or not page:isVisible() then return end

    local weightOfStack = 0.0
    if item and not instanceof(item, "InventoryItem") then
        if item.items and #item.items > 2 then weightOfStack = item.weight end
        item = item.items and item.items[1] or nil
    end

    local context = getPlayerContextMenu(playerNum)
    if not context then return end
    -- A tooltip on top of an open context menu is just noise.
    if context:isAnyVisible() then item = nil end

    if item and pane.toolRender and item == pane.toolRender.item
        and pane.toolRender.tooltip
        and weightOfStack == pane.toolRender.tooltip:getWeightOfStack()
        and pane.toolRender:isVisible() then
        return
    end

    if item and not ISMouseDrag.dragging then
        if pane.toolRender then
            pane.toolRender:setItem(item)
            pane.toolRender:setVisible(true)
            pane.toolRender:addToUIManager()
            pane.toolRender:bringToTop()
        else
            pane.toolRender = ISToolTipInv:new(item)
            pane.toolRender:initialise()
            pane.toolRender:addToUIManager()
            pane.toolRender:setVisible(true)
            pane.toolRender:setOwner(pane)
            pane.toolRender:setCharacter(getSpecificPlayer(playerNum))
            pane.toolRender.anchorBottomLeft = {
                x = pane:getAbsoluteX() + (pane.column2 or 0),
                y = page:getAbsoluteY(),
            }
        end

        pane.toolRender.followMouse = followMouse ~= false
        if pane.toolRender.tooltip then
            pane.toolRender.tooltip:setWeightOfStack(weightOfStack)
        end
    elseif pane.toolRender then
        pane.toolRender:removeFromUIManager()
        pane.toolRender:setVisible(false)
    end

    syncEngineTooltips(playerNum)
end

---@param pane ISInventoryPane
function T.hide(pane)
    if not pane or not pane.toolRender then return end
    pane.toolRender:removeFromUIManager()
    pane.toolRender:setVisible(false)
end

---@param pane ISInventoryPane
function T.bringToTop(pane)
    if pane and pane.toolRender then pane.toolRender:bringToTop() end
end

return T

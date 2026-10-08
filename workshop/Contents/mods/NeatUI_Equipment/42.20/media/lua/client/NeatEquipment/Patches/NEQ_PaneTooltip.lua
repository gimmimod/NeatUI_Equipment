--[[ ============================================================================
    NEQ_PaneTooltip - hands the tooltip over to the panel while the pointer is
    on it.

    ISInventoryPane:updateTooltip closes the tooltip whenever the pointer is not
    over one of its own rows. Since the panel borrows that same tooltip object,
    the pane would close it the instant the pointer moved onto a slot. This
    hands control to NEQ_Body for as long as the pointer (or the controller
    focus) is on the panel.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISInventoryPane"

local InventoryPage = require("NeatEquipment/Patches/NEQ_InventoryPage")

local installed = false

local function install()
    if installed then return end
    installed = true

    local og_updateTooltip = ISInventoryPane.updateTooltip
    function ISInventoryPane:updateTooltip()
        local page = self.parent
        if not page then return og_updateTooltip(self) end

        local panel = page.neqEquipmentPanel
        if not panel or not panel:isVisible() then return og_updateTooltip(self) end

        local panelHasFocus = (page.isMouseOverNeatEquipment and page:isMouseOverNeatEquipment())
            or (panel.controllerNode and panel.controllerNode.isFocused)

        local popup = panel.popup
        local popupHasFocus = popup and popup:isVisible()
            and (popup:isMouseOver() or (popup.controllerNode and popup.controllerNode.isFocused))

        if panelHasFocus or popupHasFocus then
            if panel.body then panel.body:updateTooltip() end
            return
        end

        og_updateTooltip(self)
    end
end

Events.OnGameStart.Add(install)

-- Required for its side effect: the page hook has to be installed before this
-- one can rely on page.neqEquipmentPanel existing.
return InventoryPage

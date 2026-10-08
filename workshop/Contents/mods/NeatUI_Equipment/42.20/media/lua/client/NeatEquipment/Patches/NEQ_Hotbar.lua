--[[ ============================================================================
    NEQ_Hotbar - a refresh notification on ISHotbar.

    The hotbar rebuilds its own slot list when the player puts on or takes off
    something with attachment points (a holster, a belt, a sling). There is no
    event for that, so one is added: NEQ_Body registers a callback and rebuilds
    its hotbar section instead of comparing the list every frame.

    Wrapped at OnGameBoot so Clean HotBar - which replaces several ISHotbar
    methods of its own - is already in place.
============================================================================ ]]--

if isServer() then return end

require "Hotbar/ISHotbar"

local installed = false

Events.OnGameBoot.Add(function()
    if installed then return end
    installed = true

    local og_refresh = ISHotbar.refresh
    function ISHotbar:refresh()
        og_refresh(self)
        if self.neq_onRefresh then
            self.neq_onRefresh(self)
        end
    end
end)

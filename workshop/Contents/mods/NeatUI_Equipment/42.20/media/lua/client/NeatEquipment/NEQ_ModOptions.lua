--[[ ============================================================================
    NEQ_ModOptions - Options > Mods > "NeatUI Equipment".

    Only preferences live here. Anything the player changes by using the panel -
    where it sits, how big it is, whether it is docked or closed - is UI state
    and belongs to NeatUIEquipment.ini instead (NEQ_Config).

    The one overlap is "hide equipped items": it is both a preference and the
    header's eye button, so the tickbox and the button write through the same
    NEQ_State setter and the eye pushes its value back into the tickbox.
============================================================================ ]]--

if isServer() then return end

local State = require("NeatEquipment/NEQ_State")
local Style = require("NeatEquipment/NEQ_Style")
local Config = require("NeatEquipment/NEQ_Config")

-- Mod Options is a separate mod's API. Without it the panel still works with its
-- defaults; only the preference screen goes away.
--
-- Every label goes through Style.tr rather than getText: this file runs while
-- the game is still loading, before the translation tables are guaranteed to be
-- there, and getText hands back the raw key when it cannot answer. An options
-- screen reading "UI_NEQ_options_lock_panel" is worse than one reading English.
if not PZAPI or not PZAPI.ModOptions then return end

local MOD_ID = "NEATUI_EQUIPMENT"

local options = PZAPI.ModOptions:create(MOD_ID, Style.tr("UI_NEQ_options_title", "NeatUI Equipment"))

-- In cima: e' l'interruttore di tutto il resto. Per giocatore, non per
-- server - chi non vuole il pannello in una partita condivisa lo spegne per se'
-- senza toglierlo agli altri.
options:addTickBox("DISABLE_MOD",
    Style.tr("UI_NEQ_options_disable", "Turn NeatUI Equipment off"), false,
    Style.tr("UI_NEQ_options_disable_tooltip", "For you only: no figure button, no panel, no shortcut, and the inventory list is drawn by the game again. Saved outfits are kept. Useful on a server where the mod is required."))

local hideEquippedBox = options:addTickBox("HIDE_EQUIPPED_ITEMS",
    Style.tr("UI_NEQ_options_hide_equipped", "Hide equipped items"), false,
    Style.tr("UI_NEQ_options_hide_equipped_tooltip", "Removes the whole equipped section, header row included, from the inventory list."))

options:addTickBox("HIDE_HOTBAR",
    Style.tr("UI_NEQ_options_hide_hotbar", "Hide the hotbar section"), false,
    Style.tr("UI_NEQ_options_hide_hotbar_tooltip", "Hides the hotbar attachment slots at the bottom of the panel."))

options:addTickBox("HIDE_BAG_BUTTON",
    Style.tr("UI_NEQ_options_hide_bag", "Open with the hotkey only"), false,
    Style.tr("UI_NEQ_options_hide_bag_tooltip", "Removes the Equipment button (the figure) from the inventory. The panel then opens with the key set under [NeatUI Equipment] in Options > Key Bindings."))

options:addTickBox("SHOW_ON_HOVER",
    Style.tr("UI_NEQ_options_show_on_hover", "Show only on mouse over"), false,
    Style.tr("UI_NEQ_options_show_on_hover_tooltip", "The panel stays rolled up and unrolls when the pointer reaches it, like a sidebar."))

options:addTickBox("FOLLOW_INVENTORY",
    Style.tr("UI_NEQ_options_follow_inventory", "Detached: open with the inventory"), false,
    Style.tr("UI_NEQ_options_follow_inventory_tooltip", "The detached panel opens and closes together with the inventory window, so the inventory key opens both."))

options:addTickBox("DOCK_RIGHT",
    Style.tr("UI_NEQ_options_dock_right", "Attached: on the right of the inventory"), false,
    Style.tr("UI_NEQ_options_dock_right_tooltip", "The attached panel hangs off the right edge of the inventory window instead of the left, and the figure button moves to the right with it."))

options:addTickBox("DOCK_KEEP_SCALE",
    Style.tr("UI_NEQ_options_dock_keep_scale", "Attached: keep my size"), false,
    Style.tr("UI_NEQ_options_dock_keep_scale_tooltip", "The attached panel stops resizing itself to reach the bottom of the inventory and keeps the size set with the corner grip."))

-- L'aspetto delle finestre (Style.drawWindow). Il cursore e' il fondo: la
-- barra del titolo resta piena. "Come CleanUI" prende le texture e l'opacita'
-- di CleanUI e lascia stare il cursore; senza CleanUI la casella si spegne.
local opacitySlider = options:addSlider("PANEL_OPACITY",
    Style.tr("UI_NEQ_options_panel_opacity", "Panel opacity (normal: 100)"), 10, 100, 5, 100,
    Style.tr("UI_NEQ_options_panel_opacity_tooltip", "How solid the background of the panel and the wardrobe is. 100 is fully opaque; lower lets the game show through."))

local matchCleanUIBox = options:addTickBox("MATCH_CLEANUI",
    Style.tr("UI_NEQ_options_match_cleanui", "Look like CleanUI"), false,
    Style.tr("UI_NEQ_options_match_cleanui_tooltip", "The panel and the wardrobe use CleanUI's own frame and the background opacity set in CleanUI's options, so they match the inventory. The opacity slider is not used while this is on. Needs CleanUI."))

options:addTickBox("LOCK_PANEL",
    Style.tr("UI_NEQ_options_lock_panel", "Lock the detached panel"), false,
    Style.tr("UI_NEQ_options_lock_panel_tooltip", "Stops the detached panel from being moved or resized."))

-- La via d'uscita da un pannello finito troppo grande o fuori schermo: prima
-- l'unico rimedio era cancellare NeatUIEquipment.ini a mano. Dal menu
-- principale i pannelli non esistono ancora, e basta azzerare il file.
options:addButton("RESET_GEOMETRY",
    Style.tr("UI_NEQ_options_reset_geometry", "Reset panel size and position"),
    Style.tr("UI_NEQ_options_reset_geometry_tooltip", "Puts the panel back on the inventory at its starting size. Use it if the panel has grown past the edge of the screen."),
    function()
        local pages = rawget(_G, "NEQ_InventoryPage")
        local done = false
        for p = 0, 3 do
            local panel = pages and pages.getPanel and pages.getPanel(p)
            if panel and panel.resetGeometry then
                pcall(function() panel:resetGeometry() end)
                done = true
            end
        end
        if not done then
            local cfg = Config.get()
            cfg.scale, cfg.pos_x, cfg.pos_y, cfg.docked = 0, -1, -1, true
            Config.save()
        end
    end, nil)

-- Il salvataggio ha la sua spunta per la cintura e la hotbar (NEQ_Wardrobe), e
-- le borse ne hanno un'altra: l'opzione "salva senza borse" non c'e' piu'.
-- Questa invece resta, perche' vale per tutti i completi, anche quelli gia'
-- salvati, e spegne la spunta finche' e' accesa.
options:addTickBox("WARDROBE_NO_HOTBAR",
    Style.tr("UI_NEQ_options_no_hotbar", "Leave the hotbar out of outfits"), false,
    Style.tr("UI_NEQ_options_no_hotbar_tooltip", "Every outfit ignores the hotbar, including those already saved: what is attached to it, and the belts and holsters that hold it, are never saved, put on, taken off or moved."))

options:addTickBox("WARDROBE_SWAP_CONTAINERS",
    Style.tr("UI_NEQ_options_swap_containers", "Swap outfits through containers"), true,
    Style.tr("UI_NEQ_options_swap_containers_tooltip", "When you put on an outfit, each piece you take off goes into a nearby container that already holds something of the same kind, the one its replacement came from first. A piece with no such container stays in your inventory. Nothing is dropped on the floor, and bags are never moved."))

-- Nessun tasto di serie: sul pad sono tutti gia' presi dal gioco, e i due che
-- avevamo scelto aprivano una ruota mentre aprivano il pannello. Il perche' per
-- esteso sta su NEQ_State.BIND_NONE. La voce "nessuno" e' in fondo e non in
-- cima di proposito: le posizioni di prima non si spostano, cosi' chi aveva
-- gia' scelto un tasto se lo ritrova dov'era.
local controllerBindCombo = options:addComboBox("TOGGLE_CONTROLLER_BIND",
    Style.tr("UI_NEQ_options_controller_bind", "Open Equipment panel (gamepad)"), nil)
controllerBindCombo:addItem(" A  /  X ", false)
controllerBindCombo:addItem(" B  /  O ", false)
controllerBindCombo:addItem(" X  /  [ ] ", false)
controllerBindCombo:addItem(" Y  /  /\\ ", false)
controllerBindCombo:addItem(" LB /  L1 ", false)
controllerBindCombo:addItem(" RB /  R1 ", false)
controllerBindCombo:addItem("  < /  - ", false)
controllerBindCombo:addItem("  > /  + ", false)
controllerBindCombo:addItem(" LS /  L3 ", false)
controllerBindCombo:addItem(" RS /  R3 ", false)
controllerBindCombo:addItem(Style.tr("UI_NEQ_options_controller_none", "None"), true)

--- The eye button writes back here so the tickbox and the header never disagree.
State.persistHideEquipped = function(value)
    hideEquippedBox:setValue(value == true)
    PZAPI.ModOptions:save()
end

function options:apply()
    local off = self:getOption("DISABLE_MOD"):getValue() == true
    State:setHideEquipped(self:getOption("HIDE_EQUIPPED_ITEMS"):getValue() and not off, false)
    State:setHideHotbar(self:getOption("HIDE_HOTBAR"):getValue())
    State:setLockPanel(self:getOption("LOCK_PANEL"):getValue())
    State:setShowOnHover(self:getOption("SHOW_ON_HOVER"):getValue())
    State:setFollowInventoryKey(self:getOption("FOLLOW_INVENTORY"):getValue())
    State:setDockKeepScale(self:getOption("DOCK_KEEP_SCALE"):getValue())
    State:setDockRight(self:getOption("DOCK_RIGHT"):getValue())
    State:setHideBagButton(self:getOption("HIDE_BAG_BUTTON"):getValue())
    State:setWardrobeSwapContainers(self:getOption("WARDROBE_SWAP_CONTAINERS"):getValue())
    State:setWardrobeNoHotbar(self:getOption("WARDROBE_NO_HOTBAR"):getValue())
    State:setControllerBind(self:getOption("TOGGLE_CONTROLLER_BIND"):getValue())
    State:setDisabled(off)
    Style.BODY_ALPHA = math.max(0.1, math.min(1, (tonumber(self:getOption("PANEL_OPACITY"):getValue()) or 100) / 100))
    Style.LOOK = self:getOption("MATCH_CLEANUI"):getValue() == true and "cleanui" or "neat"
end

-- Il cursore si vede mentre lo si trascina: le finestre si ridisegnano a ogni
-- fotogramma e leggono Style.BODY_ALPHA, quindi basta scriverlo. All'Applica
-- lo riscrive options:apply; il gioco chiama onChangeApply PRIMA di salvare
-- il valore nell'opzione, quindi si usa quello che arriva.
opacitySlider.onChange = function(_, v)
    Style.BODY_ALPHA = math.max(0.1, math.min(1, (tonumber(v) or 100) / 100))
end
opacitySlider.onChangeApply = opacitySlider.onChange
-- Per una casella il gioco chiama onChange(indice, selezionata)
-- (MainOptions.lua, ramo tickbox), non col solo valore come per il cursore.
matchCleanUIBox.onChange = function(_, _, selected)
    Style.LOOK = (selected == true) and "cleanui" or "neat"
end

-- PZAPI applies the saved values when the options screen is confirmed, but not
-- reliably at load: without this the first session of the game runs on the
-- defaults no matter what is in ModOptions.ini. Idempotent, so calling it again
-- costs nothing.
Events.OnGameStart.Add(function()
    pcall(function() options:apply() end)

    -- Sotto Inventory Tetris l'occhio non ha piu' un elenco su cui lavorare e
    -- sparisce anche dall'intestazione del pannello: la casella resta a
    -- schermo, spenta, invece di promettere qualcosa che non succede.
    local Tetris = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")
    if not Tetris.hasEquippedList() and hideEquippedBox.setEnabled then
        pcall(function() hideEquippedBox:setEnabled(false) end)
    end

    -- Senza CleanUI non c'e' niente a cui somigliare.
    if type(rawget(_G, "CleanUI_getBackgroundOpacity")) ~= "function" and matchCleanUIBox.setEnabled then
        pcall(function() matchCleanUIBox:setEnabled(false) end)
    end
end)

return options

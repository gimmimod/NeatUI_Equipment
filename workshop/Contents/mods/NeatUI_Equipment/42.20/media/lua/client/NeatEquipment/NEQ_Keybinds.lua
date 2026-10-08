--[[ ============================================================================
    NEQ_Keybinds - the Options > Key Bindings entry.

    The display name comes from UI_optionscreen_binding_neq_toggle_equipment,
    which is translated with the rest of the mod. Comma is the default because
    it sits next to the vanilla inventory keys and is almost never already
    taken.
============================================================================ ]]--

if isServer() then return end

local bind = {}
bind.value = "[NeatUI Equipment]"
table.insert(keyBinding, bind)

bind = {}
bind.value = "neq_toggle_equipment"
bind.key = Keyboard.KEY_COMMA
table.insert(keyBinding, bind)

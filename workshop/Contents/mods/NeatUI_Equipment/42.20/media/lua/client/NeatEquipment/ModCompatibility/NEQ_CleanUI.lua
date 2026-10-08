--[[ ============================================================================
    NEQ_CleanUI - un tasto maglietta solo.

    CleanUI mette nella barra dei comandi dell'inventario un tasto quadrato
    con la maglietta (ISInventoryWindowControlHandler_HideEquipped, in
    ISUI/InventoryWindow/Handlers/HideEquippedItems.lua) che ripiega le cose
    indossate. Con Equipment accanto sono due problemi:

      * la stessa cosa si fa gia' con l'occhio nell'intestazione del nostro
        pannello, e due comandi per una funzione sola si pestano i piedi;
      * quella maglietta e' la stessa icona che da noi vuol dire altro: il
        tasto "togli / rimetti tutto" e, nel guardaroba, "indossa".

    Quindi con tutte e due le mod attive il loro tasto non si mostra. Si
    risponde "no" alla domanda che la barra fa a ogni tasto prima di metterlo
    (ISInventoryWindowContainerControls:arrange chiede shouldBeVisible): il
    tasto non viene creato, la barra si ridispone da sola, e anche la voce del
    pad sparisce, perche' passa dalla stessa domanda.

    Resta la loro riga "Oggetti equipaggiati" dentro l'elenco, con il suo
    clic che la ripiega: e' parte dell'elenco, non un tasto, e con l'occhio
    acceso sparisce comunque (NEQ_HideEquipped).

    Sotto Inventory Tetris l'occhio non c'e' (NEQ_InventoryTetris), quindi il
    loro tasto resta dov'e': toglierlo li' vorrebbe dire togliere la funzione.
============================================================================ ]]--

if isServer() then return end

local Tetris = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")
local State  = require("NeatEquipment/NEQ_State")

local function hideShirtButton()
    local handler = rawget(_G, "ISInventoryWindowControlHandler_HideEquipped")
    if type(handler) ~= "table" or handler.neqHidden then return end
    if not Tetris.hasEquippedList() then return end

    -- Con Equipment spento dalle opzioni il loro tasto torna: la domanda passa
    -- a loro, com'era. La barra la rifa' quando si ridispone.
    local theirs = handler.shouldBeVisible
    handler.neqHidden = true
    handler.shouldBeVisible = function(...)
        if State.disabled then
            if type(theirs) == "function" then return theirs(...) end
            return true
        end
        return false
    end
end

-- A OnGameBoot tutte le mod sono caricate, CleanUI compresa, e nessuna
-- finestra dell'inventario e' ancora stata costruita.
Events.OnGameBoot.Add(hideShirtButton)

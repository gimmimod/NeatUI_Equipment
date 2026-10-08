--[[ ============================================================================
    NEQ_Controller - gamepad access to the panel.

    Due strade per lo stesso tasto, e servono entrambe.

    La prima e' la classica: si avvolge ISInventoryPage:onJoypadDown. Funziona
    finche' e' la finestra dell'inventario ad avere il fuoco del pad - ed e' un
    "finche'" grosso. In PZ i tasti del pad arrivano **solo** all'elemento che
    ha il fuoco: appena il fuoco e' su un'altra finestra, o non e' su nessuna
    UI perche' si sta giocando, quel gancio non viene chiamato affatto e il
    tasto sembra morto. Nessun errore, nessuna traccia nel log: e' esattamente
    il sintomo che e' stato segnalato.

    La seconda e' mettersi dove il gioco smista **tutte** le pressioni:
    JoypadControllerData:onPressButton (JoyPadSetup.lua:431). Ci passa ogni
    tasto di ogni pad, con o senza fuoco, e ci passa una volta per pressione -
    quindi non serve nemmeno tenere il conto di cosa era premuto il frame
    prima.

    Qui prima c'era un giro a ogni tick che chiamava isJoypadPressed(id, tasto).
    Quella funzione **non esiste**: nei sorgenti Lua del gioco non compare da
    nessuna parte, e le uniche letture dirette sono una per tasto
    (isJoypadRBPressed, isJoypadLeftStickButtonPressed, e poche altre - niente
    per A, B, X, Y, Back o Start). La chiamata stava dentro un pcall, quindi
    falliva in silenzio a ogni frame e il tasto non rispondeva mai: nessun
    errore nel log, nessuna traccia, esattamente il sintomo segnalato. L'ha
    trovata globali.js.

    Sono complementari, non alternative, e non si pestano i piedi: entrambe
    passano da togglePressed(), che ignora una seconda chiamata ravvicinata.

    In piu': sinistra dalla finestra dell'inventario e destra da quella del
    loot spostano il fuoco sul pannello - al contrario quando il pannello sta
    sul bordo destro dell'inventario (Mod Options).
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISInventoryPage"

local State         = require("NeatEquipment/NEQ_State")
local InventoryPage = require("NeatEquipment/Patches/NEQ_InventoryPage")

local C = {}

local installed = false
local lastToggleFrame = {}

--- Da quale finestra, in quale direzione, si arriva al pannello: e' appeso
--- all'inventario, a sinistra o a destra, e il loot sta dall'altra parte.
local function towardsPanel(page, direction)
    local right = State.dockRight == true
    if page == getPlayerInventory(page.player) then
        return direction == (right and "right" or "left")
    end
    if page == getPlayerLoot(page.player) then
        return direction == (right and "left" or "right")
    end
    return false
end

--- La via d'ingresso al pannello per chi gioca col pad: dall'inventario,
--- direzione sinistra (destra con il pannello a destra). Da quando non c'e' piu' un tasto di serie (i pochi che
--- il gioco lascia liberi non sono liberi: vedi NEQ_State.BIND_NONE) questa e'
--- **la** via, quindi apre anche un pannello chiuso invece di rifiutarsi.
local function focusPanel(playerNum)
    if State.disabled then return false end
    local panel = InventoryPage.getPanel(playerNum)
    if not panel then return false end

    if panel.closed then panel:openPanel() end
    setJoypadFocus(playerNum, panel)
    return true
end

--- Un solo toggle per frame per giocatore, da qualunque delle due strade
--- arrivi. Se un giorno il gancio e la lettura diretta scattassero insieme, il
--- pannello si aprirebbe e richiuderebbe nello stesso istante, cioe' non
--- succederebbe niente e sembrerebbe di nuovo rotto.
function C.togglePressed(playerNum)
    if State.disabled then return end
    local now = getTimestampMs()
    if lastToggleFrame[playerNum] and now - lastToggleFrame[playerNum] < 120 then return end
    lastToggleFrame[playerNum] = now

    local panel = InventoryPage.getPanel(playerNum)
    if not panel then return end

    -- Il valore di ritorno, non isVisible(): il pannello si apre con
    -- un'animazione e diventa visibile solo al frame successivo, quindi
    -- chiederglielo adesso risponderebbe sempre "chiuso" e il fuoco non si
    -- sposterebbe mai.
    local aperto = panel:togglePanel()

    if aperto then
        setJoypadFocus(playerNum, panel)
    else
        -- Chiudendo, il fuoco torna all'inventario: lasciarlo su una finestra
        -- che non c'e' piu' significa lasciare il giocatore senza fuoco.
        local page = getPlayerInventory(playerNum)
        if page then setJoypadFocus(playerNum, page) end
    end
end

--- Da quale giocatore arriva questo pad.
---
--- JoypadState.players e' indicizzata da 1, i giocatori si contano da 0.
local function playerNumFor(joypadData)
    if not (joypadData and JoypadState and JoypadState.players) then return nil end
    for n = 1, 4 do
        if JoypadState.players[n] == joypadData then return n - 1 end
    end
    return nil
end

local function install()
    if installed then return end
    installed = true

    -- Il punto in cui passano tutte le pressioni, con e senza fuoco.
    --
    -- Chiesto con rawget perche' e' una classe di JoyPadSetup.lua: se un
    -- giorno non ci fosse, resta comunque il gancio sull'inventario qui sotto,
    -- e il tasto funziona finche' e' l'inventario ad avere il fuoco.
    local JCD = rawget(_G, "JoypadControllerData")
    if JCD and JCD.onPressButton then
        local og_onPressButton = JCD.onPressButton
        function JCD:onPressButton(button)
            -- Prima l'originale: se il tasto ha gia' un significato per il
            -- gioco, quello viene comunque fatto. Il nostro fuoco si mette
            -- dopo, cosi' vince l'ultimo ed e' il nostro pannello.
            og_onPressButton(self, button)

            if button ~= nil and button == State:controllerButton() then
                local playerNum = playerNumFor(self.joypad)
                if playerNum then C.togglePressed(playerNum) end
            end
        end
    end

    local og_onJoypadDown = ISInventoryPage.onJoypadDown
    function ISInventoryPage:onJoypadDown(button)
        if og_onJoypadDown then og_onJoypadDown(self, button) end
        -- `button ~= nil` non e' pignoleria: senza tasto assegnato
        -- controllerButton() risponde nil, e nil == nil aprirebbe il pannello
        -- a ogni pressione.
        if button ~= nil and button == State:controllerButton() then
            C.togglePressed(self.player)
        end
    end

    local og_onJoypadDirLeft = ISInventoryPage.onJoypadDirLeft
    function ISInventoryPage:onJoypadDirLeft(joypadData)
        if og_onJoypadDirLeft then og_onJoypadDirLeft(self, joypadData) end
        if towardsPanel(self, "left") then focusPanel(self.player) end
    end

    local og_onJoypadDirRight = ISInventoryPage.onJoypadDirRight
    function ISInventoryPage:onJoypadDirRight(joypadData)
        if og_onJoypadDirRight then og_onJoypadDirRight(self, joypadData) end
        if towardsPanel(self, "right") then focusPanel(self.player) end
    end
end

Events.OnGameBoot.Add(install)

-- Niente giro a ogni tick: il gancio qui sopra viene chiamato dal gioco solo
-- quando un tasto viene davvero premuto. Prima c'era un onTick che leggeva il
-- pad a ogni frame, per tutti e quattro i giocatori, e non funzionava.

return C

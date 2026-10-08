--[[ ============================================================================
    NEQ_InventoryTetris - convivenza con Inventory Tetris.

    Con Equipment UI da solo basta la riga `incompatible=` nel mod.info: sono
    due mod, se ne tiene una. Con Tetris no. Tetris **contiene** Equipment UI
    (media/lua/client/EquipmentUI/) e ci fa `require` sopra: disattivarlo non si
    puo', e se manca Tetris apre una finestra che avvisa che manca. Quindi la
    sostituzione va fatta a mano, a finestra gia' costruita.

    Cosa cambia quando Tetris c'e':

      * il loro pannello dell'equipaggiamento se ne va. Entra come "side panel"
        di Notloc, agganciato al bordo sinistro dell'inventario - la striscia
        delle linguette sta a `inventoryPage:getX() - 16` e il pannello a
        `getX() - larghezza + 1`, cioe' esattamente dove stanno il nostro tasto
        zaino e il nostro pannello. Due pannelli identici sovrapposti non sono
        una scelta, sono un disegno rotto.

      * il nostro disegnatore del trascinamento tace. Tetris disegna da se'
        l'oggetto che stai trascinando (TetrisDragItemRenderer), e infatti il
        loro Equipment UI salta il proprio quando Tetris e' attiva
        (ISInventoryPage_create_equipmentui.lua:38). Tenendo il nostro,
        l'oggetto si vedrebbe due volte.

      * l'occhio sparisce dall'intestazione. Toglie dall'elenco
        dell'inventario la sezione delle cose indossate; sotto Tetris quel
        pannello non e' piu' un elenco di righe ma una griglia, e la sezione non
        esiste. Loro fanno la stessa cosa, uscendo subito dal filtro quando
        Tetris c'e' (ISInventoryPane_hide_equipped_items.lua:41).

    Cosa **non** cambia, ed e' la ragione per cui tutto questo si tiene in un
    file solo: il trascinamento. Il sistema di Tetris e' costruito sopra quello
    di Equipment UI, e tutti e due parlano attraverso ISMouseDrag, che e' la
    stessa tabella su cui parliamo noi (vedi NEQ_DragDrop). L'unica aggiunta
    loro e' `ISMouseDrag.rotateDrag`, ed e' l'unica cosa che ci tocca scrivere.
============================================================================ ]]--

if isServer() then return end

NEQ_InventoryTetris = NEQ_InventoryTetris or {}
local T = NEQ_InventoryTetris

local MOD_ID = "INVENTORY_TETRIS"

-- Notloc/UI/SidePanels/SidePanelManager.lua, TOGGLE_WIDTH.
local TOGGLE_STRIP_W = 16

local _active = nil

--- Vero quando Inventory Tetris e' fra le mod attive.
---
--- Le due forme dell'id sono volute: c'e' un difetto per cui l'id arriva con
--- una barra rovesciata davanti, e Tetris stessa si guarda da tutte e due
--- (IncompatibleModWarningSystem.lua:17).
---@return boolean
function T.isActive()
    if _active ~= nil then return _active end

    local mods = getActivatedMods and getActivatedMods()
    if not mods then return false end   -- troppo presto: non si memorizza

    _active = mods:contains(MOD_ID) or mods:contains("\\" .. MOD_ID)
    return _active
end

-- ---------------------------------------------------------------------------
-- Il loro pannello
-- ---------------------------------------------------------------------------
--- Sfila il pannello dell'equipaggiamento di Tetris dalla finestra.
---
--- Va chiamato **dopo** che la loro createChildren l'ha creato. La nostra
--- avvolge la loro - loro agganciano al caricamento del file, noi a OnGameBoot,
--- quindi la nostra e' la piu' esterna e quando arriva il nostro turno il loro
--- pannello e' gia' li'.
---@param page ISInventoryPage
function T.takeOverFrom(page)
    if not T.isActive() then return end

    local panel = page and page.equipmentUiPanel
    if not panel then return end

    local manager = page.notlocSidePanelManager
    local list = manager and manager.sidePanelData
    if list then
        for i = 1, #list do
            local data = list[i]
            if data.sidePanel == panel then
                table.remove(list, i)
                if data.toggle then manager:removeChild(data.toggle) end
                break
            end
        end
        -- Le linguette rimaste vanno rinumerate, o resta il buco della nostra.
        if manager.sortToggles then manager:sortToggles() end
    end

    -- Il loro pannello si iscrive a un elenco di ascoltatori dentro Settings, e
    -- a disiscriverlo pensa il removeFromUIManager della finestra - che pero'
    -- legge page.equipmentUiPanel, e fra due righe li' non c'e' piu' niente.
    local ok, settings = pcall(require, "EquipmentUI/Settings")
    if ok and type(settings) == "table" and settings.removeScaleChangedListeners then
        pcall(function() settings:removeScaleChangedListeners(panel) end)
    end

    pcall(function() panel:setVisible(false) end)
    pcall(function() panel:removeFromUIManager() end)

    -- Le loro patch sulla finestra guardano tutte `self.equipmentUiPanel` prima
    -- di toccarlo (ISInventoryPage_equipmentui_mouse_events.lua:4 e seguenti),
    -- quindi azzerarlo le mette a riposo invece di romperle.
    page.equipmentUiPanel = nil
end

-- ---------------------------------------------------------------------------
-- Quello che gli altri pezzi devono sapere
-- ---------------------------------------------------------------------------
--- Quanto spazio prendersi a sinistra prima di posare il tasto del pannello.
---
--- Tolto il loro pannello la striscia delle linguette resta senza linguette e
--- non occupa niente. Se pero' un'altra mod ne ha registrata una, la striscia
--- c'e' ed e' esattamente dove andrebbe il tasto.
---@param page ISInventoryPage
---@return number
function T.sideStripWidth(page)
    if not T.isActive() then return 0 end

    local manager = page and page.notlocSidePanelManager
    local list = manager and manager.sidePanelData
    if list and #list > 0 then return TOGGLE_STRIP_W end
    return 0
end

--- Falso sotto Tetris: l'inventario del personaggio e' una griglia e la sezione
--- "equipaggiato" da togliere non c'e'.
---@return boolean
function T.hasEquippedList()
    return not T.isActive()
end

--- Falso sotto Tetris: l'oggetto trascinato lo disegnano loro.
---@return boolean
function T.wantsDragRenderer()
    return not T.isActive()
end

--- Vero sotto Tetris: del rilascio sopra l'inventario si occupa il pannello.
---
--- Senza Tetris, uno slot che si vede rilasciare l'oggetto sopra l'elenco lo
--- toglie di dosso da se' (`unequipItem`), e sopra il loot lo trasferisce: e'
--- lo slot a fare il lavoro, perche' un elenco non ha un "dove".
---
--- Con Tetris un dove c'e', ed e' la casella sotto il puntatore. La griglia
--- legge `ISMouseDrag.dragging` nel suo onMouseUp e sistema l'oggetto da se'
--- (ItemGridUI_events.lua:85-113), poi chiama endDrag. Facendo anche noi la
--- nostra parte, lo stesso oggetto verrebbe mosso due volte e finirebbe dove
--- capita invece che dove lo si e' posato.
---
--- Il caso che resta scoperto e' il rilascio **dentro** la finestra ma fuori da
--- ogni griglia - il bordo, la barra di scorrimento: li' non succede niente,
--- che e' la stessa scelta del loro Equipment UI
--- (UI/Slots/EquipmentSlot.lua:142) ed e' meglio di un capo che si toglie da
--- solo per essere posato chissa' dove.
---@return boolean
function T.paneHandlesDrop()
    return T.isActive()
end

--- Vero sotto Tetris: nelle mani ci va qualunque cosa si possa reggere.
---
--- Fuori da Tetris uno slot delle mani rifiuta cibo e vestiario, perche' per
--- quelli ci sono la bocca e il corpo e mettere una maglietta "in mano" e' quasi
--- sempre un errore di mira. In Tetris no: le mani sono un posto come un altro
--- dove tenere una cosa mentre si riordina la griglia, ed e' cosi' che si
--- comporta il loro Equipment UI - Tetris gli riscrive `canAcceptItem` in una
--- riga sola perche' resti solo la domanda "questa mano funziona?"
--- (Patches/EquipmentUI/WeaponSlot_allow_anything_in_hands.lua).
---
--- Senza questo, chi passa a Tetris con la nostra mod perderebbe qualcosa che
--- con la loro aveva.
---@return boolean
function T.handsAcceptAnything()
    return T.isActive()
end

-- ---------------------------------------------------------------------------
-- La toppa fra Inventory Tetris e CleanUI
-- ---------------------------------------------------------------------------
--[[ Questa non ripara niente di nostro: ripara un guasto fra due mod altrui,
    che pero' porta giu' l'inventario intero e quindi anche noi.

    `ISInventoryPane:createChildren` di vanilla crea tre bottoni d'intestazione -
    `expandAll`, `collapseAll`, `filterMenu` (ISInventoryPane.lua:43 e seguenti).
    CleanUI riscrive quel metodo e **non li crea**: l'intestazione a colonne e'
    esattamente cio' che CleanUI toglie. Tetris, che chiama l'originale e poi ci
    lavora sopra, li spegne ad ogni refresh con un controllo di sola verita':

        if self.expandAll then self.expandAll:setVisible(false) end
                                    -- InventoryTetris_InventoryPane.lua:178

    Senza il bottone sull'istanza, `self.expandAll` non e' nil: risale alla
    classe e trova il **metodo** `ISInventoryPane:expandAll`. Vero, quindi il
    controllo passa; non una tabella, quindi `:setVisible` alza

        attempted index: setVisible of non-table: function expandAll:2095

    e l'eccezione risale fino a `createPlayerData` (ISPlayerData.lua:172) e la
    interrompe. `playerInventory` non viene mai assegnato: da li' in poi
    `getPlayerInventory(0)` e' nil, la finestra resta a meta', gli oggetti non si
    spostano piu' e ogni tasto premuto ripete l'errore da
    InventoryTetris_InventoryPage.lua:217.

    E' la lezione 20 vista dall'altro lato: `Classe:metodo` e `istanza.campo`
    sono la stessa voce di tabella, e un `if` che chiede solo "c'e'?" non
    distingue un bottone da un metodo ereditato.

    La riparazione vera sta a casa di Tetris ed e' una parola
    (`if type(self.expandAll) == "table"`). Qui si fa la cosa piu' piccola che
    la rende innocua: per la durata delle due chiamate che li leggono, i campi
    che non esistono sull'istanza valgono `false` invece di ereditare il metodo.
    Falso e' falso, il controllo di Tetris salta la riga, e CleanUI continua a
    chiamare `pane:expandAll()` come sempre perche' la maschera viene tolta
    subito dopo.
]]
local HEADER_FIELDS = { "expandAll", "collapseAll", "filterMenu" }

--- Mette a `false` i campi assenti sull'istanza che la classe risolve in un
--- metodo. Torna l'elenco di quelli mascherati, o nil se non ce n'erano.
local function maskHeaderFields(pane)
    local masked = nil
    for i = 1, #HEADER_FIELDS do
        local name = HEADER_FIELDS[i]
        if rawget(pane, name) == nil and type(pane[name]) == "function" then
            masked = masked or {}
            masked[#masked + 1] = name
            rawset(pane, name, false)
        end
    end
    return masked
end

--- Toglie la maschera solo dov'e' ancora la nostra: senza CleanUI il bottone
--- vero nasce **dentro** la chiamata, e quello non si tocca.
local function unmaskHeaderFields(pane, masked)
    if not masked then return end
    for i = 1, #masked do
        if rawget(pane, masked[i]) == false then rawset(pane, masked[i], nil) end
    end
end

local _shimInstalled = false

--- Va chiamata tardi: Tetris installa le sue versioni su OnGameBoot, e queste
--- devono avvolgerle. Il primo `ISInventoryPage:createChildren` e' il momento
--- giusto - dopo ogni OnGameBoot, prima che esista un solo pannello.
function T.installPaneShim()
    if _shimInstalled then return end
    if not T.isActive() then return end
    if not ISInventoryPane then return end
    _shimInstalled = true

    local og_refreshContainer = ISInventoryPane.refreshContainer
    function ISInventoryPane:refreshContainer(...)
        local masked = maskHeaderFields(self)
        local result = { og_refreshContainer(self, ...) }
        unmaskHeaderFields(self, masked)
        return unpack(result)
    end

    -- Anche qui: applyHeaderlessVanillaPane legge gli stessi tre campi sul
    -- pannello del portachiavi (InventoryTetris_InventoryPane.lua:29-38).
    local og_createChildren = ISInventoryPane.createChildren
    function ISInventoryPane:createChildren(...)
        local masked = maskHeaderFields(self)
        local result = { og_createChildren(self, ...) }
        unmaskHeaderFields(self, masked)
        return unpack(result)
    end
end

--- Da chiamare quando un trascinamento parte da noi.
---
--- Tetris tiene la rotazione dell'oggetto trascinato su ISMouseDrag.rotateDrag
--- e la imposta nel suo prepareDrag (System/DragAndDrop.lua:63), che pero'
--- passa solo per le sue griglie. Partendo dal nostro pannello non la tocca
--- nessuno e resta quella dell'ultimo trascinamento: l'oggetto rientrerebbe in
--- griglia girato.
function T.onDragStarted()
    if not T.isActive() then return end
    if ISMouseDrag then ISMouseDrag.rotateDrag = false end
end

return T

--[[ ============================================================================
    NEQ_HideEquipped - the eye button: takes the equipped items out of the
    CleanUI inventory list entirely.

    CleanUI already groups worn items under an "Equipped items" separator row
    that can be collapsed. Collapsing it hides the items but leaves the row
    behind. With the eye on, the whole section goes: the item rows *and* the
    separator, because the panel is now where equipment is managed and a header
    for an empty, unreachable group is just clutter.

    That also means the two toggles stay independent - CleanUI's own collapse
    keeps working exactly as before when the eye is off.

    Implementation is a swap, not a rebuild: refreshContainer keeps the full
    list and builds a filtered copy beside it, and renderdetails renders from
    the filtered one and puts the full list back afterwards. Vanilla
    renderdetails can call refreshContainer re-entrantly (a timed action
    dirtying the pane mid-render), so the filtered list is re-applied there too
    or equipped items flash back in for a frame.
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISInventoryPane"

local State  = require("NeatEquipment/NEQ_State")
local Tetris = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")

NEQ_HideEquipped = NEQ_HideEquipped or {}
local H = NEQ_HideEquipped

---@return ISInventoryPane|nil
local function characterPane(playerNum)
    local page = getPlayerInventory(playerNum)
    if not page or not page.onCharacter then return nil end
    return page.inventoryPane
end

--- Rebuilds the filtered list right now. Called whenever something is equipped
--- or unequipped so the inventory reacts on the same frame instead of on the
--- next natural refresh.
function H.refreshFor(playerNum)
    if not State.hideEquipped then return end
    local pane = characterPane(playerNum)
    if pane then pane:refreshContainer() end
end

--- Vera solo per il pannello che sta mostrando l'inventario **del
--- personaggio**, non una borsa.
---
--- La finestra e' la stessa: `onCharacter` resta vero anche quando dai tasti
--- dei contenitori hai aperto lo zaino Alice, cambia solo `pane.inventory`.
--- Filtrare anche li' era sbagliato due volte. Dentro una borsa non c'e'
--- niente di equipaggiato da nascondere, e soprattutto:
--- ISInventoryPage:selectContainer cambia il contenitore **senza** ricostruire
--- la lista (ISInventoryPage.lua:1104). Vanilla se lo permette perche' disegna
--- `self.itemslist`, che si rifa' da sola appena il contenitore risulta
--- sporco; noi disegnavamo la lista filtrata, che resta legata al contenitore
--- da cui era stata costruita. Risultato: aperta la borsa si continuavano a
--- vedere i vestiti addosso, e la lista non si aggiornava piu'.
local function isCharacterPane(pane)
    local page = pane.parent
    if not page or page.onCharacter ~= true then return false end

    local character = getSpecificPlayer(pane.player)
    if not character then return false end

    local ok, inventory = pcall(function() return character:getInventory() end)
    return ok and inventory ~= nil and pane.inventory == inventory
end

--- Tutto quello che il personaggio ha addosso adesso: vestito, in mano, o
--- agganciato alla barra rapida.
---
--- Si chiede al personaggio invece di fidarsi delle etichette `equipped` e
--- `inHotbar` che la lista si mette da sola. Quelle due le scrive
--- ISInventoryPane solo quando `self.hotbar` c'e' gia'
--- (ISInventoryPane.lua:2122), e valgono per la **riga**, che raggruppa piu'
--- oggetti con lo stesso nome: bastava che una riga fosse etichettata storta
--- perche' la torcia agganciata alla cintura restasse in lista con l'occhio
--- acceso. Qui invece si guarda oggetto per oggetto.
--- Fills `set` with everything equipped and returns how many distinct items
--- that is. Takes the table from the caller so the per-frame check below can
--- reuse one instead of making a new one every frame.
local function mark(set, count, item)
    if item and not set[item] then
        set[item] = true
        return count + 1
    end
    return count
end

local function fillEquipped(set, playerNum)
    local count = 0

    local character = getSpecificPlayer(playerNum)
    if not character then return count end

    local worn = character:getWornItems()
    for i = 1, worn:size() do
        count = mark(set, count, worn:get(i - 1):getItem())
    end

    count = mark(set, count, character:getPrimaryHandItem())
    count = mark(set, count, character:getSecondaryHandItem())

    local hotbar = getPlayerHotbar(playerNum)
    if hotbar and hotbar.attachedItems then
        for _, item in pairs(hotbar.attachedItems) do
            count = mark(set, count, item)
        end
    end

    return count
end

--[[ Has anything been equipped or taken off since the list was built?

    The filtered list is rebuilt on clothing and hand events, and whenever the
    pane switches container. Attaching to the hotbar sends neither: the item
    goes on the belt, the container is the same, and nothing tells the list.
    Worse, taking clothes on or off makes the hotbar re-attach every item one
    tick later (ISHotbar:refresh, run from its update), after the list has
    already been rebuilt on the clothing event. Either way the list kept an item
    that was now on the belt - usually the last one attached - until the player
    opened another bag and came back, which is exactly the reported fix.

    So the check is on the thing itself: the set of equipped items, compared
    with the one the list was built from, every frame the eye is on. It is a
    few dozen table lookups and no allocation.
]]
local scratch = {}

local function equippedChanged(pane)
    local built = pane.neqEquippedSet
    if not built then return true end

    for k in pairs(scratch) do scratch[k] = nil end
    local count = fillEquipped(scratch, pane.player)
    if count ~= pane.neqEquippedCount then return true end

    for item in pairs(scratch) do
        if not built[item] then return true end
    end
    return false
end

--- Una riga sparisce solo se **tutto** quello che raggruppa e' addosso: due
--- torce dello stesso tipo, una alla cintura e una nello zaino, restano una
--- riga sola che il giocatore deve continuare a vedere.
local function entryIsAllEquipped(entry, equipped)
    local items = entry.items
    if not items or #items == 0 then return false end

    for _, item in ipairs(items) do
        if not equipped[item] then return false end
    end
    return true
end

--- Returns the filtered list, and the equipped set and count it was built
--- from, which equippedChanged compares against.
local function buildFilteredList(itemslist, playerNum)
    local equipped = {}
    local count = fillEquipped(equipped, playerNum)

    local filtered = {}
    for _, entry in ipairs(itemslist) do
        -- Le etichette della lista restano come prima linea: quando ci sono
        -- sono giuste, e costano un confronto. Il separatore e' l'intestazione
        -- "Equipped items" di CleanUI.
        local hide = entry and (entry.type == "separator"
            or entry.equipped == true
            or entry.inHotbar == true
            or entryIsAllEquipped(entry, equipped))

        if entry and not hide then
            filtered[#filtered + 1] = entry
        end
    end
    return filtered, equipped, count
end

local installed = false

local function install()
    if installed then return end
    -- Sotto Inventory Tetris l'inventario del personaggio non e' piu' un elenco
    -- di righe ma una griglia: non c'e' nessuna sezione "equipaggiato" da
    -- togliere, e le due patch qui sotto lavorerebbero su una lista che nessuno
    -- disegna piu'.
    if not Tetris.hasEquippedList() then return end
    installed = true

    local og_refreshContainer = ISInventoryPane.refreshContainer
    function ISInventoryPane:refreshContainer()
        og_refreshContainer(self)

        if not isCharacterPane(self) then return end

        self.neqFullItemList = self.itemslist
        if not State.hideEquipped or not self.itemslist then
            self.neqFilteredFor = nil
            return
        end

        self.neqFilteredItemList, self.neqEquippedSet, self.neqEquippedCount =
            buildFilteredList(self.itemslist, self.player)
        -- Da quale contenitore viene questa lista. Senza, non c'e' modo di
        -- accorgersi che nel frattempo si e' passati a un'altra borsa.
        self.neqFilteredFor = self.inventory

        -- Re-entrant call from inside renderdetails: restore the filtered view
        -- immediately, otherwise this frame renders the full list.
        if self.neqRenderingFiltered then
            self.itemslist = self.neqFilteredItemList
        end
    end

    local og_renderdetails = ISInventoryPane.renderdetails
    function ISInventoryPane:renderdetails(doDragged)
        if not isCharacterPane(self) then
            return og_renderdetails(self, doDragged)
        end

        -- A occhio spento non si ricostruisce niente: la lista e' quella di
        -- vanilla e va disegnata com'e'. L'unica ricostruzione e' quella del
        -- fotogramma in cui l'occhio si spegne, per far tornare subito le righe
        -- nascoste.
        if not State.hideEquipped then
            if self.neqHiding then
                self.neqHiding = false
                self:refreshContainer()
            end
            return og_renderdetails(self, doDragged)
        end

        -- Si rifa' quando l'occhio si e' appena acceso, ogni volta che la
        -- lista filtrata che abbiamo in mano non e' di questo contenitore, e
        -- quando e' cambiato cosa e' equipaggiato senza che nessun evento lo
        -- dicesse (vedi equippedChanged). A full refresh, not just the
        -- filter: the pane's own equipped/inHotbar labels are stale too.
        if not self.neqHiding or self.neqFilteredFor ~= self.inventory
            or equippedChanged(self) then
            self:refreshContainer()
        end

        self.neqHiding = true
        self.neqRenderingFiltered = true
        self.itemslist = self.neqFilteredItemList or self.neqFullItemList

        -- Il ripristino deve avvenire comunque. Se qualcosa esplode qui dentro
        -- - nostro o di un'altra mod - la lista filtrata resta al posto di
        -- quella vera e il pannello si blocca su quello che stava mostrando.
        -- L'errore non viene inghiottito: si rimette a posto e lo si rilancia
        -- (METODO/03, lezione 22).
        local ok, err = pcall(og_renderdetails, self, doDragged)

        self.neqRenderingFiltered = false
        self.itemslist = self.neqFullItemList

        if not ok then error(err, 0) end
    end
end

Events.OnGameStart.Add(install)

-- ---------------------------------------------------------------------------
-- Immediate reaction to equipment changes
-- ---------------------------------------------------------------------------
-- Il personaggio non e' detto che sia il giocatore: questi eventi scattano
-- anche per gli zombie. Vedi State.localPlayerNum.
local function onEquipmentChanged(character)
    local playerNum = State.localPlayerNum(character)
    if playerNum then H.refreshFor(playerNum) end
end

Events.OnClothingUpdated.Add(onEquipmentChanged)
Events.OnEquipPrimary.Add(onEquipmentChanged)
Events.OnEquipSecondary.Add(onEquipmentChanged)

-- Flipping the eye itself has to refresh too, and for every open page.
State:addHideEquippedListener(H, function()
    for playerNum = 0, 3 do
        local pane = characterPane(playerNum)
        if pane then pane:refreshContainer() end
    end
end)

return H

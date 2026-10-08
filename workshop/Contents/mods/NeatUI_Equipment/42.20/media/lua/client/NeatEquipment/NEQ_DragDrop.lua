--[[ ============================================================================
    NEQ_DragDrop - a thin wrapper over the vanilla ISMouseDrag globals.

    Due parole del protocollo sono di vanilla e due sono nostre, ed e' una
    distinzione che conviene tenere a mente:

      dragging        vanilla. Cosa si sta trascinando, e in che forma:
                      una lista di pile. La leggono le finestre
                      dell'inventario e del loot.
      draggingFocus   vanilla. Chi ha cominciato. Senza questa, un pannello
                      vanilla **rifiuta** il rilascio (ISInventoryPane.lua:1216).
      dragOwner       nostra. Quale nostro slot ha cominciato, per il ripiego
                      differito qui sotto.
      itemsToDrag     nostra, con localXStart / localYStart: il carico in
                      attesa, finche' il puntatore non si e' mosso abbastanza
                      da trasformare la pressione in un trascinamento.

    Nei sorgenti del gioco le ultime tre non compaiono mai: sono campi nostri
    appoggiati sulla stessa tabella. Le prime due sono il vero punto di
    contatto, ed e' per questo che vanno scritte tutte e due.

    The one addition is the deferred cancel. A drag released over nothing has to
    reach every receiver first, so "cancel" only records the intent; the next
    OnTick fires the callback and clears the globals.
============================================================================ ]]--

if isServer() then return end

local Tetris = require("NeatEquipment/ModCompatibility/NEQ_InventoryTetris")

NEQ_DragDrop = NEQ_DragDrop or {}
local D = NEQ_DragDrop

D.ownersForCancel = D.ownersForCancel or {}
D.hasPendingCancel = false

-- The pointer has to travel this far before a press turns into a drag, so a
-- click on a slot stays a click.
local DRAG_LIMIT = 8

function D.isDragging()
    return ISMouseDrag.dragging ~= nil
end

---@return InventoryItem|nil
function D.stackToItem(stack)
    if instanceof(stack, "InventoryItem") then
        return stack
    elseif stack then
        if stack.items then
            return stack.items[1]
        end
        return D.stackToItem(stack[1])
    end
    return nil
end

--- Il carico di un trascinamento come lo scrive vanilla: una **lista** di
--- pile, e ogni pila ripete il primo oggetto come voce rappresentativa
--- (ISInventoryPane.getActualItems salta di proposito `items[1]`).
---
--- Prima qui usciva la pila da sola, senza la lista intorno. Le nostre parti
--- non se ne accorgevano - stackToItem sa leggere tutte e due le forme - ma il
--- gioco si', e in due modi che si vedono:
---
---   * `#ISMouseDrag.dragging > 0` e' la condizione con cui una finestra
---     dell'inventario si riapre mentre trascini (ISInventoryPage.lua:490).
---     Una tabella senza parte di array conta zero: la finestra del
---     bagagliaio restava chiusa, ed e' il "non mi apre il contenitore
---     vicino" segnalato.
---   * `getActualItems` scorre la lista con ipairs: senza lista non trovava
---     niente da trasferire.
function D.itemToStack(item)
    return { { items = { item, item } } }
end

---@return InventoryItem|nil
function D.getDraggedItem()
    if D.isDragging() then
        return D.stackToItem(ISMouseDrag.dragging)
    end
    return nil
end

function D.prepareDrag(owner, stack, x, y)
    table.wipe(D.ownersForCancel)
    D.hasPendingCancel = false

    -- Inventory Tetris tiene la rotazione dell'oggetto trascinato sulla stessa
    -- tabella, e la scrive solo quando il trascinamento parte da una sua
    -- griglia: partendo da qui resterebbe quella di prima. Vedi
    -- ModCompatibility/NEQ_InventoryTetris.
    Tetris.onDragStarted()

    ISMouseDrag.dragOwner = owner
    ISMouseDrag.itemsToDrag = stack
    ISMouseDrag.localXStart = x
    ISMouseDrag.localYStart = y
end

function D.startDrag(owner)
    if owner ~= ISMouseDrag.dragOwner then return end
    if ISMouseDrag.dragging or not ISMouseDrag.itemsToDrag then return end

    local dx = owner:getMouseX() - (ISMouseDrag.localXStart or 0)
    local dy = owner:getMouseY() - (ISMouseDrag.localYStart or 0)
    if math.abs(dx) > DRAG_LIMIT or math.abs(dy) > DRAG_LIMIT then
        ISMouseDrag.dragging = ISMouseDrag.itemsToDrag
        ISMouseDrag.itemsToDrag = nil

        -- Questa riga e' tutta la differenza fra "si puo' trascinare un oggetto
        -- dal pannello dentro il bagagliaio dell'auto" e "non succede niente".
        --
        -- ISInventoryPane:onMouseUp accetta un rilascio solo se
        -- `ISMouseDrag.draggingFocus ~= nil` (ISInventoryPane.lua:1216): e' il
        -- campo con cui un pannello vanilla dichiara di essere l'origine del
        -- trascinamento. Senza, la finestra del loot cade nel ramo che
        -- azzera e basta, e l'oggetto resta dov'era - che e' esattamente il
        -- sintomo segnalato con la tanica in mano e il bagagliaio aperto.
        --
        -- Il prezzo e' la chiamata di cortesia qui sotto: vedi D.isForeignDrop.
        ISMouseDrag.draggingFocus = owner
    end
end

--- True quando questo rilascio non e' successo qui.
---
--- Preso il trascinamento, vanilla richiama `draggingFocus:onMouseUp(0, 0)`
--- (ISInventoryPane.lua:1245, ISInventoryPage.lua:1018) per dire all'origine
--- che ha finito. A quel punto `ISMouseDrag.dragging` c'e' ancora, quindi uno
--- slot che non se ne accorgesse rimetterebbe addosso l'oggetto appena
--- trasferito.
---
--- Il segnale sono le **coordinate**: quella chiamata di cortesia arriva
--- sempre con (0, 0). Il puntatore fuori dallo slot vale come seconda
--- conferma, ma da solo non basterebbe: `isMouseOver` lo decide il motore
--- sulla geometria, e una finestra del loot appoggiata sopra al pannello
--- risponderebbe comunque "sì, il mouse è su di me".
---
--- Il rovescio - un clic vero rilasciato esattamente sul pixel in alto a
--- sinistra dello slot da cui era partito il trascinamento - vale un clic che
--- non fa niente. L'altro sbaglio, invece, rimetterebbe addosso l'oggetto
--- appena messo nel bagagliaio.
function D.isForeignDrop(owner, x, y)
    if ISMouseDrag.draggingFocus ~= owner then return false end
    if x == 0 and y == 0 then return true end
    return not owner:isMouseOver()
end

function D.endDrag()
    ISMouseDrag.itemsToDrag = nil
    ISMouseDrag.dragging = nil
    ISMouseDrag.dragOwner = nil
    ISMouseDrag.draggingFocus = nil
    table.wipe(D.ownersForCancel)
    D.hasPendingCancel = false
end

--- Records a cancel for the next tick; the receivers under the cursor get their
--- own onMouseUp first.
function D.cancelDrag(owner, callback)
    if owner ~= ISMouseDrag.dragOwner then return end
    D.ownersForCancel[owner] = { callback = callback }
    D.hasPendingCancel = true
end

--- True when the pointer is over any UI window at all. Releasing a drag over
--- nothing is what means "drop it on the ground", so this is the guard that
--- stops an item being thrown away because the cursor happened to be over the
--- crafting window.
function D.isMouseOverAnyUI()
    local mx, my = getMouseX(), getMouseY()
    local all = UIManager.getUI()
    for i = 0, all:size() - 1 do
        if all:get(i):isPointOver(mx, my) then return true end
    end
    return false
end

local function processCancelation()
    if not D.hasPendingCancel then return end

    for owner, record in pairs(D.ownersForCancel) do
        if ISMouseDrag.dragOwner == owner then
            if record.callback then record.callback(owner) end
            D.endDrag()
            break
        end
    end

    table.wipe(D.ownersForCancel)
    D.hasPendingCancel = false
end

if not D._tickHooked then
    D._tickHooked = true
    Events.OnTick.Add(processCancelation)
end

return D

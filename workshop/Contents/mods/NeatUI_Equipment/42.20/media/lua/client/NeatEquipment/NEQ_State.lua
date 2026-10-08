--[[ ============================================================================
    NEQ_State - the single source of truth for everything the UI reads.

    Two kinds of value live here:

      * metrics  - every pixel size in the panel derives from one `scale`
                   factor, exactly like NeatUI XP Drop. The corner grip writes
                   `scale`; :applyScale() recomputes the whole table and tells
                   the widgets to re-lay themselves out.
      * flags    - hideEquipped / hideHotbar / lockPanel. Set from the header
                   buttons or from Mod Options; listeners let the panel react
                   without polling.

    Listeners are stored as {owner, callback} records rather than closures, so a
    panel that is torn down can be unsubscribed by identity and never keeps an
    old UI tree alive.
============================================================================ ]]--

if isServer() then return end

NEQ_State = NEQ_State or {}
local S = NEQ_State

S.MIN_SCALE = 0.75

-- Il tetto serve a non lasciar diventare assurdo il pannello. Era stato alzato
-- a 4.0 per inseguire la larghezza dell'inventario di CleanUI (circa mille
-- pixel): quella strada era sbagliata e il tetto e' tornato dov'era. 2.5 = 610
-- px di pannello, che e' gia' molto.
S.MAX_SCALE = 2.50

-- Panel width at scale 1. Everything else is derived, so this is the one number
-- to touch when the default panel feels too narrow or too wide.
S.BASE_WIDTH = 244

-- NR_ResizeWidget.SIZE. Il trascinatore d angolo di Rocco e sempre 16 px,
-- qualunque sia la finestra.
local Y_GRIP_SIZE = 16

-- Drag & drop feedback, in the Neat palette (NR_Config) rather than pure RGB.
S.GOOD_COLOR   = { r = 0.30, g = 0.72, b = 0.38, a = 1.0 }   -- free slot
S.REPLACE_COLOR= { r = 0.95, g = 0.50, b = 0.10, a = 1.0 }   -- occupied, will swap
S.BAD_COLOR    = { r = 0.80, g = 0.20, b = 0.20, a = 1.0 }   -- conflict

-- ---------------------------------------------------------------------------
-- Listeners
-- ---------------------------------------------------------------------------
-- `or {}` rather than `{}`: this file is both auto-loaded and require'd, and a
-- second pass must not throw away subscriptions that already exist.
S._scaleListeners  = S._scaleListeners or {}
S._hideEqListeners = S._hideEqListeners or {}
S._hotbarListeners = S._hotbarListeners or {}

local function addListener(list, owner, callback)
    if not owner or not callback then return end
    for _, l in ipairs(list) do
        if l.owner == owner and l.callback == callback then return end
    end
    table.insert(list, { owner = owner, callback = callback })
end

local function notify(list, ...)
    for _, l in ipairs(list) do
        l.callback(l.owner, ...)
    end
end

local function dropOwner(list, owner)
    for i = #list, 1, -1 do
        if list[i].owner == owner then table.remove(list, i) end
    end
end

function S:addScaleListener(owner, callback)      addListener(self._scaleListeners,  owner, callback) end
function S:addHideEquippedListener(owner, cb)     addListener(self._hideEqListeners, owner, cb)       end
function S:addHideHotbarListener(owner, cb)       addListener(self._hotbarListeners, owner, cb)       end

function S:removeListeners(owner)
    dropOwner(self._scaleListeners,  owner)
    dropOwner(self._hideEqListeners, owner)
    dropOwner(self._hotbarListeners, owner)
end

function S:removeListenersForPlayer(playerNum)
    local lists = { self._scaleListeners, self._hideEqListeners, self._hotbarListeners }
    for _, list in ipairs(lists) do
        for i = #list, 1, -1 do
            local owner = list[i].owner
            if owner and owner.playerNum == playerNum then table.remove(list, i) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Metrics
-- ---------------------------------------------------------------------------
local function r(v) return math.floor(v + 0.5) end

--- Recomputes every pixel metric for `scale`. Returns true when something moved.
function S:applyScale(scale)
    scale = math.max(self.MIN_SCALE, math.min(tonumber(scale) or 1, self.MAX_SCALE))
    if self.scale and math.abs(self.scale - scale) < 0.0005 then return false end

    self.scale = scale

    self.pad        = math.max(5, r(7 * scale))
    self.gapX       = math.max(4, r(5 * scale))
    self.gapY       = math.max(4, r(5 * scale))
    self.sectionGap = math.max(6, r(9 * scale))

    self.superSize  = math.max(24, r(34 * scale))   -- the slots around the avatar
    self.slotSize   = math.max(20, r(30 * scale))   -- popup / extra slots

    -- Exactly half a slot: two stacked layer chips fill the height of the slot
    -- they sit beside, which is what makes the pair look intentional instead of
    -- like leftovers.
    self.subStrip   = math.max(9, math.floor(self.superSize / 2))

    -- Deliberately a touch larger than an equipment slot. The hotbar row is the
    -- only part of the panel that grows with the character (every belt adds
    -- slots), so it gets the emphasis and wraps on its own.
    self.hotbarSize = math.max(26, r(42 * scale))

    -- Round slots. A circle of the same diameter reads smaller than a square,
    -- so the hands get a few pixels back.
    self.weaponSize = math.max(28, r(44 * scale))

    -- 16 fissi, non scalati: e' la misura di NR_ResizeWidget.SIZE, e il grip
    -- di Rocco non cresce con la finestra. Scalandolo diventava un pollice
    -- appiccicato all'angolo invece di una freccetta discreta.
    self.gripSize   = Y_GRIP_SIZE
    self.contentW   = r(self.BASE_WIDTH * scale)

    notify(self._scaleListeners, scale)
    return true
end

-- ---------------------------------------------------------------------------
-- Flags
-- ---------------------------------------------------------------------------
--- Replaced by NEQ_ModOptions when that API is around: the eye button in the
--- header writes its value back into the tickbox so the two never disagree.
--- No-op otherwise, which is why it is safe to call unconditionally.
function S.persistHideEquipped(_hide) end

--- persist=false is how Mod Options applies its own saved value without writing
--- it straight back out again.
function S:setHideEquipped(hide, persist)
    hide = hide == true
    if self.hideEquipped == hide then return end
    self.hideEquipped = hide
    if persist ~= false then self.persistHideEquipped(hide) end
    notify(self._hideEqListeners, hide)
end

function S:setHideHotbar(hide)
    hide = hide == true
    if self.hideHotbar == hide then return end
    self.hideHotbar = hide
    notify(self._hotbarListeners, hide)
end

--- La mod spenta per questo giocatore, dalle opzioni: niente tasto, niente
--- pannello, scorciatoie ignorate, e l'elenco dell'inventario torna come lo
--- disegna il gioco. I completi salvati restano dove sono.
---
--- "Nascondi equipaggiati" si spegne senza toccare la casella delle opzioni
--- (persist = false): riaccendendo la mod, apply() rimette il valore scelto.
function S:setDisabled(off)
    self.disabled = off == true
    if self.disabled then self:setHideEquipped(false, false) end
end

function S:setLockPanel(lock)
    self.lockPanel = lock == true
end

--- Con questa attiva il tasto del pannello sul bordo dell'inventario sparisce e il
--- pannello si apre solo con la scorciatoia da tastiera.
---
--- Il tasto non viene distrutto, solo azzerato: e' lui a chiamare
--- updateVisibility ogni frame, ed e' l'unico pezzo sempre vivo. Toglierlo
--- davvero lascerebbe il pannello senza nessuno che lo apre e lo chiude.
--- (METODO/03, lezione 12.)
function S:setHideBagButton(hide)
    self.hideBagButton = hide == true
end

--- With this on, changing outfit puts each piece of the old outfit away in a
--- nearby container that already holds something of its kind, instead of
--- leaving it in the inventory. A piece with no such container stays in the
--- inventory; nothing goes on the floor. See the note on the container swap in
--- NEQ_Dresser.
function S:setWardrobeSwapContainers(swap)
    self.wardrobeSwapContainers = swap == true
end

--- With this on, outfits ignore the hotbar: nothing attached to it and no belt
--- or holster is saved, put on, taken off or put away.
function S:setWardrobeNoHotbar(exclude)
    self.wardrobeNoHotbar = exclude == true
end

--- Con questa attiva il pannello resta arrotolato e si srotola solo quando il
--- puntatore gli passa sopra, come fa una barra laterale. Il pannello sa gia'
--- dove sarebbe anche da chiuso, quindi la zona sensibile e' esattamente il
--- posto che occuperebbe: vedi NEQ_Panel:isHoverHeld.
function S:setShowOnHover(hover)
    self.showOnHover = hover == true
end

--- Con questa attiva, il pannello staccato si apre e si chiude insieme alla
--- finestra dell'inventario - cioe' con lo stesso tasto.
function S:setFollowInventoryKey(follow)
    self.followInventoryKey = follow == true
end

--- Con questa attiva il pannello agganciato e il suo tasto stanno sul bordo
--- **destro** dell'inventario invece che sul sinistro. E' una scelta, non un
--- ripiego automatico: il pannello non cambia lato da solo quando la finestra
--- si avvicina al bordo dello schermo (vedi NEQ_Panel:snapToInventory).
function S:setDockRight(right)
    self.dockRight = right == true
end

--- Con questa attiva il pannello agganciato **non** si ridimensiona da solo
--- per arrivare al fondo dell'inventario: tiene la misura scelta con la
--- maniglia. Serve a chi ha molta roba addosso, dove l'inseguimento
--- dell'altezza rimpicciolisce gli slot fino a renderli difficili da leggere.
function S:setDockKeepScale(keep)
    self.dockKeepScale = keep == true
end

-- I nomi dei bottoni nell'ordine in cui compaiono nella tendina di Mod Options.
local BIND_NAMES = {
    "AButton", "BButton", "XButton", "YButton",
    "LBumper", "RBumper", "Back", "Start",
    "LStickButton", "RStickButton",
}

--- L'ultima voce della tendina non e' un tasto: e' "nessuno", ed e' quella di
--- serie.
---
--- Sul pad non c'e' un tasto libero. Guardando JoyPadSetup.lua:
--- A/B/X/Y sono le azioni, LB e RB aprono le ruote della barra rapida, Start
--- mette in pausa, **Back apre la ruota del tasto Back** (riga 389) e **L3/R3
--- aprono il menu radiale** (riga 426). I nostri due valori di serie erano
--- Back e, con Wookiee installato, L3: tutti e due prendevano il fuoco a una
--- ruota mentre si apriva, che e' la segnalazione "questa mod rompe il menu
--- radiale col controller".
---
--- Quindi niente tasto finche' non lo si sceglie a mano. Chi gioca col pad il
--- pannello lo raggiunge lo stesso: dalla finestra dell'inventario, direzione
--- sinistra (NEQ_Controller.focusPanel), che lo apre se e' chiuso.
local BIND_NONE = #BIND_NAMES + 1
S.BIND_NONE = BIND_NONE

--- Mod Options tiene l'*indice* della tendina. Qui si conserva quello e basta:
--- il valore vero lo si chiede a :controllerButton() al momento del confronto.
function S:setControllerBind(index)
    self.controllerBindIndex = tonumber(index) or BIND_NONE
end

--- Il valore del bottone chiesto a `Joypad` **per nome**, non dedotto dalla
--- posizione nella tendina.
---
--- Prima era `indice - 1`, cioe' la scommessa che l'enum del motore fosse
--- numerato esattamente nell'ordine della nostra lista. Una scommessa del
--- genere, se e' sbagliata, non da' errore: il confronto semplicemente non
--- combacia mai e il tasto sembra morto - che e' esattamente il sintomo.
---
--- La tabella `Joypad` la riempie JoyPadSetup.lua, che non e' detto sia gia'
--- passato quando questo file viene letto: la risoluzione e' quindi tardiva.
--- nil quando non c'e' nessun tasto assegnato: chi confronta deve reggerlo, e
--- lo regge, perche' un tasto vero non e' mai nil.
function S:controllerButton()
    local index = self.controllerBindIndex or BIND_NONE
    if index >= BIND_NONE then return nil end

    local name = BIND_NAMES[index]
    if name and Joypad and Joypad[name] ~= nil then return Joypad[name] end
    return index - 1
end

-- ---------------------------------------------------------------------------
-- Guardia sui personaggi che arrivano dagli eventi
-- ---------------------------------------------------------------------------
--- OnEquipPrimary, OnEquipSecondary e OnClothingUpdated li fa scattare il
--- motore per **qualunque** personaggio: uno zombie a cui una mod mette in mano
--- un'arma li fa partire esattamente come il giocatore. `getPlayerNum` pero'
--- esiste solo su IsoPlayer, quindi chiamarlo su uno zombie fa esplodere il
--- nostro handler dentro il codice di un'altra mod - che e' come si e'
--- presentato il conflitto con "Make Zombie great again".
---
--- E' la stessa guardia che usa ISCharacterInfoWindow.OnClothingUpdated.
--- Vive qui perche' e' l'unico modulo che tutti gli handler hanno gia'.
---@return number|nil playerNum  nil se non e' il giocatore locale
function S.localPlayerNum(character)
    if not character then return nil end
    if not instanceof(character, "IsoPlayer") then return nil end
    if not character:isLocalPlayer() then return nil end
    local num = character:getPlayerNum()
    if not num or num < 0 then return nil end
    return num
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
S.disabled            = false
S.hideEquipped        = false
S.hideHotbar          = false
S.lockPanel           = false
-- On by default, like the tickbox: this is the value in force before the
-- options have been read, and the two must say the same thing.
S.wardrobeSwapContainers = true
S.wardrobeNoHotbar    = false
S.hideBagButton       = false
S.showOnHover         = false
S.followInventoryKey  = false
S.dockKeepScale       = false
S.dockRight           = false
S:setControllerBind(BIND_NONE)

-- Default metrics only. The saved scale is applied by NEQ_Panel when it is
-- built: reading a file at Lua load time is early enough to be fragile, and a
-- docked panel resets to 1.0 anyway.
S:applyScale(1.0)

return S

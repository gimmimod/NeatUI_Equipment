--[[ ============================================================================
    NEQ_Panel - the Equipment window.

    Two lives, switched by the chain button in the header:

      docked    it hangs off the outer edge of the CleanUI inventory - the left
                one, or the right one when Mod Options say so - aligned to
                the bottom of that window's title bar, and follows it around.
                No corner grip here: la misura se la prende da sola, allungandosi
                fino al fondo dell'inventario, cosi' le due finestre finiscono
                insieme e si leggono come una cosa sola. Ridimensiona CleanUI e
                il pannello lo segue.

      floating  free position, dragged by the header, resized by the corner grip.
                Entrambe restano in memoria: riagganciare **non** le butta via,
                e staccandolo di nuovo si ritrova la misura che gli avevi dato.

    Height is never set by hand: NEQ_Body measures its own contents and this
    panel is header + that. Width comes from the scale factor - la maniglia da
    staccato, l'altezza dell'inventario da agganciato.

    The window chrome is a Neat window - MainTitle_BG over MainPanelBG_FlatTop,
    drawn in one place so the rounded corners meet (METODO/03 lessons 2-4).
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISPanel"

local Config           = require("NeatEquipment/NEQ_Config")
local State            = require("NeatEquipment/NEQ_State")
local Style            = require("NeatEquipment/NEQ_Style")
local Drag             = require("NeatEquipment/NEQ_DragDrop")
local ControllerNode   = require("NeatEquipment/NEQ_ControllerNode")
local Dresser          = require("NeatEquipment/NEQ_Dresser")
local NEQ_Grip         = require("NeatEquipment/UI/NEQ_Grip")
local NEQ_Header       = require("NeatEquipment/UI/NEQ_Header")
local NEQ_Body         = require("NeatEquipment/UI/NEQ_Body")
local NEQ_SuperSlotPopup = require("NeatEquipment/UI/NEQ_SuperSlotPopup")
local NEQ_Wardrobe     = require("NeatEquipment/UI/NEQ_Wardrobe")

local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

---@class NEQ_Panel : ISPanel
local NEQ_Panel = ISPanel:derive("NEQ_Panel")

-- L'altezza del canone Neat (STILE.md, dal framework di Rocco): 1.5 volte il
-- carattere medio, la stessa del guardaroba.
--
-- La 1.0.0 l'aveva abbassata a quella della barra del titolo di CleanUI (1.2
-- volte il carattere piccolo), perche' agganciato il pannello continuasse la
-- loro barra. Ma i tasti sono una frazione dell'altezza (Style.HEADER), e
-- scesero da 21-26 pixel a 15-16 a 1080p: "buttons are way smaller since the
-- last update", e difficili da prendere. Torna il canone; della 1.0.0 resta
-- l'allineamento in alto con l'inventario (snapToInventory), che era la
-- richiesta vera.
NEQ_Panel.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.5)

function NEQ_Panel:new(inventoryPane, playerNum)
    local inventoryPage = inventoryPane.parent

    -- Lo stato salvato va letto prima che il pannello esista: la larghezza con
    -- cui nasce viene dalla scala. Qui si parte sempre dall'ultima misura nota,
    -- anche da agganciato: la misura giusta dipende dall'altezza che il corpo
    -- avra' una volta costruito, che adesso non esiste ancora. Ci pensa
    -- followInventory ai primi frame, mentre il pannello e' ancora arrotolato.
    local config = Config.get()
    local docked = config.docked ~= false
    State:applyScale(Config.startingScale())

    local o = ISPanel:new(0, 0, State.contentW, 200)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.drawFrame = false

    o.inventoryPane = inventoryPane
    o.inventoryPage = inventoryPage
    o.playerNum = playerNum
    o.char = getSpecificPlayer(playerNum)
    o.state = State

    o.docked = docked
    o.closed = config.closed == true

    -- Starts fully rolled up whatever the saved state says, so an open panel
    -- unrolls on the first frame rather than being there before the window is.
    o.anim = 0
    o.freeX = config.pos_x
    o.freeY = config.pos_y

    -- A controller player has no way to click the panel button, so the panel
    -- starts closed and is opened with the pad binding instead.
    if o:isController() then o.closed = true end

    return o
end

function NEQ_Panel:isController()
    local pad = JoypadState.players[self.playerNum + 1]
    return pad ~= nil and pad.isActive == true
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
function NEQ_Panel:createChildren()
    ISPanel.createChildren(self)

    self.popup = NEQ_SuperSlotPopup:new(0, 0, 0, 0)
    self.popup:initialise()
    self.popup:setVisible(false)
    self.popup:addToUIManager()

    self.header = NEQ_Header:new(0, 0, self.width, NEQ_Panel.headerHeight, self)
    self.header:initialise()
    self:addChild(self.header)

    self.body = NEQ_Body:new(0, NEQ_Panel.headerHeight, State.contentW,
        self.inventoryPane, self.playerNum, self.popup)
    self.body:initialise()
    self:addChild(self.body)

    self:createResizeWidget()

    State:addScaleListener(self, NEQ_Panel.onScaleChanged)
    State:addHideEquippedListener(self, NEQ_Panel.onHideEquippedChanged)

    ControllerNode
        :injectControllerNode(self, true)
        :setChildrenNodeProvider(self.body.getControllerNodes, self.body)

    -- Hidden until updateVisibility says otherwise; the animation is what
    -- brings it in.
    self:setVisible(false)
    self:applyGeometry()
end

function NEQ_Panel:createResizeWidget()
    local panel = self

    self.resizeWidget = NEQ_Grip:new(State.gripSize, self,
        function(width) panel:onGripResize(width) end,
        function() Config.set("scale", State.scale) end)

    self.resizeWidget:initialise()

    -- Handed to the body, not kept here: see NEQ_Body:attachGrip. It still
    -- measures against this panel - startWidth comes from the target, and the
    -- target is the window being resized.
    self.body:attachGrip(self.resizeWidget)
end

--- The grip reports where the cursor is; this decides what that means. Every
--- clamp lives here now, because nothing upstream applies one.
function NEQ_Panel:onGripResize(width)
    if self.docked or State.lockPanel then return end

    local floor = math.max(
        self.header and self.header:requiredWidth() or 0,
        math.floor(State.BASE_WIDTH * State.MIN_SCALE))
    local ceiling = math.floor(State.BASE_WIDTH * State.MAX_SCALE)

    -- E mai piu' grande di quello che lo schermo lascia, a partire da dove sta
    -- il pannello: oltre, la maniglia finiva sotto il bordo e il pannello non
    -- si poteva piu' rimpicciolire (segnalazione 42.21).
    ceiling = math.min(ceiling, math.floor(State.BASE_WIDTH * self:screenFitScale()))

    width = math.max(floor, math.min(width, ceiling))
    State:applyScale(width / State.BASE_WIDTH)
end

--- La scala piu' grande con cui il pannello staccato sta tutto nello schermo,
--- dalla posizione in cui si trova. L'altezza cresce con la scala in
--- proporzione (header compreso, quasi), quindi basta una proporzione sulla
--- misura di adesso.
function NEQ_Panel:screenFitScale()
    local scale = State.scale or 1.0
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local w, h = self:getWidth(), self:getHeight()
    if w <= 0 or h <= 0 then return State.MAX_SCALE end

    local x = math.max(0, self:getX())
    local y = math.max(0, self:getY())
    local fitW = scale * (screenW - x) / w
    local fitH = scale * (screenH - y) / h
    -- Mai sotto la minima: su uno schermo minuscolo vince la leggibilita', e
    -- keepOnScreen sposta il pannello invece di schiacciarlo.
    return math.max(State.MIN_SCALE, math.min(State.MAX_SCALE, fitW, fitH))
end

--- Il pannello staccato resta tutto dentro lo schermo, maniglia compresa.
---
--- Se e' piu' alto o largo dello schermo intero (una misura salvata su un
--- monitor piu' grande, o una risoluzione cambiata) prima si rimpicciolisce,
--- poi si sposta. E' cosi' che un pannello "che blocca il gioco" non puo' piu'
--- nascere: la misura salvata viene corretta alla prima apertura.
function NEQ_Panel:keepOnScreen()
    if self.docked or self.neqFitting then return end
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    if self:getHeight() > screenH or self:getWidth() > screenW then
        local scale = State.scale or 1.0
        local fit = scale * math.min(screenH / self:getHeight(), screenW / self:getWidth())
        self.neqFitting = true
        local changed = State:applyScale(fit)
        self.neqFitting = false
        -- applyScale ha gia' rifatto la geometria (onScaleChanged); la
        -- chiamata annidata qui e' uscita subito, quindi la posizione si
        -- sistema sotto, con la misura nuova.
        if changed then Config.set("scale", State.scale) end
    end

    local x = math.max(0, math.min(self:getX(), screenW - self:getWidth()))
    local y = math.max(0, math.min(self:getY(), screenH - self:getHeight()))
    if x ~= self:getX() or y ~= self:getY() then
        self:setX(x)
        self:setY(y)
        self.freeX, self.freeY = x, y
    end
end

--- Misura e posizione di partenza, come al primo avvio: dal tasto nelle
--- opzioni. Il pannello torna anche agganciato all'inventario, che e' il
--- posto da cui lo si ritrova sempre.
function NEQ_Panel:resetGeometry()
    local config = Config.get()
    config.scale = 0
    config.pos_x = -1
    config.pos_y = -1
    Config.save()
    self.freeX, self.freeY = nil, nil
    if not self.docked then self:setDocked(true) end
    State:applyScale(Config.startingScale())
    self:applyGeometry()
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------
--- Quanto in basso deve arrivare il pannello agganciato: fino al fondo della
--- finestra a cui e' appeso. Il pannello non parte dal bordo superiore
--- dell'inventario ma da sotto il tasto del pannello, quindi il bersaglio e' la
--- distanza fra dove comincia e dove finisce l'inventario, non l'altezza
--- dell'inventario in se'.
function NEQ_Panel:dockedTargetHeight()
    local page = self.inventoryPage
    if not page then return nil end

    local target = (page:getY() + page:getHeight()) - self:getY()
    if target <= 0 then return nil end
    return target
end

--- Agganciato, la misura la detta l'**altezza** della finestra a cui e'
--- appeso. Staccato, vale quella lasciata dalla maniglia d'angolo.
---
--- La larghezza era la scelta ovvia, ed era sbagliata: l'inventario di CleanUI
--- e' largo circa mille pixel - e' una lista a piu' colonne - mentre questo e'
--- un pannello stretto e alto con dentro un manichino. Copiarne la larghezza
--- voleva dire una scala oltre 4, cioe' slot da 136 px: enorme. E siccome
--- restava schiacciata contro il tetto, il pannello smetteva anche di seguire
--- l'inventario, che era il secondo sintomo.
---
--- L'altezza e' la misura che corrisponde davvero: sono i bordi inferiori che
--- combaciano a far leggere le due finestre come una cosa sola.
---
--- Per l'altezza non c'e' una formula chiusa - le righe della barra rapida
--- vanno a capo, e il corpo cresce con quello che il personaggio ha addosso -
--- ma cresce insieme alla scala. Una proporzione sulla misura attuale centra
--- il bersaglio in un passo, e il frame dopo lo rifinisce.
function NEQ_Panel:desiredScale()
    if not self.docked or State.dockKeepScale then return Config.startingScale() end

    local scale = State.scale or 1.0
    local target = self:dockedTargetHeight()
    local current = self:getHeight()
    if not target or not current or current <= 0 then return scale end

    return scale * target / current
end

--- La zona morta e' quello che tiene ferma la cosa: senza, il pannello
--- inseguirebbe l'altezza un pixel alla volta per sempre.
local HEIGHT_TOLERANCE = 8

--- Sta qui e non in prerender perche' prerender non gira sul pannello chiuso:
--- cosi' riaprirlo lo trova gia' della misura giusta.
--- Quanti aggiustamenti concedersi per uno stesso bersaglio.
local MAX_PASSES = 3

function NEQ_Panel:followInventory()
    if not self.docked then return end

    -- Chi non vuole il pannello agganciato che si ridimensiona da solo lo dice
    -- da Mod Options: resta della misura scelta a mano e basta. La si riapplica
    -- invece di uscire e basta, cosi' spuntare la casella si vede subito;
    -- applyScale non fa niente quando la misura e' gia' quella.
    if State.dockKeepScale then
        State:applyScale(Config.startingScale())
        return
    end

    local target = self:dockedTargetHeight()
    if not target then return end

    -- Un bersaglio nuovo riapre la rincorsa; finche' resta lo stesso ci si
    -- concede pochi passi e poi ci si ferma, anche senza aver centrato al
    -- pixel. L'altezza non e' continua: una riga della barra rapida che va a
    -- capo la fa saltare di colpo, e senza questo freno il pannello
    -- rimbalzerebbe fra le due misure per sempre, sotto gli occhi.
    --
    -- "Bersaglio" pero' non e' solo dove finisce l'inventario: e' anche di cosa
    -- e' fatto il pannello. Una cintura in piu' aggiunge slot alla barra
    -- rapida, cioe' una riga, cioe' altezza che non viene da qui - e senza
    -- rimettere in conto i passi il pannello restava rimpicciolito anche dopo
    -- averla tolta. Vedi NEQ_Body:layoutSignature.
    local signature = target .. "|" .. self.body:layoutSignature()
    if signature ~= self.lastDockTarget then
        self.lastDockTarget = signature
        self.dockPasses = 0
    end
    if (self.dockPasses or 0) >= MAX_PASSES then return end

    local current = self:getHeight()
    if not current or current <= 0 then return end
    if math.abs(current - target) <= HEIGHT_TOLERANCE then return end

    -- Contro un fermo, insistere non cambia l'altezza: si girerebbe a vuoto a
    -- ogni frame senza che si muova niente.
    local scale = State.scale or 1.0
    if (target > current and scale >= State.MAX_SCALE)
        or (target < current and scale <= State.MIN_SCALE) then return end

    self.dockPasses = (self.dockPasses or 0) + 1

    -- applyScale avvisa il listener, che richiama applyGeometry da solo.
    State:applyScale(self:desiredScale())
end

function NEQ_Panel:onScaleChanged()
    self:applyGeometry()
end

--- Re-measures the window and, when docked, re-attaches it to the inventory.
function NEQ_Panel:applyGeometry()
    local headerH = NEQ_Panel.headerHeight

    self:setWidth(State.contentW)
    self.header:setWidth(self.width)
    self.header:layout()

    self.body:setX(0)
    self.body:setY(headerH)
    if self.body:getWidth() ~= State.contentW then
        self.body:setWidth(State.contentW)
        self.body:layout()
    end

    self:setHeight(headerH + self.body:getHeight())

    if self.docked then
        self:snapToInventory()
    else
        -- A floating panel that has never been placed by hand starts where the
        -- docked one sat, nudged clear of the inventory.
        if not self.freeX or self.freeX < 0 then
            self:snapToInventory()
            self.freeX = self:getX() + self:outward() * 8
            self.freeY = self:getY()
        end
        self:setX(self.freeX)
        self:setY(self.freeY)
        self:keepOnScreen()
    end

    self:positionResizeWidget()
end

--- Which way is away from the inventory: -1 on the left edge, 1 on the right.
function NEQ_Panel:outward()
    return State.dockRight and 1 or -1
end

function NEQ_Panel:snapToInventory()
    local page = self.inventoryPage
    if not page then return end


    -- The side the player chose in Mod Options, the left edge by default, and
    -- only that one. Flipping sides by itself when the inventory nears the
    -- screen edge sounds helpful and is not: the panel and its button jump
    -- across the window while you are looking at them.
    if State.dockRight then
        self:setX(page:getX() + page:getWidth() - 1)
    else
        self:setX(page:getX() - self:getWidth() + 1)
    end

    -- A filo del bordo alto dell'inventario. Prima il pannello partiva sotto
    -- il tasto con la figura, e agganciato stava piu' in basso di CleanUI
    -- lasciando un vuoto in alto (segnalazione 42.21). Il tasto sta dentro la
    -- nostra barra, centrato nella sua altezza (NEQ_ToggleButton:reposition):
    -- l'intestazione gli lascia il posto (headerReserve).
    local top = page:getY()

    -- The panel is taller than the inventory's title bar by a long way, so an
    -- inventory window sitting low on the screen would push it off the bottom.
    local y = top
    local screenH = getCore():getScreenHeight()
    if y + self:getHeight() > screenH then
        y = math.max(0, screenH - self:getHeight())
    end
    self:setY(y)
    if self.header then self.header:layout() end
end

--- Lo spazio che l'intestazione lascia al tasto con la figura, e da che parte.
--- Agganciato il tasto sta dentro la nostra barra, sul lato dell'inventario:
--- a destra con il pannello a sinistra, e viceversa. Staccato, nessuno.
---@return string|nil side, number px
function NEQ_Panel:headerReserve()
    if not self.docked or not self.toggleButton then return nil, 0 end
    if State.hideBagButton or State.disabled then return nil, 0 end
    return State.dockRight and "left" or "right", self.toggleButton:reserveInPanel()
end

function NEQ_Panel:positionResizeWidget()
    if not self.resizeWidget then return end
    local show = (not self.docked) and (not State.lockPanel)
    self.body:positionGrip(State.gripSize, show)
end

function NEQ_Panel:clampToScreen()
    if self.docked then return end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local margin = 24

    local x = math.max(-self.width + margin, math.min(self:getX(), screenW - margin))
    local y = math.max(0, math.min(self:getY(), screenH - margin))
    self:setX(x)
    self:setY(y)
end

function NEQ_Panel:savePosition()
    if self.docked then return end
    self.freeX = self:getX()
    self.freeY = self:getY()

    local config = Config.get()
    config.pos_x = self.freeX
    config.pos_y = self.freeY
    Config.save()
end

-- ---------------------------------------------------------------------------
-- Dock / undock / close
-- ---------------------------------------------------------------------------
function NEQ_Panel:toggleDocked()
    self:setDocked(not self.docked)
end

function NEQ_Panel:setDocked(docked)
    docked = docked == true
    if self.docked == docked then return end

    if not docked then
        -- Undock: start from where the panel already is, nudged clear of the
        -- inventory, unless a free position was saved earlier.
        if not self.freeX or self.freeX < 0 then
            self.freeX = self:getX() + self:outward() * 8
            self.freeY = self:getY()
        end
        self.docked = false

        -- Torna la misura scelta a mano l'ultima volta, non quella che aveva
        -- da agganciato.
        State:applyScale(self:desiredScale())
        self:applyGeometry()
        self:clampToScreen()
        self:savePosition()
        self:bringToTop()
    else
        -- Riagganciare rimette il pannello al suo posto e lo lascia
        -- riallungare fino al fondo dell'inventario. La misura scelta a mano
        -- **non** viene buttata via: resta in config e torna quando lo si
        -- stacca di nuovo.
        self.docked = true
        self.lastDockTarget = nil
        self:followInventory()
        self:applyGeometry()
    end

    Config.set("docked", self.docked)
    self.header:refreshButtons()
end

--- Only the flag is set here. updateVisibility does the rest on the next
--- frame, so the panel rolls shut instead of blinking out.
function NEQ_Panel:closePanel()
    self.closed = true
    self.popup:close()
    Config.set("closed", true)
end

function NEQ_Panel:openPanel()
    self.closed = false
    Config.set("closed", false)
    if not self.docked then self:bringToTop() end
end

--- Reads the flag, never the animation. Asking "am I visible" mid-roll gets a
--- different answer depending on which tenth of a second you asked in, which is
--- how a double-click used to leave the panel open and the button saying closed.
---@return boolean isOpen
function NEQ_Panel:togglePanel()
    if self.closed then self:openPanel() else self:closePanel() end
    return not self.closed
end

-- ---------------------------------------------------------------------------
-- Hide equipped items
-- ---------------------------------------------------------------------------
function NEQ_Panel:toggleHideEquipped()
    State:setHideEquipped(not State.hideEquipped, true)
end

function NEQ_Panel:onHideEquippedChanged()
    self.header:refreshButtons()
end

-- ---------------------------------------------------------------------------
-- Strip / restore
-- ---------------------------------------------------------------------------
--- The strip button is a three-state thing, not a two-state one:
---
---     nil          nothing pending - the button strips
---     "stripping"  the unequips are still running - the button does nothing
---     "stripped"   everything is off - the button puts it all back
---
--- The middle state is the point. Pressing during the undressing used to queue
--- a restore on top of a half-finished strip, and the two would interleave into
--- a survivor wearing some of the outfit and none of the plan. Now the button
--- simply is not available until the last garment is off, so a click can never
--- land in the middle of the process.
local STRIP_GRACE_MS = 500

local function wornCount(character)
    local worn = character:getWornItems()
    local count = 0
    for i = 0, worn:size() - 1 do
        local entry = worn:get(i)
        local item = entry and entry:getItem()
        if item and not item:isHidden() then count = count + 1 end
    end
    return count
end

local function isBusy(character)
    local ok, busy = pcall(function()
        return ISTimedActionQueue.isPlayerDoingAction(character)
    end)
    return ok and busy == true
end

--- Advances the state machine. Called once a frame from prerender.
function NEQ_Panel:updateStripState()
    if not self.pendingOutfit then
        self.stripState = nil
        return
    end

    -- Wearing something the snapshot never knew about means the survivor has
    -- dressed themselves; offering to "put back" a state that no longer means
    -- anything would be a lie.
    if not Dresser.snapshotStillPending(self.char, self.pendingOutfit) then
        self.pendingOutfit = nil
        self.stripState = nil
        return
    end

    if self.stripState ~= "stripping" then return end

    if wornCount(self.char) == 0 then
        self.stripState = "stripped"
        return
    end

    -- The queue drained with clothes still on: the survivor walked away, or
    -- something else cleared it. Half-undressed is a normal state to be in, but
    -- it is not one the restore was promised for, so the offer is withdrawn
    -- rather than left hanging.
    local elapsed = getTimestampMs() - (self.stripStartedAt or 0)
    if elapsed > STRIP_GRACE_MS and not isBusy(self.char) then
        self.pendingOutfit = nil
        self.stripState = nil
    end
end

--- True when the button should offer to put the outfit back on.
function NEQ_Panel:canRestoreOutfit()
    return self.stripState == "stripped"
end

--- True while the undressing is still running: the button is drawn dimmed and
--- ignores clicks.
function NEQ_Panel:isStripBusy()
    return self.stripState == "stripping"
end

--- One button, both directions. Press it to strip; once everything is off,
--- press it again and exactly what came off goes back on, with anything picked
--- up in between taken off - so two presses always land where you started.
function NEQ_Panel:toggleStrip()
    if self:isStripBusy() then return end

    if self:canRestoreOutfit() then
        Dresser.restore(self.char, self.pendingOutfit)
        self.pendingOutfit = nil
        self.stripState = nil
    else
        local snapshot = Dresser.snapshotWorn(self.char)
        if #snapshot == 0 then
            self.char:setHaloNote(getText("UI_NEQ_nothing_worn"), 200, 200, 200, 250)
            return
        end
        Dresser.stripAll(self.char)
        self.pendingOutfit = snapshot
        self.stripState = "stripping"
        self.stripStartedAt = getTimestampMs()
    end

    getSoundManager():playUISound("UIActivateButton")
    self.header:refreshButtons()
end

--- Is the wardrobe window up? The header button lights while it is.
function NEQ_Panel:isWardrobeOpen()
    return self.wardrobe ~= nil and self.wardrobe:isVisible()
end

-- ---------------------------------------------------------------------------
-- Wardrobe
-- ---------------------------------------------------------------------------
function NEQ_Panel:openWardrobe()
    if self.wardrobe and self.wardrobe:isVisible() then
        self.wardrobe:onClose()
        return
    end

    if not self.wardrobe then
        self.wardrobe = NEQ_Wardrobe:new(self.playerNum)
        self.wardrobe:initialise()
    end

    self.wardrobe:setVisible(true)
    self.wardrobe:addToUIManager()
    self.wardrobe:layout()

    -- Placed beside the panel the first time and left where the player puts it
    -- after that: it is a window of its own, and a window that jumps back to
    -- its starting corner every time you open it is a window you have to move
    -- every time you open it. Beside means on the outer side, away from the
    -- inventory, and on the other one only when the screen ends first.
    if not self.wardrobe.placed then
        self.wardrobe.placed = true

        local screenW = getCore():getScreenWidth()
        local w = self.wardrobe:getWidth()
        local left = self:getX() - w - 4
        local right = self:getX() + self:getWidth() + 4
        local x = State.dockRight and right or left
        if x < 0 or x + w > screenW then x = State.dockRight and left or right end
        self.wardrobe:setX(math.max(0, math.min(x, screenW - w)))
        self.wardrobe:setY(self:getY())
    end

    self.wardrobe:clampToScreen()
    self.wardrobe:bringToTop()
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------
--- Whether the panel should currently be on screen.
---
--- This is driven from NEQ_ToggleButton's prerender rather than from this
--- panel's own, on purpose: prerender does not run on a hidden element, so a
--- panel that hides itself could never decide to come back. The panel button is
--- the one piece that is always alive, so it owns the decision.
--- Should the panel be on screen at all, ignoring the animation?
function NEQ_Panel:wantsToBeOpen()
    if self.closed or State.disabled then return false end

    if self.docked then
        local page = self.inventoryPage
        -- A collapsed inventory is a title bar and nothing else; a full
        -- equipment panel still hanging off it would look detached from
        -- anything.
        if not (page:isVisible() and page.isCollapsed ~= true) then return false end
    end

    if State.showOnHover then return self:isHoverHeld() end
    return true
end

-- How long the panel stays out after the pointer has left it. Without a grace
-- period the panel closes in the gap between the panel button and its own edge,
-- and reopens the moment the pointer lands - which reads as a flicker, not as
-- a window.
local HOVER_GRACE_MS = 350

--- Mouse inside `element`, with a margin. Reads the pointer straight from the
--- engine rather than asking the element: this has to answer for a panel that
--- is currently rolled up, and a hidden element is never "moused over".
local function pointerOver(element, margin)
    if not element or element:getWidth() <= 0 or element:getHeight() <= 0 then return false end

    local mx, my = getMouseX(), getMouseY()
    local x, y = element:getAbsoluteX(), element:getAbsoluteY()
    return mx >= x - margin and mx <= x + element:getWidth() + margin
        and my >= y - margin and my <= y + element:getHeight() + margin
end

--- True while the panel should be out in hover mode: the pointer is on it, on
--- the panel button, or on the layer popup - or has been within the last moment.
function NEQ_Panel:isHoverHeld()
    -- The rolled-up panel is still the trigger area, so it has to be where the
    -- inventory is now. prerender does that job while the panel is on screen,
    -- and prerender is exactly what does not run while it is not.
    if self.docked then self:snapToInventory() end

    -- Dragging a garment out of the panel takes the pointer off it, and a
    -- panel that rolls up under a dragged item is a panel you cannot drag out
    -- of. It stays until the item is dropped.
    if Drag.isDragging() then
        self.hoverUntil = getTimestampMs() + HOVER_GRACE_MS
        return true
    end

    local margin = 4
    local over = pointerOver(self, margin)
        or pointerOver(self.toggleButton, margin)
        or (self.popup and self.popup:isVisible() and pointerOver(self.popup, margin))

    local now = getTimestampMs()
    if over then
        self.hoverUntil = now + HOVER_GRACE_MS
        return true
    end
    return (self.hoverUntil or 0) > now
end

--- Detached, an option ties the panel to the inventory window: the key that
--- opens the inventory opens this too, and closing the inventory closes it.
--- Mirrors the window's own visibility rather than listening for the key, so
--- the close button and everything else that hides the inventory count as
--- well.
function NEQ_Panel:followInventoryVisibility()
    if self.docked or not State.followInventoryKey then
        self.lastPageVisible = nil
        return
    end

    local page = self.inventoryPage
    if not page then return end

    local visible = page:isVisible() == true
    if self.lastPageVisible == nil then
        -- First frame under the option: take note of where things stand rather
        -- than making the panel match, or ticking the box would shut a panel
        -- nobody asked to shut.
        self.lastPageVisible = visible
        return
    end
    if visible == self.lastPageVisible then return end

    self.lastPageVisible = visible
    if visible then self:openPanel() else self:closePanel() end
end

-- The panel unrolls from under its own header rather than appearing whole.
-- 150ms is long enough to read as a movement and short enough that a player
-- toggling it repeatedly never waits for it.
local OPEN_MS = 150

local function smoothstep(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

--- True when the inventory window this panel belongs to is off screen.
---
--- Vanilla hides it with a plain setVisible(false) (ISInventoryPage.lua:2100):
--- one frame it is there, the next it is gone, with no animation of its own.
---
--- Collapsing counts too, for an attached panel. An unpinned inventory folds
--- itself to a title bar when the pointer has been away for a moment - CleanUI
--- does it in one frame (collapseNow, ISInventoryPage.lua:2476) - but the
--- window stays "visible", so the panel used to roll up behind it instead of
--- going with it.
function NEQ_Panel:inventoryHidden()
    local page = self.inventoryPage
    if not page then return false end
    if page:isVisible() ~= true then return true end
    return self.docked == true and page.isCollapsed == true
end

function NEQ_Panel:updateVisibility()
    -- Anche a pannello chiuso: se l'inventario viene ridimensionato mentre il
    -- pannello e' giu', riaprendolo deve essere gia' della misura giusta.
    self:followInventory()
    self:followInventoryVisibility()

    local target = self:wantsToBeOpen() and 1 or 0

    -- Stepped here, not in prerender: prerender does not run on a hidden
    -- element, so a closing panel would freeze halfway and a closed one could
    -- never start opening again.
    local now = getTimestampMs()
    local elapsed = math.min(now - (self.animAt or now), 100)
    self.animAt = now

    if target == 0 and self:inventoryHidden() then
        -- Chiuso perche' e' sparita la finestra a cui e' attaccato, non perche'
        -- l'ha chiuso qualcuno: srotolarsi via in OPEN_MS dopo che l'inventario
        -- e' gia' sparito si legge come un pannello che resta indietro. Quando
        -- e' la finestra a portarlo via, se ne va insieme a lei.
        -- Solo in chiusura: in apertura la finestra c'e' gia', e lo srotolamento
        -- si legge come voluto.
        self.anim = 0
    else
        local step = elapsed / OPEN_MS
        if target > (self.anim or 0) then
            self.anim = math.min(1, (self.anim or 0) + step)
        elseif target < (self.anim or 0) then
            self.anim = math.max(0, (self.anim or 0) - step)
        end
    end

    local visible = (self.anim or 0) > 0
    if self:isVisible() ~= visible then
        self:setVisible(visible)
        -- The wardrobe is deliberately left alone: it is its own window, and
        -- only its own close button shuts it.
        if not visible then self.popup:close() end
    end
end

--- How much of the panel is currently drawn, 0..1.
function NEQ_Panel:openFraction()
    return smoothstep(self.anim or 0)
end

function NEQ_Panel:prerender()
    if self.docked then
        self:snapToInventory()
    end

    -- The body grows and shrinks with what the character is wearing.
    local wanted = NEQ_Panel.headerHeight + self.body:getHeight()
    if self.height ~= wanted then
        self:setHeight(wanted)
        self:positionResizeWidget()
    end

    self:updateStripState()

    -- Compared rather than refreshed blindly: refreshButtons touches four
    -- widgets and this runs every frame.
    local canRestore = self:canRestoreOutfit()
    local wardrobeOpen = self:isWardrobeOpen()
    if canRestore ~= self.lastRestoreState or wardrobeOpen ~= self.lastWardrobeOpen then
        self.lastRestoreState = canRestore
        self.lastWardrobeOpen = wardrobeOpen
        self.header:refreshButtons()
    end

    -- Mid-animation the window is clipped to a fraction of its height, so it
    -- rolls out from under its own header instead of snapping into place.
    -- setMaxDrawHeight clips the children too, which is why this is one line
    -- rather than an alpha applied to a dozen widgets that would each need to
    -- know about it.
    local fraction = self:openFraction()
    if fraction < 1 then
        self:setMaxDrawHeight(math.max(1, math.floor(self.height * fraction)))
        self.popup:close()
    else
        self:clearMaxDrawHeight()
    end

    -- Agganciato, il lato esterno e' quello opposto all'inventario: conta per
    -- l'aspetto CleanUI, che arrotonda un angolo solo (Style.drawWindow).
    local side = nil
    if self.docked then side = State.dockRight and "right" or "left" end
    Style.drawWindow(self, 0, 0, self.width, self.height, NEQ_Panel.headerHeight, side)
end

function NEQ_Panel:render()
    -- Drawn here rather than by the header: render runs after every child, so
    -- the label lands on top of the body instead of under it.
    if self:openFraction() >= 1 then
        -- A button that does nothing should look like it does nothing.
        local strip = self:isStripBusy() and self.header.stripButton
        if strip then
            self:drawRect(self.header.x + strip:getX(), self.header.y + strip:getY(),
                strip:getWidth(), strip:getHeight(), 0.55, 0.06, 0.06, 0.07)
        end

        local text, centreX, bottomY = self.header:hoveredTip()
        if text then
            Style.drawButtonTip(self, text, centreX, bottomY, true, 2, self.width - 2)
        end
    end

    if self.joyfocus then
        local c = ControllerNode.FOCUS_COLOR
        self:drawRectBorder(0, 0, self.width, self.height, 0.4, c.r, c.g, c.b)
        self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 0.4, c.r, c.g, c.b)
    end
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------
function NEQ_Panel:onMouseDown(x, y)
    if not self.docked then
        self:bringToTop()
    end
    return false
end

--- The layer popup stays in front of the panel it belongs to, whatever brought
--- the panel forward: a popup behind its own panel is a popup that has closed,
--- as far as anyone can see.
function NEQ_Panel:bringToTop()
    ISPanel.bringToTop(self)
    if self.toggleButton then self.toggleButton:bringToTop() end
    if self.popup and self.popup:isVisible() then self.popup:bringToTop() end
end

-- ---------------------------------------------------------------------------
-- Teardown
-- ---------------------------------------------------------------------------
function NEQ_Panel:removeFromUIManager()
    if not self.cleanedUp then
        self.cleanedUp = true

        if self.body then self.body:dispose() end
        State:removeListeners(self)
        State:removeListenersForPlayer(self.playerNum)

        if self.popup then
            self.popup:close()
            self.popup:removeFromUIManager()
        end
        if self.wardrobe then
            self.wardrobe:setVisible(false)
            self.wardrobe:removeFromUIManager()
            self.wardrobe = nil
        end
        if self.toggleButton then
            self.toggleButton:removeFromUIManager()
            self.toggleButton = nil
        end
    end

    ISPanel.removeFromUIManager(self)
end

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------
--- Towards the inventory it hangs from, away from it the loot: on the left
--- edge that is right and left, on the right edge the other way round.
function NEQ_Panel:onJoypadDirLeft(joypadData)
    local page = State.dockRight and getPlayerInventory(self.playerNum) or getPlayerLoot(self.playerNum)
    setJoypadFocus(self.playerNum, page)
end

function NEQ_Panel:onJoypadDirRight(joypadData)
    local page = State.dockRight and getPlayerLoot(self.playerNum) or getPlayerInventory(self.playerNum)
    setJoypadFocus(self.playerNum, page)
end

function NEQ_Panel:onJoypadDown(button)
    if button == Joypad.YButton then
        setJoypadFocus(self.playerNum, nil)
        local inventory = getPlayerInventory(self.playerNum)
        if inventory and inventory.onLoseJoypadFocus then
            inventory:onLoseJoypadFocus(nil)
        end
    end
end

return NEQ_Panel

--[[ ============================================================================
    NEQ_Style - every pixel NeatUI Equipment paints goes through here.

    Two source styles are being reconciled:

      * the panel itself is a Neat window - MainTitle_BG header over a
        MainPanelBG_FlatTop body, grey tints 0.08 / 0.15, orange accent only on
        active states (METODO/01_STILE_NEATUI).
      * the slots are Clean HotBar slots - the same rounded-square mask, the
        same 0.35 / 0.5 brightness pair, the same item border and inner glow, so
        an equipment slot and a hotbar slot read as the same component.

    Slot art resolves to Clean HotBar's own files when that mod is installed and
    to the byte-identical copies bundled under media/ui/NeatEquipment/ otherwise
    - the same trick NeatXPStyle uses for CleanUI's padlock. Clean HotBar is not
    a dependency, and its media tree only exists when it is enabled.

    NinePatchTexture.getSharedTexture is called inline, fresh, every frame: it is
    already the shared cache, and caching a nil from the first frames leaves the
    panel square for the whole session (METODO/03 lesson 1).
============================================================================ ]]--

if isServer() then return end

NEQ_Style = NEQ_Style or {}
local Y = NEQ_Style

-- ---------------------------------------------------------------------------
-- Palette (Neat Rocco NR_Config)
-- ---------------------------------------------------------------------------
Y.accent    = { r = 0.95, g = 0.50, b = 0.10 }
Y.close     = { r = 0.80, g = 0.20, b = 0.20 }
Y.selection = { r = 0.30, g = 0.72, b = 0.38 }
Y.text      = { r = 0.90, g = 0.90, b = 0.90 }
Y.dim       = { r = 0.62, g = 0.62, b = 0.64 }
Y.separator = { r = 0.40, g = 0.40, b = 0.42 }

-- CleanUI's own highlight (ISInventoryPage.highlightColors). Used for the
-- border of a slot holding something, so an occupied slot here and a
-- highlighted row over in the inventory are the same colour.
Y.equipped  = { r = 0.98, g = 0.56, b = 0.11 }

Y.TINT_HEADER = 0.08
Y.TINT_BODY   = 0.15
Y.PANEL_ALPHA = 1.0

-- ---------------------------------------------------------------------------
-- Anatomia della barra del titolo
-- ---------------------------------------------------------------------------
--- Le proporzioni dell'intestazione, in un posto solo.
---
--- Ogni finestra della famiglia le legge da qui invece di rifarsi i conti per
--- conto suo: e' l'unico modo perche' due intestazioni non finiscano con tasti
--- di misura diversa, che e' esattamente com'erano finite. Le stesse
--- proporzioni valgono per la riga di una lista, cosi' un tasto su una riga e
--- un tasto nell'intestazione hanno lo stesso rapporto con cio' che li
--- contiene.
Y.HEADER = {
    button = 0.80,   -- lato del tasto quadrato, sull'altezza della barra
    icon   = 0.64,   -- icona del titolo
    pad    = 0.16,   -- margine ai due capi
    gap    = 0.07,   -- spazio fra due tasti vicini
}

function Y.headerButtonSize(h) return math.max(15, math.floor(h * Y.HEADER.button)) end
function Y.headerIconSize(h)   return math.max(10, math.floor(h * Y.HEADER.icon))   end
function Y.headerPadding(h)    return math.max(3,  math.floor(h * Y.HEADER.pad))    end
function Y.headerGap(h)        return math.max(2,  math.floor(h * Y.HEADER.gap))    end

-- Clean HotBar slot brightness pair.
Y.SLOT_BRIGHT       = 0.35
Y.SLOT_BRIGHT_HOVER = 0.50
Y.SLOT_ALPHA        = 0.60

-- ---------------------------------------------------------------------------
-- Textures
-- ---------------------------------------------------------------------------
local OWN = "media/ui/NeatEquipment/"
local CHB = "media/ui/CleanHotBar/"
local NUI = "media/ui/NeatUI/"
local ROC = "media/ui/NeatRocco/ICON/"

Y.NP = {
    header = NUI .. "DefaultPanel/MainTitle_BG.png",
    body   = NUI .. "DefaultPanel/MainPanelBG_FlatTop.png",
    round  = NUI .. "DefaultPanel/MainPanelBG_RoundTop.png",

    -- Our own pair, drawn by art/genera-guardaroba.js: a rounded box and its
    -- outline, same radius, corners fixed at 10 px whatever the size.
    card       = OWN .. "Card_BG.png",
    cardBorder = OWN .. "Card_Border.png",
}

-- Each entry is tried in order; the first texture that resolves wins.
Y.TEX = {
    slotBg     = { CHB .. "CleanHotbar_Slot_BG.png",         OWN .. "Slot_BG.png" },
    slotBorder = { CHB .. "CleanHotbar_Slot_ItemBorder.png", OWN .. "Slot_Border.png" },
    slotHover  = { CHB .. "CleanHotbar_Item_Hover.png",      OWN .. "Slot_Hover.png" },

    -- Round variants for the hands, cut to the same insets as the square pair.
    circleBg     = { OWN .. "Slot_Circle_BG.png" },
    circleBorder = { OWN .. "Slot_Circle_Border.png" },

    btnBg     = { NUI .. "Button/Background.png" },
    btnBorder = { NUI .. "Button/Boarder.png" },
    btnL      = { NUI .. "Button/Button_FULL_L.png" },
    btnM      = { NUI .. "Button/Button_FULL_M.png" },
    btnR      = { NUI .. "Button/Button_FULL_R.png" },

    resize = { NUI .. "Resize/ResizeIcon.png", OWN .. "ResizeIcon.png" },

    -- La persona in piedi: il tasto che apre il pannello e l'icona della sua
    -- intestazione. Era uno zaino, e si confondeva con le borse vere
    -- (art/genera-figura.js).
    figure     = { OWN .. "Icon_Figure.png" },

    bagClosed  = { OWN .. "Icon_Bag_Closed.png" },
    eyeShow    = { OWN .. "Icon_Eye_Show.png" },
    eyeHide    = { OWN .. "Icon_Eye_Hide.png" },
    dock       = { OWN .. "Icon_Dock.png" },
    undock     = { OWN .. "Icon_Undock.png" },
    close      = { NUI .. "ICON/Icon_False.png", OWN .. "Icon_Close.png" },
    confirm    = { NUI .. "ICON/Icon_True.png",  OWN .. "Icon_Confirm.png" },

    -- CleanUI's own shirt glyphs: plain for "put it all back on" - and for
    -- "wear" in the wardrobe - struck through for "take it all off".
    unequipAll = { "media/ui/CleanUI/ICON/Icon_HideEquipped.png", OWN .. "Icon_UnequipAll.png" },
    equipAll   = { "media/ui/CleanUI/ICON/Icon_ShowEquipped.png", OWN .. "Icon_EquipAll.png" },

    wardrobe   = { OWN .. "Icon_Wardrobe.png" },
    outfitLoad = { OWN .. "Icon_Outfit_Load.png" },
    remove     = { OWN .. "Icon_Remove.png" },
    rename     = { OWN .. "Icon_Rename.png" },
    -- art/genera-cintura.js, dal disegno in art/sorgenti/cintura.png.
    belt       = { OWN .. "Icon_Belt.png" },

    -- Rocco's own icons, so the family looks like one: his character
    -- window's protection and temperature tabs (NR_CharInfoPanel VANILLA_ICONS)
    -- on the outfit's own stats, his switch and his add, and the header's
    -- collapse arrow (NR_CollapseUtils). Our copies are byte-identical and
    -- stand in when Rocco is not installed.
    armor          = { ROC .. "Icon_Armor.png",       OWN .. "Icon_Armor.png" },
    temperature    = { ROC .. "Icon_Temperature.png", OWN .. "Icon_Temperature.png" },
    swap           = { ROC .. "Icon_Switch.png",      OWN .. "Icon_Switch.png" },
    add            = { ROC .. "Icon_Add.png",         OWN .. "Icon_Add.png" },
    collapseOpen   = { ROC .. "Icon_ArrowDown.png",   OWN .. "Icon_ArrowDown.png" },
    collapseClosed = { ROC .. "Icon_Arrow_R.png",     OWN .. "Icon_Arrow_R.png" },

    -- Filled palm for the main hand, outlined for the off hand. They are the
    -- slot's backdrop, not an icon: an empty hand still says which hand it is.
    handPrimary   = { OWN .. "Icon_Hand_Primary.png" },
    handSecondary = { OWN .. "Icon_Hand_Secondary.png" },
}

local _texCache = {}

--- First texture in TEX[key] that actually resolves, or nil. Cached: plain
--- getTexture is a global function and safe to memoise, unlike the NinePatch
--- lookup below.
function Y.tex(key)
    local list = Y.TEX[key]
    if not list then return nil end

    local cached = _texCache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    for _, path in ipairs(list) do
        local ok, t = pcall(getTexture, path)
        if ok and t and t.getWidth and t:getWidth() > 0 then
            _texCache[key] = t
            return t
        end
    end
    _texCache[key] = false
    return nil
end

local function ninePatch(path)
    if not NinePatchTexture then return nil end
    local ok, np = pcall(function() return NinePatchTexture.getSharedTexture(path) end)
    if ok then return np end
    return nil
end

-- ---------------------------------------------------------------------------
-- Panels
-- ---------------------------------------------------------------------------
function Y.drawNP(el, path, x, y, w, h, tint, alpha)
    if w <= 0 or h <= 0 then return end
    local np = ninePatch(path)
    if np then
        np:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, tint, tint, tint, alpha or 1.0)
    else
        -- Fallback only: a square rect under a 9-patch shows through the rounded
        -- corners, so it is never drawn alongside one (METODO/03 lesson 3).
        el:drawRect(x, y, w, h, alpha or 1.0, tint, tint, tint)
        el:drawRectBorder(x, y, w, h, 0.8, Y.separator.r, Y.separator.g, Y.separator.b)
    end
end

--- Rocco window anatomy: rounded-top header strip, flat-top body below it.
function Y.drawWindow(el, x, y, w, h, headerH)
    Y.drawNP(el, Y.NP.header, x, y, w, headerH, Y.TINT_HEADER, Y.PANEL_ALPHA)
    -- A window rolled up to its header (NEQ_Collapse) has no body to draw.
    if h > headerH then
        Y.drawNP(el, Y.NP.body, x, y + headerH, w, h - headerH, Y.TINT_BODY, Y.PANEL_ALPHA)
    end
    -- The black hairline under the header is what separates the two tints.
    el:drawRect(x, y + headerH - 1, w, 1, 1, 0, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Slots (Clean HotBar recipe)
-- ---------------------------------------------------------------------------
--- opts: hover, hasItem, equipped, highlight {r,g,b}, focus {r,g,b}, round
--- `round` swaps in the circular masks - same recipe, different silhouette, so
--- the hands read as hands and everything else as a slot.
function Y.drawSlot(el, x, y, w, h, opts)
    opts = opts or {}
    local bg = Y.tex(opts.round and "circleBg" or "slotBg")

    local b = opts.hover and Y.SLOT_BRIGHT_HOVER or Y.SLOT_BRIGHT
    local r, g, bl = b, b, b
    if opts.focus then r, g, bl = opts.focus.r, opts.focus.g, opts.focus.b end

    if bg then
        el:drawTextureScaled(bg, x, y, w, h, Y.SLOT_ALPHA, r, g, bl)
    else
        el:drawRect(x, y, w, h, Y.SLOT_ALPHA, r * 0.4, g * 0.4, bl * 0.4)
    end

    -- The soft inner glow only exists as a rounded square; on a circle it would
    -- bleed past the edge, so a round slot goes without it.
    if opts.hasItem and not opts.round then
        local glow = Y.tex("slotHover")
        if glow then
            el:drawTextureScaled(glow, x, y, w, h, 0.6, 0.98, 0.95, 0.85)
        end
    end

    if opts.highlight then
        local c = opts.highlight
        if bg then
            el:drawTextureScaled(bg, x, y, w, h, 0.45, c.r, c.g, c.b)
        else
            el:drawRect(x + 1, y + 1, w - 2, h - 2, 0.45, c.r, c.g, c.b)
        end
    end

    local border = Y.tex(opts.round and "circleBorder" or "slotBorder")
    if border then
        if opts.hasItem then
            if opts.equipped then
                local e = Y.equipped
                el:drawTextureScaled(border, x, y, w, h, 1.0, e.r, e.g, e.b)
            else
                el:drawTextureScaled(border, x, y, w, h, 0.75, 0.70, 0.70, 0.70)
            end
        elseif opts.hover then
            local a = Y.accent
            el:drawTextureScaled(border, x, y, w, h, 0.85, a.r, a.g, a.b)
        else
            el:drawTextureScaled(border, x, y, w, h, 0.45, 0.55, 0.55, 0.55)
        end
    end
end

--[[ Un riquadro stondato: il fondo e il bordo, due nine-patch nostre.

    E' la forma di tutto quello che nel guardaroba e' "una cosa": la scheda di
    salvataggio, ogni completo salvato, aperto o chiuso. I bordi sono regolari
    perche' gli angoli non si stirano mai: sono 10 pixel fissi in qualunque
    riquadro, e una riga bassa e un completo aperto hanno lo stesso raggio.

    Prima le righe erano il 3-slice dei tasti con i cappucci schiacciati: gli
    angoli venivano ellissi, e il raggio cambiava con l'altezza.

    `fill`   grigio del fondo (0..1), `alpha` la sua opacita'
    `line`   {r,g,b} del bordo, nil per non disegnarlo; `lineAlpha` la sua
]]
function Y.drawCard(el, x, y, w, h, fill, alpha, line, lineAlpha)
    if w <= 0 or h <= 0 then return end
    local ax, ay = el:getAbsoluteX() + x, el:getAbsoluteY() + y

    local bg = ninePatch(Y.NP.card)
    if bg then
        bg:render(ax, ay, w, h, fill, fill, fill + 0.01, alpha or 1)
    else
        el:drawRect(x, y, w, h, alpha or 1, fill, fill, fill + 0.01)
    end

    if not line then return end
    local border = ninePatch(Y.NP.cardBorder)
    if border then
        border:render(ax, ay, w, h, line.r, line.g, line.b, lineAlpha or 1)
    else
        el:drawRectBorder(x, y, w, h, lineAlpha or 1, line.r, line.g, line.b)
    end
end

--- Il grigio del bordo a riposo, e quello di un riquadro aperto: piu' chiaro,
--- come fa Neat Crafting con la voce espansa (NC_InputSwitch_Box).
Y.CARD_LINE      = { r = 0.30, g = 0.30, b = 0.32 }
Y.CARD_LINE_OPEN = { r = 0.58, g = 0.58, b = 0.60 }

--- Una riga di elenco: un riquadro scuro. Il passaggio del mouse schiarisce il
--- fondo e accende il bordo d'arancione; la voce aperta ha il bordo chiaro.
function Y.drawRow(el, x, y, w, h, hover, selected)
    local fill = hover and 0.19 or 0.13
    local line, lineAlpha = Y.CARD_LINE, 0.9
    if hover then
        line, lineAlpha = Y.accent, 0.85
    elseif selected then
        line, lineAlpha = Y.CARD_LINE_OPEN, 1
    end
    Y.drawCard(el, x, y, w, h, fill, 0.92, line, lineAlpha)
end

--- Il campo di scrittura: lo stesso riquadro, un gradino piu' scuro, cosi'
--- dentro una scheda sembra un incavo e non un oggetto appoggiato sopra. Una
--- linea d'accento sul fondo mentre ha la tastiera: e' l'unica cosa che la sta
--- ascoltando, e deve dirlo.
function Y.drawTextField(el, x, y, w, h, focused)
    local fill = focused and 0.06 or 0.08
    Y.drawCard(el, x, y, w, h, fill, 0.95, Y.CARD_LINE, focused and 0.6 or 0.9)

    if focused then
        local a = Y.accent
        local inset = 8
        el:drawRect(x + inset, y + h - 2, w - inset * 2, 1, 0.9, a.r, a.g, a.b)
    end
end

--- La casella di una spunta: un quadrato Neat. Piena di verde con la spunta
--- quando e' accesa - il verde e' "questo e' scelto" in tutta la famiglia -
--- scura e vuota quando e' spenta.
function Y.drawCheck(el, x, y, size, checked, hover, disabled)
    local bg, border = Y.tex("btnBg"), Y.tex("btnBorder")
    local r, g, b = 0.10, 0.10, 0.10
    if checked then
        local c = Y.selection
        r, g, b = c.r, c.g, c.b
    elseif hover then
        r, g, b = 0.22, 0.22, 0.22
    end
    local a = disabled and 0.45 or 0.95

    if bg then
        el:drawTextureScaled(bg, x, y, size, size, a, r, g, b)
    else
        el:drawRect(x, y, size, size, a, r, g, b)
    end

    local lr, lg, lb = 0.42, 0.42, 0.44
    if hover and not disabled then
        local c = Y.accent
        lr, lg, lb = c.r, c.g, c.b
    end
    if border then
        el:drawTextureScaled(border, x, y, size, size, a, lr, lg, lb)
    else
        el:drawRectBorder(x, y, size, size, a, lr, lg, lb)
    end

    if checked then
        local tick = Y.tex("confirm")
        if tick then
            local s = math.floor(size * 0.72)
            local o = math.floor((size - s) / 2)
            el:drawTextureScaled(tick, x + o, y + o, s, s, disabled and 0.5 or 1, 1, 1, 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Buttons / pills
-- ---------------------------------------------------------------------------
--[[ Tre fette, con i cappucci alla loro proporzione.

    Button_FULL_L e _R sono 64x64: il cappuccio e' largo quanto e' alto. E'
    come le disegna il framework (NeatTool.ThreePatch.drawHorizontal). Qui
    prima si passava una larghezza a mano - meta' altezza, o il 42% - e il
    cappuccio usciva schiacciato: l'angolo diventava un'ellisse, e ogni
    altezza aveva un raggio diverso.

    Su un tasto piu' stretto di due cappucci si stringono entrambi, com'e'
    nel framework, invece di sovrapporsi.
]]
local function draw3(el, x, y, w, h, a, r, g, b)
    local L, M, R = Y.tex("btnL"), Y.tex("btnM"), Y.tex("btnR")
    if not (L and R) then return false end

    local cap = math.floor(h * L:getWidth() / math.max(1, L:getHeight()))
    cap = math.max(1, math.min(cap, math.floor(w / 2)))

    el:drawTextureScaled(L, x, y, cap, h, a, r, g, b)
    local mid = w - cap * 2
    if mid > 0 and M then el:drawTextureScaled(M, x + cap, y, mid, h, a, r, g, b) end
    el:drawTextureScaled(R, x + w - cap, y, cap, h, a, r, g, b)
    return true
end

--- A wide Neat button: the framework's own three-slice art, with the same
--- state brightnesses NI_SquareButton uses, so a wide button and a square one
--- read as the same control at different lengths.
function Y.drawWideButton(el, x, y, w, h, state)
    local r, g, b, a = 0.20, 0.20, 0.20, 0.85
    if state == "pressed" then r, g, b = 0.10, 0.10, 0.10
    elseif state == "hover" then r, g, b = 0.30, 0.30, 0.30
    elseif state == "active" then
        local c = Y.accent
        r, g, b = c.r, c.g, c.b
    elseif state == "disabled" then
        r, g, b, a = 0.16, 0.16, 0.16, 0.5
    end

    if not draw3(el, x, y, w, h, a, r, g, b) then
        el:drawRect(x, y, w, h, a, r, g, b)
        el:drawRectBorder(x, y, w, h, 1, Y.separator.r, Y.separator.g, Y.separator.b)
    end
end

--- The rounded dark pill used for slot-name labels. Same art as a Neat button
--- at rest, so a label never looks like a different UI kit.
function Y.drawPill(el, x, y, w, h)
    if not draw3(el, x, y, w, h, 0.92, 0.10, 0.10, 0.11) then
        el:drawRect(x, y, w, h, 0.92, 0.10, 0.10, 0.11)
        el:drawRectBorder(x, y, w, h, 0.8, Y.separator.r, Y.separator.g, Y.separator.b)
    end
end

--- The hover label for a button, in the same rounded pill the slots use.
---
--- Buttons get this instead of ISButton:setTooltip because the vanilla tooltip
--- is a different UI kit - square, its own font, its own colours - and having
--- half the panel explain itself in Neat and the other half in vanilla is the
--- kind of seam this mod exists to remove. Drawn by the panel rather than by
--- the button, in its render pass, so it lands on top of everything.
---
--- `below` puts it under the anchor instead of over it, which is what a button
--- in a title bar needs: there is nothing above a title bar.
function Y.drawButtonTip(el, text, centreX, anchorY, below, minX, maxX)
    if not text or text == "" then return end

    local font = UIFont.Small
    local tm = getTextManager()
    local tw = tm:MeasureStringX(font, text)
    local th = tm:getFontHeight(font)
    local padX = math.max(5, math.floor(th * 0.5))
    local w = tw + padX * 2
    local h = th + math.max(3, math.floor(th * 0.3))

    local x = centreX - math.floor(w / 2)
    if maxX and x + w > maxX then x = maxX - w end
    if minX and x < minX then x = minX end
    local y = below and anchorY or (anchorY - h)

    Y.drawPill(el, x, y, w, h)
    el:drawText(text, x + padX, y + math.floor((h - th) / 2), 1, 1, 1, 1, font)
end

--- How tall drawSlotLabel's pill is. The layout reserves this much headroom
--- above the top row of slots, so a hover label never spills into the header.
function Y.slotLabelHeight(font)
    local th = getTextManager():getFontHeight(font or UIFont.Small)
    return th + math.max(2, math.floor(th * 0.25))
end

--[[ La scala dei caratteri.

    Serviva perche' **il carattere del gioco non si rimpicciolisce insieme al
    pannello**. Gli slot sono scalabili, `UIFont.Small` no: la sua altezza la
    decide l'impostazione del giocatore, e su uno slot piccolo una scritta alta
    quanto quel carattere occupa mezzo slot.

    Stessa costruzione che fa NeatXPStyle in XP Drop: si misurano i caratteri
    disponibili una volta sola e si tiene il piu' grande che ci sta nello
    spazio dato. L'altezza vera si chiede al motore invece di indovinarla,
    perche' cambia con le impostazioni.
]]
local _ladder = nil
local function buildLadder()
    local tm = getTextManager()
    local seen, out = {}, {}
    for _, name in ipairs({ "Small", "NewSmall", "Medium", "NewMedium", "Large", "NewLarge" }) do
        local ok, font = pcall(function() return UIFont[name] end)
        if ok and font ~= nil then
            local ok2, h = pcall(function() return tm:getFontHeight(font) end)
            if ok2 and type(h) == "number" and h > 0 and not seen[h] then
                seen[h] = true
                out[#out + 1] = { font = font, h = h }
            end
        end
    end
    if #out == 0 then out = { { font = UIFont.Small, h = tm:getFontHeight(UIFont.Small) } } end
    table.sort(out, function(a, b) return a.h < b.h end)
    return out
end

--- Il carattere piu' grande che sta in `maxH`, e la sua altezza. Mai piu'
--- piccolo del piu' piccolo che il gioco ha: sotto quello non si scende.
function Y.pickFont(maxH)
    if _ladder == nil then _ladder = buildLadder() end
    local chosen = _ladder[1]
    for _, e in ipairs(_ladder) do
        if e.h <= maxH then chosen = e else break end
    end
    return chosen.font, chosen.h
end

--- A centred label sitting above an element - the hover name on a slot.
--- minX/maxX are optional bounds in the element's own coordinate space; a slot
--- near the panel edge passes them so a long name slides inwards instead of
--- being clipped.
function Y.drawSlotLabel(el, text, centreX, bottomY, font, minX, maxX)
    if not text or text == "" then return end
    font = font or UIFont.Small

    local tm = getTextManager()
    local tw = tm:MeasureStringX(font, text)
    local th = tm:getFontHeight(font)
    local padX = math.max(4, math.floor(th * 0.45))
    local w = tw + padX * 2
    local h = th + math.max(2, math.floor(th * 0.25))

    local x = centreX - math.floor(w / 2)
    if maxX and x + w > maxX then x = maxX - w end
    if minX and x < minX then x = minX end
    local y = bottomY - h

    Y.drawPill(el, x, y, w, h)
    el:drawText(text, x + padX, y + math.floor((h - th) / 2), 1, 1, 1, 1, font)
end

--- A Neat square icon button. Uses the framework's own NI_SquareButton when it
--- is loaded, so the header buttons are pixel-identical to Rocco's; falls back
--- to an ISButton painted with the same art otherwise.
--- activeColor (optional) tints the button: orange for an engaged toggle, red
--- for close.
function Y.newSquareButton(x, y, size, icon, target, onclick, activeColor)
    local SquareButton = rawget(_G, "NI_SquareButton")
    if SquareButton then
        local b = SquareButton:new(x, y, size, icon, target, onclick)
        b:initialise()
        if activeColor then
            b:setActive(true)
            b:setActiveColor(activeColor.r, activeColor.g, activeColor.b)
        else
            b:setActive(false)
        end
        return b
    end

    local b = ISButton:new(x, y, size, size, "", target, onclick)
    b:initialise()
    b:instantiate()
    b:setDisplayBackground(false)
    -- The button art carries its own rounded border; the vanilla square one
    -- would poke out of the corners.
    b.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    b.neqIcon = icon
    b.neqActiveColor = activeColor
    b.render = function(btn)
        local a = btn.neqActiveColor
        local r, g, bl = 0.20, 0.20, 0.20
        if a then
            r, g, bl = a.r, a.g, a.b
            if btn.pressed then r, g, bl = r * 0.8, g * 0.8, bl * 0.8
            elseif btn:isMouseOver() then
                r, g, bl = math.min(r * 1.2, 1), math.min(g * 1.2, 1), math.min(bl * 1.2, 1)
            end
        elseif btn.pressed then r, g, bl = 0.10, 0.10, 0.10
        elseif btn:isMouseOver() then r, g, bl = 0.30, 0.30, 0.30 end

        local bg, border = Y.tex("btnBg"), Y.tex("btnBorder")
        if bg then
            btn:drawTextureScaled(bg, 0, 0, btn.width, btn.height, 0.8, r, g, bl)
        else
            btn:drawRect(0, 0, btn.width, btn.height, 0.8, r, g, bl)
        end
        if border then
            btn:drawTextureScaled(border, 0, 0, btn.width, btn.height, 1, 0.4, 0.4, 0.4)
        end
        if btn.neqIcon then
            local s = math.floor(math.min(btn.width, btn.height) * 0.8)
            local o = math.floor((btn.width - s) / 2)
            btn:drawTextureScaled(btn.neqIcon, o, o, s, s, 1, 0.9, 0.9, 0.9)
        end
    end
    return b
end

--- Retints an existing square button, whichever of the two flavours it is.
function Y.setButtonActive(button, activeColor)
    if not button then return end
    if button.setActive then
        button:setActive(activeColor ~= nil)
        if activeColor then button:setActiveColor(activeColor.r, activeColor.g, activeColor.b) end
    end
    button.neqActiveColor = activeColor
end

function Y.setButtonIcon(button, icon)
    if not button then return end
    if button.setIcon then button:setIcon(icon) end
    button.neqIcon = icon
end

--- The "+N" chip on a slot holding more layers than the strip beside it can
--- show. Bottom-right corner of the slot, over the item icon, on the accent
--- colour so it reads as "there is more here" rather than as damage.
--- Dove finisce la pastiglia del conteggio, in un posto solo.
---
--- La usano il disegno e il riconoscimento del clic: erano due conti separati
--- e uno dei due non c'era proprio, cosi' la pastiglia si vedeva ma non si
--- poteva toccare.
--- La misura parte dallo slot, non dal carattere. E' la correzione: prima
--- `w` e `h` uscivano da `UIFont.Small`, che non scala, quindi su uno slot da
--- 24 pixel la pastiglia era alta 15 e larga 20 - due terzi di slot. Non
--- sembrava una pastiglia sopra il capo: sembrava un secondo slot infilato
--- dentro il primo, che e' precisamente com'e' stata segnalata.
---
--- Adesso il tetto e' una frazione dello slot, il carattere e' il piu' grande
--- che ci sta dentro, e c'e' un margine dal bordo: cosi' il quadrato grande
--- resta un quadrato chiuso con una pastiglia appoggiata in un angolo.
---
--- Restituisce anche carattere e margine orizzontale, cosi' il disegno non
--- rifa' il conto: era gia' successo che le due misure divergessero e la
--- pastiglia si vedesse dove non si poteva cliccare.
--[[ Il conteggio degli strati nascosti, e perche' non e' piu' una pastiglia.

    Il difetto segnalato: con quattro capi addosso i riquadri piccoli sembravano
    entrare dentro quello grande. Misurato, e' vero e ha una causa sola:

        slot 34 px (scala 1.0)   pastiglia 18x15   -> meta' slot
        slot 24 px (scala 0.7)   pastiglia 18x15   -> tre quarti di slot
        slot 54 px (scala 1.6)   pastiglia 18x15   -> un terzo

    La pastiglia **non cambiava mai misura**, perche' la decideva `UIFont.Small`,
    e quel carattere non scala con il pannello: la sua altezza la sceglie il
    giocatore nelle impostazioni del gioco. Su uno slot piccolo un blocco
    arancione pieno grande due terzi dello slot non si legge come "ce n'e'
    altri": si legge come un secondo slot infilato dentro il primo.

    Rimpicciolirlo non si puo': sotto il carattere piu' piccolo che il gioco ha
    non si scende, e stringere il riquadro sotto la scritta la taglia soltanto.
    Quindi si toglie il riquadro. Il numero resta - e' l'informazione - ma
    scritto in arancione con il contorno scuro, appoggiato nell'angolo. Occupa
    lo stesso spazio e non ha piu' una forma che possa essere scambiata per uno
    slot, che era il problema vero.

    Sotto una certa misura sparisce anche il "+": una cifra sola sta ovunque.

    Il rettangolo restituito resta il bersaglio del clic - apre il ventaglio -
    ed e' l'unico posto dove quel conto esiste, disegno e clic compresi.
]]
function Y.countBadgeRect(x, y, size, count)
    local inset = math.max(1, math.floor(size * 0.06))
    local font, fh = Y.pickFont(math.max(6, math.floor(size * 0.34)))

    -- Con il "+" davanti la scritta e' quasi il doppio. Su uno slot stretto si
    -- tiene la sola cifra: dice la stessa cosa nella meta' dello spazio.
    local text = tostring(count)
    local tm = getTextManager()
    local withPlus = "+" .. text
    if tm:MeasureStringX(font, withPlus) <= size * 0.55 then text = withPlus end

    local w = tm:MeasureStringX(font, text)
    local h = fh

    return x + size - w - inset, y + size - h - inset, w, h, font, text
end

function Y.drawCountBadge(el, x, y, size, count)
    local bx, by, _, _, font, text = Y.countBadgeRect(x, y, size, count)

    -- Il contorno al posto del fondo: quattro copie scure attorno e una
    -- arancione sopra. Si legge anche su un'icona chiara e non disegna nessun
    -- riquadro.
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        el:drawText(text, bx + d[1], by + d[2], 0.04, 0.04, 0.04, 0.95, font)
    end

    local a = Y.accent
    el:drawText(text, bx, by, a.r, a.g, a.b, 1, font)
end

-- ---------------------------------------------------------------------------
-- Separators / section headers
-- ---------------------------------------------------------------------------
function Y.drawSeparator(el, x, y, w)
    local s = Y.separator
    el:drawRect(x, y, w, 1, 0.6, s.r, s.g, s.b)
end

--- Section header: label centred in the row with a hairline running out to each
--- side. Centred rather than left-aligned because the grid underneath is
--- centred too, and a left-hung title over a centred row reads as a mistake.
function Y.drawSectionHeader(el, text, x, y, w, font)
    font = font or UIFont.Small
    local tm = getTextManager()
    local th = tm:getFontHeight(font)
    local tw = tm:MeasureStringX(font, text)
    local d = Y.dim

    local textX = x + math.floor((w - tw) / 2)
    el:drawText(text, textX, y, d.r, d.g, d.b, 1, font)

    local lineY = y + math.floor(th / 2)
    local gap = 8
    local leftW = textX - gap - x
    if leftW > 4 then Y.drawSeparator(el, x, lineY, leftW) end

    local rightX = textX + tw + gap
    local rightW = x + w - rightX
    if rightW > 4 then Y.drawSeparator(el, rightX, lineY, rightW) end

    return th
end

-- ---------------------------------------------------------------------------
-- Resize grip (framework ResizeIcon art, same maths as NeatUI XP Drop)
-- ---------------------------------------------------------------------------
--- Il trascinatore d'angolo: la ricetta di Neat Rocco (NR_ResizeWidget), e
--- basta. L'aspetto si conserva, la scatola non si sfora, e l'alfa e' la loro.
---
--- Niente piu' ingrandimento 32/22: serviva a incollare la freccia all'angolo e
--- la faceva debordare, che e' il motivo per cui il nostro sembrava piu' grosso
--- e meno integrato del loro.
function Y.drawResizeGrip(el, x, y, size, hover)
    local t = Y.tex("resize")
    local a = hover and 0.8 or 0.6
    if t then
        el:drawTextureScaledAspect(t, x, y, size, size, a, 1, 1, 1)
        return
    end
    local th = math.max(1, math.floor(size * 0.12))
    for i = 1, 3 do
        local len = math.floor(size * (0.30 + 0.22 * (i - 1)))
        local oy = y + size - i * math.floor(size * 0.28)
        el:drawRect(x + size - len, oy, len, th, a, 0.92, 0.92, 0.92)
    end
end

-- ---------------------------------------------------------------------------
-- Item icons
-- ---------------------------------------------------------------------------
--- Draws tex centred in the box, scaled down to fit, aspect preserved: item
--- icons are not all square, and a plain stretch makes the tall ones look wrong.
--[[ L'icona di un oggetto, disegnata dal motore.

    DrawItemIcon e' la strada che percorrono la lista dell'inventario e la
    hotbar (ISInventoryItem.renderItemIcon -> ISUIElement:drawItemIcon). Sa cose
    che da Lua non si vedono: come l'icona e' impacchettata nell'atlante, le
    maschere dei liquidi, quella del colore, la tinta dell'oggetto.

    Noi invece calcolavamo le proporzioni a mano da getWidthOrig/getHeightOrig e
    poi disegnavamo la texture per conto nostro. Se quei due numeri descrivono
    la tela originale e non il ritaglio che finisce a schermo, il rapporto e'
    sbagliato e l'icona esce stirata - che e' la segnalazione arrivata.

    Il ripiego resta la vecchia strada, per quando l'oggetto non c'e' e si ha
    in mano solo una texture (le icone nostre, disegnate da noi e gia' quadre).
]]
function Y.drawItemIcon(el, item, x, y, w, h, alpha)
    if not item or w <= 0 or h <= 0 then return end

    local ok = pcall(function()
        el:drawItemIcon(item, x, y, alpha or 1, w, h)
    end)
    if ok then return end

    local r, g, b = Y.getItemColor(item)
    Y.drawTextureFitted(el, item:getTex(), x, y, w, h, alpha, r, g, b)
end

function Y.drawTextureFitted(el, tex, x, y, maxW, maxH, alpha, r, g, b)
    if not tex or maxW <= 0 or maxH <= 0 then return end

    local tw = tex.getWidthOrig and tex:getWidthOrig() or tex:getWidth()
    local th = tex.getHeightOrig and tex:getHeightOrig() or tex:getHeight()
    if not tw or not th or tw <= 0 or th <= 0 then return end

    local scale = math.min(maxW / tw, maxH / th)
    local dw = math.max(1, math.floor(tw * scale + 0.5))
    local dh = math.max(1, math.floor(th * scale + 0.5))
    local dx = x + math.floor((maxW - dw) / 2 + 0.5)
    local dy = y + math.floor((maxH - dh) / 2 + 0.5)

    el:drawTextureScaled(tex, dx, dy, dw, dh, alpha or 1, r or 1, g or 1, b or 1)
end

--- An item's tint, floored so a near-black dyed item is still visible on a dark
--- slot.
function Y.getItemColor(item)
    if not item then return 1, 1, 1 end
    if not item:allowRandomTint() then
        return item:getR(), item:getG(), item:getB()
    end

    local info = item:getColorInfo()
    local r, g, b = info:getR(), info:getG(), info:getB()
    local limit = 0.2
    while r < limit and g < limit and b < limit do
        r = r + limit / 4
        g = g + limit / 4
        b = b + limit / 4
    end
    return r, g, b
end

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------
--- getText hands back the raw key when a translation is missing: never show it.
function Y.tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

function Y.fitText(text, maxW, font)
    text = tostring(text or "")
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= maxW then return text end

    local out = text
    while #out > 1 and tm:MeasureStringX(font, out .. "..") > maxW do
        out = out:sub(1, #out - 1)
    end
    return out .. ".."
end

return Y

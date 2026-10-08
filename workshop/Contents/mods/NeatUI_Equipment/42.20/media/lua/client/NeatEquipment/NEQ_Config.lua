--[[ ============================================================================
    NEQ_Config - persistent UI state for NeatUI Equipment.

    One flat ini in Zomboid/Lua, same shape as NeatUI XP Drop's NeatXPDrops.ini:
    a handful of key=value lines, read once at startup and rewritten whenever the
    panel is docked, moved, resized or toggled.

    What lives here is UI state the player changes by *using* the panel (docked,
    closed, position, scale). What lives in Mod Options instead is preference
    (hide the hotbar section, lock the size); NEQ_State owns both and only the
    ones listed in DEFAULTS below are persisted here.
============================================================================ ]]--

if isServer() then return end

NEQ_Config = NEQ_Config or {}
local C = NEQ_Config

C.FILE = "NeatUIEquipment.ini"

-- key -> default. The type of the default decides how the value is parsed back.
-- "hide equipped items" is deliberately absent: it is a Mod Options tickbox,
-- and the header's eye button writes through to it, so it has one home.
C.DEFAULTS = {
    docked = true,
    closed = false,
    -- 0 = mai scelta a mano: la prima misura la decide lo schermo. Vedi
    -- C.startingScale.
    scale  = 0,
    pos_x  = -1,      -- -1 = never placed by hand yet
    pos_y  = -1,

    -- The wardrobe is its own window with its own grip, so it keeps its own
    -- size. Its position is not saved: it opens beside the panel, which is
    -- where it is wanted and where the panel can guarantee it is on screen.
    wardrobe_scale = 1.0,

    -- Le due spunte della scheda di salvataggio: si ricordano com'erano
    -- l'ultima volta, perche' chi salva senza borse di solito lo fa sempre.
    wardrobe_save_bags   = true,
    wardrobe_save_hotbar = true,
}

local _cache = nil

local function parse(value, default)
    if type(default) == "boolean" then
        return value == "true"
    elseif type(default) == "number" then
        return tonumber(value) or default
    end
    return value
end

local function fresh()
    local t = {}
    for k, v in pairs(C.DEFAULTS) do t[k] = v end
    return t
end

--- Reads the ini once; later calls hand back the same table.
function C.get()
    if _cache then return _cache end

    local cfg = fresh()
    local file = getFileReader(C.FILE, false)
    if file then
        local line = file:readLine()
        while line ~= nil do
            local parts = string.split(line, "=")
            if parts and #parts == 2 then
                local key = parts[1]
                if C.DEFAULTS[key] ~= nil then
                    cfg[key] = parse(parts[2], C.DEFAULTS[key])
                end
            end
            line = file:readLine()
        end
        file:close()
    end

    _cache = cfg
    return cfg
end

--- Writes the whole table back. Cheap enough to call on every drag release.
function C.save()
    local cfg = C.get()
    local file = getFileWriter(C.FILE, true, false)
    if not file then return end

    for key, default in pairs(C.DEFAULTS) do
        local value = cfg[key]
        if value == nil then value = default end
        if type(default) == "number" then
            file:write(key .. "=" .. string.format("%.4f", value) .. "\n")
        else
            file:write(key .. "=" .. tostring(value) .. "\n")
        end
    end
    file:close()
end

--- La scala da cui partire: quella salvata, o - la prima volta - quella che
--- corrisponde allo schermo.
---
--- 244 px a scala 1 stanno bene su 1080p e sono un francobollo su 1440p o 4K,
--- dove tutto il resto dell'interfaccia e' grande uguale ma il giocatore siede
--- piu' lontano dai pixel. Chi apriva la mod su uno schermo grande trovava un
--- pannello minuscolo da allargare a mano ogni partita nuova. Con una misura
--- gia' salvata qui non si tocca niente: quella e' una scelta, e le scelte
--- restano.
local _derivedScale = nil

function C.startingScale()
    local cfg = C.get()
    if (cfg.scale or 0) > 0 then return cfg.scale end

    -- Calcolata una volta: il pannello agganciato la richiede a ogni
    -- fotogramma, e la risoluzione non cambia fra un fotogramma e l'altro.
    if _derivedScale then return _derivedScale end

    local ok, height = pcall(function() return getCore():getScreenHeight() end)
    if not ok or type(height) ~= "number" or height <= 0 then return 1.0 end

    -- Proporzionale all'altezza, con un tetto: su 4K un pannello due volte e
    -- mezzo il normale sarebbe piu' grande dell'inventario a cui si aggancia.
    local scale = height / 1080
    _derivedScale = math.max(1.0, math.min(1.8, math.floor(scale * 20 + 0.5) / 20))
    return _derivedScale
end

function C.set(key, value)
    if C.DEFAULTS[key] == nil then return end
    local cfg = C.get()
    if cfg[key] == value then return end
    cfg[key] = value
    C.save()
end

return C

--[[ ============================================================================
    NEQ_Outfit - what an outfit is, and where it is kept.

    An outfit is plain data: strings and numbers, never InventoryItem
    references. That is what lets the same table go to the UI, into the
    character's modData, and back out next session with no conversion step -
    and it is why a saved outfit survives the item it was saved from being
    dropped, burnt or eaten by a zombie.

        outfit = {
            name   = "Work clothes",
            saved  = <world age in hours>,
            worn   = { [bodyLocationKey] = descriptor, ... },
            hotbar = { [slotType]        = descriptor, ... },
        }

        descriptor = { type = "Base.Tshirt_White", tint = {r,g,b}, texture = 3 }

    What is deliberately NOT in an outfit: whatever is in the character's
    hands. Holding a hammer is not part of getting dressed, and restoring an
    outfit should not put a weapon back in your fist.

    Colour and pattern are recorded so that "the blue shirt" can be told apart
    from "the white shirt" when the wardrobe goes looking. They are never
    applied to an item: dyeing a garment is a permanent change, and an outfit
    remembering blue must not repaint the white shirt you actually own.
============================================================================ ]]--

if isServer() then return end

NEQ_Outfit = NEQ_Outfit or {}
local O = NEQ_Outfit

O.MODDATA_KEY = "NeatUIEquipment"
O.MAX_OUTFITS = 24

-- ---------------------------------------------------------------------------
-- Body locations as strings
-- ---------------------------------------------------------------------------
local keyToLocation = {}

--- ItemBodyLocation -> our string key.
function O.locationKey(location)
    if location == nil then return nil end
    if type(location) == "string" then
        return location ~= "" and location or nil
    end

    local ok, name = pcall(function() return location:getTranslationName() end)
    if ok and type(name) == "string" and name ~= "" then return name end

    -- tostring() prints the id on every build we have seen, but only trust it
    -- if it round-trips: a key the engine will not take back would be saved
    -- into an outfit and then quietly fail to restore.
    local text = tostring(location)
    if text and text ~= "" and text ~= "null" and O.location(text) then return text end
    return nil
end

--- Our string key -> ItemBodyLocation.
function O.location(key)
    if type(key) ~= "string" or key == "" then return nil end

    local cached = keyToLocation[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local ok, location = pcall(function()
        return ItemBodyLocation.get(ResourceLocation.of(key))
    end)
    keyToLocation[key] = (ok and location) or false
    return (ok and location) or nil
end

--- Where an item wants to go. Clothing answers with getBodyLocation, worn
--- containers (backpacks) only with canBeEquipped.
function O.itemLocationKey(item)
    if not item then return nil end

    local ok, location = pcall(function() return item:getBodyLocation() end)
    if ok then
        local key = O.locationKey(location)
        if key then return key end
    end

    local okEquip, equipLocation = pcall(function() return item:canBeEquipped() end)
    if okEquip then
        local key = O.locationKey(equipLocation)
        if key then return key end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Descriptors
-- ---------------------------------------------------------------------------
local function readTint(item)
    local ok, r, g, b = pcall(function()
        local clothing = item:getClothingItem()
        if not clothing or not clothing:getAllowRandomTint() then return nil end
        local tint = item:getVisual():getTint(clothing)
        if not tint then return nil end
        return tint:getRedFloat(), tint:getGreenFloat(), tint:getBlueFloat()
    end)
    if not ok or type(r) ~= "number" then return nil end
    -- An untinted garment reports pure white; storing that is noise.
    if r >= 0.999 and g >= 0.999 and b >= 0.999 then return nil end
    return { r = r, g = g, b = b }
end

--- Modelled garments carry a texture choice, flat ones a base texture. Both
--- are integers, read through different accessors.
local function readTexture(item)
    local ok, choice = pcall(function()
        local clothing = item:getClothingItem()
        if not clothing then return nil end
        if clothing:hasModel() then return item:getVisual():getTextureChoice() end
        return item:getVisual():getBaseTexture()
    end)
    if ok and type(choice) == "number" and choice >= 0 then return choice end
    return nil
end

--- L'identita' del singolo oggetto, non del suo aspetto.
---
--- Serve **solo come indizio**: un completo resta una descrizione, non un
--- collegamento, e deve continuare a funzionare quando il capo salvato e' stato
--- distrutto e ne indossi un altro uguale. Ma quando quell'oggetto preciso c'e'
--- ancora, e' lui che si vuole indietro.
---
--- E' il modo in cui vanilla stessa ritrova un oggetto attraverso il
--- salvataggio: `getItemById` sull'id restituito da qui.
local function readId(item)
    local ok, id = pcall(function() return item:getID() end)
    if ok and type(id) == "number" then return id end
    return nil
end

---@return table|nil { type, tint, texture, id }
function O.describe(item)
    if not item then return nil end

    local ok, fullType = pcall(function() return item:getFullType() end)
    if not ok or type(fullType) ~= "string" or fullType == "" then return nil end

    return {
        type    = fullType,
        tint    = readTint(item),
        texture = readTexture(item),
        id      = readId(item),
    }
end

--- Quanta roba c'e' dentro una borsa. Zero per tutto il resto.
---
--- Non entra nella descrizione - il contenuto cambia di continuo e un completo
--- non se ne occupa - ma serve a scegliere fra due borse identiche.
---@return number
function O.bagCount(item)
    if not O.isBag(item) then return 0 end
    local ok, n = pcall(function()
        local inv = item:getInventory()
        return inv and inv:getItems():size() or 0
    end)
    return (ok and type(n) == "number") and n or 0
end

--- True when two descriptors are the same garment in the same colour and
--- pattern. Used to rank candidates, never to modify anything.
function O.sameLook(a, b)
    if not a or not b then return false end
    if a.type ~= b.type then return false end
    if (a.texture or -1) ~= (b.texture or -1) then return false end
    if a.tint == nil and b.tint == nil then return true end
    if a.tint == nil or b.tint == nil then return false end
    return math.abs(a.tint.r - b.tint.r) < 0.02
        and math.abs(a.tint.g - b.tint.g) < 0.02
        and math.abs(a.tint.b - b.tint.b) < 0.02
end

--- Readable name for a descriptor with no live item to hand.
function O.describedName(descriptor)
    if not descriptor or not descriptor.type then return "" end

    local ok, script = pcall(function()
        return ScriptManager.instance:getItem(descriptor.type)
    end)
    if ok and script then
        local okName, name = pcall(function() return script:getDisplayName() end)
        if okName and name and name ~= "" then return name end
    end

    -- "Base.Tshirt_White" reads better as "Tshirt_White" than as nothing.
    return string.match(descriptor.type, "%.(.+)$") or descriptor.type
end

-- ---------------------------------------------------------------------------
-- Reading the character
-- ---------------------------------------------------------------------------
--- Una borsa indossata: zaino, borsone, marsupio. Vanno trattate a parte da
--- tutto il resto del vestiario perche' spostarle vuol dire spostare anche il
--- loro contenuto, e una borsa piena e' pesante abbastanza da far fallire
--- l'azione. `IsInventoryContainer` e' il test che usa vanilla.
function O.isBag(item)
    if not item then return false end
    local ok, container = pcall(function() return item:IsInventoryContainer() end)
    return ok and container == true
end

--[[ Body locations that are never part of an outfit.

    Bandages, wounds and zombie damage are worn items too: the engine puts a
    hidden clothing item in base:bandage, base:wound or base:zeddmg to draw them
    (BodyLocations.lua:5-6, 118; clothing.txt, `hidden = true`). The panel has
    always left them out of its count, because they are not clothes. Saving an
    outfit did not, so a bandage went into the outfit, and taking the bandage
    off later made the wardrobe report it missing.

    The keys are read from the engine's own constants rather than spelt out,
    because what locationKey returns for them depends on the build.
]]
local nonOutfitKeys = nil

local function nonOutfitLocationKeys()
    if nonOutfitKeys then return nonOutfitKeys end
    nonOutfitKeys = {}
    for _, name in ipairs({ "BANDAGE", "WOUND", "ZED_DMG" }) do
        local ok, location = pcall(function() return ItemBodyLocation[name] end)
        local key = ok and location and O.locationKey(location)
        if key then nonOutfitKeys[key] = true end
    end
    return nonOutfitKeys
end

--- Can this body location belong to an outfit? False for bandages, wounds and
--- zombie damage. Old outfits that saved one of those are read through this
--- too, so they stop asking for a bandage.
function O.isOutfitLocation(key)
    if type(key) ~= "string" or key == "" then return false end
    return not nonOutfitLocationKeys()[key]
end

--- Can this worn item belong to an outfit? Hidden items never can: the engine
--- hides them precisely because they are not something the player put on.
function O.isOutfitItem(item)
    if not item then return false end
    local ok, hidden = pcall(function() return item:isHidden() end)
    return not (ok and hidden == true)
end

--[[ What belongs to the hotbar.

    The "leave the hotbar out" option takes out everything attached to the
    hotbar and whatever provides the slots: belts, holsters, bandoliers. A worn
    item provides slots when getAttachmentsProvided answers with a list - the
    same test ISHotbar:refresh uses (ISHotbar.lua:472).

    A saved outfit only has the item's type, not the item, and the script
    object has no reader for that list. So for a descriptor the body location
    decides instead: base:belt and base:beltextra are where belts and holsters
    go (BodyLocations.lua:7-8).
]]
local hotbarKeys = nil

local function hotbarLocationKeys()
    if hotbarKeys then return hotbarKeys end
    hotbarKeys = {}
    for _, name in ipairs({ "BELT", "BELT_EXTRA" }) do
        local ok, location = pcall(function() return ItemBodyLocation[name] end)
        local key = ok and location and O.locationKey(location)
        if key then hotbarKeys[key] = true end
    end
    return hotbarKeys
end

function O.isHotbarLocation(key)
    return type(key) == "string" and hotbarLocationKeys()[key] == true
end

function O.providesAttachments(item)
    if not item then return false end
    local ok, list = pcall(function() return item:getAttachmentsProvided() end)
    if not ok or not list then return false end
    local okSize, size = pcall(function() return list:size() end)
    return okSize and type(size) == "number" and size > 0
end

--- A worn item that exists for the hotbar's sake.
function O.isHotbarBound(item, key)
    return O.providesAttachments(item) or O.isHotbarLocation(key)
end

--- Everything worn, as descriptors keyed by body location.
---
--- `excludeBags` lascia fuori gli zaini: un completo salvato cosi' non ha
--- niente da dire sulle borse, e rimetterlo non le tocca ne' in un senso ne'
--- nell'altro. `excludeHotbar` does the same for belts and holsters.
function O.captureWorn(character, excludeBags, excludeHotbar)
    local worn = {}
    if not character then return worn end

    local ok, items = pcall(function() return character:getWornItems() end)
    if not ok or not items then return worn end

    for i = 0, items:size() - 1 do
        local entry = items:get(i)
        local item = entry and entry:getItem()
        if item and O.isOutfitItem(item) and not (excludeBags and O.isBag(item)) then
            local key = O.locationKey(entry:getLocation()) or O.itemLocationKey(item)
            local skip = excludeHotbar and O.isHotbarBound(item, key)
            local descriptor = key and not skip and O.isOutfitLocation(key) and O.describe(item)
            if descriptor then worn[key] = descriptor end
        end
    end

    return worn
end

--- Everything attached to the hotbar, keyed by the attachment slot's type
--- rather than its index: the index moves when a belt is added or removed,
--- the type does not.
function O.captureHotbar(playerNum)
    local attached = {}

    local hotbar = getPlayerHotbar(playerNum)
    if not hotbar then return attached end

    for index, slot in ipairs(hotbar.availableSlot) do
        local item = hotbar.attachedItems[index]
        if item and slot.slotType then
            local descriptor = O.describe(item)
            if descriptor then attached[slot.slotType] = descriptor end
        end
    end

    return attached
end

--- The character's current outfit. Hands are excluded on purpose.
---
--- The two exclusions are remembered in the outfit, not only applied: an
--- outfit saved without the hotbar must also leave the hotbar alone when it is
--- put back on, or the belt it never mentioned would come off as "surplus".
function O.capture(character, playerNum, name, excludeBags, excludeHotbar)
    return {
        name = name,
        noBags = excludeBags == true or nil,
        noHotbar = excludeHotbar == true or nil,
        worn = O.captureWorn(character, excludeBags, excludeHotbar),
        hotbar = excludeHotbar and {} or O.captureHotbar(playerNum),
    }
end

--- Does wearing this outfit leave the hotbar alone? Either because it was
--- saved that way, or because Mod Options leave the hotbar out of every outfit.
function O.skipsHotbar(outfit, everywhere)
    return everywhere == true or (outfit ~= nil and outfit.noHotbar == true)
end

--- How many pieces an outfit puts on. With `excludeHotbar` the hotbar and the
--- belt slots of an older outfit are not counted, because they will not be
--- touched.
function O.count(outfit, excludeHotbar)
    local total = 0
    if outfit then
        for key in pairs(outfit.worn or {}) do
            if O.isOutfitLocation(key) and not (excludeHotbar and O.isHotbarLocation(key)) then
                total = total + 1
            end
        end
        if not excludeHotbar then
            for _ in pairs(outfit.hotbar or {}) do total = total + 1 end
        end
    end
    return total
end

function O.isEmpty(outfit)
    return O.count(outfit) == 0
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------
--[[ Dove stanno i completi.

    In single player nella modData del personaggio, come sempre: viaggia col
    salvataggio e non va da nessuna parte.

    In multiplayer **no**. La modData del giocatore e' una sola tabella, e il
    gioco la spedisce intera al server ogni volta che qualcuno chiama
    transmitModData - vanilla lo fa a ogni cambio della barra rapida
    (ISHotbar:savePosition, ISHotbar.lua:669), cioe' piu' volte per ogni capo
    che si toglie o si mette. Con i completi dentro, ventiquattro completi pieni
    facevano decine di KB a spedizione, decine di spedizioni per un cambio
    d'abito, e il server le rilancia ai vicini (segnalazione 42.21, da un
    server dedicato).

    Quindi in rete i completi stanno in un file del client, in Zomboid/Lua, uno
    per server e per personaggio, e nella modData resta solo `wid`: una manciata
    di caratteri che dice quale file e' di questo personaggio. Un personaggio
    nuovo con lo stesso nome ha un `wid` nuovo, e un guardaroba vuoto.

    I completi gia' salvati nella modData da una versione precedente passano
    nel file alla prima lettura, e la modData si svuota con un'ultima
    spedizione.
]]

local FILE_PREFIX = "NeatUIEquipment_"
local FILE_MAGIC  = "NEQ-OUTFITS 1"
local NEWLINE     = string.char(10)

--- Il carattere fuori dall'insieme sicuro diventa %XX: cosi' ; { } non
--- possono mai comparire dentro una stringa codificata.
--- Le cifre a mano e non con string.format("%02X"): quel formato in Kahlua non
--- e' garantito, e qui un errore costerebbe il guardaroba.
local HEX = "0123456789ABCDEF"
local function esc(s)
    return (string.gsub(s, "[^%w _%-%.]", function(c)
        local b = string.byte(c)
        local hi, lo = math.floor(b / 16), b % 16
        return "%" .. string.sub(HEX, hi + 1, hi + 1) .. string.sub(HEX, lo + 1, lo + 1)
    end))
end

local function unesc(s)
    return (string.gsub(s, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local encode
encode = function(v)
    local t = type(v)
    if t == "string" then return "s" .. esc(v) .. ";" end
    if t == "number" then return "n" .. tostring(v) .. ";" end
    if t == "boolean" then return v and "b1;" or "b0;" end
    if t == "table" then
        local out = { "{" }
        for k, val in pairs(v) do
            local tk = type(k)
            local tv = type(val)
            if (tk == "string" or tk == "number")
                and (tv == "string" or tv == "number" or tv == "boolean" or tv == "table") then
                out[#out + 1] = encode(k)
                out[#out + 1] = encode(val)
            end
        end
        out[#out + 1] = "}"
        return table.concat(out)
    end
    return "b0;"
end

--- Legge un valore a partire da `i`; restituisce il valore e dove riprendere.
--- Un testo malformato da' nil, mai un errore: un file rovinato a mano deve
--- costare quel completo, non il guardaroba.
local decode
decode = function(s, i)
    local tag = string.sub(s, i, i)
    if tag == "{" then
        local t = {}
        i = i + 1
        while string.sub(s, i, i) ~= "}" do
            if i > #s then return nil, i end
            local k, v
            k, i = decode(s, i)
            if k == nil then return nil, i end
            v, i = decode(s, i)
            if v == nil then return nil, i end
            t[k] = v
        end
        return t, i + 1
    end
    local stop = string.find(s, ";", i, true)
    if not stop then return nil, #s + 1 end
    local body = string.sub(s, i + 1, stop - 1)
    if tag == "s" then return unesc(body), stop + 1 end
    if tag == "n" then return tonumber(body), stop + 1 end
    if tag == "b" then return body == "1", stop + 1 end
    return nil, stop + 1
end

-- Per i controlli fuori dal gioco (STRUMENTI): la codifica e' la parte che
-- non si vede in partita, ed e' quella che non deve sbagliare.
O._encode = encode
O._decode = decode

local function safeName(s)
    return (string.gsub(tostring(s or ""), "[^%w_%-]", "_"))
end

--- Il server a cui si e' collegati, come parte del nome del file.
local function serverKey()
    local ip, port = "", ""
    pcall(function() ip = tostring(getServerIP() or "") end)
    pcall(function() port = tostring(getServerPort() or "") end)
    return safeName(ip .. "_" .. port)
end

local function modRoot(character)
    if not character then return nil end
    local ok, modData = pcall(function() return character:getModData() end)
    if not ok or not modData then return nil end
    local root = modData[O.MODDATA_KEY]
    if type(root) ~= "table" then
        root = {}
        modData[O.MODDATA_KEY] = root
    end
    return root
end

local function transmitNow(character)
    if not character or not isClient() then return end
    pcall(function() character:transmitModData() end)
end

local function readFile(name)
    local reader = getFileReader(name, false)
    if not reader then return nil end
    local outfits = {}
    local first = reader:readLine()
    if first == FILE_MAGIC then
        local line = reader:readLine()
        while line ~= nil do
            if line ~= "" then
                local ok, outfit = pcall(function() return (decode(line, 1)) end)
                if ok and type(outfit) == "table" then
                    if type(outfit.worn) ~= "table" then outfit.worn = {} end
                    if type(outfit.hotbar) ~= "table" then outfit.hotbar = {} end
                    outfits[#outfits + 1] = outfit
                end
            end
            line = reader:readLine()
        end
    end
    reader:close()
    return outfits
end

local function writeFile(name, outfits)
    local writer = getFileWriter(name, true, false)
    if not writer then return false end
    writer:write(FILE_MAGIC .. NEWLINE)
    for _, outfit in ipairs(outfits) do
        writer:write(encode(outfit) .. NEWLINE)
    end
    writer:close()
    return true
end

-- Per file, non per personaggio: in split screen ognuno ha il suo.
local fileStores = {}

--- Il file del personaggio, creato e migrato alla prima richiesta.
local function networkStore(character, root)
    if type(root.wid) ~= "string" or root.wid == "" then
        local name = "x"
        pcall(function() name = character:getUsername() or name end)
        root.wid = safeName(tostring(getTimestampMs()) .. "_" .. tostring(ZombRand(1000000)) .. "_" .. name)
        transmitNow(character)
    end

    local fileName = FILE_PREFIX .. serverKey() .. "_" .. root.wid .. ".txt"
    local entry = fileStores[fileName]
    if entry then return entry end

    entry = { fileName = fileName, outfits = readFile(fileName) or {} }
    fileStores[fileName] = entry

    -- Quelli che stavano nella modData: in coda a quelli del file, poi la
    -- modData si alleggerisce una volta per tutte.
    if type(root.outfits) == "table" and #root.outfits > 0 then
        for _, outfit in ipairs(root.outfits) do
            if #entry.outfits < O.MAX_OUTFITS then
                entry.outfits[#entry.outfits + 1] = outfit
            end
        end
        writeFile(fileName, entry.outfits)
        root.outfits = nil
        transmitNow(character)
    elseif root.outfits ~= nil then
        root.outfits = nil
    end
    return entry
end

--- Il nostro angolo: una tabella con `outfits`, ovunque stia davvero.
local function store(character)
    local root = modRoot(character)
    if not root then return nil end

    if isClient() then
        return networkStore(character, root)
    end

    if type(root.outfits) ~= "table" then root.outfits = {} end
    return root
end

--- The saved outfits, oldest first. Always a table, never nil.
function O.all(character)
    local root = store(character)
    return root and root.outfits or {}
end

--- Rende definitiva una modifica.
---
--- In rete si riscrive il file del personaggio, e basta: niente piu'
--- transmitModData, che era il carico segnalato. In single player non serve
--- niente - la tabella locale e' gia' quella salvata, come per la barra rapida
--- di vanilla, che spedisce solo sotto isClient().
local function transmit(character)
    if not character or not isClient() then return end
    local entry = store(character)
    if entry and entry.fileName then
        pcall(function() writeFile(entry.fileName, entry.outfits) end)
    end
end

--- The id has to be copied too. It was not: describe() read it, the wardrobe
--- ranked candidates by it, and this copy - the one that goes into modData -
--- dropped it. So "this exact bag" never survived saving, and only the
--- "fuller of two identical bags" rule was ever doing the work.
local function copyDescriptor(descriptor)
    if not descriptor then return nil end
    return {
        type = descriptor.type,
        texture = descriptor.texture,
        id = descriptor.id,
        tint = descriptor.tint and {
            r = descriptor.tint.r, g = descriptor.tint.g, b = descriptor.tint.b,
        } or nil,
    }
end

--- Every field of the outfit itself is listed here, the new ones too: this copy
--- is what reaches modData, and a field it forgets is a field that was never
--- saved (METODO/03, lesson 70).
function O.copy(outfit)
    local copy = {
        name = outfit and outfit.name,
        saved = outfit and outfit.saved,
        symbol = outfit and type(outfit.symbol) == "string" and outfit.symbol or nil,
        noBags = outfit and outfit.noBags == true or nil,
        noHotbar = outfit and outfit.noHotbar == true or nil,
        worn = {}, hotbar = {},
    }
    for key, descriptor in pairs(outfit and outfit.worn or {}) do
        if O.isOutfitLocation(key) then
            copy.worn[key] = copyDescriptor(descriptor)
        end
    end
    for key, descriptor in pairs(outfit and outfit.hotbar or {}) do
        copy.hotbar[key] = copyDescriptor(descriptor)
    end
    return copy
end

--- Saves a copy, so later edits to the live table cannot reach into modData.
---@return boolean saved, string|nil reason
function O.save(character, outfit)
    local root = store(character)
    if not root then return false, "nostore" end
    if O.isEmpty(outfit) then return false, "empty" end
    if #root.outfits >= O.MAX_OUTFITS then return false, "full" end

    local saved = O.copy(outfit)
    local ok, age = pcall(function() return getGameTime():getWorldAgeHours() end)
    saved.saved = ok and age or nil

    table.insert(root.outfits, saved)
    transmit(character)
    return true
end

function O.rename(character, index, name)
    local outfits = O.all(character)
    if not outfits[index] then return false end
    outfits[index].name = name
    transmit(character)
    return true
end

--- The symbol beside the name. nil or "" takes it away.
function O.setSymbol(character, index, symbol)
    local outfits = O.all(character)
    if not outfits[index] then return false end
    if symbol == "" then symbol = nil end
    outfits[index].symbol = symbol
    transmit(character)
    return true
end

--- Puts `outfit` in place of saved outfit `index`, keeping what the player
--- gave the old one: its name, its symbol and its place in the list. The
--- caller captures `outfit` with the old one's bags and hotbar choices, so an
--- outfit saved without bags stays without bags.
---@return boolean replaced, string|nil reason
function O.replace(character, index, outfit)
    local outfits = O.all(character)
    local old = outfits[index]
    if not old then return false, "missing" end
    if O.isEmpty(outfit) then return false, "empty" end

    local fresh = O.copy(outfit)
    fresh.name = old.name
    fresh.symbol = old.symbol
    local ok, age = pcall(function() return getGameTime():getWorldAgeHours() end)
    fresh.saved = ok and age or old.saved

    outfits[index] = fresh
    transmit(character)
    return true
end

function O.delete(character, index)
    local outfits = O.all(character)
    if not outfits[index] then return false end
    table.remove(outfits, index)
    transmit(character)
    return true
end

--- A default name for the next outfit: "Outfit 1", "Outfit 2", ... skipping
--- numbers already taken so deleting the middle one does not create a clash.
function O.suggestName(character)
    local outfits = O.all(character)
    local taken = {}
    for _, outfit in ipairs(outfits) do
        if outfit.name then taken[outfit.name] = true end
    end

    -- Built by concatenation rather than string.format: a translator dropping
    -- the %d would otherwise turn a name into a Lua error.
    local word = getText("UI_NEQ_outfit_default_name")
    for i = 1, O.MAX_OUTFITS + 1 do
        local name = word .. " " .. i
        if not taken[name] then return name end
    end
    return word .. " " .. (#outfits + 1)
end

return O

--[[ ============================================================================
    NEQ_Gather - everything the survivor could put on right now, indexed once.

    Wearing an outfit asks the same question a dozen times: "where is a
    Base.Tshirt_White?". Answering it by walking every container once per
    garment is what makes an outfit switch feel like the game froze. So the
    world is walked exactly once and the result is a hash of full item type ->
    candidates, which turns each of those dozen questions into a table lookup.

    Three sources, in the order the resolver prefers them:

        worn        already on the character - no work to do at all
        inventory   the character's own bags - one wear action
        nearby      a container within reach - a transfer, then a wear

    "Nearby" is read from the loot window's own container list, which is the
    authoritative one: the engine has already worked out which containers are
    in reach, floor and vehicle seats included, and re-deriving that by hand
    would only produce a second, worse answer. When the loot window
    is not up to date - it can be closed - the squares around the character are
    scanned instead.

    Nothing here mutates anything. It reads containers and returns tables.
============================================================================ ]]--

if isServer() then return end

local Outfit = require("NeatEquipment/NEQ_Outfit")

NEQ_Gather = NEQ_Gather or {}
local G = NEQ_Gather

-- How far the fallback scan reaches, in tiles, when the loot window cannot
-- answer. One ring is what "immediate vicinity" means; more than that and the
-- survivor would be fetching things they cannot see.
G.FALLBACK_RADIUS = 1

-- One level into bags: a backpack full of clothes counts, a backpack inside a
-- backpack inside a crate does not.
local BAG_DEPTH = 1

local SOURCE_RANK = { worn = 1, inventory = 2, nearby = 3 }

-- Containers that exist only to drive a UI and hold no real items.
local VIRTUAL_CONTAINERS = { proxInv = true, ["local"] = true }

-- ---------------------------------------------------------------------------
-- Building the index
-- ---------------------------------------------------------------------------
local function add(index, item, source, container)
    if not item then return end

    local descriptor = Outfit.describe(item)
    if not descriptor then return end

    local bucket = index.byType[descriptor.type]
    if not bucket then
        bucket = {}
        index.byType[descriptor.type] = bucket
    end

    bucket[#bucket + 1] = {
        item = item,
        descriptor = descriptor,
        source = source,
        container = container,
    }
end

local function addContainer(index, container, source, depth, seen)
    if not container or seen[container] then return end
    seen[container] = true

    local ok, items = pcall(function() return container:getItems() end)
    if not ok or not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            add(index, item, source, container)

            if depth > 0 and item:IsInventoryContainer() then
                local okInner, inner = pcall(function() return item:getInventory() end)
                if okInner and inner then
                    addContainer(index, inner, source, depth - 1, seen)
                end
            end
        end
    end
end

--- The loot window already knows every container in reach. Reading its list is
--- both cheaper and more correct than a hand-rolled scan: it includes the
--- floor, vehicle seats and anything another mod put there.
---@return boolean answered
local function addLootWindowContainers(index, playerNum, playerInventory, seen)
    local loot = getPlayerLoot(playerNum)
    if not loot or not loot.backpacks or #loot.backpacks == 0 then return false end

    local added = false
    for _, button in ipairs(loot.backpacks) do
        local container = button.inventory
        if container and container ~= playerInventory then
            local ok, containerType = pcall(function() return container:getType() end)
            if not ok or not VIRTUAL_CONTAINERS[containerType] then
                addContainer(index, container, "nearby", BAG_DEPTH, seen)
                added = true
            end
        end
    end

    return added
end

--- Gli oggetti posati sul pavimento di una casella.
local function addWorldItems(index, square)
    local ok, worldObjects = pcall(function() return square:getWorldObjects() end)
    if not ok or not worldObjects then return end

    for i = 0, worldObjects:size() - 1 do
        local worldObject = worldObjects:get(i)
        local okItem, item = pcall(function() return worldObject and worldObject:getItem() end)
        if okItem and item then
            add(index, item, "nearby", item:getContainer())
        end
    end
end

--- I contenitori appoggiati su una casella. `getObjects` tiene quelli piantati
--- - armadi, credenze - e `getStaticMovingObjects` quelli spostabili, come le
--- casse: sono due liste separate e servono tutte e due.
local function addSquareContainers(index, square, seen)
    for _, listName in ipairs({ "getObjects", "getStaticMovingObjects" }) do
        local okList, objects = pcall(function() return square[listName](square) end)
        if okList and objects then
            for i = 0, objects:size() - 1 do
                local worldObject = objects:get(i)
                local okContainer, container = pcall(function()
                    return worldObject and worldObject:getContainer()
                end)
                if okContainer and container then
                    addContainer(index, container, "nearby", BAG_DEPTH, seen)
                end
            end
        end
    end
end

--- Fallback for when the loot window has nothing to say: one ring of squares
--- around the survivor, every container on each.
local function addNearbySquares(index, character, seen)
    local ok, square = pcall(function() return character:getCurrentSquare() end)
    if not ok or not square then return end

    local baseX, baseY, baseZ = square:getX(), square:getY(), square:getZ()
    local radius = G.FALLBACK_RADIUS

    for dx = -radius, radius do
        for dy = -radius, radius do
            local okCell, other = pcall(function()
                return getCell():getGridSquare(baseX + dx, baseY + dy, baseZ)
            end)
            if okCell and other then
                -- Roba sciolta per terra.
                --
                -- `getWorldObjects` e' il modo in cui il gioco legge quello che
                -- sta sul pavimento di una casella (ISInventoryPage.lua:1693).
                -- Qui prima si chiedeva alla casella un `getFloorContainer`
                -- che nei sorgenti del gioco non compare da nessuna parte -
                -- dentro un pcall, quindi falliva in silenzio e da questa
                -- strada la roba a terra non e' mai stata trovata.
                addWorldItems(index, other)

                -- I contenitori appoggiati sopra: il gioco li tiene in due
                -- liste diverse, quelli piantati e quelli spostabili.
                addSquareContainers(index, other, seen)
            end
        end
    end
end

--- Walk the world once.
---@param opts table|nil { carriedOnly = true } to stop at the survivor's own bags
---@return table index { byType = { [fullType] = { {item, descriptor, source, container} } } }
function G.build(character, playerNum, opts)
    opts = opts or {}
    local index = { byType = {} }
    if not character then return index end

    local seen = {}

    -- Worn first so an entry the survivor already has on wins every tie.
    local okWorn, wornItems = pcall(function() return character:getWornItems() end)
    if okWorn and wornItems then
        for i = 0, wornItems:size() - 1 do
            local entry = wornItems:get(i)
            local item = entry and entry:getItem()
            if item then add(index, item, "worn", nil) end
        end
    end

    -- Attached hotbar items live in the inventory too, but flagging them keeps
    -- the resolver from "fetching" something already in the right place.
    local hotbar = getPlayerHotbar(playerNum)
    if hotbar then
        for _, item in pairs(hotbar.attachedItems or {}) do
            if item then add(index, item, "worn", nil) end
        end
    end

    local inventory = nil
    local okInventory, playerInventory = pcall(function() return character:getInventory() end)
    if okInventory and playerInventory then
        inventory = playerInventory
        addContainer(index, playerInventory, "inventory", BAG_DEPTH, seen)
    end

    if not opts.carriedOnly then
        if not addLootWindowContainers(index, playerNum, inventory, seen) then
            addNearbySquares(index, character, seen)
        end
    end

    return index
end

-- ---------------------------------------------------------------------------
-- Where things can be put away
-- ---------------------------------------------------------------------------
--- Containers in the world the survivor could put clothes into right now.
---
--- The same sources as the index - the loot window first, the ring of squares
--- when it has nothing to say - but only containers that are not carried: the
--- point of putting an outfit away is that the survivor stops carrying it. A
--- corpse is not somewhere to put clothes either, and neither is the floor:
--- the container swap never drops anything (NEQ_Dresser).
---@return table { ItemContainer, ... }
function G.storageTargets(character, playerNum)
    local result = {}
    if not character then return result end

    local seen = {}
    local function consider(container)
        if not container or seen[container] then return end
        seen[container] = true

        local okType, containerType = pcall(function() return container:getType() end)
        if not okType or VIRTUAL_CONTAINERS[containerType] or containerType == "floor" then return end

        local okCarried, carried = pcall(function() return container:isInCharacterInventory(character) end)
        if not okCarried or carried then return end

        local okParent, parent = pcall(function() return container:getParent() end)
        if okParent and parent and instanceof(parent, "IsoDeadBody") then return end

        result[#result + 1] = container
    end

    local loot = getPlayerLoot(playerNum)
    if loot and loot.backpacks and #loot.backpacks > 0 then
        for _, button in ipairs(loot.backpacks) do consider(button.inventory) end
    else
        local ok, square = pcall(function() return character:getCurrentSquare() end)
        if ok and square then
            local baseX, baseY, baseZ = square:getX(), square:getY(), square:getZ()
            local radius = G.FALLBACK_RADIUS
            for dx = -radius, radius do
                for dy = -radius, radius do
                    local okCell, other = pcall(function()
                        return getCell():getGridSquare(baseX + dx, baseY + dy, baseZ)
                    end)
                    if okCell and other then
                        for _, listName in ipairs({ "getObjects", "getStaticMovingObjects" }) do
                            local okList, objects = pcall(function() return other[listName](other) end)
                            if okList and objects then
                                for i = 0, objects:size() - 1 do
                                    local object = objects:get(i)
                                    local okContainer, container = pcall(function()
                                        return object and object:getContainer()
                                    end)
                                    if okContainer then consider(container) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Asking the index
-- ---------------------------------------------------------------------------
--- The best live item for a descriptor.
---
--- L'ordine delle domande, dalla piu' forte alla piu' debole:
---
---   1. **e' proprio quello?** L'id dell'oggetto salvato. Due zaini militari
---      identici sono indistinguibili per aspetto, ma non sono la stessa cosa:
---      uno ha dentro la tua roba. Se quello preciso e' ancora al mondo, e' lui.
---   2. **e' uguale a vedersi?** Colore e fantasia. Il completo ricordava una
---      maglietta blu, e dare la bianca perche' era piu' vicina e' la risposta
---      sbagliata, non una comoda.
---   3. **fra due borse identiche, quella con dentro qualcosa.** Vale per i
---      completi salvati prima che ci fosse l'id, che altrimenti resterebbero
---      con lo stesso difetto: metteva su lo zaino vuoto e lasciava a terra
---      quello pieno, perche' a parita' di tutto vinceva il primo trovato.
---   4. **quanto e' lontano.** Solo a parita' di tutto il resto.
---@return InventoryItem|nil item, string|nil source, ItemContainer|nil container
function G.find(index, descriptor, used)
    if not index or not descriptor then return nil, nil, nil end

    local bucket = index.byType[descriptor.type]
    if not bucket then return nil, nil, nil end

    local best, bestSource, bestContainer, bestRank = nil, nil, nil, math.huge
    for _, entry in ipairs(bucket) do
        if not (used and used[entry.item]) then
            local rank = (SOURCE_RANK[entry.source] or 50)

            if not Outfit.sameLook(entry.descriptor, descriptor) then
                rank = rank + 1000
            end

            -- Una borsa vuota quando ce n'e' una piena e' quasi sempre lo
            -- scambio che non si voleva: pesa piu' della vicinanza, meno
            -- dell'aspetto.
            if Outfit.isBag(entry.item) and Outfit.bagCount(entry.item) == 0 then
                rank = rank + 100
            end

            -- Domina tutto: e' l'oggetto salvato, non uno che gli somiglia.
            if descriptor.id and entry.descriptor.id == descriptor.id then
                rank = rank - 10000
            end

            if rank < bestRank then
                best, bestSource, bestContainer, bestRank =
                    entry.item, entry.source, entry.container, rank
            end
        end
    end

    return best, bestSource, bestContainer
end

return G

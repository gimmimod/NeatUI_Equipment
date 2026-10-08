--[[ ============================================================================
    NEQ_Dresser - turning an outfit into a survivor wearing it.

    Everything is expressed in vanilla timed actions: ISInventoryTransferAction
    to fetch, ISUnequipAction to take off, ISWearClothing to put on, and one
    tiny action of our own to attach to the hotbar in the right order. The
    survivor visibly does the work instead of teleporting into new clothes, and
    every step already replicates correctly in multiplayer because it is the
    path the base game uses. Nothing here calls setWornItem.

    ORDER MATTERS, AND THE OBVIOUS ORDER IS WRONG.

    The natural way to write this is "undress, then for each garment fetch it
    and wear it". That breaks for anything not already carried: by the time the
    fetch runs, a whole outfit has been unequipped into the inventory, and
    ISInventoryTransferAction:isValid() refuses a transfer into a container with
    no room. The transfer is skipped, so ISWearClothing:isValid() then finds the
    garment still in the crate and skips too - silently, because a failed
    isValid drops the action rather than erroring. The survivor ends up naked
    with the outfit never going on.

    So: fetch everything first, while the survivor is still dressed and their
    inventory is at its emptiest, and only then undress and dress. The second
    half runs inside ISTimedActionQueue.queueActions so it re-reads the world at
    the moment it happens rather than trusting item references captured when the
    wardrobe window was open.

    The whole change, in the order the survivor does it:

      1. take the new pieces out, one container at a time;
      2. empty the hotbar slots that change;
      3. change clothes from the feet up, one part of the body at a time -
         off what goes, then on what comes, each new piece replacing the old
         one in its place;
      4. hang the new things on the hotbar;
      5. with the container swap on, put away everything that came off, one
         container at a time, each piece where things of its kind already
         are - or, with no such container, left in the inventory.

    Grouping by container is for speed: vanilla folds consecutive transfers
    between the same two containers into one action.
============================================================================ ]]--

if isServer() then return end

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWearClothing"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISInventoryTransferAction"

local Outfit = require("NeatEquipment/NEQ_Outfit")
local Gather = require("NeatEquipment/NEQ_Gather")
local Categories = require("NeatEquipment/NEQ_Categories")
local State = require("NeatEquipment/NEQ_State")
local AttachAction = require("NeatEquipment/NEQ_AttachAction")

NEQ_Dresser = NEQ_Dresser or {}
local D = NEQ_Dresser

local WEAR_TIME = 50

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function queue(action)
    if action then pcall(function() ISTimedActionQueue.add(action) end) end
end

local function newTransfer(character, item, from, to)
    local ok, action = pcall(function()
        return ISInventoryTransferUtil.newInventoryTransferAction(character, item, from, to)
    end)
    if ok and action then return action end

    local okFallback, fallback = pcall(function()
        return ISInventoryTransferAction:new(character, item, from, to)
    end)
    return okFallback and fallback or nil
end

--- Move one item into the survivor's own inventory if it is not there already.
---
--- Deliberately not ISInventoryPaneContextMenu.transferIfNeeded: that routes
--- through luautils.haveToBeTransfered, which walks to the container, and
--- walking clears the timed action queue - wiping everything queued so far.
--- Where a transfer of `item` starts from.
---
--- Something lying on the ground is in no container of its own: the loot
--- window puts it in its "floor" container when it refreshes
--- (ISInventoryPage:refreshBackpacks, floorContainer:AddItem), and a transfer
--- from the floor is a transfer from that container. A piece found by the
--- fallback scan, with the loot window not refreshed yet, had no container at
--- all, and its fetch was silently never queued: the outfit left it on the
--- ground. It goes into the floor container here, the way the loot window
--- would put it.
local function sourceOf(character, item)
    local container = item:getContainer()
    if container then return container end

    local ok, world = pcall(function() return item:getWorldItem() end)
    if not ok or not world then return nil end

    local okFloor, floor = pcall(function()
        return ISInventoryPage.GetFloorContainer(character:getPlayerNum())
    end)
    if not okFloor or not floor then return nil end
    if not floor:contains(item) then floor:AddItem(item) end
    return floor
end

local function queueFetch(character, item)
    if not item then return end

    local inventory = character:getInventory()
    local container = sourceOf(character, item)
    if not inventory or not container or container == inventory then return end

    queue(newTransfer(character, item, container, inventory))
end

--[[ Puts `list` in the order transfers are fastest in, and queues it.

    Vanilla folds consecutive transfers between the same two containers into
    one action (ISInventoryTransferAction:checkQueueList): the container is
    opened once and the survivor keeps going, instead of starting over for
    every piece. So the list is grouped by container. The containers come in
    the order of the first piece each one holds, and inside a container the
    pieces keep their own order.

    Each entry is { item = ..., rank = ... }, and the rank is what "their own
    order" means; this sorts by it first.
]]
local function groupByContainer(list, containerOf)
    table.sort(list, function(a, b) return a.rank < b.rank end)

    local position, count = {}, 0
    for _, entry in ipairs(list) do
        local container = containerOf(entry)
        if container and not position[container] then
            count = count + 1
            position[container] = count
        end
    end

    for index, entry in ipairs(list) do entry.index = index end
    table.sort(list, function(a, b)
        local pa = position[containerOf(a)] or (count + 1)
        local pb = position[containerOf(b)] or (count + 1)
        if pa ~= pb then return pa < pb end
        return a.index < b.index
    end)
end

local function queueFetches(character, list)
    for _, entry in ipairs(list) do entry.source = sourceOf(character, entry.item) end
    groupByContainer(list, function(entry) return entry.source end)
    for _, entry in ipairs(list) do queueFetch(character, entry.item) end
end

--- On the survivor: worn, or in the hands.
---
--- isEquipped answers for worn clothes too: vanilla relies on it before
--- removeWornItem (ISTransferAction.lua:84), and a double click on a worn shirt
--- takes it off because of it (ISInventoryPane.lua:962).
local function isWorn(character, item)
    local ok, worn = pcall(function() return character:isEquipped(item) end)
    return ok and worn == true
end

--[[ Queue `fn` so that it reads the world only once the action before it has
    fully finished.

    A function queued with queueActions runs from ISQueueActionsAction:start(),
    and start() is called from inside the previous action's perform():
    ISBaseTimedAction.perform -> onCompleted -> begin -> StartAction ->
    waitToStart -> start. The engine calls that action's complete() only after
    perform() returns (IsoGameCharacter.updateInternal), and complete() is
    where a wear or an unequip actually changes what is worn. So a function
    queued straight after the last wear saw the piece that wear replaces still
    on the survivor, took it for "not taken off", and left it in the inventory -
    always one piece, always the same one.

    The outer step only queues the inner one and is finished on the next tick
    (forceComplete sets a flag), by which time complete() has run. It also always
    queues something, so it never takes the "nothing was added" exit, which
    clears the whole queue.
]]
local function queueSettled(character, fn, arg)
    ISTimedActionQueue.queueActions(character, function(chr, a)
        ISTimedActionQueue.queueActions(chr, fn, a)
    end, arg)
end

-- ---------------------------------------------------------------------------
-- Resolving an outfit against what is actually reachable
-- ---------------------------------------------------------------------------
--- Match every descriptor in the outfit to a live item.
---
--- `used` stops two slots claiming the same shirt: an outfit with two entries
--- of the same type needs two shirts, not one shirt twice.
---
--- Body locations that are never clothing - bandages, wounds - are skipped. An
--- outfit saved before that rule may still list a bandage, and it must not be
--- fetched, worn or reported missing.
---
--- `origin` says, for each piece, the container it was found in - but only
--- when that is somewhere other than the survivor's own inventory. It is what
--- the container swap sends the old piece back to.
---
--- With `opts.noHotbar` the hotbar entries are ignored, and so is any worn
--- piece that exists for the hotbar - a belt location, or an item found to
--- provide slots. Ignored means not fetched, not worn and not missing.
---@return table worn locationKey -> item
---@return table hotbar slotType -> item
---@return table missing display names of what could not be found
---@return table origin { worn = { key -> container }, hotbar = { slotType -> container } }
function D.resolve(outfit, index, inventory, opts)
    opts = opts or {}
    local worn, hotbar, missing = {}, {}, {}
    local origin = { worn = {}, hotbar = {} }
    local used = {}

    local function remember(into, key, source, container)
        if source ~= "worn" and container and container ~= inventory then
            into[key] = container
        end
    end

    for key, descriptor in pairs(outfit.worn or {}) do
        local wanted = Outfit.isOutfitLocation(key)
            and not (opts.noHotbar and Outfit.isHotbarLocation(key))
        if wanted then
            local item, source, container = Gather.find(index, descriptor, used)
            if item and opts.noHotbar and Outfit.providesAttachments(item) then
                -- A belt saved under another location. Left alone, like the
                -- ones the location already gave away.
                item = nil
            elseif item then
                worn[key] = item
                used[item] = true
                remember(origin.worn, key, source, container)
            else
                missing[#missing + 1] = Outfit.describedName(descriptor)
            end
        end
    end

    if not opts.noHotbar then
        for slotType, descriptor in pairs(outfit.hotbar or {}) do
            local item, source, container = Gather.find(index, descriptor, used)
            if item then
                hotbar[slotType] = item
                used[item] = true
                remember(origin.hotbar, slotType, source, container)
            else
                missing[#missing + 1] = Outfit.describedName(descriptor)
            end
        end
    end

    return worn, hotbar, missing, origin
end

--[[ The order a change happens in: from the feet up, one part of the body at a
    time, the way a person gets changed.

    Each body location gets a rank: which part of the body it belongs to, times
    ZONE_STEP, plus how far from the skin it sits. The parts are the panel's own
    slots, taken in the order below; inside a slot definition the outermost
    layer comes first, so the layer count runs backwards through it. The engine
    has no ordering to ask, and the slot definitions are already play-tested.

    A location no slot knows - another mod's - ranks after every known part.
]]
local ZONE_ORDER = {
    "UI_NEQ_slot_feet", "UI_NEQ_slot_legs", "UI_NEQ_slot_waist", "UI_NEQ_slot_torso",
    "UI_NEQ_slot_vest", "UI_NEQ_slot_back", "UI_NEQ_slot_right_hand",
    "UI_NEQ_slot_left_hand", "UI_NEQ_slot_jewelry", "UI_NEQ_slot_face", "UI_NEQ_slot_head",
}
local ZONE_STEP = 1000
local UNKNOWN_RANK = (#ZONE_ORDER + 1) * ZONE_STEP

local bodyRank = nil

local function buildBodyRanks()
    if bodyRank then return bodyRank end
    bodyRank = {}

    local ok, definitions = pcall(function()
        return require("NeatEquipment/Definitions/NEQ_SlotDefs")
    end)
    if not ok or not definitions then return bodyRank end

    local byName = {}
    for _, definition in ipairs(definitions) do byName[definition.name] = definition end

    for zone, name in ipairs(ZONE_ORDER) do
        local keys = {}
        for _, location in ipairs(byName[name] and byName[name].bodyLocations or {}) do
            keys[#keys + 1] = Outfit.locationKey(location)
        end
        -- The hands share HANDS; the first part to name a location keeps it.
        for layer = 1, #keys do
            local key = keys[#keys + 1 - layer]
            if key and bodyRank[key] == nil then
                bodyRank[key] = zone * ZONE_STEP + layer
            end
        end
    end

    return bodyRank
end

--- Lower goes on earlier: feet before head, skin before coat.
local function rankOf(key)
    return (key and buildBodyRanks()[key]) or UNKNOWN_RANK
end

local function zoneOf(rank)
    return math.floor(rank / ZONE_STEP)
end

--- Cosa il personaggio ha addosso che questo completo non prevede, e che quindi
--- va tolto. Non e' un semplice "tutto il resto":
---
---   * gli slot che il completo riempie li sfratta il capo nuovo da solo;
---   * le borse non si toccano mai (vedi la nota su queueDressing);
---   * i capi nascosti (`isHidden`) sono sotto altri capi e non sono roba che
---     l'utente veda o abbia scelto.
---
--- Un completo salvato prima che esistesse questa regola non ha nulla di
--- diverso: era comunque una fotografia di tutto il vestiario, quindi "quello
--- che non prevede" e' vuoto e si comporta come prima.
---
--- With `opts.noHotbar`, belts and holsters are never surplus: the outfit does
--- not speak for them.
---@return table lista di InventoryItem da togliere
function D.surplusWorn(character, outfit, opts)
    opts = opts or {}
    local surplus = {}
    if not character or not outfit then return surplus end

    local ok, wornItems = pcall(function() return character:getWornItems() end)
    if not ok or not wornItems then return surplus end

    local planned = outfit.worn or {}

    -- All'indietro: prima lo strato piu' esterno, come quando ci si spoglia a
    -- mano, e senza che il motore rimescoli la lista sotto al ciclo.
    for i = wornItems:size() - 1, 0, -1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        if item and not item:isHidden() and not Outfit.isBag(item) then
            local key = Outfit.locationKey(entry:getLocation()) or Outfit.itemLocationKey(item)
            local kept = opts.noHotbar and Outfit.isHotbarBound(item, key)
            if key and not planned[key] and not kept then
                surplus[#surplus + 1] = item
            end
        end
    end

    return surplus
end

--- Where a garment goes when it is put on: ISWearClothing:complete uses the
--- same two answers.
local function wearKey(item)
    return Outfit.itemLocationKey(item)
end

--- What the survivor has on right now, with where each piece sits. The dressing
--- plan works on this copy, so it can tell what an earlier step will already
--- have taken off.
local function readBody(character)
    local body = {}
    local ok, wornItems = pcall(function() return character:getWornItems() end)
    if not ok or not wornItems then return body end

    for i = 0, wornItems:size() - 1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        if item and not item:isHidden() and Outfit.isOutfitItem(item) then
            body[#body + 1] = {
                item = item,
                location = entry:getLocation(),
                key = Outfit.locationKey(entry:getLocation()) or Outfit.itemLocationKey(item),
            }
        end
    end
    return body
end

--- Would putting something on at `location` push `other` off? The engine asks
--- the same question in WornItems.setItem.
local function pushesOff(group, location, other)
    if not group or not location or not other then return false end
    local ok, exclusive = pcall(function() return group:isExclusive(location, other) end)
    return ok and exclusive == true
end

-- ---------------------------------------------------------------------------
-- Wearing an outfit
-- ---------------------------------------------------------------------------
--[[ The container swap.

    With the option on, the outfit that comes off does not pile up on the
    survivor. Each piece of it - the pieces the new outfit replaces, the
    pieces it leaves out, and what hangs on the hotbar - goes into a container
    in reach that already holds something of its kind, the way a person puts
    a shirt back with the shirts. A piece with no such container stays in the
    inventory. Nothing is ever dropped on the floor.

    "Its kind" is NEQ_Categories: the exact category first, then the family,
    so a helmet goes with other protective gear if there is some and with the
    clothes otherwise. A piece picks, taking the first one with room:

      1. the container its replacement came from, if that container holds -
         or held until a moment ago - something of its kind. The new shirt
         leaves the wardrobe; the old one goes back into it;
      2. the container with the most of its exact category;
      3. the container with the most of its family.

    What was fetched out of a container still counts for it: the plan records
    the kinds each fetch took away (`taken`), because by the time the old
    outfit is put away the new one has already emptied those shelves. A piece
    put away counts from then on too, so the rest of the outfit follows it.

    Room is counted as the pieces are assigned, so five shirts do not all pick
    the one shelf that has room for two. A fridge, a stove or a bin is never a
    choice, whatever is inside it.

    It is a third phase, queued after the dressing and settled (queueSettled):
    by then every old piece has been taken off and is in the inventory, and
    each one is moved with a plain transfer. The world is read again at that
    moment. Nothing is forced: a transfer that fails its own check leaves the
    piece in the inventory. Favourites stay there anyway, because vanilla does
    not move them out.

    Bags are never moved, for the same reason they are never taken off: moving a
    bag moves everything in it. With the "leave the hotbar out" option, neither
    are belts, holsters or anything attached to the hotbar.
]]

-- Containers that hold something, but are not where anything from an outfit
-- is put away. The names are the container types from the game's
-- distributions.
local NOT_FOR_CLOTHES = {
    fridge = true, freezer = true, stove = true, microwave = true,
    bin = true, dumpster = true, clothingwasher = true, clothingdryer = true,
    barbecue = true, fireplace = true, woodstove = true,
}

local function isAttachedTo(hotbar, item, slotType)
    if not hotbar then return false end
    for index, slot in ipairs(hotbar.availableSlot) do
        if slot.slotType == slotType and hotbar.attachedItems[index] == item then
            return true
        end
    end
    return false
end

local function inHands(character, item)
    return character:getPrimaryHandItem() == item or character:getSecondaryHandItem() == item
end

-- ---------------------------------------------------------------------------
-- Putting the old outfit away
-- ---------------------------------------------------------------------------
local function containerType(container)
    local ok, t = pcall(function() return container:getType() end)
    return ok and t or nil
end

--- What an item weighs once it is off the survivor.
local function weightOf(item)
    local ok, w = pcall(function() return item:getUnequippedWeight() end)
    if ok and type(w) == "number" then return w end
    local okActual, actual = pcall(function() return item:getActualWeight() end)
    return (okActual and type(actual) == "number") and actual or 0
end

--- Does `item` fit in `container`, counting what this phase has already sent
--- there? The container's own answer first - it knows rules this does not -
--- then the weight, with the pieces already assigned added in.
local function fits(character, container, item, planned)
    if not container then return false end

    local okAllowed, allowed = pcall(function() return container:isItemAllowed(item) end)
    if okAllowed and allowed == false then return false end

    local okRoom, room = pcall(function() return container:hasRoomFor(character, item) end)
    if not okRoom or room ~= true then return false end

    local okCap, capacity, used = pcall(function()
        return container:getEffectiveCapacity(character), container:getCapacityWeight()
    end)
    if not okCap or type(capacity) ~= "number" or type(used) ~= "number" then return false end

    return used + (planned[container] or 0) + weightOf(item) <= capacity
end

--- The kinds a list of fetched pieces took out of each container. Read in
--- phase one, before the fetch, while the pieces are still where they were.
---@return table { [container] = { exact = {...}, family = {...} } }
local function kindsTaken(fetches, inventory)
    local taken = {}
    for _, entry in ipairs(fetches) do
        local source = entry.source
        if source and source ~= inventory then
            taken[source] = taken[source] or { exact = {}, family = {} }
            Categories.add(taken[source], entry.item)
        end
    end
    return taken
end

--- How many things of `exact` / `family` a container holds, in its tally.
local function holds(counts, exact, family)
    if not counts then return 0, 0 end
    return (exact and counts.exact[exact]) or 0, (family and counts.family[family]) or 0
end

--- Phase three: put every piece of the old outfit away where things of its
--- kind already are. See the note on the container swap above.
local function queueStore(character, plan)
    local playerNum = character:getPlayerNum()
    local inventory = character:getInventory()
    local hotbarUI = getPlayerHotbar(playerNum)

    -- Every container in reach that could take it, with a tally of what is in
    -- it - and of what the fetch took out of it a moment ago.
    local candidates, counts = {}, {}
    for _, container in ipairs(Gather.storageTargets(character, playerNum)) do
        if not NOT_FOR_CLOTHES[containerType(container)] then
            candidates[#candidates + 1] = container
            local tally = Categories.count(container)
            local taken = plan.taken and plan.taken[container]
            if taken then
                for key, n in pairs(taken.exact) do tally.exact[key] = (tally.exact[key] or 0) + n end
                for key, n in pairs(taken.family) do tally.family[key] = (tally.family[key] or 0) + n end
            end
            counts[container] = tally
        end
    end

    local planned = {}
    local moves = {}

    for _, entry in ipairs(plan.pieces or {}) do
        local item = entry.item
        local free = item and item:getContainer() == inventory
            and not isWorn(character, item)
            and not inHands(character, item)
            and not (hotbarUI and hotbarUI:isInHotbar(item))

        if free then
            local exact, family = Categories.of(item)
            local dest = nil

            -- 1. where its replacement came from, if its kind is (or was) there
            local preferred = entry.preferred
            if preferred and counts[preferred] then
                local sameExact, sameFamily = holds(counts[preferred], exact, family)
                if (sameExact > 0 or sameFamily > 0) and fits(character, preferred, item, planned) then
                    dest = preferred
                end
            end

            -- 2. the most of its exact category, 3. the most of its family
            if not dest then
                local bestExact, bestFamily = 0, 0
                local byExact, byFamily = nil, nil
                for _, container in ipairs(candidates) do
                    local sameExact, sameFamily = holds(counts[container], exact, family)
                    if (sameExact > bestExact or sameFamily > bestFamily)
                        and fits(character, container, item, planned) then
                        if sameExact > bestExact then byExact, bestExact = container, sameExact end
                        if sameFamily > bestFamily then byFamily, bestFamily = container, sameFamily end
                    end
                end
                dest = byExact or byFamily
            end

            -- No container with its kind: it stays in the inventory.
            if dest then
                planned[dest] = (planned[dest] or 0) + weightOf(item)
                Categories.add(counts[dest], item)
                moves[#moves + 1] = { item = item, dest = dest, rank = #moves + 1 }
            end
        end
    end

    -- One container at a time.
    groupByContainer(moves, function(move) return move.dest end)
    for _, move in ipairs(moves) do
        queue(newTransfer(character, move.item, inventory, move.dest))
    end
end

--- Phase two. Runs once the fetches have landed, so the world is read again
--- rather than remembered.
---
--- Un completo e' **esatto**: quello che contiene va addosso, e quello che il
--- personaggio ha addosso e che il completo non prevede viene tolto. Serviva
--- per un caso concreto: un completo "per dormire" e' spesso quello di tutti i
--- giorni meno i pezzi scomodi, quindi non aggiunge niente. Con la vecchia
--- regola additiva non c'era nulla da fare e il pannello rispondeva "indossi
--- gia' questo completo" lasciando su l'armatura.
---
--- Uno slot che il completo riempie non ha bisogno di essere svuotato prima:
--- indossare un capo sfratta da solo chi occupava quel posto. Le rimozioni
--- esplicite servono solo per gli slot che il completo lascia vuoti.
---
--- **Le borse non si tolgono mai.** Un completo puo' darti uno zaino, mai
--- portartelo via: toglierlo significa spostare anche tutto il contenuto, e
--- una borsa piena e' esattamente il carico che fa fallire l'azione.
local function queueDressing(character, context)
    local playerNum = character:getPlayerNum()
    local opts = context.opts or {}
    local origin = context.origin or { worn = {}, hotbar = {} }

    -- Only what the survivor now has on or is carrying. Anything still in a
    -- crate did not make it through the fetch, and queueing a wear for it would
    -- be a silent no-op.
    local carried = Gather.build(character, playerNum, { carriedOnly = true })
    local worn, hotbar = D.resolve(context.outfit, carried, nil, opts)
    local hotbarUI = (not opts.noHotbar) and getPlayerHotbar(playerNum) or nil

    -- What the new outfit keeps using. It is never put away, whatever slot it
    -- is in right now.
    local planned = {}
    for _, item in pairs(worn) do planned[item] = true end
    for _, item in pairs(hotbar) do planned[item] = true end

    -- With the container swap on, what comes off is collected here and put
    -- away at the end. What the new outfit still uses stays, and bags are never
    -- moved (see the note on the container swap).
    local store = context.swap and {} or nil
    local function putAway(item, preferred)
        if store and item and not planned[item] and not Outfit.isBag(item) then
            store[#store + 1] = { item = item, preferred = preferred }
        end
    end

    -- The hotbar comes off first, before the belts that hold it.
    --
    -- A slot the outfit fills with something else is always emptied: the attach
    -- only ever fills an empty slot, so an outfit with a different torch for
    -- the belt used to fetch the new one and leave the old one where it was.
    -- A slot the outfit does not mention is emptied only when the old outfit
    -- is being put away, or when what is in it belongs somewhere else in the new
    -- outfit.
    if hotbarUI then
        for index, slot in ipairs(hotbarUI.availableSlot) do
            local occupant = hotbarUI.attachedItems[index]
            local wanted = hotbar[slot.slotType]
            if occupant and occupant ~= wanted
                and (wanted ~= nil or store ~= nil or planned[occupant]) then
                queue(AttachAction.newDetach(character, occupant))
                putAway(occupant, wanted and origin.hotbar[slot.slotType] or nil)
            end
        end
    end

    -- The body, from the feet up, one part at a time. In each part, what the
    -- new outfit does not want comes off first, outermost first; then the new
    -- pieces go on, from the skin out. A new piece replaces what sits in its
    -- place by itself - one action, not two. Everything that comes off waits
    -- in the inventory for the put-away at the very end.
    local steps = {}
    for key, item in pairs(worn) do
        if not isWorn(character, item) then
            local at = wearKey(item) or key
            steps[#steps + 1] = { item = item, key = key, at = at, rank = rankOf(at), on = true }
        end
    end

    local body = readBody(character)
    local placeOf = {}
    for _, piece in ipairs(body) do placeOf[piece.item] = piece.key end
    for _, item in ipairs(D.surplusWorn(character, context.outfit, opts)) do
        local at = placeOf[item] or wearKey(item)
        steps[#steps + 1] = { item = item, at = at, rank = rankOf(at), on = false }
    end

    table.sort(steps, function(a, b)
        local za, zb = zoneOf(a.rank), zoneOf(b.rank)
        if za ~= zb then return za < zb end
        if a.on ~= b.on then return b.on end
        if a.rank ~= b.rank then
            if a.on then return a.rank < b.rank end
            return a.rank > b.rank
        end
        return tostring(a.at) < tostring(b.at)
    end)

    local group = nil
    pcall(function() group = character:getWornItems():getBodyLocationGroup() end)

    -- What has come off so far, in the plan. The body is read once, before
    -- anything runs, so this is how a step knows what an earlier one removed.
    local off = {}
    local function takeOff(item)
        queue(ISUnequipAction:new(character, item, WEAR_TIME))
        off[item] = true
        putAway(item, nil)
    end

    for _, step in ipairs(steps) do
        local item = step.item
        if not step.on then
            -- Already off when a piece further down was in its way.
            if not off[item] then takeOff(item) end
        else
            local location = Outfit.location(step.at)
            for _, piece in ipairs(body) do
                local other = piece.item
                local keptOn = opts.noHotbar and Outfit.isHotbarBound(other, piece.key)
                if other ~= item and not off[other] then
                    if piece.key == step.at then
                        -- The wear pushes it off by itself.
                        off[other] = true
                        if not keptOn then
                            putAway(other, origin.worn[step.key])
                        end
                    elseif pushesOff(group, location, piece.location) and not planned[other]
                        and not Outfit.isBag(other) and not keptOn then
                        -- A piece this one cannot be worn with (trousers and a
                        -- boilersuit). The wear would push it off silently;
                        -- taking it off first is what a person does, and it
                        -- keeps its own step from aiming at a garment that is
                        -- no longer on - an action that is no longer valid
                        -- empties the whole queue.
                        takeOff(other)
                    end
                end
            end
            queue(ISWearClothing:new(character, item, WEAR_TIME))
        end
    end

    -- Last, so the belts and holsters that provide the slots are already on.
    for slotType, item in pairs(hotbar) do
        if not isAttachedTo(hotbarUI, item, slotType) then
            queue(AttachAction:new(character, item, slotType))
        end
    end

    -- Queued from inside this callback, so it lands after everything above
    -- (ISTimedActionQueue.lua:190-195), and settled, so the last of those
    -- actions has taken its piece off by the time the world is read.
    if store and #store > 0 then
        queueSettled(character, queueStore, { pieces = store, taken = context.taken })
    end
end

--- Put an outfit on. Returns whether anything was queued, and the names of
--- whatever could not be found anywhere.
---
--- Missing pieces never stop the rest: an outfit whose boots are three rooms
--- away still gets you into the shirt and trousers.
---@return boolean started, table missing
function D.wear(character, playerNum, outfit)
    if not character or not outfit then return false, {} end

    -- Saved without the hotbar, or the hotbar left out everywhere: either way
    -- belts and attached items are not this outfit's business.
    local opts = { noHotbar = Outfit.skipsHotbar(outfit, State.wardrobeNoHotbar) }
    local swap = State.wardrobeSwapContainers

    -- Phase one: one walk of the world, then fetch everything into the
    -- survivor's own inventory while they are still dressed and carrying least.
    local index = Gather.build(character, playerNum)
    local worn, hotbar, missing, origin = D.resolve(outfit, index, character:getInventory(), opts)

    local hotbarUI = (not opts.noHotbar) and getPlayerHotbar(playerNum) or nil
    local anything = false

    local fetches = {}
    for key, item in pairs(worn) do
        if not isWorn(character, item) then
            fetches[#fetches + 1] = { item = item, rank = rankOf(key) }
        end
    end

    for slotType, item in pairs(hotbar) do
        if not isAttachedTo(hotbarUI, item, slotType) then
            fetches[#fetches + 1] = { item = item, rank = UNKNOWN_RANK + 1 }
        end
    end

    queueFetches(character, fetches)
    anything = #fetches > 0

    -- What each fetch takes out of its container, read now while it is still
    -- there: the put-away counts it as that container's kind (queueStore).
    local taken = swap and kindsTaken(fetches, character:getInventory()) or nil

    -- Anche togliere e' lavoro. Senza questa riga un completo che si limita a
    -- levare roba - quello "per dormire", che e' il completo di tutti i giorni
    -- meno i pezzi scomodi - non aggiunge niente e verrebbe scambiato per
    -- "gia' indossato".
    if not anything and #D.surplusWorn(character, outfit, opts) > 0 then
        anything = true
    end

    -- Putting the old outfit away counts too: with the swap on, something on
    -- the hotbar that the outfit does not mention is part of the old outfit.
    if not anything and swap and hotbarUI then
        local planned = {}
        for _, item in pairs(hotbar) do planned[item] = true end
        for _, item in pairs(hotbarUI.attachedItems or {}) do
            if item and not planned[item] then
                anything = true
                break
            end
        end
    end

    -- Nothing found that is not already where it belongs: the survivor is
    -- wearing this outfit already, and queueing an empty change would only look
    -- like the button did nothing.
    if not anything then return false, missing end

    -- Where each piece came from is known only now, before the fetch empties
    -- those containers into the inventory. Phase two reads it from here.
    local context = { outfit = outfit, opts = opts, swap = swap, origin = origin, taken = taken }

    local ok = pcall(function()
        ISTimedActionQueue.queueActions(character, queueDressing, context)
    end)
    if not ok then
        -- queueActions is the tidy route; the change should still happen.
        queueDressing(character, context)
    end

    return true, missing
end

-- ---------------------------------------------------------------------------
-- Strip / restore
-- ---------------------------------------------------------------------------
--- What the survivor has on right now, as live item references.
---
--- References rather than descriptors on purpose: unequipped clothes land in
--- the survivor's own inventory, so the exact same objects are still to hand a
--- moment later. That makes the revert exact - the shirt that comes back is the
--- shirt that came off, with its own condition and dirt, not another one like
--- it.
function D.snapshotWorn(character)
    local snapshot = {}
    if not character then return snapshot end

    local wornItems = character:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        if item and not item:isHidden() then
            snapshot[#snapshot + 1] = {
                item = item,
                key = Outfit.locationKey(entry:getLocation()) or Outfit.itemLocationKey(item),
            }
        end
    end

    return snapshot
end

--- Take everything off.
---@return boolean anything
function D.stripAll(character)
    if not character then return false end

    local wornItems = character:getWornItems()
    local anything = false

    -- Backwards: the outermost layer comes off first, which is both the order a
    -- person would use and the order that avoids the engine re-shuffling the
    -- list under the loop.
    for i = wornItems:size() - 1, 0, -1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        if item and not item:isHidden() then
            queue(ISUnequipAction:new(character, item, WEAR_TIME))
            anything = true
        end
    end

    return anything
end

--- Put a snapshot back on exactly: everything in it goes on, everything worn
--- that is not in it comes off. Pressing the button twice therefore lands the
--- survivor exactly where they started, whichever way round they pressed it.
---@return boolean anything
function D.restore(character, snapshot)
    if not character or not snapshot then return false end

    local keep = {}
    for _, entry in ipairs(snapshot) do keep[entry.item] = true end

    local anything = false

    local wornItems = character:getWornItems()
    for i = wornItems:size() - 1, 0, -1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        if item and not item:isHidden() and not keep[item] then
            queue(ISUnequipAction:new(character, item, WEAR_TIME))
            anything = true
        end
    end

    -- From the feet up and from the skin out, the same order as an outfit.
    local ordered = {}
    for _, entry in ipairs(snapshot) do ordered[#ordered + 1] = entry end
    table.sort(ordered, function(a, b)
        local ra, rb = rankOf(a.key), rankOf(b.key)
        if ra == rb then return tostring(a.key) < tostring(b.key) end
        return ra < rb
    end)

    local inventory = character:getInventory()
    for _, entry in ipairs(ordered) do
        local item = entry.item
        -- An item that was dropped, eaten or stolen in the meantime is simply
        -- skipped; the rest of the outfit still goes back on.
        if item and not isWorn(character, item) and item:getContainer() == inventory then
            queue(ISWearClothing:new(character, item, WEAR_TIME))
            anything = true
        end
    end

    return anything
end

--- Does the snapshot still describe what the survivor is wearing? Used to drop
--- a stale revert once the player has dressed themselves by hand.
function D.snapshotStillPending(character, snapshot)
    if not character or not snapshot or #snapshot == 0 then return false end

    local known = {}
    for _, entry in ipairs(snapshot) do known[entry.item] = true end

    local wornItems = character:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local entry = wornItems:get(i)
        local item = entry and entry:getItem()
        -- Something on the survivor that the snapshot never knew about means
        -- they have moved on; the revert no longer describes anything real.
        if item and not item:isHidden() and not known[item] then return false end
    end

    return true
end

return D

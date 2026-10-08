--[[ ============================================================================
    NEQ_ClothingExtra - which body locations an item can actually occupy.

    Most clothing has exactly one body location. Rings, watches and a few other
    items carry "clothing item extra" variants: the same item worn on a
    different location, each variant being its own item type. To know where a
    ring may go, the extra types have to be instantiated once and asked for
    their own body location - hence the cache, which also remembers the misses
    so a broken definition is not re-instantiated every frame.
============================================================================ ]]--

if isServer() then return end

NEQ_ClothingExtra = NEQ_ClothingExtra or {}
local E = NEQ_ClothingExtra

---@type table<string, InventoryItem|boolean>
local _extraCache = {}

--- The location an item goes to when simply worn.
function E.getDefaultBodyLocation(item)
    if not item then return nil end
    return item:getBodyLocation() or item:canBeEquipped()
end

function E.getExtraItemBodyLocation(module, extra)
    local fullType = module .. "." .. extra

    local cached = _extraCache[fullType]
    if cached == false then return nil end
    if cached then return E.getDefaultBodyLocation(cached) end

    local ok, item = pcall(instanceItem, fullType)
    if not ok or not item then
        _extraCache[fullType] = false
        return nil
    end

    _extraCache[fullType] = item
    return E.getDefaultBodyLocation(item)
end

--- Every body location this item may be worn on, as a set.
---@return table<ItemBodyLocation, boolean>
function E.getBodyLocationsForItem(item)
    local map = {}

    local default = E.getDefaultBodyLocation(item)
    if not default then return map end
    map[default] = true

    local extras = item:getClothingItemExtra()
    if extras then
        local module = item:getModule()
        for i = 0, extras:size() - 1 do
            local location = E.getExtraItemBodyLocation(module, extras:get(i))
            if location then map[location] = true end
        end
    end

    return map
end

--- The module-qualified extra type that puts this item on `targetLocation`.
--- ISInventoryPaneContextMenu.onClothingItemExtra needs that string.
---@return string|nil
function E.findExtraOptionForBodyLocation(item, targetLocation)
    local extras = item:getClothingItemExtra()
    if not extras then return nil end

    local module = item:getModule()
    for i = 0, extras:size() - 1 do
        local extra = extras:get(i)
        if E.getExtraItemBodyLocation(module, extra) == targetLocation then
            return moduleDotType(module, extra)
        end
    end

    return nil
end

return E

--[[ ============================================================================
    NEQ_Symbols - the symbols an outfit can wear next to its name.

    The same sheet Project Writing offers on the map, filed the same way, and
    brought over rather than borrowed: Equipment does not depend on Project
    Writing, so the two packs it bundles are copied under our own media folder.

      * the game's own 91 map symbols, read from MapSymbolDefinitions;
      * 46 from ExtraMapSymbols (Wipe, Lexx, B - Rotators), ids "nw:<name>";
      * 95 from Add More Map Symbols (Golem), ids "AmmS<family>_<n>".

    The ids are Project Writing's on purpose: an outfit marked with "nw:shirt"
    means the same shirt in both mods.

    Nothing is registered with MapSymbolDefinitions. The copies are plain
    textures for our own sheet; registering them would put every symbol on the
    map twice when Project Writing is on too.

    An outfit stores only the id. A symbol that cannot be resolved any more - a
    pack removed in a future version - draws nothing, and the slot falls back
    to the hanger.
============================================================================ ]]--

if isServer() then return end

NEQ_Symbols = NEQ_Symbols or {}
local Y = NEQ_Symbols

local OWN = "media/ui/NeatEquipment/"

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
Y.MARKS, Y.PLACES, Y.LOOT, Y.ROAD = "marks", "places", "loot", "road"
Y.TOOLS, Y.WEAPONS, Y.HAZARD, Y.ANIMALS, Y.HOME = "tools", "weapons", "hazard", "animals", "home"

--- Reading order. Marks first: arrows, crosses and stars are what most people
--- reach for.
Y.ORDER = {
    Y.MARKS, Y.PLACES, Y.LOOT, Y.ROAD, Y.TOOLS, Y.WEAPONS, Y.HAZARD, Y.ANIMALS, Y.HOME,
}

local LABELS = {
    [Y.MARKS]   = "UI_NEQ_symbols_marks",
    [Y.PLACES]  = "UI_NEQ_symbols_places",
    [Y.LOOT]    = "UI_NEQ_symbols_loot",
    [Y.ROAD]    = "UI_NEQ_symbols_road",
    [Y.TOOLS]   = "UI_NEQ_symbols_tools",
    [Y.WEAPONS] = "UI_NEQ_symbols_weapons",
    [Y.HAZARD]  = "UI_NEQ_symbols_hazard",
    [Y.ANIMALS] = "UI_NEQ_symbols_animals",
    [Y.HOME]    = "UI_NEQ_symbols_home",
}

function Y.tabLabel(tab)
    local key = LABELS[tab]
    return key and getText(key) or tostring(tab)
end

-- ---------------------------------------------------------------------------
-- Taxonomy (Project Writing's NW_Categories.OF, same filing)
-- ---------------------------------------------------------------------------
local M, P, L, R, T, W, H, A, F =
    Y.MARKS, Y.PLACES, Y.LOOT, Y.ROAD, Y.TOOLS, Y.WEAPONS, Y.HAZARD, Y.ANIMALS, Y.HOME

--- id -> tab, in the order the sheet shows them inside each tab.
local ENTRIES = {
    -- the game's 91
    { "ArrowEast", M }, { "ArrowNorth", M }, { "ArrowSouth", M }, { "ArrowWest", M },
    { "ArrowNorthWest", M }, { "ArrowNorthEast", M }, { "ArrowSouthWest", M }, { "ArrowSouthEast", M },
    { "Asterisk", M }, { "Checkmark", M }, { "Club", M }, { "Diamond", M }, { "Heart", M },
    { "Spade", M }, { "Cross", M }, { "Exclamation", M }, { "Question", M }, { "Circle", M },
    { "Triangle", M }, { "Star", M }, { "FaceDead", M }, { "FaceHappy", M }, { "FaceSad", M },
    { "Heartbroken", M }, { "X", M }, { "Moon", M }, { "Sun", M }, { "Snowflake", M },
    { "Leaf", M }, { "Flower", M }, { "Tree", M }, { "Eye", M }, { "Target", M },

    { "House", P }, { "Skyscraper", P }, { "KnifeFork", P }, { "MedCross", P }, { "Police", P },
    { "Lock", P }, { "Key", P }, { "Door", P }, { "Ladder", P }, { "Columns", P }, { "Tent", P },

    { "Apple", L }, { "Burger", L }, { "Fish", L }, { "Egg", L }, { "Garbage", L },
    { "DollarSign", L }, { "Pill", L }, { "Shirt", L }, { "Book", L }, { "VHS", L },
    { "Lightbulb", L }, { "Waves", L }, { "Baseball", L },

    { "Boat", R }, { "Tire", R }, { "SteeringWheel", R }, { "Fuel", R },

    { "Axe", T }, { "Wrench", T }, { "Hammer", T }, { "Gears", T },

    { "Gun", W }, { "Knife", W }, { "CrossedSwords", W }, { "Bullets", W }, { "Bomb", W }, { "Armor", W },

    { "Fire", H }, { "Lightning", H }, { "Radiation", H }, { "Skull", H }, { "Trap", H }, { "Z", H },

    { "Sheep", A }, { "Rabbit", A }, { "Cow", A }, { "Deer", A }, { "Pig", A }, { "Chicken", A },
    { "Rodent", A }, { "Raccoon", A }, { "Turkey", A }, { "Bird", A }, { "Pawprint", A },

    { "Furnace", F }, { "Bed", F }, { "Anvil", F },

    -- ExtraMapSymbols
    { "nw:arrow1", M }, { "nw:arrow2", M }, { "nw:arrow3", M }, { "nw:arrow4", M },
    { "nw:line1", M }, { "nw:line2", M }, { "nw:line3", M }, { "nw:line4", M },
    { "nw:cross", M }, { "nw:dot", M }, { "nw:important", M }, { "nw:x_small", M }, { "nw:fuel2", M },

    { "nw:axe2", P }, { "nw:school", P }, { "nw:sheriff", P }, { "nw:warehouse", P },
    { "nw:marine", P }, { "nw:meet", P }, { "nw:parachute", P }, { "nw:tent", P },
    { "nw:electricity", P },

    { "nw:ammo", W }, { "nw:helmet", W }, { "nw:pistol", W },

    { "nw:book", L }, { "nw:food", L }, { "nw:loot", L }, { "nw:medic", L },
    { "nw:pills", L }, { "nw:shirt", L }, { "nw:vhs", L }, { "nw:water", L },

    { "nw:boat", R }, { "nw:car", R }, { "nw:fuel", R }, { "nw:helicopter", R }, { "nw:truck", R },

    { "nw:axe", T }, { "nw:pipeWrench", T }, { "nw:sledge", T }, { "nw:wrench", T },

    { "nw:fire", H }, { "nw:radioactive", H },

    { "nw:trashpanda", A },

    { "nw:bed", F },
}

-- Add More Map Symbols, family by family: { family, count, tab for each n }.
local AMMS = {
    { "Sign", { R, R, H, P, H, H, H, H, R, P, P, H, H, P } },
    { "Car", { R, R, R, R, R, R, R, R, R, R, R, R, R, R, R } },
    { "Weapon", { W, W, W, W, W, W, W, W, W, W, W, W, W } },
    { "Tool", { L, L, L, L, T, L, T, T, T, T, T, T, T, T, T, T, T, T, F, R, R, R, T, T, T, T, T, T } },
    { "Furniture", { F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, L, F, P, P, L, L, L } },
}

for _, family in ipairs(AMMS) do
    for n, tab in ipairs(family[2]) do
        ENTRIES[#ENTRIES + 1] = { "AmmS" .. family[1] .. "_" .. n, tab }
    end
end

-- ---------------------------------------------------------------------------
-- Textures
-- ---------------------------------------------------------------------------
--- Where an id's picture lives. Ours by prefix; the game's from its own
--- definitions, with its naming rule as the fallback.
local function pathOf(id)
    if id:sub(1, 3) == "nw:" then return OWN .. "Symbols/" .. id:sub(4) .. ".png" end
    if id:sub(1, 4) == "AmmS" then return OWN .. "SymbolsAMMS/" .. id .. ".png" end

    local ok, path = pcall(function()
        local def = MapSymbolDefinitions.getInstance():getSymbolById(id)
        return def and def:getTexturePath()
    end)
    if ok and path and path ~= "" then return path end
    return "media/ui/LootableMaps/map_" .. string.lower(id) .. ".png"
end

local _textures = {}

--- The texture for an id, or nil. Cached, including the misses.
function Y.texture(id)
    if type(id) ~= "string" or id == "" then return nil end
    local cached = _textures[id]
    if cached ~= nil then return cached or nil end

    local ok, tex = pcall(getTexture, pathOf(id))
    if ok and tex and tex.getWidth and tex:getWidth() > 0 then
        _textures[id] = tex
        return tex
    end
    _textures[id] = false
    return nil
end

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
local _groups = nil

--- tab -> list of ids whose picture resolves. Built once: the files are ours
--- or the game's, and neither changes while the game runs.
function Y.groups()
    if _groups then return _groups end
    _groups = {}
    for _, entry in ipairs(ENTRIES) do
        local id, tab = entry[1], entry[2]
        if Y.texture(id) then
            _groups[tab] = _groups[tab] or {}
            table.insert(_groups[tab], id)
        end
    end
    return _groups
end

--- The tabs that have at least one symbol, in reading order.
function Y.tabs()
    local groups, out = Y.groups(), {}
    for _, tab in ipairs(Y.ORDER) do
        if groups[tab] and #groups[tab] > 0 then out[#out + 1] = tab end
    end
    return out
end

--- Which tab an id is filed under, or nil.
function Y.tabOf(id)
    for _, entry in ipairs(ENTRIES) do
        if entry[1] == id then return entry[2] end
    end
    return nil
end

return Y

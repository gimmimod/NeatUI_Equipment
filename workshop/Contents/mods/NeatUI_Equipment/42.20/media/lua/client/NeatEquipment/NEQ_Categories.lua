--[[ ============================================================================
    NEQ_Categories - what kind of thing an item is, for putting it away.

    The container swap (NEQ_Dresser) puts a piece of the old outfit only into a
    container that already holds something of the same kind. "The same kind"
    has two answers here, a narrow one and a broad one:

      exact   the game's display category - the word in the inventory's
              Category column: Clothing, Accessory, ProtectiveGear, ...
      family  the categories that belong on the same shelf.

    Why both. The display categories cut across what a player sees as one
    kind of thing: a baseball cap is Clothing, a Spiffo cap is a Memento, a
    batting helmet is ProtectiveGear, and all three are hats (counted from the
    game's own scripts: 481 Clothing, 349 Accessory, 290 ProtectiveGear and 92
    Memento among the wearables). A wardrobe of shirts is the right place for
    the helmet too. The weapons are split the same way, into fifteen
    "...Weapon" categories.

    The families:

      clothes      Clothing, ProtectiveGear, and anything else that is worn as
                   clothing - a worn Memento, a mod's own category
      accessories  Accessory, Jewelry: watches, rings, glasses
      weapons      Weapon and every "...Weapon" category, and any HandWeapon
      bags         Bag, and anything that is a container
      otherwise    the exact category is its own family: LightSource,
                   Communications, Camping, ...

    Mods. A category the base game does not have (VANILLA below, read from
    the IGUI_ItemCat_ translations) says nothing about the item, so the item
    speaks for itself: a container is a bag, a HandWeapon is a weapon, and
    something with a body location is clothes. That is how a mod's "Uniform"
    shirt lands with the shirts instead of staying in the inventory. An item
    with no display category at all is judged the same way, and failing that
    takes its type category (getCategory).

    Only reads items. Nothing here moves anything.
============================================================================ ]]--

if isServer() then return end

local Outfit = require("NeatEquipment/NEQ_Outfit")

local K = {}

-- Every display category the base game names (IGUI_ItemCat_*, build 42.20).
local VANILLA = {}
for category in string.gmatch([[
    Accessory AlarmClock Ammo Animal AnimalPart AnimalPartWeapon Appearance
    Badger Bag Bandage Bear Beaver BrokenWeapon Bug Bunny Camping Cartography
    Clothing Communications Container Cooking CookingWeapon Corpse Devices Dog
    Duck Ears Electronics Entertainment Explosives Eye FireSource FirstAid
    FirstAidWeapon Fishing FishingWeapon Food Fox Frog Furniture Gardening
    GardeningWeapon Generic Goblin Hedgehog Hidden Household HouseholdWeapon
    Instrument InstrumentWeapon Item Junk JunkWeapon LightSource Literature
    MakeUp Material MaterialWeapon Memento Mole Paint ProtectiveGear Raccoon
    RecipeResource Security SkillBook Spider Sports SportsWeapon Squirrel Tail
    Teddy Tool ToolWeapon Trapping Unknown VehicleMaintenance
    VehicleMaintenanceWeapon Water WaterContainer Weapon WeaponCrafted
    WeaponImprovised WeaponPart Wound ZedDmg
]], "%S+") do
    VANILLA[category] = true
end

-- Categories that share a shelf. The weapons are matched by name, all but the
-- parts: a scope is not something a knife belongs next to.
local FAMILY = {
    Clothing = "clothes",
    ProtectiveGear = "clothes",
    Accessory = "accessories",
    Jewelry = "accessories",
    Bag = "bags",
    Container = "bags",
    WeaponPart = "WeaponPart",
}

-- Worn things whose category is about something else: a worn Memento is still
-- a cap or a pair of glasses, so it counts as clothes when it is wearable.
local WORN_AS_CLOTHES = { Memento = true }

local function call(item, method)
    local ok, value = pcall(function() return item[method](item) end)
    if ok then return value end
    return nil
end

local function isWeaponCategory(category)
    return category == "Weapon" or string.sub(category, -6) == "Weapon"
        or string.sub(category, 1, 6) == "Weapon"
end

local function isWearable(item)
    return Outfit.itemLocationKey(item) ~= nil
end

--- What the item is, whatever its category says. nil when nothing tells.
local function familyByNature(item)
    if Outfit.isBag(item) then return "bags" end
    if instanceof(item, "HandWeapon") then return "weapons" end
    if isWearable(item) then return "clothes" end
    return nil
end

--- The two answers for one item.
---@return string|nil exact  display category, or the type category without one
---@return string|nil family
function K.of(item)
    if not item then return nil, nil end

    local category = call(item, "getDisplayCategory")
    if type(category) ~= "string" or category == "" then category = nil end

    if category then
        -- The table and the weapon names first: they hold for a mod that
        -- borrows a word the game does not use, like Jewelry.
        local family = FAMILY[category]
        if not family and isWeaponCategory(category) then family = "weapons" end
        if family then return category, family end

        if VANILLA[category] then
            if WORN_AS_CLOTHES[category] and isWearable(item) then return category, "clothes" end
            return category, category
        end
    end

    -- A mod's category, or none: the item itself decides the family.
    local family = familyByNature(item)
    if not category then
        local plain = call(item, "getCategory")
        category = (type(plain) == "string" and plain ~= "") and plain or nil
    end
    return category, family or category
end

--- Tally of a container's items, by exact category and by family.
---@return table { exact = { [category] = n }, family = { [family] = n } }
function K.count(container)
    local counts = { exact = {}, family = {} }
    local ok, items = pcall(function() return container:getItems() end)
    if not ok or not items then return counts end
    for i = 0, items:size() - 1 do
        K.add(counts, items:get(i))
    end
    return counts
end

--- Adds one item to a tally made by K.count.
function K.add(counts, item)
    local exact, family = K.of(item)
    if exact then counts.exact[exact] = (counts.exact[exact] or 0) + 1 end
    if family then counts.family[family] = (counts.family[family] or 0) + 1 end
end

return K

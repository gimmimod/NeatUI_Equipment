--[[ ============================================================================
    NEQ_SlotDefs - which body locations each visible slot stands for, and where
    that slot sits around the avatar.

    Layout is declared as (column, row) rather than pixel offsets: the panel is
    resizable, so NEQ_Body turns these into coordinates from the current scale.
    The 3D preview occupies the middle, flanked by two columns of slots.

        left            centre            right
        ----------------------------------------
        head          [           ]      back
        face          [           ]      jewelry
        torso         [  avatar   ]      right hand
        vest          [    3D     ]      left hand
        waist         [           ]      feet
        legs          [           ]
                    primary   secondary

    Order inside bodyLocations still matters: the first location that holds an
    item is the one whose icon fills the slot, so the outermost layer of clothing
    ends up on top. That ordering is deliberate and play-tested: change it and
    the wrong garment starts wearing the slot's face.
============================================================================ ]]--

if isServer() then return end

---@class NEQSlotDefinition
---@field name string          translation key
---@field column string        "left" | "right"
---@field row integer          1-based row inside the column
---@field bodyLocations ItemBodyLocation[]

---@type NEQSlotDefinition[]
local SlotDefinitions = {
    {
        name = "UI_NEQ_slot_head", column = "left", row = 1,
        bodyLocations = {
            ItemBodyLocation.HAT, ItemBodyLocation.FULL_HAT, ItemBodyLocation.SCARF,
            ItemBodyLocation.NECK, ItemBodyLocation.NECK_TEXTURE,
        },
    },
    {
        name = "UI_NEQ_slot_face", column = "left", row = 2,
        bodyLocations = {
            ItemBodyLocation.SCBA, ItemBodyLocation.SCBANOTANK, ItemBodyLocation.MASK,
            ItemBodyLocation.MASK_EYES, ItemBodyLocation.MASK_FULL, ItemBodyLocation.EYES,
            ItemBodyLocation.LEFT_EYE, ItemBodyLocation.RIGHT_EYE,
        },
    },
    {
        name = "UI_NEQ_slot_torso", column = "left", row = 3,
        bodyLocations = {
            ItemBodyLocation.FULL_ROBE, ItemBodyLocation.BOILERSUIT, ItemBodyLocation.FULL_SUIT,
            ItemBodyLocation.FULL_SUIT_HEAD, ItemBodyLocation.FULL_SUIT_HEAD_SCBA,
            ItemBodyLocation.FULL_TOP, ItemBodyLocation.BATH_ROBE, ItemBodyLocation.JACKET,
            ItemBodyLocation.JACKET_BULKY, ItemBodyLocation.JACKET_DOWN, ItemBodyLocation.JACKET_HAT,
            ItemBodyLocation.JACKET_HAT_BULKY, ItemBodyLocation.JACKET_SUIT, ItemBodyLocation.JERSEY,
            ItemBodyLocation.SWEATER, ItemBodyLocation.SWEATER_HAT, ItemBodyLocation.DRESS,
            ItemBodyLocation.LONG_DRESS, ItemBodyLocation.VEST_TEXTURE, ItemBodyLocation.TORSO1LEGS1,
            ItemBodyLocation.TORSO1, ItemBodyLocation.SHIRT, ItemBodyLocation.SHORT_SLEEVE_SHIRT,
            ItemBodyLocation.TSHIRT, ItemBodyLocation.TANK_TOP, ItemBodyLocation.UNDERWEAR_TOP,
        },
    },
    {
        name = "UI_NEQ_slot_vest", column = "left", row = 4,
        bodyLocations = {
            ItemBodyLocation.SATCHEL, ItemBodyLocation.WEBBING, ItemBodyLocation.SHOULDER_HOLSTER,
            ItemBodyLocation.AMMO_STRAP, ItemBodyLocation.TORSO_EXTRA_VEST_BULLET,
            ItemBodyLocation.TORSO_EXTRA_VEST, ItemBodyLocation.TORSO_EXTRA,
        },
    },
    {
        name = "UI_NEQ_slot_waist", column = "left", row = 5,
        bodyLocations = {
            ItemBodyLocation.FANNY_PACK_FRONT, ItemBodyLocation.FANNY_PACK_BACK,
            ItemBodyLocation.BELT, ItemBodyLocation.BELT_EXTRA,
        },
    },
    {
        name = "UI_NEQ_slot_legs", column = "left", row = 6,
        bodyLocations = {
            ItemBodyLocation.LONG_SKIRT, ItemBodyLocation.SKIRT, ItemBodyLocation.PANTS,
            ItemBodyLocation.PANTS_EXTRA, ItemBodyLocation.PANTS_SKINNY, ItemBodyLocation.SHORT_PANTS,
            ItemBodyLocation.SHORTS_SHORT, ItemBodyLocation.LEGS5, ItemBodyLocation.LEGS1,
            ItemBodyLocation.UNDERWEAR, ItemBodyLocation.UNDERWEAR_BOTTOM,
            ItemBodyLocation.UNDERWEAR_EXTRA1, ItemBodyLocation.UNDERWEAR_EXTRA2,
        },
    },

    {
        name = "UI_NEQ_slot_back", column = "right", row = 1,
        bodyLocations = { ItemBodyLocation.BACK, ItemBodyLocation.TAIL },
    },
    {
        name = "UI_NEQ_slot_jewelry", column = "right", row = 2,
        bodyLocations = {
            ItemBodyLocation.NECKLACE, ItemBodyLocation.NECKLACE_LONG, ItemBodyLocation.EARS,
            ItemBodyLocation.EAR_TOP, ItemBodyLocation.NOSE, ItemBodyLocation.BELLY_BUTTON,
        },
    },
    {
        name = "UI_NEQ_slot_right_hand", column = "right", row = 3,
        bodyLocations = {
            ItemBodyLocation.HANDS, ItemBodyLocation.HANDS_RIGHT, ItemBodyLocation.RIGHT_WRIST,
            ItemBodyLocation.RIGHT_RING_FINGER, ItemBodyLocation.RIGHT_MIDDLE_FINGER,
        },
    },
    {
        name = "UI_NEQ_slot_left_hand", column = "right", row = 4,
        bodyLocations = {
            ItemBodyLocation.HANDS, ItemBodyLocation.HANDS_LEFT, ItemBodyLocation.LEFT_WRIST,
            ItemBodyLocation.LEFT_MIDDLE_FINGER, ItemBodyLocation.LEFT_RING_FINGER,
        },
    },
    {
        name = "UI_NEQ_slot_feet", column = "right", row = 5,
        bodyLocations = {
            ItemBodyLocation.ANKLE_HOLSTER, ItemBodyLocation.SHOES, ItemBodyLocation.SOCKS,
        },
    },
}

-- ---------------------------------------------------------------------------
-- Optional TwisTonFire Clothing integration.
--
-- Exclusivity is read from the live Human BodyLocationGroup, so all we add here
-- is which visual slot each custom TTF location belongs to. No dependency is
-- introduced: with the namespace absent every lookup returns nil and the entries
-- are skipped.
-- ---------------------------------------------------------------------------
local function definition(name)
    for _, def in ipairs(SlotDefinitions) do
        if def.name == name then return def end
    end
    return nil
end

local function contains(list, location)
    if not list or not location then return false end
    for _, existing in ipairs(list) do
        if existing == location then return true end
    end
    return false
end

local function insertBefore(list, anchor, location)
    if not list or not location or contains(list, location) then return end
    for i, existing in ipairs(list) do
        if existing == anchor then
            table.insert(list, i, location)
            return
        end
    end
    table.insert(list, location)
end

local function insertAfterMany(list, anchor, locations)
    if not list then return end

    local anchorIndex = nil
    for i, existing in ipairs(list) do
        if existing == anchor then anchorIndex = i break end
    end

    local at = anchorIndex and (anchorIndex + 1) or (#list + 1)
    for _, location in ipairs(locations) do
        if location and not contains(list, location) then
            table.insert(list, at, location)
            at = at + 1
        end
    end
end

local function ttfLocation(name)
    local ttf = rawget(_G, "TTF")
    local locations = ttf and ttf.ItemBodyLocation
    return locations and locations[name] or nil
end

local head = definition("UI_NEQ_slot_head")
if head then
    -- Hats stay the dominant head item; bandages and wigs stack underneath.
    insertAfterMany(head.bodyLocations, ItemBodyLocation.FULL_HAT, {
        ttfLocation("HEAD_BANDAGE"),
        ttfLocation("HEADEXTRAPLUS"),
    })
end

local torso = definition("UI_NEQ_slot_torso")
if torso then
    insertAfterMany(torso.bodyLocations, ItemBodyLocation.BATH_ROBE, {
        ttfLocation("CLOAK"),
        ttfLocation("PONCHO_UP"),
        ttfLocation("PONCHO_DOWN"),
        ttfLocation("JACKET_HAT"),
        ttfLocation("JACKET"),
        ttfLocation("JACKET_SUIT_SPC"),
    })
    insertAfterMany(torso.bodyLocations, ItemBodyLocation.SWEATER_HAT, {
        ttfLocation("SWEATER_DRESS"),
    })
    -- Underwear / lingerie layers belong at the bottom of the stack so a shirt
    -- stays the icon the slot shows.
    insertBefore(torso.bodyLocations, ItemBodyLocation.UNDERWEAR_TOP, ttfLocation("BODYSUIT"))
    insertBefore(torso.bodyLocations, ItemBodyLocation.UNDERWEAR_TOP, ttfLocation("LINGERIE_ARMS"))
    insertBefore(torso.bodyLocations, ItemBodyLocation.UNDERWEAR_TOP, ttfLocation("LINGERIE_TOP"))
    insertBefore(torso.bodyLocations, ItemBodyLocation.UNDERWEAR_TOP, ttfLocation("UNDERWEAR_TOP3D"))
end

local legs = definition("UI_NEQ_slot_legs")
if legs then
    insertBefore(legs.bodyLocations, ItemBodyLocation.PANTS, ttfLocation("PANTS"))
    insertAfterMany(legs.bodyLocations, ItemBodyLocation.LEGS1, {
        ttfLocation("RIGHT_LEG"),
        ttfLocation("LEFT_LEG"),
    })
    insertAfterMany(legs.bodyLocations, ItemBodyLocation.UNDERWEAR_BOTTOM, {
        ttfLocation("LINGERIE_BOTTOM"),
        ttfLocation("UNDERWEAR_BOTTOM3D"),
    })
end

local rightHand = definition("UI_NEQ_slot_right_hand")
if rightHand then
    insertAfterMany(rightHand.bodyLocations, ItemBodyLocation.RIGHT_WRIST, {
        ttfLocation("WRISTBAND1"),
    })
end

return SlotDefinitions

--[[ ============================================================================
    NEQ_OutfitStats - how well a saved outfit protects and keeps warm, part by
    part of the body.

    The character window measures the survivor as they stand. This measures an
    outfit, worn or not, with the engine's own arithmetic re-done on the
    outfit's garments (read with METODO/tools/bytecode.js):

      protection   IsoGameCharacter.getBodyPartClothingDefense. For each part,
                   every garment that covers it and has no hole there adds
                   Clothing:getDefForPart(part, bite, bullet); the sum stops at
                   100. Bite and scratch, the two columns of the character
                   window.

      warmth       Thermoregulator.updateClothing + ThermalNode.calculateInsulation.
                   A garment with insulation or wind resistance joins the
                   node of every part it covers (a hat or a mask that covers
                   nothing joins the head). For each garment without a hole on
                   that part:

                       condition  = 0.5 + 0.5 * clamp(condition / 100)
                       insulation += (2x + 0.5x^3) * condition   x = its insulation
                       wind       += (y + 0.5y^2)  * condition   y = its wind resistance

                   (Temperature.getTrueInsulationValue / ...WindresistanceValue),
                   and then 0.05 per garment on the node for each of the two.
                   What the character window's bar shows is that times the
                   node's multiplier (Thermoregulator.initNodes), clamped to 0..1.
                   Wetness is left out: an outfit is measured dry.

    The garments are the outfit's own when they can be found - on the survivor,
    in the bags, in reach, the saved one first, exactly as the wardrobe would
    put them on - so a torn jacket counts as torn. One nowhere to be found is
    measured as a new one of the same type.
============================================================================ ]]--

if isServer() then return end

local Outfit = require("NeatEquipment/NEQ_Outfit")
local Gather = require("NeatEquipment/NEQ_Gather")

local S = {}

-- BodyPartType 0..16: the parts the character window lists. MAX is 17.
S.PART_COUNT = 17

-- ThermalNode's UI multiplier, set per part in Thermoregulator.initNodes.
local UI_MULTIPLIER = {
    Hand_L = 1, Hand_R = 1, ForeArm_L = 0.25, ForeArm_R = 0.25,
    UpperArm_L = 0.25, UpperArm_R = 0.25, Torso_Upper = 0.25, Torso_Lower = 0.25,
    Head = 1, Neck = 0.5, Groin = 0.5, UpperLeg_L = 0.5, UpperLeg_R = 0.5,
    LowerLeg_L = 0.5, LowerLeg_R = 0.5, Foot_L = 0.5, Foot_R = 0.5,
}

local function clamp01(v) return math.max(0, math.min(1, v)) end

--- A number from a Java getter, or 0.
local function number(item, method)
    local ok, v = pcall(function() return item[method](item) end)
    return (ok and type(v) == "number") and v or 0
end

--- The garments of an outfit, as items. Only clothing: bags and hotbar things
--- neither protect nor warm (the engine counts Clothing only).
function S.items(outfit, character, playerNum)
    local items = {}
    if not outfit then return items end

    local index = Gather.build(character, playerNum)
    local used = {}
    for key, descriptor in pairs(outfit.worn or {}) do
        if Outfit.isOutfitLocation(key) then
            local item = Gather.find(index, descriptor, used)
            if item then
                used[item] = true
            else
                local ok, fresh = pcall(function() return instanceItem(descriptor.type) end)
                item = ok and fresh or nil
            end
            if item and instanceof(item, "Clothing") then items[#items + 1] = item end
        end
    end
    return items
end

--- The part indices (0..16) a garment covers, as the engine lists them.
local function coveredParts(item)
    local parts = {}
    pcall(function()
        local types = item:getBloodClothingType()
        if not types then return end
        local list = BloodClothingType.getCoveredParts(types)
        if not list then return end
        for i = 0, list:size() - 1 do
            local index = list:get(i):index()
            if index >= 0 and index < S.PART_COUNT then parts[#parts + 1] = index end
        end
    end)
    return parts
end

--- Is there a hole in this garment over part `index`?
local function holed(item, index)
    local ok, hole = pcall(function()
        return item:getVisual():getHole(BloodBodyPartType.FromIndex(index))
    end)
    return ok and type(hole) == "number" and hole > 0
end

--- Bite and scratch defence per part, 0..100, rounded as the character window
--- rounds them.
---@return table { bite = { [0..16] = n }, scratch = { [0..16] = n } }
function S.protection(items)
    local bite, scratch = {}, {}
    for i = 0, S.PART_COUNT - 1 do bite[i], scratch[i] = 0, 0 end

    for _, item in ipairs(items) do
        for _, index in ipairs(coveredParts(item)) do
            if not holed(item, index) then
                local part = BloodBodyPartType.FromIndex(index)
                local okBite, b = pcall(function() return item:getDefForPart(part, true, false) end)
                local okScratch, s = pcall(function() return item:getDefForPart(part, false, false) end)
                if okBite and type(b) == "number" then bite[index] = bite[index] + b end
                if okScratch and type(s) == "number" then scratch[index] = scratch[index] + s end
            end
        end
    end

    for i = 0, S.PART_COUNT - 1 do
        bite[i] = math.floor(math.min(bite[i], 100) + 0.5)
        scratch[i] = math.floor(math.min(scratch[i], 100) + 0.5)
    end
    return { bite = bite, scratch = scratch }
end

--- The nodes a warm garment joins: the parts it covers, or the head for a hat
--- or a mask that covers none (Thermoregulator.updateClothing).
local function thermalParts(item)
    local parts = coveredParts(item)
    if #parts > 0 then return parts end

    local ok, onHead = pcall(function()
        local location = item:getBodyLocation()
        return location ~= nil and (location == ItemBodyLocation.HAT or location == ItemBodyLocation.MASK)
    end)
    if ok and onHead then return { BodyPartType.ToIndex(BodyPartType.Head) } end
    return parts
end

--- Insulation and wind resistance per part, as the character window's bars
--- show them: 0..1.
---@return table { insulation = { [0..16] = v }, wind = { [0..16] = v } }
function S.warmth(items)
    local insulation, wind, layers = {}, {}, {}
    for i = 0, S.PART_COUNT - 1 do insulation[i], wind[i], layers[i] = 0, 0, 0 end

    for _, item in ipairs(items) do
        local x = number(item, "getInsulation")
        local y = number(item, "getWindresistance")
        if x > 0 or y > 0 then
            local condition = 0.5 + 0.5 * clamp01(number(item, "getCurrentCondition") * 0.01)
            local trueInsulation = (2 * x + 0.5 * x * x * x) * condition
            local trueWind = (y + 0.5 * y * y) * condition
            for _, index in ipairs(thermalParts(item)) do
                layers[index] = layers[index] + 1
                if not holed(item, index) then
                    insulation[index] = insulation[index] + trueInsulation
                    wind[index] = wind[index] + trueWind
                end
            end
        end
    end

    for i = 0, S.PART_COUNT - 1 do
        local name = BodyPartType.ToString(BodyPartType.FromIndex(i))
        local multiplier = UI_MULTIPLIER[name] or 0.5
        local extra = layers[i] * 0.05
        insulation[i] = clamp01((insulation[i] + extra) * multiplier)
        wind[i] = clamp01((wind[i] + extra) * multiplier)
    end
    return { insulation = insulation, wind = wind }
end

return S

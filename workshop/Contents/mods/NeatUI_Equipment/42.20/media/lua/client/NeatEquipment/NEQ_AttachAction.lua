--[[ ============================================================================
    NEQ_AttachAction - put one item on one hotbar slot, in queue order.

    Attaching is instant in vanilla: ISHotbar:attachItem is called straight from
    a click. That is no use here, because the belt or holster that *provides*
    the slot is itself being put on by a timed action further up the queue.
    Calling attachItem immediately would aim at a slot that does not exist yet.

    So the attach is wrapped in the shortest possible timed action, purely to
    hold its place in line. It re-reads the hotbar when it runs rather than
    trusting the slot index captured when the outfit was resolved - by then a
    belt has appeared and every index after it has moved.
============================================================================ ]]--

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISAttachItemHotbar"
require "TimedActions/ISDetachItemHotbar"

NEQ_AttachAction = ISBaseTimedAction:derive("NEQ_AttachAction")

--[[ The game's own hotbar actions, with their gesture chosen when they start.

    ISAttachItemHotbar and ISDetachItemHotbar last "until the animation says
    so": their duration is -1, and they finish on the animation's
    attachConnect / detachConnect event. Which animation plays is a variable on
    the character, AttachAnim, and vanilla sets it when the action is QUEUED
    (ISHotbar:attachItem, ISHotbar:removeItem).

    That is fine for one click. It is not for a queue:

      * a detach queued with no AttachAnim at all - ours were, straight from
        ISDetachItemHotbar:new - plays no animation, never gets its event, and
        never ends. Every action queued after it waits for ever: the outfit,
        a transfer by hand, equipping from the panel. Pressing Esc cancels the
        running action, which is why going through the pause menu "fixed" it;
      * several attaches queued in a row all start with the gesture of the
        last one queued.

    So the variable is set in the action's own start(). The engine looks the
    method up on the action table before its class (KahluaTableImpl.rawget),
    so a start() on the instance wraps the class one for that action only.

    And a net under it: if the event has still not come after GESTURE_TIMEOUT
    - a slot from another mod with no animation for it, say - the action is
    completed anyway. perform() does the attaching and detaching by itself;
    the event only times it with the hand. A late hand is better than a queue
    that never moves again.
]]
local GESTURE_TIMEOUT_MS = 3000

local function gestureOnStart(action, character, item, slotDef)
    local hotbar = getPlayerHotbar(character:getPlayerNum())
    if not action or not hotbar then return action end

    local start, update = action.start, action.update
    action.start = function(self)
        self.neqStartedAt = getTimestampMs()
        pcall(function() hotbar:setAttachAnim(item, slotDef) end)
        return start(self)
    end
    action.update = function(self)
        if self.neqStartedAt and getTimestampMs() - self.neqStartedAt > GESTURE_TIMEOUT_MS then
            self.neqStartedAt = nil
            self:forceComplete()
            return
        end
        return update(self)
    end
    return action
end

--- Take `item` off the hotbar, animated.
function NEQ_AttachAction.newDetach(character, item)
    return gestureOnStart(ISDetachItemHotbar:new(character, item), character, item, nil)
end

--- Hang `item` on hotbar slot `index`, animated. `attachment` is the model
--- attachment point, `slotDef` the slot's definition.
function NEQ_AttachAction.newAttach(character, item, attachment, index, slotDef)
    return gestureOnStart(ISAttachItemHotbar:new(character, item, attachment, index, slotDef),
        character, item, slotDef)
end

function NEQ_AttachAction:new(character, item, slotType)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.slotType = slotType
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end

function NEQ_AttachAction:isValid()
    if not self.item or not self.slotType then return false end
    -- The item has to be in the survivor's hands-on reach; a fetch earlier in
    -- the queue is what puts it there.
    local container = self.item:getContainer()
    return container ~= nil and container == self.character:getInventory()
end

function NEQ_AttachAction:update() end
function NEQ_AttachAction:start() end
function NEQ_AttachAction:stop() ISBaseTimedAction.stop(self) end

function NEQ_AttachAction:perform()
    local hotbar = getPlayerHotbar(self.character:getPlayerNum())
    if hotbar then
        for index, slot in ipairs(hotbar.availableSlot) do
            if slot.slotType == self.slotType and not hotbar.attachedItems[index] then
                local definition = slot.def
                local attachments = definition and definition.attachments
                local wanted = self.item:getAttachmentType()
                if attachments and wanted then
                    for attachmentType, attachment in pairs(attachments) do
                        if attachmentType == wanted then
                            local replacement = hotbar.replacements
                                and hotbar.replacements[wanted]
                            if replacement ~= "null" then
                                -- Like ISHotbar:attachItem: a bag on the back
                                -- moves what hangs there somewhere else.
                                if definition.name == "Back" and replacement then
                                    attachment = replacement
                                end
                                -- Queued right after this action, so it plays
                                -- before the next piece of the outfit, with its
                                -- own gesture (see gestureOnStart).
                                --
                                -- Il pcall resta - questo gira dentro un'azione
                                -- a tempo, e un errore qui fermerebbe tutta la
                                -- coda del completo - ma non zitto: e' proprio
                                -- in rete che l'aggancio puo' fallire per
                                -- davvero, e senza questa riga sarebbe un pezzo
                                -- che non si aggancia e non dice niente
                                -- (METODO/03, lezione 22).
                                local ok, err = pcall(function()
                                    local action = NEQ_AttachAction.newAttach(self.character,
                                        self.item, attachment, index, definition)
                                    if not ISTimedActionQueue.addAfter(self, action) then
                                        ISTimedActionQueue.add(action)
                                    end
                                end)
                                if not ok then
                                    print("[NeatUI Equipment] aggancio alla barra rapida fallito per "
                                        .. tostring(self.item and self.item:getFullType())
                                        .. ": " .. tostring(err))
                                end
                            end
                            break
                        end
                    end
                end
                break
            end
        end
    end

    ISBaseTimedAction.perform(self)
end

return NEQ_AttachAction

--[[ ============================================================================
    NEQ_Collapse - roll a window up to its header, the Rocco way.

    A copy of Neat Rocco's UI NR_CollapseUtils, rule for rule, so the arrow in
    the wardrobe header behaves exactly like the one on Rocco's panels (the
    character window, the search panel):

      * the arrow points down while the window is pinned open;
      * clicking it arms the roll-up and turns it to point right - nothing
        disappears yet: the body goes once the pointer has been away from the
        window for a moment (the same weighted frame counter as vanilla
        ISCollapsableWindow, and the same threshold: Rocco's own setting when
        Rocco is installed, vanilla's 20 otherwise);
      * the pointer back over the header rolls it down again, and it rolls up
        again when the pointer leaves;
      * clicking the arrow again pins it open.

    The intent (_isCollapsed) and what is on screen (_bodyShown) are two flags,
    as in Rocco: the arrow shows the intent, not the passing peek.

    What differs is only the plumbing: the header height is the window's own
    (headerHeight()), the button is the window's `collapseButton`, and a window
    can hear about the body coming and going through onCollapseBody(shown) -
    the wardrobe closes its symbol sheet and commits a rename there.

    setMaxDrawHeight is what hides the body. The engine then skips every child
    that starts below the header and ignores the mouse down there
    (UIElement.render / onMouseDown); the window's own drawing it leaves alone,
    so the window checks isBodyVisible before drawing its body.
============================================================================ ]]--

if isServer() then return end

local Style = require("NeatEquipment/NEQ_Style")

local C = {}

-- Rocco's threshold when his mod is there, so the two kinds of window roll up
-- after the same pause; vanilla's otherwise (ISCollapsableWindow).
local function threshold()
    local config = rawget(_G, "NR_Config")
    return (config and tonumber(config.collapseThreshold)) or 20
end

local function headerHeight(panel)
    return panel.headerHeight and panel:headerHeight() or 16
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------
local function showBody(panel)
    panel._bodyShown = true
    panel._collapseTimer = 0
    panel:clearMaxDrawHeight()
    if panel.onCollapseBody then panel:onCollapseBody(true) end
end

local function hideBody(panel)
    panel._bodyShown = false
    panel._collapseTimer = 0
    panel:setMaxDrawHeight(headerHeight(panel))
    if panel.onCollapseBody then panel:onCollapseBody(false) end
end

local function setButton(panel, expanded)
    local button = panel.collapseButton
    if not button then return end
    Style.setButtonIcon(button, Style.tex(expanded and "collapseOpen" or "collapseClosed"))
    Style.setButtonActive(button, expanded and Style.accent or nil)
end

local function anyMouseButtonDown()
    return isMouseButtonDown(0) or isMouseButtonDown(1) or isMouseButtonDown(2)
end

-- Vanilla onMouseMove + uncollapse, scoped to the intent flag.
local function handleMouseMove(panel)
    if not panel._isCollapsed then return end
    panel._collapseTimer = 0
    if panel._bodyShown then return end
    if anyMouseButtonDown() then return end
    if panel:getMouseY() < headerHeight(panel) then
        showBody(panel)
    end
end

-- Vanilla onMouseMoveOutside auto-collapse.
local function handleMouseMoveOutside(panel)
    if not panel._isCollapsed then return end
    if not panel._bodyShown then return end
    local mx, my = panel:getMouseX(), panel:getMouseY()
    if mx < 0 or my < 0 or mx > panel:getWidth() or my > panel:getHeight() then
        local gt = getGameTime()
        local tm = gt:getTrueMultiplier()
        if tm > 0 then
            panel._collapseTimer = panel._collapseTimer + (gt:getMultiplier() / tm) / 0.8
        end
        if panel._collapseTimer > threshold() then
            hideBody(panel)
        end
    end
end

-- ---------------------------------------------------------------------------
-- The contract
-- ---------------------------------------------------------------------------
--- Call once, when the window is made. Wraps the instance's onMouseMove and
--- onMouseMoveOutside, so the window must not route one into the other: the
--- inside handler resets the timer the outside one is counting.
function C.init(panel)
    panel._isCollapsed = false
    panel._bodyShown = true
    panel._collapseTimer = 0

    local origMove = panel.onMouseMove
    panel.onMouseMove = function(self, dx, dy)
        local result = origMove and origMove(self, dx, dy)
        handleMouseMove(self)
        return result
    end

    local origMoveOut = panel.onMouseMoveOutside
    panel.onMouseMoveOutside = function(self, dx, dy)
        local result = origMoveOut and origMoveOut(self, dx, dy)
        handleMouseMoveOutside(self)
        return result
    end
end

--- Guard for drawing: false while the window is rolled up to its header.
function C.isBodyVisible(panel)
    return panel._bodyShown ~= false
end

--- Is the roll-up armed? This is what the arrow shows.
function C.isCollapsed(panel)
    return panel._isCollapsed == true
end

--- The arrow's click. Arming does not hide anything by itself: the body goes
--- when the pointer leaves, as in vanilla collapse() with pin off.
function C.onClickCollapse(panel)
    if panel._isCollapsed then
        panel._isCollapsed = false
        showBody(panel)
        setButton(panel, true)
    else
        panel._isCollapsed = true
        panel._collapseTimer = 0
        setButton(panel, false)
    end
end

--- Puts the arrow in the state the flags say. For a button made after init.
--- Like Rocco's, the state outlives closing the window: a wardrobe rolled up
--- to its header comes back that way.
function C.refreshButton(panel)
    setButton(panel, not panel._isCollapsed)
end

return C

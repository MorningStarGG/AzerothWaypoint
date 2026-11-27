local path = dofile("tests/native_path.lua")
local f = assert(loadfile("tests/controller_fixture.lua"))()
local NS, Pad, Frame = f.NS, f.Pad, f.FrameMethods
function Frame:SetPropagateKeyboardInput() end
function Frame:LockHighlight() self.highlightLocked = true end
function Frame:UnlockHighlight() self.highlightLocked = false end

-- Use the installed Button/DressButton methods, including SetOff's independent
-- IsMouseOver sample. Only the rendering primitives are reduced: instant light
-- makes a stale native state visible without attributing it to an animation.
local input = assert(io.open(path("forever", "DaylightUI/Options/Widgets.lua")))
local source = input:read("*a"); input:close()
local first = assert(source:find("function W.Button(parent, text, height)", 1, true))
local last = assert(source:find("-- A button that opens a menu:", first, true))
local dress = assert(source:find("function W.DressButton(b, text)", last, true))
local dressEnd = assert(source:find("-- The glow on a window", dress, true))
local widgets = {TextColor = function() end}
function widgets.ButtonLook(button)
    button.text = f.Frame(button)
    button.Paint = function() end
    button.Light = function(on)
        button.lit = on == true and not button.off
        if button.lit then button:LockHighlight() else button:UnlockHighlight() end
    end
    button.Hover = function(on)
        button.hoverCalls = (button.hoverCalls or 0) + 1
        button.Light(on)
    end
end
local native = assert(loadstring(source:sub(first, last - 1) .. source:sub(dress, dressEnd - 1)))
setfenv(native, setmetatable({W = widgets, buttons = {}, DUI = DaylightUI, C = {value = {}}, BTN = {text = {}}}, {__index = _G}))
native()
local pointerIndex = 4
f.api.Button = function(parent, text, height)
    local button = widgets.Button(parent, text, height)
    function button:IsMouseOver()
        local owner = parent:GetParent()
        return owner.menuIndex == pointerIndex
    end
    local setOff = button.SetOff
    button.SetOff = function(off)
        button.offCalls = (button.offCalls or 0) + 1
        setOff(off)
    end
    return button
end
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))()
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
local appearance, daylight = NS.Internal.Appearance, NS.Internal.Daylight
f.Fire("PLAYER_LOGIN"); f.Flush()
daylight.SetSetting(nil, "enabled", true); f.Flush()
assert(appearance.provider == daylight)
local menus = NS.Internal.Menus
local function Open()
    return menus.CreateContextMenu(UIParent, function(_, menu)
        menu:CreateTitle("QuestieRouter")
        menu:CreateButton("Open Quest Details"):SetEnabled(false)
        menu:CreateButton("Make Active")
        menu:CreateButton("Route This Task"):CreateButton("Nested action")
    end)
end
local function State(row) return assert(appearance.visuals[row]).currentState end
local function SingleFocus(window, index)
    assert(Pad.Modal.GetState().index == index)
    for i, row in ipairs(window.rows) do
        if row.focus then
            local record, widget = appearance.visuals[row], State(row).widget
            assert((record.controllerFocused == true) == (i == index), "logical focus diverged")
            assert((widget.lit == true) == (i == index), "native border diverged from the one selected row")
        end
    end
end
for _ = 1, 3 do
    local window = Open()
    SingleFocus(window, 3)
    local firstRow, secondRow = window.rows[3], window.rows[4]
    local firstWidget, secondWidget = State(firstRow).widget, State(secondRow).widget
    local firstOff, firstHover = firstWidget.offCalls, firstWidget.hoverCalls
    local secondOff, secondHover = secondWidget.offCalls, secondWidget.hoverCalls
    local frames, scans = #f.frames, f.scans
    -- Repaint the unfocused row under the physical cursor after initial focus.
    for _ = 1, 100 do appearance.UpdateVisual(firstRow); appearance.UpdateVisual(secondRow) end
    SingleFocus(window, 3)
    assert(firstWidget.offCalls == firstOff and firstWidget.hoverCalls == firstHover)
    assert(secondWidget.offCalls == secondOff and secondWidget.hoverCalls == secondHover,
        "unchanged paints replayed enable or hover effects")
    assert(#f.frames == frames and f.scans == scans, "unchanged paint created widgets or rescanned navigation")
    -- Re-enabling this row makes native SetOff light it from IsMouseOver.
    -- The cache must notice that mutation although logical hover stayed false.
    secondRow:Disable(); SingleFocus(window, 3)
    secondRow:Enable(); SingleFocus(window, 3)
    assert(secondWidget.offCalls == secondOff + 2 and secondWidget.hoverCalls == secondHover + 2)
    firstRow:Disable(); firstRow:Enable(); SingleFocus(window, 3)
    assert(firstWidget.offCalls == firstOff + 2)

    secondRow:GetScript("OnEnter")(secondRow)
    SingleFocus(window, 4)
    f.PressKey("PADDUP"); SingleFocus(window, 3)
    f.PressKey("PADDDOWN"); f.PressKey("PAD1")
    assert(#Pad.Modal.GetState().stack == 2)
    SingleFocus(window, 1)
    f.PressKey("PAD2"); SingleFocus(window, 4)
    Pad.Modal.Close("escape")
    for _, pool in pairs(window.rowPools) do
        for _, row in ipairs(pool) do
            if row.focus then assert(not State(row).widget.lit, "a pooled hidden widget retained its border") end
        end
    end
end
print("Installed Daylight buttons: one menu focus, mouse sampling, enable transitions, cached idle paints, submenus and pooled reuse passed")

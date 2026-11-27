local f = assert(loadfile("tests/controller_fixture.lua"))()
local Frame, Pad = f.FrameMethods, f.Pad
local replace = dofile("tests/replace_method.lua")
function Frame:SetPropagateKeyboardInput() end
function Frame:LockHighlight() end
function Frame:UnlockHighlight() end

-- The general input fixture does not solve anchors. Resolve horizontal
-- constraints here so fixed-width rows cannot pass merely by having anchors.
local points = setmetatable({}, {__mode = "k"})
local setPoint, clear = Frame.SetPoint, Frame.ClearAllPoints
replace(Frame, "SetPoint", function(self, point, relative, relativePoint, x, y)
    setPoint(self, point, relative, relativePoint, x, y)
    if type(relative) == "number" then
        x, relative, relativePoint = relative, self:GetParent(), point
    elseif relative == nil then relative, relativePoint, x = self:GetParent(), point, 0 end
    points[self] = points[self] or {}
    points[self][point] = {relative, relativePoint, x or 0}
end)
replace(Frame, "ClearAllPoints", function(self) points[self] = nil; clear(self) end)
local originalWidth = Frame.GetWidth
local function Factor(point)
    if point:find("LEFT", 1, true) then return 0 end
    if point:find("RIGHT", 1, true) then return 1 end
    return 0.5
end
local function Rect(object)
    if object == UIParent then return 0, 1280 end
    if object.allPoints then return Rect(object.allPoints) end
    local first, firstFactor, width
    for point, anchor in pairs(points[object] or {}) do
        local left, relativeWidth = Rect(anchor[1])
        local position = left + relativeWidth * Factor(anchor[2]) + anchor[3]
        local factor = Factor(point)
        if first and factor ~= firstFactor then
            width = (position - first) / (factor - firstFactor)
            return first - width * firstFactor, width
        end
        first, firstFactor = position, factor
    end
    width = originalWidth(object)
    if first then return first - width * firstFactor, width end
    local left = object:GetParent() and Rect(object:GetParent()) or 0
    return left, width
end
replace(Frame, "GetWidth", function(self) local _, width = Rect(self); return width end)
local measures, stringHeight = 0, Frame.GetStringHeight
replace(Frame, "GetStringHeight", function(self) measures = measures + 1; return stringHeight(self) end)
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
local menus = f.NS.Internal.Menus
local function Open()
    return menus.CreateContextMenu(UIParent, function(_, menu)
        menu:CreateTitle(string.rep("Quest heading ", 14))
        menu:CreateButton(string.rep("Long quest description ", 12), function() end)
        menu:CreateButton("Choose task"):CreateButton(string.rep("Nested task description ", 12), function() end)
        menu:CreateDivider(); menu:CreateSpacer()
        menu:CreateButton("Disabled action", function() error("disabled") end):SetEnabled(false)
    end)
end
local window = Open()
local function Check()
    local left, width = Rect(window)
    local viewLeft, viewWidth = Rect(window.scroll)
    assert(viewLeft - left == left + width - viewLeft - viewWidth, "viewport margins are asymmetric")
    assert(window.content:GetWidth() == viewWidth, "content reserved an unused strip on the right")
    for _, row in ipairs(window.rows) do
        local rowLeft, rowWidth = Rect(row)
        assert(rowLeft == viewLeft and rowWidth == viewWidth, "row does not fill the viewport")
        assert(rowLeft - left == left + width - rowLeft - rowWidth, "row is off center")
        local text = row.label or row.line
        if text then
            local textLeft, textWidth = Rect(text)
            assert(textLeft > rowLeft and textLeft - rowLeft == rowLeft + rowWidth - textLeft - textWidth, "text/decoration insets are asymmetric")
        end
        if row.label then assert(row:GetHeight() >= row.label:GetStringHeight() + 10, "wrapped text overlaps the next row") end
    end
end
Check()
assert(window.scroll:GetWidth() == 394, "fixture did not resolve the real panel shell anchors")
local pooled = window.rows[2]
local wideHeight = pooled:GetHeight()
local function Resize(width)
    window:SetWidth(width)
    window.scroll:GetScript("OnSizeChanged")(window.scroll, window.scroll:GetWidth(), window.scroll:GetHeight())
    Check()
end
Resize(300)
assert(window.rows[2]:GetHeight() > wideHeight, "narrower content was not remeasured")
local narrowHeight = window.rows[2]:GetHeight()
Resize(620)
assert(window.rows[2]:GetHeight() < narrowHeight)
local before = measures
window.scroll:GetScript("OnSizeChanged")(window.scroll, window.scroll:GetWidth(), window.scroll:GetHeight() + 20)
f.PressKey("PADDDOWN"); f.PressKey("PADDUP")
assert(measures == before, "height/focus changes remeasured the menu")
f.PressKey("PADDDOWN"); f.PressKey("PAD1")
assert(#Pad.Modal.GetState().stack == 2 and window.rows[1] == pooled)
Check(); Resize(300)
f.PressKey("PAD2")
assert(#Pad.Modal.GetState().stack == 1 and Pad.Modal.GetState().index == 3)
Check()
f.PressKey("PAD2"); window = Open(); Check()
window:SetWidth(420); f.PressKey("PAD2")
StaticPopupDialogs.AWP_WIDTH_TEST = {text = "Confirm this change", button1 = "Accept", button2 = "Cancel"}
window = f.NS.Internal.Dialogs.Show("AWP_WIDTH_TEST")
Check(); f.PressKey("PAD2")
print("Controller menu layout: symmetric shell/viewport/row/text bounds, wrapping, width changes, idle focus, submenus, pooled rows and dialogs passed")

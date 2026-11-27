local context = assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local f, a, e = context.f, context.a, context.e
local Frame = getmetatable(f.Frame())
local setPoint, clearPoints = Frame.SetPoint, Frame.ClearAllPoints

function Frame:SetPoint(point, ...)
    self.geometryPoints = self.geometryPoints or {}
    self.geometryPoints[point] = { point, ... }
    setPoint(self, point, ...)
end

function Frame:ClearAllPoints()
    self.geometryPoints, self.allPoints = nil, nil
    clearPoints(self)
end

local root = f.Frame()
a.Tag(root, "windows.options")
local cases = {
    { kind = "window", edge = 16, tooltipInset = 5, dialog = {5.5, 6, 6, 5.5} },
    { kind = "panel", edge = 16, tooltipInset = 5, dialog = {5.5, 6, 6, 5.5} },
    { kind = "menu", edge = 8, tooltipInset = 2.5, dialog = {2.75, 3, 3, 2.75} },
    { kind = "dropdown", edge = 8, tooltipInset = 2.5 },
    { kind = "input", edge = 8, tooltipInset = 2.5 },
    { kind = "checkbox", edge = 8, tooltipInset = 2.5 },
    { kind = "header", edge = 8, tooltipInset = 2.5 },
    { kind = "border", edge = 8, tooltipInset = 2.5 },
}
local records = {}
for _, case in ipairs(cases) do
    local frame, art = f.Frame(root), f.Frame(root)
    frame:SetSize(370, case.kind == "panel" and 72 or 24)
    art:SetAlpha(0.65)
    records[case.kind] = a.RegisterVisual(frame, { kind = case.kind, regions = {art}, target = frame })
    assert(records[case.kind].applied, e.lastError)
end

local function check(record, case, look)
    local state = record.currentState
    local backdrop = state.root.backdrop
    assert(backdrop and not backdrop.bgFile, "A second, unbounded background was installed")
    assert(backdrop.edgeSize == case.edge)
    local dialog = look == "classic" and case.dialog
    local file = dialog and "Interface\\DialogFrame\\UI-DialogBox-Border" or "Interface\\Tooltips\\UI-Tooltip-Border"
    assert(backdrop.edgeFile == file)
    local left, right, top, bottom = case.tooltipInset, case.tooltipInset, case.tooltipInset, case.tooltipInset
    if dialog then left, right, top, bottom = unpack(dialog) end
    local insets = backdrop.insets
    assert(insets.left == left and insets.right == right and insets.top == top and insets.bottom == bottom)
    if case.kind == "border" then
        assert(not state.fill, "A border-only surface gained a fill")
    else
        local fill = assert(state.fill)
        assert(not fill.allPoints and not fill.masks, "Stock fill still uses the frame-wide EUI shape")
        local first, last = fill.geometryPoints.TOPLEFT, fill.geometryPoints.BOTTOMRIGHT
        assert(first[2] == state.root and first[4] == left and first[5] == -top)
        assert(last[2] == state.root and last[4] == -right and last[5] == bottom)
    end
    return state
end

for _, flavor in ipairs({"retail", "forever"}) do
    f.flavor = flavor
    for _, look in ipairs({"blizzard", "classic"}) do
        context.change(look, false)
        for _, case in ipairs(cases) do
            local record = records[case.kind]
            local state = check(record, case, look)
            local count = #f.frames
            for _, width in ipairs({100, 226, 370, 600}) do
                record.frame:SetWidth(width)
                a.UpdateVisual(record.frame)
                assert(check(record, case, look) == state and #f.frames == count)
            end
        end
        local dropdown, case = records.dropdown, cases[4]
        for _, event in ipairs({"OnEnter", "OnMouseDown", "OnMouseUp", "OnLeave"}) do
            dropdown.frame:GetScript(event)(dropdown.frame)
            check(dropdown, case, look)
        end
        dropdown.frame.enabled = false
        dropdown.frame:GetScript("OnDisable")(dropdown.frame)
        assert(dropdown.currentState.root:GetAlpha() == 0.4)
        check(dropdown, case, look)
        dropdown.frame.enabled = true
        dropdown.frame:GetScript("OnEnable")(dropdown.frame)
    end
end

context.change("blizzard", false)
local count = #f.frames
collectgarbage("collect"); collectgarbage("stop")
local memory = collectgarbage("count")
for _ = 1, 2000 do
    a.UpdateVisual(records.panel.frame)
    a.UpdateVisual(records.dropdown.frame)
end
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
assert(#f.frames == count and allocated < 8, "Stock geometry is rebuilt on unchanged updates")

a.Select("awp"); f.Flush()
for _, record in pairs(records) do
    assert(not record.applied and not record.holder:IsShown())
    assert(record.regions[1]:GetAlpha() == 0.65)
end
print("Ellesmere stock borders: native fill interiors, clients, roles, interaction states, resize reuse and restoration passed")

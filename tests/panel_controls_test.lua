local f = assert(loadfile("tests/daylight_fixture.lua"))()
local Frame = getmetatable(UIParent)
local function noop() end
for _, method in ipairs({ "EnableMouseWheel", "SetFrameStrata", "SetToplevel", "SetClampedToScreen",
    "SetMovable", "RegisterForDrag", "SetJustifyV", "SetBlendMode" }) do
    Frame[method] = noop
end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:GetHighlightTexture()
    if type(self.highlight) == "string" then
        local texture = f.Frame(self)
        texture:SetTexture(self.highlight)
        self.highlight = texture
    end
    return self.highlight
end
function Frame:SetScrollChild(child) self.child = child end
function Frame:GetVerticalScrollRange() return math.max(0, self.child:GetHeight() - self:GetHeight()) end
function Frame:GetVerticalScroll() return self.offset or 0 end
function Frame:SetVerticalScroll(offset) self.offset = offset end
function Frame:SetHideIfUnscrollable(enabled) self.hideIfFits = enabled end
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local frame = create(kind, name, parent, template)
    if template == "UIPanelScrollFrameTemplate" then
        local bar = create("Slider", nil, frame)
        bar.ScrollUpButton, bar.ScrollDownButton = f.Frame(bar), f.Frame(bar)
        frame.ScrollBar = bar
        frame:SetScript("OnMouseWheel", noop)
        frame:SetScript("OnScrollRangeChanged", function(self, _, range)
            if bar.hideIfFits then bar:SetShown(range > 0) end
            self:SetVerticalScroll(math.min(self:GetVerticalScroll(), range))
        end)
    end
    return frame
end

for _, file in ipairs({ "core/core", "interface/appearance/controller", "interface/appearance/visuals",
    "interface/appearance/provider", "interface/appearance/providers/daylight", "interface/framework/panels", "interface/framework/primitives",
    "interface/queue/state", "interface/queue/widgets", "interface/queue/list_view", "interface/queue/detail_view",
    "interface/manual_queue_prompt" }) do assert(loadfile(file .. ".lua"))() end
local NS = AzerothWaypointNS
local a, M, FW = NS.Internal.Appearance, NS.Internal.QueueUI, NS.Internal.Interface.Framework
f.Fire("PLAYER_LOGIN"); f.Flush()
a.Select("daylight"); f.Flush()
local content = f.Frame()
a.Tag(content, "windows.queue")
M.ui.content = content
M.CreateListPage(content)
M.CreateDetailPage(content)
local refreshes, toggles = 0, {}
function M.Refresh() refreshes = refreshes + 1 end
function M.SetSectionCollapsed(key, collapsed) toggles[#toggles + 1] = {key, collapsed} end
function M.SetDetailSectionCollapsed(queue, key, collapsed) toggles[#toggles + 1] = {key, collapsed, queue} end
M.CountQueues = function() return 1 end
M.IsQueueBulkSelectable = function() return false end
M.BuildDetailHeaderTexts = noop
M.BuildDetailMetaText = function() return "" end
M.GetQueueTransportStatus = noop
M.GetQueueFinalEntry = function() return nil end
M.GetQueueDetailHeaderIcon = noop
M.LayoutDetailHeaderIdentity = noop

local function Click(button, mouseButton)
    assert(button:GetScript("OnClick"))(button, mouseButton or "LeftButton")
end
local function VerifyRows(render, pool, queueKey)
    local section = { rowType = "section", sectionKey = "stops", queueKey = queueKey, label = "Waypoints", count = 1 }
    render({ section })
    local row, start = pool[1], #toggles
    local disclosure = assert(row.disclosure)
    assert(not a.visuals[row].applied and row.bg:GetAlpha() == 1)
    local visual = a.visuals[disclosure]
    local vertical = visual.tints[2].region
    assert(visual.surface == "windows.queue" and visual.applied)
    assert(disclosure.clicks[1] == "LeftButtonUp" and not vertical:IsShown())
    Click(row); assert(#toggles == start + 1 and toggles[start + 1][2] == true)
    section.collapsed = true
    render({ section })
    assert(row.disclosure == disclosure and vertical:IsShown())
    Click(disclosure); assert(#toggles == start + 2 and toggles[start + 2][2] == false)
    assert(toggles[start + 2][1] == "stops" and toggles[start + 2][3] == queueKey)
    Click(row, "RightButton"); assert(#toggles == start + 2)
    render({ { rowType = "entry", label = "Destination", title = "Destination" } })
    assert(pool[1] == row and not disclosure:IsShown())
    render({ section })
    assert(row.disclosure == disclosure and disclosure:IsShown())
    return disclosure
end
local disclosure = VerifyRows(function(rows) M.RenderListPage({}, rows) end, content.rows)
VerifyRows(function(rows) M.RenderDetailPage({}, "manual", rows) end, content.detailRows, "queue")
assert(refreshes == 4)

do
    local originalTime = GetTime
    local now = 200
    GetTime = function() return now end
    M.GetQueueTransportStatus = function(id)
        if id == "ride" then return "Riding to Ratchet", 261 end
    end
    M.RenderDetailPage({ id = "ride" }, "manual", {})
    local page = content.detailPage
    local tick = assert(page:GetScript("OnUpdate"))
    assert(content.detailMeta:GetText():find("about 1:01 remaining", 1, true))
    now = 201; tick(page, 1)
    assert(content.detailMeta:GetText():find("about 1:00 remaining", 1, true))
    now = 261; tick(page, 1)
    assert(not page:GetScript("OnUpdate") and content.detailMeta:GetText():find("Riding to Ratchet", 1, true))
    assert(not content.detailMeta:GetText():find("remaining", 1, true))
    GetTime, M.GetQueueTransportStatus = originalTime, noop
end

local scroll = content.listScroll
local bar = scroll.ScrollBar
local thumb, track = bar:GetThumbTexture(), bar.awpTrack
local visual = a.visuals[bar]
assert(visual.track == track and visual.target == thumb and visual.holder.allPoints == thumb)
assert(visual.holder.awpScrollTrack.allPoints == track and not visual.holder:IsShown())
assert(not bar.ScrollUpButton:IsShown() and not bar.ScrollDownButton:IsMouseEnabled())
local rangeChanged = scroll:GetScript("OnScrollRangeChanged")
scroll:SetHeight(10)
rangeChanged(scroll, 0, scroll:GetVerticalScrollRange())
assert(visual.holder:IsShown() and bar:IsShown() and visual.currentState.thumb.textureFile == "Daylight/ui-pill.png")
bar:GetScript("OnEnter")(bar)
assert(visual.currentState.thumb.vertex[4] == 0.38)
scroll:SetVerticalScroll(5)
local frameCount = #f.frames
FW.StyleAttachedListScrollBar(scroll, content.listPage)
assert(#f.frames == frameCount and scroll:GetScript("OnScrollRangeChanged") == rangeChanged)
assert(bar:GetThumbTexture() == thumb and scroll:GetScript("OnMouseWheel") == noop and scroll:GetVerticalScroll() == 5)
scroll:SetHeight(500)
rangeChanged(scroll, 0, scroll:GetVerticalScrollRange())
assert(not visual.holder:IsShown() and not bar:IsShown() and scroll:GetVerticalScroll() == 0)

local choices = {}
for _, key in ipairs({ "create", "replace", "append", "close" }) do
    NS.ShowManualQueuePlacementPrompt({ title = "A destination" }, function(choice) choices[#choices + 1] = choice end)
    local prompt = AWPManualQueuePrompt
    local button = prompt[key .. "Button"]
    if key ~= "close" then
        assert(button:GetWidth() == 116 and button:GetHeight() == 28 and a.visuals[button].surface == "windows.queue")
    end
    Click(button); Click(button)
    assert(not prompt:IsShown() and choices[#choices] == (key == "close" and "cancel" or key))
end
assert(#choices == 4)
a.Select("awp"); f.Flush()
assert(disclosure.bg:GetAlpha() == 1 and thumb:GetAlpha() == 1 and track:GetAlpha() == 1)
assert(select(2, AWPManualQueuePrompt.createButton.label:GetTextColor()) == 0.82)
a.Select("daylight"); f.Flush()
assert(a.visuals[bar] == visual and not visual.holder:IsShown())
print("Panel controls: shared disclosure, pooled queue rows, scrollbar range and theme restoration, and prompt choices passed")

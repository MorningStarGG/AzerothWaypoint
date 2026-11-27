local f = assert(loadfile("tests/daylight_fixture.lua"))()
local Frame = getmetatable(UIParent)
local setPoint = Frame.SetPoint
function Frame:SetPoint(point, ...)
    setPoint(self, point, ...)
    self.anchors = self.anchors or {}
    self.anchors[point] = {...}
end
function Frame:ClearAllPoints() self.point, self.anchors = nil, nil end
function Frame:SetScrollChild(child) self.child = child end
function Frame:RegisterForClicks() end
function Frame:SetBlendMode() end
function Frame:GetHighlightTexture() return self.highlight end
function Frame:SetHighlightTexture() self.highlight = f.Frame(self) end

for _, file in ipairs({"core/core", "interface/appearance/controller", "interface/appearance/visuals",
    "interface/appearance/provider", "interface/appearance/providers/daylight", "interface/framework/panels",
    "interface/queue/state", "interface/queue/model", "interface/queue/widgets", "interface/queue/list_view"}) do
    assert(loadfile(file .. ".lua"))()
end
local ns = AzerothWaypointNS
local m, appearance = ns.Internal.QueueUI, ns.Internal.Appearance
local content = f.Frame(UIParent)
appearance.Tag(content, "windows.queue")
m.ui.content = content
-- Scrollbar geometry is covered by panel_controls_test; use a plain scroll here.
ns.Internal.Interface.Framework.StyleAttachedListScrollBar = function() end
m.CreateListPage(content)
function content.emptyText:GetWidth() return self:GetParent():GetWidth() - 8 end
f.Fire("PLAYER_LOGIN"); f.Flush()
local function Render(snapshot)
    local rows = m.BuildQueueRows(snapshot)
    m.RenderListPage(snapshot, rows)
    return rows
end
local guide = {id="guide:zygor", label="Example guide", projection={entries={{}}}}
for _, style in ipairs({"awp", "daylight"}) do
    appearance.Select(style); f.Flush()
    m.SetSectionCollapsed("guide", true)
    local rows = Render({guideQueues={guide}})
    assert(#rows == 3 and m.CountQueues(rows) == 1 and not content.emptyText:IsShown())
    assert(rows[3].count == 1 and rows[3].collapsed)
    m.SetSectionCollapsed("manual", true)
    rows = Render({guideQueues={guide}, manualQueues={{id="manual:1", label="Saved queue"}}})
    assert(#rows == 3 and m.CountQueues(rows) == 2 and not content.emptyText:IsShown())
    m.SetSectionCollapsed("manual", false)
    rows = Render({guideQueues={guide}, manualQueues={{id="manual:1", label="Saved queue"}}})
    assert(#rows == 4 and m.CountQueues(rows) == 2 and not content.emptyText:IsShown())
    m.SetSectionCollapsed("transient", true)
    rows = Render({transientQueue={id="transient", label="Current route"}})
    assert(#rows == 3 and m.CountQueues(rows) == 1 and not content.emptyText:IsShown())

    rows = Render({})
    assert(#rows == 3 and m.CountQueues(rows) == 0 and content.emptyText:IsShown())
    local headerHeight = #rows * (m.ui.rowHeight + 2) - 2
    local point = content.emptyText.anchors.TOPLEFT
    assert(point[1] == content.listChild and point[2] == "TOPLEFT" and point[4] == -headerHeight - 8)
    assert(content.emptyText.anchors.RIGHT[1] == content.listChild)
    local childHeight = content.listChild:GetHeight()
    assert(childHeight == headerHeight + 8 + content.emptyText:GetStringHeight())
    assert(childHeight > headerHeight)
    content.listScroll:SetWidth(48)
    Render({})
    assert(content.listChild:GetHeight() > childHeight, "Wrapped empty text was clipped out of scroll content")
    content.listScroll:SetWidth(260)
    Render({})
    assert(content.listChild:GetHeight() == childHeight)
    rows = Render({guideQueues={guide}})
    assert(not content.emptyText:IsShown() and content.listChild:GetHeight() == headerHeight)
end
-- Simulate the engine's anchored FontString width; measure the real renderer,
-- not a fixed expected row stride, while the list is resized and themed.
for _,style in ipairs({"awp","daylight"}) do
    appearance.Select(style);f.Flush()
    m.SetSectionCollapsed("manual",false)
    local queue={id="manual:long",label="Together, as you come across them: Young Wolf, Kobold Vermin (2 quests)"}
    Render({manualQueues={queue}})
    local queueRow
    for _,row in ipairs(content.rows) do if row.queueKey==queue.id then queueRow=row end end
    assert(queueRow)
    function queueRow.text:GetWidth() return math.max(1,content.listChild:GetWidth()-40) end
    content.listScroll:SetWidth(220)
    local rows=Render({manualQueues={queue}})
    local tall=queueRow:GetHeight()
    assert(tall>m.ui.rowHeight and tall>=queueRow.text:GetStringHeight()+6)
    local total=0
    for i=1,#rows do total=total+content.rows[i]:GetHeight()+(i>1 and 2 or 0) end
    assert(content.listChild:GetHeight()==total,"scroll content ignored wrapped row heights")
    content.listScroll:SetWidth(120);Render({manualQueues={queue}})
    assert(queueRow:GetHeight()>tall,"queue name did not reflow when narrowed")
    content.listScroll:SetWidth(220);Render({manualQueues={queue}})
    assert(queueRow:GetHeight()==tall)
end
print("Queue empty state: real model counts collapsed queues and reserves message space below section headers")

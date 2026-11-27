local fixture = assert(loadfile("tests/daylight_fixture.lua"))()
local Frame = getmetatable(UIParent)
local setPoint = Frame.SetPoint
function Frame:SetPoint(point, ...)
    setPoint(self, point, ...)
    self.anchors = self.anchors or {}
    self.anchors[point] = {...}
end
function Frame:ClearAllPoints() self.point, self.anchors = nil, nil end
function Frame:SetScrollChild() end
function Frame:SetJustifyV() end
function Frame:SetBlendMode() end

for _, file in ipairs({"core/core", "interface/framework/panels", "interface/queue/state",
    "interface/queue/model", "interface/queue/widgets", "interface/queue/detail_view"}) do
    assert(loadfile(file .. ".lua"))()
end

local ns = AzerothWaypointNS
local queueUI = ns.Internal.QueueUI
local content = fixture.Frame(UIParent)
queueUI.ui.content = content
ns.Internal.Interface.Framework.StyleAttachedListScrollBar = function() end
queueUI.CreateDetailPage(content)

local page, panel, heading, details = content.detailPage, content.summaryPanel, content.detailMetaTitle, content.detailMeta
page:SetSize(340, 500)
page:Show()

local function NaturalDetailsHeight(text)
    local _, size = text:GetFont()
    local lines = 0
    for line in text:GetText():gmatch("[^\n]+") do
        lines = lines + math.ceil(#line * size * 0.5 / text:GetWidth())
    end
    return lines * size
end
-- Model text measurement when the font string has a finite height.
function details:GetStringHeight()
    return math.min(NaturalDetailsHeight(self), self:GetHeight())
end

local destination = {mapID = 1412, x = 0.51, y = 0.42, title = "Mulgore 51, 42"}
local queue = {id = "manual:1", kind = "destination_queue", sourceType = "manual_click",
    items = {destination}, projection = {derivedEntries = {destination}}}
local function Render()
    queueUI.RenderDetailPage(queue, "manual", {})
end

local function CheckLayout()
    local bodyAnchor = details.anchors.TOPLEFT
    assert(bodyAnchor[1] == heading and bodyAnchor[2] == "BOTTOMLEFT" and bodyAnchor[4] < 0)
    assert(panel.anchors.BOTTOMLEFT[1] == page and panel.anchors.BOTTOMLEFT[2] == "BOTTOMLEFT")
    local headingTop = -heading.anchors.TOPLEFT[4]
    local bodyBottom = headingTop + heading:GetStringHeight() - bodyAnchor[4] + details:GetHeight()
    assert(panel:GetHeight() > bodyBottom, "Queue summary lost its bottom padding")
    local routeTop = content.detailHeader:GetHeight() - content.routePanel.anchors.TOPLEFT[4]
    local routeBottom = page:GetHeight() - panel:GetHeight() - content.routePanel.anchors.BOTTOMLEFT[4]
    assert(routeBottom - routeTop >= 48, "Summary covered the route viewport")
end

Render()
CheckLayout()
assert(details:GetText() == "Type: Destination Queue\nSource: manual_click\nRoute Steps: 1\nQueued Destinations: 1\nFinal: Mulgore 51, 42")
local shortHeight = panel:GetHeight()
destination.title = string.rep("Azeroth ", 12) .. "Camp"
Render()
CheckLayout()
assert(panel:GetHeight() > shortHeight and details:GetHeight() >= NaturalDetailsHeight(details))

local wideHeight = panel:GetHeight()
local owner={backend="polestar"}
ns.State.routing={activeQueueKey=queue.id}
ns.GetActiveAuthorityRecord=function() return owner end
ns.GetRoutingBackend=function() return {GetNavigationStatus=function(record)
    assert(record==owner);return "partial","An enemy town on the planned walk"
end} end
Render();CheckLayout()
assert(details:GetText():find("The last steps here aren't mapped",1,true) and details:GetText():find("Hostile town:",1,true))
ns.State.routing.activeQueueKey="another-queue"
Render();CheckLayout()
assert(not details:GetText():find("Walking:",1,true),"Another queue inherited active walking qualifications")
page:SetWidth(220)
page:GetScript("OnSizeChanged")(page)
CheckLayout()
assert(panel:GetHeight() > wideHeight and details:GetHeight() >= NaturalDetailsHeight(details))

local normalFontHeight = panel:GetHeight()
heading:SetFont("Fixture.ttf", 20, "")
details:SetFont("Fixture.ttf", 17, "")
Render()
CheckLayout()
assert(panel:GetHeight() > normalFontHeight and details:GetHeight() >= NaturalDetailsHeight(details))

content.bulkDeleteButton = fixture.Frame(content)
content.bulkDeleteButton:SetSize(26, 26)
ns.RemoveQueueItems = function() end
queueUI.SetQueueItemSelected(queue.id, 1, true)
queueUI.UpdateBulkDeleteButton(queue, "manual", "detail")
Render()
CheckLayout()
local textRight = heading.anchors.TOPLEFT[3] + details:GetWidth()
local buttonLeft = page:GetWidth() + content.bulkDeleteButton.anchors.BOTTOMRIGHT[3] - content.bulkDeleteButton:GetWidth()
assert(textRight < buttonLeft, "Summary text covered the bulk delete button")

page:SetHeight(240)
page:GetScript("OnSizeChanged")(page)
CheckLayout()
assert(details:GetHeight() < NaturalDetailsHeight(details), "Short window did not bound the summary")
page:SetHeight(500)
page:GetScript("OnSizeChanged")(page)
CheckLayout()
assert(details:GetHeight() >= NaturalDetailsHeight(details), "Summary stayed truncated after growing the window")

print("Queue summary layout: title spacing, wrapped details, font changes, bulk deletion and viewport bounds passed")

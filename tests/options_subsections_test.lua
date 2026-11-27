local f = assert(loadfile("tests/daylight_fixture.lua"))()
local NS = AzerothWaypointNS
local Frame = getmetatable(UIParent)
local function noop() end
function Frame:SetScrollChild(child) self.child, self.offset = child, 0 end
function Frame:GetVerticalScroll() return self.offset or 0 end
function Frame:GetVerticalScrollRange() return math.max(0, self.child:GetHeight() - self:GetHeight()) end
function Frame:SetVerticalScroll(offset) self.offset = offset end
function Frame:SetNormalFontObject(font) self:GetFontString():SetFontObject(font) end
function Frame:GetFontString()
    self.fontString = self.fontString or self:CreateFontString()
    return self.fontString
end
function Frame:SetText(text)
    self.text = text
    if self.objectType == "Button" then self:GetFontString():SetText(text) end
    local changed = self:GetScript("OnTextChanged")
    if changed then changed(self) end
end
function Frame:LockHighlight() self.highlightLocked = true end
function Frame:UnlockHighlight() self.highlightLocked = nil end
for _, method in ipairs({ "UpdateScrollChildRect", "EnableMouseWheel", "SetMovable", "SetClampedToScreen",
    "SetFrameStrata", "SetToplevel", "SetAutoFocus", "SetTextInsets", "SetMultiLine", "SetDrawLayer",
    "SetHighlightFontObject", "SetJustifyV", "SetCheckedTexture", "SetPushedTexture", "RegisterForDrag" }) do
    Frame[method] = noop
end
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local frame = create(kind, name, parent, template)
    frame.objectType = kind
    if kind == "ScrollFrame" then frame:SetHeight(126) end
    return frame
end

for _, path in ipairs({ "core/core", "core/routing_backends", "core/db_defaults", "core/db", "core/guide_settings", "interface/appearance/controller",
    "interface/appearance/provider", "interface/appearance/providers/daylight", "interface/framework/panels", "interface/startup_notices",
    "interface/options/shared" }) do
    assert(loadfile(path .. ".lua"))()
end
local loaded = {}
for _, provider in ipairs(NS.Constants.GUIDE_PROVIDERS) do loaded[provider.key] = true end
function NS.GetGuideTargetProvider(key)
    return { isLoaded = function() return loaded[key] end }
end
local appearance = NS.Internal.Appearance
local reflow
appearance.RegisterReflow = function(_, callback) reflow = callback end
appearance.GetEffectiveID = function() return "daylight" end
for _, method in ipairs({ "RegisterVisual", "UpdateVisual", "RegisterSlider", "RegisterToggle", "StyleOptionsDropdown",
    "Input", "Tag", "Text", "Decoration", "StyleButton" }) do
    appearance[method] = noop
end
local framework = NS.Internal.Interface.Framework
framework.CreatePanelShell = function(frame)
    local body = f.Frame(frame)
    body:SetWidth(frame:GetWidth())
    return { bodyFrame = body, titleFrame = f.Frame(frame), footerFrame = f.Frame(frame) }
end

for _, path in ipairs({ "canvas_data", "canvas_widgets", "canvas", "canvas_sections" }) do
    assert(loadfile("interface/options/" .. path .. ".lua"))()
end
local canvas = NS.Internal.Interface.canvas
canvas.Renderers.about = noop
canvas.Renderers.overlay = noop
canvas.Renderers.waypoint = noop
local window = canvas.Create()
window:Show()
local sidebar, page, search
for _, frame in ipairs(f.frames) do
    if frame.objectType == "ScrollFrame" then
        if not sidebar then sidebar = frame else page = frame end
    elseif frame.objectType == "EditBox" then search = frame end
end
assert(sidebar and page and search)

local function Find(parent, label)
    for _, frame in ipairs(f.frames) do
        if frame:GetParent() == parent and frame:IsShown() and (frame:GetText() == label
            or frame.label and frame.label:GetText() == label or frame.title and frame.title:GetText() == label) then
            return frame
        end
    end
end
local function Click(button)
    assert(button, "Button missing")
    return assert(button:GetScript("OnClick"))(button)
end

local function IsCollapsed(button)
    for _, frame in ipairs(f.frames) do
        if frame:GetParent() == button and frame:GetWidth() == 1 and frame:GetHeight() == 7 then
            return frame:IsShown()
        end
    end
    error("Missing vertical disclosure stroke")
end

local dugi, zygor, daylight = Find(sidebar.child, "Dugi"), Find(sidebar.child, "Zygor"), Find(sidebar.child, "DaylightUI")
assert(dugi and zygor and daylight and not Find(sidebar.child, "Tracker Viewer"))
local overlay = assert(Find(sidebar.child, "World Overlay"))
assert(not IsCollapsed(overlay.disclosure) and Find(sidebar.child, "Pinpoint") and Find(sidebar.child, "Navigator"))
Click(Find(sidebar.child, "Waypoint"))
Click(overlay.disclosure)
assert(overlay.highlightLocked and IsCollapsed(overlay.disclosure) and not Find(sidebar.child, "Waypoint"))
Click(overlay.disclosure)
assert(Find(sidebar.child, "Waypoint"))
local strokeCount = 0
for _, frame in ipairs(f.frames) do
    if frame:GetParent() == overlay.disclosure and frame:GetNumPoints() > 0 then
        local point, relative, relativePoint = frame:GetPoint()
        if point == "CENTER" and relative == overlay.disclosure and relativePoint == "CENTER" then
            strokeCount = strokeCount + 1
        end
    end
end
assert(strokeCount == 2, "Both disclosure strokes must share the button's center")
Click(dugi)
Click(zygor)
assert(not IsCollapsed(dugi.disclosure) and not IsCollapsed(zygor.disclosure))
assert(sidebar:GetVerticalScrollRange() > 0 and search:GetParent() ~= sidebar.child)
Click(zygor.disclosure)
assert(IsCollapsed(zygor.disclosure) and not IsCollapsed(dugi.disclosure))

search:SetText("dugi hide native action controls")
local result = assert(Find(page.child, "Hide Native Action Controls"))
assert(result.section:GetText() == "Dugi / Guide Actions")
Click(result)
assert(Find(sidebar.child, "Guide Actions").highlightLocked and page:GetVerticalScroll() > 0)
assert(Find(page.child, "Reset Guide Action Panel Position"))
Click(dugi.disclosure)
assert(dugi.highlightLocked and not Find(sidebar.child, "Guide Actions"))

local function FindGuideResult(label, section)
    for _, frame in ipairs(f.frames) do
        if frame:GetParent() == page.child and frame:IsShown()
            and frame.title and frame.title:GetText() == label and frame.section:GetText() == section then
            return frame
        end
    end
end
NS.VERSION = "5.0.0"
for _, provider in ipairs(NS.Constants.GUIDE_PROVIDERS) do
    local section = canvas.Data.GUIDE_SECTIONS[provider.key].label .. " / Tracker Viewer"
    search:SetText(provider.key .. " hide provider name")
    local match = assert(FindGuideResult("Hide Guide Addon Name", section), provider.key)
    assert(match.markerTag and match.markerTag:IsShown())
    Click(match)
    assert(Find(page.child, "Hide Guide Addon Name") and page:GetVerticalScroll() > 0, provider.key)

    search:SetText(provider.key .. " enable tracker viewer")
    match = assert(FindGuideResult("Enable Tracker Viewer", section), provider.key)
    local badge = match.markerTag and match.markerTag:IsShown()
    assert((badge == true) == (provider.key ~= "zygor"), "Viewer badge borrowed another guide's release history")
    Click(match)
    assert(Find(page.child, "Enable Tracker Viewer"), provider.key)
end

search:SetText("daylight plaque border width")
result = assert(Find(page.child, "Border width"))
assert(result.section:GetText() == "DaylightUI / World Overlay / Pinpoint plaque")
search:SetText("daylight pinpoint plaque border width")
assert(Find(page.child, "Border width") == result, "Typing recreated the search result row")
Click(result)
assert(Find(page.child, "Pinpoint plaque") and page:GetVerticalScroll() > 0)
local offset = page:GetVerticalScroll()
reflow()
assert(Find(page.child, "Pinpoint plaque") and page:GetVerticalScroll() == offset)

canvas.SelectOptionsPage("dugi.viewer")
local shortcut = assert(Find(page.child, "Open DaylightUI Viewer Styling"))
local point, _, relativePoint, x = shortcut:GetPoint()
assert(point == "TOP" and relativePoint == "TOP" and x == 0)
Click(shortcut)
assert(Find(page.child, "Dugi") and not IsCollapsed(daylight.disclosure) and not IsCollapsed(dugi.disclosure))
canvas.SelectOptionsPage("daylight.viewers", "guide.rxp")
assert(Find(page.child, "RestedXP") and not Find(page.child, "Dugi") and page:GetVerticalScroll() == 0)
page:SetVerticalScroll(80)
reflow()
assert(Find(page.child, "RestedXP") and page:GetVerticalScroll() == 80)

NS.GetZygorAddonName = function() return "ZygorGuidesViewerForever" end
NS.IsManualQueuePreservationEnabled = function() return true end
search:SetText("appearance provider")
local styleResult = assert(Find(page.child, "UI Style"))
assert(styleResult.section:GetText() == "General" and styleResult.markerTag:IsShown())
Click(styleResult)
assert(Find(page.child, "UI Style"))

f.flavor = "retail"
local _, retail = canvas.Data.BuildSections()
assert(not retail.daylight and not retail.questierouter and not retail.polestar)
assert(retail["dugi.viewer"] and retail["apr.viewer"] and retail["wowpro.viewer"])
print("Options subsections: independent expansion, sidebar scrolling, exact search, Viewer links, reflow and client gating passed")

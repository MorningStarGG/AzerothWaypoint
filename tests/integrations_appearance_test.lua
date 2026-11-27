local fixture = dofile("tests/daylight_fixture.lua")
local Frame = getmetatable(fixture.Frame())
function Frame:GetFrameLevel()
    return self.level or (self.parent and self.parent:GetFrameLevel() + 1 or 5)
end
function Frame:SetJustifyV() end

local getWidth = Frame.GetWidth
function Frame:GetWidth()
    -- Panel button labels are constrained by their left and right anchors.
    if self.parent and self.parent.label == self then return math.max(1, self.parent:GetWidth() - 18) end
    return getWidth(self)
end

local setEnabled = Frame.SetEnabled
function Frame:SetEnabled(enabled)
    local changed = self:IsEnabled() ~= enabled
    setEnabled(self, enabled)
    local handler = changed and self:GetScript(enabled and "OnEnable" or "OnDisable")
    if handler then handler(self) end
end

for _, path in ipairs({
    "core/core.lua",
    "interface/appearance/controller.lua",
    "interface/appearance/visuals.lua",
    "interface/appearance/provider.lua",
    "interface/appearance/providers/daylight.lua",
    "interface/framework/panels.lua",
}) do assert(loadfile(path))() end

local NS = AzerothWaypointNS
local appearance, daylight = NS.Internal.Appearance, NS.Internal.Daylight
fixture.Fire("PLAYER_LOGIN")
fixture.Flush()
daylight.SetSetting(nil, "enabled", true)
daylight.SetSurfaceSettings("windows.options", { colors = true, customSizes = true, headingSize = 20, bodySize = 24 })
fixture.Flush()
assert(appearance.GetEffectiveID() == "daylight")

local scroll = fixture.Frame()
scroll:SetWidth(360)
appearance.Tag(scroll, "windows.options")
local copied, cursor = nil, 16
NS.Internal.Interface.options = { ShowCopyLinkPopup = function(url) copied = url end }
NS.Internal.Interface.canvas = {
    Data = { GUIDE_PAGES = {} },
    Widgets = {
        GetScrollChild = function() return scroll end,
        GetCursorY = function() return cursor end,
        SetCursorY = function(value) cursor = value end,
        SectionHeader = function() end,
        AddText = function() end,
        Spacer = function() end,
    },
}
NS.GetIntegrationInfo = function()
    return {
        { category = "Trackers", name = "A guide viewer with a longer title", url = "https://example.invalid/tracker",
            summary = "A description that wraps to several lines at the selected Options font size.",
            bullets = { "These details can wrap too." } },
        { category = "Trackers", name = "Pending" },
        { category = "Trackers", name = "Travel", links = {
            { label = "FarstriderLib", url = "https://example.invalid/library" },
            { label = "FarstriderLib Data", url = "https://example.invalid/data" },
        } },
    }, { "Trackers" }
end
NS.GetIntegrationDisplayStatus = function()
    return "Not available on WoW Forever", { 1, 0.34, 0.28, 1 }
end

assert(loadfile("interface/options/canvas_sections.lua"))()
NS.Internal.Interface.canvas.Renderers.integrations()
local buttons, texts = {}, {}
for _, frame in ipairs(fixture.frames) do
    if frame.SetDisplayText then buttons[frame.label:GetText()] = frame end
    if appearance.texts[frame] then texts[frame:GetText()] = frame end
end

local copy = assert(buttons["Copy Link"])
local copyVisual = assert(appearance.visuals[copy])
local content = copy:GetParent()
local card = content:GetParent()
local cardVisual = assert(appearance.visuals[card])
assert(cardVisual.kind == "inset" and cardVisual.surface == "windows.options")
assert(copyVisual.surface == cardVisual.surface and copyVisual.currentState.widget:IsShown())
assert(copyVisual.currentState.widget:GetFrameLevel() > card:GetFrameLevel(), "Card art overlaps the button skin")
assert(cardVisual.holder:GetFrameLevel() < content:GetFrameLevel(), "Card skin overlaps its content")
assert(card.bg:GetAlpha() == 0 and card.border:GetAlpha() == 0 and copy.bg:GetAlpha() == 0)

local title = assert(texts["A guide viewer with a longer title"])
local status = assert(texts["Not available on WoW Forever"])
local summary = assert(texts["A description that wraps to several lines at the selected Options font size."])
assert(title:GetFont() == "Daylight.ttf" and select(2, title:GetFont()) == 20)
assert(status:GetFont() == "Daylight.ttf" and select(2, status:GetFont()) == 24)
local r, g, b, a = status:GetTextColor()
assert(r == 1 and g == 0.34 and b == 0.28 and a == 1, "Theme replaced the status color")
assert(-summary.point[5] >= 11 + status:GetStringHeight() + 7, "Summary overlaps the wrapped status")
assert(copy:GetHeight() >= copy.label:GetStringHeight() + 8)

copy:GetScript("OnClick")(copy)
assert(copied == "https://example.invalid/tracker")
local pending = assert(buttons["Link Pending"])
assert(not pending:IsEnabled() and appearance.visuals[pending].currentState.widget.off)
pending:GetScript("OnClick")(pending)
assert(copied == "https://example.invalid/tracker")

local library, data = assert(buttons["FarstriderLib"]), assert(buttons["FarstriderLib Data"])
assert(data.point[5] <= library.point[5] - library:GetHeight() - 4, "Wide links did not wrap")
data:GetScript("OnClick")(data)
assert(copied == "https://example.invalid/data", "Named link copied the wrong URL")

local totalFrames = #fixture.frames
appearance.RefreshVisuals()
assert(#fixture.frames == totalFrames, "Reapplying the same style rebuilt the cards or buttons")
daylight.SetSetting("windows.options", "shell", false)
fixture.Flush()
assert(not cardVisual.holder:IsShown() and not copyVisual.holder:IsShown())
assert(card.bg:GetAlpha() ~= 0 and card.border:GetAlpha() ~= 0 and copy.bg:GetAlpha() ~= 0)

-- Use the canvas's real preview construction and page layout. The divider's
-- skinned artwork must inherit the preview column's visibility.
local file = assert(io.open("interface/options/canvas.lua", "r"))
local canvasSource = file:read("*a")
file:close()
local previewStart = assert(canvasSource:find("-- Right preview panel", 1, true))
local previewEnd = assert(canvasSource:find("-- Center scroll frame", previewStart, true))
local layoutStart = assert(canvasSource:find("local function UpdateContentLayoutForSection", 1, true))
local layoutEnd = assert(canvasSource:find("local function CreateDropdownButton", layoutStart, true))
local build = assert(loadstring(canvasSource:sub(previewStart, previewEnd - 1)
    .. canvasSource:sub(layoutStart, layoutEnd - 1) .. "\nreturn previewColumn, previewLine, UpdateContentLayoutForSection"))
local body = fixture.Frame()
appearance.Tag(body, "windows.options")
local pageScroll = fixture.Frame(body)
setfenv(build, setmetatable({
    bodyFrame = body, scrollFrame = pageScroll, PREVIEW_W = 350, PREVIEW_MAX_W = 334, PREVIEW_MAX_H = 208,
    NAV_W = 225, COLOR_PANEL = { 0, 0, 0, 1 }, COLOR_LINE = { 1, 1, 1, 1 }, ICON_PATH = "Fixture",
    ColorTexture = NS.Internal.Interface.Framework.ColorTexture,
    AnchorPreviewDescription = function() end, NS = NS,
}, { __index = _G }))
daylight.SetSetting("windows.options", "shell", true)
fixture.Flush()
local preview, divider, selectLayout = build()
local themedDivider
for _, visual in pairs(appearance.visuals) do
    if visual.kind == "decoration" and visual.regions[1] == divider then themedDivider = visual.holder end
end
assert(themedDivider and themedDivider:IsVisible())
for _, page in ipairs({ "integrations", "release" }) do
    selectLayout(page)
    appearance.RefreshVisuals()
    assert(not preview:IsShown() and not themedDivider:IsVisible() and not divider:IsVisible(), page)
    assert(pageScroll.point[4] == 0, "Document page did not fill the available width")
    selectLayout("general")
    assert(preview:IsShown() and themedDivider:IsVisible(), "Preview divider did not return")
    assert(pageScroll.point[4] == -350)
end
selectLayout("integrations")
daylight.SetSetting(nil, "enabled", false)
fixture.Flush()
assert(not divider:IsVisible(), "Stock divider appeared on Integrations after switching styles")
selectLayout("general")
assert(divider:IsVisible() and divider:GetAlpha() == 1)

print("Integrations cards match Options styling, keep buttons above the card art, and fit wrapped text and links")
print("Integrations and Release Notes hide both versions of the preview divider")

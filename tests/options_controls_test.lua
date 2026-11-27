local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
NS.Internal.StartupNotices = { RegisterArrow = function() return function() end end, PreferredIndex = function() return 3 end }
assert(loadfile("interface/options/shared.lua"))()
local options = NS.Internal.Interface.options
assert(options.GetSettingDefault("followGroundPathsWhileFlying") == false)
assert(options.GetSettingDefault("routingEnabled") == true)
assert(options.GetSettingDefault("appearanceProvider") == "auto")
assert(options.GetSettingDefault("worldOverlayPinpointDistance") == 35)
local color = options.GetSettingDefault("worldOverlayPinpointTitleCustomColor")
color.r = 0
assert(options.GetSettingDefault("worldOverlayPinpointTitleCustomColor").r ~= 0)
assert(options.ViewerDefault("zygor", "HideGuideTitle")() == false)
assert(options.ViewerDefault("dugi", "ProgressStyle")() == "rounded")
local definitions = assert(io.open("interface/options/canvas_sections.lua"))
local source = definitions:read("*a"); definitions:close()
for key in source:gmatch('[^%w_]Default%("([^"]+)"%)') do
    assert(options.GetSettingDefault(key) ~= nil, "Reset has no schema default: " .. key)
end
for _, definition in ipairs(NS.Constants.GUIDE_PROVIDERS) do
    for suffix in source:gmatch('ViewerDefault%(providerKey, "([^"]+)"%)') do
        if suffix ~= "ShowBanner" or definition.key == "questierouter" then
            assert(options.ViewerDefault(definition.key, suffix)() ~= nil, "Missing provider default: " .. definition.key .. suffix)
        end
    end
end
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))()
NS.Internal.Appearance.Select("awp")
f.Fire("PLAYER_LOGIN"); f.Flush()
local parent = f.Frame()
NS.Internal.Appearance.Tag(parent, "windows.options")
local prototype = getmetatable(parent).__index
local function noop() end
local setPoint, clearPoints = prototype.SetPoint, prototype.ClearAllPoints
function prototype:SetPoint(point, ...)
    setPoint(self, point, ...)
    self.anchors = self.anchors or {}
    self.anchors[point] = { ... }
end
function prototype:ClearAllPoints()
    clearPoints(self)
    self.anchors = nil
end
for _, key in ipairs({"SetJustifyH","SetJustifyV","SetMaxLines","SetValueStep","SetCheckedTexture","SetPushedTexture","EnableKeyboard"}) do prototype[key] = noop end
function prototype:SetDisplayText(v) self:SetText(v) end
function prototype:SetText(v) self.textValue = v end
function prototype:GetText() return self.textValue end
function prototype:GetScript(key) return self.scripts and self.scripts[key] end
function prototype:SetTexture(v) self.fileTexture = v end
function prototype:SetAtlas(v) self.atlas = v end
function prototype:SetColorTexture(...) self.rgba = {...} end
function prototype:SetVertexColor(r,g,b,a)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number")
    self.gradient = nil
    self.rgba = {r,g,b,a}
end
function prototype:GetVertexColor() return unpack(self.rgba or {1,1,1,1}) end
function prototype:GetRegions() end
function prototype:SetThumbTexture(v) self.thumb = self.thumb or f.Frame(self); self.thumb:SetTexture(v) end
function prototype:GetThumbTexture() return self.thumb end
function prototype:SetOrientation(value) self.orientation=value end
function prototype:IsEnabled() return self.enabled ~= false end
function prototype:HasFocus() return self.focus == true end
function prototype:ClearFocus() self.focus = false end
function prototype:Enable() self.enabled = true end
function prototype:Disable() self.enabled = false end
function prototype:CreateTexture() return f.Frame(self) end
function prototype:CreateFontString() return f.Frame(self) end
local refreshed, value, y = 0, true, 0
local markedToggleLabel = "Preserve Imported and Multi-Stop Queues"
local badges = {}
local tip, picker
local function UnpackOptions(get) return get() end
local function GetOptionText(get, value)
    for _, option in ipairs(get()) do
        if option.value == value then return option.text end
    end
    return tostring(value)
end
assert(loadfile("interface/options/canvas_widgets.lua"))()
local widgets = NS.Internal.Interface.canvas.CreateWidgets({
    CreateFrame = CreateFrame, GetScrollChild = function() return parent end,
    GetCursorY = function() return y end, SetCursorY = function(v) y = v end,
    CreatePanelButton = function(p) return f.Frame(p) end,
    CreateDropdownButton = function(p) return f.Frame(p) end,
    GetOpts = function() return options end, GetOptionText = GetOptionText, UnpackOptions = UnpackOptions,
    ColorPickerFrame = {
        SetupColorPickerAndShow = function(self, config) picker = config; self.swatchFunc = config.swatchFunc end,
        Hide = function(self) self.swatchFunc = nil end,
        GetColorRGB = function() return 0.2, 0.3, 0.4 end,
    },
    RestoreSectionPreview = noop,
    AddSettingMarkerTag = function(owner, label)
        if label ~= markedToggleLabel then return end
        local toggleTag = owner:CreateFontString()
        badges[label] = toggleTag
        toggleTag:SetText("NEW 4.3")
        return toggleTag
    end,
    ShowTip = function(_, _, text) tip = text end, HideTip = noop,
    RefreshActiveSection = function() refreshed = refreshed + 1 end,
    PAD = 16, SECTION_H = 24, SPACER_H = 8, TOGGLE_H = 28, SLIDER_H = 56, DROPDOWN_H = 52, COLOR_H = 52,
})
local toggle = widgets.AddToggle("Test", nil, function() return value end,
    function(v) value = v end, options.SettingDefault("followGroundPathsWhileFlying"))
assert(toggle.reset)
assert(toggle.reset:IsShown(), "Changed toggle has no reset")
assert(toggle.reset:GetWidth() == 20 and toggle.reset.icon.atlas == "common-icon-rotateleft")
assert(toggle.point[1] == "TOPRIGHT" and toggle.point[4] == -16 - 28, "Toggle mouse area covers its reset")
local idleR = toggle.reset.icon.rgba[1]
toggle.reset:GetScript("OnEnter")(toggle.reset)
assert(tip:find("Default: Off", 1, true), "False default is not readable")
assert(toggle.reset.icon.rgba[1] ~= idleR, "Reset hover did not change tint")
toggle.reset:GetScript("OnLeave")(toggle.reset)
assert(toggle.reset.icon.rgba[1] == idleR, "Reset hover tint did not restore")
toggle.reset:GetScript("OnClick")()
assert(value == false and not toggle:GetChecked() and refreshed == 0, "Reset rebuilt the page or left the toggle checked")
assert(not toggle.reset:IsShown(), "Reset remains visible at default")
toggle:SetChecked(true); toggle:GetScript("OnClick")(toggle)
assert(value and toggle.reset:IsShown(), "Toggle edit did not reveal reset")
toggle:SetChecked(false); toggle:GetScript("OnClick")(toggle)
assert(not value and not toggle.reset:IsShown(), "Returning to default did not hide reset")
local scale = 0.3
local slider = widgets.AddSlider("Scale", nil, 0, 1, 0.1, function(v) return string.format("%d%%", v * 100) end,
    function() return scale end, function(v) scale = v end, function() return 1 end)
slider.reset:GetScript("OnEnter")(slider.reset)
assert(tip:find("Default: 100%", 1, true), "Slider default lost its formatter/units")
slider.reset:GetScript("OnClick")()
assert(scale == 1 and slider:GetValue() == 1 and refreshed == 0)
assert(not slider.reset:IsShown())
slider:SetValue(0.6); slider:GetScript("OnValueChanged")(slider, 0.6, true)
assert(scale == 0.6 and slider.reset:IsShown())
slider:SetValue(1 - 1e-8); slider:GetScript("OnValueChanged")(slider, 1 - 1e-8, true)
assert(not slider.reset:IsShown(), "Float roundoff exposes a spurious reset")
local daylight = NS.Internal.Daylight
f.api.Media = function(file) return "Daylight/" .. file end
f.api.Input = function(p) return f.Frame(p) end
daylight.SetSetting(nil, "enabled", true); f.Flush()
local rowStart = y
local marked = widgets.AddToggle(markedToggleLabel, nil, function() return false end, noop, function() return true end)
local markedLabel = marked._awpSettingLabel
local toggleTag = assert(badges[markedToggleLabel], "Missing release badge")
assert(NS.Internal.Appearance.visuals[marked].applied, "Marked toggle was not styled")
assert(markedLabel.wrap and markedLabel.anchors.RIGHT[1] == toggleTag
    and markedLabel.anchors.RIGHT[2] == "LEFT" and markedLabel.anchors.RIGHT[3] < 0, "Toggle label overlaps its badge")
assert(toggleTag.anchors.RIGHT[1] == marked and marked.reset:IsShown(), "Toggle badge occupies reset space")
assert(y - rowStart >= markedLabel:GetStringHeight() + 8, "Wrapped toggle label overlaps the next row")
local nativeTinted = 0
DaylightUI.Widgets = { COLORS = { faint = {0.4, 0.45, 0.5} }, TintDaylight = function(icon)
    nativeTinted = nativeTinted + 1; icon.gradient = "daylight-options"
end }
local themedReset = widgets.AddToggle("Themed", nil, function() return false end, function() end, function() return false end)
local resetIcon=NS.Internal.Appearance.visuals[themedReset.reset].currentState.icon
assert(resetIcon.rgba[1] == 0.4)
themedReset.reset:GetScript("OnEnter")(themedReset.reset)
assert(resetIcon.gradient == "daylight-options" and nativeTinted == 1, "Used flat accent instead of native options gradient")
themedReset.reset:GetScript("OnLeave")(themedReset.reset)
assert(resetIcon.gradient == nil and resetIcon.rgba[1] == 0.4)
themedReset:GetScript("OnEnter")(themedReset)
assert(themedReset.rowHighlight.rgba[1] == f.palette.VALUE[1] and themedReset.rowHighlight.rgba[4] == 0.03,
    "Daylight option row kept AWP's gold wash")
local input
for _, frame in ipairs(f.frames) do
    if frame:GetScript("OnEnterPressed") and NS.Internal.Appearance.visuals[slider].currentState.input==frame then input = frame end
end
assert(input and input:IsShown(), "Daylight numeric input not installed")
input:SetText("50%"); input:GetScript("OnEnterPressed")(input)
assert(scale == 0.5, "Percent input changed units or ignored step")
assert(slider.reset:IsShown(), "Themed numeric edit bypassed reset visibility")
input:SetText("999%"); input:GetScript("OnEnterPressed")(input)
assert(scale == 1, "Typed input bypassed bounds")
assert(not slider.reset:IsShown())
daylight.SetSetting(nil, "enabled", false); f.Flush()
assert(not NS.Internal.Appearance.visuals[slider].applied and slider:GetThumbTexture().fileTexture == "Interface\\Buttons\\WHITE8X8")
assert(slider:GetThumbTexture():GetHeight() == 18, "Native slider geometry was not restored")
value = true; toggle:SetChecked(true); toggle:GetScript("OnClick")(toggle)
assert(toggle.reset:IsShown(), "Reset incorrectly requires Daylight")
local dropdown = f.Frame(parent)
dropdown.bg, dropdown.border, dropdown.inset, dropdown.label, dropdown.arrow = f.Frame(dropdown), f.Frame(dropdown), f.Frame(dropdown), f.Frame(dropdown), f.Frame(dropdown)
local clicks = 0
dropdown:SetScript("OnClick", function() clicks = clicks + 1 end)
NS.Internal.Appearance.StyleOptionsDropdown(dropdown)
daylight.SetSetting(nil, "enabled", true); f.Flush()
local visual
for _, frame in ipairs(f.frames) do
    if frame:GetParent() == dropdown and frame.allPoints == dropdown then visual = frame end
end
assert(visual and visual:IsShown() and dropdown.bg:GetAlpha()==0 and dropdown.arrow:GetAlpha()==0)
dropdown:GetScript("OnClick")()
assert(clicks == 1, "Dropdown styling replaced or repeated the selection handler")
daylight.SetSetting(nil, "enabled", false); f.Flush()
assert(not visual:IsShown() and dropdown.bg:IsShown() and dropdown.arrow:IsShown())
local savedDaylight = NS.Internal.Daylight
NS.Internal.Daylight = nil
local plain = widgets.AddToggle("No Daylight", nil, function() return true end, function(v) value = v end, function() return false end)
plain.reset:GetScript("OnClick")()
assert(value == false and plain.reset.icon.atlas == "common-icon-rotateleft")
NS.Internal.Daylight = savedDaylight

local selected = "rounded"
local menu
local choices = function() return {{value="rounded",text="Rounded border"},{value="square",text="Square border"}} end
NS.Internal.Interface.canvas.Dropdown = { Open = function(_, config) menu = config end }
local dd = widgets.AddDropdown("Style", nil, choices, function() return selected end,
    function(v) selected = v end, function() return "rounded" end)
assert(not dd.reset:IsShown(), "Default dropdown exposes reset")
dd:GetScript("OnClick")(dd); menu.onSelect("square")
assert(dd.reset:IsShown())
dd.reset:GetScript("OnEnter")(dd.reset)
assert(tip:find("Default: Rounded border", 1, true), "Dropdown default exposes internal key")
menu.onSelect("rounded"); assert(not dd.reset:IsShown())
menu.onSelect("square"); dd.reset:GetScript("OnClick")()
assert(selected == "rounded" and dd:GetText() == "Rounded border" and not dd.reset:IsShown() and refreshed == 0)

local mode, color = NS.Constants.WORLD_OVERLAY_COLOR_CUSTOM, {r=1,g=0.5,b=0}
local colorWrites = 0
local function DefaultColor() return {r=1,g=0.5,b=0} end
local swatch = widgets.AddColorRow("Color", nil, function() return mode end, function(v) mode = v end,
    function() return color end, function(v) color = v; colorWrites = colorWrites + 1 end, noop, true,
    function() return NS.Constants.WORLD_OVERLAY_COLOR_CUSTOM end, DefaultColor)
assert(not swatch.reset:IsShown(), "Equal copied color tables compare by identity")
swatch:GetScript("OnClick")(); picker.swatchFunc()
picker.swatchFunc()
assert(colorWrites == 1, "Picker confirmation repeated a live edit")
assert(swatch.reset:IsShown(), "Color edit did not reveal reset")
swatch.reset:GetScript("OnEnter")(swatch.reset)
assert(tip:find("Default: #FF8000", 1, true), "Color default is not readable")
picker.cancelFunc(DefaultColor()); assert(not swatch.reset:IsShown(), "Color cancel left stale reset")
swatch:GetScript("OnClick")(); picker.swatchFunc(); swatch.reset:GetScript("OnClick")()
assert(color.r == 1 and color.g == 0.5 and not swatch.reset:IsShown())
picker.swatchFunc()
assert(color.r == 1, "A picker opened before reset overwrote the default")
swatch:GetScript("OnClick")()
local oldPage = parent
parent = f.Frame(UIParent)
picker.swatchFunc()
picker.cancelFunc({r=0,g=0,b=0})
menu.onSelect("square")
assert(color.r == 1 and selected == "rounded", "A detached page still wrote settings")
parent = oldPage
swatch:GetScript("OnClick")()
local previousPicker = picker
local other = widgets.AddColorRow("Second Color", nil, function() return mode end, noop,
    DefaultColor, noop, noop, true)
other:GetScript("OnClick")()
swatch:GetScript("OnHide")(swatch)
previousPicker.cancelFunc({r=0,g=0,b=0})
assert(color.r == 1 and picker ~= previousPicker)

local unchanged = widgets.AddToggle("Independent", nil, function() return false end, noop, function() return false end)
assert(not unchanged.reset:IsShown() and toggle.reset:IsShown(), "Reset state leaked across settings")
local noDefault = widgets.AddToggle("No reset", nil, function() return true end, noop)
assert(not noDefault.reset)

-- Render settings through the actual page and overlay setters.
NS.Internal.Appearance.Select("awp"); f.Flush()
local canvas = NS.Internal.Interface.canvas
canvas.Widgets = widgets
assert(loadfile("interface/options/canvas_data.lua"))()
assert(loadfile("interface/options/canvas_sections.lua"))()
local draws, saves = 0, 0
NS.InvalidateOverlaySettings = noop
options.RefreshWorldOverlay = function() draws = draws + 1 end
local overlayRows = {
    ["Waypoint Opacity"] = {key="worldOverlayWaypointOpacity", changed=0.5, formatted="100%"},
    ["Navigator Size"] = {key="worldOverlayNavigatorSize", changed=1.5, formatted="100%"},
    ["Navigator Opacity"] = {key="worldOverlayNavigatorOpacity", changed=0.5, formatted="100%"},
    ["Navigator Distance"] = {key="worldOverlayNavigatorDistance", changed=1.5, formatted="1.0x"},
    ["Enable Navigator"] = {key="worldOverlayNavigatorShow", changed=false},
    ["Waypoint"] = {key="worldOverlayWaypointMode", changed="disabled"},
    ["Navigator Arrow"] = {key="worldOverlayNavArrowCustomColor", changed={r=0.2,g=0.3,b=0.4}},
}
for _, row in pairs(overlayRows) do NS.SetWorldOverlaySetting(row.key, row.changed) end
NS.SetWorldOverlaySetting("worldOverlayNavArrowColorMode", "custom")
local saveSetting = NS.SetWorldOverlaySetting
local writtenKeys = {}
NS.SetWorldOverlaySetting = function(key, v)
    writtenKeys[key] = (writtenKeys[key] or 0) + 1
    saves = saves + 1
    saveSetting(key, v)
end
parent = f.Frame(UIParent)
NS.Internal.Appearance.Tag(parent, "windows.options")
y = 16
canvas.Renderers.navigator()
canvas.Renderers.waypoint()
f.dispatchSliderEvents = true
local frameCount, refreshCount = #f.frames, refreshed
for _, widget in ipairs(f.frames) do
    local label = widget._awpSettingLabel
    local row = widget:GetParent() == parent and label and overlayRows[label:GetText()]
    if row then
        local before = draws
        assert(widget.reset:IsShown())
        widget.reset:GetScript("OnClick")(widget.reset)
        assert(writtenKeys[row.key] == 1 and draws == before + 1 and not widget.reset:IsShown(), row.key)
        if row.formatted then
            assert(widget:GetValue() == 1 and NS.Internal.Appearance.visuals[widget].valueText:GetText() == row.formatted)
        elseif row.key == "worldOverlayNavigatorShow" then
            assert(widget:GetChecked())
        elseif row.key == "worldOverlayWaypointMode" then
            assert(widget:GetText() == "Enabled")
        else
            assert(NS.GetWorldOverlaySetting("worldOverlayNavArrowColorMode") == "auto")
        end
    end
end
assert(saves == 8 and writtenKeys.worldOverlayNavArrowColorMode == 1 and refreshed == refreshCount and #f.frames == frameCount,
    "Reset rebuilt overlay controls or repeated a write")
canvas.Renderers.dugi()
for _, widget in ipairs(f.frames) do
    if widget._awpSettingLabel and widget._awpSettingLabel:GetText() == "Hide Dugi Native Guide Frame" then
        widget:SetChecked(not widget:GetChecked())
        widget:GetScript("OnClick")(widget)
        assert(widget.reset:IsShown() and refreshed == refreshCount + 1)
        widget.reset:GetScript("OnClick")()
        assert(not widget.reset:IsShown() and refreshed == refreshCount + 2)
    end
end
assert(refreshed == refreshCount + 2, "Dependent Dugi status was not refreshed")
print("Options: changed-only resets, readable defaults, live edits/color cancel, numeric input and appearance restoration passed")

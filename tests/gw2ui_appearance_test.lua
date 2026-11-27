local NativePath = dofile("tests/native_path.lua")
local f = assert(loadfile("tests/daylight_fixture.lua"))()
f.flavor = arg and arg[1] or "forever"
local ns = AzerothWaypointNS
local Frame = getmetatable(UIParent)
local buttonSkins, checkSkins, dropdownSkins, sliderSkins = 0, 0, 0, 0
local profileCallbacks = {}
local function Color(r, g, b, a)
    return { GetRGB = function() return r, g, b end, GetRGBA = function() return r, g, b, a or 1 end }
end
local gw = {
    isModern = f.flavor == "retail", mylocal = "enUS",
    settings = { fonts = {outline = "NONE", size = {normal = 14, header = 16, small = 12}} },
    Enum = { TextSizeType = {Normal = 1, Header = 2, Small = 3, BigHeader = 4} },
    texts = {},
    globalSettings = {RegisterCallback = function(_, event, callback) profileCallbacks[event] = callback end},
    BackdropTemplates = { DefaultWithSmallBorder = {}, OnlyBorder = {}, ColorableBorderOnly = {} },
    Colors = { Accent = Color(0.6, 0.4, 0.8), TextColors = { LightHeader = Color(0.95, 0.9, 0.85) },
        SkinColors = { SubText = Color(0.7, 0.7, 0.7), Disabled = Color(0.6, 0.6, 0.6),
            Positive = Color(0, 1, 0), Negative = Color(1, 0, 0), QuestGold = Color(1, 0.8, 0),
            ListSelected = Color(0.8, 0.8, 0.8), ListHover = Color(0.8, 0.8, 0.8, 0.8), StatusBarTrack = Color(1, 1, 1, 0.12),
            DarkIconButton = Color(0, 0, 0, 0.6), HighlightWhite = Color(1, 1, 1, 0.25),
            HeaderBorder = Color(1, 1, 1, 0.2), SeparatorHighlight = Color(1, 0.93, 0.73, 0.25) } },
    Libs = { LSM = { List = function() return {"Alternate"} end,
        Fetch = function(_, _, key) return key == "Alternate" and "Alternate.ttf" or nil end } },
    HandleBlizzardRegions = function(frame) assert(not frame.logical) end,
}
local head = "GWHeading.ttf"
gw.GetFontFamilies = function() return "GWBody.ttf", head end
gw.UpdateFontSettings = function() end
_G.DAMAGE_TEXT_FONT, _G.UNIT_NAME_FONT, _G.GENERAL = head, "GWBody.ttf", "General"
_G.GW2_ADDON = gw
_G.hooksecurefunc = function(object, key, hook)
    local original = object[key]
    object[key] = function(...) original(...); hook(...) end
end
function Frame:GwStripTextures() assert(not self.logical) end
function Frame:SetRotation(value) self.rotation = value end
function Frame:RegisterForClicks() end
function Frame:SetNormalTexture(file) self.normal = f.Frame(self); self.normal:SetTexture(file) end
function Frame:SetDisabledTexture(file) self.disabledTexture = f.Frame(self); self.disabledTexture:SetTexture(file) end
function Frame:SetPushedTexture(file) self.pushed = f.Frame(self); self.pushed:SetTexture(file) end
function Frame:SetCheckedTexture(file) self.checkedTexture = f.Frame(self); self.checkedTexture:SetTexture(file) end
function Frame:SetDisabledCheckedTexture(file) self.disabledCheck = f.Frame(self); self.disabledCheck:SetTexture(file) end
function Frame:GetCheckedTexture() return self.checkedTexture end
function Frame:GetDisabledCheckedTexture() return self.disabledCheck end
function Frame:GetHighlightTexture() return self.highlight end
function Frame:SetHighlightTexture(file)
    if type(file) == "string" then self.highlight = f.Frame(self); self.highlight:SetTexture(file)
    else self.highlight = file end
end
function Frame:LockHighlight() self.highlightLocked = true end
function Frame:UnlockHighlight() self.highlightLocked = false end
function Frame:GetStringWidth() return self:GetUnboundedStringWidth() end
function Frame:SetTextInsets() end
function Frame:GetOrientation() return self.orientation end
function Frame:SetJustifyV() end
local createText = Frame.CreateFontString
function Frame:CreateFontString(name, layer, template)
    local text = createText(self, name, layer, template)
    if template == "gw_button_font_black" then
        text:SetFont("GWBody.ttf", 12, "")
        text:SetTextColor(0, 0, 0, 1)
        text:SetShadowColor(0, 0, 0, 0)
    end
    return text
end

-- Load the installed GW art helpers so unexpected calls on a real control
-- or changes to GW's toolkit signatures surface in this fixture.
local function Installed(path, firstText, lastText, result, env)
    local input = assert(io.open(NativePath(f.flavor, "GW2_UI/") .. path, "rb"))
    local source = input:read("*a"); input:close()
    local first = assert(source:find(firstText, 1, true))
    local last = assert(source:find(lastText, first + #firstText, true))
    local chunk = assert(loadstring(source:sub(first, last - 1) .. result))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    return chunk()
end
local checkHelper = Installed("Core/API/toolkit.lua", "local CHECK_ART", "local function GwSkinSliderFrame",
    "\nreturn GwSkinCheckButton", { GW = gw })
local buttonHelper = Installed("Core/API/toolkit.lua", "local function GwSkinButton", "local function SetButtonFontStringColor",
    "\nreturn GwSkinButton", { HandleBlizzardRegions = gw.HandleBlizzardRegions, GwAddHover = function() end })
Installed("Core/API/editBox.lua", "local TEXTURES", "local function CreateSearchIcon", "", { GW = gw })
local backdropHelper = Installed("Core/API/toolkit.lua", "local function GwCreateBackdrop", "local function GwSkinButton",
    "\nreturn GwCreateBackdrop", {GW = gw})
gw.ReplaceSetupTextureCoordinates = function() end
function Frame:GwCreateBackdrop(...) return backdropHelper(self, ...) end
local dropdownHelper = Installed("Core/API/toolkit.lua", "local function GwHandleDropDownBox", "local ARROW_TEXTURE",
    "\nreturn GwHandleDropDownBox", {GW = gw, HandleBlizzardRegions = gw.HandleBlizzardRegions})
function Frame:GwHandleDropDownBox(...)
    assert(not self.logical)
    dropdownSkins = dropdownSkins + 1
    return dropdownHelper(self, ...)
end
local sliderHelper = Installed("Core/API/toolkit.lua", "local function GwSkinSliderFrame", "local function GwOffsetFrameLevel",
    "\nreturn GwSkinSliderFrame", {GW = gw})
function Frame:GwSkinSliderFrame(...)
    assert(not self.logical)
    sliderSkins = sliderSkins + 1
    return sliderHelper(self, ...)
end
Installed("Core/API/toolkit.lua", "local function AddSliderValueFill", "-- Brand logo stack", "", {GW = gw})
local fontFamilyHelper
if gw.isModern then
    local function CreateFontFamily(_, members)
        local fonts = {}
        for _, member in ipairs(members) do
            fonts[member.alphabet] = setmetatable({file=member.file, size=member.height, flags=member.flags}, Frame)
        end
        return {GetFontObjectForAlphabet=function(_, alphabet) return fonts[alphabet] end}
    end
    fontFamilyHelper = Installed("Core/API/toolkit.lua", "local FONT_ALPHABETS", "-- Gold value fill",
        "\nreturn GetFontFamily", {GW=gw, CreateFontFamily=CreateFontFamily})
    local setFontObject = Frame.SetFontObject
    function Frame:SetFontObject(font)
        assert(not self.logical, "Native font objects must not be assigned to logical AWP controls")
        setFontObject(self, font)
        if type(font) == "table" then
            local roman = font:GetFontObjectForAlphabet("roman")
            self:SetFont(roman:GetFont())
            self:SetShadowColor(roman:GetShadowColor())
            self:SetShadowOffset(roman:GetShadowOffset())
        end
    end
end
local nativeFontHelper = Installed("Core/API/toolkit.lua", "local function GwSetFontTemplate", "local function GwLockTextColor",
    "\nreturn GwSetFontTemplate", {GW = gw, strsub = string.sub, CreateFontFamily = gw.isModern, GetFontFamily=fontFamilyHelper})
function Frame:GwSetFontTemplate(...)
    assert(not self.logical)
    -- Fresh native samples have no inherited shadow on the legacy API path.
    self:SetShadowColor(0, 0, 0, 0); self:SetShadowOffset(0, 0)
    return nativeFontHelper(self, ...)
end
function Frame:GwSkinButton(...)
    buttonSkins = buttonSkins + 1
    buttonHelper(self, ...)
end
function Frame:GwSkinCheckButton(...)
    assert(not self.logical)
    checkSkins = checkSkins + 1
    checkHelper(self, ...)
end

local function AddOption(panel, name, description, values)
    panel.gwOptions[#panel.gwOptions + 1] = { name = name, description = description, binding = values }
    return panel.gwOptions[#panel.gwOptions]
end
Frame.AddOption, Frame.AddOptionButton, Frame.AddOptionColorPicker = AddOption, AddOption, AddOption
Frame.AddOptionSlider, Frame.AddOptionDropdown, Frame.AddGroupHeader = AddOption, AddOption, AddOption
local create = CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = create(kind, name, parent)
    if kind == "Slider" then frame.objectType = kind end
    if template == "GwSettingsPanelTmpl" then
        frame.header, frame.sub, frame.breadcrumb = f.Frame(frame), f.Frame(frame), f.Frame(frame)
        frame.gwOptions = {}
    end
    return frame
end
_G.GwSettingsWindow = f.Frame(UIParent)
local tab = f.Frame(GwSettingsWindow)
local calls, inGameOptions = 0, 0
gw.GetSettingsTabFrame = function() return tab end
function tab:AddSettingsPanel(parent, name, _, pages, isAddon)
    calls = calls + 1
    assert(parent.panelId and name == "AzerothWaypoint" and isAddon == true)
    self.pages = pages
end
ns.OpenOptionsPanel = function() inGameOptions = inGameOptions + 1 end

assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/gw2ui.lua"))()
local appearance, provider = ns.Internal.Appearance, ns.Internal.GW2UI
f.db.appearanceProvider = "auto"
f.Fire("PLAYER_LOGIN"); f.Flush()
assert(calls == 1 and #tab.pages == 4 and tab.pages[1].name == "General")
assert(appearance.GetEffectiveID() == "gw2ui" and provider.GetSettings().enabled)
tab.pages[1].frame.gwOptions[1].binding.callback()
assert(inGameOptions == 1 and not GwSettingsWindow:IsShown())
local fontOptions
for _, option in ipairs(tab.pages[2].frame.gwOptions) do
    if option.name == "Font" then fontOptions = option.binding; break end
end
assert(fontOptions and fontOptions.optionsList[1] == "general" and fontOptions.optionNames[2] == "Alternate")
fontOptions.setter("Alternate"); f.Flush()
assert(provider.GetSettings("guide.zygor").fontKey == "Alternate" and provider.GetSettings("guide.dugi").fontKey == "general")
fontOptions.setter(fontOptions.getDefault()); f.Flush()

local root = f.Frame(UIParent)
appearance.Tag(root, "windows.options")
local title, body = f.Frame(root), f.Frame(root)
appearance.Text(title, "windows.options", "TITLE")
appearance.Text(body, "windows.options", "TEXT")
assert(title:GetFont() == "GWHeading.ttf" and body:GetFont() == "GWBody.ttf")
local plaque = f.Frame(root)
local art = f.Frame(plaque); art:SetAlpha(0.77)
local record = appearance.Shell(plaque, "plaque", {art})
assert(record.currentState.root.backdrop == gw.BackdropTemplates.DefaultWithSmallBorder and art:GetAlpha() == 0)

local dropdown = f.Frame(root)
dropdown.logical = true
dropdown.label = f.Frame(dropdown)
dropdown.label.logical = true
dropdown.label:SetText("Selected value")
local originalClick = function() end
dropdown:SetScript("OnClick", originalClick)
local dropdownArt = f.Frame(dropdown)
local dropdownRecord = appearance.RegisterVisual(dropdown, {kind = "dropdown", text = dropdown.label, regions = {dropdownArt}})
assert(dropdown:GetScript("OnClick") == originalClick and dropdown:IsMouseEnabled())
local nativeDropdown = assert(dropdownRecord.currentState, provider.lastError)
assert(nativeDropdown.nativeText:GetText() == "Selected value" and dropdown.label:GetAlpha() == 0)
assert(select(2, nativeDropdown.nativeText:GetFont()) == 12 and select(3, nativeDropdown.nativeText:GetFont()) == "")
assert(nativeDropdown.nativeText.shadowAlpha == 0 and nativeDropdown.nativeText.r == 178 / 255)
assert(nativeDropdown.widget.allPoints == nativeDropdown.root and not nativeDropdown.widget:IsMouseEnabled())
assert(nativeDropdown.widget.gw2Arrow.textureFile:match("arrowup_down%.png"))
dropdown.label:SetText("Updated selection"); appearance.UpdateVisual(dropdown)
assert(nativeDropdown.nativeText:GetText() == "Updated selection")
dropdown:SetEnabled(false); appearance.UpdateVisual(dropdown)
assert(not nativeDropdown.widget:IsEnabled() and nativeDropdown.nativeText.r == 0.6)
dropdown:SetEnabled(true); appearance.UpdateVisual(dropdown)
local close = f.Frame(root)
close.logical = true
local closeText = f.Frame(close)
local closeRecord = appearance.RegisterVisual(close, {kind = "close", text = closeText})
assert(closeRecord.currentState.widget.normal.textureFile:find("window%-close%-button%-normal"))
assert(closeRecord.currentState.widget:GetWidth() == 20)
close:GetScript("OnEnter")(close)
assert(closeRecord.currentState.widget.highlightLocked and closeText:GetAlpha() == 0)
local check = f.Frame(root)
check.logical = true; check.boxBorder = f.Frame(check)
check:SetChecked(true)
appearance.RegisterToggle(check, {f.Frame(check)})
assert(appearance.visuals[check].currentState.widget:GetChecked())

local slider = CreateFrame("Slider", nil, root)
local track, track2, thumb, valueText = f.Frame(slider), f.Frame(slider), f.Frame(slider), f.Frame(root)
local value = 65
slider:SetValue(value)
local sliderRecord = appearance.RegisterSlider(slider, {track, track2, thumb}, function() return value end,
    function(nextValue) value = nextValue end, 0, 100, 5, tostring, valueText)
local input = sliderRecord.currentState.input
input:SetText("83")
input:GetScript("OnEnterPressed")(input)
assert(value == 85 and slider:GetValue() == 85 and not slider:IsMouseEnabled())
assert(sliderRecord.currentState.interactiveSlider:IsMouseEnabled())
assert(sliderSkins == 1 and dropdownSkins == 2)
assert(buttonSkins == 1 and checkSkins == 1 and not provider.lastError)

assert(loadfile("interface/framework/panels.lua"))()
local framework = ns.Internal.Interface.Framework
local queueDisclosure = framework.CreateDisclosureButton(root, 20)
local disclosureRecord = appearance.visuals[queueDisclosure]
local queueArrow = disclosureRecord.currentState.disclosure
assert(queueArrow.textureFile:match("arrowdown_down%.png") and queueArrow.rotation == 0)
queueDisclosure:SetCollapsed(true)
assert(queueArrow.rotation == math.pi / 2 and disclosureRecord.disclosureRegions[2]:GetAlpha() == 0)

ns.Internal.QueueUI = { ui = {} }
assert(loadfile("interface/queue/widgets.lua"))()
local queueUI = ns.Internal.QueueUI
local section = f.Frame(root)
appearance.Tag(section, "windows.queue")
section.bg = f.Frame(section)
section.bg:SetAlpha(0.9)
local selection = f.Frame(section)
selection:SetAlpha(0.4)
section:SetHighlightTexture(selection)
local function Toggle() end
local disclosure = queueUI.UpdateSectionAppearance(section, false, Toggle)
local headerRecord = appearance.visuals[section]
local headerArt = headerRecord.currentState
local separator
for _, frame in ipairs(f.frames) do
    if frame:GetParent() == headerArt.root and frame.textureFile then separator = frame.textureFile end
end
assert(separator and separator:match("textures/bag/bag%-sep%.png$"))
assert(headerArt.root.backdrop == gw.BackdropTemplates.ColorableBorderOnly)
assert(headerArt.root.borderColor[4] == 0.2 and headerArt.sectionHover.colorTexture[4] == 0.25)
assert(section.bg:GetAlpha() == 0 and selection:GetAlpha() == 0 and not headerArt.sectionHover:IsShown())
section:GetScript("OnEnter")(section)
assert(headerArt.sectionHover:IsShown())
section:GetScript("OnLeave")(section)
assert(not headerArt.sectionHover:IsShown())
queueUI.UpdateSectionAppearance(section)
assert(not disclosure:IsShown() and not headerArt.root:IsVisible())
assert(section.bg:GetAlpha() == 0.9 and selection:GetAlpha() == 0.4)
local frameCount = #f.frames
queueUI.UpdateSectionAppearance(section, true, Toggle)
assert(disclosure:IsShown() and headerArt.root:IsVisible() and #f.frames == frameCount)
assert(headerRecord.currentState == headerArt)

assert(loadfile("integrations/guides/viewer_header_style.lua"))()
local headerStyle = ns.Internal.GuideTrackerViewer.HeaderStyle
local module = f.Frame(UIParent)
module._awpGuideProvider = "zygor"
module.IsCollapsed = function(self) return self.collapsed end
module.Header = f.Frame(module)
module.Header.Text = f.Frame(module.Header)
module.Header.MinimizeButton = f.Frame(module.Header)
function module.Header:SetCollapsed(collapsed) module.collapsed = collapsed end
local minimize = module.Header.MinimizeButton
minimize:SetNormalTexture("Blizzard-collapse")
minimize:GetNormalTexture():SetAlpha(0.65)
local click = function() module.Header:SetCollapsed(not module:IsCollapsed()) end
minimize:SetScript("OnClick", click)
local settingsButton = f.Frame(module.Header)
settingsButton:SetNormalTexture("Blizzard-settings")
module._awpControls = { settingsBtn = settingsButton }
headerStyle.ApplyAppearance(module)
local viewerArrow = appearance.visuals[minimize].currentState.disclosure
assert(viewerArrow.rotation == 0 and minimize:GetNormalTexture():GetAlpha() == 0)
assert(appearance.visuals[settingsButton].currentState.iconHover and buttonSkins == 1)
minimize:GetScript("OnClick")()
assert(viewerArrow.rotation == math.pi / 2 and minimize:GetScript("OnClick") == click)
provider.SetSetting("guide.zygor", "controls", false); f.Flush()
assert(minimize:GetNormalTexture():GetAlpha() == 0.65 and not viewerArrow:IsVisible())
module.Header:SetCollapsed(false)
provider.SetSetting("guide.zygor", "controls", true); f.Flush()
assert(viewerArrow.rotation == 0 and minimize:GetNormalTexture():GetAlpha() == 0)

f.combat = true
head = "NextHeading.ttf"
for _ = 1, 20 do gw.UpdateFontSettings() end
f.Flush(); assert(title:GetFont() == "GWHeading.ttf")
f.combat = false; f.Fire("PLAYER_REGEN_ENABLED"); f.Flush()
assert(title:GetFont() == "NextHeading.ttf" and calls == 1)
appearance.Select("awp"); f.Flush()
assert(title:GetFont() == "AWP.ttf" and art:GetAlpha() == 0.77 and dropdownArt:GetAlpha() == 1)
assert(closeText:GetAlpha() == 1 and not sliderRecord.holder:IsShown() and slider:IsMouseEnabled())
assert(disclosureRecord.disclosureRegions[2]:GetAlpha() == 1 and minimize:GetNormalTexture():GetAlpha() == 0.65)
assert(not headerArt.root:IsVisible() and section.bg:GetAlpha() == 0.9 and selection:GetAlpha() == 0.4)
appearance.Select("gw2ui"); f.Flush()
assert(buttonSkins == 1 and checkSkins == 1 and sliderRecord.currentState.input == input)
assert(disclosureRecord.currentState.disclosure == queueArrow and appearance.visuals[minimize].currentState.disclosure == viewerArrow)
assert(headerRecord.currentState == headerArt and headerArt.root:IsVisible())
assert(not provider.lastError)

-- Native control typography has its own baseline; saved overrides still win.
local button = framework.CreatePanelButton(root)
button:SetDisplayText("Import")
button.label.logical = true
local buttonRecord = appearance.visuals[button]
assert(button.label:GetFont() == "GWBody.ttf" and select(2, button.label:GetFont()) == 12)
assert(select(3, button.label:GetFont()) == "" and button.label.shadowAlpha == 0 and button.label.r == 0)
provider.SetSurfaceSettings("windows.options", {fontKey="Alternate", outline="thick", shadow="on", customSizes=true, bodySize=17, textScale=1.25})
f.Flush()
assert(button.label:GetFont() == "Alternate.ttf" and select(2, button.label:GetFont()) == 17 * 1.25)
assert(select(3, button.label:GetFont()) == "THICKOUTLINE" and button.label.shadowAlpha == 1)
assert(nativeDropdown.nativeText:GetFont() == "Alternate.ttf" and select(2, nativeDropdown.nativeText:GetFont()) == 17 * 1.25)
assert(provider.GetSettings("guide.zygor").fontKey == "general")
provider.SetSurfaceSettings("windows.options", {fontKey="general", outline="inherit", shadow="inherit", customSizes=false, textScale=1})
f.Flush()
assert(button.label.shadowAlpha == 0 and select(3, button.label:GetFont()) == "")

-- Run the actual filter builder, including its custom enter/leave handlers.
local canvas = assert(io.open("interface/options/canvas.lua", "rb"))
local source = canvas:read("*a"); canvas:close()
local first = assert(source:find("local function CreateSearchFilterButton", 1, true))
local last = assert(source:find("local function AddSettingMarkerTag", first, true))
local filterBuilder = assert(loadstring(source:sub(first, last - 1) .. "\nreturn CreateSearchFilterButton"))
setfenv(filterBuilder, setmetatable({FW=framework, NS=ns, ColorTexture=function(region,color) region:SetColorTexture(unpack(color)) end,
    GameTooltip={SetOwner=function() end,SetText=function() end,AddLine=function() end,Show=function() end,Hide=function() end},
    GetSearchFilterText=function() return "All settings" end}, {__index=_G}))
local filter = filterBuilder()(root)
for _, event in ipairs({"OnEnter","OnLeave"}) do
    filter:GetScript(event)(filter)
    for _, icon in ipairs({filter.iconTop, filter.iconMid, filter.iconStem}) do
        assert(icon.colorTexture[1] == 1 and icon.colorTexture[2] == 1 and icon.colorTexture[3] == 1)
        local r,g,b = icon:GetVertexColor()
        assert(r == 0 and g == 0 and b == 0, "Paper-button icon retained the orange baseline")
    end
end

-- Dragging and typing share the normal setter and do not emit duplicate writes.
local writes = 0
local setValue = sliderRecord.set
sliderRecord.set = function(nextValue) writes = writes + 1; setValue(nextValue) end
f.dispatchSliderEvents = true
sliderRecord.currentState.interactiveSlider:SetValue(90, true)
assert(writes == 1 and value == 90 and slider:GetValue() == 90 and input:GetText() == "90")
input:SetText("93"); input:GetScript("OnEnterPressed")(input)
assert(writes == 2 and value == 95 and slider:GetValue() == 95)
slider:SetEnabled(false); appearance.UpdateVisual(slider)
assert(not input:IsEnabled() and not sliderRecord.currentState.interactiveSlider:IsEnabled())
slider:SetEnabled(true); appearance.UpdateVisual(slider)

local percent = CreateFrame("Slider", nil, root)
local percentValue, percentWrites = 0.5, 0
percent:SetValue(percentValue)
local percentRecord = appearance.RegisterSlider(percent, {}, function() return percentValue end,
    function(value) percentValue = value; percentWrites = percentWrites + 1 end, 0, 1, 0.05,
    function(value) return string.format("%.0f%%", value * 100) end, f.Frame(root))
percentRecord.currentState.input:SetText("83%")
percentRecord.currentState.input:GetScript("OnEnterPressed")(percentRecord.currentState.input)
assert(math.abs(percentValue - 0.85) < 0.00001 and percentWrites == 1)
assert(percentRecord.currentState.input:GetText() == "85%")

-- Font/profile signals repaint cached controls and unchanged refreshes reuse them.
local progress = f.Frame(root)
progress:SetValue(40)
local progressRecord = appearance.RegisterVisual(progress, {kind="progress",facet="shell"})
local framesBefore = #f.frames
local applied = provider.counters.applied
gw.settings.fonts.outline = "OUTLINE"
gw.settings.fonts.size.small = 15
gw.Colors.Accent = Color(0.2, 0.7, 0.9)
gw.Colors.SkinColors.HeaderBorder = Color(0.3, 0.4, 0.5, 0.6)
gw.UpdateFontSettings(); f.Flush()
assert(select(2, nativeDropdown.nativeText:GetFont()) == 15 and select(3, nativeDropdown.nativeText:GetFont()) == "OUTLINE")
assert(progressRecord.currentState.bar.statusColor[1] == 0.2 and headerArt.root.borderColor[4] == 0.6)
assert(provider.counters.applied == applied + 1 and #f.frames == framesBefore)
applied = provider.counters.applied
local resolved = provider.counters.surfacesResolved
for _ = 1, 30 do gw.UpdateFontSettings() end
f.Flush()
assert(provider.counters.applied == applied and #f.frames == framesBefore)
assert(provider.counters.surfacesResolved == resolved, "Identical refresh rebuilt effective surface settings")
local saved = provider.GetSettings("windows.help")
saved.textColor[1] = 0.375
provider.RequestRefresh(); f.Flush()
assert(provider.counters.surfacesResolved == resolved + 1, "In-place edit must rebuild only its own surface")
gw.Colors.Accent = Color(0.9, 0.6, 0.1)
assert(profileCallbacks.OnProfileChanged)(); f.Flush()
assert(progressRecord.currentState.bar.statusColor[1] == 0.9 and calls == 1 and #f.frames == framesBefore)

local action = f.Frame(root)
local actionText, actionIcon = f.Frame(action), f.Frame(action)
actionText:SetText("Use item"); actionIcon:SetVertexColor(0.2, 0.8, 0.4, 1)
local actionRecord = appearance.RegisterVisual(action, {kind="button", surface="guide.zygor", facet="actions", text=actionText,
    tints={{region=actionIcon, shade=1}}})
assert(actionRecord.currentState.iconFill and actionText.r == 1 and select(1, actionIcon:GetVertexColor()) == 0.2)

appearance.Select("awp"); f.Flush()
assert(button.label:GetFont() == "AWP.ttf" and select(3, button.label:GetFont()) == "OUTLINE")
assert(dropdown.label:GetAlpha() == 1 and not nativeDropdown.root:IsVisible() and slider:IsMouseEnabled())
local r,g,b = filter.iconTop:GetVertexColor()
assert(r == 1 and g == 0.72 and b == 0.28)
assert(button.label.shadowAlpha == 0.6, "Button typography did not restore its original shadow")
appearance.Select("gw2ui"); f.Flush()
assert(buttonRecord.currentState.textKind == "button" and button.label.shadowAlpha == 0)

local helper = Frame.GwHandleDropDownBox
Frame.GwHandleDropDownBox = nil
provider.RequestRefresh(); f.Flush()
assert(appearance.GetEffectiveID() == "awp" and dropdown.label:GetAlpha() == 1)
local _, reason = provider.GetStatus()
assert(reason:find("GwHandleDropDownBox", 1, true))
Frame.GwHandleDropDownBox = helper
provider.RequestRefresh(); f.Flush()
assert(appearance.GetEffectiveID() == "gw2ui" and not provider.lastError)
print("GW2_UI appearance (" .. f.flavor .. "): native typography/helpers, filter tint, sliders, live refresh, overrides and restoration passed")
return {f = f, a = appearance}

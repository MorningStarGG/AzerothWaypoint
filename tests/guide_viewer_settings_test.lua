local function expect(value, message) if not value then error(message, 2) end end
_G.AzerothWaypointNS = {}
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
NS.IsWoWForever = function() return false end
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
local db = NS.GetDB()
local guideStore = NS.Internal.GuideTrackerViewer
expect(guideStore.GetOpenGuides("dugi") == nil, "Missing open-guide state was not distinguishable from a closed list")
local identities = { "2393(80-83 Story)", "2405(88-90)", "2393(80-83 Story)", false, "" }
expect(guideStore.SetOpenGuides("dugi", identities), "Could not persist provider open guides")
identities[1] = "Mutated source"
local restored = guideStore.GetOpenGuides("dugi")
expect(#restored == 5 and restored[3] == "2393(80-83 Story)" and restored[4] == "" and restored[1] == "2393(80-83 Story)", "Dugi slot storage lost duplicate or empty slots")
restored[1] = "Mutated output"
expect(guideStore.GetOpenGuides("dugi")[1] == "2393(80-83 Story)", "Open-guide reads exposed saved mutable state")
expect(guideStore.GetOpenGuides("zygor") == nil and not guideStore.SetOpenGuides("missing", {}),
    "Open-guide storage affected an unrelated provider")
local firstCharacter = AzerothWaypointCharDB
_G.AzerothWaypointCharDB = {}
expect(guideStore.GetOpenGuides("dugi") == nil, "Open guides leaked to another character")
guideStore.SetOpenGuides("dugi", {})
expect(#guideStore.GetOpenGuides("dugi") == 0, "Explicitly closed guide list was treated as uninitialized")
_G.AzerothWaypointCharDB = firstCharacter
expect(#guideStore.GetOpenGuides("dugi") == 5, "Character open guides were lost")
db.guideTrackerViewerZygorEnabled, db.guideTrackerViewerDugiEnabled = true, true
NS.SetGuideTrackerViewerProviderSetting("dugi", "textColorMode", "custom")
NS.SetGuideTrackerViewerProviderSetting("dugi", "textCustomColor", { r = 0.2, g = 0.4, b = 0.6 })
expect(NS.GetGuideTrackerViewerSettings("dugi").textCustomColor.g == 0.4, "Dugi did not read its text color")
expect(NS.GetGuideTrackerViewerSettings("zygor").textColorMode == "auto" and NS.GetGuideTrackerViewerSettings("rxp").textColorMode == "auto", "Dugi color changed another provider")
NS.SetZygorStepChatSetting("textColorMode", "custom")
NS.SetZygorStepChatSetting("textCustomColor", { r = 1, g = 0, b = 0 })
NS.SetGuideTrackerViewerProviderSetting("dugi", "chatTextColorMode", "custom")
NS.SetGuideTrackerViewerProviderSetting("dugi", "chatTextCustomColor", { r = 0, g = 1, b = 0 })
expect(NS.GetZygorStepChatSettings().textCustomColor.r == 1, "Dugi chat setting overwrote Zygor's preference")
expect(NS.GetGuideTrackerViewerProviderSettings("dugi").chatTextCustomColor.g == 1, "Dugi chat color did not persist")
expect(not NS.GetGuideTrackerViewerProviderSettings("dugi").chatOutputOnChange, "New chat settings enabled Dugi output")
expect(not NS.SetGuideTrackerViewerProviderSetting("missing", "chatTextColorMode", "custom"), "Unknown provider wrote settings")
expect(not NS.SetGuideTrackerViewerProviderSetting("dugi", "showBanner", true))
expect(NS.SetGuideTrackerViewerProviderSetting("QuestieRouter", "showBanner", true))
expect(NS.GetGuideTrackerViewerProviderSettings("questierouter").showBanner)
expect(not NS.SetGuideTrackerViewerProviderSetting("dugi", "tracked", true))
local cachedSettings = NS.GetGuideTrackerViewerSettings("dugi")
local cachedProvider = NS.GetGuideTrackerViewerProviderSettings("dugi")
local colorIdentity = db.guideTrackerViewerDugiTextCustomColor
for index = 1, 1000 do
    expect(NS.GetGuideTrackerViewerSettings("dugi") == cachedSettings
        and NS.GetGuideTrackerViewerProviderSettings("dugi") == cachedProvider,
        "Unchanged settings reads rebuilt snapshots")
end
expect(db.guideTrackerViewerDugiTextCustomColor == colorIdentity, "Settings reads repeatedly normalized/replaced the stored color")
db.guideTrackerViewerDugiTextCustomColor.r = 0.3
expect(NS.GetGuideTrackerViewerSettings("dugi") ~= cachedSettings
    and NS.GetGuideTrackerViewerSettings("dugi").textCustomColor.r == 0.3,
    "In-place provider color changes left stale cached settings")
db.guideTrackerViewerDugiChatTextCustomColor.b = 0.5
expect(NS.GetGuideTrackerViewerProviderSettings("dugi") ~= cachedProvider
    and NS.GetGuideTrackerViewerProviderSettings("dugi").chatTextCustomColor.b == 0.5,
    "In-place provider color changes left stale cached settings")
db.guideTrackerViewerPosition = { point = "CENTER", relPoint = "CENTER", x = 1, y = 2 }
cachedSettings = NS.GetGuideTrackerViewerSettings("dugi")
db.guideTrackerViewerPosition.x = 3
expect(NS.GetGuideTrackerViewerSettings("dugi") ~= cachedSettings, "In-place position change was missed")
_G.AzerothWaypointDB = { guideTrackerViewerDugiEnabled = false }
expect(not NS.GetGuideTrackerViewerSettings("dugi").enabled, "Profile/DB replacement reused old provider settings")
_G.AzerothWaypointDB = db
expect(NS.GetGuideTrackerViewerSettings("dugi").enabled, "Restoring a profile did not refresh the cache")
local entries, refresh = {}, { zygor = 0, dugi = 0, rxp = 0 }
assert(loadfile("integrations/guides/viewer_registry.lua"))()
for _, key in ipairs({ "zygor", "dugi", "rxp" }) do
    local provider = key
    NS.RegisterGuideTrackerViewerProvider(key, { applySettings = function() refresh[provider] = refresh[provider] + 1 end })
end
local function toggle(label, _, get, set, default) entries[label] = { get = get, set = set, default = default } end
local function dropdown(label, _, _, get, set, default) toggle(label, nil, get, set, default) end
local function slider(label, _, _, _, _, _, get, set, default) toggle(label, nil, get, set, default) end
local function color(label, _, get, set, getColor, setColor, apply, _, default, defaultColor)
    entries[label] = { get = get, set = set, getColor = getColor, setColor = setColor, apply = apply, default = default, defaultColor = defaultColor }
end
NS.Internal.Interface = {
    canvas = { Widgets = { SectionHeader = function() end, Spacer = function() end, AddText = function() end,
        AddActionButton = function() end, AddToggle = toggle, AddSlider = slider, AddDropdown = dropdown, AddColorRow = color } }, Framework = {}, options = {},
}
NS.Internal.GuideTrackerViewer.Host = { GetDockingSupportStatus = function() return "kaliel", "KT", false end }
local ktLoaded = true
NS.IsAddonLoaded = function(name) return ktLoaded and name == "!KalielsTracker" end
_G.KT_ObjectiveTrackerFrame = {}
NS.Internal.StartupNotices = { RegisterArrow = function() return function() end end, PreferredIndex = function() return 3 end }
assert(loadfile("interface/options/shared.lua"))()
NS.Internal.Appearance = { GetProviders = function() return {} end, IsEnabled = function() return false end,
    GetEffectiveID = function() return "awp" end, StyleButton = function() end, Text = function() end, RegisterVisual = function() end }
assert(loadfile("interface/options/canvas_data.lua"))()
assert(loadfile("interface/options/canvas_sections.lua"))()
local renderers = NS.Internal.Interface.canvas.Renderers
for _, provider in ipairs({ "zygor", "dugi", "rxp" }) do
    entries = {}
    renderers[provider .. ".viewer"]()
    assert(not entries["Chat Step Text"] and not entries["Enable Guide Action Panel"])
    assert(entries["Use custom Viewer text sizes"] and not entries["Use custom Viewer text sizes"].get())
    entries["Use custom Viewer text sizes"].set(true)
    for _, size in ipairs(NS.Constants.GUIDE_VIEWER_TEXT_SIZES) do
        assert(entries[size.label] and entries[size.label].default()==size.default)
        entries[size.label].set(size.max)
        assert(NS.GetGuideTrackerViewerSettings(provider)[size.key]==size.max)
        entries[size.label].set(size.default)
    end
    entries["Use custom Viewer text sizes"].set(false)
    local options=NS.Internal.Interface.options.CreateGuideTrackerViewerColorModeOptions()
    assert(options[2].value=="theme" and options[2].text=="UI colors")
    for _, option in ipairs(NS.Internal.Interface.options.CreateWorldOverlayColorModeOptions()) do
        assert(option.value~="theme","Viewer-only Theme choice leaked into overlay settings")
    end
    renderers[provider .. ".chat"]()
    for _, label in ipairs({ "Tracker Viewer Text", "Tracker Viewer Progress Bar", "Hide Guide Title", "Hide Guide Addon Name", "Compact Active Indicator", "Show Native Docking Warning Popup",
        "Match Kaliel Header Texture", "Match Kaliel Header Background Color", "Match Kaliel Header Font",
        "Match Kaliel Header Text/Icon Color", "Match Kaliel Header Button Color", "Chat Step Text", "Chat Sticky Summary" }) do
        expect(entries[label], provider .. " omitted " .. label)
        expect(entries[label].default and entries[label].default() ~= nil, provider .. " omitted a real schema default for " .. label)
    end
    local before = {zygor=refresh.zygor,dugi=refresh.dugi,rxp=refresh.rxp}
    entries["Tracker Viewer Text"].set("auto")
    entries["Tracker Viewer Text"].apply()
    for key,count in pairs(before) do expect(refresh[key] == count + (key==provider and 1 or 0), "Color refreshed the wrong provider: "..provider.." -> "..key) end
    before = {zygor=refresh.zygor,dugi=refresh.dugi,rxp=refresh.rxp}
    entries["Tracker Viewer Progress Bar"].set("none")
    for key,count in pairs(before) do expect(refresh[key] == count + (key==provider and 1 or 0), "Progress refreshed the wrong provider") end
    expect(NS.GetGuideTrackerViewerSettings(provider).progressStyle=="none", "Provider progress style did not persist")
    entries["Match Kaliel Header Font"].set(true)
    expect(NS.GetGuideTrackerViewerSettings(provider).ktHeaderStyle.font, "KT facet was not stored for provider")
    entries["Match Kaliel Header Font"].set(false)
end
entries = {}
ktLoaded = false
_G.KT_ObjectiveTrackerFrame = nil
renderers["dugi.viewer"]()
renderers["dugi.chat"]()
expect(entries["Tracker Viewer Text"] and entries["Chat Step Text"], "Dugi-only settings lost color options without KT")
expect(not entries["Match Kaliel Header Texture"], "Kaliel-specific controls appeared without KT")
assert(loadfile("integrations/guides/viewer_styles.lua"))()
local styles = NS.Internal.GuideTrackerViewer.Styles
local r, g, b = styles.StatusToRGBForColorMode("incomplete", "goal", "collect", "custom", { r = 0, g = 1, b = 0 })
expect(styles.Colorize("Collect item", r, g, b) == "|cff00ff00Collect item|r", "Chat custom color formatting failed")
print("Independent Viewer appearance and chat settings across all three shared options pages passed")

local function widget()
    return setmetatable({}, { __index = function(_, key)
        if not key:match("^%u") or key=="MinimizeButton" then return nil end
        return function(self, ...)
            if key == "CreateTexture" or key == "CreateFontString" or key == "GetStatusBarTexture" then return widget() end
            if key == "GetFrameLevel" then return 2 end
            if key == "SetScript" then local event, callback = ...; self.scripts = self.scripts or {}; self.scripts[event] = callback end
            if key == "SetText" then self.text = (...) end
            if key == "Show" then self.shown = true end
            if key == "Hide" then self.shown = false end
        end
    end })
end
_G.CreateFrame = widget
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("integrations/guides/viewer_controls.lua"))()
local frame = widget()
frame.Header = widget(); frame.Header.Text = widget()
local controls = NS.Internal.GuideTrackerViewer.Controls
frame._awpGuideProvider="dugi"
controls.Create(frame, {})
controls.Update(frame, 22, 450)
expect(frame._awpControls.progressBar._awpStepText == "22 / 450", "Progress tooltip did not use the shared step count")
controls.Update(frame, 22, 450, 42)
expect(frame._awpControls.counter.text == "42%", "Dugi's native completion percentage was replaced by its step index")
print("Shared header controls and progress tooltip passed")
local providerReads = 0
NS.Internal.Appearance.GetProviders = function()
    providerReads = providerReads + 1
    return {}
end
assert(loadfile("interface/options/canvas_data.lua"))()
local data = NS.Internal.Interface.canvas.Data
assert(providerReads == 0, "Loading the addon built the settings search catalog")
local options, markers = data.GetOptions()
local again, sameMarkers = data.GetOptions()
assert(providerReads == 1 and options == again and markers == sameMarkers)
assert(markers.general["UI Style"].added == "5.0.0")
for _, label in ipairs({ "Tracker Viewer Text", "Match Kaliel Header Texture", "Match Kaliel Header Background Color",
    "Match Kaliel Header Font", "Match Kaliel Header Text/Icon Color", "Match Kaliel Header Button Color",
    "Chat Step Text", "Chat Sticky Summary", "Hide Guide Title", "Hide Guide Addon Name", "Compact Active Indicator" }) do
    local found = false
    for _, option in ipairs(options) do
        if option.key == "dugi" and option.label == label and option.tags:find("dugi", 1, true) then found = true end
    end
    expect(found, "Dugi search metadata omitted " .. label)
end
expect(data.OPTION_PREVIEWS["Tracker Viewer Text"], "Shared Viewer text lost its existing preview")
print("Dugi option search metadata and shared preview passed")

for _, definition in ipairs(NS.Constants.GUIDE_PROVIDERS) do
    local key = definition.key
    local actions = NS.GetGuideActionSettings(key)
    assert(not actions.enabled and not actions.inline and not actions.hideNative and actions.types.items and not actions.types.cleanup)
    assert(actions.groupPosition == "below")
    assert(NS.SetGuideActionSetting(key, "items", false))
    assert(not NS.GetGuideActionSettings(key).types.items)
    assert(NS.SetGuideActionSetting(key, "items", true))
end
assert(NS.SetGuideActionSetting("zygor", "groupPosition", "above"))
assert(NS.SetGuideActionSetting("zygor", "inline", true))
assert(NS.GetGuideActionSettings("zygor").groupPosition == "above" and NS.GetGuideActionSettings("polestar").groupPosition == "below")
assert(NS.SetGuideActionSetting("zygor", "groupPosition", NS.Internal.GuideActionDefaults.groupPosition))
assert(NS.GetGuideActionSettings("zygor").groupPosition == "below" and NS.GetGuideActionSettings("zygor").inline)
assert(NS.SetGuideActionSetting("apr", "enabled", true))
assert(NS.GetGuideActionSettings("apr").enabled and not NS.GetGuideActionSettings("wowpro").enabled)
assert(NS.SetGuideTrackerViewerProviderSetting("apr", "enabled", true))
assert(NS.GetGuideTrackerViewerProviderSettings("apr").enabled and not NS.GetGuideTrackerViewerProviderSettings("wowpro").enabled)

for index = 1, 8 do assert(guideStore.RememberOpenGuide("wowpro", "guide" .. index)) end
local recent = guideStore.GetOpenGuides("wowpro")
assert(#recent == 6 and recent[1] == "guide3" and recent[6] == "guide8")
assert(guideStore.RememberOpenGuide("wowpro", "guide3"))
recent = guideStore.GetOpenGuides("wowpro")
assert(#recent == 6 and recent[6] == "guide3" and recent[1] == "guide4")
assert(not guideStore.RememberOpenGuide("apr", "not-an-itinerary"))

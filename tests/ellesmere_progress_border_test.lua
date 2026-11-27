local context = assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local f, a, e = context.f, context.a, context.e
local NS = AzerothWaypointNS
f.prebuild, f.flavor = false, "forever"
local settings = {}
NS.GetGuideTrackerViewerSettings = function(key) return settings[key] end
assert(loadfile("integrations/guides/viewer_styles.lua"))()
assert(loadfile("integrations/guides/viewer_controls.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_header_style.lua"))()
local common = NS.Internal.GuideTrackerViewer
local controls = common.Controls
controls.LayoutHeader = function() end
common.Registry = { providers = {} }
context.change("classic")
local bars = {}
for _, key in ipairs({"zygor", "dugi", "rxp", "polestar", "apr", "wowpro", "questierouter"}) do
    settings[key] = {progressStyle = "rounded"}
    local owner = f.Frame(); owner._awpGuideProvider = key
    owner.Header = f.Frame(owner)
    local bar = f.Frame(owner.Header); bar:SetValue(34)
    bar._awpBaseRequestedWidth = 58
    bar.texture = f.Frame(bar)
    bar._awpSquareBorder = {f.Frame(bar), f.Frame(bar), f.Frame(bar), f.Frame(bar)}
    bar._awpRoundedBorder = {f.Frame(bar), f.Frame(bar), f.Frame(bar)}
    bar._awpBackground, bar._awpCounter = f.Frame(bar), f.Frame(bar)
    owner._awpControls = { progressBar = bar }
    local moduleName = "AwpProgressFixture" .. key
    _G[moduleName] = owner
    common.Registry.providers[key] = { moduleName = moduleName }
    assert(common.HeaderStyle.Refresh(owner))
    bars[key] = bar
end
local function Check(key, themed, border)
    local bar, style = bars[key], settings[key].progressStyle
    local visible = style ~= "none"
    assert(bar._awpProgressThemed == themed and bar:IsShown() == visible)
    assert(bar._awpCounter:IsShown() == visible)
    for _, edge in ipairs(bar._awpRoundedBorder) do assert(edge:IsShown() == (visible and border and style == "rounded")) end
    for _, edge in ipairs(bar._awpSquareBorder) do assert(edge:IsShown() == (visible and border and style == "square")) end
    assert(bar._awpBackground:IsShown() == not themed)
    assert(bar.texture:GetAlpha() == (themed and 0 or 1))
    if themed then
        assert(bar._awpAppearanceBar and bar._awpAppearanceBar:GetValue() == 34)
        assert(bar._awpAppearanceKeepProgressBorder == border)
        assert(bar._awpAppearanceBar:GetFrameLevel() < bar:GetFrameLevel(), "Themed fill covers the original border")
    else
        assert(not bar._awpAppearanceBar and bar._awpAppearanceKeepProgressBorder == nil)
    end
end
for key in pairs(bars) do Check(key, true, true) end
for _, style in ipairs({"square", "none", "rounded"}) do
    settings.dugi.progressStyle = style
    controls.ApplyProgressStyle(bars.dugi, "dugi")
    Check("dugi", true, true); Check("zygor", true, true)
end
for _ = 1, 3 do
    e.SetSetting("guide.zygor", "enabled", false); f.Flush()
    Check("zygor", false, true); Check("rxp", true, true)
    e.SetSetting("guide.zygor", "enabled", true); f.Flush()
    Check("zygor", true, true)
end
e.SetSetting("guide.zygor", "progress", false); f.Flush(); Check("zygor", false, true)
e.SetSetting("guide.zygor", "progress", true); f.Flush(); Check("zygor", true, true)
for _, look in ipairs({"blizzard", "forever", "eui", "classic"}) do
    context.change(look)
    for key, bar in pairs(bars) do
        Check(key, true, look == "classic")
        local state = a.visuals[bar].currentState
        local frame = state.progressFrame
        if look == "blizzard" or look == "forever" then
            assert(frame and frame.root:GetFrameLevel() > state.bar:GetFrameLevel(), "Progress frame must remain above its fill")
            assert(state.bar.allPoints == state.root, "Adding a frame shrank the progress fill")
            assert(frame.root.point[1] == "BOTTOMRIGHT" and frame.root.point[2] == state.root)
            assert(frame.root.point[4] == frame.insets.right and frame.root.point[5] == -frame.insets.bottom)
            if look == "blizzard" then
                assert(frame.root.backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border" and frame.root.backdrop.edgeSize == 8)
                assert(frame.insets.left == 2.5 and not frame.fill)
            else
                assert(frame.rim and frame.insets.left == context.ui.FOREVER_BORDER.fill and not frame.fill)
                assert(state.track.masks[1] == state.bar:GetStatusBarTexture().masks[1], "Forever fill and track need the same clipped shape")
            end
        else assert(not frame) end
    end
end
a.Select("daylight"); f.Flush()
for key in pairs(bars) do Check(key, true, false) end
a.Select("ellesmere"); f.Flush()
for key in pairs(bars) do Check(key, true, true) end
local count, rounded = #f.frames, bars.zygor._awpRoundedBorder
for _ = 1, 2000 do
    a.UpdateVisual(bars.zygor); controls.ApplyProgressStyle(bars.zygor, "zygor")
end
assert(#f.frames == count and bars.zygor._awpRoundedBorder == rounded, "Progress updates recreated border artwork")
f.flavor = "retail"; e.RequestRefresh(); f.Flush()
for key in pairs(bars) do Check(key, true, true) end
a.Select("awp"); f.Flush()
for key in pairs(bars) do Check(key, false, true) end
print("Classic progress: original borders, themed fill, independent styles, visibility, toggles, appearance switching and reuse passed")

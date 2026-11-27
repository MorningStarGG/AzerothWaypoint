local styles = {"Minimal", "Forever", "Blizzard", "Classic", "Clean", "Modern"}
local function alpha(layer)
    return layer.low and layer.low.a or layer.fill.vertex[4]
end
for _, client in ipairs({"retail", "forever"}) do
    local env = assert(loadfile("tests/plaque_appearance_test.lua"))(client)
    local M, p, settings = env.M, env.p, env.settings
    for _, name in ipairs(styles) do
        M.SwapPinpointPlaqueType(name)
        env.NS.SetPlaqueAppearanceSetting(name,"backgroundOpacity",0)
        env.NS.SetPlaqueAppearanceSetting(name,"borderOpacity",30)
        env.render(); p.Panel:SetVertexColor(1, 1, 1, 1)
        local layer = p.Panel._renderer
        assert(alpha(layer) == 0, name .. " middle did not become transparent")
        for _, part in ipairs(layer.parts) do
            if part.role == "border" then assert(part.texture.vertex[4] == .3) end
        end
        if layer.border then assert(layer.border.Top.vertex[4] == .3) end
        if layer.stockBorder then assert(layer.borderColor[4] == .3) end
        local titleAlpha, diamondAlpha = p.Title:GetAlpha(), p.ContextIcon:GetAlpha()
        env.NS.SetPlaqueAppearanceSetting(name,"backgroundOpacity",100)
        env.NS.SetPlaqueAppearanceSetting(name,"borderOpacity",0)
        env.render(); p.Panel:SetVertexColor(1, 1, 1, 1)
        assert(alpha(layer) == 1)
        for _, part in ipairs(layer.parts) do
            if part.role ~= "background" then assert(part.texture.vertex[4] == 0) end
        end
        if layer.border then assert(layer.border.Top.vertex[4] == 0) end
        if layer.stockBorder then assert(layer.borderColor[4] == 0) end
        assert(p.Title:GetAlpha() == titleAlpha and p.ContextIcon:GetAlpha() == diamondAlpha)
        for key, value in pairs(env.NS.Constants.PLAQUE_APPEARANCE_DEFAULTS[name]) do
            env.NS.SetPlaqueAppearanceSetting(name,key,value)
        end
        env.render(); p.Panel:SetVertexColor(1, 1, 1, 1)
        local expected = name == "Clean" and .92 or .85
        assert(alpha(layer) == expected, name .. " lost its authored default alpha")
    end
    local frames = #env.f.frames
    for _, name in ipairs({"Minimal", "Clean", "Modern"}) do
        M.SwapPinpointPlaqueType(name)
        for width = 1, 8 do
            env.NS.SetPlaqueAppearanceSetting(name,"borderThickness",width)
            env.render(); env.assertLayerOrder()
            local layer = p.Panel._renderer
            local layout = M.Plaques.GetLayoutSpec(p)
            local stroke = width + (name == "Minimal" and 1 or 0)
            assert(layer._thickness == width and layout.textInsetTop >= stroke + 4)
            assert(layout.textInsetX >= stroke + 4)
            assert(p.TextHost.point[5] == layout.textInsetBottom, "Live thickness did not update anchors")
            if name ~= "Minimal" then
                -- These partitions must share the same destination rectangle.
                assert(layer.fill.point[4] == 0 and layer.fill.point[5] == 0)
                assert(layer.band.point[4] == 0 and layer.band.point[5] == 0)
                assert(layer.fill._shapeMask.allPoints == layer.fill)
                assert(layer.band._shapeMask.allPoints == layer.band)
                assert(layer.fill._shapeMask.texture:find("-fill-" .. width .. ".tga", 1, true))
            end
            local fillTint = layer.fill.vertex
            local writes = layer.fill.gradientWrites
            local maskPath = layer.fill._shapeMask and layer.fill._shapeMask.texture
            for _ = 1, 1000 do env.render() end
            assert(layer.fill.vertex == fillTint and layer.fill.gradientWrites == writes)
            assert(not maskPath or layer.fill._shapeMask.texture == maskPath)
        end
    end
    assert(#env.f.frames == frames, "Changing opacity/thickness allocated new renderers or masks")
    for _, name in ipairs({"Fantasy", "GlowingGems", "ModernPlaque", "HordePlaque", "AlliancePlaque", "SteamPunkPlaque"}) do
        local opacity, thickness = M.Plaques.GetAppearanceSupport(name)
        assert(not opacity and not thickness)
    end
    assert(loadfile("core/routing_backends.lua"))()
    assert(loadfile("core/db_defaults.lua"))()
    assert(loadfile("core/db.lua"))()
    assert(loadfile("core/guide_settings.lua"))()
    assert(env.NS.SetPlaqueAppearanceSetting("Modern","backgroundOpacity",120))
    assert(env.NS.GetPlaqueAppearance("Modern").backgroundOpacity == 100)
    assert(env.NS.SetPlaqueAppearanceSetting("Modern","borderThickness",30))
    assert(env.NS.GetPlaqueAppearance("Modern").borderThickness == 8)
    print("Plaque opacity, thickness, text padding and cached reuse passed: " .. client)
end

-- Check the packaged mask alpha, not just the Lua geometry. Every thickness
-- must partition the same outer silhouette without an empty internal strip.
local function mask(name)
    local f = assert(io.open("media/world-overlay/plaques/plaque-" .. name .. ".tga", "rb"))
    local data = f:read("*a"); f:close()
    assert(data:byte(3) == 2 and data:byte(17) == 32)
    local result = {}
    for pixel = 0, 1023 do result[pixel + 1] = data:byte(22 + pixel * 4) end
    return result
end
for _, name in ipairs({"clean", "modern"}) do
    local fill1, rim1 = mask(name .. "-fill-1"), mask(name .. "-rim-1")
    for width = 1, 8 do
        local fill, rim = mask(name .. "-fill-" .. width), mask(name .. "-rim-" .. width)
        local outline, inner
        if name == "modern" and width >= 3 then
            outline, inner = mask("outline-6"), mask("modern-inner-" .. width)
        end
        for pixel = 1, 1024 do
            local sum = fill[pixel] + rim[pixel] + (outline and outline[pixel] or 0) + (inner and inner[pixel] or 0)
            assert(math.abs(sum - fill1[pixel] - rim1[pixel]) <= 2, name .. " has a gap at thickness " .. width)
        end
    end
end
print("Rounded fill/border coverage is continuous for all thicknesses")

-- Render the actual settings section: changing styles must update enabled
-- controls without rebuilding a page or waiting for another UI event.
local env = assert(loadfile("tests/plaque_appearance_test.lua"))("retail")
local NS, f = env.NS, env.f
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
local controls, themed = {}, false
local function noop() end
local widgets = {SectionHeader=noop, Spacer=noop, AddText=noop, AddToggle=noop, AddColorRow=noop}
function widgets.AddSlider(label, _, low, high, step, format, get, set, default)
    local control = f.Frame()
    control._awpSettingLabel, control.reset = f.Frame(), f.Frame()
    control.get, control.set, control.default, control.format = get, set, default, format
    control.min, control.max = low, high
    controls[label] = control
    return control
end
function widgets.AddDropdown(label, _, _, get, set)
    controls[label] = {get=get, set=set}
end
NS.Internal.Interface = {Framework={}, canvas={Widgets=widgets}, options={
    SettingDefault=function(key) return function() return NS.Internal.OverlaySettingDefs[key].default end end,
    FormatWorldOverlayDistance=tostring, RefreshWorldOverlay=noop,
}}
NS.Internal.Appearance.provider = {label="Test UI"}
NS.Internal.Appearance.IsEnabled = function() return themed end
NS.Internal.Appearance.GetProviders = function() return {} end
NS.SwapNativePinpointPlaque = env.M.SwapPinpointPlaqueType
assert(loadfile("interface/options/canvas_data.lua"))()
assert(loadfile("interface/options/canvas_sections.lua"))()
local render = NS.Internal.Interface.canvas.Renderers.pinpoint
local function enabled(opacity, thickness)
    assert(controls["Plaque Background Opacity"]:IsEnabled() == opacity)
    assert(controls["Plaque Border Opacity"]:IsEnabled() == opacity)
    assert(controls["Plaque Border Thickness"]:IsEnabled() == thickness)
end
NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType", "Fantasy")
NS.GetDB().plaqueAppearance = nil
render(); enabled(false, false)
controls["Plaque Style"].set("Forever"); enabled(true, false)
controls["Plaque Style"].set("Clean"); enabled(true, true)
local background = controls["Plaque Background Opacity"]
local border, thickness = controls["Plaque Border Opacity"], controls["Plaque Border Thickness"]
assert(background.min == 0 and background.max == 100 and thickness.min == 1 and thickness.max == 8)
assert(background.default() == 92 and background.get() == 92 and background:GetValue() == 92)
assert(border.default() == 50 and border:GetValue() == 50)
assert(background.format(0) == "0%" and background.format(92) == "92%")
background.set(35); assert(background.get() == 35)
background.set(background.default()); assert(background.get() == 92)
assert(not NS.GetDB().plaqueAppearance or not NS.GetDB().plaqueAppearance.Clean)
controls["Plaque Style"].set("Modern")
assert(background:GetValue() == 85 and border:GetValue() == 100 and thickness:GetValue() == 4)
for _, control in ipairs({background, border, thickness}) do
    for value = control.min, control.max do
        control.set(value)
        assert(control.get() == value, "Slider jumped at a style-default value")
    end
    for value = control.max, control.min, -1 do
        control.set(value)
        assert(control.get() == value, "Slider reversed at a style-default value")
    end
    control.set(control.default())
end
background.set(42)
controls["Plaque Style"].set("Clean")
assert(background:GetValue() == 92 and border:GetValue() == 50 and thickness:GetValue() == 1)
controls["Plaque Style"].set("Modern")
assert(background:GetValue() == 42, "A style override was not remembered independently")
controls["Plaque Style"].set("Clean")
background.set(background.default())
controls["Plaque Style"].set("Minimal")
assert(background:GetValue() == 85 and border:GetValue() == 100 and thickness:GetValue() == 1)
themed = true
render(); enabled(false, false)
themed = false
render(); enabled(true, true)
print("Plaque setting support, resets and shell override states passed")

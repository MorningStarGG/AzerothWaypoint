-- Exercise the actual factory, schema and live render path without UI addons.
local styles = {"Forever", "Blizzard", "Classic", "Clean", "Modern"}
local function check(client)
    local env = assert(loadfile("tests/plaque_appearance_test.lua"))(client)
    local f, NS, M, p = env.f, env.NS, env.M, env.p
    local renderers = {}
    for _, name in ipairs(styles) do
        M.SwapPinpointPlaqueType(name)
        env.render()
        env.assertLayerOrder()
        local renderer = p.Panel._renderer
        renderers[name] = renderer
        assert(p.Panel._styles[name] == renderer and env.effectiveShown(renderer))
        assert(not p.Gems and not p.Overlay, name .. " inherited legacy effects")
        assert(p.PanelHost:GetHeight() == (name == "Modern" and 52 or 44))
        if renderer.border then
            assert(renderer.border:GetFrameLevel() < p.ContextIcon:GetFrameLevel())
            assert(renderer.border:GetFrameLevel() < p.TextHost:GetFrameLevel())
            assert(not renderer.border.Center, "Bundled frame center was drawn twice")
            assert(#renderer.border.__awpTextures == 8)
            for _, texture in ipairs(renderer.border.__awpTextures) do
                assert(texture.masks[1] == renderer.ringMask)
                for _, coord in ipairs(texture.uv) do assert(coord >= 1/128 and coord <= 111/128) end
            end
            local border, spec = renderer.border, M.Plaques.GetSpec(name)
            assert(spec.texture:find("AzerothWaypoint\\media\\world-overlay\\plaques\\" .. name .. "Plaque.blp", 1, true))
            -- Very short previews crop corners instead of overlapping them.
            border:GetScript("OnSizeChanged")(border, 224, 14)
            assert(border.TopLeft:GetHeight() == 7 and border.BottomLeft:GetHeight() == 7)
            assert(not border.Left:IsShown() and not border.Right:IsShown())
            assert(border.TopLeft.uv[4] == 15/128, "Cropped corner changed source scale")
            border:GetScript("OnSizeChanged")(border, 224, 52)
            assert(border.Left:IsShown() and border.Right:IsShown())
            local coords = border.TopLeft.uv
            for _ = 1, 1000 do border:GetScript("OnSizeChanged")(border, 224, 52) end
            assert(border.TopLeft.uv == coords, "Unchanged size reconfigured the frame source")
        end
        if name == "Classic" then
            assert(renderer.backdrop.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border")
        elseif name == "Clean" then
            assert(renderer.fill.masks[1].texture:find("plaque-clean-fill-1.tga", 1, true))
        elseif name == "Modern" then
            assert(renderer.shadow and renderer.band and renderer.bevelTop and renderer.bevelBottom)
            assert(renderer.shadow.masks[1].slices[1] == 16)
        end
        env.settings.worldOverlayShowExtendedInfo = false
        env.render()
        assert(p.PanelHost:GetHeight() == (name == "Modern" and 40 or 32), "Title-only layout left space")
        env.settings.worldOverlayShowExtendedInfo = true
        env.render(string.rep("Long title ", 10), string.rep("Useful instruction ", 12))
        assert(p.PanelHost:GetHeight() > 52 and p.PanelHost:GetWidth() <= 224)
        local count = #f.frames
        for _ = 1, 1000 do env.render() end
        assert(#f.frames == count, "Unchanged updates rebuild standalone artwork")
    end
    -- A new style is built lazily; switching back must reuse it and its masks.
    local count = #f.frames
    for _ = 1, 3 do
        for _, name in ipairs(styles) do
            M.SwapPinpointPlaqueType(name); env.render(); env.assertLayerOrder()
            assert(p.Panel._renderer == renderers[name])
            for other, renderer in pairs(renderers) do assert(renderer:IsShown() == (other == name)) end
        end
    end
    assert(#f.frames == count)
    local modern = renderers.Modern
    p.Panel:SetVertexColor(.4, .6, .8, .5)
    assert(modern.fill.vertex[1] == .078*.4 and modern.fill.vertex[4] == .85*.5)
    local tint = modern.fill.vertex
    for _ = 1, 1000 do p.Panel:SetVertexColor(.4, .6, .8, .5) end
    assert(modern.fill.vertex == tint, "Unchanged tint rewrote the standalone parts")
    assert(not DaylightUI and not NS.Internal.Daylight and not NS.Internal.Ellesmere and not NS.Internal.ElvUI)
    assert(loadfile("core/routing_backends.lua"))()
    assert(loadfile("core/db_defaults.lua"))()
    assert(loadfile("core/db.lua"))()
    assert(loadfile("core/guide_settings.lua"))()
    for _, name in ipairs(styles) do
        assert(NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType", name) == name)
        assert(NS.GetWorldOverlaySetting("worldOverlayPinpointPlaqueType") == name)
    end
    assert(NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType", "ModernPlaque") == "ModernPlaque")
    assert(M.Plaques.GetSpec("ModernPlaque").texture:find("plaques\\FuturePlaque", 1, true))
    assert(M.Plaques.GetSpec("Fantasy").texture:find("plaques\\FantasyPlaque", 1, true))
    NS.SetPlaqueAppearanceSetting("Modern", "backgroundOpacity", 50)
    local parent = f.Frame()
    local sample = M.Plaques.ShowSample(parent, nil, "Modern")
    assert(sample._backgroundOpacity == 50 and sample:GetWidth() == 224, "Settings sample did not show saved opacity")
    assert(M.Plaques.ShowSample(parent, sample, "Modern", true) == sample and sample._backgroundOpacity == 85,
        "Help sample did not reuse the renderer and show the style default")
    M.Plaques.ShowSample(parent, sample, "Forever", true)
    assert(sample.__awpPlaqueType == "Forever" and not sample._styles.Modern:IsShown(), "Reused sample retained prior artwork")
    assert(loadfile("interface/startup_notices.lua"))()
    assert(loadfile("interface/options/shared.lua"))()
    assert(loadfile("interface/options/canvas_data.lua"))()
    assert(loadfile("docs/help_pages.lua"))()
    local options = NS.Internal.Interface.options.CreateWorldOverlayPlaqueTypeOptions()
    local labels = {}
    for _, option in ipairs(options) do labels[option.value] = option.text end
    assert(labels.ModernPlaque == "Future" and labels.Modern == "Modern")

    local helpSamples = {}
    for _, page in ipairs(NS.HELP_PAGES) do
        if page.id == "overlay_pinpoint_plaque" then
            for _, block in ipairs(page.blocks) do
                for _, item in ipairs(block.items or {}) do
                    if item.plaqueType then helpSamples[item.plaqueType] = item end
                end
            end
        end
    end

    local effectsByType = {}
    for name in pairs(NS.Constants.WORLD_OVERLAY_PLAQUE_TYPES) do
        local preview = NS.Internal.Interface.canvas.Data.OPTION_VALUE_PREVIEWS["Plaque Style"][name]
        assert(preview.plaqueType == name and not preview.image)
        local help = assert(helpSamples[name], "Help is missing a live sample for " .. name)
        assert(labels[name] and help.caption == labels[name] and not help.texture)

        local previousEffects = sample._visibleSampleEffects
        assert(M.Plaques.ShowSample(parent, sample, name, true) == sample)
        assert(not previousEffects or not previousEffects:IsShown(), "Previous plaque effects stayed visible")
        local spec = M.Plaques.GetSpec(name)
        assert(sample:GetHeight() >= spec.baseH and sample:GetHeight() < help.height and sample:GetWidth() < help.width)
        if not spec.renderer then
            assert(sample._atlas.TopLeft.texture == spec.texture, "Preview did not use the plaque artwork")
        end
        local effects = sample._visibleSampleEffects
        local animSpecs = M.PlaqueAnimations.GetSpec(name)
        assert((effects ~= nil) == (animSpecs ~= nil))
        if effects then
            assert(env.effectiveShown(effects) and not effects:GetScript("OnUpdate"))
            effectsByType[name] = effects
        end
    end
    local totalFrames = #f.frames
    for name, effects in pairs(effectsByType) do
        M.Plaques.ShowSample(parent, sample, name, true)
        assert(sample._visibleSampleEffects == effects and env.effectiveShown(effects))
    end
    assert(#f.frames == totalFrames, "Revisiting a plaque preview rebuilt the effect layers")

    NS.SetWorldOverlaySetting("worldOverlayPinpointAnimatePlaqueEffects", false)
    M.Plaques.ShowSample(parent, sample, "GlowingGems")
    local gems = effectsByType.GlowingGems
    local glowAlpha = M.PlaqueAnimations.GetSpec("GlowingGems")[1].glow.base
    for _, glow in ipairs(gems.glows) do
        assert(glow.alpha == glowAlpha and not env.effectiveShown(glow))
    end
    M.Plaques.ShowSample(parent, sample, "GlowingGems", true)
    for _, glow in ipairs(gems.glows) do assert(env.effectiveShown(glow)) end

    print("Standalone plaques: " .. client .. " geometry, layout, cache, tint, schema and previews passed")
end
check("retail")
check("forever")

-- Appearance matching still overrides any selected native style and restores it.
local env = assert(loadfile("tests/plaque_appearance_test.lua"))()
for _, name in ipairs(styles) do
    env.M.SwapPinpointPlaqueType(name); env.render(); env.assertLayerOrder()
    env.d.SetSetting(nil, "enabled", true); env.f.Flush(); env.render()
    assert(env.p.__awpThemedPlaque and not env.effectiveShown(env.p.Panel))
    env.d.SetSetting("plaque", "shell", false); env.f.Flush(); env.render(); env.assertLayerOrder()
    assert(not env.p.__awpThemedPlaque and env.effectiveShown(env.p.Panel._styles[name]))
    assert(env.p.__awpPlaqueType == name)
    env.d.SetSetting("plaque", "shell", true)
    env.d.SetSetting(nil, "enabled", false); env.f.Flush(); env.render()
end
print("Standalone plaques: appearance override and restoration passed")

local expected = {
    Minimal={backgroundOpacity=85,borderOpacity=100,borderThickness=1},
    Forever={backgroundOpacity=85,borderOpacity=100}, Blizzard={backgroundOpacity=85,borderOpacity=100},
    Classic={backgroundOpacity=85,borderOpacity=100}, Clean={backgroundOpacity=92,borderOpacity=50,borderThickness=1},
    Modern={backgroundOpacity=85,borderOpacity=100,borderThickness=4},
}
for _, client in ipairs({"retail","forever"}) do
    local env = assert(loadfile("tests/plaque_appearance_test.lua"))(client)
    local NS, M, p = env.NS, env.M, env.p
    assert(NS.GetDB().plaqueAppearance == nil)
    for name, defaults in pairs(expected) do
        local settings = NS.GetPlaqueAppearance(name)
        assert(settings == NS.GetPlaqueAppearance(name), "Unchanged reads did not reuse resolved settings")
        for key, value in pairs(defaults) do assert(settings[key] == value, name .. " default: " .. key) end
        M.SwapPinpointPlaqueType(name); env.render()
        assert(p.Panel._backgroundOpacity == defaults.backgroundOpacity and p.Panel._borderOpacity == defaults.borderOpacity)
        assert(p.Panel._borderThickness == defaults.borderThickness)
    end
    assert(NS.GetDB().plaqueAppearance == nil, "Reading/rendering defaults materialized overrides")
    assert(NS.SetPlaqueAppearanceSetting("Modern","backgroundOpacity",30))
    assert(NS.SetPlaqueAppearanceSetting("Forever","backgroundOpacity",65))
    assert(NS.SetPlaqueAppearanceSetting("Modern","borderThickness",6))
    local cached = NS.GetPlaqueAppearance("Modern")
    local stored = NS.GetDB().plaqueAppearance.Modern
    for _ = 1, 1000 do assert(NS.SetPlaqueAppearanceSetting("Modern","backgroundOpacity",30)) end
    assert(NS.GetDB().plaqueAppearance.Modern == stored and NS.GetPlaqueAppearance("Modern") == cached,
        "Unchanged edits rebuilt stored/resolved profiles")
    for _, name in ipairs({"Modern","Forever","Modern","Blizzard","Forever"}) do
        M.SwapPinpointPlaqueType(name); env.render()
        local alpha = name == "Modern" and 30 or name == "Forever" and 65 or 85
        assert(p.Panel._backgroundOpacity == alpha, "A style inherited another plaque's adjustment")
    end
    -- The previewed style owns its profile even while a different one is active.
    local preview = M.Plaques.CreatePanel(env.f.Frame(),"Modern")
    M.Plaques.ApplyAppearance(preview,NS.GetPlaqueAppearance("Modern"))
    assert(preview._backgroundOpacity == 30 and preview._borderThickness == 6)
    assert(NS.GetPlaqueAppearance("Forever").backgroundOpacity == 65)
    for name, defaults in pairs(expected) do
        for key, value in pairs(defaults) do NS.SetPlaqueAppearanceSetting(name,key,value) end
    end
    assert(NS.GetDB().plaqueAppearance == nil, "Reset left empty/default override records")
    assert(not NS.SetPlaqueAppearanceSetting("Forever","borderThickness",4))
    assert(not NS.SetPlaqueAppearanceSetting("Fantasy","backgroundOpacity",50))
    assert(not NS.SetPlaqueAppearanceSetting("Modern","backgroundOpacity",0/0))
    assert(not NS.SetPlaqueAppearanceSetting("Modern","backgroundOpacity",math.huge))
    assert(NS.GetPlaqueAppearance("Default") == nil)
    local fallback = M.Plaques.CreatePanel(env.f.Frame(),"Default")
    assert(fallback.__awpPlaqueType == (client == "forever" and "Forever" or "Blizzard"), "Retired identity aliased Fantasy")
    M.SwapPinpointPlaqueType("Default")
    assert(p.__awpPlaqueType == fallback.__awpPlaqueType, "Retired identity survived on the live frame")
    for _, key in ipairs({"worldOverlayPlaqueBackgroundOpacity","worldOverlayPlaqueBorderOpacity","worldOverlayPlaqueBorderThickness"}) do
        assert(NS.GetWorldOverlaySetting(key) == nil and NS.SetWorldOverlaySetting(key,50) == nil)
        assert(NS.GetDB()[key] == nil)
    end
    print("Plaque profiles: " .. client .. " defaults, independence, previews, cache reuse, reset and identity fallback passed")
end

local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

local C = NS.Constants

-- Zygor arrow skins. Only registers when ZygorGuidesViewer is installed and enabled.
-- All theme-building, animation, hooks, and suppression live in core/arrowskins.lua.
-- These are also the canonical examples of the zygor_mirror / zygor_full preset formats.

NS.RegisterArrowSkin(C.SKIN_STARLIGHT, {
    themeKey    = C.THEME_STARLIGHT,
    displayName = "Zygor Starlight",
    preset      = "zygor_mirror",
    skinDir     = NS.GetZygorAssetPath("Arrows\\Starlight\\"),
    -- Files resolved from skinDir by the zygor_mirror preset:
    --   arrow             navigation sprite sheet (1024×1024, 102×68 cells, 75 base frames, mirrored)
    --   arrow-specular    specular/highlight overlay (same dimensions, ADD blend)
    --   specials          arrival + misc icons (8×2 grid, cell 1,1 = arrival icon)
})

NS.RegisterArrowSkin(C.SKIN_STEALTH, {
    themeKey    = C.THEME_STEALTH,
    displayName = "Zygor Stealth",
    preset      = "zygor_full",
    skinDir     = NS.GetZygorAssetPath("Arrows\\Stealth\\"),
    -- Files resolved from skinDir by the zygor_full preset:
    --   arrow             navigation sprite sheet (1024×1024, 102×68 cells, 150 full frames)
    --   arrow-specular    specular/highlight overlay (same dimensions, ADD blend)
    --   specials          arrival + misc icons (8×2 grid, cell 1,1 = arrival icon)
    --
    -- Stealth-specific: snap to a distinct color when facing the destination closely.
    precise = {
        range  = 3,
        smooth = false,
        r      = 0.4,
        g      = 1.0,
        b      = 0.3,
    },
})

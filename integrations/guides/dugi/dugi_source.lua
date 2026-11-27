-- ============================================================
-- Dugi waypoint identification
-- ============================================================
--
-- Identifies TomTom waypoints published by Dugi for the external waypoint
-- registry.

local NS = _G.AzerothWaypointNS

NS.RegisterExternalWaypointSource("dugi", {
    displayName = "Dugi Guides",
    aliases = { "DugisGuideViewerZ", "DugisGuideViewer", "Dugi" },
    stackMatches = {
        "interface\\addons\\dugisguideviewerz",
        "dugisguideviewerz\\",
    },
    guideProvider = "dugi",
    transient = true,
    iconKey = "dugi",
})

-- ============================================================
-- SilverDragon waypoints
-- ============================================================
--
-- Registers SilverDragon rare sightings as temporary waypoint sources.

local NS = _G.AzerothWaypointNS

NS.RegisterExternalWaypointSource("silverdragon", {
    displayName = "SilverDragon",
    stackMatches = {
        "silverdragon\\integration\\tomtom.lua",
    },
    transient = true,
    iconKey = "silverdragon",
})

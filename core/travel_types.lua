-- ============================================================
-- Travel types for presentation
-- ============================================================
--
-- Provides the travel names shared by waypoint and tracker presentation.
-- Native planner kinds remain on their legs and drive advancement.

local NS = _G.AzerothWaypointNS

local aliases = {
    carrier = "travel",
    walk = "travel",
    fly = "travel",
    tram = "travel",
    boat = "ship",
    hearthstone = "hearth",
}

function NS.NormalizeTravelType(value)
    if type(value) ~= "string" then return nil end
    return aliases[value] or value
end

function NS.IsVehicleTravelType(value)
    value = NS.NormalizeTravelType(value)
    return value == "ship" or value == "zeppelin" or value == "airship"
end

function NS.ResolveCarrierTravelType(value, role, kind)
    value = NS.NormalizeTravelType(value)
    if value then return value end
    if role ~= "carrier" then return nil end
    kind = NS.NormalizeTravelType(kind)
    if kind == "portal" or kind == "taxi" or kind == "hearth" or NS.IsVehicleTravelType(kind) then return kind end
    return "travel"
end

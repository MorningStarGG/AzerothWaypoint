-- ============================================================
-- Addon metadata and load timings
-- ============================================================
--
-- Records load-group timings and reads the addon's name and version for the
-- shared namespace.

local ADDON_NAME, private = ...
if GetTimePreciseSec then
    local started = GetTimePreciseSec()
    local previous = started
    local groups = {}
    private.fileLoadGroups = groups
    -- Boundaries run at the end of unconditional TOC chunks on both clients.
    private.finishLoadGroup = function(label)
        local now = GetTimePreciseSec()
        groups[#groups + 1] = { label = label, ms = (now - previous) * 1000 }
        previous = now
        return (now - started) * 1000
    end
end

local NS = _G.AzerothWaypointNS
if type(NS) ~= "table" then
    NS = {}
    _G.AzerothWaypointNS = NS
end

function NS.GetAddonMetadataValue(field, fallback)
    local value = C_AddOns.GetAddOnMetadata(ADDON_NAME, field)
    if value == nil or value == "" then
        return fallback
    end
    return value
end

NS.ADDON_NAME = ADDON_NAME
NS.VERSION = NS.GetAddonMetadataValue("Version", "0.0.0")
NS.BUILD = 1

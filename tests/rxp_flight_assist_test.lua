_G.AzerothWaypointNS = {}
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
local C = NS.Constants
NS.State.routing = { activeGuideProvider = "rxp" }
local active, enabled, intent, taken = nil, true, { kind = "flight", destinationName = "Stormwind", nodeID = 2,
    guideID = "Guide", guideEpoch = 1, stepIndex = 1, elementIndex = 2 }, 0
NS.IsRoutingEnabled = function() return enabled end
NS.GetActiveAuthorityRecord = function() return active end
NS.After = function(_, fn) fn() end
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp", { label = "RestedXP", isLoaded = function() return true end,
    getTravelIntent = function() return intent end })
local noop = function() end
local function frame()
    return setmetatable({ SetScript = function(self, key, fn) self[key] = fn end,
        GetEffectiveScale = function() return 1 end, GetSize = function() return 20, 20 end,
        CreateTexture = function() return frame() end, CreateAnimationGroup = function() return frame() end,
        CreateAnimation = function() return frame() end }, { __index = function() return noop end })
end
_G.UIParent = frame()
local taxiEvents
_G.CreateFrame = function()
    local f = frame()
    taxiEvents = taxiEvents or f
    return f
end
_G.C_Timer = { After = NS.After }
local nodes = {
    { nodeID = 2, slotIndex = 1, name = "Hurlevent, Elwynn", state = "reachable", position = { .5, .5 } },
    { nodeID = 4, slotIndex = 2, name = "Sentinel Hill, Westfall", state = "reachable", position = { .7, .7 } },
}
local pins = {}
for _, data in ipairs(nodes) do pins[#pins + 1] = { taxiNodeData = data, IsShown = function() return true end } end
local shown = true
_G.FlightMapFrame = { IsShown = function() return shown end, GetMapID = function() return 13 end,
    HookScript = noop, EnumeratePinsByTemplate = function()
        local i = 0; return function() i = i + 1; return pins[i] end
    end }
_G.TakeTaxiNode = function(slot) taken = taken + 1; assert(slot == 2, "Wrong backend flight taken") end
_G.InCombatLockdown = function() return false end
NS.GetFlightMapAssistSettings = function() return { marker = true, autoTakeMode = C.FLIGHT_MAP_AUTO_TAKE_STRONG } end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/flightmap_window.lua"))()
assert(loadfile("bridge/flightmap_match.lua"))()
assert(loadfile("bridge/flightmap_assist.lua"))()
NS.InitializeFlightMapAssist()
local function statusChanged()
    taxiEvents.OnEvent(taxiEvents, "TAXI_NODE_STATUS_CHANGED")
end
local match = NS.GetFlightMapAssistMatch()
assert(match and match.source == "guide" and match.nodeID == 2 and match.providerLabel == "RestedXP", "Canonical ID failed against localized flight name")
assert(taken == 0, "Guide-only recommendation took a flight automatically")
local cache = NS.State.flightMapAssist.guideMatchCache
for _ = 1, 100 do assert(NS.GetFlightMapAssistMatch().nodeID == 2) end
assert(NS.State.flightMapAssist.guideMatchCache == cache, "Unchanged flight map rebuilt guide lookup")
nodes[1].state = "unreachable"
statusChanged()
assert(not NS.GetFlightMapAssistMatch(), "Unreachable guide flight selected")
nodes[1].state = "current"
statusChanged()
assert(not NS.GetFlightMapAssistMatch(), "Current flight node selected")
nodes[1].state = "reachable"
statusChanged()
intent = { kind = "flight", destinationName = "Sentinel Hill" }
assert(NS.GetFlightMapAssistMatch().nodeID == 4, "Unique settlement name was not resolved")
intent = { kind = "flight", destinationName = "Westfall" }
assert(NS.GetFlightMapAssistMatch().nodeID == 4, "Authored zone name was not resolved on the visible flight map")
intent = { kind = "flight", destinationName = "Sentinel Hill" }
local duplicate = { taxiNodeData = { nodeID = 9, slotIndex = 3, name = "Sentinel Hill, Elsewhere", state = "reachable" } }
pins[#pins + 1] = duplicate
statusChanged()
assert(not NS.GetFlightMapAssistMatch(), "Ambiguous guide flight selected")
pins[#pins] = nil
statusChanged()
active = { authority = "guide", guideProvider = "rxp", currentLegIndex = 1, legs = { { kind = "portal" } } }
assert(not NS.GetFlightMapAssistMatch(), "Guide flight conflicted with portal instructions")
active.legs = { { kind = "travel", specialAction = { secureType = "spell" } } }
assert(not NS.GetFlightMapAssistMatch(), "Guide flight conflicted with secure action")
active.legs = { { kind = "travel" } }; active._coreRoutePending = true
assert(not NS.GetFlightMapAssistMatch(), "Pending planner exposed premature guide flight")
active._coreRoutePending = nil
assert(NS.GetFlightMapAssistMatch().source == "guide", "Walking-only route suppressed guide hint")
pins[#pins + 1] = { taxiNodeData = { nodeID = 1, slotIndex = 3, name = "Origin", state = "current" } }
statusChanged()
active.legs = { { kind = "taxi", taxi = { sourceNodeID = 1, nodeID = 4 } } }
match = NS.GetFlightMapAssistMatch()
assert(match.source == "route" and match.confidence == "exact", "Backend taxi match lost priority")
NS.RefreshFlightMapAssist()
assert(taken == 1, "Existing backend auto-flight behavior regressed")
active.legs[1].taxi.nodeID = 999
assert(not NS.GetFlightMapAssistMatch(), "Unmatched backend taxi fell through to competing guide advice")
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/util.lua"))()
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Map = {
    GetWorldPosFromMapPos = function(map, pos) assert(map == 42); return 1, pos end,
    GetMapPosFromWorldPos = function(world, pos, map) assert(world == 1 and map == 13); return map, pos end,
    CanSetUserWaypointOnMap = function() error("Flight-map matching should not require a settable waypoint") end,
}
active.legs = { { kind = "taxi", mapID = 13, x = .5, y = .5, taxi = {
    operator = "farstrider", final = true, name = "Sentinel Hill",
    destination = { mapID = 42, x = .7, y = .7 },
} } }
match = NS.GetFlightMapAssistMatch()
assert(match.source == "route" and match.confidence == "strong" and match.nodeID == 4,
    "Farstrider landing was not projected onto the visible flight map")
pins[#pins + 1] = { taxiNodeData = { nodeID = 9, slotIndex = 3, name = "Sentinel Hill",
    state = "reachable", position = { .7, .7 } } }
statusChanged()
assert(not NS.GetFlightMapAssistMatch(), "Ambiguous Farstrider landing matched a taxi node")
pins[#pins] = nil
statusChanged()
active = { authority = "manual" }
assert(not NS.GetFlightMapAssistMatch(), "Manual authority exposed RXP guide advice")
active = nil; intent = nil
assert(not NS.GetFlightMapAssistMatch(), "Paused/missing intent retained suggestion")
intent = { kind = "flight", destinationName = "Sentinel Hill" }; enabled = false
assert(not NS.GetFlightMapAssistMatch(), "Routing-disabled guide showed advice")
enabled = true; shown = false
assert(not NS.GetFlightMapAssistMatch(), "Closed map retained current match")
print("Shared flight assist: RXP suggestions, localization, ambiguity, cache, authority and backend automation passed")

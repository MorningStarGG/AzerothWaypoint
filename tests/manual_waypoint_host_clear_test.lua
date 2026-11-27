local routing = {}
local overlay = {}
local enabled, internal = true, false
local mapID, x, y
local manualClears, nativeClears, cancelled, recomputes = 0, 0, 0, 0
local NS = {
    State = { routing = routing },
    Internal = { WorldOverlay = { overlay = overlay, Config = {} } },
    Signature = function(map, px, py)
        return string.format("%d:%.4f:%.4f", map, math.floor(px * 10000 + .5) / 10000,
            math.floor(py * 10000 + .5) / 10000)
    end,
    IsRoutingEnabled = function() return enabled end,
    IsInternalUserWaypointMutation = function() return internal end,
    GetCurrentUserWaypoint = function() return mapID, x, y end,
    GetActiveManualDestination = function() return routing.manualAuthority end,
    ClearPendingGuideTakeoverForClear = function() end,
    ClearActiveManualDestination = function(reason)
        assert(reason == "explicit")
        manualClears = manualClears + 1
        routing.manualAuthority = nil
        return true
    end,
    CancelPendingManualRoute = function()
        cancelled = cancelled + 1
        routing.pendingManualAuthority = nil
    end,
    RecomputeCarrier = function() recomputes = recomputes + 1 end,
    SafeCall = function(fn, ...) return fn(...) end,
}
AzerothWaypointNS = NS
Enum = {}
assert(loadfile("bridge/takeovers/tomtom_bridge_blizzard_core.lua"))()
NS.IsExplicitBlizzardUserWaypointCall = function() return true end
C_Map = { ClearUserWaypoint = function() nativeClears = nativeClears + 1 end,
    SetUserWaypoint = function(_) error("An adopted click reached the original setter") end }
assert(loadfile("bridge/routing/identity.lua"))()
assert(loadfile("world_overlay/runtime/host.lua"))()
assert(loadfile("bridge/takeovers/tomtom_bridge_userwaypoint_takeover.lua"))()
NS.InstallUserWaypointHooks()

local quest = { identity = NS.BuildQuestIdentity(745, 1412, .47174006700516, .73613011837006) }
local function PublishHost(record, source, carrierSig, hostMapID, hostX, hostY)
    routing.carrierState = { authority = record, source = source, sig = carrierSig }
    overlay.hostTargetSig = carrierSig
    overlay.hostMapID, overlay.hostX, overlay.hostY = hostMapID, hostX, hostY
    mapID, x, y = hostMapID, hostX, hostY
end

local questSig = quest.identity.sig
routing.manualAuthority = quest
PublishHost(quest, "manual", questSig, 1412, .47175006700516, .73614011837006)
assert(not NS.RouteIdentityMatchesHost(quest, mapID, x, y), "fixture must reproduce the reported mismatch")
C_Map.ClearUserWaypoint()
assert(manualClears == 1 and nativeClears == 0 and not routing.manualAuthority)

routing.manualAuthority = quest
PublishHost(quest, "manual", NS.Signature(1413, .24, .6), 1412, .6, .4)
C_Map.ClearUserWaypoint()
assert(manualClears == 2 and nativeClears == 0, "a projected intermediate host must resolve to its manual route")

routing.manualAuthority = quest
PublishHost(quest, "manual", questSig, 1412, .47175, .73614)
x = .5
C_Map.ClearUserWaypoint()
PublishHost({}, "guide", questSig, 1412, .47175, .73614)
C_Map.ClearUserWaypoint()
PublishHost({}, "manual", questSig, 1412, .47175, .73614)
C_Map.ClearUserWaypoint()
PublishHost(quest, "manual", questSig, 1412, .47175, .73614)
routing.carrierState.sig = NS.Signature(1412, .6, .4)
C_Map.ClearUserWaypoint()
assert(manualClears == 2 and nativeClears == 4 and routing.manualAuthority == quest,
    "foreign, guide, stale-owner and stale-leg pins must not clear manual authority")

PublishHost(quest, "manual", questSig, 1412, .47175, .73614)
internal = true
C_Map.ClearUserWaypoint()
internal, enabled = false, false
C_Map.ClearUserWaypoint()
assert(manualClears == 2 and nativeClears == 6)

enabled = true
local pending = {}
routing.pendingManualAuthority = pending
PublishHost(pending, "manual", questSig, 1412, .47175, .73614)
C_Map.ClearUserWaypoint()
assert(cancelled == 1 and recomputes == 1 and routing.manualAuthority == quest)

local userPoint = { identity = NS.BuildUserWaypointIdentity(1412, .6, .4) }
routing.manualAuthority, routing.carrierState = userPoint, nil
mapID, x, y = 1412, .6, .4
C_Map.ClearUserWaypoint()
assert(manualClears == 3 and nativeClears == 6, "a genuine adopted Blizzard waypoint must still clear")

assert(loadfile("tests/map_click_fixture.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
NS.GetCurrentUserWaypoint = function() return mapID, x, y end
NS.ClearPendingGuideTakeover = function() end
NS.ReadUiMapPointCoords = function(p) return p.uiMapID, p.position.x, p.position.y end
debugstack = function() return "Interface/AddOns/Blizzard_SharedMapDataProviders/WaypointLocationDataProvider.lua:100: in function 'HandleClick'" end
NS.RequestManualRoute = function(map, px, py, title, meta)
    routing.manualAuthority = {mapID=map, x=px, y=py, title=title, identity=meta.identity}
    return true
end
local click = {uiMapID=1413, position={x=.24276480065767, y=.65001007427801}}
C_Map.SetUserWaypoint(click)
local corrected = routing.manualAuthority
assert(corrected.mapID == 1412 and corrected.title == "Mulgore 49, 65")
assert(math.abs(corrected.x - click.position.x - .25) < 1e-10 and corrected.y == click.position.y)
assert(corrected.identity.mapID == 1413 and corrected.identity.x == click.position.x)
mapID, x, y = 1413, click.position.x, click.position.y
C_Map.ClearUserWaypoint()
assert(manualClears == 4 and not routing.manualAuthority)

NS.GetWorldQuestTabUserWaypointContext = function() return {title="Quest target", sourceAddon="WorldQuestTab"} end
C_Map.SetUserWaypoint(click)
assert(routing.manualAuthority.mapID == 1413 and routing.manualAuthority.title == "Quest target")
print("Ctrl-click clears the owning manual route, including adjusted and intermediate overlay pins")

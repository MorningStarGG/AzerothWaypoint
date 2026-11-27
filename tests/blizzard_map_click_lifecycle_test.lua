local fixture = assert(loadfile("tests/route_planning_fixture.lua"))()("zygor", true)
local NS = fixture.NS
Enum = {}
assert(loadfile("bridge/takeovers/tomtom_bridge_blizzard_core.lua"))()
NS.State.churn.active = false
fixture.behavior.zygor = "success"
local special, tracked, point, onUntrack = true, false, nil, nil
local rejectSupertrack, trackOnSet = false, true
local sets, clears = 0, 0
CreateVector2D = function(x, y) return {x=x, y=y} end
UiMapPoint = {CreateFromVector2D = function(map, pos) return {uiMapID=map, position=pos} end}
C_Map = {
    SetUserWaypoint = function(p)
        sets, point = sets + 1, p
        if trackOnSet then tracked = true end
    end,
    ClearUserWaypoint = function() clears, point = clears + 1, nil end,
    HasUserWaypoint = function() return point ~= nil end,
    GetUserWaypoint = function() return point end,
    GetBestMapForUnit = function() return 1413 end,
}
C_SuperTrack = {
    IsSuperTrackingUserWaypoint = function() return tracked end,
    SetSuperTrackedUserWaypoint = function(value)
        tracked = value and not rejectSupertrack
        if not value and onUntrack then onUntrack() end
    end,
}
assert(loadfile("tests/map_click_fixture.lua"))()
NS.Constants = { USER_WAYPOINT_COORD_BIAS = .00001 }
NS.Runtime = {}
assert(loadfile("core/map_coordinates.lua"))()
local internal = false
NS.IsInternalUserWaypointMutation = function() return internal end
NS.WithInternalUserWaypointMutation = function(fn, ...)
    assert(not internal, "unexpected recursive waypoint mutation")
    internal = true
    fn(...)
    internal = false
    return true
end
NS.IsExplicitBlizzardUserWaypointCall = function() return true end
NS.IsActiveSpecialActionPresenting = function() return special end
NS.GetActiveSpecialActionSignature = function() return special and "item:6948" end
NS.ClearPendingGuideTakeover = function() end
NS.ClearPendingGuideTakeoverForClear = function() end
NS.Log = function() end
NS.ReadUiMapPointCoords = function(p) return p.uiMapID, p.position.x, p.position.y end
NS.ResolveSettableUserWaypointTarget = function(map, x, y) return map, x, y end
IsInInstance = function() return false end
local host = { Config={},
    ApplySuperTrackedFrameVisibility=function() end }
NS.Internal.WorldOverlay = host
assert(loadfile("world_overlay/core/state.lua"))()
host.target.active, host.derived.distance = true, 500
assert(loadfile("world_overlay/runtime/host.lua"))()
assert(loadfile("bridge/takeovers/tomtom_bridge_userwaypoint_takeover.lua"))()
NS.InstallUserWaypointHooks()
debugstack = function() return "Blizzard_SharedMapDataProviders/WaypointLocationDataProvider.lua" end

local function Click(px)
    C_Map.SetUserWaypoint(NS.BuildUserWaypointPoint(1413, px, .65))
    C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    return NS.GetManualAuthority()
end

local function ExpectPoint(map, x, y)
    assert(host.IsSameWaypoint(map, x, y, NS.GetCurrentUserWaypoint()), "unexpected native waypoint")
end

local function Walk(record)
    special = false
    fixture.now = fixture.now + 3
    host.target.mapID, host.target.x, host.target.y = record.mapID, record.x, record.y
    host.target.sig = record.sig
    assert(host.EnsureNativeNavigationHost() and tracked)
    ExpectPoint(record.mapID, record.x + .00001, record.y + .00001)
end

-- A guide is already showing Hearthstone and has released its walking host.
-- Exercise the real click hook, coordinate resolver, planner and authority commit.
local first = Click(.24)
fixture.drain()
assert(first and first.mapID == 1412 and first.backend == "zygor" and first.identity.worldMapClick)
assert(first.identity.mapID == 1413 and fixture.db.manualAuthority.identity.worldMapClick)
assert(not host.EnsureNativeNavigationHost() and not tracked)
ExpectPoint(1413, .24, .65)
assert(sets == 1 and clears == 0)

Walk(first)
special = true
assert(not host.EnsureNativeNavigationHost() and not tracked)
ExpectPoint(1413, .24, .65)
local afterRelease = sets
assert(not host.EnsureNativeNavigationHost() and sets == afterRelease and clears == 0)
trackOnSet = false

-- While walking, a replacement click commits before the old host is released.
Walk(first)
local nextClick = Click(.23)
assert(nextClick ~= first and tracked)
special = true
assert(not host.EnsureNativeNavigationHost() and not tracked)
ExpectPoint(1413, .23, .65)
C_Map.ClearUserWaypoint()
assert(not NS.GetManualAuthority() and not point and clears == 1)
assert(not host.EnsureNativeNavigationHost() and not point)

-- A foreign update can happen during the native untrack event.
local third = Click(.22)
Walk(third)
onUntrack = function() point = NS.BuildUserWaypointPoint(1412, .8, .7) end
special = true
assert(not host.EnsureNativeNavigationHost())
onUntrack = nil
NS.ClearManualRoute("arrived")
ExpectPoint(1412, .8, .7)
assert(clears == 1)

-- Replacing a parked click with another source retires the old Blizzard pin.
Click(.21)
fixture.start(1412, .4, .5, "Manual slash waypoint")
assert(not point and clears == 2)

-- A map click queued for later must leave the active native waypoint alone.
NS.HandleManualQueueRoutingPolicy = function() return true end
Click(.20)
assert(not point and clears == 2 and not NS.GetManualAuthority().identity.worldMapClick)
NS.HandleManualQueueRoutingPolicy = nil

-- Saved neighboring-zone clicks from the previous build retain both maps.
local saved = {mapID=1412, x=.49, y=.65, title="Mulgore", identity=first.identity}
saved.identity.worldMapClick = nil
fixture.db.manualAuthority = saved
assert(NS.RestoreManualAuthority())
ExpectPoint(1413, .24, .65)
local restored = NS.GetManualAuthority()
Walk(restored)
NS.State.routing.carrierState = { source="manual", authority=restored, sig=restored.sig }
C_Map.ClearUserWaypoint()
assert(not NS.GetManualAuthority() and not tracked and not point and clears == 3)

-- An unsupported navigation leg also returns the slot and blocks retries.
local rejected = Click(.23)
special, rejectSupertrack = false, true
fixture.now = fixture.now + 3
host.target.mapID, host.target.x, host.target.y = rejected.mapID, rejected.x, rejected.y
host.target.sig = rejected.sig
assert(not host.EnsureNativeNavigationHost() and not tracked)
ExpectPoint(1413, .23, .65)
local afterRejection = sets
assert(not host.EnsureNativeNavigationHost() and sets == afterRejection)

-- A strict Ctrl-click owns its original Blizzard slot during an outstanding
-- combat plan. Supersession and clear must work before any queue commit.
special, fixture.combat = true, true
local pending
fixture.behavior.zygor = function(attempt) pending = attempt; return "pending" end
NS.PrepareManualQueueRouteRequest = function(_, _, _, _, meta) return nil, meta, {strictRouteSuccess=true} end
Click(.21)
fixture.drain()
ExpectPoint(1413, .21, .65)
assert(pending and fixture.db.manualAuthority.identity == rejected.identity)
local stale = pending
local beforeReplacement = sets
Click(.20)
fixture.drain()
assert(sets == beforeReplacement + 1 and pending ~= stale)
ExpectPoint(1413, .20, .65)
assert(not stale:Complete({status="success", legs=stale.owner.legs}))
C_Map.ClearUserWaypoint()
assert(not NS.State.routing.pendingManualAuthority and not pending:Complete({status="success", legs=pending.owner.legs}))
ExpectPoint(1413, .23, .65)
assert(NS.GetManualAuthority() == rejected)
Click(.19)
fixture.drain()
point = NS.BuildUserWaypointPoint(1412, .8, .7)
NS.CancelPendingManualRoute("superseded")
ExpectPoint(1412, .8, .7)

-- TomTom's confirmation resets the waypoint profile, emitting removals
-- followed by WaypointsReloaded. Ordinary profile reloads emit the same events.
NS.ClearManualRoute("explicit")
local callbacks = {}
TomTom = {waypoints={}, RegisterCallback=function(_, event, fn) callbacks[event] = fn end}
function TomTom:GetKeyArgs(map, x, y, title) return table.concat({map, x, y, title}, "/") end
function TomTom:AddWaypoint(map, x, y, opts)
    self.waypoints[map] = self.waypoints[map] or {}
    local uid = {map, x, y, title=opts.title, awpCarrier=opts.awpCarrier}
    self.waypoints[map][self:GetKeyArgs(map, x, y, opts.title)] = uid
    return uid
end
function TomTom:RemoveWaypoint(uid)
    local pins = self.waypoints[uid[1]]
    local key = self:GetKeyArgs(uid[1], uid[2], uid[3], uid.title)
    if pins and pins[key] == uid then
        pins[key] = nil
        callbacks.WaypointRemoved("WaypointRemoved", uid)
    end
end
local function reloadWaypoints()
    local old = TomTom.waypoints
    TomTom.waypoints = {}
    for _, pins in pairs(old) do
        for _, uid in pairs(pins) do callbacks.WaypointRemoved("WaypointRemoved", uid) end
    end
    callbacks.WaypointsReloaded()
end
StaticPopupDialogs = {TOMTOM_REMOVE_ALL_CONFIRM={OnAccept=reloadWaypoints}}
hooksecurefunc = function(object, key, after)
    local original = object[key]
    object[key] = function(...) original(...); after(...) end
end
assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
NS.InstallCarrierTomTomHooks()
NS.RecomputeCarrier = fixture.recompute
NS.ResolvePresentation = function() end
Click(.18)
fixture.drain()
local waiting = assert(NS.State.routing.pendingManualAuthority)
assert(not NS.GetManualAuthority() and NS.State.routing.carrierState.uid)
reloadWaypoints()
fixture.drain()
assert(NS.State.routing.pendingManualAuthority == waiting and NS.State.routing.carrierState.uid)
ExpectPoint(1413, .18, .65)
StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept()
fixture.drain()
assert(not NS.State.routing.pendingManualAuthority and not point, "Remove all kept the pending combat Ctrl-click")
assert(not pending:Complete({status="success", legs=waiting.legs}))
fixture.combat = false
fixture.event("PLAYER_REGEN_ENABLED")
fixture.drain()
assert(not NS.GetManualAuthority() and not NS.State.routing.carrierState and not point)

-- A committed click clears in combat too. A later click on the same frame
-- belongs to the player, even if the reload timer has not fired yet.
fixture.combat = true
fixture.behavior.zygor = "success"
Click(.17)
fixture.drain()
assert(NS.GetManualAuthority() and not NS.State.routing.pendingManualAuthority)
StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept()
assert(not NS.GetManualAuthority() and not point)
Click(.16)
fixture.drain()
assert(NS.GetManualAuthority())
ExpectPoint(1413, .16, .65)
print("Blizzard map click survives special travel and follows its committed manual route")

-- Blizzard switches the live navigation frame to the corpse while a routed
-- waypoint is still tracked. Yield only AWP's host and keep manual ownership.
fixture.combat, rejectSupertrack = false, false
local final = NS.GetManualAuthority()
Walk(final)
Enum.SuperTrackingType = { UserWaypoint = 1, Corpse = 2 }
local priority = Enum.SuperTrackingType.Corpse
C_SuperTrack.GetHighestPrioritySuperTrackingType = function() return priority end
assert(not host.EnsureNativeNavigationHost() and not host.overlay.hostMapID)
ExpectPoint(1413, .16, .65)
local parked = sets
assert(not host.EnsureNativeNavigationHost() and sets == parked and NS.GetManualAuthority() == final)
priority = Enum.SuperTrackingType.UserWaypoint
Walk(final)

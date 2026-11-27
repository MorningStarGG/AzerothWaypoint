-- Two dungeon maps can expose the same metadata and still differ in native navigation support.
assert(loadfile("tests/addon_load_order_test.lua"))()
local ns = AzerothWaypointNS
local host = ns.Internal.WorldOverlay
local now, inInstance, currentMap = 10, true, 701
local mode, calls, tracked = "reject", 0, false
local waypoint, pending, navFrame
GetTime = function() return now end
IsInInstance = function() return inInstance, inInstance and "party" or "none" end
CreateVector2D = function(x, y) return {x=x, y=y} end
UiMapPoint = {CreateFromVector2D=function(id, pos) return {uiMapID=id, position=pos} end}
C_Map = {
    GetBestMapForUnit = function() return currentMap end,
    GetMapInfo = function() return {mapType=4, parentMapID=10} end,
    CanSetUserWaypointOnMap = function() return true end,
    HasUserWaypoint = function() return waypoint ~= nil end,
    GetUserWaypoint = function() return waypoint end,
    SetUserWaypoint = function(point)
        calls = calls + 1
        if mode == "reject" then error("instance rejected the waypoint") end
        if mode == "pending" then pending = point else waypoint = point end
    end,
    ClearUserWaypoint = function() waypoint = nil end,
}
C_SuperTrack = {
    IsSuperTrackingUserWaypoint = function() return tracked end,
    SetSuperTrackedUserWaypoint = function(value) tracked = value end,
}
C_Navigation = {GetFrame = function() return navFrame end, GetDistance = function() return 100 end}
ns.UpdateNativeWorldOverlay = function() end

local function target(id)
    currentMap = id
    host.target.active, host.target.mapID, host.target.x, host.target.y = true, id, .3, .6
    host.target.sig = ns.Signature(id, .3, .6)
    now = now + 2
end
target(701)
assert(not host.EnsureNativeNavigationHost() and not host.IsCurrentMapInstanceWaypointCapable(701))
assert(not host.EnsureNativeNavigationHost() and calls == 1, "Rejected probes should respect the cooldown")
assert(not host.overlay.hostMapID and not tracked)

mode = "accept"
target(702)
assert(host.EnsureNativeNavigationHost() and tracked and calls == 2)
assert(host.IsCurrentMapInstanceWaypointCapable(702) and not host.IsCurrentMapInstanceWaypointCapable(701))
assert(host.overlay.hostMapID == 702 and waypoint.uiMapID == 702)
navFrame = {IsShown=function() return true end, GetCenter=function() return 400, 300 end}
ns.OnNativeNavFrameCreated()
local _, anchor, x, y = host.ResolvePlacementAnchor()
assert(anchor == navFrame and x == 400 and y == 300, "The confirmed instance must retain Blizzard's anchor")
ns.OnNativeNavFrameDestroyed()
assert(not select(2, host.ResolvePlacementAnchor()), "The destroyed frame cannot remain an anchor")

mode = "pending"
target(703)
assert(not host.EnsureNativeNavigationHost() and host.overlay.instanceCapabilityPending and calls == 3)
now = now + 2
assert(not host.EnsureNativeNavigationHost() and calls == 3, "Pending confirmation must not resubmit")
waypoint = assert(pending)
ns.OnNativeNavFrameCreated()
assert(host.IsCurrentMapInstanceWaypointCapable(703) and host.overlay.hostMapID == 703 and tracked)
assert(select(2, host.ResolvePlacementAnchor()) == navFrame and calls == 3)
inInstance = false
assert(host.IsCurrentMapInstanceWaypointCapable(701), "Outdoor navigation should not inherit an instance refusal")
print("Verified rejected, confirmed and delayed instance host capability and native frame placement")

local jobs, frames, registrations = {}, {}, {}
local routing, combat, alt, shift, ctrl, overMap = true, false, false, false, false, true
local guide, backend = "questierouter", "direct"
local pendingPlan, requests, scans = false, 0, 0

C_Timer = { After = function(_, fn) jobs[#jobs + 1] = fn end }
local function Flush()
    while #jobs > 0 do table.remove(jobs, 1)() end
end
function IsAltKeyDown() return alt end
function IsShiftKeyDown() return shift end
function IsControlKeyDown() return ctrl end
function InCombatLockdown() return combat end
function CreateFrame()
    local scripts = {}
    local frame = { RegisterEvent = function() end,
        SetScript = function(_, event, fn) scripts[event] = fn end,
        GetScript = function(_, event) return scripts[event] end }
    frames[#frames + 1] = frame
    return frame
end
function GetFramesRegisteredForEvent(event)
    assert(event == "GLOBAL_MOUSE_DOWN")
    scans = scans + 1
    return unpack(registrations)
end

local canvasHandler
local displayedMap, cursorX, cursorY = 1412, .506, .444
WorldMapFrame = {
    IsShown = function() return true end,
    ScrollContainer = { IsMouseOver = function() return overMap end },
    GetMapID = function() return displayedMap end,
    GetNormalizedCursorPosition = function() return cursorX, cursorY end,
    AddCanvasClickHandler = function(_, fn, priority)
        assert(not canvasHandler and priority > 1000)
        canvasHandler = fn
    end,
}

local state = { routing = {} }
local zygor
local db = {}
local NS = {
    State = state, Internal = {}, IsWoWForever = function() return true end,
    GetZygorPointer = function() if zygor then return zygor, zygor.Pointer end end,
    IsRoutingEnabled = function() return routing end,
    GetActiveGuideProvider = function() return guide end,
    GetRoutingBackend = function() return {} end,
    GetDB = function() return db end,
    ValidateRouteIdentity = function(v) return v == "manual" end,
}
AzerothWaypointNS = NS
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/native_map_waypoints.lua"))()
assert(loadfile("bridge/routing/authority.lua"))()
NS.PersistManualAuthority = function() end
local native = NS.Internal.NativeMapWaypoints
local events = frames[1]:GetScript("OnEvent")

function NS.CancelPendingManualRoute()
    local record = state.routing.pendingManualAuthority
    state.routing.pendingManualAuthority = nil
    native.Retire(record)
    return record ~= nil
end
function NS.RequestManualRoute(map, x, y, title, meta, opts)
    assert(opts.nativeMapWaypoint and opts.strictRouteSuccess)
    requests = requests + 1
    NS.CancelPendingManualRoute()
    local record = { mapID = map, x = x, y = y, backend = backend, identity = "manual", title = title,
        sourceAddon = meta.sourceAddon, _nativeMapWaypoint = opts.nativeMapWaypoint }
    if pendingPlan then state.routing.pendingManualAuthority = record else NS.CommitManualAuthority(record) end
    return true
end

local qrFrames = {}
local function QuestieRouter(withListener)
    local q = { ready = true, charDB = {}, HBD = {}, Waypoints = { hooked = true }, callbacks = {} }
    function q:On(event, cb) self.callbacks[event] = cb end
    local wp, list = q.Waypoints, {}
    function wp:All() return list end
    function wp:First() return list[1] end
    function wp:Target(p) return { name = "QR via " .. tostring(p.via) } end
    function wp:Remove(p)
        for i, item in ipairs(list) do if p == item then table.remove(list, i); break end end
        q.callbacks.WAYPOINTS_CHANGED()
    end
    function wp:Add(map, x, y, via)
        for i = #list, 1, -1 do if list[i].via == via then table.remove(list, i) end end
        table.insert(list, 1, { map = map, x = x, y = y, via = via })
        q.target = { kind = "travel", x = 0.1, y = 0.2 } -- Never adopt the route's first stop.
        q.callbacks.WAYPOINTS_CHANGED()
    end
    local listener = CreateFrame()
    function listener:GetSourceLocation() return "Interface/AddOns/QuestieRouter/Guide/Waypoints.lua:206" end
    listener:SetScript("OnEvent", function(_, event, button)
        if event ~= "GLOBAL_MOUSE_DOWN" or button ~= "LeftButton" or ctrl or alt == shift or not overMap then return end
        local map, x, y = WorldMapFrame:GetMapID(), WorldMapFrame:GetNormalizedCursorPosition()
        if wp.hit then wp:Remove(wp.hit); wp.hit = nil else wp:Add(map, x, y, alt) end
    end)
    qrFrames[q] = listener
    registrations = withListener and { listener } or {}
    native.InstallQuestieRouter(q)
    return q, wp
end

local target, held
local function CurrentPoint(p)
    if held then return nil end
    return target == p
end
local function ReleasePoint()
    target = nil
    native.Changed()
end
local p = { ready = true, Nav = { journey = {} } }
function p.Nav.journey.OnMapClick(mapID, x, y, label)
    if target and target.map == mapID and target.x == x and target.y == y then ReleasePoint(); return end
    target = { map = mapID, x = x, y = y, label = label }
    if routing then native.Adopt("polestar", target, CurrentPoint, ReleasePoint, mapID, x / 100, y / 100, label) end
    native.Changed()
end
native.InstallPolestar(p, function() return p.ready end)

local function Click(q, isAlt, isShift, isCtrl, overPin)
    alt, shift, ctrl = isAlt, isShift, isCtrl
    local listener = q and qrFrames[q]
    if listener and q.ready then listener:GetScript("OnEvent")(listener, "GLOBAL_MOUSE_DOWN", "LeftButton") end
    local mapID, x, y = WorldMapFrame:GetMapID(), WorldMapFrame:GetNormalizedCursorPosition()
    if alt and not shift and not ctrl and p.ready and not native.PolestarYields() then
        p.Nav.journey.OnMapClick(mapID, x * 100, y * 100, overPin and "Flight master" or nil)
    elseif shift and not ctrl and not overPin then
        local handled = canvasHandler and canvasHandler(WorldMapFrame, "LeftButton")
        if not handled and not (q and q.ready) and p.ready and not native.PolestarYields() then
            p.Nav.journey.OnMapClick(mapID, x * 100, y * 100)
        end
    end
    Flush()
end

local q, wp = QuestieRouter(true)
for _, planner in ipairs({ "direct", "polestar", "questierouter" }) do
    for _, source in ipairs({ "polestar", "questierouter", "zygor" }) do
        for _, isAlt in ipairs({ false, true }) do
            guide, backend = source, planner
            local before = requests
            Click(q, isAlt, not isAlt, false, isAlt)
            local route = NS.GetManualAuthority()
            assert(requests == before + 1 and route and route.backend == planner)
            assert(route.mapID == 1412 and route.x == 0.506 and route.y == 0.444)
            if source == "polestar" then
                assert(route.sourceAddon == "polestar" and target and #wp:All() == 0)
                if isAlt then assert(route.title == "Flight master") end
            else
                assert(route.sourceAddon == "questierouter" and not target and wp:First().via == isAlt)
            end
            assert(NS.ClearManualRoute("explicit"))
            Flush()
            assert(not target and #wp:All() == 0 and not NS.GetManualAuthority())
        end
    end
end
assert(scans == 1)

guide = "questierouter"
Click(q, true, false, true)
assert(#wp:All() == 0 and not target)
alt, shift, ctrl = false, false, false
wp:Add(1412, 0.25, 0.25, false) -- A prior independent native point.
local saved = wp:First()
Click(q, true, false, false)
local clickTarget = wp:First()
wp.hit = clickTarget
Click(q, true, false, false)
assert(wp:First() == saved and not NS.GetManualAuthority())

guide = "polestar"
Click(q, true, false, false)
Click(q, true, false, false)
assert(not target and not NS.GetManualAuthority() and wp:First() == saved)
Click(q, true, false, false)
guide = "questierouter"
Click(q, true, false, false)
assert(not target and wp:All()[2] == saved and NS.GetManualAuthority().sourceAddon == "questierouter")
combat = true
NS.ClearManualRoute("explicit")
assert(wp:First() ~= saved)
combat = false
events(nil, "PLAYER_REGEN_ENABLED")
Flush()
assert(wp:First() == saved and #wp:All() == 1)

Click(q, true, false, false)
combat = true
NS.ClearManualRoute("explicit")
alt = false
wp:Add(1412, 0.506, 0.444, true) -- Same coordinates, different native object.
local newer = wp:First()
combat = false
events(nil, "PLAYER_REGEN_ENABLED")
Flush()
assert(wp:First() == newer and wp:All()[2] == saved)
wp:Remove(newer)

pendingPlan = true
Click(q, true, false, false)
assert(state.routing.pendingManualAuthority)
NS.ClearManualRoute("explicit")
assert(wp:First() == saved and not state.routing.pendingManualAuthority)
pendingPlan = false

guide = "polestar"
q.ready = false
Click(q, false, true, false)
assert(target and NS.GetManualAuthority().sourceAddon == "polestar")
held = true
NS.ClearManualRoute("explicit")
assert(target)
held = false
native.Changed()
Flush()
assert(not target)

q.ready = true
p.ready = false
Click(q, true, false, false)
assert(NS.GetManualAuthority().sourceAddon == "questierouter")
NS.ClearManualRoute("explicit")
p.ready = true

local fallback = QuestieRouter(false)
Click(fallback, true, false, false)
assert(NS.GetManualAuthority().sourceAddon == "questierouter" and not target and scans == 2)
NS.ClearManualRoute("explicit")
routing = false
Click(fallback, true, false, false)
assert(target and #fallback.Waypoints:All() == 1 and not NS.GetManualAuthority())

-- When the Barrens canvas shows Mulgore, QuestieRouter must receive the resolved
-- coordinates before it creates and names the waypoint. Clear the same native object.
local maps = assert(loadfile("tests/map_click_fixture.lua"))()
function wp:Target(point) return {name=maps[point.map].name} end
routing, guide, backend = true, "questierouter", "zygor"
displayedMap, cursorX, cursorY = 1413, .24276480065767, .65001007427801
Click(q, false, true, false)
local route, point = NS.GetManualAuthority(), wp:First()
assert(route.mapID == 1412 and route.title == "Mulgore" and route.backend == "zygor")
assert(point.map == route.mapID and point.x == route.x and point.y == route.y)
assert(math.abs(point.x - cursorX - .25) < 1e-10 and point.y == cursorY)
assert(route._nativeMapWaypoint.target == point)
assert(NS.ClearManualRoute("explicit"))
Flush()
assert(not NS.GetManualAuthority() and not wp:First())

-- A second Shift-click listener polls release even after the canvas handled it.
local pointer = { OverlayProvider = {}, frame_worldmap_functions = {OnClick=function() end} }
zygor = { Pointer = pointer }
local foci = {}
GetMouseFoci = function() return foci end
local zygorPin
local function ReleaseShift()
    if pointer.IgnoreThisButtonDown then pointer.IgnoreThisButtonDown = false
    else zygorPin = {type="manual"} end
end
local callbacks = {}
TomTom = {RegisterCallback = function(_, event, fn) callbacks[event] = fn end}
StaticPopupDialogs = {TOMTOM_REMOVE_ALL_CONFIRM = {OnAccept = function() callbacks.WaypointsReloaded() end}}
hooksecurefunc = function(object, name, hook)
    local original = object[name]
    object[name] = function(...) original(...); hook(...) end
end
NS.After = C_Timer.After
assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
NS.InstallCarrierTomTomHooks()
Click(q, false, true, false)
ReleaseShift()
assert(wp:First() and NS.GetManualAuthority() and not zygorPin, "Zygor duplicated the native Shift-click")
StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept()
Flush()
assert(not NS.GetManualAuthority() and not wp:First() and not zygorPin, "Remove all left a manual pin")

-- Removing an existing QuestieRouter pin also consumes the release.
Click(q, false, true, false)
ReleaseShift()
wp.hit = wp:First()
Click(q, false, true, false)
ReleaseShift()
assert(not zygorPin and not wp:First() and not NS.GetManualAuthority())

-- A genuine Zygor pin owns its Shift-click, including the surrogate shown along a route.
for _, waypoint in ipairs({{type="manual"}, {type="route", surrogate_for={type="manual"}}}) do
    foci = {{IsObjectType=function(_, t) return t == "Button" end, IsForbidden=function() return false end,
        GetScript=function() return pointer.frame_worldmap_functions.OnClick end, waypoint=waypoint}}
    Click(q, false, true, false, true)
    assert(not wp:First() and not NS.GetManualAuthority(), "Clearing a Zygor pin created a QuestieRouter pin")
end
foci = {}
Click(q, false, true, false)
assert(pointer.IgnoreThisButtonDown)
routing = false -- Release was never polled. The following click belongs to Zygor.
Click(q, false, true, false)
ReleaseShift()
assert(zygorPin, "An earlier gesture suppressed an independent Zygor click")

print("native world map waypoint ownership tests passed")

local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local install = assert(loadfile("integrations/daylight_quests.lua"))

local f = make("zygor", true)
local NS = f.NS
Enum = {}
assert(loadfile("bridge/takeovers/tomtom_bridge_blizzard_core.lua"))()
NS.IsAddonLoaded = function(name) return name == "DaylightUI" and DaylightUI ~= nil end
NS.State.init = { playerLoggedIn = true }
NS.IsTrackedQuestAutoRouteEnabled = function() return false end
NS.ClearPendingGuideTakeover = function() end
NS.ReadWaypointCoords = function(waypoint) return waypoint.mapID, waypoint.x, waypoint.y end
NS.Log = function() end
f.behavior.mapzeroth = "success"
f.behavior.zygor = "success"

for _, file in ipairs({
    "core/quest_data",
    "core/quest_text",
    "bridge/routing/queues/state", "bridge/routing/queues/items",
    "bridge/routing/queues/routing", "bridge/routing/queues/policy",
    "bridge/takeovers/tomtom_bridge_quest_takeover",
}) do
    assert(loadfile(file .. ".lua"))()
end

local questX, questY = .51, .65
C_QuestLog = {
    AddQuestWatch = function() error("A menu route must not change the watched quests") end,
    IsOnQuest = function() return true end,
    ReadyForTurnIn = function(id) return id == 42 end,
    GetTitleForQuestID = function() return "Sharing the Land" end,
    GetNextWaypoint = function(id)
        if id == 42 then return 1412, questX, questY end
        if id == 44 then return 1412, .61, .67 end
        if id == 45 then return 1412, .71, .70 end
    end,
}
C_SuperTrack = {
    SetSuperTrackedQuestID = function() error("A menu route must not supertrack the quest") end,
}

DaylightUI = { API = { For = function() return {} end } }
local eventCount = #f.frames
install()
assert(#f.frames == eventCount, "An already loaded Daylight without this capability needs no listener")

DaylightUI = nil
install()
local frame = f.frames[#f.frames]
function frame:UnregisterEvent(event) self.events[event] = nil end
local menus, registrations = {}, 0
DaylightUI = { API = { For = function(owner)
    assert(owner == "AzerothWaypoint")
    return { AddQuestMenu = function(key, spec)
        assert(key == "route" and spec.label == "Route with AzerothWaypoint")
        menus[key] = spec
        registrations = registrations + 1
        return true
    end }
end } }
f.event("ADDON_LOADED", "DaylightUI_Quests")
assert(menus.route == nil)
f.event("ADDON_LOADED", "DaylightUI")
f.event("ADDON_LOADED", "DaylightUI")
assert(registrations == 1)
local menu = assert(menus.route, "Daylight route menu missing")

local quest = { questID = 42, state = "ready" }
f.routing = false
assert(menu.show(quest) == false)
menu.onClick(quest)
assert(#f.calls == 0 and #f.messages == 0, "A stale menu must honor routing being disabled")
f.routing = true
assert(menu.show(quest) == true)
assert(not NS.HandleQuestWatchAdded(42) and #f.calls == 0)

NS.SetManualClickQueueMode("ask")
local prompt
NS.ShowManualQueuePlacementPrompt = function(_, offer) prompt = offer end
menu.onClick(quest)
assert(prompt and #f.calls == 0, "An explicit quest click must honor the user's queue policy")
prompt("create")
f.drain()
local route = NS.GetManualAuthority()
assert(route.backend == "zygor" and route.identity.questID == 42)
assert(route.mapID == 1412 and route.x == .51 and route.y == .65)
assert(route.title == "Turn in 'Sharing the Land'")
prompt = nil
menu.onClick(quest)
assert(not prompt and NS.GetManualAuthority() == route, "Re-selecting the active quest should reuse its route")

menu.onClick({ questID = 43 })
assert(f.messages[1] == "Could not find a destination for that quest.")
assert(NS.GetManualAuthority() == route)

local requestManualRoute = NS.RequestManualRoute
NS.RequestManualRoute = function() return false end
questX, questY = .53, .66
menu.onClick(quest)
assert(f.messages[2] == "Could not start a route to that quest.")
assert(NS.GetManualAuthority() == route)

-- Mapzeroth's two quest controls share the hooked QuestArrow.Route entry.
-- Keep a simulated Mapzeroth planner behind the real AWP route coordinator.
NS.RequestManualRoute = requestManualRoute
questX, questY = .51, .65
local planner = NS.RoutingBackend_Mapzeroth
local nativeClicks = 0
MapzerothAddon = { QuestArrow = { Route = function(_) nativeClicks = nativeClicks + 1 end } }
assert(loadfile("tests/mapzeroth_navigation_fixture.lua"))()(MapzerothAddon)
assert(loadfile("bridge/routing/backends/mapzeroth.lua"))()
NS.RoutingBackend_Mapzeroth.RefreshNativeNavigationOwnership()
NS.RoutingBackend_Mapzeroth = planner
local queue = assert(NS.RouteQueueInternal.GetManualQueueByID(route.queueID))

prompt = nil
local count = #f.calls
f.behavior.mapzeroth = "failed"
MapzerothAddon.QuestArrow.Route(42)
assert(prompt, "A different planner for the same quest must open the queue prompt")
prompt("replace")
f.drain()
assert(#f.calls == count + 1 and f.calls[#f.calls] == "mapzeroth")
assert(NS.GetManualAuthority() == route and queue.items[1].meta.backendOverride == nil)
assert(f.messages[#f.messages]:find("Mapzeroth routing failed", 1, true))

f.behavior.mapzeroth = "success"
MapzerothAddon.QuestArrow.Route(42)
prompt("replace")
f.drain()
route = NS.GetManualAuthority()
assert(route.backend == "mapzeroth" and route.queueID == queue.id and #queue.items == 1)
assert(queue.items[1].meta.backendOverride == "mapzeroth" and NS.GetSelectedBackendID() == "zygor")
assert(nativeClicks == 0)
NS.RequestRoutePlan(route, NS.GetSelectedBackendID(), route.meta, "refresh")
f.drain()
assert(f.calls[#f.calls] == "mapzeroth", "A refresh must keep the stop's requested planner")

local savedAuthority = f.db.manualAuthority
NS.ClearManualAuthority("fixture_reload")
f.db.manualAuthority = savedAuthority
assert(NS.RestoreManualQueues())
f.drain()
route = NS.GetManualAuthority()
queue = assert(NS.RouteQueueInternal.GetManualQueueByID(route.queueID))
assert(route.backend == "mapzeroth" and NS.GetSelectedBackendID() == "zygor")

menu.onClick(quest)
prompt("replace")
f.drain()
route = NS.GetManualAuthority()
assert(route.backend == "zygor" and queue.items[1].meta.backendOverride == nil and #queue.items == 1)

MapzerothAddon.QuestArrow.Route(44)
prompt("append")
menu.onClick({ questID = 45 })
prompt("append")
f.drain()
assert(NS.GetManualAuthority() == route and #queue.items == 3)
assert(queue.items[2].meta.backendOverride == "mapzeroth" and queue.items[3].meta.backendOverride == nil)
assert(f.db.manualQueues.byID[queue.id].items[2].meta.backendOverride == "mapzeroth")

assert(NS.ClearManualRoute("arrival"))
f.drain()
assert(NS.GetManualAuthority().backend == "mapzeroth" and NS.GetManualAuthority().identity.questID == 44)
assert(NS.ClearManualRoute("arrival"))
f.drain()
assert(NS.GetManualAuthority().backend == "zygor" and NS.GetManualAuthority().identity.questID == 45)
assert(NS.GetSelectedBackendID() == "zygor")

NS.IsWoWForever = function() return false end
install()
assert(registrations == 1, "The menu is exclusive to Forever")
print("Daylight quest menus, explicit routing, manual queues and failure handling passed")

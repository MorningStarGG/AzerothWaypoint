local NativePath = dofile("tests/native_path.lua")
assert(loadfile("tests/mapzeroth_navigation_ownership_test.lua"))()
local NS = AzerothWaypointNS
local M, backend = NS.Internal.BlizzardTakeovers, NS.RoutingBackend_Mapzeroth
local current, selected, quest, mode, dead = nil, "zygor", nil, "ask", false
local map, x, y, resolved = 1412, .51, .65, true
local now = 100
GetTime = function() return now end
NS.IsRoutingEnabled = function() return true end
NS.GetSelectedBackendID = function() return selected end
NS.RoutePlanningCore.GetActiveRecord = function() return current end
UnitIsDeadOrGhost = function() return dead end
NS.IsInternalSuperTrackMutation = function() return false end
local supertrack = assert(rawget(_G, "C_SuperTrack"))
supertrack.GetSuperTrackedQuestID = function() return quest end
C_QuestLog.GetNextWaypoint = function() if resolved then return map, x, y end end
local requests = 0
NS.RequestManualRoute = function() requests = requests + 1; return true end
local a = dofile("tests/mapzeroth_navigation_fixture.lua")({
    L = {}, Theme = {}, Options = { Get = function(_, key) return key == "autoQuestRoute" and mode or false end },
})
a.GetWaypoint = function() return nil end
a.GetQuestTarget = function(_, id) return { questID = id, mapID = map, x = x, y = y } end
a.Navigation.ReplanTarget = function() return nil end
assert(loadfile(NativePath("forever", "Mapzeroth/UI/WaypointPrompt.lua")))("Mapzeroth", a)
local offer, offers = nil, 0
local p = a.WaypointPrompt
p.ShowQuest = function(_, value) offer = value.questID; offers = offers + 1 end
p.IsQuestShown = function() return offer ~= nil end
p.Hide = function() offer = nil end
MapzerothAddon = a
assert(backend.RefreshNativeNavigationOwnership())
local function record(id, planner, rx)
    return { type = "manual", mapID = map, x = rx or x, y = y, backendOverride = planner,
        identity = { kind = "quest", questID = id, questSource = "watch" },
        meta = { backendOverride = planner }, title = "Different display title" }
end
local function follow(id)
    now = now + 11 -- exercise durable identity, after the native recent-offer window
    quest = nil; p:Settle(); quest = id; p:OnQuestChanged()
end
NS.State.routing.pendingManualAuthority = nil
current = record(42, "mapzeroth")
NS.State.routing.manualAuthority = current
assert(M.IsQuestRouteCurrent(42, "mapzeroth"))
follow(42); assert(offers == 0)
mode = "on"; follow(42); assert(requests == 0 and NS.State.routing.manualAuthority == current)
mode = "ask"

-- Requested Mapzeroth planning remains the intent if its active backend fell back.
current.backend, current._routePlanning = "direct", { preferred = "mapzeroth" }
assert(M.IsQuestRouteCurrent(42, "mapzeroth"))
current.backendOverride, current._routePlanning, selected = nil, nil, "mapzeroth"
assert(M.IsQuestRouteCurrent(42, "mapzeroth"))
selected = "zygor"
follow(42); assert(offer == 42, "A different planner was silently suppressed")
p:Answer("route"); assert(requests == 1 and selected == "zygor" and not offer)
current = record(42, "mapzeroth"); NS.State.routing.manualAuthority = current

-- Pending authority takes precedence over the committed queue, including a
-- different quest at the same coordinates and an objective that moved.
NS.State.routing.pendingManualAuthority = record(42, "mapzeroth")
follow(42); assert(not offer)
NS.State.routing.pendingManualAuthority = record(43, "mapzeroth")
follow(42); assert(offer == 42)
local before = requests
p:Answer("route"); assert(requests == before + 1)
NS.State.routing.pendingManualAuthority = record(42, "mapzeroth", x + .02)
follow(42); assert(offer == 42)
before = requests; mode = "on"; follow(42); assert(requests == before + 1)
mode = "ask"; NS.State.routing.pendingManualAuthority = nil

-- Match the guide's final semantic target, never the current walking leg.
current = { semanticQuestID = 42, mapID = map, x = x, y = y, target = { mapID = map, x = x, y = y },
    currentLeg = { mapID = map, x = .1, y = .1 }, backendOverride = "mapzeroth" }
NS.State.routing.manualAuthority = nil
assert(M.IsQuestRouteCurrent(42, "mapzeroth")); follow(42); assert(not offer)
current.semanticQuestID = 43
follow(42); assert(offer == 42, "Coordinates alone identified a different quest")
current = { type = "manual", mapID = map, x = x, y = y,
    semanticQuestID = 42, backendOverride = "mapzeroth" }
assert(not M.IsQuestRouteCurrent(42, "mapzeroth"), "A manual pin's display hint became quest ownership")
p:Hide()
resolved = false
assert(not M.IsQuestRouteCurrent(42, "mapzeroth"))
resolved = true
dead = true; before = offers; follow(42); assert(offers == before)
dead = false; mode = "off"; follow(42); assert(offers == before)

-- An offer that became redundant or obsolete is checked again on acceptance.
mode = "ask"; current = nil; follow(42); assert(offer == 42)
current = record(42, "mapzeroth"); NS.State.routing.manualAuthority = current
before = requests; p:Answer("route"); assert(requests == before and not offer)
current = nil; NS.State.routing.manualAuthority = nil; follow(42)
quest = 43; p:Answer("route"); assert(requests == before)
print("Native Mapzeroth quest offers: final identity, pending priority, planner intent, guides and acceptance passed")

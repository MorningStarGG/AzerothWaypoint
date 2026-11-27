local f = assert(loadfile("tests/route_planning_fixture.lua"))()("zygor")
local NS = f.NS
Enum = {}
assert(loadfile("bridge/takeovers/tomtom_bridge_blizzard_core.lua"))()
NS.IsRoutingEnabled = function() return f.db.routingEnabled ~= false end
NS.State.init = { playerLoggedIn = true }
local autoRoute = false
local followedQuestID = 41
NS.IsTrackedQuestAutoRouteEnabled = function() return autoRoute end
NS.GetGuideVisibilityState = function() return "visible" end
NS.ZGV = function() return { CurrentStep = { goals = { { questid = 41 } } } } end
NS.IsExplicitUserSupertrack = function() return false end
NS.Log = function() end
NS.ReadWaypointCoords = function(point) return point.mapID or point.map, point.x, point.y end
NS.ClearPendingGuideTakeover = function() end
NS.BuildRouteMeta = function(identity, opts) return { identity = identity, backendOverride = opts and opts.backendOverride } end
NS.BuildQuestIdentity = function(questID, _, _, _, fields)
    fields.kind, fields.questID = "quest", questID
    return fields
end

local routeRequests = {}
NS.RequestManualRoute = function(map, x, y, title, meta, opts)
    routeRequests[#routeRequests + 1] = { map = map, x = x, y = y, title = title, meta = meta, opts = opts }
    return true
end
C_QuestLog = {
    AddQuestWatch = function() error("routing a quest must not watch it") end,
    GetTitleForQuestID = function() return "Watched quest" end,
    IsOnQuest = function() return true end,
    GetNextWaypoint = function(questID)
        if questID == 42 then return 1412, .51, .65 end
    end,
}
C_SuperTrack = {
    GetSuperTrackedQuestID = function() return followedQuestID end,
    SetSuperTrackedQuestID = function() error("routing a quest must not supertrack it") end,
}

local createFrame = CreateFrame
CreateFrame = function()
    local frame = createFrame()
    frame.RegisterUnitEvent = frame.RegisterEvent
    frame.UnregisterEvent = function(self, event) self.events[event] = nil end
    return frame
end

assert(loadfile("bridge/takeovers/tomtom_bridge_quest_takeover.lua"))()
assert(loadfile("bridge/routing/backends/mapzeroth.lua"))()
local backend = NS.RoutingBackend_Mapzeroth
MapzerothAddon = nil
backend.Initialize()
assert(backend._eventFrame.events.ADDON_LOADED, "Mapzeroth may load after AWP")

local active, shown, askWaypointRoute = true, true, true
local nativeStarts, stops, offers, nativeClicks = 0, 0, 0, 0
local waypoint, seen = 1, nil
local questMode, questOffer, nativeFollowCalls, dead = "off", nil, 0, false
UnitIsDeadOrGhost = function() return dead end
MapzerothAddon = {
    Panel = {
        StartRoute = function()
            nativeStarts = nativeStarts + 1
            active = true
        end,
        RouteToQuest = function(_, _)
            nativeFollowCalls = nativeFollowCalls + 1
            return true
        end,
    },
    Navigation = { IsActive = function() return active end },
    Navigator = {
        Stop = function()
            stops = stops + 1
            active = false
        end,
    },
    WaypointPrompt = {
        OnWaypointChanged = function()
            if waypoint ~= seen then
                seen = waypoint
                if askWaypointRoute then offers = offers + 1 end
            end
        end,
        OnQuestChanged = function(self)
            if questMode == "ask" then self:ShowQuest({questID=followedQuestID})
            elseif questMode == "on" then MapzerothAddon.Panel:RouteToQuest(followedQuestID) end
        end,
        ShowQuest = function(_, entry) questOffer = entry.questID end,
        IsQuestShown = function() return questOffer ~= nil end,
        Answer = function(_, choice)
            local questID = questOffer
            questOffer = nil
            if choice == "route" then MapzerothAddon.QuestArrow.Route(questID) end
        end,
        Hide = function() shown = false; questOffer = nil end,
        Settle = function() seen = waypoint end,
    },
    QuestArrow = {
        Route = function(questID)
            assert(questID == 42)
            nativeClicks = nativeClicks + 1
        end,
    },
}
assert(loadfile("tests/mapzeroth_navigation_fixture.lua"))()(MapzerothAddon)
local addon = MapzerothAddon
local nativeStart = addon.Panel.StartRoute
f.event("ADDON_LOADED", "UnrelatedAddon")
assert(addon.Panel.StartRoute == nativeStart)
f.combat = true
f.event("ADDON_LOADED", "Mapzeroth")
assert(not active and not shown and stops == 1, "AWP must stop a native trip and dismiss its offer on takeover")
assert(not backend._eventFrame.events.ADDON_LOADED)
f.combat = false

local guardedStart = addon.Panel.StartRoute
NS.RecomputeCarrier = function()
    waypoint = waypoint + 1
    addon.WaypointPrompt:OnWaypointChanged()
end
NS.SetRoutingEnabled(true)
assert(stops == 1 and addon.Panel.StartRoute == guardedStart, "ownership synchronization must be idempotent")
addon.Panel:StartRoute()
assert(nativeStarts == 0 and #f.messages == 1)
assert(offers == 0, "the shared waypoint slot must not trigger a Mapzeroth offer")

NS.HandleQuestWatchAdded(42)
assert(#routeRequests == 0, "passive watch additions should honor Auto-Route Tracked Quests")
addon.QuestArrow.Route(42)
local request = routeRequests[1]
assert(#routeRequests == 1 and nativeClicks == 0)
assert(request.map == 1412 and request.x == .51 and request.y == .65 and request.title == "Watched quest")
assert(request.meta.identity.questID == 42 and request.meta.identity.questSource == "watch")
assert(request.meta.backendOverride == "mapzeroth" and NS.GetSelectedBackendID() == "zygor")
assert(request.opts.clickContext.explicit == true)
addon.QuestArrow.Route(43)
assert(#routeRequests == 1 and #f.messages == 2, "an unresolved quest should leave the existing route alone")

NS.SetRoutingEnabled(false)
addon.WaypointPrompt:OnWaypointChanged()
assert(offers == 0, "the waypoint present at release should not trigger an offer")
waypoint = waypoint + 1
addon.WaypointPrompt:OnWaypointChanged()
addon.QuestArrow.Route(42)
addon.Panel:StartRoute()
assert(offers == 1 and nativeClicks == 1 and nativeStarts == 1 and active)
assert(#routeRequests == 1, "Mapzeroth should handle its own shortcuts when AWP routing is off")

NS.SetRoutingEnabled(true)
assert(stops == 2 and not active and addon.Panel.StartRoute == guardedStart)
autoRoute = true
NS.HandleQuestWatchAdded(41)
assert(#routeRequests == 1, "watching the guide's own quest should keep guide authority")
NS.HandleQuestWatchAdded(42)
assert(#routeRequests == 2 and routeRequests[2].opts == nil, "watching another quest should route when enabled")
NS.HandleSuperTrackedQuestIDChanged(42)
assert(#routeRequests == 3 and routeRequests[3].meta.identity.questSource == "supertrack")

local prompt = addon.WaypointPrompt
followedQuestID, questMode = 42, "on"
prompt:OnQuestChanged()
local follow = assert(routeRequests[4])
assert(follow.meta.backendOverride == "mapzeroth" and follow.meta.identity.questSource == "supertrack")
assert(follow.opts == nil and nativeFollowCalls == 0 and NS.GetSelectedBackendID() == "zygor")
NS.State.routing.pendingManualAuthority = {identity=follow.meta.identity, backendOverride="mapzeroth", mapID=1412, x=.51, y=.65}
NS.HandleSuperTrackedQuestIDChanged(42)
assert(#routeRequests == 4, "AWP's watch hook displaced the pending Mapzeroth follow route")
NS.State.routing.pendingManualAuthority = nil
questMode = "ask"
prompt:OnQuestChanged()
assert(questOffer == 42)
prompt:Answer("route")
assert(not questOffer and routeRequests[5].meta.backendOverride == "mapzeroth" and nativeClicks == 1)
prompt:OnQuestChanged()
dead = true
prompt:Answer("route")
prompt:OnQuestChanged()
addon.Panel:RouteToQuest(42)
NS.HandleQuestWatchAdded(42)
assert(not questOffer and #routeRequests == 5, "Quest follow displaced corpse guidance")

dead = false
prompt:OnQuestChanged()
followedQuestID = 43
prompt:Answer("route")
assert(#routeRequests == 5, "An obsolete followed quest was routed")
NS.SetRoutingEnabled(false)
questMode, followedQuestID = "on", 42
prompt:OnQuestChanged()
assert(nativeFollowCalls == 1 and #routeRequests == 5)
print("Mapzeroth navigation ownership and quest shortcut fixtures passed")

assert(loadfile("tests/mapzeroth_roads_test.lua"))()
local fixture = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, routing = AzerothWaypointNS, fixture.routing
NS.GetDB = function() return { routingBackend = "mapzeroth" } end
NS.GetPlayerMapPosition = function() return 1, .1, .1 end
NS.GetWorldPositionFromMapCoords = function(_, x, y) return 1, x * 1000, y * 1000 end
NS.GetPlayerWaypointDistance = function() return 1000 end
MapzerothAddon.Journey.PlanEntry = function()
    return { steps = { { method = "walk", text = "Walk to goal", path = {
        { mapID = 1, x = .1, y = .1 }, { mapID = 1, x = .9, y = .1 },
    } } } }
end
assert(loadfile("bridge/routing/backends/mapzeroth.lua"))()
local backend = NS.RoutingBackend_Mapzeroth
assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(backend)
for _, provider in ipairs({ "zygor", "dugi", "rxp", "polestar", "apr", "wowpro" }) do
    local target = { mapID = 1, x = .9, y = .1, title = "Collect Journal", subtext = "Loot the chest.",
        guideProvider = provider, semanticKind = "quest", semanticQuestID = 9,
        iconHintKind = "quest", iconHintQuestID = 9 }
    local record = {}
    for key, value in pairs(target) do record[key] = value end
    record.backend, record.type, record.authority, record.target = "mapzeroth", "guide", "guide", target
    routing.guideRouteState, routing.manualAuthority = record, nil
    backend.PlanRoute(record, 1, .9, .1, target.title)
    NS.RecomputeCarrier()
    local output = routing.presentationState
    assert(#record.legs > 2 and output.overlayTitle == "Follow the road" and output.carrierTitle == output.overlayTitle)
    assert(output.pinpointSubtext == target.title and output.iconHintKind == "travel",
        "Road lost its purpose or inherited the destination's interaction instruction")
    local projected = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
    local entry = {}; NS.RouteQueueInternal.CopyGuidePresentationFields(entry, projected)
    assert(entry.title == target.title, "Queue lost the original objective")
    record.currentLegIndex, record.currentLeg = #record.legs, record.legs[#record.legs]
    NS.RecomputeCarrier()
    output = routing.presentationState
    assert(output.carrierTitle == target.title and output.overlayTitle == target.title and output.pinpointSubtext == target.subtext)
    assert(output.iconHintKind == "quest" and output.semanticQuestID == 9)
    assert(record.currentLeg.x == .9 and record.currentLeg.y == .1)
end
-- Direct final walks retain quest presentation through conversion noise;
-- a real approach or an earlier corner remains a travel leg.
do
    local oldRoads, oldPlan = MapzerothAddon.RoadData, MapzerothAddon.Journey.PlanEntry
    MapzerothAddon.RoadData = nil
    local goal = { mapID = 1, x = .9, y = .1, title = "Turn in 'Journey into Thunder Bluff'",
        subtext = "Talk to Cairne Bloodhoof", guideProvider = "questierouter",
        semanticKind = "quest", semanticQuestID = 9, iconHintKind = "quest", iconHintQuestID = 9 }
    local function plan(offset, corner)
        MapzerothAddon.Journey.PlanEntry = function()
            local path = {{mapID = 1, x = .1, y = .1}}
            if corner then path[#path + 1] = {mapID = 1, x = .5, y = .3} end
            path[#path + 1] = {mapID = 1, x = .9, y = .1 + offset}
            return {steps = {{method = "walk", text = "Walk to goal", path = path}}}
        end
        local record = {backend = "mapzeroth", type = "guide", authority = "guide", target = goal,
            mapID = 1, x = goal.x, y = goal.y, title = goal.title, guideProvider = goal.guideProvider}
        routing.guideRouteState, routing.manualAuthority = record, nil
        backend.PlanRoute(record, 1, goal.x, goal.y, goal.title)
        assert(record._fixtureResult.status == "success", "Mapzeroth fixture failed: " .. tostring(record._fixtureResult.reason))
        NS.RecomputeCarrier()
        return record, routing.presentationState
    end
    local record, shown = plan(.00000153608322)
    assert(#record.legs == 1 and record.currentLeg.routeLegKind == "destination"
        and record.currentLeg.x == goal.x and record.currentLeg.y == goal.y,
        "Mapzeroth duplicated or moved a final walk because of conversion precision")
    assert(shown.iconHintKind == "quest" and shown.pinpointSubtext == goal.subtext,
        "Mapzeroth final walk lost the quest icon or NPC context")
    record = plan(.002)
    local translated = record._fixtureResult.legs
    assert(#translated == 2 and translated[1].routeLegKind == "carrier" and translated[2].y == goal.y,
        "Mapzeroth translation collapsed a distinct approach")
    record, shown = plan(.00000153608322, true)
    assert(#record.legs == 2 and record.legs[1].routeLegKind == "carrier" and shown.iconHintKind == "travel"
        and record.legs[2].routeLegKind == "destination" and record.legs[2].y == goal.y,
        "Mapzeroth discarded a walking corner or retained a duplicate final approach")
    MapzerothAddon.RoadData, MapzerothAddon.Journey.PlanEntry = oldRoads, oldPlan
end
print("Mapzeroth fixed road arrow/plaque/overlay/queue output and final quest presentation passed")

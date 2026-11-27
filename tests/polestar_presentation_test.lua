local replaceMethod = dofile("tests/replace_method.lua")
-- Exercise translation through the real core, presentation and icon resolver.
local fixture = assert(loadfile("tests/polestar_integration_test.lua"))()
local NS, r, backend = AzerothWaypointNS, fixture.runtime, fixture.backend
assert(loadfile("core/core.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
Polestar_NavEngine.Find = function(_, from, to, callback)
    callback({ { x = from.x, y = from.y, z = from.z }, { x = to.x, y = to.y, z = to.z } }); return {}
end
NS.GetDB = function() return { routingBackend = "polestar" } end
NS.SafeCall = function(fn, ...) if fn then return pcall(fn, ...) end end
NS.Signature = function(map, x, y) return string.format("%s/%.8f/%.8f", map, x, y) end
NS.GetGuideVisibilityState = function() return "visible" end
NS.GetGuideTargetProvider = function() return fixture.provider end
NS.IsInstanceRouteTravelType = function(t)
    return t == "dungeon" or t == "raid" or t == "delve" or t == "bountiful_delve"
end
NS.GetZygorAssetPath = function(path) return path end
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, "Hearthstone texture" end
NS.State.routing = {}
local routing = NS.State.routing
local playerMap = 1
NS.GetPlayerMapID = function() return playerMap end
local uid
NS.PushCarrierWaypoint = function(map, x, y, title)
    local carrier = routing.carrierState or {}
    local sig = NS.Signature(map, x, y)
    if carrier.sig ~= sig then uid = {} end
    carrier.mapID, carrier.x, carrier.y, carrier.title, carrier.sig, carrier.uid = map, x, y, title, sig, uid
    routing.carrierState = carrier
    return true
end
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/core.lua"))()
assert(loadfile("bridge/routing/validation.lua"))()
assert(loadfile("bridge/routing/progress.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/routing/planning.lua"))()
assert(loadfile("bridge/routing/presentation.lua"))()
local questState = "Incomplete"
local overlay = { Config = {}, overlay = {}, target = {}, arrival = {}, questIconCache = {},
    questSubtextCache = {}, fontStringTextCache = {}, settingsSnapshot = {},
    ResolveQuestType = function() return "Default", questState end }
NS.Internal.WorldOverlay = overlay
assert(loadfile("world_overlay/assets/icons.lua"))()
assert(loadfile("world_overlay/presentation/content.lua"))()
NS.RouteQueueInternal = { TrimString = function(v) return type(v) == "string" and v ~= "" and v or nil end }
assert(loadfile("bridge/routing/queues/projection.lua"))()

local function world(map, x, y)
    return { map = map, c = map, wx = x * 1000, wy = y * 1000 }
end
local function walk(to)
    return { kind = "walk", from = world(1, .1, .1), to = to, label = "Planner's walking instruction" }
end
local function run(target, plan, intent, manual)
    playerMap = 1
    r.Nav.PlanRoute = plan
    NS.ResolveInstanceRouteIntent = function() return intent end
    local record = { backend = "polestar", authority = manual and "manual" or "guide",
        type = manual and "manual" or "guide", title = target.title }
    for key, value in pairs(target) do record[key] = value end
    if manual then
        routing.manualAuthority, routing.guideRouteState = record, nil
    else
        record.guideProvider, record.target = target.guideProvider or "polestar", target
        routing.guideRouteState, routing.manualAuthority = record, nil
    end
    backend.PlanRoute(record, target.mapID, target.x, target.y, target.title)
    NS.RecomputeCarrier()
    return record, routing.presentationState
end
local function target(title, provider)
    return { mapID = 1, x = .7, y = .8, title = title, subtext = "Collect the required items.",
        guideProvider = provider or "polestar", semanticKind = "quest", semanticQuestID = 9,
        iconHintKind = "quest", iconHintQuestID = 9 }
end
local finalPlan = function(context) return { walk(context.target) } end
-- Follow the precise goal identified by Polestar even when two quests share
-- a position. Bookkeeping and tracker rows can update before the waypoint.
do
    local goals = r.Engine.GetStepView(1).goals
    local wp = r.Engine.GetWaypoint()
    local previous = goals[2]
    goals[2] = { index = 2, t = "turnin", quest = 10, text = "Turn in 'Another Quest'", npcName = "Baine",
        status = "active", map = wp.map, x = wp.x, y = wp.y }
    local identity
    for _, index in ipairs({1, 2}) do
        wp.goalIndex = index
        fixture.fire("STEP_UPDATED"); fixture.drain()
        local goal = assert(fixture.provider.extractTarget())
        local record, shown = run(goal, finalPlan)
        local queue = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
        local title = index == 1 and "Accept 'The Journal'" or "Turn in 'Another Quest'"
        local npc = index == 1 and "Talk to Leona" or "Talk to Baine"
        assert(shown.carrierTitle == title and shown.overlayTitle == title and shown.pinpointSubtext == npc)
        assert(queue.mirrorTitle == title and queue.pinpointSubtext == npc and queue.iconHintQuestID == goal.semanticQuestID)
        assert(goal.semanticQuestID == goals[index].quest and goal.guideStepIdentity ~= identity)
        identity = goal.guideStepIdentity
    end
    wp.goalIndex, goals[2] = 1, previous
    fixture.fire("STEP_UPDATED"); fixture.drain()
end
for _, provider in ipairs({ "polestar", "questierouter", "zygor", "dugi", "rxp", "apr", "wowpro" }) do
    for _, status in ipairs({ "Available", "Incomplete", "Complete" }) do
        questState = status
        local goal = target(status .. " quest in the area", provider)
        local record, output = run(goal, finalPlan)
        assert(#record.legs == 1 and record.currentLeg.routeLegKind == "destination", "Final walk remained a carrier or duplicated the destination")
        assert(record.currentLeg.polestarKind == "walk" and record.currentLeg.routeTravelType == nil, "Destination promotion discarded walking or retained travel presentation")
        assert(output.iconHintKind == "quest" and output.iconHintQuestID == 9 and output.semanticQuestID == 9, "Quest ownership lost: " .. provider)
        assert(output.carrierTitle == goal.title and output.overlayTitle == goal.title and output.pinpointSubtext == goal.subtext, "Final arrow/plaque text was replaced by walking instructions")
        assert(overlay.ResolveSnapshotIconSpec(output).key == status .. "Quest", "Wrong actual quest icon: " .. status)
        assert(record.currentLeg.x == goal.x and record.currentLeg.y == goal.y, "Exact destination changed")
        local projected = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
        local entry = {}; NS.RouteQueueInternal.CopyGuidePresentationFields(entry, projected)
        assert(entry.title == goal.title and entry.subtext == goal.subtext and entry.iconHintQuestID == 9
            and entry.guideProvider == provider, "Queue diverged from the resolved quest")
    end
end

-- WorldToMap uses client vectors: a final point can round-trip differently
-- from the requested map coordinate while retaining the exact world goal.
do
    local project = r.Compat.WorldToMap
    r.Compat.WorldToMap = function(...)
        local x, y = project(...)
        return x, y + 0.000153608322
    end
    for _, provider in ipairs({ "polestar", "questierouter", "zygor", "dugi", "rxp", "apr", "wowpro" }) do
        local goal = target("Turn in 'Journey into Thunder Bluff'", provider)
        goal.subtext = "Talk to Cairne Bloodhoof"
        local record, shown = run(goal, finalPlan)
        assert(#record.legs == 1 and record.currentLeg.routeLegKind == "destination",
            "Coordinate round-trip duplicated the final walking destination: " .. provider)
        assert(record.currentLeg.x == goal.x and record.currentLeg.y == goal.y,
            "Final walk did not retain the exact requested map coordinates")
        assert(record.currentLeg.polestarKind == "walk" and record.currentLeg.polestarTo,
            "Final destination promotion discarded the planner's walking data")
        assert(shown.iconHintKind == "quest" and shown.semanticQuestID == 9
            and shown.overlayTitle == goal.title and shown.pinpointSubtext == goal.subtext,
            "Final walking presentation lost the guide's quest context: " .. provider)
        backend.PollNavigationLeg(record)
        NS.RecomputeCarrier()
        assert(#record.legs == 1 and record.currentLeg.routeLegKind == "destination"
            and routing.presentationState.iconHintKind == "quest",
            "Terrain refinement restored the duplicate travel endpoint")
    end
    r.Compat.WorldToMap = project
end

local queries = 0
replaceMethod(Polestar_NavEngine, "Find", function(_, from, to, callback)
    queries = queries + 1
    callback({ { x = from.x, y = from.y }, { x = to.x, y = to.y } }); return {}
end)
local record, output = run(target("Complete the area quest"), finalPlan)
backend.PollNavigationLeg(record)
assert(record.currentLeg.polestarPath, "Final destination lost fixed walking path")
local oldUID, generation, oldLeg = routing.carrierState.uid, record._routeAcceptedPlanGeneration, record.currentLeg
NS.RecomputeCarrier()
assert(record.currentLeg == oldLeg and routing.carrierState.uid == oldUID and record._routeAcceptedPlanGeneration == generation,
    "Unchanged fixed path replaced the accepted destination or carrier: " .. tostring(record.currentLeg == oldLeg)
        .. "/" .. tostring(routing.carrierState.uid == oldUID) .. "/" .. tostring(record._routeAcceptedPlanGeneration) .. "/" .. tostring(generation))
assert(queries == 1 and routing.presentationState.iconHintKind == "quest", "Fixed path churned searches or reverted quest presentation")

local expected = { walk = "travel", fly = "taxi", boat = "ship", zeppelin = "zeppelin", airship = "airship", tram = "travel",
    portal = "portal", hearth = "hearth", teleport = "travel", lift = "travel" }
for kind, icon in pairs(expected) do
    local position = r.Compat.GetPlayerWorldPosition
    -- A standalone lift starts on its boarding deck; a remote lift would
    -- have a leading walk. Native height-less departure is already complete
    -- when the player is more than 30 yards from that deck.
    if kind == "lift" then r.Compat.GetPlayerWorldPosition = function() return 1, 100, 100 end end
    record, output = run(target("Final quest"), function(context)
        return { { kind = kind, from = world(1, .1, .1), to = world(1, .4, .4),
            item = kind == "hearth" and 6948 or nil, spell = kind == "teleport" and 99 or nil,
            label = "Intermediate " .. kind, stops = { { id = 123 } } }, walk(context.target) }
    end)
    assert(output.iconHintKind == icon and overlay.ResolveSnapshotIconSpec(output), "Unsupported intermediate icon: " .. kind)
    assert(output.overlayTitle == "Intermediate " .. kind and output.pinpointSubtext == nil, "Intermediate leg inherited final quest instructions")
    r.Compat.GetPlayerWorldPosition = position
    record.currentLegIndex, record.currentLeg = 2, record.legs[2]
    NS.RecomputeCarrier()
    assert(routing.presentationState.iconHintKind == "quest", "Final approach did not restore quest icon after " .. kind)
end

for _, kind in ipairs({ "dungeon", "raid", "delve", "bountiful_delve" }) do
    local goal = target("Quest inside an instance"); goal.mapID = 2
    local intent = { kind = "instance", travelType = kind, instanceName = "Fixture instance",
        entrance = { mapID = 1, x = .3, y = .4 } }
    record, output = run(goal, finalPlan, intent)
    assert(#record.legs == 2 and record.currentLeg.kind == "entrance" and record.currentLeg.polestarKind == "walk", "Entrance walk was duplicated or lost navigation")
    assert(output.iconHintKind == kind and overlay.ResolveSnapshotIconSpec(output), "Wrong instance icon: " .. kind)
    assert(record.legs[2].mapID == 2 and record.legs[2].x == goal.x, "Original instance destination was lost")
    backend.PollNavigationLeg(record)
    assert(record.currentLeg.polestarPath, "Entrance lost fixed terrain legs")
    playerMap = 2; NS.RecomputeCarrier()
    assert(record.currentLegIndex == 2 and routing.presentationState.iconHintKind == "quest",
        "Outside path distance/floor prevented entry into the intended instance")
    record, output = run(goal, function(context)
        return { { kind = "portal", from = world(1, .1, .1), to = context.target, label = "Take the portal" } }
    end, intent)
    assert(#record.legs == 3 and record.legs[1].kind == "portal" and output.iconHintKind == "portal", "Entrance classification overwrote a portal transition")
    record.currentLegIndex, record.currentLeg = 2, record.legs[2]; NS.RecomputeCarrier()
    assert(routing.presentationState.iconHintKind == kind, "Entrance after portal lost instance type")
    record = run(goal, function() return nil end, intent)
    assert(record._fixtureResult.status == "failed", "No-path result was published as an accepted entrance route")
end

record, output = run(target("Tracked quest"), finalPlan, nil, true)
-- Manual tracked-quest routing uses the original manual quest metadata.
record.manualQuestID = 9; NS.RecomputeCarrier()
assert(routing.presentationState.iconHintKind == "quest" and routing.presentationState.iconHintQuestID == 9,
    "Manual quest icon did not survive the final approach")
record = run(target("Projected destination"), function()
    return { walk(world(2, .7, .8)) }
end)
assert(#record.legs == 2 and record.legs[1].routeLegKind == "carrier" and record.legs[2].mapID == 1,
    "A projected endpoint on a different map was promoted to the exact destination")
for action, icon in pairs({ tram = "travel", sethome = "inn" }) do
    local fact = NS.Internal.PolestarPresentation.Resolve(r, { t = action, text = "Guide instruction" })
    local goal = { mapID = 1, x = .7, y = .8, title = fact.title, semanticKind = "travel", semanticTravelType = fact.travelType }
    record, output = run(goal, finalPlan)
    assert(output.iconHintKind == icon and overlay.ResolveSnapshotIconSpec(output), "Unsupported guide travel semantics: " .. action)
end
local services = { trainer = "gossip_poi", class = "gossip_poi", weapon = "gossip_poi", repair = "npc_repair",
    reagents = "npc_vendor", vendor = "npc_vendor", food = "npc_vendor", general = "npc_vendor", arrows = "npc_vendor",
    bullets = "npc_vendor", ranged = "npc_vendor", innkeeper = "npc_innkeeper", bank = "npc_banker", mailbox = "npc_mailbox",
    auction = "npc_auctioneer", flight = "npc_flightmaster", flightmaster = "npc_flightmaster", stable = "npc_stable_master" }
for service, icon in pairs(services) do
    assert(NS.Internal.PolestarProvider.RoutePoint({ map = 1, x = 70, y = 80, stop = service }, "Service"))
    local metadata = NS.manual.metadata
    record, output = run({ mapID = 1, x = .7, y = .8, title = "Service", searchKind = metadata.searchKind }, finalPlan, nil, true)
    assert(output.iconHintKind == icon and overlay.ResolveSnapshotIconSpec(output), "Unsupported service icon: " .. service)
end
print("Polestar final quest icons, text, queue, fixed walking, intermediate travel and instance entrances passed")

return { fixture = fixture, run = run, target = target, runtime = r, backend = backend, routing = routing }

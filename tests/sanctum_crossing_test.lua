local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local function LetPlayerMove(fixture, mapID)
    local observed = { subzone = "Mage Quarter", outdoors = true, height = 145 }
    fixture.map = mapID
    fixture.NS.GetGuideVisibilityState = function() return "visible" end
    fixture.px, fixture.py = -9009, 867
    GetSubZoneText = function() return observed.subzone end
    GetMinimapZoneText = GetSubZoneText
    IsOutdoors = function() return observed.outdoors end
    IsIndoors = function() return not observed.outdoors end
    UnitPosition = function() return fixture.px, fixture.py, observed.height, 0 end
    return observed
end

-- Every planner goes through the same coordinator; the test installs a
-- planner that supplies walking but has no native map for this crossing.
for _, client in ipairs({
    { forever = false, map = 84, npcID = 216129, x = .4869, y = .8706,
        planners = {"zygor", "farstrider", "mapzeroth", "dugi", "direct"} },
    { forever = true, map = 1453, npcID = 5497, x = .4936, y = .8592,
        planners = {"zygor", "farstrider", "mapzeroth", "polestar", "dugi", "questierouter", "direct"} },
}) do
    for _, id in ipairs(client.planners) do
        local f = make("direct", client.forever)
        local ns = f.NS
        local observation = LetPlayerMove(f, client.map)
        local attempts = {}
        f.behavior[id] = function(attempt)
            attempts[#attempts + 1] = attempt
            return attempt:Complete({ status = "success", backendID = id, reason = id .. "_plan",
                legs = { ns.RouteSpecials.MakeDestinationLeg(id, attempt.mapID, attempt.x, attempt.y, attempt.title) } })
        end
        ns.GetPlayerWaypointDistance = function() return 0 end
        assert(ns.RouteViaBackend(client.map, client.x, client.y, "Trainer", nil, {
            authority = "guide", guideProvider = "zygor", backendOverride = id,
            guideTarget = { navigationNpcID = client.npcID },
        }))
        f.drain()
        local route = ns.State.routing.guideRouteState
        local progress = ns.Internal.RouteProgress
        assert(route.backend == id and #attempts == 2 and #f.calls == 2, id .. " switched planners")
        assert(attempts[2].mapID == client.map and attempts[2].x ~= client.x)
        assert(route.target.x == client.x and route.target.y == client.y and route.target.title == "Trainer")
        assert(progress.PollLeg(route, "guide"))
        local entry = route.currentLeg
        assert(entry.sanctumCrossing and entry.kind == "entrance")
        assert(not ns.AdvanceActiveRouteLeg(route, entry, route._routeAcceptedPlanGeneration, "distance"))
        assert(not progress.PollLeg(route, "guide"))
        observation.subzone, observation.outdoors = "Wizard's Sanctum", false
        assert(progress.PollLeg(route, "guide"))
        assert(route.currentLeg.sanctumContinuation)
        f.drain()
        if client.forever then
            assert(#attempts == 4 and #f.calls == 4, id .. " did not renew its chamber approach")
            assert(progress.PollLeg(route, "guide"))
            local portal = route.currentLeg
            assert(portal.sanctumCrossing.to == "chamber" and portal.kind == "portal")
            observation.height = nil
            assert(not progress.PollLeg(route, "guide"))
            f.px, f.py, observation.height = -9017.5, 885.9, 148.6
            assert(not progress.PollLeg(route, "guide"), "Horizontal proximity confirmed the wrong floor")
            observation.height = 29.6
            assert(progress.PollLeg(route, "guide"))
            f.drain()
        end
        assert(route.backend == id and #route.legs == 1 and route.legs[1].x == client.x)
        assert(route.legs[1].y == client.y and route.legs[1].routeLegKind == "destination")
        assert(f.db.routingBackend == "direct" and #f.calls == #attempts)
    end
end

-- A walker leaving the chamber needs both crossings. An ordinary portable
-- exit remains a valid route and does not acquire a forced walking detour.
do
    local f = make("dugi", true)
    local ns = f.NS
    local observation = LetPlayerMove(f, 1453)
    observation.subzone, observation.outdoors, observation.height = "Wizard's Sanctum", false, 29.6
    ns.GetPlayerWaypointDistance = function() return 0 end
    f.behavior.dugi = "success"
    local route = f.start(1429, .25, .35, "Leave Stormwind")
    f.drain()
    local progression = ns.Internal.RouteProgress
    assert(progression.PollLeg(route, "manual") and route.currentLeg.sanctumCrossing.to == "tower")
    assert(not progression.PollLeg(route, "manual"))
    observation.height = 148.6
    assert(progression.PollLeg(route, "manual"))
    f.drain()
    assert(progression.PollLeg(route, "manual") and route.currentLeg.sanctumCrossing.to == "street")
    observation.subzone, observation.outdoors = "Mage Quarter", true
    assert(progression.PollLeg(route, "manual"))
    f.drain()
    assert(route.backend == "dugi" and #route.legs == 1 and route.legs[1].mapID == 1429)

    observation.subzone, observation.outdoors, observation.height = "Wizard's Sanctum", false, 29.6
    f.behavior.dugi = function(attempt)
        return attempt:Complete({ status = "success", reason = "dugi_plan", legs = {
            { mapID = 1453, x = .49, y = .86, kind = "spell", routeLegKind = "carrier",
                specialAction = { secureType = "spell", securePayload = 3562, activationMode = "portable" } },
            ns.RouteSpecials.MakeDestinationLeg("dugi", attempt.mapID, attempt.x, attempt.y, attempt.title),
        } })
    end
    route = f.start(1455, .25, .35, "Use teleport")
    f.drain()
    assert(#route.legs == 2 and route.legs[1].kind == "spell" and not route.hasSanctumCrossing)
end

-- A planner's remote portal already ends on the receiving side. There is no
-- extra walk to the outside door before this portal or after it lands.
do
    local f = make("mapzeroth", true)
    local ns = f.NS
    local observation = LetPlayerMove(f, 1416)
    local sanctum = ns.RouteSpecials.Sanctum
    f.behavior.mapzeroth = function(attempt)
        local portal = { mapID = 1416, x = .12, y = .56, kind = "portal", routeLegKind = "carrier" }
        sanctum.SetCrossing(portal, sanctum.ForeverPortalArrival())
        return attempt:Complete({ status = "success", reason = "mapzeroth_plan", legs = {
            portal, ns.RouteSpecials.MakeDestinationLeg("mapzeroth", attempt.mapID, attempt.x, attempt.y, attempt.title),
        } })
    end
    local route = f.start(1453, .494, .867, "Tower")
    f.drain()
    local progress = ns.Internal.RouteProgress
    progress.EnsureLeg(route)
    assert(#f.calls == 1 and #route.legs == 2 and route.currentLeg.kind == "portal")
    assert(not progress.PollLeg(route, "manual"))
    f.map = 1453
    observation.subzone, observation.outdoors = "Wizard's Sanctum", false
    assert(progress.PollLeg(route, "manual") and route.currentLeg.routeLegKind == "destination")
end

-- No NPC or floor evidence: this could be a manual waypoint on the street.
do
    local f = make("dugi", true)
    LetPlayerMove(f, 1453)
    f.behavior.dugi = "success"
    local route = f.start(1453, .4936, .8592, "Ordinary map pin")
    f.drain()
    assert(route.backend == "dugi" and #route.legs == 1 and #f.calls == 1)
end

-- The approach cannot publish if a newer destination has superseded it.
do
    local f = make("questierouter", true)
    LetPlayerMove(f, 1453)
    local ns = f.NS
    local late
    f.behavior.questierouter = function(attempt)
        if attempt.sanctumApproach then late = attempt; return "pending" end
        return attempt:Complete({ status = "success", backendID = "questierouter", reason = "questierouter_plan",
            legs = { ns.RouteSpecials.MakeDestinationLeg("questierouter", attempt.mapID, attempt.x, attempt.y, attempt.title) } })
    end
    assert(ns.RouteViaBackend(1453, .4936, .8592, "Trainer", nil, {
        authority = "guide", guideProvider = "zygor", guideTarget = { navigationNpcID = 5497 },
    }))
    f.drain()
    assert(late and late:IsCurrent())
    local replacement = f.start(1, .1, .2, "New waypoint")
    f.drain()
    assert(not late:Complete({ status = "success", reason = "late" }))
    assert(ns.State.routing.manualAuthority == replacement and replacement.legs[1].mapID == 1)
end
-- A doorway that was crossed during an asynchronous search is obsolete,
-- even at the same destination and on the same map.
do
    local f = make("dugi", false)
    local ns = f.NS
    local observation = LetPlayerMove(f, 84)
    local late
    f.behavior.dugi = function(attempt)
        if attempt.sanctumApproach then late = attempt; return "pending" end
        return attempt:Complete({ status = "success", reason = "dugi_plan", legs = {
            ns.RouteSpecials.MakeDestinationLeg("dugi", attempt.mapID, attempt.x, attempt.y, attempt.title),
        } })
    end
    assert(ns.RouteViaBackend(84, .4869, .8706, "Emmery Fiske", nil, {
        authority = "guide", guideProvider = "dugi", guideTarget = { navigationNpcID = 216129 },
    }))
    f.drain()
    assert(late and late.sanctumApproach)
    observation.subzone, observation.outdoors = "Wizard's Sanctum", false
    assert(late:Complete({ status = "success", reason = "dugi_plan", legs = {
        ns.RouteSpecials.MakeDestinationLeg("dugi", late.mapID, late.x, late.y, late.title),
    } }))
    f.drain()
    local record = ns.State.routing.guideRouteState
    assert(#f.calls == 3 and record.backend == "dugi" and #record.legs == 1)
    assert(record.legs[1].x == .4869 and not record.legs[1].sanctumCrossing)
end
print("Sanctum same-planner approaches, exact targets, arrival evidence and superseded results passed")

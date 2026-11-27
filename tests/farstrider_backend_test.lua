-- Standalone Lua 5.1 fixture tests. Run from the addon root with:
--   lua tests/farstrider_backend_test.lua

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local acceptedPlans = {}
local nextRoute = nil
local validationRequests = {}
local validators = {}
local registeredEvents = {}
local rebuildCallbacks = {}
local predicateCalls, playerLocationReads = 0, 0
local usable, bindX = true, .3
local checkTravel = function() predicateCalls = predicateCalls + 1; return usable end

_G.C_Map = {
    GetMapInfo = function(mapID)
        return { name = "Map " .. tostring(mapID) }
    end,
}
_G.C_Spell = {
    GetSpellName = function(spellID)
        if spellID == 100 then return "Teleport: Fixture" end
        return "Fixture Spell " .. tostring(spellID)
    end,
}
_G.C_Item = {
    GetItemNameByID = function(itemID)
        return "Fixture Item " .. tostring(itemID)
    end,
}
_G.FarstriderLibData = {
    Util = {
        CanUseItem = function()
            return true
        end,
    },
}
_G.FarstriderLib = {
    Pathfinding = {
        allNodes = {
            ["dynamic:from"] = { isDynamic = true, key = "dynamic:from",
                edges = { { condition = checkTravel }, { condition = checkTravel }, {} },
                getLocation = function() playerLocationReads = playerLocationReads + 1 end },
            ["dynamic:to"] = { isDynamic = true, edges = {},
                getLocation = function() return { mapId = 2, pos = { x = bindX, y = .4 }, isUI = true } end },
        },
        Rebuild = function() end,
        GetValidTravelNodes = function()
            return {}
        end,
        InvalidateCache = function() error("Do not clear Farstrider geometry caches") end,
    },
}
_G.FarstriderLib_API = {
    RegisterRebuildCallback = function(callback) rebuildCallbacks[#rebuildCallbacks + 1] = callback end,
    FindTrailTo = function(mapID, x, y)
        if nextRoute == "error" then
            error("fixture route failure")
        end
        if nextRoute == nil then
            return nil
        end
        local result = nextRoute
        nextRoute = nil
        if result.exactTarget then
            result.steps[#result.steps].completionLoc = {
                mapId = mapID,
                pos = { x = x, y = y },
                isUI = true,
            }
        end
        return result.steps, result.path, result.edges
    end,
}

_G.CreateFrame = function()
    return {
        RegisterEvent = function(_, event)
            registeredEvents[event] = true
        end,
        SetScript = function(_, scriptType, handler)
            if scriptType == "OnEvent" then
                _G.FARSTRIDER_FIXTURE_EVENT_HANDLER = handler
            end
        end,
    }
end

_G.AzerothWaypointNS = {
    RouteSpecials = {},
    IsAddonLoaded = function(name)
        return name == "FarstriderLib" or name == "FarstriderLibData"
    end,
    AcceptBackendPlan = function(record, backendID, legs, reason)
        acceptedPlans[record] = {
            record = record,
            backendID = backendID,
            legs = legs,
            reason = reason,
        }
        return true
    end,
    RegisterRouteBackendStateValidator = function(backendID, validator, dependencyProbe)
        validators[backendID] = {
            backendID = backendID,
            validator = validator,
            dependencyProbe = dependencyProbe,
        }
    end,
    RequestRouteBackendStateValidation = function(backendID, reason, requestClass)
        validationRequests[#validationRequests + 1] = {
            backendID = backendID,
            reason = reason,
            requestClass = requestClass,
        }
        return true
    end,
    ProbeRouteTravelDependency = function()
        return "ready"
    end,
}

assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("bridge/routing/backends/farstrider.lua"))()
local plannerFixture = assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(AzerothWaypointNS.RoutingBackend_Farstrider)
local backend = _G.AzerothWaypointNS.RoutingBackend_Farstrider

local function loc(mapID, x, y)
    return {
        mapId = mapID,
        pos = { x = x, y = y },
        isUI = true,
    }
end

local function routeWithFirstLeg(edgeType, options)
    options = options or {}
    return {
        exactTarget = true,
        steps = {
            {
                loc = loc(1, 0.10, 0.20),
                completionLoc = loc(2, 0.30, 0.40),
                loca = options.title or "Fixture transition",
                actionOptions = options.actionOptions,
            },
            {
                loc = loc(2, 0.30, 0.40),
                completionLoc = loc(3, 0.50, 0.60),
                loca = "Reach the destination",
            },
        },
        path = {
            { key = "start" },
            { key = "middle" },
            { key = "goal" },
        },
        edges = {
            {
                locaId = edgeType,
                from = options.from or { key = "start" },
                to = options.to or { key = "middle" },
                locaArgs = options.locaArgs,
            },
            {
                locaId = 1000,
                from = { key = "middle" },
                to = { key = "goal" },
            },
        },
    }
end

local function plan(route, mapID, x, y, title)
    nextRoute = route
    local record = {}
    backend.PlanRoute(record, mapID or 3, x or 0.73, y or 0.64, title or "Exact destination")
    local acceptedPlan = assert(acceptedPlans[record], "Farstrider did not accept this request")
    expect(acceptedPlan.backendID == "farstrider", "Farstrider accepted a plan under the wrong backend")
    return acceptedPlan
end

expect(backend.IsAvailable() == true, "Farstrider was unavailable with its current public API loaded")

local movement = plan(routeWithFirstLeg(2000))
expect(movement.legs[1].kind == "carrier" and movement.legs[1].routeTravelType == "travel",
    "Movement leg was not translated")
expect(movement.legs[2].mapID == 3 and movement.legs[2].x == 0.73 and movement.legs[2].y == 0.64,
    "Exact final destination was not preserved")

local connectingFlight = routeWithFirstLeg(1001, { locaArgs = function() return { "Final Flight Master" } end })
local firstStop = { key = "connection" }
connectingFlight.edges[1].from = firstStop
table.insert(connectingFlight.path, 2, firstStop)
table.insert(connectingFlight.edges, 1, {
    locaId = 1001, from = connectingFlight.path[1], to = firstStop,
    locaArgs = function() return { "Intermediate Flight Master" } end,
})
FarstriderLibData.TaxiNodes = {
    [124] = { 0, .10, .20, 1 }, [125] = { 0, .20, .30, 1 }, [126] = { 1, .30, .40, 1 },
}
FarstriderLib.NavNode = { makeNavKey = function(_, pos)
    return ({ [.10] = "start", [.20] = "connection", [.30] = "middle" })[pos.x]
end }
FarstriderLib.Pathfinding.GetNavMapPosFromWorldPos = function(_, position)
    return position.mapId + 1, position.pos
end
local flight = plan(connectingFlight)
expect(flight.legs[1].kind == "taxi" and flight.legs[1].routeTravelType == "taxi",
    "Flight leg was not translated")
local taxiLeg = flight.legs[1]
expect(taxiLeg.mapID == 1 and taxiLeg.x == .10 and taxiLeg.y == .20
    and taxiLeg.taxi.destination.mapID == 2 and taxiLeg.taxi.destination.x == .30
    and taxiLeg.taxi.name == "Final Flight Master" and taxiLeg.taxi.final
    and taxiLeg.taxi.sourceNodeID == 124 and taxiLeg.taxi.nodeID == 126,
    "Taxi matching received the departure point or lost the landing name")

local inside = plan(routeWithFirstLeg(1007, { title = "Leave the instance",
    actionOptions = { { type = "leave_instance", data = 409 } } }))
expect(inside.legs[1].leaveInstanceMapID == 409 and inside.legs[1].kind == "leave_instance"
    and inside.legs[1].title == "Leave the instance" and not inside.legs[1].specialAction,
    "Instance exit lost its manual transition contract")

local tram = plan(routeWithFirstLeg(1008, { title = "Take the Deeprun Tram" })).legs[1]
expect(tram.kind == "tram" and tram.routeTravelType == "tram" and tram.mapID == 1
    and tram.transportDestination.mapID == 2 and tram.transportDestination.x == .30,
    "Tram did not retain separate boarding and landing points")

local mapped = routeWithFirstLeg(2000)
mapped.exactTarget = nil
local mappedPlan = plan(mapped, 13, .75, .64)
local final = mappedPlan.legs[#mappedPlan.legs]
expect(final.mapID == 13 and final.x == .75 and final.y == .64,
    "Zone remapping replaced the original exact destination")
expect(final.routeLegKind == "destination" and final.kind == "destination" and final.routeTravelType == nil,
    "Projected final walking coordinates became an intermediate travel leg")

local portal = plan(routeWithFirstLeg(1002))
expect(portal.legs[1].kind == "portal" and portal.legs[1].routeTravelType == "portal",
    "Portal leg was not translated")

do
    local inside = { key = "sanctum", wizardsSanctum = true }
    local route = routeWithFirstLeg(9, { to = inside, title = "Enter the Wizard's Sanctum" })
    route.steps[1].loc = loc(84, .4951, .8666)
    route.steps[1].completionLoc = loc(84, .4921, .8709)
    route.edges[2].from = inside
    local legs = plan(route, 84, .4813, .9195).legs
    expect(legs[1].kind == "entrance" and legs[1].mapID == 84, "Local tower entry became a portal")
    expect(legs[2].arrivalGate and legs[2].arrivalGate.subzone == "Wizard's Sanctum",
        "The interior leg lost its Retail arrival gate")

    route = routeWithFirstLeg(1002, { to = inside, title = "Portal to Stormwind" })
    route.steps[1].completionLoc = loc(84, .4921, .8709)
    legs = plan(route, 84, .4813, .9195).legs
    expect(legs[1].kind == "portal" and legs[1].mapID == 1 and legs[1].x == .1,
        "An incoming portal lost its original departure")
end

local boat = plan(routeWithFirstLeg(1003))
expect(boat.legs[1].routeTravelType == "ship", "Boat transport lost its presentation type")
expect(boat.legs[1].kind == "boat" and boat.legs[1].transportDestination.mapID == 2,
    "Boat leg was not translated")

local zeppelin = plan(routeWithFirstLeg(1004))
expect(zeppelin.legs[1].routeTravelType == "zeppelin", "Zeppelin transport lost its presentation type")
expect(zeppelin.legs[1].kind == "zeppelin" and zeppelin.legs[1].transportDestination.mapID == 2,
    "Zeppelin leg was not translated")

local item = plan(routeWithFirstLeg(1005, {
    actionOptions = { { type = "item", data = 6948 } },
    locaArgs = function() return { "Fixture Item", "Fixture destination" } end,
}))
expect(item.legs[1].specialAction.secureType == "item"
    and item.legs[1].specialAction.securePayload == 6948,
    "Item action was not translated")
expect(item.legs[1].specialAction.routeDependency.kind == "item"
    and item.legs[1].specialAction.routeDependency.id == 6948,
    "Item action dependency was not retained")

local instanceTeleport = routeWithFirstLeg(1006, { actionOptions = { { type = "spell", data = 100 } } })
instanceTeleport.path[1].key = "instance:409"
instanceTeleport.edges[1].from = { key = "dynamic:from" }
local portable = plan(instanceTeleport).legs[1]
expect(portable.specialAction.activationMode == "portable" and not portable.activationCoords,
    "An indoor teleport was treated as a departure from its exterior reference map")

local hearth = plan(routeWithFirstLeg(1005, {
    actionOptions = { { type = "item", data = 6948, allowAny = true } },
    to = { key = "middle", isDynamic = true },
}))
expect(hearth.legs[1].kind == "hearth" and hearth.legs[1].routeTravelType == "hearth",
    "Hearthstone action was not translated")

local spell = plan(routeWithFirstLeg(1006, {
    actionOptions = { { type = "spell", data = 100 } },
}))
expect(spell.legs[1].specialAction.secureType == "spell"
    and spell.legs[1].specialAction.securePayload == "Teleport: Fixture",
    "Spell action was not translated")
expect(spell.legs[1].specialAction.routeDependency.kind == "spell"
    and spell.legs[1].specialAction.routeDependency.id == 100,
    "Spell action dependency was not retained")

local failed = plan("error", 9, 0.11, 0.22, "Fallback destination")
expect(#failed.legs == 1 and failed.legs[1].kind == "destination",
    "Failed route did not use the direct fallback")
expect(failed.legs[1].mapID == 9 and failed.legs[1].x == 0.11 and failed.legs[1].y == 0.22,
    "Failed-route fallback lost its destination")
expect(failed.reason == "farstrider_nopath_fallback", "Failed-route fallback reason was wrong")

backend.Initialize()
local registeredValidator = assert(validators.farstrider, "Farstrider did not register its validator")
expect(type(registeredValidator) == "table" and registeredValidator.backendID == "farstrider",
    "Farstrider validator was not registered")
expect(type(registeredValidator.validator) == "function", "Farstrider validator callback was missing")
expect(registeredEvents.SPELL_UPDATE_COOLDOWN and registeredEvents.SPELLS_CHANGED,
    "Farstrider validation events were not registered")

backend.OnPlanInvalidated("SPELL_UPDATE_COOLDOWN")
backend.OnPlanInvalidated("BAG_UPDATE_DELAYED")
expect(validationRequests[1].requestClass == "cooldown",
    "Cooldown invalidation did not request coalesced validation")
expect(validationRequests[2].requestClass == "structural",
    "Structural invalidation did not request structural validation")

local notifications = 0
local function notify() notifications = notifications + 1 end
backend.InstallReadinessHooks(notify)
backend.InstallReadinessHooks(notify)
expect(#rebuildCallbacks == 1, "Farstrider callback was registered twice")
local graph = FarstriderLib.Pathfinding
local function state(requestClass)
    local ok, fingerprint = registeredValidator.validator(nil, nil, requestClass)
    expect(ok, "Farstrider could not read travel state")
    return fingerprint
end
local baseline = state()
local cached = {}
graph._validTravelNodesCache = cached
local calls = predicateCalls
expect(state() == baseline and graph._validTravelNodesCache == cached
    and predicateCalls == calls + 1 and playerLocationReads == 0, "An unchanged scan discarded caches or duplicated lookups")
usable = false
local cooldown = state()
expect(cooldown ~= baseline and not graph._validTravelNodesCache,
    "A changed edge on a node that remains valid was missed")
bindX = .6
local rebound = state()
expect(rebound ~= cooldown, "A changed bind location was missed")
rebuildCallbacks[1]()
expect(notifications == 1 and validationRequests[3].reason == "farstrider_graph_rebuilt"
    and state() ~= rebound, "A ready-to-ready rebuild did not invalidate the accepted state")

local runtime = assert(loadfile("tests/route_planning_fixture.lua"))()("farstrider", true)
local ns = runtime.NS
local title
ns.PushCarrierWaypoint = function(_, _, _, text) title = text; return true end
ns.ResolvePresentation = function() end
local instance = 409
GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, instance end
local destination = ns.RouteSpecials.MakeDestinationLeg("farstrider", 2, .8, .9, "Final")
local record = { backend = "farstrider", mapID = 2, x = .8, y = .9, title = "Final",
    legs = { inside.legs[1], destination } }
ns.State.routing.manualAuthority = record
local distanceToLanding = 0
ns.GetPlayerWaypointDistance = function(mapID, x, y)
    if mapID == 2 and x == .30 and y == .40 then return distanceToLanding end
    if mapID == 1 and runtime.map ~= 1 then return 500 end
    return 0
end
runtime.recompute()
expect(title == "Leave the instance" and record.currentLegIndex == 1,
    "Nearness to the exterior entrance discarded the leave instruction")
runtime.map = 2
runtime.recompute()
expect(record.currentLegIndex == 1, "A map change inside the instance advanced the exit")
instance = 0
runtime.recompute()
expect(title == "Final" and record.currentLegIndex == 2 and record._coreLastAdvanceReason == "left_instance",
    "Exiting the instance did not advance the route")

for _, leg in ipairs({ tram, boat.legs[1], zeppelin.legs[1] }) do
    record = { backend = "farstrider", mapID = 2, x = .8, y = .9, title = "Final", legs = { leg, destination } }
    ns.State.routing.manualAuthority = record
    distanceToLanding = 300
    runtime.map = 1
    runtime.recompute()
    expect(record.currentLegIndex == 1, leg.kind .. " advanced at the boarding point")
    runtime.map = 2
    runtime.recompute()
    expect(record.currentLegIndex == 1, "An intermediate map transition skipped " .. leg.kind)
    distanceToLanding = 15
    local monitor = assert(ns.Internal.RouteProgress.frame)
    monitor.scripts.OnUpdate(monitor, .21)
    expect(record.currentLegIndex == 2 and record._coreLastAdvanceReason == "transport_arrival",
        leg.kind .. " did not advance at its landing")
end

-- Exercise the real adapter and validation scheduler across combat. The
-- native search may use combat-only eligibility until the owner is rechecked.
local f = assert(loadfile("tests/route_planning_fixture.lua"))()("farstrider", true)
local active = f.NS
active.IsAddonLoaded = function() return true end
assert(loadfile("bridge/routing/backends/farstrider.lua"))()
active.RoutingBackend_Farstrider.Initialize()
local search = FarstriderLib_API.FindTrailTo
local routes = 0
FarstriderLib_API.FindTrailTo = function(...)
    routes = routes + 1
    assert(not graph._validTravelNodesCache, "reused eligibility across combat states")
    graph._validTravelNodesCache = {}
    nextRoute = routeWithFirstLeg(2000)
    return search(...)
end
calls = predicateCalls
f.combat = true
local owner = f.start(3, .73, .64, "Combat", {strictRouteSuccess=true})
f.drain()
expect(routes == 1 and owner.backend == "farstrider" and owner == active.GetManualAuthority(),
    "Explicit combat request did not commit its Farstrider route")
for _ = 1, 20 do f.event("SPELL_UPDATE_COOLDOWN") end
f.drain()
expect(predicateCalls == calls and routes == 1, "Combat performed an AWP eligibility scan")
f.combat = false
expect(active.FlushDeferredRouteBackendStateValidations())
f.drain()
f.drain()
expect(routes == 2 and predicateCalls > calls and owner == active.GetManualAuthority(),
    "The combat itinerary was not reconsidered once after combat")

print("farstrider_backend_test: ok")

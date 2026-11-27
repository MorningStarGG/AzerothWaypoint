-- Standalone Lua 5.1 fixture tests. Run from the addon root with:
--   lua tests/mapzeroth_backend_test.lua

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

_G.AzerothWaypointNS = {
    CanExecuteRouteEquipmentItem = function(itemID) return tonumber(itemID) ~= 999 end,
    RouteSpecials = {},
}
local mapzerothVersion = "2.3.0"
_G.C_AddOns = {
    IsAddOnLoaded = function(name) return name == "Mapzeroth" end,
    GetAddOnMetadata = function(_, field) return field == "Version" and mapzerothVersion or nil end,
}
_G.GetTime = function() return 0 end
local inCombat = false
_G.InCombatLockdown = function() return inCombat end

local nodes = {
    A = { id = "A", mapID = 1, x = 0.1, y = 0.2 },
    B = { id = "B", mapID = 2, x = 0.3, y = 0.4 },
    TAXI_77 = { id = "TAXI_77", mapID = 2, x = 0.5, y = 0.6 },
    STORMWIND_MAGE_TOWER_ENTRANCE = { id = "STORMWIND_MAGE_TOWER_ENTRANCE", mapID = 84, x = 0.49, y = 0.86 },
    STORMWIND_PORTAL_ROOM_LOWER = { id = "STORMWIND_PORTAL_ROOM_LOWER", mapID = 84, x = 0.46, y = 0.90 },
}
local fixtureSteps = {
    { method = "walk", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Walk" },
    { method = "transition", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Transition" },
    { method = "fly", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Fly" },
    { method = "phaseswitch", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Phase" },
    { method = "taxi", fromID = "A", nodeID = "TAXI_77", path = { nodes.A, nodes.TAXI_77 }, text = "Taxi" },
    { method = "ship", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Ship" },
    { method = "zeppelin", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Zeppelin" },
    { method = "tram", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Tram" },
    { method = "portal", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Click portal", clickPortal = true },
    { method = "teleport", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Teleport", source = { spellID = 42, to = "B" } },
    { method = "hearthstone", fromID = "A", nodeID = "B", path = { nodes.A, nodes.B }, text = "Hearth", source = { itemID = 6948, spellID = 8690, to = "B" } },
    { method = "equip", fromID = "A", nodeID = "A", path = {}, text = "Equip", source = { itemID = 123, equipSeconds = 30 } },
}

local graph = {
    adjacency = {
        A = {
            { from = "A", to = "B", method = "portal", cost = 5 },
            { from = "A", to = "TAXI_77", method = "taxi", cost = 10, fare = 2 },
        },
        YOU_1_1_1 = { { from = "YOU_1_1_1", to = "A", method = "walk", cost = 99 } },
    },
    anywhere = { { to = "B", method = "teleport", cost = 10, source = { spellID = 42 } } },
    phase = { tirisfal = 123 },
}
---@type {cost: integer|table, [string]: unknown}[]
local availableActions = {{
    to = "B", cost = 10, method = "teleport", loadingScreens = 1, bias = 0.01,
    ability = { id = "fixture", spellID = 42, to = "B", cost = 10, cooldown = 60 },
}}
local edgeAvailable = true
local journeyBuildCalls = 0

_G.MapzerothAddon = {
    World = {
        generation = 7,
        GetNode = function(_, id) return nodes[id] end,
        LivePhases = function() return { tirisfal = 123 } end,
    },
    TravelGraph = { Build = function() return graph end },
    Abilities = { GroundForms = {} },
    Edges = {{ from = "A", to = "B", method = "portal", requirements = { quest = 1 } }},
    Options = {
        Get = function(_, key) return ({ loadingScreenTax = 5, maxCooldown = 8, assumeFlightsFound = true })[key] end,
        OnChange = function(_, fn) _G.__mapzerothOptionListener = fn end,
    },
    GetPlayerStart = function() return { id = "YOU_1_1_1", mapID = 1, x = 0.11, y = 0.22 } end,
    PlaceAt = function(_, mapID, x, y) return { id = "AWP_" .. mapID, mapID = 2, x = x + 0.01, y = y + 0.01 } end,
    GetPlayerContext = function()
        return {
            faction = "Alliance", class = "MAGE", race = "Human", raceID = 1, level = 80,
            loadingScreenTax = 5, maxCooldown = 28800, money = 100,
            isEquippable = function() return true end,
            knowsSpell = function() return true end,
            talentRank = function() return 0 end,
            questCompleted = function() return edgeAvailable end,
            mapArtID = function() return 123 end,
            flightNodeFound = function() return true end,
            flightUsable = function() return true end,
            fareFactor = function() return 1 end,
        }
    end,
    GetKnownTeleports = function() return availableActions end,
    GetFlightSpeedMultiplier = function() return 1 end,
    MeetsRequirements = function() return edgeAvailable end,
    Journey = {
        Build = function(_, ctx, start, extras)
            journeyBuildCalls = journeyBuildCalls + 1
            expect(extras[1].nocache == true, "AWP's temporary destination entered the native position cache")
            if inCombat then
                expect(ctx.cooldownRemaining(556) > 0 and ctx.itemCooldownRemaining(6948) > 0,
                    "Combat context offered portable travel")
            end
            return { ctx = ctx, start = start, extras = extras, graph = graph }
        end,
        PlanEntry = function() return { cost = 20, fare = 2, steps = fixtureSteps } end,
    },
}

assert(loadfile("tests/mapzeroth_navigation_fixture.lua"))()(MapzerothAddon)

assert(loadfile("bridge/routing/shared.lua"))()
AzerothWaypointNS.Internal = AzerothWaypointNS.Internal or {}
assert(loadfile("bridge/routing/walking.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
assert(loadfile("bridge/routing/backends/mapzeroth.lua"))()
local plannerFixture = assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(AzerothWaypointNS.RoutingBackend_Mapzeroth)
local backend = _G.AzerothWaypointNS.RoutingBackend_Mapzeroth
local nativePlanner
for index = 1, 32 do
    local name, value = debug.getupvalue(backend.BeginPlan, index)
    if name == "PlanRoute" then nativePlanner = value; break end
end
local private
for index = 1, 32 do
    local name, value = debug.getupvalue(nativePlanner, index)
    if not name then break end
    if name == "Private" then private = value; break end
end
expect(type(private) == "table", "backend compatibility helpers were not found")
local status = private.GetCompatibilityStatus()
expect(status.compatible and status.version == "2.3.0", "complete current Mapzeroth fixture was rejected")
mapzerothVersion = "1.6.0"
status = private.GetCompatibilityStatus()
expect(status.compatible and status.version == "1.6.0", "current Forever Mapzeroth fixture was rejected")
mapzerothVersion = "2.3.0"

local ok, plan = private.PlanRoute({ mapID = 9, x = 0.2, y = 0.3, title = "Fixture" })
expect(ok and #plan.steps == #fixtureSteps, "readable steps were not normalized")
expect(plan.steps[1] ~= fixtureSteps[1] and plan.steps[1].path[1] ~= fixtureSteps[1].path[1], "backend retained mutable upstream tables")
inCombat = true
local combatOK, combatPlan = private.PlanRoute({ mapID = 9, x = 0.2, y = 0.3 })
expect(combatOK and combatPlan.stateFingerprint == AzerothWaypointNS.RouteSpecials.COMBAT_TRAVEL_STATE, "Missing combat itinerary")
inCombat = false
expect(type(plan.stateFingerprint) == "string", "accepted plan lacks a state fingerprint")
expect(#plan.stateFingerprint < 64, "accepted state fingerprint is not compact")
local buildsBeforeSnapshot = journeyBuildCalls
local snapshotOK, snapshotA = private.SnapshotState("test")
local snapshotOK2, snapshotB = private.SnapshotState("test")
expect(snapshotOK and snapshotOK2 and snapshotA == snapshotB, "state fingerprint is not deterministic")
expect(journeyBuildCalls == buildsBeforeSnapshot, "state validation rebuilt Mapzeroth's graph")
local livingContext = MapzerothAddon.GetPlayerContext
MapzerothAddon.GetPlayerContext = function()
    local ctx = livingContext()
    ctx.ghost, ctx.ghostSpeed = true, 8.2
    return ctx
end
local ghostOK, ghostSnapshot = private.SnapshotState("released")
expect(ghostOK and ghostSnapshot ~= snapshotA, "Ghost travel was treated like living travel")
MapzerothAddon.GetPlayerContext = livingContext
edgeAvailable = false
local changedOK, changedSnapshot = private.SnapshotState("edge change")
expect(changedOK and changedSnapshot ~= snapshotA, "route-affecting requirement change was not detected")
edgeAvailable = true
local secretValue = {}
availableActions[1].cost = secretValue
_G.issecretvalue = function(value) return value == secretValue end
local secretOK, secretSnapshot = private.SnapshotState("secret")
expect(secretOK and type(secretSnapshot) == "string", "inaccessible snapshot value was compared or rejected")
availableActions[1].cost, _G.issecretvalue = 10, nil

local workingAbilities = _G.MapzerothAddon.GetKnownTeleports
_G.MapzerothAddon.GetKnownTeleports = function() error("fixture failure") end
local failedSnapshot = private.SnapshotState("failure")
expect(failedSnapshot == false, "failed state snapshot was reported as successful")
_G.MapzerothAddon.GetKnownTeleports = workingAbilities

local savedBuild = _G.MapzerothAddon.Journey.Build
_G.MapzerothAddon.Journey.Build = nil
local incomplete = private.GetCompatibilityStatus()
expect(not incomplete.compatible and incomplete.missing == "Journey.Build", "incomplete Mapzeroth capability set was accepted")
_G.MapzerothAddon.Journey.Build = savedBuild

-- Backend translation fixture.
local NS = _G.AzerothWaypointNS
local accepted
NS.RouteSpecials.CoordsMatch = function(am, ax, ay, bm, bx, by, e)
    return am == bm and math.abs(ax - bx) <= e and math.abs(ay - by) <= e
end
local needsSanctumEntry = false
NS.RouteSpecials.PlayerNeedsWizardsSanctumEntry = function() return needsSanctumEntry end
NS.ResolveInstanceRouteIntent = function(mapID, x, y, title)
    if mapID ~= 999 then return nil end
    return {
        travelType = "dungeon", instanceName = title,
        entrance = { mapID = 2, x = 0.4, y = 0.5 },
        final = { mapID = mapID, x = x, y = y, title = title },
    }
end
NS.AcceptBackendPlan = function(record, backendID, legs, reason)
    accepted = { record = record, backendID = backendID, legs = legs, reason = reason }
    record.legs = legs
    return true
end
NS.ClearRouteTravelDependencies = function() end
local record = { backend = "mapzeroth", target = { mapID = 9, x = 0.2, y = 0.3, title = "Exact" } }
backend.PlanRoute(record, 9, 0.2, 0.3, "Exact")
expect(accepted and accepted.backendID == "mapzeroth", "backend did not accept translated plan")
local taxi, equip, hearth
for _, leg in ipairs(accepted.legs) do
    if leg.kind == "taxi" then taxi = leg end
    if leg.kind == "equip" then equip = leg end
    if leg.kind == "hearthstone" then hearth = leg end
end
expect(taxi and taxi.taxi.nodeID == 77 and taxi.taxi.final, "numeric taxi-node extraction failed")
expect(equip and equip.specialAction.executionType == "equip" and equip.specialAction.itemID == 123, "equip step translation failed")
expect(hearth and hearth.specialAction.secureType == "item" and hearth.specialAction.securePayload == 6948, "hearth item translation failed")
local final = accepted.legs[#accepted.legs]
expect(final.mapID == 9 and final.x == 0.2 and final.y == 0.3, "exact final coordinates were not preserved")

local normalPlanRoute = private.PlanRoute
needsSanctumEntry = true
NS.RouteSpecials.MakeWizardsSanctumArrivalGate = function() return { subzone = "Wizard's Sanctum" } end
NS.RouteSpecials.EnsureMageTowerEntryBeforeWizardsSanctumLeg = function(legs, source, mapID, x, y)
    legs[#legs + 1] = { mapID = mapID, x = x, y = y, kind = "entrance", routeLegKind = "carrier", source = source }
end
private.PlanRoute = function(_target)
    return true, {
        start = nodes.A, destination = nodes.STORMWIND_PORTAL_ROOM_LOWER, stateFingerprint = "sanctum",
        steps = {{
            method = "walk", fromID = "A", nodeID = "STORMWIND_PORTAL_ROOM_LOWER",
            path = { nodes.A, nodes.STORMWIND_PORTAL_ROOM_LOWER }, text = "Enter the portal room",
        }},
    }
end
backend.PlanRoute(record, 84, 0.46, 0.90, "Sanctum")
expect(accepted.legs[1].kind == "entrance" and accepted.legs[2].arrivalGate ~= nil,
    "Wizard's Sanctum entrance gate was not preserved")
private.PlanRoute = normalPlanRoute
needsSanctumEntry = false

-- Native Journey hides the zero-cost door from its display steps. Its raw
-- route still establishes the edge, and each directed crossing keeps its
-- source by the correct side of the doorway.
do
    NS.IsWoWForever = function() return true end
    local outer, inner = "ENTRANCE_SW_WIZARDS_SANCTUM_OUTER", "ENTRANCE_SW_WIZARDS_SANCTUM_INNER"
    nodes[outer] = { id = outer, mapID = 1453, x = .4944, y = .8677 }
    nodes[inner] = { id = inner, mapID = 1453, x = .4936, y = .8693 }
    local journey = MapzerothAddon.Journey
    local replaceMethod = dofile("tests/replace_method.lua")
    local saved = journey.PlanEntry
    local endpoint = { id = "GOAL", mapID = 1453, x = .49, y = .86 }
    for _, pair in ipairs({ { outer, inner }, { inner, outer } }) do
        local from, to = pair[1], pair[2]
        replaceMethod(journey, "PlanEntry", function()
            return { cost = 6, goal = endpoint.id, raw = { { method = "walk", from = from, to = to, cost = 0 } },
                steps = { { method = "walk", fromID = to, nodeID = endpoint.id,
                    path = { nodes[to], endpoint }, text = "Continue" } } }
        end)
        backend.PlanRoute(record, 1453, .49, .86, "Forever")
        local crossing = accepted.legs[1]
        expect(crossing.sanctumCrossing and crossing.kind == "entrance" and crossing.x == nodes[from].x,
            "Hidden native doorway was lost or aimed at the far side")
        expect(crossing.sanctumCrossing.to == (to == inner and "inside" or "street"))
        expect(accepted.legs[#accepted.legs].routeLegKind == "destination")

        replaceMethod(journey, "PlanEntry", function()
            return { cost = 6, goal = endpoint.id, raw = { { method = "walk", from = from, to = to, cost = 0 } },
                steps = { { method = "walk", fromID = from, nodeID = endpoint.id,
                    path = { nodes[from], nodes[to], endpoint }, text = "Merged walk" } } }
        end)
        backend.PlanRoute(record, 1453, .49, .86, "Forever")
        expect(accepted.legs[1].sanctumCrossing and accepted.legs[1].x == nodes[from].x,
            "The merged native walk lost the doorway")
        expect(not accepted.legs[2].sanctumCrossing, "The merged walk added the doorway twice")
    end
    journey.PlanEntry = saved
    NS.IsWoWForever = nil
end

backend.PlanRoute(record, 9, 0.2, 0.3, "Exact")
inCombat = true
backend.PlanRoute(record, 9, 0.2, 0.3, "Exact")
expect(record._fixtureResult.status == "success", "Same-target combat search failed")
backend.PlanRoute(record, 10, 0.4, 0.5, "New in combat")
final = accepted.legs[#accepted.legs]
expect(record._fixtureResult.status == "success" and final.mapID == 10 and final.x == .4 and final.y == .5,
    "New combat destination was not accepted")
local replaceMethod = dofile("tests/replace_method.lua")
local originalPlan = replaceMethod(MapzerothAddon.Journey, "PlanEntry", function() return nil end)
backend.PlanRoute(record, 10, .4, .5, "No eligible path")
expect(record._fixtureResult.status == "deferred" and record._fixtureResult.reason == "combat", "Missing combat path was discarded")
replaceMethod(MapzerothAddon.Journey, "PlanEntry", function() error("fixture failure") end)
backend.PlanRoute(record, 10, .4, .5, "Broken planner")
expect(record._fixtureResult.status == "failed", "Planner error waited for combat")
MapzerothAddon.Journey.PlanEntry = originalPlan
inCombat = false

backend.PlanRoute(record, 999, 0.7, 0.8, "Instance")
final = accepted.legs[#accepted.legs]
expect(final.mapID == 999 and final.x == 0.7 and final.y == 0.8 and final.routeTravelType == "dungeon",
    "instance entrance plan lost its exact instance destination")

print("mapzeroth_backend_test: ok")

return { backend = backend, private = private, nodes = nodes, setSteps = function(steps) fixtureSteps = steps end, setCombat = function(value) inCombat = value end }

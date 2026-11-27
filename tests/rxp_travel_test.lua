local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
local fixture = assert(loadfile("tests/rxp_integration_test.lua"))()
local NS = AzerothWaypointNS
local API = NS.Internal.RXPProvider
local rxp, provider, drain = fixture.runtime, fixture.provider, fixture.drain
local function expect(value, message) assert(value, message) end
local function read(path)
    local file = assert(io.open(path, "rb")); local text = file:read("*a"):gsub("\r\n", "\n"); file:close(); return text
end
local function refresh() API.Schedule("fixture"); drain(); return provider.extractTarget() end
local step, flight, boarding, conversions, current
local function setup(root, flavor)
    rxp.game, rxp.player.faction = flavor, "Alliance"
    assert(loadfile(root .. "DB/" .. (flavor == "FOREVER" and "forever" or "mainline") .. "/flightData.lua"))("RXPGuides", rxp)
    local text = read(root .. "DB/" .. (flavor == "FOREVER" and "forever" or "mainline") .. "/db.lua")
    rxp.taxiPos = assert(loadstring("return " .. assert(text:match("addon%.taxiPos%s*=%s*(%b{})"))))()
    conversions, current = 0, 1
    NS.ResolveUserWaypointMapCoordsFromWorldPosition = function(wx, wy, preferred, world)
        local native = rxp.taxiPos[0][2]
        expect(wx == native.wy and wy == native.wx and world == 0 and preferred == nil, "Flight world axes/instance were corrupted")
        conversions = conversions + 1
        return flavor == "FOREVER" and 1453 or 84, .7, .8
    end
    step = { index = 1, active = true, elements = {} }
    flight = { tag = "fly", location = "STORMWIND", text = "Fly to Stormwind", step = step }
    boarding = { tag = "goto", zone = 47, x = 77.48, y = 44.28, arrow = true, textOnly = true, step = step }
    step.elements = { boarding, flight, { tag = "target", targets = { "Felicia Maline" }, textOnly = true, step = step } }
    rxp.currentGuide = { group = "Travel fixture", name = flavor, steps = { step } }
    rxp.GetGuideProgress = function() return current end
    rxp.RXPFrame.activeSteps, rxp.activeWaypoints, rxp.arrowFrame.element = { step }, { boarding }, boarding
    rxp.isHidden, rxp.settings.profile.showEnabled = false, true
    NS.SelectGuideProvider("rxp")
end

for _, client in ipairs({ { NativePath("retail", "RXPGuides/"), "MAINLINE" }, { NativePath("forever", "RXPGuides/"), "FOREVER" } }) do
    setup(client[1], client[2])
    local target = refresh()
    expect(target and target.mapID ~= 47 and target.x == .7 and target.title == "Travel to Stormwind", "Flight arrival was confused with boarding")
    expect(target.guideTravelIntent.nodeID == 2 and target.rxpOwner == 1 and target.rxpElement == 2, "Arrival lost instruction ownership")
    expect(not target.specialAction and target.subtext == nil and target.semanticTravelType == "travel", "Guide forced transportation or carried departure context")
    rxp.activeWaypoints, rxp.arrowFrame.element = {}, nil
    expect(refresh().mapID == target.mapID, "Coordinate-less native selection lost resolvable flight arrival")
    rxp.activeWaypoints, rxp.arrowFrame.element = { boarding }, boarding
    local intent = provider.getTravelIntent()
    local snapshot = API.GetSnapshot()
    for _ = 1, 100 do refresh() end
    expect(provider.getTravelIntent() == intent and API.GetSnapshot() == snapshot and conversions == 1, "Stable arrival rebuilt snapshots or converted coordinates repeatedly")
    local calls = 0
    rxp.SetElementComplete = function(element) expect(element == flight, "Completed a different objective"); calls = calls + 1; element.completed = true end
    local record = { target = target }
    current = 2
    expect(not provider.onDestinationReached(record, intent), "Stale native step completed")
    current = 1
    expect(provider.onDestinationReached(record, intent) and calls == 1, "Verified arrival did not use native element completion")
    drain()
    expect(not provider.onDestinationReached(record, intent) and calls == 1, "Completed flight was checked twice")

    flight.completed = nil
    local quest = { tag = "accept", questId = 9, text = "Accept A Journal", step = step }
    step.elements[#step.elements + 1] = quest
    expect(refresh().mapID == 47 and provider.getTravelIntent().reason == "departure_or_other_objective", "Arrival bypassed departure quest")
    quest.completed = true
    expect(refresh().mapID ~= 47, "Flight did not activate after native departure objective completion")
    boarding.textOnly = nil
    expect(refresh().mapID == 47, "Required movement checkpoint was bypassed")
    boarding.textOnly = true

    local other = { tag = "fly", location = "WESTFALL", text = "Fly to Westfall", step = step }
    step.elements[#step.elements + 1] = other
    expect(refresh().mapID == 47 and provider.getTravelIntent().reason == "conflicting_flight_instructions", "Conflicting active flights selected a landing")
    step.elements[#step.elements] = nil

    flight.location = "DOES NOT EXIST"
    expect(refresh().mapID == 47 and provider.getTravelIntent().reason == "unknown_flight_name", "Unresolved flight manufactured coordinates")
    flight.location = "STORMWIND"
    rxp.FPDB = { Alliance = { [2] = { name = "Stormwind, Elwynn" }, [999] = { name = "Stormwind, Elsewhere" } } }
    expect(refresh().mapID == 47 and provider.getTravelIntent().reason == "ambiguous_flight_name", "Ambiguous landing selected")
    rxp.FPDB = { Alliance = { [2] = { name = "Stormwind, Elwynn" } } }
    rxp.taxiPos = {}
    expect(refresh().mapID == 47 and provider.getTravelIntent().nodeID == 2, "Missing coordinates lost advisory node identity")
    rxp.FPDB = { Alliance = {} }
    rxp.taxiPos = { [0] = { [2] = { wx = -111, wy = 333, flag = 1, name = "Pinewood Post, Azure Span" } } }
    flight.location = "PINEWOOD POST"
    expect(refresh().mapID ~= 47, "Position-only flight node required an unrelated timing entry")
    flight.location = "AZURE SPAN"
    expect(refresh().mapID ~= 47, "Unambiguous authored zone name was not resolved")
    rxp.taxiPos = { [0] = { [2] = { wx = -111, wy = 333, flag = 2, name = "Pinewood Post, Azure Span" } } }
    expect(refresh().mapID == 47, "Opposite-faction position-only node became a destination")
    rxp.settings.profile.showEnabled = false; refresh()
    expect(not provider.getTravelIntent(), "Paused guide retained a flight hint")

    -- Execute the installed native handler: departure, rather than arrival,
    -- completes RXP's own flight instruction. AWP must leave this intact.
    local source = read(client[1] .. "functions.lua")
    local first = assert(source:find("function addon.functions.fly(self, ...)", 1, true))
    local last = assert(source:find("function addon.functions.deathskip", first, true))
    local completed = 0
    local addon = { functions = {}, settings = { profile = { enableFPAutomation = true } },
        flightInfo = { startFlight = 1 }, comms = { AnnounceStepEvent = function() end },
        SetElementComplete = function(_element) completed = completed + 1 end }
    local env = setmetatable({ addon = addon, IsShiftKeyDown = function() return false end,
        UnitOnTaxi = function() return true end, GetTime = function() return 1.1 end, RXPCData = {} }, { __index = _G })
    local chunk = assert(loadstring(source:sub(first, last - 1))); setfenv(chunk, env); chunk()
    addon.functions.fly({ element = { step = { active = true } } }, "PLAYER_CONTROL_LOST")
    expect(completed == 1, "Native departure completion contract changed")
    local completionFirst = assert(source:find("function addon.SetElementComplete(", 1, true))
    local completionLast = assert(source:find("function addon.SetElementIncomplete(", completionFirst, true))
    addon.UpdateMap = function() end
    addon.lastStepUpdate = 1
    local nativeCompletion = assert(loadstring(source:sub(completionFirst, completionLast - 1)))
    setfenv(nativeCompletion, env); nativeCompletion()
    local other = { tag = "accept" }
    local nativeFlight = { tag = "fly", step = { active = true }, sibling = other }
    addon.SetElementComplete(nativeFlight)
    expect(nativeFlight.completed and nativeFlight.skip and not other.completed, "Native element completion affected another objective")
end

-- Exercise the real shared dispatcher and delayed-arrival guards.
setup(NativePath("retail", "RXPGuides/"), "MAINLINE"); local target = refresh()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp", provider)
NS.State.routing = { activeGuideProvider = "rxp" }
local record = { authority = "guide", guideProvider = "rxp", target = target, currentLegIndex = 1,
    legs = { { mapID = target.mapID, x = target.x, y = target.y } }, _routeAcceptedPlanGeneration = 1 }
local active, distance, taxi, combat, calls = record, 20, false, false, 0
NS.GetActiveAuthorityRecord = function() return active end
NS.GetPlayerWaypointDistance = function() return distance end
NS.RouteArrivalGateMatches = function() return true end
UnitOnTaxi = function() return taxi end
InCombatLockdown = function() return combat end
replaceMethod(rxp, "SetElementComplete", function(element) calls = calls + 1; element.completed = true end)
taxi = true; NS.CheckGuideRouteDestinationReached(record, 55); drain(); expect(calls == 0, "Flight completed while airborne")
taxi = false; distance = 56; NS.CheckGuideRouteDestinationReached(record, 55); drain(); expect(calls == 0, "Flight completed before arrival")
distance = 20; combat = true; NS.CheckGuideRouteDestinationReached(record, 55); drain(); expect(calls == 0, "Flight completed in combat")
combat = false; NS.CheckGuideRouteDestinationReached(record, 55)
record._routeAcceptedPlanGeneration = 2; drain(); expect(calls == 0, "Replaced plan's callback completed flight")
NS.CheckGuideRouteDestinationReached(record, 55); combat = true; drain()
expect(calls == 0, "Queued arrival completed after combat began")
combat = false
local originalProbe = issecretvalue
issecretvalue = function(value) return value == distance end
NS.CheckGuideRouteDestinationReached(record, 55); drain()
expect(calls == 0, "Secret arrival distance completed a flight")
issecretvalue = originalProbe
NS.CheckGuideRouteDestinationReached(record, 55); active = { authority = "manual" }; drain()
expect(calls == 0 and not NS.GetActiveGuideTravelIntent(), "Manual authority failed to suppress completion/intent")
active = record; NS.CheckGuideRouteDestinationReached(record, 55); distance = 100; drain()
expect(calls == 0, "Delayed callback ignored movement away")
distance = 20; NS.CheckGuideRouteDestinationReached(record, 55); drain()
expect(calls == 1, "Confirmed backend arrival did not complete exactly one flight instruction")
NS.CheckGuideRouteDestinationReached(record, 55); drain(); expect(calls == 1, "Arrival callback repeated")
flight.completed = nil; target = refresh(); record.target = target
record._routeAcceptedPlanGeneration = 3
replaceMethod(rxp, "SetElementComplete", function() calls = calls + 1; error("native failure") end)
NS.CheckGuideRouteDestinationReached(record, 55); drain()
for _ = 1, 100 do NS.CheckGuideRouteDestinationReached(record, 55) end
drain()
expect(calls == 2 and not flight.completed, "Failed native completion retried continuously or fabricated progress")
print("RXP Retail/Forever flight endpoints, native progression, cached conversion and shared arrival guards passed")

local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local core = make("direct", false)
core.NS.RouteViaBackend(84, .7, .8, "Travel to Stormwind", nil,
    { authority = "guide", guideProvider = "rxp", guideTarget = { guideTravelIntent = { kind = "flight", nodeID = 2 } } })
core.drain()
local accepted = core.NS.State.routing.guideRouteStates.rxp
expect(accepted.target.guideTravelIntent.nodeID == 2 and accepted.backend == "direct", "Real core dropped intent before accepting a backend plan")
print("Core guide route publication preserves arrival intent through selected-backend planning")

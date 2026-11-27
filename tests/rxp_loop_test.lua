local NativePath = dofile("tests/native_path.lua")
-- Run the real installed RXP loop/arrow functions, with deterministic player
-- distances and map-pin filtering, through AWP's existing provider observers.
local fixture = assert(loadfile("tests/rxp_integration_test.lua"))()
local NS = AzerothWaypointNS
local API, rxp, provider = NS.Internal.RXPProvider, fixture.runtime, fixture.provider
local function expect(value, message) if not value then error(message, 2) end end
local function read(path)
    local file = assert(io.open(path, "rb"), path)
    local source = file:read("*a"); file:close()
    return (source:gsub("\r\n", "\n"))
end
local originalLibStub = LibStub
local observedGoto, observedMap = rxp.UpdateGotoSteps, rxp.UpdateMap
local routed = 0
provider.installHooks(function() routed = routed + 1 end)
local roots = { NativePath("retail", "RXPGuides/"), NativePath("forever", "RXPGuides/") }
local guideSource = read(roots[1] .. "Guides/Retail/Endgame/Midnight/Storylines.lua")
local reported = assert(guideSource:match("#loop\n(%.goto 2405,46%.78,56%.55,10,0.-)\nstep"))
expect(reported:find(".complete 91145,2", 1, true), "Reported loop/objective association changed")
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp", provider)
NS.RegisterGuideTargetProvider("zygor", { isLoaded = function() return true end })
NS.IsInstanceRouteTravelType = function() return false end
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/presentation.lua"))()
NS.RouteQueueInternal = { TrimString = function(value) return type(value) == "string" and value ~= "" and value or nil end,
    GetWaypointSig = function() return "loop_fixture" end }
assert(loadfile("bridge/routing/queues/projection.lua"))()
NS.SyncGuideQueueProjection = function() end
local function checkOutput(target)
    NS.State.routing = { activeGuideProvider = "zygor", guideRouteStates = {} }
    NS.UpdateGuideTarget("rxp", target, false)
    NS.State.routing.activeGuideProvider = "rxp"
    local record = assert(NS.GetActiveGuideRouteState())
    NS.State.routing.carrierState = { source = "guide", kind = "guide", routeLegKind = "destination",
        title = target.title, sig = "loop_fixture", finalMapID = target.mapID, finalX = target.x, finalY = target.y }
    local output = NS.ResolvePresentation()
    expect(output.carrierTitle == target.title and output.overlayTitle == target.title
        and output.pinpointSubtext == target.subtext and output.semanticQuestID == 91145,
        "Loop point diverged from shared arrow/plaque/overlay presentation")
    local queue = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
    expect(queue.mirrorTitle == target.title and queue.pinpointSubtext == target.subtext
        and queue.semanticQuestID == 91145, "Loop point diverged from queue presentation")
end

for _, root in ipairs(roots) do
    local distances, playerInstance, located = {}, 99, true
    local secretDistance
    local hbd = {
        GetWorldCoordinatesFromZone = function(_, x, y) return x * 10000, y * 10000, 99 end,
        GetPlayerWorldPosition = function() if located then return 0, 0, playerInstance end end,
        GetWorldVector = function(_, _, _, _, wx) return 0, secretDistance or distances[wx] end,
    }
    _G.LibStub = function(name, ...)
        if name == "HereBeDragons-2.0" then return hbd end
        return originalLibStub(name, ...)
    end
    _G.issecretvalue = function(value) return value == "secret distance" end
    local mapSource, functions = read(root .. "map.lua"), read(root .. "functions.lua")
    expect(mapSource:find("if not af:IsShown() then", 1, true), "Native reset precondition changed; review fixture")
    local constructor = assert(functions:match('(addon%.functions%["goto"%] = function%(self, %.%.%.%).-\nend)'))
    local nativeParser = { functions = {}, mapConversion = {}, icons = { ["goto"] = "" },
        GetMapInfo = function(zone, x, y) return tonumber(zone), tonumber(x), tonumber(y) end }
    assert(loadstring("local addon,HBD,L=...;local fmt=string.format;\n" .. constructor))(
        nativeParser, hbd, function(value) return value end)
    local arrowSource = assert(mapSource:match("(local function updateArrowData%(%).-\nend)"))
    local gotoSource = assert(mapSource:match("(function addon%.UpdateGotoSteps%(%).-\nend)"))
    local af = { shown = false }
    function af:IsShown() return self.shown end
    function af:SetShown(value) self.shown = value end
    function af:Hide() self.shown = false end
    rxp.arrowFrame = af
    rxp.linePoints = {}
    rxp.comms = { PrettyDebug = function() end }
    rxp.SetElementComplete = function() error("Cursor must not complete native objectives") end
    rxp.ScheduleTask = function() end
    local nativeData = { completedWaypoints = {} }
    local nativeGoto, nativeArrow = assert(loadstring([[
        local addon,HBD,af,RXPCData,LibStub=...
        local RXP=addon; local corpseWP={};local closestPoint,currentPoint,lastPoint
        local maxDist=math.huge
        local function DisplayLines() end
        local function UnitIsGhost() return false end
        local function IsInInstance() return false end
        local function IsDeathSkip() return false end
        local bit={band=function(a,b) return a%b end}
    ]] .. arrowSource .. "\n" .. gotoSource .. "\nreturn addon.UpdateGotoSteps,updateArrowData"))(
        rxp, hbd, af, nativeData, LibStub)
    -- The production hook calls this observer after the native routine.
    rxp.UpdateGotoSteps = observedGoto
    local rebuilds, observing = 0, false
    local step
    local function rebuild()
        rebuilds = rebuilds + 1
        rxp.updateMap = false
        rxp.activeWaypoints = {}
        for _, element in ipairs(step.elements) do
            if element.arrow then
                local wp = nativeData.completedWaypoints[step.index] or {}
                local skip = wp[element.wpHash] or element.skip
                wp[element.wpHash] = skip
                nativeData.completedWaypoints[step.index] = wp
                if not skip and not (type(element.parent) == "table" and (element.parent.skip or element.parent.completed)) then
                    rxp.activeWaypoints[#rxp.activeWaypoints + 1] = element
                end
            end
        end
        nativeArrow()
        if observing then observedMap(true) end
    end
    rxp.UpdateMap = function(reset) if reset then rebuild() else rxp.updateMap = true end end
    local function setup(disabled)
        step = { index = 1, stepId = 50, active = true, loop = "", arrowtext = "Click on the Bodies", elements = {} }
        for args in reported:gmatch("%.goto ([^\n]+)") do
            local values = {}; for value in args:gmatch("[^,]+") do values[#values + 1] = value end
            local element = nativeParser.functions["goto"]("reported guide", nil, unpack(values))
            element.tag, element.step, element.wpHash = "goto", step, #step.elements + 1
            -- GuideLoader resolves the constructor's parent=true marker to
            -- the preceding actionable element (none in this reported step).
            element.parent = nil
            step.elements[#step.elements + 1] = element
        end
        expect(#step.elements == 3 and step.elements[1].textOnly and step.elements[1].radius == 10,
            "Reported goto was not parsed through the installed native constructor")
        step.elements[4] = { tag = "complete", questId = 91145, obj = 2,
            text = "0/3 Bodies investigated", step = step }
        rxp.currentGuide = { group = "RestedXP Midnight", name = root, key = root, steps = { step } }
        rxp.GetGuideProgress = function() return 1 end
        rxp.RXPFrame.activeSteps = { step }
        rxp.settings.profile.disableArrow, rxp.settings.profile.showEnabled = disabled, true
        rxp.settings.profile.hideGuideWindow = nil
        rxp.hideArrow, rxp.isHidden, af.element = false, false, nil
        nativeData.completedWaypoints = {}
        distances = { [step.elements[1].wx] = 4.2841, [step.elements[2].wx] = 22.4468, [step.elements[3].wx] = 35 }
        rebuilds = 0
        observing = false
        rebuild()
        fixture.messages.RXP_GUIDE_LOADED()
        fixture.drain()
    end
    local function tick()
        nativeGoto()
        if observing then observedGoto() end
        if rxp.updateMap then rebuild() end
        fixture.drain()
    end
    setup(true)
    local first, second
    for _ = 1, 12 do
        tick()
        if af.element.x == 46.78 then first = true end
        if af.element.x == 46.95 then second = true end
    end
    expect(first and second and rebuilds > 8 and not af:IsShown(), "Installed hidden-arrow reset no longer reproduces")
    print(root .. " native hidden-arrow oscillation reproduced: " .. rebuilds .. " map builds")

    setup(true); observing = true
    tick(); tick()
    local target = assert(provider.extractTarget())
    expect(target.rxpOwner == 1 and target.rxpElement == 4 and target.rxpWaypoint == 2
        and target.title == "0/3 Bodies investigated" and target.subtext == "Click on the Bodies"
        and target.semanticQuestID == 91145 and math.abs(target.x - .4695) < .000001,
        "Stable point lost exact destination, objective or presentation ownership")
    expect(API.GetSnapshot().navigationReason == "loop_cursor", "Cursor ownership was not diagnosed")
    checkOutput(target)
    local snapshot, received, built, routeCount = API.GetSnapshot(), API.counters.received, API.counters.built, routed
    local nativeBuilds = rebuilds
    for _ = 1, 500 do tick() end
    expect(provider.extractTarget() == target and API.GetSnapshot() == snapshot and API.counters.received == received
        and API.counters.built == built and routed == routeCount,
        "Stationary native pointer flips scheduled AWP work, rebuilt presentation or requested routes")
    expect(rebuilds > nativeBuilds + 400, "Fixture concealed native map churn")
    expect(rxp.settings.profile.disableArrow and not af:IsShown(), "AWP changed the native arrow preference/visibility")
    -- Isolate AWP's unchanged observer from native map allocations. Collection
    -- controls are test-only; the addon never forces or suspends collection.
    collectgarbage("collect"); collectgarbage("stop")
    local startKB = collectgarbage("count")
    for _ = 1, 10000 do observedGoto() end
    local deltaKB = collectgarbage("count") - startKB
    collectgarbage("restart")
    expect(deltaKB < 2 and API.counters.received == received,
        "Unchanged cursor observations allocate or schedule work: " .. deltaKB .. " KB")
    print(root .. " AWP-only 10,000 stable observations: " .. deltaKB .. " KB temporary allocation")
    distances[step.elements[1].wx], distances[step.elements[2].wx], distances[step.elements[3].wx] = 25, 0, 30
    tick(); tick()
    expect(provider.extractTarget().rxpWaypoint == 3 and routed == routeCount + 1, "Arrival did not advance exactly once")
    distances[step.elements[2].wx], distances[step.elements[3].wx] = 30, 0
    tick(); tick()
    expect(provider.extractTarget().rxpWaypoint == 1 and routed == routeCount + 2, "Finished cycle did not return to its first point")
    distances[step.elements[1].wx], distances[step.elements[3].wx] = 0, 30
    tick(); tick()
    expect(provider.extractTarget().rxpWaypoint == 2, "A second cycle did not progress")

    -- Unknown/secret HBD values must neither advance nor compare arithmetic.
    local held = provider.extractTarget()
    located = false; tick(); expect(provider.extractTarget() == held, "Missing position advanced a loop")
    located = true; secretDistance = "secret distance"
    -- Only call the AWP observer: the native routine cannot handle secret distances.
    observedGoto(); fixture.drain()
    expect(provider.extractTarget() == held, "Secret distance changed navigation")
    secretDistance = nil
    for _, point in ipairs(step.elements) do if point.wx then distances[point.wx] = 0 end end
    observedGoto(); fixture.drain(); observedGoto(); fixture.drain()
    held, routeCount, received = provider.extractTarget(), routed, API.counters.received
    for _ = 1, 100 do observedGoto(); fixture.drain() end
    expect(provider.extractTarget() == held and routed == routeCount and API.counters.received == received,
        "Coincident arrival circles spun the cursor at rest")

    step.elements[4].completed = true
    fixture.messages.RXP_OBJECTIVE_COMPLETE(); fixture.drain()
    expect(provider.extractTarget() == nil, "Completed owning objective retained a loop target")
    setup(true); observing = true; tick()
    distances[step.elements[1].wx], distances[step.elements[2].wx], distances[step.elements[3].wx] = 25, 0, 30
    tick(); tick()
    expect(provider.extractTarget().rxpWaypoint == 3, "Objective reset fixture did not advance")
    step.elements[4].obj = 3
    observedGoto(); fixture.drain()
    expect(provider.extractTarget().rxpWaypoint == 1, "Changed objective retained a previous objective's cursor")
    setup(true); observing = true; tick()
    rxp.GetGuideProgress = function() return 2 end
    observedGoto(); fixture.drain()
    expect(API.GetSnapshot().current == 2, "Changed guide progress did not invalidate the cursor scope")
    setup(true); observing = true; tick()
    step.active = false
    observedGoto(); fixture.drain()
    expect(provider.extractTarget() == nil, "Inactive step retained its cursor")

    setup(false); observing = true; tick(); tick()
    expect(API.GetSnapshot().navigationReason == "waypoint" and af:IsShown(), "Enabled native arrow stopped owning progression")
    setup(true); observing = true; tick()
    step.elements[2].activationRadius = 20
    observedGoto(); fixture.drain()
    expect(API.GetSnapshot().navigationReason == "waypoint", "A conditional/mixed loop was partially taken over")
    for _, field in ipairs({ "dynamic", "persistent", "generated", "currentObjective" }) do
        setup(true); observing = true; tick()
        step.elements[2][field] = 1
        observedGoto(); fixture.drain()
        expect(API.GetSnapshot().navigationReason == "waypoint", field .. " loop bypassed native progression")
    end
    setup(true); observing = true; tick()
    step.elements[2].tag = "loop"
    observedGoto(); fixture.drain()
    expect(API.GetSnapshot().navigationReason == "waypoint", ".loop element was treated as a #loop goto sequence")

    setup(true); observing = true; tick()
    rxp.settings.profile.showEnabled = false
    observedGoto(); fixture.drain()
    expect(provider.extractTarget() == nil and API.GetSnapshot().state == "paused", "Pause retained live loop navigation")
    rxp.settings.profile.showEnabled = true
    fixture.messages.RXP_GUIDE_LOADED(); fixture.drain()
    expect(provider.extractTarget() and API.GetSnapshot().navigationReason == "loop_cursor", "Reload did not rebuild a scoped cursor")
    rxp.settings.profile.disableArrow = false
    nativeArrow(); observedGoto(); fixture.drain()
    expect(API.GetSnapshot().navigationReason == "waypoint" and af:IsShown(), "Arrow setting change did not restore native progression")

    setup(true); observing = true; tick()
    local originalRoutingEnabled = NS.IsRoutingEnabled
    NS.IsRoutingEnabled = function() return false end
    observedGoto(); fixture.drain()
    expect(API.GetSnapshot().navigationReason == "waypoint", "Disabled routing retained cursor ownership")
    NS.IsRoutingEnabled = originalRoutingEnabled

    -- A one-point loop must stay stable until the player leaves and returns.
    setup(true); observing = true
    step.elements = { step.elements[1], step.elements[4] }
    af.element, rxp.activeWaypoints = step.elements[1], { step.elements[1] }
    API.Schedule("one_point_loop"); fixture.drain(); observedGoto(); fixture.drain()
    held, routeCount, received = provider.extractTarget(), routed, API.counters.received
    for _ = 1, 100 do observedGoto(); fixture.drain() end
    expect(held and provider.extractTarget() == held and routed == routeCount and API.counters.received == received,
        "Single-point loop spun or manufactured repeated routing")
    print(root .. " AWP loop cursor: stable ticks, ordered arrivals, cycles, ownership, native preference and fallbacks passed")
end

_G.LibStub = originalLibStub
print("RXP authored #loop regression fixtures passed for both installed clients")

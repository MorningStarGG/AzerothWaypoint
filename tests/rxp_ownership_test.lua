local NativePath = dofile("tests/native_path.lua")
-- Reproduce the installed guide/parser shapes, then exercise the complete
-- RXP extraction -> shared presentation -> queue projection path.
local fixture = assert(loadfile("tests/rxp_integration_test.lua"))()
local NS = AzerothWaypointNS
local P, API = NS.Internal.RXPPresentation, NS.Internal.RXPProvider
local rxp, adapter = fixture.runtime, fixture.provider
local function expect(value, message) if not value then error(message, 2) end end
local mapNames = { [2405] = "Voidstorm", [2395] = "Eversong Woods" }
local maps = assert(rawget(_G, "C_Map"), "RXP source fixture did not install C_Map")
maps.GetMapInfo = function(id) return { name = mapNames[id] or "Unknown map" } end

local function Read(path)
    local file = assert(io.open(path, "rb"), path)
    local source = file:read("*a"); file:close()
    return (source:gsub("\r\n", "\n"))
end

local function NativeConstructors(root)
    local source = Read(root .. "functions.lua")
    local gotoSource = assert(source:match('(addon%.functions%["goto"%] = function%(self, %.%.%.%).-\nend)'))
    local scenarioSource = assert(source:match('(function addon%.functions%.enterScenario%(self, text, %.%.%.%).-\nend)'))
    local native = { functions = {}, mapConversion = {}, locale = {}, icons = { ["goto"] = "" },
        GetMapInfo = function(zone, x, y) return tonumber(zone), tonumber(x), tonumber(y) end }
    local hbd = { GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end }
    local prefix = "local addon, HBD, L = ...; local fmt, lastZone = string.format, nil;\n"
    assert(loadstring(prefix .. gotoSource .. "\n" .. scenarioSource))(native, hbd, function(text) return text end)
    return native.functions
end

local function GuideBlocks(source, instruction)
    local blocks, offset = {}, 1
    while true do
        local at = source:find(instruction, offset, true)
        if not at then break end
        local start = assert(source:sub(1, at):match(".*\nstep\n()"))
        blocks[#blocks + 1] = source:sub(start, at + #instruction - 1)
        offset = at + #instruction
    end
    expect(#blocks > 0, "Installed guide instruction was not found")
    return blocks
end

local function ParseBlock(native, source)
    local step = { index = 1, stepId = 1001, active = true, elements = {} }
    local lastObjective
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        local tag, args = line:match("^%.(%S+)%s*(.*)")
        if tag then
            local authored
            args = args:gsub("%s*>>%s*(.*)", function(text) authored = text; return "" end)
            local values = {}; for value in args:gmatch("[^,]+") do values[#values + 1] = value end
            local element = native[tag] and native[tag]("guide fixture", authored, unpack(values)) or {}
            element.tag, element.step = tag, step
            -- This is GuideLoader.ParseLine's parent linkage, rather than
            -- setting every goto's parent to the following action in fixtures.
            if element.parent then element.parent = lastObjective end
            if element.text and not element.textOnly or element.dynamicText then lastObjective = element end
            step.elements[#step.elements + 1] = element
        end
    end
    return step
end

assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp", adapter)
NS.RegisterGuideTargetProvider("zygor", { isLoaded = function() return true end })
NS.IsInstanceRouteTravelType = function() return false end
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/presentation.lua"))()
NS.GetDB().worldOverlayShowCoordinateFallback = false
NS.RouteQueueInternal = { TrimString = function(value) return type(value) == "string" and value ~= "" and value or nil end,
    GetWaypointSig = function() return "fixture" end }
assert(loadfile("bridge/routing/queues/projection.lua"))()
NS.SyncGuideQueueProjection = function() end

local function Publish(step, selected)
    rxp.currentGuide.steps = { step }
    rxp.RXPFrame.activeSteps = { step }
    rxp.activeWaypoints = { selected }; rxp.arrowFrame.element = selected
    P.Invalidate()
    API.Schedule("ownership_fixture"); fixture.drain()
    return adapter.extractTarget(), API.GetSnapshot().steps[1]
end

local function CheckOutput(target, expected)
    NS.State.routing = { activeGuideProvider = "zygor", guideRouteStates = {} }
    NS.UpdateGuideTarget("rxp", target, false)
    NS.State.routing.activeGuideProvider = "rxp"
    local record = assert(NS.GetActiveGuideRouteState())
    NS.State.routing.carrierState = { source = "guide", kind = "guide", routeLegKind = "destination",
        title = target.title, sig = "ownership", finalMapID = target.mapID, finalX = target.x, finalY = target.y }
    local result = NS.ResolvePresentation()
    expect(result.carrierTitle == expected and result.overlayTitle == expected and result.pinpointSubtext == nil,
        "Final arrow/plaque/overlay did not follow the owning instruction")
    local queue = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
    expect(queue.mirrorTitle == expected and queue.pinpointSubtext == nil, "Queue diverged from the final instruction")
    local carrier = NS.State.routing.carrierState
    carrier.kind, carrier.routeLegKind, carrier.routeTravelType, carrier.title = "route", "carrier", "travel", "Take the boat"
    result = NS.ResolvePresentation()
    expect(result.overlayTitle == "Take the boat" and result.pinpointSubtext == nil, "Backend leg lost its own travel instruction")
end

local instructions = {
    { text = "Enter the Sunkiller Sanctum Delve in Void Storm.", expected = "Enter the Sunkiller Sanctum Delve in Void Storm.", map = 2405 },
    { text = "Enter the Shadow Enclave Delve in Eversong Woods.", expected = "Enter the Shadow Enclave Delve", map = 2395 },
}
-- The reports are Retail guide content; run those exact blocks through both
-- installed parser implementations without requiring identical guide packs.
local reportedGuides = Read(NativePath("retail", "RXPGuides/Guides/Retail/Endgame/Midnight/Storylines.lua"))
for _, root in ipairs({ NativePath("retail", "RXPGuides/"), NativePath("forever", "RXPGuides/") }) do
    local native = NativeConstructors(root)
    local guides = reportedGuides
    for _, case in ipairs(instructions) do
        for _, block in ipairs(GuideBlocks(guides, case.text)) do
            local step = ParseBlock(native, block)
            local owner = #step.elements
            local selected = step.elements[owner - 1]
            expect(selected.tag == "goto" and step.elements[owner].tag == "enterScenario", "Native guide fixture shape changed")
            local target, snapshot = Publish(step, selected)
            expect(target and target.title == case.expected and target.subtext == nil, "Reported plaque title/context is still wrong")
            expect(target.rxpElement == owner and target.rxpWaypoint == owner - 1
                and target.rxpElementTag == "enterScenario" and target.rxpOwnerReason == "following_objective",
                "Bare coordinate node still owns the interaction presentation")
            expect(target.mapID == case.map and target.x == selected.x / 100 and target.y == selected.y / 100,
                "Presentation ownership moved RXP's selected destination")
            expect(#snapshot.rows == 1 and snapshot.rows[1].text == target.title and snapshot.rows[1].fullHeight,
                "Viewer duplicates or disagrees with the plaque instruction")
            CheckOutput(target, case.expected)
            local generated = { source = selected, anchor = selected, generated = 3, step = step,
                zone = selected.zone, x = selected.x + 0.1, y = selected.y + 0.1 }
            target = Publish(step, generated)
            expect(target.rxpElement == owner and target.x == generated.x / 100 and target.y == generated.y / 100,
                "Generated line/loop point lost the instruction or replaced its selected coordinates")
            if step.elements[owner - 2] and step.elements[owner - 2].tag == "goto" then
                -- The first authored approach point must retain its own coordinates
                -- while sharing the entry action with the consecutive final goto.
                local first = step.elements[owner - 2]
                target = Publish(step, first)
                expect(target.x == first.x / 100 and target.y == first.y / 100 and target.rxpElement == owner,
                    "A consecutive goto was discarded or stole unrelated text")
            end
        end
    end
end

local function Step(elements)
    local step = { index = 1, stepId = 2001, active = true, elements = elements }
    for _, element in ipairs(elements) do element.step = step end
    return step
end
for _, tag in ipairs({ "zone", "vehicle", "exitvehicle", "leaveScenario" }) do
    local step = Step({ { tag = "goto", zone = 2405, x = 10, y = 20, arrow = true, textOnly = true },
        { tag = tag, text = "Use the console (upper floor); wait for the signal." } })
    local target, snapshot = Publish(step, step.elements[1])
    expect(target.rxpElement == 2 and target.title == snapshot.rows[1].text and target.title:find("upper floor", 1, true),
        "Travel-colored interaction or meaningful procedure was lost: " .. tag)
end
local step = Step({ { tag = "goto", zone = 2405, x = 10, y = 20, arrow = true },
    { tag = "complete", questId = 9, obj = 1 },
    { tag = "goto", zone = 2405, x = 30, y = 40, arrow = true },
    { tag = "enterScenario", text = "Enter a different scenario" } })
local target = Publish(step, step.elements[1])
expect(target.rxpElement == 2 and target.semanticQuestID == 9, "Later waypoint group stole the first objective")
step.elements[1].parent = step.elements[4]
target = Publish(step, step.elements[1])
expect(target.rxpElement == 4, "Explicit native parent did not take precedence")
step = Step({ { tag = "goto", zone = 2405, x = 10, y = 20, arrow = true },
    { tag = "goto", zone = 2405, x = 30, y = 40, arrow = true, text = "Board the ship" },
    { tag = "accept", questId = 9 } })
target = Publish(step, step.elements[1])
expect(target.rxpElement == 1 and target.rxpTitleSource == "map_name_fallback", "Named later waypoint leaked into an earlier group")
step.elements = { step.elements[1] }
target = Publish(step, step.elements[1])
expect(target.rxpTitleSource == "map_name_fallback" and target.rxpTitleSource ~= "authored_text", "Fallback provenance is still misleading")
step.arrowtext = "Use the authored arrow instruction"
target = Publish(step, step.elements[1])
expect(target.title == step.arrowtext and target.rxpTitleSource == "step_arrowtext", "Explicit arrow text lost its authority/provenance")

-- Localized generated coordinate text is structural; authored non-English
-- instructions remain authoritative without an ASCII-letter heuristic.
local oldLocale = rxp.locale
rxp.locale = { Get = function(text) return text == "Go to" and "Aller Ã " or text end }
step = Step({ { tag = "goto", zone = 2405, x = 10, y = 20, arrow = true, text = "Aller Ã  10.0,20.0 (2405)" },
    { tag = "enterScenario", text = "Entrer dans le sanctuaire" } })
target = Publish(step, step.elements[1])
expect(target.rxpElement == 2 and target.title == "Entrer dans le sanctuaire", "Localized coordinate text hid the meaningful instruction")
step.elements[1].text = "è¿›å…¥æ´žç©´"
target = Publish(step, step.elements[1])
expect(target.rxpElement == 1 and target.title == "è¿›å…¥æ´žç©´", "Authored non-ASCII waypoint instructions lost ownership")
rxp.locale = oldLocale

-- Reusing a cached step must not repeat common travel-classification work.
local classifier, classifications = NS.ClassifyTravelSemantics, 0
NS.ClassifyTravelSemantics = function(action)
    classifications = classifications + 1
    return action == "fly" and "taxi" or action == "home" and "inn" or nil
end
step = Step({ { tag = "goto", zone = 2405, x = 10, y = 20, arrow = true },
    { tag = "fly", text = "Fly to the destination" } })
target = Publish(step, step.elements[1])
expect(target.semanticTravelType == "taxi", "RXP bypassed the shared travel semantics")
local before, snapshot = classifications, API.GetSnapshot()
local built = API.counters.built
for _ = 1, 50 do API.Schedule("unchanged_ownership") end
fixture.drain()
expect(classifications == before and API.counters.built == built and API.GetSnapshot() == snapshot,
    "Unchanged ownership bursts rebuilt snapshots or repeated travel classification")
NS.ClassifyTravelSemantics = classifier
print("RXP installed Retail/Forever waypoint/interaction ownership, reported plaques, Viewer rows and full output path passed")

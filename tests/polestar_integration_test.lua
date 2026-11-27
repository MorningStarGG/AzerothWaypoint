local replaceMethod = dofile("tests/replace_method.lua")
local function check(v, message) assert(v, message) end
local pending, listeners, providers, frames, timers = {}, {}, {}, {}, {}
local combat, enabled, selected = false, true, "dugi"
local current, time = 1, 100
local guide = { id = "forever/fixture", title = "Fixture guide" }
local goals = {
    { index = 1, t = "accept", text = "Accept 'The Journal'", verb = "Accept", subject = "'The Journal'",
        quest = 9, status = "active", npcName = "Leona", tickable = true, map = 1, x = 0, y = 0.5 },
    { index = 2, t = "collect", text = "Collect [Journal]", note = "Collect [Journal] in The Ridge",
        status = "active", item = 10, map = 1, x = 20, y = 30 },
}
local wp = { stepIndex = 1, goalIndex = 1, map = 1, x = 0, y = 0.5 }
local settings = { ["nav.travel"] = true, ["nav.navRouting"] = true, ["nav.teleports"] = true,
    ["nav.tomtom"] = true, ["nav.routeStyle"] = "roads" }
_G.GetTime = function() return time end
_G.InCombatLockdown = function() return combat end
_G.UnitLevel = function() return 10 end
_G.UnitIsGhost = function() return false end
_G.IsIndoors = function() return false end
_G.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
_G.C_Timer.NewTimer = function(delay, fn)
    local timer = { at = GetTime() + delay, fn = fn }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
_G.CreateFrame = function()
    local f = { scripts = {}, RegisterEvent = function() end,
        SetScript = function(self, key, fn) self.scripts[key] = fn; if key == "OnEvent" then self.event = fn end end,
        Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end }
    frames[#frames + 1] = f; return f
end
_G.hooksecurefunc = function(o, name, fn)
    local original = o[name]
    o[name] = function(...) local a = original(...); fn(...); return a end
end
_G.AzerothWaypointNS = { Internal = {}, State = { routing = {} } }
local NS = AzerothWaypointNS
NS.IsWoWForever = function() return true end
NS.RegisterExternalWaypointSource = function() end
NS.RegisterGuideTargetProvider = function(key, provider) providers[key] = provider end
NS.IsRoutingEnabled = function() return enabled end
local selections = 0
NS.SelectGuideProvider = function(key) selected = key; selections = selections + 1 end
NS.RequestManualRoute = function(map, x, y, title, metadata)
    NS.manual = { map = map, x = x, y = y, title = title, metadata = metadata }; return true
end
NS.RecomputeCarrier = function() end
NS.GetPlayerMapID = function() return 1 end
NS.GetActiveAuthorityRecord = function() return NS.record end
local combatCooldownReads = 0
_G.C_Item = { GetItemCooldown = function()
    if combat then combatCooldownReads = combatCooldownReads + 1 end
    return 0, 0
end }
_G.Polestar = {
    On = function(event, fn)
        local previous = listeners[event]
        listeners[event] = previous and function(...) previous(...); fn(...) end or fn
    end, Off = function() end,
    Get = function(path) return settings[path] end,
    Engine = {
        GetGuide = function() return guide end, GetStepIndex = function() return current end,
        GetStepView = function(i) return { index = i, goals = goals, groups = { { kind = "here", name = "The Ridge" } } } end,
        GetWaypoint = function() return wp end, GetTabs = function() return { { guideId = guide.id, title = guide.title } }, 1 end,
        StepNumber = function(i) return i end, StepTotal = function() return 20 end, GetProgress = function() return 2, 20 end,
        GetAlong = function() return {} end,
        Prev = function() current = current - 1; listeners.STEP_CHANGED() end,
        Next = function() current = current + 1; listeners.STEP_CHANGED() end,
        Skip = function() current = current + 1 end, AimGoal = function() end, ToggleGoal = function() end,
    },
    UI = { PlainGoalText = function(g) return g.text end, Picker = {}, GuideFrame = {} },
    Nav = { walk = { Floor = function() return nil end, Floors = function() return nil end }, GetTravelData = function() return { build = 1, taxi = {}, inns = {}, transports = {}, portals = {} } end,
        GetKnownTaxiNodes = function() return { [123] = true } end,
        GetTaxiSeen = function() return {} end, TaxiMaybe = function() return false end,
        LiveCoords = function(p) return p.map, p.x, p.y end,
    },
    Transit = { Teleports = function() return {} end },
    Compat = {
        GetPlayerWorldPosition = function() return 1, 0, 0 end,
        MapToWorld = function(map, x, y) return map, x * 10, y * 10 end,
        WorldToMap = function(_, x, y) return x / 10, y / 10 end,
        GetPlayerFaction = function() return "Alliance" end, GetItemCount = function() return 1 end,
        QuestTimerRunning = function() return false end,
    },
}
local r = Polestar
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
assert(loadfile("integrations/guides/polestar/polestar_presentation.lua"))()
local P = NS.Internal.PolestarPresentation
local shared = NS.Internal.GuidePresentation
check(not shared.LocationOnly("Talk to Grull Hawkwind", false), "Absent location treated as text")
check(shared.TrimLocationSuffix("Talk to Grull Hawkwind", false) == "Talk to Grull Hawkwind", "Absent location changed instruction")
local npcFact = P.Resolve(r, { t = "accept", text = "Accept 'A Task'", npcName = "Grull Hawkwind" }, { kind = "npc", name = "Grull Hawkwind" })
check(npcFact.context == "Talk to Grull Hawkwind", "NPC group without a location failed")
local placeStep = P.BuildStep(r, { index = 1, title = "The Ridge", goals = {
    { index = 1, t = "goto", header = true, text = "Travel to The Ridge", status = "active" },
} }, false)
check(#placeStep.rows == 1 and placeStep.rows[1].text == "Travel to The Ridge", "Native place heading left an empty AWP step")
goals[2].group = 1
local fact = P.Resolve(r, goals[2], { kind = "here", name = "The Ridge" })
check(fact.title == "Collect [Journal]" and not fact.context, "Location repetition retained")
goals[2].note = "Kill enemies to collect [Journal] (keep five for later)."
fact = P.Resolve(r, goals[2])
check(fact.context:find("keep five", 1, true), "Meaningful instruction lost")
for _, action in ipairs({ "accept", "turnin", "complete", "collect", "kill", "interact", "use", "cast",
    "goto", "explore", "fly", "boat", "hearth", "sethome", "train", "craft", "buy", "die", "task", "note", "level", "money", "wait" }) do
    check(P.Resolve(r, { t = action, text = "Fixture" }), "Missing action " .. action)
end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/service_search.lua"))()
assert(loadfile("integrations/guides/polestar/polestar_provider.lua"))()
local API = NS.Internal.PolestarProvider
local routeOptions
providers.polestar.installHooks(function(_, opts) routeOptions = opts end)
local function drain()
    for i = #timers, 1, -1 do
        local timer = timers[i]
        if timer.at <= GetTime() then
            table.remove(timers, i)
            if not timer.cancelled then pending[#pending + 1] = timer.fn end
        end
    end
    local count = 0
    while #pending > 0 do
        count = count + 1; assert(count < 20, "Event loop")
        local p = pending; pending = {}
        for _, fn in ipairs(p) do fn() end
    end
end
drain()
local target = providers.polestar.extractTarget()
check(target.x == 0 and target.y == 0.005, "Zero/sub-one-percent coordinates changed")
check(target.title == "Accept 'The Journal'" and target.subtext == "Talk to Leona", "Quest/context ownership lost")
check(selected == "dugi", "Passive load stole authority")
goals[1].status = "done"
API.Schedule("STEP_UPDATED"); drain()
check(providers.polestar.extractTarget() == nil, "Completed native owner retained navigation")
goals[1].status = "active"
API.Schedule("STEP_UPDATED"); drain()
API.Activate(); drain(); check(selected == "polestar", "Make Active failed")
check(API.RoutePoint({ map = 1, x = 0, y = .5 }, "Mailbox", "mailbox"), "Nearest-service route failed")
check(NS.manual.x == 0 and NS.manual.y == .005 and NS.manual.metadata.searchKind == "npc_mailbox", "Nearest service lost coordinates or semantic metadata")
local searchCalls, skill = 0, nil
r.Compat.SKILL_LINES = {alchemy = 171}
r.Nav.nearby = {KINDS = {{key = "trainer"}, {key = "repair"}}, Find = function(key, line)
    searchCalls, skill = searchCalls + 1, line
    return {map = 1, x = 20, y = 30, name = key, z = 9}
end}
check(NS.Internal.ServiceSearch.Request({service = "trainer", profession = "alchemy", label = "Alchemy Trainer"}, "polestar")
    and skill == 171 and NS.manual.title == "trainer", "Polestar lookup lost the requested profession")
local saved = NS.manual
check(not NS.Internal.ServiceSearch.Request({service = "trainer", profession = "engineering", label = "Engineering Trainer"}, "polestar")
    and NS.manual == saved and searchCalls == 1, "Unknown profession was broadened to a generic trainer")
check(not NS.Internal.ServiceSearch.Request({service = "workshop", label = "Workshop"}, "polestar")
    and searchCalls == 1, "Unsupported workshop ran another search")
check(API.FindNearest("repair", nil, "Repair") and NS.manual.title == "repair", "Native menu search changed provider")
check(r.Get("nav.tomtom") == false and settings["nav.tomtom"], "Runtime override wrote saved preferences")
enabled = false; check(r.Get("nav.tomtom") == true, "Native output not restored")
enabled = true
local function preview(move, expected)
    local before = selections
    routeOptions = nil
    move()
    drain()
    check(current == expected and API.GetSnapshot().rawCurrent == expected, "Step preview did not refresh the Viewer")
    check(selections == before and routeOptions and routeOptions.presentationRefresh and not routeOptions.explicit
        and not routeOptions.allowProviderSwitch, "Step preview requested navigation ownership")
end
preview(r.Engine.Next, 2)
preview(r.Engine.Prev, 1)
preview(function() API.Action("next", guide.id, 1) end, 2)
preview(function() API.Action("previous", guide.id, 2) end, 1)
preview(r.Engine.Next, 2)
check(not API.Action("skip", guide.id, 1), "Stale checkbox affected a different step")
preview(r.Engine.Prev, 1)
local beforeRoute = selections
check(API.Action("route", guide.id, 1, 1), "Could not route the selected goal")
drain()
check(selections > beforeRoute and routeOptions.explicit, "Explicit goal routing lost navigation ownership")
local old = API.GetSnapshot()
for i = 1, 20 do API.Schedule("STEP_UPDATED") end
drain(); check(API.GetSnapshot() == old, "Unchanged snapshot replaced")
local callbacks, planCount = {}, 0
r.Nav.PlanRoute = function(context)
    planCount = planCount + 1
    local a = { map = 1, c = 1, wx = 0, wy = 0 }
    local b = { map = 1, c = 1, wx = 500, wy = 500 }
    context.places[1] = { wx = 0, wy = 0, start = true }
    context.places[2] = { wx = 500, wy = 500 }
    local route = { { kind = "walk", from = a, to = b, label = "Approach" },
        { kind = "fly", from = b, to = context.target, stops = { { id = 123 } }, label = "Fly" } }
    if combat then
        check(not context.hearth and not context.teleports, "Combat context offered portable actions")
    else
        route[#route + 1] = { kind = "teleport", from = b, to = context.target, spell = 99, label = "Teleport" }
    end
    return route
end
_G.Polestar_NavEngine = { Find = function(_, _, _, cb, opts)
    check(opts.style == "roads", "Native route style ignored"); callbacks[#callbacks + 1] = cb; return {}
end, Cancel = function() end }
NS.AcceptBackendPlan = function(record, id, legs)
    record.backend, record.legs, record.currentLeg, record.currentLegIndex = id, legs, legs[1], 1
    record._routeAcceptedPlanGeneration = (record._routeAcceptedPlanGeneration or 0) + 1
    return true
end
NS.ReplaceActiveRouteLegs = function(record, leg, generation, replacements, lastLeg)
    if record ~= NS.record or record.currentLeg ~= leg or record._routeAcceptedPlanGeneration ~= generation then return false end
    local index = record.currentLegIndex
    local last = index
    if lastLeg then while record.legs[last] and record.legs[last] ~= lastLeg do last = last + 1 end end
    if not record.legs[last] then return false end
    local legs = {}
    for i = 1, index - 1 do legs[#legs + 1] = record.legs[i] end
    for _, replacement in ipairs(replacements) do legs[#legs + 1] = replacement end
    for i = last + 1, #record.legs do legs[#legs + 1] = record.legs[i] end
    record.legs, record.currentLeg = legs, legs[index]
    record._routeAcceptedPlanGeneration = generation + 1
    return true
end
NS.RetainBackendPlan = function(record, _, reason) record.lastPlanSkipStatus = reason; return true end
NS.RegisterRouteBackendStateValidator = function(_, validator) NS.validator = validator end
NS.RequestRouteBackendStateValidation = function(_, _, class) NS.requestClass = class end
NS.CancelRouteBackendStateValidations = function() end
assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("tests/route_cleanup_fixture.lua"))()
AzerothWaypointNS.Internal = AzerothWaypointNS.Internal or {}
assert(loadfile("bridge/routing/walking.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
r.Nav.travel = { PortalItems = function() return nil end }
assert(loadfile("bridge/routing/backends/polestar.lua"))()
local plannerFixture = assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(NS.RoutingBackend_Polestar)
local b = NS.RoutingBackend_Polestar
b.Initialize()
NS.record = {}
b.PlanRoute(NS.record, 1, 0.7, 0.8, "Final")
check(NS.record.legs[#NS.record.legs].x == 0.7, "Exact destination not preserved")
check(NS.record.legs[2].taxi.nodeID == 123, "Numeric flight metadata missing")
check(NS.record.legs[3].specialAction.routeDependency.id == 99, "Spell dependency missing")
check(b.PollNavigationLeg(NS.record) == false and #callbacks == 1, "Walk request missing")
callbacks[1]({ { x = 0, y = 0 }, { x = 500, y = 500 } })
check(NS.record.currentLeg.polestarPath ~= nil, "Path did not become fixed walking legs")
check(b.CanAdvanceLeg(NS.record, NS.record.currentLeg) == false, "Premature walking arrival")
local accept = NS.AcceptBackendPlan
replaceMethod(NS, "AcceptBackendPlan", function(record)
    record.lastPlanSkipStatus = "equivalent"; return true
end)
local requested = #callbacks
b.PlanRoute(NS.record, 1, .7, .8, "Final")
b.PollNavigationLeg(NS.record)
check(NS.record.currentLeg.polestarPath and #callbacks == requested, "Equivalent plan discarded the accepted walking path")
NS.AcceptBackendPlan = accept
NS.record.lastPlanSkipStatus = nil
b.OnPlanInvalidated("SPELL_UPDATE_COOLDOWN"); check(NS.requestClass == "cooldown", "Wrong validation priority")
local count = planCount
combat = true
b.PlanRoute(NS.record, 1, 0.7, 0.8, "Final")
b.PlanRoute(NS.record, 1, 0.7, 0.8, "Final")
check(planCount == count + 2 and NS.record.legs[2].taxi.nodeID == 123 and
    NS.record._routeBackendStateFingerprint == NS.RouteSpecials.COMBAT_TRAVEL_STATE, "Combat flight itinerary missing")
check(NS.validator() == false, "Snapshot ran in combat")
check(combatCooldownReads == 0, "Combat planning read the hearthstone cooldown")
local fullPlanner = replaceMethod(r.Nav, "PlanRoute", function() return nil end)
b.PlanRoute(NS.record, 1, .7, .8, "No eligible itinerary")
check(NS.record._fixtureResult.status == "deferred" and NS.record._fixtureResult.reason == "combat",
    "Missing combat itinerary was discarded")
replaceMethod(r.Nav, "PlanRoute", function() error("fixture failure") end)
b.PlanRoute(NS.record, 1, .7, .8, "Broken planner")
check(NS.record._fixtureResult.status == "failed", "Planner error waited for combat")
r.Nav.PlanRoute = fullPlanner
combat = false
b.frame.event(nil, "PLAYER_REGEN_ENABLED"); b.PlanRoute(NS.record, 1, .7, .8, "Final"); drain()
check(planCount == count + 3 and NS.record.legs[3].specialAction, "Post-combat search did not restore portable actions")
local valid, fingerprint = NS.validator()
check(valid and type(fingerprint) == "string", "Snapshot failed")
check(select(2, NS.validator()) == fingerprint, "Snapshot nondeterministic")
local secret = {}
_G.issecretvalue = function(value) return value == secret end
r.Transit.Teleports = function() return { { spell = 99, ready = 0 } } end
_G.C_Spell = { GetSpellCooldown = function() return { startTime = secret, duration = 1 } end }
check(NS.validator() == false, "Secret cooldown accepted as ready after a native substitute")
_G.C_Spell = nil
_G.issecretvalue = nil
local before = NS.record._routeAcceptedPlanGeneration
b.PollNavigationLeg(NS.record)
local late = callbacks[#callbacks]
b.Clear(NS.record)
late({ { x = 0, y = 0 }, { x = 50, y = 50 } })
check(not NS.record.legs and b.counters.stale > 0, "Late path callback resurrected a cleared route")
check(NS.record._routeAcceptedPlanGeneration == before, "Clear or stale callback accepted a new plan")
local from = { map = 1, c = 1, wx = 0, wy = 0 }
local to = { map = 2, c = 2, wx = 500, wy = 500, z = 100 }
for _, kind in ipairs({ "walk", "fly", "boat", "zeppelin", "tram", "portal", "hearth", "teleport", "lift" }) do
    replaceMethod(r.Nav, "PlanRoute", function()
        return { { kind = kind, from = from, to = to, item = kind == "hearth" and 6948 or nil,
            spell = kind == "teleport" and 99 or nil, label = "Native " .. kind, stops = { { id = 123 } } } }
    end)
    b.PlanRoute(NS.record, 1, .7, .8, "Final")
    local leg = NS.record.legs[1]
    check(#NS.record.legs == 2 and leg.polestarKind == kind and leg.polestarTo.z == 100, "Failed typed translation: " .. kind)
    if kind == "hearth" then check(leg.specialAction.securePayload == "item:6948", "Hearth item payload changed") end
    if kind == "portal" then check(leg.x == 0 and leg.y == 0, "Portal pointed at arrival instead of entrance") end
end
local previousLegs = NS.record.legs
replaceMethod(r.Nav, "PlanRoute", function() return { false } end)
b.PlanRoute(NS.record, 1, .7, .8, "Final")
check(NS.record._fixtureResult.status == "failed" and NS.record.legs == previousLegs, "Malformed foreign plan replaced accepted guidance")
replaceMethod(r.Nav, "PlanRoute", function() return { { kind = "walk", from = from, to = { map = 1, c = 1, wx = 500, wy = 0 } } } end)
Polestar_NavEngine.Find = function(_, from, to, callback)
    callback({ { x = from.x, y = from.y }, { x = to.x, y = to.y } }); return {}
end
r.Compat.GetPlayerWorldPosition = function() return 1, 500, 0 end
b.PlanRoute(NS.record, 1, .7, .8, "Final")
b.PollNavigationLeg(NS.record)
check(NS.record.currentLeg.polestarPath, "Immediate path completion was lost")
check(b.CanAdvanceLeg(NS.record, NS.record.currentLeg) ~= false, "Completed search retained a phantom pending job")
print("Polestar provider, presentation, backend and walking fixtures passed")
return { runtime = r, provider = providers.polestar, backend = b, settings = settings, drain = drain,
    fire = function(event, ...) if listeners[event] then return listeners[event](...) end end }

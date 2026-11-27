-- Lua 5.1: exercise fresh sessions, not just Make Active within one session.
local function expect(value, message) if not value then error(message, 2) end end
local function session(saved, source)
    local pending, adapters, routes = {}, {}, {}
    local db = { activeGuideProvider = saved, activeRouteSource = source or "guide" }
    local NS = { State = { routing = {} }, Internal = {},
        GetDB = function() return db end,
        After = function(_, callback) pending[#pending + 1] = callback end,
        GetSavedActiveRouteSource = function() return db.activeRouteSource end,
        SetActiveRouteSource = function(value) db.activeRouteSource = value end,
        RouteViaBackend = function(_, _, _, _, _, opts) routes[#routes + 1] = opts.guideProvider; return true end,
    }
    _G.AzerothWaypointNS = NS
    _G.C_Timer = { After = NS.After }
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
    for _, key in ipairs({"zygor", "dugi", "rxp", "polestar"}) do
        local entry = { loaded = true, present = true, target = {mapID=1,x=.1,y=.2} }
        adapters[key] = entry
        NS.RegisterGuideTargetProvider(key, {
            isLoaded = function() return entry.loaded end,
            hasGuide = function() return entry.present end,
            getVisibilityState = function() return entry.loaded and entry.present and "visible" or "absent" end,
            extractTarget = function() return entry.target, entry.target == nil end,
        })
    end
    local function flush()
        local count = 0
        while #pending > 0 do
            count = count + 1; expect(count < 100, "Fallback scheduling did not settle")
            table.remove(pending, 1)()
        end
    end
    return NS, db, adapters, routes, flush
end

for _, preferred in ipairs({"zygor", "dugi", "rxp", "polestar"}) do
    local NS, db, adapters, routes, flush = session(preferred)
    NS.StartGuideRoutingEvaluation(); flush()
    expect(NS.GetActiveGuideProvider() == preferred and #routes == 1 and routes[1] == preferred,
        "Startup order replaced " .. preferred)

    NS, db, adapters, routes, flush = session(preferred)
    adapters[preferred].loaded = false
    NS.StartGuideRoutingEvaluation(); flush()
    expect(NS.GetActiveGuideProvider() ~= preferred and #routes > 0 and db.activeGuideProvider == preferred,
        "Missing preferred provider erased the remembered choice or blocked fallback")
    adapters[preferred].loaded = true
    NS.StartGuideRoutingEvaluation(); flush()
    expect(NS.GetActiveGuideProvider() == preferred and routes[#routes] == preferred,
        "Late preferred engine did not reclaim navigation")

    NS, db, adapters, routes, flush = session(preferred)
    adapters[preferred].present = false
    NS.StartGuideRoutingEvaluation(); flush()
    expect(NS.GetActiveGuideProvider() ~= preferred and db.activeGuideProvider == preferred,
        "An empty guide prevented fallback or erased the preference")
    adapters[preferred].present = true; adapters[preferred].target = nil
    NS.ScheduleGuideProviderEvaluation(preferred, "guide_ready"); flush()
    expect(NS.GetActiveGuideProvider() == preferred and db.activeGuideProvider == preferred,
        "A valid coordinate-less/paused guide was not restored")
    local before = #routes
    NS.ScheduleGuideProviderEvaluation("zygor", "afk"); NS.ScheduleGuideProviderEvaluation("dugi", "afk"); flush()
    expect(NS.GetActiveGuideProvider() == preferred and #routes == before,
        "Coordinate-less restored provider lost authority to a passive update")

    NS, db, adapters, routes, flush = session(preferred, "manual")
    NS.State.routing.manualAuthority = {}
    NS.StartGuideRoutingEvaluation(); flush()
    expect(NS.GetActiveGuideProvider() == preferred and #routes == 0 and db.activeRouteSource == "manual",
        "Manual route prevented provider restoration or was replaced by it")
end

local NS, db, adapters, routes, flush = session("rxp")
adapters.rxp.loaded = false
NS.StartGuideRoutingEvaluation(); flush()
NS.SelectGuideProvider("dugi"); flush()
adapters.rxp.loaded = true
NS.StartGuideRoutingEvaluation(); flush()
expect(NS.GetActiveGuideProvider() == "dugi" and db.activeGuideProvider == "dugi",
    "Late initialization undid an explicit choice")
adapters.dugi.present = false
NS.ScheduleGuideProviderEvaluation("dugi", "guide_closed"); flush()
expect(NS.GetActiveGuideProvider() ~= "dugi" and db.activeGuideProvider == "dugi",
    "Closing the active guide did not use a temporary fallback")
NS, db, adapters, routes, flush = session(nil)
NS.StartGuideRoutingEvaluation(); flush()
expect(NS.GetActiveGuideProvider() == "zygor" and db.activeGuideProvider == "zygor",
    "First-run registration precedence changed")
NS, db, adapters, routes, flush = session("rxp")
adapters.rxp.present = false
NS.StartGuideRoutingEvaluation(); flush()
local target = adapters.rxp.target
local record = {guideProvider="rxp", target=target, authority="guide",
    legs={{routeLegKind="destination",mapID=1,x=.1,y=.2}}}
NS.State.routing.guideRouteStates.rxp = record
local republished = false
NS.RecomputeCarrier = function() republished = NS.GetActiveGuideRouteState() == record end
adapters.rxp.present = true
NS.ScheduleGuideProviderEvaluation("rxp", "ready_again"); flush()
expect(republished, "Restoration did not republish the unchanged accepted preferred route")
print("Guide startup restoration, late readiness, coordinate-less ownership and fallback fixtures passed")
return session

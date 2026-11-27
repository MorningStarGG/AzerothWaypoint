local fixture = dofile("tests/route_planning_fixture.lua")
for _, forever in ipairs({false, true}) do
    local f = fixture("direct", forever)
    local ns = f.NS
    ns.GetGuideTrackerViewerOrder = function() return {"dugi"} end
    assert(loadfile("core/service_search.lua"))()
    local search, callback, cancelled = ns.Internal.ServiceSearch, nil, 0
    search.Register("dugi", {label = "Dugi", Find = function(_, complete)
        callback = complete
        return "pending", function() cancelled = cancelled + 1 end
    end})
    local function begin()
        assert(search.Request({service = "repair", label = "Repair"}))
        return callback
    end
    local function late(done)
        done({mapID = 2, x = .2, y = .3, title = "Obsolete service", meta = {sourceAddon = "Dugi"}})
    end
    local done = begin()
    f.start(2, .5, .6, "New manual destination")
    assert(cancelled == 1, "Manual routing did not cancel the pending lookup")
    late(done)
    local record = ns.State.routing.pendingManualAuthority or ns.State.routing.manualAuthority
    assert(record.title == "New manual destination", "Late search replaced manual intent")
    done = begin()
    ns.HandleExplicitManualAuthorityRemove()
    assert(cancelled == 2, "Explicit removal did not cancel the pending lookup")
    late(done)
    assert(not ns.State.routing.pendingManualAuthority and not ns.State.routing.manualAuthority)
    ns.RegisterGuideTargetProvider("zygor", {isLoaded = function() return true end})
    done = begin()
    assert(ns.SelectGuideProvider("zygor"))
    assert(cancelled == 3, "Explicit guide selection did not cancel the pending lookup")
    late(done)
    assert(not ns.State.routing.manualAuthority and ns.GetActiveGuideProvider() == "zygor")
    done = begin()
    ns.SetRoutingEnabled(false)
    assert(cancelled == 4, "Disabling routing retained a pending search")
    late(done)
    assert(not ns.State.routing.manualAuthority)
end
print("Service searches respect real manual-route, explicit removal and guide-selection authority on both clients")

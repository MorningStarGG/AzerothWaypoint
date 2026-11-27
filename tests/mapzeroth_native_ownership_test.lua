-- Native corpse storage, Resume, and coroutine scheduling; only planning and
-- UI commits are controlled boundaries. No native navigation code is copied.
local NativePath = dofile("tests/native_path.lua")
assert(loadfile("tests/mapzeroth_navigation_ownership_test.lua"))()
local NS, backend = AzerothWaypointNS, AzerothWaypointNS.RoutingBackend_Mapzeroth
local complete = dofile("tests/mapzeroth_navigation_fixture.lua")
local root = NativePath("forever", "Mapzeroth/")
local enabled, timers, clock = false, {}, 0
NS.IsRoutingEnabled = function() return enabled end
debugprofilestop = function() clock = clock + 100; return clock end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function drain()
    local n = 0
    while #timers > 0 do
        local fn = table.remove(timers, 1); fn()
        n = n + 1; assert(n < 100, "Native coroutine did not finish")
    end
end

local function make()
    local active, plan, starts, commits = nil, nil, 0, 0
    local a = complete({ L = {}, Theme = {}, Equipment = { Sync = function() end }, Journey = {} })
    assert(loadfile(root .. "MultiRoute.lua"))("Mapzeroth", a)
    a.Navigation.ReplanTarget = function() return active end
    a.Navigation.CurrentPlan = function() return plan end
    a.Navigation.IsActive = function() return plan ~= nil end
    a.Navigation.Start = function(_, entry, value) active, plan = entry, value; starts = starts + 1 end
    a.Navigation.Stop = function() active, plan = nil, nil end
    a.Journey.PlanFromHere = function(_, _, _, yield)
        for _ = 1, 3 do yield() end
        return { steps = { {} } }
    end
    assert(loadfile(root .. "UI/Navigator.lua"))("Mapzeroth", a)
    -- Supply the private UI boundary without replacing Resume or restart.
    local restart
    for i = 1, 30 do
        local key, value = debug.getupvalue(a.Navigator.Resume, i)
        if key == "restart" then restart = value; break end
    end
    assert(type(restart) == "function", "Native Resume contract changed")
    local seated = false
    for i = 1, 30 do
        local key = debug.getupvalue(restart, i)
        if key == "ui" then debug.setupvalue(restart, i, {}); seated = true; break end
    end
    assert(seated, "Native restart UI boundary changed")
    a.Navigator.Tick = function() end
    a.Navigator.Stop = function() a.Navigation:Stop() end
    a.Panel.OnRerouted = function() commits = commits + 1 end
    a.WaypointPrompt.IsCorpseShown = function() return false end
    assert(loadfile(root .. "UI/Corpse.lua"))("Mapzeroth", a)
    local original = { name = "Original trip", dest = { id = "original" } }
    a.Panel.RouteToCorpse = function()
        a.Navigation:Start({ dest = { corpse = true } }, { steps = { {} } })
    end
    return a, original, function() return starts, commits end
end

local function own(a, value)
    MapzerothAddon, enabled = a, value
    assert(backend.RefreshNativeNavigationOwnership())
end

for _, forever in ipairs({ false, true }) do
    NS.IsWoWForever = function() return forever end
    local a, original, counts = make()
    own(a, false)
    a.Navigation:Start(original, { steps = { {} } })
    a.Corpse:Lead("mapzeroth")
    local before = counts()
    own(a, true)
    a.Corpse:OnAlive(); drain()
    assert(counts() == before and select(2, counts()) == 0,
        "A remembered native trip resumed after AWP takeover")

    own(a, false)
    a.Navigation:Start(original, { steps = { {} } })
    a.Corpse:Lead("mapzeroth")
    a.Navigation:Stop() -- the corpse trip can have finished before resurrection
    a.Corpse:OnAlive()
    assert(#timers > 0, "Resume did not use the native asynchronous planner")
    before = counts()
    own(a, true); own(a, false); drain()
    assert(counts() == before and select(2, counts()) == 0,
        "An on/off ownership cycle revived an obsolete native resume")

    a.Navigator:Resume(original); drain()
    assert(counts() == before + 1 and select(2, counts()) == 1)
    local currentPlan = a.Navigation.CurrentPlan
    a.Navigation.CurrentPlan = function() error("fixture: native resume failure") end
    assert(not pcall(a.Navigator.Resume, a, original))
    a.Navigation.CurrentPlan = currentPlan
    own(a, true)
    local previews = 0
    a.MultiRoute:Run(function(yield) yield(); return "preview" end,
        function(result) assert(result == "preview"); previews = previews + 1 end)
    assert(a.Navigator:Resume(original) == false)
    drain(); assert(previews == 1 and counts() == before + 1)

    own(a, false)
    local resume, run = a.Navigator.Resume, a.MultiRoute.Run
    own(a, false); own(a, true); own(a, false)
    assert(a.Navigator.Resume == resume and a.MultiRoute.Run == run, "Guards accumulated")
    a.Navigation:Stop(); a.Navigator:Resume(original)
    local replacement = make()
    own(replacement, false); drain()
    assert(counts() == before + 1, "An obsolete runtime committed a resume")
    own(a, false)
    assert(a.Navigator.Resume == resume and a.MultiRoute.Run == run, "Returning runtime was wrapped twice")
end

-- A missing current contract is reported, never emulated by an old path.
local incomplete = make()
incomplete.Navigator.Resume = nil
MapzerothAddon, enabled = incomplete, true
local ok, reason = backend.RefreshNativeNavigationOwnership()
assert(ok == false and reason:find("Navigator.Resume", 1, true))
print("Current Mapzeroth native corpse/resume ownership, async generations, previews and runtime contracts passed")

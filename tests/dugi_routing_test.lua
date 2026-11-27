-- Lua 5.1: lua tests/dugi_routing_test.lua [retail-Dugi-path] [forever-Dugi-path]
-- Optional paths exercise the actual installed coroutine/caller implementations.
local function expect(value, message) if not value then error(message, 2) end end
local function pack(...) return { n = select("#", ...), ... } end
local function read(path)
    local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close()
    return value:gsub("\r\n", "\n")
end
local function extract(source, first, following, result, env)
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(following, start + #first, true), following)
    local chunk = assert(loadstring(source:sub(start, finish - 1) .. "\nreturn " .. result))
    setfenv(chunk, env)
    return chunk()
end

for clientIndex, client in ipairs({ "retail", "forever" }) do
    local routing, nativeCalls = true, 0
    local providers = {}
    local signals, hooks = {}, {}
    local final, args, resultPolicy
    local dugi = { Modules = {}, qid = { [31] = 81514 }, actions = { [31] = "A" },
        GetQuestStepText = function() return "Talk to Brann" end,
        GetQuestDescription = function() return "Accept 'Bountiful Delves'" end,
        getCoords = function() return { { 47.62, 44.41 } } end,
        GetQuestState = function() return "U" end,
        UpdateIconStatus = function() end,
        UserSetting = function() return true end,
        settings = { useTaxiSystem = true, showArrow = true },
    }
    local arrow = { getFinalWaypoint = function() return final end,
        WaypointsChanged = function() end }
    dugi.DugisArrow = arrow
    local NS = { Internal = { DugiPresentation = {
        StripMarkup = function(value) return value end,
        Invalidate = function() end,
        GetRelevantIndices = function() return { 31 } end,
        SetRouteOwner = function() end,
        ResolveStep = function()
            return { title = "Accept 'Bountiful Delves'", rawTitle = "Bountiful Delves",
                subtext = "Talk to Brann", questID = 81514, semanticKind = "quest", action = "A",
                semantic = "accept", actionReason = "explicit", titleSource = "quest", contextSource = "NPC",
                facts = { guide = "Campaign", state = "U" } }
        end,
    } }, IsRoutingEnabled = function() return routing end,
        GetActiveGuideProvider = function() return "zygor" end,
        RegisterGuideTargetProvider = function(key, provider) providers[key] = provider end,
    }
    _G.AzerothWaypointNS, _G.DugisGuideViewer = NS, dugi
    assert(loadfile("integrations/guides/presentation.lua"))()
    _G.CurrentTitle, _G.DugisGuideUser = "Campaign", { CurrentQuestIndex = 31 }
    _G.hooksecurefunc = function(object, method, after)
        expect(method ~= "GetBestRoute" and method ~= "SetSmartWaypoint" and method ~= "DisplayViewTab",
            "Post-hooked a yielding Dugi operation")
        local original = object[method]
        object[method] = function(...)
            local returned = pack(original(...)); after(...); return unpack(returned, 1, returned.n)
        end
        hooks[method] = (hooks[method] or 0) + 1
    end
    assert(loadfile("core/service_search.lua"))()
    assert(loadfile("integrations/guides/dugi/dugi_provider.lua"))()
    local adapter = assert(providers.dugi, "Dugi did not register its guide provider")
    adapter.installHooks(function(reason) signals[#signals + 1] = reason end)
    expect(adapter.getDebugLines()[1]:find("nativeTravelSearch=unavailable", 1, true), "Missing Taxi status was inaccurate")

    local taxi = {}
    local original = function(self, ...)
        expect(self == taxi, "Lost native planner receiver")
        nativeCalls = nativeCalls + 1; args = pack(...)
        if resultPolicy then return resultPolicy(...) end
    end
    taxi.GetBestRoute = original
    dugi.Modules.Taxi = taxi
    dugi.UpdateIconStatus() -- late initialization
    local wrapper = taxi.GetBestRoute
    expect(wrapper ~= original, "Late Taxi initialization did not install the override")
    for index = 1, 10 do dugi.UpdateIconStatus() end
    expect(taxi.GetBestRoute == wrapper, "Repeated availability events stacked planner wrappers")
    expect(taxi:GetBestRoute(nil, 1, nil, false) == nil and nativeCalls == 0,
        "Inactive Dugi guide update still ran its native planner with AWP routing enabled")
    expect(adapter.getDebugLines()[1]:find("nativeTravelSearch=bypassed", 1, true), "Bypass status was inaccurate")

    local env = setmetatable({ DGV = dugi, DugisArrow = arrow, Taxi = taxi,
        routeStackDefaultLimit = 6, MinimumRecalculateRoutes_sec = 0,
        GetTime = function() return 100 end, CheckEncapsulatedZones = function(_, m, f, x, y) return m, f, x, y end,
        PoolRoute = function() end, SetExtraData = function() end,
        DiffRecalculationPoints = function() end,
    }, { __index = _G })
    env.AddWaypoint = function(mapID, x, y, description)
        final = { map = mapID, x = x, y = y, desc = description }; return final
    end
    arrow.SetProgressSpinner = function() end
    dugi.GetPlayerMapPositionDisruptive = function() return 2405, 0, 0.5, 0.5 end
    dugi.Modules.Corpse = {}
    -- Standalone fixtures preserve the two installed native fallback contracts.
    dugi.SetSmartWaypoint = function(self, mapID, floor, x, y, description)
        local route = taxi:GetBestRoute(nil, 2405, 0, 0.5, 0.5, mapID, floor, x / 100, y / 100)
        if not route then return end
        return route.builder:AddWaypoint(route, description)
    end
    local function initial(mapID, floor, x, y, description, guideIndex, isWTag, questID, _, _, _, onEnd)
        local point = dugi:SetSmartWaypoint(mapID, floor, x, y, description)
        point = point or env.AddWaypoint(mapID, x, y, description)
        point.isRouteDestination = true; point.isRouteWaypoint = nil
        point.guideIndex, point.isWTag, point.questId = guideIndex, isWTag, questID
        if onEnd then onEnd() end
        arrow:WaypointsChanged()
    end
    local function recalculate()
        arrow.recalculatingRoutes = true
        for _, location in env.recalculationQueue:IPairs() do
            local mapID, floor, x, y, description, guideIndex, isWTag, questID = location:Unpack()
            local point = dugi:SetSmartWaypoint(mapID, floor, x, y, description)
            point = point or env.AddWaypoint(mapID, x, y, description)
            point.guideIndex, point.isWTag, point.questId = guideIndex, isWTag, questID
        end
        arrow.recalculatingRoutes = false
    end
    if arg and arg[clientIndex] then
        local root = arg[clientIndex]:gsub("[\\/]$", "")
        local taxiSource, arrowSource = read(root .. "/Taxi.lua"), read(root .. "/arrow.lua")
        extract(taxiSource, "function DGV:SetSmartWaypoint(", "function DGV:SPELLS_CHANGED", "DGV.SetSmartWaypoint", env)
        initial = extract(arrowSource, "local UID = 0", "local waypointInfoQueue", "SetSmartWaypointRoutine", env)
        recalculate = extract(arrowSource, "local RecalculateRoutesRoutine_lastTime = 0",
            "local function AddRecalculationLocation", "RecalculateRoutesRoutine", env)
    end

    local completions = 0
    initial(2339, 0, 47.62, 44.41, "Accept 'Bountiful Delves'", 31, false, 81514, nil, nil, false,
        function() completions = completions + 1 end)
    expect(nativeCalls == 0 and completions == 1, "Initial fallback ran the planner or lost completion")
    expect(final.map == 2339 and final.x == 47.62 and final.y == 44.41 and final.guideIndex == 31
        and final.questId == 81514 and final.isRouteDestination and not final.isRouteWaypoint,
        "Initial fallback lost coordinates, guide ownership or quest metadata")
    local target = NS.Internal.DugiProvider.ExtractTarget()
    expect(target and target.mapID == 2339 and math.abs(target.x - 0.4762) < 0.000001
        and math.abs(target.y - 0.4441) < 0.000001 and target.semanticQuestID == 81514,
        "Native direct fallback did not reach AWP as the exact guide target")
    local location = { Unpack = function() return 2339, 0, 47.62, 44.41, "Accept 'Bountiful Delves'", 31, false, 81514, true end }
    env.recalculationQueue = { IPairs = function() return ipairs({ location }) end }
    recalculate()
    expect(nativeCalls == 0 and final.map == 2339 and final.guideIndex == 31 and final.questId == 81514
        and final.x == 47.62 and final.y == 44.41 and not arrow.recalculatingRoutes,
        "Recalculation fallback ran the planner, lost metadata or left the job busy")

    -- Original arguments/results, yields and errors must pass through untouched.
    routing = false
    resultPolicy = function() return "route", nil, false, "tail" end
    local returned = pack(taxi:GetBestRoute(nil, 2339, nil, false, "tail"))
    expect(args.n == 5 and args[1] == nil and args[2] == 2339 and args[3] == nil and args[4] == false
        and returned.n == 4 and returned[1] == "route" and returned[2] == nil
        and returned[3] == false and returned[4] == "tail", "Native planner arguments/results changed")
    resultPolicy = function() coroutine.yield("native yield"); return "resumed", nil, false end
    local thread = coroutine.create(function() return taxi:GetBestRoute(nil, 2339) end)
    local ok, value = coroutine.resume(thread)
    expect(ok and value == "native yield", "Wrapper broke native planner coroutine yielding")
    local resumed = pack(coroutine.resume(thread))
    expect(resumed.n == 4 and resumed[1] and resumed[2] == "resumed" and resumed[3] == nil and resumed[4] == false,
        "Native resume result was altered")
    resultPolicy = function() error("native planner error") end
    thread = coroutine.create(function() return taxi:GetBestRoute(nil, 2339) end)
    ok, value = coroutine.resume(thread)
    expect(not ok and value:find("native planner error", 1, true), "Wrapper swallowed the native planner error")
    expect(adapter.getDebugLines()[1]:find("nativeTravelSearch=enabled", 1, true), "Native-mode status was inaccurate")

    -- Requests queued before a toggle use the runtime policy on execution.
    routing = false
    local callsBefore = nativeCalls
    thread = coroutine.create(function()
        initial(2339, 0, 47.62, 44.41, "Queued guide", 31, false, 81514, nil, nil, nil,
            function() completions = completions + 1 end)
    end)
    routing = true
    expect(coroutine.resume(thread) and nativeCalls == callsBefore and completions == 2,
        "Queued native job ignored the new routing state or lost its callback")
    expect(dugi.settings.useTaxiSystem and dugi.settings.showArrow, "Override changed Dugi settings")

    -- A native search suspended before enabling AWP can unwind through its
    -- next recursive planner call without cancelling its coroutine/queues.
    routing = false
    resultPolicy = function()
        coroutine.yield("pending native search")
        return taxi:GetBestRoute("recursive continuation")
    end
    thread = coroutine.create(function() return taxi:GetBestRoute("started before AWP") end)
    ok, value = coroutine.resume(thread)
    expect(ok and value == "pending native search", "Native pending-search fixture failed to yield")
    callsBefore = nativeCalls
    routing = true
    ok, value = coroutine.resume(thread)
    expect(ok and value == nil and coroutine.status(thread) == "dead" and nativeCalls == callsBefore,
        "Pending search did not unwind through the runtime bypass")

    -- Reinitializing either the method or the entire Taxi module rebinds once.
    taxi.GetBestRoute = original
    dugi.UpdateIconStatus()
    local rebound = taxi.GetBestRoute
    expect(rebound ~= original and rebound ~= wrapper, "Dugi method replacement was not rebound")
    dugi.UpdateIconStatus(); expect(taxi.GetBestRoute == rebound, "Method rebind stacked wrappers")
    taxi = { GetBestRoute = original }; dugi.Modules.Taxi = taxi
    dugi.UpdateIconStatus()
    expect(taxi:GetBestRoute() == nil and nativeCalls == callsBefore, "Replacement Taxi module bypass failed")
    routing = false; resultPolicy = function() return "replacement native" end
    expect(taxi:GetBestRoute() == "replacement native", "Replacement module lost its native planner")
    -- Also cover an already-ready Taxi module when the addon file first loads,
    -- before guide-provider hooks/evaluation have been started.
    taxi.GetBestRoute = original
    routing = true
    callsBefore = nativeCalls
    assert(loadfile("core/service_search.lua"))()
    assert(loadfile("integrations/guides/dugi/dugi_provider.lua"))()
    local adapter = assert(providers.dugi, "Dugi did not register its guide provider")
    expect(taxi:GetBestRoute() == nil and nativeCalls == callsBefore,
        "Already-ready Taxi module was not guarded before guide evaluation")
    print(client .. ": initial/recalculation targets, callbacks, coroutine behavior, runtime toggles and reloads passed")
end

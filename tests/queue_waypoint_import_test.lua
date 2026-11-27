local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local waypoints = {
    { 51.39, 56.00, "1 A Rolled-Up Pillow" },
    { 51.15, 58.56, "2 Altar of Wisdom" },
    { 45.14, 54.12, "3 A Lost Hunting Knife" },
    { 47.18, 53.14, "4 Altar of Vigor" },
    { 51.10, 50.49, "5 A Tattered Ball" },
    { 51.15, 47.55, "6 Altar of Innocence" },
    { 51.21, 52.93, "7 Gift of the Cycle" },
}

for _, forever in ipairs({ false, true }) do
    local f = make("mapzeroth", forever)
    local NS = f.NS
    for _, name in ipairs({ "state", "items", "routing", "policy" }) do
        assert(loadfile("bridge/routing/queues/" .. name .. ".lua"))()
    end
    TomTom = { waypoints = {}, L = {}, hbd = {}, NameToMapId = {} }
    function TomTom:GetCurrentPlayerPosition() return 1412 end
    function TomTom:AddWaypoint(mapID, x, y, opts)
        return { mapID, x, y, title = opts.title, from = opts.from }
    end
    assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
    NS.InstallExternalTomTomHooks()
    if arg[1] then
        SlashCmdList = {}
        assert(loadfile(arg[1]))("TomTom", TomTom)
    else
        function TomTom.SlashWayCommand(line)
            local x, y, title = line:match("^%s+([%d.]+)%s+([%d.]+)%s+(.+)$")
            TomTom:AddWaypoint(1412, tonumber(x) / 100, tonumber(y) / 100, { title = title, from = "TomTom/way" })
        end
    end

    local function Paste()
        for _, point in ipairs(waypoints) do
            TomTom.SlashWayCommand(string.format(" %.2f %.2f %s", point[1], point[2], point[3]))
        end
    end

    local function CheckNewestImport(queueCount)
        local manual = NS.RouteQueueInternal.GetManualQueueState()
        assert(#manual.order == queueCount)
        local queue = manual.byID[manual.order[queueCount]]
        local saved = f.db.manualQueues.byID[queue.id]
        assert(queue.sourceType == "imported" and #queue.items == #waypoints and #saved.items == #waypoints)
        for index, point in ipairs(waypoints) do
            local item = saved.items[index]
            assert(item.mapID == 1412 and item.x == point[1] / 100 and item.y == point[2] / 100 and item.title == point[3])
        end
        return queue
    end

    Paste()
    f.drain()
    local queue = CheckNewestImport(1)
    assert(NS.GetManualAuthority().queueID == queue.id)

    -- A planner change or explicit clear can cancel the first route while it is pending.
    f.combat = true
    local prior = f.behavior.mapzeroth
    f.behavior.mapzeroth = function() return "pending" end
    Paste()
    f.drain()
    assert(NS.State.routing.pendingManualAuthority)
    NS.CancelPendingManualRoute("backend_change")
    f.behavior.mapzeroth = prior
    CheckNewestImport(2)
    assert(NS.GetManualAuthority().queueID == queue.id)

    -- Even a synchronous route rejection must retain the imported destinations.
    local route = NS.RouteViaBackend
    NS.RouteViaBackend = function() return false end
    Paste()
    f.drain()
    CheckNewestImport(3)

    NS.RouteViaBackend, f.combat = route, false
    f.db.manualClickQueueMode = "replace"
    local manual = NS.RouteQueueInternal.GetManualQueueState()
    assert(NS.RouteQueueByID(queue.id, 3))
    f.drain()
    TomTom.SlashWayCommand(" 52 51 Temporary waypoint")
    f.drain()
    assert(NS.GetManualAuthority().queueID ~= queue.id and #manual.order == 4)
    assert(manual.byID[queue.id] == queue and queue.activeItemIndex == 3 and #queue.items == #waypoints)
    assert(f.db.manualQueues.byID[queue.id].activeItemIndex == 3)

    -- Replacing another one-off still removes only that one-off.
    local oneOffID = NS.GetManualAuthority().queueID
    TomTom.SlashWayCommand(" 53 51 Different waypoint")
    f.drain()
    assert(#manual.order == 4 and manual.byID[oneOffID] == nil)

    -- Passive TomTom waypoint adoption must leave saved queues alone, even
    -- when Replace active is configured to replace every kind of queue.
    NS.SetManualQueuePreservationEnabled(false)
    local activeID = NS.GetManualAuthority().queueID
    TomTom:AddWaypoint(1412, .54, .51, { title = "Published waypoint", from = "ExampleAddon" })
    f.drain()
    assert(NS.GetManualAuthority().title == "Published waypoint" and manual.byID[activeID] and manual.byID[queue.id])

    assert(NS.RouteQueueByID(queue.id, 3))
    f.drain()
    TomTom.SlashWayCommand(" 55 51 Intentional replacement")
    f.drain()
    assert(manual.byID[queue.id] == nil and f.db.manualQueues.byID[queue.id] == nil)
    assert(manual.byID[activeID], "replacing the active queue must keep unrelated queues")

    NS.SetManualQueuePreservationEnabled(true)
    local builtQueueID = NS.GetManualAuthority().queueID
    NS.SetManualClickQueueMode("append")
    TomTom.SlashWayCommand(" 56 51 Appended waypoint")
    f.drain()
    assert(NS.GetManualAuthority().queueID == builtQueueID and #manual.byID[builtQueueID].items == 2)

    NS.SetManualClickQueueMode("replace")
    local questMeta = NS.BuildRouteMeta(NS.BuildQuestIdentity(745, 1412, .47, .7361))
    assert(NS.RequestManualRoute(1412, .47, .7361, "Quest shortcut", questMeta, {
        clickContext = { source = "watch", explicit = true },
    }))
    f.drain()
    assert(NS.GetManualAuthority().queueID ~= builtQueueID and #manual.byID[builtQueueID].items == 2)
end
print("TomTom import, explicit replacement and passive waypoint queue fixtures passed")

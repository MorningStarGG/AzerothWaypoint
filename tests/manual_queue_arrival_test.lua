local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local points = {
    { mapID = 1, x = .5139, y = .5600, title = "1 A Rolled-Up Pillow" },
    { mapID = 1, x = .5115, y = .5856, title = "2 Altar of Wisdom" },
    { mapID = 1, x = .4514, y = .5412, title = "3 A Lost Hunting Knife" },
}

local function Setup(backend, forever)
    local f = make(backend, forever)
    local ns = f.NS
    local createFrame = CreateFrame
    CreateFrame = function(...)
        local frame = createFrame(...)
        frame.Show = function(self) self.shown = true end
        frame.Hide = function(self) self.shown = false end
        return frame
    end
    AzerothWaypointDB = f.db
    for _, path in ipairs({
        "core/core", "core/db_defaults", "core/db", "core/guide_settings",
        "bridge/routing/queues/state", "bridge/routing/queues/items", "bridge/routing/queues/routing",
    }) do assert(loadfile(path .. ".lua"))() end
    f.db.routingEnabled = true
    f.behavior[backend] = "success"
    f.x, f.y = .1, .2
    ns.GetPlayerMapPosition = function() return f.map, f.x, f.y end
    ns.GetWorldPositionFromMapCoords = function(_, x, y) return 1, x * 1000, y * 1000 end
    ns.GetPlayerWaypointDistance = function(map, x, y)
        f.distanceReads = (f.distanceReads or 0) + 1
        if map == f.map then return math.sqrt((x - f.x)^2 + (y - f.y)^2) * 1000 end
    end
    ns.ResolvePresentation = function() return nil end
    ns.PushCarrierWaypoint = function()
        f.publications = (f.publications or 0) + 1
        return true
    end
    ns.ClearCarrierWaypoint = function() end
    ns.RecomputeCarrier = f.recompute
    if backend == "zygor" then
        ns.IsZygorLoaded = function() return true end
        ZygorGuidesViewer = { LibRover = {
            ready = true,
            QueueFindPath = function(_, _, _, _, map, x, y, callback)
                f.calls[#f.calls + 1] = "zygor"
                callback("success", { { type = "end", m = map, x = x, y = y } })
            end,
        } }
        assert(loadfile("bridge/routing/backends/zygor.lua"))()
    end
    ns.InitializeRoutingCore()
    local progress = ns.Internal.RouteProgress
    function f.sample(x, y, ticks)
        if x then f.x, f.y, f.px, f.py, f.moving = x, y, x * 1000, y * 1000, true end
        for _ = 1, ticks or 1 do
            local frame = progress.frame
            if frame and frame.shown then frame.scripts.OnUpdate(frame, .21) end
            f.drain(.21)
        end
    end
    function f.import()
        assert(ns.RouteImportedWaypointBatch(points))
        f.drain()
        return assert(ns.GetManualAuthority())
    end
    return f, ns, progress
end

for _, backend in ipairs({ "zygor", "farstrider", "direct" }) do
    for _, forever in ipairs({ false, true }) do
        local f, ns, progress = Setup(backend, forever)
        ns.SetManualWaypointAutoClearEnabled(true)
        ns.SetManualWaypointClearDistance(30)
        local first = f.import()
        assert(first.backend == backend and first.title == points[1].title)
        assert(progress.frame.shown and ns.State.routing.manualArrival.armed)
        f.sample(.4, .56)
        local readPosition, positionReads = UnitPosition, 0
        UnitPosition = function(unit)
            positionReads = positionReads + 1
            return readPosition(unit)
        end
        local reads, publications, plans, saved = f.distanceReads, f.publications, #f.calls, f.db.manualQueues
        f.sample(nil, nil, 100)
        assert(positionReads == 100 and f.distanceReads == reads and f.publications == publications and #f.calls == plans)
        f.sample(.47, .56)
        assert(positionReads == 101 and f.distanceReads == reads + 1 and f.publications == publications and #f.calls == plans
            and f.db.manualQueues == saved, "Approach must only sample distance")
        f.sample(.49, .56) -- Inside 30 yards, outside the usual 15-yard display radius.
        local second = assert(ns.GetManualAuthority())
        assert(second.title == points[2].title and second.queueID == first.queueID)
        assert(#f.calls == plans + 1)
        local items = f.db.manualQueues.byID[first.queueID].items
        assert(#items == 2 and items[1].title == points[2].title and items[2].title == points[3].title)
        f.sample(nil, nil, 10)
        assert(ns.GetManualAuthority() == second and #f.calls == plans + 1, "Stationary samples replayed arrival")
        f.sample(points[2].x, points[2].y)
        assert(ns.GetManualAuthority().title == points[3].title)
        f.sample(points[3].x, points[3].y)
        assert(not ns.GetManualAuthority() and not progress.frame.shown)
    end
end

-- Cross an outdoor zone on the same continent while a stop remains queued
-- in the original zone. Remaining stationary after validation is cheap.
for _, backend in ipairs({ "direct", "zygor", "farstrider" }) do
    local f, ns = Setup(backend, true)
    ns.SetManualWaypointAutoClearEnabled(true)
    local first = f.import()
    f.sample(.4, .56)
    local plans = #f.calls
    f.map = 2
    ns.NoteRouteEnvironmentChanged("ZONE_CHANGED_NEW_AREA")
    f.sample(.41, .56, 10)
    assert(#f.calls == plans + 1 and ns.GetManualAuthority() == first)
    assert(#f.db.manualQueues.byID[first.queueID].items == #points)
    local reads, publications = f.distanceReads, f.publications
    f.sample(nil, nil, 100)
    assert(f.distanceReads == reads and f.publications == publications and #f.calls == plans + 1)
end

do
    local f, ns, progress = Setup("direct", false)
    local first = f.import()
    assert(not progress.frame, "An ordinary manual route with auto-clear off activated the watcher")
    ns.SetManualWaypointAutoClearEnabled(true)
    f.sample(.49, .56)
    assert(ns.GetManualAuthority() == first)
    ns.SetManualWaypointClearDistance(30) -- Wake a stationary route with an edited setting.
    f.sample()
    assert(ns.GetManualAuthority().title == points[2].title)
    ns.SetManualWaypointAutoClearEnabled(false)
    assert(not progress.frame.shown and not ns.State.routing.manualArrival)
end

do
    local f, ns = Setup("direct", false)
    ns.SetManualWaypointAutoClearEnabled(true)
    ns.SetManualWaypointClearDistance(10)
    f.sample(.51, .56)
    local first = f.import()
    f.sample(.513, .56)
    assert(ns.GetManualAuthority() == first, "A newly selected stop inside the radius cleared prematurely")
    f.sample(.48, .56)
    assert(ns.State.routing.manualArrival.armed)
    UnitPosition = function() end -- The map-position fallback still observes movement.
    f.combat, f.taxi = true, true
    f.sample(.51, .56)
    assert(ns.GetManualAuthority() == first and not ns.State.routing.pendingManualAuthority)
    f.taxi = false
    f.sample()
    assert(ns.GetManualAuthority().title == points[2].title, "Direct queue arrival waited for combat to end")
end

do
    local f, ns = Setup("farstrider", false)
    local pending
    f.behavior.farstrider = function(attempt)
        local destination = ns.RouteSpecials.MakeDestinationLeg("farstrider", attempt.mapID, attempt.x, attempt.y, attempt.title)
        if attempt.title == points[1].title then
            return attempt:Complete({ status = "success", reason = "farstrider_plan", legs = {
                { mapID = 1, x = .3, y = .3, title = "Required portal", kind = "portal",
                    routeTravelType = "portal", routeLegKind = "carrier", arrivalGate = { indoors = true } },
                destination,
            } })
        end
        pending = function()
            attempt:Complete({ status = "success", reason = "farstrider_plan", legs = { destination } })
        end
        return "pending"
    end
    ns.SetManualWaypointAutoClearEnabled(true)
    ns.SetManualWaypointClearDistance(10)
    local first = f.import()
    assert(#first.legs == 2 and first.currentLegIndex == 1, "The fixture must retain the required portal")
    local walking = ns.Internal.RouteWalking
    local readMode, modeReads = walking.ReadMode, 0
    walking.ReadMode = function()
        modeReads = modeReads + 1
        return readMode()
    end
    local plans, publications = #f.calls, f.publications
    for index = 1, 100 do f.sample(.1 + index * .0001, .2) end
    assert(modeReads == 100, "Movement-mode reads for 100 moving samples: " .. modeReads)
    assert(#f.calls == plans and f.publications == publications and first.currentLegIndex == 1)
    walking.ReadMode = readMode
    f.sample(points[1].x, points[1].y)
    assert(ns.GetManualAuthority() == first and first.currentLegIndex == 1, "Arrival bypassed an intermediate leg")
    assert(ns.AdvanceActiveRouteLeg(first, first.currentLeg, first._routeAcceptedPlanGeneration, "portal_arrival"))
    f.sample(nil, nil, 3)
    assert(pending and ns.State.routing.pendingManualAuthority)
    assert(#f.db.manualQueues.byID[first.queueID].items == 3, "First stop was consumed before its successor committed")
    f.sample(points[2].x, points[2].y)
    assert(#f.db.manualQueues.byID[first.queueID].items == 3)
    pending()
    f.drain()
    assert(ns.GetManualAuthority().title == points[2].title and #f.db.manualQueues.byID[first.queueID].items == 2)
end

local function SetupTomTomHandoff()
    local f, ns = Setup("zygor", false)
    local queue = ns.RouteQueueInternal
    ns.HydrateManualQueues()
    assert(loadfile("bridge/routing/queues/projection.lua"))()
    assert(loadfile("bridge/routing/carrier_tomtom.lua"))()

    local counts = { adds = 0, removes = 0, saves = 0, refreshes = 0, recomputes = 0, projections = 0 }
    local pins = {}
    TomTom = { waypoints = { [1] = pins } }
    function TomTom:GetKeyArgs(map, x, y, title)
        return string.format("%d:%s:%s:%s", map, x * 1e8, y * 1e8, title)
    end
    function TomTom:AddWaypoint(map, x, y, opts)
        counts.adds = counts.adds + 1
        local key = self:GetKeyArgs(map, x, y, opts.title)
        if pins[key] then return pins[key] end
        local uid = { map, x, y }
        for name, value in pairs(opts) do uid[name] = value end
        pins[key] = uid
        return uid
    end
    function TomTom:RemoveWaypoint(uid)
        local key = self:GetKeyArgs(uid[1], uid[2], uid[3], uid.title)
        assert(pins[key] == uid)
        counts.removes = counts.removes + 1
        pins[key] = nil
    end
    function TomTom:SetCrazyArrow(uid) self.arrow = uid end
    ns.InstallExternalTomTomHooks()

    local save, refresh = queue.PersistManualQueues, queue.RefreshQueueUI
    local recompute, sync = ns.RecomputeCarrier, ns.SyncAuthorityQueueProjection
    queue.PersistManualQueues = function(...) counts.saves = counts.saves + 1; return save(...) end
    queue.RefreshQueueUI = function(...) counts.refreshes = counts.refreshes + 1; return refresh(...) end
    ns.RecomputeCarrier = function(...) counts.recomputes = counts.recomputes + 1; return recompute(...) end
    ns.SyncAuthorityQueueProjection = function(...) counts.projections = counts.projections + 1; return sync(...) end

    local batch = {
        points[1], points[2], points[3],
        { mapID = 1, x = .4718, y = .5314, title = "4 Altar of Vigor" },
        { mapID = 1, x = .5110, y = .5049, title = "5 A Tattered Ball" },
        { mapID = 1, x = .5115, y = .4755, title = "6 Altar of Innocence" },
        { mapID = 1, x = .5121, y = .5293, title = "7 Gift of the Cycle" },
    }
    ns.SetManualWaypointAutoClearEnabled(true)
    ns.SetManualWaypointClearDistance(10)
    assert(ns.RouteImportedWaypointBatch(batch))
    f.drain()
    local first = assert(ns.GetManualAuthority())
    local liveQueue = assert(queue.GetManualQueueByID(first.queueID))
    local savedQueue = f.db.manualQueues
    local originalPins = {}
    for index, stop in ipairs(batch) do
        originalPins[index] = assert(pins[TomTom:GetKeyArgs(stop.mapID, stop.x, stop.y, stop.title)])
    end
    for name in pairs(counts) do counts[name] = 0 end

    local finishPlan
    ZygorGuidesViewer.LibRover.QueueFindPath = function(_, _, _, _, map, x, y, callback)
        f.calls[#f.calls + 1] = "zygor"
        finishPlan = function(status)
            callback(status or "success", { { type = "end", m = map, x = x, y = y } })
            f.drain()
        end
    end
    local plans = #f.calls
    f.sample(batch[1].x, batch[1].y)
    assert(#f.calls == plans + 1 and finishPlan)
    assert(not ns.GetManualAuthority() and ns.State.routing.pendingManualAuthority)
    assert(TomTom.arrow == originalPins[2], "The pending route did not provisionally point to the next stop")
    assert(f.db.manualQueues == savedQueue and liveQueue.activeItemIndex == 1 and #liveQueue.items == #batch)
    assert(counts.saves == 0 and counts.refreshes == 0, "Pending publication triggered a save or panel refresh")
    return f, ns, batch, liveQueue, originalPins, counts, function(...) return finishPlan(...) end
end

do
    local f, ns, batch, queue, originalPins, counts, finish = SetupTomTomHandoff()
    finish()
    assert(counts.saves == 1 and counts.refreshes == 1 and counts.recomputes == 2 and counts.projections == 2,
        string.format("Handoff counts: saves=%d refreshes=%d recomputes=%d projections=%d",
            counts.saves, counts.refreshes, counts.recomputes, counts.projections))
    assert(counts.removes == 1 and counts.adds == 0, "Unchanged TomTom pins were republished")
    assert(TomTom.arrow == originalPins[2] and ns.GetManualAuthority().title == batch[2].title and #queue.items == 6)
    for index = 3, #batch do
        local stop = batch[index]
        local uid = TomTom.waypoints[1][TomTom:GetKeyArgs(stop.mapID, stop.x, stop.y, stop.title)]
        assert(uid == originalPins[index] and uid.awpQueueItemIndex == index - 1)
    end
    TomTom:SetCrazyArrow(originalPins[7])
    f.drain()
    finish()
    assert(ns.GetManualAuthority().title == batch[7].title and queue.activeItemIndex == 6)
end

do
    local f, ns, batch, queue, _, _, finish = SetupTomTomHandoff()
    assert(ns.RemoveQueueItem(queue.id, 2))
    finish()
    assert(not ns.State.routing.pendingManualAuthority and not ns.GetManualAuthority())
    assert(#queue.items == 6 and queue.items[1].title == batch[1].title and queue.items[2].title == batch[3].title)
    assert(f.db.manualQueues.byID[queue.id].activeItemIndex == 1)
end

do
    local f, ns, batch, queue, _, counts, finish = SetupTomTomHandoff()
    assert(ns.CancelPendingManualRoute("test_cancelled"))
    ns.RecomputeCarrier()
    finish()
    assert(counts.saves == 0 and not ns.State.routing.pendingManualAuthority)
    assert(not ns.GetManualAuthority() and #queue.items == 7)
    assert(#f.db.manualQueues.byID[queue.id].items == 7)
end

do
    local f, ns, batch, queue, _, _, finish = SetupTomTomHandoff()
    assert(ns.MoveQueueItem(queue.id, 1, 7))
    finish()
    assert(ns.GetManualAuthority().title == batch[2].title and queue.activeItemIndex == 1)
    assert(#queue.items == 6 and queue.items[6].title == batch[7].title)
end

for _, directFails in ipairs({ false, true }) do
    local f, ns, batch, queue, _, counts, finish = SetupTomTomHandoff()
    if directFails then
        ns.RoutingBackend_Direct.BeginPlan = function(attempt)
            return attempt:Complete({ status = "failed", reason = "direct_test_failure" })
        end
    end
    finish("failure")
    f.drain(2)
    finish("failure")
    f.drain(2)
    assert(not ns.State.routing.pendingManualAuthority, "The failed planning session left a pending queue route")
    if directFails then
        assert(counts.saves == 0 and #queue.items == 7 and not ns.GetManualAuthority())
    else
        assert(counts.saves == 1 and #queue.items == 6 and ns.GetManualAuthority().title == batch[2].title)
    end
end

-- Remove all also owns a displayed queue while its next stop awaits a plan.
do
    local f, ns, _, queue, _, _, finish = SetupTomTomHandoff()
    local callbacks = {}
    TomTom.RegisterCallback = function(_, event, fn) callbacks[event] = fn end
    StaticPopupDialogs = {TOMTOM_REMOVE_ALL_CONFIRM={OnAccept=function()
        for _, pins in pairs(TomTom.waypoints) do
            for key, uid in pairs(pins) do
                pins[key] = nil
                callbacks.WaypointRemoved("WaypointRemoved", uid)
            end
        end
        callbacks.WaypointsReloaded()
    end}}
    hooksecurefunc = function(object, name, hook)
        local original = object[name]
        object[name] = function(...) original(...); hook(...) end
    end
    ns.InstallCarrierTomTomHooks()
    f.combat = true
    StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept()
    finish()
    assert(not ns.State.routing.pendingManualAuthority and not ns.GetManualAuthority())
    assert(not f.db.manualQueues.byID[queue.id] and not next(TomTom.waypoints[1]))
end

print("Manual queue arrival and TomTom handoff passed, including retained UIDs, single save, cancellation and queue edits")

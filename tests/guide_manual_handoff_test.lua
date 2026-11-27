local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local function session(forever, backend)
    backend = backend or "zygor"
    local f = make(backend, forever)
    local ns = f.NS
    ns.RecomputeCarrier = f.recompute
    ns.Constants = {}
    ns.GetZygorAssetPath = function(path) return path end
    ns.ZGV = function() end
    ns.ClassifyTravelSemantics = function() end
    assert(loadfile("bridge/routing/special_actions.lua"))()
    assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
    assert(loadfile("bridge/routing/presentation.lua"))()
    f.behavior[backend] = "success"
    f.targets = {}
    for index, key in ipairs({"rxp", "polestar"}) do
        f.targets[key] = {mapID=1412, x=.4, y=index*.2, title=key, guideStepIdentity=key.." step 1"}
        ns.RegisterGuideTargetProvider(key, {
            isLoaded=function() return true end, hasGuide=function() return true end,
            getVisibilityState=function() return "visible" end,
            extractTarget=function() return f.targets[key] end,
        })
    end
    assert(ns.SelectGuideProvider("rxp"))
    f.drain()
    f.drain()
    assert(ns.State.routing.carrierState.authority == ns.GetActiveGuideRouteState())
    return f, ns, ns.State.routing
end

local cases = {}
function cases.combat(forever)
    local backends = {"direct", "zygor", "farstrider", "mapzeroth", "dugi"}
    if forever then backends[#backends + 1] = "questierouter"; backends[#backends + 1] = "polestar" end
    for _, backend in ipairs(backends) do
        local f, ns, routing = session(forever, backend)
        local capable = backend ~= "zygor" or forever
        local calls = #f.calls
        f.combat = true
        f.event("PLAYER_REGEN_DISABLED")
        f.targets.rxp = {mapID=1413, x=.3, y=.4, title="Next objective", guideStepIdentity="step 2"}
        ns.ScheduleGuideProviderEvaluation("rxp", "next_step")
        f.drain()
        assert(routing.carrierState.title == "Next objective" and routing.carrierState.source == "guide")
        assert(#f.calls == calls + (capable and 1 or 0), backend .. " guide combat search policy")
        local pending
        f.behavior[backend] = function(a) pending = a; return "pending" end
        local strict = {strictRouteSuccess=true}
        local first = f.start(1412, .2, .4, "First", strict)
        f.drain()
        assert(routing.carrierState.authority == first and not f.db.manualAuthority and f.db.activeRouteSource == "guide")
        local stale = pending
        local second = f.start(1412, .3, .4, "Second", strict)
        f.drain()
        assert(routing.carrierState.authority == second and routing.pendingManualAuthority == second)
        assert(not stale or not stale:Complete({status="success", legs=first.legs}))
        assert((pending ~= nil) == capable)
        f.behavior[backend] = "success"
        if capable then
            assert(pending:Complete({status="success", legs=second.legs}))
            f.drain()
            assert(routing.manualAuthority == second and f.db.manualAuthority.title == "Second")
        end
        ns.ClearManualRoute("explicit")
        assert(routing.carrierState.source == "guide" and routing.carrierState.title == "Next objective")
        f.combat = false
        f.event("PLAYER_REGEN_ENABLED")
        f.drain()
        assert(not routing.manualAuthority and not routing.pendingManualAuthority and not f.db.manualAuthority)
    end
end
function cases.pending(forever)
    local f, ns, routing = session(forever)
    local attempt
    f.behavior.zygor = function(a) attempt = a; return "pending" end
    local pending = f.start(1413, .2, .4, "Manual", {strictRouteSuccess=true})
    f.drain()
    assert(attempt and routing.pendingManualAuthority == pending and not routing.manualAuthority)
    f.combat = true
    assert(ns.SelectGuideProvider("polestar"))
    assert(not routing.pendingManualAuthority, "Guide selection kept an outstanding manual request")
    assert(not attempt:Complete({status="success",legs={{mapID=1413,x=.2,y=.4}}}))
    f.combat = false
    f.behavior.zygor = "success"
    f.event("PLAYER_REGEN_ENABLED")
    f.drain()
    assert(not f.db.manualAuthority and routing.carrierState.authority == ns.GetGuideRouteState("polestar"))
end

function cases.order(forever)
    local f, ns, routing = session(forever)
    ns.SelectGuideProvider("polestar")
    local manual = f.start()
    f.drain()
    assert(routing.manualAuthority == manual, "A deferred guide selection erased a later manual click")
    assert(routing.carrierState.authority == manual and f.db.activeRouteSource == "manual")
    ns.ScheduleGuideProviderEvaluation("rxp", "native_step_click", {explicit=true, allowProviderSwitch=true})
    local newer = f.start(1413, .3, .6, "Newer")
    f.drain()
    assert(routing.manualAuthority == newer and ns.GetActiveGuideProvider() == "polestar")
    -- Reverse the order of the coalesced callbacks relative to the last user click.
    ns.ScheduleGuideProviderEvaluation("rxp", "passive")
    ns.ScheduleGuideProviderEvaluation("polestar", "first_click", {explicit=true, allowProviderSwitch=true})
    ns.ScheduleGuideProviderEvaluation("rxp", "last_click", {explicit=true, allowProviderSwitch=true})
    f.drain()
    assert(not routing.manualAuthority and ns.GetActiveGuideProvider() == "rxp")

    -- Provider callbacks may publish a manual request during target extraction.
    local adapter = ns.GetGuideTargetProvider("polestar")
    local extract = adapter.extractTarget
    adapter.extractTarget = function()
        adapter.extractTarget = extract
        newer = f.start(1413, .5, .7, "During guide evaluation")
        return extract()
    end
    ns.ScheduleGuideProviderEvaluation("polestar", "guide_click", {explicit=true, allowProviderSwitch=true})
    f.drain()
    assert(routing.manualAuthority == newer, "A running guide evaluation erased a later manual request")
end

function cases.resume(forever)
    local f, ns, routing = session(forever)
    local manual = f.start()
    f.drain()
    f.targets.rxp = {mapID=1413,x=.2,y=.6,title="New guide step",guideStepIdentity="step 2"}
    ns.ScheduleGuideProviderEvaluation("rxp", "next_step")
    f.drain()
    assert(routing.carrierState.authority == manual)
    local guide = ns.GetGuideRouteState("rxp")
    assert(not guide._routePlanning and not guide.backend)
    routing.specialActionCasting = true
    f.event("UNIT_SPELLCAST_START", "player", "travel-1")
    local before = #f.calls
    ns.ClearManualRoute("explicit")
    assert(routing.carrierState.authority == guide)
    f.drain()
    assert(#f.calls == before and ns.GetRoutePlanningStatus(guide).deferred)
    f.event("UNIT_SPELLCAST_SUCCEEDED", "player", "travel-1")
    f.drain()
    f.drain()
    assert(guide.backend == "zygor", "Resuming the passive guide step skipped the selected planner")
    assert(guide.currentLeg.mapID == 1413 and guide.title == "New guide step")
end

function cases.step(forever)
    local f, ns = session(forever)
    local before = #f.calls
    f.targets.rxp.title = "Localized step text"
    f.targets.rxp.rawTitle = "Localized step text"
    ns.ScheduleGuideProviderEvaluation("rxp", "text_updated")
    f.drain()
    assert(#f.calls == before, "A text refresh for an unchanged guide step restarted the planner")
    assert(ns.GetActiveGuideRouteState().currentLeg.title == "Localized step text")
    f.targets.rxp.guideStepIdentity = "New step at the same coordinates"
    ns.ScheduleGuideProviderEvaluation("rxp", "next_step")
    f.drain()
    assert(#f.calls == before + 1 and ns.GetActiveGuideRouteState().target.guideStepIdentity == f.targets.rxp.guideStepIdentity)

    f.behavior.zygor = function() return "pending" end
    local goal = f.targets.rxp
    goal.guideStepIdentity, goal.title, goal.rawTitle = "NPC quest handoff", "First quest", "First quest"
    ns.ScheduleGuideProviderEvaluation("rxp", "next_step")
    f.drain()
    local attempt = f.lastAttempt
    local calls = #f.calls
    assert(attempt.title == goal.title)
    local leg = ns.RouteSpecials.MakeDestinationLeg("zygor", goal.mapID, goal.x, goal.y, goal.title)
    leg.subtext, leg.semanticQuestID, leg.iconHintQuestID = "Old NPC", 11, 11
    goal.title, goal.rawTitle, goal.subtext = "Second quest", "Second quest", "Talk to Baine"
    goal.semanticKind, goal.semanticQuestID, goal.iconHintKind, goal.iconHintQuestID = "quest", 22, "quest", 22
    ns.ScheduleGuideProviderEvaluation("rxp", "quest_rewarded")
    f.drain()
    assert(attempt:Complete({status="success", legs={leg}})); f.drain()
    local final = ns.GetActiveGuideRouteState().currentLeg
    assert(#f.calls == calls and final.title == goal.title and final.rawTitle == goal.rawTitle
        and final.subtext == goal.subtext and final.semanticQuestID == 22 and final.iconHintQuestID == 22,
        "A pending plan restored stale quest metadata or restarted planning")
end

function cases.metadata(forever)
    local f, ns, routing = session(forever)
    local manual = f.start()
    manual.manualQuestID = 11
    f.drain()
    f.behavior.zygor = function() return "pending" end
    local pending = f.start(1413, .2, .4, "Requested", {strictRouteSuccess=true})
    pending.manualQuestID = 22
    local resolutions, syncs, subtext = 0, 0, "0/1"
    ns.ResolveQuestPresentation = function(id)
        resolutions = resolutions + 1
        return {title="Quest " .. id, subtext=subtext}
    end
    ns.SyncWorldOverlay = function() syncs = syncs + 1 end
    local pushedTitle
    local push = ns.PushCarrierWaypoint
    ns.PushCarrierWaypoint = function(map, x, y, title, ...)
        pushedTitle = title
        return push(map, x, y, title, ...)
    end
    ns.RecomputeCarrier()
    assert(routing.carrierState.authority == pending and routing.manualAuthority == manual)
    assert(routing.presentationState.manualQuestID == 22, "Pending carrier inherited the previous route's quest")
    assert(pushedTitle == "Quest 22" and routing.presentationState.overlayTitle == pushedTitle)
    local pendingSnapshot = routing.presentationState
    resolutions, syncs = 0, 0
    local searches = #f.calls
    for _ = 1, 100 do ns.RecomputeCarrier() end
    assert(resolutions == 100 and syncs == 0 and #f.calls == searches)
    subtext = "1/1"
    ns.RecomputeCarrier()
    assert(syncs == 1 and routing.presentationState.pinpointSubtext == subtext)
    assert(pendingSnapshot.pinpointSubtext == "0/1", "A subsequent refresh mutated the published snapshot")
    pending.mapPinInfo = {kind="vignette", atlas="FirstIcon"}
    ns.RecomputeCarrier()
    local firstIcon = routing.presentationState
    pending.mapPinInfo.atlas = "UpdatedIcon"
    ns.RecomputeCarrier()
    assert(syncs == 3 and firstIcon.iconHintAtlas == "FirstIcon" and routing.presentationState.iconHintAtlas == "UpdatedIcon")
    assert(firstIcon.contentSig ~= routing.presentationState.contentSig, "Changing only the icon must invalidate overlay content")
    ns.CancelPendingManualRoute("explicit")
    ns.RecomputeCarrier()
    assert(routing.carrierState.authority == manual and routing.presentationState.manualQuestID == 11)
end

-- TomTom delivers callbacks before AddWaypoint / SetCrazyArrow return.
-- Exercise replacement and clear while the older publication is on the stack.
function cases.callbacks(forever)
    local original = TomTom
    for _, callback in ipairs({"added", "arrow", "removed", "queueAdded", "queueRemoved"}) do
        for _, replace in ipairs({true, false}) do
            TomTom = nil
            local f, ns, routing = session(forever)
            local fired, arrows, showQueue = false, 0, true
            local function notify(event, uid)
                if event ~= callback or fired or (uid.title ~= "First click" and uid.title ~= "Queued stop") then return end
                fired = true
                if replace then f.start(1413, .3, .6, "Latest click", {strictRouteSuccess=true})
                else ns.ClearManualRoute("explicit") end
            end
            TomTom = {waypoints = {}}
            function TomTom:GetKeyArgs(map, x, y, title) return table.concat({map, x, y, title}, "/") end
            function TomTom:AddWaypoint(map, x, y, opts)
                self.waypoints[map] = self.waypoints[map] or {}
                local key = self:GetKeyArgs(map, x, y, opts.title)
                if self.waypoints[map][key] then return self.waypoints[map][key] end
                local uid = {map, x, y, title=opts.title, awpCarrier=opts.awpCarrier, awpQueueProjection=opts.awpQueueProjection}
                self.waypoints[map][key] = uid
                if opts.crazy ~= false then self:SetCrazyArrow(uid) end
                notify(uid.awpQueueProjection and "queueAdded" or "added", uid)
                return uid
            end
            function TomTom:RemoveWaypoint(uid)
                self.waypoints[uid[1]][self:GetKeyArgs(uid[1],uid[2],uid[3],uid.title)] = nil
                notify(uid.awpQueueProjection and "queueRemoved" or "removed", uid)
            end
            function TomTom:SetCrazyArrow(uid)
                arrows = arrows + 1
                self.arrow = uid
                notify("arrow", uid)
            end
            local overlayTitle, overlayPin
            ns.SyncWorldOverlay = function(uid, _, _, _, title) overlayTitle, overlayPin = title, uid end
            ns.GetActiveQueuePublishedEntries = function()
                if showQueue and routing.carrierState.title == "First click" then
                    return {{mapID=1413, x=.5, y=.6, title="Queued stop"}}, "test queue"
                end
            end
            ns.RouteViaBackend(1413, .2, .4, "First click", nil, {strictRouteSuccess=true})
            if callback == "queueRemoved" then
                f.drain()
                showQueue = false
                ns.RecomputeCarrier()
            elseif callback == "removed" then
                f.drain()
                if replace then
                    ns.ResolveManualQueueFollowup = function()
                        return {mapID=1413, x=.7, y=.4, title="Previous queue successor"}
                    end
                end
                ns.ClearManualRoute("explicit")
            end
            local expected = replace and "Latest click" or "rxp"
            local function check()
                assert(fired and TomTom.arrow == routing.carrierState.uid and TomTom.arrow.title == expected)
                assert(routing.presentationState.overlayTitle == expected and routing.carrierState.title == expected)
                -- If the guide never lost the screen, it needs no overlay rewrite.
                assert(overlayTitle == expected or not replace and overlayTitle == nil)
                for _, pins in pairs(TomTom.waypoints) do
                    for _, uid in pairs(pins) do assert(uid == TomTom.arrow, "Superseded pin remained on the map") end
                end
            end
            check()
            f.drain()
            check()
            local before = arrows
            ns.RecomputeCarrier()
            assert(arrows == before + 1, "A single publication wrote TomTom's arrow twice")
            local oldPin = TomTom.arrow
            TomTom:RemoveWaypoint(oldPin)
            ns.RecomputeCarrier()
            assert(overlayPin == TomTom.arrow and overlayPin ~= oldPin, "Recreated pin did not reach the overlay")
        end
    end
    TomTom = original
end

for _, forever in ipairs({false, true}) do
    for _, name in ipairs({"pending", "order", "resume", "step", "metadata", "combat", "callbacks"}) do
        cases[name](forever)
    end
end
print("Manual and guide handoff ownership passed")

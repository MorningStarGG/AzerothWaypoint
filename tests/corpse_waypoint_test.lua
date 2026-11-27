local make = assert(loadfile("tests/route_planning_fixture.lua"))()
for _, forever in ipairs{false, true} do
    local f = make("mapzeroth", forever)
    local function SetBehavior(key, value) f.behavior[key]=value end
    local NS, routing = f.NS, f.NS.State.routing
    local db, callbacks, pins = NS.GetDB(), {}, {}
    NS.RecomputeCarrier = f.recompute
    NS.GetZygorAssetPath = function(path) return path end
    NS.Constants = {}
    NS.ZGV = function() return nil end
    NS.IsInstanceRouteTravelType = function() return false end
    NS.ClassifyTravelSemantics = function() return nil end
    local forwardedKind
    NS.SyncWorldOverlay = function(_,_,_,_,_,_,kind) forwardedKind=kind end
    for _, name in ipairs{"state", "items", "routing", "projection", "snapshot", "policy"} do
        assert(loadfile("bridge/routing/queues/" .. name .. ".lua"))()
    end
    assert(loadfile("core/travel_types.lua"))()
    assert(loadfile("bridge/routing/presentation.lua"))()
    local overlay = { Config = {}, overlay = {}, target = {}, arrival = {}, questIconCache = {},
        questSubtextCache = {}, fontStringTextCache = {}, settingsSnapshot = {} }
    NS.Internal.WorldOverlay = overlay
    assert(loadfile("world_overlay/assets/icons.lua"))()
    assert(loadfile("world_overlay/presentation/content.lua"))()
    TomTom = { waypoints = {} }
    function TomTom:GetKeyArgs(map,x,y,title) return NS.Signature(map,x,y) .. ":" .. title end
    function TomTom:AddWaypoint(map,x,y,opts)
        local key = self:GetKeyArgs(map,x,y,opts.title)
        self.waypoints[map] = self.waypoints[map] or {}
        if self.waypoints[map][key] then return self.waypoints[map][key] end
        local uid = {map,x,y,title=opts.title,from=opts.from or opts.source or "?"}
        for k,v in pairs(opts) do if not uid[k] then uid[k]=v end end
        self.waypoints[map][key], pins[uid] = uid, true
        return uid
    end
    function TomTom:RemoveWaypoint(uid)
        local removed = false
        pins[uid] = nil
        for key,value in pairs(self.waypoints[uid[1]] or {}) do
            if value == uid then self.waypoints[uid[1]][key]=nil; removed=true end
        end
        if removed and callbacks.WaypointRemoved then callbacks.WaypointRemoved("WaypointRemoved",uid) end
    end
    function TomTom:SetCrazyArrow() end
    function TomTom.RegisterCallback(_,event,fn) callbacks[event]=fn end
    StaticPopupDialogs = { TOMTOM_REMOVE_ALL_CONFIRM = { OnAccept = function()
        for uid in pairs(pins) do TomTom:RemoveWaypoint(uid) end
        callbacks.WaypointsReloaded()
    end } }
    hooksecurefunc = function(owner, key, after)
        local original = owner[key]
        owner[key] = function(...) original(...); after(...) end
    end
    assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
    NS.InstallExternalTomTomHooks()
    NS.InstallCarrierTomTomHooks()
    local originalProbe = debugstack
    debugstack = function() error("Corpse detection consulted debugstack/title") end

    -- A localized title cannot establish corpse identity; the native flag can.
    local meta = NS.CreateRouteMetaForExternalWaypoint({corpse=true},2,.8,.9,"Meine Leiche")
    local ordinary = NS.CreateRouteMetaForExternalWaypoint({},2,.8,.9,"My Corpse")
    assert(meta.identity.destinationKind == "corpse" and meta.queueSourceType == "transient_source")
    assert(not ordinary.identity.destinationKind and not ordinary.queueSourceType)
    assert(not NS.RouteIdentitiesMatch(meta.identity,ordinary.identity))
    local normalized = NS.RouteQueueInternal.NormalizeQueueItemMeta(meta,2,.8,.9)
    assert(normalized.identity.destinationKind == "corpse" and normalized.queueSourceType == "transient_source")

    local dead = false
    UnitIsDeadOrGhost = function() return dead end
    NS.InitializeRoutingCore()
    local guideTitle = "Guide before death"
    NS.RegisterGuideTargetProvider("rxp", {
        isLoaded=function() return true end, hasGuide=function() return true end,
        getVisibilityState=function() return "visible" end,
        extractTarget=function() return {mapID=2,x=.2,y=.3,title=guideTitle,guideStepIdentity=guideTitle} end,
    })
    local id = forever and "questierouter" or "mapzeroth"
    db.routingBackend, routing.selectedBackend, f.behavior[id] = id, id, "success"
    assert(NS.SelectGuideProvider("rxp")); f.drain()
    assert(routing.carrierState.source == "guide")
    local guide = NS.GetActiveAuthorityRecord()
    local oldAttempt
    f.behavior[id] = function(attempt) oldAttempt = attempt; return "pending" end
    NS.RequestRoutePlan(guide, id, nil, "refresh"); f.drain()
    assert(oldAttempt)
    dead = true
    NS.TickUpdate(); f.drain()
    assert(not NS.GetActiveAuthorityRecord() and not routing.carrierState, "Guide kept its arrow after death")
    assert(not oldAttempt:Complete({status="success", legs=guide.legs}), "Stale guide result survived death")
    f.behavior[id] = function(attempt)
        return attempt:Complete({status="success",legs={
            {mapID=2,x=.6,y=.7,title="Follow the path",kind="walk",routeLegKind="carrier",routeTravelType="travel"},
            NS.RouteSpecials.MakeDestinationLeg(id,attempt.mapID,attempt.x,attempt.y,attempt.title),
        }})
    end
    TomTom:AddWaypoint(2,.8,.9,{title="Corpse",corpse=true,persistent=false}); f.drain()
    assert(routing.manualAuthority.identity.destinationKind == "corpse" and routing.carrierState.title == "Follow the path")
    guideTitle = "Guide updated during corpse walk"
    NS.ScheduleGuideProviderEvaluation("rxp", "step"); f.drain()
    assert(routing.carrierState.source == "manual" and routing.carrierState.title == "Follow the path")
    StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept(); f.drain()
    assert(not routing.manualAuthority and not routing.carrierState and not next(pins), "Remove all restored a guide while ghosted")
    NS.Internal.Interface = {commands = {}}
    assert(loadfile("interface/commands_diagnostics.lua"))()
    NS.Internal.Interface.commands.handleRouteDump("legs")
    assert(f.messages[#f.messages] == "[ROUTE] LEGS nil", "Route diagnostics reported an inactive guide")
    guideTitle = "Guide updated while ghosted"
    f.behavior[id] = "success"
    NS.ScheduleGuideProviderEvaluation("rxp", "step"); f.drain()
    assert(not routing.carrierState and not NS.RoutePlanningCore.GetActiveRecord(), "Guide update took over the ghost route")
    dead = false
    NS.TickUpdate(); f.drain()
    assert(routing.carrierState.source == "guide" and routing.carrierState.title == guideTitle and
        NS.GetActiveAuthorityRecord().backend == id,
        "Resurrection did not restore the current guide step")
    NS.ClearGuideRouteState("rxp")

    -- Exercise every planner through the real hook, coordinator and presentation.
    for _, id in ipairs{"direct", "mapzeroth", "farstrider", "zygor", "polestar", "dugi"} do
        db.routingBackend, routing.selectedBackend, f.behavior[id] = id, id, "success"
        local uid = TomTom:AddWaypoint(2,.8,.9,{title="Meine Leiche",corpse=true,persistent=false})
        f.drain()
        local record = assert(routing.manualAuthority)
        assert(record.backend == (id == "polestar" and not forever and "zygor" or id)
            and record.identity.destinationKind == "corpse")
        assert(record.sourceAddon == "TomTom" and db.manualAuthority == nil, "Corpse source/persistence changed")
        local before = f.commits
        assert(TomTom:AddWaypoint(2,.8,.9,{title="Meine Leiche",corpse=true,persistent=false}) == uid)
        f.drain()
        assert(routing.manualAuthority == record and f.commits == before
            and #NS.RouteQueueInternal.GetTransientQueueStack() == 1, "Corpse republication duplicated its route/overlay")
        local output = routing.presentationState
        assert(routing.carrierState.kind == "corpse" and forwardedKind == "corpse"
            and output.iconHintKind == "corpse" and output.semanticKind == "corpse")
        assert(overlay.ResolveSnapshotIconSpec(output) == overlay.Config.ICON_SPECS.corpse)
        local item = {mapID=2,x=.8,y=.9,title="Meine Leiche",meta=record.meta}
        assert(overlay.ResolveWaypointIconSpec(item) == overlay.Config.ICON_SPECS.corpse)
        local entry = NS.RouteQueueInternal.BuildProjectionEntry({id="corpse"},record.currentLeg,1,record,"final_destination")
        assert(entry.iconHintKind == "corpse" and overlay.ResolveWaypointIconSpec(entry) == overlay.Config.ICON_SPECS.corpse)
        TomTom:RemoveWaypoint(uid); f.drain()
        assert(routing.manualAuthority == nil, "Native corpse removal did not clear its route")
    end

    -- Travel legs retain their own instruction/icon until the corpse destination.
    db.routingBackend, routing.selectedBackend = "mapzeroth", "mapzeroth"
    SetBehavior("mapzeroth",function(attempt)
        return attempt:Complete({status="success",legs={
            {mapID=1,x=.4,y=.4,title="Take the portal",kind="portal",routeLegKind="carrier",routeTravelType="portal"},
            NS.RouteSpecials.MakeDestinationLeg("mapzeroth",attempt.mapID,attempt.x,attempt.y,attempt.title),
        }})
    end)
    local nativeCorpse = TomTom:AddWaypoint(2,.8,.9,{title="Corpse",corpse=true,persistent=false})
    f.drain()
    local current = routing.manualAuthority
    assert(not nativeCorpse.fromAWP, "Queue publication claimed TomTom's native corpse UID")
    TomTom:RemoveWaypoint(nativeCorpse); f.drain()
    assert(not routing.manualAuthority, "Resurrection during an intermediate leg left the corpse route active")
    nativeCorpse = TomTom:AddWaypoint(2,.8,.9,{title="Corpse",corpse=true,persistent=false}); f.drain()
    current = routing.manualAuthority
    assert(routing.presentationState.iconHintKind == "portal" and routing.carrierState.kind == "route")
    local travel = NS.RouteQueueInternal.BuildProjectionEntry({id="travel"},current.currentLeg,1,current,"travel")
    assert(overlay.ResolveWaypointIconSpec(travel) == overlay.Config.ICON_SPECS.portal)
    current.currentLegIndex, current.currentLeg = 2, current.legs[2]
    NS.RecomputeCarrier()
    assert(routing.presentationState.iconHintKind == "corpse")
    TomTom:RemoveWaypoint(nativeCorpse); f.drain()
    assert(not routing.manualAuthority)

    -- A delayed removal of an older corpse cannot clear a new manual route
    -- simply because the new route targets the same coordinates.
    nativeCorpse = TomTom:AddWaypoint(2,.8,.9,{title="Old corpse",corpse=true,persistent=false})
    f.drain()
    TomTom:AddWaypoint(2,.8,.9,{title="New ordinary target",from="OtherAddon"}); f.drain()
    current = routing.manualAuthority
    assert(pins[nativeCorpse], "Carrier teardown removed TomTom's corpse before its native lifecycle")
    assert(not current.identity.destinationKind)
    TomTom:RemoveWaypoint(nativeCorpse); f.drain()
    assert(routing.manualAuthority == current, "Old corpse removal cleared a newer ordinary route")
    NS.HandleExplicitManualAuthorityRemove(); f.drain()

    -- A same-coordinate title change must not keep using the native corpse UID.
    f.behavior.mapzeroth = "success"
    nativeCorpse = TomTom:AddWaypoint(2,.8,.9,{title="Direct corpse",corpse=true,persistent=false}); f.drain()
    TomTom:AddWaypoint(2,.8,.9,{title="Ordinary at corpse coordinates",from="OtherAddon"}); f.drain()
    current = routing.manualAuthority
    assert(routing.carrierState.uid ~= nativeCorpse and pins[nativeCorpse])
    TomTom:RemoveWaypoint(nativeCorpse); f.drain()
    assert(routing.manualAuthority == current and routing.presentationState.iconHintKind == "manual")
    NS.HandleExplicitManualAuthorityRemove(); f.drain()

    -- A corpse temporarily overlays an existing manual queue and resumes it.
    db.routingBackend, routing.selectedBackend, f.behavior.mapzeroth = "mapzeroth", "mapzeroth", "success"
    local user = TomTom:AddWaypoint(2,.7,.6,{title="Ordinary destination",from="OtherAddon"})
    f.drain()
    local previousQueue = routing.manualAuthority.queueID
    local corpse = TomTom:AddWaypoint(2,.8,.9,{title="Corpse",corpse=true,persistent=false})
    f.drain()
    assert(NS.RouteQueueInternal.GetQueueByID(previousQueue), "Corpse adoption cleared the user's queue")
    TomTom:RemoveWaypoint(corpse); f.drain()
    assert(routing.manualAuthority and routing.manualAuthority.queueID == previousQueue)
    assert(not routing.manualAuthority.identity.destinationKind)
    for _, action in ipairs({"resume", "remove_again", "replace"}) do
        dead = true
        TomTom:AddWaypoint(2,.8,.9,{title="Corpse",corpse=true,persistent=false}); f.drain()
        StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept(); f.drain()
        NS.TickUpdate()
        assert(not routing.carrierState and not routing.manualAuthority and not next(pins),
            "Previous queue took the arrow while ghosted")
        if action == "remove_again" then
            StaticPopupDialogs.TOMTOM_REMOVE_ALL_CONFIRM.OnAccept()
        elseif action == "replace" then
            TomTom:AddWaypoint(2,.5,.5,{title="New destination",from="OtherAddon"}); f.drain()
        end
        dead = false
        NS.TickUpdate(); f.drain()
        if action == "resume" then
            assert(routing.manualAuthority and routing.manualAuthority.queueID == previousQueue)
        elseif action == "remove_again" then
            assert(not routing.manualAuthority, "Second explicit clear restored a queue on resurrection")
            assert(NS.RouteQueueByID(previousQueue)); f.drain()
        else
            assert(routing.manualAuthority and routing.manualAuthority.title == "New destination")
        end
    end
    local ordinaryItem = {mapID=2,x=.8,y=.9,title="Meine Leiche",meta=ordinary}
    assert(overlay.ResolveWaypointIconSpec(ordinaryItem) == overlay.Config.ICON_SPECS.manual,
        "Corpse cache contaminated an ordinary waypoint at the same coordinates")

    -- Mapzeroth joins the corpse lifecycle before opening its native panel or
    -- adding a second external destination. Keep the test planner installed.
    local planner = NS.RoutingBackend_Mapzeroth
    assert(loadfile("bridge/routing/backends/mapzeroth.lua"))()
    local syncOwnership = NS.RoutingBackend_Mapzeroth.RefreshNativeNavigationOwnership
    NS.RoutingBackend_Mapzeroth = planner
    local nativeLeads = 0
    MapzerothAddon = {
        Corpse = { Lead = function(_, _) nativeLeads = nativeLeads + 1 end },
        GetCorpseTarget = function() return {mapID=2,x=.83,y=.91} end,
        L = {PICK_CORPSE="Mapzeroth corpse"},
    }
    UnitIsGhost = function() return dead end
    IsInInstance = function() return false end
    assert(loadfile("tests/mapzeroth_navigation_fixture.lua"))()(MapzerothAddon)
    syncOwnership()
    db.routingBackend, routing.selectedBackend = "direct", "direct"
    for _, mode in ipairs({"mapzeroth", "tomtom", "both"}) do
        local previous = routing.manualAuthority
        dead = true
        assert(MapzerothAddon.Corpse:Lead(mode)); f.drain()
        local corpseRoute = assert(routing.manualAuthority)
        assert(NS.IsCorpseRoute(corpseRoute) and corpseRoute.sourceAddon == "Mapzeroth")
        assert(corpseRoute.backend == (mode == "tomtom" and "direct" or "mapzeroth"))
        assert(not db.manualAuthority and #NS.RouteQueueInternal.GetTransientQueueStack() == 1 and nativeLeads == 0)
        local latePin = TomTom:AddWaypoint(2,.83,.91,{title="Native corpse",corpse=true,persistent=false}); f.drain()
        assert(routing.manualAuthority == corpseRoute and #NS.RouteQueueInternal.GetTransientQueueStack() == 1)
        dead = false
        NS.EndCorpseRoute(); f.drain()
        TomTom:RemoveWaypoint(latePin); f.drain()
        assert(routing.manualAuthority and routing.manualAuthority.queueID == previous.queueID)
        assert(#NS.RouteQueueInternal.GetTransientQueueStack() == 0 and not MapzerothAddon.Corpse:Lead(mode))
    end

    dead = true
    local nativePin = TomTom:AddWaypoint(2,.83,.91,{title="Native corpse",corpse=true,persistent=false}); f.drain()
    local adopted = routing.manualAuthority
    assert(adopted.backend == "direct")
    MapzerothAddon.Corpse:Lead("both"); f.drain()
    assert(routing.manualAuthority == adopted and adopted.backend == "mapzeroth")
    assert(#NS.RouteQueueInternal.GetTransientQueueStack() == 1)
    dead = false
    TomTom:RemoveWaypoint(nativePin); f.drain()
    NS.EndCorpseRoute(); f.drain()

    dead = true
    local pendingAttempt
    SetBehavior("mapzeroth",function(attempt) pendingAttempt = attempt; return "pending" end)
    local previous = routing.manualAuthority
    MapzerothAddon.Corpse:Lead("mapzeroth"); f.drain()
    assert(pendingAttempt and NS.IsCorpseRoute(routing.pendingManualAuthority))
    dead = false
    NS.EndCorpseRoute(); f.drain()
    assert(not routing.pendingManualAuthority and routing.manualAuthority == previous)
    assert(not pendingAttempt:Complete({status="success", legs=previous.legs}))

    f.routing = false
    syncOwnership()
    MapzerothAddon.Corpse:Lead("both")
    assert(nativeLeads == 1, "Disabling AWP did not release Mapzeroth's corpse handoff")
    local before = routing.manualAuthority
    local native = TomTom:AddWaypoint(2,.6,.5,{title="Native corpse",corpse=true,persistent=false})
    f.drain()
    assert(native.corpse and native.crazy == nil and routing.manualAuthority == before,
        "Disabled AWP still diverted corpse navigation")
    debugstack = originalProbe
end
print("Retail/Forever corpse adoption, all planners, overlay/queue icons, transient lifecycle and manual-queue restoration passed")

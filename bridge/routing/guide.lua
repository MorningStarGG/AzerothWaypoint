local NS = _G.AzerothWaypointNS
local state = NS.State
local Queue = NS.RouteQueueInternal

-- ============================================================
-- Guide provider dispatcher
-- ============================================================
--
-- Guide addons are target providers, not routing backends. Each provider
-- extracts one current guide target, the selected routing backend still plans
-- the path. Manual/transient authority remains higher priority than all guide
-- providers.

local GUIDE_COORD_EPSILON = 0.00005
local providers = {}
local providerOrder = {}
local providerStarted = {}
local evaluationQueues = {}
local pendingReasonByProvider = {}
local pendingOptsByProvider = {}
local pendingGuideSelection
local guidePresence = {}

local function TrimString(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function NormalizeProviderKey(value)
    value = TrimString(value)
    return value and value:lower() or nil
end

local function GetTimeSafe()
    return type(GetTime) == "function" and GetTime() or 0
end

local function EnsureGuideRoutingState()
    state.routing = state.routing or {}
    state.routing.guideRouteStates = state.routing.guideRouteStates or {}
    if type(Queue) == "table" and type(Queue.EnsureQueueState) == "function" then
        Queue.EnsureQueueState()
    end
    return state.routing
end

local function GetDB()
    return type(NS.GetDB) == "function" and NS.GetDB() or nil
end

local function SaveActiveGuideProvider(providerKey)
    local db = GetDB()
    if type(db) == "table" then
        db.activeGuideProvider = providerKey
    end
end

local function GetSavedGuideProvider()
    local db = GetDB()
    return NormalizeProviderKey(type(db) == "table" and db.activeGuideProvider)
end

local function IsValidTarget(target)
    return type(target) == "table"
        and type(target.mapID) == "number"
        and type(target.x) == "number"
        and type(target.y) == "number"
end

function NS.IsValidGuideRouteTarget(target)
    return IsValidTarget(target)
end

local function HasCarrierLeg(legs)
    if type(legs) ~= "table" then
        return false
    end
    for index = 1, #legs do
        local leg = legs[index]
        if type(leg) == "table" and leg.routeLegKind == "carrier" then
            return true
        end
    end
    return false
end

local function IsSameGuideRouteTarget(a, b)
    return IsValidTarget(a)
        and IsValidTarget(b)
        and a.mapID == b.mapID
        and math.abs(a.x - b.x) < GUIDE_COORD_EPSILON
        and math.abs(a.y - b.y) < GUIDE_COORD_EPSILON
end

local function IsGuideDestinationLegForTarget(leg, target)
    if type(leg) ~= "table" or not IsSameGuideRouteTarget(leg, target) then
        return false
    end

    if leg.routeLegKind == "destination" then
        return true
    end

    -- Direct/fallback guide legs should still be considered destinations even
    -- if a backend omitted routeLegKind. Never rewrite carrier/travel legs.
    return leg.routeLegKind == nil
        and (leg.kind == nil or leg.kind == "destination" or leg.kind == "guide_goal" or leg.kind == "guide")
end

-- Provider hooks still need to read their latest step, but an older click
-- must lose its right to select a provider or replace a manual destination.
function NS.ClearPendingGuideSelection()
    if not pendingGuideSelection then return end
    for key in pairs(pendingGuideSelection) do pendingGuideSelection[key] = nil end
    pendingGuideSelection.presentationRefresh = true
    pendingGuideSelection = nil
end

local function ClearManualRouteForGuideSelection(reason)
    state.routing.queueAfterCorpse = nil
    if state.routing.manualAuthority or state.routing.pendingManualAuthority then
        NS.ClearManualRoute(reason or "guide_explicit_takeover", { preserveManualQueue = true })
    end
end

local function EnsureGuideQueue(providerKey, label)
    if type(Queue) == "table" and type(Queue.EnsureGuideQueue) == "function" then
        return Queue.EnsureGuideQueue(providerKey, label)
    end
    if type(NS.SetGuideQueueProvider) == "function" then
        return NS.SetGuideQueueProvider(providerKey, label)
    end
    return nil
end

local function SetActiveGuideProvider(providerKey, persist)
    providerKey = NormalizeProviderKey(providerKey)
    local routing = EnsureGuideRoutingState()
    local changed = routing.activeGuideProvider ~= providerKey
    if providerKey then
        EnsureGuideQueue(providerKey, providers[providerKey] and providers[providerKey].label)
    end
    routing.activeGuideProvider = providerKey
    if type(Queue) == "table" and type(Queue.SetActiveGuideProvider) == "function" then
        Queue.SetActiveGuideProvider(providerKey)
    end
    routing.guideRouteState = providerKey and routing.guideRouteStates[providerKey] or nil
    if persist ~= false then
        SaveActiveGuideProvider(providerKey)
    end
    if changed and type(NS.GetGuideTrackerViewerProviders) == "function"
        and type(NS.RefreshGuideTrackerViewerProvider) == "function"
    then
        local function refreshIndicators()
            local viewerProviders = NS.GetGuideTrackerViewerProviders()
            for index = 1, #viewerProviders do
                NS.RefreshGuideTrackerViewerProvider(viewerProviders[index], "active_provider_changed")
            end
        end
        if type(NS.After) == "function" then NS.After(0, refreshIndicators) else refreshIndicators() end
    end
    return providerKey
end

function NS.GetActiveGuideProvider()
    local routing = EnsureGuideRoutingState()
    return NormalizeProviderKey(routing.activeGuideProvider)
end

function NS.GetActiveGuideRouteState()
    local routing = EnsureGuideRoutingState()
    local activeProvider = NormalizeProviderKey(routing.activeGuideProvider)
    if activeProvider then
        return routing.guideRouteStates[activeProvider]
    end
    return routing.guideRouteState
end

function NS.GetGuideRouteState(providerKey)
    local routing = EnsureGuideRoutingState()
    providerKey = NormalizeProviderKey(providerKey)
    if providerKey then
        return routing.guideRouteStates[providerKey]
    end
    return NS.GetActiveGuideRouteState()
end

-- ============================================================
-- Guide provider registry
-- ============================================================

local function GetProvider(providerKey)
    providerKey = NormalizeProviderKey(providerKey)
    return providerKey and providers[providerKey] or nil, providerKey
end

function NS.RegisterGuideTargetProvider(providerKey, adapter)
    providerKey = NormalizeProviderKey(providerKey)
    if not providerKey or type(adapter) ~= "table" then
        return false
    end
    if providers[providerKey] == nil then
        providerOrder[#providerOrder + 1] = providerKey
    end
    adapter.key = providerKey
    adapter.label = adapter.label or adapter.displayName or providerKey
    providers[providerKey] = adapter

    if type(NS.RegisterGuideProvider) == "function" then
        NS.RegisterGuideProvider(providerKey, {
            displayName = adapter.displayName or adapter.label or providerKey,
            icon = adapter.icon,
            iconTint = adapter.iconTint,
            iconSize = adapter.iconSize,
        })
    end
    EnsureGuideQueue(providerKey, adapter.label or adapter.displayName or providerKey)
    return true
end

function NS.GetGuideTargetProvider(providerKey)
    return GetProvider(providerKey)
end

function NS.GetGuideProviderList()
    local list = {}
    for index = 1, #providerOrder do
        list[#list + 1] = providerOrder[index]
    end
    return list
end

local function ProviderIsLoaded(adapter)
    if type(adapter) ~= "table" then
        return false
    end
    if type(adapter.isLoaded) ~= "function" then
        return true
    end
    local ok, loaded = pcall(adapter.isLoaded)
    return ok and loaded == true
end

local function GetProviderVisibility(providerKey)
    local adapter = providers[providerKey]
    if not ProviderIsLoaded(adapter) then
        return "absent"
    end
    if state.routing.cinematicActive then
        return "hidden"
    end
    if type(adapter.getVisibilityState) == "function" then
        local ok, value = pcall(adapter.getVisibilityState)
        if ok and (value == "visible" or value == "hidden" or value == "absent") then
            return value
        end
    end
    return "visible"
end

function NS.GetActiveGuideTravelIntent()
    if not NS.IsRoutingEnabled or not NS.IsRoutingEnabled() then return end
    local key = NS.GetActiveGuideProvider()
    local adapter = key and providers[key]
    local getIntent = type(adapter) == "table" and rawget(adapter, "getTravelIntent")
    if not ProviderIsLoaded(adapter) or type(getIntent) ~= "function" then return end
    local routing = EnsureGuideRoutingState()
    if routing.pendingManualAuthority or routing.cinematicActive then return end
    local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
    if record and (record.authority ~= "guide" or record.guideProvider ~= key or record.suppressed) then return end
    local ok, intent = pcall(getIntent)
    if ok and type(intent) == "table" then return intent end
end

local function GuideDestinationReached(record, radius)
    local target = record and record.target
    local intent = target and target.guideTravelIntent
    if not intent or NS.GetActiveGuideTravelIntent() ~= intent or record._coreRoutePending or record._corePlanning
        or not record.legs or record.currentLegIndex ~= #record.legs
        or InCombatLockdown and InCombatLockdown() or UnitOnTaxi and UnitOnTaxi("player")
        or UnitInVehicle and UnitInVehicle("player") or UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return
    end
    local leg = record.legs[record.currentLegIndex]
    if not leg or leg.specialAction or NS.RouteArrivalGateMatches and not NS.RouteArrivalGateMatches(leg) then return end
    local distance = NS.GetPlayerWaypointDistance and NS.GetPlayerWaypointDistance(target.mapID, target.x, target.y)
    if type(distance) ~= "number" or type(issecretvalue) == "function" and issecretvalue(distance) then return end
    return distance >= 0 and distance <= radius and intent or nil
end

-- Observe the final accepted destination through the existing core monitor.
-- Native progression runs next frame, after checking authority/generation again.
function NS.CheckGuideRouteDestinationReached(record, radius)
    local key = record and record.guideProvider
    local adapter = key and providers[key]
    if not adapter or type(adapter.onDestinationReached) ~= "function" then return end
    local generation = record._routeAcceptedPlanGeneration
    local expected = record.target and record.target.guideTravelIntent
    if expected and record._guideArrivalIntent == expected and record._guideArrivalGeneration == generation then return end
    local intent = GuideDestinationReached(record, radius)
    if not intent then return end
    record._guideArrivalIntent, record._guideArrivalGeneration = intent, generation
    NS.After(0, function()
        if NS.GetActiveAuthorityRecord() ~= record or record._routeAcceptedPlanGeneration ~= generation
            or GuideDestinationReached(record, radius) ~= intent then
            if record._guideArrivalIntent == intent and record._guideArrivalGeneration == generation then
                record._guideArrivalIntent, record._guideArrivalGeneration = nil, nil
            end
            return
        end
        pcall(adapter.onDestinationReached, record, intent)
    end)
end

-- A guide can own navigation without a waypoint (hearth instructions, paused
-- engines, etc.). Availability must not be inferred from its current target.
local function ProviderHasGuide(providerKey)
    local adapter = providers[providerKey]
    if not ProviderIsLoaded(adapter) then return false end
    if type(adapter.hasGuide) == "function" then
        local ok, present = pcall(adapter.hasGuide)
        return ok and present == true
    end
    return GetProviderVisibility(providerKey) ~= "absent"
end

function NS.GetGuideVisibilityState(providerKey)
    providerKey = NormalizeProviderKey(providerKey)
    if providerKey then
        return GetProviderVisibility(providerKey)
    end

    local activeProvider = NS.GetActiveGuideProvider()
    if activeProvider then
        local activeState = GetProviderVisibility(activeProvider)
        if activeState ~= "absent" then
            return activeState
        end
    end

    local sawHidden = false
    for index = 1, #providerOrder do
        local visibility = GetProviderVisibility(providerOrder[index])
        if visibility == "visible" then
            return "visible"
        elseif visibility == "hidden" then
            sawHidden = true
        end
    end
    return sawHidden and "hidden" or "absent"
end

-- ============================================================
-- Guide selection and visibility
-- ============================================================

-- Provider selection is authority, not route creation. An explicitly selected
-- guide remains active even when its current step has no coordinates, the next
-- routable step can then take over without requiring another user action.
function NS.SelectGuideProvider(providerKey, reason)
    providerKey = NormalizeProviderKey(providerKey)
    local adapter = providerKey and providers[providerKey] or nil
    if not providerKey or not ProviderIsLoaded(adapter) then return false end
    if NS.Internal.ServiceSearch then NS.Internal.ServiceSearch.Cancel() end
    NS.ClearPendingGuideSelection()
    SetActiveGuideProvider(providerKey, true)
    ClearManualRouteForGuideSelection(reason or "guide_provider_selected")
    if type(NS.SetActiveRouteSource) == "function" then NS.SetActiveRouteSource("guide") end
    if type(NS.ScheduleGuideProviderEvaluation) == "function" then
        NS.ScheduleGuideProviderEvaluation(providerKey, reason or "guide_provider_selected", {
            presentationRefresh = true,
        })
    end
    return true
end

local function ShouldShowGuideVisuals()
    if NS.GetGuideVisibilityState() ~= "visible" then
        return false
    end
    if state.routing.manualAuthority ~= nil or state.routing.pendingManualAuthority ~= nil then
        return false
    end
    return NS.GetActiveGuideRouteState() ~= nil
end

function NS.SyncGuideVisualState()
    state.routing.guideVisualShown = ShouldShowGuideVisuals()
    return state.routing.guideVisualShown
end

function NS.ClearGuideRouteState(providerKey)
    local routing = EnsureGuideRoutingState()
    providerKey = NormalizeProviderKey(providerKey) or NormalizeProviderKey(routing.activeGuideProvider)
    if not providerKey then
        routing.guideRouteState = nil
        NS.SyncGuideVisualState()
        if type(NS.RecomputeCarrier) == "function" then
            NS.RecomputeCarrier()
        end
        return
    end

    local record = routing.guideRouteStates[providerKey]
    if type(record) == "table" and type(record.backend) == "string" then
        local backend = NS.GetRoutingBackend(record.backend)
        if backend and type(backend.Clear) == "function" then
            pcall(backend.Clear, record, "guide_clear")
        end
    end

    routing.guideRouteStates[providerKey] = nil
    if routing.activeGuideProvider == providerKey then
        routing.guideRouteState = nil
    end
    if type(NS.ClearGuideQueueProjection) == "function" then
        NS.ClearGuideQueueProjection(providerKey)
    end
    NS.SyncGuideVisualState()
    if type(NS.RecomputeCarrier) == "function" then
        NS.RecomputeCarrier()
    end
end

local guideLegPresentation = { "title", "rawTitle", "subtext", "source", "guideProvider",
    "semanticKind", "semanticQuestID", "semanticTravelType", "iconHintKind", "iconHintQuestID",
    "navigationHeight", "navigationContinent", "destinationName", "destinationKind", "destinationAction",
    "destinationPurpose" }

-- Both a live guide refresh and a newly accepted backend plan use the current
-- guide's text and quest identity at its destination. Travel legs own theirs.
function NS.ApplyGuideDestinationPresentation(leg, target)
    if not IsGuideDestinationLegForTarget(leg, target) then return false end
    local changed = false
    for _, key in ipairs(guideLegPresentation) do
        if leg[key] ~= target[key] then
            leg[key] = target[key]
            changed = true
        end
    end
    return changed
end

-- ============================================================
-- Publishing guide targets
-- ============================================================

-- All guide records take their navigation coordinates from the route request.
-- The provider supplies step identity and display fields for the same target.
---@param mapID? number
---@param x? number
---@param y? number
---@param title? string
function NS.SetGuideRouteTarget(record, target, providerKey, mapID, x, y, title)
    if mapID == nil then mapID, x, y, title = target.mapID, target.x, target.y, target.title end
    local changed = false
    local function set(tbl, key, value)
        if tbl[key] ~= value then
            tbl[key] = value
            changed = true
        end
    end

    providerKey = NormalizeProviderKey(providerKey)
        or NormalizeProviderKey(target.guideProvider)
        or NormalizeProviderKey(record.guideProvider)

    local recordTarget = type(record.target) == "table" and record.target or {}
    if record.target ~= recordTarget then
        record.target = recordTarget
        changed = true
    end

    set(recordTarget, "mapID", mapID)
    set(recordTarget, "x", x)
    set(recordTarget, "y", y)
    set(recordTarget, "title", title)
    set(recordTarget, "rawTitle", target.rawTitle)
    set(recordTarget, "subtext", target.subtext)
    set(recordTarget, "source", target.source)
    set(recordTarget, "kind", target.kind or "guide_goal")
    set(recordTarget, "guideProvider", providerKey)
    set(recordTarget, "guideStepIdentity", target.guideStepIdentity)
    set(recordTarget, "liveRouteLegKind", target.liveRouteLegKind)
    set(recordTarget, "semanticKind", target.semanticKind)
    set(recordTarget, "guideTravelIntent", target.guideTravelIntent)
    set(recordTarget, "semanticQuestID", target.semanticQuestID)
    set(recordTarget, "semanticTravelType", target.semanticTravelType)
    set(recordTarget, "iconHintKind", target.iconHintKind)
    set(recordTarget, "iconHintQuestID", target.iconHintQuestID)
    set(recordTarget, "navigationArea", target.navigationArea)
    set(recordTarget, "navigationNpcID", target.navigationNpcID)
    set(recordTarget, "navigationHeight", target.navigationHeight)
    set(recordTarget, "navigationContinent", target.navigationContinent)
    for _, key in ipairs({ "destinationName", "destinationKind", "destinationAction", "destinationPurpose" }) do
        set(recordTarget, key, target[key])
        set(record, key, target[key])
    end

    set(record, "mapID", mapID)
    set(record, "x", x)
    set(record, "y", y)
    set(record, "title", title)
    set(record, "rawTitle", target.rawTitle)
    set(record, "subtext", target.subtext)
    set(record, "guideProvider", providerKey)
    set(record, "guideSource", target.source)
    set(record, "sourceAddon", providerKey)
    set(record, "liveRouteLegKind", target.liveRouteLegKind)
    set(record, "semanticKind", target.semanticKind)
    set(record, "semanticQuestID", target.semanticQuestID)
    set(record, "semanticTravelType", target.semanticTravelType)
    set(record, "iconHintKind", target.iconHintKind)
    set(record, "iconHintQuestID", target.iconHintQuestID)
    set(record, "navigationArea", target.navigationArea)
    set(record, "navigationHeight", target.navigationHeight)
    set(record, "navigationContinent", target.navigationContinent)

    if type(record.legs) == "table" then
        for index = 1, #record.legs do
            changed = NS.ApplyGuideDestinationPresentation(record.legs[index], recordTarget) or changed
        end
    end
    return NS.ApplyGuideDestinationPresentation(record.currentLeg, recordTarget) or changed
end

local function SameGuideRecordTarget(record, target, providerKey)
    local previousTarget = type(record) == "table" and record.target or nil
    local previousIdentity = type(previousTarget) == "table" and previousTarget.guideStepIdentity or nil
    local identity = type(target) == "table" and target.guideStepIdentity or nil
    -- A named native interaction can hand in another quest without changing
    -- the accepted walk. Identity still refreshes all presentation metadata;
    -- unknown actors and pending plans retain normal goal-change semantics.
    local function Handoff(action) return action == "accept" or action == "turnin" end
    local sameInteraction = previousTarget and target and previousTarget.destinationName ~= nil
        and previousTarget.destinationName == target.destinationName
        and (target.destinationKind == "npc" or target.destinationKind == "object")
        and previousTarget.destinationKind == target.destinationKind
        and Handoff(previousTarget.destinationAction) and Handoff(target.destinationAction)
        and not previousTarget.navigationArea and not target.navigationArea
        and not previousTarget.guideTravelIntent and not target.guideTravelIntent
        and not record._corePlanning and not record._coreRoutePending
        and record.currentLeg and record.currentLeg.walkingDescription ~= nil
    local sameStep
    -- Providers with stable step identities can update localized text or late
    -- item/NPC names without turning a presentation refresh into pathfinding.
    if previousIdentity ~= nil or identity ~= nil then
        sameStep = previousIdentity == identity
    else
        sameStep = tostring(previousTarget and previousTarget.rawTitle or "") ==
            tostring(target and target.rawTitle or "")
    end
    return type(record) == "table"
        and NormalizeProviderKey(record.guideProvider) == providerKey
        and IsSameGuideRouteTarget(record.target, target)
        and record.target.navigationNpcID == target.navigationNpcID
        and record.target.navigationHeight == target.navigationHeight
        and record.target.navigationContinent == target.navigationContinent
        and (sameStep or sameInteraction)
        and
        (sameInteraction or tostring(record.target and record.target.source or "") == tostring(target and target.source or ""))
end

local function ShouldRouteProvider(providerKey, opts)
    opts = type(opts) == "table" and opts or {}
    if opts.explicit == true then
        return true
    end
    if state.routing.manualAuthority ~= nil or state.routing.pendingManualAuthority ~= nil then
        return false
    end

    local savedSource = type(NS.GetSavedActiveRouteSource) == "function"
        and NS.GetSavedActiveRouteSource()
        or "guide"
    if savedSource ~= "guide" then
        return false
    end

    local allowProviderSwitch = opts.allowProviderSwitch == true
    local savedProvider = GetSavedGuideProvider()
    if not allowProviderSwitch and savedProvider and ProviderHasGuide(savedProvider) then
        return savedProvider == providerKey
    end
    local activeProvider = NS.GetActiveGuideProvider()
    if activeProvider then
        if activeProvider == providerKey then
            return true
        end
        if not ProviderHasGuide(activeProvider) then
            return true
        end
        return allowProviderSwitch
    end

    return true
end

local function StorePassiveGuideProjection(providerKey, target)
    local routing = EnsureGuideRoutingState()
    local previous = routing.guideRouteStates[providerKey]
    if type(previous) == "table"
        and previous.authority == "guide"
        and SameGuideRecordTarget(previous, target, providerKey)
        and type(previous.legs) == "table"
    then
        if NS.SetGuideRouteTarget(previous, target, providerKey)
            and type(NS.SyncGuideQueueProjection) == "function"
        then
            NS.SyncGuideQueueProjection(previous)
        end
        return previous
    end
    -- Preserve provider-specific fields without sharing its mutable target table.
    local snapshot = {}
    for key, value in pairs(target) do snapshot[key] = value end
    local record = {
        target = snapshot,
        authority = "guide",
        suppressed = false,
        createdAt = GetTimeSafe(),
        _routePlanningResume = true
    }
    NS.SetGuideRouteTarget(record, target, providerKey)
    routing.guideRouteStates[providerKey] = record
    if routing.activeGuideProvider == providerKey then
        routing.guideRouteState = record
    end
    if type(NS.SyncGuideQueueProjection) == "function" then
        NS.SyncGuideQueueProjection(record)
    end
    return record
end

function NS.UpdateGuideTarget(providerKey, target, suppressed, opts)
    if type(providerKey) == "table" then
        opts = suppressed
        suppressed = target
        target = providerKey
        providerKey = NormalizeProviderKey(target and target.guideProvider)
            or NS.GetActiveGuideProvider()
            or "zygor"
    else
        providerKey = NormalizeProviderKey(providerKey) or "zygor"
    end
    opts = type(opts) == "table" and opts or {}

    EnsureGuideQueue(providerKey, providers[providerKey] and providers[providerKey].label)

    if suppressed or not IsValidTarget(target) then
        NS.ClearGuideRouteState(providerKey)
        return false
    end

    target.guideProvider = providerKey
    target.kind = target.kind or "guide_goal"
    target.title = TrimString(target.title) or TrimString(target.rawTitle) or "Guide step"

    if not ShouldRouteProvider(providerKey, opts) then
        StorePassiveGuideProjection(providerKey, target)
        return true
    end

    -- A temporary fallback must not erase the provider we are waiting to
    -- restore. Explicit selection replaces that preference immediately.
    SetActiveGuideProvider(providerKey, not GetSavedGuideProvider()
        or opts.explicit == true or opts.allowProviderSwitch == true)
    if type(NS.SetActiveRouteSource) == "function" then
        NS.SetActiveRouteSource("guide")
    end
    if opts.explicit == true then
        local reason = opts.reason
        NS.ClearPendingGuideSelection()
        ClearManualRouteForGuideSelection(reason)
    end

    local routing = EnsureGuideRoutingState()
    local gs = routing.guideRouteStates[providerKey]
    local effectiveBackend = type(NS.GetEffectiveBackendID) == "function" and NS.GetEffectiveBackendID() or nil
    local sameTarget = SameGuideRecordTarget(gs, target, providerKey)
    local routePending = sameTarget and gs and gs._coreRoutePending == true
    local hasPlannedLegs = sameTarget and type(gs and gs.legs) == "table" and #gs.legs > 0
    local needsCarrierRetry = effectiveBackend ~= "direct"
        and target.liveRouteLegKind == "carrier"
        and not HasCarrierLeg(gs and gs.legs)
        and not routePending
    if sameTarget and (hasPlannedLegs or routePending) and not needsCarrierRetry then
        local presentationChanged = NS.SetGuideRouteTarget(gs, target, providerKey)
        routing.guideRouteState = gs
        -- Explicit activation must republish an accepted route even when its
        -- target/text are unchanged: the carrier can still belong to another
        -- provider (or a manual route that was just cleared).
        if opts.explicit == true or presentationChanged or opts.presentationRefresh == true then
            if hasPlannedLegs and type(NS.RecomputeCarrier) == "function" then
                NS.RecomputeCarrier()
            elseif type(NS.SyncGuideQueueProjection) == "function" then
                NS.SyncGuideQueueProjection(gs)
            end
        end
        NS.SyncGuideVisualState()
        return true
    end

    if type(NS.RouteViaBackend) ~= "function" then
        return false
    end
    local routed = NS.RouteViaBackend(target.mapID, target.x, target.y, target.title, nil, {
        authority = "guide",
        guideTarget = target,
        guideProvider = providerKey,
    })
    NS.SyncGuideVisualState()
    return routed == true
end

-- ============================================================
-- Target extraction and diagnostics
-- ============================================================

local function ExtractProviderTarget(providerKey, opts)
    local adapter = providers[providerKey]
    if not ProviderIsLoaded(adapter) or type(adapter.extractTarget) ~= "function" then
        return nil, true
    end
    local ok, target, suppressed = pcall(adapter.extractTarget, opts)
    if not ok then
        return nil, true
    end
    if IsValidTarget(target) then
        target.guideProvider = providerKey
        target.kind = target.kind or "guide_goal"
        return target, suppressed == true
    end
    return nil, suppressed ~= false
end

local function ChooseDebugProvider(providerKey)
    providerKey = NormalizeProviderKey(providerKey) or NS.GetActiveGuideProvider()
    if providerKey and providers[providerKey] then
        return providerKey
    end

    local activeRecord = NS.GetActiveGuideRouteState()
    providerKey = NormalizeProviderKey(type(activeRecord) == "table" and activeRecord.guideProvider)
    if providerKey and providers[providerKey] then
        return providerKey
    end

    for index = 1, #providerOrder do
        local candidate = providerOrder[index]
        if GetProviderVisibility(candidate) == "visible" then
            return candidate
        end
    end

    for index = 1, #providerOrder do
        local candidate = providerOrder[index]
        if ProviderIsLoaded(providers[candidate]) then
            return candidate
        end
    end
    return nil
end

local function FormatDebugCoords(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return "nil"
    end
    return string.format("%s@%.4f,%.4f", tostring(mapID), x, y)
end

local function BuildGenericProviderDebugLines(providerKey)
    local adapter = providers[providerKey]
    local target, suppressed = ExtractProviderTarget(providerKey)
    local record = NS.GetGuideRouteState(providerKey)
    local currentLeg = type(record) == "table" and record.currentLeg or nil
    local lines = {}

    lines[#lines + 1] = table.concat({
        "provider=" .. tostring(providerKey),
        "label=" .. tostring(adapter and adapter.label or "-"),
        "loaded=" .. tostring(ProviderIsLoaded(adapter)),
        "visibility=" .. tostring(GetProviderVisibility(providerKey)),
        "active=" .. tostring(NS.GetActiveGuideProvider() == providerKey),
    }, " ")

    if type(target) == "table" then
        lines[#lines + 1] = table.concat({
            "target",
            "title=" .. tostring(target.title),
            "subtext=" .. tostring(target.subtext),
            "source=" .. tostring(target.source),
            "coords=" .. FormatDebugCoords(target.mapID, target.x, target.y),
            "semanticKind=" .. tostring(target.semanticKind),
            "semanticQuestID=" .. tostring(target.semanticQuestID),
        }, " ")
    else
        lines[#lines + 1] = table.concat({
            "target=nil",
            "suppressed=" .. tostring(suppressed),
        }, " ")
    end

    if type(record) == "table" then
        lines[#lines + 1] = table.concat({
            "route",
            "backend=" .. tostring(record.backend),
            "outcome=" .. tostring(record.routeOutcome),
            "reason=" .. tostring(record.routeOutcomeReason or record.replanReason),
            "legs=" .. tostring(type(record.legs) == "table" and #record.legs or 0),
            "currentLegIndex=" .. tostring(record.currentLegIndex),
            "current=" ..
            FormatDebugCoords(currentLeg and currentLeg.mapID, currentLeg and currentLeg.x, currentLeg and currentLeg.y),
            "currentTitle=" .. tostring(currentLeg and currentLeg.title),
        }, " ")
    else
        lines[#lines + 1] = "route=nil"
    end

    return lines
end

function NS.GetGuideProviderDebugLines(providerKey)
    providerKey = ChooseDebugProvider(providerKey)
    if not providerKey then
        return { "no guide provider available" }
    end

    local adapter = providers[providerKey]
    if type(adapter) == "table" and type(adapter.getDebugLines) == "function" then
        local ok, lines = pcall(adapter.getDebugLines, BuildGenericProviderDebugLines(providerKey))
        if ok and type(lines) == "table" and #lines > 0 then
            return lines
        end
    end

    return BuildGenericProviderDebugLines(providerKey)
end

-- ============================================================
-- Refresh scheduling
-- ============================================================

local function EvaluateGuideProvider(providerKey, reason, opts)
    providerKey = NormalizeProviderKey(providerKey)
    if not providerKey then return false end
    local hasGuide = ProviderHasGuide(providerKey)
    local previousPresence = guidePresence[providerKey]
    guidePresence[providerKey] = hasGuide
    local savedProvider = GetSavedGuideProvider()
    if hasGuide and (providerKey == savedProvider
            or (type(opts) == "table" and (opts.explicit or opts.allowProviderSwitch)))
        and NS.GetActiveGuideProvider() ~= providerKey
    then
        opts = opts or {}
        opts.presentationRefresh = true
        SetActiveGuideProvider(providerKey, opts.explicit == true or opts.allowProviderSwitch == true)
    end
    if not hasGuide and previousPresence ~= false and NS.GetActiveGuideProvider() == providerKey then
        -- Reconsider other providers when a guide is closed or becomes
        -- unavailable. Their normal evaluations choose the available fallback,
        -- coordinate-less and paused guides never enter this path.
        for index = 1, #providerOrder do
            local other = providerOrder[index]
            if other ~= providerKey then NS.ScheduleGuideProviderEvaluation(other, "guide_unavailable") end
        end
    end
    local visibility = providerKey and GetProviderVisibility(providerKey) or "absent"
    if visibility == "hidden" then
        -- AFK cameras, cinematics and native-frame cloaking hide presentation,
        -- they do not relinquish the user's provider selection or accepted plan.
        NS.SyncGuideVisualState()
        return false
    end
    if not providerKey or visibility ~= "visible" then
        NS.ClearGuideRouteState(providerKey)
        return false
    end
    local target, suppressed = ExtractProviderTarget(providerKey, opts)
    return NS.UpdateGuideTarget(providerKey, target, suppressed, opts)
end

local function MergeEvaluationOpts(previous, nextOpts)
    if type(nextOpts) ~= "table" then return previous end
    local merged = previous or {}
    for key, value in pairs(nextOpts) do
        if key == "explicit" or key == "allowProviderSwitch" then
            merged[key] = merged[key] == true or value == true
        else
            merged[key] = value
        end
    end
    return merged
end

function NS.ScheduleGuideProviderEvaluation(providerKey, reason, opts)
    providerKey = NormalizeProviderKey(providerKey)
    if not providerKey then return false end
    local selection = type(opts) == "table" and (opts.explicit or opts.allowProviderSwitch)
    if selection then NS.ClearPendingGuideSelection() end
    pendingReasonByProvider[providerKey] = type(reason) == "string" and reason
        or pendingReasonByProvider[providerKey] or "guide_signal"
    pendingOptsByProvider[providerKey] = MergeEvaluationOpts(pendingOptsByProvider[providerKey], opts)
    if selection then pendingGuideSelection = pendingOptsByProvider[providerKey] end
    local queue = evaluationQueues[providerKey]
    if not queue then
        queue = NS.Internal.Scheduling.CreateCoalescer(function()
            local signalReason = pendingReasonByProvider[providerKey] or "guide_signal"
            local signalOpts = pendingOptsByProvider[providerKey]
            pendingReasonByProvider[providerKey], pendingOptsByProvider[providerKey] = nil, nil
            EvaluateGuideProvider(providerKey, signalReason, signalOpts)
            if pendingGuideSelection == signalOpts then pendingGuideSelection = nil end
            if type(NS.HandlePendingGuideTakeoverSignal) == "function" then
                NS.HandlePendingGuideTakeoverSignal(signalReason)
            end
        end)
        evaluationQueues[providerKey] = queue
    end
    queue:Request()
    return true
end

function NS.ScheduleActiveGuidePresentationRefresh(reason, opts)
    local routing = EnsureGuideRoutingState()
    if routing.manualAuthority ~= nil or routing.pendingManualAuthority ~= nil then
        return false
    end
    if NS.GetActiveGuideRouteState() == nil then
        return false
    end
    local providerKey = NS.GetActiveGuideProvider()
    if not providerKey or GetProviderVisibility(providerKey) ~= "visible" then
        return false
    end
    opts = type(opts) == "table" and opts or {}
    opts.presentationRefresh = true
    return NS.ScheduleGuideProviderEvaluation(providerKey, reason or "guide_presentation_refresh", opts)
end

function NS.GetCurrentGuideActivationToken(providerKey)
    providerKey = NormalizeProviderKey(providerKey) or NS.GetActiveGuideProvider()
    local adapter = providers[providerKey]
    if type(adapter) == "table" and type(adapter.getActivationToken) == "function" then
        local ok, token = pcall(adapter.getActivationToken)
        if ok then
            return token
        end
    end
    return nil
end

local function DidGuideActivationTokenChange(providerKey, startToken)
    local currentToken = NS.GetCurrentGuideActivationToken(providerKey)
    if startToken == nil then
        return type(currentToken) == "string"
    end
    if type(startToken) ~= "string" then
        return false
    end
    return type(currentToken) == "string" and currentToken ~= startToken
end

local function FindVisibleProviderForTarget(fallbackTarget)
    local activeProvider = NS.GetActiveGuideProvider()
    if activeProvider and GetProviderVisibility(activeProvider) == "visible" then
        return activeProvider
    end
    for index = 1, #providerOrder do
        local providerKey = providerOrder[index]
        if GetProviderVisibility(providerKey) == "visible" then
            local target = ExtractProviderTarget(providerKey)
            if IsSameGuideRouteTarget(target, fallbackTarget) then
                return providerKey
            end
        end
    end
    for index = 1, #providerOrder do
        local providerKey = providerOrder[index]
        if GetProviderVisibility(providerKey) == "visible" then
            return providerKey
        end
    end
    return nil
end

-- ============================================================
-- Explicit guide activation
-- ============================================================

function NS.ActivateGuideProvider(providerKey, reason, opts)
    providerKey = NormalizeProviderKey(providerKey)
    if not providerKey or GetProviderVisibility(providerKey) ~= "visible" then
        return false
    end
    local target, suppressed = ExtractProviderTarget(providerKey)
    if suppressed or not IsValidTarget(target) then
        return false
    end
    opts = type(opts) == "table" and opts or {}
    opts.explicit = true
    opts.reason = reason or opts.reason or "guide_explicit_takeover"
    return NS.UpdateGuideTarget(providerKey, target, false, opts)
end

function NS.ActivateGuideQueueByID(queueID, reason)
    local providerKey = type(Queue) == "table"
        and type(Queue.GetGuideProviderFromQueueID) == "function"
        and Queue.GetGuideProviderFromQueueID(queueID)
        or nil
    providerKey = NormalizeProviderKey(providerKey)
    return providerKey and NS.ActivateGuideProvider(providerKey, reason or "queue_ui") or false
end

function NS.ActivateGuideRouteForExplicitTakeover(reason, opts)
    opts = type(opts) == "table" and opts or {}
    local providerKey = NormalizeProviderKey(opts.providerKey) or FindVisibleProviderForTarget(opts.fallbackTarget)
    if not providerKey then
        return false
    end

    if opts.requireGuideChangeOrTargetMatch == true then
        local target, suppressed = ExtractProviderTarget(providerKey)
        if suppressed or not IsValidTarget(target) then
            return false
        end
        local changed = DidGuideActivationTokenChange(providerKey, opts.startGuideStateToken)
        local matchesTarget = IsSameGuideRouteTarget(target, opts.fallbackTarget)
        if not changed and not matchesTarget then
            return false
        end
    end

    return NS.ActivateGuideProvider(providerKey, reason or "guide_explicit_takeover", opts)
end

local function InstallProviderHooks(providerKey)
    if providerStarted[providerKey] then
        return true
    end
    local adapter = providers[providerKey]
    if not ProviderIsLoaded(adapter) then
        return false
    end
    if type(adapter.installHooks) == "function" then
        local function schedule(reason, opts)
            NS.ScheduleGuideProviderEvaluation(providerKey, reason, opts)
        end
        local ok = pcall(adapter.installHooks, schedule)
        if not ok then
            return false
        end
    end
    providerStarted[providerKey] = true
    return true
end

function NS.StartGuideRoutingEvaluation()
    local routing = EnsureGuideRoutingState()
    if not NormalizeProviderKey(routing.activeGuideProvider) then
        local savedProvider = GetSavedGuideProvider()
        if savedProvider and ProviderHasGuide(savedProvider) then
            SetActiveGuideProvider(savedProvider, false)
        end
    end

    for index = 1, #providerOrder do
        local providerKey = providerOrder[index]
        if InstallProviderHooks(providerKey) then
            NS.ScheduleGuideProviderEvaluation(providerKey, "initial", { initial = true })
        end
    end
    NS.SyncGuideVisualState()
end

-- ============================================================
-- Routing core
-- ============================================================
--
-- Owns the accepted route, its current leg, and the target published to
-- TomTom and the world overlay. The planning coordinator runs backend
-- attempts. This module validates their results and commits the route.

local NS = _G.AzerothWaypointNS
local state = NS.State

local SafeCall = NS.SafeCall
local Signature = NS.Signature
local Sanctum = NS.RouteSpecials and NS.RouteSpecials.Sanctum
local ROUTE_COORD_TOLERANCE = 0.00005
local ROUTE_REPLAN_DEBOUNCE_SECONDS = 0.35
local DEFAULT_ACTION_RADIUS_YARDS = 15
local DEFAULT_MOVEMENT_RADIUS_YARDS = 55

local NOISY_ACTION_INVALIDATION_REASON = {
    SPELL_UPDATE_COOLDOWN = true,
}

local NOISY_ACTION_INVALIDATION_BACKEND = {
    dugi = true,
    polestar = true,
    mapzeroth = true,
    farstrider = true,
}

local SECURE_SPECIAL_TYPES = {
    spell = true,
    item = true,
    toy = true,
    macro = true,
    ["function"] = true,
}

local DISTANCE_ADVANCE_KIND = {
    walk = true,
    fly = true,
    movement = true,
    carrier = true,
    ["_INITIAL_STEP"] = true,
}

local RESET_LEG_ON_REPLAN_REASON = {
    environment = true,
    LOADING_SCREEN_DISABLED = true,
    NEW_WMO_CHUNK = true,
    PLAYER_CONTROL_LOST = true,
    PLAYER_CONTROL_GAINED = true,
    UNIT_ENTERING_VEHICLE = true,
    UNIT_EXITING_VEHICLE = true,
    ZONE_CHANGED = true,
    ZONE_CHANGED_INDOORS = true,
    ZONE_CHANGED_NEW_AREA = true,
}

local FORCE_ENVIRONMENT_REFRESH_REASON = {
    LOADING_SCREEN_DISABLED = true,
    PLAYER_CONTROL_LOST = true,
    PLAYER_CONTROL_GAINED = true,
    UNIT_ENTERING_VEHICLE = true,
    UNIT_EXITING_VEHICLE = true,
}

local ENVIRONMENT_REFRESH_REASON = {
    environment = true,
    NEW_WMO_CHUNK = true,
    PLAYER_CONTROL_LOST = true,
    PLAYER_CONTROL_GAINED = true,
    ZONE_CHANGED = true,
    ZONE_CHANGED_INDOORS = true,
    ZONE_CHANGED_NEW_AREA = true,
}

local ROUTE_SUCCESS_REASON = {
    polestar_plan = true,
    direct_plan = true,
    mapzeroth_plan = true,
    mapzeroth_instance_entrance_plan = true,
    mapzeroth_instance_node_plan = true,
    zygor_librover_success = true,
    farstrider_plan = true,
    farstrider_instance_entrance_plan = true,
}

local ROUTE_PLANNING_REASON = {
    dugi_planning_fallback = true,
    dugi_combat_continuity = true,
    polestar_combat_continuity = true,
    zygor_planning_fallback = true,
}

local ROUTE_FAILURE_REASON = {
    polestar_nopath_fallback = true,
    mapzeroth_missing = true,
    mapzeroth_nopath_fallback = true,
    mapzeroth_emptysteps_fallback = true,
    mapzeroth_nolegs_fallback = true,
    zygor_no_librover = true,
    zygor_queue_failed = true,
    zygor_plan_timeout = true,
    zygor_plan_timeout_fallback = true,
    zygor_librover_arrival = true,
    zygor_librover_failure = true,
    zygor_librover_failed = true,
    farstrider_missing = true,
    farstrider_nopath_fallback = true,
    farstrider_correlation_fallback = true,
}

local function GetTimeSafe()
    return type(GetTime) == "function" and GetTime() or 0
end

local function ShouldResetLegOnReplan(reason)
    return type(reason) == "string" and RESET_LEG_ON_REPLAN_REASON[reason] == true
end

local function CopyMeta(meta)
    if type(meta) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in pairs(meta) do
        copy[key] = value
    end
    return copy
end

local function BuildPlanMeta(record, reason)
    local sourceMeta = type(record) == "table" and record.meta or nil
    if type(reason) ~= "string" then
        return sourceMeta
    end

    local planMeta = CopyMeta(sourceMeta) or {}
    planMeta.replanReason = reason
    planMeta.routeInvalidated = ShouldResetLegOnReplan(reason) or nil
    return planMeta
end

-- ============================================================
-- Backend selection
-- ============================================================

local BackendCatalog = NS.Internal.RoutingBackends
local GetBackendObject = NS.GetRoutingBackend

local function ResolveEffectiveBackend(opts)
    local override = opts and opts.backendOverride
    if override then
        local b = GetBackendObject(override)
        if b and BackendCatalog.IsAvailable(override) then return b end
    end

    local db = NS.GetDB()
    local selected = db and db.routingBackend
    local b = GetBackendObject(selected)
    if b and BackendCatalog.IsAvailable(selected) then return b end

    for _, entry in ipairs(BackendCatalog.entries) do
        local fallback = GetBackendObject(entry.id)
        if fallback and BackendCatalog.IsAvailable(entry.id) then return fallback end
    end

    -- direct is the floor, should never miss, but defensive return.
    return NS.RoutingBackend_Direct
end

function NS.GetSelectedBackendID()
    local db = NS.GetDB()
    return state.routing.selectedBackend
        or (db and db.routingBackend)
        or "direct"
end

function NS.GetEffectiveBackendID()
    local record = type(NS.GetActiveAuthorityRecord) == "function" and NS.GetActiveAuthorityRecord()
    if record and record.backend then return record.backend end
    local b = ResolveEffectiveBackend()
    return b and b.id or "direct"
end

-- ============================================================
-- Route authority and destination lookup
-- ============================================================

local function ResolveAuthorityDestination(record)
    if type(record) ~= "table" then
        return nil, nil, nil, nil
    end
    if type(record.destination) == "table" then
        return record.destination.mapID, record.destination.x, record.destination.y, record.destination.title
    end
    if record.target then
        return record.target.mapID, record.target.x, record.target.y, record.target.title
    end
    return record.mapID, record.x, record.y, record.title
end

local function GetRoutableGuide()
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    local guide = NS.GetActiveGuideRouteState and NS.GetActiveGuideRouteState() or state.routing.guideRouteState
    if guide and guide.target and not guide.suppressed then return guide end
end

local function GetActiveRouteRecord()
    local routing = state.routing
    -- A pending replacement owns guidance. Its session handles changes until
    -- acceptance, the previous committed route must not progress or replan.
    if not routing or routing.pendingManualAuthority then return nil end
    if routing.manualAuthority then
        return type(routing.manualAuthority) == "table" and routing.manualAuthority or nil
    end
    return GetRoutableGuide()
end

-- ============================================================
-- Leg coordinates and travel action identity
-- ============================================================

local function IsValidLeg(leg)
    return type(leg) == "table"
        and type(leg.mapID) == "number"
        and type(leg.x) == "number"
        and type(leg.y) == "number"
end

local function GetLegSignature(leg)
    if not IsValidLeg(leg) then
        return nil
    end
    if type(Signature) == "function" then
        return Signature(leg.mapID, leg.x, leg.y)
    end
    return table.concat({ tostring(leg.mapID), tostring(leg.x), tostring(leg.y) }, ":", 1, 3)
end

local function IsSecureSpecialAction(action)
    return type(action) == "table"
        and SECURE_SPECIAL_TYPES[action.secureType] == true
        and action.securePayload ~= nil
        and action.securePayload ~= ""
end

local function IsEquipmentSpecialAction(action)
    return type(action) == "table"
        and action.executionType == "equip"
        and type(action.itemID) == "number"
        and action.itemID > 0
end

local function IsExecutableSpecialAction(action)
    return IsSecureSpecialAction(action) or IsEquipmentSpecialAction(action)
end

local function GetSpecialActionIdentity(action)
    if not IsExecutableSpecialAction(action) then
        return nil
    end
    return table.concat({
        tostring(action.semanticKind or "-"),
        tostring(action.executionType or "secure"),
        tostring(action.itemID or "-"),
        tostring(action.secureType or "-"),
        tostring(action.securePayload or "-"),
        tostring(action.destinationName or "-"),
    }, "/")
end

local function SanitizeSpecialAction(action)
    if IsExecutableSpecialAction(action) then
        return action
    end
    return nil
end


NS.GetRouteSpecialActionIdentity = GetSpecialActionIdentity

-- ============================================================
-- Travel dependencies and cooldown changes
-- ============================================================

local ROUTE_DEPENDENCY_KIND = {
    spell = true,
    item = true,
    toy = true,
}

local function CanAccessRouteValue(value)
    local isSecret = rawget(_G, "issecretvalue")
    if type(isSecret) == "function" then
        local ok, secret = pcall(isSecret, value)
        if not ok or secret == true then return false end
    end
    local canAccess = rawget(_G, "canaccessvalue")
    if type(canAccess) == "function" then
        local ok, accessible = pcall(canAccess, value)
        if not ok or accessible ~= true then return false end
    end
    return true
end

local function NormalizeRouteDependency(value)
    if type(value) ~= "table" then
        return nil
    end
    local kind = value.kind
    if not CanAccessRouteValue(kind) or type(kind) ~= "string" or not ROUTE_DEPENDENCY_KIND[kind] then
        return nil
    end
    if not CanAccessRouteValue(value.id) then return nil end
    local converted, id = pcall(tonumber, value.id)
    if not converted or not CanAccessRouteValue(id) then return nil end
    local compared, valid = pcall(function() return type(id) == "number" and id > 0 end)
    if not compared or not valid then
        return nil
    end
    return kind, id
end

local function RouteDependencyKey(kind, id)
    return tostring(kind) .. ":" .. tostring(id)
end

local function RefreshRouteTravelDependencies(record)
    if type(record) ~= "table" then return end

    local previousStates = type(record._routeTravelDependencyStates) == "table"
        and record._routeTravelDependencyStates
        or nil
    local dependencies = {}
    local states = {}
    local seen = {}
    local legs = record.legs
    local firstLeg = math.max(1, tonumber(record.currentLegIndex) or 1)

    if type(legs) == "table" then
        for index = firstLeg, #legs do
            local action = type(legs[index]) == "table" and legs[index].specialAction or nil
            local kind, id = NormalizeRouteDependency(type(action) == "table" and action.routeDependency or nil)
            if kind and id then
                local key = RouteDependencyKey(kind, id)
                if not seen[key] then
                    seen[key] = true
                    dependencies[#dependencies + 1] = { kind = kind, id = id, key = key }
                    states[key] = previousStates and previousStates[key] or "ready"
                end
            end
        end
    end

    record._routeTravelDependencies = dependencies
    record._routeTravelDependencyStates = states
end

local function ClearRouteTravelDependencies(record)
    if type(record) ~= "table" then return end
    record._routeTravelDependencies = nil
    record._routeTravelDependencyStates = nil
end

NS.ClearRouteTravelDependencies = ClearRouteTravelDependencies

local function ProbeSpellRouteDependency(spellID)
    if type(C_Spell) ~= "table" or type(C_Spell.GetSpellCooldown) ~= "function" then
        return "unknown"
    end
    local ok, cooldownInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cooldownInfo) ~= "table" then return "unknown" end
    local startTime = cooldownInfo.startTime
    local duration = cooldownInfo.duration
    if not CanAccessRouteValue(startTime) or not CanAccessRouteValue(duration) then
        return "unknown"
    end
    local compared, unavailable = pcall(function()
        return type(startTime) == "number" and type(duration) == "number"
            and startTime > 0 and duration > 1.5
    end)
    if not compared then return "unknown" end
    return unavailable and "unavailable" or "ready"
end

local function ProbeItemRouteDependency(itemID)
    local cooldownFn = type(C_Item) == "table" and C_Item.GetItemCooldown
        or rawget(_G, "GetItemCooldown")
        or nil
    if type(cooldownFn) ~= "function" then return "unknown" end
    local ok, startTime, duration = pcall(cooldownFn, itemID)
    if not ok or not CanAccessRouteValue(startTime) or not CanAccessRouteValue(duration) then
        return "unknown"
    end
    local compared, unavailable = pcall(function()
        return type(startTime) == "number" and type(duration) == "number"
            and startTime > 0 and duration > 0
    end)
    if not compared then return "unknown" end
    return unavailable and "unavailable" or "ready"
end

function NS.ProbeRouteTravelDependency(_, dependency)
    if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
        return "unknown"
    end
    if type(dependency) ~= "table" or type(dependency.id) ~= "number" then return "unknown" end
    if dependency.kind == "spell" then
        return ProbeSpellRouteDependency(dependency.id)
    end
    if dependency.kind == "item" or dependency.kind == "toy" then
        return ProbeItemRouteDependency(dependency.id)
    end
    return "unknown"
end

local function IsNoisyActionInvalidation(reason)
    return type(reason) == "string" and NOISY_ACTION_INVALIDATION_REASON[reason] == true
end

-- ============================================================
-- Route environment and zone changes
-- ============================================================

local function TrimRouteText(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

local function NormalizeZoneText(value)
    return TrimRouteText(value)
end

local function ReadRouteEnvironmentText(fn)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn)
    if not ok then
        return nil
    end
    return NormalizeZoneText(value)
end

function NS.GetRouteEnvironmentSnapshot()
    local indoors = nil
    if type(IsIndoors) == "function" and IsIndoors() then
        indoors = true
    elseif type(IsOutdoors) == "function" and IsOutdoors() then
        indoors = false
    end

    return {
        indoors = indoors,
        zone = ReadRouteEnvironmentText(GetZoneText),
        realzone = ReadRouteEnvironmentText(GetRealZoneText),
        subzone = ReadRouteEnvironmentText(GetSubZoneText),
        minizone = ReadRouteEnvironmentText(GetMinimapZoneText),
    }
end

local function RouteEnvironmentFingerprint(env)
    return table.concat({
        tostring(env.mapID or "-"),
        tostring(env.indoors),
        tostring(env.zone or "-"),
        tostring(env.realzone or "-"),
        tostring(env.subzone or "-"),
        tostring(env.minizone or "-"),
    }, "|")
end

local function RememberRouteEnvironment()
    local current = NS.GetRouteEnvironmentSnapshot()
    current.mapID = NS.GetPlayerMapID and NS.GetPlayerMapID()
    local fingerprint = RouteEnvironmentFingerprint(current)
    state.routing._routeEnvironmentSnapshot = current
    state.routing._routeEnvironmentFingerprint = fingerprint
    return current, fingerprint
end

local function ShouldRefreshForEnvironment(reason)
    local previous = state.routing._routeEnvironmentFingerprint
    local last = state.routing._routeEnvironmentSnapshot
    local current, fingerprint = RememberRouteEnvironment()

    if type(reason) == "string" and FORCE_ENVIRONMENT_REFRESH_REASON[reason] then
        return true
    end
    if type(reason) == "string" and not ENVIRONMENT_REFRESH_REASON[reason] then
        return true
    end

    if previous == fingerprint then return false end
    if reason == "ZONE_CHANGED" and last and last.indoors == false and current.indoors == false
        and current.mapID and current.mapID == last.mapID and current.zone == last.zone
        and current.realzone == last.realzone then
        local record = GetActiveRouteRecord()
        local backend = record and GetBackendObject(record.backend)
        if backend and backend.CanRetainOutdoorWalk and backend.CanRetainOutdoorWalk(record) then return false end
    end
    return true
end

-- ============================================================
-- Route outcomes and failure reporting
-- ============================================================

local function IsStrictRouteRecord(record)
    if type(record) ~= "table" then
        return false
    end
    if record.strictRouteSuccess == true or record._coreStrictRouteSuccess == true then
        return true
    end
    local queueTransaction = record._corePendingQueueTransaction
    if type(queueTransaction) == "table" and queueTransaction.strictRouteSuccess == true then
        return true
    end
    return false
end

local function IsFallbackRouteReason(reason)
    if type(reason) ~= "string" then
        return false
    end
    if ROUTE_FAILURE_REASON[reason] then
        return true
    end
    return reason:find("_fallback$", 1, false) ~= nil
end

local function IsFailedRouteReason(reason)
    if type(reason) ~= "string" then
        return false
    end
    if ROUTE_FAILURE_REASON[reason] then
        return true
    end
    return reason:find("failure", 1, true) ~= nil
        or reason:find("failed", 1, true) ~= nil
        or reason:find("timeout", 1, true) ~= nil
        or reason:find("nopath", 1, true) ~= nil
        or reason:find("emptysteps", 1, true) ~= nil
        or reason:find("nolegs", 1, true) ~= nil
end

local function ClassifyRouteOutcome(record, backendID, legs, reason)
    if type(record) == "table" and record._coreRouteOutcomeHint == "planning" then
        return "planning"
    end
    if ROUTE_PLANNING_REASON[reason] then
        return "planning"
    end
    if ROUTE_SUCCESS_REASON[reason] then
        return "success"
    end
    if IsFallbackRouteReason(reason) then
        return "fallback"
    end
    if IsFailedRouteReason(reason) then
        return "failed"
    end
    if type(legs) == "table" and #legs > 0 then
        return "success"
    end
    if backendID == "direct" then
        return "success"
    end
    return IsStrictRouteRecord(record) and "failed" or "fallback"
end

local function MarkRouteOutcome(record, outcome, reason)
    if type(record) ~= "table" then
        return
    end
    record.routeOutcome = outcome
    record.routeOutcomeReason = reason
    record.routeOutcomeAt = GetTimeSafe()
end

local function ResolveRouteFailureTitle(record)
    if type(record) ~= "table" then
        return "destination"
    end
    local _, _, _, title = ResolveAuthorityDestination(record)
    return TrimRouteText(title) or "destination"
end

local function ReportStrictRouteFailure(record, reason)
    if type(record) ~= "table" then
        return
    end
    local title = ResolveRouteFailureTitle(record)
    local key = table.concat({
        tostring(record._corePendingRouteSerial or "-"),
        tostring(record.backend or "-"),
        tostring(reason or "-"),
        tostring(title),
    }, "\031", 1, 4)
    if record._coreLastStrictFailureMessageKey == key then
        return
    end
    record._coreLastStrictFailureMessageKey = key
    if type(NS.Msg) == "function" then
        local routing = record.backendOverride and BackendCatalog.Label(record.backendOverride) .. " routing" or
            "Routing"
        NS.Msg(string.format("%s failed: no route found to %s.", routing, title))
    end
end

-- ============================================================
-- Pending manual route handoff
-- ============================================================

-- A ready pending route can supply guidance while the previous queue is
-- still saved. Only an accepted result commits the queue transaction.
-- Cancellation or a failed result releases the pending route.

local function IsPendingManualRouteRecord(record)
    return type(record) == "table" and record._corePendingManualRoute == true
end

local function ClearPendingManualRoute(record, replacement)
    if type(record) ~= "table" then
        return
    end
    if state.routing.pendingManualAuthority == record then
        NS.SetPendingManualAuthority(replacement)
    end
    record._corePendingManualRoute = nil
    record._corePendingRouteSerial = nil
end

local function CancelPendingManualRoute(reason, replacement)
    local pending = state.routing.pendingManualAuthority
    if type(pending) ~= "table" then
        return false
    end
    if type(NS.RollbackPendingManualQueueTransaction) == "function" then
        NS.RollbackPendingManualQueueTransaction(pending, "cancelled", reason or "superseded")
    end
    if pending._routePlanning then NS.CancelRoutePlanning(pending) end
    ClearPendingManualRoute(pending, replacement)
    local native = NS.Internal and NS.Internal.NativeMapWaypoints
    if native then native.Retire(pending) end
    pending._coreStrictRouteCompleted = true
    pending._coreStrictRouteSucceeded = false
    pending._coreRoutePending = nil
    pending._corePlanning = nil
    return true
end

function NS.CancelPendingManualRoute(reason)
    return CancelPendingManualRoute(reason)
end

local function CompletePendingManualRoute(record, outcome, reason)
    if not IsPendingManualRouteRecord(record) then
        return nil
    end

    local routing = state.routing
    if routing.pendingManualAuthority ~= record
        or routing._pendingManualRouteSerial ~= record._corePendingRouteSerial
    then
        return false
    end

    if outcome == "planning" then
        return nil
    end

    if outcome ~= "success" and outcome ~= "fallback" then
        if type(NS.RollbackPendingManualQueueTransaction) == "function" then
            NS.RollbackPendingManualQueueTransaction(record, outcome, reason)
        end
        ReportStrictRouteFailure(record, reason)
        ClearPendingManualRoute(record)
        local native = NS.Internal and NS.Internal.NativeMapWaypoints
        if native then native.Retire(record) end
        record._coreRoutePending = nil
        record._corePlanning = nil
        record._coreStrictRouteCompleted = true
        record._coreStrictRouteSucceeded = false
        return false
    end

    if type(NS.CommitPendingManualQueueTransaction) == "function"
        and NS.CommitPendingManualQueueTransaction(record) == false
    then
        CancelPendingManualRoute("queue_changed")
        return false
    end
    record._coreStrictRouteCompleted = true
    record._coreStrictRouteSucceeded = true
    local committed = NS.CommitManualAuthority(record)
    ClearPendingManualRoute(record)
    return committed
end

-- ============================================================
-- Arrival gates and matching legs
-- ============================================================

local function GateTextMatches(expected, actual)
    expected = NormalizeZoneText(expected)
    if not expected then
        return true
    end
    return expected == NormalizeZoneText(actual)
end

local function ArrivalGateMatches(leg)
    if leg and (leg.sanctumContinuation
            or leg.sanctumDestination and not Sanctum.AtDestination(leg.sanctumDestination)) then
        return false
    end
    local gate = type(leg) == "table" and leg.arrivalGate or nil
    if type(gate) ~= "table" then
        return true
    end

    local env = NS.GetRouteEnvironmentSnapshot()
    if gate.indoors ~= nil and env.indoors ~= nil and gate.indoors ~= env.indoors then
        return false
    end
    if gate.indoors == true and env.indoors ~= true then
        return false
    end
    if not GateTextMatches(gate.zone, env.zone) then
        return false
    end
    if not GateTextMatches(gate.realzone, env.realzone) then
        return false
    end
    if not GateTextMatches(gate.subzone, env.subzone) then
        return false
    end
    if not GateTextMatches(gate.minizone, env.minizone) then
        return false
    end

    return true
end

NS.RouteArrivalGateMatches = ArrivalGateMatches

local function FindMatchingLegIndex(legs, previousLeg)
    local previousSig = GetLegSignature(previousLeg)
    if type(previousSig) ~= "string" or type(legs) ~= "table" then
        return nil
    end
    for index = 1, #legs do
        if GetLegSignature(legs[index]) == previousSig then
            -- A matching endpoint does not establish that the incoming
            -- walking section is unchanged. Preserving it can jump over
            -- freshly inserted road/terrain legs after a preference change.
            if previousLeg.routeGeometryKey ~= legs[index].routeGeometryKey
                and (previousLeg.routeGeometryKey or legs[index].routeGeometryKey) then
                return nil
            end
            -- Do not let a temporary direct/fallback destination leg skip a
            -- newly available route plan. This was the failure mode where a
            -- guide target first planned as one final destination, then a
            -- backend returned carrier legs, and the core jumped straight to
            -- the matching final destination coordinate.
            if previousLeg.routeLegKind == "destination" then
                for prior = 1, index - 1 do
                    local leg = legs[prior]
                    if IsValidLeg(leg) and leg.routeLegKind == "carrier" then
                        return nil
                    end
                end
            end
            return index
        end
    end
    return nil
end

local function FindMatchingSpecialActionLegIndex(legs, previousLeg)
    if type(legs) ~= "table" or not IsValidLeg(previousLeg) then
        return nil
    end
    local previousActionIdentity = GetSpecialActionIdentity(previousLeg.specialAction)
    if type(previousActionIdentity) ~= "string" then
        return nil
    end
    for index = 1, #legs do
        local leg = legs[index]
        if IsValidLeg(leg)
            and ArrivalGateMatches(leg)
            and GetSpecialActionIdentity(leg.specialAction) == previousActionIdentity
        then
            return index
        end
    end
    return nil
end

local function PreservePreviousSpecialActionLeg(legs, previousLeg)
    if type(legs) ~= "table" or not IsValidLeg(previousLeg) then
        return nil
    end
    if type(GetSpecialActionIdentity(previousLeg.specialAction)) ~= "string" then
        return nil
    end
    if FindMatchingSpecialActionLegIndex(legs, previousLeg) then
        return nil
    end

    local previousSig = GetLegSignature(previousLeg)
    if type(previousSig) ~= "string" then
        return nil
    end

    for index = 1, #legs do
        local leg = legs[index]
        if IsValidLeg(leg)
            and GetLegSignature(leg) == previousSig
            and ArrivalGateMatches(leg)
            and not IsExecutableSpecialAction(leg.specialAction)
        then
            leg.specialAction = previousLeg.specialAction
            leg.activationCoords = leg.activationCoords or previousLeg.activationCoords
            leg.kind = previousLeg.kind or leg.kind
            leg.routeTravelType = previousLeg.routeTravelType or leg.routeTravelType
            leg.arrivalRadius = previousLeg.arrivalRadius or leg.arrivalRadius
            leg.title = previousLeg.title or leg.title
            leg._corePreservedSpecialAction = true
            return index
        end
    end

    return nil
end

-- ============================================================
-- Fallback legs and plan normalization
-- ============================================================

local function MakeFallbackLeg(record)
    local mapID, x, y, title = ResolveAuthorityDestination(record)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    return NS.RouteSpecials.MakeDestinationLeg(record and record.backend or "direct", mapID, x, y, title)
end

local function MakeDirectDestinationLeg(record, backendID)
    local leg = MakeFallbackLeg(record)
    if type(leg) ~= "table" then
        return nil
    end
    leg.source = backendID or record and record.backend or leg.source
    return leg
end

local NON_COLLAPSIBLE_ROUTE_TRAVEL_TYPE = {
    taxi = true,
    dungeon = true,
    raid = true,
    delve = true,
    bountiful_delve = true,
}

local function IsInstanceRouteReason(reason)
    return type(reason) == "string" and reason:find("instance", 1, true) ~= nil
end

local function LegRequiresHardTransition(leg)
    if type(leg) ~= "table" then
        return false
    end
    if IsEquipmentSpecialAction(leg.specialAction) then
        return true
    end
    if leg.sanctumCrossing or type(leg.arrivalGate) == "table" or leg.leaveInstanceMapID or leg.transportDestination then
        return true
    end
    if leg.kind == "entrance" then
        return true
    end
    return NON_COLLAPSIBLE_ROUTE_TRAVEL_TYPE[leg.routeTravelType] == true
end

local function PlanRequiresHardTransition(legs)
    if type(legs) ~= "table" then
        return false
    end
    for index = 1, #legs do
        if LegRequiresHardTransition(legs[index]) then
            return true
        end
    end
    return false
end

local function LegRequiresExplicitTransition(leg)
    return LegRequiresHardTransition(leg) or IsExecutableSpecialAction(type(leg) == "table" and leg.specialAction or nil)
end

local function PlanRequiresExplicitTransition(legs)
    if type(legs) ~= "table" then
        return false
    end
    for index = 1, #legs do
        if LegRequiresExplicitTransition(legs[index]) then
            return true
        end
    end
    return false
end

local function CurrentMapRouteContext(record)
    local targetMapID, targetX, targetY = ResolveAuthorityDestination(record)
    if type(targetMapID) ~= "number" or type(targetX) ~= "number" or type(targetY) ~= "number" then
        return nil
    end

    local playerMapID = type(NS.GetPlayerMapID) == "function" and NS.GetPlayerMapID() or nil
    if playerMapID ~= targetMapID then
        return nil
    end
    return targetMapID
end

local function FindFirstOffTargetMapLegIndex(legs, targetMapID)
    if type(legs) ~= "table" or type(targetMapID) ~= "number" then
        return nil
    end
    for index = 1, #legs do
        local leg = legs[index]
        if IsValidLeg(leg) and leg.mapID ~= targetMapID then
            return index
        end
    end
    return nil
end

local function ShouldCollapseCurrentMapSetupRoute(record, legs, reason)
    if type(record) ~= "table" or type(legs) ~= "table" or #legs == 0 then
        return false
    end
    local firstLeg = legs[1]
    if type(firstLeg) ~= "table" or firstLeg.routeLegKind ~= "carrier" then
        return false
    end

    local targetMapID = CurrentMapRouteContext(record)
    if type(targetMapID) ~= "number" then
        return false
    end
    if IsInstanceRouteReason(reason) then
        return false
    end

    -- Current-map plans that leave the target map are backend detours. Only
    -- the first presented local leg can block collapse, later off-map gates
    -- belong to the detour we are intentionally discarding.
    if FindFirstOffTargetMapLegIndex(legs, targetMapID) then
        return not LegRequiresHardTransition(firstLeg)
    end

    if PlanRequiresHardTransition(legs) then
        return false
    end
    if record.type == "manual" then
        return true
    end

    return not PlanRequiresExplicitTransition(legs)
end

local function NormalizeAcceptedLegs(record, backendID, legs, reason)
    local backend = GetBackendObject(backendID)
    if backend and backend.preserveItinerary then return legs end
    for _, leg in ipairs(legs) do
        if leg.fixedWalkingGeometry or leg.sanctumCrossing then return legs end
    end
    if ShouldCollapseCurrentMapSetupRoute(record, legs, reason) then
        local directLeg = MakeDirectDestinationLeg(record, backendID)
        if directLeg then
            return { directLeg }
        end
    end
    return legs
end

local function ClearRecordPlan(record, reason)
    if type(record) ~= "table" then
        return
    end
    NS.Internal.RouteWalking.Forget(record)
    if record._routePlanning then NS.CancelRoutePlanning(record) end
    record._routePlanningResume = nil
    if type(NS.CancelRouteEquipmentTransaction) == "function" then
        NS.CancelRouteEquipmentTransaction(record, reason or "clear_record_plan")
    end
    ClearRouteTravelDependencies(record)
    NS.CancelRouteBackendStateValidations(record.backend, record)
    record.replanReason = nil
    record.legs = nil
    record.currentLegIndex = nil
    record.currentLeg = nil
    record.specialAction = nil
    record._corePlanning = nil
    record._coreRoutePending = nil
    record.planFingerprint = nil
    record.hasSanctumCrossing = nil
    record._routeBackendStateFingerprint = nil
    record.lastPlanSkippedAt = nil
    record.lastPlanSkipReason = nil
    record.lastPlanSkipStatus = nil
    record.lastPlanSkippedFingerprint = nil
    record.routeOutcome = nil
    record.routeOutcomeReason = nil
    record.routeOutcomeAt = nil
end

NS.ClearAcceptedRoutePlan = ClearRecordPlan

-- ============================================================
-- Destination signatures and plan fingerprints
-- ============================================================

local function FormatPlanCoord(value)
    if type(value) == "number" then
        return string.format("%.5f", value)
    end
    return "-"
end

local function BuildValidationDestinationSignature(record)
    local mapID, x, y, title = ResolveAuthorityDestination(record)
    return table.concat({
        tostring(mapID or "-"),
        FormatPlanCoord(x),
        FormatPlanCoord(y),
        tostring(title or "-"),
        tostring(record and record.sig or "-"),
    }, "/")
end

local function BuildAuthorityTargetSignature(mapID, x, y, title, guideTarget)
    return table.concat({
        tostring(mapID or "-"),
        FormatPlanCoord(x),
        FormatPlanCoord(y),
        tostring(title or "-"),
        tostring(type(guideTarget) == "table" and guideTarget.guideProvider or "-"),
        tostring(type(guideTarget) == "table" and guideTarget.rawTitle or "-"),
        tostring(type(guideTarget) == "table" and guideTarget.guideStepIdentity or "-"),
        tostring(type(guideTarget) == "table" and guideTarget.source or "-"),
    }, "|")
end

local function FingerprintGate(gate)
    if type(gate) ~= "table" then
        return "-"
    end
    return table.concat({
        tostring(gate.indoors),
        tostring(NormalizeZoneText(gate.zone) or "-"),
        tostring(NormalizeZoneText(gate.realzone) or "-"),
        tostring(NormalizeZoneText(gate.subzone) or "-"),
        tostring(NormalizeZoneText(gate.minizone) or "-"),
    }, "/")
end

local function FingerprintCoords(coords)
    if type(coords) ~= "table" then
        return "-"
    end
    return table.concat({
        tostring(coords.mapID or "-"),
        FormatPlanCoord(coords.x),
        FormatPlanCoord(coords.y),
    }, "/")
end

local function FingerprintSpecialAction(action)
    if type(action) ~= "table" then
        return "-"
    end
    local dependencyKind, dependencyID = NormalizeRouteDependency(action.routeDependency)
    return table.concat({
        tostring(action.semanticKind or "-"),
        tostring(action.executionType or "-"),
        tostring(action.itemID or "-"),
        tostring(action.secureType or "-"),
        tostring(action.securePayload or "-"),
        tostring(action.destinationName or "-"),
        tostring(action.activationMode or "-"),
        FingerprintCoords(action.activationCoords),
        tostring(dependencyKind or "-"),
        tostring(dependencyID or "-"),
    }, "/")
end

local function FingerprintTaxi(taxi)
    if type(taxi) ~= "table" then
        return "-"
    end
    return table.concat({
        tostring(taxi.sourceNodeID or "-"),
        tostring(taxi.nodeID or "-"),
        tostring(taxi.operator or "-"),
        tostring(taxi.final == true),
        FingerprintCoords(taxi.destination),
        FingerprintCoords(taxi.departure),
        tostring(taxi.name or "-"),
        tostring(taxi.offerSerial or "-"),
        tostring(taxi.offerMap or "-"),
        tostring(taxi.offerSource or "-"),
    }, "/")
end

local function FingerprintLeg(leg)
    if type(leg) ~= "table" then
        return "-"
    end
    local parts = {
        tostring(leg.mapID or "-"),
        FormatPlanCoord(leg.x),
        FormatPlanCoord(leg.y),
        tostring(leg.title or "-"),
        tostring(leg.source or "-"),
        tostring(leg.kind or "-"),
        tostring(leg.routeLegKind or "-"),
        tostring(leg.routeTravelType or "-"),
        tostring(leg.arrivalRadius or "-"),
        tostring(leg.navigationHeight), tostring(leg.navigationContinent),
        FingerprintCoords(leg.activationCoords),
        FingerprintGate(leg.arrivalGate),
        tostring(leg.leaveInstanceMapID or "-"),
        FingerprintCoords(leg.transportDestination),
        FingerprintSpecialAction(leg.specialAction),
        FingerprintTaxi(leg.taxi),
        tostring(leg.routeGeometryKey or "-"),
        tostring(leg.preservePlanOnArrival == true),
    }
    if leg.sanctumCrossing then
        parts[#parts + 1] = leg.sanctumCrossing.id
        parts[#parts + 1] = leg.sanctumResume and "resume" or "continue"
    end
    if leg.sanctumDestination then parts[#parts + 1] = leg.sanctumDestination end
    if leg.sanctumContinuation then parts[#parts + 1] = "sanctum_pending" end
    return table.concat(parts, ":")
end

local function BuildPlanFingerprint(record, backendID, legs)
    local mapID, x, y, title = ResolveAuthorityDestination(record)
    local parts = {
        tostring(backendID or record and record.backend or "-"),
        tostring(mapID or "-"),
        FormatPlanCoord(x),
        FormatPlanCoord(y),
        tostring(title or "-"),
        tostring(type(legs) == "table" and #legs or 0),
    }
    if type(legs) == "table" then
        for index = 1, #legs do
            parts[#parts + 1] = tostring(index) .. "=" .. FingerprintLeg(legs[index])
        end
    end
    return table.concat(parts, "|")
end

-- ============================================================
-- Accepting backend plans
-- ============================================================

function NS.AcceptBackendPlan(record, backendID, legs, reason, serial, install)
    if type(record) ~= "table" then
        return false
    end

    local acceptedLegs = type(legs) == "table" and legs or nil
    if type(acceptedLegs) ~= "table" or #acceptedLegs == 0 then
        local fallback = MakeFallbackLeg(record)
        acceptedLegs = fallback and { fallback } or nil
    end
    acceptedLegs = NormalizeAcceptedLegs(record, backendID, acceptedLegs, reason)
    if type(acceptedLegs) ~= "table" or #acceptedLegs == 0 then
        return false
    end

    if record.authority == "guide" and record.target then
        for _, leg in ipairs(acceptedLegs) do
            NS.ApplyGuideDestinationPresentation(leg, record.target)
        end
    end

    local outcome = ClassifyRouteOutcome(record, backendID, acceptedLegs, reason)
    MarkRouteOutcome(record, outcome, reason)
    if outcome == "failed" and IsStrictRouteRecord(record) then
        record.backend = backendID or record.backend
        record.planSerial = serial or record.planSerial
        record.replanReason = reason
        record.planAcceptStatus = "failed"
        record._corePlanning = nil
        record._coreRoutePending = nil
        record._coreResetLegOnNextPlan = nil
        record.lastPlanSkipStatus = nil
        CompletePendingManualRoute(record, outcome, reason)
        return false
    end

    local firstCrossing
    if Sanctum then
        for index, leg in ipairs(acceptedLegs) do
            if leg.sanctumCrossing then
                firstCrossing = index; break
            end
        end
    end
    local final = acceptedLegs[#acceptedLegs]
    local previousLeg = record.currentLeg
    local resetLeg = record._coreResetLegOnNextPlan == true
    local preservedActionLegIndex = nil
    if not resetLeg
        and NOISY_ACTION_INVALIDATION_BACKEND[backendID or record.backend] == true
        and IsNoisyActionInvalidation(record._coreLastRefreshReason)
    then
        preservedActionLegIndex = PreservePreviousSpecialActionLeg(acceptedLegs, previousLeg)
    end
    local planFingerprint = BuildPlanFingerprint(record, backendID, acceptedLegs)
    local equivalentPlan = type(record.planFingerprint) == "string"
        and record.planFingerprint == planFingerprint
    local currentGateMismatch = equivalentPlan
        and not resetLeg
        and type(record.legs) == "table"
        and type(record.currentLegIndex) == "number"
        and not ArrivalGateMatches(record.legs[record.currentLegIndex])

    record.backend = backendID or record.backend
    record.planSerial = serial or record.planSerial
    record.replanReason = reason
    record._corePlanning = nil
    record._coreRoutePending = nil
    if equivalentPlan and not resetLeg and not currentGateMismatch then
        local churn = state.churn
        if churn and churn.active then
            churn.routePlanSkip = (churn.routePlanSkip or 0) + 1
        end
        record.lastPlanSkippedAt = GetTimeSafe()
        record.lastPlanSkipReason = reason
        record.lastPlanSkipStatus = "equivalent"
        record.lastPlanSkippedFingerprint = planFingerprint
        record._coreResetLegOnNextPlan = nil
        MarkRouteOutcome(record, outcome, reason)
        if install then install(record) end
        CompletePendingManualRoute(record, outcome, reason)
        if record.authority == "guide" and type(NS.SyncGuideQueueProjection) == "function" then
            SafeCall(NS.SyncGuideQueueProjection, record)
        end
        RememberRouteEnvironment()
        return true
    end

    record.backend = backendID or record.backend
    NS.Internal.RouteWalking.Forget(record)
    record.legs = acceptedLegs
    record.hasSanctumCrossing = firstCrossing ~= nil or final.sanctumDestination ~= nil or nil
    record.planSerial = serial or record.planSerial
    record.planFingerprint = planFingerprint
    record._routeAcceptedPlanGeneration = (tonumber(record._routeAcceptedPlanGeneration) or 0) + 1
    record.planAcceptedAt = GetTimeSafe()
    local churn = state.churn
    if churn and churn.active then
        churn.routePlanAccept = (churn.routePlanAccept or 0) + 1
    end
    record.planAcceptStatus = currentGateMismatch and "equivalent_gate_reset"
        or (equivalentPlan and "equivalent_reset" or "accepted")
    record.lastPlanSkipStatus = nil
    record.replanReason = reason
    if resetLeg then
        record.currentLegIndex = nil
    else
        record.currentLegIndex = preservedActionLegIndex
            or FindMatchingSpecialActionLegIndex(acceptedLegs, previousLeg)
            or FindMatchingLegIndex(acceptedLegs, previousLeg)
    end
    if firstCrossing and record.currentLegIndex and record.currentLegIndex > firstCrossing
        and not Sanctum.HasArrived(acceptedLegs[firstCrossing].sanctumCrossing) then
        record.currentLegIndex = nil
    end
    -- Gate regression safety: FindMatchingLegIndex may preserve a leg whose
    -- arrival gate the player no longer satisfies (e.g. matched a portal leg
    -- that requires being indoors, but player is now outside). Reset to leg 1
    -- so the route guides the player back to the required conditions.
    if not resetLeg and record.currentLegIndex then
        if not ArrivalGateMatches(acceptedLegs[record.currentLegIndex]) then
            record.currentLegIndex = nil
        end
    end
    if install then install(record) end
    if type(NS.SyncRouteEquipmentTransaction) == "function" then
        local retainedLeg = record.currentLegIndex and acceptedLegs[record.currentLegIndex] or nil
        NS.SyncRouteEquipmentTransaction(record, retainedLeg and retainedLeg.specialAction or nil)
    end
    RefreshRouteTravelDependencies(record)
    record.currentLeg = nil
    record.specialAction = nil
    record._corePlanning = nil
    record._coreResetLegOnNextPlan = nil
    record._coreLastPlayerMapID = type(NS.GetPlayerMapID) == "function" and NS.GetPlayerMapID() or nil
    MarkRouteOutcome(record, outcome, reason)
    CompletePendingManualRoute(record, outcome, reason)
    if record.authority == "guide" and type(NS.SyncGuideQueueProjection) == "function" then
        SafeCall(NS.SyncGuideQueueProjection, record)
    end
    RememberRouteEnvironment()
    return true
end

local function IsRouteActionTransactionLocked()
    return state.routing.specialActionCasting == true
        or (type(NS.IsRouteEquipmentTransactionActive) == "function" and NS.IsRouteEquipmentTransactionActive())
end

NS.RoutePlanningCore = {
    GetActiveRecord = GetActiveRouteRecord,
    GetTime = GetTimeSafe,
    GetValidationDestinationSignature = BuildValidationDestinationSignature,
    IsActionTransactionLocked = IsRouteActionTransactionLocked,
    DependencyKey = RouteDependencyKey,
    GetDestination = ResolveAuthorityDestination,
    IsValidLeg = IsValidLeg,
    CompletePendingManualRoute = CompletePendingManualRoute,
}

-- ============================================================
-- Switching the routing backend
-- ============================================================

-- Switch backend live. Tears down old backend's state, switches the DB
-- key, re-plans whichever authority is active, and recomputes.
function NS.SetBackend(newID)
    local db = NS.GetDB()
    if not db then return false end
    if not GetBackendObject(newID) then
        return false
    end

    CancelPendingManualRoute("backend_change")
    local function clear(record)
        if not record then return end
        local old = GetBackendObject(record.backend)
        if old and old.Clear then old.Clear(record, "backend_change") else ClearRecordPlan(record, "backend_change") end
    end
    clear(state.routing.manualAuthority)
    if state.routing.guideRouteStates then
        for _, record in pairs(state.routing.guideRouteStates) do clear(record) end
    else
        clear(state.routing.guideRouteState)
    end
    db.routingBackend, state.routing.selectedBackend = newID, newID
    local active = NS.GetActiveAuthorityRecord()
    if active then NS.RequestRoutePlan(active, newID, active.meta, "initial") end

    NS.RecomputeCarrier()
    return true
end

-- ============================================================
-- Routing requests
-- ============================================================

function NS.RouteViaBackend(mapID, x, y, title, meta, opts)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    if NS.IsRoutingEnabled and NS.IsRoutingEnabled() == false then return false end

    local authority = opts and opts.authority or "manual"
    local explicitBackend = authority == "manual" and NS.GetRouteBackendOverride(meta)
    local preferred = explicitBackend or opts and opts.backendOverride or NS.GetSelectedBackendID()
    local backend = GetBackendObject(preferred)
    if not backend then return false end

    if authority == "manual" and NS.Internal.ServiceSearch then NS.Internal.ServiceSearch.Cancel() end

    if authority == "manual"
        and not (type(opts) == "table" and type(opts.queueContext) == "table")
        and type(NS.HandleManualQueueRoutingPolicy) == "function"
        and NS.HandleManualQueueRoutingPolicy(mapID, x, y, title, meta, opts)
    then
        return true
    end

    if authority == "guide" then
        local guideTarget = opts and opts.guideTarget or nil
        local providerKey = type(opts) == "table" and type(opts.guideProvider) == "string" and opts.guideProvider
            or type(guideTarget) == "table" and guideTarget.guideProvider
            or type(NS.GetActiveGuideProvider) == "function" and NS.GetActiveGuideProvider()
            or "zygor"
        providerKey = tostring(providerKey):lower()
        state.routing.guideRouteStates = state.routing.guideRouteStates or {}
        local gs = state.routing.guideRouteStates[providerKey] or {}
        local targetSig = BuildAuthorityTargetSignature(mapID, x, y, title, guideTarget)
        if gs._coreTargetSignature ~= targetSig then
            ClearRecordPlan(gs)
            gs._coreTargetSignature = targetSig
        end
        NS.SetGuideRouteTarget(gs, type(guideTarget) == "table" and guideTarget or {}, providerKey, mapID, x, y, title)
        gs.suppressed                               = false
        gs.authority                                = "guide"
        state.routing.guideRouteStates[providerKey] = gs
        state.routing.activeGuideProvider           = providerKey
        if type(NS.SetActiveRouteSource) == "function" then
            NS.SetActiveRouteSource("guide")
        end
        state.routing.guideRouteState = gs
        NS.RequestRoutePlan(gs, preferred, meta, "initial")
    else
        local queueContext = nil
        local queueTransaction = nil
        if type(NS.PrepareManualQueueRouteRequest) == "function" then
            queueContext, meta, queueTransaction = NS.PrepareManualQueueRouteRequest(mapID, x, y, title, meta, opts or {})
        end
        local record = NS.BuildManualAuthorityRecord(mapID, x, y, title, meta, backend.id)
        if not record then return false end
        if NS.ClearPendingGuideSelection then NS.ClearPendingGuideSelection() end
        record._nativeMapWaypoint = opts and opts.nativeMapWaypoint
        if type(queueContext) == "table" then
            record.queueID = queueContext.queueID
            record.queueKind = queueContext.queueKind
            record.queueSourceType = queueContext.queueSourceType
            record.queueItemIndex = queueContext.queueItemIndex
            record.queueIsTransient = queueContext.queueIsTransient == true or nil
        end
        local strictRouteSuccess = record.backendOverride ~= nil
            or type(opts) == "table" and opts.strictRouteSuccess == true
            or type(queueContext) == "table" and queueContext.strictRouteSuccess == true
            or type(queueTransaction) == "table" and queueTransaction.strictRouteSuccess == true
        if strictRouteSuccess then
            local routing = state.routing
            routing._pendingManualRouteSerial = (tonumber(routing._pendingManualRouteSerial) or 0) + 1
            record.strictRouteSuccess = true
            record._coreStrictRouteSuccess = true
            record._corePendingManualRoute = true
            record._corePendingRouteSerial = routing._pendingManualRouteSerial
            record._corePendingQueueTransaction = queueTransaction
            if not CancelPendingManualRoute("superseded", record) then NS.SetPendingManualAuthority(record) end
            NS.RequestRoutePlan(record, preferred, meta, "initial")
            if record._corePendingManualRoute == true
                and record._coreRoutePending ~= true
                and record.routeOutcome == nil
            then
                MarkRouteOutcome(record, "failed", "backend_no_plan")
                CompletePendingManualRoute(record, "failed", "backend_no_plan")
            end
            NS.RecomputeCarrier()
            return record._coreStrictRouteSucceeded == true or record._corePendingManualRoute == true
        end

        CancelPendingManualRoute("manual_route")
        NS.RequestRoutePlan(record, preferred, meta, "initial")
        if type(NS.CommitManualAuthority) == "function" then
            NS.CommitManualAuthority(record)
        end
    end

    NS.RecomputeCarrier()
    return true
end

-- ============================================================
-- Choosing which route to display
-- ============================================================

-- A pending manual route can take over once it has legs to show. While it
-- is still planning, a committed manual route can remain visible, but a
-- guide cannot take over. Without manual input, show the visible guide.

local function IsPresentablePendingManualAuthority(record)
    return type(record) == "table"
        and type(record.legs) == "table"
        and #record.legs > 0
        and record._coreStrictRouteCompleted ~= true
end

local function ArbitrateAuthority()
    local routing = state.routing
    local pending = routing.pendingManualAuthority
    if IsPresentablePendingManualAuthority(pending) then
        return pending, "manual"
    end
    if routing.manualAuthority then
        return routing.manualAuthority, "manual"
    end
    if pending then
        return nil, nil
    end
    local gs = GetRoutableGuide()
    if gs and type(NS.GetGuideVisibilityState) == "function"
        and NS.GetGuideVisibilityState(gs.guideProvider) == "visible"
    then
        return gs, "guide"
    end
    return nil, nil
end

function NS.GetActiveAuthorityRecord()
    return ArbitrateAuthority()
end

local function IsSameRouteCoord(aMapID, aX, aY, bMapID, bX, bY)
    return type(aMapID) == "number"
        and type(aX) == "number"
        and type(aY) == "number"
        and type(bMapID) == "number"
        and type(bX) == "number"
        and type(bY) == "number"
        and aMapID == bMapID
        and math.abs(aX - bX) <= ROUTE_COORD_TOLERANCE
        and math.abs(aY - bY) <= ROUTE_COORD_TOLERANCE
end

-- ============================================================
-- Active leg transitions and arrival
-- ============================================================

local function SetCoreLegIndex(record, index, reason)
    if type(record) ~= "table" or type(record.legs) ~= "table" or not IsValidLeg(record.legs[index]) then
        return false
    end

    local previousIndex = tonumber(record.currentLegIndex)
    if record.hasSanctumCrossing and previousIndex and index > previousIndex then
        for i = previousIndex, index - 1 do
            if record.legs[i].sanctumCrossing and (reason ~= "sanctum_crossed" or i ~= previousIndex) then
                return false
            end
        end
    end
    local previousLeg = record.currentLeg
    local leg = record.legs[index]
    record.currentLegIndex = index
    record.currentLeg = leg
    record.specialAction = SanitizeSpecialAction(leg.specialAction)
    RefreshRouteTravelDependencies(record)
    if type(NS.SyncRouteEquipmentTransaction) == "function" then
        NS.SyncRouteEquipmentTransaction(record, record.specialAction)
    end

    if previousIndex and previousIndex ~= index then
        record._coreLastAdvancedLegSig = GetLegSignature(previousLeg)
        record._coreLastAdvanceReason = reason
        record._coreLastAdvanceAt = GetTimeSafe()
        record._coreLastAdvancePreservesPlan = previousLeg and previousLeg.preservePlanOnArrival == true
        if previousLeg and (previousLeg.kind == "portal" or previousLeg.kind == "taxi" or previousLeg.kind == "boat"
                or previousLeg.kind == "ship" or previousLeg.kind == "tram" or previousLeg.kind == "zeppelin") then
            NS.SignalPreferredRouteRecovery(nil, "travel_transition")
        end
    end
    return previousIndex ~= index
end

local function RouteAreaNumber(value)
    return CanAccessRouteValue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Area arrival retires travel, never the guide objective. The guide owns the
-- selected camp, walking away or selecting another camp restores travel.
function NS.UpdateRouteDestinationArea(record, suppressRefresh)
    if type(record) ~= "table" then return false, false end
    if state.routing.specialActionCasting == true
        or type(NS.IsRouteEquipmentTransactionActive) == "function" and NS.IsRouteEquipmentTransactionActive() then
        return false, false
    end
    if record.hasSanctumCrossing then
        for index = record.currentLegIndex or 1, #record.legs do
            local leg = record.legs[index]
            if leg.sanctumCrossing or leg.sanctumContinuation
                or leg.sanctumDestination and not Sanctum.AtDestination(leg.sanctumDestination) then
                return false, false
            end
        end
    end
    local target = type(record.target) == "table" and record.target or record
    local area = target.navigationArea
    local previous = record._routeDestinationAreaState
    local backend = GetBackendObject(record.backend)
    if type(area) ~= "table" or not RouteAreaNumber(area.radius) or area.radius <= 0
        or not RouteAreaNumber(area.arrivalRadius) or area.arrivalRadius < 0 then
        record._routeDestinationAreaState = nil
        if previous and previous.arrived then
            if backend and backend.OnDestinationAreaChanged then backend.OnDestinationAreaChanged(record, false) end
            if not suppressRefresh then NS.ScheduleActiveRouteRefresh("destination_area_removed") end
        end
        return false, false
    end
    local map, x, y = ResolveAuthorityDestination(record)
    if type(NS.GetPlayerWaypointDistance) ~= "function" then return false, false end
    local same = previous and previous.id == area.id and previous.map == map and previous.x == x and previous.y == y
    local height, continent
    if backend and type(backend.GetDestinationAreaFloor) == "function" then
        height, continent = backend.GetDestinationAreaFloor(record, area)
    elseif type(UnitPosition) == "function" then
        local ok, _, _, z, c = pcall(UnitPosition, "player")
        if ok then
            continent = RouteAreaNumber(c) and c or nil
            if RouteAreaNumber(z) and z ~= 0 and continent == area.continent then height = z end
        end
    end
    local far = RouteAreaNumber(continent) and RouteAreaNumber(area.continent) and continent ~= area.continent
    local distance = NS.GetPlayerWaypointDistance(map, x, y)
    if not far and (not RouteAreaNumber(distance) or distance < 0) then
        return same and previous.arrived == true or false,
            false
    end
    local observed = same and previous or { id = area.id, map = map, x = x, y = y, arrived = false }
    record._routeDestinationAreaState = observed
    local wasArrived = observed.arrived
    local wrongFloor = RouteAreaNumber(height) and RouteAreaNumber(area.height) and math.abs(height - area.height) > 8
    local limit = area.radius + area.arrivalRadius
    if wasArrived then limit = limit + math.max(5, area.arrivalRadius * 0.5) end
    observed.arrived, observed.distance = not far and not wrongFloor and distance <= limit, distance
    local changed = false
    if observed.arrived and type(record.legs) == "table" then
        local last = #record.legs
        local final = record.legs[last]
        if final and final.routeLegKind == "destination" and IsSameRouteCoord(map, x, y, final.mapID, final.x, final.y)
            and record.currentLeg ~= final then
            changed = SetCoreLegIndex(record, last, "destination_area_arrival")
            record._coreLastAdvancePreservesPlan = true
        end
    end
    if backend and type(backend.OnDestinationAreaChanged) == "function"
        and (changed or wasArrived ~= observed.arrived or not same and (observed.arrived or previous and previous.arrived)) then
        backend.OnDestinationAreaChanged(record, observed.arrived)
    end
    if previous and (wasArrived or not same and previous.arrived) and not observed.arrived and not suppressRefresh then
        NS.ScheduleActiveRouteRefresh("destination_area_left")
    end
    return observed.arrived, changed, wasArrived ~= observed.arrived
end

function NS.AdvanceActiveRouteAction(expectedIdentity, expectedGeneration, reason)
    local record = GetActiveRouteRecord()
    if type(record) ~= "table" or type(record.legs) ~= "table" then return false end
    if expectedGeneration ~= nil and record._routeAcceptedPlanGeneration ~= expectedGeneration then return false end
    local index = tonumber(record.currentLegIndex) or 1
    local leg = record.legs[index]
    if type(leg) ~= "table" or GetSpecialActionIdentity(leg.specialAction) ~= expectedIdentity then return false end
    if index >= #record.legs then return false end
    local advanced = SetCoreLegIndex(record, index + 1, reason or "action_complete")
    if advanced and type(NS.RecomputeCarrier) == "function" then NS.RecomputeCarrier() end
    return advanced
end

function NS.RetainBackendPlan(record, backendID, reason)
    if record and record._routePlanAttempt then
        return NS.RouteSpecials.CompletePlan(record, backendID, "success", record.legs, reason, nil, "retained")
    end
    if type(record) ~= "table" or record.backend ~= backendID or type(record.legs) ~= "table" or #record.legs == 0 then return false end
    record.lastPlanSkipStatus, record.lastPlanSkipReason = reason or "equivalent", reason
    record.lastPlanSkippedAt = GetTimeSafe()
    record._corePlanning, record._coreResetLegOnNextPlan = nil, nil
    local churn = state.churn
    if churn and churn.active then churn.routePlanSkip = (churn.routePlanSkip or 0) + 1 end
    if record.routeOutcome ~= "planning" then
        record._coreRoutePending = nil
        record.planAcceptStatus = "equivalent"
        CompletePendingManualRoute(record, record.routeOutcome or "success", reason)
    end
    return true
end

function NS.AdvanceActiveRouteLeg(record, expectedLeg, generation, reason)
    if GetActiveRouteRecord() ~= record or record.currentLeg ~= expectedLeg
        or record._routeAcceptedPlanGeneration ~= generation then
        return false
    end
    local index = tonumber(record.currentLegIndex) or 1
    if not record.legs or index >= #record.legs then return false end
    return SetCoreLegIndex(record, index + 1, reason or "backend_arrival")
end

-- Commit one proven prefix, so pins and presentation see only its final index.
function NS.AdvanceActiveWalkingLegs(record, expectedLeg, generation, nextIndex, reason)
    if GetActiveRouteRecord() ~= record or record.currentLeg ~= expectedLeg
        or record._routeAcceptedPlanGeneration ~= generation
        or NS.Internal.RouteProgress.IsBlocked(record) then
        return false
    end
    local index, walking = record.currentLegIndex or 1, expectedLeg.walking
    if not walking or nextIndex <= index or nextIndex > math.min(#record.legs, index + 128) then return false end
    for i = index, nextIndex - 1 do
        local leg = record.legs[i]
        local point = leg.walking
        if not point or point.group ~= walking.group or point.required or leg.specialAction
            or leg.arrivalGate or leg.sanctumCrossing or leg.routeLegKind == "destination" then
            return false
        end
    end
    return SetCoreLegIndex(record, nextIndex, reason)
end

-- Refine an accepted walking section without replaying completed travel legs
-- or allowing a late asynchronous search to replace a different route.
function NS.ReplaceActiveRouteLegs(record, expectedLeg, generation, replacements, lastLeg)
    if GetActiveRouteRecord() ~= record or record.currentLeg ~= expectedLeg
        or record._routeAcceptedPlanGeneration ~= generation or _G.InCombatLockdown()
        or NS.Internal.RouteProgress and NS.Internal.RouteProgress.IsBlocked() then
        return false
    end
    local index = tonumber(record.currentLegIndex) or 1
    if type(record.legs) ~= "table" or record.legs[index] ~= expectedLeg
        or type(replacements) ~= "table" or #replacements == 0 then
        return false
    end
    local lastIndex = index
    if lastLeg then
        while record.legs[lastIndex] and record.legs[lastIndex] ~= lastLeg do lastIndex = lastIndex + 1 end
        if not record.legs[lastIndex] then return false end
    end
    if record.hasSanctumCrossing then
        for i = index, lastIndex do
            if record.legs[i].sanctumCrossing or record.legs[i].sanctumContinuation then return false end
        end
    end
    local legs = {}
    for i = 1, index - 1 do legs[#legs + 1] = record.legs[i] end
    for _, leg in ipairs(replacements) do
        if not IsValidLeg(leg) then return false end
        legs[#legs + 1] = leg
    end
    for i = lastIndex + 1, #record.legs do legs[#legs + 1] = record.legs[i] end
    if not NS.AcceptBackendPlan(record, record.backend, legs, record.backend .. "_plan") then return false end
    SetCoreLegIndex(record, index, "walking_path")
    return true
end

local function EnsureCoreLeg(record)
    if type(record) ~= "table" then
        return nil
    end

    if type(record.legs) ~= "table" or #record.legs == 0 then
        if record._corePlanning == true then
            record.currentLegIndex = nil
            record.currentLeg = nil
            record.specialAction = nil
            return nil
        end
        local fallback = MakeFallbackLeg(record)
        if not fallback then
            return nil
        end
        record.legs = { fallback }
        record.currentLegIndex = nil
        record.currentLeg = nil
        record.specialAction = nil
    end

    local index = tonumber(record.currentLegIndex) or 1
    if not IsValidLeg(record.legs[index]) then
        index = 1
    end
    SetCoreLegIndex(record, index, "ensure")
    return record.currentLeg
end

local function ResolveLegToCarry(record)
    local leg = EnsureCoreLeg(record)
    -- The final point remains available to the queue. Until the same planner
    -- provides the onward route, the continuation isn't a navigation leg.
    if leg and leg.sanctumContinuation then return end
    local backend = leg and GetBackendObject(record.backend)
    return backend and backend.GetCarrierLeg and backend.GetCarrierLeg(record, leg) or leg
end

local function GetPlayerMapIDSafe()
    return type(NS.GetPlayerMapID) == "function" and NS.GetPlayerMapID() or nil
end

local function IsDistanceAdvanceLeg(leg)
    if not IsValidLeg(leg) then
        return false
    end
    if IsExecutableSpecialAction(leg.specialAction) then
        return false
    end
    return DISTANCE_ADVANCE_KIND[leg.kind] == true
end

local function ShouldAdvanceByDistance(leg)
    if not IsDistanceAdvanceLeg(leg) or type(NS.GetPlayerWaypointDistance) ~= "function" then
        return false
    end
    if not ArrivalGateMatches(leg) then
        return false
    end

    local distance = NS.GetPlayerWaypointDistance(leg.mapID, leg.x, leg.y)
    if not RouteAreaNumber(distance) then
        return false
    end

    local radius = type(leg.arrivalRadius) == "number" and leg.arrivalRadius or nil
    if type(radius) ~= "number" then
        radius = DISTANCE_ADVANCE_KIND[leg.kind] and DEFAULT_MOVEMENT_RADIUS_YARDS or DEFAULT_ACTION_RADIUS_YARDS
    end
    return distance <= radius
end

local function AdvanceToPlayerMapLeg(record, currentIndex, playerMapID)
    if type(playerMapID) ~= "number" or type(record.legs) ~= "table" then
        return false
    end
    for index = currentIndex + 1, #record.legs do
        local leg = record.legs[index]
        if IsValidLeg(leg) and leg.mapID == playerMapID then
            return SetCoreLegIndex(record, index, "map_transition")
        end
    end
    return false
end

local function AdvanceAuthorityLeg(record, reason)
    local backend = record and GetBackendObject(record.backend)
    if backend and backend.CanAdvanceLeg and record.currentLeg
        and backend.CanAdvanceLeg(record, record.currentLeg) == false then
        return false
    end
    local leg = EnsureCoreLeg(record)
    if type(leg) ~= "table" or not IsValidLeg(leg) or type(record.legs) ~= "table" then
        return false
    end

    local currentIndex = tonumber(record.currentLegIndex) or 1
    if currentIndex >= #record.legs then
        record._coreLastPlayerMapID = GetPlayerMapIDSafe()
        return false
    end

    local playerMapID = GetPlayerMapIDSafe()
    local previousMapID = record._coreLastPlayerMapID
    record._coreLastPlayerMapID = playerMapID

    if leg.leaveInstanceMapID then
        if type(GetInstanceInfo) ~= "function" then return false end
        local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
        if not CanAccessRouteValue(instanceMapID) or type(instanceMapID) ~= "number"
            or instanceMapID == leg.leaveInstanceMapID then
            return false
        end
        return SetCoreLegIndex(record, currentIndex + 1, "left_instance")
    end

    local transportDestination = leg.transportDestination
    if transportDestination then
        if type(NS.GetPlayerWaypointDistance) ~= "function" then return false end
        local distance = NS.GetPlayerWaypointDistance(transportDestination.mapID, transportDestination.x,
            transportDestination.y)
        if not RouteAreaNumber(distance) or distance > (leg.arrivalRadius or DEFAULT_MOVEMENT_RADIUS_YARDS) then return false end
        local boardingDistance = NS.GetPlayerWaypointDistance(leg.mapID, leg.x, leg.y)
        if RouteAreaNumber(boardingDistance) and boardingDistance <= distance then return false end
        return SetCoreLegIndex(record, currentIndex + 1, "transport_arrival")
    end

    if type(playerMapID) == "number"
        and type(previousMapID) == "number"
        and playerMapID ~= previousMapID
        and (not leg.preservePlanOnArrival or leg.kind == "entrance")
        and AdvanceToPlayerMapLeg(record, currentIndex, playerMapID)
    then
        return true
    end

    local activationCoords = type(leg.activationCoords) == "table" and leg.activationCoords or nil
    if type(playerMapID) == "number"
        and type(activationCoords) == "table"
        and type(activationCoords.mapID) == "number"
        and playerMapID ~= activationCoords.mapID
    then
        return SetCoreLegIndex(record, currentIndex + 1, "left_source_map")
    end

    if ShouldAdvanceByDistance(leg) then
        return SetCoreLegIndex(record, currentIndex + 1, "distance")
    end

    return false
end

-- ============================================================
-- Route refresh and backend invalidation
-- ============================================================

local function ReplanAuthority(record, reason)
    if type(record) ~= "table" then
        return false
    end

    local mapID, x, y, title = ResolveAuthorityDestination(record)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    local backend = GetBackendObject(record.backend)
    if not backend then return false end
    local crossing = record.currentLeg and record.currentLeg.sanctumCrossing
    if crossing and NS.GetPlayerMapID() == crossing.mapID and not Sanctum.HasArrived(crossing) then return false end
    if NS.UpdateRouteDestinationArea(record, true) and record.legs then
        return NS.RetainBackendPlan(record, backend.id, "destination_area_arrived")
    end
    record._coreLastRefreshReason = reason
    record._coreLastRefreshAt = GetTimeSafe()
    if ShouldResetLegOnReplan(reason) then
        record._coreResetLegOnNextPlan = true
    end
    local session = record._routePlanning
    return NS.RequestRoutePlan(record, session and session.preferred or NS.GetSelectedBackendID(),
        BuildPlanMeta(record, reason), "refresh")
end

function NS.RefreshActiveRoutePlans(reason)
    local routing = state.routing
    -- Defense in depth: if the cast-freeze flipped on after a refresh
    -- was already scheduled but before the debounce timer fired, drop
    -- the pending replan rather than racing the cast.
    if IsRouteActionTransactionLocked() then
        if type(NS.IsRouteEquipmentTransactionActive) == "function" and NS.IsRouteEquipmentTransactionActive() then
            routing._routeRefreshAfterEquipment = reason or routing._routeRefreshAfterEquipment or "equipment_complete"
        end
        return false
    end
    local replanned = ReplanAuthority(GetActiveRouteRecord(), reason or "refresh")
    if replanned and type(NS.RecomputeCarrier) == "function" then
        NS.RecomputeCarrier()
    end
    return replanned
end

function NS.ScheduleActiveRouteRefresh(reason)
    local routing = state.routing

    -- Special-action cast in progress: freeze replans so a transient
    -- side-effect of the cast (e.g. hearthstone going on cooldown,
    -- LibRover/Mapzeroth re-reporting travel options) doesn't switch
    -- the route to an alternative leg mid-cast. The cast-end handler
    -- in bridge/routing/special_actions.lua drops the flag and triggers a
    -- single post_cast refresh.
    if IsRouteActionTransactionLocked() then
        if type(NS.IsRouteEquipmentTransactionActive) == "function" and NS.IsRouteEquipmentTransactionActive() then
            routing._routeRefreshAfterEquipment = reason or routing._routeRefreshAfterEquipment or "equipment_complete"
        end
        return
    end

    if routing._routeRefreshPending then
        -- Reset reasons (zone change, map load, vehicle, etc.) take priority
        -- over non-reset reasons (leg_advance, LIBROVER_TRAVEL_REPORTED, etc.).
        -- Without this, a LIBROVER_TRAVEL_REPORTED event arriving after
        -- ZONE_CHANGED would silently overwrite the reset reason and the leg
        -- index would never be cleared on building exit.
        local currentIsReset = ShouldResetLegOnReplan(routing._routeRefreshReason)
        local newIsReset = ShouldResetLegOnReplan(reason)
        if newIsReset or not currentIsReset then
            routing._routeRefreshReason = reason or routing._routeRefreshReason
        end
        return
    end

    local elapsed = GetTimeSafe() - (routing._lastRouteRefreshAt or 0)
    local delay = elapsed >= ROUTE_REPLAN_DEBOUNCE_SECONDS
        and 0
        or ROUTE_REPLAN_DEBOUNCE_SECONDS - elapsed

    routing._routeRefreshPending = true
    routing._routeRefreshReason = reason
    NS.After(delay, function()
        routing._routeRefreshPending = false
        routing._lastRouteRefreshAt = GetTimeSafe()
        NS.RefreshActiveRoutePlans(routing._routeRefreshReason or "scheduled")
        routing._routeRefreshReason = nil
    end)
end

function NS.FlushDeferredRouteActionRefresh()
    local routing = state.routing
    if IsRouteActionTransactionLocked() then return false end
    local reason = routing._routeRefreshAfterEquipment
    routing._routeRefreshAfterEquipment = nil
    if not reason then return false end
    NS.ScheduleActiveRouteRefresh(reason)
    return true
end

function NS.NoteRouteEnvironmentChanged(reason)
    NS.NoteRoutePlanningEnvironment(reason)
    local routing = state.routing
    routing._lastRouteEnvironmentChange = reason
    local shouldRefresh = ShouldRefreshForEnvironment(reason or "environment")
    if shouldRefresh and (routing.manualAuthority or (type(NS.GetActiveGuideRouteState) == "function" and NS.GetActiveGuideRouteState() or routing.guideRouteState)) then
        NS.ScheduleActiveRouteRefresh(reason or "environment")
    end
    NS.RecomputeCarrier()
end

local function ShouldSuppressNoisyActionInvalidation(record, backendID, reason)
    if not NOISY_ACTION_INVALIDATION_BACKEND[backendID] or not IsNoisyActionInvalidation(reason) then
        return false
    end

    local routing = state.routing
    if routing.specialActionPresented ~= true then
        return false
    end

    local currentLeg = type(record) == "table" and record.currentLeg or nil
    local activeAction = SanitizeSpecialAction(record and record.specialAction)
        or SanitizeSpecialAction(currentLeg and currentLeg.specialAction)
    local presentedAction = SanitizeSpecialAction(routing.specialActionState)
    local activeIdentity = GetSpecialActionIdentity(activeAction)
    local presentedIdentity = GetSpecialActionIdentity(presentedAction)

    return type(activeIdentity) == "string" and activeIdentity == presentedIdentity
end

function NS.NoteRouteBackendInvalidated(backendID, reason)
    local record = GetActiveRouteRecord()
    if type(record) ~= "table" or record.backend ~= backendID then
        return false
    end
    if backendID == "zygor"
        and reason == "LIBROVER_TRAVEL_REPORTED"
        and type(record._zygorSuppressLibRoverReportedUntil) == "number"
        and record._zygorSuppressLibRoverReportedUntil > GetTimeSafe()
    then
        local churn = state.churn
        if churn and churn.active then
            churn.routeBackendInvalidationSkip = (churn.routeBackendInvalidationSkip or 0) + 1
        end
        record._coreLastBackendInvalidationSkipped = reason
        record._coreLastBackendInvalidationSkippedAt = GetTimeSafe()
        return false
    end
    if ShouldSuppressNoisyActionInvalidation(record, backendID, reason) then
        local churn = state.churn
        if churn and churn.active then
            churn.routeBackendInvalidationSkip = (churn.routeBackendInvalidationSkip or 0) + 1
        end
        record._coreLastBackendInvalidationSkipped = reason
        record._coreLastBackendInvalidationSkippedAt = GetTimeSafe()
        record._coreLastBackendInvalidationSkipReason = "active_special_action"
        return false
    end
    local churn = state.churn
    if churn and churn.active then
        churn.routeBackendInvalidation = (churn.routeBackendInvalidation or 0) + 1
    end
    NS.ScheduleActiveRouteRefresh(reason or "backend_invalidated")
    NS.RecomputeCarrier()
    return true
end

-- ============================================================
-- Notify validators when a selected travel action is used
-- ============================================================

function NS.NotifyRouteTravelActionUsed(dependency, reason)
    local record = GetActiveRouteRecord()
    local kind, id = NormalizeRouteDependency(dependency)
    if not record or not kind or not id then return false end
    local dependencies = record._routeTravelDependencies
    if type(dependencies) ~= "table" then return false end
    local key = RouteDependencyKey(kind, id)
    for index = 1, #dependencies do
        if dependencies[index].key == key then
            return NS.RequestRouteBackendStateValidation(
                record.backend,
                reason or "selected_travel_action",
                "selected_action")
        end
    end
    return false
end

function NS.NotifyRouteTravelSpellUsed(spellID)
    return NS.NotifyRouteTravelActionUsed({ kind = "spell", id = spellID }, "travel_spell_succeeded")
end

local function ScheduleRefreshAfterAdvance(record)
    if type(record) ~= "table" or record.backend == "direct" then
        return
    end
    if record._coreLastAdvancePreservesPlan then return end
    local advancedSig = record._coreLastAdvancedLegSig
    if type(advancedSig) ~= "string" or record._coreLastRefreshAdvanceSig == advancedSig then
        return
    end
    record._coreLastRefreshAdvanceSig = advancedSig
    NS.ScheduleActiveRouteRefresh(record._coreLastAdvanceReason or "leg_advance")
end

-- ============================================================
-- Movement sampling and arrival monitoring
-- ============================================================

-- One scheduler owns movement observations. Backends retain coordinate,
-- geometry, floor and asynchronous-search policy.
local Progress = {
    GetActiveRecord = GetActiveRouteRecord,
    IsValidCoordinate = RouteAreaNumber,
    GetTime = GetTimeSafe,
    requests = setmetatable({}, { __mode = "k" }),
}
NS.Internal.RouteProgress = Progress

function Progress.IsBlocked(record)
    if Progress.frame and Progress.frame.loading or state.routing.specialActionCasting
        or NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive() then
        return true
    end
    -- Each terrain adapter opts in once it can follow accepted legs in combat.
    if _G.InCombatLockdown() then
        record = record or GetActiveRouteRecord()
        local backend = record and GetBackendObject(record.backend)
        return backend and not backend.canFollowRouteInCombat and backend.WantsNavigationProgress
            and backend.WantsNavigationProgress(record) or false
    end
    return false
end

function Progress.EnsureLeg(record)
    if record and (not record.currentLeg or not record.legs
            or record.legs[record.currentLegIndex or 1] ~= record.currentLeg) then
        EnsureCoreLeg(record)
    end
end

function Progress.PollLeg(record, source, sampledMode, key, x, y, z, observedAt)
    if not record or GetActiveRouteRecord() ~= record then return false end
    if Progress.IsBlocked(record) then return false end
    Progress.EnsureLeg(record)
    local leg = record.currentLeg
    if leg and (leg.sanctumContinuation
            or leg.sanctumDestination and not ArrivalGateMatches(leg)) then
        return false
    end
    if leg and leg.sanctumCrossing then
        local generation = record._routeAcceptedPlanGeneration
        if not Sanctum.HasArrived(leg.sanctumCrossing)
            or not NS.AdvanceActiveRouteLeg(record, leg, generation, "sanctum_crossed") then
            return false
        end
        if leg.sanctumResume then NS.ScheduleActiveRouteRefresh("sanctum_crossed") end
        return true
    end
    if source == "guide" and NS.CheckGuideRouteDestinationReached then
        NS.CheckGuideRouteDestinationReached(record, DEFAULT_MOVEMENT_RADIUS_YARDS)
    end
    if GetActiveRouteRecord() ~= record then return false end
    local backend = GetBackendObject(record.backend)
    local walking = NS.Internal.RouteWalking
    local mode = sampledMode or walking.ReadMode()
    if mode == "taxi" then
        if backend and backend.StopNavigationProgress then
            backend.StopNavigationProgress(record,
                record._routeAcceptedPlanGeneration, "taxi")
        end
        return false
    end
    local db = NS.GetDB()
    if walking.UpdateFlight(record, backend, mode, db and db.followGroundPathsWhileFlying == true) then return true end
    local arrived, changed = NS.UpdateRouteDestinationArea(record)
    if arrived then return changed end
    if backend and backend.PollNavigationLeg then
        local advanced, carrierChanged = backend.PollNavigationLeg(record, sampledMode ~= nil, key, x, y, z, observedAt)
        if advanced or carrierChanged then return advanced, carrierChanged end
    end
    if GetActiveRouteRecord() ~= record then return false end
    return AdvanceAuthorityLeg(record, source == "manual" and "manual_progress" or "guide_progress")
end

function Progress.CanFinishManualArrival(record)
    local leg, backend = record.currentLeg, GetBackendObject(record.backend)
    return not leg.sanctumCrossing and not IsExecutableSpecialAction(leg.specialAction) and ArrivalGateMatches(leg)
        and not (backend and backend.CanAdvanceLeg and backend.CanAdvanceLeg(record, leg) == false)
end

function Progress.CheckManualArrival(arrival, mode)
    if not arrival or Progress.IsBlocked() or (mode or NS.Internal.RouteWalking.ReadMode()) == "taxi" then return false end
    return NS.CheckManualAuthorityArrival(arrival, Progress.CanFinishManualArrival)
end

function NS.RefreshManualArrivalMonitoring()
    local record = ArbitrateAuthority()
    local frame = Progress.frame
    if record and frame and frame.record == record then
        Progress.requests[record] = (Progress.requests[record] or 0) + 1
    end
    Progress.Refresh(record)
end

function NS.RequestRouteNavigationProgress(record, reason)
    if not record or GetActiveRouteRecord() ~= record then return false end
    Progress.requests[record] = (Progress.requests[record] or 0) + 1
    Progress.lastWakeReason = reason
    Progress.Refresh(record)
    return true
end

-- ============================================================
-- TomTom and overlay publication
-- ============================================================

-- Reuse the indexed TomTom waypoint and publish overlay changes by
-- signature. Clear both when routing has no visible authority.

local function ResolveCarrierSemanticKind(authority, source, leg)
    if type(leg) ~= "table" then
        return source == "guide" and "guide" or "manual", "destination"
    end

    local identity = type(authority) == "table" and authority.identity
    if leg.kind == "corpse" or leg.routeLegKind == "destination"
        and type(identity) == "table" and identity.destinationKind == "corpse" then
        return "corpse", "destination"
    end

    if leg.routeLegKind == "destination" then
        return source == "guide" and "guide" or "manual", "destination"
    end

    if leg.routeLegKind == "carrier" then
        return "route", "carrier"
    end

    local destMapID, destX, destY = ResolveAuthorityDestination(authority)
    if IsSameRouteCoord(leg.mapID, leg.x, leg.y, destMapID, destX, destY) then
        return source == "guide" and "guide" or "manual", "destination"
    end

    if type(leg.kind) == "string"
        and leg.kind ~= ""
        and leg.kind ~= "destination"
        and leg.kind ~= "guide_goal"
    then
        return "route", "carrier"
    end

    return "route", "carrier"
end

local function NormalizeCarrierRouteTravelType(leg)
    if type(leg) ~= "table" then return nil end
    return NS.ResolveCarrierTravelType(leg.routeTravelType, leg.routeLegKind, leg.kind)
end

local function BuildCarrierSignature(mapID, x, y)
    if type(Signature) == "function" then
        return Signature(mapID, x, y)
    end
    return string.format("%s:%s:%s", tostring(mapID), tostring(x), tostring(y))
end

local function RefreshFlightMapAssist()
    if type(NS.RefreshFlightMapAssist) == "function" then
        SafeCall(NS.RefreshFlightMapAssist)
    end
end

local function ClearCarrierPresentation()
    local routing = state.routing
    if routing.carrierState then NS.ClearCarrierWaypoint() end
    if routing.carrierState then return end
    if type(NS.ClearPublishedQueuePins) == "function" then
        NS.ClearPublishedQueuePins()
    end
    if routing.carrierState then return end
    routing.presentationState = nil
    if routing.specialActionState then
        routing.specialActionState = nil
        if NS.DisarmSpecialActionButton then NS.DisarmSpecialActionButton() end
    end
    if routing.lastPushedOverlayUID or routing.lastPushedOverlaySig ~= nil then
        if routing.carrierState then return end
        routing.lastPushedOverlaySig, routing.lastPushedOverlayUID = nil, nil
        if type(NS.SyncWorldOverlay) == "function" then
            SafeCall(NS.SyncWorldOverlay, nil, nil, nil, nil, nil, nil, nil, nil)
        end
    end
    if type(NS.SyncGuideVisualState) == "function" then
        NS.SyncGuideVisualState()
    end
    RefreshFlightMapAssist()
end

function NS.RecomputeCarrier()
    if NS.RefreshPolestarNavigationOwnership then NS.RefreshPolestarNavigationOwnership() end
    local routing = state.routing
    local authority, source = ArbitrateAuthority()
    NS.ReconcileRoutePlanning(authority, routing.pendingManualAuthority)
    Progress.EnsureLeg(authority)
    local monitor = Progress.frame
    local consumed = authority and monitor and monitor.skipRecord == authority and
        monitor.skipGeneration == authority._routeAcceptedPlanGeneration
        and monitor.skipLeg == authority.currentLeg
    if monitor then monitor.skipRecord, monitor.skipGeneration, monitor.skipLeg = nil, nil, nil end
    local advanced = not consumed and Progress.PollLeg(authority, source) or false
    local manualArrival = Progress.Refresh(authority)
    if Progress.CheckManualArrival(manualArrival) then
        Progress.Refresh(ArbitrateAuthority())
        return
    end
    if advanced then
        ScheduleRefreshAfterAdvance(authority)
    end
    authority, source = ArbitrateAuthority()

    -- No authority, release carrier.
    if not authority then
        ClearCarrierPresentation()
        return
    end

    local leg = ResolveLegToCarry(authority)
    if not leg then
        ClearCarrierPresentation()
        return
    end
    if not authority._corePendingManualRoute and type(NS.SetActiveRouteSource) == "function" then
        SafeCall(NS.SetActiveRouteSource, source)
    end
    local semanticKind, routeLegKind = ResolveCarrierSemanticKind(authority, source, leg)
    local destinationMapID, destinationX, destinationY, destinationTitle = ResolveAuthorityDestination(authority)

    -- Surface the active special action (if any) to state.routing.
    routing.specialActionState = SanitizeSpecialAction(authority.specialAction) or
        SanitizeSpecialAction(leg.specialAction)
    local specialAction = type(routing.specialActionState) == "table" and routing.specialActionState or nil
    if specialAction and rawget(specialAction, "sig") == nil then
        local actionSig = nil
        if type(Signature) == "function"
            and type(leg.mapID) == "number"
            and type(leg.x) == "number"
            and type(leg.y) == "number"
        then
            actionSig = Signature(leg.mapID, leg.x, leg.y)
        end
        if type(actionSig) == "string" then
            specialAction["sig"] = actionSig .. ":" .. tostring(rawget(specialAction, "semanticKind") or "_")
        end
    end

    -- A pending manual request owns the displayed leg. Its queue and saved
    -- destination change only when the planner accepts it.
    local previous = routing.carrierState
    local carrier = {
        authority = authority,
        authorityPending = authority._corePendingManualRoute == true or nil,
        mapID = leg.mapID,
        x = leg.x,
        y = leg.y,
        sig = BuildCarrierSignature(leg.mapID, leg.x, leg.y),
        title = leg.title or authority.title or destinationTitle or "AWP Route",
        source = source,
        kind = semanticKind,
        routeLegKind = routeLegKind,
        routeTravelType = NormalizeCarrierRouteTravelType(leg),
        plannerLegKind = leg.kind,
        finalMapID = destinationMapID,
        finalX = destinationX,
        finalY = destinationY,
        finalTitle = destinationTitle,
    }
    local presentation = NS.ResolvePresentation(carrier)
    if routing.carrierState ~= previous then return end
    carrier.title = presentation and presentation.carrierTitle or carrier.title
    routing.carrierState = carrier
    routing.presentationState = presentation

    -- TomTom can notify listeners synchronously. A replacement published
    -- from a listener owns all subsequent queue, button and overlay updates.
    local pushed = NS.PushCarrierWaypoint(carrier.mapID, carrier.x, carrier.y, carrier.title, authority.meta, previous)
    if routing.carrierState ~= carrier then return end
    if not pushed then
        carrier.uid = nil
        routing.lastPushedCarrierUID = nil
    end
    if not carrier.uid then
        carrier.overlayUID = previous and previous.sig == carrier.sig and previous.overlayUID or
            { fromAWPOverlayCarrier = true }
    end
    if type(NS.SyncAuthorityQueueProjection) == "function" then
        SafeCall(NS.SyncAuthorityQueueProjection, authority, source)
    end
    if routing.carrierState ~= carrier then return end
    if type(NS.PublishQueueProjectionPins) == "function" then
        SafeCall(NS.PublishQueueProjectionPins)
    end
    if routing.carrierState ~= carrier then return end

    -- Apply the special action (combat-safe via ApplySpecialAction).
    if routing.specialActionState then
        if NS.ApplySpecialAction then
            SafeCall(NS.ApplySpecialAction, routing.specialActionState)
        end
    else
        if NS.DisarmSpecialActionButton then NS.DisarmSpecialActionButton() end
    end

    if routing.carrierState ~= carrier then return end

    -- A TomTom reload can replace the actual pin at identical coordinates.
    local overlayUID = carrier.uid or carrier.overlayUID
    if presentation and (presentation.overlaySig ~= routing.lastPushedOverlaySig or overlayUID ~= routing.lastPushedOverlayUID) then
        routing.lastPushedOverlaySig, routing.lastPushedOverlayUID = presentation.overlaySig, overlayUID
        if type(NS.SyncWorldOverlay) == "function" then
            SafeCall(NS.SyncWorldOverlay,
                overlayUID,
                carrier.mapID,
                carrier.x,
                carrier.y,
                presentation.overlayTitle,
                source,
                carrier.kind,
                presentation -- contentSnapshot: world_overlay reads what it needs
            )
        end
        if routing.carrierState ~= carrier then return end
    end
    if type(NS.SyncGuideVisualState) == "function" then
        NS.SyncGuideVisualState()
    end
    RefreshFlightMapAssist()
end

function NS.SetRoutingEnabled(enabled)
    enabled = enabled == true
    if not enabled and NS.Internal.ServiceSearch then NS.Internal.ServiceSearch.Cancel() end
    NS.GetDB().routingEnabled = enabled
    local mapzeroth = GetBackendObject("mapzeroth")
    local syncOwnership = mapzeroth and mapzeroth.RefreshNativeNavigationOwnership
    -- Hold the native prompt until AWP has released its carrier on disable.
    if enabled and syncOwnership then syncOwnership() end
    NS.RecomputeCarrier()
    if not enabled and syncOwnership then syncOwnership() end
end

-- ============================================================
-- Routing initialization
-- ============================================================

function NS.InitializeRoutingCore()
    NS.InitializeRoutePlanning()
    local db = NS.GetDB()
    if db then
        state.routing.selectedBackend = db.routingBackend or "direct"
    end

    for _, id in ipairs(BackendCatalog.initialization) do
        local backend = GetBackendObject(id)
        if backend and type(backend.Initialize) == "function" then
            SafeCall(backend.Initialize)
        end
    end

    NS.TickUpdate = function()
        if state.routing.queueAfterCorpse then NS.ResumeQueueAfterCorpse() end
        NS.RecomputeCarrier()
    end

    NS.SetCinematicActive = function(active)
        state.routing.cinematicActive = active and true or false
        NS.RecomputeCarrier()
    end
end

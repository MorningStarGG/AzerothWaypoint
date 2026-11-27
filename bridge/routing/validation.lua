-- ============================================================
-- Route validation scheduling
-- ============================================================
--
-- Coalesce backend scans for the active route. Keep scans deferred during
-- combat or a travel action tied to a cast or equipment change. Requests for
-- the same accepted route share a deadline. Before validation runs, match the
-- record and plan generation to the queued request.

local NS = _G.AzerothWaypointNS
local state = NS.State
local Core = NS.RoutePlanningCore
local ROUTE_VALIDATION_COOLDOWN_WINDOW_SECONDS = 0.5

local ROUTE_VALIDATION_PRIORITY = {
    cooldown = 1,
    structural = 2,
    selected_action = 3,
}

local routeBackendValidators = {}
-- One slot per backend. Replacing a slot also invalidates its queued callback.
local requests = {}

local function IsCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function NoteRouteValidationChurn(backendID, key)
    local churn = state.churn
    if not churn or not churn.active then return end
    churn.routeValidation = churn.routeValidation or {}
    local counters = churn.routeValidation[backendID]
    if type(counters) ~= "table" then
        counters = {}
        churn.routeValidation[backendID] = counters
    end
    counters[key] = (tonumber(counters[key]) or 0) + 1
end

-- ============================================================
-- Validation request identity
-- ============================================================

local function CaptureValidationRequest(record, backendID, reason, requestClass)
    local mapID, x, y, title = Core.GetDestination(record)
    return {
        record = record,
        backendID = backendID,
        reason = reason,
        requestClass = requestClass,
        priority = ROUTE_VALIDATION_PRIORITY[requestClass] or ROUTE_VALIDATION_PRIORITY.structural,
        destinationSignature = Core.GetValidationDestinationSignature(record),
        mapID = mapID,
        x = x,
        y = y,
        title = title,
        sig = record.sig,
        planFingerprint = record.planFingerprint,
        planGeneration = record._routeAcceptedPlanGeneration,
    }
end

local function MatchesPlan(request, record)
    if not record or record ~= request.record then return false end
    if record.backend ~= request.backendID or record.planFingerprint ~= request.planFingerprint
        or record._routeAcceptedPlanGeneration ~= request.planGeneration then
        return false
    end
    local mapID, x, y, title = Core.GetDestination(record)
    if mapID == request.mapID and x == request.x and y == request.y and title == request.title
        and record.sig == request.sig then
        return true
    end
    -- Providers can return slightly different coordinates for the same point.
    return Core.GetValidationDestinationSignature(record) == request.destinationSignature
end

-- ============================================================
-- Validation and scheduling
-- ============================================================

local function ExecuteRouteBackendStateValidation(request)
    local backendID = request.backendID
    if not MatchesPlan(request, Core.GetActiveRecord()) then
        NoteRouteValidationChurn(backendID, "stale")
        return
    end

    local registration = routeBackendValidators[backendID]
    if type(registration) ~= "table" or type(registration.validator) ~= "function" then
        NoteRouteValidationChurn(backendID, "failed")
        return
    end

    NoteRouteValidationChurn(backendID, "executed")
    local callOK, scanOK, fingerprint = pcall(
        registration.validator,
        request.record,
        request.reason,
        request.requestClass)
    -- A validator may synchronously cause a route replacement during its scan.
    if not MatchesPlan(request, Core.GetActiveRecord()) then
        NoteRouteValidationChurn(backendID, "stale")
        return
    end
    if not callOK or scanOK ~= true or type(fingerprint) ~= "string" then
        NoteRouteValidationChurn(backendID, "failed")
        request.record._coreLastBackendValidationError = callOK and tostring(fingerprint or "no_fingerprint") or
            tostring(scanOK)
        request.record._coreLastBackendValidationErrorAt = Core.GetTime()
        return
    end

    local previous = request.record._routeBackendStateFingerprint
    request.record._routeBackendStateFingerprint = fingerprint
    request.record._coreLastBackendValidationError = nil
    request.record._coreLastBackendValidationAt = Core.GetTime()
    request.record._coreLastBackendValidationReason = request.reason
    if type(previous) ~= "string" or previous == fingerprint then
        return
    end

    NoteRouteValidationChurn(backendID, "stateChanged")
    NS.NoteRouteBackendInvalidated(backendID, backendID .. "_state_changed")
end

local function ScheduleValidationRequest(request, delay)
    local backendID = request.backendID
    request.deferred = false
    NS.After(delay, function()
        if requests[backendID] ~= request then return end
        local combat = IsCombatLocked()
        if combat or Core.IsActionTransactionLocked() then
            request.deferred = true
            if combat then NoteRouteValidationChurn(backendID, "combatDeferred") end
            return
        end
        requests[backendID] = nil
        ExecuteRouteBackendStateValidation(request)
    end)
end

local function ProbeRouteDependencies(record, backendID)
    local registration = routeBackendValidators[backendID]
    local probe = type(registration) == "table" and registration.dependencyProbe or nil
    local dependencies = type(record._routeTravelDependencies) == "table"
        and record._routeTravelDependencies
        or nil
    if type(probe) ~= "function" or type(dependencies) ~= "table" or #dependencies == 0 then
        return false
    end

    local states = type(record._routeTravelDependencyStates) == "table"
        and record._routeTravelDependencyStates
        or {}
    record._routeTravelDependencyStates = states
    local changed = false
    for index = 1, #dependencies do
        local dependency = dependencies[index]
        NoteRouteValidationChurn(backendID, "dependencyChecked")
        local ok, result = pcall(probe, record, dependency)
        if not ok or (result ~= "ready" and result ~= "unavailable") then
            NoteRouteValidationChurn(backendID, "dependencyUnknown")
        else
            local key = dependency.key or Core.DependencyKey(dependency.kind, dependency.id)
            local previous = states[key]
            states[key] = result
            if previous and previous ~= result then
                changed = true
                NoteRouteValidationChurn(backendID, "dependencyChanged")
            end
        end
    end
    return changed
end

-- ============================================================
-- Registration and route invalidation
-- ============================================================

function NS.RegisterRouteBackendStateValidator(backendID, validator, dependencyProbe)
    if type(backendID) ~= "string" or backendID == "" or type(validator) ~= "function" then
        return false
    end
    routeBackendValidators[backendID] = {
        validator = validator,
        dependencyProbe = type(dependencyProbe) == "function" and dependencyProbe or nil,
    }
    return true
end

-- Clear only the route being replaced. Another route can use the same backend.
function NS.CancelRouteBackendStateValidations(backendID, record)
    local request = requests[backendID]
    if request and request.record == record then
        requests[backendID] = nil
        NoteRouteValidationChurn(backendID, "coalesced")
    end
end

function NS.RequestRouteBackendStateValidation(backendID, reason, requestClass)
    NS.SignalPreferredRouteRecovery(backendID, reason)
    local record = Core.GetActiveRecord()
    if type(record) ~= "table" or record.backend ~= backendID or not routeBackendValidators[backendID] then
        return false
    end

    requestClass = ROUTE_VALIDATION_PRIORITY[requestClass] and requestClass or "structural"
    NoteRouteValidationChurn(backendID, "requested")

    local combatLocked = IsCombatLocked()
    local blocked = combatLocked or Core.IsActionTransactionLocked() == true
    if requestClass == "cooldown" and not blocked then
        if ProbeRouteDependencies(record, backendID) then
            requestClass = "selected_action"
        end
    end

    local previous = requests[backendID]
    if previous then
        if MatchesPlan(previous, record) then
            local priority = ROUTE_VALIDATION_PRIORITY[requestClass]
            NoteRouteValidationChurn(backendID, "coalesced")
            if previous.priority >= priority and previous.deferred == blocked then
                -- Keep the first deadline for a burst of equal or lower priority events.
                return true
            end
            if previous.priority > priority then
                requestClass, reason = previous.requestClass, previous.reason
            end
        else
            NoteRouteValidationChurn(backendID, "stale")
        end
    end

    local incoming = CaptureValidationRequest(record, backendID, reason or "backend_state", requestClass)
    requests[backendID] = incoming
    if blocked then
        incoming.deferred = true
        if combatLocked then NoteRouteValidationChurn(backendID, "combatDeferred") end
    else
        local delay = incoming.requestClass == "cooldown" and ROUTE_VALIDATION_COOLDOWN_WINDOW_SECONDS or 0
        ScheduleValidationRequest(incoming, delay)
    end
    return true
end

function NS.FlushDeferredRouteBackendStateValidations()
    if IsCombatLocked() or Core.IsActionTransactionLocked() then return false end
    local flushed = false
    for _, request in pairs(requests) do
        if request.deferred then
            ScheduleValidationRequest(request, 0)
            flushed = true
        end
    end
    return flushed
end

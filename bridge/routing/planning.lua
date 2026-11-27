-- ============================================================
-- Route planning coordinator
-- ============================================================
--
-- Owns each planning attempt, its fallback order and recovery when the
-- preferred backend becomes available. A planning session can keep accepted
-- guidance visible while an attempt runs. A result is committed only while its
-- session and authority are current.

local NS = _G.AzerothWaypointNS
local Core, Catalog = NS.RoutePlanningCore, NS.Internal.RoutingBackends
local Scheduling = NS.Internal.Scheduling
local sessions = setmetatable({}, { __mode = "k" })
local Sanctum = NS.RouteSpecials.Sanctum
local Session, Attempt = {}, {}
Session.__index, Attempt.__index = Session, Attempt
local BACKOFF = { 10, 20, 40, 60 }
local STARTUP_WAIT = 30
local startupDeadlines = {}
local loadingScreen
local confirmedChanges = {
    HEARTHSTONE_BOUND = true,
    NEW_TAXI_PATH = true,
    DugiPlannerInitialized = true,
    polestar_graph_changed = true,
    polestar_data_ready = true,
    farstrider_graph_rebuilt = true,
    route_state_changed = true,
    travel_transition = true,
    mapzeroth_camp_changed = true,
    mapzeroth_ghost_changed = true,
}

local function Now() return GetTime() end
local function Number(v)
    return not (type(issecretvalue) == "function" and issecretvalue(v))
        and type(v) == "number" and v == v and math.abs(v) < math.huge
end
local transportKinds = { boat = true, ship = true, zeppelin = true, airship = true, tram = true }
local function Blocked(record)
    local session = record and record._routePlanning
    local leg = record and record.currentLeg
    if session then
        if session.transportLeg ~= leg then session.transportLeg = nil end
        if leg and transportKinds[leg.kind] then
            local backend = NS.GetRoutingBackend(record.backend)
            if backend and backend.GetCarrierLeg and backend.GetCarrierLeg(record, leg) then return true end
            if session.transportLeg == leg then return true end
            local distance = NS.GetPlayerWaypointDistance and NS.GetPlayerWaypointDistance(leg.mapID, leg.x, leg.y)
            if Number(distance) and distance <= (leg.arrivalRadius or 15) then
                session.transportLeg = leg; return true
            end
        end
    end
    local r = NS.State.routing
    if loadingScreen or r.cinematicActive or r.specialActionCasting
        or NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive() then
        return true
    end
    if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then
        if session then session.wasOnTaxi = true end
        return true
    end
    if type(UnitInVehicle) == "function" and UnitInVehicle("player") then
        if session then session.wasInVehicle = true end
        return true
    end
    return false
end
local function Note(id, field)
    local churn = NS.State.churn
    if not churn or not churn.active then return end
    churn.routePlanning = churn.routePlanning or {}
    local counts = churn.routePlanning[id]
    if not counts then
        counts = {}; churn.routePlanning[id] = counts
    end
    counts[field] = (counts[field] or 0) + 1
end
local function CopyScalars(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(source) do
        local t = type(value)
        if t == "string" or t == "number" or t == "boolean" then copy[key] = value end
    end
    return copy
end
local function Position()
    if type(UnitPosition) == "function" then
        local ok, x, y, _, continent = pcall(UnitPosition, "player")
        if ok and Number(x) and Number(y) and Number(continent) then return continent, x, y end
    end
    local map, x, y = NS.GetPlayerMapPosition()
    if Number(map) and Number(x) and Number(y) then return NS.GetWorldPositionFromMapCoords(map, x, y) end
end

function Session:IsCurrent()
    if self.cancelled or self.owner._routePlanning ~= self or NS.IsRoutingEnabled() == false
        or self.selection ~= NS.GetSelectedBackendID() then
        return false
    end
    local map, x, y = Core.GetDestination(self.owner)
    local height, continent = NS.RouteSpecials.GetNavigationHeight(self.owner)
    return map == self.mapID and x == self.x and y == self.y
        and height == self.navigationHeight and continent == self.navigationContinent
        and (self.owner.target or self.owner).navigationNpcID == self.navigationNpcID
        and NS.IsActiveRouteRecord(self.owner, true)
end

-- ============================================================
-- Attempt ownership and completion
-- ============================================================

function Attempt:IsCurrent()
    return not self.cancelled and self.session.attempt == self and self.session:IsCurrent()
        and self.generation == self.owner._routeAcceptedPlanGeneration
        and (not self.geometry or self.geometry.leg == self.owner.currentLeg
            and (not self.geometry.validate or self.geometry.validate()))
end

function Attempt:IsAtDestination()
    if Sanctum and not self.sanctumApproach then
        local place = Sanctum.DestinationPlace(self.owner, self.mapID, self.x, self.y)
        if place and not Sanctum.AtDestination(place) then return false end
    end
    local area = self.owner._routeDestinationAreaState
    if not self.sanctumApproach and area and area.arrived then return true end
    local distance = NS.GetPlayerWaypointDistance and NS.GetPlayerWaypointDistance(self.mapID, self.x, self.y)
    return Number(distance) and distance <= 15
end

function Attempt:Complete(result)
    if self.result then return false end
    if not self:IsCurrent() then
        Note(self.backendID, "stale")
        if not self.cancelled and self.session.attempt == self then self.session.queue:Request() end
        return false
    end
    if result.status ~= "success" and result.status ~= "failed" and result.status ~= "deferred" then
        result = { status = "failed", reason = "invalid_result" }
    end
    if result.backendID and result.backendID ~= self.backendID then
        result = { status = "failed", reason = "wrong_backend" }
    end
    self.result = result
    self.session.queue:Request()
    return true
end

function Session:CancelAttempt()
    local attempt = self.attempt
    if not attempt then return end
    attempt.cancelled = true
    if attempt.backend.CancelPlan then attempt.backend.CancelPlan(attempt) end
    self.attempt = nil
    if not attempt.result or attempt.result.status == "deferred" then Note(attempt.backendID, "cancelled") end
end

function Session:ClearWait()
    if self.waitTimer then
        self.waitTimer:Cancel(); self.waitTimer = nil
    end
    self.waitReason, self.waitUntil = nil, nil
end

function Session:WaitForPreferred(reason)
    local deadline = startupDeadlines[self.preferred]
    if not deadline then
        deadline = Now() + STARTUP_WAIT
        startupDeadlines[self.preferred] = deadline
    end
    if Now() >= deadline then return false end
    self.cycle.tried[self.preferred] = nil
    local entering = not self.waitUntil
    self.waitReason, self.waitUntil = reason or "initializing", deadline
    if entering and NS.RequestRouteNavigationProgress then
        NS.RequestRouteNavigationProgress(self.owner, "planner_waiting")
    end
    if not self.waitTimer then
        self.waitTimer = C_Timer.NewTimer(deadline - Now(), function()
            self.waitTimer = nil
            if self:IsCurrent() then self.queue:Request() end
        end)
    end
    return true
end

function Session:Cancel()
    local geometry = self.geometry
    self.geometry = nil
    self:CancelAttempt()
    self:ClearWait()
    self.cancelled = true
    self.queue:Cancel()
    self.recoveryQueue:Cancel()
    if self.retry then
        self.retry:Cancel(); self.retry = nil
    end
    self.owner._corePlanning, self.owner._coreRoutePending = nil, nil
    self.owner._routePlanningResume = self.owner.legs ~= nil
    if self.owner._routePlanning == self then self.owner._routePlanning = nil end
    sessions[self.owner] = nil
    if geometry then geometry.done(false, "cancelled") end
end

-- ============================================================
-- Deferral and recovery
-- ============================================================

function Session:Defer(backendID)
    if NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive() then
        NS.State.routing._routeRefreshAfterEquipment = "deferred_planning"
    end
    self:CancelAttempt()
    if self.cycle then
        if backendID then self.cycle.tried[backendID] = nil else self.cycle.tried = {} end
    end
    self.combatBackend = backendID
    self.deferred = true
    self.owner._corePlanning, self.owner._coreRoutePending = true, true
end

function Session:RecoveryEligible()
    return self.owner.backend ~= self.preferred and self.preferred ~= "direct"
        and not self.cancelled and
        not (self.owner._routeDestinationAreaState and self.owner._routeDestinationAreaState.arrived)
end

function Session:RequestRecovery(bypass)
    if not self:IsCurrent() or self.waitUntil or not self:RecoveryEligible() then return false end
    if self.cycle and self.cycle.kind == "recovery" then return true end
    self.recoverRequested = true
    self.bypass = self.bypass or bypass == true
    if self.cycle then return true end
    local delay = self.bypass and 0.35 or math.max(0.35, (self.nextRecoveryAt or 0) - Now())
    if delay <= 0.35 then
        if self.retry then
            self.retry:Cancel(); self.retry = nil
        end
        self.recoveryQueue:Request()
    elseif not self.retry then
        self.retry = C_Timer.NewTimer(delay, function()
            self.retry = nil
            if self:IsCurrent() and self.recoverRequested then self.queue:Request() end
        end)
    end
    return true
end

function Session:StartCycle(kind, meta)
    self:CancelAttempt()
    self.cycle = { kind = kind, tried = {} }
    self.meta = meta or self.meta
    self.deferred = nil
    self.owner._corePlanning, self.owner._coreRoutePending = true, true
    self.queue:Request()
end

function Session:NextBackend()
    local cycle = self.cycle
    if cycle.sanctumApproach then return cycle.sanctumBackend end
    if cycle.kind == "geometry" then
        local id = self.geometry and self.geometry.backend
        if not id or cycle.tried[id] then return nil end
        cycle.tried[id] = true
        return id
    end
    if self.preferred == "mapzeroth" and UnitIsGhost and UnitIsGhost("player") and cycle.kind ~= "recovery" then
        -- A failed ghost walk can keep a direct heading. Falling through to
        -- ordinary travel planners could reintroduce unusable travel actions.
        if not cycle.tried.mapzeroth then
            cycle.tried.mapzeroth = true; return "mapzeroth"
        end
        if not cycle.tried.direct then
            cycle.tried.direct = true; return "direct"
        end
        return nil
    end
    if self.owner.backendOverride or cycle.kind == "recovery" then
        if cycle.tried[self.preferred] then return nil end
        cycle.tried[self.preferred] = true
        return self.preferred
    end
    local first = cycle.kind == "refresh" and self.owner.backend or self.preferred
    if not cycle.tried[first] then
        cycle.tried[first] = true; return first
    end
    if not cycle.tried[self.preferred] then
        cycle.tried[self.preferred] = true; return self.preferred
    end
    for _, entry in ipairs(Catalog.entries) do
        if not cycle.tried[entry.id] then
            cycle.tried[entry.id] = true; return entry.id
        end
    end
end

function Session:FinishFailure(id, result)
    self.lastReasons[id] = result.reason or "no_route"
    if self.cycle then self.cycle.sanctumApproach, self.cycle.sanctumBackend = nil, nil end
    if self.cycle and self.cycle.kind == "geometry" then
        local geometry = self.geometry
        self.geometry, self.cycle = nil, nil
        self.owner._corePlanning, self.owner._coreRoutePending = nil, nil
        self:CancelAttempt()
        Note(id, "geometryFailed")
        if geometry then geometry.done(false, result.reason or "no_route") end
        return
    end
    if id == self.preferred then
        self.preferredFailureKind = result.failureKind
        if not self.attempt then
            self.positionContinent, self.positionX, self.positionY = Position()
        end
        if self.preferredSince and Now() - self.preferredSince >= 60 then self.failures = 0 end
        self.preferredSince = nil
        self.failures = math.min(4, self.failures + 1)
        self.nextRecoveryAt = Now() + BACKOFF[self.failures]
    end
    Note(id, "failed")
    self:CancelAttempt()
    if self.cycle.kind == "recovery" then
        self.cycle = nil
        self.owner._corePlanning, self.owner._coreRoutePending = nil, nil
        if self.recoverRequested then self:RequestRecovery(false) end
    else
        self.queue:Request()
    end
end

-- A verified crossing ends this part of the plan. Preserve the exact final
-- point for the queue while the onward plan waits for live arrival evidence.
local function FinishSanctumItinerary(session, attempt, legs, prefix, crossing)
    local itinerary = {}
    for i = 1, prefix do itinerary[i] = legs[i] end
    local last = itinerary[prefix]
    if crossing then
        if last.routeLegKind == "destination" then
            last.routeLegKind = "carrier"
            if last.kind == "destination" then last.kind = "walk" end
        end
        itinerary[#itinerary + 1] = Sanctum.MakeCrossingLeg(attempt.backendID, crossing)
    else
        local crossingLeg = {}
        for key, value in pairs(last) do crossingLeg[key] = value end
        crossingLeg.sanctumResume = true
        itinerary[prefix] = crossingLeg
    end
    local _, _, _, title = Core.GetDestination(session.owner)
    local final = NS.RouteSpecials.MakeDestinationLeg(attempt.backendID, session.mapID, session.x, session.y, title)
    final.sanctumContinuation = true
    itinerary[#itinerary + 1] = final
    return itinerary
end

function Session:Commit(attempt, result)
    local owner, backend, oldID = self.owner, attempt.backend, self.owner.backend
    local geometry = self.geometry
    local retained = result.mode == "retained" and oldID == attempt.backendID and owner.legs == result.legs
    local legs = result.legs
    if type(legs) ~= "table" or #legs == 0 then return self:FinishFailure(attempt.backendID, { reason = "empty_plan" }) end
    for i = 1, #legs do
        local leg = legs[i]
        if not Core.IsValidLeg(leg) or not Number(leg.mapID) or not Number(leg.x) or not Number(leg.y)
            or leg.mapID <= 0 or leg.x < 0 or leg.x > 1 or leg.y < 0 or leg.y > 1 then
            return self:FinishFailure(attempt.backendID, { reason = "invalid_leg" })
        end
    end
    if result.mode == "intentional_direct" and attempt.backendID ~= self.preferred then
        return self:FinishFailure(attempt.backendID, { reason = "planning_disabled" })
    end
    local place = Sanctum and not retained and Sanctum.DestinationPlace(owner, self.mapID, self.x, self.y)
    if Sanctum and not retained and not geometry then
        local approach = attempt.sanctumApproach
        if approach then
            -- Same-map crossings can occur while an asynchronous approach
            -- is still planning. Resume from the observed side in that case.
            if Sanctum.HasArrived(approach) then
                self.cycle.sanctumApproach, self.cycle.sanctumBackend = nil, nil
                self.cycle.tried[attempt.backendID] = nil
                self:CancelAttempt()
                self.queue:Request()
                return
            end
            local last = legs[#legs]
            if last.mapID ~= approach.mapID or math.abs(last.x - approach.x) > .00005
                or math.abs(last.y - approach.y) > .00005 then
                return self:FinishFailure(attempt.backendID, { reason = "sanctum_approach_missed" })
            end
            legs = FinishSanctumItinerary(self, attempt, legs, #legs, approach)
        else
            local missing, prefix = Sanctum.FindMissingCrossing(place or nil, self.mapID, legs)
            if missing and prefix then
                legs = FinishSanctumItinerary(self, attempt, legs, prefix)
            elseif missing then
                self.cycle.sanctumApproach, self.cycle.sanctumBackend = missing, attempt.backendID
                self:CancelAttempt()
                self.queue:Request()
                return
            end
        end
    end
    local last = legs[#legs]
    if place and last.routeLegKind == "destination" then last.sanctumDestination = place end
    local function install()
        local old = NS.GetRoutingBackend(oldID)
        if not retained and old and old.ReleasePlan then old.ReleasePlan(owner) end
        if backend.AdoptPlan then backend.AdoptPlan(attempt, owner, result) end
        owner._routeBackendStateFingerprint = attempt.record._routeBackendStateFingerprint
    end
    local accepted
    -- Releasing old backend state during installation cancels its local
    -- recovery ticket. The validated commit now owns that handoff.
    self.geometry = nil
    if geometry and not retained then owner._coreResetLegOnNextPlan = true end
    if retained then
        install()
        accepted = NS.RetainBackendPlan(owner, attempt.backendID, result.reason)
    else
        -- Refresh final presentation from the owner: text-only changes do not
        -- cancel an otherwise valid destination-scoped attempt.
        local _, _, _, title = Core.GetDestination(owner)
        local last = legs[#legs]
        if owner.authority ~= "guide" and last.mapID == self.mapID and last.x == self.x
            and last.y == self.y and last.routeLegKind == "destination" then
            last.title = title
        end
        accepted = NS.AcceptBackendPlan(owner, attempt.backendID, legs, result.reason, result.serial, install)
    end
    if self.cancelled then
        NS.RecomputeCarrier(); return
    end
    if not accepted then
        self.geometry = geometry
        return self:FinishFailure(attempt.backendID, { reason = "plan_rejected" })
    end
    if owner._routeBackendStateFingerprint == NS.RouteSpecials.COMBAT_TRAVEL_STATE and Core.GetActiveRecord() == owner then
        NS.RequestRouteBackendStateValidation(attempt.backendID, "combat_plan", "structural")
    end
    local recovered = attempt.backendID == self.preferred
    if recovered then self.preferredSince = self.preferredSince or Now() end
    self.activeBackend = attempt.backendID
    self.lastReasons[attempt.backendID] = nil
    self.lastAttemptKind = self.cycle.kind
    local kind = self.cycle.kind
    self.cycle = nil
    self.owner._corePlanning, self.owner._coreRoutePending = nil, nil
    self:CancelAttempt()
    if kind == "geometry" then
        if geometry then geometry.done(true, "recovered") end
        NS.RecomputeCarrier()
        return
    end
    local notice = NS.State.routing.routeFallbackNotice
    if recovered then
        if notice and notice.preferred == self.preferred then
            NS.Msg(Catalog.Label(self.preferred) .. " routing restored.")
            Note(self.preferred, "recovered")
        end
        NS.State.routing.routeFallbackNotice = nil
    else
        if not notice or notice.preferred ~= self.preferred then
            local kind = self.preferredFailureKind
            local message = kind == "waiting" and " is still loading." or kind == "unavailable" and " is unavailable."
                or " could not find a route."
            NS.Msg(Catalog.Label(self.preferred) .. message .. " Using " .. Catalog.Label(self.activeBackend) .. ".")
            NS.State.routing.routeFallbackNotice = { preferred = self.preferred }
        end
        Note(self.activeBackend, "fallback")
    end
    Note(self.activeBackend, "committed")
    if recovered then
        self.recoverRequested, self.bypass = nil, nil
    elseif self.recoverRequested then
        self:RequestRecovery(false)
    end
    if kind ~= "recovery" then self.lastRefreshAt = Now() end
    NS.RecomputeCarrier()
end

-- ============================================================
-- Running the planner
-- ============================================================

function Session:Drive()
    if not self:IsCurrent() then
        self:Cancel(); return
    end
    if self.combatBackend and InCombatLockdown() then return end
    self.combatBackend = nil
    if self.preferred ~= "direct" and Blocked(self.owner) then
        self:Defer(); return
    end
    self.deferred = nil
    if self.waitUntil then
        local ok, status, reason = pcall(Catalog.GetReadiness, self.preferred)
        if ok and status == "waiting" and Now() < self.waitUntil then
            self.waitReason = reason or "initializing"
            return
        end
        self:ClearWait()
    end
    if not self.cycle then
        if not self.recoverRequested or not self:RecoveryEligible() then return end
        if not self.bypass and Now() < (self.nextRecoveryAt or 0) then
            self:RequestRecovery(false); return
        end
        self.recoverRequested, self.bypass = nil, nil
        self.cycle = { kind = "recovery", tried = {} }
        self.owner._corePlanning, self.owner._coreRoutePending = true, true
    end
    local attempt = self.attempt
    if attempt then
        if not attempt:IsCurrent() then
            if self.geometry then return self:FinishFailure(attempt.backendID, { reason = "geometry_obsolete" }) end
            Note(attempt.backendID, "stale")
            self:CancelAttempt()
            self.cycle = nil
            self.owner._corePlanning, self.owner._coreRoutePending = nil, nil
            return
        end
        local result = attempt.result
        if not result then return end
        if result.status == "deferred" then
            Note(attempt.backendID, "deferred")
            self:Defer(result.reason == "combat" and attempt.backendID or nil)
            -- The result and the end-of-combat event can arrive in one frame.
            if self.combatBackend and not InCombatLockdown() then self.queue:Request() end
        elseif result.status == "success" then
            self:Commit(attempt, result)
        else
            self:FinishFailure(attempt.backendID, result)
        end
        return
    end
    local id = self:NextBackend()
    if not id then
        if self.geometry then return self:FinishFailure(self.geometry.backend, { reason = "no_route" }) end
        self.cycle = nil
        self.owner._corePlanning, self.owner._coreRoutePending = nil, nil
        if self.owner._corePendingManualRoute then
            local failedBackend = self.owner.backendOverride or "direct"
            Core.CompletePendingManualRoute(self.owner, "failed", self.lastReasons[failedBackend] or "backend_no_plan")
            self:Cancel()
            NS.RecomputeCarrier()
        end
        return
    end
    local backend = NS.GetRoutingBackend(id)
    local ok, readiness, unavailable = pcall(Catalog.GetReadiness, id)
    if not ok or readiness ~= "ready" or not backend or type(backend.BeginPlan) ~= "function" then
        local reason = ok and type(unavailable) == "string" and unavailable or "unavailable"
        if ok and readiness == "waiting" then
            if self.geometry then return self:FinishFailure(id, { reason = reason or "initializing" }) end
            if id ~= self.preferred then
                self.lastReasons[id] = reason
                self.queue:Request()
                return
            end
            if self:WaitForPreferred(reason) then return end
            return self:FinishFailure(id, { reason = "startup_wait_expired", failureKind = "waiting" })
        end
        return self:FinishFailure(id, { reason = reason, failureKind = "unavailable" })
    end
    if InCombatLockdown() and not Catalog.CanPlanInCombat(id) then
        self:Defer(id); return
    end
    local record = assert(CopyScalars(self.owner))
    local target = self.owner.target
    record.target, record.destination = CopyScalars(target), CopyScalars(self.owner.destination)
    if record.target and type(target) == "table" then record.target.navigationArea = target.navigationArea end
    record.navigationArea = self.owner.navigationArea
    record.meta = self.meta
    if self.geometry then record._coreResetLegOnNextPlan = true end
    if self.owner.backend ~= id then record._routeBackendStateFingerprint = nil end
    record.backend, record._corePlanning, record._coreRoutePending = id, true, true
    local approach = self.cycle.sanctumApproach
    local mapID, x, y, title = self.mapID, self.x, self.y, select(4, Core.GetDestination(self.owner))
    if approach then
        mapID, x, y, title = approach.mapID, approach.x, approach.y, approach.title
        local destination = {
            mapID = mapID,
            x = x,
            y = y,
            title = title,
            navigationHeight = approach.height,
            navigationContinent = approach.height and 0 or nil
        }
        record.mapID, record.x, record.y, record.title = mapID, x, y, title
        record.navigationArea = nil
        record.navigationHeight, record.navigationContinent = destination.navigationHeight,
            destination.navigationContinent
        record.target, record.destination = record.target and destination, record.destination and destination
        record._routeDestinationAreaState = nil
    elseif self.owner.backend == id then
        record.legs, record.currentLeg, record.currentLegIndex = self.owner.legs, self.owner.currentLeg,
            self.owner.currentLegIndex
    end
    attempt = setmetatable({
        session = self,
        owner = self.owner,
        backend = backend,
        backendID = id,
        record = record,
        mapID = mapID,
        x = x,
        y = y,
        title = title,
        sanctumApproach = approach,
        meta = self.meta,
        generation = self.owner._routeAcceptedPlanGeneration,
        geometry = self.geometry
    }, Attempt)
    record._routePlanAttempt = attempt
    self.attempt = attempt
    if id == self.preferred then
        self.positionContinent, self.positionX, self.positionY = Position()
        self.lastPreferredAttemptAt = Now()
        if self.cycle.kind == "recovery" then Note(id, "recoveryAttempt") end
    end
    Note(id, "attempted")
    local started, outcome = pcall(backend.BeginPlan, attempt)
    if not started then
        attempt:Complete({ status = "failed", reason = "planner_error", detail = tostring(outcome) })
    elseif not attempt.result and outcome ~= "pending" then
        attempt:Complete({ status = "failed", reason = "backend_no_result" })
    end
end

-- ============================================================
-- Cancelling or refreshing a plan
-- ============================================================

function NS.CancelRoutePlanning(record)
    local session = record and record._routePlanning
    if session then session:Cancel() end
end

function NS.RequestRoutePlan(record, preferred, meta, kind, geometry)
    local map, x, y = Core.GetDestination(record)
    local height, continent = NS.RouteSpecials.GetNavigationHeight(record)
    if not Number(map) or not Number(x) or not Number(y) then return false end
    preferred = record.backendOverride or preferred
    record._routePlanningResume = nil
    local session = record._routePlanning
    if session and (session.preferred ~= preferred or session.mapID ~= map or session.x ~= x or session.y ~= y
            or session.navigationHeight ~= height or session.navigationContinent ~= continent
            or session.navigationNpcID ~= (record.target or record).navigationNpcID) then
        session:Cancel(); session = nil
    end
    if session and session.geometry and kind ~= "geometry" then
        NS.CancelRouteGeometryRefresh(record, session.geometry.ticket)
    end
    if not session then
        session = setmetatable({
            owner = record,
            preferred = preferred,
            selection = NS.GetSelectedBackendID(),
            mapID = map,
            x = x,
            y = y,
            failures = 0,
            lastReasons = {},
            meta = meta
        }, Session)
        session.navigationHeight, session.navigationContinent = height, continent
        session.navigationNpcID = (record.target or record).navigationNpcID
        session.queue = Scheduling.CreateCoalescer(function() session:Drive() end)
        session.recoveryQueue = Scheduling.CreateCoalescer(function() session.queue:Request() end, 0.35)
        session.playerMapID = NS.GetPlayerMapID()
        record._routePlanning, sessions[record] = session, session
    end
    if kind == "refresh" and record.backend == "direct" and preferred ~= "direct" then
        return session:RequestRecovery(false)
    end
    if not record.legs then
        record._coreRouteOutcomeHint = "planning"
        NS.AcceptBackendPlan(record, "direct", { NS.RouteSpecials.MakeDestinationLeg("direct", map, x, y,
            select(4, Core.GetDestination(record))) }, "route_planning_continuity")
        record._coreRouteOutcomeHint = nil
    end
    if session.deferred and session.recoverRequested then
        session.queue:Request()
        return true
    end
    if session.cycle then
        if session.deferred and not Blocked(record) then session.queue:Request() end
        return true
    end
    session.geometry = geometry
    session:StartCycle(kind or "initial", meta)
    return true
end

-- Refresh an accepted itinerary with its current planner, without changing
-- the user's preference or falling through to other backends on failure.
function NS.RequestRouteGeometryRefresh(record, ticket, done, validate)
    if not ticket.leg or not NS.IsActiveRouteRecord(record, false) or record.currentLeg ~= ticket.leg
        or record._routeAcceptedPlanGeneration ~= ticket.generation then
        return false
    end
    local session = record._routePlanning
    if session and session.cycle then return false end
    local preferred = session and session.preferred or record.backendOverride or NS.GetSelectedBackendID()
    record._coreLastRefreshReason, record._coreLastRefreshAt = "walking_recovery", Now()
    local geometry = { backend = record.backend, leg = ticket.leg, ticket = ticket, done = done, validate = validate }
    return NS.RequestRoutePlan(record, preferred, record.meta, "geometry", geometry)
end

function NS.CancelRouteGeometryRefresh(record, ticket)
    local session = record and record._routePlanning
    local geometry = session and session.geometry
    if not geometry or geometry.ticket ~= ticket then return end
    session.geometry, session.cycle, session.deferred = nil, nil, nil
    session:CancelAttempt()
    record._corePlanning, record._coreRoutePending = nil, nil
    geometry.done(false, "cancelled")
end

function NS.NeedsRouteRecovery(record)
    local session = record and record._routePlanning
    return session and not session.waitUntil and session:RecoveryEligible() or false
end

function NS.ObserveRouteRecovery(record)
    local session = record and record._routePlanning
    if not session or not session:RecoveryEligible() or session.cycle or Blocked(record) then return end
    local now = Now()
    if now < (session.observeAt or 0) then return end
    session.observeAt = now + 1
    if type(IsPlayerMoving) == "function" and not IsPlayerMoving() then return end
    local continent, x, y = Position()
    if not Number(x) or not Number(y) or not Number(continent) then return end
    if continent ~= session.positionContinent or not session.positionX then
        session.positionContinent, session.positionX, session.positionY = continent, x, y
        return
    end
    if (x - session.positionX) ^ 2 + (y - session.positionY) ^ 2 >= 100 ^ 2 then session:RequestRecovery(false) end
end

-- ============================================================
-- Preferred backend recovery
-- ============================================================

function NS.SignalPreferredRouteRecovery(id, reason)
    local owner = NS.GetActiveAuthorityRecord()
    local session = owner and owner._routePlanning
    if not session or session.waitUntil or id and id ~= session.preferred or not session:RecoveryEligible() then return false end
    if reason == "SPELL_UPDATE_COOLDOWN" or reason == "BAG_UPDATE_COOLDOWN" then return false end
    local confirmed = confirmedChanges[reason] or type(reason) == "string" and reason:match("^MAPZEROTH_OPTION_") ~= nil
    if confirmed then
        if session.cycle then
            if session.cycle.kind == "recovery" then
                session:CancelAttempt(); session.cycle = nil
            else
                session:Defer(); session.queue:Request()
            end
        end
    end
    return session:RequestRecovery(confirmed == true)
end

function NS.NotifyRouteBackendReadiness(id, status)
    for _, session in pairs(sessions) do
        if session.preferred == id and session:IsCurrent() then
            if session.waitUntil then
                session.queue:Request()
            elseif status == "ready" and session:RecoveryEligible() then
                session:RequestRecovery(true)
            end
        end
    end
end

function NS.NoteRoutePlanningEnvironment(reason)
    local owner = NS.GetActiveAuthorityRecord()
    local session = owner and owner._routePlanning
    if not session then return end
    local map = NS.GetPlayerMapID()
    local changed = session.playerMapID and map and session.playerMapID ~= map
    session.playerMapID = map
    if session.waitUntil then return end
    if changed or reason == "LOADING_SCREEN_DISABLED" or reason == "PLAYER_CONTROL_GAINED" and session.wasOnTaxi
        or reason == "UNIT_EXITING_VEHICLE" and session.wasInVehicle then
        session.wasOnTaxi, session.wasInVehicle = nil, nil
        if session.cycle then
            session:Defer(); session.queue:Request()
        end
        session:RequestRecovery(true)
    end
end

function NS.ReconcileRoutePlanning(active, pending)
    local enabled = NS.IsRoutingEnabled()
    local notice = NS.State.routing.routeFallbackNotice
    if notice and (not enabled or notice.preferred ~= NS.GetSelectedBackendID()) then NS.State.routing.routeFallbackNotice = nil end
    for owner, session in pairs(sessions) do
        if not enabled or owner ~= active and owner ~= pending then session:Cancel() end
    end
    if enabled and active and active._routePlanningResume and not active._routePlanning then
        NS.RequestRoutePlan(active, NS.GetSelectedBackendID(), active.meta, active.backend and "refresh" or "initial")
    end
end

function NS.GetRoutePlanningStatus(record)
    local session = record and record._routePlanning
    if not session then return nil end
    return {
        preferred = session.preferred,
        active = record.backend,
        attempting = session.attempt and session.attempt.backendID,
        waiting = session.waitReason,
        waitUntil = session.waitUntil,
        deferred = session.deferred == true,
        nextRecoveryAt = session.nextRecoveryAt,
        reasons = CopyScalars(session.lastReasons)
    }
end

local readinessObservers = {}

local function ObserveBackendReadiness(changedAddon)
    for _, entry in ipairs(Catalog.entries) do
        local backend = NS.GetRoutingBackend(entry.id)
        if backend and type(backend.InstallReadinessHooks) == "function" and Catalog.SupportsClient(entry) then
            local relevant = changedAddon == nil
            if not relevant then
                for _, dependency in ipairs(Catalog.GetAddons(entry)) do
                    if dependency == changedAddon then
                        relevant = true; break
                    end
                end
            end
            if relevant then
                local id = entry.id
                local observer = readinessObservers[id]
                if not observer then
                    local lastStatus
                    local queue = Scheduling.CreateCoalescer(function()
                        local ok, status = pcall(Catalog.GetReadiness, id)
                        if ok and status ~= lastStatus then
                            lastStatus = status
                            NS.NotifyRouteBackendReadiness(id, status)
                        end
                    end)
                    observer = function() queue:Request() end
                    readinessObservers[id] = observer
                end
                pcall(backend.InstallReadinessHooks, observer)
                observer()
            end
        end
    end
end

local lifecycleFrame
-- A cast, equipment change or combat can defer a still-uncommitted request.
-- Wake its own session. Drive rechecks ownership and any remaining blockers.
function NS.ResumeDeferredRoutePlanning()
    for _, session in pairs(sessions) do
        if session.deferred then session.queue:Request() end
    end
end

function NS.InitializeRoutePlanning()
    if lifecycleFrame then return end
    local frame = CreateFrame("Frame")
    lifecycleFrame = frame
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOADING_SCREEN_ENABLED",
        "LOADING_SCREEN_DISABLED", "PLAYER_LOGOUT", "ADDON_LOADED" }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            ObserveBackendReadiness(name)
        elseif event == "PLAYER_LOGIN" then
            ObserveBackendReadiness()
        end
        if event == "LOADING_SCREEN_ENABLED" then
            loadingScreen = true
        elseif event == "LOADING_SCREEN_DISABLED" then
            loadingScreen = nil
        end
        if event == "PLAYER_REGEN_ENABLED" or event == "LOADING_SCREEN_DISABLED" then
            NS.ResumeDeferredRoutePlanning()
            return
        end
        for _, session in pairs(sessions) do
            if event == "PLAYER_LOGOUT" then
                session:Cancel()
            elseif event == "PLAYER_REGEN_DISABLED" then
                local attempt = session.attempt
                if attempt and not attempt.result and not Catalog.CanPlanInCombat(attempt.backendID) then
                    session:Defer(attempt.backendID)
                end
            elseif event == "LOADING_SCREEN_ENABLED" then
                if session.cycle then session:Defer() end
            elseif event == "ADDON_LOADED" and session:RecoveryEligible() then
                local entry = Catalog.byID[session.preferred]
                for _, addon in ipairs(Catalog.GetAddons(entry)) do
                    if name == addon then
                        if session.waitUntil then session.queue:Request() else session:RequestRecovery(true) end
                        break
                    end
                end
            end
        end
    end)
    ObserveBackendReadiness()
end

local _, private = ...
if private and private.finishLoadGroup then private.finishLoadGroup("Routing and providers") end
